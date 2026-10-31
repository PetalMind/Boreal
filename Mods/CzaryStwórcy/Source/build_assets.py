"""Create the incineration palette and recolor a local Skyrim flame mesh."""

from __future__ import annotations

import math
import struct
from collections.abc import Callable
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


def transform_nif(data: bytes, transform: Callable[[str, bytes], bytes]) -> bytes:
    """Transform Skyrim SE blocks while preserving links and animation."""
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
    for index, (type_index, size) in enumerate(zip(indexes, sizes)):
        block = data[position:position + size]
        position += size
        block = transform(types[type_index], block)
        struct.pack_into("<I", header, size_table + 4 * index, len(block))
        blocks.append(block)
    if position + 8 != len(data):
        raise ValueError("Unexpected vanilla mesh layout")
    return bytes(header) + b"".join(blocks) + data[position:]


def recolor_flames(data: bytes) -> bytes:
    """Give stream, hands and impact particles the same violet palette."""
    changed = 0

    def recolor(kind: str, block: bytes) -> bytes:
        nonlocal changed
        if kind == "BSEffectShaderProperty":
            source_length = struct.unpack_from("<I", block, 36)[0]
            source_end = 40 + source_length
            palette_offset = source_end + 44
            palette_length = struct.unpack_from("<I", block, palette_offset)[0]
            if palette_offset + 4 + palette_length != len(block):
                raise ValueError("Unsupported Skyrim effect shader layout")
            shader = bytearray(block[:palette_offset])
            flags = struct.unpack_from("<I", shader, 12)[0]
            struct.pack_into("<I", shader, 12, flags | 0x10)
            brightness = max(struct.unpack_from("<3f", shader, source_end + 20))
            struct.pack_into("<3f", shader, source_end + 20, *([brightness] * 3))
            changed += 1
            return bytes(shader) + struct.pack("<I", len(PALETTE)) + PALETTE
        if kind == "BSPSysSimpleColorModifier":
            # Particle colors multiply the palette: remove inherited orange tint.
            modifier = bytearray(block)
            for offset in (37, 53, 69):
                brightness = max(struct.unpack_from("<3f", modifier, offset))
                struct.pack_into("<3f", modifier, offset, *([brightness] * 3))
            return bytes(modifier)
        return block

    result = transform_nif(data, recolor)
    if not changed:
        raise ValueError("Mesh has no recolorable effect shaders")
    return result


def gradient_dds() -> bytes:
    """An uncompressed RGBA palette with violet hues at every intensity."""
    width, height = 256, 16
    header = struct.pack("<7I", 124, 0x100F, height, width, width * 4, 0, 0)
    header += bytes(44)
    header += struct.pack("<8I", 32, 0x41, 0, 32, 0xFF, 0xFF00, 0xFF0000, 0xFF000000)
    header += struct.pack("<5I", 0x1000, 0, 0, 0, 0)
    stops = ((0, (0, 0, 0)), (40, (30, 0, 75)), (115, (100, 0, 210)),
             (165, (145, 15, 255)), (220, (180, 55, 255)), (255, (210, 95, 255)))
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
    def load_mesh(name: str) -> bytes:
        for archive in ("Skyrim - Meshes0.bsa", "Skyrim - Meshes1.bsa"):
            mesh = extract_mesh(skyrim_data / archive, "meshes\\" + name)
            if mesh is not None:
                return mesh
        raise ValueError(f"Vanilla mesh not found: {name}")

    mesh_folder = output / "Meshes/CreatorSpells"
    mesh_folder.mkdir(parents=True, exist_ok=True)
    for name, original in (
        ("Incineration.nif", r"magic\firesprayfx01.nif"),
        ("IncinerationHands.nif", r"magic\Fireball01HandEffects.nif"),
        ("IncinerationImpact.nif", r"effects\ImpactEffects\ImpactWaterSplashFire.nif"),
    ):
        (mesh_folder / name).write_bytes(recolor_flames(load_mesh(original)))
    (mesh_folder / "InternalExplosion.nif").write_bytes(
        radial_blood_burst(load_mesh(r"effects\BloodSprayDecap01.nif"))
    )
    palette_path = output / "Textures/CreatorSpells/IncinerationGradient.dds"
    palette_path.parent.mkdir(parents=True, exist_ok=True)
    palette_path.write_bytes(gradient_dds())


def radial_blood_burst(data: bytes) -> bytes:
    """Emit blood in a full circle instead of the vanilla directional spray."""
    changed = 0

    def radial(kind: str, block: bytes) -> bytes:
        nonlocal changed
        if kind not in ("NiPSysCylinderEmitter", "NiPSysSphereEmitter"):
            return block
        emitter = bytearray(block)
        # NiPSysModifier (13 bytes), then speed, speed variation and four angles.
        struct.pack_into("<4f", emitter, 21, math.pi / 2, 0.45, 0.0, math.pi)
        changed += 1
        return bytes(emitter)

    result = transform_nif(data, radial)
    if changed != 4:
        raise ValueError("Unexpected vanilla blood emitter layout")
    return result
