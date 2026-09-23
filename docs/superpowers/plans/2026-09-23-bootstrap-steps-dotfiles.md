# Bootstrap Steps + dotfiles Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `bootstrap.sh` into a step runner (named steps, `--skip`, `--list`, per-machine config, summary) and add the `dotfiles` sibling repo as a default step.

**Architecture:** `bootstrap.sh` becomes a short entry point that sources three focused libraries: `lib/cli.sh` (step table, argument parsing, selection — pure functions), `lib/config.sh` (load + validate a sourced shell config), `lib/steps.sh` (one `step_<name>` function per step plus sibling-checkout helpers). The entry point parses args, loads config, selects steps, runs each one best-effort, and prints a summary.

**Tech Stack:** Bash (must run under macOS `/bin/bash` 3.2), git, a dependency-free bash test script.

**Spec:** `docs/superpowers/specs/2026-09-23-bootstrap-steps-dotfiles-design.md`

## Global Constraints

- Every script runs under macOS `/bin/bash` 3.2.57 with `set -uo pipefail` (no `-e` in `bootstrap.sh`/`lib/`). No associative arrays, no `mapfile`, no `${var,,}`. Expanding a possibly-empty array needs `${arr[@]+"${arr[@]}"}`; prefer space-separated strings for step lists (step names never contain spaces).
- Split untrusted word lists with `read -r -a` (no glob expansion), never with an unquoted `$var` — except `$ALL_STEPS` and already-validated selections.
- Step order is fixed: `repos karabiner macos jetbrains vscode dotfiles manual`. Alias: `keymaps` = `jetbrains vscode`.
- Exit codes: `2` = usage/config error before any step runs; `1` = at least one step failed; `0` otherwise (including "nothing to do").
- Config path: `${XDG_CONFIG_HOME:-$HOME/.config}/macos-base-config/config.sh`; `--config <path>` overrides.
- All code, comments, identifiers, commit messages in English. Commits: `<type>: <description>`, no trailers, never `--no-verify`.
- Never run `bootstrap.sh` for real from this worktree: its parent is `.worktrees/`, so it would clone siblings there. Use the tests (sandboxed) or `--dry-run`.
- Run tests with `/bin/bash tests/bootstrap-test.sh` from the repo root.

## Review Focus

1. A sibling clone/pull that reads stdin (credential or host-key prompt) must not swallow the rest of `repos.txt` — the loop reads `repos.txt` on fd 3 (test in Task 3).
2. A config value with glob characters (`BOOTSTRAP_STEPS="*"`) must be rejected as an unknown step, not expanded against the cwd (test in Task 1 via `select_steps`, reused by config validation).
3. `DOTFILES_DIR` containing spaces or a quoted `~/…` must be used verbatim / expanded to `$HOME` (test in Task 4).
4. An own omnishell config must land *after* the dotfiles bootstrap, because that bootstrap overwrites `~/.config/omnishell/config.toml` every run (order asserted in Task 4).
5. `--dry-run` must not run git, the dotfiles bootstrap, or `omnishell`, while sub-tools that support it still get `--dry-run` (test in Tasks 3 and 4).

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/cli.sh` (new) | step table, `step_description`, `expand_names`, `select_steps`, `parse_args`, `usage`, `print_step_list` |
| `lib/config.sh` (new) | `default_config_path`, `expand_home`, `load_config`, `validate_config` |
| `lib/steps.sh` (new) | `skip`, `run_cmd`, `show_cmd`, `run_in`, sibling helpers, `step_*` functions |
| `bootstrap.sh` (rewrite) | entry point: parse → config → select → run → summary |
| `repos.txt` (modify) | drop the apply column, add `dotfiles` |
| `config.example.sh` (new) | documented config template |
| `tests/bootstrap-test.sh` (new) | unit + sandboxed end-to-end tests |
| `README.md` (modify) | steps, options, configuration, tests, dotfiles |

---

### Task 1: Step table, selection and argument parsing (`lib/cli.sh`)

**Files:**
- Create: `lib/cli.sh`
- Create: `tests/bootstrap-test.sh`

**Interfaces:**
- Produces (globals): `ALL_STEPS` = `"repos karabiner macos jetbrains vscode dotfiles manual"`.
- Produces (functions):
  - `step_description NAME` → prints one-line description.
  - `expand_names NAME...` → prints space-separated step names with aliases resolved; unknown name → stderr `bootstrap.sh: unknown step: <name> (see --list)`, return 2.
  - `select_steps "<wanted>" "<skipped>"` → prints selected steps in table order, space-separated; empty `<wanted>` = all; return 2 on unknown.
  - `parse_args ARG...` → sets `ACTION` (`run|list|help`), `CLI_STEPS`, `CLI_SKIP` (space-separated strings), `DRY_RUN`, `NO_PULL` (`true|false`), `CONFIG_PATH`; return 2 on error.
  - `usage_error MSG`, `usage`, `print_step_list`.
- Produces (test harness in `tests/bootstrap-test.sh`): `it NAME`, `fail MSG`, `assert_eq ACTUAL EXPECTED`, `assert_contains HAYSTACK NEEDLE`, `assert_not_contains HAYSTACK NEEDLE`, globals `REPO`, `COUNT`. The file ends with the line `echo "all $COUNT cases passed"`; later tasks insert their sections **above** that line.

- [ ] **Step 1: Write the test harness and failing CLI tests**

Create `tests/bootstrap-test.sh`:

```bash
#!/bin/bash
# Tests for bootstrap.sh and lib/. Plain bash, no dependencies; meant to run
# under macOS /bin/bash 3.2 on purpose.
#
#   /bin/bash tests/bootstrap-test.sh
#
# End-to-end cases run bootstrap.sh inside a throwaway sandbox: a copy of the
# scripts next to stub sibling repos, a fake HOME, and stub tools (git, brew,
# python3, omnishell) that only log their arguments.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CURRENT=""
COUNT=0

it() { CURRENT="$1"; COUNT=$((COUNT + 1)); echo "- $1"; }
fail() { echo "FAIL: $CURRENT: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
assert_contains() {
  case "$1" in *"$2"*) ;; *) fail "expected [$2] in: $1" ;; esac
}
assert_not_contains() {
  case "$1" in *"$2"*) fail "did not expect [$2] in: $1" ;; esac
}

# --- lib/cli.sh -------------------------------------------------------------
. "$REPO/lib/cli.sh"

it "no steps selects every step in order"
assert_eq "$(select_steps "" "")" "repos karabiner macos jetbrains vscode dotfiles manual"

it "steps run in table order, aliases expand"
assert_eq "$(select_steps "dotfiles keymaps" "")" "jetbrains vscode dotfiles"

it "skip removes steps, aliases included"
assert_eq "$(select_steps "" "keymaps dotfiles")" "repos karabiner macos manual"

it "duplicates collapse"
assert_eq "$(select_steps "macos macos keymaps jetbrains" "")" "macos jetbrains vscode"

it "extra whitespace is ignored"
assert_eq "$(select_steps "  macos   manual " "")" "macos manual"

it "unknown step is exit 2 with a message"
out="$(select_steps "bogus" "" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "unknown step: bogus"

it "unknown skipped step is exit 2"
out="$(select_steps "" "nope" 2>&1)"; rc=$?
assert_eq "$rc" 2

it "glob characters are rejected, not expanded"
out="$(cd "$REPO" && select_steps "*" "" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "unknown step: *"

it "parse_args defaults"
parse_args
assert_eq "$ACTION|$CLI_STEPS|$CLI_SKIP|$DRY_RUN|$NO_PULL|$CONFIG_PATH" "run|||false|false|"

