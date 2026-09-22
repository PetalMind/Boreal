#!/usr/bin/env python3
"""Minimal macOS reader/writer for The Witcher 2 DZIP archives.

The game archive is not a ZIP file.  This tool implements the version 2
container used by The Witcher 2, including its 64 KiB block layout and LZF
compression.  It intentionally exposes only the operations needed by the
mod build script: extract an archive, then pack it again after a script edit.
"""

from __future__ import annotations

import argparse
import os
import struct
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


MAGIC = 0x50495A44  # ASCII "DZIP" in little-endian order.
VERSION = 2
BLOCK_SIZE = 0x10000
FILETIME_EPOCH = 11644473600
FILETIME_TICKS = 10_000_000


@dataclass
class Entry:
    name: str
    timestamp: int
    uncompressed_size: int
    offset: int
    compressed_size: int


def read_exact(stream, size: int) -> bytes:
    data = stream.read(size)
    if len(data) != size:
        raise ValueError("truncated DZIP data")
    return data


def read_entries(stream) -> list[Entry]:
    magic, version, count, _unknown, table_offset, _hash = struct.unpack(
        "<IIIIqQ", read_exact(stream, 32)
    )
    if magic != MAGIC:
        raise ValueError("not a Witcher 2 DZIP archive")
    if version < VERSION:
        raise ValueError(f"unsupported DZIP version: {version}")

    stream.seek(table_offset)
    entries: list[Entry] = []
    for _ in range(count):
        name_length = struct.unpack("<H", read_exact(stream, 2))[0]
        raw_name = read_exact(stream, name_length)
        name = raw_name.rstrip(b"\0").decode("ascii")
        timestamp, uncompressed_size, offset, compressed_size = struct.unpack(
            "<qqqq", read_exact(stream, 32)
        )
        entries.append(
            Entry(name, timestamp, uncompressed_size, offset, compressed_size)
        )
    return entries


def lzf_decompress(data: bytes, expected_size: int) -> bytes:
    source = 0
    output = bytearray()
    while source < len(data):
        control = data[source]
        source += 1
        if control < 1 << 5:
            length = control + 1
            output.extend(read_slice(data, source, length))
            source += length
            continue

        length = control >> 5
        back_offset = (control & 0x1F) << 8
        if length == 7:
            if source >= len(data):
                raise ValueError("truncated LZF match length")
            length += data[source]
            source += 1
        length += 2
        if source >= len(data):
            raise ValueError("truncated LZF back reference")
        back_offset |= data[source]
        source += 1
        start = len(output) - 1 - back_offset
        if start < 0:
            raise ValueError("invalid LZF back reference")
        for index in range(length):
            output.append(output[start + index])

    if len(output) != expected_size:
        raise ValueError(
            f"LZF size mismatch: expected {expected_size}, got {len(output)}"
        )
    return bytes(output)


def read_slice(data: bytes, start: int, length: int) -> bytes:
    end = start + length
    if start < 0 or end > len(data):
        raise ValueError("truncated LZF literal")
    return data[start:end]


def unpack_entry(stream, entry: Entry) -> bytes:
    stream.seek(entry.offset)
    if entry.compressed_size == entry.uncompressed_size:
        return read_exact(stream, entry.uncompressed_size)

    block_count = (entry.uncompressed_size + BLOCK_SIZE - 1) // BLOCK_SIZE
    offsets = [
        entry.offset + struct.unpack("<I", read_exact(stream, 4))[0]
        for _ in range(block_count)
    ]
    offsets.append(entry.offset + entry.compressed_size)
    output = bytearray()
    for index in range(block_count):
        stream.seek(offsets[index])
        block_size = offsets[index + 1] - offsets[index]
        if block_size < 1:
            raise ValueError("invalid DZIP block size")
        compressed = read_exact(stream, block_size)
        output.extend(
            lzf_decompress(
                compressed,
                min(BLOCK_SIZE, entry.uncompressed_size - len(output)),
            )
        )

    if len(output) != entry.uncompressed_size:
        raise ValueError(
            f"DZIP size mismatch for {entry.name}: expected "
            f"{entry.uncompressed_size}, got {len(output)}"
        )
    return bytes(output)


def safe_relative_path(name: str) -> Path:
    path = PurePosixPath(name.replace("\\", "/"))
    if path.is_absolute() or ".." in path.parts or any(":" in part for part in path.parts):
        raise ValueError(f"unsafe DZIP path: {name}")
    return Path(*path.parts)


