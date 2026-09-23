#!/usr/bin/env python3
"""
AltTab and Sidebar settings, kept outside this public repo - without licenses.

    python3 app_settings.py apply [--dir DIR] [--dry-run]   DIR -> this Mac (bootstrap: apps step)
    python3 app_settings.py export [--dir DIR]              this Mac -> DIR

DIR is the private settings directory: SETTINGS_DIR in the bootstrap config,
by default ~/.config/macos-base-config (next to config.sh). An app without a
file there is skipped.

AltTab   alttab.plist: the com.lwouis.alt-tab-macos defaults minus window
         frames, update and telemetry state. apply merges them into the
         domain (other keys stay) and restarts AltTab. Its license lives in a
         separate domain that is never read.
Sidebar  sidebar.sidebarbackup: Sidebar's own backup format, stripped of
         every license field, usage data and personal state. Sidebar can't
         be told to import from a script, so apply only adds it to Sidebar's
         backup list; restore it there (Settings > Expert > Backups). A
         license already entered on the Mac stays in place.

export takes the newest Sidebar backup - create one first in Sidebar
(Settings > Expert > Backups > Create backup).
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

ALTTAB_FILE_NAME = "alttab.plist"
SIDEBAR_FILE_NAME = "sidebar.sidebarbackup"
ALTTAB_DOMAIN = "com.lwouis.alt-tab-macos"
ALTTAB_RUNTIME_PREFIXES = ("NSWindow Frame", "NSStatusItem", "SU", "MSAppCenter")
SIDEBAR_SUPPORT = Path("Library/Application Support/at.sidebar.Sidebar")
# portableSettingsData: usage and bookkeeping, besides the license* fields
SIDEBAR_PORTABLE_DROP = {"daysOfUsage", "lastUsedAt", "lastLaunchedVersion", "settingsCreatedAt"}
# preferencesPlist: settings only - no statistics, window state, calendars,
# update state or onboarding
SIDEBAR_PREF_KEEP = {
    "SettingsAdvancedMode", "activeWorkspaceName", "applicationConfigurations",
    "launcherConfigurations", "linkConfigurations", "sidebarStyle",
    "smartStackConfigurations", "spacerConfigurations", "stackConfigurations",
    "at.sidebar.Sidebar.tabView.onlyShowAppsOnThisScreen",
    "at.sidebar.Sidebar.tabView.shortcutModeEnabled",
    "at.sidebar.Sidebar.tabView.stacks",
}
SIDEBAR_PREF_KEEP_PREFIXES = ("KeyboardShortcuts_", "unlocked")
# metadata of a manual backup (an update backup adds fromVersion / toVersion)
SIDEBAR_METADATA_KEEP = ("appVersion", "configurationVersion", "edition")


def is_license_key(key: str) -> bool:
    return "licen" in key.lower()


def default_settings_dir() -> Path:
    config_home = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(config_home) / "macos-base-config"


def write_private(path: Path, data: bytes) -> None:
    """write a settings file readable only by you, like config.sh (600) - it
    shows your pinned apps, links and screen names"""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as out:
        out.write(data)
    os.chmod(path, 0o600)  # an existing file would keep its old mode


def app_installed(name: str) -> bool:
    return (Path(os.environ.get("APPLICATIONS_DIR", "/Applications")) / f"{name}.app").is_dir()


# --- AltTab -------------------------------------------------------------------

def read_alttab_domain() -> dict:
    result = subprocess.run(["defaults", "export", ALTTAB_DOMAIN, "-"], capture_output=True)
    return plistlib.loads(result.stdout) if result.returncode == 0 and result.stdout else {}


def alttab_settings(domain: dict) -> dict:
    return {key: value for key, value in domain.items()
            if not key.startswith(ALTTAB_RUNTIME_PREFIXES) and not is_license_key(key)}


def export_alttab(settings_dir: Path) -> None:
    domain = read_alttab_domain()
    if not domain:
        print("  AltTab: no settings on this Mac - skipped")
        return
    target = settings_dir / ALTTAB_FILE_NAME
    write_private(target, plistlib.dumps(alttab_settings(domain), fmt=plistlib.FMT_XML))
    print(f"  AltTab: {target}")


def apply_alttab(settings_dir: Path, dry_run: bool) -> None:
    if not app_installed("AltTab"):
        print("  AltTab: not installed - skipped")
        return
    source = settings_dir / ALTTAB_FILE_NAME
    if not source.is_file():
        print(f"  AltTab: no settings in {settings_dir} - skipped")
        return
    wanted = plistlib.loads(source.read_bytes())
    current = read_alttab_domain()
    changed = sorted(key for key, value in wanted.items() if current.get(key) != value)
    if not changed:
        print("  AltTab: already set")
        return
    if dry_run:
        print(f"  AltTab: would set {', '.join(changed)}")
        return
    # AltTab writes its settings on exit - quit it before importing
    subprocess.run(["osascript", "-e", 'tell application "AltTab" to quit'], capture_output=True)
    for _ in range(20):
        if subprocess.run(["pgrep", "-x", "AltTab"], capture_output=True).returncode != 0:
            break
        time.sleep(0.25)
    with tempfile.NamedTemporaryFile(suffix=".plist") as merged:
        merged.write(plistlib.dumps({**current, **wanted}, fmt=plistlib.FMT_BINARY))
        merged.flush()
        subprocess.run(["defaults", "import", ALTTAB_DOMAIN, merged.name], check=True)
    subprocess.run(["open", "-a", "AltTab"], capture_output=True)
    print(f"  AltTab: set {', '.join(changed)} (restarted)")


# --- Sidebar ------------------------------------------------------------------

def sidebar_support() -> Path:
    return Path.home() / SIDEBAR_SUPPORT


def sanitized_sidebar_backup(backup: dict) -> dict:
    """backup without license, usage data and personal state; restoring it
    merges into the existing preferences, so a license on the Mac stays."""
    clean = {key: value for key, value in backup.items() if key != "encryptedLicenseInfo"}
    portable = json.loads(backup["portableSettingsData"])
    portable = {key: value for key, value in portable.items()
                if not is_license_key(key) and key not in SIDEBAR_PORTABLE_DROP}
    clean["portableSettingsData"] = json.dumps(portable, separators=(",", ":")).encode()
    prefs = plistlib.loads(backup["preferencesPlist"])
    prefs = {key: value for key, value in prefs.items()
             if not is_license_key(key)
             and (key in SIDEBAR_PREF_KEEP or key.startswith(SIDEBAR_PREF_KEEP_PREFIXES))}
    clean["preferencesPlist"] = plistlib.dumps(prefs, fmt=plistlib.FMT_BINARY)
    clean["mergesWithExistingPreferences"] = True
    return clean


def _without_metadata(backup: dict) -> dict:
    return {key: value for key, value in backup.items() if key != "metadata"}


def export_sidebar(settings_dir: Path) -> None:
    backups = sorted(sidebar_support().glob("*.sidebarbackup"), key=lambda p: p.stat().st_mtime)
    if not backups:
        print("  Sidebar: no backup found - create one in Sidebar: Settings > Expert > Backups")
        return
    source = backups[-1]
    clean = sanitized_sidebar_backup(plistlib.loads(source.read_bytes()))
    target = settings_dir / SIDEBAR_FILE_NAME
    if target.is_file() and \
            _without_metadata(plistlib.loads(target.read_bytes())) == _without_metadata(clean):
        print(f"  Sidebar: unchanged (from {source.name})")
        return
    # Sidebar reads createdAt as UTC; plistlib writes naive datetimes as is
    clean["metadata"] = {
        **{key: clean["metadata"][key] for key in SIDEBAR_METADATA_KEEP if key in clean["metadata"]},
        "id": str(uuid.uuid4()).upper(),
        "createdAt": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
        "reason": "manual",
    }
    write_private(target, plistlib.dumps(clean, fmt=plistlib.FMT_BINARY))
    print(f"  Sidebar: {target} (from {source.name})")


def sidebar_backup_name(backup: dict) -> str:
    """Sidebar's own naming: <app version>_<local time>_<id prefix>."""
    meta = backup["metadata"]
    created = meta["createdAt"].replace(tzinfo=datetime.timezone.utc).astimezone()
    return f"{meta['appVersion']}_{created:%Y%m%d-%H%M%S}_{meta['id'][:8]}.sidebarbackup"


