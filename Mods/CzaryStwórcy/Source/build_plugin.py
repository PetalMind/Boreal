#!/usr/bin/env python3
"""Build the Creator spell plugin from the user's Skyrim SE master file."""

from __future__ import annotations

import argparse
import struct
import zlib
from pathlib import Path

MIND_TAKEOVER_DURATION = 0x7FFFFFFF
MIND_TAKEOVER_MANUAL_COST_FLAG = 0x00000001
MIND_TAKEOVER_GUARD_KEYWORD = 0x0007EAF3
MIND_TAKEOVER_HAS_KEYWORD_FUNCTION = 560
MGEF_CONDITION_OR_FLAG = 0x01
MIND_TAKEOVER_EFFECT_EDITOR_IDS = {
    "CreatorMindTakeoverSpellEffect01",
    "CreatorMindTakeoverSpellEffect02",
    "CreatorMindTakeoverSpellEffect03",
}
MGEF_HOSTILE_FLAG = 0x00000001


SPELLS: tuple[dict, ...] = (
    {
        "source": 0x0008D5BF,
        "editor_id": "CreatorAbsorptionSpell",
        "name": "Pochłonięcie Stwórcy I",
        "description": (
            "Wysysa 16 pkt zdrowia na sekundę i przywraca je rzucającemu. "
            "Zasięg 30 m."
        ),
        "cost": 12,
        "range": 2100.0,
        "effects": ((0x000F5B57, 16.0, 0, 0),),
        "sound_profiles": ("absorption",),
    },
    {
        "source": 0x0005AD5E,
        "editor_id": "CreatorBarrier01Spell",
        "name": "Bariera Stwórcy I",
        "description": (
            "Dodaje 167 pkt pancerza i 20% odporności na magię przez 10 s."
        ),
        "cost": 35,
        "effects": ((0x00059B7C, 167.0, 0, 10), (0x00039E51, 20.0, 0, 10)),
        "sound_profiles": ("alteration", "silent"),
    },
    {
        "source": 0x0005AD5E,
        "editor_id": "CreatorBarrier02Spell",
        "name": "Bariera Stwórcy II",
        "description": (
            "Dodaje 250 pkt pancerza i 30% odporności na magię przez 12 s."
        ),
        "cost": 50,
        "effects": ((0x00059B7C, 250.0, 0, 12), (0x00039E51, 30.0, 0, 12)),
        "sound_profiles": ("alteration", "silent"),
    },
    {
        "source": 0x0005AD5E,
        "editor_id": "CreatorBarrier03Spell",
        "name": "Bariera Stwórcy III",
        "description": (
            "Dodaje 333 pkt pancerza i 40% odporności na magię przez 15 s."
        ),
        "cost": 65,
        "effects": ((0x00059B7C, 333.0, 0, 15), (0x00039E51, 40.0, 0, 15)),
        "sound_profiles": ("alteration", "silent"),
    },
    {
        "source": 0x0002B96C,
        "editor_id": "CreatorImpulseSpell",
        "name": "Impuls Stwórcy I",
        "description": "Zadaje 15 pkt obrażeń i zachwiewa cele w promieniu 16 stóp.",
        "cost": 45,
        "effects": ((0x00013E08, 0.75, 16, 0), (0x000EA075, 15.0, 16, 0)),
        "sound_profiles": ("impulse", "silent"),
    },
    {
        "source": 0x0004DEEE,
        "editor_id": "CreatorMindTakeoverSpell",
        "name": "Przejęcie Jaźni I",
        "manual_cost": True,
        "description": (
            "Istota do poziomu 50 atakuje pobliskie cele aż do śmierci."
        ),
        "cost": 45,
        "effects": (
            (0x0001EA78, 50.0, 0, MIND_TAKEOVER_DURATION),
            (0x0009E0BF, 50.0, 0, MIND_TAKEOVER_DURATION),
            (0x00026D7C, 50.0, 0, MIND_TAKEOVER_DURATION),
        ),
        "sound_profiles": ("alteration_hit", "silent", "silent"),
    },
    {
        "source": 0x0002B96C,
        "editor_id": "CreatorRealityWeakeningSpell",
        "name": "Osłabienie Rzeczywistości I",
        "description": "Spowalnia ruch celu o 75% przez 10 s.",
        "cost": 40,
        "effects": ((0x000B729F, 75.0, 0, 10),),
        "sound_profiles": ("alteration_hit",),
    },
    {
        "source": 0x0002B96C,
        "editor_id": "CreatorDecaySpell",
        "name": "Zanik I",
        "description": "Zadaje 6 pkt obrażeń zdrowia na sekundę przez 5 s.",
        "cost": 40,
        "effects": ((0x000EA075, 6.0, 0, 5),),
        "sound_profiles": ("alteration_hit",),
    },
    {
        "source": 0x0005AD5E,
        "editor_id": "CreatorWillReflectionSpell",
        "name": "Odbicie Woli I",
        "description": (
            "Odbija 20% obrażeń fizycznych i dodaje 20% odporności "
            "na magię przez 6 s."
        ),
        "cost": 40,
        "effects": ((0x00108A41, 20.0, 0, 6), (0x00039E51, 20.0, 0, 6)),
        "sound_profiles": ("alteration", "silent"),
    },
)


