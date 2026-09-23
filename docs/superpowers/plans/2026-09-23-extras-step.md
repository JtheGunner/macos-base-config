# extras step: non-Homebrew packages (MBC-10) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new `extras` step installs the selected catalog packages whose
source is `script`, `npm`, `pipx`, `uv` or `go`. The `brew` step pulls in
the tools those sources need, and `manual` packages show up as hints in the
`manual` step.

**Architecture:**
- **Brewfile prerequisites.** `write_brewfiles` (lib/packages.sh) adds
  `brew "pipx"` / `brew "uv"` / `brew "go"` when a selected, not yet
  installed package needs that tool.
- **extras step.** `step_extras` (lib/steps.sh) walks the selected rows. It
  skips packages whose check command is already on PATH and installs the
  rest one by one with `install_extra`, collecting the failures.
- **manual hints.** `manual_package_hints` (lib/packages.sh) prints the
  `manual` hints, and `step_manual` calls it.

**Tech Stack:** bash 3.2, BWK awk; tests in `tests/bootstrap-test.sh` (plain
bash, sandbox with stub tools).

**Spec:** `docs/superpowers/specs/2026-09-23-package-catalog-design.md`
(sections *Sources*, *Steps*; this plan is ticket 2 of its Rollout, MBC-10).

## Global Constraints

- macOS `/bin/bash` 3.2; the catalog helpers stay bash + awk.
- Install commands:
  - `script`: `curl -fsSL <ref>` piped to `/bin/bash`;
  - `npm`: `npm install -g <ref>`;
  - `pipx`: `pipx install <ref>`;
  - `uv`: `uv tool install <ref>`;
  - `go`: `go install <ref>@latest`.
- Already installed: `command -v <check>` succeeds → skipped.
- npm without `npm` on PATH: skipped with "install Node first (e.g. nvm
  install --lts)". Node comes from nvm, not Homebrew.
- `pipx`, `uv` and `go` are added automatically to the brew run.
- One failing package does not stop the others. The step fails at the end
  with the ids of the failed packages.
- Nothing selected for extras → skip "no extra packages selected". Dry run
  installs nothing.
- `manual`: `step_manual` prints `Install <check> by hand (<description>): <ref>`
  when the package is selected and its app is missing.
- `applet` (nas-mount) is MBC-12. The extras step ignores it here.
- Step order: `repos brew extras karabiner keyboard macos jetbrains vscode editor apps dotfiles manual`.

## Review Focus

- **An installer that reads stdin** (npm or pipx prompting, or curl's script
  reading input) must not swallow the remaining catalog rows. The loop reads
  the rows on fd 3. Owned by Task 2, test "extras installs every source
  once" (its pipx stub reads stdin).
- **A tool that brew should have installed but did not** (pipx missing after
  a failed brew). Expect a clear failure naming the package and the hint to
  run brew, not a silent skip. Owned by Task 2, test "a missing tool fails
  its packages with a brew hint".
- **Dry run on a fresh Mac, before any tool exists.** Every command is
  printed, no "not found" failures appear, and nothing runs. Owned by
  Task 2, test "dry run prints every install, runs nothing".
- **A package already installed by other means** (e.g. `claude` from the
  native installer, `uv` from its own installer). It is left alone, and no
  prerequisite is pulled into the brew run for it. Owned by Tasks 1 and 2,
  tests "prerequisites only for missing packages" and "already installed
  commands are left alone".
- **Only npm packages selected, no Node.** The step ends `skipped` with the
  Node hint, not `ok` and not `failed`. Owned by Task 2, test "npm without
  Node is skipped with a hint; the rest still installs".

---

### Task 1: Brewfile prerequisites and manual hints (`lib/packages.sh`)

**Files:**
- Modify: `lib/packages.sh`:
  - `write_brewfiles` gets prerequisites;
  - new `manual_package_hints`.
- Modify: `lib/steps.sh`: `step_manual` calls `manual_package_hints`.
- Modify: `tests/bootstrap-test.sh`:
  - unit tests in the `lib/packages.sh` section, after the `write_brewfiles`
    tests;
  - e2e tests after `it "manual step lists every manual hint"`.

**Interfaces:**
- Consumes (existing): `catalog_rows`, `package_state SOURCE CHECK`,
  `SELECTED_PACKAGES`.
