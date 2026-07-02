#!/usr/bin/env bash
set -euo pipefail

# List or search skills discovered across every sub-repo listed in .meta.
#
# Usage:
#   ./skills.sh list             # grouped by repo and category: name — description
#   ./skills.sh search QUERY      # search name/description/body of each SKILL.md
#   ./skills.sh show NAME         # pretty-print a skill's SKILL.md (NAME may be a substring)
#   ./skills.sh peek NAME         # print just a skill's frontmatter (NAME may be a substring)
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
    # Pass an explicit theme and width so bat does not query the terminal for
    # background colour / size (those query responses otherwise leak as stray
    # escape sequences into the output and onto the next shell prompt).
    bat --style=plain --paging=never --color=always --terminal-width="$cols" \
        --theme="${BAT_THEME:-ansi}" --language=markdown "$f"
  elif command -v mdcat >/dev/null 2>&1; then
    mdcat "$f"
  else
    cat "$f"
  fi
}

# Resolve a name-or-substring to a single SKILL.md path (echoed on stdout).
# Exact name/folder match wins; otherwise case-insensitive substring match.
# Errors and exits when there is no match or the match is ambiguous.
resolve_skill() {
  local query="$1" q
  q="$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]')"
  local exact=() fuzzy=()
  local f nm bn
  for f in "${skill_files[@]}"; do
    nm="$(name_of "$f")"; bn="$(basename "$(dirname "$f")")"
    if [[ "$nm" == "$query" || "$bn" == "$query" ]]; then
      exact+=("$f")
    elif [[ "$(printf '%s' "$nm" | tr '[:upper:]' '[:lower:]')" == *"$q"* \
         || "$(printf '%s' "$bn" | tr '[:upper:]' '[:lower:]')" == *"$q"* ]]; then
      fuzzy+=("$f")
    fi
  done
  local matches=()
  if [[ ${#exact[@]} -gt 0 ]]; then matches=("${exact[@]}")
  elif [[ ${#fuzzy[@]} -gt 0 ]]; then matches=("${fuzzy[@]}"); fi
  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "No skill matching '$query'. Try: ./skills.sh list" >&2
    exit 1
  fi
  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "'$query' matches several skills — be more specific:" >&2
    local m mcat mloc
    for m in "${matches[@]}"; do
      mcat="$(category_of "$m")"; mloc="$(repo_of "$m")"; [[ -n "$mcat" ]] && mloc="$mloc/$mcat"
      echo "  - $(name_of "$m")  ($mloc)" >&2
    done
    exit 1
  fi
  printf '%s' "${matches[0]}"
}

# Print the header line (name, location, relative path) for a resolved skill.
skill_header() {
  local f="$1" fcat floc
  fcat="$(category_of "$f")"; floc="$(repo_of "$f")"; [[ -n "$fcat" ]] && floc="$floc/$fcat"
  printf '\033[1m%s\033[0m  \033[2m(%s)\033[0m\n\033[2m%s\033[0m\n\n' \
    "$(name_of "$f")" "$floc" "${f#"$repo_root"/}"
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
    [[ -n "$query" ]] || { echo "Usage: ./skills.sh show <name-or-substring>" >&2; exit 1; }
    f="$(resolve_skill "$query")"
    skill_header "$f"
    render_md "$f"
    ;;
  peek)
    [[ -n "$query" ]] || { echo "Usage: ./skills.sh peek <name-or-substring>" >&2; exit 1; }
    f="$(resolve_skill "$query")"
    skill_header "$f"
    # Print only the YAML frontmatter (between the leading pair of --- fences).
    awk '
      NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
      /^---[[:space:]]*$/ { fence++; if (fence==1) next; if (fence==2) exit }
      fence==1 { print }
    ' "$f"
    ;;
  *)
    echo "Unknown command: $cmd (use 'list', 'search QUERY', 'show NAME', or 'peek NAME')" >&2
    exit 1
    ;;
esac
