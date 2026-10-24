#!/usr/bin/env python3
"""Attach Skyrim sounds to Energia Stwórcy's spell effect and explosion."""

from __future__ import annotations

import argparse
import struct
import zlib
from pathlib import Path


SOUNDS = (
    (0, 0x0003F37A),
    (1, 0x000FDA53),
    (2, 0x000FDA52),
    (3, 0x0007D014),
    (5, 0x0008196E),
)
COMPRESSED_FLAG = 0x00040000
TARGET_FORM_ID = 0x01000800
EXPLOSION_FORM_ID = 0x01000802
EXPLOSION_SOUND_ID = 0x0003F320


def read_plugin(path: Path) -> dict[int, bytes]:
    data = path.read_bytes()
    records: dict[int, bytes] = {}

    def walk(start: int, end: int) -> None:
        position = start
        while position < end:
            signature = data[position:position + 4]
            if signature == b"GRUP":
                group_size = struct.unpack_from("<I", data, position + 4)[0]
                if group_size < 24 or position + group_size > end:
                    raise ValueError("Malformed GRUP in plugin")
                walk(position + 24, position + group_size)
                position += group_size
                continue

            if position + 24 > end:
                raise ValueError("Truncated record header")
            payload_size, _, form_id = struct.unpack_from(
                "<III", data, position + 4
            )
            record_end = position + 24 + payload_size
            if record_end > end:
                raise ValueError("Truncated record payload")
            records[form_id] = data[position:record_end]
            position = record_end

    walk(0, len(data))
    return records


def make_subrecord(tag: bytes, payload: bytes) -> bytes:
    if len(payload) > 0xFFFF:
        raise ValueError(f"{tag!r} subrecord exceeds standard size")
    return tag + struct.pack("<H", len(payload)) + payload


def patch_magic_effect(record: bytes) -> bytes:
    signature, payload_size, flags = struct.unpack_from("<4sII", record)
    if signature != b"MGEF":
        raise ValueError("CreatorEnergyDamage is not an MGEF record")
    payload = record[24:24 + payload_size]
    if flags & COMPRESSED_FLAG:
        if len(payload) < 4:
            raise ValueError("Compressed MGEF has no expanded size")
        expected_size = struct.unpack_from("<I", payload)[0]
        payload = zlib.decompress(payload[4:])
        if len(payload) != expected_size:
            raise ValueError("Compressed MGEF size does not match")

    sound_data = b"".join(
        struct.pack("<II", sound_type, sound_id)
        for sound_type, sound_id in SOUNDS
    )
    subrecords = []
    offset = 0
    found_editor_id = False
    found_sound_data = False
    while offset < len(payload):
        if offset + 6 > len(payload):
            raise ValueError("Truncated MGEF subrecord")
        tag = payload[offset:offset + 4]
        size = struct.unpack_from("<H", payload, offset + 4)[0]
        offset += 6
        if tag == b"XXXX":
            if offset + 4 > len(payload):
                raise ValueError("Malformed XXXX subrecord")
            size = struct.unpack_from("<I", payload, offset)[0]
            offset += 4
            if offset + 6 > len(payload):
                raise ValueError("Malformed extended subrecord")
            tag = payload[offset:offset + 4]
            offset += 6
        if offset + size > len(payload):
            raise ValueError(f"Malformed {tag!r} subrecord")
        value = payload[offset:offset + size]
        offset += size
        if tag == b"EDID":
            found_editor_id = value.rstrip(b"\0") == b"CreatorEnergyDamage"
        if tag == b"SNDD":
            value = sound_data
            found_sound_data = True
        subrecords.append(make_subrecord(tag, value))

    if not found_editor_id:
        raise ValueError("MGEF is not CreatorEnergyDamage")
    if not found_sound_data:
        subrecords.append(make_subrecord(b"SNDD", sound_data))
    new_payload = b"".join(subrecords)
    if flags & COMPRESSED_FLAG:
        new_payload = (
            struct.pack("<I", len(new_payload)) + zlib.compress(new_payload)
        )
    header = bytearray(record[:24])
    struct.pack_into("<I", header, 4, len(new_payload))
    return bytes(header) + new_payload


