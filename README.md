<div align="center">

# 🍎 macOS base config

**Windows / PC muscle memory on a Mac, with a Swiss‑German ISO keyboard.**
One bootstrap for the keyboard layout, the Karabiner remaps, the IDE keymaps and
the few macOS tweaks that go with them.

<code>🇨🇭 layout</code> &nbsp;→&nbsp; <code>⌨️ Karabiner</code> &nbsp;→&nbsp; <code>🧠 JetBrains keymap</code> &nbsp;→&nbsp; <code>💻 VS Code family</code>

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
./bootstrap.sh
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
> └── intelli-key-port/
> ```
>
> A sibling that is already there is updated with `git pull --ff-only`
> instead of cloned again.

`bootstrap.sh` is best-effort and re-runnable: a missing piece prints a note,
it never aborts the rest.

```text
 ./bootstrap.sh
   │
   ├─ 1. repos.txt      clone / pull each sibling repo into the parent folder
   │                    karabiner-windows-keyboard-mapping-macos  → ./apply.sh
   │                    swiss-windows-keyboard-layout-macos       → manual (see below)
   │                    intelli-key-port                          → clone only
   ├─ 2. macos-defaults.py            system hotkeys, Finder shortcut, font smoothing
   ├─ 3. ide-keymaps/apply.sh         JetBrains keymap → IDE config, set active
   │     ide-keymaps/port-vscode.sh   same keymap → VS Code / Antigravity
   │                                  (only if a PhpStorm / IntelliJ config exists)
   └─ 4. print the manual steps
```

> [!IMPORTANT]
> `bootstrap.sh` runs Karabiner's `apply.sh`, which expects Karabiner-Elements
> to be installed. On a fresh Mac, run `./bootstrap.sh` once so the sibling
> repos get cloned, then `../karabiner-windows-keyboard-mapping-macos/setup.sh`.
> It installs Karabiner via Homebrew and walks you through its permissions.
> Then run `./bootstrap.sh` again.

---

## 🧩 What lives where

|    | Piece                                                                      | Repo / file                                                                                                           | Apply                                                                  |
|:--:|----------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| 🇨🇭 | **AltGr characters** (`@ # \| \ ~ [] {} €`): custom keyboard *layout*       | [`swiss-windows-keyboard-layout-macos`](https://github.com/JtheGunner/swiss-windows-keyboard-layout-macos)           | manual: see [Manual steps](#-manual-steps)                            |
| ⌨️ | **Windows key behaviour** (`Ctrl+C/V/Z`, word jump, `Alt+F4`, …): Karabiner | [`karabiner-windows-keyboard-mapping-macos`](https://github.com/JtheGunner/karabiner-windows-keyboard-mapping-macos) | `./setup.sh` (fresh Mac) or `./apply.sh`: bootstrap runs `apply.sh`    |
| 🛠️ | **macOS-level shortcuts Karabiner can't do**                               | `macos-defaults.py` (this repo)                                                                                       | `python3 macos-defaults.py`: bootstrap runs it                         |
| 🧠 | **JetBrains keymap** `jeffry-default-macos-win Proper Redo`                | `ide-keymaps/` (this repo): [README](ide-keymaps/README.md)                                                          | `ide-keymaps/apply.sh` (quit the IDE first): bootstrap runs it         |
| 💻 | **VS Code / Antigravity keybindings**, generated from the JetBrains keymap | [`intelli-key-port`](https://github.com/JtheGunner/intelli-key-port) + layers from `ide-keymaps/`                    | `ide-keymaps/port-vscode.sh`: bootstrap runs it                        |
| 🐚 | **Shell, prompt, git, tmux, Ghostty**                                      | [`dotfiles`](https://github.com/JtheGunner/dotfiles)                                                                  | its own `bootstrap.sh`, not part of this one                          |

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

|    | Piece              | What it does                                                                                                                         |
|:--:|--------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| 🇨🇭 | keyboard layout    | AltGr+1 / 2 / 3 / 7 type `\|` `@` `#` `\|`                                                                                            |
| ⌨️ | Karabiner rule 45  | in IDEs, the physical **Alt** key + digit becomes `Ctrl+Shift+Alt+Cmd` + digit (on the MX Keys in Mac mode, Alt arrives as `left_command`) |
| 🧠 | JetBrains keymap   | tool windows (Project, Find, Structure, …) sit on `Ctrl+Shift+Alt+Cmd+<digit>`, so no `Option+<digit>` shortcut is left               |
| 💻 | `port-vscode.sh`   | carries those bindings over to VS Code / Antigravity                                                                                 |

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
  disabled. Otherwise macOS takes `Ctrl+Arrow` before any app sees it, and word
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

`bootstrap.sh` prints a reminder of these at the end. None of them can be
scripted reliably.

|    | Step                               | How                                                                                                                                              |
|:--:|------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| 🇨🇭 | **Keyboard layout**                | in `swiss-windows-keyboard-layout-macos`: `sudo cp CustomSwissGerman.* "/Library/Keyboard Layouts/"`, add *Custom Swiss German* under System Settings → Keyboard → Input Sources, restart |
| 🔐 | **Karabiner permissions**          | Driver Extension, Input Monitoring, Accessibility. `karabiner-windows-keyboard-mapping-macos/setup.sh` opens the panes and lists the steps        |
| 🖥️ | **PhpStorm terminal**              | Settings → Tools → Terminal → **"Use Option as Meta key" off**. Otherwise AltGr characters turn into escape sequences in the IDE console          |
| 🔇 | **Disable VoiceOver**              | System Settings → Accessibility → VoiceOver → off, so `Ctrl+F5` isn't taken by VoiceOver                                                          |
| 🛡️ | **Gatekeeper: apps from anywhere** | `sudo spctl --master-disable`, then System Settings → Privacy & Security → "Allow applications from: Anywhere"                                   |
| 📦 | **Apps**                           | AltTab and uBar, see [Apps](#-apps-homebrew)                                                                                                      |

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

<div align="center">
<sub>Windows habits, Mac hardware: one <code>./bootstrap.sh</code> away.</sub>
</div>
