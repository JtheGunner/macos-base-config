# Package catalog + PACKAGES selection (MBC-9) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed `Brewfile` with a package catalog and a `PACKAGES`
selection in the config. The `brew` step then installs only what is selected,
and nothing is mandatory.

**Architecture:**
- **Catalog and code.** `packages/catalog.txt` is the catalog; `lib/packages.sh`
  (bash + awk) parses it, resolves the selection, writes the Brewfiles and
  prints `--list-packages`.
- **Config.** `lib/config.sh` resolves `PACKAGES` into `SELECTED_PACKAGES`
  while loading the config (bad token → exit 2).
- **brew step.** `step_brew` writes the Brewfiles into a temp dir and runs
  `brew bundle` on them.

**Tech Stack:** bash 3.2, BWK awk (macOS), Homebrew `brew bundle`; tests in
`tests/bootstrap-test.sh` (plain bash, stub tools).

**Spec:** `docs/superpowers/specs/2026-09-23-package-catalog-design.md`
(this plan covers ticket 1 of its Rollout: MBC-9).

**Deviation from the spec, and why:** the spec names `packages/packages.py`.
The catalog is read while the **config loads**, which happens before the
`brew` step. On a fresh Mac without the Command Line Tools, `/usr/bin/python3`
only opens the CLT install dialog. So the catalog code is bash + awk in
`lib/packages.sh`, and Task 1 amends the spec to say so.

## Global Constraints

- Runs under macOS `/bin/bash` 3.2: no associative arrays, no `mapfile`, no
  `${var,,}`.
- Only macOS base tools before the `brew` step: `awk`, `sed`, `mktemp`; no
  python3.
- The catalog line format is
  `id | source | ref | check | category | description`, where `description`
  is the rest of the line.
- Allowed sources: `formula cask mas script npm pipx uv go applet manual`.
  MBC-9 installs only `formula`, `cask` and `mas`; the other sources are
  accepted by the parser but ignored by the `brew` step.
- `PACKAGES` without the key (or without a config file) means `@base`.
  `PACKAGES=""` means nothing.
- Tokens: `id`, `@category`, `@all`; a leading `-` removes.
- An unknown token is a config error, exit 2.
- The existing-app guard: a `cask`/`mas` entry whose
  `$APPLICATIONS_DIR/<check>.app` exists is left out of the Brewfile.
- `brew bundle --no-upgrade` stays. `BREW_BUNDLE_EXTRA` stays and runs last.
- Failure reasons: `brew bundle` for the main Brewfile or the extra one;
  `App Store: sign in, then re-run` for the App Store one.
- English in code, comments, docs and commits. Commit subjects follow
  `feat:`/`docs:`/`test:`, with no trailers.

## Review Focus

- **Catalog edited by hand with tabs or trailing spaces.** Cells are trimmed,
  and a tab inside a cell must not shift columns. Owned by Task 1, test
  "comments, blank lines and spacing are ignored".
- **`PACKAGES` spanning several lines in the config** (like `BOOTSTRAP_STEPS`
  can). Tokens are split on any whitespace, newlines included. Owned by
  Task 1, test "tokens may span lines".
- **An app name with spaces** (`Google Chrome`, `Visual Studio Code`). The
  existing-app check must quote the path. Owned by Task 3, test "apps
  already installed are left out".
- **A `PACKAGES` value in the user's shell environment** leaking into the
  run. `load_config` must reset `PACKAGES` to `@base` before sourcing. Owned
  by Task 2, test "a later load resets PACKAGES".
- **Running `--list-packages` with a broken config.** Exit 2 with the config
  message, not a half-printed list. Owned by Task 4, test "--list-packages
  with an invalid PACKAGES is exit 2".

---

### Task 1: Catalog parser and selection (`lib/packages.sh`, `packages/catalog.txt`)

**Files:**
- Create: `packages/catalog.txt`
- Create: `lib/packages.sh`
- Modify: `tests/bootstrap-test.sh`. Source `lib/packages.sh` before
  `lib/config.sh` and set `HERE="$REPO"`. Add a new section
  `# --- lib/packages.sh` right after the `expand_home` test (the one that
  ends with `assert_eq "$(HOME=/h expand_home "~")" "/h"`), where `$TMP`
  exists.
- Modify: `docs/superpowers/specs/2026-09-23-package-catalog-design.md`
  (Layout: `packages/packages.py` → `lib/packages.sh`, plus one sentence on
  why).

**Interfaces:**
- Produces:
  - `catalog_file`: prints the catalog path, `${PACKAGE_CATALOG:-$HERE/packages/catalog.txt}`.
  - `catalog_rows`: prints tab-separated rows `id source ref check category description`.
    A malformed catalog prints `<file>:<line>: <problem>` on stderr and
    returns 2.
  - `select_packages "<tokens>"`: prints the selected ids in catalog order,
    space-separated (empty when none). An unknown token prints a message on
    stderr and returns 2.
  - `PACKAGE_SOURCES`: the allowed sources, space-separated.
  - `APPLICATIONS_DIR`: the apps folder, overridable; default `/Applications`.

