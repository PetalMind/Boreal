"""Index winning location parents and real teleport-door entrances, read only."""
from __future__ import annotations

from collections import defaultdict, deque
import mmap
import struct
import zlib
from pathlib import Path

from .records import subrecords


def collect_world(data_dir: Path, plugins: list[str]):
    locations, cells, doors = {}, {}, {}
    filenames = {name.lower(): name for name in plugins}
    for plugin in plugins:
        with (data_dir / plugin).open('rb') as source, mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as data:
            header_size = struct.unpack_from('<I', data, 4)[0]
            masters = [value.rstrip(b'\0').decode('utf-8').lower()
                       for tag, value in subrecords(data[24:24 + header_size]) if tag == b'MAST']

            def resolve(form_id):
                if not form_id:
                    return None
                index = form_id >> 24
                if index > len(masters):
                    raise ValueError(f'Invalid world master index in {plugin}: {form_id:08X}')
                return (masters[index] if index < len(masters) else plugin.lower(), form_id & 0xFFFFFF)

            def walk(start, end, parent_cell=None, world=None):
                pos = start
                while pos < end:
                    tag, size = struct.unpack_from('<4sI', data, pos)
                    if tag == b'GRUP':
                        if size < 24 or pos + size > end:
                            raise ValueError('Invalid world group')
                        label = data[pos + 8:pos + 12]
                        kind = struct.unpack_from('<i', data, pos + 12)[0]
                        if kind != 0 or label in (b'CELL', b'WRLD', b'LCTN'):
                            nested_cell, nested_world = parent_cell, world
                            if kind in (6, 8, 9, 10):
                                nested_cell = resolve(struct.unpack('<I', label)[0])
                            elif kind == 1:
                                nested_world = resolve(struct.unpack('<I', label)[0])
                            walk(pos + 24, pos + size, nested_cell, nested_world)
                        pos += size
                        continue
                    if pos + size + 24 > end:
                        raise ValueError('Truncated world record')
                    if tag in (b'LCTN', b'CELL', b'REFR'):
                        flags, form_id = struct.unpack_from('<II', data, pos + 8)
                        key = resolve(form_id)
                        destination = locations if tag == b'LCTN' else cells if tag == b'CELL' else doors
                        if flags & 0x20:
                            destination.pop(key, None)
                        else:
                            raw = data[pos + 24:pos + 24 + size]
                            if flags & 0x40000:
                                expected = struct.unpack_from('<I', raw)[0]
                                raw = zlib.decompress(raw[4:])
                                if len(raw) != expected:
                                    raise ValueError('Invalid compressed world record')
                            fields = dict(subrecords(raw))
                            if tag == b'LCTN':
                                locations[key] = resolve(struct.unpack('<I', fields.get(b'PNAM', bytes(4)))[0])
                            elif tag == b'CELL':
                                interior = bool(fields.get(b'DATA', b'\0')[0] & 1)
                                cells[key] = (interior, world)
                            elif b'XTEL' in fields and parent_cell is not None:
                                doors[key] = (parent_cell, resolve(struct.unpack_from('<I', fields[b'XTEL'])[0]))
                            else:
                                doors.pop(key, None)
                    pos += 24 + size
            walk(0, len(data))

    def node(cell):
        interior, world = cells.get(cell, (True, None))
        return ('cell', cell) if interior or world is None else ('world', world)

    graph = defaultdict(list)
    for reference, (cell, destination) in doors.items():
        other = doors.get(destination)
        if other is None:
            continue
        start, end = node(cell), node(other[0])
        if start != end:
            graph[start].append((end, destination))

    entrances = {}
    for source_node in sorted(graph):
        queue = deque([(source_node, 0, None)])
        visited = {}
        candidates = {}
        while queue:
            current, depth, anchor = queue.popleft()
            if depth > 16 or depth > visited.get(current, 1000):
                continue
            first_visit = current not in visited
            visited[current] = depth
            if current[0] == 'world' and anchor is not None:
                previous_depth, references = candidates.get(current[1], (depth, set()))
                if depth < previous_depth:
                    previous_depth, references = depth, set()
                if depth == previous_depth:
                    references.add(anchor)
                    candidates[current[1]] = (previous_depth, references)
            if not first_visit:
                continue
            for next_node, reference in graph[current]:
                # Once outside, traverse only direct world-to-world city gates.
                # Never infer a route through an unrelated dungeon or building.
                if current[0] == 'world' and next_node[0] != 'world':
                    continue
                queue.append((next_node, depth + 1, reference))
        references = sorted({ref for _, refs in candidates.values() for ref in refs})
        if references:
            if len(references) > 128:
                raise ValueError(f'Too many exterior entrances for {source_node}')
            entrances[source_node[1]] = references

    def encode(key):
        return f'{filenames.get(key[0], key[0])}|{key[1]}'

    location_data = {encode(key): encode(parent) for key, parent in locations.items() if parent is not None}
    entrance_data = {encode(key): ';'.join(encode(ref) for ref in refs) for key, refs in entrances.items()}
    stats = {'location_parent_links': len(location_data), 'teleport_doors': len(doors),
             'areas_with_exterior_entrances': len(entrance_data)}
    return location_data, entrance_data, stats


def generate_lookup(script: str, database: dict[str, str]) -> str:
    lines = [f'Scriptname {script} Hidden', '', 'String Function Lookup(String key) Global', '    String result']
    entries = sorted(database.items())
    chunks = [entries[i:i + 60] for i in range(0, len(entries), 60)]
    for index in range(len(chunks)):
        lines += [f'    result = Part{index}(key)', '    If result != ""', '        Return result', '    EndIf']
    lines += ['    Return ""', 'EndFunction', '']
    for index, chunk in enumerate(chunks):
        lines += [f'String Function Part{index}(String key) Global']
        for position, (key, value) in enumerate(chunk):
            if any(char in key + value for char in ('"', '\\', '\n', '\r')):
                raise ValueError('Unsafe plugin filename in generated Papyrus')
            lines += [f'    {"If" if position == 0 else "ElseIf"} key == "{key}"', f'        Return "{value}"']
        lines += ['    EndIf', '    Return ""', 'EndFunction', '']
    return '\n'.join(lines)
