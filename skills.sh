#!/usr/bin/env bash
set -euo pipefail

# List or search skills discovered across every sub-repo listed in .meta.
#
# Usage:
#   ./skills.sh list            # list every skill: name (repo) — description
#   ./skills.sh search QUERY     # search name/description/body of each SKILL.md
#
# Source of truth is .meta; sub-repos must already be cloned (make bootstrap).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
meta_file="$repo_root/.meta"
cmd="${1:-list}"
query="${2:-}"

if [[ ! -f "$meta_file" ]]; then
  echo "No .meta file at $meta_file (run from a meta-repo root)" >&2
  exit 1
fi

projects=()
while IFS= read -r line; do
  [[ -n "$line" ]] && projects+=("$line")
done < <(node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).projects||{};for(const k of Object.keys(p))console.log(k)' "$meta_file")

# Collect SKILL.md paths across all cloned sub-repos.
skill_files=()
for proj in "${projects[@]}"; do
  proj_dir="$repo_root/$proj"
  [[ -d "$proj_dir" ]] || { echo "Warning: sub-repo not cloned, skipping: $proj (make update)" >&2; continue; }
  while IFS= read -r f; do
    skill_files+=("$f")
  done < <(find "$proj_dir" -name SKILL.md -print | sort)
done

if [[ ${#skill_files[@]} -eq 0 ]]; then
  echo "No skills found. Clone sub-repos first: make bootstrap" >&2
  exit 1
fi

# Frontmatter field from the leading --- block (first match wins).
field() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -1; }

print_skill() {
  local f="$1" dir name desc proj
  dir="$(dirname "$f")"
  proj="${f#"$repo_root"/}"; proj="${proj%%/*}"
  name="$(field "$f" name)"; [[ -n "$name" ]] || name="$(basename "$dir")"
  desc="$(field "$f" description)"
  if [[ -n "$desc" ]]; then
    printf "\033[36m%-22s\033[0m \033[2m%-18s\033[0m %s\n" "$name" "($proj)" "$desc"
  else
    printf "\033[36m%-22s\033[0m \033[2m%-18s\033[0m\n" "$name" "($proj)"
  fi
}

case "$cmd" in
  list)
    for f in "${skill_files[@]}"; do print_skill "$f"; done
    ;;
  search)
    [[ -n "$query" ]] || { echo "Usage: ./skills.sh search QUERY" >&2; exit 1; }
    hits=0
    for f in "${skill_files[@]}"; do
      if grep -iq -- "$query" "$f"; then
        hits=$((hits + 1))
        print_skill "$f"
        # show the matching lines (skip frontmatter keys for signal)
        grep -in -- "$query" "$f" | grep -viE '^[0-9]+:(name|description):' | sed 's/^/    /' || true
      fi
    done
    [[ $hits -gt 0 ]] || { echo "No skills match: $query"; exit 1; }
    ;;
  *)
    echo "Unknown command: $cmd (use 'list' or 'search QUERY')" >&2
    exit 1
    ;;
esac
