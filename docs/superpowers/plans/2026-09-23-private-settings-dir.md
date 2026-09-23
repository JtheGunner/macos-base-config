# Private settings directory (MBC-11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the AltTab and Sidebar settings out of the public repo into an
optional private settings directory. Apps still install without it; settings
are applied only where the app is installed **and** its file exists.

**Architecture:**
- **`apps/app_settings.py`** reads and writes `alttab.plist` /
  `sidebar.sidebarbackup` in a directory given by `--dir`. The default is
  `${XDG_CONFIG_HOME:-~/.config}/macos-base-config`.
- **`lib/config.sh`** resolves `SETTINGS_DIR`. The default is the directory
  of the config file in use.
- **`step_apps`** passes `--dir "$SETTINGS_DIR"`, and skips when that
  directory does not exist.
- **`step_manual`** names the Sidebar restore and the licenses only for
  installed apps.
- **The repo** stops tracking the two settings files.

**Tech Stack:** bash 3.2, Python 3 (system), tests in `tests/bootstrap-test.sh`.

**Spec:** `docs/superpowers/specs/2026-09-23-package-catalog-design.md`
(section *Private settings directory*; this is ticket 3 of its Rollout,
MBC-11).

## Global Constraints

- **File names stay** `alttab.plist` and `sidebar.sidebarbackup`, now inside
  the settings dir.
