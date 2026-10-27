"""Read quest objective/alias links from the user's winning plugin records."""
from __future__ import annotations

import mmap
import struct
import zlib
from pathlib import Path


def subrecords(payload: bytes):
    pos, extended = 0, None
    while pos < len(payload):
        sig, size = struct.unpack_from('<4sH', payload, pos)
        pos += 6
        if sig == b'XXXX':
            if size != 4:
                raise ValueError('Invalid extended subrecord')
            extended = struct.unpack_from('<I', payload, pos)[0]
            pos += 4
            continue
        size = size if extended is None else extended
        extended = None
        if pos + size > len(payload):
            raise ValueError('Truncated subrecord')
        yield sig, payload[pos:pos + size]
        pos += size


def quest_records(data, start: int, end: int):
    pos = start
    while pos < end:
        sig, size = struct.unpack_from('<4sI', data, pos)
        if sig == b'GRUP':
            if size < 24 or pos + size > end:
                raise ValueError('Invalid plugin group')
            # All QUST records are in the top-level QUST group.
            if data[pos + 8:pos + 12] == b'QUST':
                yield from quest_records(data, pos + 24, pos + size)
            pos += size
            continue
        if pos + 24 + size > end:
            raise ValueError('Truncated plugin record')
        if sig in (b'TES4', b'QUST'):
            flags, form_id = struct.unpack_from('<II', data, pos + 8)
            payload = data[pos + 24:pos + 24 + size]
            if flags & 0x40000:
                expected = struct.unpack_from('<I', payload)[0]
                payload = zlib.decompress(payload[4:])
                if len(payload) != expected:
                    raise ValueError('Invalid compressed record size')
            yield sig, flags, form_id, payload
        pos += 24 + size


def collect_targets(data_dir: Path, plugins: list[str]) -> tuple[dict, dict]:
    winning = {}
    for plugin in plugins:
        path = data_dir / plugin
        with path.open('rb') as source, mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as data:
            masters = []
            for sig, flags, form_id, payload in quest_records(data, 0, len(data)):
                if sig == b'TES4':
                    masters = [value.rstrip(b'\0').decode('utf-8') for tag, value in subrecords(payload) if tag == b'MAST']
                    continue
                index = form_id >> 24
                if index > len(masters):
                    raise ValueError(f'Invalid master index in {plugin}: {form_id:08X}')
                origin = masters[index] if index < len(masters) else plugin
                key = (origin.lower(), form_id & 0xFFFFFF)
                winning[key] = None if flags & 0x20 else parse_quest(payload)
    database = {}
    seen_ids = set()
    conditional, direct = 0, 0
    for value in winning.values():
        if not value:
            continue
        editor_id, objectives = value
        # Case-insensitive editor IDs match Papyrus; duplicates fail closed.
        key = 'q_' + editor_id.lower()
        if key in seen_ids:
            raise ValueError(f'Duplicate quest editor ID: {editor_id}')
        seen_ids.add(key)
        encoded = []
        for objective, targets in objectives.items():
            for alias, has_conditions in targets:
                encoded.append(f'{objective}:{-1 if has_conditions else alias}')
                conditional += has_conditions
                direct += not has_conditions
        if encoded:
            if len(encoded) > 128:
                raise ValueError(f'Too many targets for Papyrus: {editor_id}')
            database[editor_id] = ';'.join(encoded)
    return database, {'quests': len(database), 'unconditional_targets': direct, 'conditional_targets': conditional, 'plugins': plugins}


def generate_index(database: dict) -> str:
    """Papyrus string equality is case-insensitive, matching Skyrim editor IDs."""
    lines = ['Scriptname QDJTargetIndex Hidden', '', 'String Function GetTargets(String editorID) Global', '    String result']
    entries = sorted(database.items())
    chunks = [entries[i:i + 80] for i in range(0, len(entries), 80)]
    for index in range(len(chunks)):
        lines += [f'    result = Lookup{index}(editorID)', '    If result != ""', '        Return result', '    EndIf']
    lines += ['    Return ""', 'EndFunction', '']
    for index, chunk in enumerate(chunks):
        lines += [f'String Function Lookup{index}(String editorID) Global']
        for position, (editor_id, encoded) in enumerate(chunk):
            if not editor_id.replace('_', '').isalnum():
                raise ValueError(f'Unsafe editor ID: {editor_id}')
            lines += [f'    {"If" if position == 0 else "ElseIf"} editorID == "{editor_id}"', f'        Return "{encoded}"']
        lines += ['    EndIf', '    Return ""', 'EndFunction', '']
    return '\n'.join(lines)


def parse_quest(payload: bytes):
    editor_id, objective, target = '', None, None
    objectives: dict[int, list[list[int]]] = {}
    for tag, value in subrecords(payload):
        if tag == b'EDID':
            editor_id = value.rstrip(b'\0').decode('utf-8')
        elif tag == b'QOBJ':
            objective = struct.unpack('<H', value)[0]
            objectives[objective] = []
            target = None
        elif tag == b'ANAM':
            # Objective targets end before the alias definition section.
            break
        elif tag == b'QSTA' and objective is not None:
            if len(value) != 8:
                raise ValueError('Unexpected QSTA layout')
            target = [struct.unpack_from('<i', value)[0], False]
            objectives[objective].append(target)
        elif tag == b'CTDA' and target is not None:
            target[1] = True
    return (editor_id, objectives) if editor_id else None


def load_order(data_dir: Path, plugins_file: Path) -> list[str]:
    available = {p.name.lower(): p.name for p in data_dir.iterdir() if p.suffix.lower() in ('.esm', '.esp', '.esl')}
    ordered = ['Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm']
    ccc = data_dir.parent / 'Skyrim.ccc'
    if ccc.exists():
        ordered += ccc.read_text(encoding='utf-8-sig').splitlines()
    ordered += [line[1:].strip() for line in plugins_file.read_text(encoding='utf-8-sig').splitlines() if line.startswith('*')]
    result: list[str] = []
    for name in ordered:
        name = name.strip()
        if not name or name.lower() in {p.lower() for p in result}:
            continue
        if name.lower() not in available:
            if name in ('Update.esm',) or (ccc.exists() and name in ccc.read_text(encoding='utf-8-sig').splitlines()):
                continue
            raise ValueError(f'Active plugin missing: {name}')
        result.append(available[name.lower()])
    # Skyrim loads masters before non-masters, preserving order within each group.

    def is_master(name):
        with (data_dir / name).open('rb') as source:
            return bool(struct.unpack_from('<I', source.read(12), 8)[0] & 1)
    return [p for p in result if is_master(p)] + [p for p in result if not is_master(p)]
