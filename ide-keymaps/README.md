# ide-keymaps

`jeffry-default-macos-win Proper Redo`, a JetBrains keymap built for **Windows / PC
muscle memory** (parent: *Default for XWin*). It covers `Ctrl+←/→` word jump,
`Ctrl+§` comment, Windows‑style clipboard and `Ctrl+Y` redo, among others.
Tool windows sit on `Ctrl+Shift+Alt+Cmd+<digit>` instead of `Alt+<digit>`, so
AltGr+1/2/3/7 still type `| @ # |`. The Karabiner rule `winkeys-45` maps the left
`Alt+<digit>` there. The keymap is the human‑authored source that
[`intelli-key-port`](https://github.com/JtheGunner/intelli-key-port)
converts into a VS Code / Antigravity `keybindings.json` (via `port-vscode.sh`).

## Why a tracked copy

The keymap is synced by PhpStorm's **Backup and Sync** (JetBrains cloud), but
that has no public API — you can only get it back *through* the IDE, on a
machine tied to the JetBrains account. This checked‑in `.xml` is the offline,
git‑diffable fallback: ~1 KB, regenerated on demand.

| file                                       |                                                                                                                        |
|--------------------------------------------|------------------------------------------------------------------------------------------------------------------------|
| `jeffry-default-macos-win-proper-redo.xml` | the keymap (action overrides on top of *Default for XWin*); installed as `jeffry-default-macos-win Proper Redo.xml`     |
| `DATE`                                     | when + which IDE config dir it was last pulled from                                                                    |
| `sync.sh`                                  | live `…/JetBrains/<IDE>/keymaps/` → this repo. Run after editing the keymap in PhpStorm.                               |
| `apply.sh`                                 | this repo → the IDE config + set it active (`options/mac/keymap.xml`); terminal *Use Option as Meta key* off. Quit the IDE first. |
| `set-terminal-option.py`                   | sets one option in `options/terminal.xml` (used by `apply.sh`), keeps the others, backs the file up                    |
| `port-vscode.sh`                           | runs `intelli-key-port` with this machine's layers: `windows-keymap`, `karabiner-winkeys`, then the personal one below. |
| `intelli-key-port-personal.jsonc`          | personal layer: `Ctrl+Y` redo, `Ctrl+S` save, numpad zoom, `Shift+Enter` terminal newline, `Ctrl+Shift+C` copies in Claude Code (terminal), … |

`apply.sh` and `sync.sh` walk every `PhpStorm*` / `IntelliJIdea*` config dir
they find and use the newest.
