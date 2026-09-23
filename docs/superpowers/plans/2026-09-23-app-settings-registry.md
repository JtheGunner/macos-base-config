# Registry-driven app settings (MBC-15) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hard-coded AltTab/Sidebar code in `apps/app_settings.py`
with a registry (`apps/registry.txt`) and three generic kinds: `defaults`,
`file` and `sidebar`. Adding an app then takes one line, not code.

**Architecture:** `apps/app_settings.py` works like this:
- **Loading.** It loads the registry; a parse error names the line.
- **Per entry.** It exports or applies each entry through the handler for its
  kind:
  - `defaults` filters runtime and secret keys, and applies by merging, with
    a quit / import / reopen cycle;
  - `file` copies, and backs up the old file on apply;
  - `sidebar` keeps the existing sanitised backup logic.
- **Settings file.** Each entry's file is `SETTINGS_DIR/<id>.<ext>`.

The default `SETTINGS_DIR` becomes `<config dir>/settings` when that dir
exists, otherwise the config dir itself, so the flat MBC-11 layout keeps
working.

**Tech Stack:** Python 3.9+ (system), bash 3.2; tests in `tests/bootstrap-test.sh`.

**Spec:** `docs/superpowers/specs/2026-09-23-private-config-repo-design.md`.
The spike result is on the ticket. It sets two decisions:
- Rectangle is a `defaults` entry (`com.knollsoft.Rectangle`), because it
  consumes `RectangleConfig.json` at launch.
- MouseBoost Pro stays out, because it has no portable settings.

## Global Constraints

- **Registry format:** `id | kind | where | app`, with `#` comments; blank
  lines are ignored.
  - `id` must match `^[a-z0-9][a-z0-9-]*$` and be unique.
  - `kind` is one of `defaults`, `file` or `sidebar`.
  - `where`: a domain for `defaults`, a path (with `~` expanded) for `file`
    and `sidebar`.
  - `app` is the app name in `/Applications` (`APPLICATIONS_DIR` in tests).
- **Settings file names:**
  - `defaults` → `<id>.plist` (XML);
  - `file` → `<id><suffix of where>` (e.g. `tabby.yaml`);
  - `sidebar` → `<id>.sidebarbackup`.
- **Runtime key prefixes** dropped on a `defaults` export: `NSWindow`,
  `NSStatusItem`, `NSNavPanel`, `NSOSPLast`, `NSSplitView`, `NSToolbar`,
  `NSQuitAlwaysKeepsWindows`, `SU`, `MSAppCenter`, `GATelemetry`,
  `LaunchAtLogin__`.
- **Secret key substrings** (case-insensitive) dropped on a `defaults` export:
  `licen`, `token`, `serial`, `password`, `secret`. The full guard across all
  kinds is MBC-16.
- **App restart on apply (`defaults` / `file`):** quit the app via osascript
  and wait until `pgrep -x <app>` finds nothing (max 5 s), change the
  settings, then `open -a <app>` **only if it was running before**.
  Unchanged settings → no quit and no reopen.
- **Messages:**
  - `<app>: not installed - skipped`
  - `<app>: no settings in <dir> - skipped`
  - `<app>: already set`
  - `<app>: set <keys> (restarted)`
- **Export files** are 600, and a new settings dir is 700 (as MBC-11).
- **Legacy name:** in the settings dir, `alttab.plist` is still read for
  `alt-tab` when `alt-tab.plist` is missing.
- **Default settings dir:**
  - `app_settings.py` without `--dir`: `<config home>/macos-base-config/settings`
    if it exists, else `<config home>/macos-base-config`.
  - `lib/config.sh` applies the same rule when `SETTINGS_DIR` is empty.
- English code, comments and commits; commits have no trailers.

## Review Focus

- **A domain that can't be exported** (the app has never run, so
  `defaults export` fails). Expected: `<app>: no settings on this Mac -
  skipped`, other apps continue, and export exits 0. Owned by Task 2, test
  "defaults export skips a missing domain".
- **Apply while the app is not running.** Expected: no reopen, so apply
  doesn't launch Tabby or Shottr on its own. Owned by Task 2, test "defaults
  apply reopens only an app that was running".
