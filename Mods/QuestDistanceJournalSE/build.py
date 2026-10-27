#!/usr/bin/env python3
"""Build a ready-to-import mod from a local SkyUI and active quest plugins."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import tempfile
import zipfile
from pathlib import Path

from tools.interface import extract_journal, patch_journal
from tools.plugin import build_plugin
from tools.records import collect_targets, generate_index, load_order

ROOT = Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, required=True, help='Skyrim Data directory (read only)')
    parser.add_argument('--plugins', type=Path, required=True, help='Active Plugins.txt (read only)')
    parser.add_argument('--ffdec', type=Path, required=True, help='JPEXS ffdec.jar')
    parser.add_argument('--compiler', type=Path, default=ROOT.parents[1] / '.local-tools/caprica/Caprica.exe')
    parser.add_argument('--journal-swf', type=Path, help='Optional extracted SkyUI quest_journal.swf')
    args = parser.parse_args()
    for path in (args.data / 'SkyUI_SE.bsa', args.plugins, args.ffdec, args.compiler):
        if not path.exists():
            parser.error(f'Missing dependency: {path}')
    # A loose journal is the real active interface; do not silently discard it.
    loose = args.data / 'Interface/quest_journal.swf'
    if loose.exists() and args.journal_swf is None:
        parser.error('A loose quest journal is installed. Inspect compatibility and pass --journal-swf explicitly.')
    version = json.loads((ROOT / 'manifest.json').read_text())['version']
    order = load_order(args.data, args.plugins)
    database, stats = collect_targets(args.data, order)
    with tempfile.TemporaryDirectory(prefix='quest-distance-journal-') as temp:
        work = Path(temp)
        data = work / 'Data'
        output = data / 'Scripts'
        output.mkdir(parents=True)
        source = work / 'quest_journal.swf'
        if args.journal_swf:
            shutil.copy2(args.journal_swf, source)
        else:
            extract_journal(args.data / 'SkyUI_SE.bsa', source)
        stats['skyui_journal_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
        patch_journal(ROOT, work, source, args.ffdec, data / 'Interface/quest_journal.swf')
        script_sources = work / 'sources'
        shutil.copytree(ROOT / 'Source/Scripts', script_sources)
        (script_sources / 'QDJTargetIndex.psc').write_text(generate_index(database), encoding='utf-8')
        command = [str(args.compiler)]
        if args.compiler.suffix.lower() == '.exe':
            command.insert(0, 'wine')
        command += ['--game=skyrim', '--strict', '--ignorecwd', '-f',
                    str(ROOT / 'Source/CompilerImports/TESV_Papyrus_Flags.flg'),
                    '-i', str(ROOT / 'Source/CompilerImports'), '-o', str(output),
                    'QDJController.psc', 'QDJPlayerAlias.psc', 'QDJTargetResolver.psc', 'QDJTargetIndex.psc',
                    'QDJCache.psc', 'QDJCompass.psc']
        subprocess.run(command, cwd=script_sources, check=True)
        expected = {'QDJController.pex', 'QDJPlayerAlias.pex', 'QDJTargetResolver.pex', 'QDJTargetIndex.pex',
                    'QDJCache.pex', 'QDJCompass.pex'}
        actual = {p.name for p in output.glob('*.pex')}
        if actual != expected:
            raise ValueError(f'Unexpected compiler output: {actual}')
        for pex in output.glob('*.pex'):
            if pex.read_bytes()[:4] != b'\xfa\x57\xc0\xde':
                raise ValueError(f'Invalid PEX header: {pex.name}')
        (data / 'QuestDistanceJournalSE.esp').write_bytes(build_plugin())
        (data / 'SEQ').mkdir()
        (data / 'SEQ/QuestDistanceJournalSE.seq').write_bytes(struct.pack('<I', 0x01000800))
        # Keep the generated database inspectable, including exact winning inputs.
        report = {'version': version, **stats, 'targets': database}
        (work / 'README-build-report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
        for name in ('README.md', 'CHANGELOG.md', 'THIRD_PARTY.md'):
            shutil.copy2(ROOT / name, work / name)
        archive = ROOT / 'QuestDistanceJournalSE.zip'
        temporary_archive = work / archive.name
        with zipfile.ZipFile(temporary_archive, 'w', zipfile.ZIP_DEFLATED) as package:
            for path in sorted(work.rglob('*')):
                if path.is_file() and (data in path.parents or path.parent == work and path.suffix in ('.md', '.json')):
                    package.write(path, path.relative_to(work).as_posix())
        with zipfile.ZipFile(temporary_archive) as package:
            if package.testzip() is not None:
                raise ValueError('Corrupt output archive')
        shutil.copy2(temporary_archive, archive)
        (ROOT / 'build-report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
        print(f'Built {archive} v{version}: {stats["quests"]} indexed quests')


if __name__ == '__main__':
    main()
