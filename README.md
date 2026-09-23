<div align="center">

# 🍎 macOS base config

**Windows / PC muscle memory on a Mac, with a Swiss‑German ISO keyboard.**
One bootstrap for the apps, the keyboard layout, the Karabiner remaps, the IDE
keymaps, the few macOS tweaks that go with them, and the shell dotfiles.

<code>🇨🇭 layout</code> &nbsp;→&nbsp; <code>⌨️ Karabiner</code> &nbsp;→&nbsp; <code>🧠 JetBrains keymap</code> &nbsp;→&nbsp; <code>💻 VS Code family</code> &nbsp;→&nbsp; <code>🐚 dotfiles</code>

![macOS](https://img.shields.io/badge/macOS-only-0ea5e9?style=flat-square&logo=apple&logoColor=white)
![Bash · Python](https://img.shields.io/badge/bash%20·%20python%203-scripts-3776ab?style=flat-square&logo=python&logoColor=white)
![Keyboard](https://img.shields.io/badge/keyboard-Swiss%20German%20ISO-8b5cf6?style=flat-square)
![Re-runnable](https://img.shields.io/badge/bootstrap-re--runnable-22c55e?style=flat-square)

</div>

---

## 🚀 Quick start

Clone it into whatever folder you keep your repos in, e.g. `~/code`:

```sh
cd ~/code                   # any folder works
git clone git@github.com:JtheGunner/macos-base-config.git
cd macos-base-config
./bootstrap.sh --dry-run    # see what would happen
./bootstrap.sh              # every step
./bootstrap.sh keymaps      # only some steps
./bootstrap.sh --skip dotfiles
```

> [!NOTE]
> **Where you clone it does not matter.** `bootstrap.sh` puts the sibling repos
> **next to this one**, in the same parent folder, and every script finds them
> there. No path is hard-coded.
>
> ```text
> <your folder>/
> ├── macos-base-config/                          ← you clone this
> ├── karabiner-windows-keyboard-mapping-macos/   ← bootstrap.sh clones the rest
> ├── swiss-windows-keyboard-layout-macos/
> ├── intelli-key-port/
> └── dotfiles/                                   ← or DOTFILES_DIR, see Configuration
> ```
>
> A sibling that is already there is updated with `git pull --ff-only`
> instead of cloned again.

`bootstrap.sh` is best-effort and re-runnable: a failing step is reported in
the summary at the end (exit code 1), it never aborts the rest.

```text
 ./bootstrap.sh [step ...]
   │
   ├─ repos       clone / pull each sibling repo (repos.txt) into the parent folder
   ├─ brew        Homebrew (installed if missing) + the selected packages (default: Karabiner, AltTab, Sidebar, font)
   ├─ extras      selected packages from outside Homebrew: install scripts, npm, pipx, uv, go; the nas-mount app
   ├─ karabiner   Karabiner config → ~/.config/karabiner   (starts Karabiner once if needed)
   ├─ keyboard    Custom Swiss German layout → ~/Library/Keyboard Layouts, enabled + selected
   ├─ macos       macos-defaults.py: system hotkeys, Finder shortcut, font smoothing (+ Gatekeeper, opt-in)
   ├─ jetbrains   JetBrains keymap → IDE config, set active (skipped until PhpStorm has a config)
   ├─ vscode      same keymap → VS Code / Antigravity         (same condition)
   ├─ editor      font settings → settings.json of every VS Code-family editor
   ├─ apps        app settings from SETTINGS_DIR, per apps/registry.txt   (no licenses)
   ├─ dotfiles    the dotfiles repo's own bootstrap.sh: shell, prompt, git, tmux, Ghostty
   ├─ manual      print the manual steps
   └─ summary     ok / skipped / failed per step
```

> [!IMPORTANT]
> On a fresh Mac the `brew` step installs Homebrew first, which asks once for
> your password. Karabiner then still needs its permissions (Driver Extension,
> Input Monitoring, Accessibility), see [Manual steps](#-manual-steps).

---

## 🎛️ Steps and options

Name steps to run only those; they always run in the order below. With no
step named, every step runs.

|    | Step        | Runs                                                |
|:--:|-------------|-----------------------------------------------------|
| 📥 | `repos`     | clone missing / pull existing sibling repos         |
| 🍺 | `brew`      | Homebrew installer if missing, `brew bundle` of the selected packages |
| 🧩 | `extras`    | install scripts, `npm -g`, `pipx`, `uv tool`, `go install` for the selected packages |
| ⌨️  | `karabiner` | `karabiner-windows-keyboard-mapping-macos/apply.sh` |
| 🇨🇭 | `keyboard`  | layout copy + `enable-input-source.swift`           |
| 🛠️ | `macos`     | `macos-defaults.py`, Gatekeeper if opted in         |
| 🧠 | `jetbrains` | `ide-keymaps/apply.sh`                              |
| 💻 | `vscode`    | `ide-keymaps/port-vscode.sh`                        |
| 🔤 | `editor`    | `editor-settings/apply.py`                          |
| 🗂️ | `apps`      | `apps/app_settings.py apply`                        |
| 🐚 | `dotfiles`  | `dotfiles/bootstrap.sh`                             |
| ✋ | `manual`    | print the manual steps                              |

`keymaps` is an alias for `jetbrains vscode`. A step that needs a sibling repo
clones it itself, so `./bootstrap.sh dotfiles` works on its own.

| Option            | Effect                                                                     |
|-------------------|----------------------------------------------------------------------------|
| `--skip <step>`   | skip a step or alias; repeatable                                           |
| `--dry-run`       | show what would happen; sub-tools get `--dry-run`, no git, no dotfiles run |
| `--no-pull`       | don't update siblings that are already cloned                              |
| `--config <path>` | use this config file                                                       |
| `--list`          | list the steps                                                             |
| `--list-packages` | list the package catalog: what is selected, what is installed             |
| `--save-settings [app…]` | save the app settings into `SETTINGS_DIR`, see [App settings](#app-settings) |
| `--init-config <git-url>` | clone your private config repo into the config dir, see [Private config repo](#private-config-repo) |
| `-h`, `--help`    | usage                                                                      |

---

## ⚙️ Configuration

Per-machine settings live in `~/.config/macos-base-config/config.sh`, a plain
bash file that is **not** part of the repo. Start from the template:

```sh
mkdir -p ~/.config/macos-base-config
cp config.example.sh ~/.config/macos-base-config/config.sh
```

### Private config repo

Keep that folder as a **private** git repo, and a new Mac gets your config
and app settings in one step:

```text
~/.config/macos-base-config/      ← your private repo, e.g. macos-private-config
├─ config.sh                      PACKAGES, NAS_MOUNT_SHARES, …
└─ settings/                      app settings (./bootstrap.sh --save-settings)
```

```sh
./bootstrap.sh --init-config git@github.com:<you>/macos-private-config.git   # new Mac
./bootstrap.sh                                                                # then everything
```

- `--init-config` clones only into a missing or empty folder. A folder with
  other files, or a checkout of another repo, is left alone (exit 2).
- The `repos` step pulls it on every run (`--no-pull` skips). A checkout
  with local changes is not pulled, only warned about. A pulled `config.sh`
  takes effect on the next run.
- Cloning a private repo needs your GitHub access (SSH key or `gh auth login`)
  set up first, like the sibling repos.
- License keys and passwords never go into it:
  `--save-settings` refuses to write them.

| Key                         | Default             | Effect                                                                                                                 |
|-----------------------------|---------------------|------------------------------------------------------------------------------------------------------------------------|
| `BOOTSTRAP_STEPS`           | all steps           | steps to run when none are named on the command line                                                                   |
| `BOOTSTRAP_SKIP`            | —                   | steps never to run on this machine                                                                                     |
| `PACKAGES`                  | `@base`             | packages to install from the [catalog](#-apps-and-tools): ids, `@category`, `@all`; a leading `-` removes; `""` = none |
| `BREW_BUNDLE_EXTRA`         | —                   | extra Brewfile for apps outside the catalog, installed after the selected packages                                    |
| `MACOS_DISABLE_GATEKEEPER`  | `0`                 | `1` = allow apps from anywhere (`sudo spctl --master-disable`); macOS asks you to confirm in Privacy & Security       |
| `SETTINGS_DIR`              | `settings/` next to `config.sh` | private app settings (`alt-tab.plist`, `sidebar.sidebarbackup`, …), see [App settings](#app-settings)       |
| `NAS_MOUNT_SHARES`          | —                   | smb:// / afp:// / nfs:// shares the `nas-mount` app mounts, see [NAS shares](#nas-shares-nas-mount)             |
| `DOTFILES_DIR`              | `<parent>/dotfiles` | dotfiles checkout to use, e.g. an existing `~/Git/dotfiles`                                                            |
| `DOTFILES_URL`              | URL in `repos.txt`  | clone URL, e.g. a fork                                                                                                 |
| `DOTFILES_ASSUME_YES`       | `0`                 | `1` = repoint stow links from another checkout without asking                                                          |
| `DOTFILES_TERMINALS`        | —                   | extra terminal stow packages for the dotfiles bootstrap                                                                |
| `DOTFILES_OMNISHELL_CONFIG` | —                   | own omnishell `config.toml`, applied after the dotfiles bootstrap                                                      |
| `DOTFILES_LOCAL_RC`         | —                   | shell lines for `~/.zshrc.local` + `~/.bashrc.local`, see [Machine-local shell aliases](#-machine-local-shell-aliases) |

Steps named on the command line replace `BOOTSTRAP_STEPS`; `--skip` adds to
`BOOTSTRAP_SKIP`. An invalid config (syntax error, unknown step, bad value)
stops the bootstrap before any step runs.

> [!TIP]
> Already have the dotfiles checked out somewhere else? Set `DOTFILES_DIR` to
> that checkout. Otherwise, the dotfiles bootstrap asks whether to repoint every
> stow link to the new `<parent>/dotfiles` clone. If you decline, or there is no
> terminal to ask, the `dotfiles` step fails and names both ways out:
> `DOTFILES_ASSUME_YES=1` (repoint without asking) or `DOTFILES_DIR`.

---

## 🧩 What lives where

|    | Piece                                                                       | Repo / file                                                                                                          | Apply                                                               |
|:--:|-----------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| 🇨🇭 | **AltGr characters** (`@ # \| \ ~ [] {} €`): custom keyboard *layout*       | [`swiss-windows-keyboard-layout-macos`](https://github.com/JtheGunner/swiss-windows-keyboard-layout-macos)           | the `keyboard` step installs and enables it                         |
| ⌨️  | **Windows key behaviour** (`Ctrl+C/V/Z`, word jump, `Alt+F4`, …): Karabiner | [`karabiner-windows-keyboard-mapping-macos`](https://github.com/JtheGunner/karabiner-windows-keyboard-mapping-macos) | `./setup.sh` (fresh Mac) or `./apply.sh`: bootstrap runs `apply.sh` |
| 🛠️ | **macOS-level shortcuts Karabiner can't do**                                | `macos-defaults.py` (this repo)                                                                                      | `python3 macos-defaults.py`: bootstrap runs it                      |
| 🧠 | **JetBrains keymap** `jeffry-default-macos-win Proper Redo`                 | `ide-keymaps/` (this repo): [README](ide-keymaps/README.md)                                                          | `ide-keymaps/apply.sh` (quit the IDE first): bootstrap runs it; also turns the terminal's *Use Option as Meta key* off |
| 💻 | **VS Code / Antigravity keybindings**, generated from the JetBrains keymap  | [`intelli-key-port`](https://github.com/JtheGunner/intelli-key-port) + layers from `ide-keymaps/`                    | `ide-keymaps/port-vscode.sh`: bootstrap runs it                     |
| 🐚 | **Shell, prompt, git, tmux, Ghostty**                                       | [`dotfiles`](https://github.com/JtheGunner/dotfiles)                                                                 | its own `bootstrap.sh`: the `dotfiles` step runs it                 |

> [!WARNING]
> Port the VS Code keybindings only through `ide-keymaps/port-vscode.sh`. It
> adds the `windows-keymap` and `karabiner-winkeys` layers and the personal
> layer. A bare `./port.py` in `intelli-key-port` installs a neutral port over
> your current bindings. It backs them up first.

---

## 🔠 AltGr characters vs. IDE shortcuts

AltGr is the right Option key. macOS apps cannot tell left from right Option,
so any IDE shortcut on `Option+<digit>` swallows the character AltGr+digit
should type. The pieces are set up to keep both working:

|    | Piece             | What it does                                                                                                                               |
|:--:|-------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| 🇨🇭 | keyboard layout   | AltGr+1 / 2 / 3 / 7 type `\|` `@` `#` `\|`                                                                                                 |
| ⌨️  | Karabiner rule 45 | in IDEs, the physical **Alt** key + digit becomes `Ctrl+Shift+Alt+Cmd` + digit (on the MX Keys in Mac mode, Alt arrives as `left_command`) |
| 🧠 | JetBrains keymap  | tool windows (Project, Find, Structure, …) sit on `Ctrl+Shift+Alt+Cmd+<digit>`, so no `Option+<digit>` shortcut is left                    |
| 💻 | `port-vscode.sh`  | carries those bindings over to VS Code / Antigravity                                                                                       |

Result: **Alt+digit** opens a tool window, **AltGr+digit** types the character.
In the PhpStorm terminal, *Use Option as Meta key* must be off, or AltGr
characters turn into escape sequences. `ide-keymaps/apply.sh` turns it off.

---

## 🛠️ macOS-level shortcuts Karabiner can't do

Karabiner is an event remapper with no awareness of app menus or text-field
focus, so a few things must be done at the macOS `defaults` level.
`macos-defaults.py` does them idempotently and writes a `restore-<timestamp>.sh`
per run:

- **Mission Control `Ctrl+←/→` "Move a space"** (symbolic hotkeys 79‑82) is
  disabled. Otherwise, macOS takes `Ctrl+Arrow` before any app sees it, and word
  navigation never works in editors.
- **"Turn VoiceOver on or off"** (symbolic hotkey 59, `Cmd+F5`) is disabled.
  Karabiner sends `Ctrl+F5` as `Cmd+F5`, which would start VoiceOver.
- **Finder: forward-delete key → "Move to Bin"** via an *App Shortcut*
  (`NSUserKeyEquivalents`). It is menu-aware, so it still deletes forward inside
  a rename or search field. A Karabiner rule could not tell the difference.
- **`AppleFontSmoothing = 1`**: thinner bold system font.

```sh
python3 macos-defaults.py --show     # current state
python3 macos-defaults.py --dry-run
python3 macos-defaults.py            # apply; log out / in for the hotkeys + font
```

---

## ✋ Manual steps

The `manual` step prints a reminder of these. macOS doesn't let a script do
them.

|    | Step                      | How                                                                                                                                         |
|:--:|---------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| 🔐 | **Karabiner permissions** | Driver Extension, Input Monitoring, Accessibility. `karabiner-windows-keyboard-mapping-macos/setup.sh` opens the panes and lists the steps |
| 🇨🇭 | **Input source**          | check *Custom Swiss German* under System Settings → Keyboard → Input Sources, then log out and in. The `keyboard` step enables it when it can |
| 🛡️ | **Gatekeeper**            | only with `MACOS_DISABLE_GATEKEEPER=1`: confirm "Allow applications from: Anywhere" under Privacy & Security (the `macos` step opens it)    |
| 📌 | **Sidebar settings**      | only when Sidebar is installed and its backup is in `SETTINGS_DIR`: Sidebar → Settings → Expert → Backups → **Restore** the backup the `apps` step added (Sidebar has no way to import from a script) |
| 🔑 | **Licenses**              | the installed ones of AltTab (Pro) and Sidebar: enter the keys from your password manager in each app                                      |

---

## 🐚 Machine-local shell aliases

The public [`dotfiles`](https://github.com/JtheGunner/dotfiles) repo keeps
only generic aliases. Anything tied to this machine's setup goes in
`~/.zshrc.local` / `~/.bashrc.local`, which the dotfiles source last and never
version-control. Set them through `DOTFILES_LOCAL_RC` in your `config.sh`:

```sh
DOTFILES_LOCAL_RC='
# Kubernetes dashboard: print a login token for the admin-user service account
command -v kubectl >/dev/null 2>&1 &&
  alias kdash-token="kubectl -n kubernetes-dashboard create token admin-user"
'
```

The `dotfiles` step writes these lines into both files as one managed block:

```text
# >>> macos-base-config >>>
# managed by macos-base-config (DOTFILES_LOCAL_RC) - edit its config.sh, not this block
...
# <<< macos-base-config <<<
```

- Every run replaces the block; whatever else is in those files stays as it is.
- An empty `DOTFILES_LOCAL_RC` removes the block.
- A file that doesn't exist yet is created readable only by you (`600`), since it
  may hold tokens.
- The lines must be valid for both bash and zsh. A syntax error stops the
  bootstrap before any step runs.

Run `./bootstrap.sh dotfiles`, then open a new shell (`exec $SHELL`).

---

## 🧪 Tests

```sh
/bin/bash tests/bootstrap-test.sh
```

Runs the argument parsing, config and step tests under macOS's bash 3.2. The
end-to-end cases run in a throwaway sandbox with stub tools, so nothing on
the machine changes.

---

## 📦 Apps and tools

Everything the bootstrap can install is listed in the catalog,
[`packages/catalog.txt`](packages/catalog.txt): one package per line with its
source (Homebrew formula or cask, App Store, …) and a description. **Nothing
is mandatory**: pick what this Mac gets with `PACKAGES` in the
[config](#%EF%B8%8F-configuration).

```sh
./bootstrap.sh --list-packages   # the catalog: [x] selected, installed / missing
./bootstrap.sh brew extras       # install the selection
```

Where a package comes from decides which step installs it:

| Source    | Installed by                                   | Step     |
|-----------|------------------------------------------------|----------|
| `formula` | `brew bundle` (`brew "…"`)                     | `brew`   |
| `cask`    | `brew bundle` (`cask "…"`)                     | `brew`   |
| `mas`     | `brew bundle` (`mas "…"`), App Store           | `brew`   |
| `script`  | the vendor's install script (`curl … \| bash`) | `extras` |
| `npm`     | `npm install -g`                               | `extras` |
| `pipx`    | `pipx install`                                 | `extras` |
| `uv`      | `uv tool install`                              | `extras` |
| `go`      | `go install …@latest`                          | `extras` |
| `applet`  | built from a template in this repo (`nas-mount`) | `extras` |
| `manual`  | you: the `manual` step prints the download link | `manual` |

| `PACKAGES`                    | Installs                                        |
|-------------------------------|-------------------------------------------------|
| *(key not set)*               | `@base`: Karabiner-Elements, AltTab, Sidebar, JetBrains Mono |
| `""`                          | nothing                                         |
| `"alt-tab font-jetbrains-mono"` | just these packages                           |
| `"@all -sidebar"`             | everything except one package (`-@category` removes a whole category) |

The `@base` packages:

|    | Package                                                 | For                                  |
|:--:|---------------------------------------------------------|--------------------------------------|
| ⌨️  | [Karabiner-Elements](https://karabiner-elements.pqrs.org/) | Windows key behaviour (`karabiner` step) |
| 🔀 | [AltTab](https://alt-tab.app/)                          | Windows-style `Alt+Tab` window switching |
| 📌 | [Sidebar](https://sidebarapp.net/)                      | Windows-style taskbar, Dock replacement |
| 🔤 | JetBrains Mono                                          | editor font, see [Fonts](#-fonts)    |

The whole catalog at a glance. Homebrew wherever it has the package; the
source column in `packages/catalog.txt` says where each one comes from.

|    | Category        | Packages |
|:--:|-----------------|----------|
| 🧱 | `base`          | karabiner-elements, alt-tab, sidebar, font-jetbrains-mono |
| 🌐 | `browser`       | firefox, google-chrome |
| 💻 | `dev`           | visual-studio-code, antigravity, antigravity-ide, jetbrains-toolbox, tabby, docker-desktop, dbeaver-community, postman, wireshark-app, filezilla *(download link)* |
| 🤖 | `ai`            | claude, claude-code, lm-studio, mlx-dspark |
| 🧰 | `productivity`  | bitwarden, google-drive, rectangle, shottr, trex, maccy, mouseboost-pro *(App Store)*, pearcleaner, swiftdefaultappsprefpane |
| 💬 | `communication` | telegram, whatsapp |
| 🛰️ | `remote`        | tailscale-app, teamviewer, windows-app, nas-mount |
| 🎵 | `media`         | spotify, vlc, steam |
| 🐚 | `cli-shell`     | coreutils, htop, tldr, screenfetch, iproute2mac |
| 🛠️ | `cli-dev`       | gh, git-filter-repo, go, gopls, nvm, pipx, uv, python@3.12, python@3.14, php@8.3, php@8.4, composer, qodana, sass |
| 🗄️ | `cli-ops`       | mariadb, mysql-client, helm, sshpass |
| 🧠 | `cli-ai`        | summarize, openai-whisper, hf, mlx-lm, gemini-cli, litellm, mlx-vlm, mlx-dspark-cli *(pipx)*, nano-pdf *(uv)*, continue-cli, openclaw, clawhub *(npm)* |
| 📄 | `cli-docs`      | ghostscript, poppler, tesseract, tesseract-lang |
| 🍎 | `cli-macos`     | codexbar, remindctl, memo, spogo, dutix |

Shell tools (bat, eza, fd, fzf, ripgrep, starship, tmux, zoxide, …) are not in
the catalog: the [`dotfiles`](https://github.com/JtheGunner/dotfiles) step
installs them.

- Installed apps are never upgraded by the bootstrap (`--no-upgrade`); they
  update themselves.
- An app already in `/Applications` is left alone, even when Homebrew didn't
  install it.
- App Store packages need you signed in to the App Store. Paid apps must
  already belong to your Apple ID.
- Apps outside the catalog go in your own Brewfile: set `BREW_BUNDLE_EXTRA`.
- `pipx`, `uv` and `go` are installed by the `brew` step when a selected
  package needs them. `npm` packages need Node: `nvm install --lts` first.
- A package whose command is already on your `PATH` is left alone, however it
  was installed. `~/.local/bin` and `~/go/bin` (where pipx, `uv tool`,
  `go install` and most install scripts put commands) count too; put them on
  your shell's `PATH` to use what lands there.
- Install scripts are fetched over https only.

### NAS shares (nas-mount)

`nas-mount` is a small app that mounts your NAS shares in Finder; open it or
add it to your login items. Select it with `nas-mount` in `PACKAGES` and list
the shares in the config:

```sh
PACKAGES="@base nas-mount"
NAS_MOUNT_SHARES="smb://nas.local/data smb://nas.local/media"
```

- The `extras` step builds `/Applications/nas-mount.app` from
  [`packages/nas-mount.applescript`](packages/nas-mount.applescript). Each
  share has its own `try`, so one that is offline doesn't stop the rest.
- No credentials in the config or the app: Finder asks once and keeps them in
  the Keychain.
- Changed shares rebuild the app on the next run; the old one goes to the
  Trash. Unchanged shares leave it alone.
- Shares are separated by spaces or newlines; write a space inside a path as
  `%20`.

### App settings

The `apps` step brings your app settings onto the Mac. Which apps, and where
each one keeps its settings, is listed in [`apps/registry.txt`](apps/registry.txt).
The settings themselves are **private and never part of this public repo**:
they live in your settings directory, `SETTINGS_DIR`, by default
`settings/` next to your config file
(`~/.config/macos-base-config/settings/`, or the config folder itself if it
has no `settings/`). **No license is ever exported**: enter those from your
password manager once per Mac.

|    | App     | File in `SETTINGS_DIR`                                                                                 | On `./bootstrap.sh apps`                                                          |
|:--:|---------|--------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| 🔀 | AltTab  | `alt-tab.plist`: its preferences, minus window frames, update and telemetry state                      | merged into its preferences; a running AltTab restarts. Unchanged settings leave it alone |
| 📌 | Sidebar | `sidebar.sidebarbackup`: a Sidebar backup without license, usage data, statistics, calendars or window state | added to Sidebar's backup list; restore it there (Settings → Expert → Backups)     |

Everything is optional: an app that isn't installed, or has no file in the
settings directory, is skipped. Without a settings directory the step is
skipped.

Adding an app is one line in the registry, in one of three kinds:

| Kind       | For                                   | Export                                                  | Apply                                                   |
|------------|---------------------------------------|---------------------------------------------------------|---------------------------------------------------------|
| `defaults` | a preferences domain (most Mac apps)  | the domain without window / update / telemetry state and without license or token keys | merged into the domain; a running app is restarted |
| `file`     | an app with a settings file           | the file as it is                                       | copied in; the old file is kept as `.bak-<time>`        |
| `sidebar`  | Sidebar's backup format               | the newest backup, stripped of license and usage data   | added to Sidebar's backup list                          |

To save the settings of this Mac (for Sidebar, first create a backup in
Sidebar → Settings → Expert → Backups → *Create backup*):

```sh
./bootstrap.sh --save-settings            # every installed app in the registry
./bootstrap.sh --save-settings alt-tab    # only these apps (registry ids)
```

- The files go to `SETTINGS_DIR`, readable only by you (`600`).
- A **secret guard** checks every file before it is written: a key that looks
  like a license, token, serial, password or secret stops that app's export
  (the file is not written, the key is named, exit 1). Tabby's vault-encrypted
  config passes.
- When `SETTINGS_DIR` is in a git repo (your private config repo), the command
  shows `git status` and `git diff --stat`. It never commits: review, then
  commit and push yourself.

> [!TIP]
> Keep the config and settings in iCloud Drive to have them on a new Mac
> right after signing in, before anything is installed:
> `./bootstrap.sh --config "$HOME/Library/Mobile Documents/com~apple~CloudDocs/macos-base-config/config.sh"`.
> The settings directory follows the config file.

---

## 🔤 Fonts

The `brew` step installs JetBrains Mono (package `font-jetbrains-mono`, in
`@base`). The `editor` step sets the keys from
[`editor-settings/vscode.jsonc`](editor-settings/vscode.jsonc) (font family,
size, weight) in the `User/settings.json` of every VS Code-family editor it
finds: VS Code, VS Code Insiders, VSCodium, Cursor, Windsurf, Antigravity,
Antigravity IDE.

```sh
./bootstrap.sh editor --dry-run   # diff per settings.json
./bootstrap.sh editor
```

- Only those keys change; comments and every other setting stay as they are.
- A changed file is backed up first (`settings.json.bak-<timestamp>`); a file
  that already has the values is not touched.
- To change the font, edit `editor-settings/vscode.jsonc` and run the step
  again. The editors pick up the new settings without a restart.

---

## 🤝 Contributing

Issues and pull requests are welcome. Run the [tests](#-tests) before opening a
PR; for larger changes, open an issue first.

---

## 📄 License

MIT — see [LICENSE](LICENSE). © 2026 Jeffry Würmli.

---

<div align="center">
<sub>Windows habits, Mac hardware: one <code>./bootstrap.sh</code> away.</sub>
</div>
