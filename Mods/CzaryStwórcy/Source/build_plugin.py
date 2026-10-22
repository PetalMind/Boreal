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
            "Ciągły, celowany promień. Wysysa 8 punktów zdrowia na sekundę "
            "i przekazuje je rzucającemu. Koszt bazowy 12 Magicki na sekundę."
        ),
        "cost": 12,
        "effects": ((0x000F5B57, 8.0, 0, 0),),
    },
    {
        "source": 0x0005AD5E,
        "editor_id": "CreatorBarrier01Spell",
        "name": "Bariera Stwórcy I",
        "description": (
            "10 sekund. Zwiększa pancerz o 167 punktów (około 20% redukcji "
            "obrażeń fizycznych) i odporność na magię o 20%."
        ),
        "cost": 35,
        "effects": ((0x00059B7C, 167.0, 0, 10), (0x00039E51, 20.0, 0, 10)),
    },
    {
        "source": 0x0005AD5E,
        "editor_id": "CreatorBarrier02Spell",
        "name": "Bariera Stwórcy II",
        "description": (
            "12 sekund. Zwiększa pancerz o 250 punktów (około 30% redukcji "
            "obrażeń fizycznych) i odporność na magię o 30%."
        ),
        "cost": 50,
        "effects": ((0x00059B7C, 250.0, 0, 12), (0x00039E51, 30.0, 0, 12)),
    },
    {
        "source": 0x0005AD5E,
        "editor_id": "CreatorBarrier03Spell",
        "name": "Bariera Stwórcy III",
        "description": (
            "15 sekund. Zwiększa pancerz o 333 punkty (około 40% redukcji "
            "obrażeń fizycznych) i odporność na magię o 40%."
        ),
        "cost": 65,
        "effects": ((0x00059B7C, 333.0, 0, 15), (0x00039E51, 40.0, 0, 15)),
    },
    {
        "source": 0x0002B96C,
        "editor_id": "CreatorImpulseSpell",
        "name": "Impuls Stwórcy",
        "description": (
            "Fala energii skierowana przed siebie. Zadaje 15 obrażeń i "
            "wywołuje niewielki odrzut oraz stagger w promieniu około 5 m."
        ),
        "cost": 45,
        "effects": ((0x00013E08, 0.75, 16, 0), (0x000EA075, 15.0, 16, 0)),
    },
    {
        "source": 0x0004DEEE,
        "editor_id": "CreatorMindTakeoverSpell",
        "name": "Przejęcie Jaźni",
        "description": (
            "Przez 20 sekund pojedynczy trafiony przeciwnik uznaje otoczenie "
            "za wrogie i atakuje inne istoty. Zaklęcie nie zadaje obrażeń."
        ),
        "cost": 45,
        "effects": (
            (0x0001EA78, 50.0, 0, 20),
            (0x0009E0BF, 50.0, 0, 20),
            (0x00026D7C, 50.0, 0, 20),
        ),
    },
    {
        "source": 0x0002B96C,
        "editor_id": "CreatorRealityWeakeningSpell",
        "name": "Osłabienie Rzeczywistości",
        "description": (
            "Spowalnia ruch celu o około 75% na 10 sekund. W pierwszej wersji "
            "wykorzystuje wbudowany efekt spowolnienia Skyrima."
        ),
        "cost": 40,
        "effects": ((0x000B729F, 75.0, 0, 10),),
    },
    {
        "source": 0x0002B96C,
        "editor_id": "CreatorDecaySpell",
        "name": "Zanik",
        "description": (
            "Czyste obrażenia magiczne w czasie: 6 punktów zdrowia na sekundę "
            "przez 5 sekund. Łącznie do 30 obrażeń."
        ),
        "cost": 40,
        "effects": ((0x000EA075, 6.0, 0, 5),),
    },
    {
        "source": 0x0005AD5E,
        "editor_id": "CreatorWillReflectionSpell",
        "name": "Odbicie Woli",
        "description": (
            "Przez 6 sekund zapewnia 20% odporności na magię i 20% odbicia "
            "obrażeń. Wbudowany efekt Skyrima odbija ciosy fizyczne; nie "
            "zwraca obrażeń magicznych."
        ),
        "cost": 40,
        "effects": ((0x00108A41, 20.0, 0, 6), (0x00039E51, 20.0, 0, 6)),
    },
)


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


def build_spell(source: dict[int, Record], spec: dict, form_id: int) -> bytes:
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
            if len(payload) < 4:
                raise ValueError("Malformed SPIT subrecord")
            payload = struct.pack("<I", spec["cost"]) + payload[4:]
            found.add(tag)
        leading.append((tag, payload))

    if not {b"EDID", b"FULL", b"DESC", b"SPIT"}.issubset(found):
        raise ValueError(
            f"Required SPEL fields missing for {spec['editor_id']}"
        )

    subrecords = list(leading)
    for effect_id, magnitude, area, duration in spec["effects"]:
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


def build_plugin(master: Path, output: Path) -> None:
    source_records = read_plugin(master)
    for spec in SPELLS:
        for effect_id, _, _, _ in spec["effects"]:
            effect = source_records.get(effect_id)
            if effect is None or effect[0] != b"MGEF":
                raise ValueError(
                    f"Missing source magic effect {effect_id:08X}"
                )
    built_records = [
        build_spell(source_records, spec, 0x01000800 + index)
        for index, spec in enumerate(SPELLS)
    ]

    header_subrecords = [
        make_subrecord(
            b"HEDR",
            struct.pack(
                "<fII",
                1.71,
                len(built_records),
                0x00000800 + len(built_records),
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
    group_payload = b"".join(built_records)
    group = struct.pack(
        "<4sI4sIHHHH", b"GRUP", 24 + len(group_payload), b"SPEL", 0, 0, 0, 0, 0
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(header + group + group_payload)


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
    print(f"Created {args.output} with {len(SPELLS)} spells")


if __name__ == "__main__":
    main()
