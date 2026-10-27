#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COMPILER=${CAPRICA_EXE:-"$ROOT_DIR/../../.local-tools/caprica/Caprica.exe"}
BUILD_DIR=$(mktemp -d /tmp/potion-glow-se.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT HUP INT TERM
mkdir -p "$BUILD_DIR/Data/Scripts"
if [ "${COMPILER##*.}" = exe ]; then
    set -- wine "$COMPILER"
else
    set -- "$COMPILER"
fi
(
    cd "$ROOT_DIR/Source/Scripts"
    "$@" --game=skyrim --strict --all-warnings-as-errors --ignorecwd \
        --flags "$ROOT_DIR/Source/CompilerImports/TESV_Papyrus_Flags.flg" \
        -i "$ROOT_DIR/Source/CompilerImports" -o "$BUILD_DIR/Data/Scripts" \
        PotionGlowQuest.psc PotionGlowMCM.psc PotionGlowPlayerAlias.psc
)
python3 "$ROOT_DIR/tools/build_plugin.py" "$BUILD_DIR/Data/PotionGlowSE.esp"
python3 - "$BUILD_DIR" "$ROOT_DIR" <<'PY'
from pathlib import Path
import shutil
import struct
import sys
import zipfile

build, root = map(Path, sys.argv[1:])
version = (root / 'VERSION').read_text().strip()
seq = build / 'Data/SEQ/PotionGlowSE.seq'
seq.parent.mkdir(parents=True)
seq.write_bytes(struct.pack('<I', 0x01000800))
with zipfile.ZipFile(build / 'mod.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((build / 'Data').rglob('*')):
        if path.is_file():
            archive.write(path, path.relative_to(build).as_posix())
    for name in ('README.md', 'CHANGELOG.md', 'VERSION'):
        archive.write(root / name, name)
shutil.copytree(build / 'Data', root / 'Data', dirs_exist_ok=True)
shutil.copyfile(build / 'mod.zip', root / 'PotionGlowSE.zip')
print('Built Potion Glow SE ' + version)
PY