- **`SETTINGS_DIR`:**
  - It is optional. Empty means the directory of the config file in use
    (`~/.config/macos-base-config/` by default, or the `--config` path's dir).
  - `~` is expanded.
  - A `SETTINGS_DIR` that is set but is not a directory is a config error
    (exit 2).
- **`apps` step:**
  - Settings dir missing → step skipped with `no settings dir: <dir>`.
  - Per app: not installed → `<App>: not installed - skipped`; no file →
    `<App>: no settings in <dir> - skipped`.
- **Export:** still license-free. It creates the dir if needed.
- **`manual` step:**
  - The Sidebar restore line appears only when Sidebar is installed **and**
    `sidebar.sidebarbackup` is in the settings dir.
  - The license line names only the installed apps (AltTab, Sidebar) and is
    left out when neither is installed.
- **Repo contents:** the two settings files are removed from the repo and
  ignored under `apps/`. A guard test keeps them out.
- **Git history:** rewriting it is out of scope.
- **Language:** English in code, docs and commits.

## Review Focus

- **The config dir holds only `config.sh`** (the normal case right after
  setup). The `apps` step must run, print a per-app "no settings" skip and
  still count as ok, not fail. Owned by Task 1, test "apps apply skips an
  installed app without a settings file".
- **`--config` points into iCloud Drive** (a path with spaces:
  `~/Library/Mobile Documents/com~apple~CloudDocs/...`). `SETTINGS_DIR`
  follows it, and the path reaches `app_settings.py` as one argument. Owned
  by Task 2, test "the settings dir follows --config, spaces included".
- **Export on a Mac where the settings dir does not exist yet.** It is
  created, not a traceback. Owned by Task 1, test "apps export creates the
  settings dir; without --dir it uses the config dir".
- **A stale settings file left in `apps/` of an old checkout** after the
  update. It must not be tracked again, and nothing reads it. Owned by
  Task 3 (`.gitignore` plus the guard test).
- **The dry run in the default sandbox**, where there is no settings dir.
  The `apps` step is skipped rather than called. The existing "dry run hands
  --dry-run to every sub-tool" test must keep covering `app_settings.py`
  (by creating the dir). Owned by Task 2.

---

### Task 1: `app_settings.py --dir`, per-app skip, license-free export

**Files:**
- Modify: `apps/app_settings.py`
- Modify: `tests/bootstrap-test.sh`, section `# --- apps/app_settings.py`

**Interfaces:**
- Produces:
  - `python3 app_settings.py {apply,export} [--dir DIR] [--dry-run]`.
  - `DIR` defaults to `${XDG_CONFIG_HOME:-$HOME/.config}/macos-base-config`.
  - Messages: `  AltTab: no settings in <DIR> - skipped`,
    `  Sidebar: no settings in <DIR> - skipped`,
    `  AltTab: not installed - skipped`, `  Sidebar: not installed - skipped`.

- [ ] **Step 1: Rewrite the test helpers and existing tests to use a settings dir**

In `app_sandbox`:
- The comment's first line becomes
  `# app_sandbox -> AH (fake HOME), AD (a copy of apps/), AS (settings dir, not created),`.
- Add `AS="$root/settings"` to the variable line.
- `run_app_settings` becomes:

```bash
run_app_settings() {
  OUT="$(HOME="$AH" PATH="$AB:$PATH" APPLICATIONS_DIR="$AAPPS" python3 "$AD/app_settings.py" "$@" --dir "$AS" 2>&1)"
  RC=$?
}
```

In every existing test of this section, replace `"$AD/alttab.plist"` with
`"$AS/alttab.plist"`, and `"$AD/sidebar.sidebarbackup"` / `b="$AD/sidebar.sidebarbackup"`
with the `$AS` form. Use `sed -i '' 's|\$AD/alttab.plist|$AS/alttab.plist|g; s|\$AD/sidebar.sidebarbackup|$AS/sidebar.sidebarbackup|g'`
on the file, then check with `grep -n '\$AD/' tests/bootstrap-test.sh` that
only the `cp` / `python3 "$AD/app_settings.py"` lines remain.

- [ ] **Step 2: Write the new failing tests**

In `it "apps export strips the Sidebar license, usage and personal data"`,
after its last assertion, add the license guard (moved here from the
tracked-files test in Task 3):

```bash
leaks="$(py '
def keys(value):
    if isinstance(value, dict):
        for k, v in value.items():
            yield k
            yield from keys(v)
    elif isinstance(value, list):
        for v in value:
            yield from keys(v)
alttab = plistlib.load(open(sys.argv[1], "rb"))
sidebar = plistlib.load(open(sys.argv[2], "rb"))
found = list(keys(alttab)) + list(keys(sidebar))
found += list(keys(json.loads(sidebar["portableSettingsData"])))
found += list(keys(plistlib.loads(sidebar["preferencesPlist"])))
print([k for k in found if "licen" in k.lower()])' "$AS/alttab.plist" "$AS/sidebar.sidebarbackup")"
assert_eq "$leaks" "[]"
```

Add after `it "apps apply skips apps that are not installed"`:

```bash
it "apps apply skips an installed app without a settings file"
app_sandbox
run_app_settings apply
assert_eq "$RC" 0
assert_contains "$OUT" "AltTab: no settings in $AS - skipped"
assert_contains "$OUT" "Sidebar: no settings in $AS - skipped"
assert_eq "$(cat "$ALOG")" ""

it "apps export creates the settings dir; without --dir it uses the config dir"
app_sandbox
write_alttab "$(alttab_domain)" appearanceTheme=2
run_app_settings export
assert_eq "$RC" 0
[ -f "$AS/alttab.plist" ] || fail "no alttab.plist in the new settings dir"
OUT="$(env -u XDG_CONFIG_HOME HOME="$AH" PATH="$AB:$PATH" APPLICATIONS_DIR="$AAPPS" python3 "$AD/app_settings.py" export 2>&1)"
assert_eq "$?" 0
[ -f "$AH/.config/macos-base-config/alttab.plist" ] || fail "default dir not used: $OUT"
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: the first `apps export …` test fails because `--dir` is an
unknown argument (`app_settings.py: error: unrecognized arguments: --dir`).

- [ ] **Step 4: Implement**

`apps/app_settings.py`.

Docstring, first lines:

```python
"""
AltTab and Sidebar settings, kept outside this public repo - without licenses.

    python3 app_settings.py apply [--dir DIR] [--dry-run]   DIR -> this Mac (bootstrap: apps step)
    python3 app_settings.py export [--dir DIR]              this Mac -> DIR

DIR is the private settings directory: SETTINGS_DIR in the bootstrap config,
by default ~/.config/macos-base-config (next to config.sh). An app without a
file there is skipped.
```

Keep the rest of the docstring. Its `alttab.plist` / `sidebar.sidebarbackup`
paragraphs stay as they are.

Replace the two constants `ALTTAB_FILE = …` / `SIDEBAR_FILE = …` (and drop
the now unused `HERE`) with:

```python
ALTTAB_FILE_NAME = "alttab.plist"
SIDEBAR_FILE_NAME = "sidebar.sidebarbackup"


def default_settings_dir() -> Path:
    config_home = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(config_home) / "macos-base-config"
```

AltTab functions:

```python
def export_alttab(settings_dir: Path) -> None:
    domain = read_alttab_domain()
    if not domain:
        print("  AltTab: no settings on this Mac - skipped")
        return
    target = settings_dir / ALTTAB_FILE_NAME
    target.write_bytes(plistlib.dumps(alttab_settings(domain), fmt=plistlib.FMT_XML))
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
    # ... rest unchanged
```

Sidebar functions, the same pattern:
- `export_sidebar(settings_dir: Path)` uses `target = settings_dir / SIDEBAR_FILE_NAME`
  wherever it used `SIDEBAR_FILE`, and prints `f"  Sidebar: {target} (from {source.name})"`.
- `apply_sidebar(settings_dir: Path, dry_run: bool)` uses
  `source_file = settings_dir / SIDEBAR_FILE_NAME`. When it is missing it
  prints `f"  Sidebar: no settings in {settings_dir} - skipped"`.

`main`:

```python
    parser.add_argument("command", choices=["apply", "export"])
    parser.add_argument("--dir", type=Path, default=None,
                        help="private settings directory (default: ~/.config/macos-base-config)")
    parser.add_argument("--dry-run", action="store_true", help="apply: change nothing")
    args = parser.parse_args(argv)
    settings_dir = (args.dir or default_settings_dir()).expanduser()
    try:
        if args.command == "export":
            settings_dir.mkdir(parents=True, exist_ok=True)
            export_alttab(settings_dir)
            export_sidebar(settings_dir)
        else:
            apply_alttab(settings_dir, args.dry_run)
            apply_sidebar(settings_dir, args.dry_run)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`. The tracked-files test still passes, because
the files are still tracked until Task 3.

- [ ] **Step 6: Commit**

```bash
git add apps/app_settings.py tests/bootstrap-test.sh
git commit -m "feat: read and write app settings in a --dir outside the repo"
```

---

### Task 2: `SETTINGS_DIR`, the `apps` step and the `manual` hints

**Files:**
- Modify: `lib/config.sh`: the default, validation, and the `load_config`
  doc comment.
- Modify: `config.example.sh`: a new `# --- apps step` section before
  `# --- dotfiles step`.
- Modify: `lib/steps.sh`: `step_apps` and `step_manual`.
- Modify: `lib/cli.sh`: `step_description apps`.
- Modify: `tests/bootstrap-test.sh`: the config section, the
  `config.example.sh` test and the e2e tests.

**Interfaces:**
- Consumes: `app_settings.py apply --dir DIR` (Task 1), `APPLICATIONS_DIR`
  (lib/packages.sh).
- Produces: `SETTINGS_DIR`, always set after `load_config`. It is an absolute
  path and may not exist.

- [ ] **Step 1: Write the failing tests**

Config section, after the `PACKAGES` tests:

```bash
it "SETTINGS_DIR defaults to the config file's directory"
XDG_CONFIG_HOME="$TMP/none" load_config ""
assert_eq "$SETTINGS_DIR" "$TMP/none/macos-base-config"
f="$(write_config 'BOOTSTRAP_STEPS=""')"
load_config "$f"
assert_eq "$SETTINGS_DIR" "$TMP"

it "SETTINGS_DIR: ~ expands; a set dir that doesn't exist is exit 2"
mkdir -p "$TMP/h/icloud dir"
f="$(write_config 'SETTINGS_DIR="~/icloud dir"')"
HOME="$TMP/h" load_config "$f"; rc=$?
assert_eq "$rc" 0
assert_eq "$SETTINGS_DIR" "$TMP/h/icloud dir"
f="$(write_config 'SETTINGS_DIR="~/nope"')"
out="$(HOME="$TMP/h" load_config "$f" 2>&1)"; rc=$?
assert_eq "$rc" 2
assert_contains "$out" "SETTINGS_DIR is not a directory: $TMP/h/nope"
```

In `it "config.example.sh is a valid config with the defaults"`, add
`assert_eq "$SETTINGS_DIR" "$REPO"` and add `SETTINGS_DIR` to the
`for key in …` list.

e2e.

1. Replace `it "apps runs right after editor and applies apps/app_settings.py"`
   with:

```bash
it "apps runs right after editor and applies the settings dir"
make_sandbox
mkdir -p "$SB/home/.config/macos-base-config"
run_bootstrap --no-pull manual apps editor
assert_eq "$(headers)" "== editor == apps == manual == summary "
assert_contains "$(cat "$LOG")" "python3 app_settings.py apply --dir $SB/home/.config/macos-base-config"

it "apps skips without a settings dir"
make_sandbox
run_bootstrap --no-pull apps
assert_eq "$RC" 0
assert_contains "$OUT" "  apps       skipped  (no settings dir: $SB/home/.config/macos-base-config)"
assert_not_contains "$(cat "$LOG")" "app_settings.py"

it "the settings dir follows --config, spaces included"
make_sandbox
mkdir -p "$SB/home/Cloud Docs/mbc"
echo 'BOOTSTRAP_STEPS=""' > "$SB/home/Cloud Docs/mbc/config.sh"
run_bootstrap --no-pull --config "$SB/home/Cloud Docs/mbc/config.sh" apps
assert_eq "$RC" 0
assert_contains "$(cat "$LOG")" "python3 app_settings.py apply --dir $SB/home/Cloud Docs/mbc"
```

2. Replace `it "manual step points to the Sidebar backup to restore"` with:

```bash
it "manual step names the Sidebar restore and licenses only for installed apps"
make_sandbox
run_bootstrap manual
assert_not_contains "$OUT" "Sidebar settings"
assert_not_contains "$OUT" "Licenses"
mkdir -p "$SB/Applications/AltTab.app"
run_bootstrap manual
assert_contains "$OUT" "Licenses: enter the AltTab (Pro) key from your password manager"
assert_not_contains "$OUT" "Sidebar settings"
mkdir -p "$SB/Applications/Sidebar.app"
run_bootstrap manual
assert_contains "$OUT" "Licenses: enter the AltTab (Pro) and Sidebar keys from your password manager"
assert_not_contains "$OUT" "Sidebar settings"
sandbox_config 'BOOTSTRAP_STEPS=""'
touch "$SB/home/.config/macos-base-config/sidebar.sidebarbackup"
run_bootstrap manual
assert_contains "$OUT" "Sidebar settings: Settings > Expert > Backups > restore the backup the apps step added"
```

3. In `it "manual step lists every manual hint"`, add
   `mkdir -p "$SB/Applications/AltTab.app"` right after `make_sandbox`, so
   that its `password manager` assertion keeps holding.

4. In `it "dry run hands --dry-run to every sub-tool and runs no git"`:
   - add `mkdir -p "$SB/home/.config/macos-base-config"` after
     `with_jetbrains`;
   - change `assert_contains "$log" "python3 app_settings.py apply --dry-run"`
     to
     `assert_contains "$log" "python3 app_settings.py apply --dir $SB/home/.config/macos-base-config --dry-run"`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: SETTINGS_DIR defaults to the config file's directory`.

- [ ] **Step 3: Implement**

`lib/config.sh`:
- In the `load_config` doc comment, add `SETTINGS_DIR` after
  `MACOS_DISABLE_GATEKEEPER,`.
- Add `SETTINGS_DIR=""` to the defaults (next to `MACOS_DISABLE_GATEKEEPER=0`).
- In `validate_config`, after the `BREW_BUNDLE_EXTRA` readability check, add:

```bash
  SETTINGS_DIR="$(expand_home "$SETTINGS_DIR")"
  if [ -n "$SETTINGS_DIR" ] && [ ! -d "$SETTINGS_DIR" ]; then
    echo "bootstrap.sh: $config_file: SETTINGS_DIR is not a directory: $SETTINGS_DIR" >&2
    return 2
  fi
  # default: next to the config file - one --config path locates everything private
  [ -n "$SETTINGS_DIR" ] || SETTINGS_DIR="$(dirname "$config_file")"
```

`config.example.sh`, before `# --- dotfiles step`:

```bash
# --- apps step ----------------------------------------------------------------

# Private settings directory: alttab.plist and sidebar.sidebarbackup, written
# by "python3 apps/app_settings.py export --dir <dir>". Empty = the directory
# of this config file. Keep it out of the public repo, e.g. in iCloud Drive:
# "~/Library/Mobile Documents/com~apple~CloudDocs/macos-base-config".
SETTINGS_DIR=""
```

`lib/steps.sh`:

```bash
step_apps() {
  if [ ! -d "$SETTINGS_DIR" ]; then
    skip "no settings dir: $SETTINGS_DIR"
    return 0
  fi
  run_in "$HERE/apps" python3 app_settings.py apply --dir "$SETTINGS_DIR"
}
```

`step_manual`: replace its two lines
`echo "  - Sidebar settings: …"` and `echo "  - Licenses: …"` with:

```bash
  local licensed=""
  if [ -d "$APPLICATIONS_DIR/Sidebar.app" ] && [ -f "$SETTINGS_DIR/sidebar.sidebarbackup" ]; then
    echo "  - Sidebar settings: Settings > Expert > Backups > restore the backup the apps step added"
  fi
  [ -d "$APPLICATIONS_DIR/AltTab.app" ] && licensed="AltTab (Pro)"
  [ -d "$APPLICATIONS_DIR/Sidebar.app" ] && licensed="${licensed:+$licensed and }Sidebar"
  case "$licensed" in
    "") ;;
    *" and "*) echo "  - Licenses: enter the $licensed keys from your password manager" ;;
    *) echo "  - Licenses: enter the $licensed key from your password manager" ;;
  esac
```

Put `local licensed=""` as the first line of the function body; bash allows
`local` anywhere in a function.

`lib/cli.sh`:
`apps)      echo "AltTab settings; Sidebar backup into its backup list, from SETTINGS_DIR (no licenses)" ;;`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 5: Commit**

```bash
git add lib config.example.sh tests/bootstrap-test.sh
git commit -m "feat: apply app settings from SETTINGS_DIR, skip what isn't there"
```

---

### Task 3: Settings files out of the repo

**Files:**
- Copy (on this Mac, not in the repo): `apps/alttab.plist` and
  `apps/sidebar.sidebarbackup` → `~/.config/macos-base-config/`. Check both
  targets first, and never overwrite an existing file.
- Delete: `apps/alttab.plist`, `apps/sidebar.sidebarbackup` (`git rm`).
- Modify: `.gitignore`.
- Modify: `tests/bootstrap-test.sh`: replace the tracked-files license test
  with a guard.

- [ ] **Step 1: Write the failing guard test**

Replace the whole `it "the tracked app settings hold no license data"` test,
up to and including its `assert_eq "$leaks" "[]"`, with:

```bash
it "no app settings are tracked in this public repo"
tracked="$(git -C "$REPO" ls-files apps)"
assert_eq "$tracked" "apps/app_settings.py"
assert_contains "$(cat "$REPO/.gitignore")" "apps/*.plist"
assert_contains "$(cat "$REPO/.gitignore")" "apps/*.sidebarbackup"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: no app settings are tracked in this public repo: expected [apps/app_settings.py], got [apps/alttab.plist …]`.

- [ ] **Step 3: Copy to this Mac's settings dir, then remove from the repo**

```bash
dest="$HOME/.config/macos-base-config"
for f in alttab.plist sidebar.sidebarbackup; do
  if [ -e "$dest/$f" ]; then echo "exists, left alone: $dest/$f"; else cp -p "apps/$f" "$dest/$f"; fi
done
ls -l "$dest"
git rm -q apps/alttab.plist apps/sidebar.sidebarbackup
```

Append to `.gitignore`:

```text
# private app settings live in SETTINGS_DIR, never in this public repo
apps/*.plist
apps/*.sidebarbackup
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`. Then run
`./bootstrap.sh --dry-run --no-pull apps` on this Mac. Expected: `AltTab:
already set` or `would set …`, and `Sidebar: backup already in its list` or
`would add …`, read from `~/.config/macos-base-config`.

- [ ] **Step 5: Commit**

```bash
git add .gitignore tests/bootstrap-test.sh
git commit -m "feat: keep app settings out of the public repo"
```

(the `git rm` is already staged)

---

### Task 4: README

**Files:**
- Modify: `README.md`:
  - the diagram `apps` line;
  - the Configuration table (a `SETTINGS_DIR` row after
    `MACOS_DISABLE_GATEKEEPER`);
  - the Manual steps table (Sidebar and Licenses rows);
  - the `### App settings` subsection.

- [ ] **Step 1: Edit README.md**

Diagram line:

```text
   ├─ apps        AltTab settings; Sidebar backup → its backup list, from SETTINGS_DIR   (no licenses)
```

Configuration table row:

```markdown
| `SETTINGS_DIR`              | config file's dir   | private app settings (`alttab.plist`, `sidebar.sidebarbackup`), see [App settings](#app-settings)                     |
```

Manual steps table:

```markdown
| 📌 | **Sidebar settings**      | only when Sidebar is installed and its backup is in `SETTINGS_DIR`: Sidebar → Settings → Expert → Backups → **Restore** the backup the `apps` step added (Sidebar has no way to import from a script) |
| 🔑 | **Licenses**              | the installed ones of AltTab (Pro) and Sidebar: enter the keys from your password manager in each app                                      |
```

Replace the `### App settings` subsection, up to the `---` before
`## 🔤 Fonts`, with:

````markdown
### App settings

The `apps` step brings your AltTab and Sidebar settings onto the Mac. They
are **private and never part of this public repo**. They live in your
settings directory, `SETTINGS_DIR`, which by default is the folder of your
config file (`~/.config/macos-base-config/`). **No license is ever
exported**: enter those from your password manager once per Mac.

|    | App     | File in `SETTINGS_DIR`                                                                                 | On `./bootstrap.sh apps`                                                          |
|:--:|---------|--------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| 🔀 | AltTab  | `alttab.plist`: its preferences, minus window frames, update and telemetry state                       | merged into its preferences; AltTab restarts. Unchanged settings leave it running  |
| 📌 | Sidebar | `sidebar.sidebarbackup`: a Sidebar backup without license, usage data, statistics, calendars or window state | added to Sidebar's backup list; restore it there (Settings → Expert → Backups)     |

Everything is optional: an app that isn't installed, or has no file in the
settings directory, is skipped. Without a settings directory the step is
skipped.

To save the settings of this Mac (for Sidebar, first create a backup in
Sidebar → Settings → Expert → Backups → *Create backup*):

```sh
python3 apps/app_settings.py export                 # into ~/.config/macos-base-config
python3 apps/app_settings.py export --dir <dir>     # or into your SETTINGS_DIR
```

> [!TIP]
> Keep the config and settings in iCloud Drive to have them on a new Mac
> right after signing in, before anything is installed:
> `./bootstrap.sh --config "$HOME/Library/Mobile Documents/com~apple~CloudDocs/macos-base-config/config.sh"`.
> The settings directory follows the config file.
````

Also check for links to the old wording:
`grep -n "apps/alttab\|apps/sidebar\|settings of this Mac into the repo" README.md`.
Expected: no output.

- [ ] **Step 2: Verify**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document the private settings directory"
```

---

### Task 5: Final verification

- [ ] Run `/bin/bash tests/bootstrap-test.sh`. Expected: all cases pass.
- [ ] Run `git ls-files apps`. Expected: only `apps/app_settings.py`.
- [ ] Run `./bootstrap.sh --dry-run --no-pull apps manual` on this Mac.
  Expected: `apps` reads `~/.config/macos-base-config`; `manual` names the
  AltTab (Pro) and Sidebar keys and the Sidebar restore.