it "parse_args collects steps, skips and flags"
parse_args --dry-run keymaps --skip vscode --no-pull --config /tmp/x.sh dotfiles --skip manual
assert_eq "$ACTION" run
assert_eq "$CLI_STEPS" "keymaps dotfiles"
assert_eq "$CLI_SKIP" "vscode manual"
assert_eq "$DRY_RUN|$NO_PULL|$CONFIG_PATH" "true|true|/tmp/x.sh"

it "--list and --help set the action"
parse_args --list; assert_eq "$ACTION" list
parse_args -h; assert_eq "$ACTION" help
parse_args --help; assert_eq "$ACTION" help

it "unknown option is exit 2 with a message"
out="$(parse_args --bogus 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "unknown option: --bogus"

it "--skip and --config need a value"
out="$(parse_args --skip 2>&1)"; rc=$?
assert_eq "$rc" 2
out="$(parse_args --config 2>&1)"; rc=$?
assert_eq "$rc" 2

it "step list names every step and the alias"
out="$(print_step_list)"
for s in repos karabiner macos jetbrains vscode dotfiles manual keymaps; do
  assert_contains "$out" "$s"
done

it "usage lists the options"
out="$(usage)"
for o in --skip --dry-run --no-pull --config --list --help; do
  assert_contains "$out" "$o"
done

echo "all $COUNT cases passed"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: error `lib/cli.sh: No such file or directory`, then `FAIL: no steps selects every step in order`.

- [ ] **Step 3: Implement `lib/cli.sh`**

```bash
#!/usr/bin/env bash
# Step table, argument parsing and step selection for bootstrap.sh.
# Sourced; defines data and functions only, no side effects.

# Execution order. Every name has a step_<name> function in lib/steps.sh.
ALL_STEPS="repos karabiner macos jetbrains vscode dotfiles manual"

step_description() {
  case "$1" in
    repos)     echo "clone missing / pull existing sibling repos (repos.txt)" ;;
    karabiner) echo "apply the Karabiner config (needs Karabiner-Elements)" ;;
    macos)     echo "macOS defaults: system hotkeys, Finder shortcut, font smoothing" ;;
    jetbrains) echo "JetBrains keymap into the PhpStorm / IntelliJ config" ;;
    vscode)    echo "port the keymap to VS Code / Antigravity" ;;
    dotfiles)  echo "run the dotfiles repo's bootstrap (shell, git, tmux, Ghostty)" ;;
    manual)    echo "print the manual, non-scriptable steps" ;;
  esac
}

usage_error() {
  echo "bootstrap.sh: $1" >&2
  echo "run ./bootstrap.sh --help for usage" >&2
}

# expand_names NAME... -> step names with aliases resolved, space-separated.
# Unknown name: message on stderr, return 2.
expand_names() {
  local name expanded=""
  for name in "$@"; do
    case "$name" in
      keymaps) expanded="$expanded jetbrains vscode" ;;
      *)
        case " $ALL_STEPS " in
          *" $name "*) expanded="$expanded $name" ;;
          *) usage_error "unknown step: $name (see --list)"; return 2 ;;
        esac ;;
    esac
  done
  echo "${expanded# }"
}

# select_steps "<wanted>" "<skipped>" -> the steps to run, in execution order,
# space-separated. Empty <wanted> = every step. Unknown name: return 2.
select_steps() {
  local words wanted skipped step selected=""
  read -r -a words <<< "$1"
  if [ ${#words[@]} -eq 0 ]; then
    wanted="$ALL_STEPS"
  else
    wanted="$(expand_names "${words[@]}")" || return 2
  fi
  read -r -a words <<< "$2"
  skipped=""
  if [ ${#words[@]} -gt 0 ]; then
    skipped="$(expand_names "${words[@]}")" || return 2
  fi
  for step in $ALL_STEPS; do
    case " $wanted " in *" $step "*) ;; *) continue ;; esac
    case " $skipped " in *" $step "*) continue ;; esac
    selected="$selected $step"
  done
  echo "${selected# }"
}

# parse_args ARG... -> sets ACTION (run|list|help), CLI_STEPS, CLI_SKIP,
# DRY_RUN, NO_PULL (true|false), CONFIG_PATH. Return 2 on a usage error.
# Step names are validated later by select_steps.
parse_args() {
  ACTION=run; CLI_STEPS=""; CLI_SKIP=""
  DRY_RUN=false; NO_PULL=false; CONFIG_PATH=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --skip)
        [ $# -ge 2 ] || { usage_error "--skip needs a step"; return 2; }
        CLI_SKIP="$CLI_SKIP $2"; shift ;;
      --config)
        [ $# -ge 2 ] || { usage_error "--config needs a path"; return 2; }
        CONFIG_PATH="$2"; shift ;;
      --dry-run) DRY_RUN=true ;;
      --no-pull) NO_PULL=true ;;
      --list) ACTION=list ;;
      -h | --help) ACTION=help ;;
      -*) usage_error "unknown option: $1"; return 2 ;;
      *) CLI_STEPS="$CLI_STEPS $1" ;;
    esac
    shift
  done
  CLI_STEPS="${CLI_STEPS# }"
  CLI_SKIP="${CLI_SKIP# }"
}

print_step_list() {
  local step
  for step in $ALL_STEPS; do
    printf '  %-10s %s\n' "$step" "$(step_description "$step")"
  done
  printf '  %-10s %s\n' keymaps "alias for: jetbrains vscode"
}

usage() {
  cat <<'EOF'
usage: ./bootstrap.sh [options] [step ...]

Runs every step when no step is given. Steps always run in this order:

EOF
  print_step_list
  cat <<'EOF'

options:
  --skip <step>     skip a step or alias (repeatable)
  --dry-run         show what would happen, change nothing
  --no-pull         don't update sibling repos that are already cloned
  --config <path>   config file (default: ~/.config/macos-base-config/config.sh)
  --list            list the steps
  -h, --help        this help
EOF
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: every case printed, last line `all 15 cases passed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/cli.sh tests/bootstrap-test.sh
git commit -m "feat: add step table and argument parsing for bootstrap"
```

---

### Task 2: Config loading and validation (`lib/config.sh`)

**Files:**
- Create: `lib/config.sh`
- Modify: `tests/bootstrap-test.sh` (insert a section above the final `echo "all …"` line)

**Interfaces:**
- Consumes: `select_steps` from Task 1.
- Produces:
  - `default_config_path` → prints `${XDG_CONFIG_HOME:-$HOME/.config}/macos-base-config/config.sh`.
  - `expand_home VALUE` → `~` / `~/x` → `$HOME` / `$HOME/x`, anything else unchanged.
  - `load_config [PATH]` → resets and sets globals `BOOTSTRAP_STEPS`, `BOOTSTRAP_SKIP`, `DOTFILES_DIR`, `DOTFILES_URL`, `DOTFILES_ASSUME_YES` (`0|1`), `DOTFILES_TERMINALS`, `DOTFILES_OMNISHELL_CONFIG`; return 2 on any error. `DOTFILES_DIR` / `DOTFILES_OMNISHELL_CONFIG` come back `~`-expanded.
- Produces (test harness): `TMP` (temp dir removed on exit), `write_config LINE...` → writes `$TMP/config.sh`, prints its path.

- [ ] **Step 1: Write the failing config tests**

Insert above `echo "all $COUNT cases passed"`:

```bash
# --- lib/config.sh ----------------------------------------------------------
. "$REPO/lib/config.sh"
# physical path: macOS TMPDIR ends in "/" and sits behind the /var symlink,
# while bootstrap.sh derives its own paths with cd + pwd
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/mbc-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# write_config LINE... -> writes $TMP/config.sh, prints its path
write_config() { printf '%s\n' "$@" > "$TMP/config.sh"; echo "$TMP/config.sh"; }