- [ ] **Step 1: Write the failing tests**

In `tests/bootstrap-test.sh`, directly above `# --- lib/config.sh ---`, add:

```bash
# --- lib/packages.sh (sourced before lib/config.sh, which uses it) ----------
HERE="$REPO"
. "$REPO/lib/packages.sh"
```

After the `expand_home` test, add:

```bash
# --- lib/packages.sh --------------------------------------------------------
# write_catalog LINE... -> $TMP/catalog.txt, prints its path
write_catalog() { printf '%s\n' "$@" > "$TMP/catalog.txt"; echo "$TMP/catalog.txt"; }

TEST_CATALOG_LINES=(
  '# id | source | ref | check | category | description'
  'gh        | formula | gh              | -        | cli    | GitHub CLI'
  'tool      | formula | user/tap/tool   | -        | cli    | a tapped formula'
  'firefox   | cask    | firefox         | Firefox  | web    | Web browser'
  'app       | cask    | user/tap/app    | Some App | web    | a tapped cask'
  'whatsapp  | mas     | 310633997       | WhatsApp | chat   | Messenger (App Store)'
  'claude    | script  | https://x/i.sh  | claude   | chat   | not a brew package'
)

it "the shipped catalog parses and @base is today's Brewfile"
catalog_rows >/dev/null; rc=$?
assert_eq "$rc" 0
assert_eq "$(select_packages "@base")" "karabiner-elements alt-tab sidebar font-jetbrains-mono"

it "catalog rows are trimmed and tab-separated; a | in the description is kept"
f="$(write_catalog '' '# comment' "  gh |formula|	gh |  -  | cli | GitHub CLI | the official one  ")"
assert_eq "$(PACKAGE_CATALOG="$f" catalog_rows)" "$(printf 'gh\tformula\tgh\t-\tcli\tGitHub CLI | the official one')"

it "catalog problems are reported with their line number"
f="$(write_catalog \
  'ok    | formula | ok  | -   | cli | fine' \
  'short | formula | x   | -   | cli' \
  'bad   | rpm     | x   | -   | cli | unknown source' \
  'ok    | formula | ok  | -   | cli | again' \
  'empty | formula |     | -   | cli | no ref' \
  'm     | mas     | abc | App | cli | not a number' \
  'Upper | formula | x   | -   | cli | bad id' \
  'x2    | formula | x   | -   | all | reserved category')"
out="$(PACKAGE_CATALOG="$f" catalog_rows 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "$f:2: expected 6 columns"
assert_contains "$out" "$f:3: unknown source: rpm"
assert_contains "$out" "$f:4: duplicate id: ok (first on line 1)"
assert_contains "$out" "$f:5: empty column"
assert_contains "$out" "$f:6: mas needs a numeric App Store id and the app name"
assert_contains "$out" "$f:7: invalid id: Upper"
assert_contains "$out" "$f:8: category @all is reserved"

it "a missing catalog is exit 2"
out="$(PACKAGE_CATALOG="$TMP/nope.txt" catalog_rows 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "package catalog not found: $TMP/nope.txt"

it "selection: ids, categories, @all, removals, catalog order"
f="$(write_catalog "${TEST_CATALOG_LINES[@]}")"
assert_eq "$(PACKAGE_CATALOG="$f" select_packages "firefox gh")" "gh firefox"
assert_eq "$(PACKAGE_CATALOG="$f" select_packages "@cli whatsapp")" "gh tool whatsapp"
assert_eq "$(PACKAGE_CATALOG="$f" select_packages "@all -@web -claude")" "gh tool whatsapp"
assert_eq "$(PACKAGE_CATALOG="$f" select_packages "-gh @cli")" "tool"
assert_eq "$(PACKAGE_CATALOG="$f" select_packages "gh gh @cli")" "gh tool"
assert_eq "$(PACKAGE_CATALOG="$f" select_packages "")" ""

it "tokens may span lines"
assert_eq "$(PACKAGE_CATALOG="$f" select_packages "$(printf 'gh\n  firefox\t')")" "gh firefox"

it "unknown tokens are exit 2 with a message; globs are not expanded"
out="$(PACKAGE_CATALOG="$f" select_packages "gh bogus" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "unknown package: bogus (see ./bootstrap.sh --list-packages)"
out="$(PACKAGE_CATALOG="$f" select_packages "@nope" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "unknown package category: @nope"
out="$(PACKAGE_CATALOG="$f" select_packages "-" 2>&1)"; rc=$?
assert_eq "$rc" 2
out="$(cd "$REPO" && PACKAGE_CATALOG="$f" select_packages "*" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "unknown package: *"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: it aborts, because `lib/packages.sh` does not exist
(`No such file or directory`).

- [ ] **Step 3: Create `packages/catalog.txt`**

```text
# Package catalog - what ./bootstrap.sh can install. Pick with PACKAGES in the
# config (config.example.sh); ./bootstrap.sh --list-packages shows it all.
#
#   id | source | ref | check | category | description
#
# id           unique, lowercase; what PACKAGES names
# source       formula, cask, mas (App Store), script, npm, pipx, uv, go,
#              applet, manual
# ref          formula / cask name (user/tap/name adds the tap), App Store id,
#              installer URL, package or module name
# check        app name for cask / mas / applet / manual (/Applications/<check>.app),
#              command name for the others; - = the source checks itself
# category     one word; PACKAGES can pick @category. Keep entries grouped.
# description  the rest of the line

