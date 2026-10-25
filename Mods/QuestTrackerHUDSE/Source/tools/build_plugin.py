#!/usr/bin/env python3
"""Build the minimal quest, MCM and setting globals for Quest Tracker HUD SE."""
from __future__ import annotations

import struct
import sys
from pathlib import Path


def subrecord(signature: bytes, data: bytes) -> bytes:
    return signature + struct.pack("<H", len(data)) + data


def zstring(value: str) -> bytes:
    return value.encode("utf-8") + b"\0"


def length_string(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack("<H", len(encoded)) + encoded


def record(signature: bytes, form_id: int, payload: bytes) -> bytes:
    return signature + struct.pack("<IIIIHH", len(payload), 0, form_id, 0, 44, 0) + payload


def vmad() -> bytes:
    scripts = struct.pack("<HHH", 5, 2, 2)
    for name in ("QuestTrackerController", "QuestTrackerMCM"):
        scripts += length_string(name) + struct.pack("<BH", 0, 0)
    quest_fragments = struct.pack("<bH", 2, 0) + length_string("") + struct.pack("<H", 0)
    return scripts + quest_fragments


def global_record(editor_id: str, form_id: int, value: float) -> bytes:
    payload = (
        subrecord(b"EDID", zstring(editor_id))
        + subrecord(b"FNAM", b"f")
        + subrecord(b"FLTV", struct.pack("<f", value))
    )
    return record(b"GLOB", form_id, payload)


def group(signature: bytes, payload: bytes) -> bytes:
    return (
        b"GRUP"
        + struct.pack("<I", 24 + len(payload))
        + signature
        + struct.pack("<iHHHH", 0, 0, 0, 0, 0)
        + payload
    )


def build() -> bytes:
    settings = (
        ("QTH_Enabled", 1.0),
        ("QTH_HorizontalPosition", 850.0),
        ("QTH_VerticalPosition", 220.0),
        ("QTH_PanelWidth", 360.0),
        ("QTH_PanelOpacity", 88.0),
        ("QTH_MaximumQuests", 6.0),
    )

    header_payload = (
        subrecord(b"HEDR", struct.pack("<fII", 1.7, 7, 0x807))
        + subrecord(b"CNAM", zstring("Quest Tracker HUD SE"))
        + subrecord(b"MAST", zstring("Skyrim.esm"))
        + subrecord(b"DATA", bytes(8))
    )
    header = record(b"TES4", 0, header_payload)

    quest_data = bytes((0x01, 0x00, 80, 0)) + struct.pack("<II", 0, 0)
    quest_payload = (
        subrecord(b"EDID", zstring("QuestTrackerHUDStartQuest"))
        + subrecord(b"FULL", zstring("Quest Tracker HUD SE"))
        + subrecord(b"DNAM", quest_data)
        + subrecord(b"VMAD", vmad())
    )
    quest = record(b"QUST", 0x01000800, quest_payload)
    globals_payload = b"".join(
        global_record(editor_id, 0x01000801 + index, value)
        for index, (editor_id, value) in enumerate(settings)
    )

    return header + group(b"GLOB", globals_payload) + group(b"QUST", quest)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: build_plugin.py <output.esp>")
    Path(sys.argv[1]).write_bytes(build())