# Higher ranks are separate spells. They reuse each rank-I spell's custom
# magic effects so the existing effect FormIDs remain stable across rebuilds.
RANK_VARIANTS: tuple[dict, ...] = (
    {
        "base": "CreatorAbsorptionSpell",
        "editor_id": "CreatorAbsorption02Spell",
        "name": "Pochłonięcie Stwórcy II",
        "description": (
            "Wysysa 24 pkt zdrowia na sekundę i przywraca je rzucającemu. "
            "Zasięg 30 m."
        ),
        "cost": 18,
        "effects": ((24.0, 0, 0),),
    },
    {
        "base": "CreatorAbsorptionSpell",
        "editor_id": "CreatorAbsorption03Spell",
        "name": "Pochłonięcie Stwórcy III",
        "description": (
            "Wysysa 32 pkt zdrowia na sekundę i przywraca je rzucającemu. "
            "Zasięg 30 m."
        ),
        "cost": 24,
        "effects": ((32.0, 0, 0),),
    },
    {
        "base": "CreatorImpulseSpell",
        "editor_id": "CreatorImpulse02Spell",
        "name": "Impuls Stwórcy II",
        "description": "Zadaje 25 pkt obrażeń i zachwiewa cele w promieniu 16 stóp.",
        "cost": 75,
        "effects": ((0.75, 16, 0), (25.0, 16, 0)),
    },
    {
        "base": "CreatorImpulseSpell",
        "editor_id": "CreatorImpulse03Spell",
        "name": "Impuls Stwórcy III",
        "description": "Zadaje 40 pkt obrażeń i zachwiewa cele w promieniu 16 stóp.",
        "cost": 120,
        "effects": ((0.75, 16, 0), (40.0, 16, 0)),
    },
    {
        "base": "CreatorMindTakeoverSpell",
        "editor_id": "CreatorMindTakeover02Spell",
        "name": "Przejęcie Jaźni II",
        "manual_cost": True,
        "description": (
            "Istota do poziomu 75 atakuje pobliskie cele aż do śmierci."
        ),
        "cost": 80,
        "effects": (
            (75.0, 0, MIND_TAKEOVER_DURATION),
            (75.0, 0, MIND_TAKEOVER_DURATION),
            (75.0, 0, MIND_TAKEOVER_DURATION),
        ),
    },
    {
        "base": "CreatorMindTakeoverSpell",
        "editor_id": "CreatorMindTakeover03Spell",
        "name": "Przejęcie Jaźni III",
        "manual_cost": True,
        "description": (
            "Istota do poziomu 100 atakuje pobliskie cele aż do śmierci."
        ),
        "cost": 120,
        "effects": (
            (100.0, 0, MIND_TAKEOVER_DURATION),
            (100.0, 0, MIND_TAKEOVER_DURATION),
            (100.0, 0, MIND_TAKEOVER_DURATION),
        ),
    },
    {
        "base": "CreatorRealityWeakeningSpell",
        "editor_id": "CreatorRealityWeakening02Spell",
        "name": "Osłabienie Rzeczywistości II",
        "description": "Spowalnia ruch celu o 75% przez 15 s.",
        "cost": 65,
        "effects": ((75.0, 0, 15),),
    },
    {
        "base": "CreatorRealityWeakeningSpell",
        "editor_id": "CreatorRealityWeakening03Spell",
        "name": "Osłabienie Rzeczywistości III",
        "description": "Spowalnia ruch celu o 75% przez 20 s.",
        "cost": 90,
        "effects": ((75.0, 0, 20),),
    },
    {
        "base": "CreatorDecaySpell",
        "editor_id": "CreatorDecay02Spell",
        "name": "Zanik II",
        "description": "Zadaje 8 pkt obrażeń zdrowia na sekundę przez 6 s.",
        "cost": 65,
        "effects": ((8.0, 0, 6),),
    },
    {
        "base": "CreatorDecaySpell",
        "editor_id": "CreatorDecay03Spell",
        "name": "Zanik III",
        "description": "Zadaje 10 pkt obrażeń zdrowia na sekundę przez 8 s.",
        "cost": 100,
        "effects": ((10.0, 0, 8),),
    },
    {
        "base": "CreatorWillReflectionSpell",
        "editor_id": "CreatorWillReflection02Spell",
        "name": "Odbicie Woli II",
        "description": (
            "Odbija 30% obrażeń fizycznych i dodaje 30% odporności "
            "na magię przez 8 s."
        ),
        "cost": 70,
        "effects": ((30.0, 0, 8), (30.0, 0, 8)),
    },
    {
        "base": "CreatorWillReflectionSpell",
        "editor_id": "CreatorWillReflection03Spell",
        "name": "Odbicie Woli III",
        "description": (
            "Odbija 40% obrażeń fizycznych i dodaje 40% odporności "
            "na magię przez 10 s."
        ),
        "cost": 100,
        "effects": ((40.0, 0, 10), (40.0, 0, 10)),
    },
)


