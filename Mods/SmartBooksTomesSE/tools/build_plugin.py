#!/usr/bin/env python3
"""Build the Smart Books & Tomes MCM quest and runtime form list."""

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


def length_string(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack("<H", len(encoded)) + encoded


def record(signature: bytes, form_id: int, payload: bytes) -> bytes:
    return signature + struct.pack("<IIIIHH", len(payload), 0, form_id, 0, 0, 0) + payload


def build_vmad() -> bytes:
    scripts = struct.pack("<HHH", 5, 2, 1)
    scripts += length_string("SmartBooksTomesMCM") + struct.pack("<BH", 0, 0)
    fragments = struct.pack("<bH", 2, 0) + length_string("")
    alias = struct.pack("<HhIHHH", 0, 0, 0x01000800, 5, 2, 1)
    alias += length_string("SmartBooksTomesPlayerAlias") + struct.pack("<BH", 0, 0)
    return scripts + fragments + struct.pack("<H", 1) + alias


def build_plugin() -> bytes:
    hedr = struct.pack("<fII", 1.7, 2, 0x802)
    header_payload = (
        subrecord(b"HEDR", hedr)
        + subrecord(b"CNAM", zstring("Smart Books & Tomes SE"))
        + subrecord(b"MAST", zstring("Skyrim.esm"))
        + subrecord(b"DATA", bytes(8))
    )
    header = record(b"TES4", 0, header_payload)

    quest_data = bytes((0x01, 0x00, 80, 0)) + struct.pack("<II", 0, 0)
    quest_payload = (
        subrecord(b"EDID", zstring("SmartBooksTomesMCMQuest"))
        + subrecord(b"VMAD", build_vmad())
        + subrecord(b"FULL", zstring("Smart Books & Tomes SE"))
        + subrecord(b"DNAM", quest_data)
        + subrecord(b"NEXT", b"")
        + subrecord(b"ANAM", struct.pack("<I", 1))
        + subrecord(b"ALST", struct.pack("<I", 0))
        + subrecord(b"ALID", zstring("Player"))
        + subrecord(b"FNAM", struct.pack("<I", 0))
        + subrecord(b"ALFR", struct.pack("<I", 0x14))
        + subrecord(b"ALED", b"")
    )
    quest_record = record(b"QUST", 0x01000800, quest_payload)
    quest_group = (
        b"GRUP"
        + struct.pack("<I", 24 + len(quest_record))
        + b"QUST"
        + struct.pack("<iHHHH", 0, 0, 0, 0, 0)
    )

    list_record = record(b"FLST", 0x01000801, subrecord(b"EDID", zstring("SBT_BookInventory")))
    list_group = (
        b"GRUP"
        + struct.pack("<I", 24 + len(list_record))
        + b"FLST"
        + struct.pack("<iHHHH", 0, 0, 0, 0, 0)
    )
    return header + quest_group + quest_record + list_group + list_record


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(build_plugin())


if __name__ == "__main__":
    main()
