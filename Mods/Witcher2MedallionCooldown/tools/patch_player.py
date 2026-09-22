#!/usr/bin/env python3
"""Change only the Witcher 2 medallion cooldown in player.ws."""

from __future__ import annotations

import re
import sys
from pathlib import Path


TIMER = re.compile(
    r"(?P<prefix>AddTimer\s*\(\s*['\"]OnEnableMedallion['\"]\s*,\s*)"
    r"(?P<literal>[0-9]+(?:\.[0-9]*)?f?)",
    re.IGNORECASE,
)


def decode(data: bytes) -> tuple[str, str, bytes]:
    if data.startswith(b"\xff\xfe"):
        return data[2:].decode("utf-16-le"), "utf-16-le", b"\xff\xfe"
    if data.startswith(b"\xfe\xff"):
        return data[2:].decode("utf-16-be"), "utf-16-be", b"\xfe\xff"
    try:
        return data.decode("utf-8"), "utf-8", b""
    except UnicodeDecodeError:
        return data.decode("cp1252"), "cp1252", b""


def encode(text: str, encoding: str, bom: bytes) -> bytes:
    return bom + text.encode(encoding)


def patch(path: Path) -> None:
    text, encoding, bom = decode(path.read_bytes())
    matches = list(TIMER.finditer(text))
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one OnEnableMedallion timer in {path}, found {len(matches)}"
        )
    match = matches[0]
    literal = match.group("literal")
    if literal.lower() in {"1", "1.", "1.f", "1.0f"}:
        print(f"Already patched: {path}")
        return
    replacement = "1.f" if ("." in literal or literal.lower().endswith("f")) else "1"
    patched = text[: match.start("literal")] + replacement + text[match.end("literal") :]
    path.write_bytes(encode(patched, encoding, bom))
    print(f"Changed OnEnableMedallion: {literal} -> {replacement} seconds")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: patch_player.py PATH/TO/player.ws")
    patch(Path(sys.argv[1]))
