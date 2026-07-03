#!/usr/bin/env bash
set -euo pipefail

# Installs skills into a target repo by symlinking SKILL.md directories
# discovered across every sub-repo listed in this meta-repo's .meta.
#
# Skill folders are chosen for cross-tool compatibility (Claude Code, Copilot
# CLI, OpenCode, Codex): real per-skill links go into whichever of
# .claude/skills / .agents/skills / .github/skills / .gemini/skills /
# .opencode/skills already exist (each, if 2+), else a single canonical dir
# (.agents/skills when none exist) with .claude/.agents folder-symlinked to it.
#
# Usage:
#   ./install-skills.sh [--target DIR] [--list | --uninstall] [SKILL...]
#
#   --target DIR, -t DIR   Repo to install into / list / uninstall from
#                          (default: this meta-repo). Point it at the repo you
#                          want skills installed into.
#   --list, -l             List skills already installed in the target, and where
#                          each link points (no SKILL args needed).
#   --uninstall, -u        Remove the selected skills' links from the target
#                          (and clean up emptied skill dirs / stale dir links).
#   SKILL...               Skill name(s) to install, or 'all'. Omit for an
#                          interactive picker.
#
# Examples:
#   ./install-skills.sh                              # interactive, into this meta-repo
#   ./install-skills.sh meta-repo                    # named, into this meta-repo
#   ./install-skills.sh --target ~/code/app all      # everything, into ~/code/app
#   ./install-skills.sh -t ~/code/app code-review    # one skill, into ~/code/app
#   ./install-skills.sh --list                       # what's installed in this meta-repo
#   ./install-skills.sh --list -t ~/code/app         # what's installed in ~/code/app
#   ./install-skills.sh -u -t ~/code/app code-review # uninstall one skill
#   ./install-skills.sh --uninstall all              # uninstall all, from this meta-repo
#
# Source of truth is .meta; sub-repos must already be cloned
# (e.g. via `meta git clone` / `meta git update`).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
meta_file="$repo_root/.meta"
project_dir="$repo_root"

# Skill name comes from the SKILL.md 'name:' frontmatter, falling back to the
# containing directory's basename (matches skills.sh). This lets a skill whose
# SKILL.md sits at its repo root still be addressed by its declared name.
field() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -1; }
name_of() { local n; n="$(field "$1" name)"; [[ -n "$n" ]] && echo "$n" || basename "$(dirname "$1")"; }

