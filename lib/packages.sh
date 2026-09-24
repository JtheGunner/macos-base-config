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

# casks that are built for Intel and need Rosetta 2 to start
ROSETTA_CASKS="steam"

# tap_urls -> "<user>/<tap>\t<url>" per line of taps.txt next to the catalog:
# the taps whose repo is not github.com/<user>/homebrew-<tap>. No file, no
# lines. Malformed line: "<file>:<line>: <problem>" on stderr, return 2.
tap_urls() {
  local file
  file="$(dirname "$(catalog_file)")/taps.txt"
  [ -r "$file" ] || return 0
  awk -F'|' -v file="$file" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*(#|$)/ { next }
    {
      tap = trim($1); url = trim($2)
      if (NF != 2 || tap !~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/ || url !~ /^https:\/\/[^ \t]+$/) {
        printf "%s:%d: expected: <user>/<tap> | https://<url>\n", file, FNR > "/dev/stderr"; bad = 1; next
      }
      rows = rows tap "\t" url "\n"
    }
    END { if (bad) exit 2; printf "%s", rows }
  ' "$file"
}

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
      # rows are emitted tab-separated: an inner tab would shift the columns
      if (index(id source ref check category description, "\t")) { problem("tab inside a column"); next }
      if (id == "" || source == "" || ref == "" || check == "" || category == "" || description == "") {
        problem("empty column"); next
      }
      if (id !~ /^[a-z0-9][a-z0-9@._-]*$/) { problem("invalid id: " id); next }
      if (category !~ /^[a-z][a-z0-9-]*$/) { problem("invalid category: " category); next }
      if (category == "all") { problem("category @all is reserved"); next }
      if (index(sources, " " source " ") == 0) { problem("unknown source: " source); next }
      if (source == "script" && ref !~ /^https:\/\//) { problem("script needs an https:// URL"); next }
      if (check ~ /^bin:/ && source != "cask") { problem("bin:<command> is for casks only"); next }
      if (source ~ /^(script|npm|pipx|uv|go)$/ && check == "-") { problem(source " needs a command to check, not -"); next }
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

# user_bin_dirs_on_path -> append the dirs pipx, uv tool, go install and vendor
# install scripts write to (~/.local/bin, $GOBIN or ~/go/bin) to PATH for this
# run. On a fresh Mac they are not on PATH yet (the dotfiles step comes later):
# a package there would look missing and be installed again on every run.
user_bin_dirs_on_path() {
  local dir
  for dir in "$HOME/.local/bin" "${GOBIN:-$HOME/go/bin}"; do
    case ":$PATH:" in *":$dir:"*) ;; *) PATH="$PATH:$dir" ;; esac
  done
  export PATH
}

# package_state SOURCE CHECK -> "installed" or "missing"; empty when CHECK is
# "-" (the source checks itself). Apps by their folder in APPLICATIONS_DIR,
# everything else - and a cask's "bin:<command>" - as a command on PATH.
package_state() {
  [ "$2" = - ] && { echo; return 0; }
  case "$2" in
    bin:*) command -v "${2#bin:}" >/dev/null 2>&1 && echo installed || echo missing
           return 0 ;;
  esac
  case "$1" in
    cask | mas | applet | manual) [ -d "$APPLICATIONS_DIR/$2.app" ] ;;
    *) command -v "$2" >/dev/null 2>&1 ;;
  esac && echo installed || echo missing
}

# write_brewfiles DIR "<ids>" -> DIR/Brewfile (formulae, casks and their
# taps) and DIR/Brewfile.mas (App Store entries plus mas itself), each only
# when it has entries. An app already in APPLICATIONS_DIR is left out: brew
# refuses to install over an app it didn't install, failing the whole bundle.
# So is a formula or cask whose check command is already on PATH, however it
# was installed (no second copy). A selected pipx / uv / go package whose command is missing pulls in its
# tool (brew "pipx", "uv", "go") unless that formula is listed already.
write_brewfiles() {
  local dir="$1" rows id source ref check _category _description tap url urls
  local taps="" entries="" store="" needs="" tool
  rows="$(catalog_rows)" || return 2
  urls="$(tap_urls)" || return 2
  while IFS=$'\t' read -r id source ref check _category _description; do
    case " $2 " in *" $id "*) ;; *) continue ;; esac
    case "$source" in
      formula | cask | mas) ;;
      pipx | uv | go)
        if [ "$(package_state "$source" "$check")" != installed ]; then
          case " $needs " in *" $source "*) ;; *) needs="$needs $source" ;; esac
        fi
        continue ;;
      *) continue ;;
    esac
    if [ "$(package_state "$source" "$check")" = installed ]; then
      case "$source:$check" in
        *:bin:*) echo "  $id: ${check#bin:} already installed - left alone" ;;
        formula:*) echo "  $id: $check already installed - left alone" ;;
        *) echo "  $id: $check.app already in $APPLICATIONS_DIR - left alone" ;;
      esac
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
        case "$taps" in *"tap \"$tap\""*) continue ;; esac
        url="$(printf '%s\n' "$urls" | awk -F'\t' -v tap="$tap" '$1 == tap { print $2 }')"
        taps="${taps}tap \"$tap\"${url:+, \"$url\"}"$'\n' ;;
    esac
  done <<< "$rows"
  for tool in $needs; do
    case "$entries" in *"brew \"$tool\""*) ;; *) entries="${entries}brew \"$tool\""$'\n' ;; esac
  done
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

# manual_package_hints "<selected ids>" -> "Install <app> by hand
# (<description>)<TAB><url>" per selected "manual" package that is missing
manual_package_hints() {
  local rows id source ref check _category description
  rows="$(catalog_rows)" || return 2
  while IFS=$'\t' read -r id source ref check _category description; do
    [ "$source" = manual ] || continue
    case " $1 " in *" $id "*) ;; *) continue ;; esac
    [ "$(package_state manual "$check")" = installed ] && continue
    printf 'Install %s by hand (%s)\t%s\n' "$check" "$description" "$ref"
  done <<< "$rows"
}

# applet_source TEMPLATE -> TEMPLATE with @@NAS_MOUNT_SHARES@@ replaced by the
# shares as AppleScript list items ("smb://a", "afp://b"). The config check
# keeps quotes and backslashes out of them. 1 when TEMPLATE can't be read
# or has no placeholder.
applet_source() {
  local template list
  template="$(cat "$1" 2>/dev/null)" || return 1
  list="$(printf '%s\n' "$NAS_MOUNT_SHARES" |
    awk '{ for (i = 1; i <= NF; i++) printf "%s\"%s\"", (n++ ? ", " : ""), $i }')"
  case "$template" in *@@NAS_MOUNT_SHARES@@*) ;; *) return 1 ;; esac
  # prefix + list + suffix, not ${template//...}: bash 5.2+ would expand an &
  # in the replacement (patsub_replacement)
  printf '%s%s%s\n' "${template%%@@NAS_MOUNT_SHARES@@*}" "$list" "${template#*@@NAS_MOUNT_SHARES@@}"
}
