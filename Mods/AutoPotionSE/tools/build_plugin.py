#!/usr/bin/env python3
"""Build the minimal Auto Potion SE quest and configuration globals."""

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
    scripts = struct.pack("<HHH", 5, 2, 2)
    for name in ("AutoPotionQuest", "AutoPotionMCM"):
        scripts += length_string(name) + struct.pack("<BH", 0, 0)
    fragments = struct.pack("<bH", 2, 0) + length_string("")
    alias = struct.pack("<HhIHHH", 0, 0, 0x01000800, 5, 2, 1)
    alias += length_string("AutoPotionPlayerAlias") + struct.pack("<BH", 0, 0)
    return scripts + fragments + struct.pack("<H", 1) + alias


def build_global(editor_id: str, form_id: int, value: float) -> bytes:
    payload = (
        subrecord(b"EDID", zstring(editor_id))
        + subrecord(b"FNAM", b"f")
        + subrecord(b"FLTV", struct.pack("<f", value))
    )
    return record(b"GLOB", form_id, payload)


def build_plugin() -> bytes:
    settings = (
        ("AP_AutoHealth", 1.0),
        ("AP_AutoMagicka", 1.0),
        ("AP_AutoStamina", 0.0),
        ("AP_HealthThreshold", 0.30),
        ("AP_MagickaThreshold", 0.20),
        ("AP_StaminaThreshold", 0.20),
        ("AP_CooldownSeconds", 5.0),
        ("AP_OnlyInCombat", 1.0),
        ("AP_WeakestSufficient", 1.0),
    )
    hedr = struct.pack("<fII", 1.7, len(settings) + 1, 0x80A)
    header_payload = (
        subrecord(b"HEDR", hedr)
        + subrecord(b"CNAM", zstring("Auto Potion SE"))
        + subrecord(b"MAST", zstring("Skyrim.esm"))
        + subrecord(b"DATA", bytes(8))
    )
    header = record(b"TES4", 0, header_payload)

    quest_data = bytes((0x01, 0x00, 80, 0)) + struct.pack("<II", 0, 0)
    quest_payload = (
        subrecord(b"EDID", zstring("AutoPotionStartQuest"))
        + subrecord(b"VMAD", build_vmad())
        + subrecord(b"FULL", zstring("Auto Potion SE"))
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

    global_records = b"".join(
        build_global(editor_id, 0x01000800 + index, value)
        for index, (editor_id, value) in enumerate(settings, start=1)
    )
    global_group = (
        b"GRUP"
        + struct.pack("<I", 24 + len(global_records))
        + b"GLOB"
        + struct.pack("<iHHHH", 0, 0, 0, 0, 0)
    )
    return header + quest_group + quest_record + global_group + global_records


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(build_plugin())


if __name__ == "__main__":
    main()
