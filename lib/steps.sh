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
  echo "  - Karabiner permissions: karabiner-windows-keyboard-mapping-macos/setup.sh prints them"
  echo "  - Swiss keyboard layout: swiss-windows-keyboard-layout-macos/README.md"
  echo "  - PhpStorm: Settings > Tools > Terminal > 'Use Option as Meta key' off (AltGr in the console)"
  echo "  - see README.md 'Manual steps' (VoiceOver off, Gatekeeper, AltTab, uBar)"
}