karabiner-elements  | cask | karabiner-elements     | Karabiner-Elements | base | Windows key behaviour (karabiner step)
alt-tab             | cask | alt-tab                | AltTab             | base | Windows-style Alt+Tab window switching
sidebar             | cask | otuerk/sidebar/sidebar | Sidebar            | base | Windows-style taskbar, Dock replacement
font-jetbrains-mono | cask | font-jetbrains-mono    | -                  | base | JetBrains Mono, the editor font (editor step)
```

- [ ] **Step 4: Create `lib/packages.sh`**

```bash
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
```

Notes:
- A lone `-` becomes the empty name. It fails the `name in category` check,
  so it reports `unknown package: -`.
- In awk, `exit 2` inside `END` stops before the output loop.

- [ ] **Step 5: Amend the spec**

In `docs/superpowers/specs/2026-09-23-package-catalog-design.md`, in the
`## Layout` block:
- replace the `packages/packages.py …` lines with
  `lib/packages.sh            catalog parser, selection, Brewfile generation, --list-packages`;
- replace the sentence starting "Python 3 (macOS system Python 3.9 …" with:

```markdown
The catalog code is bash + awk (`lib/packages.sh`): `PACKAGES` is resolved
while the config loads, before the `brew` step, and on a Mac without the
Command Line Tools `/usr/bin/python3` only opens their install dialog.
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 7: Commit**

```bash
git add packages/catalog.txt lib/packages.sh tests/bootstrap-test.sh docs/superpowers/specs/2026-09-23-package-catalog-design.md
git commit -m "feat: add the package catalog and PACKAGES token selection"
```

---

### Task 2: `PACKAGES` in the config

**Files:**
- Modify: `lib/config.sh`. Update the header comment ("needs lib/cli.sh and
  lib/packages.sh loaded first"), `load_config` and `validate_config`.
- Modify: `bootstrap.sh` (source `lib/packages.sh` between `cli.sh` and
  `config.sh`).
- Modify: `config.example.sh` (new section before `# --- brew step`).
- Modify: `tests/bootstrap-test.sh` (config section and the
  `config.example.sh` test).

**Interfaces:**
- Consumes: `select_packages` (Task 1).
- Produces:
  - `PACKAGES`: the raw value; defaults to `@base`.
  - `SELECTED_PACKAGES`: the resolved ids, space-separated. It is set by
    every successful `load_config`, including when no config file exists.

- [ ] **Step 1: Write the failing tests** (config section, after the
  `MACOS_DISABLE_GATEKEEPER` test)

```bash
it "PACKAGES defaults to @base, with no config file or without the key"
XDG_CONFIG_HOME="$TMP/none" load_config ""; rc=$?
assert_eq "$rc" 0
assert_eq "$PACKAGES" "@base"
assert_eq "$SELECTED_PACKAGES" "karabiner-elements alt-tab sidebar font-jetbrains-mono"
f="$(write_config 'BOOTSTRAP_STEPS="brew"')"
load_config "$f"
assert_eq "$SELECTED_PACKAGES" "karabiner-elements alt-tab sidebar font-jetbrains-mono"

it "PACKAGES=\"\" selects nothing; tokens resolve in catalog order"
f="$(write_config 'PACKAGES=""')"
load_config "$f"; rc=$?
assert_eq "$rc" 0
assert_eq "$SELECTED_PACKAGES" ""
f="$(write_config 'PACKAGES="font-jetbrains-mono
  alt-tab"')"
load_config "$f"
assert_eq "$SELECTED_PACKAGES" "alt-tab font-jetbrains-mono"
f="$(write_config 'PACKAGES="@base -sidebar"')"
load_config "$f"
assert_eq "$SELECTED_PACKAGES" "karabiner-elements alt-tab font-jetbrains-mono"

it "a later load resets PACKAGES, also one from the environment"
f="$(write_config 'PACKAGES=""')"
load_config "$f"
# a plain assignment, not a prefix: bash restores prefix variables after a function
PACKAGES="alt-tab"
XDG_CONFIG_HOME="$TMP/none" load_config ""
assert_eq "$PACKAGES" "@base"
assert_eq "$SELECTED_PACKAGES" "karabiner-elements alt-tab sidebar font-jetbrains-mono"

it "an unknown package in the config is exit 2"
f="$(write_config 'PACKAGES="@base bogus"')"
out="$(load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "unknown package: bogus"
assert_contains "$out" "in $f (PACKAGES)"
```

