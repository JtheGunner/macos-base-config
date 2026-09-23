#!/usr/bin/env python3
"""
Set the keys from vscode.jsonc (next to this script) in the User/settings.json
of every VS Code-family editor installed on this Mac.

    python3 apply.py            # apply
    python3 apply.py --dry-run  # show a diff per file, change nothing

settings.json is JSONC. Only the values of the managed top-level keys are
replaced, and missing keys are added before the closing brace. Comments,
formatting and all other keys stay as they are. A changed file is backed up
first (settings.json.bak-<timestamp>); a file that already has the values is
not touched. A file that can't be read as JSONC is reported and left alone.
The editors reload settings.json on their own.
"""

from __future__ import annotations

import argparse
import datetime
import difflib
import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "vscode.jsonc"
# config folder under ~/Library/Application Support -> label
# (same editors as intelli-key-port's install.py, macOS only)
EDITORS = {
    "Code": "VS Code",
    "Code - Insiders": "VS Code Insiders",
    "VSCodium": "VSCodium",
    "Cursor": "Cursor",
    "Windsurf": "Windsurf",
    "Antigravity": "Antigravity",
    "Antigravity IDE": "Antigravity IDE",
}
DEFAULT_INDENT = "    "


class JsoncError(ValueError):
    pass


# --- a minimal JSONC scanner: finds the root object's members by position ---

def _skip_blank(text: str, i: int) -> int:
    """Index of the next character that is neither whitespace nor comment."""
    while i < len(text):
        if text[i].isspace():
            i += 1
        elif text.startswith("//", i):
            end = text.find("\n", i)
            i = len(text) if end == -1 else end + 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end == -1:
                raise JsoncError("unterminated /* comment")
            i = end + 2
        else:
            break
    return i


def _skip_string(text: str, i: int) -> int:
    """Index just past the string that starts at i."""
    i += 1
    while i < len(text):
        if text[i] == "\\":
            i += 2
        elif text[i] == '"':
            return i + 1
        else:
            i += 1
    raise JsoncError("unterminated string")


def _skip_value(text: str, i: int) -> int:
    """Index just past the value that starts at i."""
    if i >= len(text):
        raise JsoncError("value missing at end of file")
    if text[i] == '"':
        return _skip_string(text, i)
    if text[i] in "{[":
        depth = 0
        while i < len(text):
            i = _skip_blank(text, i)
            if i >= len(text):
                break
            char = text[i]
            if char == '"':
                i = _skip_string(text, i)
                continue
            if char in "{[":
                depth += 1
            elif char in "}]":
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1
        raise JsoncError("unclosed object or array")
    start = i
    while i < len(text) and text[i] not in ",}]/" and not text[i].isspace():
        i += 1
    if i == start:
        raise JsoncError(f"value missing at offset {start}")
    return i


def parse_members(text: str) -> tuple[list[tuple[str, int, int, int]], int]:
    """([(key, key_start, value_start, value_end), ...], index of the root's
    closing brace) for the top-level members of the JSONC object in text."""
    i = _skip_blank(text, 0)
    if i >= len(text) or text[i] != "{":
        raise JsoncError("not a JSON object")
    i += 1
    members = []
    while True:
        i = _skip_blank(text, i)
        if i >= len(text):
            raise JsoncError("unclosed object")
        if text[i] == "}":
            break
        if text[i] != '"':
            raise JsoncError(f"expected a key at offset {i}")
        key_start = i
        i = _skip_string(text, i)
        key = json.loads(text[key_start:i])
        i = _skip_blank(text, i)
        if i >= len(text) or text[i] != ":":
            raise JsoncError(f"expected ':' after {key!r}")
        value_start = _skip_blank(text, i + 1)
        value_end = _skip_value(text, value_start)
        members.append((key, key_start, value_start, value_end))
        i = _skip_blank(text, value_end)
        if i < len(text) and text[i] == ",":
            i += 1
        elif i >= len(text) or text[i] != "}":
            raise JsoncError(f"expected ',' or '}}' after {key!r}")
    if _skip_blank(text, i + 1) != len(text):
        raise JsoncError("content after the closing brace")
    return members, i