it "missing default config file means defaults"
XDG_CONFIG_HOME="$TMP/none" load_config ""; rc=$?
assert_eq "$rc" 0
assert_eq "$BOOTSTRAP_STEPS|$BOOTSTRAP_SKIP|$DOTFILES_DIR|$DOTFILES_URL|$DOTFILES_ASSUME_YES|$DOTFILES_TERMINALS|$DOTFILES_OMNISHELL_CONFIG" "||||0||"

it "default config path follows XDG_CONFIG_HOME, then HOME"
assert_eq "$(XDG_CONFIG_HOME=/x default_config_path)" "/x/macos-base-config/config.sh"
assert_eq "$(XDG_CONFIG_HOME="" HOME=/h default_config_path)" "/h/.config/macos-base-config/config.sh"

it "default config file is read"
mkdir -p "$TMP/xdg/macos-base-config"
echo 'BOOTSTRAP_STEPS="manual"' > "$TMP/xdg/macos-base-config/config.sh"
XDG_CONFIG_HOME="$TMP/xdg" load_config ""
assert_eq "$BOOTSTRAP_STEPS" manual

it "a later load resets earlier values"
XDG_CONFIG_HOME="$TMP/none" load_config ""
assert_eq "$BOOTSTRAP_STEPS" ""

it "explicit config values load, quoted ~ expands"
f="$(write_config 'DOTFILES_DIR="~/Git/dot files"' 'DOTFILES_ASSUME_YES=1' \
  'DOTFILES_TERMINALS="kitty"' 'BOOTSTRAP_SKIP="keymaps"')"
HOME=/Users/test load_config "$f"; rc=$?
assert_eq "$rc" 0
assert_eq "$DOTFILES_DIR" "/Users/test/Git/dot files"
assert_eq "$DOTFILES_ASSUME_YES|$DOTFILES_TERMINALS|$BOOTSTRAP_SKIP" "1|kitty|keymaps"

it "expand_home leaves other paths alone"
assert_eq "$(HOME=/h expand_home "~")" "/h"
assert_eq "$(HOME=/h expand_home "/a/~b")" "/a/~b"
assert_eq "$(HOME=/h expand_home "")" ""

it "missing explicit config is exit 2"
out="$(load_config "$TMP/missing.sh" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "config file not found: $TMP/missing.sh"

it "config syntax error is exit 2"
f="$(write_config 'BOOTSTRAP_STEPS=(')"
out="$(load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "syntax error in config"

it "unknown step in config is exit 2"
f="$(write_config 'BOOTSTRAP_STEPS="macos bogus"')"
out="$(load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "unknown step: bogus"
assert_contains "$out" "$f"

it "glob in config steps is exit 2"
f="$(write_config 'BOOTSTRAP_SKIP="*"')"
out="$(cd "$REPO" && load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2

it "DOTFILES_ASSUME_YES must be 0 or 1"
f="$(write_config 'DOTFILES_ASSUME_YES=yes')"
out="$(load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "DOTFILES_ASSUME_YES must be 0 or 1"

it "DOTFILES_OMNISHELL_CONFIG must be a readable file"
f="$(write_config "DOTFILES_OMNISHELL_CONFIG=\"$TMP/nope.toml\"")"
out="$(load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "DOTFILES_OMNISHELL_CONFIG"
echo 'x = 1' > "$TMP/omni.toml"
f="$(write_config "DOTFILES_OMNISHELL_CONFIG=\"$TMP/omni.toml\"")"
load_config "$f"; rc=$?
assert_eq "$rc" 0
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `lib/config.sh: No such file or directory`, then `FAIL: missing default config file means defaults`.

- [ ] **Step 3: Implement `lib/config.sh`**

```bash
#!/usr/bin/env bash
# Per-machine config for bootstrap.sh: defaults, loading the config file, and
# validation. Sourced; needs lib/cli.sh (select_steps) loaded first.
#
# The config file is plain bash (see config.example.sh) and is sourced, so it
# must be the user's own file - it is never part of the repo.

default_config_path() {
  echo "${XDG_CONFIG_HOME:-$HOME/.config}/macos-base-config/config.sh"
}

# expand_home VALUE -> VALUE with a leading "~" replaced by $HOME
# (for values written in quotes, where the shell didn't expand it)
expand_home() {
  case "$1" in
    "~") echo "$HOME" ;;
    "~/"*) echo "$HOME/${1#"~/"}" ;;
    *) echo "$1" ;;
  esac
}

# load_config [PATH] -> sets BOOTSTRAP_STEPS, BOOTSTRAP_SKIP and the DOTFILES_*
# values. Without PATH the default file is used if it exists. Return 2 on a
# missing explicit file, a syntax error, or an invalid value.
load_config() {
  local config_file="${1:-}"
  BOOTSTRAP_STEPS=""; BOOTSTRAP_SKIP=""
  DOTFILES_DIR=""; DOTFILES_URL=""; DOTFILES_ASSUME_YES=0
  DOTFILES_TERMINALS=""; DOTFILES_OMNISHELL_CONFIG=""

  if [ -n "$config_file" ]; then
    [ -f "$config_file" ] || { echo "bootstrap.sh: config file not found: $config_file" >&2; return 2; }
  else
    config_file="$(default_config_path)"
    [ -f "$config_file" ] || return 0
  fi
  "$BASH" -n "$config_file" || { echo "bootstrap.sh: syntax error in config: $config_file" >&2; return 2; }
  # shellcheck source=/dev/null
  . "$config_file"
  validate_config "$config_file"
}

# validate_config FILE -> normalises paths, checks every value; return 2 on error
validate_config() {
  local config_file="$1"
  DOTFILES_DIR="$(expand_home "$DOTFILES_DIR")"
  DOTFILES_OMNISHELL_CONFIG="$(expand_home "$DOTFILES_OMNISHELL_CONFIG")"

  if ! select_steps "$BOOTSTRAP_STEPS" "$BOOTSTRAP_SKIP" >/dev/null; then
    echo "  in $config_file (BOOTSTRAP_STEPS / BOOTSTRAP_SKIP)" >&2
    return 2
  fi
  case "$DOTFILES_ASSUME_YES" in
    0 | 1) ;;
    *) echo "bootstrap.sh: $config_file: DOTFILES_ASSUME_YES must be 0 or 1, got '$DOTFILES_ASSUME_YES'" >&2
       return 2 ;;
  esac
  if [ -n "$DOTFILES_OMNISHELL_CONFIG" ] && { [ ! -f "$DOTFILES_OMNISHELL_CONFIG" ] || [ ! -r "$DOTFILES_OMNISHELL_CONFIG" ]; }; then
    echo "bootstrap.sh: $config_file: DOTFILES_OMNISHELL_CONFIG is not a readable file: $DOTFILES_OMNISHELL_CONFIG" >&2
    return 2
  fi
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: last line `all 27 cases passed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/config.sh tests/bootstrap-test.sh
git commit -m "feat: load and validate a per-machine bootstrap config"
```

---

### Task 3: Step runner, non-dotfiles steps, new `bootstrap.sh`

**Files:**
- Create: `lib/steps.sh`
- Rewrite: `bootstrap.sh`
- Modify: `repos.txt`
- Modify: `tests/bootstrap-test.sh` (insert above the final line)

**Interfaces:**
- Consumes: everything from Tasks 1–2.
- Produces (in `lib/steps.sh`; globals it reads: `HERE`, `PARENT_DIR`, `DRY_RUN`, `NO_PULL`, config values):
  - `KARABINER_APP` (default `/Applications/Karabiner-Elements.app`, env-overridable).
  - `STEP_SKIP_REASON`, `STEP_FAIL_REASON` — reset by the runner before each step.
  - `skip REASON` → marks the current step skipped (step then `return 0`).
  - `run_cmd CMD...` → prints `+ CMD`, runs it unless dry run (git, cp, omnishell).
  - `show_cmd CMD...` → prints `+ CMD`, always runs it.
  - `run_in DIR CMD...` → runs CMD from DIR, appending `--dry-run` in dry mode; a missing DIR is fine in dry mode (clone only announced), an error otherwise.
  - `sibling_url NAME` → URL for NAME from `repos.txt`, empty if absent.
  - `sibling_dir NAME` → `$DOTFILES_DIR` for `dotfiles` when set, else `$PARENT_DIR/NAME`.
  - `dotfiles_url` → `$DOTFILES_URL` if set, else `sibling_url dotfiles`.
  - `ensure_sibling NAME URL DIR` → clone if missing; pull once per run unless `--no-pull`; pull failure = warning + return 0; clone failure = return 1.
  - `has_jetbrains_config` → 0 if a PhpStorm*/IntelliJIdea* config dir exists under `$HOME`.
  - `step_repos`, `step_karabiner`, `step_macos`, `step_jetbrains`, `step_vscode`, `step_manual` (Task 4 adds `step_dotfiles`).
- Produces (test harness): `make_sandbox` (sets `SB`, `APP`, `LOG`), `stub PATH LABEL [EXIT]`, `stub_sibling NAME [SCRIPT [EXIT]]`, `with_jetbrains`, `sandbox_config LINE...` (writes the default config inside the fake HOME), `run_bootstrap ARG...` (sets `OUT`, `RC`), `headers` (prints the `== step` headers of `$OUT` on one line).

- [ ] **Step 1: Write the failing end-to-end tests**

Insert above `echo "all $COUNT cases passed"`:

```bash
# --- end to end: bootstrap.sh in a sandbox ----------------------------------
# stub PATH LABEL [EXIT] -> executable that appends "LABEL <args>" to $LOG
stub() {
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/bash\necho "%s $*" >> "%s"\nexit %s\n' "$2" "$LOG" "${3:-0}" > "$1"
  chmod +x "$1"
}

