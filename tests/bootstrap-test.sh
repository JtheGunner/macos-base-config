#!/bin/bash
# Tests for bootstrap.sh and lib/. Plain bash, no dependencies; meant to run
# under macOS /bin/bash 3.2 on purpose.
#
#   /bin/bash tests/bootstrap-test.sh
#
# End-to-end cases run bootstrap.sh inside a throwaway sandbox: a copy of the
# scripts next to stub sibling repos, a fake HOME, and stub tools (git, brew,
# python3, omnishell, curl, open, swift, sudo, spctl; npm, pipx, uv, go where a
# test needs them) that only log their arguments.
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
assert_eq "$(select_steps "" "")" "repos brew extras karabiner keyboard macos jetbrains vscode editor apps dotfiles manual"

it "steps run in table order, aliases expand"
assert_eq "$(select_steps "dotfiles keymaps" "")" "jetbrains vscode dotfiles"

it "skip removes steps, aliases included"
assert_eq "$(select_steps "" "keymaps dotfiles")" "repos brew extras karabiner keyboard macos editor apps manual"

it "duplicates collapse"
assert_eq "$(select_steps "macos macos keymaps jetbrains" "")" "macos jetbrains vscode"

it "extra whitespace is ignored"
assert_eq "$(select_steps "  macos   manual " "")" "macos manual"

it "lists spanning several lines are read in full"
assert_eq "$(select_steps "keymaps
dotfiles" "")" "jetbrains vscode dotfiles"
assert_eq "$(select_steps "" "
  dotfiles
")" "repos brew extras karabiner keyboard macos jetbrains vscode editor apps manual"
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

it "parse_args: --yes answers every prompt, default off"
parse_args
assert_eq "$ASSUME_YES" false
parse_args --yes
assert_eq "$ASSUME_YES" true

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

it "--list-packages sets its action"
parse_args --list-packages; assert_eq "$ACTION" list-packages

it "--save-settings sets its action; the ids stay in CLI_STEPS"
parse_args --save-settings alt-tab tabby; assert_eq "$ACTION|$CLI_STEPS" "save-settings|alt-tab tabby"

it "--init-config takes the private repo's URL"
parse_args --init-config git@example.test:me/private.git
assert_eq "$ACTION|$INIT_CONFIG_URL" "init-config|git@example.test:me/private.git"
out="$(parse_args --init-config 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "--init-config needs a git URL"

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
for s in repos brew extras karabiner keyboard macos jetbrains vscode editor apps dotfiles manual keymaps; do
  assert_contains "$out" "$s"
done

it "usage lists the options"
out="$(usage)"
for o in --skip --dry-run --no-pull --config --list --list-packages --save-settings --help; do
  assert_contains "$out" "$o"
done

# --- lib/packages.sh (sourced before lib/config.sh, which uses it) ----------
HERE="$REPO"
. "$REPO/lib/packages.sh"

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

it "the shipped catalog covers every group and leaves the dotfiles' tools out"
all=" $(select_packages @all) "
for id in karabiner-elements firefox visual-studio-code filezilla claude claude-code maccy mouseboost-pro \
  whatsapp windows-app nas-mount spotify coreutils gh gopls sass composer mariadb hf mlx-lm litellm \
  nano-pdf antigravity-cli openclaw ghostscript codexbar dutix; do
  assert_contains "$all" " $id "
done
for group in base browser dev ai productivity communication remote media \
  cli-shell cli-dev cli-ops cli-ai cli-docs cli-macos; do
  select_packages "@$group" >/dev/null || fail "no category @$group"
done
refs=" $(catalog_rows | awk -F'\t' '{ n = split($3, part, "/"); printf "%s ", part[n] }') "
for tool in stow git-delta fzf zoxide ripgrep fd bat eza starship mise tmux direnv broot \
  zsh-autosuggestions zsh-syntax-highlighting omnishell ghostty; do
  assert_not_contains "$refs" " $tool "
done

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

it "a tab inside a catalog cell is rejected, not read as a column break"
f="$(write_catalog "$(printf 'chrome | cask | google-chrome | Google\tChrome | web | Web browser')")"
out="$(PACKAGE_CATALOG="$f" catalog_rows 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "$f:1: tab inside a column"

it "a script package must be fetched over https"
f="$(write_catalog 'x | script | http://example.test/i.sh | x | ai | plain http')"
out="$(PACKAGE_CATALOG="$f" catalog_rows 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "$f:1: script needs an https:// URL"

it "bin: checks are for casks only; extras sources need a real check"
f="$(write_catalog \
  'cc  | cask    | claude-code | bin:claude | ai  | a command-only cask' \
  'x   | formula | x           | bin:x      | cli | bin: on a formula' \
  'hf  | pipx    | hf          | -          | ai  | no check')"
out="$(PACKAGE_CATALOG="$f" catalog_rows 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_not_contains "$out" "$f:1:"
assert_contains "$out" "$f:2: bin:<command> is for casks only"
assert_contains "$out" "$f:3: pipx needs a command to check, not -"

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

it "package_state: apps by folder, commands on PATH, - means no check"
mkdir -p "$TMP/apps/Some App.app"
assert_eq "$(APPLICATIONS_DIR="$TMP/apps" package_state cask "Some App")" installed
assert_eq "$(APPLICATIONS_DIR="$TMP/apps" package_state mas WhatsApp)" missing
assert_eq "$(package_state pipx sh)" installed
assert_eq "$(package_state npm no-such-command-xyz)" missing
assert_eq "$(package_state formula -)" ""

it "a cask that only installs a command is checked by that command"
f="$(write_catalog 'cc | cask | claude-code | bin:sh | ai | a command-only cask' \
  'cx | cask | nothing | bin:no-such-command-xyz | ai | missing')"
assert_eq "$(package_state cask bin:sh)" installed
assert_eq "$(package_state cask bin:no-such-command-xyz)" missing
d="$(mktemp -d "$TMP/bf.XXXXXX")"
out="$(PACKAGE_CATALOG="$f" write_brewfiles "$d" "cc cx")"
assert_contains "$out" "cc: sh already installed - left alone"
assert_eq "$(cat "$d/Brewfile")" 'cask "nothing"'

it "a formula with a check command is left alone when that command exists"
f="$(write_catalog 'here | formula | here-formula | sh | cli | its command is on PATH' \
  'nope | formula | nope-formula | no-such-command-xyz | cli | missing' \
  'free | formula | free-formula | - | cli | no check')"
d="$(mktemp -d "$TMP/bf.XXXXXX")"
out="$(PACKAGE_CATALOG="$f" write_brewfiles "$d" "here nope free")"
assert_contains "$out" "here: sh already installed - left alone"
assert_eq "$(cat "$d/Brewfile")" 'brew "nope-formula"
brew "free-formula"'

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

it "write_brewfiles: a tap listed in taps.txt next to the catalog gets its URL"
f="$(write_catalog "${TEST_CATALOG_LINES[@]}")"
printf '%s\n' '# tap | url' 'user/tap | https://github.com/User/tap-repo' > "$TMP/taps.txt"
d="$(mktemp -d "$TMP/bf.XXXXXX")"
APPLICATIONS_DIR="$TMP/none" PACKAGE_CATALOG="$f" write_brewfiles "$d" "tool app" >/dev/null
assert_eq "$(cat "$d/Brewfile")" 'tap "user/tap", "https://github.com/User/tap-repo"
brew "user/tap/tool"
cask "user/tap/app"'
printf '%s\n' 'user/tap | http://example.test/tap' > "$TMP/taps.txt"
out="$(PACKAGE_CATALOG="$f" write_brewfiles "$d" "tool" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "$TMP/taps.txt:1: expected: <user>/<tap> | https://<url>"
rm "$TMP/taps.txt"

it "the shipped catalog: tlrc and antigravity-cli replace tldr and gemini-cli; mlx-dspark's tap has its URL"
rows="$(catalog_rows)"
assert_contains "$rows" "tlrc"
assert_contains "$rows" "antigravity-cli"
assert_not_contains "$rows" "gemini-cli"
assert_not_contains "$(printf '%s\n' "$rows" | cut -f1)" "tldr"
assert_eq "$(tap_urls)" "arahim3/mlx-dspark	https://github.com/ARahim3/mlx-dspark"

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
assert_eq "$out" "Install FileZilla by hand (FTP client)	https://filezilla-project.org/download.php?type=client"
assert_eq "$(APPLICATIONS_DIR="$TMP/apps3" PACKAGE_CATALOG="$f" manual_package_hints "hf")" ""
mkdir -p "$TMP/apps3/FileZilla.app"
assert_eq "$(APPLICATIONS_DIR="$TMP/apps3" PACKAGE_CATALOG="$f" manual_package_hints "filezilla")" ""

it "the shipped catalog has nas-mount, its template renders one try per share"
assert_eq "$(select_packages nas-mount)" "nas-mount"
out="$(NAS_MOUNT_SHARES="smb://nas/a
  afp://nas/b" applet_source "$REPO/packages/nas-mount.applescript")"
assert_contains "$out" '{"smb://nas/a", "afp://nas/b"}'
assert_contains "$out" "try"
assert_contains "$out" "mount volume"
assert_not_contains "$out" "@@"
out="$(applet_source "$TMP/no-template" 2>&1)"; rc=$?
assert_eq "$rc" 1

it "applet_source keeps an & in a share, also under the bash on PATH (5.2+ patsub_replacement)"
for shell in /bin/bash "$(command -v bash)"; do
  out="$(NAS_MOUNT_SHARES="smb://nas/a&b" HERE="$REPO" "$shell" -c \
    '. "$HERE/lib/packages.sh"; applet_source "$HERE/packages/nas-mount.applescript"')"
  assert_contains "$out" '{"smb://nas/a&b"}'
done

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