# --- applying the managed keys -----------------------------------------------

def load_source(path: Path) -> dict:
    text = path.read_text()
    members, _ = parse_members(text)
    return {key: json.loads(text[start:end]) for key, _, start, end in members}


def _indent_of(text: str, index: int) -> str:
    line_start = text.rfind("\n", 0, index) + 1
    prefix = text[line_start:index]
    return prefix if prefix.isspace() else DEFAULT_INDENT


def with_settings(text: str, wanted: dict) -> str:
    """text with every key of wanted set to its value (JSONC-preserving)."""
    members, close = parse_members(text)
    present = {key: (start, end) for key, _, start, end in members}
    edits = []  # (start, end, replacement)
    for key, value in wanted.items():
        if key in present:
            start, end = present[key]
            edits.append((start, end, json.dumps(value, ensure_ascii=False)))
    missing = [key for key in wanted if key not in present]
    if missing:
        indent = _indent_of(text, members[0][1]) if members else DEFAULT_INDENT
        lines = [f"{json.dumps(key)}: {json.dumps(wanted[key], ensure_ascii=False)}"
                 for key in missing]
        if not members:
            insert_at = text.rfind("{", 0, close) + 1
            block = "".join(f"\n{indent}{line}" + ("," if n < len(lines) - 1 else "")
                            for n, line in enumerate(lines)) + "\n"
            edits.append((insert_at, close, block))
        else:
            last_end = members[-1][3]
            after = _skip_blank(text, last_end)
            if text[after] == ",":  # keep the file's trailing-comma style
                block = "".join(f"\n{indent}{line}," for line in lines)
                edits.append((after + 1, after + 1, block))
            else:
                block = "".join(f",\n{indent}{line}" for line in lines)
                edits.append((last_end, last_end, block))
    for start, end, replacement in sorted(edits, reverse=True):
        text = text[:start] + replacement + text[end:]
    return text


def new_settings(wanted: dict) -> str:
    lines = [f"{DEFAULT_INDENT}{json.dumps(key)}: {json.dumps(value, ensure_ascii=False)}"
             for key, value in wanted.items()]
    return "{\n" + ",\n".join(lines) + "\n}\n"


def apply_to(label: str, path: Path, wanted: dict, dry_run: bool) -> bool:
    """Bring path in line with wanted; False when it couldn't be read."""
    exists = path.is_file()
    try:
        before = path.read_text() if exists else ""
        after = with_settings(before, wanted) if exists else new_settings(wanted)
    except (OSError, JsoncError, UnicodeDecodeError) as error:
        print(f"  {label}: {path}: {error} - left unchanged", file=sys.stderr)
        return False
    if after == before:
        print(f"  {label}: already set")
        return True
    if dry_run:
        print(f"  {label}: would {'update' if exists else 'create'} {path}")
        sys.stdout.writelines(difflib.unified_diff(
            before.splitlines(keepends=True), after.splitlines(keepends=True),
            fromfile=str(path), tofile=str(path)))
        return True
    if exists:
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = path.with_name(f"{path.name}.bak-{stamp}")
        shutil.copy2(path, backup)
        path.write_text(after)
        print(f"  {label}: updated (backup {backup.name})")
    else:
        path.write_text(after)
        print(f"  {label}: created {path}")
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    wanted = load_source(SOURCE)
    support = Path.home() / "Library" / "Application Support"
    found = [(label, support / folder / "User") for folder, label in EDITORS.items()
             if (support / folder / "User").is_dir()]
    if not found:
        print("  no VS Code-family editor found")
        return 0
    ok = all([apply_to(label, user_dir / "settings.json", wanted, args.dry_run)
              for label, user_dir in found])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