# stub_sibling NAME [SCRIPT [EXIT]] -> fake cloned sibling, optional stub script
stub_sibling() {
  mkdir -p "$SB/parent/$1/.git"
  if [ -n "${2:-}" ]; then stub "$SB/parent/$1/$2" "$1/$2" "${3:-0}"; fi
}

# make_sandbox -> fresh sandbox; sets SB (root), APP (the repo copy), LOG
make_sandbox() {
  SB="$(mktemp -d "$TMP/sb.XXXXXX")"
  APP="$SB/parent/macos-base-config"
  LOG="$SB/calls.log"
  mkdir -p "$APP" "$SB/home" "$SB/bin" "$SB/Karabiner-Elements.app"
  : > "$LOG"
  cp -R "$REPO/bootstrap.sh" "$REPO/lib" "$REPO/repos.txt" "$APP/"
  stub "$APP/ide-keymaps/apply.sh" jetbrains-apply
  stub "$APP/ide-keymaps/port-vscode.sh" port-vscode
  local tool
  for tool in git brew python3 omnishell; do stub "$SB/bin/$tool" "$tool"; done
  stub_sibling swiss-windows-keyboard-layout-macos
  stub_sibling karabiner-windows-keyboard-mapping-macos apply.sh
  stub_sibling intelli-key-port
  stub_sibling dotfiles bootstrap.sh
}

with_jetbrains() { mkdir -p "$SB/home/Library/Application Support/JetBrains/PhpStorm2026.1"; }

# sandbox_config LINE... -> the default config file inside the fake HOME
sandbox_config() {
  mkdir -p "$SB/home/.config/macos-base-config"
  printf '%s\n' "$@" > "$SB/home/.config/macos-base-config/config.sh"
}

# run_bootstrap ARG... -> OUT (stdout + stderr), RC. stdin is /dev/null.
run_bootstrap() {
  OUT="$(env -u XDG_CONFIG_HOME -u DOTFILES_TERMINALS HOME="$SB/home" \
    PATH="$SB/bin:/usr/bin:/bin" KARABINER_APP="$SB/Karabiner-Elements.app" \
    /bin/bash "$APP/bootstrap.sh" "$@" 2>&1 </dev/null)"
  RC=$?
}

# headers -> the "== <step>" headers of $OUT on one line
headers() { printf '%s\n' "$OUT" | grep -o '^== [a-z]*' | tr '\n' ' '; }

it "--list and --help exit 0"
make_sandbox
run_bootstrap --list
assert_eq "$RC" 0
assert_contains "$OUT" "dotfiles"
run_bootstrap --help
assert_eq "$RC" 0
assert_contains "$OUT" "--skip"

it "unknown step aborts before any step runs"
make_sandbox
run_bootstrap macos bogus
assert_eq "$RC" 2
assert_contains "$OUT" "unknown step: bogus"
assert_eq "$(headers)" ""
assert_eq "$(cat "$LOG")" ""

it "unknown option is exit 2"
make_sandbox
run_bootstrap --bogus
assert_eq "$RC" 2

it "steps run in table order with a summary"
make_sandbox
run_bootstrap --no-pull manual macos
assert_eq "$RC" 0
assert_eq "$(headers)" "== macos == manual == summary "
assert_contains "$OUT" "  macos      ok"
assert_contains "$OUT" "  manual     ok"
assert_contains "$(cat "$LOG")" "python3 macos-defaults.py"

it "dry run hands --dry-run to every sub-tool and runs no git"
make_sandbox
with_jetbrains
run_bootstrap --dry-run --skip dotfiles
assert_eq "$RC" 0
log="$(cat "$LOG")"
assert_contains "$log" "karabiner-windows-keyboard-mapping-macos/apply.sh --dry-run"
assert_contains "$log" "python3 macos-defaults.py --dry-run"
assert_contains "$log" "jetbrains-apply --dry-run"
assert_contains "$log" "port-vscode --dry-run"
assert_not_contains "$log" "git "
while IFS= read -r line; do assert_contains "$line" "--dry-run"; done < "$LOG"
assert_contains "$OUT" "+ git -C $SB/parent/intelli-key-port pull --ff-only"
assert_contains "$OUT" "(dry run)"

it "dry run announces a clone for a missing sibling"
make_sandbox
rm -rf "$SB/parent/intelli-key-port"
run_bootstrap --dry-run repos
assert_eq "$RC" 0
assert_contains "$OUT" "+ git clone git@github.com:JtheGunner/intelli-key-port.git $SB/parent/intelli-key-port"
assert_eq "$(cat "$LOG")" ""

it "missing siblings are cloned; git reading stdin doesn't eat repos.txt"
make_sandbox
rm -rf "$SB/parent/intelli-key-port" "$SB/parent/dotfiles"
printf '#!/bin/bash\ncat >/dev/null\necho "git $*" >> "%s"\n' "$LOG" > "$SB/bin/git"
run_bootstrap --no-pull repos
assert_eq "$RC" 0
log="$(cat "$LOG")"
assert_contains "$log" "git clone git@github.com:JtheGunner/intelli-key-port.git $SB/parent/intelli-key-port"
assert_contains "$log" "git clone git@github.com:JtheGunner/dotfiles.git $SB/parent/dotfiles"

