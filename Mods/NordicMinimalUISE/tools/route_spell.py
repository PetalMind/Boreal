"""Build private, free, short-lived Guide records from Skyrim's Clairvoyance."""
from __future__ import annotations

import os
import struct
import zlib
from pathlib import Path
from typing import Callable

ROUTE_SPELL_ID = 0x01000806
ROUTE_EFFECT_ID = 0x01000807


def read_effect() -> list[tuple[bytes, bytes]]:
    data_dir = Path(os.environ.get(
        "SKYRIM_DATA",
        "/Volumes/Zewnetrzny/Gry windows/The Elder Scrolls V Skyrim Special Edition/Data",
    ))
    with (data_dir / "Skyrim.esm").open("rb") as source:
        while header := source.read(24):
            if len(header) != 24:
                raise ValueError("Truncated Skyrim.esm record header")
            signature, size, flags, form_id = struct.unpack_from("<4sIII", header)
            if signature == b"GRUP":
                if header[8:12] != b"MGEF":
                    source.seek(size - 24, 1)
                continue
            if signature != b"MGEF" or form_id != 0x2113F:
                source.seek(size, 1)
                continue
            payload = source.read(size)
            if len(payload) != size:
                raise ValueError("Truncated Clairvoyance magic effect")
            if flags & 0x40000:
                expanded_size = struct.unpack_from("<I", payload)[0]
                payload = zlib.decompress(payload[4:])
                if len(payload) != expanded_size:
                    raise ValueError("Invalid Clairvoyance expanded size")
            fields = []
            offset = 0
            while offset < len(payload):
                tag, length = struct.unpack_from("<4sH", payload, offset)
                offset += 6
                value = payload[offset:offset + length]
                if len(value) != length:
                    raise ValueError("Truncated Clairvoyance subrecord")
                fields.append((tag, value))
                offset += length
            return fields
    raise ValueError("Clairvoyance magic effect not found in Skyrim.esm")


def build_route_records(
    record: Callable[[bytes, int, bytes], bytes],
    subrecord: Callable[[bytes, bytes], bytes],
    zstring: Callable[[str], bytes],
    group: Callable[[bytes, bytes], bytes],
) -> bytes:
    fields = []
    found_data = False
    for tag, value in read_effect():
        if tag == b"EDID":
            value = zstring("NMUI_RouteGuideEffect")
        elif tag == b"FULL":
            value = zstring("Nawigacja")
        elif tag == b"DNAM":
            value = zstring("Wskazuje drogę do celu.")
        elif tag == b"SNDD":
            # Frequent route refreshes must not replay the casting sound.
            continue
        elif tag == b"DATA":
            if len(value) != 152 or struct.unpack_from("<I", value, 64)[0] != 25:
                raise ValueError("Unexpected Clairvoyance Guide data layout")
            data = bytearray(value)
            flags = struct.unpack_from("<I", data)[0]
            # Allow a timed effect and recasts, hide the helper from Active Effects.
            struct.pack_into("<If", data, 0, (flags & ~0x20200) | 0x8000, 0.0)
            struct.pack_into("<I", data, 12, 0xFFFFFFFF)  # No magic skill.
            struct.pack_into("<I", data, 80, 1)  # Fire and Forget.
            struct.pack_into("<I", data, 92, 0)  # No casting art.
            struct.pack_into("<f", data, 104, 0.0)  # No skill experience.
            value = bytes(data)
            found_data = True
        fields.append(subrecord(tag, value))
    if not found_data:
        raise ValueError("Clairvoyance magic effect has no DATA")
    effect = record(b"MGEF", ROUTE_EFFECT_ID, b"".join(fields))
    spell = record(b"SPEL", ROUTE_SPELL_ID, b"".join((
        subrecord(b"EDID", zstring("NMUI_RouteGuideSpell")),
        subrecord(b"OBND", bytes(12)),
        subrecord(b"FULL", zstring("Nawigacja")),
        subrecord(b"SPIT", struct.pack(
            "<IIIfIIffI", 0, 1, 0, 0.0, 1, 0, 0.0, 0.0, 0,
        )),  # Manual cost 0; Fire and Forget; Self.
        subrecord(b"EFID", struct.pack("<I", ROUTE_EFFECT_ID)),
        subrecord(b"EFIT", struct.pack("<fII", 0.0, 0, 2)),
    )))
    return group(b"MGEF", effect) + group(b"SPEL", spell)