# Sound descriptors are existing Skyrim.esm records. SNDD sound types are
# draw/sheath, charge, ready, release, concentration loop, and effect hit.
SOUND_PROFILES = {
    "absorption": ((0, 0x0003F208), (3, 0x0003F206), (4, 0x0003F205)),
    "alteration": (
        (0, 0x0003F37A),
        (1, 0x000FDA53),
        (2, 0x000FDA52),
        (3, 0x0007D014),
    ),
    "alteration_hit": (
        (0, 0x0003F37A),
        (1, 0x000FDA53),
        (2, 0x000FDA52),
        (3, 0x0007D014),
        (5, 0x0008196E),
    ),
    "impulse": ((3, 0x000A0F52), (5, 0x0003F320)),
    "silent": (),
}


Record = tuple[bytes, int, list[tuple[bytes, bytes]]]


def read_plugin(path: Path) -> dict[int, Record]:
    data = path.read_bytes()
    records: dict[int, tuple[bytes, int, list[tuple[bytes, bytes]]]] = {}

    def walk(start: int, end: int) -> None:
        position = start
        while position < end:
            signature = data[position:position + 4]
            if signature == b"GRUP":
                group_size = struct.unpack_from("<I", data, position + 4)[0]
                if group_size < 24 or position + group_size > end:
                    raise ValueError("Malformed GRUP in Skyrim.esm")
                walk(position + 24, position + group_size)
                position += group_size
                continue

            if position + 24 > end:
                raise ValueError("Truncated record header in Skyrim.esm")
            payload_size, flags, form_id = struct.unpack_from(
                "<III", data, position + 4
            )
            record_end = position + 24 + payload_size
            if record_end > end:
                raise ValueError("Truncated record payload in Skyrim.esm")
            payload = data[position + 24:record_end]
            if flags & 0x00040000:
                if len(payload) < 4:
                    raise ValueError("Compressed record has no expanded size")
                expected_size = struct.unpack_from("<I", payload)[0]
                payload = zlib.decompress(payload[4:])
                if len(payload) != expected_size:
                    raise ValueError("Compressed record size does not match")

            subrecords = []
            offset = 0
            while offset < len(payload):
                if offset + 6 > len(payload):
                    raise ValueError("Truncated subrecord header")
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
                subrecords.append((tag, payload[offset:offset + size]))
                offset += size

            records[form_id] = (signature, flags & ~0x00040000, subrecords)
            position = record_end

    walk(0, len(data))
    return records