it "--no-pull leaves existing siblings alone"
make_sandbox
run_bootstrap --no-pull repos
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" ""

it "each sibling is pulled once per run"
make_sandbox
with_jetbrains
run_bootstrap repos vscode
assert_eq "$RC" 0
assert_eq "$(grep -c 'intelli-key-port pull' "$LOG")" 1

it "a failed pull only warns"
make_sandbox
stub "$SB/bin/git" git 1
run_bootstrap repos
assert_eq "$RC" 0
assert_contains "$OUT" "warn: pull failed"
assert_contains "$OUT" "  repos      ok"

it "a failed clone fails the step"
make_sandbox
rm -rf "$SB/parent/intelli-key-port"
stub "$SB/bin/git" git 128
run_bootstrap repos
assert_eq "$RC" 1
assert_contains "$OUT" "  repos      failed"

it "jetbrains and vscode skip without a JetBrains config"
make_sandbox
run_bootstrap --no-pull keymaps
assert_eq "$RC" 0
assert_contains "$OUT" "  jetbrains  skipped  (no JetBrains config yet"
assert_contains "$OUT" "  vscode     skipped  (no JetBrains config yet"
assert_eq "$(cat "$LOG")" ""

it "keymaps run when a JetBrains config exists"
make_sandbox
with_jetbrains
run_bootstrap --no-pull keymaps
assert_eq "$RC" 0
assert_contains "$(cat "$LOG")" "jetbrains-apply"
assert_contains "$(cat "$LOG")" "port-vscode"

it "karabiner skips when Karabiner-Elements is missing"
make_sandbox
rmdir "$SB/Karabiner-Elements.app"
run_bootstrap --no-pull karabiner
assert_eq "$RC" 0
assert_contains "$OUT" "  karabiner  skipped  (Karabiner-Elements not installed"
assert_eq "$(cat "$LOG")" ""

it "a failing step is reported, later steps still run, exit 1"
make_sandbox
stub_sibling karabiner-windows-keyboard-mapping-macos apply.sh 3
run_bootstrap --no-pull karabiner macos
assert_eq "$RC" 1
assert_contains "$OUT" "  karabiner  failed   (exit 3)"
assert_contains "$OUT" "  macos      ok"

it "config steps are the default; CLI steps replace them; skips add up"
make_sandbox
sandbox_config 'BOOTSTRAP_STEPS="macos manual"' 'BOOTSTRAP_SKIP="manual"'
run_bootstrap --no-pull
assert_eq "$(headers)" "== macos == summary "
run_bootstrap --no-pull repos manual
assert_eq "$(headers)" "== repos == summary "
run_bootstrap --no-pull --skip macos
assert_eq "$RC" 0
assert_contains "$OUT" "nothing to do"

