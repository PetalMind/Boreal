# SA Target Focus

Single-player **Target Focus / Lock-On System** for **GTA San Andreas: The Definitive Edition**.

The mod is designed as soft aim assistance rather than an aimbot. While the aim button is held, it searches visible peds inside a configurable camera cone, scores them by crosshair angle, distance, visibility and threat, and gently blends the camera towards the selected target.

Included:

- `Free Aim+`, `Soft Lock` and `Classic Lock-On` modes.
- `Free Aim+`, `Balanced`, `Strong Assist`, `Classic Lock-On` and `Custom` presets.
- Detection FOV presets: 10°, 25° and 45°.
- Aim assist strength, target stickiness, aim friction, camera smoothing, maximum distance and break-lock delay.
- Center Mass, Upper Body and Dynamic target points.
- Hostile NPCs, enemy gangs, wanted police and optional civilians.
- Mission-ped filtering that avoids mission allies until the ped is already targeted or has been damaged by the player.
- Target switching with Mouse 4/5 or the controller's right stick.
- Configurable visual states: `+` with no target, `(+)` for a candidate and `[+]` for an active lock.
- Default `Minimal` HUD: subtle target corners, short lock-acquired animation, target-switch fade and lock-break fade.
- Optional target highlight: `OFF`, `Corners`, `Outline` or `Classic GTA`.
- Optional `Modern` confidence ring and a small status indicator (`○` available, `◎` candidate, `◉` locked).
- A lost-target direction arrow is shown for 0.3 sec only when the target remains visible; the mod does not mark or steer through walls.
- Automatic lock break when the target dies, leaves the view, becomes obstructed, exceeds range or the aim button is released.
- Manual camera input has priority over the assist, with a short lost-target grace period.
- Optional Developer Mode with live target, score, visibility, correction and scanner diagnostics.
- Settings are stored outside the script in `CLEO/SA_TargetFocus.ini` and are saved automatically.

## Controls

- Hold Right Mouse Button or LT to activate focus.
- Press Mouse 4/5, or move the mouse/right stick horizontally while aiming, to switch targets.
- Press `F6` to open or close the settings window.
- Press `F7` to toggle the feature without opening the menu.

The default F6/F7 assignment avoids the F5 shortcut used by the separate Mefisto Trainer. To change the bindings, edit the `[input]` section of `SA_TargetFocus.ini` with Windows virtual-key codes. The installer never overwrites an existing configuration.

The settings persist between game sessions. The gameplay path uses supported CLEO Redux/SA DE commands; optional 2D target projection is detected and falls back to world-space markers when unavailable. The mod does not inject input, fire weapons, alter multiplayer state or bypass anti-cheat systems.

## Requirements

- PC release of GTA San Andreas: The Definitive Edition supported by CLEO Redux.
- [CLEO Redux 1.5.0 x64](https://github.com/cleolibrary/CLEO-Redux/releases/tag/1.5.0).
- [ImGuiRedux Win64](https://github.com/user-grinch/ImGuiRedux).
- IniFiles 1.2 x64 (`IniFiles64.cleo`, included as a CLEO Redux plugin; required for persistent settings).
- Ultimate ASI Loader x64 installed as `version.dll` (the proxy selected by the official CLEO Redux installer for 64-bit games).

Install those dependencies in `Gameface/Binaries/Win64` and place the CLEO plugins in `Gameface/Binaries/Win64/CLEO/CLEO_PLUGINS`, then run:

```sh
chmod +x install.sh
./install.sh "/path/to/GTA San Andreas - The Definitive Edition"
```

The installer verifies `SanAndreas.exe`, `version.dll`, CLEO Redux, ImGuiRedux and IniFiles before copying `sa_target_focus[fs].js`. The `[fs]` suffix grants this script the file-system permission required by IniFiles while leaving the global CLEO permission setting unchanged. It also installs the default `SA_TargetFocus.ini` only when no user configuration exists. If a different installed copy exists, it creates a timestamped backup first.

The default `Balanced` profile is intentionally usable without tuning:

```text
Mode                 Soft Lock
Strength             55%
Target Stickiness    65%
Detection FOV        25°
Aim Friction         35%
Lost Target Delay    0.4 sec
Target Point         Center Mass
Indicator            Minimal
Target Highlight     Corners
Status Indicator     On
Maximum Distance     60 m
```
