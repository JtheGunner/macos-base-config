# nas-mount applet from a template (MBC-12) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `nas-mount.app` from a template in the repo plus the shares in
`NAS_MOUNT_SHARES`, as the optional catalog package `nas-mount` (source
`applet`), installed by the `extras` step.

**Architecture:**
- **Template and catalog.** `packages/nas-mount.applescript` loops over
  `{@@NAS_MOUNT_SHARES@@}` with one `try` per share. The catalog row points to
  it: `nas-mount | applet | packages/nas-mount.applescript | nas-mount | remote | …`.
- **Config.** `lib/config.sh` validates `NAS_MOUNT_SHARES` (whitespace-separated
  `smb://` / `afp://` / `nfs://` URLs).
- **Rendering.** `applet_source` (lib/packages.sh) renders the template.
- **Build.** `install_applet` (lib/steps.sh) compiles it with `osacompile` into
  a temp dir. It compares the `osadecompile` output with the installed app and
  replaces the app only when they differ; the old app goes to `~/.Trash`.
- **extras step.** `step_extras` handles the `applet` source.

**Tech Stack:** bash 3.2, awk, `osacompile` / `osadecompile`, tests in
`tests/bootstrap-test.sh`.

**Spec:** `docs/superpowers/specs/2026-09-23-package-catalog-design.md`
(section *nas-mount*; ticket 4 of its Rollout, MBC-12).

## Global Constraints

- **`NAS_MOUNT_SHARES`:**
  - Optional, default `""`.
  - Tokens are separated by any whitespace; newlines are allowed.
  - Each token must match `^(smb|afp|nfs)://[^"\\*?[]+$`, so that it can go
    safely into an AppleScript string. Anything else is a config error
    (exit 2) that names the token.
  - No credentials: Finder uses the Keychain.
- **Rendered list:** `"smb://a", "afp://b"`, which replaces `@@NAS_MOUNT_SHARES@@`.
- **Selected but no shares:**
  - The package line is `nas-mount: skipped - set NAS_MOUNT_SHARES in the config`.
  - The step skip reason includes `set NAS_MOUNT_SHARES in the config for: nas-mount`.
  - Nothing is built.
- **Build outcomes:** `installed` (no app yet), `unchanged` (same decompiled
  script), or `updated (old one in the Trash)`. The old app moves to
  `$HOME/.Trash/nas-mount-<yyyymmdd-HHMMSS>.app`.
- **A failing build** (template missing, `osacompile` error) fails the package
  and leaves the installed app untouched.
- **Dry run:** prints `+ osacompile -o <target> (<template> with NAS_MOUNT_SHARES)`
  and builds nothing.
- **Out of scope:** login items and credentials.

## Review Focus

- **A share with spaces in its path** (`smb://nas/My Files`). Whitespace
  separates tokens, so it would split into two shares. Expected: documented
  as "percent-encode spaces (`%20`)". Owned by Task 3 (README / config
  example); the Task 1 validation rejects nothing extra, but the split is
  visible in `--dry-run`.
- **Changing the shares on a Mac where the old hand-made app exists.** It is
  replaced exactly once, the old one lands in the Trash, and later runs say
  `unchanged`. Owned by Task 2, test "an unchanged nas-mount is left alone;
  a changed one replaced, the old one in the Trash".
- **An `osacompile` failure** must not delete the working app. Owned by
  Task 2, test "a failing build fails nas-mount and keeps the installed app".
- **`TMPDIR` ending in `/`** (the macOS default) gives no `//` paths and no
  leftover temp dirs. Owned by Task 2 (the same `tmp_root%/` pattern as
  `step_brew`; the e2e test asserts `$SB/tmp` is empty afterwards).
- **nas-mount selected together with npm packages without Node, and no
  shares.** Both skip hints end up in the summary reason. Owned by Task 2,
  test "nas-mount without shares is skipped with a hint".

---

### Task 1: `NAS_MOUNT_SHARES`, the template, the catalog row, `applet_source`