- Produces:
  - `write_brewfiles DIR "<ids>"` keeps its signature. `DIR/Brewfile`
    additionally holds `brew "<tool>"` for each of pipx/uv/go that a selected,
    not yet installed package needs, unless that formula is already listed.
  - `manual_package_hints "<ids>"` prints one line per selected `manual`
    package whose app is missing.

- [ ] **Step 1: Write the failing tests**

Unit tests, after `it "write_brewfiles writes nothing for an empty selection, removes stale files"`
(and its trailing `true`):

```bash
EXTRA_CATALOG_LINES=(
  'hf        | pipx    | huggingface-hub          | hf        | ai  | Hugging Face CLI'
  'nano-pdf  | uv      | nano-pdf                 | nano-pdf  | ai  | PDF tool'
  'gopls     | go      | golang.org/x/tools/gopls | gopls     | dev | Go language server'
  'sass      | npm     | sass                     | sass      | dev | Sass compiler'
  'uv        | formula | uv                       | -         | dev | Python package manager'
  'here      | pipx    | here-pkg                 | sh        | ai  | its command is already on PATH'
  'filezilla | manual  | https://filezilla-project.org/download.php?type=client | FileZilla | dev | FTP client'
)

# PATH=/usr/bin:/bin: this Mac may have hf / nano-pdf installed
it "write_brewfiles adds pipx / uv / go for selected packages that need them"
f="$(write_catalog "${EXTRA_CATALOG_LINES[@]}")"
d="$(mktemp -d "$TMP/bf.XXXXXX")"
PATH=/usr/bin:/bin PACKAGE_CATALOG="$f" write_brewfiles "$d" "hf nano-pdf gopls sass" >/dev/null
assert_eq "$(cat "$d/Brewfile")" 'brew "pipx"
brew "uv"
brew "go"'

it "prerequisites only for missing packages, never twice"
d="$(mktemp -d "$TMP/bf.XXXXXX")"
PATH=/usr/bin:/bin PACKAGE_CATALOG="$f" write_brewfiles "$d" "here" >/dev/null
[ -e "$d/Brewfile" ] && fail "pipx added for an installed package"
PATH=/usr/bin:/bin PACKAGE_CATALOG="$f" write_brewfiles "$d" "uv nano-pdf" >/dev/null
assert_eq "$(cat "$d/Brewfile")" 'brew "uv"'

it "manual hints: selected and missing only"
mkdir -p "$TMP/apps3"
out="$(APPLICATIONS_DIR="$TMP/apps3" PACKAGE_CATALOG="$f" manual_package_hints "filezilla hf")"
assert_eq "$out" "  - Install FileZilla by hand (FTP client): https://filezilla-project.org/download.php?type=client"
assert_eq "$(APPLICATIONS_DIR="$TMP/apps3" PACKAGE_CATALOG="$f" manual_package_hints "hf")" ""
mkdir -p "$TMP/apps3/FileZilla.app"
assert_eq "$(APPLICATIONS_DIR="$TMP/apps3" PACKAGE_CATALOG="$f" manual_package_hints "filezilla")" ""
```

e2e tests, after the `manual step lists every manual hint` test. They use
`SB_CATALOG` (supported by `run_bootstrap` since MBC-9):

```bash
it "manual step names a selected manual package that is missing"
make_sandbox
SB_CATALOG="$SB/catalog.txt"
echo 'filezilla | manual | https://filezilla-project.org/download.php?type=client | FileZilla | dev | FTP client' > "$SB_CATALOG"
sandbox_config 'PACKAGES="filezilla"'
run_bootstrap manual
assert_contains "$OUT" "Install FileZilla by hand (FTP client): https://filezilla-project.org/download.php?type=client"
mkdir -p "$SB/Applications/FileZilla.app"
run_bootstrap manual
SB_CATALOG=""
assert_not_contains "$OUT" "FileZilla"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: write_brewfiles adds pipx / uv / go …` (the Brewfile is not
written, so `cat` fails and the output is empty).

- [ ] **Step 3: Implement**

In `write_brewfiles` (lib/packages.sh), extend the doc comment with:

```bash
# A selected pipx / uv / go package whose command is missing pulls in its
# tool (brew "pipx", "uv", "go") unless that formula is listed already.
```

Declare `local needs="" tool` next to the other locals. Replace the line
`case "$source" in formula | cask | mas) ;; *) continue ;; esac` with:

