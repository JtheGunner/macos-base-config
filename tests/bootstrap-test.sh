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

it "lists spanning several lines are read in full"
assert_eq "$(select_steps "keymaps
dotfiles" "")" "jetbrains vscode dotfiles"
assert_eq "$(select_steps "" "
  dotfiles
")" "repos karabiner macos jetbrains vscode manual"
assert_eq "$(select_steps "$(printf 'macos\tmanual')" "")" "macos manual"

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

it "load_config records the config file in use, even when absent"
XDG_CONFIG_HOME="$TMP/none" load_config ""
assert_eq "$CONFIG_FILE" "$TMP/none/macos-base-config/config.sh"
XDG_CONFIG_HOME="$TMP/xdg" load_config ""
assert_eq "$CONFIG_FILE" "$TMP/xdg/macos-base-config/config.sh"

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

it "DOTFILES_LOCAL_RC defaults to empty and loads several lines"
XDG_CONFIG_HOME="$TMP/none" load_config ""
assert_eq "$DOTFILES_LOCAL_RC" ""
f="$(write_config "DOTFILES_LOCAL_RC='" "alias a=b" "export X=1" "'")"
load_config "$f"; rc=$?
assert_eq "$rc" 0
assert_eq "$DOTFILES_LOCAL_RC" "
alias a=b
export X=1
"

it "DOTFILES_LOCAL_RC with a syntax error is exit 2"
f="$(write_config "DOTFILES_LOCAL_RC='if true; then'")"
out="$(load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "DOTFILES_LOCAL_RC has a syntax error"

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

it "manual step lists every manual hint"
make_sandbox
run_bootstrap manual
assert_eq "$RC" 0
assert_contains "$OUT" "Karabiner permissions"
assert_not_contains "$OUT" "kdash-token"

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

it "a failing dotfiles bootstrap explains the checkout prompt"
make_sandbox
dotfiles_stub 1
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 1
assert_contains "$OUT" "hint: if it stopped at \"repoint every stow link"
assert_contains "$OUT" "set DOTFILES_ASSUME_YES=1 in $SB/home/.config/macos-base-config/config.sh"
assert_contains "$OUT" "set DOTFILES_DIR in $SB/home/.config/macos-base-config/config.sh to the checkout the links already use"
assert_contains "$OUT" "  dotfiles   failed   (exit 1)"

it "the hint names --config's file and skips ASSUME_YES when already set"
make_sandbox
dotfiles_stub 1
printf 'DOTFILES_ASSUME_YES=1\n' > "$SB/own.sh"
run_bootstrap --no-pull --config "$SB/own.sh" dotfiles
assert_eq "$RC" 1
assert_contains "$OUT" "to the checkout the links already use"
assert_contains "$OUT" "$SB/own.sh"
assert_not_contains "$OUT" "set DOTFILES_ASSUME_YES=1"

it "no checkout hint when the dotfiles step succeeds or runs dry"
make_sandbox
dotfiles_stub
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 0
assert_not_contains "$OUT" "hint:"
dotfiles_stub 1
run_bootstrap --dry-run --no-pull dotfiles
assert_eq "$RC" 0
assert_not_contains "$OUT" "hint:"

it "dotfiles without Homebrew fails with a hint"
make_sandbox
rm "$SB/bin/brew"
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 1
assert_contains "$OUT" "Homebrew required"
assert_eq "$(cat "$LOG")" ""
assert_not_contains "$OUT" "hint:"

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
stub "$SB/bin/omnishell" omnishell 2
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 1
assert_contains "$OUT" "  dotfiles   failed   (omnishell apply exit 2)"
assert_not_contains "$OUT" "hint:"

it "omnishell apply exit 1 (degraded modules) only warns"
make_sandbox
echo 'x = 1' > "$SB/omni.toml"
sandbox_config "DOTFILES_OMNISHELL_CONFIG=\"$SB/omni.toml\""
stub "$SB/bin/omnishell" omnishell 1
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 0
assert_contains "$OUT" "degraded"
assert_contains "$OUT" "  dotfiles   ok"

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

# --- DOTFILES_LOCAL_RC -------------------------------------------------------
KDASH="alias kdash-token='kubectl -n kubernetes-dashboard create token admin-user'"
BLOCK_BEGIN="# >>> macos-base-config >>>"

# blocks FILE -> how many managed blocks FILE has
blocks() { grep -cxF "$BLOCK_BEGIN" "$1" || true; }

