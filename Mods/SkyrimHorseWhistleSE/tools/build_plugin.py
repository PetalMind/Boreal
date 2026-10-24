#!/usr/bin/env python3
"""Build the quest, settings global, private anchor cell and map marker ESP."""

from __future__ import annotations

import struct
import sys
from pathlib import Path


QUEST_ID = 0x01000800
KEY_ID = 0x01000801
CELL_ID = 0x01000802
MARKER_ID = 0x01000803


def subrecord(signature: bytes, data: bytes) -> bytes:
    if len(signature) != 4 or len(data) > 0xFFFF:
        raise ValueError("Invalid subrecord")
    return signature + struct.pack("<H", len(data)) + data


def zstring(value: str) -> bytes:
    return value.encode("utf-8") + b"\0"


def length_string(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack("<H", len(encoded)) + encoded


def record(signature: bytes, form_id: int, payload: bytes, flags: int = 0) -> bytes:
    return signature + struct.pack("<IIIIHH", len(payload), flags, form_id, 0, 44, 0) + payload


def group(label: bytes, group_type: int, contents: bytes) -> bytes:
    if len(label) != 4:
        raise ValueError("GRUP labels must be four bytes")
    header = b"GRUP" + struct.pack("<I", len(contents) + 24) + label
    return header + struct.pack("<iHHHH", group_type, 0, 0, 0, 0) + contents


def build_vmad() -> bytes:
    scripts = struct.pack("<HHH", 5, 2, 2)
    for name in ("HorseWhistleQuest", "HorseWhistleMCM"):
        scripts += length_string(name) + struct.pack("<BH", 0, 0)
    # QUST VMAD stores a signed extra-bind-data version, fragment count,
    # length-prefixed filename, then alias count.
    quest_fragments = struct.pack("<bH", 2, 0) + length_string("") + struct.pack("<H", 0)
    return scripts + quest_fragments


def build_global() -> bytes:
    payload = (
        subrecord(b"EDID", zstring("HorseWhistle_KeyCode"))
        + subrecord(b"FNAM", b"i")
        + subrecord(b"FLTV", struct.pack("<f", 34.0))
    )
    return record(b"GLOB", KEY_ID, payload)


def build_quest() -> bytes:
    # Start-game-enabled, priority 80, and zero run delay.
    dnam = bytes((0x01, 0x00, 80, 0)) + struct.pack("<II", 0, 0)
    payload = (
        subrecord(b"EDID", zstring("HorseWhistle_StartQuest"))
        + subrecord(b"FULL", zstring("Horse Whistle SE"))
        + subrecord(b"DNAM", dnam)
        + subrecord(b"VMAD", build_vmad())
    )
    return record(b"QUST", QUEST_ID, payload)


def build_marker() -> bytes:
    # MapMarker base object from Skyrim.esm; persistent flag + XMRK make this
    # reference discoverable through ObjectReference.AddToMap().
    data = struct.pack("<6f", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    payload = (
        subrecord(b"EDID", zstring("HorseWhistle_PlayerHorseMapMarker"))
        + subrecord(b"NAME", struct.pack("<I", 0x00000010))
        + subrecord(b"XMRK", b"")
        + subrecord(b"FNAM", b"\x00")
        + subrecord(b"FULL", zstring("Koń gracza"))
        # Reuse Skyrim's built-in Stable marker icon (the horseshoe).
        + subrecord(b"TNAM", struct.pack("<H", 21))
        + subrecord(b"DATA", data)
    )
    return record(b"REFR", MARKER_ID, payload, flags=0x00000400)


def build_cell_group() -> bytes:
    default_interior_lighting = bytes.fromhex(
        "1e1e28000000000000000000000000000000000000000000"
        "0000000000000000000000000000803f211e29001a1e2600"
        "1e1f28001e1c28000e0e12002d2d3d00000000000000803f"
        "000000000000803f00000000000000009f000000"
    )
    cell = record(
        b"CELL",
        CELL_ID,
        subrecord(b"EDID", zstring("HorseWhistle_MarkerAnchorCell"))
        + subrecord(b"FULL", zstring("Horse Whistle Marker Anchor"))
        + subrecord(b"DATA", struct.pack("<H", 0x0001))
        + subrecord(b"XCLL", default_interior_lighting),
    )
    marker_group = group(struct.pack("<I", CELL_ID), 8, build_marker())
    sub_block = group(struct.pack("<I", 0), 3, cell + marker_group)
    block = group(struct.pack("<I", 0), 2, sub_block)
    return group(b"CELL", 0, block)


def build_plugin() -> bytes:
    hedr = struct.pack("<fII", 1.7, 4, MARKER_ID)
    header_payload = (
        subrecord(b"HEDR", hedr)
        + subrecord(b"CNAM", zstring("Horse Whistle SE"))
        + subrecord(b"MAST", zstring("Skyrim.esm"))
        + subrecord(b"DATA", bytes(8))
    )
    header = record(b"TES4", 0, header_payload)
    return (
        header
        + group(b"GLOB", 0, build_global())
        + group(b"QUST", 0, build_quest())
        + build_cell_group()
    )


def main() -> None:
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(build_plugin())


if __name__ == "__main__":
    main()
