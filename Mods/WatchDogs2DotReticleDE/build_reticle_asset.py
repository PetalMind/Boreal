#!/usr/bin/env python3
"""Replace the cooked 128x128 DXT5 payload of SA:DE's default reticle.

The script intentionally edits only the inline texture payload. The cooked
UAsset header, export metadata, dimensions, format and trailing package data
remain byte-for-byte identical to the asset from the user's installation.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path


WIDTH = 128
HEIGHT = 128
PAYLOAD_OFFSET = 0x125
PAYLOAD_SIZE = 0x4000


def clamp(value: float, low: float = 0.0, high: float = 255.0) -> int:
    return max(int(low), min(int(high), int(round(value))))


def alpha_palette(a0: int, a1: int) -> list[int]:
    if a0 > a1:
        return [
            a0,
            a1,
            (6 * a0 + a1) // 7,
            (5 * a0 + 2 * a1) // 7,
            (4 * a0 + 3 * a1) // 7,
            (3 * a0 + 4 * a1) // 7,
            (2 * a0 + 5 * a1) // 7,
            (a0 + 6 * a1) // 7,
        ]
    return [
        a0,
        a1,
        (4 * a0 + a1) // 5,
        (3 * a0 + 2 * a1) // 5,
        (2 * a0 + 3 * a1) // 5,
        (a0 + 4 * a1) // 5,
        0,
        255,
    ]


def encode_alpha(values: list[int]) -> bytes:
    if max(values) == 0:
        return bytes(8)

    palette = alpha_palette(255, 0)
    indices = [min(range(8), key=lambda i: abs(palette[i] - value)) for value in values]
    packed = 0
    for index, value in enumerate(indices):
        packed |= value << (index * 3)
    return bytes((255, 0)) + packed.to_bytes(6, "little")


def encode_color(values: list[tuple[int, int, int, int]]) -> bytes:
    visible = any(alpha > 0 for _, _, _, alpha in values)
    if not visible:
        return bytes(8)

    # DXT1 four-colour mode: endpoint 0 is white, endpoint 1 is black. The
    # alpha plane controls visibility while the colour plane preserves the
    # subtle dark outline around the white centre.
    indices = [0 if red >= 128 else 1 for red, _, _, _ in values]
    packed = sum(index << (position * 2) for position, index in enumerate(indices))
    return bytes((255, 255, 0, 0)) + packed.to_bytes(4, "little")


def pixel(x: int, y: int) -> tuple[int, int, int, int]:
    # A small white dot with a soft dark edge, centred on the same canvas as
    # the original reticle. The texture remains transparent everywhere else.
    distance = math.hypot(x - 63.5, y - 63.5)
    outer = max(0.0, min(1.0, (3.0 - distance) / 0.85))
    inner = max(0.0, min(1.0, (1.75 - distance) / 0.55))
    alpha = clamp(outer * 255.0)
    if alpha == 0:
        return (0, 0, 0, 0)
    if inner > 0:
        return (255, 255, 255, alpha)
    return (0, 0, 0, alpha)


def encode_texture() -> bytes:
    output = bytearray()
    for block_y in range(0, HEIGHT, 4):
        for block_x in range(0, WIDTH, 4):
            pixels = [pixel(block_x + x, block_y + y) for y in range(4) for x in range(4)]
            output.extend(encode_alpha([alpha for _, _, _, alpha in pixels]))
            output.extend(encode_color(pixels))
    if len(output) != PAYLOAD_SIZE:
        raise RuntimeError(f"Unexpected BC3 payload size: {len(output):#x}")
    return bytes(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    source = args.source.read_bytes()
    expected_size = PAYLOAD_OFFSET + PAYLOAD_SIZE + 16
    if len(source) != expected_size:
        raise RuntimeError(
            f"Unexpected T_crosshair_BC.uexp size: {len(source)}; expected {expected_size}"
        )

    output = bytearray(source)
    output[PAYLOAD_OFFSET : PAYLOAD_OFFSET + PAYLOAD_SIZE] = encode_texture()
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    args.destination.write_bytes(output)


if __name__ == "__main__":
    main()
