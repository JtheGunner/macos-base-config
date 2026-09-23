#!/bin/bash
# Tests for bootstrap.sh and lib/. Plain bash, no dependencies; meant to run
# under macOS /bin/bash 3.2 on purpose.
#
#   /bin/bash tests/bootstrap-test.sh
#
# End-to-end cases run bootstrap.sh inside a throwaway sandbox: a copy of the
# scripts next to stub sibling repos, a fake HOME, and stub tools (git, brew,
# python3, omnishell, curl, open, swift, sudo, spctl) that only log their
# arguments.
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
assert_eq "$(select_steps "" "")" "repos brew karabiner keyboard macos jetbrains vscode dotfiles manual"

it "steps run in table order, aliases expand"
assert_eq "$(select_steps "dotfiles keymaps" "")" "jetbrains vscode dotfiles"

it "skip removes steps, aliases included"
assert_eq "$(select_steps "" "keymaps dotfiles")" "repos brew karabiner keyboard macos manual"

it "duplicates collapse"
assert_eq "$(select_steps "macos macos keymaps jetbrains" "")" "macos jetbrains vscode"

it "extra whitespace is ignored"
assert_eq "$(select_steps "  macos   manual " "")" "macos manual"

it "lists spanning several lines are read in full"
assert_eq "$(select_steps "keymaps
dotfiles" "")" "jetbrains vscode dotfiles"
assert_eq "$(select_steps "" "
  dotfiles
")" "repos brew karabiner keyboard macos jetbrains vscode manual"
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
for s in repos brew karabiner keyboard macos jetbrains vscode dotfiles manual keymaps; do
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

it "BREW_BUNDLE_EXTRA must be a readable file; ~ is expanded"
f="$(write_config "BREW_BUNDLE_EXTRA=\"$TMP/nope.Brewfile\"")"
out="$(load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "BREW_BUNDLE_EXTRA is not a readable file"
mkdir -p "$TMP/home"
echo 'cask "firefox"' > "$TMP/home/Brewfile.local"
f="$(write_config 'BREW_BUNDLE_EXTRA="~/Brewfile.local"')"
HOME="$TMP/home" load_config "$f"; rc=$?
assert_eq "$rc" 0
assert_eq "$BREW_BUNDLE_EXTRA" "$TMP/home/Brewfile.local"

it "MACOS_DISABLE_GATEKEEPER must be 0 or 1, default 0"
XDG_CONFIG_HOME="$TMP/none" load_config ""
assert_eq "$MACOS_DISABLE_GATEKEEPER" 0
f="$(write_config 'MACOS_DISABLE_GATEKEEPER=yes')"
out="$(load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "MACOS_DISABLE_GATEKEEPER must be 0 or 1"
f="$(write_config 'MACOS_DISABLE_GATEKEEPER=1')"
load_config "$f"; rc=$?
assert_eq "$rc" 0
assert_eq "$MACOS_DISABLE_GATEKEEPER" 1

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

# --- macos-defaults.py ------------------------------------------------------
it "macos-defaults.py dry run disables the VoiceOver and space hotkeys"
mkdir -p "$TMP/fresh-home"
out="$(HOME="$TMP/fresh-home" python3 "$REPO/macos-defaults.py" --dry-run 2>&1)"; rc=$?
assert_eq "$rc" 0
assert_contains "$out" "symbolic hotkeys: would disable [59, 79, 80, 81, 82]"
[ -e "$TMP/fresh-home/Library/Preferences/com.apple.symbolichotkeys.plist" ] && fail "written in dry run"

# --- ide-keymaps/set-terminal-option.py -------------------------------------
TERMINAL_OPTION="$REPO/ide-keymaps/set-terminal-option.py"

it "set-terminal-option creates a missing terminal.xml"
f="$TMP/opt1/terminal.xml"
out="$(python3 "$TERMINAL_OPTION" "$f" useOptionAsMetaKey false 2>&1)"; rc=$?
assert_eq "$rc" 0
assert_contains "$(cat "$f")" '<component name="TerminalOptionsProvider">'
assert_contains "$(cat "$f")" '<option name="useOptionAsMetaKey" value="false" />'
assert_eq "$(ls "$TMP/opt1" | grep -c bak)" 0

it "set-terminal-option flips the value, keeps other options, backs up"
mkdir -p "$TMP/opt2"
f="$TMP/opt2/terminal.xml"
cat > "$f" <<'XML'
<application>
  <component name="TerminalOptionsProvider">
    <option name="shellPath" value="/bin/zsh" />
    <option name="useOptionAsMetaKey" value="true" />
  </component>
