#!/usr/bin/env python3
"""Install or remove the PAK, preserving the previous Watch Dogs dot."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

NAME = "GTAVSimpleReticleSA_P.pak"
CONFLICTS = ("WatchDogs2DotReticleSA.pak", "SimpleReticleSA.pak", "SimpleReticleSA-V2.pak")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path)
    parser.add_argument("--uninstall", action="store_true")
    args = parser.parse_args()
    game = args.game.resolve()
    paks = game / "Gameface/Content/Paks"
    if not (game / "Gameface/Binaries/Win64/SanAndreas.exe").is_file() or not paks.is_dir():
        parser.error("Expected the root of GTA San Andreas Definitive Edition")
    mods = next((p for p in paks.iterdir() if p.is_dir() and p.name.lower() == "~mods"), paks / "~mods")
    backup = game / "BorealModBackups/GTAVSimpleReticleDE"
    manifest = backup / "installation.json"
    target = mods / NAME
    if args.uninstall:
        if not manifest.exists():
            parser.error("No installation record; refusing to remove unmanaged files")
        record = json.loads(manifest.read_text())
        if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() != record["sha256"]:
            parser.error("Installed PAK was changed; leaving files intact")
        for name in record["disabled"]:
            if (mods / name).exists() or not (backup / name).is_file():
                parser.error("Cannot safely restore previous mod: " + name)
        target.unlink(missing_ok=True)
        for name in record["disabled"]:
            shutil.move(str(backup / name), str(mods / name))
        manifest.unlink()
        print("Removed GTA V Simple Reticle; restored previous mods.")
        return
    source = Path(__file__).resolve().parent / NAME
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if manifest.exists():
        record = json.loads(manifest.read_text())
        if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest() == digest:
            print("Already installed:", target)
            return
        parser.error("Previous installation exists; uninstall it before replacing")
    if target.exists():
        parser.error("Destination already exists without an installation record")
    conflicts = [p for p in mods.iterdir() if p.name.lower() in {n.lower() for n in CONFLICTS}] if mods.exists() else []
    if any((backup / p.name).exists() for p in conflicts):
        parser.error("Backup already exists; refusing to overwrite it")
    mods.mkdir(exist_ok=True)
    backup.mkdir(parents=True, exist_ok=True)
    moved = []
    try:
        for p in conflicts:
            shutil.move(str(p), str(backup / p.name))
            moved.append(p.name)
        shutil.copyfile(source, target)
        manifest.write_text(json.dumps({"sha256": digest, "disabled": moved}, indent=2) + "\n")
    except Exception:
        target.unlink(missing_ok=True)
        for name in moved:
            shutil.move(str(backup / name), str(mods / name))
        raise
    print("Installed:", target)
    print("Previous mods preserved:", ", ".join(moved) or "none")


if __name__ == "__main__":
    main()
