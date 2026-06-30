#!/usr/bin/env bash
set -euo pipefail

# List or search skills discovered across every sub-repo listed in .meta.
#
# Usage:
#   ./skills.sh list             # grouped by repo and category: name — description
#   ./skills.sh search QUERY      # search name/description/body of each SKILL.md
#   ./skills.sh show NAME         # pretty-print a skill's SKILL.md
#
# Source of truth is .meta; sub-repos must already be cloned (make bootstrap).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
meta_file="$repo_root/.meta"
cmd="${1:-list}"
query="${2:-}"

if [[ ! -f "$meta_file" ]]; then
  echo "No .meta file at $meta_file (run from a meta-repo root)" >&2
  exit 1
fi

# Detect terminal width so descriptions stay on one line. COLUMNS is an explicit
# override; otherwise ask the controlling terminal directly (works even when our
# stdout is a pipe, e.g. under make or `| head`), then fall back to tput, then 80.
detect_cols() {
  local c
  if [[ "${COLUMNS:-}" =~ ^[0-9]+$ ]]; then echo "$COLUMNS"; return; fi
  c="$( { stty size </dev/tty | awk '{print $2}'; } 2>/dev/null || true )"
  [[ "$c" =~ ^[0-9]+$ && "$c" -gt 0 ]] && { echo "$c"; return; }
  c="$( (tput cols) 2>/dev/null || true )"
  [[ "$c" =~ ^[0-9]+$ && "$c" -gt 0 ]] && { echo "$c"; return; }
  echo 80
}
cols="$(detect_cols)"

projects=()
while IFS= read -r line; do
  [[ -n "$line" ]] && projects+=("$line")
done < <(node -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).projects||{};for(const k of Object.keys(p))console.log(k)' "$meta_file")

# Collect SKILL.md paths across all cloned sub-repos (sorted by path => grouped).
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

field() { sed -n "s/^$2:[[:space:]]*//p" "$1" | head -1; }
repo_of() { local r="${1#"$repo_root"/}"; echo "${r%%/*}"; }
name_of() { local n; n="$(field "$1" name)"; [[ -n "$n" ]] && echo "$n" || basename "$(dirname "$1")"; }

# Category = path between the repo folder and the skill folder, minus a leading "skills".
category_of() {
  local rel="${1#"$repo_root"/}"; rel="${rel%/SKILL.md}"
  local after="${rel#*/}"
  [[ "$after" == "$rel" ]] && { echo ""; return; }      # no category segment
  local cat="${after%/*}"
  [[ "$cat" == "$after" ]] && { echo ""; return; }       # skill sits directly under repo
  cat="${cat#skills/}"; [[ "$cat" == "skills" ]] && cat=""
  echo "$cat"
}

# Truncate $1 to width $2, adding an ellipsis when cut.
truncate() {
  local t="$1" w="$2"
  (( w <= 1 )) && return
  if (( ${#t} > w )); then printf '%s…' "${t:0:w-1}"; else printf '%s' "$t"; fi
}

# Render a markdown file with the best available tool.
render_md() {
  local f="$1"
  if command -v glow >/dev/null 2>&1; then
    glow -w "$cols" "$f"
  elif command -v bat >/dev/null 2>&1; then
    bat --style=plain --paging=never --language=markdown "$f"
  elif command -v mdcat >/dev/null 2>&1; then
    mdcat "$f"
  else
    cat "$f"
  fi
}

case "$cmd" in
  list)
    cur_repo=""; cur_cat='//unset//'
    namecol=26
    for f in "${skill_files[@]}"; do
      repo="$(repo_of "$f")"; cat="$(category_of "$f")"
      name="$(name_of "$f")"; desc="$(field "$f" description)"
      if [[ "$repo" != "$cur_repo" ]]; then
        printf '\n\033[1m%s\033[0m\n' "$repo"; cur_repo="$repo"; cur_cat='//unset//'
      fi
      if [[ "$cat" != "$cur_cat" ]]; then
        if [[ -n "$cat" ]]; then printf '  \033[33m%s/\033[0m\n' "$cat"; else printf '  \033[33m(uncategorized)\033[0m\n'; fi
        cur_cat="$cat"
      fi
      local_field=$(( ${#name} > namecol ? ${#name} : namecol ))
      printf '    \033[36m%s\033[0m%*s ' "$name" $(( local_field - ${#name} )) ''
      remain=$(( cols - 4 - local_field - 1 ))
      [[ -n "$desc" && $remain -gt 1 ]] && truncate "$desc" "$remain"
      printf '\n'
    done
    ;;
  search)
    [[ -n "$query" ]] || { echo "Usage: ./skills.sh search QUERY" >&2; exit 1; }
    hits=0
    for f in "${skill_files[@]}"; do
      grep -iq -- "$query" "$f" || continue
      hits=$((hits + 1))
      repo="$(repo_of "$f")"; cat="$(category_of "$f")"
      name="$(name_of "$f")"; desc="$(field "$f" description)"
      loc="$repo"; [[ -n "$cat" ]] && loc="$repo/$cat"
      printf '\033[36m%s\033[0m \033[2m(%s)\033[0m ' "$name" "$loc"
      remain=$(( cols - ${#name} - ${#loc} - 4 ))
      [[ -n "$desc" && $remain -gt 1 ]] && truncate "$desc" "$remain"
      printf '\n'
      grep -in -- "$query" "$f" | grep -viE '^[0-9]+:(name|description):' | sed 's/^/    /' || true
    done
    [[ $hits -gt 0 ]] || { echo "No skills match: $query"; exit 1; }
    ;;
  show)
    [[ -n "$query" ]] || { echo "Usage: ./skills.sh show <skill-name>" >&2; exit 1; }
    matches=()
    for f in "${skill_files[@]}"; do
      [[ "$(name_of "$f")" == "$query" || "$(basename "$(dirname "$f")")" == "$query" ]] && matches+=("$f")
    done
    if [[ ${#matches[@]} -eq 0 ]]; then
      echo "No skill named '$query'. Try: ./skills.sh list" >&2
      exit 1
    fi
    f="${matches[0]}"
    if [[ ${#matches[@]} -gt 1 ]]; then
      echo "Note: '$query' exists in multiple repos; showing $(repo_of "$f"). Others:" >&2
      for m in "${matches[@]:1}"; do echo "  - $(repo_of "$m")/$(category_of "$m")" >&2; done
    fi
    cat="$(category_of "$f")"; loc="$(repo_of "$f")"; [[ -n "$cat" ]] && loc="$loc/$cat"
    printf '\033[1m%s\033[0m  \033[2m(%s)\033[0m\n\033[2m%s\033[0m\n\n' "$(name_of "$f")" "$loc" "${f#"$repo_root"/}"
    render_md "$f"
    ;;
  *)
    echo "Unknown command: $cmd (use 'list', 'search QUERY', or 'show NAME')" >&2
    exit 1
    ;;
esac
