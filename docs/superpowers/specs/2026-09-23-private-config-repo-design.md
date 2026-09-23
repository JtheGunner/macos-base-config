# Private config repo and generic app settings — design

## Goal

On a new Mac:

1. clone this repo;
2. run `./bootstrap.sh --init-config <private repo url>`;
3. run `./bootstrap.sh`.

The private config (`config.sh`) and the app settings arrive together, and
they are applied as part of the bootstrap run.

After changing an app's settings, one command (`./bootstrap.sh --save-settings`)
exports them into the private repo. The user then reviews the change and
commits it.

**What the user said:** config and settings live only locally today. They
have to be carried to a new Mac and backed up by hand, and that is the pain.
A private repo should hold the config for macos-base-config plus the
settings of several apps, and a mechanism should import them again.

**Constraints:**
- License keys and passwords are never stored, not even in the private repo.
  They stay in the password manager.
- Everything stays optional. Apps install whether or not settings exist.
- The public repo holds the logic and the knowledge of *how* an app stores
  its settings. The private repo holds only *data*.

**Out of scope:**
- automatic commits and pushes;
- syncing between Macs while the apps are running;
- apps that sync themselves (VS Code / Antigravity Settings Sync, JetBrains
  account, Bitwarden, Docker);
- Ghostty, whose config already lives in the dotfiles repo, and whose
  preferences hold only window and update state;
- MouseBoost Pro, until the spike finds where it stores its settings;
- rewriting the history of the public repo.

## Approaches considered