def extract(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    with source.open("rb") as stream:
        entries = read_entries(stream)
        for entry in entries:
            output = destination / safe_relative_path(entry.name)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(unpack_entry(stream, entry))
            timestamp = max(0, entry.timestamp / FILETIME_TICKS - FILETIME_EPOCH)
            os.utime(output, (timestamp, timestamp))


def lzf_compress(data: bytes) -> bytes:
    """Compress one block using the LZF variant used by DZIP."""

    if len(data) < 3:
        return data

    hash_log = 14
    hash_size = 1 << hash_log
    max_literal = 1 << 5
    max_offset = 1 << 13
    max_reference = (1 << 8) + (1 << 3)
    table = [0] * hash_size
    output = bytearray()
    position = 0
    literal_count = 0

    def hash_value_at(index: int) -> int:
        value = (data[index] << 8) | data[index + 1]
        value = ((value << 8) | data[index + 2]) & 0xFFFFFFFF
        mixed = (value ^ ((value << 5) & 0xFFFFFFFF)) & 0xFFFFFFFF
        shift = ((3 * 8 - hash_log) - value * 5) & 31
        return (mixed >> shift) & (hash_size - 1)

    def flush_literals(start: int, count: int) -> None:
        if count:
            output.append(count - 1)
            output.extend(data[start : start + count])

    literal_start = 0
    while True:
        if position < len(data) - 2:
            slot = hash_value_at(position)
            reference = table[slot]
            table[slot] = position
            back_offset = position - reference - 1
            if (
                back_offset < max_offset
                and position + 4 < len(data)
                and reference > 0
                and data[reference : reference + 3] == data[position : position + 3]
            ):
                match_length = 2
                max_length = min(max_reference, len(data) - position - match_length)
                while (
                    match_length < max_length
                    and data[reference + match_length] == data[position + match_length]
                ):
                    match_length += 1

                flush_literals(literal_start, literal_count)
                literal_count = 0
                match_length -= 2
                position += 1
                if match_length < 7:
                    output.append((back_offset >> 8) + (match_length << 5))
                else:
                    output.append((back_offset >> 8) + (7 << 5))
                    output.append(match_length - 7)
                output.append(back_offset & 0xFF)

                position += match_length - 1
                if position < len(data) - 2:
                    table[hash_value_at(position)] = position
                    position += 1
                if position < len(data) - 2:
                    table[hash_value_at(position)] = position
                    position += 1
                literal_start = position
                continue
        elif position == len(data):
            break

        if literal_count == 0:
            literal_start = position
        literal_count += 1
        position += 1
        if literal_count == max_literal:
            flush_literals(literal_start, literal_count)
            literal_count = 0
            literal_start = position

    flush_literals(literal_start, literal_count)
    return bytes(output)


def to_filetime(seconds: float) -> int:
    return int((seconds + FILETIME_EPOCH) * FILETIME_TICKS)


def entry_hash(entries: list[Entry]) -> int:
    value = 0x00000000FFFFFFFF
    prime = 0x00000100000001B3
    for entry in entries:
        for byte in entry.name.encode("ascii"):
            value = ((value ^ byte) * prime) & 0xFFFFFFFFFFFFFFFF
        value = ((value ^ len(entry.name)) * prime) & 0xFFFFFFFFFFFFFFFF
        for field in (
            entry.timestamp,
            entry.uncompressed_size,
            entry.offset,
            entry.compressed_size,
        ):
            value = ((value ^ (field & 0xFFFFFFFFFFFFFFFF)) * prime) & 0xFFFFFFFFFFFFFFFF
    return value


def pack(source: Path, destination: Path) -> None:
    files = sorted(path for path in source.rglob("*") if path.is_file())
    destination.parent.mkdir(parents=True, exist_ok=True)
    entries: list[Entry] = []
    with destination.open("wb") as stream:
        stream.write(b"\0" * 32)
        for path in files:
            # Gibbed.RED writes Windows-style, lower-case paths even though the
            # builder itself runs on macOS.  Keep that layout for compatibility
            # with the native archive reader in the game.
            name = path.relative_to(source).as_posix().replace("/", "\\").lower()
            if not name.isascii() or len(name.encode("ascii")) + 1 > 0xFFFF:
                raise ValueError(f"DZIP path is not representable: {name}")
            data = path.read_bytes()
            offset = stream.tell()
            block_count = (len(data) + BLOCK_SIZE - 1) // BLOCK_SIZE
            table_offset = stream.tell()
            stream.write(b"\0" * (block_count * 4))
            block_offsets: list[int] = []
            for index in range(block_count):
                block_offsets.append(stream.tell() - offset)
                block = data[index * BLOCK_SIZE : (index + 1) * BLOCK_SIZE]
                compressed = lzf_compress(block)
                if not compressed:
                    raise ValueError(f"could not compress DZIP block for {name}")
                stream.write(compressed)
            compressed_size = stream.tell() - offset
            end = stream.tell()
            stream.seek(table_offset)
            for block_offset in block_offsets:
                stream.write(struct.pack("<I", block_offset))
            stream.seek(end)
            stat = path.stat()
            entries.append(
                Entry(
                    name,
                    to_filetime(stat.st_mtime),
                    len(data),
                    offset,
                    compressed_size,
                )
            )

        table_offset = stream.tell()
        for entry in entries:
            encoded_name = entry.name.encode("ascii") + b"\0"
            stream.write(struct.pack("<H", len(encoded_name)))
            stream.write(encoded_name)
            stream.write(
                struct.pack(
                    "<qqqq",
                    entry.timestamp,
                    entry.uncompressed_size,
                    entry.offset,
                    entry.compressed_size,
                )
            )
        stream.seek(0)
        stream.write(
            struct.pack(
                "<IIIIqQ",
                MAGIC,
                VERSION,
                len(entries),
                0x64626267,
                table_offset,
                entry_hash(entries),
            )
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    extract_parser = subparsers.add_parser("extract")
    extract_parser.add_argument("source", type=Path)
    extract_parser.add_argument("destination", type=Path)
    pack_parser = subparsers.add_parser("pack")
    pack_parser.add_argument("source", type=Path)
    pack_parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    if args.command == "extract":
        extract(args.source, args.destination)
    else:
        pack(args.source, args.destination)


if __name__ == "__main__":
    main()
