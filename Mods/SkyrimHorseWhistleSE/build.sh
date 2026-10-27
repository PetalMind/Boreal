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
                wine "$COMPILER" --game=skyrim --strict --ignorecwd --flags "$IMPORT_DIR/TESV_Papyrus_Flags.flg" -i "$IMPORT_DIR" -o "$SCRIPT_OUTPUT" HorseWhistleQuest.psc HorseWhistleMCM.psc HorseWhistlePlayerAlias.psc
            )
        else
            echo "Caprica.exe requires Wine on this platform." >&2
            exit 1
        fi
        ;;
    *)
        (
            cd "$ROOT_DIR/Source/Scripts"
            "$COMPILER" --game=skyrim --strict --ignorecwd --flags "$IMPORT_DIR/TESV_Papyrus_Flags.flg" -i "$IMPORT_DIR" -o "$SCRIPT_OUTPUT" HorseWhistleQuest.psc HorseWhistleMCM.psc HorseWhistlePlayerAlias.psc
        )
        ;;
esac

python3 "$ROOT_DIR/tools/build_plugin.py" "$BUILD_DIR/Data/SkyrimHorseWhistleSE.esp"
python3 "$ROOT_DIR/tools/whistle_audio.py" "$BUILD_DIR/Data/Sound/FX/HorseWhistleSE/whistle.wav"

python3 - "$BUILD_DIR" "$ROOT_DIR" <<'PY'
from pathlib import Path
import sys
import zipfile
import struct
import shutil
import json
import xml.etree.ElementTree as ET

build_dir = Path(sys.argv[1])
root_dir = Path(sys.argv[2])
archive_path = root_dir / "SkyrimHorseWhistleSE.zip"
version = json.loads((root_dir / "manifest.json").read_text())["version"]
seq = build_dir / "Data/SEQ/SkyrimHorseWhistleSE.seq"
seq.parent.mkdir(parents=True, exist_ok=True)
seq.write_bytes(struct.pack("<I", 0x01000800))
for path in sorted((build_dir / "Data").rglob("*")):
    if path.is_file() and not any(part.startswith(".") for part in path.relative_to(build_dir).parts):
        destination = root_dir / path.relative_to(build_dir)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)
with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((build_dir / "Data").rglob("*")):
        if path.is_file() and not any(part.startswith(".") for part in path.relative_to(build_dir).parts):
            archive.write(path, path.relative_to(build_dir).as_posix())
    for relative in ("fomod/info.xml", "fomod/ModuleConfig.xml", "README.md", "CHANGELOG.md"):
        path = root_dir / relative
        if relative == "fomod/info.xml":
            info = ET.fromstring(path.read_text())
            info.find("Version").text = version
            archive.writestr(relative, ET.tostring(info, encoding="utf-8", xml_declaration=True))
        else:
            archive.write(path, path.relative_to(root_dir).as_posix())
print(archive_path)
print("Built Horse Whistle SE " + version)
PY
