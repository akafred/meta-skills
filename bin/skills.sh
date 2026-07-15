#!/usr/bin/env bash
set -euo pipefail

# List or search skills discovered across every sub-repo listed in .meta.
#
# Usage:
#   ./skills.sh list             # grouped by repo and category: name — description
#   ./skills.sh search QUERY      # ranked search; LIMIT=10 and SNIPPETS=2 by default
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
  done < <(find "$proj_dir" \( -name node_modules -o -name .git \) -prune -o -name SKILL.md -print | sort)
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

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
contains() { [[ "$1" == *"$2"* ]]; }
is_word() { [[ "$1" =~ ^[[:alnum:]]+$ ]]; }
contains_token() {
  local text term tokenized
  text="$1"; term="$2"
  tokenized="$(printf '%s' "$text" | tr -c '[:alnum:]' ' ' | tr -s ' ')"
  [[ " $tokenized " == *" $term "* ]]
}
field_matches_query() {
  local text="$1"
  if is_word "$query_lc"; then contains_token "$text" "$query_lc"; else contains "$text" "$query_lc"; fi
}
field_matches_term() {
  local text="$1" term="$2"
  if is_word "$term"; then contains_token "$text" "$term"; else contains "$text" "$term"; fi
}
grep_skill_term() {
  local term="$1" f="$2"
  if is_word "$term"; then grep -inwF -- "$term" "$f"; else grep -inF -- "$term" "$f"; fi
}
grep_skill_term_quiet() {
  local term="$1" f="$2"
  if is_word "$term"; then grep -iqwF -- "$term" "$f"; else grep -iqF -- "$term" "$f"; fi
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

append_match_field() {
  local field="$1"
  case ", $match_fields_text, " in
    *", $field, "*) ;;
    *) match_fields_text="${match_fields_text:+$match_fields_text, }$field" ;;
  esac
}

body_hit_count() {
  local f="$1" count=0 term c
  for term in "${terms[@]}"; do
    c="$(grep_skill_term "$term" "$f" 2>/dev/null \
      | grep -viE '^[0-9]+:[[:space:]]*(name|description):' \
      | wc -l | tr -d ' ' || true)"
    count=$(( count + c ))
  done
  printf '%s' "$count"
}

skill_matches_query() {
  local f="$1" term
  if ! is_word "$query_lc" && grep -iqF -- "$query" "$f"; then return 0; fi
  for term in "${terms[@]}"; do
    grep_skill_term_quiet "$term" "$f" || return 1
  done
  return 0
}

set_skill_search_score() {
  local f="$1" name="$2" desc="$3" loc="$4"
  local name_lc desc_lc loc_lc score=0 term body_hits
  name_lc="$(lc "$name")"; desc_lc="$(lc "$desc")"; loc_lc="$(lc "$loc")"
  match_fields_text=""

  if field_matches_query "$name_lc"; then score=$((score + 120)); append_match_field "name"; fi
  if field_matches_query "$desc_lc"; then score=$((score + 80)); append_match_field "description"; fi
  if field_matches_query "$loc_lc"; then score=$((score + 50)); append_match_field "location"; fi

  for term in "${terms[@]}"; do
    if field_matches_term "$name_lc" "$term"; then score=$((score + 30)); append_match_field "name"; fi
    if field_matches_term "$desc_lc" "$term"; then score=$((score + 20)); append_match_field "description"; fi
    if field_matches_term "$loc_lc" "$term"; then score=$((score + 10)); append_match_field "location"; fi
  done

  body_hits="$(body_hit_count "$f")"
  if (( body_hits > 0 )); then
    score=$((score + (body_hits > 8 ? 8 : body_hits) * 2))
    append_match_field "body"
  fi

  search_score="$score"
}

print_search_snippets() {
  local f="$1" max="$2" printed=0 seen='' pattern line line_no text width
  (( max <= 0 )) && return
  width=$(( cols - 10 ))
  (( width < 20 )) && width=20

  local patterns=("$query" "${terms[@]}")
  for pattern in "${patterns[@]}"; do
    [[ -n "$pattern" ]] || continue
    while IFS= read -r line; do
      line_no="${line%%:*}"
      text="${line#*:}"
      case " $seen " in *" $line_no "*) continue ;; esac
      seen="$seen $line_no"
      text="$(printf '%s' "$text" | sed 's/^[[:space:]]*//')"
      printf '    \033[2m%s:\033[0m ' "$line_no"
      truncate "$text" "$width"
      printf '\n'
      printed=$((printed + 1))
      (( printed >= max )) && return
    done < <(grep_skill_term "$pattern" "$f" 2>/dev/null \
      | grep -viE '^[0-9]+:[[:space:]]*(name|description):' || true)
  done
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
    query_lc="$(lc "$query")"
    terms=()
    read -r -a terms <<< "$query_lc"
    [[ ${#terms[@]} -gt 0 ]] || terms=("$query_lc")

    limit="${LIMIT:-${SEARCH_LIMIT:-10}}"
    snippets="${SNIPPETS:-${SEARCH_SNIPPETS:-2}}"
    if [[ "$limit" == "all" ]]; then
      limit=0
    elif ! [[ "$limit" =~ ^[0-9]+$ ]] || (( limit < 1 )); then
      echo "LIMIT must be a positive number or 'all'." >&2
      exit 1
    fi
    if ! [[ "$snippets" =~ ^[0-9]+$ ]]; then
      echo "SNIPPETS must be a number." >&2
      exit 1
    fi

    records=()
    for f in "${skill_files[@]}"; do
      skill_matches_query "$f" || continue
      repo="$(repo_of "$f")"; cat="$(category_of "$f")"
      name="$(name_of "$f")"; desc="$(field "$f" description)"
      loc="$repo"; [[ -n "$cat" ]] && loc="$repo/$cat"
      set_skill_search_score "$f" "$name" "$desc" "$loc"
      score="$search_score"
      records+=("$(printf '%05d\t%s' "$score" "$f")")
    done
    hits="${#records[@]}"
    [[ $hits -gt 0 ]] || { echo "No skills match: $query"; exit 1; }

    shown="$hits"
    (( limit > 0 && hits > limit )) && shown="$limit"
    printf 'Found %s skills for "%s"; showing %s' "$hits" "$query" "$shown"
    if (( limit > 0 && hits > limit )); then
      printf ' (use LIMIT=%s or LIMIT=all for more)' "$((limit * 2))"
    fi
    printf '.\nOpen one with: make show SKILL=<name>\n\n'

    i=0
    while IFS=$'\t' read -r score f; do
      i=$((i + 1))
      (( limit > 0 && i > limit )) && break
      repo="$(repo_of "$f")"; cat="$(category_of "$f")"
      name="$(name_of "$f")"; desc="$(field "$f" description)"
      loc="$repo"; [[ -n "$cat" ]] && loc="$repo/$cat"
      set_skill_search_score "$f" "$name" "$desc" "$loc"
      score="$search_score"

      printf '\033[2m%2d.\033[0m \033[36m%s\033[0m \033[2m(%s)\033[0m\n' "$i" "$name" "$loc"
      if [[ -n "$desc" ]]; then
        printf '    '
        truncate "$desc" "$((cols - 4))"
        printf '\n'
      fi
      printf '    \033[2mmatched: %s\033[0m\n' "$match_fields_text"
      print_search_snippets "$f" "$snippets"
      printf '\n'
    done < <(printf '%s\n' "${records[@]}" | sort -t $'\t' -k1,1nr -k2,2)
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