def make_subrecord(tag: bytes, payload: bytes) -> bytes:
    if len(payload) > 0xFFFF:
        raise ValueError(f"{tag!r} subrecord exceeds standard size")
    return tag + struct.pack("<H", len(payload)) + payload


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
    if flags & 0x00040000:
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
    flags = struct.unpack_from("<I", template, 8)[0]
    payload = b"".join(make_subrecord(tag, value) for tag, value in subrecords)
    if flags & 0x00040000:
        payload = struct.pack("<I", len(payload)) + zlib.compress(payload)
    header = bytearray(template[:24])
    struct.pack_into("<I", header, 4, len(payload))
    struct.pack_into("<I", header, 12, form_id)
    return bytes(header) + payload


def mind_takeover_guard_condition() -> bytes:
    """Apply the effect only when its target is not a guard."""
    return struct.pack(
        "<B3sfH2sIIIIi",
        0x20,  # HasKeyword != 1.0
        b"\0" * 3,
        1.0,
        MIND_TAKEOVER_HAS_KEYWORD_FUNCTION,
        b"\0" * 2,
        MIND_TAKEOVER_GUARD_KEYWORD,
        0,
        0,  # Run on the effect target (Subject).
        0,
        -1,
    )


def patch_mind_takeover_magic_effect(record: bytes, editor_id: str) -> bytes:
    """Keep the frenzy effect non-hostile and exclude guards as targets."""
    signature, _, form_id, subrecords = unpack_record(record)
    is_mind_takeover_effect = editor_id in MIND_TAKEOVER_EFFECT_EDITOR_IDS
    if signature != b"MGEF" or not is_mind_takeover_effect:
        raise ValueError(f"Unexpected Mind Takeover magic effect: {editor_id}")

    guard_condition = mind_takeover_guard_condition()
    patched = []
    has_data = False
    condition_indexes = []
    guard_condition_index = None
    for tag, payload in subrecords:
        if tag == b"DATA":
            if len(payload) < 4:
                raise ValueError(f"Malformed DATA subrecord in {editor_id}")
            magic_effect_data = bytearray(payload)
            flags = struct.unpack_from("<I", magic_effect_data)[0]
            struct.pack_into(
                "<I", magic_effect_data, 0, flags & ~MGEF_HOSTILE_FLAG
            )
            payload = bytes(magic_effect_data)
            has_data = True
        patched.append((tag, payload))
        if tag == b"CTDA":
            condition_indexes.append(len(patched) - 1)
            if payload == guard_condition:
                guard_condition_index = len(patched) - 1

    if not has_data:
        raise ValueError(f"MGEF {editor_id} has no DATA subrecord")
    if (
        guard_condition_index is not None
        and guard_condition_index != condition_indexes[-1]
    ):
        raise ValueError(f"Guard condition is not last in {editor_id}")
    if guard_condition_index is None:
        if condition_indexes:
            last_condition_index = condition_indexes[-1]
            previous_condition = bytearray(patched[last_condition_index][1])
            previous_condition[0] &= ~MGEF_CONDITION_OR_FLAG
            patched[last_condition_index] = (
                b"CTDA",
                bytes(previous_condition),
            )
        patched.append((b"CTDA", guard_condition))
    elif len(condition_indexes) > 1:
        previous_condition_index = condition_indexes[-2]
        previous_condition = bytearray(patched[previous_condition_index][1])
        previous_condition[0] &= ~MGEF_CONDITION_OR_FLAG
        patched[previous_condition_index] = (
            b"CTDA",
            bytes(previous_condition),
        )
    return pack_record(record, form_id, patched)


