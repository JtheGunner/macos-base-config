#!/usr/bin/env bash
# Set up a fresh Mac: keyboard layout, Karabiner, macOS defaults, IDE keymaps
# and the dotfiles (shell, git, tmux, Ghostty).
#
#   ./bootstrap.sh                   run every step
#   ./bootstrap.sh keymaps dotfiles  run only these steps
#   ./bootstrap.sh --skip dotfiles   run every step but these
#   ./bootstrap.sh --dry-run         show what would happen
#   ./bootstrap.sh --list-packages   what PACKAGES can pick, and what is picked
#   ./bootstrap.sh --init-config URL clone your private config repo (new Mac)
#   ./bootstrap.sh --save-settings   save the app settings into SETTINGS_DIR
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
. "$HERE/lib/packages.sh"
. "$HERE/lib/config.sh"
. "$HERE/lib/steps.sh"

parse_args "$@" || exit 2
case "$ACTION" in
  help) usage; exit 0 ;;
  list) print_step_list; exit 0 ;;
esac
# before the config loads: on a new Mac it doesn't exist yet
if [ "$ACTION" = init-config ]; then
  init_config "$INIT_CONFIG_URL" "$(dirname "${CONFIG_PATH:-$(default_config_path)}")"
  exit $?
fi
load_config "$CONFIG_PATH" || exit 2
if [ "$ACTION" = list-packages ]; then
  user_bin_dirs_on_path
  print_package_list "$SELECTED_PACKAGES" || exit 2
  exit 0
fi
if [ "$ACTION" = save-settings ]; then
  # the words after --save-settings are app ids, not steps
  # shellcheck disable=SC2086
  save_settings $CLI_STEPS
  exit $?
fi

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
