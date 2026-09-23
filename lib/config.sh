#!/usr/bin/env bash
# Per-machine config for bootstrap.sh: defaults, loading the config file, and
# validation. Sourced; needs lib/cli.sh (select_steps) and lib/packages.sh
# (select_packages) loaded first.
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

# load_config [PATH] -> sets BOOTSTRAP_STEPS, BOOTSTRAP_SKIP, BREW_BUNDLE_EXTRA,
# PACKAGES (+ the resolved SELECTED_PACKAGES), MACOS_DISABLE_GATEKEEPER,
# SETTINGS_DIR (default: settings/ next to the config file, else its
# directory), NAS_MOUNT_SHARES, the DOTFILES_* values, and CONFIG_FILE (the
# file in use - PATH or the default path, even when that doesn't exist yet).
# Without PATH the default file is used if it exists. Return 2 on a missing
# explicit file, a syntax error, or an invalid value.
load_config() {
  local config_file="${1:-}"
  BOOTSTRAP_STEPS=""; BOOTSTRAP_SKIP=""; BREW_BUNDLE_EXTRA=""
  PACKAGES="@base"; SELECTED_PACKAGES=""
  MACOS_DISABLE_GATEKEEPER=0; SETTINGS_DIR=""; NAS_MOUNT_SHARES=""
  DOTFILES_DIR=""; DOTFILES_URL=""; DOTFILES_ASSUME_YES=0
  DOTFILES_TERMINALS=""; DOTFILES_OMNISHELL_CONFIG=""; DOTFILES_LOCAL_RC=""

  if [ -n "$config_file" ]; then
    [ -f "$config_file" ] || { echo "bootstrap.sh: config file not found: $config_file" >&2; return 2; }
  else
    config_file="$(default_config_path)"
  fi
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
}

# validate_config FILE -> normalises paths, checks every value; return 2 on error
validate_config() {
  local config_file="$1"
  DOTFILES_DIR="$(expand_home "$DOTFILES_DIR")"
  DOTFILES_OMNISHELL_CONFIG="$(expand_home "$DOTFILES_OMNISHELL_CONFIG")"
  BREW_BUNDLE_EXTRA="$(expand_home "$BREW_BUNDLE_EXTRA")"

  if ! select_steps "$BOOTSTRAP_STEPS" "$BOOTSTRAP_SKIP" >/dev/null; then
    echo "  in $config_file (BOOTSTRAP_STEPS / BOOTSTRAP_SKIP)" >&2
    return 2
  fi
  if ! SELECTED_PACKAGES="$(select_packages "$PACKAGES")"; then
    echo "  in $config_file (PACKAGES)" >&2
    return 2
  fi
  case "$MACOS_DISABLE_GATEKEEPER" in
    0 | 1) ;;
    *) echo "bootstrap.sh: $config_file: MACOS_DISABLE_GATEKEEPER must be 0 or 1, got '$MACOS_DISABLE_GATEKEEPER'" >&2
       return 2 ;;
  esac
  case "$DOTFILES_ASSUME_YES" in
    0 | 1) ;;
    *) echo "bootstrap.sh: $config_file: DOTFILES_ASSUME_YES must be 0 or 1, got '$DOTFILES_ASSUME_YES'" >&2
       return 2 ;;
  esac
  if [ -n "$BREW_BUNDLE_EXTRA" ] && { [ ! -f "$BREW_BUNDLE_EXTRA" ] || [ ! -r "$BREW_BUNDLE_EXTRA" ]; }; then
    echo "bootstrap.sh: $config_file: BREW_BUNDLE_EXTRA is not a readable file: $BREW_BUNDLE_EXTRA" >&2
    return 2
  fi
  # SETTINGS_DIR is handed to a script that runs from apps/: make it absolute,
  # a relative one relative to the config file
  local config_dir
  config_dir="$(dirname "$config_file")"
  case "$config_dir" in
    /*) ;;
    *) config_dir="$(cd "$config_dir" 2>/dev/null && pwd)" || config_dir="$PWD/$config_dir" ;;
  esac
  local settings_explicit=false
  SETTINGS_DIR="$(expand_home "$SETTINGS_DIR")"
  case "$SETTINGS_DIR" in
    # default: settings/ next to the config file (the private config repo's
    # layout), else the config file's folder itself (the older flat layout) -
    # one --config path locates everything private
    "") if [ -d "$config_dir/settings" ]; then SETTINGS_DIR="$config_dir/settings"; else SETTINGS_DIR="$config_dir"; fi ;;
    /*) settings_explicit=true ;;
    *) settings_explicit=true; SETTINGS_DIR="$config_dir/$SETTINGS_DIR" ;;
  esac
  if $settings_explicit && [ ! -d "$SETTINGS_DIR" ]; then
    echo "bootstrap.sh: $config_file: SETTINGS_DIR is not a directory: $SETTINGS_DIR" >&2
    return 2
  fi
  # the shares go into an AppleScript string: plain smb / afp / nfs URLs only
  local bad_share
  bad_share="$(printf '%s\n' "$NAS_MOUNT_SHARES" | awk '{
    for (i = 1; i <= NF; i++)
      if ($i !~ /^(smb|afp|nfs):\/\/[^"\\*?[]+$/) { print $i; exit }
  }')"
  if [ -n "$bad_share" ]; then
    echo "bootstrap.sh: $config_file: NAS_MOUNT_SHARES: not an smb://, afp:// or nfs:// URL: $bad_share" >&2
    return 2
  fi
  if [ -n "$DOTFILES_OMNISHELL_CONFIG" ] && { [ ! -f "$DOTFILES_OMNISHELL_CONFIG" ] || [ ! -r "$DOTFILES_OMNISHELL_CONFIG" ]; }; then
    echo "bootstrap.sh: $config_file: DOTFILES_OMNISHELL_CONFIG is not a readable file: $DOTFILES_OMNISHELL_CONFIG" >&2
    return 2
  fi
  # sourced by zsh and bash later - catch a broken snippet before any step runs
  # (bash 3.2's -n can exit 0 on a syntax error, so any message counts as one)
  local syntax_errors
  if [ -n "$DOTFILES_LOCAL_RC" ] &&
    { ! syntax_errors="$(printf '%s\n' "$DOTFILES_LOCAL_RC" | "$BASH" -n 2>&1)" || [ -n "$syntax_errors" ]; }; then
    echo "$syntax_errors" >&2
    echo "bootstrap.sh: $config_file: DOTFILES_LOCAL_RC has a syntax error" >&2
    return 2
  fi
}