def patch_spell_record(
    record: bytes,
    spec: dict,
    form_id: int,
) -> bytes:
    signature, _, _, subrecords = unpack_record(record)
    if signature != b"SPEL":
        raise ValueError(f"{spec['editor_id']} is not a SPEL record")

    found = set()
    effect_index = 0
    patched = []
    for tag, payload in subrecords:
        if tag == b"EDID":
            payload = spec["editor_id"].encode("ascii") + b"\0"
            found.add(tag)
        elif tag == b"FULL":
            payload = spec["name"].encode("utf-8") + b"\0"
            found.add(tag)
        elif tag == b"DESC":
            payload = spec["description"].encode("utf-8") + b"\0"
            found.add(tag)
        elif tag == b"SPIT":
            if len(payload) < 36:
                raise ValueError("Malformed SPIT subrecord")
            spell_data = bytearray(payload)
            struct.pack_into("<I", spell_data, 0, spec["cost"])
            if spec.get("manual_cost", False):
                flags = struct.unpack_from("<I", spell_data, 4)[0]
                struct.pack_into(
                    "<I",
                    spell_data,
                    4,
                    flags | MIND_TAKEOVER_MANUAL_COST_FLAG,
                )
            if "range" in spec:
                struct.pack_into("<f", spell_data, 28, spec["range"])
            payload = bytes(spell_data)
            found.add(tag)
        elif tag == b"EFIT":
            if effect_index >= len(spec["effects"]):
                raise ValueError(
                    f"Unexpected effect data in {spec['editor_id']}"
                )
            payload = struct.pack("<fII", *spec["effects"][effect_index])
            effect_index += 1
        patched.append((tag, payload))

    if not {b"EDID", b"FULL", b"DESC", b"SPIT"}.issubset(found):
        raise ValueError(f"Required SPEL fields missing for {spec['editor_id']}")
    if effect_index != len(spec["effects"]):
        raise ValueError(
            f"Effect count mismatch for {spec['editor_id']}: "
            f"expected {len(spec['effects'])}, found {effect_index}"
        )
    return pack_record(record, form_id, patched)


def spell_editor_id(record: bytes) -> str:
    signature, _, _, subrecords = unpack_record(record)
    if signature != b"SPEL":
        raise ValueError("Expected a SPEL record")
    for tag, payload in subrecords:
        if tag == b"EDID":
            return payload.rstrip(b"\0").decode("ascii")
    raise ValueError("SPEL record has no EDID")


def patch_header_count(header: bytes, added_records: int, next_object_id: int) -> bytes:
    signature, _, _, subrecords = unpack_record(header)
    if signature != b"TES4":
        raise ValueError("Expected TES4 header record")
    patched = []
    found_hedr = False
    for tag, payload in subrecords:
        if tag == b"HEDR":
            if len(payload) < 12:
                raise ValueError("Malformed HEDR subrecord")
            value = bytearray(payload)
            record_count = struct.unpack_from("<I", value, 4)[0]
            current_next_id = struct.unpack_from("<I", value, 8)[0]
            struct.pack_into("<I", value, 4, record_count + added_records)
            struct.pack_into(
                "<I", value, 8, max(current_next_id, next_object_id)
            )
            payload = bytes(value)
            found_hedr = True
        patched.append((tag, payload))
    if not found_hedr:
        raise ValueError("TES4 header has no HEDR subrecord")
    return pack_record(header, 0, patched)