**Files:**
- Create: `packages/nas-mount.applescript`
- Modify: `packages/catalog.txt` (a new `remote` group after `@base`)
- Modify: `lib/packages.sh` (`applet_source`)
- Modify: `lib/config.sh`: the default, the validation and the doc comment
- Modify: `config.example.sh`: a new `# --- extras step` section before
  `# --- apps step`
- Modify: `tests/bootstrap-test.sh`: the config section, the packages
  section and the `config.example.sh` test

**Interfaces:**
- Produces:
  - `NAS_MOUNT_SHARES`, validated.
  - `applet_source TEMPLATE`: prints the template with `@@NAS_MOUNT_SHARES@@`
    replaced by the AppleScript list items; returns 1 when the template
    can't be read.
  - Catalog id `nas-mount`.

- [ ] **Step 1: Write the failing tests**

Config section, after the SETTINGS_DIR tests:

```bash
it "NAS_MOUNT_SHARES: empty by default; smb, afp, nfs URLs over several lines load"
XDG_CONFIG_HOME="$TMP/none" load_config ""
assert_eq "$NAS_MOUNT_SHARES" ""
f="$(write_config 'NAS_MOUNT_SHARES="smb://10.0.12.20/privat
  afp://nas.local/data	nfs://nas.local/export/media"')"
load_config "$f"; rc=$?
assert_eq "$rc" 0

it "a NAS share that isn't a plain smb, afp or nfs URL is exit 2"
for bad in 'http://nas/data' 'smb://' 'smb://nas/a"b' 'smb://nas/*'; do
  f="$(write_config "NAS_MOUNT_SHARES='smb://nas/ok $bad'")"
  out="$(load_config "$f" 2>&1)"; rc=$?
  assert_eq "$rc" 2
  assert_contains "$out" "NAS_MOUNT_SHARES: not an smb://, afp:// or nfs:// URL: $bad"
done
```

In `it "config.example.sh is a valid config with the defaults"`, add
`assert_eq "$NAS_MOUNT_SHARES" ""` and add `NAS_MOUNT_SHARES` to the
`for key in …` list.

Packages section, after `it "manual hints: selected and missing only"`:

```bash
it "the shipped catalog has nas-mount, its template renders one try per share"
assert_eq "$(select_packages nas-mount)" "nas-mount"
out="$(NAS_MOUNT_SHARES="smb://nas/a
  afp://nas/b" applet_source "$REPO/packages/nas-mount.applescript")"
assert_contains "$out" '{"smb://nas/a", "afp://nas/b"}'
assert_contains "$out" "try"
assert_contains "$out" "mount volume"
assert_not_contains "$out" "@@"
out="$(applet_source "$TMP/no-template" 2>&1)"; rc=$?
assert_eq "$rc" 1
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: NAS_MOUNT_SHARES: empty by default …` (unbound variable).

- [ ] **Step 3: Implement**

`packages/nas-mount.applescript`:

```applescript
-- nas-mount: mount the NAS shares. Built by macos-base-config
-- (./bootstrap.sh extras) from packages/nas-mount.applescript and
-- NAS_MOUNT_SHARES - edit those, not this app. Finder takes the credentials
-- from the Keychain. Each share has its own try: one that is offline doesn't
-- stop the others.
tell application "Finder"
	repeat with share in {@@NAS_MOUNT_SHARES@@}
		try
			mount volume (share as text)
		end try
	end repeat
end tell
```

`packages/catalog.txt`: append after the `@base` block (one blank line
before it):

```text
nas-mount           | applet | packages/nas-mount.applescript | nas-mount | remote | Mount the NAS shares in NAS_MOUNT_SHARES (credentials from the Keychain)
```

`lib/packages.sh`: append:

```bash
# applet_source TEMPLATE -> TEMPLATE with @@NAS_MOUNT_SHARES@@ replaced by the
# shares as AppleScript list items ("smb://a", "afp://b"). The config check
# keeps quotes and backslashes out of them. 1 when TEMPLATE can't be read.
applet_source() {
  local template list
  template="$(cat "$1" 2>/dev/null)" || return 1
  list="$(printf '%s\n' "$NAS_MOUNT_SHARES" |
    awk '{ for (i = 1; i <= NF; i++) printf "%s\"%s\"", (n++ ? ", " : ""), $i }')"
  printf '%s\n' "${template//@@NAS_MOUNT_SHARES@@/$list}"
}
```

