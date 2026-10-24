#!/usr/bin/env python3
"""Attach existing Skyrim sound descriptors to Energia Stwórcy's magic effect."""

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
        new_payload = struct.pack("<I", len(new_payload)) + zlib.compress(new_payload)
    header = bytearray(record[:24])
    struct.pack_into("<I", header, 4, len(new_payload))
    return bytes(header) + new_payload


def update_plugin(plugin_path: Path, master_path: Path) -> None:
    master_records = read_plugin(master_path)
    for _, sound_id in SOUNDS:
        record = master_records.get(sound_id)
        if record is None or record[:4] != b"SNDR":
            raise ValueError(f"Missing Skyrim sound descriptor {sound_id:08X}")

    plugin_data = plugin_path.read_bytes()
    rebuilt = bytearray()
    position = 0
    changed = False
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
                child_signature = plugin_data[child_position:child_position + 4]
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
                if child_signature == b"MGEF":
                    record_id = struct.unpack_from("<I", record, 12)[0]
                    if record_id == TARGET_FORM_ID:
                        record = patch_magic_effect(record)
                        changed = True
                children.extend(record)
                child_position = child_end
            struct.pack_into("<I", group_header, 4, 24 + len(children))
            rebuilt.extend(group_header)
            rebuilt.extend(children)
            position = group_end
        else:
            if position + 24 > len(plugin_data):
                raise ValueError("Truncated top-level record")
            payload_size = struct.unpack_from("<I", plugin_data, position + 4)[0]
            record_end = position + 24 + payload_size
            if record_end > len(plugin_data):
                raise ValueError("Truncated top-level record payload")
            rebuilt.extend(plugin_data[position:record_end])
            position = record_end

    if not changed:
        raise ValueError("CreatorEnergyDamage MGEF was not found")
    plugin_path.write_bytes(rebuilt)


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
    print(f"Added non-elemental spell sounds to {args.plugin}")


if __name__ == "__main__":
    main()
