#!/usr/bin/env bash
# Restore the tracked keymap into the JetBrains IDE config and make it active,
# and turn the terminal's "Use Option as Meta key" off (AltGr characters
# would turn into escape sequences in the IDE terminal otherwise).
#
#   ./apply.sh            all PhpStorm*/IntelliJIdea* config dirs found
#   ./apply.sh --dry-run
#
# Quit the IDE first - it rewrites these files on exit. After launch, "Backup
# and Sync" will push the keymap up to the JetBrains cloud on its own.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
JB="$HOME/Library/Application Support/JetBrains"
# keymap name (as the IDE shows it) and the tracked copy in this repo
NAME="jeffry-default-macos-win Proper Redo"
FILE="jeffry-default-macos-win-proper-redo.xml"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY=false; [[ "${1:-}" == "--dry-run" ]] && DRY=true

[ -f "$HERE/$FILE" ] || { echo "missing $HERE/$FILE - run ./sync.sh once"; exit 1; }

# A running IDE rewrites its keymap files on exit, and a keymap edited in the IDE
# but not yet pulled with ./sync.sh would be overwritten by the tracked copy.
if ! $DRY && pgrep -f '/(PhpStorm|IntelliJ IDEA)[^/]*\.app/Contents/MacOS/' >/dev/null; then
  echo "a JetBrains IDE is running - quit it first (and run ./sync.sh if you changed the keymap)"
  exit 1
fi

found=0
while IFS= read -r cfg; do
  found=1
  km="$cfg/keymaps"; act="$cfg/options/mac/keymap.xml"
  echo "== ${cfg#$HOME/}"
  if $DRY; then
    echo "  would copy   $FILE -> $km/$NAME.xml"
    echo "  would set    <active_keymap name=\"$NAME\"/> in options/mac/keymap.xml"
    python3 "$HERE/set-terminal-option.py" "$cfg/options/terminal.xml" useOptionAsMetaKey false --dry-run
    continue
  fi
  mkdir -p "$km" "$(dirname "$act")"
  [ -f "$km/$NAME.xml" ] && cp -p "$km/$NAME.xml" "$km/$NAME.xml.bak-$STAMP"
  cp "$HERE/$FILE" "$km/$NAME.xml"
  echo "  copied  $km/$NAME.xml"
  [ -f "$act" ] && cp -p "$act" "$act.bak-$STAMP"
  cat > "$act" <<XML
<application>
  <component name="KeymapManager">
    <active_keymap name="$NAME" />
  </component>
</application>
XML
  echo "  active keymap -> $NAME"
  python3 "$HERE/set-terminal-option.py" "$cfg/options/terminal.xml" useOptionAsMetaKey false
done < <(find "$JB" -maxdepth 1 -type d \( -name 'PhpStorm*' -o -name 'IntelliJIdea*' \) | sort)

[ "$found" = 1 ] || { echo "no JetBrains config dirs under $JB"; exit 1; }
$DRY && echo $'\n(dry run)' || echo $'\nDone. Start the IDE; it will sync the keymap to the cloud.'
