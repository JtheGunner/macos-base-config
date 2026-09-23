#!/usr/bin/env bash
# Refresh the tracked keymap snapshot from the live JetBrains config.
#
# Run this after you edit the keymap inside PhpStorm. The IDE's own
# "Backup and Sync" (JetBrains cloud) has no public API - this file is the
# offline, git-diffable copy.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
JB="$HOME/Library/Application Support/JetBrains"
# keymap name (as the IDE shows it) and the tracked copy in this repo
NAME="jeffry-default-macos-win Proper Redo"
FILE="jeffry-default-macos-win-proper-redo.xml"

src=""
while IFS= read -r d; do
  [ -f "$d/keymaps/$NAME.xml" ] && src="$d/keymaps/$NAME.xml"
done < <(find "$JB" -maxdepth 1 -type d -name 'PhpStorm*' -o -maxdepth 1 -type d -name 'IntelliJIdea*' | sort)

[ -n "$src" ] || { echo "no $NAME.xml under $JB/*/keymaps/ - open the IDE once so it syncs"; exit 1; }

cp "$src" "$HERE/$FILE"
printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)  from  ${src#$HOME/}" > "$HERE/DATE"
echo "updated $HERE/$FILE"
git -C "$HERE" --no-pager diff --stat -- "$FILE" DATE || true