def apply_sidebar(settings_dir: Path, dry_run: bool) -> None:
    if not app_installed("Sidebar"):
        print("  Sidebar: not installed - skipped")
        return
    source_file = settings_dir / SIDEBAR_FILE_NAME
    if not source_file.is_file():
        print(f"  Sidebar: no settings in {settings_dir} - skipped")
        return
    data = source_file.read_bytes()
    support = sidebar_support()
    if any(existing.read_bytes() == data for existing in support.glob("*.sidebarbackup")):
        print("  Sidebar: backup already in its list")
        return
    backup = plistlib.loads(data)
    created = backup["metadata"]["createdAt"].replace(tzinfo=datetime.timezone.utc).astimezone()
    if dry_run:
        print(f"  Sidebar: would add the backup from {created:%Y-%m-%d %H:%M} to its list")
        return
    support.mkdir(parents=True, exist_ok=True)
    (support / sidebar_backup_name(backup)).write_bytes(data)
    print(f"  Sidebar: backup from {created:%Y-%m-%d %H:%M} added - restore it in "
          "Sidebar: Settings > Expert > Backups")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["apply", "export"])
    parser.add_argument("--dir", type=Path, default=None,
                        help="private settings directory (default: ~/.config/macos-base-config)")
    parser.add_argument("--dry-run", action="store_true", help="apply: change nothing")
    args = parser.parse_args(argv)
    settings_dir = (args.dir or default_settings_dir()).expanduser()
    try:
        if args.command == "export":
            # a new settings dir is private (700); an existing one is left as it is
            settings_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
            export_alttab(settings_dir)
            export_sidebar(settings_dir)
        else:
            apply_alttab(settings_dir, args.dry_run)
            apply_sidebar(settings_dir, args.dry_run)
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException,
            subprocess.CalledProcessError) as error:
        print(f"app_settings: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