| Approach | Verdict |
|---|---|
| **A. The private repo *is* the config dir** (`~/.config/macos-base-config/`) | **chosen**: builds on MBC-11 (`SETTINGS_DIR` defaults to the config file's dir), no new tool, versioned, diffable |
| B. chezmoi with a private source repo | a second dotfile tool next to the dotfiles repo's stow; macOS preferences would still need custom code |
| C. Mackup / an iCloud Drive folder | Mackup's symlinks break for preferences since macOS 14; iCloud has no history or diffs and produces conflict copies |

## Layout

**macos-base-config (public)**

```text
apps/registry.txt     how each app keeps its settings (no data)
apps/app_settings.py  generic export / apply driven by the registry
lib/cli.sh            --init-config <url>, --save-settings [app...]
lib/steps.sh          repos: pull the config dir; apps: apply
```

**macos-private-config (private GitHub repo)**, cloned to
`~/.config/macos-base-config/`:

```text
config.sh             PACKAGES, NAS_MOUNT_SHARES, DOTFILES_*, ...
settings/
  alt-tab.plist
  maccy.plist
  shottr.plist
  rectangle.json
  tabby.yaml
  sidebar.sidebarbackup
Brewfile              optional, for BREW_BUNDLE_EXTRA
README.md             what this is, how to restore / save
.gitignore            *.bak-*, .DS_Store
```

`SETTINGS_DIR` in the new layout:
- The default becomes `<config dir>/settings`.
- A config dir that still has the MBC-11 flat layout (`alttab.plist`,
  `sidebar.sidebarbackup` next to `config.sh`) keeps working: when
  `<config dir>/settings` does not exist, the config dir itself is used.
- An explicitly set `SETTINGS_DIR` wins, as today.
- In the flat fallback, the MBC-11 file name `alttab.plist` is still read
  for `alt-tab`.

## Registry (`apps/registry.txt`)

The format is the same `|`-separated line format as `packages/catalog.txt`,
with `#` comments:

```text
# id      | kind     | where                                                         | app
alt-tab   | defaults | com.lwouis.alt-tab-macos                                      | AltTab
maccy     | defaults | org.p0deje.Maccy                                              | Maccy
shottr    | defaults | cc.ffitch.shottr                                              | Shottr
rectangle | file     | ~/Library/Application Support/Rectangle/RectangleConfig.json  | Rectangle
tabby     | file     | ~/Library/Application Support/tabby/config.yaml               | Tabby
sidebar   | sidebar  | ~/Library/Application Support/at.sidebar.Sidebar              | Sidebar
```

**Columns:**
- **`id`:** lowercase, unique. It names the settings file
  `settings/<id>.<ext>`, where the extension comes from the kind (`plist`,
  `sidebarbackup`) or, for `file`, from `where`.
- **`kind`:** one of `defaults`, `file` or `sidebar`, described below.
- **`where`:** the preferences domain, or the file path (a leading `~` is
  expanded).
- **`app`:** the app name in `/Applications`. It decides "installed?", and
  it is the app that is quit and restarted around an import.

Parse errors (wrong column count, unknown kind, duplicate id) name the line,
the same way as the catalog.

### Kinds

**`defaults`**
- **Export:** `defaults export <domain> -`, then drop every key that is:
  - runtime state, by prefix: `NSWindow`, `NSStatusItem`, `NSNavPanel`,
    `NSOSPLast`, `NSSplitView`, `NSToolbar`, `NSQuitAlwaysKeepsWindows`,
    `SU`, `MSAppCenter`, `GATelemetry`, `LaunchAtLogin__`;
  - secret by name (case-insensitive substring): `licen`, `token`, `serial`,
    `password`, `secret`.

  The result is written as an XML plist.
- **Apply:** merge into the current domain (existing keys the file doesn't
  have stay), wrapped as quit app → `defaults import` → reopen app.
  Unchanged settings mean nothing is restarted.
- `defaults` reads and writes sandboxed apps (Shottr, Maccy) through
  cfprefsd. This was verified on this Mac.

**`file`**
- **Export:** copy the file as it is.
- **Apply:** when the content differs, quit the app, back up the existing
  file as `<file>.bak-<yyyymmdd-HHMMSS>`, copy the file in, reopen the app.
  An identical file means nothing happens.
- Tabby's config is encrypted with its vault. On the new Mac, Tabby asks
  for the vault passphrase, which lives in the password manager.
- Rectangle loads `RectangleConfig.json` from its Application Support folder
  at launch. The spike (below) verifies this first; if it doesn't hold,
  Rectangle becomes a `defaults` entry (`com.knollsoft.Rectangle`).

**`sidebar`**
- Unchanged from MBC-7/11: the sanitised backup goes into Sidebar's backup
  list, and the user restores it in the app.

### Secret guard

After every export, before anything is written, every key is scanned
recursively, including keys in nested dicts and lists and inside Sidebar's
JSON:
- A key that still matches the secret names fails the export for that app.
  The error names the key, and the file is not written.
- `file` exports can't be filtered, so they are checked by type:
  - **`.json`**: every key, recursively.
  - **`.yaml` / `.yml`**: every `key:` at the start of a line. A YAML file
    whose top level has `encrypted: true` (Tabby's vault) passes: its
    secrets are encrypted.
  - **anything else**: every `key=` / `key:` at the start of a line.

## Commands

**`./bootstrap.sh --init-config <git-url>`**
- **Missing or empty config dir:** `git clone <url>` into it, then print what
  was cloned.
- **Config dir that is already a checkout of that URL:** "already set up".
- **Config dir with other content:** exit 2 with a message, and nothing is
  touched.
- **Dry run:** print only.

**`repos` step**
- When the config dir is a git checkout, it is pulled like a sibling repo
  (`pull --ff-only`, skipped with `--no-pull`).
- A dirty checkout or a diverged branch gives a warning, and the current
  state is kept. The step does not fail.

**`apps` step**
- For each registry entry whose app is installed **and** whose settings file
  exists: apply it.
- Otherwise the entry gets a one-line skip.
- No settings dir at all means the step is skipped (MBC-11 behaviour).

**`./bootstrap.sh --save-settings [id...]`**
- Exports every registry entry, or only the given ids, whose app is
  installed, into `SETTINGS_DIR`.
- It runs the secret guard.
- It prints `git -C <config dir> status --short` and `diff --stat` when the
  config dir is a checkout.
- It never commits: the user reviews the diff, then runs `git -C … commit`
  and `push`.
- It exits 1 when any app's export failed (the guard, or an unreadable
  domain or file).
- Export files are written 600 and a new dir 700, as in MBC-11.

## Migration on this Mac

1. Create the private GitHub repo `JtheGunner/macos-private-config` with
   `gh repo create --private`. This is an outward action, so the user
   confirms it first.
2. Turn `~/.config/macos-base-config/` into a checkout:
   - move `alttab.plist` → `settings/alt-tab.plist` and
     `sidebar.sidebarbackup` → `settings/sidebar.sidebarbackup`;
   - add a README and a `.gitignore`;
   - make the first commit.
3. Run `./bootstrap.sh --save-settings` for all registry apps. Review the
   files and the guard output with the user, commit, and push.
4. The raw exports in `~/Downloads/macos-configs` are **not** committed:
   Sidebar and Shottr ones contain license data. The user deletes them after
   the migration.

## Spike (first ticket)

- Rectangle: does it load `~/Library/Application Support/Rectangle/RectangleConfig.json`
  at launch? Test on a copy, with Rectangle quit and restarted.
- MouseBoost Pro: where are its settings? The bundle domain is empty, and
  the `group.com.shrek.rightmouse` domain only holds usage state. Look for
  files in `~/Library/Containers/com.shreklaunch.mouseboostpro/Data/`. If
  nothing portable is found, it stays out.

## Testing

All tests live in `tests/bootstrap-test.sh`: plain bash 3.2, the sandbox,
and stubs for `defaults`, `osascript`, `open` and `git`.

**Registry**
- It parses, and a malformed line reports its line number.
- The shipped registry parses.

**`defaults` kind**
- Export drops runtime and secret keys.
- Apply merges and keeps foreign keys.
- Unchanged settings mean no restart.
- Dry run changes nothing.

**`file` kind**
- Apply backs up the old file and copies in the new one.
- An identical file means nothing happens.
- A secret line fails the export.
- An encrypted Tabby config passes.

**Guard**
- A nested secret key fails that app. The other apps still export.

**`--init-config`**
- A missing dir gets cloned.
- The same URL is a no-op.
- Foreign content gives exit 2.
- Dry run prints only.

**`repos` step**
- The config checkout is pulled.
- A dirty checkout gives a warning and keeps its state.
- `--no-pull` skips it.

**`--save-settings`**
- It exports only installed apps and respects the `id` filter.
- It prints the git status.
- It exits 1 on a guard failure.

**Layout**
- `<config dir>/settings` is used when it exists.
- A flat MBC-11 dir keeps working.
- An explicit `SETTINGS_DIR` wins.

**Existing tests**
- The AltTab and Sidebar tests move onto the registry path, with the same
  behaviour.

## Rollout (tickets under one epic)

1. Spike (Rectangle JSON import, MouseBoost Pro settings), plus the registry
   parser and the `defaults` / `file` / `sidebar` kinds. AltTab and Sidebar
   move onto the registry. Includes the `settings/` layout with the flat
   fallback.
2. The secret guard, and `--save-settings`.
3. `--init-config`, and pulling the config checkout in the `repos` step.
4. Registry entries for Maccy, Shottr, Rectangle and Tabby, plus README
   sections: private config repo, saving and restoring settings.
5. Migration on this Mac: create the private repo (after confirmation), the
   first commit, the first `--save-settings`, review, push.

Ticket 1 comes first. Tickets 2 and 3 are independent of each other. Ticket 4
needs 1 and 2. Ticket 5 needs all of them.
