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


def record(signature: bytes, form_id: int, payload: bytes) -> bytes:
    return signature + struct.pack("<IIIIHH", len(payload), 0, form_id, 0, 0, 0) + payload


def vmad() -> bytes:
    scripts = struct.pack("<HHH", 5, 2, 2)
    for name in ("NordicMinimalUIQuest", "NordicMinimalUIMCM"):
        scripts += zstring(name) + struct.pack("<BH", 0, 0)
    return scripts + struct.pack("<HH", 2, 0) + zstring("") + struct.pack("<H", 0)


def global_record(editor_id: str, form_id: int, value: float) -> bytes:
    payload = subrecord(b"EDID", zstring(editor_id)) + subrecord(b"FNAM", b"f") + subrecord(b"FLTV", struct.pack("<f", value))
    return record(b"GLOB", form_id, payload)


def group(signature: bytes, payload: bytes) -> bytes:
    return b"GRUP" + struct.pack("<I", 24 + len(payload)) + signature + struct.pack("<iHHHH", 0, 0, 0, 0, 0) + payload


def build() -> bytes:
    settings = (("NMUI_FadeSeconds", 5.0), ("NMUI_BarsEnabled", 1.0), ("NMUI_CompassEnabled", 1.0), ("NMUI_RouteKeyCode", 35.0))
    header_payload = subrecord(b"HEDR", struct.pack("<fII", 1.7, 5, 0x805)) + subrecord(b"CNAM", zstring("Nordic Minimal UI SE")) + subrecord(b"MAST", zstring("Skyrim.esm")) + subrecord(b"DATA", bytes(8)) + subrecord(b"MAST", zstring("SkyUI_SE.esp")) + subrecord(b"DATA", bytes(8))
    header = record(b"TES4", 0, header_payload)
    quest_data = bytes((0x01, 0x00, 80, 0)) + struct.pack("<II", 0, 0)
    quest = record(b"QUST", 0x01000800, subrecord(b"EDID", zstring("NordicMinimalUIStartQuest")) + subrecord(b"FULL", zstring("Nordic Minimal UI SE")) + subrecord(b"DNAM", quest_data) + subrecord(b"VMAD", vmad()))
    globs = b"".join(global_record(editor, 0x01000800 + index, value) for index, (editor, value) in enumerate(settings, 1))
    return header + group(b"QUST", quest) + group(b"GLOB", globs)


Path(sys.argv[1]).write_bytes(build())
