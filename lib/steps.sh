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

# overridable so tests can point them into a sandbox
KARABINER_APP="${KARABINER_APP:-/Applications/Karabiner-Elements.app}"
# seconds to wait for ~/.config/karabiner after starting Karabiner-Elements
KARABINER_WAIT_SECONDS="${KARABINER_WAIT_SECONDS:-10}"
# where Homebrew lives when it is installed but not on PATH (Apple silicon, Intel)
BREW_CANDIDATES="${BREW_CANDIDATES:-/opt/homebrew/bin/brew /usr/local/bin/brew}"
HOMEBREW_INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
# system-wide keyboard layouts (a copy there needs sudo) and the swift binary
KEYBOARD_SYSTEM_DIR="${KEYBOARD_SYSTEM_DIR:-/Library/Keyboard Layouts}"
SWIFT="${SWIFT:-swift}"
KEYBOARD_LAYOUT_NAME="Custom Swiss German"
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

# find_brew -> 0 when brew is usable; a brew found in BREW_CANDIDATES but not
# on PATH is put on PATH for the rest of the run
find_brew() {
  local candidate
  command -v brew >/dev/null 2>&1 && return 0
  for candidate in $BREW_CANDIDATES; do
    if [ -x "$candidate" ]; then
      PATH="$(dirname "$candidate"):$PATH"
      export PATH
      return 0
    fi
  done
  return 1
}

# install_homebrew -> run the official installer (asks for the sudo password)
install_homebrew() {
  local installer
  echo "+ install Homebrew: /bin/bash -c \"\$(curl -fsSL $HOMEBREW_INSTALLER_URL)\""
  $DRY_RUN && return 0
  installer="$(curl -fsSL "$HOMEBREW_INSTALLER_URL")" || return 1
  /bin/bash -c "$installer" && find_brew
}

# init_config URL DIR -> clone the private config repo into DIR (the config
# dir) when DIR is missing or empty. A checkout of URL is left as it is; a
# checkout of another URL or a dir with other files is exit 2, untouched.
init_config() {
  local url="$1" dir="$2" origin
  if [ -d "$dir/.git" ]; then
    origin="$(git -C "$dir" remote get-url origin 2>/dev/null)"
    if [ "$origin" = "$url" ]; then
      echo "already set up: $dir is a checkout of $url"
      return 0
    fi
    echo "bootstrap.sh: $dir is a checkout of ${origin:-an unknown remote}, not $url" >&2
    return 2
  fi
  if [ -d "$dir" ] && [ -n "$(ls -A "$dir")" ]; then
    echo "bootstrap.sh: $dir already has files - move them away first, or make it a checkout of $url yourself" >&2
    return 2
  fi
  run_cmd mkdir -p "$(dirname "$dir")" && run_cmd git clone "$url" "$dir" || return 1
  $DRY_RUN || echo "cloned $url into $dir - next: ./bootstrap.sh"
}

# pull_config_repo -> update the private config checkout (the dir of the
# config file) like a sibling repo: never with local changes, a failed pull
# only warns. A pulled config.sh takes effect on the next run.
pull_config_repo() {
  local dir
  dir="$(dirname "$CONFIG_FILE")"
  [ -d "$dir/.git" ] || return 0
  $NO_PULL && return 0
  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    echo "  warn: local changes in $dir - not pulled" >&2
    return 0
  fi
  run_cmd git -C "$dir" pull --ff-only ||
    echo "  warn: pull failed in $dir - using the existing checkout" >&2
  return 0
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
  pull_config_repo
  return $failed
}

# brew_bundle BREWFILE -> install what BREWFILE lists; nothing already
# installed is upgraded (the apps update themselves)
brew_bundle() {
  run_cmd brew bundle --file="$1" --no-upgrade
}

# bundle_brewfile FILE -> show what FILE installs, then brew bundle it
bundle_brewfile() {
  sed 's/^/    /' "$1"
  brew_bundle "$1"
}

