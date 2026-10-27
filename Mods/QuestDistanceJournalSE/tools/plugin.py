"""Create a private start-game quest with a player load-game listener."""
import struct


def subrecord(tag: bytes, data: bytes) -> bytes:
    return tag + struct.pack('<H', len(data)) + data


def text(value: str) -> bytes:
    data = value.encode('utf-8')
    return struct.pack('<H', len(data)) + data


def record(tag: bytes, form_id: int, payload: bytes) -> bytes:
    return tag + struct.pack('<IIIIHH', len(payload), 0, form_id, 0, 44, 0) + payload


def build_plugin() -> bytes:
    quest_id = 0x01000800
    header = record(b'TES4', 0,
                    subrecord(b'HEDR', struct.pack('<fII', 1.7, 4, 0x804))
                    + subrecord(b'CNAM', b'Quest Distance Journal SE\0')
                    + subrecord(b'MAST', b'Skyrim.esm\0') + subrecord(b'DATA', bytes(8)))
    vmad = struct.pack('<HHH', 5, 2, 4)
    for script in ('QDJController', 'QDJCache', 'QDJCompass', 'QDJMCM'):
        vmad += text(script) + struct.pack('<BH', 0, 0)
    vmad += struct.pack('<bH', 2, 0) + text('') + struct.pack('<H', 1)
    vmad += struct.pack('<HhIHHH', 0, 0, quest_id, 5, 2, 1)
    vmad += text('QDJPlayerAlias') + struct.pack('<BH', 0, 0)
    quest = record(b'QUST', quest_id,
                   subrecord(b'EDID', b'QDJStartQuest\0')
                   + subrecord(b'VMAD', vmad)
                   + subrecord(b'FULL', b'Quest Distance Journal\0')
                   + subrecord(b'DNAM', bytes((1, 0, 80, 0)) + bytes(8))
                   + subrecord(b'NEXT', b'') + subrecord(b'ANAM', struct.pack('<I', 1))
                   + subrecord(b'ALST', bytes(4)) + subrecord(b'ALID', b'Player\0')
                   + subrecord(b'FNAM', bytes(4)) + subrecord(b'ALFR', struct.pack('<I', 0x14))
                   + subrecord(b'ALED', b''))
    group = b'GRUP' + struct.pack('<I', len(quest) + 24) + b'QUST' + struct.pack('<iHHHH', 0, 0, 0, 0, 0)
    globals_payload = b''
    for local_id, editor_id, value in (
            (0x801, 'QDJSortMode', 0.0),
            (0x802, 'QDJTrackedFirst', 1.0),
            (0x803, 'QDJShowDetails', 1.0)):
        globals_payload += record(b'GLOB', 0x01000000 + local_id,
                                  subrecord(b'EDID', editor_id.encode() + b'\0')
                                  + subrecord(b'FNAM', b's')
                                  + subrecord(b'FLTV', struct.pack('<f', value)))
    globals_group = b'GRUP' + struct.pack('<I', len(globals_payload) + 24) + b'GLOB' + struct.pack('<iHHHH', 0, 0, 0, 0, 0)
    return header + globals_group + globals_payload + group + quest