it "an invalid config aborts with exit 2"
make_sandbox
run_bootstrap --config "$SB/missing.sh"
assert_eq "$RC" 2
sandbox_config 'BOOTSTRAP_STEPS="bogus"'
run_bootstrap
assert_eq "$RC" 2
assert_eq "$(cat "$LOG")" ""
```

- [ ] **Step 2: Run them to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: --list and --help exit 0` (the old `bootstrap.sh` ignores `--list` and doesn't source `lib/`).

- [ ] **Step 3: Update `repos.txt`**

Replace the whole file with:

```text
# Sibling repos bootstrap.sh clones/pulls next to this repo (into its parent
# folder, wherever that is). Format:  <dir-name>  <git-url>
# What runs from each one is a named step in lib/steps.sh (see --list).
# dotfiles: DOTFILES_DIR / DOTFILES_URL in the config override this entry.

swiss-windows-keyboard-layout-macos       git@github.com:JtheGunner/swiss-windows-keyboard-layout-macos.git
karabiner-windows-keyboard-mapping-macos  git@github.com:JtheGunner/karabiner-windows-keyboard-mapping-macos.git
intelli-key-port                          git@github.com:JtheGunner/intelli-key-port.git
dotfiles                                  git@github.com:JtheGunner/dotfiles.git
```

- [ ] **Step 4: Implement `lib/steps.sh`**

```bash
#!/usr/bin/env bash
# The steps bootstrap.sh runs, one step_<name> function each (names match
# ALL_STEPS in lib/cli.sh), plus the helpers they share. Sourced.
#
# A step returns 0 (ok) or non-zero (failed). To report "skipped", it calls
# skip "<reason>" and returns 0. STEP_FAIL_REASON overrides the default
# "exit <n>" in the summary.
#
# Reads the globals bootstrap.sh sets: HERE, PARENT_DIR, DRY_RUN, NO_PULL, and
# the config values from lib/config.sh.

# overridable so tests can point it into a sandbox
KARABINER_APP="${KARABINER_APP:-/Applications/Karabiner-Elements.app}"
STEP_SKIP_REASON=""
STEP_FAIL_REASON=""
PULLED_DIRS=""

skip() { STEP_SKIP_REASON="$1"; }

# run_cmd CMD... -> print, then run unless dry run (for commands that change
# state and have no dry-run mode of their own: git, cp, omnishell)
run_cmd() { echo "+ $*"; $DRY_RUN || "$@"; }

# show_cmd CMD... -> print, then always run
show_cmd() { echo "+ $*"; "$@"; }

# run_in DIR CMD... -> run CMD from DIR; in dry run CMD gets --dry-run. A DIR
# that doesn't exist yet is fine in dry run (its clone was only announced).
run_in() {
  local dir="$1"
  shift
  if $DRY_RUN; then set -- "$@" --dry-run; fi
  if [ ! -d "$dir" ]; then
    echo "+ (cd $dir && $*)"
    $DRY_RUN && return 0
    echo "  missing $dir" >&2
    return 1
  fi
  ( cd "$dir" && show_cmd "$@" )
}

# sibling_url NAME -> the git URL for NAME in repos.txt, empty if absent
sibling_url() {
  awk -v name="$1" '$1 == name { print $2; exit }' "$HERE/repos.txt"
}

# sibling_dir NAME -> where the sibling lives (DOTFILES_DIR wins for dotfiles)
sibling_dir() {
  if [ "$1" = dotfiles ] && [ -n "$DOTFILES_DIR" ]; then
    echo "$DOTFILES_DIR"
  else
    echo "$PARENT_DIR/$1"
  fi
}

dotfiles_url() {
  if [ -n "$DOTFILES_URL" ]; then echo "$DOTFILES_URL"; else sibling_url dotfiles; fi
}

# ensure_sibling NAME URL DIR -> clone DIR if missing, else pull it (once per
# run, unless --no-pull). A failed pull warns and keeps the existing checkout;
# a failed clone returns 1.
ensure_sibling() {
  local name="$1" url="$2" dir="$3"
  if [ -d "$dir/.git" ]; then
    $NO_PULL && return 0
    case "$PULLED_DIRS" in *"|$dir|"*) return 0 ;; esac
    PULLED_DIRS="$PULLED_DIRS|$dir|"
    run_cmd git -C "$dir" pull --ff-only ||
      echo "  warn: pull failed in $dir - using the existing checkout" >&2
    return 0
  fi
  if [ -z "$url" ]; then
    echo "  no git URL for $name in repos.txt" >&2
    return 1
  fi
  run_cmd git clone "$url" "$dir"
}

has_jetbrains_config() {
  find "$HOME/Library/Application Support/JetBrains" -maxdepth 1 \
    \( -name 'PhpStorm*' -o -name 'IntelliJIdea*' \) 2>/dev/null | grep -q .
}

step_repos() {
  local name url _rest failed=0
  # repos.txt on fd 3: a git that reads stdin (credential / host-key prompt)
  # must not swallow the remaining lines
  while read -r name url _rest <&3; do
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    [ "$name" = dotfiles ] && url="$(dotfiles_url)"
    ensure_sibling "$name" "$url" "$(sibling_dir "$name")" || failed=1
  done 3< "$HERE/repos.txt"
  return $failed
}

step_karabiner() {
  local name=karabiner-windows-keyboard-mapping-macos
  local dir="$PARENT_DIR/$name"
  if [ ! -d "$KARABINER_APP" ]; then
    skip "Karabiner-Elements not installed - run $dir/setup.sh first"
    return 0
  fi
  ensure_sibling "$name" "$(sibling_url "$name")" "$dir" || return 1
  run_in "$dir" ./apply.sh
}

step_macos() {
  run_in "$HERE" python3 macos-defaults.py
}

step_jetbrains() {
  if ! has_jetbrains_config; then
    skip "no JetBrains config yet - start PhpStorm once, then run: ./bootstrap.sh keymaps"
    return 0
  fi
  run_in "$HERE/ide-keymaps" ./apply.sh
}

step_vscode() {
  if ! has_jetbrains_config; then
    skip "no JetBrains config yet - start PhpStorm once, then run: ./bootstrap.sh keymaps"
    return 0
  fi
  ensure_sibling intelli-key-port "$(sibling_url intelli-key-port)" "$PARENT_DIR/intelli-key-port" || return 1
  run_in "$HERE/ide-keymaps" ./port-vscode.sh
}

step_manual() {
  echo "  - Karabiner permissions: karabiner-windows-keyboard-mapping-macos/setup.sh prints them"
  echo "  - Swiss keyboard layout: swiss-windows-keyboard-layout-macos/README.md"
  echo "  - PhpStorm: Settings > Tools > Terminal > 'Use Option as Meta key' off (AltGr in the console)"
  echo "  - see README.md 'Manual steps' (VoiceOver off, Gatekeeper, AltTab, uBar)"
}
```

- [ ] **Step 5: Rewrite `bootstrap.sh`**

```bash
#!/usr/bin/env bash
# Set up a fresh Mac: keyboard layout, Karabiner, macOS defaults, IDE keymaps
# and the dotfiles (shell, git, tmux, Ghostty).
#
#   ./bootstrap.sh                   run every step
#   ./bootstrap.sh keymaps dotfiles  run only these steps
#   ./bootstrap.sh --skip dotfiles   run every step but these
#   ./bootstrap.sh --dry-run         show what would happen
#   ./bootstrap.sh --help            all options; --list for the steps
#
# Per-machine settings: ~/.config/macos-base-config/config.sh (see
# config.example.sh). Each step is best-effort: a failing step is reported in
# the summary, it doesn't abort the rest. Re-runnable.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# sibling repos live next to this one, wherever it was cloned
PARENT_DIR="$(cd "$HERE/.." && pwd)"

. "$HERE/lib/cli.sh"
. "$HERE/lib/config.sh"
. "$HERE/lib/steps.sh"

parse_args "$@" || exit 2
case "$ACTION" in
  help) usage; exit 0 ;;
  list) print_step_list; exit 0 ;;
esac
load_config "$CONFIG_PATH" || exit 2

# command-line steps replace the configured default; --skip adds to the config's
SELECTED="$(select_steps "${CLI_STEPS:-$BOOTSTRAP_STEPS}" "$BOOTSTRAP_SKIP $CLI_SKIP")" || exit 2
if [ -z "$SELECTED" ]; then
  echo "nothing to do (every step skipped)"
  exit 0
fi

SUMMARY=""
ANY_FAILED=false

# record STEP STATUS [REASON] -> one summary line
record() {
  local line
  if [ -n "${3:-}" ]; then
    line="$(printf '  %-10s %-8s (%s)' "$1" "$2" "$3")"
  else
    line="$(printf '  %-10s %s' "$1" "$2")"
  fi
  SUMMARY="$SUMMARY$line"$'\n'
}

for step in $SELECTED; do
  echo
  echo "== $step: $(step_description "$step")"
  STEP_SKIP_REASON=""
  STEP_FAIL_REASON=""
  if "step_$step"; then
    if [ -n "$STEP_SKIP_REASON" ]; then
      echo "  -> skipped: $STEP_SKIP_REASON"
      record "$step" skipped "$STEP_SKIP_REASON"
    else
      record "$step" ok
    fi
  else
    rc=$?
    ANY_FAILED=true
    record "$step" failed "${STEP_FAIL_REASON:-exit $rc}"
  fi
done

echo
echo "== summary"
printf '%s' "$SUMMARY"
$DRY_RUN && echo $'\n(dry run)'
$ANY_FAILED && exit 1
exit 0
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: last line `all 44 cases passed`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/steps.sh bootstrap.sh repos.txt tests/bootstrap-test.sh
git commit -m "feat: run bootstrap as named, individually selectable steps"
```

---

### Task 4: The `dotfiles` step

**Files:**
- Modify: `lib/steps.sh` (add `step_dotfiles` between `step_vscode` and `step_manual`)
- Modify: `tests/bootstrap-test.sh` (insert above the final line)

**Interfaces:**
- Consumes: `ensure_sibling`, `sibling_dir`, `dotfiles_url`, `run_cmd`, `STEP_FAIL_REASON` (Task 3); `DOTFILES_*` (Task 2); sandbox helpers (Task 3).
- Produces: `step_dotfiles`.

- [ ] **Step 1: Write the failing dotfiles tests**

Insert above `echo "all $COUNT cases passed"`:

```bash
# --- the dotfiles step ------------------------------------------------------
# dotfiles_stub [EXIT] -> dotfiles/bootstrap.sh stub that also logs the
# DOTFILES_TERMINALS it was given
dotfiles_stub() {
  printf '#!/bin/bash\necho "dotfiles/bootstrap.sh terminals=[$DOTFILES_TERMINALS] $*" >> "%s"\nexit %s\n' \
    "$LOG" "${1:-0}" > "$SB/parent/dotfiles/bootstrap.sh"
  chmod +x "$SB/parent/dotfiles/bootstrap.sh"
}

it "dotfiles runs its bootstrap, terminals passed, no --yes by default"
make_sandbox
dotfiles_stub
sandbox_config 'DOTFILES_TERMINALS="kitty"'
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "dotfiles/bootstrap.sh terminals=[kitty] "
assert_contains "$OUT" "  dotfiles   ok"

it "DOTFILES_ASSUME_YES=1 passes --yes"
make_sandbox
dotfiles_stub
sandbox_config 'DOTFILES_ASSUME_YES=1'
run_bootstrap --no-pull dotfiles
assert_eq "$(cat "$LOG")" "dotfiles/bootstrap.sh terminals=[] --yes"

it "a failing dotfiles bootstrap fails only that step"
make_sandbox
dotfiles_stub 1
run_bootstrap --no-pull dotfiles manual
assert_eq "$RC" 1
assert_contains "$OUT" "  dotfiles   failed   (exit 1)"
assert_contains "$OUT" "  manual     ok"

it "dotfiles without Homebrew fails with a hint"
make_sandbox
rm "$SB/bin/brew"
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 1
assert_contains "$OUT" "Homebrew required"
assert_eq "$(cat "$LOG")" ""

it "own omnishell config is copied after the dotfiles run, then applied"
make_sandbox
echo 'x = 1' > "$SB/omni.toml"
sandbox_config "DOTFILES_OMNISHELL_CONFIG=\"$SB/omni.toml\""
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 0
assert_eq "$(cat "$SB/home/.config/omnishell/config.toml")" "x = 1"
assert_eq "$(head -1 "$LOG")" "dotfiles/bootstrap.sh "
assert_eq "$(tail -1 "$LOG")" "omnishell apply -y"

it "a failing omnishell apply fails the step"
make_sandbox
echo 'x = 1' > "$SB/omni.toml"
sandbox_config "DOTFILES_OMNISHELL_CONFIG=\"$SB/omni.toml\""
stub "$SB/bin/omnishell" omnishell 1
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 1
assert_contains "$OUT" "  dotfiles   failed   (omnishell config)"

it "dry run shows the dotfiles commands but runs nothing"
make_sandbox
echo 'x = 1' > "$SB/omni.toml"
sandbox_config "DOTFILES_OMNISHELL_CONFIG=\"$SB/omni.toml\"" 'DOTFILES_ASSUME_YES=1'
run_bootstrap --dry-run --no-pull dotfiles
assert_eq "$RC" 0
assert_contains "$OUT" "bash $SB/parent/dotfiles/bootstrap.sh --yes"
assert_contains "$OUT" "+ omnishell apply -y"
assert_eq "$(cat "$LOG")" ""
[ -e "$SB/home/.config/omnishell/config.toml" ] && fail "config copied in dry run"

it "DOTFILES_DIR with spaces and ~ is used, cloned from DOTFILES_URL"
make_sandbox
sandbox_config 'DOTFILES_DIR="~/my dots"' 'DOTFILES_URL="https://example.invalid/fork.git"'
run_bootstrap --dry-run dotfiles
assert_eq "$RC" 0
assert_contains "$OUT" "+ git clone https://example.invalid/fork.git $SB/home/my dots"
assert_contains "$OUT" "bash $SB/home/my dots/bootstrap.sh"
run_bootstrap --dry-run repos
assert_contains "$OUT" "+ git clone https://example.invalid/fork.git $SB/home/my dots"
assert_not_contains "$OUT" "$SB/parent/dotfiles"
```

- [ ] **Step 2: Run them to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: dotfiles runs its bootstrap, …` (`step_dotfiles: command not found`, summary `dotfiles failed (exit 127)`).

- [ ] **Step 3: Implement `step_dotfiles`**

Add to `lib/steps.sh` between `step_vscode` and `step_manual`:

```bash
step_dotfiles() {
  local dir omnishell_target rc=0
  dir="$(sibling_dir dotfiles)"
  ensure_sibling dotfiles "$(dotfiles_url)" "$dir" || return 1
  if ! command -v brew >/dev/null 2>&1; then
    echo "  Homebrew required - install it first (README: Apps)" >&2
    STEP_FAIL_REASON="Homebrew missing"
    return 1
  fi

  # dotfiles/bootstrap.sh has no dry-run mode: only show the command then.
  # It runs with set -e in its own process; its exit code decides the step.
  set --
  [ "$DOTFILES_ASSUME_YES" = 1 ] && set -- --yes
  echo "+ DOTFILES_TERMINALS=\"$DOTFILES_TERMINALS\" bash $dir/bootstrap.sh $*"
  if ! $DRY_RUN; then
    DOTFILES_TERMINALS="$DOTFILES_TERMINALS" bash "$dir/bootstrap.sh" "$@" || rc=$?
    if [ "$rc" -ne 0 ]; then
      STEP_FAIL_REASON="exit $rc"
      return 1
    fi
  fi

  [ -n "$DOTFILES_OMNISHELL_CONFIG" ] || return 0
  # after the dotfiles bootstrap, which installs the repo's own copy every run
  omnishell_target="${XDG_CONFIG_HOME:-$HOME/.config}/omnishell/config.toml"
  if ! { run_cmd mkdir -p "$(dirname "$omnishell_target")" &&
    run_cmd cp "$DOTFILES_OMNISHELL_CONFIG" "$omnishell_target" &&
    run_cmd omnishell apply -y; }; then
    STEP_FAIL_REASON="omnishell config"
    return 1
  fi
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: last line `all 52 cases passed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/steps.sh tests/bootstrap-test.sh
git commit -m "feat: run the dotfiles bootstrap as a default step"
```

---

### Task 5: `config.example.sh` and README

**Files:**
- Create: `config.example.sh`
- Modify: `README.md`
- Modify: `tests/bootstrap-test.sh` (insert above the final line)

**Interfaces:**
- Consumes: `load_config`, `TMP` (Task 2).

- [ ] **Step 1: Write the failing test**

Insert above `echo "all $COUNT cases passed"`:

```bash
# --- config.example.sh ------------------------------------------------------
it "config.example.sh is a valid config with the defaults"
load_config "$REPO/config.example.sh"; rc=$?
assert_eq "$rc" 0
assert_eq "$BOOTSTRAP_STEPS|$BOOTSTRAP_SKIP|$DOTFILES_DIR|$DOTFILES_URL|$DOTFILES_ASSUME_YES|$DOTFILES_TERMINALS|$DOTFILES_OMNISHELL_CONFIG" "||||0||"
for key in BOOTSTRAP_STEPS BOOTSTRAP_SKIP DOTFILES_DIR DOTFILES_URL DOTFILES_ASSUME_YES DOTFILES_TERMINALS DOTFILES_OMNISHELL_CONFIG; do
  assert_contains "$(cat "$REPO/config.example.sh")" "$key="
done
```

- [ ] **Step 2: Run it to verify it fails**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: config.example.sh is a valid config with the defaults` (file not found, exit 2).

- [ ] **Step 3: Create `config.example.sh`**

```sh
# macos-base-config - per-machine settings for bootstrap.sh.
#
# Copy to ~/.config/macos-base-config/config.sh (or pass --config <path>) and
# edit. Plain bash, sourced by bootstrap.sh. Every key is optional; an empty
# value means the default. Steps named on the command line replace
# BOOTSTRAP_STEPS; --skip adds to BOOTSTRAP_SKIP.

# Steps to run when none are given, e.g. "keymaps dotfiles".
# Empty = every step. See ./bootstrap.sh --list.
BOOTSTRAP_STEPS=""

# Steps (or aliases) never to run on this machine, e.g. "karabiner".
BOOTSTRAP_SKIP=""

# --- dotfiles step ------------------------------------------------------------

# Checkout to use, cloned there if missing. Empty = next to this repo
# (<parent>/dotfiles). Point it at an existing checkout, e.g. "~/Git/dotfiles".
DOTFILES_DIR=""

# Clone URL when DOTFILES_DIR doesn't exist yet. Empty = the URL in repos.txt.
DOTFILES_URL=""

# 1 = run dotfiles/bootstrap.sh with --yes: repoint stow links that belong to
# another checkout without asking. 0 = ask.
DOTFILES_ASSUME_YES=0

# Extra terminal stow packages, handed to dotfiles/bootstrap.sh.
DOTFILES_TERMINALS=""

# Own omnishell config.toml. Copied to ~/.config/omnishell/config.toml after
# the dotfiles bootstrap (which installs the repo's copy every run), then
# applied with "omnishell apply -y". Empty = keep the dotfiles repo's config.
DOTFILES_OMNISHELL_CONFIG=""
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: last line `all 53 cases passed`.

- [ ] **Step 5: Update `README.md`**

Follow the house style already used in the file (emoji `##` headings, `---` between sections, emoji column in tables). Make exactly these edits:

(a) Tagline paragraph under the title: replace
`One bootstrap for the keyboard layout, the Karabiner remaps, the IDE keymaps and the few macOS tweaks that go with them.`
with
`One bootstrap for the keyboard layout, the Karabiner remaps, the IDE keymaps, the few macOS tweaks that go with them, and the shell dotfiles.`
Append ` &nbsp;→&nbsp; <code>🐚 dotfiles</code>` to the flow line.

(b) Quick start code block: replace it with

```sh
cd ~/code                   # any folder works
git clone git@github.com:JtheGunner/macos-base-config.git
cd macos-base-config
./bootstrap.sh --dry-run    # see what would happen
./bootstrap.sh              # every step
./bootstrap.sh keymaps      # only some steps
./bootstrap.sh --skip dotfiles
```

(c) Sibling tree in the NOTE callout: replace its last line
`> └── intelli-key-port/` with these two lines:
```text
> ├── intelli-key-port/
> └── dotfiles/                                   ← or DOTFILES_DIR, see Configuration
```

(d) Replace the sentence after the callout and the flow diagram with:

`bootstrap.sh` is best-effort and re-runnable: a failing step is reported in the summary at the end (exit code 1), it never aborts the rest.

```text
 ./bootstrap.sh [step ...]
   │
   ├─ repos       clone / pull each sibling repo (repos.txt) into the parent folder
   ├─ karabiner   Karabiner config → ~/.config/karabiner   (skipped until Karabiner is installed)
   ├─ macos       macos-defaults.py: system hotkeys, Finder shortcut, font smoothing
   ├─ jetbrains   JetBrains keymap → IDE config, set active (skipped until PhpStorm has a config)
   ├─ vscode      same keymap → VS Code / Antigravity         (same condition)
   ├─ dotfiles    the dotfiles repo's own bootstrap.sh: shell, prompt, git, tmux, Ghostty
   ├─ manual      print the manual steps
   └─ summary     ok / skipped / failed per step
```

(e) Replace the IMPORTANT callout with:

> [!IMPORTANT]
> On a fresh Mac the `karabiner` step is skipped until Karabiner-Elements is
> installed. Run `../karabiner-windows-keyboard-mapping-macos/setup.sh` (it
> installs Karabiner via Homebrew and walks you through its permissions), then
> `./bootstrap.sh karabiner`. The `dotfiles` step needs Homebrew as well.

(f) Insert two new sections right after the Quick start section (each preceded by `---`):

````markdown
## 🎛️ Steps and options

Name steps to run only those; they always run in the order below. With no
step named, every step runs.

|    | Step        | Runs                                                        |
|:--:|-------------|-------------------------------------------------------------|
| 📥 | `repos`     | clone missing / pull existing sibling repos                 |
| ⌨️ | `karabiner` | `karabiner-windows-keyboard-mapping-macos/apply.sh`         |
| 🛠️ | `macos`     | `macos-defaults.py`                                         |
| 🧠 | `jetbrains` | `ide-keymaps/apply.sh`                                      |
| 💻 | `vscode`    | `ide-keymaps/port-vscode.sh`                                |
| 🐚 | `dotfiles`  | `dotfiles/bootstrap.sh`                                     |
| ✋ | `manual`    | print the manual steps                                      |

`keymaps` is an alias for `jetbrains vscode`. A step that needs a sibling repo
clones it itself, so `./bootstrap.sh dotfiles` works on its own.

| Option            | Effect                                                          |
|-------------------|-----------------------------------------------------------------|
| `--skip <step>`   | skip a step or alias; repeatable                                |
| `--dry-run`       | show what would happen; sub-tools get `--dry-run`, no git, no dotfiles run |
| `--no-pull`       | don't update siblings that are already cloned                   |
| `--config <path>` | use this config file                                            |
| `--list`          | list the steps                                                  |
| `-h`, `--help`    | usage                                                           |

---

## ⚙️ Configuration

Per-machine settings live in `~/.config/macos-base-config/config.sh`, a plain
bash file that is **not** part of the repo. Start from the template:

```sh
mkdir -p ~/.config/macos-base-config
cp config.example.sh ~/.config/macos-base-config/config.sh
```

| Key                         | Default             | Effect                                                              |
|-----------------------------|---------------------|---------------------------------------------------------------------|
| `BOOTSTRAP_STEPS`           | all steps           | steps to run when none are named on the command line                |
| `BOOTSTRAP_SKIP`            | —                   | steps never to run on this machine                                  |
| `DOTFILES_DIR`              | `<parent>/dotfiles` | dotfiles checkout to use, e.g. an existing `~/Git/dotfiles`         |
| `DOTFILES_URL`              | URL in `repos.txt`  | clone URL, e.g. a fork                                              |
| `DOTFILES_ASSUME_YES`       | `0`                 | `1` = repoint stow links from another checkout without asking       |
| `DOTFILES_TERMINALS`        | —                   | extra terminal stow packages for the dotfiles bootstrap             |
| `DOTFILES_OMNISHELL_CONFIG` | —                   | own omnishell `config.toml`, applied after the dotfiles bootstrap   |

Steps named on the command line replace `BOOTSTRAP_STEPS`; `--skip` adds to
`BOOTSTRAP_SKIP`. An invalid config (syntax error, unknown step, bad value)
stops the bootstrap before any step runs.

> [!TIP]
> Already have the dotfiles checked out somewhere else? Set `DOTFILES_DIR` to
> that checkout. Otherwise the dotfiles bootstrap asks whether to repoint every
> stow link to the new `<parent>/dotfiles` clone.
````

(g) "What lives where" table, dotfiles row: change the Apply cell from
`its own `bootstrap.sh`, not part of this one` to
`its own `bootstrap.sh`: the `dotfiles` step runs it`.

(h) Manual steps section, first sentence: change
`` `bootstrap.sh` prints a reminder of these at the end. `` to
`` The `manual` step prints a reminder of these. ``

(i) Insert before the Apps section (preceded by `---`):

````markdown
## 🧪 Tests

```sh
/bin/bash tests/bootstrap-test.sh
```

Runs the argument parsing, config and step tests under macOS's bash 3.2. The
end-to-end cases run in a throwaway sandbox with stub tools, so nothing on
the machine changes.
````

- [ ] **Step 6: Check the README renders sensibly**

Run: `grep -n 'not part of this one' README.md` → expected: no output.
Run: `grep -c '^## ' README.md` → expected: 3 more than before the edit.

- [ ] **Step 7: Commit**

```bash
git add config.example.sh README.md tests/bootstrap-test.sh
git commit -m "docs: document bootstrap steps, options and configuration"
```

---

### Task 6: Final verification

- [ ] **Step 1: Full test run under bash 3.2**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all 53 cases passed`, exit 0.

- [ ] **Step 2: Syntax check every script**

Run: `for f in bootstrap.sh lib/*.sh config.example.sh tests/bootstrap-test.sh; do /bin/bash -n "$f" || echo "BAD $f"; done`
Expected: no output.

- [ ] **Step 3: Real-repo smoke checks (read-only)**

Run: `./bootstrap.sh --list` → the 7 steps + `keymaps`, exit 0.
Run: `./bootstrap.sh bogus; echo $?` → `unknown step: bogus`, `2`.
Do **not** run a real or `--dry-run` bootstrap from the worktree (its parent is `.worktrees/`).

- [ ] **Step 4: Walk the MBC-1 acceptance criteria**

Tick each against a test case or file: repos.txt entry, default dotfiles step, named steps + `--skip`, `--list`, `--help` + exit 2, fixed order, missing sibling cloned, config honoured / defaults without config, dry-run for dotfiles, dotfiles failure isolated, summary + exit 1, `DOTFILES_ASSUME_YES`, README, bash 3.2.