step_brew() {
  local tmp_root="${TMPDIR:-/tmp}" dir failed=""
  if ! find_brew && ! install_homebrew; then
    STEP_FAIL_REASON="Homebrew install failed"
    return 1
  fi
  dir="$(mktemp -d "${tmp_root%/}/macos-base-config.XXXXXX")" || return 1
  # packages in ~/.local/bin / ~/go/bin count as installed: no pipx / uv / go for them
  user_bin_dirs_on_path
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

# install_extra SOURCE REF -> install one package of an extras source (dry
# run: print only). A script is fetched first, then run, like the Homebrew
# installer.
install_extra() {
  local installer
  case "$1" in
    script)
      echo "+ curl --proto '=https' --tlsv1.2 -fsSL $2 | bash"
      $DRY_RUN && return 0
      installer="$(curl --proto '=https' --tlsv1.2 -fsSL "$2")" || return 1
      /bin/bash -c "$installer" ;;
    npm) run_cmd npm install -g "$2" ;;
    pipx) run_cmd pipx install "$2" ;;
    uv) run_cmd uv tool install "$2" ;;
    go) run_cmd go install "$2@latest" ;;
  esac
}

# install_applet ID REF CHECK -> build CHECK.app from the template REF (a
# path in this repo) and NAS_MOUNT_SHARES. The installed app is replaced only
# when its script differs; the old one goes to the Trash. 0 ok, 1 failed,
# 2 skipped (no shares).
install_applet() {
  local id="$1" template="$HERE/$2" target="$APPLICATIONS_DIR/$3.app"
  local tmp_root="${TMPDIR:-/tmp}" build
  if [ -z "$NAS_MOUNT_SHARES" ]; then
    echo "  $id: skipped - set NAS_MOUNT_SHARES in the config"
    return 2
  fi
  if $DRY_RUN; then
    echo "+ osacompile -o $target ($2 with NAS_MOUNT_SHARES)"
    return 0
  fi
  build="$(mktemp -d "${tmp_root%/}/applet.XXXXXX")" || return 1
  if ! applet_source "$template" > "$build/$3.applescript" ||
    ! osacompile -o "$build/$3.app" "$build/$3.applescript" 2> "$build/errors"; then
    echo "  $id: build failed" >&2
    cat "$build/errors" >&2
    rm -rf "$build"
    return 1
  fi
  if [ -d "$target" ] && [ "$(osadecompile "$target" 2>/dev/null)" = "$(osadecompile "$build/$3.app")" ]; then
    echo "  $id: unchanged"
  elif [ -d "$target" ]; then
    mkdir -p "$HOME/.Trash" &&
      mv "$target" "$HOME/.Trash/$3-$(date +%Y%m%d-%H%M%S).app" &&
      mv "$build/$3.app" "$target" || { rm -rf "$build"; return 1; }
    echo "  $id: updated (old one in the Trash)"
  else
    mv "$build/$3.app" "$target" || { rm -rf "$build"; return 1; }
    echo "  $id: installed"
  fi
  rm -rf "$build"
}

# step_extras -> install the selected script / npm / pipx / uv / go packages
# whose command is missing. The tools come from the brew step (npm: from
# Node, which nvm installs). The nas-mount applet is (re)built from its
# template. A failing package doesn't stop the others.
step_extras() {
  local rows id source ref check _category _description tool
  local selected=false failed="" need_node="" need_shares="" rc
  rows="$(catalog_rows)" || { STEP_FAIL_REASON="package catalog"; return 1; }
  # Homebrew's pipx / uv / go, also when brew isn't on this shell's PATH yet
  find_brew >/dev/null 2>&1 || true
  user_bin_dirs_on_path
  # rows on fd 3: an installer that reads stdin must not eat the rest
  while IFS=$'\t' read -r id source ref check _category _description <&3; do
    case " $SELECTED_PACKAGES " in *" $id "*) ;; *) continue ;; esac
    case "$source" in script | npm | pipx | uv | go | applet) ;; *) continue ;; esac
    selected=true
    if [ "$source" = applet ]; then
      rc=0
      install_applet "$id" "$ref" "$check" || rc=$?
      case "$rc" in
        0) ;;
        2) need_shares="$need_shares $id" ;;
        *) failed="$failed $id" ;;
      esac
      continue
    fi
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
    if ! install_extra "$source" "$ref"; then
      failed="$failed $id"
    elif ! $DRY_RUN && ! command -v "$check" >/dev/null 2>&1; then
      echo "  $id: installed, but $check is not on PATH - add its directory to PATH (e.g. in the dotfiles)"
    fi
  done 3<<< "$rows"
  if ! $selected; then
    skip "no extra packages selected"
    return 0
  fi
  if [ -n "$failed" ]; then
    STEP_FAIL_REASON="failed:$failed"
    return 1
  fi
  local reason=""
  [ -z "$need_node" ] || reason="install Node first (e.g. nvm install --lts) for:$need_node"
  [ -z "$need_shares" ] || reason="${reason:+$reason; }set NAS_MOUNT_SHARES in the config for:$need_shares"
  [ -z "$reason" ] || skip "$reason"
  return 0
}

