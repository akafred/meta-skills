#!/usr/bin/env bash
set -euo pipefail

# Installs skills into a target repo's .claude/skills/ by symlinking SKILL.md
# directories discovered across every sub-repo listed in this meta-repo's .meta.
#
# Usage:
#   ./install-skills.sh [--target DIR] [SKILL...]
#
#   --target DIR, -t DIR   Repo to install skills into (default: this meta-repo).
#                          This is the main use: point it at the repo you want
#                          a skill installed into.
#   SKILL...               Skill name(s) to install, or 'all'. Omit for an
#                          interactive picker.
#
# Examples:
#   ./install-skills.sh                              # interactive, into this meta-repo
#   ./install-skills.sh meta-repo                    # named, into this meta-repo
#   ./install-skills.sh --target ~/code/app all      # everything, into ~/code/app
#   ./install-skills.sh -t ~/code/app code-review    # one skill, into ~/code/app
#
# Source of truth is .meta; sub-repos must already be cloned
# (e.g. via `meta git clone` / `meta git update`).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
meta_file="$repo_root/.meta"
project_dir="$repo_root"

# Parse options; collect non-option args as the skill selection.
selection_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)
      [[ $# -ge 2 ]] || { echo "$1 requires a directory argument" >&2; exit 1; }
      project_dir="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '3,24p' "$0" | sed 's/^# \{0,1\}//'
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
target_dir="$project_dir/.claude/skills"

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
    names+=("$(basename "$skill_dir")")
    sources+=("$skill_dir")
    labels+=("$(basename "$skill_dir")  ($proj)")
  done < <(find "$proj_dir" -name SKILL.md -print | sort)
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
  echo "Target:  $target_dir"
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

mkdir -p "$target_dir"

for index in "${chosen_idx[@]}"; do
  name="${names[$index]}"
  source_dir="${sources[$index]}"
  link_path="$target_dir/$name"
  # Relative link (resolved from the link's own directory), so committed links
  # stay valid across clones and machines.
  link_target="$(node -e 'console.log(require("path").relative(process.argv[1], process.argv[2]))' "$target_dir" "$source_dir")"

  if [[ -L "$link_path" ]]; then
    if [[ "$(readlink "$link_path")" == "$link_target" ]]; then
      echo "Already linked: $name"
      continue
    fi
    echo "Replacing existing symlink: $name"
    rm "$link_path"
  elif [[ -e "$link_path" ]]; then
    echo "Skipping $name: target exists and is not a symlink ($link_path)" >&2
    continue
  fi

  ln -s "$link_target" "$link_path"
  echo "Linked: $name -> $link_target"
done