`lib/config.sh`:
- Doc comment: add `NAS_MOUNT_SHARES,` after `SETTINGS_DIR (default: the config file's directory),`.
- Defaults: `MACOS_DISABLE_GATEKEEPER=0; SETTINGS_DIR=""` becomes
  `MACOS_DISABLE_GATEKEEPER=0; SETTINGS_DIR=""; NAS_MOUNT_SHARES=""`.
- In `validate_config`, right after the SETTINGS_DIR block, add:

```bash
  # the shares go into an AppleScript string: plain smb / afp / nfs URLs only
  local bad_share
  bad_share="$(printf '%s\n' "$NAS_MOUNT_SHARES" | awk '{
    for (i = 1; i <= NF; i++)
      if ($i !~ /^(smb|afp|nfs):\/\/[^"\\*?[]+$/) { print $i; exit }
  }')"
  if [ -n "$bad_share" ]; then
    echo "bootstrap.sh: $config_file: NAS_MOUNT_SHARES: not an smb://, afp:// or nfs:// URL: $bad_share" >&2
    return 2
  fi
```

`config.example.sh`, before `# --- apps step`:

```bash
# --- extras step ----------------------------------------------------------------

# NAS shares for the nas-mount app (package nas-mount in PACKAGES): smb://,
# afp:// or nfs:// URLs, separated by spaces or newlines; a space inside a
# path is %20. No credentials - Finder takes them from the Keychain. Empty =
# nas-mount is skipped. Example: "smb://nas.local/data smb://nas.local/media"
NAS_MOUNT_SHARES=""
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 5: Commit**

```bash
git add packages lib/packages.sh lib/config.sh config.example.sh tests/bootstrap-test.sh
git commit -m "feat: add the nas-mount template, catalog entry and NAS_MOUNT_SHARES"
```

---

### Task 2: `applet` in the `extras` step

**Files:**
- Modify: `lib/steps.sh`: new `install_applet` before `step_extras`;
  `step_extras` handles `applet`
- Modify: `lib/cli.sh`: `step_description extras` mentions the nas-mount app
- Modify: `tests/bootstrap-test.sh`: new tests at the end of
  `# --- the extras step`

**Interfaces:**
- Consumes: `applet_source` and `NAS_MOUNT_SHARES` (Task 1), plus
  `APPLICATIONS_DIR`, `DRY_RUN` and `HERE`.
- Produces: `install_applet ID REF CHECK` → 0 ok, 1 failed, 2 skipped (no
  shares).

- [ ] **Step 1: Write the failing tests**

Append to the extras section, before `# --- the dotfiles step`:

