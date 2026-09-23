#!/usr/bin/env bash
# Step table, argument parsing and step selection for bootstrap.sh.
# Sourced; defines data and functions only, no side effects.

# Execution order. Every name has a step_<name> function in lib/steps.sh.
ALL_STEPS="repos brew extras karabiner keyboard macos jetbrains vscode editor apps dotfiles manual"

step_description() {
  case "$1" in
    repos)     echo "clone missing / pull existing sibling repos (repos.txt)" ;;
    brew)      echo "install Homebrew if missing, then the selected brew / App Store packages (PACKAGES)" ;;
    extras)    echo "install the selected packages that don't come from Homebrew (script, npm, pipx, uv, go) and build the nas-mount app" ;;
    karabiner) echo "apply the Karabiner config (needs Karabiner-Elements)" ;;
    keyboard)  echo "install and enable the Custom Swiss German keyboard layout" ;;
    macos)     echo "macOS defaults: system hotkeys, Finder shortcut, font smoothing, Gatekeeper" ;;
    jetbrains) echo "JetBrains keymap into the PhpStorm / IntelliJ config" ;;
    vscode)    echo "port the keymap to VS Code / Antigravity" ;;
    editor)    echo "editor font settings for every VS Code-family editor" ;;
    apps)      echo "AltTab settings; Sidebar backup into its backup list, from SETTINGS_DIR (no licenses)" ;;
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
  # -d '': read the whole value, not just its first line (config lists may
  # span lines); read -a never glob-expands. Exits 1 at EOF by design.
  read -r -d '' -a words <<< "$1"
  if [ ${#words[@]} -eq 0 ]; then
    wanted="$ALL_STEPS"
  else
    wanted="$(expand_names "${words[@]}")" || return 2
  fi
  read -r -d '' -a words <<< "$2"
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

# parse_args ARG... -> sets ACTION (run|list|list-packages|help), CLI_STEPS, CLI_SKIP,
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
      --list-packages) ACTION=list-packages ;;
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
  --list-packages   list the package catalog, the selection and what is installed
  -h, --help        this help
EOF
}
