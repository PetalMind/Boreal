# Adaptive Third-Person Camera DE

Pełna dokumentacja techniczna znajduje się w
[DOCUMENTATION.md](DOCUMENTATION.md).

Contextual third-person camera for **Grand Theft Auto: San Andreas – The
Definitive Edition**. It follows movement intent and vehicle travel instead of
using one fixed camera distance for every situation.

## What is implemented

- On-foot presets for idle, walk, jog, sprint and aim.
- Smooth spring movement for both camera position and look target.
- Look-ahead that grows with sprint/car speed, placing the player lower in the
  frame and showing more of the road ahead.
- WD2-oriented on-foot and vehicle presets: speed adds FOV/look-ahead before it
  adds substantial distance, keeping CJ and the car large in frame.
- Separate presets for cars, motorcycles, bicycles, boats, helicopters and
  aircraft.
- Camera Director handoff between vehicle, on-foot and other anchors. Ordinary
  changes use a configurable 320 ms anchor/profile transition and preserve a
  damped portion of the previous spring velocity before feeding one camera
  spring.
- `IS_CHAR_ON_FOOT`, `IS_CHAR_SITTING_IN_ANY_CAR` and `IS_CHAR_IN_ANY_CAR` are
  interpreted as separate signals for the latched driving, entering, exiting
  and on-foot states. The on-foot signal has priority so a stale vehicle-use
  result cannot keep the camera attached after an exit.
- Manual camera input has priority without restoring the standard camera. The
  adaptive camera follows the user's yaw/pitch for 1.1 s, then blends back
  instead of taking control immediately. Recenter delay scales from about
  1.8 s at low speed to 0.65 s at high speed.
- Motion analysis uses `Car.GetSpeedVector` / `Char.GetVelocity` first, with
  position delta only as a fallback. It includes dt-aware acceleration,
  slip angle, velocity prediction, reverse hysteresis and airborne/landing.
- Horizontal and vertical spring response are separated. Cars follow bumps and
  jumps more conservatively on the Z axis, keeping the horizon stable.
- Camera collision uses a cached 30 Hz result, a six-step center-ray search and
  one five-point envelope check. Center/top/bottom are hard requirements;
  side probes are soft. Vehicle cameras check static world geometry while
  excluding cars, because SA:DE LOS cannot exclude only the player's vehicle.
- Configuration reload with `F11` and a global enable/disable toggle with
  `F9`.

## Important SA:DE capability boundary

The official `sa_unreal` command definition exposes `Camera.GetFov` and
`Camera.SetLerpFov`. The script probes that pair once per session by requesting
a small 5-degree change and reading the value back. Profile FOV is applied only
after successful readback; otherwise FOV changes stay disabled for the session.
No classic GTA SA memory address is used.

The camera position and target are real scriptable camera operations using
`SET_FIXED_CAMERA_POSITION` and `POINT_CAMERA_AT_POINT`. The collision path is
real LOS data, not a visual approximation.

Vehicle ownership is cleared whenever `IS_CHAR_ON_FOOT` becomes true. While
the ped is not on foot, the seated state (`IS_CHAR_SITTING_IN_ANY_CAR`) and the
broader `IS_CHAR_IN_ANY_CAR` family provide compatible driving/transition
signals. This ordering matters because the broader condition can remain true
while a character is opening or closing a door, and the seated condition is
not reliable in every CLEO Redux SA:DE build.

The full `CAMERA_RESET_NEW_SCRIPTABLES` → `RESTORE_CAMERA` path remains a
safety fallback for cutscenes, fades, death, missing entities and large
teleports. It is not used for an ordinary vehicle-to-on-foot handoff.

## Requirements

- PC release of GTA San Andreas: The Definitive Edition supported by CLEO
  Redux.