```bash
# nas_sandbox [CONFIG_LINE...] -> sandbox with nas-mount selected; osacompile
# "builds" an app dir holding the source, osadecompile prints it back
nas_sandbox() {
  make_sandbox
  sandbox_config 'PACKAGES="nas-mount"' "$@"
  printf '#!/bin/bash\necho "osacompile $*" >> "%s"\nmkdir -p "$2" && cp "$3" "$2/source"\n' "$LOG" > "$SB/bin/osacompile"
  printf '#!/bin/bash\ncat "$1/source"\n' > "$SB/bin/osadecompile"
  chmod +x "$SB/bin/osacompile" "$SB/bin/osadecompile"
}
nas_app() { echo "$SB/Applications/nas-mount.app"; }

it "extras builds nas-mount with one try per share"
nas_sandbox 'NAS_MOUNT_SHARES="smb://nas/a smb://nas/b"'
run_bootstrap --no-pull extras
assert_eq "$RC" 0
assert_contains "$(cat "$(nas_app)/source")" '{"smb://nas/a", "smb://nas/b"}'
assert_contains "$OUT" "nas-mount: installed"
assert_contains "$OUT" "  extras     ok"
[ -z "$(ls -A "$SB/tmp")" ] || fail "temp build dir left behind"

it "an unchanged nas-mount is left alone; a changed one replaced, the old one in the Trash"
run_bootstrap --no-pull extras
assert_contains "$OUT" "nas-mount: unchanged"
[ -e "$SB/home/.Trash" ] && fail "trashed an unchanged app"
sandbox_config 'PACKAGES="nas-mount"' 'NAS_MOUNT_SHARES="smb://nas/c"'
run_bootstrap --no-pull extras
assert_contains "$OUT" "nas-mount: updated (old one in the Trash)"
assert_contains "$(cat "$(nas_app)/source")" '{"smb://nas/c"}'
assert_contains "$(cat "$SB/home/.Trash"/nas-mount-*.app/source)" '"smb://nas/a"'

it "a failing build fails nas-mount and keeps the installed app"
nas_sandbox 'NAS_MOUNT_SHARES="smb://nas/new"'
mkdir -p "$(nas_app)"; echo old > "$(nas_app)/source"
printf '#!/bin/bash\necho "compile error" >&2\nexit 1\n' > "$SB/bin/osacompile"
run_bootstrap --no-pull extras
assert_eq "$RC" 1
assert_contains "$OUT" "  extras     failed   (failed: nas-mount)"
assert_contains "$OUT" "compile error"
assert_eq "$(cat "$(nas_app)/source")" old

it "nas-mount without shares is skipped with a hint"
nas_sandbox
run_bootstrap --no-pull extras
assert_eq "$RC" 0
assert_contains "$OUT" "nas-mount: skipped - set NAS_MOUNT_SHARES in the config"
assert_contains "$OUT" "  extras     skipped  (set NAS_MOUNT_SHARES in the config for: nas-mount)"
assert_not_contains "$(cat "$LOG")" "osacompile"
[ -e "$(nas_app)" ] && fail "built without shares"
extras_sandbox "sass"
printf '%s\n' 'nas-mount | applet | packages/nas-mount.applescript | nas-mount | remote | NAS' >> "$SB_CATALOG"
sandbox_config 'PACKAGES="sass nas-mount"'
rm "$SB/bin/npm"
run_bootstrap --no-pull extras
SB_CATALOG=""
assert_contains "$OUT" "  extras     skipped  (install Node first (e.g. nvm install --lts) for: sass; set NAS_MOUNT_SHARES in the config for: nas-mount)"

it "dry run shows the nas-mount build, builds nothing"
nas_sandbox 'NAS_MOUNT_SHARES="smb://nas/a"'
run_bootstrap --dry-run --no-pull extras
assert_eq "$RC" 0
assert_contains "$OUT" "+ osacompile -o $(nas_app) (packages/nas-mount.applescript with NAS_MOUNT_SHARES)"
assert_eq "$(cat "$LOG")" ""
[ -e "$(nas_app)" ] && fail "built in dry run"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `FAIL: extras builds nas-mount with one try per share`. The step
reports `skipped (no extra packages selected)`, because `applet` is still
filtered out.

- [ ] **Step 3: Implement**

`lib/steps.sh`, before the `# step_extras` comment:

```bash
# install_applet ID REF CHECK -> build CHECK.app from the template REF (a
# path in this repo) and NAS_MOUNT_SHARES. The installed app is replaced only
# when its script differs; the old one goes to the Trash. 0 ok, 1 failed,
# 2 skipped (no shares).
install_applet() {
  local id="$1" template="$HERE/$2" target="$APPLICATIONS_DIR/$3.app"
  local tmp_root="${TMPDIR:-/tmp}" build
  if [ -z "$NAS_MOUNT_SHARES" ]; then
    echo "  $id: skipped - set NAS_MOUNT_SHARES in the config"
    return 2
  fi
  if $DRY_RUN; then
    echo "+ osacompile -o $target ($2 with NAS_MOUNT_SHARES)"
    return 0
  fi
  build="$(mktemp -d "${tmp_root%/}/applet.XXXXXX")" || return 1
  if ! applet_source "$template" > "$build/$3.applescript" ||
    ! osacompile -o "$build/$3.app" "$build/$3.applescript" 2> "$build/errors"; then
    echo "  $id: build failed" >&2
    cat "$build/errors" >&2
    rm -rf "$build"
    return 1
  fi
  if [ -d "$target" ] && [ "$(osadecompile "$target" 2>/dev/null)" = "$(osadecompile "$build/$3.app")" ]; then
    echo "  $id: unchanged"
  elif [ -d "$target" ]; then
    mkdir -p "$HOME/.Trash" &&
      mv "$target" "$HOME/.Trash/$3-$(date +%Y%m%d-%H%M%S).app" &&
      mv "$build/$3.app" "$target" || { rm -rf "$build"; return 1; }
    echo "  $id: updated (old one in the Trash)"
  else
    mv "$build/$3.app" "$target" || { rm -rf "$build"; return 1; }
    echo "  $id: installed"
  fi
  rm -rf "$build"
}
```

