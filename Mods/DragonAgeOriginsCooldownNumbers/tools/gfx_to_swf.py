#!/usr/bin/env python3
"""Change a Scaleform CFX/GFX signature to the equivalent SWF signature."""

from __future__ import annotations

import sys
from pathlib import Path


def convert(source: Path, destination: Path) -> None:
    data = source.read_bytes()
    if data[:3] == b"CFX":
        signature = b"CWS"
    elif data[:3] == b"GFX":
        signature = b"FWS"
    else:
        raise SystemExit(f"{source} is not a Scaleform GFX/CFX file")
    destination.write_bytes(signature + data[3:])


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: gfx_to_swf.py INPUT OUTPUT")
    convert(Path(sys.argv[1]), Path(sys.argv[2]))