```bash
    case "$source" in
      formula | cask | mas) ;;
      pipx | uv | go)
        if [ "$(package_state "$source" "$check")" != installed ]; then
          case " $needs " in *" $source "*) ;; *) needs="$needs $source" ;; esac
        fi
        continue ;;
      *) continue ;;
    esac
```

Right after the `done <<< "$rows"` line, add:

```bash
  for tool in $needs; do
    case "$entries" in *"brew \"$tool\""*) ;; *) entries="${entries}brew \"$tool\""$'\n' ;; esac
  done
```

Append to `lib/packages.sh`:

```bash
# manual_package_hints "<selected ids>" -> one line per selected "manual"
# package whose app is missing: where to get it
manual_package_hints() {
  local rows id source ref check _category description
  rows="$(catalog_rows)" || return 2
  while IFS=$'\t' read -r id source ref check _category description; do
    [ "$source" = manual ] || continue
    case " $1 " in *" $id "*) ;; *) continue ;; esac
    [ "$(package_state manual "$check")" = installed ] && continue
    echo "  - Install $check by hand ($description): $ref"
  done <<< "$rows"
}
```

In `step_manual` (lib/steps.sh), add as its last line:

```bash
  manual_package_hints "$SELECTED_PACKAGES"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 5: Commit**

```bash
git add lib/packages.sh lib/steps.sh tests/bootstrap-test.sh
git commit -m "feat: pull pipx, uv and go into the brew run; hint manual packages"
```

---

### Task 2: The `extras` step

**Files:**
- Modify: `lib/cli.sh`: `ALL_STEPS` gets `extras` after `brew`, plus its
  `step_description`.
- Modify: `lib/steps.sh`: new `install_extra` and `step_extras`, after
  `step_brew`.
- Modify: `tests/bootstrap-test.sh`:
  - the step lists in the cli tests;
  - the header comment's stub list;
  - a new `# --- the extras step` section before `# --- the dotfiles step`.

**Interfaces:**
- Consumes: `catalog_rows`, `package_state`, `SELECTED_PACKAGES`, `run_cmd`,
  `skip`, `DRY_RUN`.
- Produces:
  - `step_extras`: 0 = ok, or skipped via `skip`; 1 = failed, with
    `STEP_FAIL_REASON="failed: <ids>"`.
  - `install_extra SOURCE REF`: installs one package and returns the
    installer's status.

- [ ] **Step 1: Write the failing tests**

Step lists in the cli section: in each of these four places, change
`repos brew karabiner` to `repos brew extras karabiner`:
- the `no steps selects every step in order` expectation;
- the `skip removes steps` expectation;
- the multi-line `lists spanning several lines` expectation;
- the `for s in …` loop of `step list names every step and the alias`.

Header comment, stub list: `(git, brew, python3, omnishell, curl, open, swift, sudo, spctl)`
becomes `(git, brew, python3, omnishell, curl, open, swift, sudo, spctl; npm,
pipx, uv, go where a test needs them)`.

New section before `# --- the dotfiles step`:

