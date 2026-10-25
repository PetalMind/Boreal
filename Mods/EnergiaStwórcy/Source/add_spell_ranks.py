#!/usr/bin/env python3
"""Add the separate rank-II and rank-III Creator Energy spells."""

from __future__ import annotations

import argparse
import struct
import zlib
from pathlib import Path


BASE_FORM_ID = 0x01000803
RANKS = (
    {
        "form_id": 0x01000804,
        "editor_id": "CreatorEnergySpell02",
        "name": "Energia Stwórcy II",
        "description": "Zadaje 40 pkt obrażeń magicznych w promieniu 10 stóp.",
        "cost": 45,
        "magnitude": 40.0,
    },
    {
        "form_id": 0x01000805,
        "editor_id": "CreatorEnergySpell03",
        "name": "Energia Stwórcy III",
        "description": "Zadaje 60 pkt obrażeń magicznych w promieniu 10 stóp.",
        "cost": 70,
        "magnitude": 60.0,
    },
)
COMPRESSED_FLAG = 0x00040000


def parse_subrecords(payload: bytes) -> list[tuple[bytes, bytes]]:
    subrecords = []
    offset = 0
    while offset < len(payload):
        if offset + 6 > len(payload):
            raise ValueError("Truncated subrecord header")
        tag = payload[offset:offset + 4]
        size = struct.unpack_from("<H", payload, offset + 4)[0]
        offset += 6
        if tag == b"XXXX":
            if offset + 10 > len(payload):
                raise ValueError("Malformed XXXX subrecord")
            size = struct.unpack_from("<I", payload, offset)[0]
            offset += 4
            tag = payload[offset:offset + 4]
            offset += 6
        if offset + size > len(payload):
            raise ValueError(f"Malformed {tag!r} subrecord")
        subrecords.append((tag, payload[offset:offset + size]))
        offset += size
    return subrecords


def unpack_record(record: bytes) -> tuple[bytes, int, int, list[tuple[bytes, bytes]]]:
    if len(record) < 24:
        raise ValueError("Truncated record")
    signature, payload_size, flags, form_id = struct.unpack_from(
        "<4sIII", record
    )
    payload = record[24:24 + payload_size]
    if len(payload) != payload_size:
        raise ValueError("Truncated record payload")
    if flags & COMPRESSED_FLAG:
        if len(payload) < 4:
            raise ValueError("Compressed record has no expanded size")
        expected_size = struct.unpack_from("<I", payload)[0]
        payload = zlib.decompress(payload[4:])
        if len(payload) != expected_size:
            raise ValueError("Compressed record size does not match")
    return signature, flags, form_id, parse_subrecords(payload)


def pack_record(
    template: bytes,
    form_id: int,
    subrecords: list[tuple[bytes, bytes]],
) -> bytes:
    _, flags, _, _ = unpack_record(template)
    payload = b"".join(
        tag + struct.pack("<H", len(value)) + value
        for tag, value in subrecords
    )
    if any(len(value) > 0xFFFF for _, value in subrecords):
        raise ValueError("A subrecord is too large for the standard encoding")
    if flags & COMPRESSED_FLAG:
        payload = struct.pack("<I", len(payload)) + zlib.compress(payload)
    header = bytearray(template[:24])
    struct.pack_into("<I", header, 4, len(payload))
    struct.pack_into("<I", header, 12, form_id)
    return bytes(header) + payload


def editor_id(record: bytes) -> str:
    signature, _, _, subrecords = unpack_record(record)
    if signature != b"SPEL":
        raise ValueError("Expected a SPEL record")
    for tag, payload in subrecords:
        if tag == b"EDID":
            return payload.rstrip(b"\0").decode("ascii")
    raise ValueError("SPEL record has no EDID")


def patch_spell(record: bytes, rank: dict, form_id: int) -> bytes:
    signature, _, _, subrecords = unpack_record(record)
    if signature != b"SPEL":
        raise ValueError("CreatorEnergySpell is not a SPEL record")
    patched = []
    found = set()
    found_effect = False
    current_effect = None
    for tag, payload in subrecords:
        if tag == b"EDID":
            payload = rank["editor_id"].encode("ascii") + b"\0"
            found.add(tag)
        elif tag == b"FULL":
            payload = rank["name"].encode("cp1250") + b"\0"
            found.add(tag)
        elif tag == b"DESC":
            payload = rank["description"].encode("cp1250") + b"\0"
            found.add(tag)
        elif tag == b"SPIT":
            if len(payload) < 4:
                raise ValueError("Malformed SPEL SPIT subrecord")
            spell_data = bytearray(payload)
            struct.pack_into("<I", spell_data, 0, rank["cost"])
            payload = bytes(spell_data)
            found.add(tag)
        elif tag == b"EFID":
            current_effect = struct.unpack("<I", payload)[0]
        elif tag == b"EFIT" and current_effect == 0x01000800:
            if found_effect:
                raise ValueError("CreatorEnergySpell has multiple effects")
            if len(payload) != 12:
                raise ValueError("Malformed CreatorEnergySpell EFIT")
            _, area, duration = struct.unpack("<fII", payload)
            payload = struct.pack(
                "<fII", rank["magnitude"], area, duration
            )
            found_effect = True
        patched.append((tag, payload))
    if not {b"EDID", b"FULL", b"DESC", b"SPIT"}.issubset(found):
        raise ValueError("CreatorEnergySpell is missing required fields")
    if not found_effect:
        raise ValueError("CreatorEnergySpell has no EFIT effect")
    return pack_record(record, form_id, patched)


