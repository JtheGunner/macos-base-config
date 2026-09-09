#!/usr/bin/env python3
"""
macOS defaults that Karabiner cannot do (menu-aware shortcuts, system hotkeys).

  1. Mission Control "Move left/right a space" (Ctrl+Arrow, symbolic hotkeys
     79-82) -> disabled, so Ctrl+Arrow reaches the app for word navigation.
  2. Finder: forward-delete key (Delete / Fn+Backspace) -> "Move to Bin"
     (App Shortcut via NSUserKeyEquivalents; menu-aware, so it still
     forward-deletes inside a rename field).
  3. AppleFontSmoothing = 1  (thinner bold system font).

Idempotent. Every change is backed up and a restore-<timestamp>.sh is written.

    python3 macos-defaults.py            # apply all
    python3 macos-defaults.py --dry-run
    python3 macos-defaults.py --show     # print current state, change nothing
"""

from __future__ import annotations

import argparse
import datetime
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHK_PLIST = Path.home() / "Library/Preferences/com.apple.symbolichotkeys.plist"
SPACE_HOTKEYS = {79: "Move left a space (Ctrl+Left)",
                 80: "Move left a space (Ctrl+Shift+Left)",
                 81: "Move right a space (Ctrl+Right)",
                 82: "Move right a space (Ctrl+Shift+Right)"}
FORWARD_DELETE = ""  # NSDeleteFunctionKey = the "Delete" / Fn+Backspace key
FINDER_KEYEQ = {"Move to Bin": FORWARD_DELETE, "Move to Trash": FORWARD_DELETE}

_restore: list[str] = []


def defaults_read(domain: str, key: str) -> str | None:
    r = subprocess.run(["defaults", "read", domain, key],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def show() -> None:
    print("symbolic hotkeys (Ctrl+Arrow space switch):")
    try:
        shk = plistlib.loads(SHK_PLIST.read_bytes()).get("AppleSymbolicHotKeys", {})
        for i in SPACE_HOTKEYS:
            print(f"  {i}: enabled={shk.get(str(i), {}).get('enabled')}")
    except OSError:
        print("  (no plist)")
    print("Finder NSUserKeyEquivalents:", defaults_read("com.apple.finder",
                                                        "NSUserKeyEquivalents"))
    print("AppleFontSmoothing:", defaults_read("-g", "AppleFontSmoothing"))


def disable_space_hotkeys(dry: bool) -> None:
    if not SHK_PLIST.is_file():
        print("symbolic hotkeys: no plist yet - skipping (nothing bound)")
        return
    data = plistlib.loads(SHK_PLIST.read_bytes())
    shk = data.setdefault("AppleSymbolicHotKeys", {})
    to_change = [i for i in SPACE_HOTKEYS
                 if shk.get(str(i), {}).get("enabled", True)]
    if not to_change:
        print("symbolic hotkeys 79-82: already disabled")
        return
    if dry:
        print(f"symbolic hotkeys: would disable {to_change}")
        return
    bak = _backup(SHK_PLIST)
    _restore.append(f'cp "{bak}" "{SHK_PLIST}"')
    for i in to_change:
        shk.setdefault(str(i), {})["enabled"] = False
    SHK_PLIST.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
    print(f"symbolic hotkeys: disabled {to_change}  (log out / log in to take effect)")


def set_finder_keyequiv(dry: bool) -> None:
    cur = subprocess.run(["defaults", "export", "com.apple.finder", "-"],
                         capture_output=True).stdout
    cur_dict = plistlib.loads(cur).get("NSUserKeyEquivalents", {}) if cur else {}
    if all(cur_dict.get(k) == v for k, v in FINDER_KEYEQ.items()):
        print("Finder App Shortcut (Delete -> Move to Bin): already set")
        return
    if dry:
        print("Finder App Shortcut: would set NSUserKeyEquivalents ->", FINDER_KEYEQ)
        return
    old = cur_dict or None
    _restore.append(
        'defaults delete com.apple.finder NSUserKeyEquivalents 2>/dev/null || true'
        if old is None else
        f'defaults write com.apple.finder NSUserKeyEquivalents {_plist_arg(old)}'
    )
    for k, v in FINDER_KEYEQ.items():
        subprocess.run(["defaults", "write", "com.apple.finder",
                        "NSUserKeyEquivalents", "-dict-add", k, v], check=True)
    subprocess.run(["killall", "Finder"], capture_output=True)
    print("Finder App Shortcut: Delete key -> Move to Bin")


def set_font_smoothing(dry: bool) -> None:
    if defaults_read("-g", "AppleFontSmoothing") == "1":
        print("AppleFontSmoothing: already 1")
        return
    if dry:
        print("AppleFontSmoothing: would set to 1")
        return
    _restore.append("defaults -currentHost delete -g AppleFontSmoothing 2>/dev/null || true")
    subprocess.run(["defaults", "-currentHost", "write", "-g",
                    "AppleFontSmoothing", "-int", "1"], check=True)
    print("AppleFontSmoothing: 1  (re-login to see it)")


def _plist_arg(obj) -> str:
    inner = " ".join(f'"{k}" = "{v}";' for k, v in obj.items())
    return f"'{{ {inner} }}'"


def _backup(p: Path) -> Path:
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    b = p.with_name(f"{p.name}.bak-{stamp}")
    shutil.copy2(p, b)
    print(f"  backup: {b}")
    return b


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--show", action="store_true")
    args = ap.parse_args(argv)

    if args.show:
        show()
        return 0

    disable_space_hotkeys(args.dry_run)
    set_finder_keyequiv(args.dry_run)
    set_font_smoothing(args.dry_run)

    if not args.dry_run:
        subprocess.run(["killall", "cfprefsd"], capture_output=True)
        subprocess.run(["/System/Library/PrivateFrameworks/SystemAdministration.framework/"
                        "Resources/activateSettings", "-u"], capture_output=True)
        if _restore:
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
            rp = HERE / f"restore-{stamp}.sh"
            rp.write_text("#!/usr/bin/env bash\nset -euo pipefail\n"
                          "# generated by macos-defaults.py - reverts that run\n"
                          + "\n".join(_restore) + "\n"
                          'killall cfprefsd; killall Finder 2>/dev/null || true\n'
                          'echo "reverted - log out / log in for hotkeys + font"\n')
            rp.chmod(0o755)
            print(f"\nrollback script: {rp.name}")
        print("\nSome changes need a logout/login (space hotkeys, font smoothing).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
