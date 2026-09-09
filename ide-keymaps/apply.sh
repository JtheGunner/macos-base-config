#!/usr/bin/env bash
# Restore the tracked keymap into the JetBrains IDE config and make it active.
#
#   ./apply.sh            all PhpStorm*/IntelliJIdea* config dirs found
#   ./apply.sh --dry-run
#
# Quit the IDE first - it rewrites these files on exit. After launch, "Backup
# and Sync" will push the keymap up to the JetBrains cloud on its own.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
JB="$HOME/Library/Application Support/JetBrains"
NAME="jeffry-default-macos-win"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY=false; [[ "${1:-}" == "--dry-run" ]] && DRY=true

[ -f "$HERE/$NAME.xml" ] || { echo "missing $HERE/$NAME.xml - run ./sync.sh once"; exit 1; }

found=0
while IFS= read -r cfg; do
  found=1
  km="$cfg/keymaps"; act="$cfg/options/mac/keymap.xml"
  echo "== ${cfg#$HOME/}"
  if $DRY; then
    echo "  would copy   $NAME.xml -> $km/"
    echo "  would set    <active_keymap name=\"$NAME\"/> in options/mac/keymap.xml"
    continue
  fi
  mkdir -p "$km" "$(dirname "$act")"
  [ -f "$km/$NAME.xml" ] && cp -p "$km/$NAME.xml" "$km/$NAME.xml.bak-$STAMP"
  cp "$HERE/$NAME.xml" "$km/$NAME.xml"
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
done < <(find "$JB" -maxdepth 1 -type d \( -name 'PhpStorm*' -o -name 'IntelliJIdea*' \) | sort)

[ "$found" = 1 ] || { echo "no JetBrains config dirs under $JB"; exit 1; }
$DRY && echo $'\n(dry run)' || echo $'\nDone. Start the IDE; it will sync the keymap to the cloud.'