In `it "config.example.sh is a valid config with the defaults"` add
`assert_eq "$PACKAGES" "@base"`, and add `PACKAGES` to the `for key in …`
list.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: PACKAGES defaults to @base, … expected [@base], got []`.

- [ ] **Step 3: Implement**

`bootstrap.sh`: source the new file between the other two:

```bash
. "$HERE/lib/cli.sh"
. "$HERE/lib/packages.sh"
. "$HERE/lib/config.sh"
. "$HERE/lib/steps.sh"
```

`lib/config.sh` header, second sentence: `Sourced; needs lib/cli.sh
(select_steps) and lib/packages.sh (select_packages) loaded first.`

In `load_config`:
- Extend the doc comment: `sets … BREW_BUNDLE_EXTRA, PACKAGES (+ the
  resolved SELECTED_PACKAGES), MACOS_DISABLE_GATEKEEPER, …`.
- Add `PACKAGES="@base"; SELECTED_PACKAGES=""` to the defaults line.
- Replace the early return `[ -f "$config_file" ] || return 0` and what
  follows it, so the defaults are validated too and `SELECTED_PACKAGES` is
  always set:

```bash
  CONFIG_FILE="$config_file"
  if [ -f "$config_file" ]; then
    # bash 3.2's -n can exit 0 on a syntax error, so any message counts as one
    local syntax_errors
    if ! syntax_errors="$("$BASH" -n "$config_file" 2>&1)" || [ -n "$syntax_errors" ]; then
      echo "$syntax_errors" >&2
      echo "bootstrap.sh: syntax error in config: $config_file" >&2
      return 2
    fi
    # shellcheck source=/dev/null
    . "$config_file"
  fi
  validate_config "$config_file"
```

In `validate_config`, after the `select_steps` check:

```bash
  if ! SELECTED_PACKAGES="$(select_packages "$PACKAGES")"; then
    echo "  in $config_file (PACKAGES)" >&2
    return 2
  fi
```

`config.example.sh`, before `# --- brew step`:

```bash
# --- packages (brew step) -----------------------------------------------------

# What to install from the catalog, packages/catalog.txt (see
# ./bootstrap.sh --list-packages): package ids, @category or @all; a leading
# "-" removes one, e.g. "@all -steam -@cli-ai". Nothing is required: ""
# installs nothing. Without this key: "@base" = Karabiner-Elements, AltTab,
# Sidebar, JetBrains Mono.
PACKAGES="@base"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 5: Commit**

```bash
git add lib/config.sh bootstrap.sh config.example.sh tests/bootstrap-test.sh
git commit -m "feat: resolve PACKAGES from the config, @base when unset"
```

---

### Task 3: Generated Brewfiles in the `brew` step

**Files:**
- Modify: `lib/packages.sh` (add `package_state`, `write_brewfiles`).
- Modify: `lib/steps.sh`:
  - `step_brew` and a new `bundle_brewfile`;
  - in `step_karabiner`, the skip message changes;
  - drop `APPLICATIONS_DIR` from the list of things steps define (it lives in
    `lib/packages.sh`).
- Modify: `lib/cli.sh` (`step_description brew`).
- Delete: `Brewfile`.
- Modify: `tests/bootstrap-test.sh`:
  - unit tests;
  - `make_sandbox` copies `packages/` instead of `Brewfile`;
  - `run_bootstrap` gets `APPLICATIONS_DIR`, `TMPDIR`, `PACKAGE_CATALOG`
    and `-u PACKAGES`;
  - a new `brew_stub`, and the brew tests rewritten;
  - the karabiner skip test.

**Interfaces:**
- Consumes: `catalog_rows`, `APPLICATIONS_DIR` (Task 1), `SELECTED_PACKAGES`
  (Task 2).
- Produces:
  - `package_state SOURCE CHECK`: prints `installed`, `missing`, or an empty
    line when `CHECK` is `-`. Used by Task 4.
  - `write_brewfiles DIR "<ids>"`: writes `DIR/Brewfile` and
    `DIR/Brewfile.mas`, each only when it has entries. It prints one
    "left alone" line per skipped app.

- [ ] **Step 1: Write the failing unit tests** (in the `lib/packages.sh`
  section, after the selection tests)

```bash
it "package_state: apps by folder, commands on PATH, - means no check"
mkdir -p "$TMP/apps/Some App.app"
assert_eq "$(APPLICATIONS_DIR="$TMP/apps" package_state cask "Some App")" installed
assert_eq "$(APPLICATIONS_DIR="$TMP/apps" package_state mas WhatsApp)" missing
assert_eq "$(package_state pipx sh)" installed
assert_eq "$(package_state npm no-such-command-xyz)" missing
assert_eq "$(package_state formula -)" ""