def add_spell_ranks(plugin_path: Path) -> None:
    """Update rank-I text and append or refresh separate higher-rank spells."""
    plugin_data = plugin_path.read_bytes()
    position = 0
    rebuilt = bytearray()
    header_record = None
    spell_records: dict[int, bytes] = {}
    spell_group_header = None
    spell_group_data = None
    spell_group_insert_at = None
    magic_effect_group_found = False

    while position < len(plugin_data):
        signature = plugin_data[position:position + 4]
        if signature == b"GRUP":
            group_size = struct.unpack_from("<I", plugin_data, position + 4)[0]
            group_end = position + group_size
            if group_size < 24 or group_end > len(plugin_data):
                raise ValueError("Malformed GRUP in CreatorSpells.esp")
            label = plugin_data[position + 8:position + 12]
            if label == b"MGEF":
                if magic_effect_group_found:
                    raise ValueError("Duplicate MGEF groups")
                magic_effect_group_found = True
                group_header = bytearray(plugin_data[position:position + 24])
                group_records = []
                child_position = position + 24
                while child_position < group_end:
                    child_signature = plugin_data[
                        child_position:child_position + 4
                    ]
                    if child_signature == b"GRUP":
                        raise ValueError("Nested MGEF groups are not expected")
                    payload_size = struct.unpack_from(
                        "<I", plugin_data, child_position + 4
                    )[0]
                    record_end = child_position + 24 + payload_size
                    if record_end > group_end:
                        raise ValueError("Truncated MGEF record")
                    record = plugin_data[child_position:record_end]
                    signature, _, _, subrecords = unpack_record(record)
                    if signature != b"MGEF":
                        raise ValueError("Non-MGEF record in MGEF group")
                    editor_id = next(
                        (
                            payload.rstrip(b"\0").decode("ascii")
                            for tag, payload in subrecords
                            if tag == b"EDID"
                        ),
                        "",
                    )
                    if editor_id in MIND_TAKEOVER_EFFECT_EDITOR_IDS:
                        record = patch_mind_takeover_magic_effect(
                            record, editor_id
                        )
                    group_records.append(record)
                    child_position = record_end
                group_children = b"".join(group_records)
                struct.pack_into(
                    "<I", group_header, 4, 24 + len(group_children)
                )
                rebuilt.extend(bytes(group_header) + group_children)
            elif label == b"SPEL":
                if spell_group_data is not None:
                    raise ValueError("Duplicate SPEL groups")
                spell_group_header = bytearray(
                    plugin_data[position:position + 24]
                )
                spell_group_insert_at = len(rebuilt)
                child_position = position + 24
                while child_position < group_end:
                    if plugin_data[child_position:child_position + 4] == b"GRUP":
                        raise ValueError("Nested SPEL groups are not expected")
                    payload_size = struct.unpack_from(
                        "<I", plugin_data, child_position + 4
                    )[0]
                    record_end = child_position + 24 + payload_size
                    if record_end > group_end:
                        raise ValueError("Truncated SPEL record")
                    record = plugin_data[child_position:record_end]
                    form_id = struct.unpack_from("<I", record, 12)[0]
                    if form_id in spell_records:
                        raise ValueError(f"Duplicate SPEL FormID {form_id:08X}")
                    spell_records[form_id] = record
                    child_position = record_end
                spell_group_data = True
            else:
                rebuilt.extend(plugin_data[position:group_end])
            position = group_end
            continue

        if position + 24 > len(plugin_data):
            raise ValueError("Truncated top-level record")
        payload_size = struct.unpack_from("<I", plugin_data, position + 4)[0]
        record_end = position + 24 + payload_size
        if record_end > len(plugin_data):
            raise ValueError("Truncated top-level record payload")
        record = plugin_data[position:record_end]
        if signature == b"TES4":
            header_record = record
        else:
            rebuilt.extend(record)
        position = record_end

    if header_record is None or spell_group_header is None:
        raise ValueError("TES4 header or SPEL group was not found")
    if not magic_effect_group_found:
        raise ValueError("MGEF group was not found")

    id_to_record = {
        spell_editor_id(record): form_id
        for form_id, record in spell_records.items()
    }
    base_specs = {spec["editor_id"]: spec for spec in SPELLS}
    for editor_id, spec in base_specs.items():
        form_id = id_to_record.get(editor_id)
        if form_id is None:
            raise ValueError(f"Base spell {editor_id} was not found")
        rank_one_spec = dict(spec)
        rank_one_spec["effects"] = tuple(
            (magnitude, area, duration)
            for _, magnitude, area, duration in spec["effects"]
        )
        spell_records[form_id] = patch_spell_record(
            spell_records[form_id], rank_one_spec, form_id
        )

    id_to_record = {
        spell_editor_id(record): form_id
        for form_id, record in spell_records.items()
    }
    variant_count_added = 0
    rank_start = 0x01000819
    for index, variant in enumerate(RANK_VARIANTS):
        form_id = rank_start + index
        existing_id = id_to_record.get(variant["editor_id"])
        if existing_id is not None and existing_id != form_id:
            raise ValueError(
                f"{variant['editor_id']} has unexpected FormID {existing_id:08X}"
            )
        if form_id in spell_records and existing_id is None:
            raise ValueError(f"SPEL FormID {form_id:08X} is already in use")
        base_id = id_to_record.get(variant["base"])
        if base_id is None:
            raise ValueError(f"Base spell {variant['base']} was not found")
        variant_record = patch_spell_record(
            spell_records[base_id], variant, form_id
        )
        if existing_id is None:
            variant_count_added += 1
        spell_records[form_id] = variant_record
        id_to_record[variant["editor_id"]] = form_id

    group_children = b"".join(
        record for _, record in sorted(spell_records.items())
    )
    struct.pack_into("<I", spell_group_header, 4, 24 + len(group_children))
    spell_group = bytes(spell_group_header) + group_children

    next_object_id = 0x00000819 + len(RANK_VARIANTS)
    header_record = patch_header_count(
        header_record, variant_count_added, next_object_id
    )
    if spell_group_insert_at is None:
        raise ValueError("SPEL group insertion point was not found")
    non_header_data = bytes(rebuilt)
    final_data = (
        header_record
        + non_header_data[:spell_group_insert_at]
        + spell_group
        + non_header_data[spell_group_insert_at:]
    )
    plugin_path.write_bytes(final_data)


