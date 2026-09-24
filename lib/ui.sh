#!/usr/bin/env bash
# How bootstrap.sh talks to you: colours for its own lines, warnings, and
# whether it may wait for input. Sourced.
#
# Colours only when stdout is a terminal and NO_COLOR is unset; UI_COLOR=1 / 0
# forces them on / off. Output of other tools (brew, npm, ...) stays as is -
# bootstrap.sh's coloured lines stand out from it.

ui_init() {
  local on=false
  case "${UI_COLOR:-}" in
    1) on=true ;;
    0) ;;
    *) if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then on=true; fi ;;
  esac
  if $on; then
    C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_RED=$'\033[31m' C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m' C_MAGENTA=$'\033[35m' C_CYAN=$'\033[36m' C_RESET=$'\033[0m'
  else
    C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_MAGENTA="" C_CYAN="" C_RESET=""
  fi
}

# is_interactive -> 0 when a person can answer: stdin and stdout are a
# terminal. BOOTSTRAP_INTERACTIVE=1 / 0 forces it (tests).
is_interactive() {
  case "${BOOTSTRAP_INTERACTIVE:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  [ -t 0 ] && [ -t 1 ]
}

# may_wait -> 0 when bootstrap.sh may stop and wait for you: interactive,
# no dry run, no --yes
may_wait() { is_interactive && ! $DRY_RUN && ! $ASSUME_YES; }

ui_header() { printf '\n%s== %s%s%s\n' "$C_BOLD$C_CYAN" "$1" "$C_RESET" "${2:+ $2}"; }

# warn MSG -> "  warn: MSG" on stderr, yellow
warn() { printf '%s  warn: %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }

# note MSG -> "  note: MSG", yellow: something to know before it happens
note() { printf '%s  note: %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }

# status_color STATUS -> the colour for a summary status
status_color() {
  case "$1" in
    ok) printf '%s' "$C_GREEN" ;;
    skipped) printf '%s' "$C_YELLOW" ;;
    failed) printf '%s' "$C_RED" ;;
  esac
}

ui_init
