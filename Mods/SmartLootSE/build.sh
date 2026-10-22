#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COMPILER=${CAPRICA_EXE:-"$ROOT_DIR/../../.local-tools/caprica/Caprica.exe"}
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/smartloot-se.XXXXXX")
SCRIPT_OUTPUT="$BUILD_DIR/Data/Scripts"
IMPORT_DIR="$ROOT_DIR/Source/CompilerImports"
trap 'rm -rf "$BUILD_DIR"' EXIT HUP INT TERM

if [ ! -f "$COMPILER" ]; then
    echo "Papyrus compiler not found: $COMPILER" >&2
    echo "Set CAPRICA_EXE to a Caprica.exe path." >&2
    exit 1
fi

mkdir -p "$SCRIPT_OUTPUT"
case "$COMPILER" in
    *.exe)
        if command -v wine >/dev/null 2>&1; then
            (
                cd "$ROOT_DIR/Source/Scripts"
                wine "$COMPILER" --game=skyrim --strict --ignorecwd -i "$IMPORT_DIR" -f "$IMPORT_DIR/TESV_Papyrus_Flags.flg" -o "$SCRIPT_OUTPUT" SmartLootQuest.psc
            )
        else
            echo "Caprica.exe requires Wine on this platform." >&2
            exit 1
        fi
        ;;
    *)
        (
            cd "$ROOT_DIR/Source/Scripts"
            "$COMPILER" --game=skyrim --strict --ignorecwd -i "$IMPORT_DIR" -f "$IMPORT_DIR/TESV_Papyrus_Flags.flg" -o "$SCRIPT_OUTPUT" SmartLootQuest.psc
        )
        ;;
esac

python3 "$ROOT_DIR/tools/build_plugin.py" "$BUILD_DIR/Data/SmartLoot.esp"
python3 - "$BUILD_DIR" "$ROOT_DIR" <<'PY'
from pathlib import Path
import shutil
import sys
import zipfile

build_dir = Path(sys.argv[1])
root_dir = Path(sys.argv[2])
archive_path = root_dir / "SmartLootSE.zip"
for path in sorted((build_dir / "Data").rglob("*")):
    if path.is_file():
        destination = root_dir / path.relative_to(build_dir)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((root_dir / "Data").rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(root_dir).as_posix())
print(archive_path)
PY
