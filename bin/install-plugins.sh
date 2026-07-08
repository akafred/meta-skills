#!/usr/bin/env bash
set -euo pipefail

# Installs Claude Code plugins discovered across every sub-repo listed in this
# meta-repo's .meta, using the claude CLI (Claude Code only — no other agent
# properly supports plugins).
#
# Sub-repos with .claude-plugin/marketplace.json are registered as marketplaces
# themselves; sub-repos with only .claude-plugin/plugin.json are served by a
# synthesized 'meta-skills' marketplace generated at this repo's root
# (.claude-plugin/marketplace.json, gitignored).
#
# Usage:
#   ./install-plugins.sh [--target DIR] [--scope SCOPE] [--source MODE] \
#                        [--list | --uninstall] [PLUGIN...]
#
#   --target DIR, -t DIR   Repo to install into / list / uninstall from
#                          (default: this meta-repo).
#   --scope SCOPE, -s ...  Where enablement is recorded in the target:
#                          local (default, .claude/settings.local.json),
#                          project (.claude/settings.json, committed), or
#                          user (~/.claude/settings.json, global).
#   --source MODE          Where marketplaces/plugins are installed from:
#                          origin (default, the repo's upstream URL from .meta)
#                          or local (the clone under this meta-repo).
#   --list, -l             Show plugins enabled in the target's settings files.
#   --uninstall, -u        Uninstall the selected plugins from the target.
#   PLUGIN...              Plugin name(s) or name@marketplace, or 'all'.
#                          Omit for an interactive picker.
#
# Examples:
#   ./install-plugins.sh                                # interactive, into this meta-repo
#   ./install-plugins.sh superpowers                    # one plugin, into this meta-repo
#   ./install-plugins.sh --target ~/code/app all        # everything, into ~/code/app
#   ./install-plugins.sh -t ~/code/app --source local superpowers
#   ./install-plugins.sh --list -t ~/code/app           # what's enabled in ~/code/app
#   ./install-plugins.sh -u -t ~/code/app superpowers   # uninstall one plugin
#
# Source of truth is .meta; sub-repos must already be cloned
# (e.g. via `meta git clone` / `meta git update`).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
meta_file="$repo_root/.meta"
project_dir="$repo_root"
synth_market="meta-skills"

mode="install"
scope="local"
source_mode="origin"
selection_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)
      [[ $# -ge 2 ]] || { echo "$1 requires a directory argument" >&2; exit 1; }
      project_dir="$2"
      shift 2
      ;;
    -s|--scope)
      [[ $# -ge 2 ]] || { echo "$1 requires an argument (local|project|user)" >&2; exit 1; }
      scope="$2"
      shift 2
      ;;
    --source)
      [[ $# -ge 2 ]] || { echo "$1 requires an argument (origin|local)" >&2; exit 1; }
      source_mode="$2"
      shift 2
      ;;
    -u|--uninstall)
      mode="uninstall"
      shift
      ;;
    -l|--list)
      mode="list"
      shift
      ;;
    -h|--help)
      awk 'NR<=2{next} /^#/{sub(/^# ?/,"");print;found=1;next} found{exit}' "$0"
      exit 0
      ;;
    *)
      selection_args+=("$1")
      shift
      ;;
  esac
done

if [[ ! -f "$meta_file" ]]; then
  echo "No .meta file at $meta_file (run this from a meta-repo root)" >&2
  exit 1
fi
if [[ ! -d "$project_dir" ]]; then
  echo "Target directory does not exist: $project_dir" >&2
  exit 1
fi
project_dir="$(cd "$project_dir" && pwd)"
case "$scope" in local|project|user) ;; *)
  echo "Invalid --scope '$scope' (use local, project, or user)" >&2; exit 1 ;;
esac
case "$source_mode" in origin|local) ;; *)
  echo "Invalid --source '$source_mode' (use origin or local)" >&2; exit 1 ;;
esac

