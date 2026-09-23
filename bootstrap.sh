#!/usr/bin/env bash
# Set up a fresh Mac's keyboard / desktop behaviour.
#
#   ./bootstrap.sh              clone/pull the sibling repos, apply everything
#   ./bootstrap.sh --dry-run    show what would happen
#
# Each step is best-effort: a missing piece prints a note, it does not abort
# the rest. Re-runnable.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECTS="$(cd "$HERE/.." && pwd)"          # ~/Projects
DRY=false; DRYFLAG=()
[[ "${1:-}" == "--dry-run" ]] && { DRY=true; DRYFLAG=(--dry-run); }
# git ops: skipped in dry mode. sub-tools: always run (they get --dry-run).
run() { echo "+ $*"; $DRY || "$@"; }
step() { echo "+ $*"; "$@"; }

echo "== sibling repos (into $PROJECTS)"
while read -r name url apply _; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue
  dst="$PROJECTS/$name"
  if [[ -d "$dst/.git" ]]; then run git -C "$dst" pull --ff-only
  else run git -C "$PROJECTS" clone "$url" "$name"; fi
  if [[ -n "${apply:-}" && -x "$dst/${apply#./}" ]]; then
    ( cd "$dst" && step "$apply" "${DRYFLAG[@]}" )
  elif [[ -f "$dst/README.md" ]]; then
    echo "  -> manual: see $dst/README.md"
  fi
done < "$HERE/repos.txt"

echo
echo "== macOS defaults"
step python3 "$HERE/macos-defaults.py" "${DRYFLAG[@]}"

echo
echo "== JetBrains keymap + VS Code family keybindings (if an IDE config is present)"
if find "$HOME/Library/Application Support/JetBrains" -maxdepth 1 -name 'PhpStorm*' -o -name 'IntelliJIdea*' 2>/dev/null | grep -q .; then
  ( cd "$HERE/ide-keymaps" && step ./apply.sh "${DRYFLAG[@]}" )
  ( cd "$HERE/ide-keymaps" && step ./port-vscode.sh "${DRYFLAG[@]}" )
else
  echo "  -> no JetBrains IDE config yet; after installing PhpStorm run"
  echo "     ide-keymaps/apply.sh, then ide-keymaps/port-vscode.sh"
fi

echo
echo "== manual, not scriptable"
echo "  - Karabiner permissions: karabiner-windows-keyboard-mapping-macos/setup.sh prints them"
echo "  - Swiss keyboard layout: swiss-windows-keyboard-layout-macos/README.md"
echo "  - PhpStorm: Settings > Tools > Terminal > 'Use Option as Meta key' off (AltGr in the console)"
echo "  - see README.md 'Manual steps' (VoiceOver off, Gatekeeper, AltTab, uBar)"
$DRY && echo $'\n(dry run)'