```bash
# --- the extras step --------------------------------------------------------
SCRIPT_URL="https://example.test/install.sh"

# extras_sandbox PACKAGES -> sandbox with a catalog of one package per extras
# source, PACKAGES selected; curl serves a script that logs "script-ran"
extras_sandbox() {
  make_sandbox
  SB_CATALOG="$SB/catalog.txt"
  printf '%s\n' \
    "claude   | script | $SCRIPT_URL              | claude   | ai  | Claude Code" \
    'sass     | npm    | sass                     | sass     | dev | Sass compiler' \
    'hf       | pipx   | huggingface-hub          | hf       | ai  | Hugging Face CLI' \
    'nano-pdf | uv     | nano-pdf                 | nano-pdf | ai  | PDF tool' \
    'gopls    | go     | golang.org/x/tools/gopls | gopls    | dev | Go language server' \
    > "$SB_CATALOG"
  sandbox_config "PACKAGES=\"$1\""
  printf '#!/bin/bash\necho "curl $*" >> "%s"\necho "echo script-ran >> \\"%s\\""\n' "$LOG" "$LOG" > "$SB/bin/curl"
  chmod +x "$SB/bin/curl"
  local tool
  for tool in npm uv go; do stub "$SB/bin/$tool" "$tool"; done
  # pipx reads stdin: it must not eat the catalog rows the step loops over
  printf '#!/bin/bash\ncat >/dev/null\necho "pipx $*" >> "%s"\n' "$LOG" > "$SB/bin/pipx"
  chmod +x "$SB/bin/pipx"
}

it "extras installs every source once"
extras_sandbox "@all"
run_bootstrap --no-pull extras
SB_CATALOG=""
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "curl -fsSL $SCRIPT_URL
script-ran
npm install -g sass
pipx install huggingface-hub
uv tool install nano-pdf
go install golang.org/x/tools/gopls@latest"
assert_contains "$OUT" "  extras     ok"

it "already installed commands are left alone"
extras_sandbox "hf gopls"
stub "$SB/bin/hf" hf
run_bootstrap --no-pull extras
SB_CATALOG=""
assert_eq "$(cat "$LOG")" "go install golang.org/x/tools/gopls@latest"
assert_contains "$OUT" "hf: hf already installed"

it "npm without Node is skipped with a hint; the rest still installs"
extras_sandbox "sass hf"
rm "$SB/bin/npm"
run_bootstrap --no-pull extras
SB_CATALOG=""
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "pipx install huggingface-hub"
assert_contains "$OUT" "sass: skipped - install Node first (e.g. nvm install --lts)"
assert_contains "$OUT" "  extras     skipped  (install Node first (e.g. nvm install --lts) for: sass)"

it "a failing package fails the step by name, later packages still install"
extras_sandbox "hf nano-pdf"
stub "$SB/bin/pipx" pipx 1
run_bootstrap --no-pull extras macos
SB_CATALOG=""
assert_eq "$RC" 1
assert_contains "$(cat "$LOG")" "uv tool install nano-pdf"
assert_contains "$OUT" "  extras     failed   (failed: hf)"
assert_contains "$OUT" "  macos      ok"

it "a missing tool fails its packages with a brew hint"
extras_sandbox "hf"
rm "$SB/bin/pipx"
run_bootstrap --no-pull extras
SB_CATALOG=""
assert_eq "$RC" 1
assert_contains "$OUT" "hf: pipx not found - run ./bootstrap.sh brew"
assert_contains "$OUT" "  extras     failed   (failed: hf)"

it "dry run prints every install, runs nothing"
extras_sandbox "@all"
rm "$SB/bin/npm" "$SB/bin/pipx" "$SB/bin/uv" "$SB/bin/go"
run_bootstrap --dry-run --no-pull extras
SB_CATALOG=""
assert_eq "$RC" 0
assert_contains "$OUT" "+ curl -fsSL $SCRIPT_URL | bash"
assert_contains "$OUT" "+ npm install -g sass"
assert_contains "$OUT" "+ pipx install huggingface-hub"
assert_contains "$OUT" "+ uv tool install nano-pdf"
assert_contains "$OUT" "+ go install golang.org/x/tools/gopls@latest"
assert_eq "$(cat "$LOG")" ""

it "extras skips when no extra package is selected, runs right after brew"
make_sandbox
run_bootstrap --no-pull manual extras brew
assert_eq "$(headers)" "== brew == extras == manual == summary "
assert_contains "$OUT" "  extras     skipped  (no extra packages selected)"

it "the brew run pulls in pipx for a selected pipx package"
extras_sandbox "hf"
brew_stub
run_bootstrap --no-pull brew
SB_CATALOG=""
assert_contains "$(cat "$LOG")" '  | brew "pipx"'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: no steps selects every step in order` (no `extras` in
`ALL_STEPS` yet).

- [ ] **Step 3: Implement**

`lib/cli.sh`:

```bash
ALL_STEPS="repos brew extras karabiner keyboard macos jetbrains vscode editor apps dotfiles manual"
```

and in `step_description`, after the `brew)` line:

```bash
    extras)    echo "install the selected packages that don't come from Homebrew (script, npm, pipx, uv, go)" ;;
```

`lib/steps.sh`, after `step_brew`:

