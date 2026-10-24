#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COMPILER=${CAPRICA_EXE:-$ROOT_DIR/../../.local-tools/caprica/Caprica.exe}
BUILD_DIR=$(mktemp -d "/tmp/nordic-minimal-ui-se.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT HUP INT TERM
export SWF_ARCHIVE="$BUILD_DIR/swf.zip"
python3 "$ROOT_DIR/tools/patch_swf.py"
mkdir -p "$BUILD_DIR/Data/Scripts"
case "$COMPILER" in
    *.exe)
        (cd "$ROOT_DIR/Source/Scripts" && wine "$COMPILER" --game=skyrim --strict --ignorecwd --flags "$ROOT_DIR/Source/CompilerImports/TESV_Papyrus_Flags.flg" -i "$ROOT_DIR/Source/CompilerImports" -o "$BUILD_DIR/Data/Scripts" NordicMinimalUIQuest.psc NordicMinimalUIMCM.psc)
        ;;
    *) (cd "$ROOT_DIR/Source/Scripts" && "$COMPILER" --game=skyrim --strict --ignorecwd --flags "$ROOT_DIR/Source/CompilerImports/TESV_Papyrus_Flags.flg" -i "$ROOT_DIR/Source/CompilerImports" -o "$BUILD_DIR/Data/Scripts" NordicMinimalUIQuest.psc NordicMinimalUIMCM.psc) ;;
esac
python3 "$ROOT_DIR/tools/build_plugin.py" "$BUILD_DIR/Data/NordicMinimalUISE.esp"
python3 - "$BUILD_DIR" "$ROOT_DIR/NordicMinimalUISE.zip" <<'PY'
from pathlib import Path
import sys, zipfile
root = Path(sys.argv[1])
data = root / "Data"
with zipfile.ZipFile(root / "swf.zip") as source:
    for member in source.infolist():
        (data / member.filename.removeprefix("Data/")).parent.mkdir(parents=True, exist_ok=True)
        (data / member.filename.removeprefix("Data/")).write_bytes(source.read(member.filename))
archive = Path(sys.argv[2])
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as output:
    for item in sorted(data.rglob("*")):
        if item.is_file(): output.write(item, item.relative_to(root).as_posix())
print(archive)
PY
