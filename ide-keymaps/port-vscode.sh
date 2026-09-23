#!/usr/bin/env bash
# Port the active JetBrains keymap into the VS Code family (VS Code,
# Antigravity, ...) with intelli-key-port and this machine's layers.
#
#   ./port-vscode.sh              resolve + generate + install (editor picker)
#   ./port-vscode.sh --dry-run    preview the install
#   ./port-vscode.sh --only Code  any further intelli-key-port/port.py flag
#
# Layers, stacked in this order on intelli-key-port's neutral base:
#   windows-keymap           the keymap is Ctrl-based (parent: Default for XWin)
#   karabiner-winkeys        the Karabiner [winkeys] rules are installed
#   intelli-key-port-personal.jsonc (next to this script)  personal choices
#
# Always port through this script: a bare ./port.py in intelli-key-port runs
# without these layers and installs a plain port over the current bindings.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# intelli-key-port is a sibling of macos-base-config, wherever that was cloned
PARENT_DIR="$(cd "$HERE/../.." && pwd)"
PORT="$PARENT_DIR/intelli-key-port/port.py"

[ -f "$PORT" ] || { echo "missing $PORT - run ../bootstrap.sh, it clones intelli-key-port"; exit 1; }

exec python3 "$PORT" \
  --layer windows-keymap \
  --layer karabiner-winkeys \
  --layer "$HERE/intelli-key-port-personal.jsonc" \
  "$@"