def build_spell(
    source: dict[int, Record],
    spec: dict,
    form_id: int,
    local_effect_ids: tuple[int, ...],
) -> bytes:
    record = source.get(spec["source"])
    if record is None or record[0] != b"SPEL":
        raise ValueError(f"Missing source spell {spec['source']:08X}")
    original_subrecords = record[2]
    effect_start = next(
        (
            index
            for index, (tag, _) in enumerate(original_subrecords)
            if tag == b"EFID"
        ),
        None,
    )
    if effect_start is None:
        raise ValueError(
            f"Source spell {spec['source']:08X} has no effect list"
        )

    leading = []
    found = set()
    for tag, payload in original_subrecords[:effect_start]:
        if tag == b"EDID":
            payload = spec["editor_id"].encode("ascii") + b"\0"
            found.add(tag)
        elif tag == b"FULL":
            payload = spec["name"].encode("utf-8") + b"\0"
            found.add(tag)
        elif tag == b"DESC":
            payload = spec["description"].encode("utf-8") + b"\0"
            found.add(tag)
        elif tag == b"SPIT":
            if len(payload) < 36:
                raise ValueError("Malformed SPIT subrecord")
            spell_data = bytearray(payload)
            struct.pack_into("<I", spell_data, 0, spec["cost"])
            if spec.get("manual_cost", False):
                flags = struct.unpack_from("<I", spell_data, 4)[0]
                struct.pack_into(
                    "<I",
                    spell_data,
                    4,
                    flags | MIND_TAKEOVER_MANUAL_COST_FLAG,
                )
            if "range" in spec:
                struct.pack_into("<f", spell_data, 28, spec["range"])
            payload = bytes(spell_data)
            found.add(tag)
        leading.append((tag, payload))

    if not {b"EDID", b"FULL", b"DESC", b"SPIT"}.issubset(found):
        raise ValueError(
            f"Required SPEL fields missing for {spec['editor_id']}"
        )

    subrecords = list(leading)
    for effect_id, (_, magnitude, area, duration) in zip(
        local_effect_ids, spec["effects"]
    ):
        subrecords.append((b"EFID", struct.pack("<I", effect_id)))
        subrecords.append(
            (b"EFIT", struct.pack("<fII", magnitude, area, duration))
        )

    payload = b"".join(
        make_subrecord(tag, value) for tag, value in subrecords
    )
    header = struct.pack(
        "<4sIIIIHH", b"SPEL", len(payload), 0, form_id, 0, 44, 0
    )
    return header + payload


def build_magic_effect(
    source: dict[int, Record],
    source_id: int,
    form_id: int,
    editor_id: str,
    sound_profile: str,
) -> bytes:
    record = source.get(source_id)
    if record is None or record[0] != b"MGEF":
        raise ValueError(f"Missing source magic effect {source_id:08X}")

    sounds = SOUND_PROFILES[sound_profile]
    sound_data = b"".join(
        struct.pack("<II", sound_type, sound_id)
        for sound_type, sound_id in sounds
    )
    subrecords = []
    found_edid = False
    found_sounds = False
    for tag, payload in record[2]:
        if tag == b"EDID":
            payload = editor_id.encode("ascii") + b"\0"
            found_edid = True
        elif tag == b"SNDD":
            payload = sound_data
            found_sounds = True
        subrecords.append((tag, payload))

    if not found_edid:
        raise ValueError(f"Source magic effect {source_id:08X} has no EDID")
    if not found_sounds:
        subrecords.append((b"SNDD", sound_data))

    payload = b"".join(make_subrecord(tag, value) for tag, value in subrecords)
    signature, flags, _ = record
    header = struct.pack(
        "<4sIIIIHH", signature, len(payload), flags, form_id, 0, 44, 0
    )
    return header + payload


