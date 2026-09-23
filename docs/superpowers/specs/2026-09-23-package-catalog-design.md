# Package catalog, optional installs and private settings — design

## Goal

- Every app and CLI tool the bootstrap can install is **optional**, AltTab,
  Sidebar and Karabiner-Elements included. The user picks from a catalog in
  their per-machine config instead of passing CLI flags.
- The repo ships a documented catalog (name, source, description) covering the
  user's apps and CLI tools. The repo is public, so the catalog holds nothing
  private.
- Private settings (AltTab, Sidebar, nas-mount shares) live **outside the
  repo**, in a private settings directory. That directory is optional. An app
  installs whether or not settings exist for it. Settings are applied only
  when both the app and its settings file are present.
- nas-mount is built from a template in the repo plus the shares in the
  private config.

Out of scope:
- uninstalling deselected packages;
- rewriting git history to purge the already-committed settings files (a
  separate, explicitly approved action);
- license keys, which stay manual from the password manager;
- tools the `dotfiles` repo / omnishell already installs.

## Layout

```text
packages/catalog.txt        the catalog: one package per line
lib/packages.sh             catalog parser, selection, Brewfile generation,
                            non-brew installers, --list-packages output
packages/nas-mount.applescript  template for the nas-mount applet
apps/app_settings.py        export/apply against the settings dir (no data in repo)
lib/steps.sh                brew + new extras step call lib/packages.sh
lib/config.sh               PACKAGES, SETTINGS_DIR, NAS_MOUNT_SHARES
Brewfile                    removed (replaced by the catalog)
apps/alttab.plist, apps/sidebar.sidebarbackup   removed from the repo
```

The catalog code is bash + awk (`lib/packages.sh`): `PACKAGES` is resolved
while the config loads, before the `brew` step, and on a Mac without the
Command Line Tools `/usr/bin/python3` only opens their install dialog.

## Catalog format

`packages/catalog.txt` is a `|`-separated line format with `#` comments, in the
spirit of `repos.txt`. It has no dependencies, is readable in a diff, and
allows app names with spaces:

```text
# id                | source  | ref                          | check              | category     | description
karabiner-elements  | cask    | karabiner-elements           | Karabiner-Elements | base         | Windows key behaviour (karabiner step)
firefox             | cask    | firefox                      | Firefox            | browser      | Web browser
whatsapp            | mas     | 310633997                    | WhatsApp           | communication| Messenger (App Store)
claude-code         | script  | https://claude.ai/install.sh | claude             | ai           | Claude Code CLI (native installer, self-updating)
gh                  | formula | gh                           | -                  | cli-dev      | GitHub CLI
huggingface-hub     | pipx    | huggingface-hub              | hf                 | cli-ai       | Hugging Face hub CLI (hf)
```

**Columns**

- `id`: unique, lowercase kebab-case. This is what `PACKAGES` names.
- `source`: one of the values in the Sources table below.
- `ref`: the package name, App Store id, URL or module path. What it means
  depends on the source.
- `check`: how to tell whether it is already installed.
  - For `cask` / `mas` / `applet` / `manual` it is the app name
    (`/Applications/<check>.app`).
  - For `script` / `npm` / `pipx` / `uv` / `go` it is a command on `PATH`.
  - `-` means the source is idempotent on its own (formulae, fonts).
- `category`: one word. `PACKAGES` can select it as `@category`.
- `description`: the rest of the line; shown by `--list-packages`.

The parser rejects the whole catalog with a line number for any of these:
duplicate ids, an unknown source, a wrong column count, or an empty required
column. A test runs the parser over the shipped catalog.

## Sources

| source    | installed by                                        | step     | "already there" check                 |
|-----------|-----------------------------------------------------|----------|---------------------------------------|
| `formula` | generated Brewfile: `brew "<ref>"` (tap auto-added for `user/tap/name`) | `brew` | brew bundle |
| `cask`    | generated Brewfile: `cask "<ref>"`                   | `brew`   | `/Applications/<check>.app` exists → not listed |
| `mas`     | separate generated Brewfile: `mas "<check>", id: <ref>` | `brew` | `/Applications/<check>.app` exists → not listed |
| `script`  | `curl -fsSL <ref> \| bash`                           | `extras` | `command -v <check>`                  |
| `npm`     | `npm install -g <ref>`                               | `extras` | `command -v <check>`                  |
| `pipx`    | `pipx install <ref>`                                 | `extras` | `command -v <check>`                  |
| `uv`      | `uv tool install <ref>`                              | `extras` | `command -v <check>`                  |
| `go`      | `go install <ref>@latest`                            | `extras` | `command -v <check>`                  |
| `applet`  | build from template (nas-mount only, see below)      | `extras` | rebuilt only when the script differs  |
| `manual`  | not installed; `manual` prints a hint + `ref` URL    | `manual` | `/Applications/<check>.app` exists → no hint |

**Details**

- **Existing apps.** The existing-app guard (today the Ruby `app_missing?` in
  the Brewfile) moves into the generator. Brew refuses to install over an app
  it did not install, and would fail the whole bundle.