</application>
XML
out="$(python3 "$TERMINAL_OPTION" "$f" useOptionAsMetaKey false 2>&1)"; rc=$?
assert_eq "$rc" 0
assert_contains "$(cat "$f")" '<option name="useOptionAsMetaKey" value="false" />'
assert_contains "$(cat "$f")" '<option name="shellPath" value="/bin/zsh" />'
assert_not_contains "$(cat "$f")" 'value="true"'
assert_eq "$(ls "$TMP/opt2" | grep -c 'terminal.xml.bak-')" 1

it "set-terminal-option leaves a file that is already right alone"
before="$(cat "$f")"
out="$(python3 "$TERMINAL_OPTION" "$f" useOptionAsMetaKey false 2>&1)"; rc=$?
assert_eq "$rc" 0
assert_contains "$out" "already"
assert_eq "$(cat "$f")" "$before"
assert_eq "$(ls "$TMP/opt2" | grep -c 'terminal.xml.bak-')" 1

it "set-terminal-option dry run changes nothing"
mkdir -p "$TMP/opt3"
f="$TMP/opt3/terminal.xml"
printf '<application>\n</application>\n' > "$f"
out="$(python3 "$TERMINAL_OPTION" "$f" useOptionAsMetaKey false --dry-run 2>&1)"; rc=$?
assert_eq "$rc" 0
assert_contains "$out" "would set useOptionAsMetaKey=false"
assert_eq "$(cat "$f")" "<application>
</application>"
python3 "$TERMINAL_OPTION" "$TMP/opt4/terminal.xml" useOptionAsMetaKey false --dry-run >/dev/null
[ -e "$TMP/opt4" ] && fail "created in dry run"

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

# spctl_stub STATUS -> spctl that logs itself and prints STATUS for --status
spctl_stub() {
  printf '#!/bin/bash\necho "spctl $*" >> "%s"\n[ "$1" = --status ] && echo "%s"\nexit 0\n' \
    "$LOG" "$1" > "$SB/bin/spctl"
  chmod +x "$SB/bin/spctl"
}

