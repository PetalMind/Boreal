#!/usr/bin/env python3
"""Extract one resource from a Dragon Age: Origins ERF V2 archive."""

from __future__ import annotations

import struct
import sys
from pathlib import Path


ENTRY_SIZE = 72
ENTRY_NAME_SIZE = 64
ENTRY_TABLE_OFFSET = 0x20


def extract(archive: Path, resource_name: str, destination: Path) -> None:
    data = archive.read_bytes()
    if data[:16] != "ERF V2.0".encode("utf-16le"):
        raise SystemExit(f"Unsupported ERF signature in {archive}")

    entry_count = struct.unpack_from("<I", data, 0x10)[0]
    for index in range(entry_count):
        entry = ENTRY_TABLE_OFFSET + index * ENTRY_SIZE
        name = data[entry : entry + ENTRY_NAME_SIZE].decode("utf-16le").split("\x00", 1)[0]
        if name.casefold() != resource_name.casefold():
            continue
        offset = struct.unpack_from("<I", data, entry + ENTRY_NAME_SIZE)[0]
        size = struct.unpack_from("<I", data, entry + ENTRY_NAME_SIZE + 4)[0]
        end = offset + size
        if offset < 0 or end > len(data):
            raise SystemExit(f"Invalid ERF range for {name}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data[offset:end])
        return

    raise SystemExit(f"{resource_name} was not found in {archive}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("Usage: erf_extract.py ARCHIVE RESOURCE DESTINATION")
    extract(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]))
