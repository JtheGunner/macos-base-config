# macOS base config

Set up a fresh Mac for **Windows / PC muscle memory** with a Swiss‑German ISO
keyboard, plus the small system tweaks that go with it.

## Quick start

```sh
git clone git@github.com:JtheGunner/macos-base-config.git ~/Projects/macos-base-config
cd ~/Projects/macos-base-config
./bootstrap.sh            # or --dry-run first
```

`bootstrap.sh` clones/pulls the sibling repos listed in `repos.txt`, runs their
`apply.sh`, then `macos-defaults.py`, then `ide-keymaps/apply.sh`. It never
aborts the whole run on one missing piece. The manual, non‑scriptable steps
(macOS permission prompts, VoiceOver, Gatekeeper) are printed at the end and
listed below.

## What lives where

| layer | repo / file | apply |
|---|---|---|
| **Swiss AltGr characters** (`@ \ ~ [] {} €`) — custom keyboard *layout* | [`swiss-windows-keyboard-layout-macos`](https://github.com/JtheGunner/swiss-windows-keyboard-layout-macos) | copy `.keylayout` → `~/Library/Keyboard Layouts/`, re‑login (see its README) |
| **Windows key *behaviour*** (`Ctrl+C/V/Z`, word jump, `Alt+F4`, …) — Karabiner | [`karabiner-windows-keyboard-mapping-macos`](https://github.com/JtheGunner/karabiner-windows-keyboard-mapping-macos) | `./setup.sh` (fresh) or `./apply.sh` |
| **macOS‑level shortcuts Karabiner can't do** (see below) | `macos-defaults.py` (this repo) | `python3 macos-defaults.py` |
| **JetBrains keymap** `jeffry-default-macos-win` | `ide-keymaps/` (this repo) | `ide-keymaps/apply.sh` — see [its README](ide-keymaps/README.md) |
| **VS Code / Antigravity keybindings** (generated from the JetBrains keymap) | [`phpstorm-keymap-port`](https://github.com/JtheGunner/phpstorm-keymap-port) | `./port.py` |
| **shell / prompt / ghostty** | [`dotfiles`](https://github.com/JtheGunner/dotfiles) | `bootstrap.sh` |

## macOS‑level shortcuts Karabiner can't do

Karabiner is an event remapper with no awareness of app menus or text‑field
focus, so a few things must be done at the macOS `defaults` level. `macos-defaults.py`
does them idempotently, with a `restore-<timestamp>.sh` per run:

- **Mission Control `Ctrl+←/→` "Move a space"** (symbolic hotkeys 79‑82) is
  disabled — otherwise macOS eats `Ctrl+Arrow` before any app and word
  navigation never works in editors.
- **Finder: the forward‑delete key → "Move to Bin"** via an *App Shortcut*
  (`NSUserKeyEquivalents`). Menu‑aware, so it still forward‑deletes a character
  inside a rename / search field (a Karabiner rule could not tell the
  difference and broke text input).
- `AppleFontSmoothing = 1` (thinner bold system font).

```sh
python3 macos-defaults.py --show     # current state
python3 macos-defaults.py --dry-run
python3 macos-defaults.py            # apply  (log out / log in for the hotkeys + font)
```

## Fonts

VS Code / editor font (paste into *Preferences: Open User Settings (JSON)*):

```json
{
  "editor.fontFamily": "'JetBrains Mono', 'Menlo', 'Monaco', 'Courier New', monospace",
  "editor.fontSize": 12,
  "editor.fontWeight": "100"
}
```

## Apps (Homebrew)

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install --cask alt-tab      # Windows-style Alt+Tab window switching
# uBar (Windows-style taskbar): https://ubarapp.com/
```

## General settings (manual)

- **Disable VoiceOver** — System Settings → Accessibility → VoiceOver → off.
  Needed so `Ctrl+F5` isn't swallowed by VoiceOver.
- **Gatekeeper / apps from anywhere** — `sudo spctl --master-disable`, then
  System Settings → Privacy & Security → "Allow applications from: Anywhere".
- **Karabiner permissions** — Driver Extension, Input Monitoring, Accessibility.
  `karabiner-windows-keyboard-mapping-macos/setup.sh` opens the panes and lists
  the steps.
