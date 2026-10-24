#!/usr/bin/env python3
"""Build the Creator spell plugin from the user's Skyrim SE master file."""

from __future__ import annotations

import argparse
import struct
import zlib
from pathlib import Path


SPELLS = (
    {
        "source": 0x0008D5BF,
        "editor_id": "CreatorAbsorptionSpell",
        "name": "Pochłonięcie Stwórcy",
        "description": (
            "Czarno-czerwony promień oplata ofiarę i wyciąga z niej życiową "
            "esencję, którą Stwórca przywraca własnemu ciału. Wysysa i "
            "przywraca po 8 punktów zdrowia na sekundę; kosztuje 12 Magicki "
            "na sekundę. Zasięg około 30 m."
        ),
        "cost": 12,
        "range": 2100.0,
        "effects": ((0x000F5B57, 8.0, 0, 0),),
        "sound_profiles": ("absorption",),
    },
    {
        "source": 0x0005AD5E,
        "editor_id": "CreatorBarrier01Spell",
        "name": "Bariera Stwórcy I",
        "description": (
            "Pierwszy splot mocy Stwórcy przyjmuje część siły ciosów i "
            "zakłóca wrogą magię. Przez 10 sekund dodaje 167 punktów "
            "pancerza i 20% odporności na magię."
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
            "Wzmocniony splot Stwórcy osłania ciało i tłumi napływającą "
            "magię. Przez 12 sekund dodaje 250 punktów pancerza i 30% "
            "odporności na magię."
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
            "Wielowarstwowa pieczęć Stwórcy otacza ciało i rozprasza "
            "uderzenia oraz wrogą magię. Przez 15 sekund dodaje 333 punkty "
            "pancerza i 40% odporności na magię."
        ),
        "cost": 65,
        "effects": ((0x00059B7C, 333.0, 0, 15), (0x00039E51, 40.0, 0, 15)),
        "sound_profiles": ("alteration", "silent"),
    },
    {
        "source": 0x0002B96C,
        "editor_id": "CreatorImpulseSpell",
        "name": "Impuls Stwórcy",
        "description": (
            "Stwórca uwalnia nagromadzoną energię jako falę, która rozrywa "
            "rytm walki i odrzuca napastników. Zadaje 15 obrażeń oraz "
            "zachwiewa celami w promieniu około 5 m."
        ),
        "cost": 45,
        "effects": ((0x00013E08, 0.75, 16, 0), (0x000EA075, 15.0, 16, 0)),
        "sound_profiles": ("impulse", "silent"),
    },
    {
        "source": 0x0004DEEE,
        "editor_id": "CreatorMindTakeoverSpell",
        "name": "Przejęcie Jaźni",
        "description": (
            "Stwórca przepisuje obraz rzeczywistości w umyśle ofiary, "
            "sprawiając, że pobliskie istoty jawią się jej jako wrogowie. "
            "Trafiony przeciwnik walczy z otoczeniem przez 20 sekund. Czar "
            "nie zadaje obrażeń."
        ),
        "cost": 45,
        "effects": (
            (0x0001EA78, 50.0, 0, 20),
            (0x0009E0BF, 50.0, 0, 20),
            (0x00026D7C, 50.0, 0, 20),
        ),
        "sound_profiles": ("alteration_hit", "silent", "silent"),
    },
    {
        "source": 0x0002B96C,
        "editor_id": "CreatorRealityWeakeningSpell",
        "name": "Osłabienie Rzeczywistości",
        "description": (
            "Stwórca rozstraja rytm celu względem świata, przez co każdy "
            "ruch staje się ciężki i opóźniony. Spowalnia ruch o około 75% "
            "na 10 sekund."
        ),
        "cost": 40,
        "effects": ((0x000B729F, 75.0, 0, 10),),
        "sound_profiles": ("alteration_hit",),
    },
    {
        "source": 0x0002B96C,
        "editor_id": "CreatorDecaySpell",
        "name": "Zanik",
        "description": (
            "Dotknięta mocą Stwórcy istota zaczyna rozpadać się od wewnątrz, "
            "jakby pękał splot podtrzymujący jej istnienie. Zadaje 6 "
            "obrażeń zdrowia na sekundę przez 5 sekund."
        ),
        "cost": 40,
        "effects": ((0x000EA075, 6.0, 0, 5),),
        "sound_profiles": ("alteration_hit",),
    },
    {
        "source": 0x0005AD5E,
        "editor_id": "CreatorWillReflectionSpell",
        "name": "Odbicie Woli",
        "description": (
            "Stwórca oplata się splotem, który odsyła siłę fizycznych ciosów "
            "ku napastnikom i tłumi część obcej magii. Przez 6 sekund "
            "zapewnia 20% odporności na magię i 20% odbicia obrażeń "
            "fizycznych."
        ),
        "cost": 40,
        "effects": ((0x00108A41, 20.0, 0, 6), (0x00039E51, 20.0, 0, 6)),
        "sound_profiles": ("alteration", "silent"),
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
        make_subrecord(b"SNAM", "Czary klasy Stwórcy".encode("utf-8") + b"\0"),
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--skyrim-data",
        type=Path,
        required=True,
        help="Skyrim SE Data folder containing Skyrim.esm",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=(
            Path(__file__).resolve().parents[1] / "Data" / "CreatorSpells.esp"
        ),
    )
    args = parser.parse_args()
    master = args.skyrim_data / "Skyrim.esm"
    if not master.is_file():
        raise SystemExit(f"Skyrim.esm not found in {args.skyrim_data}")
    build_plugin(master, args.output)
    print(
        f"Created {args.output} with {len(SPELLS)} spells and "
        f"{sum(len(spec['effects']) for spec in SPELLS)} local magic effects"
    )


if __name__ == "__main__":
    main()
