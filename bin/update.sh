#!/usr/bin/env bash
set -euo pipefail

# Update all sub-repos (clone newly-added ones, pull the rest) and summarize how
# the available skills changed: added, removed, and changed (by SKILL.md content).
#
# Source of truth is .meta.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
meta_file="$repo_root/.meta"
[[ -f "$meta_file" ]] || { echo "No .meta file at $meta_file (run from a meta-repo root)" >&2; exit 1; }

projects=()
while IFS= read -r line; do
  [[ -n "$line" ]] && projects+=("$line")
done < <(node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).projects||{};for(const k of Object.keys(p))console.log(k)' "$meta_file")

name_of() {
  local n; n="$(sed -n 's/^name:[[:space:]]*//p' "$1" | head -1)"
  [[ -n "$n" ]] && printf '%s' "$n" || basename "$(dirname "$1")"
}

# Snapshot every skill as "relpath<TAB>contenthash<TAB>name", sorted by relpath.
snapshot() {
  local out="$1" proj proj_dir f rel
  {
    for proj in "${projects[@]}"; do
      proj_dir="$repo_root/$proj"
      [[ -d "$proj_dir" ]] || continue
      while IFS= read -r f; do
        rel="${f%/SKILL.md}"; rel="${rel#"$repo_root"/}"
        printf '%s\t%s\t%s\n' "$rel" "$(shasum "$f" | awk '{print $1}')" "$(name_of "$f")"
      done < <(find "$proj_dir" -name SKILL.md -print)
    done
  } | sort > "$out"
}

before="$(mktemp)"; after="$(mktemp)"
trap 'rm -f "$before" "$after"' EXIT

snapshot "$before"

echo "Updating sub-repos…"
meta git update                                                              # clone any newly-added sub-repos
meta exec "git pull --rebase --autostash" --parallel --exclude "$(basename "$repo_root")"

snapshot "$after"

# Look up a skill's display name by relpath from a snapshot file.
name_for() { awk -F'\t' -v r="$1" '$1==r{print $3; exit}' "$2"; }

added="$(comm -13 <(cut -f1 "$before") <(cut -f1 "$after"))"
removed="$(comm -23 <(cut -f1 "$before") <(cut -f1 "$after"))"
changed="$(join -t"$(printf '\t')" "$before" "$after" | awk -F'\t' '$2!=$4{print $1}')"

echo
echo "Skill changes:"
n=0
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  printf '  \033[32m+ %s\033[0m  \033[2m%s\033[0m\n' "$(name_for "$rel" "$after")" "$rel"; n=$((n+1))
done <<< "$added"
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  printf '  \033[31m- %s\033[0m  \033[2m%s\033[0m\n' "$(name_for "$rel" "$before")" "$rel"; n=$((n+1))
done <<< "$removed"
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  printf '  \033[33m~ %s\033[0m  \033[2m%s\033[0m\n' "$(name_for "$rel" "$after")" "$rel"; n=$((n+1))
done <<< "$changed"
if [[ "$n" -eq 0 ]]; then echo "  (no changes)"; fi
