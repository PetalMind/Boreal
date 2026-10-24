#!/usr/bin/env python3
"""Create the two exported horse-marker sprites required by CoMAP."""

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

from PIL import Image, ImageDraw


SIZE = 128
TWIPS_PER_PIXEL = 20
NAME_DISCOVERED = "HorseWhistleSE_HorseMarker"
NAME_UNDISCOVERED = "HorseWhistleSE_HorseMarkerUndiscovered"


class BitWriter:
    def __init__(self) -> None:
        self.bits: list[int] = []

    def write(self, value: int, count: int) -> None:
        for shift in range(count - 1, -1, -1):
            self.bits.append((value >> shift) & 1)

    def write_signed(self, value: int, count: int) -> None:
        self.write(value & ((1 << count) - 1), count)

    def bytes(self) -> bytes:
        padded = self.bits + [0] * ((-len(self.bits)) % 8)
        return bytes(
            sum(padded[offset + bit] << (7 - bit) for bit in range(8))
            for offset in range(0, len(padded), 8)
        )


def signed_bits(value: int) -> int:
    return max(2, value.bit_length() + 1 if value >= 0 else (~value).bit_length() + 1)


def rect(x_min: int, y_min: int, x_max: int, y_max: int) -> bytes:
    width = max(signed_bits(value) for value in (x_min, y_min, x_max, y_max))
    bits = BitWriter()
    bits.write(width, 5)
    for value in (x_min, x_max, y_min, y_max):
        bits.write_signed(value, width)
    return bits.bytes()


def matrix_identity() -> bytes:
    bits = BitWriter()
    bits.write(0, 1)  # HasScale
    bits.write(0, 1)  # HasRotate
    bits.write(0, 5)  # NTranslateBits
    return bits.bytes()


def matrix_bitmap_scale() -> bytes:
    scale = TWIPS_PER_PIXEL * 65536
    width = signed_bits(scale)
    bits = BitWriter()
    bits.write(1, 1)  # HasScale
    bits.write(width, 5)
    bits.write_signed(scale, width)
    bits.write_signed(scale, width)
    bits.write(0, 1)  # HasRotate
    bits.write(0, 5)  # NTranslateBits
    return bits.bytes()


