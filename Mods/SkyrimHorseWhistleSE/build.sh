#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
COMPILER=$(printenv CAPRICA_EXE || true)
if [ -z "$COMPILER" ]; then
    COMPILER="$ROOT_DIR/../../.local-tools/caprica/Caprica.exe"
fi
BUILD_DIR=$(mktemp -d "/tmp/skyrim-horse-whistle.XXXXXX")
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
                wine "$COMPILER" --game=skyrim --strict --ignorecwd --flags "$IMPORT_DIR/TESV_Papyrus_Flags.flg" -i "$IMPORT_DIR" -o "$SCRIPT_OUTPUT" HorseWhistleQuest.psc HorseWhistleMCM.psc
            )
        else
            echo "Caprica.exe requires Wine on this platform." >&2
            exit 1
        fi
        ;;
    *)
        (
            cd "$ROOT_DIR/Source/Scripts"
            "$COMPILER" --game=skyrim --strict --ignorecwd --flags "$IMPORT_DIR/TESV_Papyrus_Flags.flg" -i "$IMPORT_DIR" -o "$SCRIPT_OUTPUT" HorseWhistleQuest.psc HorseWhistleMCM.psc
        )
        ;;
esac

python3 "$ROOT_DIR/tools/build_plugin.py" "$BUILD_DIR/Data/SkyrimHorseWhistleSE.esp"

python3 - "$BUILD_DIR" "$ROOT_DIR" <<'PY'
from pathlib import Path
import sys
import zipfile

build_dir = Path(sys.argv[1])
root_dir = Path(sys.argv[2])
archive_path = root_dir / "SkyrimHorseWhistleSE.zip"
with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((build_dir / "Data").rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(build_dir).as_posix())
    for relative in ("fomod/info.xml", "fomod/ModuleConfig.xml", "README.md", "CHANGELOG.md"):
        path = root_dir / relative
        archive.write(path, path.relative_to(root_dir).as_posix())
print(archive_path)
PY