- **A `file` target whose folder doesn't exist yet** (the app has never
  launched). Expected: the folder is created, then the file is copied. Owned
  by Task 3, test "file apply creates the target folder".
- **An old flat config dir after the update.** `alttab.plist` next to
  `config.sh` must still apply. Owned by Task 4, tests "legacy alttab.plist
  is read" and "SETTINGS_DIR falls back to the config dir".
- **Registry typos** (4 columns expected, unknown kind, duplicate id). Each is
  a clear error with its line number and exit 2, not a traceback. Owned by
  Task 1.

---

### Task 1: Registry file and parser

**Files:**
- Create: `apps/registry.txt`
- Modify: `apps/app_settings.py` (add `Entry`, `load_registry`, `RegistryError`)
- Modify: `tests/bootstrap-test.sh` (new tests at the start of the
  `# --- apps/app_settings.py` section; the `app_sandbox` copies
  `registry.txt` too; the guard test "no app settings are tracked" allows
  `apps/registry.txt`)

**Interfaces:**
- Produces:
  - `Entry(id: str, kind: str, where: str, app: str)`, a NamedTuple.
  - `load_registry(path: Path) -> list[Entry]`, which raises
    `RegistryError("<file>:<line>: <problem>")`.
  - `REGISTRY_FILE = HERE / "registry.txt"`, overridable with the env
    `APP_REGISTRY`.
  - A CLI parse error prints `app_settings: <message>` and exits 2.

- [ ] **Step 1: Write the failing tests**

After the helper block (`sidebar_support() { … }` and `write_alttab`/`write_sidebar_backup`), add:

```bash
# write_registry LINE... -> $AD/registry.txt
write_registry() { printf '%s\n' "$@" > "$AD/registry.txt"; }

it "the shipped app registry parses"
python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import app_settings as a
print(",".join(e.id for e in a.load_registry(a.REGISTRY_FILE)))' "$REPO/apps" > "$TMP/reg.out" 2>&1
assert_eq "$?" 0
assert_contains "$(cat "$TMP/reg.out")" "alt-tab"
assert_contains "$(cat "$TMP/reg.out")" "sidebar"

it "registry problems name their line and exit 2"
app_sandbox
write_registry '# comment' '' \
  'ok     | defaults | com.example.ok | Ok' \
  'short  | defaults | com.example' \
  'bad    | rsync    | x              | Bad' \
  'ok     | defaults | com.example.x  | Dup' \
  'Upper  | defaults | com.example.u  | U'
run_app_settings apply
assert_eq "$RC" 2
assert_contains "$OUT" "registry.txt:4: expected 4 columns: id | kind | where | app"
assert_contains "$OUT" "registry.txt:5: unknown kind: rsync"
assert_contains "$OUT" "registry.txt:6: duplicate id: ok (first on line 3)"
assert_contains "$OUT" "registry.txt:7: invalid id: Upper"
```

In `app_sandbox`, after `cp "$REPO/apps/app_settings.py" "$AD/"`, add
`cp "$REPO/apps/registry.txt" "$AD/"`.

In `it "no app settings are tracked in this public repo"`, change
`assert_eq "$tracked" "apps/app_settings.py"` to:

```bash
assert_eq "$tracked" "apps/app_settings.py
apps/registry.txt"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: the shipped app registry parses` (AttributeError: `load_registry`).

- [ ] **Step 3: Implement**

`apps/registry.txt`:

```text
# App settings registry - how each app keeps its settings. The settings
# themselves live in the private SETTINGS_DIR, never in this repo.
#
#   id | kind | where | app
#
# id     lowercase; the settings file is <id>.plist / <id>.sidebarbackup /
#        <id><suffix of where>
# kind   defaults  a preferences domain: exported without runtime state and
#                  secrets, applied by merging (the app restarts)
#        file      a file, copied as is (the old one is backed up on apply)
#        sidebar   Sidebar's backup format: added to its backup list
# where  the domain, or the path (~ allowed)
# app    the app in /Applications: installed?, and what is restarted

alt-tab | defaults | com.lwouis.alt-tab-macos                         | AltTab
sidebar | sidebar  | ~/Library/Application Support/at.sidebar.Sidebar | Sidebar
```

`apps/app_settings.py`: add `import re` and `from typing import NamedTuple`,
then after the constants:

