#!/usr/bin/env bash
# The package catalog (packages/catalog.txt): parsing, the PACKAGES
# selection, the generated Brewfiles and --list-packages. Sourced; reads HERE.
#
# bash + awk only: the config (and with it PACKAGES) is loaded before the brew
# step, on a Mac that may not have the Command Line Tools - and so no working
# python3 - yet.

PACKAGE_SOURCES="formula cask mas script npm pipx uv go applet manual"
# overridable so tests can point it into a sandbox
APPLICATIONS_DIR="${APPLICATIONS_DIR:-/Applications}"

catalog_file() { echo "${PACKAGE_CATALOG:-$HERE/packages/catalog.txt}"; }

# catalog_rows -> the catalog as tab-separated rows (id, source, ref, check,
# category, description): comments and blank lines dropped, cells trimmed.
# Malformed catalog: "<file>:<line>: <problem>" on stderr per problem, return 2.
catalog_rows() {
  local file
  file="$(catalog_file)"
  if [ ! -r "$file" ]; then
    echo "bootstrap.sh: package catalog not found: $file" >&2
    return 2
  fi
  awk -F'|' -v file="$file" -v sources=" $PACKAGE_SOURCES " '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function problem(msg) { printf "%s:%d: %s\n", file, FNR, msg > "/dev/stderr"; bad = 1 }
    /^[ \t]*(#|$)/ { next }
    {
      if (NF < 6) { problem("expected 6 columns: id | source | ref | check | category | description"); next }
      description = $6
      for (i = 7; i <= NF; i++) description = description "|" $i
      id = trim($1); source = trim($2); ref = trim($3); check = trim($4)
      category = trim($5); description = trim(description)
      if (id == "" || source == "" || ref == "" || check == "" || category == "" || description == "") {
        problem("empty column"); next
      }
      if (id !~ /^[a-z0-9][a-z0-9@._-]*$/) { problem("invalid id: " id); next }
      if (category !~ /^[a-z][a-z0-9-]*$/) { problem("invalid category: " category); next }
      if (category == "all") { problem("category @all is reserved"); next }
      if (index(sources, " " source " ") == 0) { problem("unknown source: " source); next }
      if (source == "mas" && (ref !~ /^[0-9]+$/ || check == "-")) {
        problem("mas needs a numeric App Store id and the app name"); next
      }
      if (id in first) { problem("duplicate id: " id " (first on line " first[id] ")"); next }
      first[id] = FNR
      rows = rows id "\t" source "\t" ref "\t" check "\t" category "\t" description "\n"
    }
    END { if (bad) exit 2; printf "%s", rows }
  ' "$file"
}

# select_packages "<tokens>" -> the selected ids in catalog order,
# space-separated. Tokens (any whitespace between them): id, @category, @all;
# a leading "-" removes. Unknown token: message on stderr, return 2.
select_packages() {
  local rows
  rows="$(catalog_rows)" || return 2
  printf '%s\n' "$rows" | PACKAGE_TOKENS="$1" awk -F'\t' '
    NF { order[++count] = $1; category[$1] = $5; known["@" $5] = 1 }
    END {
      known["@all"] = 1
      tokens = split(ENVIRON["PACKAGE_TOKENS"], token, /[ \t\n]+/)
      for (t = 1; t <= tokens; t++) {
        name = token[t]
        if (name == "") continue
        removing = sub(/^-/, "", name)
        if (name ~ /^@/ && !(name in known)) {
          printf "unknown package category: %s (see ./bootstrap.sh --list-packages)\n", token[t] > "/dev/stderr"
          exit 2
        }
        if (name !~ /^@/ && !(name in category)) {
          printf "unknown package: %s (see ./bootstrap.sh --list-packages)\n", token[t] > "/dev/stderr"
          exit 2
        }
        for (i = 1; i <= count; i++) {
          id = order[i]
          if (name != "@all" && name != "@" category[id] && name != id) continue
          if (removing) removed[id] = 1; else added[id] = 1
        }
      }
      separator = ""
      for (i = 1; i <= count; i++) {
        id = order[i]
        if ((id in added) && !(id in removed)) { printf "%s%s", separator, id; separator = " " }
      }
      print ""
    }
  '
}

# package_state SOURCE CHECK -> "installed" or "missing"; empty when CHECK is
# "-" (the source checks itself). Apps by their folder in APPLICATIONS_DIR,
# everything else as a command on PATH.
package_state() {
  [ "$2" = - ] && { echo; return 0; }
  case "$1" in
    cask | mas | applet | manual) [ -d "$APPLICATIONS_DIR/$2.app" ] ;;
    *) command -v "$2" >/dev/null 2>&1 ;;
  esac && echo installed || echo missing
}

# write_brewfiles DIR "<ids>" -> DIR/Brewfile (formulae, casks and their
# taps) and DIR/Brewfile.mas (App Store entries plus mas itself), each only
# when it has entries. An app already in APPLICATIONS_DIR is left out: brew
# refuses to install over an app it didn't install, failing the whole bundle.
write_brewfiles() {
  local dir="$1" rows id source ref check _category _description tap
  local taps="" entries="" store=""
  rows="$(catalog_rows)" || return 2
  while IFS=$'\t' read -r id source ref check _category _description; do
    case " $2 " in *" $id "*) ;; *) continue ;; esac
    case "$source" in formula | cask | mas) ;; *) continue ;; esac
    if [ "$source" != formula ] && [ "$(package_state "$source" "$check")" = installed ]; then
      echo "  $id: $check.app already in $APPLICATIONS_DIR - left alone"
      continue
    fi
    case "$source" in
      formula) entries="${entries}brew \"$ref\""$'\n' ;;
      cask) entries="${entries}cask \"$ref\""$'\n' ;;
      mas) store="${store}mas \"$check\", id: $ref"$'\n' ;;
    esac
    case "$source:$ref" in
      mas:*) ;;
      */*/*)
        tap="${ref%/*}"
        case "$taps" in *"tap \"$tap\""*) ;; *) taps="${taps}tap \"$tap\""$'\n' ;; esac ;;
    esac
  done <<< "$rows"
  rm -f "$dir/Brewfile" "$dir/Brewfile.mas"
  [ -z "$entries" ] || printf '%s%s' "$taps" "$entries" > "$dir/Brewfile"
  [ -z "$store" ] || printf 'brew "mas"\n%s' "$store" > "$dir/Brewfile.mas"
}

# print_package_list "<selected ids>" -> the catalog under its @category
# headers: [x] when selected, installed / missing, the description
print_package_list() {
  local rows id source _ref check category description current="" mark
  rows="$(catalog_rows)" || return 2
  while IFS=$'\t' read -r id source _ref check category description; do
    [ -n "$id" ] || continue
    if [ "$category" != "$current" ]; then
      current="$category"
      printf '\n@%s\n' "$category"
    fi
    case " $1 " in *" $id "*) mark=x ;; *) mark=" " ;; esac
    printf '  [%s] %-24s %-9s %s\n' "$mark" "$id" "$(package_state "$source" "$check")" "$description"
  done <<< "$rows"
}
