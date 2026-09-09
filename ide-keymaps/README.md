# ide-keymaps

`jeffry-default-macos-win` — a JetBrains keymap built for **Windows / PC muscle
memory** (parent: *Default for XWin*; `Ctrl+←/→` word jump, `Ctrl+§` comment,
Windows‑style clipboard, …). It is the human‑authored source that
[`phpstorm-keymap-port`](https://github.com/JtheGunner/phpstorm-keymap-port)
converts into a VS Code / Antigravity `keybindings.json`.

## Why a tracked copy

The keymap is synced by PhpStorm's **Backup and Sync** (JetBrains cloud), but
that has no public API — you can only get it back *through* the IDE, on a
machine tied to the JetBrains account. This checked‑in `.xml` is the offline,
git‑diffable fallback: ~1 KB, regenerated on demand.

| file | |
|---|---|
| `jeffry-default-macos-win.xml` | the keymap (action overrides on top of *Default for XWin*) |
| `DATE` | when + which IDE config dir it was last pulled from |
| `sync.sh` | live `…/JetBrains/<IDE>/keymaps/` → this repo. Run after editing the keymap in PhpStorm. |
| `apply.sh` | this repo → the IDE config + set it active (`options/mac/keymap.xml`). Quit the IDE first. |

`apply.sh` and `sync.sh` walk every `PhpStorm*` / `IntelliJIdea*` config dir
they find and use the newest.
