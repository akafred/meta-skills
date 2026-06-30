#!/usr/bin/env bash
set -euo pipefail

# Installs skills into THIS meta-repo's .claude/skills/ by symlinking SKILL.md
# directories discovered across every sub-repo listed in .meta.
#
# Usage:
#   ./install-skills.sh                 # interactive picker
#   ./install-skills.sh all             # install every discovered skill
#   ./install-skills.sh meta-repo ...   # install named skill(s) non-interactively
#
# Source of truth is the .meta file; sub-repos must already be cloned
# (e.g. via `meta git clone` / `meta git update`).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
meta_file="$repo_root/.meta"
target_dir="$repo_root/.claude/skills"

if [[ ! -f "$meta_file" ]]; then
  echo "No .meta file at $meta_file (run this from a meta-repo root)" >&2
  exit 1
fi

# Sub-repo folder names, read from .meta (node is a meta prerequisite).
projects=()
while IFS= read -r line; do
  [[ -n "$line" ]] && projects+=("$line")
done < <(node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).projects||{};for(const k of Object.keys(p))console.log(k)' "$meta_file")

# Discover skills across all sub-repos.
names=()        # skill name (link name)
rels=()         # source dir relative to repo_root
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
    rels+=("${skill_dir#"$repo_root"/}")
    labels+=("$(basename "$skill_dir")  ($proj)")
  done < <(find "$proj_dir" -name SKILL.md -print | sort)
done

if [[ ${#names[@]} -eq 0 ]]; then
  echo "No skills found across sub-repos. Clone them first: meta git clone / meta git update" >&2
  exit 1
fi

# Resolve the selection into indices.
chosen_idx=()
if [[ $# -gt 0 ]]; then
  if [[ "$1" == "all" ]]; then
    for i in "${!names[@]}"; do chosen_idx+=("$i"); done
  else
    for arg in "$@"; do
      found=0
      for i in "${!names[@]}"; do
        if [[ "${names[$i]}" == "$arg" ]]; then chosen_idx+=("$i"); found=1; fi
      done
      if [[ $found -eq 0 ]]; then
        echo "No skill named '$arg' found across sub-repos." >&2
        exit 1
      fi
    done
  fi
else
  echo "Target: $target_dir"
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
        match=-1
        for i in "${!names[@]}"; do
          [[ "${names[$i]}" == "$item" ]] && match="$i"
        done
        if [[ "$match" -lt 0 ]]; then
          echo "No skill named '$item' found." >&2
          exit 1
        fi
        chosen_idx+=("$match")
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
  rel="${rels[$index]}"
  link_path="$target_dir/$name"
  # Relative link: .claude/skills -> repo_root is ../.. , then the source rel path.
  link_target="../../$rel"

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
  echo "Linked: $name -> $rel"
done
