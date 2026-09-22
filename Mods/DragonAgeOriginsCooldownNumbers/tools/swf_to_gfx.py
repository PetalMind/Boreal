#!/usr/bin/env python3
"""Change a compressed SWF signature back to the Scaleform CFX signature."""

from __future__ import annotations

import sys
from pathlib import Path


def convert(source: Path, destination: Path) -> None:
    data = source.read_bytes()
    if data[:3] == b"CWS":
        signature = b"CFX"
    elif data[:3] == b"FWS":
        signature = b"GFX"
    else:
        raise SystemExit(f"{source} is not a supported SWF file")
    destination.write_bytes(signature + data[3:])


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: swf_to_gfx.py INPUT OUTPUT")
    convert(Path(sys.argv[1]), Path(sys.argv[2]))