it "SETTINGS_DIR defaults to the config file's directory"
XDG_CONFIG_HOME="$TMP/none" load_config ""
assert_eq "$SETTINGS_DIR" "$TMP/none/macos-base-config"
f="$(write_config 'BOOTSTRAP_STEPS=""')"
load_config "$f"
assert_eq "$SETTINGS_DIR" "$TMP"

it "SETTINGS_DIR: ~ expands; a set dir that doesn't exist is exit 2"
mkdir -p "$TMP/h/icloud dir"
f="$(write_config 'SETTINGS_DIR="~/icloud dir"')"
HOME="$TMP/h" load_config "$f"; rc=$?
assert_eq "$rc" 0
assert_eq "$SETTINGS_DIR" "$TMP/h/icloud dir"
f="$(write_config 'SETTINGS_DIR="~/nope"')"
out="$(HOME="$TMP/h" load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "SETTINGS_DIR is not a directory: $TMP/h/nope"

it "SETTINGS_DIR defaults to <config dir>/settings when it exists"
mkdir -p "$TMP/cfg2/settings"
echo 'BOOTSTRAP_STEPS=""' > "$TMP/cfg2/config.sh"
load_config "$TMP/cfg2/config.sh"
assert_eq "$SETTINGS_DIR" "$TMP/cfg2/settings"
rmdir "$TMP/cfg2/settings"
load_config "$TMP/cfg2/config.sh"
assert_eq "$SETTINGS_DIR" "$TMP/cfg2"

it "a relative SETTINGS_DIR or --config resolves to an absolute path"
mkdir -p "$TMP/priv"
f="$(write_config 'SETTINGS_DIR="priv"')"
out="$(cd / && load_config "$f" && echo "$SETTINGS_DIR")"
assert_eq "$out" "$TMP/priv"
write_config 'BOOTSTRAP_STEPS=""' >/dev/null
out="$(cd "$TMP" && load_config config.sh && echo "$SETTINGS_DIR")"
assert_eq "$out" "$TMP"

it "NAS_MOUNT_SHARES: empty by default; smb, afp, nfs URLs over several lines load"
XDG_CONFIG_HOME="$TMP/none" load_config ""
assert_eq "$NAS_MOUNT_SHARES" ""
f="$(write_config 'NAS_MOUNT_SHARES="smb://10.0.12.20/privat
  afp://nas.local/data	nfs://nas.local/export/media"')"
load_config "$f"; rc=$?
assert_eq "$rc" 0

it "a NAS share that isn't a plain smb, afp or nfs URL is exit 2"
for bad in 'http://nas/data' 'smb://' 'smb://nas/a"b' 'smb://nas/*'; do
  f="$(write_config "NAS_MOUNT_SHARES='smb://nas/ok $bad'")"
  out="$(load_config "$f" 2>&1)"; rc=$?
  assert_eq "$rc" 2
  assert_contains "$out" "NAS_MOUNT_SHARES: not an smb://, afp:// or nfs:// URL: $bad"
done

it "an unknown package in the config is exit 2"
f="$(write_config 'PACKAGES="@base bogus"')"
out="$(load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "unknown package: bogus"
assert_contains "$out" "in $f (PACKAGES)"

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

# --- editor-settings/apply.py -----------------------------------------------
EDITOR_APPLY="$REPO/editor-settings/apply.py"
FONT_FAMILY="\"'JetBrains Mono', 'Menlo', 'Monaco', 'Courier New', monospace\""

# editor_home -> fresh fake HOME in EH; editor_dir NAME -> its User dir
editor_home() { EH="$(mktemp -d "$TMP/eh.XXXXXX")"; }
editor_dir() {
  local dir="$EH/Library/Application Support/$1/User"
  mkdir -p "$dir"
  echo "$dir"
}
run_editor_apply() { OUT="$(HOME="$EH" APPLICATIONS_DIR="$EH/Applications" python3 "$EDITOR_APPLY" "$@" 2>&1)"; RC=$?; }
backups() { ls "$1" | grep -c 'settings.json.bak-' || true; }

it "editor settings replace a value, keep comments and other keys"
editor_home
d="$(editor_dir Code)"
cat > "$d/settings.json" <<'JSON'
{
    "security.workspace.trust.untrustedFiles": "open",
    // "editor.fontSize": 99,
    //"editor.fontFamily": "'Cascadia Code', monospace",
    "editor.fontFamily": "Menlo",
    /* block comment with "editor.fontWeight": "900" inside */
    "yaml.schemas": { "editor.fontSize": 7 },
    "editor.fontSize": 14,
    "editor.fontWeight": "100",
}
JSON
run_editor_apply
assert_eq "$RC" 0
f="$(cat "$d/settings.json")"
assert_contains "$f" "\"editor.fontFamily\": $FONT_FAMILY,"
assert_contains "$f" '"editor.fontSize": 12,'
assert_contains "$f" '// "editor.fontSize": 99,'
assert_contains "$f" "//\"editor.fontFamily\": \"'Cascadia Code', monospace\","
assert_contains "$f" '/* block comment with "editor.fontWeight": "900" inside */'
assert_contains "$f" '"yaml.schemas": { "editor.fontSize": 7 },'
assert_contains "$f" '"security.workspace.trust.untrustedFiles": "open",'
assert_eq "$(backups "$d")" 1
assert_contains "$OUT" "VS Code: updated"

it "editor settings add missing keys, also after a trailing comma"
editor_home
d="$(editor_dir Cursor)"
printf '{\n  "workbench.colorTheme": "Default Dark+",\n}\n' > "$d/settings.json"
run_editor_apply
assert_eq "$RC" 0
f="$(cat "$d/settings.json")"
assert_eq "$f" "{
  \"workbench.colorTheme\": \"Default Dark+\",
  \"editor.fontFamily\": $FONT_FAMILY,
  \"editor.fontSize\": 12,
  \"editor.fontWeight\": \"100\",
}"
d="$(editor_dir Windsurf)"
printf '{\n    "a": 1\n}\n' > "$d/settings.json"
run_editor_apply
assert_eq "$RC" 0
assert_contains "$(cat "$d/settings.json")" "\"a\": 1,
    \"editor.fontFamily\": $FONT_FAMILY"

it "editor settings create a missing settings.json, skip missing editors"
editor_home
d="$(editor_dir "Antigravity IDE")"
run_editor_apply
assert_eq "$RC" 0
assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["editor.fontSize"])' "$d/settings.json")" 12
assert_contains "$OUT" "Antigravity IDE: created"
assert_not_contains "$OUT" "VS Code"
[ -e "$EH/Library/Application Support/Code" ] && fail "created a dir for a missing editor"

it "editor settings are idempotent: no change, no backup"
run_editor_apply
before="$(cat "$d/settings.json")"
run_editor_apply
assert_eq "$RC" 0
assert_contains "$OUT" "Antigravity IDE: already set"
assert_eq "$(cat "$d/settings.json")" "$before"
assert_eq "$(backups "$d")" 0

it "editor settings are created for an installed editor that was never started"
editor_home
mkdir -p "$EH/Applications/Visual Studio Code.app"
OUT="$(HOME="$EH" APPLICATIONS_DIR="$EH/Applications" python3 "$EDITOR_APPLY" 2>&1)"; RC=$?
assert_eq "$RC" 0
assert_contains "$OUT" "VS Code: created"
[ -f "$EH/Library/Application Support/Code/User/settings.json" ] || fail "settings.json not created"
[ -e "$EH/Library/Application Support/Cursor" ] && fail "created a dir for a missing editor"
OUT="$(HOME="$EH" APPLICATIONS_DIR="$EH/none" python3 "$EDITOR_APPLY" --dry-run 2>&1)"
assert_contains "$OUT" "VS Code: already set"

it "editor settings dry run shows a diff and writes nothing"
editor_home
d="$(editor_dir Code)"
printf '{\n    "editor.fontSize": 14\n}\n' > "$d/settings.json"
run_editor_apply --dry-run
assert_eq "$RC" 0
assert_contains "$OUT" '-    "editor.fontSize": 14'
assert_contains "$OUT" '+    "editor.fontSize": 12'
assert_eq "$(cat "$d/settings.json")" '{
    "editor.fontSize": 14
}'
assert_eq "$(backups "$d")" 0
d2="$(editor_dir VSCodium)"
run_editor_apply --dry-run
[ -e "$d2/settings.json" ] && fail "created in dry run"

it "a broken settings.json is reported and left alone; others still run"
editor_home
d="$(editor_dir Code)"
printf '{\n    "editor.fontSize": \n' > "$d/settings.json"
d2="$(editor_dir Cursor)"
run_editor_apply
assert_eq "$RC" 1
assert_contains "$OUT" "VS Code: "
assert_contains "$OUT" "left unchanged"
assert_eq "$(cat "$d/settings.json")" '{
    "editor.fontSize": '
assert_contains "$OUT" "Cursor: created"

# --- apps/app_settings.py ---------------------------------------------------
# app_sandbox -> AH (fake HOME), AD (a copy of apps/), AS (settings dir, not created),
# AB (stub bin: defaults keeps domains under $AH/defaults-store,
# osascript and open only log), ALOG (their calls), AAPPS (fake /Applications)
app_sandbox() {
  local root
  root="$(mktemp -d "$TMP/apps.XXXXXX")"
  AH="$root/home"; AD="$root/apps"; AS="$root/settings"; AB="$root/bin"; ALOG="$root/calls.log"; AAPPS="$root/Applications"
  mkdir -p "$AH" "$AD" "$AB" "$AAPPS/AltTab.app" "$AAPPS/Sidebar.app"
  : > "$ALOG"
  cp "$REPO/apps/app_settings.py" "$AD/"
  cp "$REPO/apps/registry.txt" "$AD/"
  cat > "$AB/defaults" <<EOF
#!/bin/bash
echo "defaults \$*" >> "$ALOG"
store="$AH/defaults-store"; mkdir -p "\$store"
case "\$1" in
  export) if [ -f "\$store/\$2.plist" ]; then cat "\$store/\$2.plist"; else exit 1; fi ;;
  import) [ -n "\${FAIL_IMPORT:-}" ] && exit 1; cp "\$3" "\$store/\$2.plist" ;;