- [CLEO Redux x64 1.5.0+](https://github.com/cleolibrary/CLEO-Redux/releases).
- Ultimate ASI Loader x64 installed as `version.dll`.
- `IniFiles64.cleo` in `CLEO/CLEO_PLUGINS` for the persistent INI.

## Installation

With Boreal, import `AdaptiveThirdPersonCameraDE.zip` from this directory in
the game's Mods view. The archive contains the CLEO script and INI, and Boreal
deploys them to:

```text
Gameface/Binaries/Win64/CLEO/adaptive_third_person_camera[fs].js
Gameface/Binaries/Win64/CLEO/AdaptiveThirdPersonCamera.ini
```

For manual installation:

```sh
chmod +x install.sh
./install.sh "/path/to/GTA San Andreas - The Definitive Edition"
```

The installer verifies the executable and runtime, keeps a timestamped backup
when replacing the script, and never overwrites an existing user INI.

## Controls and configuration

- `F9`: enable/disable the adaptive camera.
- `F11`: reload `AdaptiveThirdPersonCamera.ini`.
- The in-game `Change Camera` action (`V` by default) while in a vehicle:
  cycle the Close, Standard and Wide layouts. The script observes the native
  in-car mode so remapped/controller input works; physical `V` is only a
  keyboard fallback if the fixed camera blocks that native state change. The
  controller Select/Back button is also accepted as a physical fallback.
- Move the mouse or right stick strongly: take manual control of the adaptive
  camera. It waits, respects a speed-dependent recenter delay and blends back
  over `manual_blend_ms`.

Distances and heights are stored in centimetres in the INI. The state machine
uses the following starting values:

| State | Distance | Height | FOV target |
| --- | ---: | ---: | ---: |
| Idle | 3.65 m | 1.65 m | 72° |
| Walk | 3.8 m | 1.62 m | 73° |
| Jog | 4.15 m | 1.58 m | 75° |
| Sprint | 4.55 m | 1.52 m | 77° |
| Aim | native camera | native | 59° |
| Car slow | 5.25 m | 1.85 m | 74° |
| Car normal | 5.65 m | 1.95 m | 76° |
| Car fast | 6.1 m → 6.45 m | 2.05 m → 2.12 m | 79° → 81° |
| Motorbike | 5.6 m → 5.0 m | 1.9 m → 1.7 m | 75° → 78° |
| Aircraft | 15 m | 5 m | 79° |

`position_frequency_hz_x100` and `position_damping_ratio_percent` control the
stable horizontal spring response. `vertical_tracking_percent` limits how
strongly vehicle height changes reach the camera;
`airborne_vertical_tracking_percent` applies while jumping. The collision cache
uses `collision_update_ms`, the probe envelope uses
`collision_probe_radius_cm`. Higher `drift_velocity_influence_percent` makes
the camera follow actual velocity more strongly during a slide, while
`drift_distance_cm` controls its additional drift distance. Reverse enter and
exit holds prevent rapid front/back toggling while parking. Vehicle yaw uses a
120 ms follow delay, 70% follow strength and a maximum 7-degree steering bias.

## Safety and scope

This is a single-player camera script. It does not change player physics,
vehicle handling, weapons, missions, save data, multiplayer state or anti-cheat
behavior. When the script is disabled, the camera is explicitly restored with
the public camera reset natives.

While the player aims on foot, the mod releases its fixed XYZ camera and leaves
position, pitch and targeting fully under GTA's native aiming camera. It does
not call `Camera.SetPositionUnfixed`: runtime verification in SA:DE showed that
repeated calls can force the aim upward and block manual pitch. Aim FOV uses
only the capability-probed lerped FOV command. The adaptive camera resumes
after a 230 ms handoff when aiming ends.

The repository does not contain a GTA SA:DE runtime, so an in-game camera
smoke test is not claimed here. FOV application is capability-gated: the mod
uses `Camera.SetLerpFov`/`CAMERA_SET_LERP_FOV` when available and otherwise
keeps the profile target for diagnostics without claiming a visual FOV change.