`step_extras`:
- Doc comment first line: `# step_extras -> install the selected script / npm / pipx / uv / go packages`
  gets a second sentence, `The nas-mount applet is (re)built from its template.`
- `local … need_node=""` becomes `local … need_node="" need_shares="" rc`.
- The source filter becomes
  `case "$source" in script | npm | pipx | uv | go | applet) ;; *) continue ;; esac`.
- Right after `selected=true`, insert:

```bash
    if [ "$source" = applet ]; then
      rc=0
      install_applet "$id" "$ref" "$check" || rc=$?
      case "$rc" in
        0) ;;
        2) need_shares="$need_shares $id" ;;
        *) failed="$failed $id" ;;
      esac
      continue
    fi
```

- Replace the final
  `[ -z "$need_node" ] || skip "install Node first (e.g. nvm install --lts) for:$need_node"`
  with:

```bash
  local reason=""
  [ -z "$need_node" ] || reason="install Node first (e.g. nvm install --lts) for:$need_node"
  [ -z "$need_shares" ] || reason="${reason:+$reason; }set NAS_MOUNT_SHARES in the config for:$need_shares"
  [ -z "$reason" ] || skip "$reason"
```

`lib/cli.sh`:
`extras)    echo "install the selected packages that don't come from Homebrew (script, npm, pipx, uv, go) and build the nas-mount app" ;;`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 5: Commit**

```bash
git add lib/steps.sh lib/cli.sh tests/bootstrap-test.sh
git commit -m "feat: build the nas-mount applet in the extras step"
```

---

### Task 3: README

**Files:**
- Modify: `README.md`:
  - the diagram `extras` line;
  - the Configuration table (a `NAS_MOUNT_SHARES` row after `SETTINGS_DIR`);
  - the sources table in `## 📦 Apps and tools` (an `applet` row);
  - a new `### NAS shares (nas-mount)` subsection before `### App settings`.

- [ ] **Step 1: Edit README.md**

Diagram line:

```text
   ├─ extras      selected packages from outside Homebrew: install scripts, npm, pipx, uv, go; the nas-mount app
```

Configuration row:

```markdown
| `NAS_MOUNT_SHARES`          | —                   | smb:// / afp:// / nfs:// shares the `nas-mount` app mounts, see [NAS shares](#nas-shares-nas-mount)             |
```

Sources table row, after `go`:

```markdown
| `applet`  | built from a template in this repo (`nas-mount`) | `extras` |
```

Subsection:

````markdown
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
````

- [ ] **Step 2: Verify**

Run: `/bin/bash tests/bootstrap-test.sh`
Expected: `all N cases passed`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document the nas-mount package and NAS_MOUNT_SHARES"
```

---

### Task 4: Final verification

- [ ] Run `/bin/bash tests/bootstrap-test.sh`. Expected: all cases pass.
- [ ] **Real build without touching /Applications.** Use a scratch config with
  `PACKAGES="nas-mount"` and this Mac's three shares, and run
  `APPLICATIONS_DIR=<scratch>/Applications ./bootstrap.sh --config <scratch>/config.sh --no-pull extras`.
  Expected: `nas-mount: installed`. `osadecompile <scratch>/Applications/nas-mount.app`
  shows the loop over the three shares.
- [ ] Run `./bootstrap.sh --list-packages`. Expected:
  `@remote` with `nas-mount` `installed` (the existing app).