def patch_explosion(record: bytes) -> bytes:
    signature, payload_size, flags = struct.unpack_from("<4sII", record)
    if signature != b"EXPL":
        raise ValueError("CreatorEnergyExplosion is not an EXPL record")
    payload = record[24:24 + payload_size]
    if flags & COMPRESSED_FLAG:
        if len(payload) < 4:
            raise ValueError("Compressed EXPL has no expanded size")
        expected_size = struct.unpack_from("<I", payload)[0]
        payload = zlib.decompress(payload[4:])
        if len(payload) != expected_size:
            raise ValueError("Compressed EXPL size does not match")

    subrecords = []
    offset = 0
    found_editor_id = False
    found_data = False
    while offset < len(payload):
        if offset + 6 > len(payload):
            raise ValueError("Truncated EXPL subrecord")
        tag = payload[offset:offset + 4]
        size = struct.unpack_from("<H", payload, offset + 4)[0]
        offset += 6
        if tag == b"XXXX":
            if offset + 4 > len(payload):
                raise ValueError("Malformed XXXX subrecord")
            size = struct.unpack_from("<I", payload, offset)[0]
            offset += 4
            if offset + 6 > len(payload):
                raise ValueError("Malformed extended subrecord")
            tag = payload[offset:offset + 4]
            offset += 6
        if offset + size > len(payload):
            raise ValueError(f"Malformed {tag!r} subrecord")
        value = payload[offset:offset + size]
        offset += size
        if tag == b"EDID":
            found_editor_id = value.rstrip(b"\0") == b"CreatorEnergyExplosion"
        elif tag == b"DATA":
            if len(value) < 12:
                raise ValueError(
                    "CreatorEnergyExplosion DATA is too short for sound fields"
                )
            value = bytearray(value)
            # EXPL DATA starts with the Light, Sound 1, and Sound 2 FormIDs.
            struct.pack_into("<I", value, 4, EXPLOSION_SOUND_ID)
            value = bytes(value)
            found_data = True
        subrecords.append(make_subrecord(tag, value))

    if not found_editor_id:
        raise ValueError("EXPL is not CreatorEnergyExplosion")
    if not found_data:
        raise ValueError("CreatorEnergyExplosion DATA was not found")
    new_payload = b"".join(subrecords)
    if flags & COMPRESSED_FLAG:
        new_payload = (
            struct.pack("<I", len(new_payload)) + zlib.compress(new_payload)
        )
    header = bytearray(record[:24])
    struct.pack_into("<I", header, 4, len(new_payload))
    return bytes(header) + new_payload


def patch_plugin_data(plugin_data: bytes) -> bytes:
    rebuilt = bytearray()
    position = 0
    found_magic_effect = False
    found_explosion = False
    while position < len(plugin_data):
        signature = plugin_data[position:position + 4]
        if signature == b"GRUP":
            group_size = struct.unpack_from("<I", plugin_data, position + 4)[0]
            group_end = position + group_size
            if group_size < 24 or group_end > len(plugin_data):
                raise ValueError("Malformed GRUP in CreatorEnergy.esp")
            group_header = bytearray(plugin_data[position:position + 24])
            children = bytearray()
            child_position = position + 24
            while child_position < group_end:
                child_signature = plugin_data[
                    child_position:child_position + 4
                ]
                if child_signature == b"GRUP":
                    raise ValueError(
                        "Nested GRUPs are not expected in CreatorEnergy.esp"
                    )
                payload_size = struct.unpack_from(
                    "<I", plugin_data, child_position + 4
                )[0]
                child_end = child_position + 24 + payload_size
                if child_end > group_end:
                    raise ValueError("Truncated record inside GRUP")
                record = plugin_data[child_position:child_end]
                record_id = struct.unpack_from("<I", record, 12)[0]
                if child_signature == b"MGEF" and record_id == TARGET_FORM_ID:
                    record = patch_magic_effect(record)
                    found_magic_effect = True
                elif (
                    child_signature == b"EXPL"
                    and record_id == EXPLOSION_FORM_ID
                ):
                    record = patch_explosion(record)
                    found_explosion = True
                children.extend(record)
                child_position = child_end
            struct.pack_into("<I", group_header, 4, 24 + len(children))
            rebuilt.extend(group_header)
            rebuilt.extend(children)
            position = group_end
        else:
            if position + 24 > len(plugin_data):
                raise ValueError("Truncated top-level record")
            payload_size = struct.unpack_from(
                "<I", plugin_data, position + 4
            )[0]
            record_end = position + 24 + payload_size
            if record_end > len(plugin_data):
                raise ValueError("Truncated top-level record payload")
            rebuilt.extend(plugin_data[position:record_end])
            position = record_end

    if not found_magic_effect:
        raise ValueError("CreatorEnergyDamage MGEF was not found")
    if not found_explosion:
        raise ValueError("CreatorEnergyExplosion EXPL was not found")
    return bytes(rebuilt)


def update_plugin(plugin_path: Path, master_path: Path) -> None:
    master_records = read_plugin(master_path)
    sound_ids = [sound_id for _, sound_id in SOUNDS]
    sound_ids.append(EXPLOSION_SOUND_ID)
    for sound_id in sound_ids:
        record = master_records.get(sound_id)
        if record is None or record[:4] != b"SNDR":
            raise ValueError(f"Missing Skyrim sound descriptor {sound_id:08X}")

    plugin_path.write_bytes(patch_plugin_data(plugin_path.read_bytes()))


def main() -> None:
    source_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--plugin",
        type=Path,
        default=source_root / "Data" / "CreatorEnergy.esp",
    )
    parser.add_argument(
        "--skyrim-data",
        type=Path,
        required=True,
        help="Skyrim SE Data folder containing Skyrim.esm",
    )
    args = parser.parse_args()
    update_plugin(args.plugin, args.skyrim_data / "Skyrim.esm")
    print(f"Updated cast, hit, and explosion sounds in {args.plugin}")


if __name__ == "__main__":
    main()