# --list: read enabledPlugins straight from the target's settings files
# (no claude CLI needed).
if [[ "$mode" == "list" ]]; then
  echo "Plugins enabled in $project_dir:"
  any=0
  while IFS=$'\x1f' read -r fscope id state; do
    [[ -n "$id" ]] || continue
    any=1
    extra=""; [[ "$state" == "disabled" ]] && extra=", disabled"
    printf '  \033[36m%s\033[0m \033[2m(%s%s)\033[0m\n' "$id" "$fscope" "$extra"
  done < <(node -e '
    const fs=require("fs"),path=require("path");
    const dir=process.argv[1];
    const files=[["project",path.join(dir,".claude","settings.json")],
                 ["local",path.join(dir,".claude","settings.local.json")]];
    for(const [scope,f] of files){
      let s; try{s=JSON.parse(fs.readFileSync(f,"utf8"))}catch{continue}
      for(const [id,on] of Object.entries(s.enabledPlugins||{}))
        console.log([scope,id,on?"enabled":"disabled"].join("\u001f"))
    }' "$project_dir")
  [[ "$any" -eq 0 ]] && echo "  (none)"
  printf '\033[2mUser-scope plugins are global, not listed here — see: claude plugin list\033[0m\n'
  exit 0
fi

# Install/uninstall need the claude CLI; the settings edits and marketplace
# registry are its domain.
if ! command -v claude >/dev/null 2>&1; then
  echo "✗ claude CLI required — plugin install only works with Claude Code installed" >&2
  exit 1
fi

# Plugin enablement is written to <target>/.claude/settings*.json. If .claude
# itself is a symlink (some manual cross-tool setups), those writes would land
# in whatever it points at — refuse rather than scribble elsewhere.
if [[ -L "$project_dir/.claude" ]]; then
  echo "✗ $project_dir/.claude is a symlink — plugin settings would be written through it into another directory. Make it a real directory first." >&2
  exit 1
fi

# Sub-repo folders and their upstream URLs, read from .meta.
projects=()
project_urls=()
while IFS=$'\x1f' read -r folder url; do
  [[ -n "$folder" ]] || continue
  projects+=("$folder")
  project_urls+=("$url")
done < <(node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).projects||{};for(const [k,v] of Object.entries(p))console.log(k+"\u001f"+v)' "$meta_file")

url_of() {
  local folder="$1" i
  for i in "${!projects[@]}"; do
    [[ "${projects[$i]}" == "$folder" ]] && { echo "${project_urls[$i]}"; return; }
  done
  echo ""
}

# "owner/repo" for GitHub URLs (https or ssh), empty otherwise.
github_shorthand() {
  local u="$1"
  case "$u" in
    https://github.com/*) u="${u#https://github.com/}"; echo "${u%.git}" ;;
    git@github.com:*)     u="${u#git@github.com:}";     echo "${u%.git}" ;;
    *) echo "" ;;
  esac
}

