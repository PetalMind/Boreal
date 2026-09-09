# Mefisto Trainer

Single-player trainer for **GTA San Andreas: The Definitive Edition**. Press `F5` to open or close its in-game ImGui overlay.

Included sections:

- Player: god mode, armor, stamina and wanted level.
- Weapons: item catalog, weapon selection, ammunition and infinite ammo.
- Vehicle: catalog-backed spawner, repair and invincibility for the current vehicle.
- World: weather and time controls.
- Teleport: four city locations plus one temporary saved position.

There are no multiplayer, anti-cheat bypass, mission, scenario, NPC spawner, developer or camera features.

## Catalog and spawner architecture

The trainer keeps GTA identifiers out of the ImGui layer:

```text
vehicles.ide -> Tools/generate_vehicle_catalog.js -> Data/vehicles.json
                                                   -> catalog.mjs
                                                   -> vehicle_spawner.mjs
                                                   -> CLEO Redux / GTA SA DE
```

`Data/vehicles.json` is a bundled fallback catalog containing the common vehicles. During installation, when the Definitive Edition source file exists at
`Gameface/Content/OriginalData/GTASA/data/vehicles.ide`, the installer regenerates the catalog from that file. This keeps the runtime list tied to the installed game data and also supports custom vehicles added to that file.

To regenerate the catalog manually:

```sh
node Tools/generate_vehicle_catalog.js \
  '/path/to/Gameface/Content/OriginalData/GTASA/data/vehicles.ide' \
  Data/vehicles.json
```

`Data/vehicle_metadata.json` contains UI-only names, categories, tags and favorites. The parser preserves the source IDE fields under `ide`, so adding a new vehicle does not require changing the trainer UI.

Weapons use the same separation of concerns. Each `Data/items.json` entry has a `typeId` used by `giveWeapon()` and a separate `modelId` for the visual model metadata. The item spawner passes only `typeId` to CLEO Redux.

## Requirements

- PC release of GTA San Andreas: The Definitive Edition supported by CLEO Redux.
- [CLEO Redux 1.5.0 x64](https://github.com/cleolibrary/CLEO-Redux/releases/tag/1.5.0).
- [ImGuiRedux Win64](https://github.com/user-grinch/ImGuiRedux).
- Ultimate ASI Loader x64 installed as `version.dll` (the proxy selected by the official CLEO Redux installer for 64-bit games).

Install those dependencies in `Gameface/Binaries/Win64`, then run:

```sh
chmod +x install.sh
./install.sh "/path/to/GTA San Andreas - The Definitive Edition"
```

The installer verifies `SanAndreas.exe` and both runtime dependencies before copying the trainer. It creates a timestamped backup when replacing a different `mefisto_trainer.js`.