- **App Store entries** go through their own `brew bundle` run.
  - A signed-out App Store then fails only those entries. The failure reason
    is "App Store: sign in, then re-run".
  - `mas` cannot sign in by itself, and paid apps must already belong to the
    Apple ID. The README says so.
- **Prerequisites.**
  - `mas`, `pipx`, `uv` and `go` are added automatically to the brew run when
    a selected package needs them.
  - `npm` packages need a Node on `PATH`; without one they are skipped with
    "install Node first (e.g. nvm install --lts)". Node comes from nvm, not
    Homebrew.
- **Dry run** prints the generated Brewfiles and the commands. It installs
  nothing.
- **Failures.** One failing `extras` package does not stop the others. The
  step fails at the end with the names of the failed packages.

## Selection (`PACKAGES`)

In the config (`config.example.sh` documents it):

```bash
# ids, @category, @all; a leading "-" removes: "@all -steam -@cli-ai"
PACKAGES="@base @browser bitwarden claude-code @cli-dev -php@8.3"
```

**How the list is evaluated**

- Tokens are read left to right, and the order does not matter for the
  result.
- The selection is everything the plain tokens add, minus everything the
  `-` tokens remove.
- An unknown id or category is a config error (exit 2) and names the token.

**Unset vs. empty**

- `PACKAGES` **unset** (no config, or the key is missing) means `@base`, which
  is exactly today's behaviour: Karabiner-Elements, AltTab, Sidebar and
  JetBrains Mono. Existing machines see no change.
- `PACKAGES=""` means install **nothing** from the catalog. Every entry,
  `@base` included, is therefore optional.

`BREW_BUNDLE_EXTRA` stays as is for things outside the catalog.

**`./bootstrap.sh --list-packages`** prints the catalog grouped by category.
Each line shows:
- whether the package is selected;
- whether it is installed (the check column);
- its description.

## Steps

New order: `repos brew extras karabiner keyboard macos jetbrains vscode editor apps dotfiles manual`.

**brew**
- Installs Homebrew if missing.
- Generates the Brewfiles for the selected `formula`/`cask`/`mas` entries into
  a temp dir, then runs `brew bundle --no-upgrade` on them.
- Runs `BREW_BUNDLE_EXTRA` last.
- Nothing selected for brew: "no brew packages selected" (ok).

**extras** (new): installs the selected `script`/`npm`/`pipx`/`uv`/`go`/`applet`
entries. Nothing selected: skip.

**karabiner:** the skip message becomes "Karabiner-Elements not installed - add
karabiner-elements to PACKAGES".

**apps**
- Runs `app_settings.py apply --dir "$SETTINGS_DIR"`.
- Each app is applied only when it is installed **and** its file exists in
  the settings dir. Otherwise: "AltTab: no settings in <dir> - skipped".
- No settings dir at all → step skip.

**manual:** the Sidebar-restore and license lines are printed only when that
app is installed. FileZilla-style `manual` entries print "install <id>: <url>"
when selected and missing.

`step_description` and the README step table are updated to match.

## Private settings directory

- `SETTINGS_DIR` in the config sets it. Its default is the directory of the
  config file in use (`~/.config/macos-base-config/`, or wherever `--config`
  points), so one `--config` path locates everything private.
- It holds `alttab.plist` and `sidebar.sidebarbackup`. The nas-mount shares are
  a config value, not a file.
- **Export:** `python3 apps/app_settings.py export [--dir DIR]` writes there
  (default = the default config dir). It uses the same sanitising as today,
  with no license keys.
- **Keeping it across machines** is up to the user and not scripted. The README
  suggests keeping the directory in iCloud Drive and pointing
  `--config` at it (e.g.
  `~/Library/Mobile Documents/com~apple~CloudDocs/macos-base-config/config.sh`).
  iCloud Drive is available right after the Apple ID sign-in, before any app
  is installed.
- `apps/alttab.plist` and `apps/sidebar.sidebarbackup` are removed from the
  repo (`git rm`) and added to `.gitignore`. Before that, the current files
  are copied to the user's settings dir.
- **Guard test:** `apps/` tracks no `*.plist` / `*.sidebarbackup`. The
  existing "no `licen*` key" guard moves to the export output in the tests.

## nas-mount

- **Template.** `packages/nas-mount.applescript` loops over the shares, with a
  `try` per share so one unreachable share does not block the rest:

  ```applescript
  tell application "Finder"
    repeat with share in {%SHARES%}
      try
        mount volume share
      end try
    end repeat
  end tell
  ```

- **Config:** `NAS_MOUNT_SHARES="smb://10.0.12.20/privat smb://10.0.12.20/data smb://10.0.12.20/mac-studio"`
  (space-separated URLs). Each must start with `smb://`, `afp://` or
  `nfs://`, otherwise it is a config error. No credentials: Finder takes them
  from the Keychain.
- **Build.** The `applet` handler renders the template, compiles it with
  `osacompile -o <tmp>/nas-mount.app` and compares it with the installed
  applet's `osadecompile` output. It replaces `/Applications/nas-mount.app`
  only when they differ, and prints "unchanged" otherwise.
- **Selected but no shares:** skip with "set NAS_MOUNT_SHARES in the config".
  Login-item registration is not part of this.

