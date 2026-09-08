# SA Target Focus

Single-player **Target Focus / Lock-On System** for **GTA San Andreas: The Definitive Edition**.

The mod is designed as soft aim assistance rather than an aimbot. While the aim button is held, it searches visible peds inside a configurable camera cone, scores them by crosshair angle, distance, visibility and threat, and gently blends the camera towards the selected target.

Included:

- `Classic`, `Soft Lock` and `Free Aim+` modes.
- Detection FOV presets: 10°, 25° and 45°.
- Aim assist strength, target stickiness, aim friction and break-lock delay.
- Center Mass, Upper Body and Dynamic target points.
- Hostile NPCs, enemy gangs, wanted police and optional civilians.
- Mission-ped filtering that avoids mission allies until the ped is already targeted or has been damaged by the player.
- Target switching with horizontal mouse movement or the controller's right stick.
- Minimal, Classic GTA and Modern world-space target indicators.
- Automatic lock break when the target dies, leaves the view, becomes obstructed, exceeds range or the aim button is released.

## Controls

- Hold Right Mouse Button or LT to activate focus.
- Move the mouse/right stick horizontally while aiming to switch targets.
- Press `F6` to open or close the settings window.

The settings are held for the current game session. The mod uses only supported CLEO Redux/SA DE commands and does not inject input, fire weapons, alter multiplayer state or bypass anti-cheat systems.

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

The installer verifies `SanAndreas.exe`, `version.dll`, CLEO Redux and ImGuiRedux before copying `sa_target_focus.js`. If a different installed copy exists, it creates a timestamped backup first.

