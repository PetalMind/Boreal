"""Patch only the locally installed SkyUI quest journal; never alter game files."""
from __future__ import annotations

import struct
import subprocess
from pathlib import Path


def extract_journal(archive: Path, output: Path) -> None:
    data = archive.read_bytes()
    magic, version, offset, flags, folder_count, file_count, _, _, _ = struct.unpack_from('<9I', data)
    if magic != 0x00415342 or version not in (104, 105) or flags & 0x100:
        raise ValueError('Unsupported SkyUI BSA format')
    folder_size = 24 if version == 105 else 16
    pos = offset + folder_count * folder_size
    files = []
    for index in range(folder_count):
        count = struct.unpack_from('<I', data, offset + index * folder_size + 8)[0]
        length = data[pos]
        folder = data[pos + 1:pos + length].rstrip(b'\0').decode('utf-8')
        pos += length + 1
        for _ in range(count):
            _, size, address = struct.unpack_from('<QII', data, pos)
            files.append((folder, size, address))
            pos += 16
    if len(files) != file_count:
        raise ValueError('Invalid BSA file count')
    for folder, size, address in files:
        end = data.index(b'\0', pos)
        filename = data[pos:end].decode('utf-8')
        pos = end + 1
        if folder.lower() == 'interface' and filename.lower() == 'quest_journal.swf':
            if bool(flags & 4) != bool(size & (1 << 30)):
                raise ValueError('Compressed journal: extract with BSArch and pass --journal-swf')
            size &= ~(1 << 30)
            output.write_bytes(data[address:address + size])
            if output.read_bytes()[:3] not in (b'FWS', b'CWS', b'GFX', b'CFX'):
                raise ValueError('Invalid extracted journal')
            return
    raise ValueError('SkyUI quest_journal.swf not found')


def replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding='utf-8')
    if source.count(old) != 1:
        raise ValueError(f'Unsupported SkyUI code at {path.name}: expected one patch point')
    path.write_text(source.replace(old, new), encoding='utf-8')


def patch_journal(root: Path, work: Path, source: Path, ffdec: Path, output: Path) -> None:
    java = ['java', f'-Duser.home={work}', '-jar', str(ffdec)]
    exports = work / 'export'
    subprocess.run(java + ['-format', 'script:as', '-export', 'script', str(exports), str(source)], check=True,
                   stdout=subprocess.DEVNULL)
    scripts = exports / 'scripts'
    page = scripts / '__Packages/QuestsPage.as'
    replace_once(page, '      this.TitleList.bAllowUpToTabs = true;',
                 '      this.TitleList.bAllowUpToTabs = true;\n'
                 '      this.TitleList.numTopHalfEntries = 3;\n'
                 '      _root.QDJPage = this;\n'
                 '      _root.QDJRequests = new Object();\n'
                 '      _root.QDJCount = 0;')
    replace_once(page, '   function QuestsPage()\n   {',
                 (root / 'Source/JournalBridge.as').read_text() + '\n   function QuestsPage()\n   {')
    replace_once(page, '      this.TitleList.InvalidateData();',
                 '      this.QDJQueueEntries();\n      this.TitleList.InvalidateData();')
    replace_once(page, '      this.UpdateButtonsVisibility();\n      this.ObjectiveList.InvalidateData();',
                 '      this.QDJQueueEntries();\n      this.UpdateButtonsVisibility();\n      this.ObjectiveList.InvalidateData();')
    replace_once(page, '   function onObjectiveListHighlight(event)\n   {',
                 '   function onObjectiveListHighlight(event)\n   {\n      this.QDJQueueEntries();')
    base = scripts / '__Packages/Shared/BSScrollingList.as'
    marker = '   function SetPlatform(aiPlatform, abPS3Switch)'
    source_text = base.read_text()
    start = source_text.index('   function SetEntryText(')
    end = source_text.index(marker, start)
    function = source_text[start:end]
    suffix = '   }\n'
    assert function.endswith(suffix)
    replacement = function[:-len(suffix)] + (root / 'Source/EntryMetadata.as').read_text() + '\n' + suffix
    replace_once(base, function, replacement)
    # Only edited scripts are imported: unrelated SkyUI bytecode is preserved.
    edited = {page, base}
    for item in scripts.rglob('*.as'):
        if item not in edited:
            item.unlink()
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(java + ['-importScript', str(source), str(output), str(scripts)], check=True,
                   stdout=subprocess.DEVNULL)
    if not output.is_file() or output.stat().st_size < 10000:
        raise ValueError('FFDec did not create a compiled journal')
