#!/usr/bin/env python3
"""
App settings - AltTab, Sidebar and the other apps in registry.txt - kept
outside this public repo, without licenses.

    python3 app_settings.py apply [--dir DIR] [--dry-run]   DIR -> this Mac (bootstrap: apps step)
    python3 app_settings.py export [--dir DIR]              this Mac -> DIR

DIR is the private settings directory: SETTINGS_DIR in the bootstrap config,
by default ~/.config/macos-base-config/settings (or the folder itself when it
has no settings/). registry.txt says for each app where its settings live:

defaults  a preferences domain; exported without window / update / telemetry
          state and without license or token keys, applied by merging into
          the domain (other keys stay). A running app is quit first and
          reopened after.
file      a settings file, copied as is; apply backs up the old one.
sidebar   Sidebar's own backup format, stripped of every license field,
          usage data and personal state. Sidebar can't be told to import
          from a script, so apply only adds it to Sidebar's backup list;
          restore it there (Settings > Expert > Backups).

export takes the newest Sidebar backup - create one first in Sidebar
(Settings > Expert > Backups > Create backup).
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import NamedTuple

HERE = Path(__file__).resolve().parent
REGISTRY_FILE = Path(os.environ.get("APP_REGISTRY") or HERE / "registry.txt")
KINDS = ("defaults", "file", "sidebar")


class RegistryError(Exception):
    pass


class Entry(NamedTuple):
    id: str
    kind: str
    where: str
    app: str


def registry_problem(path: Path, number: int, line: str, first_line: dict[str, int]) -> str | None:
    """what is wrong with one registry line, None when it is fine"""
    cells = [cell.strip() for cell in line.split("|")]
    where = f"{path.name}:{number}"
    if len(cells) != 4 or not all(cells):
        return f"{where}: expected 4 columns: id | kind | where | app"
    entry = Entry(*cells)
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", entry.id):
        return f"{where}: invalid id: {entry.id}"
    if entry.kind not in KINDS:
        return f"{where}: unknown kind: {entry.kind}"
    if entry.id in first_line:
        return f"{where}: duplicate id: {entry.id} (first on line {first_line[entry.id]})"
    return None


def load_registry(path: Path) -> list[Entry]:
    """The registry's entries; malformed lines raise one RegistryError that
    names every one of them."""
    entries: list[Entry] = []
    problems: list[str] = []
    first_line: dict[str, int] = {}
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        problem = registry_problem(path, number, line, first_line)
        if problem:
            problems.append(problem)
            continue
        entry = Entry(*[cell.strip() for cell in line.split("|")])
        first_line[entry.id] = number
        entries.append(entry)
    if problems:
        raise RegistryError("\n".join(problems))
    return entries


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


# --- defaults / generic ------------------------------------------------------

RUNTIME_PREFIXES = ("NSWindow", "NSStatusItem", "NSNavPanel", "NSOSPLast", "NSSplitView",
                    "NSToolbar", "NSQuitAlwaysKeepsWindows", "SU", "MSAppCenter",
                    "GATelemetry", "LaunchAtLogin__")
SECRET_WORDS = ("licen", "token", "serial", "password", "secret")
LEGACY_NAMES = {"alt-tab": "alttab.plist"}


def is_secret_key(key: str) -> bool:
    return any(word in key.lower() for word in SECRET_WORDS)


def settings_file(settings_dir: Path, entry: Entry) -> Path:
    """<id>.plist / <id>.sidebarbackup / <id><suffix of where>; for reading,
    an MBC-11 legacy name when only that exists."""
    if entry.kind == "defaults":
        name = f"{entry.id}.plist"
    elif entry.kind == "sidebar":
        name = f"{entry.id}.sidebarbackup"
    else:
        name = entry.id + Path(entry.where).suffix
    path = settings_dir / name
    legacy = LEGACY_NAMES.get(entry.id)
    if not path.exists() and legacy and (settings_dir / legacy).exists():
        return settings_dir / legacy
    return path


def quit_app(app: str) -> bool:
    """quit app if it runs (it writes its settings on exit); True if it ran"""
    if subprocess.run(["pgrep", "-x", app], capture_output=True).returncode != 0:
        return False
    subprocess.run(["osascript", "-e", f'tell application "{app}" to quit'], capture_output=True)
    for _ in range(20):
        if subprocess.run(["pgrep", "-x", app], capture_output=True).returncode != 0:
            break
        time.sleep(0.25)
    return True


def reopen_app(app: str) -> None:
    subprocess.run(["open", "-a", app], capture_output=True)


def read_domain(domain: str) -> dict:
    result = subprocess.run(["defaults", "export", domain, "-"], capture_output=True)
    return plistlib.loads(result.stdout) if result.returncode == 0 and result.stdout else {}


def portable_settings(domain: dict) -> dict:
    return {key: value for key, value in domain.items()
            if not key.startswith(RUNTIME_PREFIXES) and not is_secret_key(key)}


def export_defaults(entry: Entry, settings_dir: Path) -> None:
    domain = read_domain(entry.where)
    if not domain:
        print(f"  {entry.app}: no settings on this Mac - skipped")
        return
    target = settings_dir / f"{entry.id}.plist"
    write_private(target, plistlib.dumps(portable_settings(domain), fmt=plistlib.FMT_XML))
    print(f"  {entry.app}: {target}")


def apply_defaults(entry: Entry, source: Path, dry_run: bool) -> None:
    wanted = plistlib.loads(source.read_bytes())
    current = read_domain(entry.where)
    changed = sorted(key for key, value in wanted.items() if current.get(key) != value)
    if not changed:
        print(f"  {entry.app}: already set")
        return
    if dry_run:
        print(f"  {entry.app}: would set {', '.join(changed)}")
        return
    was_running = quit_app(entry.app)
    with tempfile.NamedTemporaryFile(suffix=".plist") as merged:
        merged.write(plistlib.dumps({**current, **wanted}, fmt=plistlib.FMT_BINARY))
        merged.flush()
        subprocess.run(["defaults", "import", entry.where, merged.name], check=True)
    if was_running:
        reopen_app(entry.app)
    print(f"  {entry.app}: set {', '.join(changed)}" + (" (restarted)" if was_running else ""))


def export_file(entry: Entry, settings_dir: Path) -> None:
    source = Path(os.path.expanduser(entry.where))
    if not source.is_file():
        print(f"  {entry.app}: no settings on this Mac - skipped")
        return
    target = settings_file(settings_dir, entry)
    write_private(target, source.read_bytes())
    print(f"  {entry.app}: {target}")


def apply_file(entry: Entry, source: Path, dry_run: bool) -> None:
    target = Path(os.path.expanduser(entry.where))
    data = source.read_bytes()
    if target.is_file() and target.read_bytes() == data:
        print(f"  {entry.app}: already set")
        return
    if dry_run:
        print(f"  {entry.app}: would replace {target}")
        return
    was_running = quit_app(entry.app)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        target.rename(target.with_name(f"{target.name}.bak-{time.strftime('%Y%m%d-%H%M%S')}"))
    target.write_bytes(data)
    if was_running:
        reopen_app(entry.app)
    print(f"  {entry.app}: set {target}" + (" (restarted)" if was_running else ""))


def export_entry(entry: Entry, settings_dir: Path) -> None:
    if entry.kind == "defaults":
        export_defaults(entry, settings_dir)
    elif entry.kind == "file":
        export_file(entry, settings_dir)
    elif entry.kind == "sidebar":
        export_sidebar(entry, settings_dir)


def apply_entry(entry: Entry, settings_dir: Path, dry_run: bool) -> None:
    if not app_installed(entry.app):
        print(f"  {entry.app}: not installed - skipped")
        return
    source = settings_file(settings_dir, entry)
    if not source.is_file():
        print(f"  {entry.app}: no settings in {settings_dir} - skipped")
        return
    if entry.kind == "defaults":
        apply_defaults(entry, source, dry_run)
    elif entry.kind == "file":
        apply_file(entry, source, dry_run)
    elif entry.kind == "sidebar":
        apply_sidebar(entry, source, dry_run)


# --- Sidebar ------------------------------------------------------------------

def sidebar_support(entry: Entry) -> Path:
    return Path(os.path.expanduser(entry.where))


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


def export_sidebar(entry: Entry, settings_dir: Path) -> None:
    backups = sorted(sidebar_support(entry).glob("*.sidebarbackup"), key=lambda p: p.stat().st_mtime)
    if not backups:
        print(f"  {entry.app}: no backup found - create one in Sidebar: Settings > Expert > Backups")
        return
    source = backups[-1]
    clean = sanitized_sidebar_backup(plistlib.loads(source.read_bytes()))
    target = settings_file(settings_dir, entry)
    if target.is_file() and \
            _without_metadata(plistlib.loads(target.read_bytes())) == _without_metadata(clean):
        print(f"  {entry.app}: unchanged (from {source.name})")
        return
    # Sidebar reads createdAt as UTC; plistlib writes naive datetimes as is
    clean["metadata"] = {
        **{key: clean["metadata"][key] for key in SIDEBAR_METADATA_KEEP if key in clean["metadata"]},
        "id": str(uuid.uuid4()).upper(),
        "createdAt": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
        "reason": "manual",
    }
    write_private(target, plistlib.dumps(clean, fmt=plistlib.FMT_BINARY))
    print(f"  {entry.app}: {target} (from {source.name})")


def sidebar_backup_name(backup: dict) -> str:
    """Sidebar's own naming: <app version>_<local time>_<id prefix>."""
    meta = backup["metadata"]
    created = meta["createdAt"].replace(tzinfo=datetime.timezone.utc).astimezone()
    return f"{meta['appVersion']}_{created:%Y%m%d-%H%M%S}_{meta['id'][:8]}.sidebarbackup"


