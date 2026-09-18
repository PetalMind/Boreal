# Police Pursuit Radar

> Ten katalog zawiera wariant dla klasycznego GTA San Andreas 1.0 US x86.
> Dla instalacji **Grand Theft Auto: San Andreas – The Definitive Edition**
> użyj [PolicePursuitRadarDE](../PolicePursuitRadarDE/README.md), który działa
> jako skrypt CLEO Redux x64.

`PolicePursuitRadar.asi` is a native x86 plugin for the classic PC release of
Grand Theft Auto: San Andreas. It adds a radar-only visualization layer over
the vanilla wanted system:

- active pursuit cops, police cars, bikes, boats and helicopters;
- separate geometric markers for foot units, vehicles and helicopters;
- cached line-of-sight checks for the closest active pursuit units;
- `Pursuit`, `LosingContact`, `Searching` and `Escaped` state handling;
- a frozen last-known player position and a clipped circular search area;
- optional compact radar status and debug text;
- no wanted-level changes, spawning, AI changes or mission-script writes.

## Requirements and supported game

- Grand Theft Auto: San Andreas PC Classic, **1.0 US x86** (Compact or
  Hoodlum executable recognized by plugin-sdk).
- Silent ASI Loader or Ultimate ASI Loader.
- A current checkout of [DK22Pac/plugin-sdk](https://github.com/DK22Pac/plugin-sdk).
- A Windows x86 MSVC toolchain or an i686 MinGW toolchain.
- Direct3D 9, as provided by the game. No .NET, CEF, ImGui or external
  overlay is required.

The source is intentionally not built for Definitive Edition, Steam R2, 1.01,
or other executable layouts. plugin-sdk performs the game-version detection;
the plugin disables itself and writes a log entry for any unsupported version.

## Build

The project compiles the plugin-sdk sources together with this plugin, matching
the SDK's normal ASI project layout. The SDK is an external dependency and is
not copied into this repository.

From a Windows x86 developer prompt, or from a shell with an i686 MinGW CMake
toolchain:

```text
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DPLUGIN_SDK_DIR=C:/src/plugin-sdk
cmake --build build --config Release
```

The resulting `dist/PolicePursuitRadar.asi` is an x86 PE DLL with an `.asi`
extension. The source currently has no generated binary checked in because the
workspace does not contain a Windows GTA installation or the SDK build output.

## Installation

Copy these two files to the loader-supported scripts directory:

```text
GTA San Andreas/
└── scripts/
    ├── PolicePursuitRadar.asi
    └── PolicePursuitRadar.ini
```

If the loader requires ASI files beside `gta_sa.exe`, put both files there
instead. The plugin resolves the INI and log beside its own module, so the two
files always stay together.

## Configuration

`config/PolicePursuitRadar.ini` is the default configuration. Values are
validated while loading: tracking distance is limited to 50–2500 m, update
intervals to 16–2000 ms, the lost-contact delay to 250–10000 ms, and the search
ring to 16–128 segments. Invalid or missing values fall back to defaults and
are reported in `PolicePursuitRadar.log`.

Press F11 once to reload the INI. The hotkey only reacts to the key-down edge
and can be disabled with:

```ini
[Input]
ReloadHotkeyEnabled=false
```

`ShowOnPauseMap` is disabled by default. Interior, loading/fade, hidden-radar,
pause-menu and cutscene/fade states suppress the custom layer; when the game
does not expose a valid exterior radar context, the plugin draws nothing.

## Detection and state algorithm

1. `WantedStateProvider` reads `FindPlayerWanted(0)` and the current
   `CWanted` fields. Back-off flags, missing player state and inactive vanilla
   wanted state gate the tracker.
2. `PoliceTracker` treats `m_pCopsInPursuit` as the authoritative active-cop
   list, then scans the live ped and vehicle pools only to associate those cops
   with their current vehicles. Vehicles are supplemented when the SDK's
   `bIsLawEnforcer` or a verified police mission state identifies an active
   pursuit. Ordinary patrol peds are not promoted to pursuit units.
3. `PoliceVisibilitySystem` checks no more than eight prioritized active units
   every visibility interval. It uses each entity's area code and
   `CWorld::GetIsLineOfSightClear` against the player; it does not use a
   distance-only detection rule.
4. On contact, `lastKnownPlayerPosition` follows the player. When contact is
   lost, `LosingContact` waits for `LostSightDelayMs`; `Searching` then freezes
   that position until a new LOS contact occurs.
5. `SearchAreaRenderer` generates a world-space circle, transforms all points
   through `CRadar::TransformRealWorldPointToRadarSpace`, clips polygon edges
   against the radar's unit circle, and transforms the result to screen space.
   It draws the fill first and the police markers later in `drawBlipsEvent`.

The plugin uses SDK structures and functions rather than custom addresses. In
particular it uses `CWanted`, `CPools`, `CWorld`, `CVehicle`, `CCopPed`,
`CAutoPilot`, `CRadar`, `CTimer` and the SDK render/event APIs. It does not
modify `CCarAI`, `m_pCopsInPursuit`, wanted level, mission data or entity pools.

## Debugging

Set:

```ini
[Debug]
Enabled=true
LogTrackedUnits=true
ShowSearchCenter=true
ShowPoliceLOS=true
```

The compact debug readout shows wanted level, state, unit count, cops in
pursuit, detection, frozen position and search radius. The log contains the
plugin initialization, detected game version, configuration warnings, tracked
unit summaries and unsupported-version errors. It intentionally does not log
every frame or every LOS raycast.

With `ShowPoliceLOS=true`, radar unit markers use green for a cached LOS hit and
red for a cached LOS miss. This is deliberately limited to the radar and does
not add world-space markers that could be mistaken for gameplay data.

## Compatibility and known limits

- The target is the classic 1.0 US x86 executable only. A different version is
  rejected before game data is read.
- The implementation uses the game's RenderWare/D3D9 device and restores the
  RenderWare blend, texture, depth and D3D scissor state after drawing.
- The state is rebuilt after pool shutdown and game reinitialization. Tracked
  entities are short-lived pool observations, not long-lived owned pointers.
- Pause-map drawing is optional and disabled by default. Full-map scaling is
  intentionally not enabled unless `ShowOnPauseMap=true`.
- SilentPatch, Widescreen Fix and ModLoader are expected to coexist because no
  vanilla radar textures or radar functions are patched. A different plugin
  that replaces the same radar draw event may still change draw order.
- Wine should work when GTA SA runs through a 32-bit Wine prefix with a
  compatible ASI loader. This source does not add managed or graphics runtime
  dependencies, but actual loader/prefix behavior remains installation-specific.

## License

The new source files in this directory are released under the MIT License.
plugin-sdk remains under its own license and is consumed from the external
checkout named by `PLUGIN_SDK_DIR`.