def build_horse_bitmap(color: tuple[int, int, int, int]) -> bytes:
    scale = 4
    image = Image.new("RGBA", (SIZE * scale, SIZE * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    fill = color
    stroke = (25, 24, 23, 255)
    outline = max(1, scale)

    def xy(points: list[tuple[int, int]]) -> list[tuple[int, int]]:
        return [(x * scale, y * scale) for x, y in points]

    # Draw rear limbs and tail first, then the body, neck, and head.
    limbs = [
        [(39, 49), (46, 49), (43, 68), (46, 83), (43, 87), (36, 86), (36, 69)],
        [(30, 47), (36, 48), (34, 67), (35, 82), (32, 86), (25, 84), (27, 66)],
        [(70, 47), (76, 47), (77, 68), (81, 82), (78, 86), (71, 85), (70, 68)],
        [(79, 45), (85, 47), (86, 67), (91, 82), (88, 86), (81, 84), (80, 66)],
    ]
    for polygon in limbs:
        draw.polygon(xy(polygon), fill=fill, outline=stroke, width=outline)
    draw.line(xy([(31, 45), (24, 40), (20, 34), (17, 30), (18, 38), (22, 46), (31, 51)]), fill=stroke, width=outline + 2, joint="curve")
    draw.line(xy([(31, 45), (24, 40), (20, 34), (17, 30), (18, 38), (22, 46), (31, 51)]), fill=fill, width=outline, joint="curve")
    draw.ellipse((30 * scale, 34 * scale, 86 * scale, 60 * scale), fill=fill, outline=stroke, width=outline)
    draw.polygon(xy([(65, 44), (73, 22), (81, 14), (91, 15), (97, 23), (93, 33), (87, 49), (78, 54)]), fill=fill, outline=stroke, width=outline)
    draw.polygon(xy([(80, 17), (77, 9), (80, 4), (85, 12), (93, 9), (102, 12), (107, 17), (103, 22), (95, 24), (87, 21)]), fill=fill, outline=stroke, width=outline)
    draw.polygon(xy([(82, 13), (80, 3), (85, 9)]), fill=fill, outline=stroke, width=outline)
    draw.polygon(xy([(90, 20), (86, 29), (80, 35), (78, 30), (83, 20)]), fill=stroke)
    draw.ellipse((99 * scale, 13 * scale, 101 * scale, 15 * scale), fill=stroke)

    # A narrow outline keeps the silhouette visible over pale map textures.
    return image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).tobytes()


def tag(code: int, payload: bytes) -> bytes:
    if len(payload) < 63:
        header = struct.pack("<H", (code << 6) | len(payload))
    else:
        header = struct.pack("<HI", (code << 6) | 63, len(payload))
    return header + payload


def define_bitmap(character_id: int, rgba: bytes) -> bytes:
    argb = bytearray()
    for offset in range(0, len(rgba), 4):
        red, green, blue, alpha = rgba[offset:offset + 4]
        argb.extend((alpha, red, green, blue))
    payload = struct.pack("<HBHH", character_id, 5, SIZE, SIZE) + zlib.compress(bytes(argb), 9)
    return tag(36, payload)  # DefineBitsLossless2


def define_shape(character_id: int, bitmap_id: int) -> bytes:
    bounds = rect(0, 0, SIZE * TWIPS_PER_PIXEL, SIZE * TWIPS_PER_PIXEL)
    fill_style = b"\x01\x43" + struct.pack("<H", bitmap_id) + matrix_bitmap_scale()
    shape_bits = BitWriter()

    def move_to(x: int, y: int) -> None:
        shape_bits.write(0, 1)
        shape_bits.write(0, 1)  # StateNewStyles
        shape_bits.write(0, 1)  # StateLineStyle
        shape_bits.write(1, 1)  # StateFillStyle1
        shape_bits.write(0, 1)  # StateFillStyle0
        shape_bits.write(1, 1)  # StateMoveTo
        shape_bits.write(14, 5)
        shape_bits.write_signed(x * TWIPS_PER_PIXEL, 14)
        shape_bits.write_signed(y * TWIPS_PER_PIXEL, 14)
        shape_bits.write(1, 1)  # FillStyle1

    def edge(dx: int, dy: int) -> None:
        dx *= TWIPS_PER_PIXEL
        dy *= TWIPS_PER_PIXEL
        width = max(signed_bits(dx), signed_bits(dy))
        shape_bits.write(1, 1)  # TypeFlag
        shape_bits.write(1, 1)  # StraightFlag
        shape_bits.write(width - 2, 4)
        shape_bits.write(1, 1)  # GeneralLineFlag
        shape_bits.write_signed(dx, width)
        shape_bits.write_signed(dy, width)

    # The transparent lossless bitmap contains the actual silhouette; a full
    # canvas shape keeps the same pixels for both exported marker states.
    for polygon in [[(0, 0), (SIZE, 0), (SIZE, SIZE), (0, SIZE)]]:
        move_to(*polygon[0])
        for start, end in zip(polygon, polygon[1:] + polygon[:1]):
            edge(end[0] - start[0], end[1] - start[1])

    shape_bits.write(0, 6)  # EndShapeRecord
    shape_with_style = fill_style + b"\x00" + b"\x10" + shape_bits.bytes()
    payload = struct.pack("<H", character_id) + bounds + shape_with_style
    return tag(32, payload)  # DefineShape3


def define_sprite(character_id: int, shape_id: int) -> bytes:
    place = b"\x06" + struct.pack("<HH", 1, shape_id) + matrix_identity()
    timeline = tag(26, place) + tag(1, b"") + tag(0, b"")
    return tag(39, struct.pack("<HH", character_id, 1) + timeline)


def export_assets(entries: list[tuple[int, str]]) -> bytes:
    payload = struct.pack("<H", len(entries))
    for character_id, name in entries:
        payload += struct.pack("<H", character_id) + name.encode("ascii") + b"\0"
    return tag(56, payload)


def build_swf() -> bytes:
    discovered = build_horse_bitmap((238, 229, 201, 255))
    undiscovered = build_horse_bitmap((133, 132, 128, 255))
    tags = b"".join((
        define_bitmap(1, discovered),
        define_bitmap(2, undiscovered),
        define_shape(3, 1),
        define_shape(4, 2),
        define_sprite(5, 3),
        define_sprite(6, 4),
        export_assets([(5, NAME_DISCOVERED), (6, NAME_UNDISCOVERED)]),
        tag(1, b""),
        tag(0, b""),
    ))
    body = rect(0, 0, SIZE * TWIPS_PER_PIXEL, SIZE * TWIPS_PER_PIXEL)
    body += struct.pack("<HH", 24 * 256, 1) + tags
    return b"FWS" + bytes((10,)) + struct.pack("<I", len(body) + 8) + body


def main() -> None:
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(build_swf())


if __name__ == "__main__":
    main()
