#!/usr/bin/env python3
"""Build the quest and settings globals for Nordic Minimal UI SE."""
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
    for name in ("NordicMinimalUIQuest", "NordicMinimalUIMCM"):
        scripts += length_string(name) + struct.pack("<BH", 0, 0)
    fragments = struct.pack("<bH", 2, 0) + length_string("")
    alias = struct.pack("<HhIHHH", 0, 0, 0x01000805, 5, 2, 1)
    alias += length_string("NordicMinimalUIPlayerAlias") + struct.pack("<BH", 0, 0)
    return scripts + fragments + struct.pack("<H", 1) + alias


def global_record(editor_id: str, form_id: int, value: float) -> bytes:
    payload = subrecord(b"EDID", zstring(editor_id)) + subrecord(b"FNAM", b"f") + subrecord(b"FLTV", struct.pack("<f", value))
    return record(b"GLOB", form_id, payload)


def group(signature: bytes, payload: bytes) -> bytes:
    return b"GRUP" + struct.pack("<I", 24 + len(payload)) + signature + struct.pack("<iHHHH", 0, 0, 0, 0, 0) + payload


def build() -> bytes:
    settings = (("NMUI_FadeSeconds", 5.0), ("NMUI_BarsEnabled", 1.0), ("NMUI_CompassEnabled", 1.0), ("NMUI_RouteKeyCode", 35.0))
    # SkyUI is a script dependency, not a record master. All local records use
    # index 01; adding SkyUI here made them override SkyUI's own namespace.
    header_payload = subrecord(b"HEDR", struct.pack("<fII", 1.7, 6, 0x806)) + subrecord(b"CNAM", zstring("Nordic Minimal UI SE")) + subrecord(b"MAST", zstring("Skyrim.esm")) + subrecord(b"DATA", bytes(8))
    header = record(b"TES4", 0, header_payload)
    quest_data = bytes((0x01, 0x00, 80, 0)) + struct.pack("<II", 0, 0)
    quest_payload = (
        subrecord(b"EDID", zstring("NordicMinimalUIRuntimeQuest"))
        + subrecord(b"VMAD", vmad())
        + subrecord(b"FULL", zstring("Nordic Minimal UI SE"))
        + subrecord(b"DNAM", quest_data)
        + subrecord(b"NEXT", b"")
        + subrecord(b"ANAM", struct.pack("<I", 1))
        + subrecord(b"ALST", struct.pack("<I", 0))
        + subrecord(b"ALID", zstring("Player"))
        + subrecord(b"FNAM", struct.pack("<I", 0))
        + subrecord(b"ALFR", struct.pack("<I", 0x14))
        + subrecord(b"ALED", b"")
    )
    # Keep the old form as an inert tombstone. A fresh private quest initializes
    # aliases/scripts even in saves made with the earlier invalid record headers.
    legacy = record(b"QUST", 0x01000800,
                    subrecord(b"EDID", zstring("NordicMinimalUIStartQuest"))
                    + subrecord(b"DNAM", bytes(12)))
    quest = record(b"QUST", 0x01000805, quest_payload)
    globs = b"".join(global_record(editor, 0x01000800 + index, value) for index, (editor, value) in enumerate(settings, 1))
    return header + group(b"QUST", legacy + quest) + group(b"GLOB", globs)


Path(sys.argv[1]).write_bytes(build())