it "write_brewfiles: taps first, catalog order; App Store entries apart, with mas"
f="$(write_catalog "${TEST_CATALOG_LINES[@]}")"
d="$(mktemp -d "$TMP/bf.XXXXXX")"
APPLICATIONS_DIR="$TMP/none" PACKAGE_CATALOG="$f" write_brewfiles "$d" "gh tool firefox app whatsapp claude" >/dev/null
assert_eq "$(cat "$d/Brewfile")" 'tap "user/tap"
brew "gh"
brew "user/tap/tool"
cask "firefox"
cask "user/tap/app"'
assert_eq "$(cat "$d/Brewfile.mas")" 'brew "mas"
mas "WhatsApp", id: 310633997'

it "apps already installed are left out; an empty Brewfile is not written"
mkdir -p "$TMP/apps2/Some App.app" "$TMP/apps2/WhatsApp.app"
d="$(mktemp -d "$TMP/bf.XXXXXX")"
out="$(APPLICATIONS_DIR="$TMP/apps2" PACKAGE_CATALOG="$f" write_brewfiles "$d" "app whatsapp")"
assert_contains "$out" "app: Some App.app already in $TMP/apps2 - left alone"
assert_contains "$out" "whatsapp: WhatsApp.app already in $TMP/apps2 - left alone"
[ -e "$d/Brewfile" ] && fail "wrote an empty Brewfile"
[ -e "$d/Brewfile.mas" ] && fail "wrote an empty Brewfile.mas"

it "write_brewfiles writes nothing for an empty selection, removes stale files"
echo old > "$d/Brewfile"
PACKAGE_CATALOG="$f" write_brewfiles "$d" "" >/dev/null
[ -e "$d/Brewfile" ] && fail "stale Brewfile kept"
true
```

- [ ] **Step 2: Rewrite the sandbox helpers and brew e2e tests**

In `make_sandbox`:
- Replace `"$REPO/Brewfile"` in the `cp -R` line with `"$REPO/packages"`.
- Add `"$SB/Applications" "$SB/tmp"` to its `mkdir -p` line.

`run_bootstrap` becomes:

```bash
run_bootstrap() {
  OUT="$(env -u XDG_CONFIG_HOME -u DOTFILES_TERMINALS -u PACKAGES HOME="$SB/home" \
    PATH="$SB/bin:/usr/bin:/bin" KARABINER_APP="$SB/Karabiner-Elements.app" \
    BREW_CANDIDATES="$SB/homebrew/bin/brew" KARABINER_WAIT_SECONDS=0 \
    KEYBOARD_SYSTEM_DIR="$SB/system-layouts" SWIFT="${SWIFT_BIN:-$SB/bin/swift}" \
    APPLICATIONS_DIR="$SB/Applications" TMPDIR="$SB/tmp" PACKAGE_CATALOG="${SB_CATALOG:-}" \
    /bin/bash "$APP/bootstrap.sh" "$@" 2>&1 </dev/null)"
  RC=$?
}
```

Add, below `installer_stub` in the brew section:

```bash
# brew_stub [EXIT] [FAIL_ON] -> brew that logs its arguments and, for
# --file=X, X's lines as "  | <line>"; exits EXIT, or 1 only when an argument
# contains FAIL_ON
brew_stub() {
  cat > "$SB/bin/brew" <<EOF
#!/bin/bash
echo "brew \$*" >> "$LOG"
for arg in "\$@"; do
  case "\$arg" in --file=*) sed 's/^/  | /' "\${arg#--file=}" >> "$LOG" ;; esac
done
case "${2:-}" in ?*) case "\$*" in *"${2:-}"*) exit 1 ;; esac ;; esac
exit ${1:-0}
EOF
  chmod +x "$SB/bin/brew"
}

# brew_log -> $LOG with the random temp dir replaced by <tmp>
brew_log() { sed "s|$SB/tmp/macos-base-config\.[A-Za-z0-9]*|<tmp>|g" "$LOG"; }

BASE_BREWFILE='  | tap "otuerk/sidebar"
  | cask "karabiner-elements"
  | cask "alt-tab"
  | cask "otuerk/sidebar/sidebar"
  | cask "font-jetbrains-mono"'
```

Replace the brew tests from `it "brew with Homebrew on PATH only runs brew bundle"`
through `it "dry run announces the Homebrew install and the bundle, runs nothing"`
with:

```bash
it "brew bundles the generated Brewfile: @base without a config"
make_sandbox
brew_stub
run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_eq "$(brew_log)" "brew bundle --file=<tmp>/Brewfile --no-upgrade
$BASE_BREWFILE"
assert_contains "$OUT" '    cask "alt-tab"'
assert_contains "$OUT" "  brew       ok"
[ -z "$(ls -A "$SB/tmp")" ] || fail "temp Brewfile dir left behind"

it "brew installs only the selected packages; PACKAGES=\"\" installs nothing"
make_sandbox
brew_stub
sandbox_config 'PACKAGES="font-jetbrains-mono"'
run_bootstrap --no-pull brew
assert_eq "$(brew_log)" "brew bundle --file=<tmp>/Brewfile --no-upgrade
  | cask \"font-jetbrains-mono\""