esac
EOF
  cat > "$AB/osascript" <<EOF
#!/bin/bash
echo "osascript \$*" >> "$ALOG"
app="\$(printf '%s' "\$*" | sed -n 's/.*application "\\([^"]*\\)" to quit.*/\\1/p')"
[ -n "\$app" ] && [ -z "\${REFUSE_QUIT:-}" ] && rm -f "$AH/running-\$app"
exit 0
EOF
  cat > "$AB/open" <<EOF
#!/bin/bash
echo "open \$*" >> "$ALOG"
[ "\$1" = -a ] && touch "$AH/running-\$2"
exit 0
EOF
  printf '#!/bin/bash\n[ -e "%s/running-$2" ]\n' "$AH" > "$AB/pgrep"
  chmod +x "$AB"/*
}
run_app_settings() {
  OUT="$(HOME="$AH" PATH="$AB:$PATH" APPLICATIONS_DIR="$AAPPS" APP_QUIT_TIMEOUT=0.5 python3 "$AD/app_settings.py" "$@" --dir "$AS" 2>&1)"
  RC=$?
}
# py EXPR... -> run python3 with plistlib, json, sys imported
py() { python3 -c "import plistlib, json, sys, datetime; $1" "${@:2}"; }
alttab_domain() { echo "$AH/defaults-store/com.lwouis.alt-tab-macos.plist"; }
sidebar_support() { echo "$AH/Library/Application Support/at.sidebar.Sidebar"; }
running_app() { touch "$AH/running-$1"; }

# write_alttab FILE KEY=VALUE... -> XML plist of string values
write_alttab() {
  local file="$1"; shift
  mkdir -p "$(dirname "$file")"
  py 'plistlib.dump(dict(a.split("=", 1) for a in sys.argv[2:]), open(sys.argv[1], "wb"))' "$file" "$@"
}
# write_sidebar_backup FILE -> a backup like Sidebar writes, license included
write_sidebar_backup() {
  mkdir -p "$(dirname "$1")"
  py '
portable = {"licenseKey": "SECRET-KEY", "licenseCurrentInfo": "x", "daysOfUsage": 9,
            "lastUsedAt": 1, "useLiveApplicationPreviews": True, "autoHideDelay": 0.5}
prefs = {"SULastCheckTime": "x", "applicationStatistics": b"{}", "recentlyClosedApps": b"[]",
         "SidebarCalendarOrderIds": ["CAL-ID"], "applicationWindowCustomNames_x": b"[]",
         "sidebarStyle": b"[1]", "KeyboardShortcuts_toggleApplicationList": "k",
         "unlockedWeatherConfiguration": b"[]", "applicationConfigurations": b"[]"}
backup = {"encryptedLicenseInfo": b"\x01\x02", "formatVersion": 2,
          "mergesWithExistingPreferences": False, "files": [],
          "metadata": {"id": "AAAAAAAA-0000-0000-0000-000000000000",
                       "createdAt": datetime.datetime(2026, 9, 23, 6, 0, 0),
                       "appVersion": "2.2.5", "configurationVersion": "2.2.5",
                       "edition": "regular", "reason": "update",
                       "fromVersion": "2.2.4", "toVersion": "2.2.5"},
          "portableSettingsData": json.dumps(portable).encode(),
          "preferencesPlist": plistlib.dumps(prefs, fmt=plistlib.FMT_BINARY)}
plistlib.dump(backup, open(sys.argv[1], "wb"), fmt=plistlib.FMT_BINARY)' "$1"
}

# write_registry LINE... -> $AD/registry.txt
write_registry() { printf '%s\n' "$@" > "$AD/registry.txt"; }

it "the shipped app registry parses"
python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import app_settings as a
print(",".join(e.id for e in a.load_registry(a.REGISTRY_FILE)))' "$REPO/apps" > "$TMP/reg.out" 2>&1
assert_eq "$?" 0
assert_eq "$(cat "$TMP/reg.out")" "alt-tab,maccy,shottr,rectangle,tabby,sidebar"

it "registry problems name their line and exit 2"
app_sandbox
write_registry '# comment' '' \
  'ok     | defaults | com.example.ok | Ok' \
  'short  | defaults | com.example' \
  'bad    | rsync    | x              | Bad' \
  'ok     | defaults | com.example.x  | Dup' \
  'Upper  | defaults | com.example.u  | U'
run_app_settings apply
assert_eq "$RC" 2
assert_contains "$OUT" "registry.txt:4: expected 4 columns: id | kind | where | app"
assert_contains "$OUT" "registry.txt:5: unknown kind: rsync"
assert_contains "$OUT" "registry.txt:6: duplicate id: ok (first on line 3)"
assert_contains "$OUT" "registry.txt:7: invalid id: Upper"
write_registry 'tabby | file | Library/Application Support/tabby/config.yaml | Tabby' \
  'sidebar | sidebar | ~/Library/Application Support/at.sidebar.Sidebar | Sidebar'
run_app_settings apply
assert_eq "$RC" 2
assert_contains "$OUT" "registry.txt:1: where must be an absolute or ~/ path"

it "apps export keeps AltTab settings, drops runtime and license keys"
app_sandbox
write_alttab "$(alttab_domain)" appearanceTheme=2 hideStatusIcons=true \
  "NSWindow Frame SettingsWindow=1 2 3 4" SULastCheckTime=x MSAppCenterInstallId=y \
  "NSStatusItem VisibleCC Item-0=false" proLicenseKey=nope
write_sidebar_backup "$(sidebar_support)/2.2.5_20260923-080000_AAAAAAAA.sidebarbackup"
run_app_settings export
assert_eq "$RC" 0
assert_eq "$(py 'print(sorted(plistlib.load(open(sys.argv[1], "rb"))))' "$AS/alt-tab.plist")" "['appearanceTheme', 'hideStatusIcons']"
assert_contains "$(cat "$AS/alt-tab.plist")" "<?xml"

it "apps export strips the Sidebar license, usage and personal data"
b="$AS/sidebar.sidebarbackup"
assert_eq "$(py 'b = plistlib.load(open(sys.argv[1], "rb")); print("encryptedLicenseInfo" in b, b["mergesWithExistingPreferences"])' "$b")" "False True"
assert_eq "$(py 'm = plistlib.load(open(sys.argv[1], "rb"))["metadata"]; print(sorted(m), m["reason"])' "$b")" "['appVersion', 'configurationVersion', 'createdAt', 'edition', 'id', 'reason'] manual"
assert_eq "$(py 'b = plistlib.load(open(sys.argv[1], "rb")); print(sorted(json.loads(b["portableSettingsData"])))' "$b")" "['autoHideDelay', 'useLiveApplicationPreviews']"
assert_eq "$(py 'b = plistlib.load(open(sys.argv[1], "rb")); print(sorted(plistlib.loads(b["preferencesPlist"])))' "$b")" "['KeyboardShortcuts_toggleApplicationList', 'applicationConfigurations', 'sidebarStyle', 'unlockedWeatherConfiguration']"
assert_not_contains "$(py 'print(open(sys.argv[1], "rb").read())' "$b")" "SECRET-KEY"
assert_contains "$OUT" "2.2.5_20260923-080000_AAAAAAAA.sidebarbackup"
leaks="$(py '
def keys(value):
    if isinstance(value, dict):
        for k, v in value.items():
            yield k
            yield from keys(v)
    elif isinstance(value, list):
        for v in value:
            yield from keys(v)
alttab = plistlib.load(open(sys.argv[1], "rb"))
sidebar = plistlib.load(open(sys.argv[2], "rb"))
found = list(keys(alttab)) + list(keys(sidebar))
found += list(keys(json.loads(sidebar["portableSettingsData"])))
found += list(keys(plistlib.loads(sidebar["preferencesPlist"])))
print([k for k in found if "licen" in k.lower()])' "$AS/alt-tab.plist" "$AS/sidebar.sidebarbackup")"
assert_eq "$leaks" "[]"

it "apps export leaves an unchanged Sidebar export alone"
before="$(py 'print(open(sys.argv[1], "rb").read())' "$b")"
write_sidebar_backup "$(sidebar_support)/2.2.5_20260923-090000_BBBBBBBB.sidebarbackup"
touch "$(sidebar_support)/2.2.5_20260923-090000_BBBBBBBB.sidebarbackup"
run_app_settings export
assert_eq "$RC" 0
assert_eq "$(py 'print(open(sys.argv[1], "rb").read())' "$b")" "$before"
assert_contains "$OUT" "Sidebar: unchanged"

it "apps apply merges AltTab settings, keeps other keys, restarts AltTab"
app_sandbox
running_app AltTab
write_alttab "$AS/alt-tab.plist" appearanceTheme=2 hideStatusIcons=true
write_alttab "$(alttab_domain)" appearanceTheme=0 SULastCheckTime=x
run_app_settings apply
assert_eq "$RC" 0
assert_eq "$(py 'd = plistlib.load(open(sys.argv[1], "rb")); print(d["appearanceTheme"], d["hideStatusIcons"], d["SULastCheckTime"])' "$(alttab_domain)")" "2 true x"
log="$(cat "$ALOG")"
assert_contains "$log" 'osascript -e tell application "AltTab" to quit'
assert_contains "$log" "defaults import com.lwouis.alt-tab-macos"
assert_contains "$log" "open -a AltTab"

it "apps apply leaves AltTab alone when it already has the settings"
: > "$ALOG"
run_app_settings apply
assert_eq "$RC" 0
assert_contains "$OUT" "AltTab: already set"
assert_not_contains "$(cat "$ALOG")" "osascript"
assert_not_contains "$(cat "$ALOG")" "import"

it "apps apply dry run only lists the AltTab keys it would change"
app_sandbox
write_alttab "$AS/alt-tab.plist" appearanceTheme=2
write_alttab "$(alttab_domain)" appearanceTheme=0
run_app_settings apply --dry-run
assert_eq "$RC" 0
assert_contains "$OUT" "AltTab: would set appearanceTheme"
assert_not_contains "$(cat "$ALOG")" "import"
assert_eq "$(py 'print(plistlib.load(open(sys.argv[1], "rb"))["appearanceTheme"])' "$(alttab_domain)")" 0

it "defaults apply reopens only an app that was running"
app_sandbox
write_alttab "$AS/alt-tab.plist" appearanceTheme=2
write_alttab "$(alttab_domain)" appearanceTheme=0
run_app_settings apply
assert_eq "$RC" 0
assert_contains "$(cat "$ALOG")" "defaults import com.lwouis.alt-tab-macos"
assert_not_contains "$(cat "$ALOG")" "open -a AltTab"
assert_contains "$OUT" "AltTab: set appearanceTheme"

it "a failed import reopens the app it quit; later apps still apply"
app_sandbox
write_registry 'alt-tab | defaults | com.lwouis.alt-tab-macos | AltTab' \
  'tabby | file | ~/Library/Application Support/tabby/config.yaml | Tabby'
mkdir -p "$AAPPS/Tabby.app"
write_alttab "$AS/alt-tab.plist" appearanceTheme=2
write_alttab "$(alttab_domain)" appearanceTheme=0
echo new > "$AS/tabby.yaml"
running_app AltTab
FAIL_IMPORT=1 run_app_settings apply
assert_eq "$RC" 1
assert_contains "$OUT" "AltTab: failed:"
assert_contains "$(cat "$ALOG")" "open -a AltTab"
assert_eq "$(cat "$AH/Library/Application Support/tabby/config.yaml")" new

it "an app that does not quit is left alone, nothing imported"
app_sandbox
write_alttab "$AS/alt-tab.plist" appearanceTheme=2
write_alttab "$(alttab_domain)" appearanceTheme=0
running_app AltTab
REFUSE_QUIT=1 run_app_settings apply
assert_eq "$RC" 1
assert_contains "$OUT" "AltTab: failed: AltTab did not quit - settings left unchanged"
assert_not_contains "$(cat "$ALOG")" "defaults import"

it "defaults export drops runtime and secret keys of any registry app"
app_sandbox
write_registry 'shottr | defaults | cc.ffitch.shottr | Shottr'
mkdir -p "$AAPPS/Shottr.app"
write_alttab "$AH/defaults-store/cc.ffitch.shottr.plist" afterGrabCopy=1 kc-license=L token=T \
  "NSWindow Frame x=1" SULastCheckTime=x GATelemetry=1 "LaunchAtLogin__hasMigrated=1" \
  "NSToolbar Configuration y=1" customBackdropColor=red
run_app_settings export
assert_eq "$RC" 0
assert_eq "$(py 'print(sorted(plistlib.load(open(sys.argv[1], "rb"))))' "$AS/shottr.plist")" "['afterGrabCopy', 'customBackdropColor']"

it "defaults export skips a missing domain, other apps still export"
app_sandbox
write_registry 'shottr | defaults | cc.ffitch.shottr | Shottr' \
  'alt-tab | defaults | com.lwouis.alt-tab-macos | AltTab'
mkdir -p "$AAPPS/Shottr.app"
write_alttab "$(alttab_domain)" appearanceTheme=2
run_app_settings export
assert_eq "$RC" 0
assert_contains "$OUT" "Shottr: no settings on this Mac - skipped"
[ -f "$AS/alt-tab.plist" ] || fail "AltTab not exported"

it "legacy alttab.plist in the settings dir is still applied"
app_sandbox
write_alttab "$AS/alttab.plist" appearanceTheme=2
write_alttab "$(alttab_domain)" appearanceTheme=0
run_app_settings apply
assert_contains "$OUT" "AltTab: set appearanceTheme"

it "the secret guard finds keys in plist, embedded plist / JSON, JSON, YAML and key=value"
out="$(python3 -B - "$REPO/apps" <<'PYEOF'
import sys, plistlib, json
sys.path.insert(0, sys.argv[1])
import app_settings as a
inner = plistlib.dumps({"licenseKey": "x", "ok": 1}, fmt=plistlib.FMT_BINARY)
print(a.find_secret_keys(plistlib.dumps({"a": 1, "nested": {"apiToken": "t"}, "blob": inner}), "x.plist"))
print(a.find_secret_keys(plistlib.dumps({"data": json.dumps({"deep": [{"Password": 1}]}).encode()}), "x.sidebarbackup"))
print(a.find_secret_keys(json.dumps({"a": {"b": [{"clientSecret": 1}]}}).encode(), "x.json"))
print(a.find_secret_keys(b"theme: dark\npassword: hunter2\n", "x.yaml"))
print(a.find_secret_keys(b"encrypted: true\nvault: x\ntoken: y\n", "x.yaml"))
print(a.find_secret_keys(b"name=x\nSERIAL = 1\n", "x.conf"))
print(a.find_secret_keys(plistlib.dumps({"theme": 2}), "x.plist"))
print(a.find_secret_keys(plistlib.dumps({"com.apple.Passwords": {"pinned": True}, "passwordLength": 3}), "x.plist"))
PYEOF
)"
assert_eq "$out" "['apiToken', 'licenseKey']
['Password']
['clientSecret']
['password']
[]
['SERIAL']
[]
['passwordLength']"

it "a secret in an export is not written; the other apps still export, exit 1"
app_sandbox
write_registry 'tool | file | ~/Library/Application Support/tool/config.json | Tool' \
  'alt-tab | defaults | com.lwouis.alt-tab-macos | AltTab'
mkdir -p "$AAPPS/Tool.app" "$AH/Library/Application Support/tool"
echo '{"ui": {"theme": "dark", "apiToken": "abc"}}' > "$AH/Library/Application Support/tool/config.json"
write_alttab "$(alttab_domain)" appearanceTheme=2
run_app_settings export
assert_eq "$RC" 1
assert_contains "$OUT" "Tool: failed: secret keys in export: apiToken - not written"
[ -e "$AS/tool.json" ] && fail "secret export written"
[ -f "$AS/alt-tab.plist" ] || fail "AltTab not exported"

it "the shipped registry exports Shottr without its license, token, device and runtime keys"
app_sandbox
mkdir -p "$AAPPS/Shottr.app"
write_alttab "$AH/defaults-store/cc.ffitch.shottr.plist" afterGrabCopy=1 kc-license=L token=T \
  kc-vault=V uid=U defaultFolderBookmark=B localEventCounter=773 activeAppVersion=1090235 \
  latestBuild=135 latestVersionCode=10902 latestVersionPackageUrl=P latestVersionURL=U \
  "NSStatusItem VisibleCC Item-0=1" GATelemetry=1 customBackdropColor=red
run_app_settings export shottr
assert_eq "$RC" 0
assert_eq "$(py 'print(sorted(plistlib.load(open(sys.argv[1], "rb"))))' "$AS/shottr.plist")" "['afterGrabCopy', 'customBackdropColor']"
[ -e "$AS/alt-tab.plist" ] && fail "exported more than shottr"
true

it "export takes app ids, skips apps that are not installed, rejects unknown ids"
app_sandbox
write_alttab "$(alttab_domain)" appearanceTheme=2
write_sidebar_backup "$(sidebar_support)/2.2.5_20260923-080000_AAAAAAAA.sidebarbackup"
run_app_settings export alt-tab
assert_eq "$RC" 0
[ -f "$AS/alt-tab.plist" ] || fail "alt-tab not exported"
[ -e "$AS/sidebar.sidebarbackup" ] && fail "sidebar exported without being asked"
rmdir "$AAPPS/Sidebar.app"
run_app_settings export
assert_contains "$OUT" "Sidebar: not installed - skipped"
run_app_settings export nope
assert_eq "$RC" 2
assert_contains "$OUT" "unknown app: nope (see apps/registry.txt)"

it "file export copies the settings file"
app_sandbox
write_registry 'tabby | file | ~/Library/Application Support/tabby/config.yaml | Tabby'
mkdir -p "$AAPPS/Tabby.app" "$AH/Library/Application Support/tabby"
printf 'encrypted: true\nvault: abc\n' > "$AH/Library/Application Support/tabby/config.yaml"
run_app_settings export
assert_eq "$RC" 0
assert_eq "$(cat "$AS/tabby.yaml")" "$(printf 'encrypted: true\nvault: abc')"
assert_eq "$(stat -f %Lp "$AS/tabby.yaml")" 600

it "file apply backs up the old file, copies, restarts a running app"
app_sandbox
write_registry 'tabby | file | ~/Library/Application Support/tabby/config.yaml | Tabby'
mkdir -p "$AAPPS/Tabby.app" "$AH/Library/Application Support/tabby" "$AS"
echo old > "$AH/Library/Application Support/tabby/config.yaml"
echo new > "$AS/tabby.yaml"
running_app Tabby
run_app_settings apply
assert_eq "$RC" 0
assert_eq "$(cat "$AH/Library/Application Support/tabby/config.yaml")" new
assert_eq "$(cat "$AH/Library/Application Support/tabby"/config.yaml.bak-*)" old
assert_contains "$(cat "$ALOG")" 'osascript -e tell application "Tabby" to quit'
assert_contains "$(cat "$ALOG")" "open -a Tabby"
assert_contains "$OUT" "Tabby: set"
: > "$ALOG"
run_app_settings apply
assert_contains "$OUT" "Tabby: already set"
assert_eq "$(cat "$ALOG")" ""

it "file apply creates the target folder; dry run changes nothing"
app_sandbox
write_registry 'tabby | file | ~/Library/Application Support/tabby/config.yaml | Tabby'
mkdir -p "$AAPPS/Tabby.app" "$AS"
echo new > "$AS/tabby.yaml"
run_app_settings apply --dry-run
assert_contains "$OUT" "Tabby: would replace"
[ -e "$AH/Library/Application Support/tabby" ] && fail "written in dry run"
run_app_settings apply
assert_eq "$(cat "$AH/Library/Application Support/tabby/config.yaml")" new
assert_not_contains "$(cat "$ALOG")" "open -a Tabby"

it "apps apply adds the Sidebar backup to its backup list once"
app_sandbox
write_sidebar_backup "$AS/sidebar.sidebarbackup"
run_app_settings apply
assert_eq "$RC" 0
placed="$(ls "$(sidebar_support)")"
assert_contains "$placed" "2.2.5_"
assert_contains "$placed" "_AAAAAAAA.sidebarbackup"
cmp -s "$AS/sidebar.sidebarbackup" "$(sidebar_support)/$placed" || fail "placed copy differs"
assert_contains "$OUT" "Settings > Expert > Backups"
run_app_settings apply
assert_eq "$(ls "$(sidebar_support)" | wc -l | tr -d ' ')" 1
assert_contains "$OUT" "Sidebar: backup already in its list"

it "apps apply dry run does not add the Sidebar backup"
app_sandbox
write_sidebar_backup "$AS/sidebar.sidebarbackup"
run_app_settings apply --dry-run
assert_eq "$RC" 0
assert_contains "$OUT" "Sidebar: would add"
[ -e "$(sidebar_support)" ] && fail "written in dry run"

it "apps apply skips apps that are not installed"
app_sandbox
rmdir "$AAPPS/AltTab.app" "$AAPPS/Sidebar.app"
write_alttab "$AS/alt-tab.plist" appearanceTheme=2
write_sidebar_backup "$AS/sidebar.sidebarbackup"
run_app_settings apply
assert_eq "$RC" 0
assert_contains "$OUT" "AltTab: not installed"
assert_contains "$OUT" "Sidebar: not installed"
assert_eq "$(cat "$ALOG")" ""

it "apps export writes private files: dir 700, files 600"
app_sandbox
write_alttab "$(alttab_domain)" appearanceTheme=2
write_sidebar_backup "$(sidebar_support)/2.2.5_20260923-080000_AAAAAAAA.sidebarbackup"
run_app_settings export
assert_eq "$RC" 0
assert_eq "$(stat -f %Lp "$AS")" 700
assert_eq "$(stat -f %Lp "$AS/alt-tab.plist")" 600
assert_eq "$(stat -f %Lp "$AS/sidebar.sidebarbackup")" 600
chmod 644 "$AS/alt-tab.plist"
write_alttab "$(alttab_domain)" appearanceTheme=3
run_app_settings export
assert_eq "$(stat -f %Lp "$AS/alt-tab.plist")" 600

it "apps apply skips an installed app without a settings file"
app_sandbox
run_app_settings apply
assert_eq "$RC" 0
assert_contains "$OUT" "AltTab: no settings in $AS - skipped"
assert_contains "$OUT" "Sidebar: no settings in $AS - skipped"
assert_eq "$(cat "$ALOG")" ""

it "apps export creates the settings dir; without --dir it uses the config dir"
app_sandbox
write_alttab "$(alttab_domain)" appearanceTheme=2
run_app_settings export
assert_eq "$RC" 0
[ -f "$AS/alt-tab.plist" ] || fail "no alttab.plist in the new settings dir"
OUT="$(env -u XDG_CONFIG_HOME HOME="$AH" PATH="$AB:$PATH" APPLICATIONS_DIR="$AAPPS" python3 "$AD/app_settings.py" export 2>&1)"
assert_eq "$?" 0
[ -f "$AH/.config/macos-base-config/alt-tab.plist" ] || fail "flat default dir not used: $OUT"
mkdir -p "$AH/.config/macos-base-config/settings"
OUT="$(env -u XDG_CONFIG_HOME HOME="$AH" PATH="$AB:$PATH" APPLICATIONS_DIR="$AAPPS" python3 "$AD/app_settings.py" export 2>&1)"
[ -f "$AH/.config/macos-base-config/settings/alt-tab.plist" ] || fail "settings/ not used: $OUT"

it "no app settings are tracked in this public repo"
tracked="$(git -C "$REPO" ls-files apps)"
assert_eq "$tracked" "apps/app_settings.py
apps/registry.txt"
assert_contains "$(cat "$REPO/.gitignore")" "apps/*.plist"
assert_contains "$(cat "$REPO/.gitignore")" "apps/*.sidebarbackup"

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
  mkdir -p "$APP" "$SB/home/.config/karabiner" "$SB/bin" "$SB/Karabiner-Elements.app" "$SB/Applications" "$SB/tmp"
  : > "$LOG"
  cp -R "$REPO/bootstrap.sh" "$REPO/lib" "$REPO/repos.txt" "$REPO/packages" "$APP/"
  stub "$APP/ide-keymaps/apply.sh" jetbrains-apply
  stub "$APP/ide-keymaps/port-vscode.sh" port-vscode
  mkdir -p "$APP/editor-settings" "$APP/apps"
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
  OUT="$(env -u XDG_CONFIG_HOME -u DOTFILES_TERMINALS -u PACKAGES -u GOBIN HOME="$SB/home" \
    PATH="$SB/bin:/usr/bin:/bin" KARABINER_APP="$SB/Karabiner-Elements.app" \
    BREW_CANDIDATES="$SB/homebrew/bin/brew" KARABINER_WAIT_SECONDS=0 \
    KEYBOARD_SYSTEM_DIR="$SB/system-layouts" SWIFT="${SWIFT_BIN:-$SB/bin/swift}" \
    APPLICATIONS_DIR="$SB/Applications" TMPDIR="$SB/tmp/" PACKAGE_CATALOG="${SB_CATALOG:-}" \
    UI_COLOR="${UI_COLOR:-0}" BOOTSTRAP_INTERACTIVE="${BOOTSTRAP_INTERACTIVE:-0}" \
    /bin/bash "$APP/bootstrap.sh" "$@" 2>&1 < <(if [ -n "${RUN_INPUT+x}" ]; then printf '%s' "$RUN_INPUT"; fi))"
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
mkdir -p "$SB/Applications/AltTab.app"
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

it "manual step names the Gatekeeper confirmation only when opted in"
make_sandbox
sandbox_config 'MACOS_DISABLE_GATEKEEPER=1'
run_bootstrap manual
assert_contains "$OUT" "Gatekeeper"

it "no colours unless asked for (no terminal here)"
make_sandbox
stub_sibling karabiner-windows-keyboard-mapping-macos apply.sh 3
run_bootstrap --no-pull karabiner macos
assert_not_contains "$OUT" $'\033['

it "UI_COLOR=1 colours step headers, commands, warnings and the summary by status"
make_sandbox
stub_sibling karabiner-windows-keyboard-mapping-macos apply.sh 3
UI_COLOR=1 run_bootstrap --no-pull karabiner macos jetbrains
assert_contains "$OUT" $'\033[1m\033[36m== macos:\033[0m'
assert_contains "$OUT" $'\033[2m+ '
assert_contains "$OUT" $'\033[32mok'
assert_contains "$OUT" $'\033[31mfailed  \033[0m'
assert_contains "$OUT" $'\033[33mskipped \033[0m'

it "an interactive run asks for the sudo password once, up front"
make_sandbox
printf '#!/bin/bash\necho "sudo $*" >> "%s"\n[ "$1" = -n ] && exit 1\nexit 0\n' "$LOG" > "$SB/bin/sudo"
chmod +x "$SB/bin/sudo"
BOOTSTRAP_INTERACTIVE=1 RUN_INPUT="" run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_eq "$(head -2 "$LOG")" "sudo -n true
sudo -v"
assert_contains "$OUT" "Your password is needed once"

it "no password up front in a dry run, without a terminal, or when no step needs sudo"
make_sandbox
BOOTSTRAP_INTERACTIVE=1 RUN_INPUT="" run_bootstrap --dry-run --no-pull brew
assert_not_contains "$(cat "$LOG")" "sudo"
run_bootstrap --no-pull brew
assert_not_contains "$(cat "$LOG")" "sudo"
BOOTSTRAP_INTERACTIVE=1 RUN_INPUT="" run_bootstrap --no-pull editor
assert_not_contains "$(cat "$LOG")" "sudo"
: > "$LOG"
sandbox_config 'MACOS_DISABLE_GATEKEEPER=1'
BOOTSTRAP_INTERACTIVE=1 RUN_INPUT="" run_bootstrap --no-pull macos
assert_contains "$(head -1 "$LOG")" "sudo -n true"

it "the Homebrew installer runs without its prompts once sudo is primed"
make_sandbox
rm "$SB/bin/brew"
stub "$SB/brew-to-install" brew
printf '#!/bin/bash\necho "curl $*" >> "%s"\necho "echo installer NONINTERACTIVE=\\${NONINTERACTIVE:-} >> %s; mkdir -p %s && cp %s %s"\n' \
  "$LOG" "$LOG" "$SB/homebrew/bin" "$SB/brew-to-install" "$SB/homebrew/bin/brew" > "$SB/bin/curl"
chmod +x "$SB/bin/curl"
BOOTSTRAP_INTERACTIVE=1 RUN_INPUT="" run_bootstrap --no-pull brew
assert_contains "$(cat "$LOG")" "installer NONINTERACTIVE=1"
make_sandbox
rm "$SB/bin/brew"
stub "$SB/brew-to-install" brew
printf '#!/bin/bash\necho "curl $*" >> "%s"\necho "echo installer NONINTERACTIVE=\\${NONINTERACTIVE:-} >> %s; mkdir -p %s && cp %s %s"\n' \
  "$LOG" "$LOG" "$SB/homebrew/bin" "$SB/brew-to-install" "$SB/homebrew/bin/brew" > "$SB/bin/curl"
chmod +x "$SB/bin/curl"
run_bootstrap --no-pull brew
assert_contains "$(cat "$LOG")" "installer NONINTERACTIVE="
assert_not_contains "$(cat "$LOG")" "installer NONINTERACTIVE=1"

it "an interactive manual step walks through the items: Enter opens, Enter confirms, s skips"
make_sandbox
mkdir -p "$SB/Applications/AltTab.app"
sandbox_config 'MACOS_DISABLE_GATEKEEPER=1'
BOOTSTRAP_INTERACTIVE=1 RUN_INPUT=$'\n\ns\n\n\n\n' run_bootstrap manual
assert_eq "$RC" 0
assert_contains "$OUT" "[1/4] Karabiner permissions"
assert_contains "$OUT" "[2/4] Input source"
assert_contains "$OUT" "[3/4] Gatekeeper"
assert_contains "$OUT" "[4/4] Licenses"
assert_eq "$(cat "$LOG")" "open -a Karabiner-Elements
open x-apple.systempreferences:com.apple.preference.security?General"
assert_not_contains "$OUT" "  - Karabiner permissions"

it "the guide stops at the end of input instead of waiting"
make_sandbox
BOOTSTRAP_INTERACTIVE=1 RUN_INPUT="" run_bootstrap manual
assert_eq "$RC" 0
assert_contains "$OUT" "[1/2] Karabiner permissions"
assert_not_contains "$OUT" "[2/2]"
assert_eq "$(cat "$LOG")" ""

it "--yes and a dry run keep the manual step a plain list"
make_sandbox
BOOTSTRAP_INTERACTIVE=1 RUN_INPUT="" run_bootstrap --yes manual
assert_contains "$OUT" "  - Karabiner permissions:"
assert_not_contains "$OUT" "[1/"
BOOTSTRAP_INTERACTIVE=1 RUN_INPUT="" run_bootstrap --dry-run manual
assert_contains "$OUT" "  - Karabiner permissions:"
assert_eq "$(cat "$LOG")" ""

it "editor runs right after vscode and calls editor-settings/apply.py"
make_sandbox
run_bootstrap --no-pull manual editor vscode
assert_eq "$(headers)" "== vscode == editor == manual == summary "
assert_contains "$(cat "$LOG")" "python3 apply.py"

it "apps runs right after editor and applies the settings dir"
make_sandbox
mkdir -p "$SB/home/.config/macos-base-config"
run_bootstrap --no-pull manual apps editor
assert_eq "$(headers)" "== editor == apps == manual == summary "
assert_contains "$(cat "$LOG")" "python3 app_settings.py apply --dir $SB/home/.config/macos-base-config"

it "--save-settings exports into SETTINGS_DIR and shows the private repo's changes"
make_sandbox
mkdir -p "$SB/home/.config/macos-base-config/settings"
run_bootstrap --save-settings alt-tab
assert_eq "$RC" 0
assert_contains "$(cat "$LOG")" "python3 $APP/apps/app_settings.py export --dir $SB/home/.config/macos-base-config/settings alt-tab"
assert_contains "$(cat "$LOG")" "git -C $SB/home/.config/macos-base-config/settings status --short"
assert_contains "$(cat "$LOG")" "git -C $SB/home/.config/macos-base-config/settings diff --stat"
assert_not_contains "$(cat "$LOG")" "commit"
assert_not_contains "$OUT" "== summary"

it "--save-settings outside a git repo shows no git output; the export's exit code wins"
make_sandbox
stub "$SB/bin/git" git 128
stub "$SB/bin/python3" python3 1
run_bootstrap --save-settings
assert_eq "$RC" 1
assert_not_contains "$(cat "$LOG")" "status --short"

it "--save-settings dry run only shows the export"
make_sandbox
run_bootstrap --dry-run --save-settings
assert_eq "$RC" 0
assert_contains "$OUT" "+ python3 $APP/apps/app_settings.py export --dir $SB/home/.config/macos-base-config"
assert_eq "$(cat "$LOG")" ""

it "apps skips without a settings dir"
make_sandbox
run_bootstrap --no-pull apps
assert_eq "$RC" 0
assert_contains "$OUT" "  apps       skipped  (no settings dir: $SB/home/.config/macos-base-config)"
assert_not_contains "$(cat "$LOG")" "app_settings.py"

it "a relative --config reads the settings next to it, not apps/ of the repo"
make_sandbox
mkdir -p "$SB/home/cfg"
echo 'BOOTSTRAP_STEPS=""' > "$SB/home/cfg/config.sh"
old_pwd="$PWD"
cd "$SB/home/cfg"
run_bootstrap --no-pull --config config.sh apps
cd "$old_pwd"
assert_eq "$RC" 0
assert_contains "$(cat "$LOG")" "python3 app_settings.py apply --dir $SB/home/cfg"

it "the settings dir follows --config, spaces included"
make_sandbox
mkdir -p "$SB/home/Cloud Docs/mbc"
echo 'BOOTSTRAP_STEPS=""' > "$SB/home/Cloud Docs/mbc/config.sh"
run_bootstrap --no-pull --config "$SB/home/Cloud Docs/mbc/config.sh" apps
assert_eq "$RC" 0
assert_contains "$(cat "$LOG")" "python3 app_settings.py apply --dir $SB/home/Cloud Docs/mbc"

it "manual step names the Sidebar restore and licenses only for installed apps"
make_sandbox
run_bootstrap manual
assert_not_contains "$OUT" "Sidebar settings"
assert_not_contains "$OUT" "Licenses"
mkdir -p "$SB/Applications/AltTab.app"
run_bootstrap manual
assert_contains "$OUT" "Licenses: enter the AltTab (Pro) key from your password manager"
assert_not_contains "$OUT" "Sidebar settings"
mkdir -p "$SB/Applications/Sidebar.app"
run_bootstrap manual
assert_contains "$OUT" "Licenses: enter the AltTab (Pro) and Sidebar keys from your password manager"
assert_not_contains "$OUT" "Sidebar settings"
sandbox_config 'BOOTSTRAP_STEPS=""'
touch "$SB/home/.config/macos-base-config/sidebar.sidebarbackup"
run_bootstrap manual
assert_contains "$OUT" "Sidebar settings: Settings > Expert > Backups > restore the backup the apps step added"
mkdir -p "$SB/Applications/Shottr.app"
run_bootstrap manual
assert_contains "$OUT" "Licenses: enter the AltTab (Pro), Sidebar and Shottr keys from your password manager"
assert_not_contains "$OUT" "Tabby"
mkdir -p "$SB/Applications/Tabby.app"
run_bootstrap manual
assert_not_contains "$OUT" "Tabby"
touch "$SB/home/.config/macos-base-config/tabby.yaml"
run_bootstrap manual
assert_contains "$OUT" "Tabby: unlock its vault with the passphrase from your password manager"

it "manual step names a single Shottr license"
make_sandbox
mkdir -p "$SB/Applications/Shottr.app"
run_bootstrap manual
assert_contains "$OUT" "Licenses: enter the Shottr key from your password manager"

it "brew runs right after repos"
make_sandbox
run_bootstrap --no-pull manual brew repos
assert_eq "$(headers)" "== repos == brew == manual == summary "

it "dry run hands --dry-run to every sub-tool and runs no git"
make_sandbox
with_jetbrains
mkdir -p "$SB/home/.config/macos-base-config"
run_bootstrap --dry-run --skip dotfiles
assert_eq "$RC" 0
log="$(cat "$LOG")"
assert_contains "$log" "karabiner-windows-keyboard-mapping-macos/apply.sh --dry-run"
assert_contains "$log" "python3 macos-defaults.py --dry-run"
assert_contains "$log" "jetbrains-apply --dry-run"
assert_contains "$log" "port-vscode --dry-run"
assert_contains "$log" "python3 apply.py --dry-run"
assert_contains "$log" "python3 app_settings.py apply --dir $SB/home/.config/macos-base-config --dry-run"
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

it "jetbrains skips while a JetBrains IDE is running; vscode still runs"
make_sandbox
with_jetbrains
stub "$APP/ide-keymaps/apply.sh" jetbrains-apply 75
run_bootstrap --no-pull keymaps
assert_eq "$RC" 0
assert_contains "$OUT" "  jetbrains  skipped  (a JetBrains IDE is running - quit it, then run: ./bootstrap.sh jetbrains)"
assert_contains "$(cat "$LOG")" "port-vscode"

it "any other jetbrains failure still fails the step"
make_sandbox
with_jetbrains
stub "$APP/ide-keymaps/apply.sh" jetbrains-apply 1
run_bootstrap --no-pull keymaps
assert_eq "$RC" 1
assert_contains "$OUT" "  jetbrains  failed"

it "karabiner skips when Karabiner-Elements is missing"
make_sandbox
rmdir "$SB/Karabiner-Elements.app"
run_bootstrap --no-pull karabiner
assert_eq "$RC" 0
assert_contains "$OUT" "Karabiner-Elements not installed - add karabiner-elements to PACKAGES, then run ./bootstrap.sh brew"
assert_contains "$OUT" "  karabiner  skipped  (Karabiner-Elements not installed"
assert_eq "$(cat "$LOG")" ""

it "karabiner creates a missing config dir instead of starting the app"
make_sandbox
rmdir "$SB/home/.config/karabiner"
run_bootstrap --no-pull karabiner
assert_eq "$RC" 0
[ -d "$SB/home/.config/karabiner" ] || fail "config dir not created"
assert_eq "$(cat "$LOG")" "karabiner-windows-keyboard-mapping-macos/apply.sh "

it "karabiner fails when its config dir can't be created"
make_sandbox
rm -rf "$SB/home/.config"
touch "$SB/home/.config"
run_bootstrap --no-pull karabiner
assert_eq "$RC" 1
assert_contains "$OUT" "  karabiner  failed   (could not create ~/.config/karabiner)"
assert_eq "$(cat "$LOG")" ""

it "karabiner dry run only announces the config dir"
make_sandbox
rmdir "$SB/home/.config/karabiner"
run_bootstrap --dry-run --no-pull karabiner
assert_eq "$RC" 0
assert_contains "$OUT" "+ mkdir -p $SB/home/.config/karabiner"
[ -d "$SB/home/.config/karabiner" ] && fail "dry run created the config dir"
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

it "enable-input-source.swift picks the right source and names a layout switch"
if [ -x /usr/bin/swift ]; then
  out="$(/usr/bin/swift "$REPO/enable-input-source.swift" --self-test 2>&1)"
  assert_eq "$?" 0
  assert_contains "$out" "self-test passed"
else
  echo "  (skipped: no /usr/bin/swift)"
fi

it "a swift that fails to compile shows one line and keeps its errors in a log"
make_sandbox
printf '#!/bin/bash\necho "error: failed to build module '"'"'Swift'"'"'; this SDK is not supported by the compiler" >&2\nexit 1\n' > "$SB/bin/swift"
chmod +x "$SB/bin/swift"
run_bootstrap --no-pull keyboard
assert_eq "$RC" 0
assert_not_contains "$OUT" "failed to build module"
assert_contains "$OUT" "swift failed - the Command Line Tools may be out of date (System Settings > General > Software Update); details: $SB/home/Library/Logs/macos-base-config/keyboard-swift.log"
assert_contains "$(cat "$SB/home/Library/Logs/macos-base-config/keyboard-swift.log")" "failed to build module"
assert_contains "$OUT" "  keyboard   skipped  (enable 'Custom Swiss German'"

it "a swift that succeeds shows its own output"
make_sandbox
printf '#!/bin/bash\necho "  input source '"'"'Custom Swiss German'"'"': enabled"\n' > "$SB/bin/swift"
chmod +x "$SB/bin/swift"
run_bootstrap --no-pull keyboard
assert_contains "$OUT" "input source 'Custom Swiss German': enabled"
assert_contains "$OUT" "  keyboard   ok"

# --- Gatekeeper (macos step) ------------------------------------------------
it "Gatekeeper is left alone by default"
make_sandbox
run_bootstrap --no-pull macos
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "python3 macos-defaults.py"

it "MACOS_DISABLE_GATEKEEPER=1 requests it; the manual step opens the pane later"
make_sandbox
sandbox_config 'MACOS_DISABLE_GATEKEEPER=1'
run_bootstrap --no-pull macos
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "python3 macos-defaults.py
spctl --status
sudo spctl --master-disable"
assert_contains "$OUT" "Gatekeeper: requested - confirm it in the manual step at the end"

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

it "Gatekeeper waiting for its confirmation in System Settings is ok"
make_sandbox
printf '#!/bin/bash\necho "sudo $*" >> "%s"\necho "Globally disabling the assessment system needs to be confirmed in System Settings."\nexit 1\n' \
  "$LOG" > "$SB/bin/sudo"
chmod +x "$SB/bin/sudo"
sandbox_config 'MACOS_DISABLE_GATEKEEPER=1'
run_bootstrap --no-pull macos
assert_eq "$RC" 0
assert_contains "$OUT" "needs to be confirmed in System Settings"
assert_not_contains "$(cat "$LOG")" "open "
assert_contains "$OUT" "  macos      ok"

it "Gatekeeper dry run only shows the commands"
make_sandbox
sandbox_config 'MACOS_DISABLE_GATEKEEPER=1'
run_bootstrap --dry-run --no-pull macos
assert_eq "$RC" 0
assert_contains "$OUT" "+ sudo spctl --master-disable"
assert_not_contains "$(cat "$LOG")" "sudo"

# --- the private config repo -----------------------------------------------
CONFIG_URL="git@example.test:me/macos-private-config.git"
CFG_DIR_REL=".config/macos-base-config"

# config_git_stub -> git that logs, answers "remote get-url" with $SB/git-origin
# and "status --porcelain" with $SB/git-status, and fails a pull when
# $SB/git-pull-fails exists
config_git_stub() {
  cat > "$SB/bin/git" <<STUB
#!/bin/bash
echo "git \$*" >> "$LOG"
case "\$*" in
  *"remote get-url"*) cat "$SB/git-origin" 2>/dev/null ;;
  *"status --porcelain"*) cat "$SB/git-status" 2>/dev/null ;;
  *pull*) [ -e "$SB/git-pull-fails" ] && exit 1 ;;
esac
exit 0
STUB
  chmod +x "$SB/bin/git"
}

it "--init-config clones the private repo into a missing or empty config dir"
make_sandbox
config_git_stub
run_bootstrap --init-config "$CONFIG_URL"
assert_eq "$RC" 0
assert_contains "$(cat "$LOG")" "git clone $CONFIG_URL $SB/home/$CFG_DIR_REL"
assert_contains "$OUT" "next: ./bootstrap.sh"
assert_not_contains "$OUT" "== summary"
: > "$LOG"
mkdir -p "$SB/home/$CFG_DIR_REL"
run_bootstrap --init-config "$CONFIG_URL"
assert_eq "$RC" 0
assert_contains "$(cat "$LOG")" "git clone $CONFIG_URL $SB/home/$CFG_DIR_REL"

it "--init-config leaves a dir with other files alone, exit 2"
make_sandbox
config_git_stub
sandbox_config 'PACKAGES="@base"'
run_bootstrap --init-config "$CONFIG_URL"
assert_eq "$RC" 2
assert_contains "$OUT" "$SB/home/$CFG_DIR_REL already has files"
assert_not_contains "$(cat "$LOG")" "clone"

it "--init-config on a checkout: same URL is set up, another URL is exit 2"
make_sandbox
config_git_stub
mkdir -p "$SB/home/$CFG_DIR_REL/.git"
echo "$CONFIG_URL" > "$SB/git-origin"
run_bootstrap --init-config "$CONFIG_URL"
assert_eq "$RC" 0
assert_contains "$OUT" "already set up"
assert_not_contains "$(cat "$LOG")" "clone"
echo "git@example.test:someone/else.git" > "$SB/git-origin"
run_bootstrap --init-config "$CONFIG_URL"
assert_eq "$RC" 2
assert_contains "$OUT" "is a checkout of git@example.test:someone/else.git"

it "--init-config follows --config and only prints in a dry run"
make_sandbox
config_git_stub
run_bootstrap --dry-run --init-config "$CONFIG_URL" --config "$SB/home/Cloud/mbc/config.sh"
assert_eq "$RC" 0
assert_contains "$OUT" "+ git clone $CONFIG_URL $SB/home/Cloud/mbc"
assert_eq "$(cat "$LOG")" ""

it "repos pulls the private config checkout"
make_sandbox
config_git_stub
mkdir -p "$SB/home/$CFG_DIR_REL/.git"
run_bootstrap repos
assert_eq "$RC" 0
assert_contains "$(cat "$LOG")" "git -C $SB/home/$CFG_DIR_REL pull --ff-only"
: > "$LOG"
run_bootstrap --no-pull repos
assert_not_contains "$(cat "$LOG")" "$CFG_DIR_REL pull"

it "repos keeps a config checkout with local changes, warns about a failed pull"
make_sandbox
config_git_stub
mkdir -p "$SB/home/$CFG_DIR_REL/.git"
echo " M config.sh" > "$SB/git-status"
run_bootstrap repos
assert_eq "$RC" 0
assert_contains "$OUT" "warn: local changes in $SB/home/$CFG_DIR_REL - not pulled"
assert_not_contains "$(cat "$LOG")" "$CFG_DIR_REL pull"
rm "$SB/git-status"
touch "$SB/git-pull-fails"
run_bootstrap repos
assert_eq "$RC" 0
assert_contains "$OUT" "warn: pull failed in $SB/home/$CFG_DIR_REL"
assert_contains "$OUT" "  repos      ok"

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

it "brew bundles the generated Brewfile: @base without a config"
make_sandbox
brew_stub
run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_eq "$(brew_log)" "brew tap otuerk/sidebar
brew trust --cask otuerk/sidebar/sidebar
brew bundle --file=<tmp>/Brewfile --no-upgrade
$BASE_BREWFILE"
assert_contains "$OUT" '    cask "alt-tab"'
assert_contains "$OUT" "note: installers may open windows or ask for permissions - close them; the manual step at the end walks you through what matters"
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
assert_eq "$(brew_log | grep -v '^python3 ')" "brew bundle --file=<tmp>/Brewfile --no-upgrade
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
brew tap otuerk/sidebar
brew trust --cask otuerk/sidebar/sidebar
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

# brew_flaky_stub N -> brew that logs its arguments, fails the first N
# "bundle --file" runs, and answers "bundle check" with a missing cask
brew_flaky_stub() {
  cat > "$SB/bin/brew" <<EOF
#!/bin/bash
echo "brew \$*" >> "$LOG"
case "\$*" in
  "bundle check"*) echo "brew bundle can't satisfy your Brewfile's dependencies."
    echo "→ Cask firefox needs to be installed."; exit 1 ;;
  "bundle --file"*)
    n=\$(cat "$SB/bundle-runs" 2>/dev/null || echo 0); echo \$((n + 1)) > "$SB/bundle-runs"
    [ "\$n" -lt "$1" ] && exit 1 ;;
esac
exit 0
EOF
  chmod +x "$SB/bin/brew"
}

it "third-party taps are tapped (with their URL) and their packages trusted one by one"
make_sandbox
SB_CATALOG="$SB/catalog.txt"
printf '%s\n' 'tool | formula | user/tap/tool | - | cli | a tapped formula' \
  'app | cask | other/tap/app | Some App | web | a tapped cask' \
  'gh | formula | gh | - | cli | GitHub CLI' > "$SB_CATALOG"
echo 'other/tap | https://github.com/Other/app-tap' > "$SB/taps.txt"
sandbox_config 'PACKAGES="@all"'
brew_stub
run_bootstrap --no-pull brew
SB_CATALOG=""
assert_eq "$RC" 0
assert_eq "$(brew_log | grep -v '^  |')" "brew tap user/tap
brew tap other/tap https://github.com/Other/app-tap
brew trust --formula user/tap/tool
brew trust --cask other/tap/app
brew bundle --file=<tmp>/Brewfile --no-upgrade"

it "a failing tap or trust only warns; the bundle still runs"
make_sandbox
brew_stub 0 otuerk
run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_contains "$OUT" "warn: brew tap otuerk/sidebar failed"
assert_contains "$OUT" "warn: brew trust failed - Homebrew may skip packages from third-party taps"
assert_contains "$(brew_log)" "brew bundle --file=<tmp>/Brewfile --no-upgrade"

it "a failed brew bundle is tried once more; a second success is ok"
make_sandbox
brew_flaky_stub 1
run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_eq "$(grep -c '^brew bundle --file' "$LOG")" 2
assert_contains "$OUT" "brew bundle failed - trying once more"
assert_contains "$OUT" "  brew       ok"

it "a brew bundle that fails twice names what is still missing"
make_sandbox
brew_flaky_stub 9
run_bootstrap --no-pull brew
assert_eq "$RC" 1
assert_eq "$(grep -c '^brew bundle --file' "$LOG")" 2
assert_contains "$OUT" "  still missing: Cask firefox"
assert_contains "$OUT" "  brew       failed   (brew bundle)"

it "Rosetta is installed when a selected package needs it and it is missing"
make_sandbox
SB_CATALOG="$SB/catalog.txt"
printf '%s\n' 'steam | cask | steam | Steam | media | Steam games' 'vlc | cask | vlc | VLC | media | player' > "$SB_CATALOG"
sandbox_config 'PACKAGES="@all"'
brew_stub
stub "$SB/bin/arch" arch 1
run_bootstrap --no-pull brew
assert_eq "$RC" 0
assert_contains "$(cat "$LOG")" "sudo softwareupdate --install-rosetta --agree-to-license"
: > "$LOG"
stub "$SB/bin/arch" arch 0
run_bootstrap --no-pull brew
assert_not_contains "$(cat "$LOG")" "softwareupdate"
: > "$LOG"
stub "$SB/bin/arch" arch 1
sandbox_config 'PACKAGES="vlc"'
run_bootstrap --no-pull brew
assert_not_contains "$(cat "$LOG")" "softwareupdate"
: > "$LOG"
sandbox_config 'PACKAGES="@all"'
stub "$SB/bin/sudo" sudo 1
run_bootstrap --no-pull brew
SB_CATALOG=""
assert_eq "$RC" 0
assert_contains "$OUT" "warn: Rosetta install failed - steam needs it to start"

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
assert_eq "$(cat "$LOG")" "curl --proto =https --tlsv1.2 -fsSL $SCRIPT_URL
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
assert_contains "$OUT" "+ curl --proto '=https' --tlsv1.2 -fsSL $SCRIPT_URL | bash"
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

it "commands in ~/.local/bin and ~/go/bin count as installed, also for brew"
extras_sandbox "hf gopls"
stub "$SB/home/.local/bin/hf" hf
stub "$SB/home/go/bin/gopls" gopls
brew_stub
run_bootstrap --no-pull brew extras
SB_CATALOG=""
assert_eq "$RC" 0
assert_not_contains "$(cat "$LOG")" "pipx"
assert_not_contains "$(cat "$LOG")" "go install"
assert_contains "$OUT" "hf: hf already installed"
assert_contains "$OUT" "gopls: gopls already installed"

it "an install whose command is still not on PATH says so"
extras_sandbox "nano-pdf"
run_bootstrap --no-pull extras
SB_CATALOG=""
assert_eq "$RC" 0
assert_contains "$OUT" "nano-pdf: installed, but nano-pdf is not on PATH"

it "extras finds Homebrew's tools when brew is not on PATH"
extras_sandbox "hf"
rm "$SB/bin/brew" "$SB/bin/pipx"
stub "$SB/homebrew/bin/brew" brew
stub "$SB/homebrew/bin/pipx" pipx
run_bootstrap --no-pull extras
SB_CATALOG=""
assert_eq "$RC" 0
assert_eq "$(cat "$LOG")" "pipx install huggingface-hub"

it "the brew run pulls in pipx for a selected pipx package"
extras_sandbox "hf"
brew_stub
run_bootstrap --no-pull brew
SB_CATALOG=""
assert_contains "$(cat "$LOG")" '  | brew "pipx"'

# nas_sandbox [CONFIG_LINE...] -> sandbox with nas-mount selected; osacompile
# "builds" an app dir holding the source, osadecompile prints it back
nas_sandbox() {
  make_sandbox
  sandbox_config 'PACKAGES="nas-mount"' "$@"
  printf '#!/bin/bash\necho "osacompile $*" >> "%s"\nmkdir -p "$2" && cp "$3" "$2/source"\n' "$LOG" > "$SB/bin/osacompile"
  printf '#!/bin/bash\ncat "$1/source"\n' > "$SB/bin/osadecompile"
  chmod +x "$SB/bin/osacompile" "$SB/bin/osadecompile"
}
nas_app() { echo "$SB/Applications/nas-mount.app"; }

it "extras builds nas-mount with one try per share"
nas_sandbox 'NAS_MOUNT_SHARES="smb://nas/a smb://nas/b"'
run_bootstrap --no-pull extras
assert_eq "$RC" 0
assert_contains "$(cat "$(nas_app)/source")" '{"smb://nas/a", "smb://nas/b"}'
assert_contains "$OUT" "nas-mount: installed"
assert_contains "$OUT" "  extras     ok"
[ -z "$(ls -A "$SB/tmp")" ] || fail "temp build dir left behind"

it "an unchanged nas-mount is left alone; a changed one replaced, the old one in the Trash"
run_bootstrap --no-pull extras
assert_contains "$OUT" "nas-mount: unchanged"
[ -e "$SB/home/.Trash" ] && fail "trashed an unchanged app"
sandbox_config 'PACKAGES="nas-mount"' 'NAS_MOUNT_SHARES="smb://nas/c"'
run_bootstrap --no-pull extras
assert_contains "$OUT" "nas-mount: updated (old one in the Trash)"
assert_contains "$(cat "$(nas_app)/source")" '{"smb://nas/c"}'
assert_contains "$(cat "$SB/home/.Trash"/nas-mount-*.app/source)" '"smb://nas/a"'

it "a failing build fails nas-mount and keeps the installed app"
nas_sandbox 'NAS_MOUNT_SHARES="smb://nas/new"'
mkdir -p "$(nas_app)"; echo old > "$(nas_app)/source"
printf '#!/bin/bash\necho "compile error" >&2\nexit 1\n' > "$SB/bin/osacompile"
run_bootstrap --no-pull extras
assert_eq "$RC" 1
assert_contains "$OUT" "  extras     failed   (failed: nas-mount)"
assert_contains "$OUT" "compile error"
assert_eq "$(cat "$(nas_app)/source")" old

it "nas-mount without shares is skipped with a hint"
nas_sandbox
run_bootstrap --no-pull extras
assert_eq "$RC" 0
assert_contains "$OUT" "nas-mount: skipped - set NAS_MOUNT_SHARES in the config"
assert_contains "$OUT" "  extras     skipped  (set NAS_MOUNT_SHARES in the config for: nas-mount)"
assert_not_contains "$(cat "$LOG")" "osacompile"
[ -e "$(nas_app)" ] && fail "built without shares"
extras_sandbox "sass"
printf '%s\n' 'nas-mount | applet | packages/nas-mount.applescript | nas-mount | remote | NAS' >> "$SB_CATALOG"
sandbox_config 'PACKAGES="sass nas-mount"'
rm "$SB/bin/npm"
run_bootstrap --no-pull extras
SB_CATALOG=""
assert_contains "$OUT" "  extras     skipped  (install Node first (e.g. nvm install --lts) for: sass; set NAS_MOUNT_SHARES in the config for: nas-mount)"

it "dry run shows the nas-mount build, builds nothing"
nas_sandbox 'NAS_MOUNT_SHARES="smb://nas/a"'
run_bootstrap --dry-run --no-pull extras
assert_eq "$RC" 0
assert_contains "$OUT" "+ osacompile -o $(nas_app) (packages/nas-mount.applescript with NAS_MOUNT_SHARES)"
assert_eq "$(cat "$LOG")" ""
[ -e "$(nas_app)" ] && fail "built in dry run"

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
assert_eq "$PACKAGES" "@base"
assert_eq "$SETTINGS_DIR" "$REPO"
assert_eq "$NAS_MOUNT_SHARES" ""
for key in BOOTSTRAP_STEPS BOOTSTRAP_SKIP PACKAGES BREW_BUNDLE_EXTRA MACOS_DISABLE_GATEKEEPER SETTINGS_DIR NAS_MOUNT_SHARES DOTFILES_DIR DOTFILES_URL DOTFILES_ASSUME_YES DOTFILES_TERMINALS DOTFILES_OMNISHELL_CONFIG DOTFILES_LOCAL_RC; do
  assert_contains "$(cat "$REPO/config.example.sh")" "$key="
done

it "the PACKAGES example in config.example.sh names real packages"
example="$(sed -n '/^# --- packages/,/^PACKAGES=/p' "$REPO/config.example.sh" | tr '\n' ' ' | sed -n 's/.*e\.g\. "\([^"]*\)".*/\1/p')"
[ -n "$example" ] || fail "no PACKAGES example found"
select_packages "$example" >/dev/null || fail "example does not resolve: $example"

it "the commented example in config.example.sh is a valid DOTFILES_LOCAL_RC"
example="$(sed -n "/^#   DOTFILES_LOCAL_RC='/,/^#   '\$/s/^#   //p" "$REPO/config.example.sh")"
assert_contains "$example" "kdash-token"
f="$(write_config "$example")"
load_config "$f"; rc=$?
assert_eq "$rc" 0
assert_contains "$DOTFILES_LOCAL_RC" "create token admin-user"

echo "all $COUNT cases passed"
