#!/usr/bin/env python3
"""Build the minimal Start Game Enabled quest plugin for Smart Loot SE."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


def subrecord(signature: bytes, data: bytes) -> bytes:
    if len(signature) != 4 or len(data) > 0xFFFF:
        raise ValueError("invalid subrecord")
    return signature + struct.pack("<H", len(data)) + data


def zstring(value: str) -> bytes:
    return value.encode("utf-8") + b"\0"


def pascal_string(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack("<H", len(encoded)) + encoded


def record(signature: bytes, form_id: int, payload: bytes) -> bytes:
    return signature + struct.pack("<IIIIHH", len(payload), 0, form_id, 0, 0, 0) + payload


def build_vmad() -> bytes:
    scripts = struct.pack("<HHH", 5, 2, 1)
    scripts += pascal_string("SmartLootQuest") + struct.pack("<BH", 0, 0)
    # QUST VMAD always includes the quest-fragment section and alias-script count.
    fragments = struct.pack("<HH", 2, 0) + zstring("") + struct.pack("<H", 0)
    return scripts + fragments


def build_plugin() -> bytes:
    hedr = struct.pack("<fII", 1.7, 1, 0x801)
    header_payload = (
        subrecord(b"HEDR", hedr)
        + subrecord(b"CNAM", zstring("Smart Loot SE"))
        + subrecord(b"MAST", zstring("Skyrim.esm"))
        + subrecord(b"DATA", bytes(8))
    )
    header = record(b"TES4", 0, header_payload)

    quest_data = bytes((0x01, 0x00, 80, 0)) + struct.pack("<II", 0, 0)
    quest_payload = (
        subrecord(b"EDID", zstring("SmartLootStartQuest"))
        + subrecord(b"FULL", zstring("Smart Loot"))
        + subrecord(b"DNAM", quest_data)
        + subrecord(b"VMAD", build_vmad())
    )
    quest_record = record(b"QUST", 0x01000800, quest_payload)
    group_header = (
        b"GRUP"
        + struct.pack("<I", 24 + len(quest_record))
        + b"QUST"
        + struct.pack("<iHHHH", 0, 0, 0, 0, 0)
    )
    return header + group_header + quest_record


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(build_plugin())


if __name__ == "__main__":
    main()