: > "$LOG"
sandbox_config 'PACKAGES=""'
run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" ""
assert_contains "$OUT" "no brew packages to install"

it "the Brewfile leaves apps already in /Applications alone"
make_sandbox
brew_stub
mkdir -p "$SB/Applications/AltTab.app"
run_bootstrap --no-pull brew
assert_not_contains "$(cat "$LOG")" "alt-tab"
assert_contains "$(cat "$LOG")" 'cask "karabiner-elements"'
assert_contains "$OUT" "alt-tab: AltTab.app already in $SB/Applications - left alone"

it "App Store packages run in their own bundle; a failure asks to sign in"
make_sandbox
SB_CATALOG="$SB/catalog.txt"
printf '%s\n' 'firefox | cask | firefox | Firefox | web | Web browser' \
  'whatsapp | mas | 310633997 | WhatsApp | chat | Messenger' > "$SB_CATALOG"
sandbox_config 'PACKAGES="@all"'
brew_stub 0 Brewfile.mas
run_bootstrap --no-pull brew macos
SB_CATALOG=""
assert_eq "$RC" 1
assert_eq "$(brew_log)" "brew bundle --file=<tmp>/Brewfile --no-upgrade
  | cask \"firefox\"
brew bundle --file=<tmp>/Brewfile.mas --no-upgrade
  | brew \"mas\"
  | mas \"WhatsApp\", id: 310633997"
assert_contains "$OUT" "  brew       failed   (App Store: sign in, then re-run)"
assert_contains "$OUT" "  macos      ok"

it "brew installs Homebrew when missing, then bundles"
make_sandbox
rm "$SB/bin/brew"
installer_stub
run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_eq "$(brew_log)" "curl -fsSL $INSTALLER_URL
brew bundle --file=<tmp>/Brewfile --no-upgrade"

it "brew uses a Homebrew that is installed but not on PATH"
make_sandbox
rm "$SB/bin/brew"
stub "$SB/homebrew/bin/brew" brew
run_bootstrap --no-pull brew dotfiles
assert_eq "$RC" 0
assert_not_contains "$(cat "$LOG")" "curl"
assert_contains "$(brew_log)" "brew bundle --file=<tmp>/Brewfile --no-upgrade"
assert_contains "$OUT" "  dotfiles   ok"

it "a failed Homebrew install fails the step, later steps still run"
make_sandbox
rm "$SB/bin/brew"
installer_stub 22
run_bootstrap --no-pull brew macos
assert_eq "$RC" 1
assert_contains "$OUT" "  brew       failed   (Homebrew install failed)"
assert_contains "$OUT" "  macos      ok"
assert_not_contains "$(cat "$LOG")" "brew bundle"

it "a failing brew bundle fails the step, the extra Brewfile still runs"
make_sandbox
echo 'cask "firefox"' > "$SB/home/Brewfile.local"
sandbox_config 'BREW_BUNDLE_EXTRA="~/Brewfile.local"'
brew_stub 1
run_bootstrap --no-pull brew
assert_eq "$RC" 1
assert_contains "$OUT" "  brew       failed   (brew bundle)"
assert_contains "$(cat "$LOG")" "brew bundle --file=$SB/home/Brewfile.local --no-upgrade"

it "BREW_BUNDLE_EXTRA runs after the catalog bundle, also with PACKAGES=\"\""
make_sandbox
brew_stub
echo 'cask "firefox"' > "$SB/home/Brewfile.local"
sandbox_config 'BREW_BUNDLE_EXTRA="~/Brewfile.local"' 'PACKAGES=""'
run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_eq "$(brew_log)" "brew bundle --file=$SB/home/Brewfile.local --no-upgrade
  | cask \"firefox\""
assert_not_contains "$OUT" "no brew packages to install"

it "dry run shows the Homebrew install and the Brewfile, runs nothing"
make_sandbox
rm "$SB/bin/brew"
run_bootstrap --dry-run --no-pull brew
assert_eq "$RC" 0
assert_contains "$OUT" "+ install Homebrew: /bin/bash -c \"\$(curl -fsSL $INSTALLER_URL)\""
assert_contains "$OUT" '    cask "font-jetbrains-mono"'
assert_contains "$OUT" "+ brew bundle --file=$SB/tmp/macos-base-config."
assert_eq "$(cat "$LOG")" ""
```

In `it "karabiner skips when Karabiner-Elements is missing"`, replace
`assert_contains "$OUT" "  karabiner  skipped  (Karabiner-Elements not installed - run ./bootstrap.sh brew"`
with:

```bash
assert_contains "$OUT" "Karabiner-Elements not installed - add karabiner-elements to PACKAGES, then run ./bootstrap.sh brew"
assert_contains "$OUT" "  karabiner  skipped  (Karabiner-Elements not installed"
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: package_state: …` (function not found → empty output).

- [ ] **Step 4: Implement `package_state` and `write_brewfiles`** (append to `lib/packages.sh`)

```bash
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
```

- [ ] **Step 5: Rewrite `step_brew`** (in `lib/steps.sh`, keeping `brew_bundle`)

```bash
# bundle_brewfile FILE -> show what FILE installs, then brew bundle it
bundle_brewfile() {
  sed 's/^/    /' "$1"
  brew_bundle "$1"
}