# Discover installable plugins across sub-repos.
pnames=()     # plugin name
pmarkets=()   # marketplace name it installs from
pids=()       # name@marketplace
prepos=()     # sub-repo folder
pstypes=()    # marketplace entry source: relative | github | url | ... | synth
plabels=()    # display label for the picker
for i in "${!projects[@]}"; do
  proj="${projects[$i]}"
  proj_dir="$repo_root/$proj"
  if [[ ! -d "$proj_dir" ]]; then
    echo "Warning: sub-repo not cloned, skipping: $proj (run 'meta git update')" >&2
    continue
  fi
  cp_dir="$proj_dir/.claude-plugin"
  if [[ -f "$cp_dir/marketplace.json" ]]; then
    while IFS=$'\x1f' read -r mname pname stype; do
      [[ -n "$pname" ]] || continue
      pnames+=("$pname")
      pmarkets+=("$mname")
      pids+=("$pname@$mname")
      prepos+=("$proj")
      pstypes+=("$stype")
      plabels+=("$pname@$mname  ($proj)")
    done < <(node -e '
      const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
      for(const p of m.plugins||[]){
        let st="relative";
        if(p.source&&typeof p.source==="object")st=p.source.source||"?";
        console.log([m.name,p.name,st].join("\u001f"))
      }' "$cp_dir/marketplace.json")
  elif [[ -f "$cp_dir/plugin.json" ]]; then
    pname="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).name||"")' "$cp_dir/plugin.json")"
    [[ -n "$pname" ]] || pname="$proj"
    pnames+=("$pname")
    pmarkets+=("$synth_market")
    pids+=("$pname@$synth_market")
    prepos+=("$proj")
    pstypes+=("synth")
    plabels+=("$pname@$synth_market  ($proj, via synthesized marketplace)")
  fi
done

if [[ ${#pnames[@]} -eq 0 ]]; then
  echo "No Claude Code plugins found across sub-repos (looked for .claude-plugin/)." >&2
  exit 1
fi

# Resolve the selection into indices; names may be bare or name@marketplace.
chosen_idx=()
resolve_plugin() {
  local item="$1" i hits=""
  for i in "${!pids[@]}"; do
    if [[ "${pids[$i]}" == "$item" || "${pnames[$i]}" == "$item" ]]; then
      hits="$hits $i"
    fi
  done
  echo "$hits"
}

add_selection() {
  local item="$1" hits
  hits="$(resolve_plugin "$item")"
  # shellcheck disable=SC2086  # hits is a space-separated list of numeric indices
  set -- $hits
  if [[ $# -eq 0 ]]; then
    echo "No plugin named '$item' found across sub-repos (try 'make list-plugins')." >&2
    exit 1
  fi
  if [[ $# -gt 1 ]]; then
    echo "'$item' matches several plugins — use the name@marketplace form:" >&2
    local i; for i in "$@"; do echo "  - ${pids[$i]}" >&2; done
    exit 1
  fi
  chosen_idx+=("$1")
}

if [[ ${#selection_args[@]} -gt 0 ]]; then
  if [[ "${selection_args[0]}" == "all" ]]; then
    for i in "${!pids[@]}"; do chosen_idx+=("$i"); done
  else
    for arg in "${selection_args[@]}"; do add_selection "$arg"; done
  fi
else
  echo "Source:  $repo_root (across sub-repos, --source $source_mode)"
  if [[ "$mode" == "uninstall" ]]; then
    echo "Action:  uninstall from $project_dir (scope: $scope)"
  else
    echo "Target:  $project_dir (scope: $scope)"
  fi
  echo
  echo "Available plugins:"
  for i in "${!plabels[@]}"; do
    printf "  %2d) %s\n" "$((i + 1))" "${plabels[$i]}"
  done
  echo
  echo "Enter numbers separated by spaces, plugin names, or 'all':"
  read -r selection
  if [[ "$selection" == "all" ]]; then
    for i in "${!pids[@]}"; do chosen_idx+=("$i"); done
  else
    for item in $selection; do
      if [[ "$item" =~ ^[0-9]+$ ]]; then
        index=$((item - 1))
        if (( index < 0 || index >= ${#pids[@]} )); then
          echo "Selection out of range: $item" >&2
          exit 1
        fi
        chosen_idx+=("$index")
      else
        add_selection "$item"
      fi
    done
  fi
fi

if [[ ${#chosen_idx[@]} -eq 0 ]]; then
  echo "No plugins selected."
  exit 0
fi

if [[ "$mode" == "uninstall" ]]; then
  removed_any=0
  markets_hint=""
  for index in "${chosen_idx[@]}"; do
    id="${pids[$index]}"
    if (cd "$project_dir" && claude plugin uninstall "$id" --scope "$scope"); then
      removed_any=1
      m="${pmarkets[$index]}"
      case " $markets_hint " in *" $m "*) ;; *) markets_hint="$markets_hint $m" ;; esac
    else
      echo "Not installed (or uninstall failed): $id"
    fi
  done
  if [[ "$removed_any" -eq 1 ]]; then
    echo "ℹ marketplaces stay registered (other repos may use them) — remove with:"
    for m in $markets_hint; do echo "    claude plugin marketplace remove $m"; done
  else
    echo "Nothing to uninstall."
  fi
  exit 0
fi

# Regenerate the synthesized marketplace when a selected plugin needs it, so
# its entry sources reflect the requested --source mode.
needs_synth=0
for index in "${chosen_idx[@]}"; do
  if [[ "${pmarkets[$index]}" == "$synth_market" ]]; then needs_synth=1; fi
done
if [[ "$needs_synth" -eq 1 ]]; then
  node -e '
    const fs=require("fs"),path=require("path");
    const root=process.argv[1], mode=process.argv[2], mname=process.argv[3];
    const meta=JSON.parse(fs.readFileSync(path.join(root,".meta"),"utf8")).projects||{};
    const plugins=[];
    for(const [folder,url] of Object.entries(meta)){
      const cp=path.join(root,folder,".claude-plugin");
      if(fs.existsSync(path.join(cp,"marketplace.json")))continue;
      const pj=path.join(cp,"plugin.json");
      if(!fs.existsSync(pj))continue;
      const man=JSON.parse(fs.readFileSync(pj,"utf8"));
      let source="./"+folder;
      if(mode==="origin"){
        const m=url.match(/^https:\/\/github\.com\/(.+?)(\.git)?$/)||url.match(/^git@github\.com:(.+?)(\.git)?$/);
        source=m?{source:"github",repo:m[1]}:{source:"url",url};
      }
      const entry={name:man.name||folder,source};
      if(man.description)entry.description=man.description;
      plugins.push(entry);
    }
    const mp={name:mname,
      description:"Synthesized marketplace for plugin-only sub-repos of this meta-repo (generated by bin/install-plugins.sh — do not edit)",
      owner:{name:"meta-skills"},plugins};
    fs.mkdirSync(path.join(root,".claude-plugin"),{recursive:true});
    fs.writeFileSync(path.join(root,".claude-plugin","marketplace.json"),JSON.stringify(mp,null,2)+"\n");
  ' "$repo_root" "$source_mode" "$synth_market"
  echo "Generated synthesized marketplace: .claude-plugin/marketplace.json (--source $source_mode)"
fi

# Registered marketplace names, fetched once.
registered=""
registered="$(claude plugin marketplace list --json 2>/dev/null | node -e '
  let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{
    try{for(const m of JSON.parse(d))console.log(m.name)}catch{}
  })' || true)"

is_registered() {
  local name="$1" line
  while IFS= read -r line; do
    [[ "$line" == "$name" ]] && return 0
  done <<< "$registered"
  return 1
}

# Register a marketplace once, honouring --source. Never re-point an existing
# registration — say how to switch instead.
ensure_marketplace() {
  local mname="$1" folder="$2" src
  if is_registered "$mname"; then
    if [[ "$mname" == "$synth_market" && "$needs_synth" -eq 1 ]]; then
      # Pick up the regenerated marketplace.json.
      claude plugin marketplace update "$mname"
    fi
    echo "Marketplace already registered: $mname (to change its source: claude plugin marketplace remove $mname, then re-run)"
    return
  fi
  if [[ "$mname" == "$synth_market" ]]; then
    src="$repo_root"
  elif [[ "$source_mode" == "local" ]]; then
    src="$repo_root/$folder"
  else
    src="$(github_shorthand "$(url_of "$folder")")"
    [[ -n "$src" ]] || src="$(url_of "$folder")"
  fi
  echo "→ registering marketplace '$mname' from $src"
  claude plugin marketplace add "$src"
}

seen_markets=""
for index in "${chosen_idx[@]}"; do
  m="${pmarkets[$index]}"
  case " $seen_markets " in *" $m "*) continue ;; esac
  seen_markets="$seen_markets $m"
  ensure_marketplace "$m" "${prepos[$index]}"
done

for index in "${chosen_idx[@]}"; do
  id="${pids[$index]}"
  echo "→ installing $id (scope: $scope) into $project_dir"
  (cd "$project_dir" && claude plugin install "$id" --scope "$scope")
  if [[ "$source_mode" == "local" && "${pstypes[$index]}" == "github" ]]; then
    echo "ℹ $id: its marketplace entry pins a GitHub source, so the plugin content was fetched from GitHub (into ~/.claude/plugins/cache), not from the local clone."
  fi
done
