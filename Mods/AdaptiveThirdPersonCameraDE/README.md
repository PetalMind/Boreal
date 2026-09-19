# Adaptive Third-Person Camera DE

Contextual third-person camera for **Grand Theft Auto: San Andreas – The
Definitive Edition**. It follows movement intent and vehicle travel instead of
using one fixed camera distance for every situation.

## What is implemented

- On-foot presets for idle, walk, jog, sprint and aim.
- Smooth spring movement for both camera position and look target.
- Look-ahead that grows with sprint/car speed, placing the player lower in the
  frame and showing more of the road ahead.
- Vehicle distance that grows with speed: slow car, normal car and fast car
  profiles use the ranges described in the design note.
- Separate presets for cars, motorcycles, bicycles, boats, helicopters and
  aircraft.
- Camera Director handoff between vehicle, on-foot and other anchors. Ordinary
  changes use a configurable 320 ms world-space transition and preserve a
  damped portion of the previous spring velocity.
- `IS_CHAR_SITTING_IN_ANY_CAR` and `IS_CHAR_IN_ANY_CAR` are interpreted as
  separate states: driving, entering, exiting and on foot.
- Manual camera input has priority. The normal game camera is free for 1.2 s,
  then the adaptive camera blends back instead of taking control immediately.
  Recenter delay scales from about 2.0 s at low speed to 0.8 s at high speed.
- Motion analysis includes filtered acceleration, slip angle, velocity
  prediction, speed-scaled steering look-ahead, reverse hysteresis and an
  airborne/landing state for ground vehicles.
- Horizontal and vertical spring response are separated. Cars follow bumps and
  jumps more conservatively on the Z axis, keeping the horizon stable.
- Camera collision uses a cached 30 Hz center probe and a five-point probe
  envelope near obstacles. Inward correction is faster than the return after
  the path becomes clear.
- Aim camera shoulder swap is attempted when the current shoulder is blocked,
  with a cooldown to avoid oscillation.
- Configuration reload with `F11` and a global enable/disable toggle with
  `F9`.

## Important SA:DE capability boundary

The official `sa_unreal` command definition exposes `GET_CAMERA_FOV`, but does
not expose a supported `SET_CAMERA_FOV` native. The INI therefore keeps the
requested FOV targets as profile data and logs the active target for diagnosis,
but the script does not claim to change the game's FOV. It also does not use a
classic GTA SA memory address, because that address is not a verified contract
for the 64-bit Unreal executable.

The camera position and target are real scriptable camera operations using
`SET_FIXED_CAMERA_POSITION` and `POINT_CAMERA_AT_POINT`. The collision path is
real LOS data, not a visual approximation.

Vehicle ownership is based on the seated state (`IS_CHAR_SITTING_IN_ANY_CAR`),
not only on the broader `IS_CHAR_IN_ANY_CAR` condition. The latter also remains
true while a character is opening or closing a vehicle door, which would keep
the camera anchored to the vehicle during the exit transition.

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
- Move the mouse or right stick strongly: return control to the normal game
  camera. The adaptive camera waits, respects a speed-dependent recenter delay
  and blends back over `manual_blend_ms`.

Distances and heights are stored in centimetres in the INI. The state machine
uses the following starting values:

| State | Distance | Height | FOV target |
| --- | ---: | ---: | ---: |
| Walk | 3.5 m | 1.5 m | 66° |
| Jog | 4.0 m | 1.5 m | 70° |
| Sprint | 4.6 m | 1.4 m | 74° |
| Aim | 2.7 m | 1.45 m | 58° |
| Car slow | 6.2 m | 2.2 m | 71° |
| Car normal | 7.2 m | 2.25 m | 75° |
| Car fast | 8.8 m | 2.4 m | 79° |
| Motorbike | 5.6 m → 5.0 m | 1.9 m → 1.7 m | 75° → 78° |
| Aircraft | 15 m | 5 m | 79° |

`position_stiffness` and `position_damping` control horizontal spring response.
`vertical_tracking_percent` limits how strongly vehicle height changes reach the
camera; `airborne_vertical_tracking_percent` applies while jumping. The
collision cache uses `collision_update_ms` and the probe envelope uses
`collision_probe_radius_cm`. Higher `drift_velocity_influence_percent` makes
the camera follow actual velocity more strongly during a slide. Reverse enter
and exit holds prevent rapid front/back toggling while parking.

## Safety and scope

This is a single-player camera script. It does not change player physics,
vehicle handling, weapons, missions, save data, multiplayer state or anti-cheat
behavior. When the script is disabled, the camera is explicitly restored with
the public camera reset natives.

The repository does not contain a GTA SA:DE runtime, so an in-game camera
smoke test is not claimed here. The FOV profile still has a spring for
diagnostics, but the official SA:DE command set exposes no supported
`SET_CAMERA_FOV`; the game FOV is therefore not changed by this script.
