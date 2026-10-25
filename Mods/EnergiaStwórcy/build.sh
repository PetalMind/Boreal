#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COMPILER=${CAPRICA_EXE:-"$ROOT_DIR/../../.local-tools/caprica/Caprica.exe"}
PAPYRUS_IMPORTS=${PAPYRUS_IMPORTS:-"$ROOT_DIR/Source/CompilerImports"}
BUILD_DIR=$(mktemp -d /tmp/creator-energy.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT HUP INT TERM
mkdir -p "$BUILD_DIR/Data/Scripts"
cp "$ROOT_DIR/Data/CreatorEnergy.esp" "$BUILD_DIR/Data/CreatorEnergy.esp"
cat > "$BUILD_DIR/TESV_Papyrus_Flags.flg" <<'FLAGS'
Flag Hidden 0
{
    Script
    Property
}
Flag Conditional 1
{
    Script
    Variable
}
FLAGS
if [ "${COMPILER##*.}" = exe ]; then
    set -- wine "$COMPILER"
else
    set -- "$COMPILER"
fi
(
cd "$ROOT_DIR/Source/Scripts"
"$@" --game=skyrim --strict --all-warnings-as-errors --ignorecwd \
    --flags "$BUILD_DIR/TESV_Papyrus_Flags.flg" -i "$PAPYRUS_IMPORTS" \
    -o "$BUILD_DIR/Data/Scripts" CreatorEnergySoulCapture.psc
)
python3 "$ROOT_DIR/Source/add_soul_capture.py" --plugin "$BUILD_DIR/Data/CreatorEnergy.esp"
python3 - "$BUILD_DIR" "$ROOT_DIR" <<'PY'
import json
from pathlib import Path
import shutil
import sys
import zipfile
build, root = map(Path, sys.argv[1:])
with zipfile.ZipFile(build / 'mod.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((build / 'Data').rglob('*')):
        if path.is_file():
            archive.write(path, path.relative_to(build).as_posix())
    for name in ('README.md', 'CHANGELOG.md', 'manifest.json'):
        archive.write(root / name, name)
shutil.copytree(build / 'Data', root / 'Data', dirs_exist_ok=True)
shutil.copyfile(build / 'mod.zip', root / 'EnergiaStwórcy.zip')
print('Built Energia Stwórcy ' + json.loads((root / 'manifest.json').read_text())['version'])
PY