# wait_for_karabiner_config -> start Karabiner-Elements once so it creates
# ~/.config/karabiner (apply.sh needs it); 1 if it doesn't appear in time
wait_for_karabiner_config() {
  local config_dir="$HOME/.config/karabiner" tries
  [ -d "$config_dir" ] && return 0
  run_cmd open -ga Karabiner-Elements || true
  $DRY_RUN && return 0
  tries=$((KARABINER_WAIT_SECONDS * 2))
  while [ ! -d "$config_dir" ] && [ "$tries" -gt 0 ]; do
    sleep 0.5
    tries=$((tries - 1))
  done
  [ -d "$config_dir" ]
}

step_karabiner() {
  local name=karabiner-windows-keyboard-mapping-macos
  local dir="$PARENT_DIR/$name"
  if [ ! -d "$KARABINER_APP" ]; then
    skip "Karabiner-Elements not installed - add karabiner-elements to PACKAGES, then run ./bootstrap.sh brew"
    return 0
  fi
  if ! wait_for_karabiner_config; then
    STEP_FAIL_REASON="no ~/.config/karabiner - open Karabiner-Elements once"
    return 1
  fi
  ensure_sibling "$name" "$(sibling_url "$name")" "$dir" || return 1
  run_in "$dir" ./apply.sh
}

# without_xml_comments FILE -> FILE minus its <!-- ... --> lines (layout
# editors like Ukelele stamp the export date into them)
without_xml_comments() { sed '/<!--/,/-->/d' "$1"; }

# installed_layout SRC_DIR -> the path of an installed copy of SRC_DIR's
# CustomSwissGerman.keylayout (~/Library first), empty if none. Copies that
# differ only in comments count as the same layout.
installed_layout() {
  local src="$1/CustomSwissGerman.keylayout" dir installed
  for dir in "$HOME/Library/Keyboard Layouts" "$KEYBOARD_SYSTEM_DIR"; do
    installed="$dir/CustomSwissGerman.keylayout"
    [ -f "$installed" ] || continue
    if [ "$(without_xml_comments "$src")" = "$(without_xml_comments "$installed")" ]; then
      echo "$installed"
      return 0
    fi
  done
}

step_keyboard() {
  local name=swiss-windows-keyboard-layout-macos dir layout
  local user_dir="$HOME/Library/Keyboard Layouts"
  local enable_hint="enable '$KEYBOARD_LAYOUT_NAME' under System Settings > Keyboard > Input Sources, then log out and in"
  dir="$PARENT_DIR/$name"
  ensure_sibling "$name" "$(sibling_url "$name")" "$dir" || return 1
  if [ ! -f "$dir/CustomSwissGerman.keylayout" ]; then
    $DRY_RUN && return 0
    STEP_FAIL_REASON="no CustomSwissGerman.keylayout in $dir"
    return 1
  fi

  layout="$(installed_layout "$dir")"
  if [ -n "$layout" ]; then
    echo "  layout already installed: $layout"
  elif [ -e "$KEYBOARD_SYSTEM_DIR/CustomSwissGerman.keylayout" ]; then
    # a user copy next to it would show the layout twice in the menu
    skip "an older $KEYBOARD_LAYOUT_NAME is in $KEYBOARD_SYSTEM_DIR - update it: sudo cp \"$dir\"/CustomSwissGerman.* \"$KEYBOARD_SYSTEM_DIR/\""
    return 0
  else
    layout="$user_dir/CustomSwissGerman.keylayout"
    run_cmd mkdir -p "$user_dir" &&
      run_cmd cp "$dir/CustomSwissGerman.keylayout" "$dir/CustomSwissGerman.icns" "$user_dir/" || return 1
  fi

  if ! command -v "$SWIFT" >/dev/null 2>&1 ||
    ! run_cmd "$SWIFT" "$HERE/enable-input-source.swift" "$layout" "$KEYBOARD_LAYOUT_NAME"; then
    skip "$enable_hint"
  fi
}