step_brew() {
  local dir failed=""
  if ! find_brew && ! install_homebrew; then
    STEP_FAIL_REASON="Homebrew install failed"
    return 1
  fi
  dir="$(mktemp -d "${TMPDIR:-/tmp}/macos-base-config.XXXXXX")" || return 1
  if ! write_brewfiles "$dir" "$SELECTED_PACKAGES"; then
    rm -rf "$dir"
    return 1
  fi
  if [ ! -f "$dir/Brewfile" ] && [ ! -f "$dir/Brewfile.mas" ] && [ -z "$BREW_BUNDLE_EXTRA" ]; then
    echo "  no brew packages to install"
  fi
  if [ -f "$dir/Brewfile" ] && ! bundle_brewfile "$dir/Brewfile"; then
    failed="brew bundle"
  fi
  if [ -f "$dir/Brewfile.mas" ] && ! bundle_brewfile "$dir/Brewfile.mas"; then
    failed="${failed:+$failed; }App Store: sign in, then re-run"
  fi
  if [ -n "$BREW_BUNDLE_EXTRA" ] && ! brew_bundle "$BREW_BUNDLE_EXTRA"; then
    case "$failed" in *"brew bundle"*) ;; *) failed="${failed:+$failed; }brew bundle" ;; esac
  fi
  rm -rf "$dir"
  [ -z "$failed" ] && return 0
  STEP_FAIL_REASON="$failed"
  return 1
}
```

In `step_karabiner`:
`skip "Karabiner-Elements not installed - add karabiner-elements to PACKAGES, then run ./bootstrap.sh brew"`.

In `lib/cli.sh`, `step_description`:
`brew)      echo "install Homebrew if missing, then the selected brew / App Store packages (PACKAGES)" ;;`

Delete the Brewfile: `git rm Brewfile`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`. Then check this Mac with a dry run:
`./bootstrap.sh --dry-run --no-pull brew`. It should show "left alone" lines
for the apps that are already installed, and a Brewfile with
`font-jetbrains-mono`.

- [ ] **Step 7: Commit**

```bash
git add -A lib tests packages Brewfile
git commit -m "feat: generate the brew step's Brewfiles from the selected packages"
```

---

### Task 4: `./bootstrap.sh --list-packages`

**Files:**
- Modify: `lib/packages.sh` (`print_package_list`).
- Modify: `lib/cli.sh` (`parse_args`: `--list-packages` → `ACTION=list-packages`;
  `usage` gets a line).
- Modify: `bootstrap.sh` (handle the action after `load_config`).
- Modify: `tests/bootstrap-test.sh`.

**Interfaces:**
- Consumes: `catalog_rows`, `package_state`, `SELECTED_PACKAGES`.
- Produces: `print_package_list "<selected ids>"`, which prints to stdout and
  returns 2 on a broken catalog.

- [ ] **Step 1: Write the failing tests**

cli section:

```bash
it "--list-packages sets its action"
parse_args --list-packages; assert_eq "$ACTION" list-packages
```

In `it "usage lists the options"`, add `--list-packages` to the `for o in` list.

e2e (after the brew tests):

```bash
it "--list-packages groups by category, marks the selection and what is installed"
make_sandbox
mkdir -p "$SB/Applications/AltTab.app"
sandbox_config 'PACKAGES="alt-tab font-jetbrains-mono"'
run_bootstrap --list-packages
assert_eq "$RC" 0
assert_contains "$OUT" "@base"
assert_contains "$OUT" "[x] alt-tab                  installed Windows-style Alt+Tab window switching"
assert_contains "$OUT" "[ ] sidebar                  missing   Windows-style taskbar, Dock replacement"
assert_contains "$OUT" "[x] font-jetbrains-mono                JetBrains Mono, the editor font (editor step)"
assert_not_contains "$OUT" "== summary"
assert_eq "$(cat "$LOG")" ""

it "--list-packages with an invalid PACKAGES is exit 2"
make_sandbox
sandbox_config 'PACKAGES="bogus"'
run_bootstrap --list-packages
assert_eq "$RC" 2
assert_contains "$OUT" "unknown package: bogus"
assert_not_contains "$OUT" "@base"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: --list-packages sets its action: expected [list-packages], got [run]`.

- [ ] **Step 3: Implement**

`lib/packages.sh`:

```bash
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
```

`lib/cli.sh`, `parse_args`: add `--list-packages) ACTION=list-packages ;;`
above `--list)`. Update its doc comment to `ACTION
(run|list|list-packages|help)`. In `usage`, after the `--list` line, add:

```text
  --list-packages   list the package catalog, the selection and what is installed
```