## Catalog content

Tools installed by dotfiles/omnishell are **not** listed: stow, git-delta, fzf,
zoxide, ripgrep, fd, bat, eza, starship, mise, tmux, direnv, broot, the zsh
plugins, omnishell, ghostty.

| category | entries (source) |
|---|---|
| `base` | karabiner-elements, alt-tab, sidebar (`otuerk/sidebar/sidebar`), font-jetbrains-mono (cask) |
| `browser` | firefox, google-chrome (cask) |
| `dev` | visual-studio-code, antigravity, antigravity-ide, jetbrains-toolbox, tabby, docker-desktop, dbeaver-community, postman, wireshark-app (cask); filezilla (manual, https://filezilla-project.org/download.php?type=client) |
| `ai` | claude (cask), claude-code (script), lm-studio (cask), mlx-dspark (cask, `arahim3/mlx-dspark`) |
| `productivity` | bitwarden, google-drive, rectangle, shottr, trex, pearcleaner, swiftdefaultappsprefpane (cask); maccy 1527619437, mouseboost-pro 1555844307 (mas) |
| `communication` | telegram (cask); whatsapp 310633997 (mas) |
| `remote` | tailscale-app, teamviewer (cask); windows-app 1295203466 (mas); nas-mount (applet) |
| `media` | spotify, vlc, steam (cask) |
| `cli-shell` | coreutils, htop, tldr, screenfetch, iproute2mac (formula) |
| `cli-dev` | gh, git-filter-repo, go, nvm, pipx, uv, python@3.12, python@3.14, php@8.3, php@8.4, composer, qodana (`jetbrains/utils/qodana`) (formula); gopls (go, `golang.org/x/tools/gopls`); sass (npm) |
| `cli-ops` | mariadb, mysql-client, helm, sshpass (formula) |
| `cli-ai` | summarize, openai-whisper (formula); huggingface-hub, litellm, mlx-lm, mlx-vlm, mlx-dspark-cli (pipx); nano-pdf (uv); @google/gemini-cli, @continuedev/cli, openclaw, clawhub (npm) |
| `cli-docs` | ghostscript, poppler, tesseract, tesseract-lang (formula) |
| `cli-macos` | codexbar (`steipete/tap/codexbar`), remindctl (`steipete/tap/remindctl`), spogo (`steipete/tap/spogo`), memo (`antoniorodr/memo/memo`), dutix (`jackchuka/tap/dutix`) (formula) |

Each cask's `check` app name is taken from its installed bundle and
double-checked against `brew info --cask`. App Store ids were read from the
installed apps (`kMDItemAppStoreAdamID`); Maccy's id is checked against the
App Store when the catalog is written.

## Testing

All tests go in the existing `tests/bootstrap-test.sh`, in plain bash 3.2 with
stubs for `brew`, `mas`, `npm`, `pipx`, `uv`, `go`, `curl`, `osacompile`,
`osadecompile`.

**Catalog**
- The shipped catalog parses.
- Malformed lines fail with a line number.
- Duplicate ids are rejected.

**Selection**
- Unset → `@base`; empty → nothing.
- `@category`, `@all`, `-id`, `-@category` work.
- Unknown token → config error.

**Brewfile generation**
- Casks whose app already exists are left out.
- A tap is added for `user/tap/name`.
- App Store entries go to a separate file, and `mas` is added as a
  prerequisite.
- `pipx`/`uv`/`go` prerequisites are added.

**brew and extras steps**
- Commands are logged per source, and the dry run installs nothing.
- Already-installed commands are skipped.
- `npm` without Node → skip hint.
- One failing package still runs the rest and fails the step with its name.

**Other steps**
- **karabiner:** new skip hint when not installed.
- **apps:** no settings dir → skip; app installed without a file → per-app
  skip; file without the app → skip; both → apply. Export writes to `--dir`
  and contains no `licen*` key.
- **nas-mount:** rendered script contains every share with its own `try`;
  unchanged → no replace; no shares → skip; invalid URL → config error.
- **manual:** lines depend on what is installed.

**Guards and end to end**
- Guard: no settings files tracked under `apps/`.
- E2E: the full dry run in the sandbox shows the new step order.

## Rollout (tickets under one epic)

1. **Catalog + selection + brew step**
   - Adds `catalog.txt` with the `base` entries only.
   - Adds `lib/packages.sh` (parse, select, Brewfile generation, `--list-packages`),
     `PACKAGES` in the config, and removes `Brewfile`.
   - Karabiner hint, README.
2. **extras step**: `script`/`npm`/`pipx`/`uv`/`go` handlers and `manual` hints.
3. **Private settings dir**: `SETTINGS_DIR`, `app_settings.py --dir`, per-app
   skip, copy the current files to the user's dir, `git rm` + `.gitignore` +
   guard test, README.
4. **nas-mount**: template, `NAS_MOUNT_SHARES`, `applet` handler.
5. **Fill the catalog**: every app and CLI tool above, with verified `check`
   names and App Store ids, and the README catalog overview.

Tickets 2–5 depend on 1. Tickets 3 and 4 are independent of 2.