# disable_gatekeeper -> allow apps from anywhere; macOS asks to confirm it in
# Privacy & Security, so that pane is opened. Since macOS 15, spctl only
# requests the change and fails with "needs to be confirmed in System
# Settings" - that is the expected outcome, not an error.
disable_gatekeeper() {
  local out
  if spctl --status 2>/dev/null | grep -q 'assessments disabled'; then
    echo "  Gatekeeper: already off"
    return 0
  fi
  echo "+ sudo spctl --master-disable"
  if ! $DRY_RUN && ! out="$(sudo spctl --master-disable 2>&1)"; then
    [ -n "$out" ] && echo "$out"
    case "$out" in
      *"needs to be confirmed in System Settings"*) ;;
      *) return 1 ;;
    esac
  elif [ -n "${out:-}" ]; then
    echo "$out"
  fi
  run_cmd open "x-apple.systempreferences:com.apple.preference.security?General" || true
  echo "  Gatekeeper: confirm 'Allow applications from: Anywhere' under Privacy & Security"
}

step_macos() {
  run_in "$HERE" python3 macos-defaults.py || return 1
  [ "$MACOS_DISABLE_GATEKEEPER" = 1 ] || return 0
  if ! disable_gatekeeper; then
    STEP_FAIL_REASON="Gatekeeper"
    return 1
  fi
}

step_jetbrains() {
  if ! has_jetbrains_config; then
    skip "no JetBrains config yet - start PhpStorm once, then run: ./bootstrap.sh keymaps"
    return 0
  fi
  local rc=0
  run_in "$HERE/ide-keymaps" ./apply.sh || rc=$?
  case "$rc" in
    0) ;;
    75) skip "a JetBrains IDE is running - quit it, then run: ./bootstrap.sh jetbrains" ;;
    *) return 1 ;;
  esac
}

step_vscode() {
  if ! has_jetbrains_config; then
    skip "no JetBrains config yet - start PhpStorm once, then run: ./bootstrap.sh keymaps"
    return 0
  fi
  ensure_sibling intelli-key-port "$(sibling_url intelli-key-port)" "$PARENT_DIR/intelli-key-port" || return 1
  run_in "$HERE/ide-keymaps" ./port-vscode.sh
}

step_editor() {
  run_in "$HERE/editor-settings" python3 apply.py
}

# save_settings [ID...] -> export the app settings (all, or these registry
# ids) into SETTINGS_DIR; the secret guard checks every file. When
# SETTINGS_DIR is in a git repo (the private config repo), show what changed -
# committing is left to you. Returns the export's exit code.
save_settings() {
  local rc=0
  if $DRY_RUN; then
    echo "+ python3 $HERE/apps/app_settings.py export --dir $SETTINGS_DIR $*"
    return 0
  fi
  show_cmd python3 "$HERE/apps/app_settings.py" export --dir "$SETTINGS_DIR" "$@" || rc=$?
  if git -C "$SETTINGS_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo
    git -C "$SETTINGS_DIR" status --short
    git -C "$SETTINGS_DIR" diff --stat
    echo "  review the changes, then commit and push them in $SETTINGS_DIR"
  fi
  return $rc
}

step_apps() {
  if [ ! -d "$SETTINGS_DIR" ]; then
    skip "no settings dir: $SETTINGS_DIR"
    return 0
  fi
  run_in "$HERE/apps" python3 app_settings.py apply --dir "$SETTINGS_DIR"
}

LOCAL_RC_BEGIN="# >>> macos-base-config >>>"
LOCAL_RC_END="# <<< macos-base-config <<<"