it "the local rc block lands in both rc.local files, other lines kept"
make_sandbox
echo 'export MINE=1' > "$SB/home/.zshrc.local"
sandbox_config "DOTFILES_LOCAL_RC=\"$KDASH\""
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 0
for rc in .zshrc.local .bashrc.local; do
  assert_contains "$(cat "$SB/home/$rc")" "$KDASH"
  assert_eq "$(blocks "$SB/home/$rc")" 1
done
assert_eq "$(head -1 "$SB/home/.zshrc.local")" "export MINE=1"

it "a new rc.local file is private"
assert_eq "$(stat -f %Lp "$SB/home/.bashrc.local")" 600

it "a re-run replaces the block instead of adding one"
sandbox_config 'DOTFILES_LOCAL_RC="alias k=kubectl"'
run_bootstrap --no-pull dotfiles
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 0
assert_eq "$(blocks "$SB/home/.zshrc.local")" 1
assert_contains "$(cat "$SB/home/.zshrc.local")" "alias k=kubectl"
assert_not_contains "$(cat "$SB/home/.zshrc.local")" "kdash-token"
assert_contains "$(cat "$SB/home/.zshrc.local")" "export MINE=1"

it "an empty DOTFILES_LOCAL_RC removes the block, keeps the rest"
sandbox_config 'DOTFILES_LOCAL_RC=""'
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 0
assert_eq "$(cat "$SB/home/.zshrc.local")" "export MINE=1"
assert_eq "$(blocks "$SB/home/.bashrc.local")" 0

it "no DOTFILES_LOCAL_RC creates no rc.local files"
make_sandbox
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 0
[ -e "$SB/home/.zshrc.local" ] && fail ".zshrc.local created"
[ -e "$SB/home/.bashrc.local" ] && fail ".bashrc.local created"

it "a symlinked rc.local stays a symlink"
make_sandbox
echo 'export MINE=1' > "$SB/real.zsh"
ln -s "$SB/real.zsh" "$SB/home/.zshrc.local"
sandbox_config "DOTFILES_LOCAL_RC=\"$KDASH\""
run_bootstrap --no-pull dotfiles
[ -L "$SB/home/.zshrc.local" ] || fail "symlink replaced"
assert_contains "$(cat "$SB/real.zsh")" "$KDASH"

it "the block is valid for bash and zsh"
bash -n "$SB/home/.bashrc.local" || fail "bash -n"
if command -v zsh >/dev/null 2>&1; then zsh -n "$SB/real.zsh" || fail "zsh -n"; fi

it "dry run announces the block but writes nothing"
make_sandbox
sandbox_config "DOTFILES_LOCAL_RC=\"$KDASH\""
run_bootstrap --dry-run --no-pull dotfiles
assert_eq "$RC" 0
assert_contains "$OUT" "+ update the macos-base-config block in $SB/home/.zshrc.local"
[ -e "$SB/home/.zshrc.local" ] && fail "written in dry run"

it "a failing dotfiles bootstrap leaves the rc.local files alone"
make_sandbox
dotfiles_stub 1
sandbox_config "DOTFILES_LOCAL_RC=\"$KDASH\""
run_bootstrap --no-pull dotfiles
assert_eq "$RC" 1
[ -e "$SB/home/.zshrc.local" ] && fail "written after a failed bootstrap"

# --- config.example.sh ------------------------------------------------------
it "config.example.sh is a valid config with the defaults"
load_config "$REPO/config.example.sh"; rc=$?
assert_eq "$rc" 0
assert_eq "$BOOTSTRAP_STEPS|$BOOTSTRAP_SKIP|$DOTFILES_DIR|$DOTFILES_URL|$DOTFILES_ASSUME_YES|$DOTFILES_TERMINALS|$DOTFILES_OMNISHELL_CONFIG" "||||0||"
assert_eq "$DOTFILES_LOCAL_RC" ""
for key in BOOTSTRAP_STEPS BOOTSTRAP_SKIP DOTFILES_DIR DOTFILES_URL DOTFILES_ASSUME_YES DOTFILES_TERMINALS DOTFILES_OMNISHELL_CONFIG DOTFILES_LOCAL_RC; do
  assert_contains "$(cat "$REPO/config.example.sh")" "$key="
done

it "the commented example in config.example.sh is a valid DOTFILES_LOCAL_RC"
example="$(sed -n "/^#   DOTFILES_LOCAL_RC='/,/^#   '\$/s/^#   //p" "$REPO/config.example.sh")"
assert_contains "$example" "kdash-token"
f="$(write_config "$example")"
load_config "$f"; rc=$?
assert_eq "$rc" 0
assert_contains "$DOTFILES_LOCAL_RC" "create token admin-user"

echo "all $COUNT cases passed"
