"""Create the incineration palette and recolor a local Skyrim flame mesh."""

from __future__ import annotations

import struct
from pathlib import Path

PALETTE = b"textures\\CreatorSpells\\IncinerationGradient.dds"


def extract_mesh(archive: Path, wanted: str) -> bytes | None:
    """Read one file from a Skyrim SE BSA without extracting the archive."""
    with archive.open("rb") as stream:
        magic, version, offset, flags, folders, files, _, _, _ = struct.unpack(
            "<9I", stream.read(36)
        )
        if magic != 0x00415342 or version != 105:
            raise ValueError(f"Unsupported Skyrim SE BSA: {archive}")
        stream.seek(offset)
        headers = [stream.read(24) for _ in range(folders)]
        entries = []
        for header in headers:
            count = struct.unpack_from("<I", header, 8)[0]
            length = stream.read(1)[0]
            folder = stream.read(length).rstrip(b"\0").decode("utf-8")
            for _ in range(count):
                _, size, address = struct.unpack("<QII", stream.read(16))
                entries.append((folder, size, address))
        if len(entries) != files:
            raise ValueError("Invalid BSA file count")
        for folder, size, address in entries:
            name = bytearray()
            while True:
                char = stream.read(1)
                if not char:
                    raise ValueError("Truncated BSA filename")
                if char == b"\0":
                    break
                name.extend(char)
            if f"{folder}\\{name.decode('utf-8')}".lower() != wanted.lower():
                continue
            stream.seek(address)
            data = stream.read(size & 0x3FFFFFFF)
            if flags & 0x100:
                data = data[1 + data[0]:]
            if bool(flags & 4) != bool(size & 0x40000000):
                import lz4.frame

                expected = struct.unpack_from("<I", data)[0]
                data = lz4.frame.decompress(data[4:])
                if len(data) != expected:
                    raise ValueError("BSA expanded size mismatch")
            return data
    return None


def recolor_flames(data: bytes) -> bytes:
    """Replace the three flame palettes, preserving NIF blocks and animation."""
    start = data.index(b"\n") + 1
    version, endian, user, count, bethesda = struct.unpack_from("<IBIII", data, start)
    if (version, endian, user, bethesda) != (0x14020007, 1, 12, 100):
        raise ValueError("Expected a Skyrim SE NIF")
    position = start + 17
    for _ in range(3):
        position += 1 + data[position]
    type_count = struct.unpack_from("<H", data, position)[0]
    position += 2
    types = []
    for _ in range(type_count):
        length = struct.unpack_from("<I", data, position)[0]
        position += 4
        types.append(data[position:position + length].decode("ascii"))
        position += length
    indexes = struct.unpack_from(f"<{count}H", data, position)
    position += count * 2
    size_table = position
    sizes = struct.unpack_from(f"<{count}I", data, position)
    position += count * 4
    strings, _ = struct.unpack_from("<II", data, position)
    position += 8
    for _ in range(strings):
        length = struct.unpack_from("<I", data, position)[0]
        position += 4 + length
    groups = struct.unpack_from("<I", data, position)[0]
    position += 4 + groups * 4
    header = bytearray(data[:position])
    blocks = []
    changed = 0
    for index, (type_index, size) in enumerate(zip(indexes, sizes)):
        block = data[position:position + size]
        position += size
        if types[type_index] == "BSEffectShaderProperty":
            for old in (
                b"textures\\effects\\gradients\\GradFlame01.dds",
                b"textures\\effects\\gradients\\GradFireCloak01.dds",
            ):
                old_field = struct.pack("<I", len(old)) + old
                if old_field in block:
                    block = block.replace(old_field, struct.pack("<I", len(PALETTE)) + PALETTE)
                    changed += 1
        struct.pack_into("<I", header, size_table + 4 * index, len(block))
        blocks.append(block)
    if changed != 3 or position + 8 != len(data):
        raise ValueError("Unexpected vanilla flame mesh layout")
    return bytes(header) + b"".join(blocks) + data[position:]


def gradient_dds() -> bytes:
    """An uncompressed RGBA palette: violet edges, orange flame, warm core."""
    width, height = 256, 16
    header = struct.pack("<7I", 124, 0x100F, height, width, width * 4, 0, 0)
    header += bytes(44)
    header += struct.pack("<8I", 32, 0x41, 0, 32, 0xFF, 0xFF00, 0xFF0000, 0xFF000000)
    header += struct.pack("<5I", 0x1000, 0, 0, 0, 0)
    stops = ((0, (0, 0, 0)), (40, (45, 0, 100)), (115, (155, 15, 255)),
             (165, (255, 65, 10)), (220, (255, 160, 25)), (255, (255, 245, 180)))
    row = bytearray()
    for x in range(width):
        for (left, a), (right, b) in zip(stops, stops[1:]):
            if left <= x <= right:
                ratio = (x - left) / (right - left)
                row.extend(round(v + (w - v) * ratio) for v, w in zip(a, b))
                row.append(255)
                break
    return b"DDS " + header + bytes(row) * height


def build_assets(skyrim_data: Path, output: Path) -> None:
    mesh = None
    for name in ("Skyrim - Meshes0.bsa", "Skyrim - Meshes1.bsa"):
        mesh = extract_mesh(skyrim_data / name, r"meshes\magic\firesprayfx01.nif")
        if mesh is not None:
            break
    if mesh is None:
        raise ValueError("Vanilla flame mesh not found")
    mesh_path = output / "Meshes/CreatorSpells/Incineration.nif"
    palette_path = output / "Textures/CreatorSpells/IncinerationGradient.dds"
    mesh_path.parent.mkdir(parents=True, exist_ok=True)
    palette_path.parent.mkdir(parents=True, exist_ok=True)
    mesh_path.write_bytes(recolor_flames(mesh))
    palette_path.write_bytes(gradient_dds())
