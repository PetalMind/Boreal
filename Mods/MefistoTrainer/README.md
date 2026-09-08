# Mefisto Trainer

Single-player trainer for **GTA San Andreas: The Definitive Edition**. Press `F5` to open or close its in-game ImGui overlay.

Included sections:

- Player: god mode, armor, stamina and wanted level.
- Weapons: weapon selection, ammunition and infinite ammo.
- Vehicle: repair and invincibility for the current vehicle.
- World: weather and time controls.
- Teleport: four city locations plus one temporary saved position.

There are no multiplayer, anti-cheat bypass, mission, scenario, NPC spawner, developer or camera features.

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