# make_sandbox -> fresh sandbox; sets SB (root), APP (the repo copy), LOG
make_sandbox() {
  SB="$(mktemp -d "$TMP/sb.XXXXXX")"
  APP="$SB/parent/macos-base-config"
  LOG="$SB/calls.log"
  mkdir -p "$APP" "$SB/home/.config/karabiner" "$SB/bin" "$SB/Karabiner-Elements.app"
  : > "$LOG"
  cp -R "$REPO/bootstrap.sh" "$REPO/lib" "$REPO/repos.txt" "$REPO/Brewfile" "$APP/"
  stub "$APP/ide-keymaps/apply.sh" jetbrains-apply
  stub "$APP/ide-keymaps/port-vscode.sh" port-vscode
  local tool
  for tool in git brew python3 omnishell curl open swift sudo; do stub "$SB/bin/$tool" "$tool"; done
  spctl_stub "assessments enabled"
  stub_sibling swiss-windows-keyboard-layout-macos
  echo layout > "$SB/parent/swiss-windows-keyboard-layout-macos/CustomSwissGerman.keylayout"
  echo icon > "$SB/parent/swiss-windows-keyboard-layout-macos/CustomSwissGerman.icns"
  mkdir -p "$SB/system-layouts"
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
    BREW_CANDIDATES="$SB/homebrew/bin/brew" KARABINER_WAIT_SECONDS=0 \
    KEYBOARD_SYSTEM_DIR="$SB/system-layouts" SWIFT="${SWIFT_BIN:-$SB/bin/swift}" \
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
assert_contains "$OUT" "Input source"
assert_contains "$OUT" "password manager"
assert_not_contains "$OUT" "kdash-token"
assert_not_contains "$OUT" "uBar"
assert_not_contains "$OUT" "PhpStorm"
assert_not_contains "$OUT" "VoiceOver"
assert_not_contains "$OUT" "Gatekeeper"

it "manual step names the Gatekeeper confirmation only when opted in"
make_sandbox
sandbox_config 'MACOS_DISABLE_GATEKEEPER=1'
run_bootstrap manual
assert_contains "$OUT" "Gatekeeper"

it "brew runs right after repos"
make_sandbox
run_bootstrap --no-pull manual brew repos
assert_eq "$(headers)" "== repos == brew == manual == summary "

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
assert_contains "$OUT" "  karabiner  skipped  (Karabiner-Elements not installed - run ./bootstrap.sh brew"
assert_eq "$(cat "$LOG")" ""

it "karabiner opens the app once when its config dir is missing"
make_sandbox
rmdir "$SB/home/.config/karabiner"
printf '#!/bin/bash\necho "open $*" >> "%s"\nmkdir -p "$HOME/.config/karabiner"\n' "$LOG" > "$SB/bin/open"
run_bootstrap --no-pull karabiner
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "open -ga Karabiner-Elements
karabiner-windows-keyboard-mapping-macos/apply.sh "

it "karabiner fails when its config dir never appears"
make_sandbox
rmdir "$SB/home/.config/karabiner"
run_bootstrap --no-pull karabiner
assert_eq "$RC" 1
assert_contains "$OUT" "  karabiner  failed   (no ~/.config/karabiner - open Karabiner-Elements once)"
assert_eq "$(cat "$LOG")" "open -ga Karabiner-Elements"

it "karabiner dry run only announces the first launch"
make_sandbox
rmdir "$SB/home/.config/karabiner"
run_bootstrap --dry-run --no-pull karabiner
assert_eq "$RC" 0
assert_contains "$OUT" "+ open -ga Karabiner-Elements"
assert_not_contains "$(cat "$LOG")" "open "

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

# --- the keyboard step ------------------------------------------------------
USER_LAYOUTS_REL="home/Library/Keyboard Layouts"

it "keyboard copies a missing layout to ~/Library and enables it"
make_sandbox
run_bootstrap --no-pull keyboard
assert_eq "$RC" 0
assert_eq "$(cat "$SB/$USER_LAYOUTS_REL/CustomSwissGerman.keylayout")" layout
assert_eq "$(cat "$SB/$USER_LAYOUTS_REL/CustomSwissGerman.icns")" icon
assert_eq "$(cat "$LOG")" "swift $APP/enable-input-source.swift $SB/$USER_LAYOUTS_REL/CustomSwissGerman.keylayout Custom Swiss German"
assert_contains "$OUT" "  keyboard   ok"

it "keyboard leaves an identical layout in ~/Library alone"
make_sandbox
mkdir -p "$SB/$USER_LAYOUTS_REL"
echo layout > "$SB/$USER_LAYOUTS_REL/CustomSwissGerman.keylayout"
run_bootstrap --no-pull keyboard
assert_eq "$RC" 0
assert_contains "$OUT" "already installed"
assert_not_contains "$OUT" "+ cp "
assert_contains "$(cat "$LOG")" "swift $APP/enable-input-source.swift $SB/$USER_LAYOUTS_REL/CustomSwissGerman.keylayout"

it "keyboard uses an identical layout in /Library, no second copy"
make_sandbox
echo layout > "$SB/system-layouts/CustomSwissGerman.keylayout"
run_bootstrap --no-pull keyboard
assert_eq "$RC" 0
[ -e "$SB/$USER_LAYOUTS_REL/CustomSwissGerman.keylayout" ] && fail "copied next to the /Library one"
assert_contains "$(cat "$LOG")" "swift $APP/enable-input-source.swift $SB/system-layouts/CustomSwissGerman.keylayout"

it "keyboard treats a copy that differs only in XML comments as identical"
make_sandbox
printf '<!--\n\tGenerated by Ukelele\n-->\nlayout\n' > "$SB/system-layouts/CustomSwissGerman.keylayout"
run_bootstrap --no-pull keyboard
assert_eq "$RC" 0
assert_contains "$OUT" "layout already installed: $SB/system-layouts/CustomSwissGerman.keylayout"

it "keyboard skips with a sudo hint when /Library holds another version"
make_sandbox
echo old > "$SB/system-layouts/CustomSwissGerman.keylayout"
run_bootstrap --no-pull keyboard
assert_eq "$RC" 0
assert_contains "$OUT" "  keyboard   skipped  (an older Custom Swiss German is in $SB/system-layouts"
assert_contains "$OUT" "sudo cp"
assert_eq "$(cat "$LOG")" ""

it "keyboard dry run copies and enables nothing"
make_sandbox
run_bootstrap --dry-run --no-pull keyboard
assert_eq "$RC" 0
assert_contains "$OUT" "+ cp "
assert_contains "$OUT" "+ $SB/bin/swift $APP/enable-input-source.swift"
[ -e "$SB/$USER_LAYOUTS_REL" ] && fail "copied in dry run"
assert_eq "$(cat "$LOG")" ""

it "keyboard without swift installs the layout, skips enabling with a hint"
make_sandbox
SWIFT_BIN="$SB/no-swift" run_bootstrap --no-pull keyboard
assert_eq "$RC" 0
[ -e "$SB/$USER_LAYOUTS_REL/CustomSwissGerman.keylayout" ] || fail "layout not copied"
assert_contains "$OUT" "  keyboard   skipped  (enable 'Custom Swiss German' under System Settings > Keyboard > Input Sources, then log out"

it "keyboard skips with the same hint when enabling fails"
make_sandbox
stub "$SB/bin/swift" swift 1
run_bootstrap --no-pull keyboard
assert_eq "$RC" 0
assert_contains "$OUT" "  keyboard   skipped  (enable 'Custom Swiss German' under System Settings"

# --- Gatekeeper (macos step) ------------------------------------------------
it "Gatekeeper is left alone by default"
make_sandbox
run_bootstrap --no-pull macos
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "python3 macos-defaults.py"

it "MACOS_DISABLE_GATEKEEPER=1 disables it and opens the confirmation pane"
make_sandbox
sandbox_config 'MACOS_DISABLE_GATEKEEPER=1'
run_bootstrap --no-pull macos
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "python3 macos-defaults.py
spctl --status
sudo spctl --master-disable
open x-apple.systempreferences:com.apple.preference.security?General"

it "Gatekeeper that is already off is not touched"
make_sandbox
spctl_stub "assessments disabled"
sandbox_config 'MACOS_DISABLE_GATEKEEPER=1'
run_bootstrap --no-pull macos
assert_eq "$RC" 0
assert_contains "$OUT" "Gatekeeper: already off"
assert_not_contains "$(cat "$LOG")" "sudo"

it "a failing sudo spctl fails the macos step"
make_sandbox
stub "$SB/bin/sudo" sudo 1
sandbox_config 'MACOS_DISABLE_GATEKEEPER=1'
run_bootstrap --no-pull macos
assert_eq "$RC" 1
assert_contains "$OUT" "  macos      failed   (Gatekeeper)"

it "Gatekeeper dry run only shows the commands"
make_sandbox
sandbox_config 'MACOS_DISABLE_GATEKEEPER=1'
run_bootstrap --dry-run --no-pull macos
assert_eq "$RC" 0
assert_contains "$OUT" "+ sudo spctl --master-disable"
assert_not_contains "$(cat "$LOG")" "sudo"

# --- the brew step ----------------------------------------------------------
INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# installer_stub [EXIT] -> curl stub that logs itself and serves an installer
# which puts a brew stub at $SB/homebrew/bin/brew (the BREW_CANDIDATES path);
# a non-zero EXIT makes curl fail instead
installer_stub() {
  stub "$SB/brew-to-install" brew
  printf '#!/bin/bash\necho "curl $*" >> "%s"\n[ %s = 0 ] || exit %s\necho "mkdir -p %s && cp %s %s"\n' \
    "$LOG" "${1:-0}" "${1:-0}" "$SB/homebrew/bin" "$SB/brew-to-install" "$SB/homebrew/bin/brew" \
    > "$SB/bin/curl"
  chmod +x "$SB/bin/curl"
}

it "brew with Homebrew on PATH only runs brew bundle"
make_sandbox
run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "brew bundle --file=$APP/Brewfile --no-upgrade"
assert_contains "$OUT" "  brew       ok"

it "brew installs Homebrew when missing, then bundles"
make_sandbox
rm "$SB/bin/brew"
installer_stub
run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "curl -fsSL $INSTALLER_URL
brew bundle --file=$APP/Brewfile --no-upgrade"

it "brew uses a Homebrew that is installed but not on PATH"
make_sandbox
rm "$SB/bin/brew"
stub "$SB/homebrew/bin/brew" brew
run_bootstrap --no-pull brew dotfiles
assert_eq "$RC" 0
assert_not_contains "$(cat "$LOG")" "curl"
assert_contains "$(cat "$LOG")" "brew bundle --file=$APP/Brewfile --no-upgrade"
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

it "a failing brew bundle fails the step"
make_sandbox
stub "$SB/bin/brew" brew 1
run_bootstrap --no-pull brew
assert_eq "$RC" 1
assert_contains "$OUT" "  brew       failed   (brew bundle)"

it "BREW_BUNDLE_EXTRA runs a second bundle"
make_sandbox
echo 'cask "firefox"' > "$SB/home/Brewfile.local"
sandbox_config 'BREW_BUNDLE_EXTRA="~/Brewfile.local"'
run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "brew bundle --file=$APP/Brewfile --no-upgrade
brew bundle --file=$SB/home/Brewfile.local --no-upgrade"

it "dry run announces the Homebrew install and the bundle, runs nothing"
make_sandbox
rm "$SB/bin/brew"
run_bootstrap --dry-run --no-pull brew
assert_eq "$RC" 0
assert_contains "$OUT" "+ install Homebrew: /bin/bash -c \"\$(curl -fsSL $INSTALLER_URL)\""
assert_contains "$OUT" "+ brew bundle --file=$APP/Brewfile --no-upgrade"
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
assert_contains "$OUT" "Homebrew required - run ./bootstrap.sh brew"
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
assert_eq "$BREW_BUNDLE_EXTRA" ""
assert_eq "$MACOS_DISABLE_GATEKEEPER" 0
for key in BOOTSTRAP_STEPS BOOTSTRAP_SKIP BREW_BUNDLE_EXTRA MACOS_DISABLE_GATEKEEPER DOTFILES_DIR DOTFILES_URL DOTFILES_ASSUME_YES DOTFILES_TERMINALS DOTFILES_OMNISHELL_CONFIG DOTFILES_LOCAL_RC; do
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
