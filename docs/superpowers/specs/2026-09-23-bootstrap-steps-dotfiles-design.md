# Bootstrap steps + dotfiles integration — design

Issue: MBC-1 · Branch: `feat/MBC-1-add-dotfiles-step-and-step-selection`

## Goal

- `./bootstrap.sh` with no step arguments runs every step, including the
  `dotfiles` sibling repo's own bootstrap.
- Every step has a stable name and can be run alone, combined, or skipped.
- One per-machine shell config file controls the bootstrap and the dotfiles
  step without touching either repo.
- Best-effort stays: a failing step never aborts the others; a summary at the
  end shows what happened, and the exit code reflects failures.

Out of scope: changes to the `dotfiles` repo itself (e.g. a `--dry-run` there),
installing Homebrew, reworking the keymap scripts.

## Layout

```text
bootstrap.sh           entry point: load config, select steps, run, summary
lib/cli.sh             argument parsing, step table, alias + selection logic
lib/config.sh          config file discovery, syntax check, load, validate
lib/steps.sh           one function per step + sibling checkout helper
config.example.sh      documented config keys (copied by the user, not loaded)
repos.txt              sibling repos: <dir-name> <git-url> (apply column removed)
tests/bootstrap-test.sh  dependency-free test runner
```

`bootstrap.sh` sources the three `lib/` files. `lib/cli.sh` has no side effects
on source, so tests can call its functions directly.

## Steps

Fixed execution order:

| Step        | Does                                                           | Skipped when                         |
|-------------|----------------------------------------------------------------|--------------------------------------|
| `repos`     | clone missing / pull existing siblings from `repos.txt`       | —                                    |
| `karabiner` | `karabiner-windows-keyboard-mapping-macos/apply.sh`           | Karabiner-Elements not installed     |
| `macos`     | `python3 macos-defaults.py`                                    | —                                    |
| `jetbrains` | `ide-keymaps/apply.sh`                                         | no PhpStorm / IntelliJ config dir    |
| `vscode`    | `ide-keymaps/port-vscode.sh`                                   | no PhpStorm / IntelliJ config dir    |
| `dotfiles`  | `<DOTFILES_DIR>/bootstrap.sh`                                  | —                                    |
| `manual`    | print the manual, non-scriptable steps                        | —                                    |

Alias: `keymaps` = `jetbrains vscode`.

"Karabiner not installed" = `/Applications/Karabiner-Elements.app` is absent;
the skip reason points at `setup.sh`. The `jetbrains` / `vscode` detection is
the existing `find … PhpStorm* IntelliJIdea*` check.

Steps that need a sibling (`karabiner`, `vscode` → `intelli-key-port`,
`dotfiles`) call the shared checkout helper themselves, so they work without
`repos` being selected. `repos` itself does not handle `dotfiles` specially: the
`dotfiles` entry in `repos.txt` is overridden by `DOTFILES_DIR` / `DOTFILES_URL`
when set.

## CLI

```text
./bootstrap.sh [options] [step|alias ...]

  --skip <step>     exclude a step or alias; repeatable
  --dry-run         show what would happen; no git ops, sub-tools get --dry-run
  --no-pull         don't pull existing siblings; still clone missing ones
  --config <path>   use this config file instead of the default
  --list            print the steps in order with a description, exit 0
  -h, --help        usage, exit 0
```

Rules:

- No positional steps → `BOOTSTRAP_STEPS` from config → all steps.
- Positional steps replace `BOOTSTRAP_STEPS`; `--skip` values are added to
  `BOOTSTRAP_SKIP`.
- Aliases expand before selection; the result is deduplicated and always run in
  table order, regardless of argument order.
- Unknown step, alias, or option, or `--skip`/`--config` without a value →
  message on stderr + usage hint, exit 2, nothing runs.
- A selection that ends up empty prints "nothing to do" and exits 0.

## Config

Default path: `${XDG_CONFIG_HOME:-$HOME/.config}/macos-base-config/config.sh`.
`--config <path>` overrides it.

```sh
BOOTSTRAP_STEPS=""              # default steps when none are given; empty = all
BOOTSTRAP_SKIP=""               # always skip these

DOTFILES_DIR=""                 # empty = <parent>/dotfiles
DOTFILES_URL=""                 # empty = the dotfiles URL in repos.txt
DOTFILES_ASSUME_YES=0           # 1 = pass --yes (repoint stow links without asking)
DOTFILES_TERMINALS=""           # exported to dotfiles/bootstrap.sh
DOTFILES_OMNISHELL_CONFIG=""    # path to an own omnishell config.toml
```

Loading:

1. Default path missing → defaults, no message. `--config` path missing → exit 2.
2. `bash -n <file>` fails → exit 2 with the file name.
3. `source` the file.
4. Validate: every name in `BOOTSTRAP_STEPS` / `BOOTSTRAP_SKIP` is a known step
   or alias; `DOTFILES_ASSUME_YES` is `0` or `1`; `DOTFILES_OMNISHELL_CONFIG`,
   when set, is a readable file. Any violation → exit 2.

