"""Append the two scripted spells without changing existing spell FormIDs."""

from __future__ import annotations

import struct
from pathlib import Path

from build_plugin import Record, build_group, build_spell, make_subrecord, read_plugin

INCINERATION = 0x01000825
INTERNAL_EXPLOSION = 0x01000826
FIRE_EFFECT = 0x01000827
FEAR_EFFECT = 0x01000828
TIMER_EFFECT = 0x01000829
FIRE_PROJECTILE = 0x0100082A
CHARRED_SHADER = 0x0100082B
BLOOD_VISUAL = 0x0100082C
VIOLET_LIGHT = 0x0100082D
VIOLET_HIT_SHADER = 0x0100082E
VIOLET_HAND_ART = 0x0100082F
RADIAL_BLOOD_ART = 0x01000830
RED_AURA = 0x01000831
VIOLET_IMPACT_SET = 0x01000832
IMPACT_SOURCES = (0x3172C, 0x26114, 0x3E079, 0x3E078, 0xF3A92, 0x3E077)
IMPACT_IDS = {source: 0x01000833 + i for i, source in enumerate(IMPACT_SOURCES)}


def record(signature: bytes, form_id: int, fields: list[tuple[bytes, bytes]]) -> bytes:
    payload = b"".join(make_subrecord(tag, value) for tag, value in fields)
    return struct.pack("<4sIIIIHH", signature, len(payload), 0, form_id, 0, 44, 0) + payload


def string(value: str) -> bytes:
    return value.encode("utf-8") + b"\0"


def vmad(name: str, properties: dict[str, int]) -> bytes:
    def counted(value: str) -> bytes:
        data = value.encode("ascii")
        return struct.pack("<H", len(data)) + data

    result = struct.pack("<HHH", 5, 2, 1)
    result += counted(name) + struct.pack("<BH", 0, len(properties))
    for key, form_id in properties.items():
        result += counted(key) + struct.pack("<BBHhI", 1, 1, 0, -1, form_id)
    return result


def magic_effect(
    source: dict[int, Record], source_id: int, form_id: int, name: str,
    *, integers: dict[int, int], floats: dict[int, float] | None = None,
    script: bytes | None = None,
) -> bytes:
    fields = []
    if script is not None:
        fields.append((b"VMAD", script))
    for tag, value in source[source_id][2]:
        # These are new effects: vanilla perk/race gates and scripts do not apply.
        if tag in (b"VMAD", b"CTDA", b"CIS1", b"CIS2", b"ESCE"):
            continue
        if tag == b"EDID":
            value = string(name)
        elif tag in (b"FULL", b"DNAM"):
            value = b"\0"
        elif tag == b"DATA":
            data = bytearray(value)
            for offset, number in integers.items():
                struct.pack_into("<I", data, offset, number & 0xFFFFFFFF)
            for offset, float_number in (floats or {}).items():
                struct.pack_into("<f", data, offset, float_number)
            struct.pack_into("<H", data, 20, 0)  # No counter effects.
            value = bytes(data)
        fields.append((tag, value))
    # EDID precedes VMAD in Skyrim records.
    fields.sort(key=lambda field: 0 if field[0] == b"EDID" else 1)
    return record(b"MGEF", form_id, fields)


def red_aura_shader() -> bytes:
    data = bytearray(400)
    # A translucent red membrane with a stronger red rim, preserving the actor.
    for offset, value in {4: 5, 8: 1, 12: 3, 92: 6, 384: 0x408}.items():
        struct.pack_into("<I", data, offset, value)
    for offset in (16, 312, 316):
        data[offset:offset + 4] = bytes((220, 0, 0, 0))
    data[56:60] = bytes((255, 8, 8, 0))
    for offset, float_value in {
        20: 0.2, 24: 1.0, 28: 0.2, 32: 0.2, 84: 0.2,
        52: 2.0, 60: 0.2, 64: 1.0, 68: 0.2, 72: 0.9, 88: 0.9,
        320: 1.0, 324: 1.0, 328: 1.0, 336: 0.5, 340: 1.0,
        344: 1.0, 388: 2.0, 392: 2.0,
    }.items():
        struct.pack_into("<f", data, offset, float_value)
    return record(b"EFSH", RED_AURA, [
        (b"EDID", string("CreatorInternalExplosionRedAura")),
        (b"ICON", string(r"Effects\VaporTile01.dds")),
        (b"ICO2", b"\0"), (b"NAM7", b"\0"), (b"NAM8", b"\0"), (b"NAM9", b"\0"),
        (b"DATA", bytes(data)),
    ])