def patch_header(header: bytes, added: int) -> bytes:
    signature, _, _, subrecords = unpack_record(header)
    if signature != b"TES4":
        raise ValueError("Expected TES4 header")
    patched = []
    found_hedr = False
    for tag, payload in subrecords:
        if tag == b"HEDR":
            if len(payload) < 12:
                raise ValueError("Malformed TES4 HEDR")
            value = bytearray(payload)
            count = struct.unpack_from("<I", value, 4)[0]
            next_id = struct.unpack_from("<I", value, 8)[0]
            struct.pack_into("<I", value, 4, count + added)
            struct.pack_into("<I", value, 8, max(next_id, 0x00000806))
            payload = bytes(value)
            found_hedr = True
        patched.append((tag, payload))
    if not found_hedr:
        raise ValueError("TES4 HEDR was not found")
    return pack_record(header, 0, patched)


def add_ranks(plugin_path: Path) -> None:
    data = plugin_path.read_bytes()
    position = 0
    header = None
    rebuilt = bytearray()
    spell_group = None
    spell_group_insert_at = None
    spell_records = {}

    while position < len(data):
        signature = data[position:position + 4]
        if signature == b"GRUP":
            size = struct.unpack_from("<I", data, position + 4)[0]
            end = position + size
            if size < 24 or end > len(data):
                raise ValueError("Malformed GRUP in CreatorEnergy.esp")
            label = data[position + 8:position + 12]
            if label == b"SPEL":
                if spell_group is not None:
                    raise ValueError("Duplicate SPEL groups")
                spell_group = bytearray(data[position:position + 24])
                spell_group_insert_at = len(rebuilt)
                child = position + 24
                while child < end:
                    if data[child:child + 4] == b"GRUP":
                        raise ValueError("Nested SPEL groups are not expected")
                    payload_size = struct.unpack_from("<I", data, child + 4)[0]
                    record_end = child + 24 + payload_size
                    if record_end > end:
                        raise ValueError("Truncated SPEL record")
                    record = data[child:record_end]
                    form_id = struct.unpack_from("<I", record, 12)[0]
                    if form_id in spell_records:
                        raise ValueError(f"Duplicate SPEL FormID {form_id:08X}")
                    spell_records[form_id] = record
                    child = record_end
            else:
                rebuilt.extend(data[position:end])
            position = end
            continue

        if position + 24 > len(data):
            raise ValueError("Truncated top-level record")
        size = struct.unpack_from("<I", data, position + 4)[0]
        end = position + 24 + size
        if end > len(data):
            raise ValueError("Truncated top-level record payload")
        record = data[position:end]
        if signature == b"TES4":
            header = record
        else:
            rebuilt.extend(record)
        position = end

    if header is None or spell_group is None:
        raise ValueError("TES4 header or SPEL group was not found")
    base = spell_records.get(BASE_FORM_ID)
    if base is None or editor_id(base) != "CreatorEnergySpell":
        raise ValueError("CreatorEnergySpell base record was not found")

    rank_one = {
        "editor_id": "CreatorEnergySpell",
        "name": "Energia Stwórcy I",
        "description": "Zadaje 25 pkt obrażeń magicznych w promieniu 10 stóp.",
        "cost": 25,
        "magnitude": 25.0,
    }
    base = patch_spell(base, rank_one, BASE_FORM_ID)
    spell_records[BASE_FORM_ID] = base

    ids = {editor_id(record): form_id for form_id, record in spell_records.items()}
    added = 0
    for rank in RANKS:
        existing_id = ids.get(rank["editor_id"])
        if existing_id is not None and existing_id != rank["form_id"]:
            raise ValueError(
                f"{rank['editor_id']} has unexpected FormID {existing_id:08X}"
            )
        if rank["form_id"] in spell_records and existing_id is None:
            raise ValueError(f"SPEL FormID {rank['form_id']:08X} is already in use")
        spell_records[rank["form_id"]] = patch_spell(
            base, rank, rank["form_id"]
        )
        if existing_id is None:
            added += 1
        ids[rank["editor_id"]] = rank["form_id"]

    children = b"".join(record for _, record in sorted(spell_records.items()))
    struct.pack_into("<I", spell_group, 4, 24 + len(children))
    rebuilt_group = bytes(spell_group) + children
    if spell_group_insert_at is None:
        raise ValueError("SPEL group insertion point was not found")
    non_header_data = bytes(rebuilt)
    plugin_path.write_bytes(
        patch_header(header, added)
        + non_header_data[:spell_group_insert_at]
        + rebuilt_group
        + non_header_data[spell_group_insert_at:]
    )


def main() -> None:
    source_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--plugin",
        type=Path,
        default=source_root / "Data" / "CreatorEnergy.esp",
    )
    args = parser.parse_args()
    add_ranks(args.plugin)
    print(f"Updated Creator Energy ranks in {args.plugin}")


if __name__ == "__main__":
    main()
