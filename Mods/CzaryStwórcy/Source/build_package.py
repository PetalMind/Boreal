#!/usr/bin/env python3
"""Build the plugin, assets, strictly compiled Papyrus, and installable ZIP."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

from build_assets import build_assets
from build_plugin import build_plugin, read_plugin

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skyrim-data", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    args = parser.parse_args()
    before = read_plugin(ROOT / "Data/CreatorSpells.esp")
    with tempfile.TemporaryDirectory(prefix="creator-spells-") as temporary:
        data = Path(temporary) / "Data"
        scripts = data / "Scripts"
        scripts.mkdir(parents=True)
        plugin = data / "CreatorSpells.esp"
        build_plugin(args.skyrim_data / "Skyrim.esm", plugin)
        after = read_plugin(plugin)
        # Existing IDs are save-game references and must survive a rebuild.
        for form_id, old in before.items():
            if form_id == 0 or form_id >= 0x01000825:
                continue
            if after.get(form_id) != old:
                raise ValueError(f"Existing record changed: {form_id:08X}")
        build_assets(args.skyrim_data, data)
        sources = Path(temporary) / "sources"
        imports = Path(temporary) / "imports"
        shutil.copytree(ROOT / "Source/Scripts", sources)
        shutil.copytree(ROOT / "Source/CompilerImports", imports)
        command = [str(args.compiler.resolve())]
        if args.compiler.suffix.lower() == ".exe":
            command.insert(0, "wine")
        command += ["--game=skyrim", "--strict", "--all-warnings-as-errors", "--ignorecwd",
                    "--enable-debug-info=false", "-f", str(imports / "TESV_Papyrus_Flags.flg"),
                    "-i", str(imports), "-o", str(scripts),
                    "CreatorIncineration.psc", "CreatorInternalExplosion.psc"]
        environment = dict(os.environ, WINEDEBUG="-all", PYTHONDONTWRITEBYTECODE="1")
        subprocess.run(command, check=True, env=environment, cwd=sources)
        expected = {"CreatorIncineration.pex", "CreatorInternalExplosion.pex"}
        if {path.name for path in scripts.iterdir()} != expected:
            raise ValueError("Unexpected Papyrus compiler output")
        for path in scripts.iterdir():
            if path.read_bytes()[:4] != b"\xfaW\xc0\xde":
                raise ValueError(f"Invalid PEX: {path}")
        for path in data.rglob("*"):
            if path.is_file():
                destination = ROOT / "Data" / path.relative_to(data)
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(path.read_bytes())
    manifest = json.loads((ROOT / "manifest.json").read_text())
    files = [path for path in (ROOT / "Data").rglob("*") if path.is_file()]
    files += [ROOT / name for name in ("README.md", "CHANGELOG.md", "manifest.json")]
    with zipfile.ZipFile(ROOT / "CzaryStwórcy.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(files):
            info = zipfile.ZipInfo(path.relative_to(ROOT).as_posix(), (2026, 10, 29, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes())
    print(f"Built Czary Stwórcy {manifest['version']}: 23 spells, 2 compiled scripts, custom flame assets")


if __name__ == "__main__":
    main()