def clone_visual(
    source: dict[int, Record], source_id: int, form_id: int,
    name: str, replacements: dict[bytes, bytes],
) -> bytes:
    fields = [(b"EDID", string(name))]
    fields.extend((tag, replacements.get(tag, value)) for tag, value in source[source_id][2]
                  if tag not in (b"EDID", b"MODT"))
    return record(source[source_id][0], form_id, fields)


def add_new_spells(source: dict[int, Record], output: Path) -> None:
    existing = read_plugin(output)
    ids = range(INCINERATION, max(IMPACT_IDS.values()) + 1)
    if any(form_id in existing for form_id in ids):
        raise ValueError("New spell FormIDs already exist; rebuild from Skyrim.esm")
    records: dict[bytes, list[bytes]] = {}
    for form_id, (signature, _, fields) in existing.items():
        if signature != b"TES4":
            records.setdefault(signature, []).append(record(signature, form_id, fields))

    fields = []
    for tag, value in source[0x12FCF][2]:
        if tag == b"EDID":
            value = string("CreatorIncinerationProjectile")
        elif tag == b"MODL":
            value = string(r"CreatorSpells\Incineration.nif")
        elif tag == b"MODT":
            continue  # Texture hashes from the old model are no longer valid.
        elif tag == b"DATA":
            data = bytearray(value)
            struct.pack_into("<f", data, 12, 2100.0)
            struct.pack_into("<II", data, 16, VIOLET_LIGHT, VIOLET_LIGHT)
            value = bytes(data)
        fields.append((tag, value))
    records.setdefault(b"PROJ", []).append(record(b"PROJ", FIRE_PROJECTILE, fields))
    light_data = bytearray(dict(source[0x140EC][2])[b"DATA"])
    light_data[8:12] = bytes((145, 15, 255, 0))
    records.setdefault(b"LIGH", []).append(clone_visual(
        source, 0x140EC, VIOLET_LIGHT, "CreatorIncinerationLight", {b"DATA": bytes(light_data)},
    ))
    palette = string(r"CreatorSpells\IncinerationGradient.dds")
    records.setdefault(b"EFSH", []).extend([
        clone_visual(source, 0xD22FB, CHARRED_SHADER, "CreatorCharredBodyShader",
                     {b"NAM8": palette, b"NAM9": palette}),
        clone_visual(source, 0x1B212, VIOLET_HIT_SHADER, "CreatorIncinerationHitShader",
                     {b"NAM8": palette, b"NAM9": palette}),
        red_aura_shader(),
    ])
    records.setdefault(b"ARTO", []).extend([
        clone_visual(source, 0x1B211, VIOLET_HAND_ART, "CreatorIncinerationHands",
                     {b"MODL": string(r"CreatorSpells\IncinerationHands.nif")}),
        clone_visual(source, 0xA6EF5, RADIAL_BLOOD_ART, "CreatorInternalExplosionRadialArt",
                     {b"MODL": string(r"CreatorSpells\InternalExplosion.nif")}),
    ])
    records.setdefault(b"IPCT", []).extend(
        clone_visual(source, source_id, form_id, f"CreatorIncinerationImpact{index:02d}",
                     {b"MODL": string(r"CreatorSpells\IncinerationImpact.nif")})
        for index, (source_id, form_id) in enumerate(IMPACT_IDS.items())
    )
    impact_fields = [(b"EDID", string("CreatorIncinerationImpactSet"))]
    for tag, value in source[0x26113][2]:
        if tag == b"EDID":
            continue
        if tag == b"PNAM":
            material, impact = struct.unpack("<II", value)
            value = struct.pack("<II", material, IMPACT_IDS[impact])
        impact_fields.append((tag, value))
    records.setdefault(b"IPDS", []).append(record(b"IPDS", VIOLET_IMPACT_SET, impact_fields))
    records.setdefault(b"RFCT", []).append(record(b"RFCT", BLOOD_VISUAL, [
        (b"EDID", string("CreatorInternalExplosionBlood")),
        (b"DATA", struct.pack("<III", RADIAL_BLOOD_ART, 0, 4)),
    ]))

    records[b"MGEF"].extend([
        magic_effect(source, 0x13CA9, FIRE_EFFECT, "CreatorIncinerationEffect",
                     integers={0: 0x10001805, 24: VIOLET_LIGHT, 32: VIOLET_HIT_SHADER,
                               72: FIRE_PROJECTILE, 92: VIOLET_HAND_ART, 100: VIOLET_IMPACT_SET},
                     floats={28: 0.0, 52: 0.0, 56: 0.0},
                     script=vmad("CreatorIncineration", {
                         "CharredBody": CHARRED_SHADER, "EmptySoulGem": 0x2E500, "AshPile": 0x1B,
                     })),
        magic_effect(source, 0x1EA77, FEAR_EFFECT, "CreatorInternalExplosionFear",
                     integers={0: 0x21803, 16: -1, 32: 0, 96: 0}, floats={104: 0.0}),
        magic_effect(source, 0x1EA77, TIMER_EFFECT, "CreatorInternalExplosionTimer",
                     integers={0: 0x28C01, 12: 20, 16: -1, 32: 0, 64: 1,
                               68: -1, 92: 0, 96: 0}, floats={104: 0.0},
                     script=vmad("CreatorInternalExplosion", {
                         "BloodBurst": BLOOD_VISUAL, "BurstSound": 0xDAB82, "RedAura": RED_AURA,
                     })),
    ])
    specs = [
        (INCINERATION, (FIRE_EFFECT,), {
            "source": 0x12FCD, "editor_id": "CreatorIncinerationSpell",
            "name": "Spopielenie", "description": "Fioletowy ogień zadaje 25 pkt obrażeń na sekundę. Po śmierci cel obraca się w pył, a dusza trafia do kamienia duszy.",
            "cost": 30, "manual_cost": True, "range": 2100.0,
            "effects": ((0x13CA9, 25.0, 0, 1),),
        }),
        (INTERNAL_EXPLOSION, (FEAR_EFFECT, TIMER_EFFECT), {
            "source": 0x4DEEA, "editor_id": "CreatorInternalExplosionSpell",
            "name": "Wewnętrzna eksplozja", "description": "Cel otoczony czerwoną aurą ucieka przez 5 s, po czym ginie w krwawym wybuchu dookoła ciała. Aura trwa do śmierci. Nie zabija postaci niezbędnych dla fabuły.",
            "cost": 100, "manual_cost": True,
            "effects": ((0x1EA77, 1000000.0, 0, 5), (0x1EA77, 0.0, 0, 0x7FFFFFFF)),
        }),
    ]
    for form_id, effects, spec in specs:
        records[b"SPEL"].append(build_spell(source, spec, form_id, effects))
    header_fields = []
    for tag, value in existing[0][2]:
        if tag == b"HEDR":
            value = struct.pack("<fII", 1.71, sum(map(len, records.values())),
                                (max(IMPACT_IDS.values()) & 0xFFFFFF) + 1)
        header_fields.append((tag, value))
    output.write_bytes(record(b"TES4", 0, header_fields) + b"".join(
        build_group(signature, children) for signature, children in records.items()
    ))
