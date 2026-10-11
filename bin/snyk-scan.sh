#!/usr/bin/env bash
# Scan the skills in the public sub-repos with Snyk agent scan.
#
# The scanner treats each path as a directory of skills and only looks at its direct
# children, so we pass every directory that directly contains skill folders. Sub-repos
# listed under "# Private sub-repos" in .gitignore are skipped: the scan uploads skill
# files to api.snyk.io.
set -euo pipefail
cd "$(dirname "$0")/.."

mapfile -t private < <(awk '/^# Private sub-repos/ { p = 1; next } /^$/ { p = 0 } p && /^\// { gsub("/", ""); print }' .gitignore)

is_private() {
  local repo
  for repo in "${private[@]}"; do [[ $1 == "$repo" ]] && return 0; done
  return 1
}

dirs=()
for repo in */; do
  repo=${repo%/}
  [[ -e $repo/.git ]] || continue
  if is_private "$repo"; then echo "→ skipping private $repo"; continue; fi
  while IFS= read -r skill_md; do
    container=$(dirname "$(dirname "$skill_md")")
    if [[ $container == "$repo/.." ]]; then
      echo "⚠ $repo has a SKILL.md at its root; not scanned (the scan would include sibling repos)"
      continue
    fi
    dirs+=("$container")
  done < <(find "$repo" \( -name .git -o -name node_modules \) -prune -o -name SKILL.md -print)
done

mapfile -t dirs < <(printf '%s\n' "${dirs[@]}" | sort -u)
echo "→ scanning ${#dirs[@]} skill directories in public sub-repos"
exec uvx snyk-agent-scan@latest "${dirs[@]}"
