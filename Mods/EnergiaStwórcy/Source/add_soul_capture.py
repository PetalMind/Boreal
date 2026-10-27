#!/usr/bin/env python3
"""Add scripted soul capture to all three existing Creator Energy ranks."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

from add_spell_ranks import BASE_FORM_ID, RANKS, pack_record, unpack_record
from add_spell_sounds import read_plugin

SOUL_EFFECT_ID = 0x01000806
DAMAGE_EFFECT_ID = 0x01000800
SPELL_IDS = {BASE_FORM_ID, *(rank["form_id"] for rank in RANKS)}
MCM_QUEST_ID = 0x01000807
SOUL_CAPTURE_ENABLED_ID = 0x01000808
FREE_GEM_ENABLED_ID = 0x01000809


def soul_effect(template: bytes) -> bytes:
    """Use the same projectile and delivery as the existing damage effect."""
    fields = dict(unpack_record(template)[3])
    data = bytearray(fields[b"DATA"])
    if len(data) != 152:
        raise ValueError("Unexpected magic effect DATA layout")
    # Hostile, no hit event, no magnitude, hidden, no death dispel.
    struct.pack_into("<If", data, 0, 0x10008411, 0.0)
    struct.pack_into("<i", data, 16, -1)  # No resistance for capture.
    for offset in (24, 28, 32, 36, 40, 44, 48, 52, 56, 60):
        struct.pack_into("<I", data, offset, 0)
    struct.pack_into("<Ii", data, 64, 1, -1)  # Script archetype, no actor value.
    struct.pack_into("<I", data, 76, 0)  # No second explosion.
    for offset in range(92, 140, 4):
        struct.pack_into("<I", data, offset, 0)
    name = b"CreatorEnergySoulCapture"
    vmad = struct.pack("<HHHH", 5, 2, 1, len(name)) + name + struct.pack("<BH", 0, 0)
    return pack_record(template, SOUL_EFFECT_ID, [
        (b"EDID", b"CreatorEnergySoulCaptureEffect\0"),
        (b"VMAD", vmad),
        (b"FULL", "Przechwycenie duszy".encode("cp1250") + b"\0"),
        (b"DATA", bytes(data)),
    ])


def patch_spell(record: bytes) -> bytes:
    _, _, form_id, fields = unpack_record(record)
    if any(tag == b"EFID" and struct.unpack("<I", value)[0] == SOUL_EFFECT_ID
           for tag, value in fields):
        return record
    for index, (tag, _) in enumerate(fields):
        if tag == b"EFID":
            # Place capture first so it is active before the native damage.
            fields[index:index] = [
                (b"EFID", struct.pack("<I", SOUL_EFFECT_ID)),
                (b"EFIT", struct.pack("<fII", 0.0, 10, 5)),
            ]
            break
    else:
        raise ValueError("Spell has no damage effect")
    return pack_record(record, form_id, fields)


def make_subrecord(signature: bytes, data: bytes) -> bytes:
    if len(data) > 0xFFFF:
        raise ValueError(f"{signature!r} subrecord is too large")
    return signature + struct.pack("<H", len(data)) + data


def zstring(value: str) -> bytes:
    return value.encode("utf-8") + b"\0"


def length_string(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack("<H", len(encoded)) + encoded


def make_record(signature: bytes, form_id: int, payload: bytes) -> bytes:
    return signature + struct.pack("<IIIIHH", len(payload), 0, form_id, 0, 44, 0) + payload


def make_group(signature: bytes, records: list[bytes]) -> bytes:
    payload = b"".join(records)
    return b"GRUP" + struct.pack("<I", 24 + len(payload)) + signature + struct.pack("<iHHHH", 0, 0, 0, 0, 0) + payload


def make_mcm_quest() -> bytes:
    vmad = struct.pack("<HHH", 5, 2, 1)
    vmad += length_string("CreatorEnergyMCM") + struct.pack("<BH", 0, 0)
    vmad += struct.pack("<bH", 2, 0) + length_string("") + struct.pack("<H", 1)
    alias = struct.pack("<HhIHHH", 0, 0, MCM_QUEST_ID, 5, 2, 1)
    alias += length_string("CreatorEnergyPlayerAlias") + struct.pack("<BH", 0, 0)
    vmad += alias
    quest_data = bytes((0x01, 0x00, 80, 0)) + struct.pack("<II", 0, 0)
    payload = (
        make_subrecord(b"EDID", zstring("CreatorEnergyMCMQuest"))
        + make_subrecord(b"VMAD", vmad)
        + make_subrecord(b"FULL", zstring("Energia Stwórcy"))
        + make_subrecord(b"DNAM", quest_data)
        + make_subrecord(b"NEXT", b"")
        + make_subrecord(b"ANAM", struct.pack("<I", 1))
        + make_subrecord(b"ALST", struct.pack("<I", 0))
        + make_subrecord(b"ALID", zstring("Player"))
        + make_subrecord(b"FNAM", struct.pack("<I", 0))
        + make_subrecord(b"ALFR", struct.pack("<I", 0x14))
        + make_subrecord(b"ALED", b"")
    )
    return make_record(b"QUST", MCM_QUEST_ID, payload)


def make_global(editor_id: str, form_id: int, value: float) -> bytes:
    payload = (
        make_subrecord(b"EDID", zstring(editor_id))
        + make_subrecord(b"FNAM", b"f")
        + make_subrecord(b"FLTV", struct.pack("<f", value))
    )
    return make_record(b"GLOB", form_id, payload)


def append_records_to_group(group: bytes, records: list[bytes]) -> bytes:
    if not records:
        return group
    payload = group[24:] + b"".join(records)
    header = bytearray(group[:24])
    struct.pack_into("<I", header, 4, len(payload) + 24)
    return bytes(header) + payload


def update_plugin(path: Path) -> None:
    data = path.read_bytes()
    records = read_plugin(path)
    if not SPELL_IDS.issubset(records) or DAMAGE_EFFECT_ID not in records:
        raise ValueError("Creator Energy damage effect or ranks are missing")
    effect = soul_effect(records[DAMAGE_EFFECT_ID])
    added = SOUL_EFFECT_ID not in records
    add_quest = MCM_QUEST_ID not in records
    globals_to_add = [
        ("CreatorEnergySoulCaptureEnabled", SOUL_CAPTURE_ENABLED_ID, 1.0),
        ("CreatorEnergyFreeBlackGemEnabled", FREE_GEM_ENABLED_ID, 1.0),
    ]
    globals_to_add = [entry for entry in globals_to_add if entry[1] not in records]
    result = bytearray()
    offset = 0
    found_effect_group = False
    found_quest_group = False
    found_global_group = False
    while offset < len(data):
        signature = data[offset:offset + 4]
        size = struct.unpack_from("<I", data, offset + 4)[0]
        end = offset + size if signature == b"GRUP" else offset + 24 + size
        chunk = data[offset:end]
        if signature == b"TES4":
            fields = unpack_record(chunk)[3]
            for index, (tag, value) in enumerate(fields):
                if tag == b"HEDR":
                    version, count, next_id = struct.unpack("<fII", value)
                    fields[index] = (tag, struct.pack("<fII", version,
                        count + int(added) + int(add_quest) + len(globals_to_add), max(next_id, 0x80A)))
            chunk = pack_record(chunk, 0, fields)
        elif signature == b"GRUP" and chunk[8:12] in (b"MGEF", b"SPEL"):
            children = bytearray()
            position = 24
            while position < len(chunk):
                length = 24 + struct.unpack_from("<I", chunk, position + 4)[0]
                record = chunk[position:position + length]
                form_id = struct.unpack_from("<I", record, 12)[0]
                if form_id == SOUL_EFFECT_ID:
                    record = effect
                elif form_id in SPELL_IDS:
                    record = patch_spell(record)
                children.extend(record)
                position += length
            if chunk[8:12] == b"MGEF":
                found_effect_group = True
                if added:
                    children.extend(effect)
            header = bytearray(chunk[:24])
            struct.pack_into("<I", header, 4, len(children) + 24)
            chunk = bytes(header) + children
        elif signature == b"GRUP" and chunk[8:12] == b"QUST":
            found_quest_group = True
            if add_quest:
                chunk = append_records_to_group(chunk, [make_mcm_quest()])
        elif signature == b"GRUP" and chunk[8:12] == b"GLOB":
            found_global_group = True
            new_globals = [make_global(*entry) for entry in globals_to_add]
            chunk = append_records_to_group(chunk, new_globals)
        result.extend(chunk)
        offset = end
    if add_quest and not found_quest_group:
        result.extend(make_group(b"QUST", [make_mcm_quest()]))
    if globals_to_add and not found_global_group:
        result.extend(make_group(b"GLOB", [make_global(*entry) for entry in globals_to_add]))
    if not found_effect_group:
        raise ValueError("MGEF group is missing")
    path.write_bytes(result)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin", type=Path,
        default=Path(__file__).resolve().parents[1] / "Data/CreatorEnergy.esp")
    update_plugin(parser.parse_args().plugin)