```python
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
```

In `main`, load the registry before dispatching:

```python
    try:
        entries = load_registry(REGISTRY_FILE)
    except (OSError, RegistryError) as error:
        print(f"app_settings: {error}", file=sys.stderr)
        return 2
```

(For now the entries are only loaded; Task 2 dispatches on them.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 5: Commit**

```bash
git add apps tests/bootstrap-test.sh
git commit -m "feat: add the app settings registry and its parser"
```

---

### Task 2: The `defaults` kind (AltTab moves onto it)

**Files:**
- Modify: `apps/app_settings.py`:
  - replace `ALTTAB_*`, `export_alttab` and `apply_alttab` with generic
    `export_defaults` / `apply_defaults`;
  - add `quit_app` and `reopen_app`;
  - add `settings_file`;
  - dispatch on the entries in `main`.
- Modify: `tests/bootstrap-test.sh`:
  - in the AltTab tests, `$AS/alttab.plist` → `$AS/alt-tab.plist`;
  - a `pgrep` stub in `app_sandbox`;
  - new tests.

**Interfaces:**
- Consumes: `Entry` and `load_registry` (Task 1).
- Produces:
  - `settings_file(settings_dir: Path, entry: Entry) -> Path`: resolves
    `<id>.plist`, `<id>.sidebarbackup`, `<id><suffix of where>`, and the
    legacy `alttab.plist` for reads.
  - `export_entry(entry, settings_dir) -> None`.
  - `apply_entry(entry, settings_dir, dry_run) -> None`.
  - `quit_app(app: str) -> bool` (True if it was running) and
    `reopen_app(app: str) -> None`.

- [ ] **Step 1: Update the sandbox and existing AltTab tests, add new ones**

`app_sandbox`: add a stateful `pgrep` / `osascript` pair. A marker file
`$AH/running-<App>` means "running": osascript's quit removes it, and
`open -a <App>` recreates it.

```bash
  cat > "$AB/osascript" <<EOF
#!/bin/bash
echo "osascript \$*" >> "$ALOG"
app="\$(printf '%s' "\$*" | sed -n 's/.*application "\\([^"]*\\)" to quit.*/\\1/p')"
[ -n "\$app" ] && rm -f "$AH/running-\$app"
exit 0
EOF
  cat > "$AB/open" <<EOF
#!/bin/bash
echo "open \$*" >> "$ALOG"
[ "\$1" = -a ] && touch "$AH/running-\$2"
exit 0
EOF
  printf '#!/bin/bash\n[ -e "%s/running-$2" ]\n' "$AH" > "$AB/pgrep"
```

These replace the two current `printf … osascript` / `printf … open` lines.
Keep `chmod +x "$AB"/*`, and add `running_app() { touch "$AH/running-$1"; }`
next to the other helpers.

Rename the AltTab file in the existing tests:
`sed -i '' 's|\$AS/alttab\.plist|$AS/alt-tab.plist|g' tests/bootstrap-test.sh`.
Then, in `it "apps export creates the settings dir; without --dir it uses the config dir"`,
change the default-dir expectation to
`"$AH/.config/macos-base-config/alt-tab.plist"`.

In `it "apps apply merges AltTab settings, keeps other keys, restarts AltTab"`,
add `running_app AltTab` right after `app_sandbox`.

New tests, after `it "apps apply dry run only lists the AltTab keys it would change"`:

```bash
it "defaults apply reopens only an app that was running"
app_sandbox
write_alttab "$AS/alt-tab.plist" appearanceTheme=2
write_alttab "$(alttab_domain)" appearanceTheme=0
run_app_settings apply
assert_eq "$RC" 0
assert_contains "$(cat "$ALOG")" "defaults import com.lwouis.alt-tab-macos"
assert_not_contains "$(cat "$ALOG")" "open -a AltTab"
assert_contains "$OUT" "AltTab: set appearanceTheme"

it "defaults export drops runtime and secret keys of any registry app"
app_sandbox
write_registry 'shottr | defaults | cc.ffitch.shottr | Shottr'
mkdir -p "$AAPPS/Shottr.app"
write_alttab "$AH/defaults-store/cc.ffitch.shottr.plist" afterGrabCopy=1 kc-license=L token=T \
  "NSWindow Frame x=1" SULastCheckTime=x GATelemetry=1 "LaunchAtLogin__hasMigrated=1" \
  "NSToolbar Configuration y=1" customBackdropColor=red
run_app_settings export
assert_eq "$RC" 0
assert_eq "$(py 'print(sorted(plistlib.load(open(sys.argv[1], "rb"))))' "$AS/shottr.plist")" "['afterGrabCopy', 'customBackdropColor']"

it "defaults export skips a missing domain, other apps still export"
app_sandbox
write_registry 'shottr | defaults | cc.ffitch.shottr | Shottr' \
  'alt-tab | defaults | com.lwouis.alt-tab-macos | AltTab'
mkdir -p "$AAPPS/Shottr.app"
write_alttab "$(alttab_domain)" appearanceTheme=2
run_app_settings export
assert_eq "$RC" 0
assert_contains "$OUT" "Shottr: no settings on this Mac - skipped"
[ -f "$AS/alt-tab.plist" ] || fail "AltTab not exported"

it "legacy alttab.plist in the settings dir is still applied"
app_sandbox
write_alttab "$AS/alttab.plist" appearanceTheme=2
write_alttab "$(alttab_domain)" appearanceTheme=0
run_app_settings apply
assert_contains "$OUT" "AltTab: set appearanceTheme"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: apps export keeps AltTab settings…`, because the file is
still written as `alttab.plist`.

- [ ] **Step 3: Implement**

`apps/app_settings.py`: remove `ALTTAB_FILE_NAME`, `ALTTAB_DOMAIN`,
`ALTTAB_RUNTIME_PREFIXES`, `read_alttab_domain`, `alttab_settings`,
`export_alttab` and `apply_alttab`. Keep the docstring's AltTab paragraph but
reword it generically:

```python
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
```

Add:

```python
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
```

Generic dispatch (Task 3 adds `file`; the sidebar functions are adapted in
Task 3 as well; for now `sidebar` calls the existing ones with the entry's
paths):

```python
def export_entry(entry: Entry, settings_dir: Path) -> None:
    if entry.kind == "defaults":
        export_defaults(entry, settings_dir)
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
    elif entry.kind == "sidebar":
        apply_sidebar(entry, source, dry_run)
```

Adapt the Sidebar functions to the entry:
- `sidebar_support()` becomes `Path(os.path.expanduser(entry.where))`. Keep
  the `HOME`-relative expansion: `Path.home()` honours `HOME` in tests.
- `export_sidebar(entry, settings_dir)` writes to `settings_file(settings_dir, entry)`.
- `apply_sidebar(entry, source, dry_run)`:
  - drop its own installed / file checks (`apply_entry` does them);
  - read `source`;
  - use `Path(os.path.expanduser(entry.where))` as the support dir;
  - print with `entry.app`.

The messages stay as today ("Sidebar: backup already in its list", …).
Remove the `SIDEBAR_FILE_NAME` constant.

`main`, after loading the registry:

```python
        if args.command == "export":
            settings_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
            for entry in entries:
                export_entry(entry, settings_dir)
        else:
            for entry in entries:
                apply_entry(entry, settings_dir, args.dry_run)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 5: Commit**

```bash
git add apps tests/bootstrap-test.sh
git commit -m "feat: export and apply defaults-domain apps through the registry"
```

---

### Task 3: The `file` kind

**Files:**
- Modify: `apps/app_settings.py` (`export_file`, `apply_file`, dispatch)
- Modify: `tests/bootstrap-test.sh`

**Interfaces:**
- Consumes: `settings_file`, `quit_app`, `reopen_app`, `write_private`.
- Produces:
  - `export_file(entry, settings_dir)`: copies `where` → `settings_dir/<id><suffix>`
    (600). A missing source gives `<app>: no settings on this Mac - skipped`.
  - `apply_file(entry, source, dry_run)`:
    - identical content → `<app>: already set`;
    - otherwise it quits the app if running, creates the target's folder,
      backs up an existing target as `<target>.bak-<yyyymmdd-HHMMSS>`,
      copies, and reopens the app if it was running;
    - it prints `<app>: set <target>` (plus ` (restarted)`);
    - dry run: `<app>: would replace <target>`.

- [ ] **Step 1: Write the failing tests**

After the defaults tests:

```bash
it "file export copies the settings file"
app_sandbox
write_registry 'tabby | file | ~/Library/Application Support/tabby/config.yaml | Tabby'
mkdir -p "$AAPPS/Tabby.app" "$AH/Library/Application Support/tabby"
printf 'encrypted: true\nvault: abc\n' > "$AH/Library/Application Support/tabby/config.yaml"
run_app_settings export
assert_eq "$RC" 0
assert_eq "$(cat "$AS/tabby.yaml")" "$(printf 'encrypted: true\nvault: abc')"
assert_eq "$(stat -f %Lp "$AS/tabby.yaml")" 600

it "file apply backs up the old file, copies, restarts a running app"
app_sandbox
write_registry 'tabby | file | ~/Library/Application Support/tabby/config.yaml | Tabby'
mkdir -p "$AAPPS/Tabby.app" "$AH/Library/Application Support/tabby" "$AS"
echo old > "$AH/Library/Application Support/tabby/config.yaml"
echo new > "$AS/tabby.yaml"
running_app Tabby
run_app_settings apply
assert_eq "$RC" 0
assert_eq "$(cat "$AH/Library/Application Support/tabby/config.yaml")" new
assert_eq "$(cat "$AH/Library/Application Support/tabby"/config.yaml.bak-*)" old
assert_contains "$(cat "$ALOG")" 'osascript -e tell application "Tabby" to quit'
assert_contains "$(cat "$ALOG")" "open -a Tabby"
assert_contains "$OUT" "Tabby: set"
: > "$ALOG"
run_app_settings apply
assert_contains "$OUT" "Tabby: already set"
assert_eq "$(cat "$ALOG")" ""

it "file apply creates the target folder; dry run changes nothing"
app_sandbox
write_registry 'tabby | file | ~/Library/Application Support/tabby/config.yaml | Tabby'
mkdir -p "$AAPPS/Tabby.app" "$AS"
echo new > "$AS/tabby.yaml"
run_app_settings apply --dry-run
assert_contains "$OUT" "Tabby: would replace"
[ -e "$AH/Library/Application Support/tabby" ] && fail "written in dry run"
run_app_settings apply
assert_eq "$(cat "$AH/Library/Application Support/tabby/config.yaml")" new
assert_not_contains "$(cat "$ALOG")" "open -a Tabby"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: file export copies the settings file` (nothing is exported for `file`).

- [ ] **Step 3: Implement**

```python
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
```

In `export_entry` / `apply_entry`, add the `file` branches:

```python
    elif entry.kind == "file":
        export_file(entry, settings_dir)
```

```python
    elif entry.kind == "file":
        apply_file(entry, source, dry_run)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 5: Commit**

```bash
git add apps/app_settings.py tests/bootstrap-test.sh
git commit -m "feat: add the file kind to the app settings registry"
```

---

### Task 4: `settings/` as the default settings dir

**Files:**
- Modify: `lib/config.sh`: the SETTINGS_DIR default and its doc comment
- Modify: `apps/app_settings.py`: `default_settings_dir`
- Modify: `lib/steps.sh`: `step_manual`'s Sidebar check uses `sidebar.sidebarbackup` in SETTINGS_DIR (unchanged path logic; verify)
- Modify: `config.example.sh`, `README.md`
- Modify: `tests/bootstrap-test.sh`

**Interfaces:**
- Produces: `SETTINGS_DIR` default = `<config dir>/settings` when that
  directory exists, else `<config dir>`.
  `app_settings.py` without `--dir` uses the same rule under
  `${XDG_CONFIG_HOME:-~/.config}/macos-base-config`.

- [ ] **Step 1: Write the failing tests**

Config section, after the SETTINGS_DIR tests:

```bash
it "SETTINGS_DIR defaults to <config dir>/settings when it exists"
mkdir -p "$TMP/cfg2/settings"
echo 'BOOTSTRAP_STEPS=""' > "$TMP/cfg2/config.sh"
load_config "$TMP/cfg2/config.sh"
assert_eq "$SETTINGS_DIR" "$TMP/cfg2/settings"
rmdir "$TMP/cfg2/settings"
load_config "$TMP/cfg2/config.sh"
assert_eq "$SETTINGS_DIR" "$TMP/cfg2"
```

Apps section, replace the second half of
`it "apps export creates the settings dir; without --dir it uses the config dir"`
(from `OUT="$(env -u XDG_CONFIG_HOME …`) with:

```bash
OUT="$(env -u XDG_CONFIG_HOME HOME="$AH" PATH="$AB:$PATH" APPLICATIONS_DIR="$AAPPS" python3 "$AD/app_settings.py" export 2>&1)"
assert_eq "$?" 0
[ -f "$AH/.config/macos-base-config/alt-tab.plist" ] || fail "flat default dir not used: $OUT"
mkdir -p "$AH/.config/macos-base-config/settings"
OUT="$(env -u XDG_CONFIG_HOME HOME="$AH" PATH="$AB:$PATH" APPLICATIONS_DIR="$AAPPS" python3 "$AD/app_settings.py" export 2>&1)"
[ -f "$AH/.config/macos-base-config/settings/alt-tab.plist" ] || fail "settings/ not used: $OUT"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: SETTINGS_DIR defaults to <config dir>/settings when it exists`.

- [ ] **Step 3: Implement**

`lib/config.sh`, in `validate_config`, change the empty-default branch:

```bash
    # default: settings/ next to the config file (the private config repo's
    # layout), else the config file's folder itself (the older flat layout)
    "") if [ -d "$config_dir/settings" ]; then SETTINGS_DIR="$config_dir/settings"; else SETTINGS_DIR="$config_dir"; fi ;;
```

The following "not a directory" check compares against `$config_dir`. Change
it so that it only runs for an explicitly set value: introduce
`local settings_explicit=false`, set it to `true` when the raw value is
non-empty (before the `case`), and test
`if $settings_explicit && [ ! -d "$SETTINGS_DIR" ]`.

Update the doc comment `SETTINGS_DIR (default: the config file's directory)`
to `SETTINGS_DIR (default: settings/ next to the config file, else its directory)`.

`apps/app_settings.py`:

```python
def default_settings_dir() -> Path:
    config_home = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    config_dir = Path(config_home) / "macos-base-config"
    return config_dir / "settings" if (config_dir / "settings").is_dir() else config_dir
```

`config.example.sh`, the SETTINGS_DIR comment's first lines become:

```bash
# Private settings directory: the app settings in apps/registry.txt, written
# by "python3 apps/app_settings.py export --dir <dir>". Empty = settings/ next
# to this config file, else this file's directory; a relative path is
# relative to this file.
```

Keep its remaining lines (iCloud example) as they are.

`README.md`, `### App settings`:
- The intro says the apps and their storage are listed in
  [`apps/registry.txt`](apps/registry.txt).
- Table file names: `alt-tab.plist`, `sidebar.sidebarbackup`.
- Default dir: `~/.config/macos-base-config/settings/` (or the folder itself
  in the older flat layout).
- Add one sentence: adding an app is one line in the registry (kinds
  `defaults`, `file`, `sidebar`).
- The Configuration table's `SETTINGS_DIR` row gets the default
  `settings/ next to config.sh`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`. Then run `./bootstrap.sh --dry-run --no-pull apps`
on this Mac. Expected: AltTab and Sidebar are read from
`~/.config/macos-base-config` (flat layout, `alttab.plist` legacy name),
`AltTab: already set`.

- [ ] **Step 5: Commit**

```bash
git add lib config.example.sh apps README.md tests/bootstrap-test.sh
git commit -m "feat: default SETTINGS_DIR to settings/ next to the config, flat layout still works"
```

---

### Task 5: Final verification

- [ ] Run `/bin/bash tests/bootstrap-test.sh`. Expected: all cases pass.
- [ ] Run `./bootstrap.sh --dry-run --no-pull apps` on this Mac. Expected:
  AltTab `already set`, Sidebar `would add …` or `already in its list`.
- [ ] Run `python3 apps/app_settings.py export --dir <scratch>`. Expected:
  `alt-tab.plist` (600) and `sidebar.sidebarbackup` in the scratch dir, no
  `licen*` keys. Remove the scratch dir afterwards.