def apply_sidebar(entry: Entry, source: Path, dry_run: bool) -> None:
    data = source.read_bytes()
    support = sidebar_support(entry)
    if any(existing.read_bytes() == data for existing in support.glob("*.sidebarbackup")):
        print(f"  {entry.app}: backup already in its list")
        return
    backup = plistlib.loads(data)
    created = backup["metadata"]["createdAt"].replace(tzinfo=datetime.timezone.utc).astimezone()
    if dry_run:
        print(f"  {entry.app}: would add the backup from {created:%Y-%m-%d %H:%M} to its list")
        return
    support.mkdir(parents=True, exist_ok=True)
    (support / sidebar_backup_name(backup)).write_bytes(data)
    print(f"  {entry.app}: backup from {created:%Y-%m-%d %H:%M} added - restore it in "
          "Sidebar: Settings > Expert > Backups")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["apply", "export"])
    parser.add_argument("--dir", type=Path, default=None,
                        help="private settings directory (default: ~/.config/macos-base-config)")
    parser.add_argument("--dry-run", action="store_true", help="apply: change nothing")
    args = parser.parse_args(argv)
    try:
        entries = load_registry(REGISTRY_FILE)
    except (OSError, RegistryError) as error:
        print(f"app_settings: {error}", file=sys.stderr)
        return 2
    settings_dir = (args.dir or default_settings_dir()).expanduser()
    try:
        if args.command == "export":
            # a new settings dir is private (700); an existing one is left as it is
            settings_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
            for entry in entries:
                export_entry(entry, settings_dir)
        else:
            for entry in entries:
                apply_entry(entry, settings_dir, args.dry_run)
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException,
            subprocess.CalledProcessError) as error:
        print(f"app_settings: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