# write_local_rc FILE -> replace the managed block in FILE with
# $DOTFILES_LOCAL_RC (remove it when empty); everything else in FILE stays.
# A new FILE is created private: these files may hold tokens.
write_local_rc() {
  local file="$1" tmp
  if [ -z "$DOTFILES_LOCAL_RC" ] && ! grep -qxF "$LOCAL_RC_BEGIN" "$file" 2>/dev/null; then
    return 0
  fi
  if $DRY_RUN; then
    echo "+ update the macos-base-config block in $file"
    return 0
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/local-rc.XXXXXX")" || return 1
  {
    [ -f "$file" ] && awk -v begin="$LOCAL_RC_BEGIN" -v end="$LOCAL_RC_END" '
      $0 == begin { inside = 1; next }
      $0 == end   { inside = 0; next }
      !inside' "$file"
    if [ -n "$DOTFILES_LOCAL_RC" ]; then
      echo "$LOCAL_RC_BEGIN"
      echo "# managed by macos-base-config (DOTFILES_LOCAL_RC) - edit its config.sh, not this block"
      printf '%s\n' "$DOTFILES_LOCAL_RC"
      echo "$LOCAL_RC_END"
    fi
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  [ -e "$file" ] || ( umask 077 && : > "$file" ) || { rm -f "$tmp"; return 1; }
  # cat instead of mv: keeps the file's permissions and a symlinked rc file
  echo "+ update the macos-base-config block in $file"
  cat "$tmp" > "$file" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
}

# The dotfiles bootstrap exits non-zero when its "repoint every stow link to
# this checkout?" prompt is declined or has no terminal to ask - its own hint
# (--yes) is not an option here. The exit code can't tell that apart from other
# failures, so the hint is conditional.
explain_dotfiles_checkout_prompt() {
  echo "  hint: if it stopped at \"repoint every stow link ...?\" (declined, or no terminal to ask):" >&2
  if [ "$DOTFILES_ASSUME_YES" != 1 ]; then
    echo "        - set DOTFILES_ASSUME_YES=1 in $CONFIG_FILE to switch without asking, or" >&2
  fi
  echo "        - set DOTFILES_DIR in $CONFIG_FILE to the checkout the links already use" >&2
}

step_dotfiles() {
  local dir omnishell_target rc=0
  dir="$(sibling_dir dotfiles)"
  ensure_sibling dotfiles "$(dotfiles_url)" "$dir" || return 1
  if ! find_brew; then
    echo "  Homebrew required - run ./bootstrap.sh brew" >&2
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
      explain_dotfiles_checkout_prompt
      return 1
    fi
  fi

  if ! { write_local_rc "$HOME/.zshrc.local" && write_local_rc "$HOME/.bashrc.local"; }; then
    STEP_FAIL_REASON="local rc"
    return 1
  fi

  [ -n "$DOTFILES_OMNISHELL_CONFIG" ] || return 0
  # after the dotfiles bootstrap, which installs the repo's own copy every run
  omnishell_target="${XDG_CONFIG_HOME:-$HOME/.config}/omnishell/config.toml"
  if ! { run_cmd mkdir -p "$(dirname "$omnishell_target")" &&
    run_cmd cp "$DOTFILES_OMNISHELL_CONFIG" "$omnishell_target"; }; then
    STEP_FAIL_REASON="omnishell config"
    return 1
  fi
  # exit 1 = degraded module(s): a state, not a crash (same as the dotfiles
  # bootstrap treats it); >= 2 = a real error
  run_cmd omnishell apply -y || rc=$?
  case "$rc" in
    0) ;;
    1) echo "  warn: omnishell reports degraded module(s) - see 'omnishell doctor'" >&2 ;;
    *) STEP_FAIL_REASON="omnishell apply exit $rc"
       return 1 ;;
  esac
}

step_manual() {
  local licensed="" app count=0 last=""
  echo "  - Karabiner permissions: karabiner-windows-keyboard-mapping-macos/setup.sh opens the panes"
  echo "  - Input source: check '$KEYBOARD_LAYOUT_NAME' under System Settings > Keyboard > Input Sources, then log out and in"
  if [ "$MACOS_DISABLE_GATEKEEPER" = 1 ]; then
    echo "  - Gatekeeper: confirm 'Allow applications from: Anywhere' under Privacy & Security"
  fi
  if [ -d "$APPLICATIONS_DIR/Sidebar.app" ] && [ -f "$SETTINGS_DIR/sidebar.sidebarbackup" ]; then
    echo "  - Sidebar settings: Settings > Expert > Backups > restore the backup the apps step added"
  fi
  for app in "AltTab:AltTab (Pro)" "Sidebar:Sidebar" "Shottr:Shottr"; do
    [ -d "$APPLICATIONS_DIR/${app%%:*}.app" ] || continue
    [ -n "$last" ] && licensed="${licensed:+$licensed, }$last"
    last="${app#*:}"
    count=$((count + 1))
  done
  case "$count" in
    0) ;;
    1) echo "  - Licenses: enter the $last key from your password manager" ;;
    *) echo "  - Licenses: enter the $licensed and $last keys from your password manager" ;;
  esac
  if [ -d "$APPLICATIONS_DIR/Tabby.app" ] && [ -f "$SETTINGS_DIR/tabby.yaml" ]; then
    echo "  - Tabby: unlock its vault with the passphrase from your password manager"
  fi
  manual_package_hints "$SELECTED_PACKAGES"
}