`~` in path values is expanded. The config is the user's own file, so sourcing
it (arbitrary shell) is acceptable; it is never committed.

## Sibling checkout helper

`ensure_sibling <name> <url> <dir>`:

- `<dir>/.git` exists → `git -C <dir> pull --ff-only`, unless `--no-pull`.
  A failed pull prints a warning and returns success (the existing checkout is
  used).
- otherwise → `git clone <url> <dir>`. A failed clone returns failure.
- `--dry-run` → print the command, don't run it; treat as success.

## dotfiles step

1. `ensure_sibling dotfiles "$DOTFILES_URL" "$DOTFILES_DIR"`; failure → step
   failed.
2. `command -v brew` missing → step failed ("Homebrew required").
3. Run in a subshell:
   `DOTFILES_TERMINALS="$DOTFILES_TERMINALS" bash "$DOTFILES_DIR/bootstrap.sh" [--yes]`.
   `--yes` only when `DOTFILES_ASSUME_YES=1`; otherwise its repoint prompt stays
   interactive. Non-zero exit → step failed (`exit <n>`).
4. If `DOTFILES_OMNISHELL_CONFIG` is set: copy it to
   `${XDG_CONFIG_HOME:-$HOME/.config}/omnishell/config.toml`, then
   `omnishell apply -y`. This must run after 3, because the dotfiles bootstrap
   overwrites that file with its own copy every run. Failure → step failed.
5. `--dry-run`: steps 3 and 4 print the command lines (with the env passed)
   instead of running; nothing is installed.

## Error handling + summary

- `set -uo pipefail`, no `-e`. Bash 3.2 compatible (empty-array expansion via
  `${arr[@]+"${arr[@]}"}`).
- Each step function returns 0 = ok, 1 = failed, or sets a skip reason and
  returns 0 via a `skip "<reason>"` helper.
- The runner records one result per selected step and prints:

  ```text
  == summary
    repos      ok
    jetbrains  skipped  (no JetBrains config yet)
    dotfiles   failed   (exit 1)
  ```

- Exit code: 1 if any step failed, else 0. Parse/config errors exit 2 before
  any step runs.

## Tests — `tests/bootstrap-test.sh`

Plain bash, runs under `/bin/bash` 3.2, tiny `assert_eq` / `assert_contains`
helpers, prints each case, exits non-zero on the first failure.

- `lib/cli.sh` unit cases: no args → all steps; `dotfiles keymaps` →
  `jetbrains vscode dotfiles`; `--skip keymaps`; dedup; unknown step/option and
  missing option value → exit 2.
- Config cases: syntax error, unknown step in `BOOTSTRAP_STEPS`, missing
  `--config` file, bad `DOTFILES_ASSUME_YES` → exit 2; CLI steps override
  `BOOTSTRAP_STEPS`.
- End-to-end in a sandbox (temp dir: `bootstrap.sh` + `lib/` + `repos.txt`
  copied to `parent/macos-base-config`, stub `ide-keymaps/*.sh`, stub siblings
  with an empty `.git/` and stub scripts that log their argv, fake `HOME`, stub
  `git` / `brew` / `omnishell` / `python3` first on `PATH`):
  - `--dry-run` → every logged sub-tool call carries `--dry-run`; `git`, the
    dotfiles bootstrap and `omnishell` are never called; output contains the
    dotfiles command.
  - missing sibling + `--dry-run` → clone is announced.
  - real run `--no-pull --skip macos` with the dotfiles stub exiting 1 → other
    selected steps ran, summary shows `dotfiles  failed`, exit 1.
  - `DOTFILES_ASSUME_YES=1` → stub received `--yes`.
  - `DOTFILES_OMNISHELL_CONFIG` → file copied into the fake `HOME`, `omnishell
    apply -y` logged.
  - `--list` / `--help` exit 0 and name every step.

Nothing in the tests touches the real machine: `python3` (→ `macos-defaults.py`),
the keymap scripts, `git`, `brew` and `omnishell` are all stubs. The Karabiner
install check reads `KARABINER_APP` (default
`/Applications/Karabiner-Elements.app`) so the sandbox can point it elsewhere.

## README

- Quick start: step examples (`./bootstrap.sh keymaps`, `--skip dotfiles`,
  `--list`) and the options table.
- Flow diagram: the seven steps.
- New "⚙️ Configuration" section: path, keys, precedence, `config.example.sh`,
  `DOTFILES_DIR` for an existing checkout elsewhere.
- Sibling tree gains `dotfiles/`; the "What lives where" row for dotfiles says
  the `dotfiles` step runs it (drop "not part of this one").
- "🧪 Tests" line: `bash tests/bootstrap-test.sh`.
