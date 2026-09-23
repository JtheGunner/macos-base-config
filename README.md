<div style="text-align: center;">

# 🍎 macOS base config

**Windows / PC muscle memory on a Mac, with a Swiss‑German ISO keyboard.**
One bootstrap for the keyboard layout, the Karabiner remaps, the IDE keymaps,
the few macOS tweaks that go with them, and the shell dotfiles.

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
   ├─ karabiner   Karabiner config → ~/.config/karabiner   (skipped until Karabiner is installed)
   ├─ macos       macos-defaults.py: system hotkeys, Finder shortcut, font smoothing
   ├─ jetbrains   JetBrains keymap → IDE config, set active (skipped until PhpStorm has a config)
   ├─ vscode      same keymap → VS Code / Antigravity         (same condition)
   ├─ dotfiles    the dotfiles repo's own bootstrap.sh: shell, prompt, git, tmux, Ghostty
   ├─ manual      print the manual steps
   └─ summary     ok / skipped / failed per step
```

> [!IMPORTANT]
> On a fresh Mac the `karabiner` step is skipped until Karabiner-Elements is
> installed. Run `../karabiner-windows-keyboard-mapping-macos/setup.sh` (it
> installs Karabiner via Homebrew and walks you through its permissions), then
> `./bootstrap.sh karabiner`. The `dotfiles` step needs Homebrew as well.

---

## 🎛️ Steps and options

Name steps to run only those; they always run in the order below. With no
step named, every step runs.

|    | Step        | Runs                                                |
|:--:|-------------|-----------------------------------------------------|
| 📥 | `repos`     | clone missing / pull existing sibling repos         |
| ⌨️  | `karabiner` | `karabiner-windows-keyboard-mapping-macos/apply.sh` |
| 🛠️ | `macos`     | `macos-defaults.py`                                 |
| 🧠 | `jetbrains` | `ide-keymaps/apply.sh`                              |
| 💻 | `vscode`    | `ide-keymaps/port-vscode.sh`                        |
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
| `-h`, `--help`    | usage                                                                      |

---

## ⚙️ Configuration

Per-machine settings live in `~/.config/macos-base-config/config.sh`, a plain
bash file that is **not** part of the repo. Start from the template:

```sh
mkdir -p ~/.config/macos-base-config
cp config.example.sh ~/.config/macos-base-config/config.sh
```

| Key                         | Default             | Effect                                                                                                                 |
|-----------------------------|---------------------|------------------------------------------------------------------------------------------------------------------------|
| `BOOTSTRAP_STEPS`           | all steps           | steps to run when none are named on the command line                                                                   |
| `BOOTSTRAP_SKIP`            | —                   | steps never to run on this machine                                                                                     |
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
| 🇨🇭 | **AltGr characters** (`@ # \| \ ~ [] {} €`): custom keyboard *layout*       | [`swiss-windows-keyboard-layout-macos`](https://github.com/JtheGunner/swiss-windows-keyboard-layout-macos)           | manual: see [Manual steps](#-manual-steps)                          |
| ⌨️  | **Windows key behaviour** (`Ctrl+C/V/Z`, word jump, `Alt+F4`, …): Karabiner | [`karabiner-windows-keyboard-mapping-macos`](https://github.com/JtheGunner/karabiner-windows-keyboard-mapping-macos) | `./setup.sh` (fresh Mac) or `./apply.sh`: bootstrap runs `apply.sh` |
| 🛠️ | **macOS-level shortcuts Karabiner can't do**                                | `macos-defaults.py` (this repo)                                                                                      | `python3 macos-defaults.py`: bootstrap runs it                      |
| 🧠 | **JetBrains keymap** `jeffry-default-macos-win Proper Redo`                 | `ide-keymaps/` (this repo): [README](ide-keymaps/README.md)                                                          | `ide-keymaps/apply.sh` (quit the IDE first): bootstrap runs it      |
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
The PhpStorm terminal needs one more setting, listed under
[Manual steps](#-manual-steps).

---

## 🛠️ macOS-level shortcuts Karabiner can't do

Karabiner is an event remapper with no awareness of app menus or text-field
focus, so a few things must be done at the macOS `defaults` level.
`macos-defaults.py` does them idempotently and writes a `restore-<timestamp>.sh`
per run:

- **Mission Control `Ctrl+←/→` "Move a space"** (symbolic hotkeys 79‑82) is
  disabled. Otherwise, macOS takes `Ctrl+Arrow` before any app sees it, and word
  navigation never works in editors.
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

The `manual` step prints a reminder of these. None of them can be
scripted reliably.

|    | Step                               | How                                                                                                                                                                                       |
|:--:|------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 🇨🇭 | **Keyboard layout**                | in `swiss-windows-keyboard-layout-macos`: `sudo cp CustomSwissGerman.* "/Library/Keyboard Layouts/"`, add *Custom Swiss German* under System Settings → Keyboard → Input Sources, restart |
| 🔐 | **Karabiner permissions**          | Driver Extension, Input Monitoring, Accessibility. `karabiner-windows-keyboard-mapping-macos/setup.sh` opens the panes and lists the steps                                                |
| 🖥️ | **PhpStorm terminal**              | Settings → Tools → Terminal → **"Use Option as Meta key" off**. Otherwise AltGr characters turn into escape sequences in the IDE console                                                  |
| 🔇 | **Disable VoiceOver**              | System Settings → Accessibility → VoiceOver → off, so `Ctrl+F5` isn't taken by VoiceOver                                                                                                  |
| 🛡️ | **Gatekeeper: apps from anywhere** | `sudo spctl --master-disable`, then System Settings → Privacy & Security → "Allow applications from: Anywhere"                                                                            |
| 📦 | **Apps**                           | AltTab and uBar, see [Apps](#-apps-homebrew)                                                                                                                                              |

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

## 📦 Apps (Homebrew)

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install --cask alt-tab      # Windows-style Alt+Tab window switching
# uBar (Windows-style taskbar): https://ubarapp.com/
```

---

## 🔤 Fonts

VS Code / editor font. Paste into *Preferences: Open User Settings (JSON)*:

```json
{
  "editor.fontFamily": "'JetBrains Mono', 'Menlo', 'Monaco', 'Courier New', monospace",
  "editor.fontSize": 12,
  "editor.fontWeight": "100"
}
```

---

## 🤝 Contributing

Issues and pull requests are welcome. Run the [tests](#-tests) before opening a
PR; for larger changes, open an issue first.

---

## 📄 License

MIT — see [LICENSE](LICENSE). © 2026 Jeffry Würmli.

---

<div style="text-align: center;">
<sub>Windows habits, Mac hardware: one <code>./bootstrap.sh</code> away.</sub>
</div>
