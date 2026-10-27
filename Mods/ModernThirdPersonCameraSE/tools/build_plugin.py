#!/usr/bin/env python3
"""Build the MCM quest and live camera settings globals."""
from __future__ import annotations

import struct
import sys
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
    return signature + struct.pack("<IIIIHH", len(payload), 0, form_id, 0, 44, 0) + payload


def group(signature: bytes, payload: bytes) -> bytes:
    return b"GRUP" + struct.pack("<I", 24 + len(payload)) + signature + struct.pack("<iHHHH", 0, 0, 0, 0, 0) + payload


SETTINGS = (
    ("MTC_Enabled", 1.0),
    ("MTC_NormalShoulderX", 18.0),
    ("MTC_NormalShoulderZ", 2.0),
    ("MTC_CombatShoulderX", 24.0),
    ("MTC_CombatAddY", 8.0),
    ("MTC_CombatShoulderZ", 2.0),
    ("MTC_BowShoulderX", 14.0),
    ("MTC_BowAddY", 10.0),
    ("MTC_BowShoulderZ", 1.0),
    ("MTC_NormalFOV", 74.0),
    ("MTC_CombatFOV", 78.0),
    ("MTC_BowFOV", 68.0),
    ("MTC_FOVResponse", 3.5),
    ("MTC_ZoomSensitivity", 1.0),
    ("MTC_AutoRecenter", 1.0),
    ("MTC_RecenterDelay", 1.1),
    ("MTC_RecenterResponse", 2.4),
    ("MTC_MCMOverrides", 0.0),
)


def global_record(editor_id: str, form_id: int, value: float) -> bytes:
    payload = (
        subrecord(b"EDID", zstring(editor_id))
        + subrecord(b"FNAM", b"f")
        + subrecord(b"FLTV", struct.pack("<f", value))
    )
    return record(b"GLOB", form_id, payload)


def build() -> bytes:
    quest_id = 0x01000800
    last_form_id = 0x800 + len(SETTINGS)
    header_payload = (
        subrecord(b"HEDR", struct.pack("<fII", 1.7, len(SETTINGS) + 1, last_form_id + 1))
        + subrecord(b"CNAM", zstring("Modern Third Person Camera SE"))
        + subrecord(b"MAST", zstring("Skyrim.esm"))
        + subrecord(b"DATA", bytes(8))
    )
    header = record(b"TES4", 0, header_payload)

    vmad = struct.pack("<HHH", 5, 2, 1)
    vmad += length_string("ModernThirdPersonCameraMCM") + struct.pack("<BH", 0, 0)
    vmad += struct.pack("<bH", 2, 0) + length_string("") + struct.pack("<H", 1)
    alias = struct.pack("<HhIHHH", 0, 0, quest_id, 5, 2, 1)
    alias += length_string("ModernThirdPersonCameraPlayerAlias") + struct.pack("<BH", 0, 0)
    vmad += alias

    quest_data = bytes((0x01, 0x00, 80, 0)) + struct.pack("<II", 0, 0)
    quest_payload = (
        subrecord(b"EDID", zstring("ModernThirdPersonCameraMCMQuest"))
        + subrecord(b"FULL", zstring("Modern Third Person Camera SE"))
        + subrecord(b"DNAM", quest_data)
        + subrecord(b"VMAD", vmad)
        + subrecord(b"NEXT", b"")
        + subrecord(b"ANAM", struct.pack("<I", 1))
        + subrecord(b"ALST", struct.pack("<I", 0))
        + subrecord(b"ALID", zstring("Player"))
        + subrecord(b"FNAM", struct.pack("<I", 0))
        + subrecord(b"ALFR", struct.pack("<I", 0x14))
        + subrecord(b"ALED", b"")
    )
    quest = record(b"QUST", quest_id, quest_payload)
    globals_payload = b"".join(
        global_record(editor_id, 0x01000801 + index, value)
        for index, (editor_id, value) in enumerate(SETTINGS)
    )
    return header + group(b"GLOB", globals_payload) + group(b"QUST", quest)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: build_plugin.py <output.esp>")
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(build())