```bash
# install_extra SOURCE REF -> install one package of an extras source (dry
# run: print only). A script is fetched first, then run, like the Homebrew
# installer.
install_extra() {
  local installer
  case "$1" in
    script)
      echo "+ curl -fsSL $2 | bash"
      $DRY_RUN && return 0
      installer="$(curl -fsSL "$2")" || return 1
      /bin/bash -c "$installer" ;;
    npm) run_cmd npm install -g "$2" ;;
    pipx) run_cmd pipx install "$2" ;;
    uv) run_cmd uv tool install "$2" ;;
    go) run_cmd go install "$2@latest" ;;
  esac
}

# step_extras -> install the selected script / npm / pipx / uv / go packages
# whose command is missing. The tools come from the brew step (npm: from
# Node, which nvm installs). A failing package doesn't stop the others.
step_extras() {
  local rows id source ref check _category _description tool
  local selected=false failed="" need_node=""
  rows="$(catalog_rows)" || { STEP_FAIL_REASON="package catalog"; return 1; }
  # rows on fd 3: an installer that reads stdin must not eat the rest
  while IFS=$'\t' read -r id source ref check _category _description <&3; do
    case " $SELECTED_PACKAGES " in *" $id "*) ;; *) continue ;; esac
    case "$source" in script | npm | pipx | uv | go) ;; *) continue ;; esac
    selected=true
    if [ "$(package_state "$source" "$check")" = installed ]; then
      echo "  $id: $check already installed"
      continue
    fi
    tool="$source"
    [ "$source" = script ] && tool=curl
    if ! $DRY_RUN && ! command -v "$tool" >/dev/null 2>&1; then
      if [ "$source" = npm ]; then
        echo "  $id: skipped - install Node first (e.g. nvm install --lts)"
        need_node="$need_node $id"
      else
        echo "  $id: $tool not found - run ./bootstrap.sh brew"
        failed="$failed $id"
      fi
      continue
    fi
    install_extra "$source" "$ref" || failed="$failed $id"
  done 3<<< "$rows"
  if ! $selected; then
    skip "no extra packages selected"
    return 0
  fi
  if [ -n "$failed" ]; then
    STEP_FAIL_REASON="failed:$failed"
    return 1
  fi
  [ -z "$need_node" ] || skip "install Node first (e.g. nvm install --lts) for:$need_node"
  return 0
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 5: Commit**

```bash
git add lib/cli.sh lib/steps.sh tests/bootstrap-test.sh
git commit -m "feat: add the extras step for script, npm, pipx, uv and go packages"
```

---

### Task 3: README

**Files:**
- Modify: `README.md`:
  - diagram: a line for `extras` after `brew`;
  - steps table: a row after `brew`;
  - section `## 📦 Apps and tools`: a sources table and the extras notes.

- [ ] **Step 1: Edit README.md**

Diagram, after the `brew` line:

```text
   ├─ extras      selected packages from outside Homebrew: install scripts, npm, pipx, uv, go
```

Steps table, after the `brew` row:

```markdown
| 🧩 | `extras`    | install scripts, `npm -g`, `pipx`, `uv tool`, `go install` for the selected packages |
```

In `## 📦 Apps and tools`, right after the `./bootstrap.sh brew` code block
(before the `PACKAGES` table), insert:

```markdown
Where a package comes from decides which step installs it:

| Source    | Installed by                                   | Step     |
|-----------|------------------------------------------------|----------|
| `formula` | `brew bundle` (`brew "…"`)                     | `brew`   |
| `cask`    | `brew bundle` (`cask "…"`)                     | `brew`   |
| `mas`     | `brew bundle` (`mas "…"`), App Store           | `brew`   |
| `script`  | the vendor's install script (`curl … \| bash`) | `extras` |
| `npm`     | `npm install -g`                               | `extras` |
| `pipx`    | `pipx install`                                 | `extras` |
| `uv`      | `uv tool install`                              | `extras` |
| `go`      | `go install …@latest`                          | `extras` |
| `manual`  | you: the `manual` step prints the download link | `manual` |
```

and add to the bullet list at the end of that section (before
`### App settings`):

```markdown
- `pipx`, `uv` and `go` are installed by the `brew` step when a selected
  package needs them. `npm` packages need Node: `nvm install --lts` first.
- A package whose command is already on your `PATH` is left alone, however it
  was installed.
```

- [ ] **Step 2: Verify**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document the extras step and the package sources"
```

---

### Task 4: Final verification

- [ ] Run `/bin/bash tests/bootstrap-test.sh`. Expected: all cases pass.
- [ ] Run `./bootstrap.sh --dry-run --no-pull brew extras manual` on this Mac
  (default config). Expected: `extras     skipped  (no extra packages selected)`.
- [ ] Run `./bootstrap.sh --list`. Expected: `extras` listed between `brew`
  and `karabiner`.
