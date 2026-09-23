#!/usr/bin/env python3
"""
Set one option of the JetBrains terminal settings (options/terminal.xml).

    set-terminal-option.py FILE NAME VALUE [--dry-run]

Used by apply.sh to turn "Use Option as Meta key" off, so AltGr characters
reach the IDE terminal:  set-terminal-option.py <cfg>/options/terminal.xml
useOptionAsMetaKey false

Other options in FILE stay as they are; a missing FILE is created. FILE is
backed up (FILE.bak-<timestamp>) before it is changed, and not touched when
the option already has VALUE. Quit the IDE first - it rewrites FILE on exit.
"""

from __future__ import annotations

import argparse
import datetime
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

COMPONENT = "TerminalOptionsProvider"


def load(path: Path) -> ET.Element:
    if not path.is_file():
        return ET.Element("application")
    return ET.parse(path).getroot()


def find_or_add(parent: ET.Element, tag: str, name: str) -> ET.Element:
    for child in parent.findall(tag):
        if child.get("name") == name:
            return child
    return ET.SubElement(parent, tag, {"name": name})


def set_option(path: Path, name: str, value: str, dry_run: bool) -> None:
    root = load(path)
    component = find_or_add(root, "component", COMPONENT)
    option = find_or_add(component, "option", name)
    if option.get("value") == value:
        print(f"  {path.name}: {name}={value} already")
        return
    if dry_run:
        print(f"  {path.name}: would set {name}={value}")
        return
    option.set("value", value)
    if path.is_file():
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        shutil.copy2(path, path.with_name(f"{path.name}.bak-{stamp}"))
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(root, space="  ")
    # JetBrains writes these files without an XML declaration, " />" style
    path.write_text(ET.tostring(root, encoding="unicode", short_empty_elements=True)
                    .replace('"/>', '" />') + "\n")
    print(f"  {path.name}: {name}={value}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", type=Path)
    parser.add_argument("name")
    parser.add_argument("value")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try:
        set_option(args.file, args.name, args.value, args.dry_run)
    except (OSError, ET.ParseError) as error:
        print(f"set-terminal-option: {args.file}: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