def build_group(signature: bytes, records: list[bytes]) -> bytes:
    payload = b"".join(records)
    return struct.pack(
        "<4sI4sIHHHH", b"GRUP", 24 + len(payload), signature, 0, 0, 0, 0, 0
    ) + payload


def build_plugin(master: Path, output: Path) -> None:
    source_records = read_plugin(master)
    for spec in SPELLS:
        for effect_id, _, _, _ in spec["effects"]:
            effect = source_records.get(effect_id)
            if effect is None or effect[0] != b"MGEF":
                raise ValueError(
                    f"Missing source magic effect {effect_id:08X}"
                )
        for sound_profile in spec["sound_profiles"]:
            for _, sound_id in SOUND_PROFILES[sound_profile]:
                sound = source_records.get(sound_id)
                if sound is None or sound[0] != b"SNDR":
                    raise ValueError(f"Missing source sound {sound_id:08X}")
    spell_records = []
    effect_records = []
    next_local_id = 0x01000800 + len(SPELLS)
    for index, spec in enumerate(SPELLS):
        local_effect_ids = []
        sound_profiles = spec["sound_profiles"]
        if len(sound_profiles) != len(spec["effects"]):
            raise ValueError(
                f"Sound profile count does not match {spec['editor_id']}"
            )
        for effect_index, ((source_id, _, _, _), sound_profile) in enumerate(
            zip(spec["effects"], sound_profiles), start=1
        ):
            local_effect_ids.append(next_local_id)
            effect_records.append(
                build_magic_effect(
                    source_records,
                    source_id,
                    next_local_id,
                    f"{spec['editor_id']}Effect{effect_index:02d}",
                    sound_profile,
                )
            )
            next_local_id += 1
        spell_records.append(
            build_spell(
                source_records,
                spec,
                0x01000800 + index,
                tuple(local_effect_ids),
            )
        )
    record_count = len(spell_records) + len(effect_records)

    header_subrecords = [
        make_subrecord(
            b"HEDR",
            struct.pack(
                "<fII",
                1.71,
                record_count,
                0x00000800 + record_count,
            ),
        ),
        make_subrecord(b"CNAM", b"Codex\0"),
        make_subrecord(b"SNAM", "Czary klasy Stwórcy".encode() + b"\0"),
        make_subrecord(b"MAST", b"Skyrim.esm\0"),
        make_subrecord(b"DATA", b"\0" * 8),
    ]
    header_payload = b"".join(header_subrecords)
    header = struct.pack(
        "<4sIIIIHH", b"TES4", len(header_payload), 0, 0, 0, 44, 0
    ) + header_payload
    groups = build_group(b"MGEF", effect_records) + build_group(
        b"SPEL", spell_records
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(header + groups)
    add_spell_ranks(output)
    from build_new_spells import add_new_spells

    add_new_spells(source_records, output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--skyrim-data",
        type=Path,
        help="Skyrim SE Data folder containing Skyrim.esm",
    )
    parser.add_argument(
        "--plugin-only",
        action="store_true",
        help=(
            "Patch effects and ranks in an existing ESP without Skyrim.esm"
        ),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=(
            Path(__file__).resolve().parents[1] / "Data" / "CreatorSpells.esp"
        ),
    )
    args = parser.parse_args()
    if args.plugin_only:
        add_spell_ranks(args.output)
        print(
            f"Updated {len(SPELLS) + len(RANK_VARIANTS)} Creator spells "
            f"in {args.output}"
        )
        return
    if args.skyrim_data is None:
        parser.error("--skyrim-data is required unless --plugin-only is used")
    master = args.skyrim_data / "Skyrim.esm"
    if not master.is_file():
        raise SystemExit(f"Skyrim.esm not found in {args.skyrim_data}")
    build_plugin(master, args.output)
    print(
        f"Created {args.output} with "
        f"{len(SPELLS) + len(RANK_VARIANTS) + 2} spells and "
        f"{sum(len(spec['effects']) for spec in SPELLS) + 3} local magic effects"
    )


if __name__ == "__main__":
    main()