`bootstrap.sh`, right after `load_config "$CONFIG_PATH" || exit 2`:

```bash
if [ "$ACTION" = list-packages ]; then
  print_package_list "$SELECTED_PACKAGES" || exit 2
  exit 0
fi
```

Add a usage line to the header comment:
`#   ./bootstrap.sh --list-packages   what PACKAGES can pick, and what is picked`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`. Then run `./bootstrap.sh --list-packages` on
this Mac. It should show `@base` with four entries, all selected.

- [ ] **Step 5: Commit**

```bash
git add lib bootstrap.sh tests/bootstrap-test.sh
git commit -m "feat: add --list-packages"
```

---

### Task 5: README

**Files:**
- Modify: `README.md`: the diagram line for `brew`; the Steps table row for
  `brew`; the Options table (`--list-packages`); the Configuration table
  (`PACKAGES` row, and `BREW_BUNDLE_EXTRA` wording); the `## 📦 Apps (Homebrew)`
  section; and the Fonts sentence "The `brew` step installs JetBrains Mono".

- [ ] **Step 1: Edit README.md**

Diagram line:
```text
   ├─ brew        Homebrew (installed if missing) + the selected packages (PACKAGES, default: Karabiner, AltTab, Sidebar, font)
```

Steps table row:
`| 🍺 | \`brew\`      | Homebrew installer if missing, \`brew bundle\` of the selected packages |`

Options table, after `--list`:
`| \`--list-packages\` | list the package catalog: what is selected, what is installed |`

Configuration table, a row before `BREW_BUNDLE_EXTRA`:
`| \`PACKAGES\` | \`@base\` | packages to install from the [catalog](#-apps-and-tools): ids, \`@category\`, \`@all\`; \`-\` removes; \`""\` = none |`

`BREW_BUNDLE_EXTRA` effect:
`extra Brewfile for apps outside the catalog, installed after the selected packages`.

Replace the whole `## 📦 Apps (Homebrew)` section, up to its
`### App settings` subsection (which stays as it is), with:

````markdown
## 📦 Apps and tools

Everything the bootstrap can install is listed in the catalog,
[`packages/catalog.txt`](packages/catalog.txt): one package per line with its
source (Homebrew formula or cask, App Store, …) and a description. **Nothing
is mandatory**: pick what this Mac gets with `PACKAGES` in the
[config](#%EF%B8%8F-configuration).

```sh
./bootstrap.sh --list-packages   # the catalog: [x] selected, installed / missing
./bootstrap.sh brew              # install the selection
```

| `PACKAGES`                    | Installs                                        |
|-------------------------------|-------------------------------------------------|
| *(key not set)*               | `@base`: Karabiner-Elements, AltTab, Sidebar, JetBrains Mono |
| `""`                          | nothing                                         |
| `"@base firefox"`             | a category plus one package                     |
| `"@all -steam -@cli-ai"`      | everything except one package and one category  |

The `@base` packages:

|    | Package                                                 | For                                  |
|:--:|---------------------------------------------------------|--------------------------------------|
| ⌨️  | [Karabiner-Elements](https://karabiner-elements.pqrs.org/) | Windows key behaviour (`karabiner` step) |
| 🔀 | [AltTab](https://alt-tab.app/)                          | Windows-style `Alt+Tab` window switching |
| 📌 | [Sidebar](https://sidebarapp.net/)                      | Windows-style taskbar, Dock replacement |
| 🔤 | JetBrains Mono                                          | editor font, see [Fonts](#-fonts)    |

- Installed apps are never upgraded by the bootstrap (`--no-upgrade`); they
  update themselves.
- An app already in `/Applications` is left alone, even when Homebrew didn't
  install it.
- App Store packages need you signed in to the App Store. Paid apps must
  already belong to your Apple ID.
- Apps outside the catalog go in your own Brewfile: set `BREW_BUNDLE_EXTRA`.
````

Fonts section, first sentence:
`The \`brew\` step installs JetBrains Mono (package \`font-jetbrains-mono\`, in \`@base\`).`

Also search the README for other links to `#-apps-homebrew` and for mentions
of `Brewfile` (`grep -n "apps-homebrew\|Brewfile" README.md`). Point them at
`#-apps-and-tools`, or reword them.

- [ ] **Step 2: Verify**

Run: `grep -n "apps-homebrew\|(Brewfile)" README.md`
Expected: no output.
Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document the package catalog and PACKAGES"
```

---

### Task 6: Final verification

- [ ] Run `/bin/bash tests/bootstrap-test.sh`. Expected: all cases pass.
- [ ] Run `./bootstrap.sh --dry-run --no-pull`. Expected: every step is `ok`
  or `skipped` for a known reason.
- [ ] Run `./bootstrap.sh --list-packages`. Expected: `@base`, four packages,
  all `[x]`.
- [ ] Run `git grep -n "Brewfile" -- ':!docs'`. Expected: only
  `BREW_BUNDLE_EXTRA`/generated-Brewfile wording, no reference to a tracked
  `Brewfile`.