# Parse options; collect non-option args as the skill selection.
mode="install"
selection_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)
      [[ $# -ge 2 ]] || { echo "$1 requires a directory argument" >&2; exit 1; }
      project_dir="$2"
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

# Decide where to install skills for cross-tool compatibility.
#
# Different agents discover skills from different per-repo folders:
#   .claude/skills    Claude Code, Copilot CLI, OpenCode
#   .agents/skills    Copilot CLI, OpenCode, Codex (the vendor-neutral standard)
#   .github/skills    Copilot CLI
#   .gemini/skills    Gemini CLI
#   .opencode/skills  OpenCode
#
# .claude/skills + .agents/skills together cover all four major tools, so those
# are the only dirs we ever auto-create (the "materialize" set). The detection
# set is wider: if a repo already opted into any of them, we respect it.
#
# Logic, by how many prominent skill dirs already physically exist:
#   >= 2 exist  -> install real per-skill links into EACH (respect the repo).
#   exactly 1   -> that one is canonical; real links there, then folder-level
#                  symlink the missing materialize dirs to it.
#   0 exist     -> create .agents/skills as canonical, then folder-level symlink
#                  the rest of the materialize set to it.
detect_dirs=(.claude/skills .agents/skills .github/skills .gemini/skills .opencode/skills)
materialize_dirs=(.claude/skills .agents/skills)

existing_dirs=()
for d in "${detect_dirs[@]}"; do
  [[ -e "$project_dir/$d" || -L "$project_dir/$d" ]] && existing_dirs+=("$d")
done

# Resolve a symlink's target to an absolute path via pure path math (target need
# not exist), so dangling links are still recognized.
resolve_link_abs() {
  node -e 'const fs=require("fs"),path=require("path");const p=process.argv[1];console.log(path.resolve(path.dirname(p),fs.readlinkSync(p)))' "$1"
}

# --list: show what's installed in the target and where each link points.
if [[ "$mode" == "list" ]]; then
  echo "Installed skills in $project_dir:"
  any=0
  for d in "${detect_dirs[@]}"; do
    dir_path="$project_dir/$d"
    [[ -e "$dir_path" || -L "$dir_path" ]] || continue
    # A skill dir that is itself a symlink is a folder-level mirror of another.
    if [[ -L "$dir_path" ]]; then
      mirror="$(cd "$dir_path" 2>/dev/null && pwd -P || true)"
      mirror="${mirror#"$project_dir"/}"
      printf '  \033[2m%s -> %s (mirror)\033[0m\n' "$d" "${mirror:-?}"
      continue
    fi
    [[ -d "$dir_path" ]] || continue
    printf '  \033[1m%s\033[0m\n' "$d"
    listed=0
    while IFS= read -r e; do
      [[ -n "$e" ]] || continue
      listed=1; any=1
      name="$(basename "$e")"
      if [[ -L "$e" ]]; then
        tgt="$(resolve_link_abs "$e")"
        if [[ "$tgt" == "$repo_root"/* ]]; then
          mark=""; [[ -e "$e" ]] || mark=" \033[31m(dangling — run 'make update')\033[0m"
          printf "    \033[36m%s\033[0m -> %s$mark\n" "$name" "${tgt#"$repo_root"/}"
        else
          printf "    \033[36m%s\033[0m -> %s \033[2m(external)\033[0m\n" "$name" "$tgt"
        fi
      elif [[ -d "$e" ]]; then
        printf "    \033[36m%s\033[0m \033[2m(local dir)\033[0m\n" "$name"
      fi
    done < <(find "$dir_path" -mindepth 1 -maxdepth 1 | sort)
    [[ "$listed" -eq 0 ]] && printf '    (empty)\n'
  done
  [[ "$any" -eq 0 ]] && echo "  (none)"
  exit 0
fi

target_dirs=()        # dirs that receive real per-skill links
canonical_rel=""      # set only when there is a single canonical dir
if [[ ${#existing_dirs[@]} -ge 2 ]]; then
  for d in "${existing_dirs[@]}"; do target_dirs+=("$project_dir/$d"); done
else
  if [[ ${#existing_dirs[@]} -eq 1 ]]; then
    canonical_rel="${existing_dirs[0]}"
  else
    canonical_rel=".agents/skills"
  fi
  target_dirs+=("$project_dir/$canonical_rel")
fi

# Create folder-level symlinks from the materialize set to the canonical dir.
link_dir_to_canonical() {
  local canonical_abs="$project_dir/$canonical_rel"
  for d in "${materialize_dirs[@]}"; do
    [[ "$d" == "$canonical_rel" ]] && continue
    local link_path="$project_dir/$d"
    [[ -e "$link_path" || -L "$link_path" ]] && continue
    local link_parent; link_parent="$(dirname "$link_path")"
    mkdir -p "$link_parent"
    local rel; rel="$(node -e 'console.log(require("path").relative(process.argv[1], process.argv[2]))' "$link_parent" "$canonical_abs")"
    ln -s "$rel" "$link_path"
    echo "Linked dir: $d -> $rel"
  done
}

# Sub-repo folder names, read from .meta (node is a meta prerequisite).
projects=()
while IFS= read -r line; do
  [[ -n "$line" ]] && projects+=("$line")
done < <(node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).projects||{};for(const k of Object.keys(p))console.log(k)' "$meta_file")

# Discover skills across all sub-repos.
names=()        # skill name (link name)
sources=()      # absolute source dir
labels=()       # display label
for proj in "${projects[@]}"; do
  proj_dir="$repo_root/$proj"
  if [[ ! -d "$proj_dir" ]]; then
    echo "Warning: sub-repo not cloned, skipping: $proj (run 'meta git update')" >&2
    continue
  fi
  while IFS= read -r skill_md; do
    skill_dir="$(dirname "$skill_md")"
    names+=("$(name_of "$skill_md")")
    sources+=("$skill_dir")
    labels+=("$(name_of "$skill_md")  ($proj)")
  done < <(find "$proj_dir" \( -name node_modules -o -name .git \) -prune -o -name SKILL.md -print | sort)
done

if [[ ${#names[@]} -eq 0 ]]; then
  echo "No skills found across sub-repos. Clone them first: meta git clone / meta git update" >&2
  exit 1
fi

# Resolve the selection into indices.
chosen_idx=()
resolve_name() {
  local item="$1" match=-1 i
  for i in "${!names[@]}"; do
    [[ "${names[$i]}" == "$item" ]] && match="$i"
  done
  echo "$match"
}

if [[ ${#selection_args[@]} -gt 0 ]]; then
  if [[ "${selection_args[0]}" == "all" ]]; then
    for i in "${!names[@]}"; do chosen_idx+=("$i"); done
  else
    for arg in "${selection_args[@]}"; do
      idx="$(resolve_name "$arg")"
      if [[ "$idx" -lt 0 ]]; then
        echo "No skill named '$arg' found across sub-repos." >&2
        exit 1
      fi
      chosen_idx+=("$idx")
    done
  fi
else
  echo "Source:  $repo_root (across sub-repos)"
  if [[ "$mode" == "uninstall" ]]; then
    echo "Action:  uninstall from $project_dir"
  else
    echo "Target:  ${target_dirs[*]}"
  fi
  echo
  echo "Available skills:"
  for i in "${!labels[@]}"; do
    printf "  %2d) %s\n" "$((i + 1))" "${labels[$i]}"
  done
  echo
  echo "Enter numbers separated by spaces, skill names, or 'all':"
  read -r selection
  if [[ "$selection" == "all" ]]; then
    for i in "${!names[@]}"; do chosen_idx+=("$i"); done
  else
    for item in $selection; do
      if [[ "$item" =~ ^[0-9]+$ ]]; then
        index=$((item - 1))
        if (( index < 0 || index >= ${#names[@]} )); then
          echo "Selection out of range: $item" >&2
          exit 1
        fi
        chosen_idx+=("$index")
      else
        idx="$(resolve_name "$item")"
        if [[ "$idx" -lt 0 ]]; then
          echo "No skill named '$item' found." >&2
          exit 1
        fi
        chosen_idx+=("$idx")
      fi
    done
  fi
fi

if [[ ${#chosen_idx[@]} -eq 0 ]]; then
  echo "No skills selected."
  exit 0
fi

if [[ "$mode" == "uninstall" ]]; then
  removed_any=0
  for index in "${chosen_idx[@]}"; do
    name="${names[$index]}"
    found=0
    for d in "${detect_dirs[@]}"; do
      dir_path="$project_dir/$d"
      # Only descend into real skill dirs; folder-level symlinks are handled in cleanup.
      [[ -d "$dir_path" && ! -L "$dir_path" ]] || continue
      link_path="$dir_path/$name"
      [[ -L "$link_path" ]] || continue
      # Safety: only remove links that point back into this meta-repo's sub-repos.
      if [[ "$(resolve_link_abs "$link_path")" == "$repo_root"/* ]]; then
        rm "$link_path"
        echo "Removed: $name ($dir_path)"
        found=1
        removed_any=1
      fi
    done
    [[ "$found" -eq 0 ]] && echo "Not installed: $name"
  done

  # Cleanup, in order: drop now-empty real skill dirs (and empty parents), then
  # remove folder-level symlinks whose canonical target is gone or empty.
  is_empty_dir() { [[ -z "$(ls -A "$1" 2>/dev/null)" ]]; }
  for d in "${detect_dirs[@]}"; do
    dir_path="$project_dir/$d"
    if [[ -d "$dir_path" && ! -L "$dir_path" ]] && is_empty_dir "$dir_path"; then
      rmdir "$dir_path" && echo "Removed empty dir: $d"
      rmdir "$(dirname "$dir_path")" 2>/dev/null || true
    fi
  done
  for d in "${detect_dirs[@]}"; do
    dir_path="$project_dir/$d"
    if [[ -L "$dir_path" ]]; then
      target_abs="$(resolve_link_abs "$dir_path")"
      if [[ ! -d "$target_abs" ]] || is_empty_dir "$target_abs"; then
        rm "$dir_path" && echo "Removed dangling dir link: $d"
        rmdir "$(dirname "$dir_path")" 2>/dev/null || true
      fi
    fi
  done

  [[ "$removed_any" -eq 0 ]] && echo "Nothing to uninstall."
  exit 0
fi

mkdir -p "${target_dirs[@]}"

for index in "${chosen_idx[@]}"; do
  name="${names[$index]}"
  source_dir="${sources[$index]}"
  for target_dir in "${target_dirs[@]}"; do
    link_path="$target_dir/$name"
    # Relative link (resolved from the link's own directory), so committed links
    # stay valid across clones and machines.
    link_target="$(node -e 'console.log(require("path").relative(process.argv[1], process.argv[2]))' "$target_dir" "$source_dir")"

    if [[ -L "$link_path" ]]; then
      if [[ "$(readlink "$link_path")" == "$link_target" ]]; then
        echo "Already linked: $name ($target_dir)"
        continue
      fi
      echo "Replacing existing symlink: $name ($target_dir)"
      rm "$link_path"
    elif [[ -e "$link_path" ]]; then
      echo "Skipping $name: target exists and is not a symlink ($link_path)" >&2
      continue
    fi

    ln -s "$link_target" "$link_path"
    echo "Linked: $name -> $link_target ($target_dir)"
  done
done

# When there's a single canonical dir, point the other tools' folders at it.
# (Plain `[[ ]] && cmd` would make the script exit non-zero when canonical_rel
# is empty — the multi-dir case — so use an explicit if.)
if [[ -n "$canonical_rel" ]]; then link_dir_to_canonical; fi
