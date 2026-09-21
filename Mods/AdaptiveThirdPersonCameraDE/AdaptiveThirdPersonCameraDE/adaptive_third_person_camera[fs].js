/// <reference path="./.config/sa.d.ts" />

// Adaptive Third-Person Camera for GTA San Andreas: The Definitive Edition.
// Runtime: CLEO Redux x64 + IniFiles64.
//
// Driving-only camera. GTA owns all on-foot movement and aiming.
// Public SA:DE natives only; no physics writes or classic-SA memory offsets.
// Speed, acceleration, yaw rate and slip shape a damped road-focused camera.
// Reverse keeps the same side of the vehicle; manual input overrides follow.

if (HOST !== "sa_unreal") {
  exit("Adaptive Third-Person Camera supports only GTA San Andreas: The Definitive Edition.");
}

const PLAYER_ID = 0;
const CONFIG_PATH = "./AdaptiveThirdPersonCamera.ini";
const CONFIG_VERSION = 2;
const MOD_BUILD_ID = "ATC-DE-20260921-41-frame-rate-independent-anchor";
const VK_TOGGLE = 120; // F9.
const VK_RELOAD = 122; // F11.
const VK_CAMERA_DISTANCE = 116; // F5.
const KEY_V = 0x56;
const RIGHT_MOUSE_BUTTON = 2;
const PAD_ID = 0;
const AIM_BUTTON = 6; // GTA action: Aim (controller LT/L2).
const CONTROLLER_VIEW_BUTTON = 13; // Physical Select/Back fallback.

const VEHICLE_CAMERA_LAYOUT_NAMES = ["Close", "Standard", "Wide"];
const VEHICLE_CAMERA_LAYOUTS = [
  { name: "Close", distance: 0.82, height: -0.15, targetHeight: 0 },
  { name: "Standard", distance: 1.00, height: 0, targetHeight: 0 },
  { name: "Wide", distance: 1.18, height: 0.30, targetHeight: 0 },
];
const VEHICLE_LAYOUT_BLEND_MS = 280;
const MIN_CAMERA_RELATIVE_Z = 0.40;
const VEHICLE_MANUAL_MOUSE_ACTIVATION_MIN = 0.25;
const VEHICLE_MANUAL_STICK_ACTIVATION_MIN = 24;
const VEHICLE_MANUAL_STICK_CONFIRM_FRAMES = 2;
const VEHICLE_MANUAL_ACQUIRE_GRACE_MS = 420;
const MANUAL_INPUT_DIAGNOSTIC_MS = 500;
// v28 mouse bridge. On this SA:DE/Wine build GET_PC_MOUSE_MOVEMENT becomes a
// synthetic near-diagonal signal while a fixed CLEO camera owns the transform.
// Instead of integrating that broken signal, a confident gesture temporarily
// releases camera ownership back to GTA, where native mouse-look is correct.
const NATIVE_MOUSE_BRIDGE_TRIGGER_VARIATION = 0.82;
const NATIVE_MOUSE_BRIDGE_TRIGGER_RESIDUAL = 1.05;
const NATIVE_MOUSE_BRIDGE_TRIGGER_CURSOR_PIXELS = 1.0;
// v31: Input64 exposes WinAPI GetCursorPos/SetCursorPos. While the scripted
// camera owns the view we turn those absolute coordinates into a relative
// mouse source by returning the cursor to a stable anchor every frame. This is
// deliberately separate from Mouse.GetMovement(), which is synthetic/diagonal
// on this SA:DE + Wine setup.
const RELATIVE_CURSOR_ENABLED = true;
const RELATIVE_CURSOR_MAX_DELTA_PIXELS = 120;
const RELATIVE_CURSOR_ACTIVATION_PIXELS = 0.75;
const RELATIVE_CURSOR_TO_MOUSE_UNITS = 0.62;
const RELATIVE_CURSOR_REANCHOR_DISTANCE = 260;
const NATIVE_MOUSE_BRIDGE_MIN_HOLD_MS = 260;
const NATIVE_MOUSE_BRIDGE_IDLE_RELEASE_MS = 620;
const NATIVE_MOUSE_BRIDGE_MAX_HOLD_MS = 15000;
// Vehicle free-look must not bounce between native and scripted ownership every
// few hundred milliseconds. Keep native ownership sticky after a real mouse
// gesture and only hand back once the view has been idle for long enough.
const VEHICLE_MOUSE_BRIDGE_MIN_HOLD_MS = 420;
const VEHICLE_MOUSE_BRIDGE_IDLE_RELEASE_MS = 1800;
const VEHICLE_MOUSE_BRIDGE_HIGH_SPEED_IDLE_RELEASE_MS = 3000;
const VEHICLE_MOUSE_BRIDGE_HIGH_SPEED_KMH = 60;
const VEHICLE_MOUSE_BRIDGE_REENTRY_COOLDOWN_MS = 420;
// Mouse deltas are already frame deltas, so they are applied directly.
// Analogue-stick values represent a held deflection and therefore drive an
// angular velocity that is multiplied by dt. Keeping those paths separate
// makes controller free-look independent of frame rate.
const MANUAL_MOUSE_YAW_RADIANS_PER_UNIT = 0.0055;
const MANUAL_MOUSE_PITCH_RADIANS_PER_UNIT = 0.0036;
const MANUAL_STICK_YAW_RADIANS_PER_SECOND = (155 * Math.PI) / 180;
const MANUAL_STICK_PITCH_RADIANS_PER_SECOND = (110 * Math.PI) / 180;
const VEHICLE_MIN_ORBIT_PITCH = -0.20;
const VEHICLE_MAX_ORBIT_PITCH = 0.65;
const CameraControl = {
  AUTO: 0,
  MANUAL: 1,
};
const COLLISION_EMERGENCY_GRACE_MS = 220;
const VEHICLE_ANCHOR_ACQUIRE_MS = 120;
const VEHICLE_ENTER_FALLBACK_MS = 1400;
const PLAYER_ORIGIN_GLITCH_RADIUS = 0.75;
const PLAYER_ORIGIN_CONTINUITY_GUARD_MS = 1800;
const PLAYER_ORIGIN_CONTINUITY_DISTANCE = 25;
const MANUAL_COLLISION_UPDATE_MS = 16;
const SPRING_PATH_VALIDATION_MS = 33;
const CAMERA_GROUND_CLEARANCE = 0.35;
const VEHICLE_SPEED_FILTER_TIME_CONSTANT = 0.10;
// Camera composition reacts more slowly than gameplay state. A separate
// profile-speed filter prevents small/high-frequency velocity errors from
// repeatedly pulling the camera in/out at high speed.
const VEHICLE_CAMERA_SPEED_FILTER_TIME_CONSTANT = 0.28;
const VEHICLE_DRIFT_FILTER_TIME_CONSTANT = 0.30;
const AIRBORNE_CONFIRM_MS = 120;
// SA:DE can report a small persistent GET_PC_MOUSE_MOVEMENT vector even while
// the physical mouse is idle (observed around 1.7,1.7). Learn that idle bias
// during camera acquisition and subtract it before deciding user intent.
const MOUSE_BASELINE_TRACK_ALPHA = 0.12;
const MOUSE_BASELINE_CALIBRATION_ALPHA = 0.35;
const MOUSE_BASELINE_MAX_LEARN_DELTA = 5.5;
const MOUSE_RESIDUAL_DEADZONE = 0.35;
// The DE binding can sit on a stable +3,+3-ish value even with the physical
// mouse idle. v22 distinguishes that stable signature from actual movement
// using temporal variation and, when available, OS cursor displacement.
const MOUSE_IDLE_DIAGONAL_MAX_MAGNITUDE = 5.5;
const MOUSE_IDLE_DIAGONAL_AXIS_DELTA = 0.40;
const MOUSE_RAW_VARIATION_TRIGGER = 0.70;
const MOUSE_RAW_STABLE_VARIATION = 0.35;
const MOUSE_GESTURE_LATCH_MS = 180;
const MOUSE_CURSOR_TRIGGER_PIXELS = 2.0;
const MOUSE_CURSOR_MAX_DELTA_PIXELS = 120;
const MOUSE_CURSOR_TO_DELTA_SCALE = 0.35;
const VEHICLE_HIGH_SPEED_SPRING_START_KMH = 70;
const VEHICLE_HIGH_SPEED_SPRING_FULL_KMH = 160;
const VEHICLE_HIGH_SPEED_SPRING_MAX_BOOST = 1.28;
const VEHICLE_HIGH_SPEED_MAX_RELATIVE_LAG_LOW = 1.60;
const VEHICLE_HIGH_SPEED_MAX_RELATIVE_LAG_HIGH = 0.90;
const VEHICLE_VISUAL_ANCHOR_START_KMH = 70;
const VEHICLE_VISUAL_ANCHOR_FULL_KMH = 155;
const VEHICLE_VISUAL_ANCHOR_RESET_DISTANCE = 3.0;
const VEHICLE_VISUAL_ANCHOR_MAX_ERROR_LOW = 0.18;
const VEHICLE_VISUAL_ANCHOR_MAX_ERROR_HIGH = 0.55;
const VEHICLE_DIRECTION_FILTER_TIME_CONSTANT = 0.13;
const VEHICLE_TURN_FILTER_TIME_CONSTANT = 0.10;
// Corner preview is driven by turn rate, not only by the already-rotated
// vehicle heading. It must become visible before a fast bend is completed.
const VEHICLE_CORNER_PREVIEW_MIN_KMH = 6;
const VEHICLE_CORNER_PREVIEW_FULL_KMH = 55;
const VEHICLE_CORNER_PREVIEW_ACTIVATION_MIN_KMH = 2;
const VEHICLE_CORNER_PREVIEW_ACTIVATION_FULL_KMH = 14;
const VEHICLE_CORNER_TURN_RATE_REFERENCE_DEG = 92;
const VEHICLE_CORNER_STEERING_PREVIEW_DEG = 7;
const VEHICLE_CORNER_PREVIEW_EXTRA_LEAD_M = 0.65;
const VEHICLE_CORNER_LATERAL_LEAD_M = 0.35;
const VEHICLE_MOUSE_BRIDGE_RAW_AXIS_SEPARATION = 0.75;
const HIGH_SPEED_DIAGNOSTIC_MS = 1000;
// v23: On this SA:DE/Wine setup Mouse.GetMovement() is not a trustworthy
// physical-mouse signal: logs show equal X/Y synthetic values while the OS
// cursor remains stationary. The vehicle path therefore keeps scripted camera
// ownership only when explicitly configured, and the native backend remains
// available as a fallback. The scripted path does not use that synthetic mouse
// value to predict vehicle direction; corner preview comes from vehicle motion.
const NATIVE_VEHICLE_TWEAK_UPDATE_MS = 140;
// Five hysteretic speed bands make the native vehicle camera evolve more
// gradually than the old 3-step setup without rewriting opcode 09EF every
// frame. Context (drift/acceleration/airborne) is quantized separately.
const NATIVE_VEHICLE_SPEED_BUCKETS = [45, 80, 120, 155];
// F5/V changes the profile owned by this script. Do not call
// SetPlayerInCarMode here: its values are GTA camera modes (including
// Top-Down), not Close/Standard/Wide distances, and changing that native
// mode would create a second owner for the rendered camera transform.

const VEHICLE_MODELS = {
  motorcycles: new Set([448, 461, 462, 463, 468, 471, 521, 522, 523, 581]),
  bicycles: new Set([481, 509, 510]),
};

const DEFAULTS = {
  enabled: true,
  manualOverride: true,
  manualOverrideThreshold: 24,
  manualFreeMs: 1100,
  manualBlendMs: 900,
  recenterLowSpeedMs: 2200,
  recenterNormalSpeedMs: 1300,
  recenterHighSpeedMs: 900,
  anchorTransitionMs: 280,
  collisionEnabled: true,
  collisionProbeRadius: 0.22,
  collisionUpdateMs: 33,
  reloadHotkeyEnabled: true,
  toggleHotkeyEnabled: true,
  verticalTracking: 0.50,
  airborneVerticalTracking: 0.22,
  positionFrequencyHz: 4.4,
  positionDampingRatio: 1.0,
  targetFrequencyHz: 6.5,
  targetDampingRatio: 1.0,
  collisionFrequencyHz: 8.0,
  collisionDampingRatio: 1.0,
  nativeVehicleCamera: false,
  nativeVehicleDynamicFov: true,
  nativeVehicleContextualTweak: true,
  driftVelocityInfluence: 0.28,
  driftMinSpeedKmh: 22,
  driftDistance: 0.25,
  vehicleYawDelayMs: 150,
  vehicleYawFollowStrength: 0.85,
  maxSteeringYawBiasDegrees: 3,
  vehicleManualCornerPreviewWeight: 0,
  cornerPreviewSeconds: 0.48,
  cornerPreviewMaxDegrees: 18,
  cornerTargetMaxOffset: 1.2,
  manualAutoRecenter: true,
  reverseMinSpeedKmh: 3,
  reverseEnterHoldMs: 280,
  reverseExitHoldMs: 420,
  reverseExitSpeedKmh: 4,
  accelerationFilterAlpha: 0.12,
  airborneEnterVerticalSpeed: 9 / 3.6,
  airborneExitVerticalSpeed: 4 / 3.6,
  landingMinAirborneMs: 180,
  landingDurationMs: 220,
  vehicleDriftFovBoost: 1.2,
  vehicleAccelerationFovBoost: 1.8,
  vehicleBrakingFovReduction: 0.8,
  collisionSafetyMargin: 0.20,
  collisionEmergencyDistance: 1.45,
  velocityDirectionThresholdMps: 0.35,
  // Distances are stored in metres here and as centimetres in the INI file.
  carSlowDistance: 5.25,
  carSlowHeight: 1.85,
  carSlowFov: 74,
  carNormalDistance: 5.65,
  carNormalHeight: 1.90,
  carNormalFov: 78,
  carFastDistance: 5.95,
  carFastHeight: 1.95,
  carFastFov: 84,
  motorbikeDistance: 5.6,
  motorbikeHeight: 1.9,
  motorbikeFov: 77,
  bicycleDistance: 4.8,
  bicycleHeight: 1.7,
  bicycleFov: 73,
  boatDistance: 8.6,
  boatHeight: 2.7,
  boatFov: 77,
  helicopterDistance: 12.5,
  helicopterHeight: 4.0,
  helicopterFov: 79,
  aircraftDistance: 15.0,
  aircraftHeight: 5.0,
  aircraftFov: 80,
};

const player = new Player(PLAYER_ID);
let config = { ...DEFAULTS };
let cameraApplied = false;
let springPosition = null;
let springPositionVelocity = { x: 0, y: 0, z: 0 };
let springTarget = null;
let springTargetVelocity = { x: 0, y: 0, z: 0 };
let lastActorSample = null;
let lastFrameAt = getGameTimerMs();
let manualFreeUntil = 0;
let manualRecenterUntil = 0;
let manualControlActive = false;
let vehicleManualStickFrames = 0;
let vehicleManualInputSuppressedUntil = 0;
let lastManualInputDiagnosticAt = 0;
let lastHighSpeedDiagnosticAt = 0;
let mouseMovementBaselineX = null;
let mouseMovementBaselineY = null;
let mouseBaselineCalibrateUntil = 0;
let previousRawMouseX = null;
let previousRawMouseY = null;
let previousMouseCursorPosition = null;
let relativeMouseAnchor = null;
let relativeMouseSetCursorAvailable = null;
let relativeMouseObservedMotion = false;
let lastRelativeMouseMotionAt = 0;
let mouseGestureUntil = 0;
let nativeMouseBridgeActive = false;
let nativeMouseBridgeEnteredAt = 0;
let nativeMouseBridgeLastGestureAt = 0;
let nativeMouseBridgeAnchorKey = "";
let nativeMouseBridgeSuppressedUntil = 0;
let lastNativeMouseBridgeDiagnosticAt = 0;
let vehicleVisualAnchor = null;
let vehicleVisualAnchorVelocity = { x: 0, y: 0, z: 0 };
let vehicleVisualAnchorIdentity = null;
let nativeVehicleTweakActive = false;
let nativeVehicleTweakModel = -1;
let nativeVehicleTweakKey = "";
let nativeVehicleSpeedBucket = 0;
let nativeVehicleTweakCapability = null;
let lastNativeVehicleTweakAt = 0;
let nativeCameraFovActive = false;
let vehicleCameraControl = CameraControl.AUTO;
let vehicleOrbitYaw = null;
let vehicleOrbitPitch = 0;
let vehicleRecenterStartedAt = 0;
let vehicleRecenterFromYaw = null;
let vehicleRecenterFromPitch = 0;
// World-space springs are transported by the vehicle's translation each
// frame. The spring then smooths only the camera's relative offset/orientation
// instead of physically lagging metres behind a fast-moving car.
let springAnchorPosition = null;
let anchorTransition = null;
let vehicleFollowDirection = null;
let reverseState = false;
let reverseCandidateSince = 0;
let forwardCandidateSince = 0;
let landingUntil = 0;
let airborneSince = 0;
let interactionState = "onFoot";
let interactionStateStartedAt = 0;
let collisionCache = null;
let collisionEmergencySince = 0;
let lastSpringPathValidationAt = 0;
let lastToggleDown = false;
let lastReloadDown = false;
let lastCameraDistanceDown = false;
let lastVehicleCameraDown = false;
let keyboardInputCapability = null;
let cameraPoseDiagnosticLogged = false;
let lastLayoutDiagnosticRevision = -1;
let lastVehicleGeometryDiagnosticKey = null;
let lastInvalidVehicleAnchorDiagnosticAt = 0;
let lastInvalidPlayerAnchorDiagnosticAt = 0;
let lastPedestrianRestoreDiagnosticAt = 0;
let lastReliablePlayerPosition = null;
let lastReliablePlayerPositionAt = 0;
let pedestrianRestoreArmedUntil = 0;
const cameraLayoutController = {
  layout: 1,
  observedNativeMode: null,
  source: "default",
  transition: null,
  revision: 0,

  requestNext(source) {
    const now = getGameTimerMs();
    const current = this.getParameters(now);
    this.layout = (this.layout + 1) % VEHICLE_CAMERA_LAYOUT_NAMES.length;
    this.source = source;
    this.transition = { from: current, startedAt: now };
    this.revision += 1;
    log(
      "Adaptive Third-Person Camera vehicle layout=" +
        VEHICLE_CAMERA_LAYOUT_NAMES[this.layout] +
        " (" + source + "; " +
        (config.nativeVehicleCamera ? "native tweak" : "script profile") + ")"
    );
  },

  getParameters(now) {
    const target = VEHICLE_CAMERA_LAYOUTS[this.layout] || VEHICLE_CAMERA_LAYOUTS[1];
    if (!this.transition) return target;
    const amount = smoothstep(
      0,
      VEHICLE_LAYOUT_BLEND_MS,
      now - this.transition.startedAt
    );
    const result = {
      name: target.name,
      distance: lerp(this.transition.from.distance, target.distance, amount),
      height: lerp(this.transition.from.height, target.height, amount),
      targetHeight: lerp(this.transition.from.targetHeight, target.targetHeight, amount),
    };
    if (amount >= 1) this.transition = null;
    return result;
  },

  observeNativeMode(mode) {
    if (!Number.isFinite(mode)) return;
    if (this.observedNativeMode === null) {
      this.observedNativeMode = mode;
      return;
    }
    if (mode !== this.observedNativeMode) {
      const previous = this.observedNativeMode;
      this.observedNativeMode = mode;
      log(
        "Adaptive Third-Person Camera observed native vehicle camera mode=" +
          mode + " (previous=" + previous + "; local layout unchanged)."
      );
    }
  },

  resetInputState() {
    lastCameraDistanceDown = false;
    lastVehicleCameraDown = false;
    this.observedNativeMode = null;
  },
};
let vehicleSessionFov = null;
let vehicleFovOwned = false;
let fovCapability = null;
let fovProbe = null;
let lastAppliedFovTarget = null;
let lastStateName = null;
let cameraSessionDisabled = false;

loadConfig();
keyboardInputCapability = probeInputCapability();
if (!keyboardInputCapability) {
  log("Adaptive Third-Person Camera: keyboard input API unavailable; F5/F9/F11 are disabled.");
}
log(
  "Adaptive Third-Person Camera loaded. build=" + MOD_BUILD_ID +
    "; scope=driving-only; onFoot=untouched" +
    "; vehicleBackend=" + (config.nativeVehicleCamera ? "hybrid-native" : "scripted+relative-mouse") +
    "; F5 cycles vehicle layouts; V cycles vehicle layouts; F9 toggles the camera; F11 reloads the INI."
);

while (true) {
  wait(0);

  const now = getGameTimerMs();
  const rawDt = Math.max(0, (now - lastFrameAt) / 1000);
  const dt = clamp(rawDt, 0.001, 0.05);
  lastFrameAt = now;
  if (rawDt > 0.08) {
    springPositionVelocity = scaleVector(springPositionVelocity, 0.10);
    springTargetVelocity = scaleVector(springTargetVelocity, 0.10);
  }
  handleHotkeys();

  if (
    !config.enabled ||
    !player.isPlaying() ||
    cameraTransitionIsActive() ||
    !isPlayerControlAvailable()
  ) {
    cameraLayoutController.resetInputState();
    releaseCamera();
    pedestrianRestoreArmedUntil = 0;
    lastActorSample = null;
    continue;
  }

  const actor = player.getChar();
  const sample = readActorSample(actor, now);
  if (!sample) {
    cameraLayoutController.resetInputState();

    // Losing the vehicle anchor while CJ is confirmed on foot is an ownership
    // boundary, not merely a missing sample. On SA:DE a normal RESTORE_CAMERA
    // can interpolate from the fixed vehicle camera through an invalid pose
    // during the exit animation. RestoreJumpcut plus SetBehindPlayer returns
    // ownership directly to the native pedestrian camera behind CJ.
    const exitState = readPlayerVehicleState(actor);
    const hadVehicleCameraSession = now <= pedestrianRestoreArmedUntil ||
      !!lastActorSample?.vehicle || cameraApplied || vehicleFovOwned ||
      vehicleSessionFov !== null || nativeMouseBridgeActive;
    const confirmedPedestrianExit = hadVehicleCameraSession && exitState.isOnFoot;
    releaseCamera(confirmedPedestrianExit);
    if (confirmedPedestrianExit) pedestrianRestoreArmedUntil = 0;
    if (confirmedPedestrianExit && now - lastPedestrianRestoreDiagnosticAt >= 500) {
      lastPedestrianRestoreDiagnosticAt = now;
      log(
        "Adaptive Third-Person Camera vehicle -> onFoot; " +
          "restored native pedestrian camera behind player with jumpcut."
      );
    }
    lastActorSample = null;
    continue;
  }

  // Keep a short-lived exit latch even if the DE wrapper drops the vehicle
  // handle one or two frames before IS_CHAR_ON_FOOT becomes authoritative.
  // Without this latch the first bad frame can clear lastActorSample and the
  // later confirmed on-foot frame would miss the jumpcut restoration.
  pedestrianRestoreArmedUntil = now + 3000;

  // During the enter animation, and for a short period after the game first
  // reports DRIVING, keep the native camera in charge. This avoids anchoring
  // the scripted camera to a door animation or an unstable vehicle handle.
  if (sample.interactionState === "entering" ||
      (sample.interactionState === "driving" && !sample.vehicle)) {
    cameraLayoutController.resetInputState();
    releaseCamera();
    lastActorSample = sample;
    continue;
  }

  handleVehicleCameraLayout(sample);
  if (!lastActorSample || cameraAnchorChanged(lastActorSample, sample)) {
    const previousAnchor = lastActorSample?.kind || "native";
    const nextAnchor = sample.vehicle ? sample.kind : "onFoot";
    beginAnchorTransition(sample, now);
    log(
      "Adaptive Third-Person Camera anchor changed " +
        previousAnchor +
        " -> " +
        nextAnchor +
        "; starting smooth handoff."
    );
  }

  if (isHardTeleport(lastActorSample, sample, rawDt)) {
    releaseCamera();
    lastActorSample = sample;
    log("Adaptive Third-Person Camera safety reset after a large anchor displacement.");
    continue;
  }

  // Snapshot before either camera backend writes a pose or FOV.
  if (vehicleSessionFov === null) {
    const nativeFov = getCameraFov();
    if (Number.isFinite(nativeFov)) vehicleSessionFov = nativeFov;
  }

  // Vehicle camera ownership can be native when explicitly configured. The log from
  // this runtime shows Mouse.GetMovement() returning a synthetic diagonal
  // value even while the physical cursor does not move. A fixed scripted
  // camera can therefore never offer reliable mouse orbiting here. Let GTA
  // own the vehicle transform/input and only apply coarse camera tweaks.
  if (sample.vehicle && config.nativeVehicleCamera) {
    // Do not call readManualCameraInput() in this branch. On this SA:DE/Wine
    // runtime GET_PC_MOUSE_MOVEMENT reports a synthetic diagonal signal and
    // cannot be used to drive a reliable scripted orbit. GTA therefore keeps
    // full ownership of vehicle orbit/input; CLEO only changes coarse follow
    // geometry through SET_VEHICLE_CAMERA_TWEAK.
    releaseScriptCameraForNativeOrbit();
    applyNativeVehicleCamera(sample, now);
    applyNativeVehicleDynamicEffects(sample, now);
    lastActorSample = sample;
    continue;
  } else if (!sample.vehicle) {
    resetNativeVehicleTweak();
  }

  const manualInput = readManualCameraInput(now);

  // v28: never integrate the unreliable DE mouse delta into the scripted
  // camera. A confident gesture is used only as a *handoff trigger*. GTA then
  // owns the camera while the mouse is active, giving us its real native
  // mouse-look. After a short idle period we capture that native orbit and
  // smoothly resume the dynamic scripted camera from the same view.
  const mouseBridgeGesture = config.manualOverride &&
    now >= nativeMouseBridgeSuppressedUntil &&
    isConfidentNativeMouseBridgeGesture(manualInput, sample);

  if (mouseBridgeGesture) {
    nativeMouseBridgeLastGestureAt = now;
    if (!nativeMouseBridgeActive) {
      enterNativeMouseBridge(sample, now, manualInput);
    }
  }

  if (nativeMouseBridgeActive) {
    const sameAnchor = nativeMouseBridgeAnchorKey === getMouseBridgeAnchorKey(sample);
    if (!sameAnchor) {
      cancelNativeMouseBridge();
    } else {
      releaseScriptCameraForNativeOrbit();
      if (sample.vehicle) {
        // Do not rewrite 09EF speed/drift buckets while native free-look owns
        // the camera. Those discrete native-camera changes were visible as
        // small pops during fast driving. Keep the currently selected native
        // view stable until the scripted camera takes over again.
        applyNativeVehicleDynamicEffects(sample, now);
      }

      const heldFor = now - nativeMouseBridgeEnteredAt;
      const idleFor = now - nativeMouseBridgeLastGestureAt;
      const releaseIdleMs = sample.vehicle
        ? ((sample.cameraSpeedKmh ?? sample.speedKmh) >= VEHICLE_MOUSE_BRIDGE_HIGH_SPEED_KMH
            ? VEHICLE_MOUSE_BRIDGE_HIGH_SPEED_IDLE_RELEASE_MS
            : VEHICLE_MOUSE_BRIDGE_IDLE_RELEASE_MS)
        : NATIVE_MOUSE_BRIDGE_IDLE_RELEASE_MS;
      const minimumHoldMs = sample.vehicle
        ? VEHICLE_MOUSE_BRIDGE_MIN_HOLD_MS
        : NATIVE_MOUSE_BRIDGE_MIN_HOLD_MS;
      const shouldRelease =
        heldFor >= minimumHoldMs &&
        (idleFor >= releaseIdleMs ||
          (!sample.vehicle && heldFor >= NATIVE_MOUSE_BRIDGE_MAX_HOLD_MS));

      if (!shouldRelease) {
        if (now - lastNativeMouseBridgeDiagnosticAt >= MANUAL_INPUT_DIAGNOSTIC_MS) {
          lastNativeMouseBridgeDiagnosticAt = now;
          log(
            "Adaptive Third-Person Camera native mouse bridge active" +
              " rawMouse=(" + manualInput.rawMouseX.toFixed(1) + "," + manualInput.rawMouseY.toFixed(1) + ")" +
              " variation=" + manualInput.rawVariation.toFixed(1) +
              " cursorDelta=(" + manualInput.cursorDeltaX.toFixed(1) + "," + manualInput.cursorDeltaY.toFixed(1) + ")" +
              " idleMs=" + idleFor.toFixed(0)
          );
        }
        lastActorSample = sample;
        continue;
      }

      exitNativeMouseBridge(sample, now);
    }
  }

  // Only trusted mouse deltas or confirmed right-stick input enter manual orbit.
  const directMouseIntent = config.manualOverride &&
    manualInput.mouseInputReliable &&
    manualInput.mouseMagnitude >= 0.28;

  if (directMouseIntent) {
    beginManualOverride(
      sample,
      { ...manualInput, stickX: 0, stickY: 0, stickMagnitude: 0 },
      now,
      dt
    );
  }

  const stickActivationThreshold = Math.max(
    VEHICLE_MANUAL_STICK_ACTIVATION_MIN,
    config.manualOverrideThreshold
  );
  const stickIntent = config.manualOverride &&
    manualInput.stickMagnitude >= stickActivationThreshold;
  vehicleManualStickFrames = stickIntent
    ? Math.min(VEHICLE_MANUAL_STICK_CONFIRM_FRAMES, vehicleManualStickFrames + 1)
    : 0;
  const confirmedStickIntent =
    vehicleManualStickFrames >= VEHICLE_MANUAL_STICK_CONFIRM_FRAMES;

  if ((mouseBridgeGesture || stickIntent || manualInput.rawVariation >= 0.70 ||
      Math.abs(manualInput.cursorDeltaX) >= 1 || Math.abs(manualInput.cursorDeltaY) >= 1) &&
      now - lastManualInputDiagnosticAt >= MANUAL_INPUT_DIAGNOSTIC_MS) {
    lastManualInputDiagnosticAt = now;
    log(
      "Adaptive Third-Person Camera input diagnostic" +
        " bridgeGesture=" + (mouseBridgeGesture ? "yes" : "no") +
        " rawMouse=(" + manualInput.rawMouseX.toFixed(1) + "," + manualInput.rawMouseY.toFixed(1) + ")" +
        " baseline=(" + manualInput.mouseBaselineX.toFixed(1) + "," + manualInput.mouseBaselineY.toFixed(1) + ")" +
        " residual=(" + manualInput.mouseX.toFixed(1) + "," + manualInput.mouseY.toFixed(1) + ")" +
        " variation=" + manualInput.rawVariation.toFixed(1) +
        " cursorDelta=(" + manualInput.cursorDeltaX.toFixed(1) + "," + manualInput.cursorDeltaY.toFixed(1) + ")" +
        " relative=" + (manualInput.relativeCursorActive ? "yes" : "no") +
        " reliableMouse=" + (manualInput.mouseInputReliable ? "yes" : "no") +
        " syntheticDiagonal=" + (manualInput.syntheticDiagonalSuppressed ? "suppressed" : "no") +
        " setCursor=" + (manualInput.relativeCursorAvailable ? "yes" : "no") +
        " stickMag=" + manualInput.stickMagnitude.toFixed(1)
    );
  }

  if (confirmedStickIntent) {
    // Suppress the broken mouse component when the right stick is the real
    // manual source.
    beginManualOverride(sample, { ...manualInput, mouseX: 0, mouseY: 0, mouseMagnitude: 0 }, now, dt);
  }

  if (cameraSessionDisabled) {
    releaseCamera();
    lastActorSample = sample;
    continue;
  }

  const autoFollowWeight = getAutoFollowWeight(sample, now);
  applyCameraDirector(sample, dt, now, autoFollowWeight);
  lastActorSample = sample;
}

function handleHotkeys() {
  if (config.reloadHotkeyEnabled) {
    const reloadDown = isKeyPressed(VK_RELOAD);
    if (reloadDown && !lastReloadDown) {
      if (loadConfig()) {
        cameraSessionDisabled = false;
        cameraLayoutController.resetInputState();
        releaseCamera();
        log("Adaptive Third-Person Camera configuration reloaded.");
      } else {
        log("Adaptive Third-Person Camera reload rejected; previous configuration retained.");
      }
    }
    lastReloadDown = reloadDown;
  }

  if (config.toggleHotkeyEnabled) {
    const toggleDown = isKeyPressed(VK_TOGGLE);
    if (toggleDown && !lastToggleDown) {
      config.enabled = !config.enabled;
      if (!config.enabled) releaseCamera();
      else cameraSessionDisabled = false;
      log("Adaptive Third-Person Camera: " + (config.enabled ? "enabled" : "disabled"));
    }
    lastToggleDown = toggleDown;
  }
}

function handleVehicleCameraLayout(sample) {
  if (!sample.vehicle) {
    cameraLayoutController.resetInputState();
    return;
  }

  // Native mode is observed for diagnostics only. It cannot be safely mapped
  // to the local Close/Standard/Wide index on every game build, so it must not
  // mutate the local layout by itself.
  cameraLayoutController.observeNativeMode(getPlayerInCarCameraMode());
  const cameraDown = isVehicleCameraControlActive();
  const distanceHotkeyDown = isKeyPressed(VK_CAMERA_DISTANCE);
  const distanceHotkeyPressed = distanceHotkeyDown && !lastCameraDistanceDown;

  if (distanceHotkeyPressed) {
    cameraLayoutController.requestNext("F5");
  } else if (!config.nativeVehicleCamera) {
    // Scripted backend historically used V/controller input as a local
    // Close/Standard/Wide cycle. In native backend mode GTA must receive V
    // untouched so its own camera/free-look state remains authoritative.
    const fallbackPressed = cameraDown && !lastVehicleCameraDown;
    if (fallbackPressed) cameraLayoutController.requestNext("V/controller fallback");
  }

  lastVehicleCameraDown = cameraDown;
  lastCameraDistanceDown = distanceHotkeyDown;
}

function applyRequestedFov(targetFov, durationMs, now) {
  targetFov = clamp(targetFov, 50, 90);
  if (fovCapability === false) return;

  if (fovProbe) {
    if (now - fovProbe.startedAt < 220) return;
    const measured = getCameraFov();
    fovCapability = Number.isFinite(measured) &&
      (measured - fovProbe.baseline) * (fovProbe.target - fovProbe.baseline) > 0 &&
      Math.abs(measured - fovProbe.target) < 0.8;
    log(
      "Adaptive Third-Person Camera: FOV lerp capability=" +
        (fovCapability ? "available" : "unavailable")
    );
    if (!fovCapability) {
      setLerpFov(Number.isFinite(measured) ? measured : fovProbe.baseline, fovProbe.baseline, 0);
    }
    fovProbe = null;
    lastAppliedFovTarget = null;
    if (!fovCapability) return;
  }

  if (fovCapability === null) {
    const baseline = getCameraFov();
    if (!Number.isFinite(baseline)) {
      fovCapability = false;
      log("Adaptive Third-Person Camera: FOV readback unavailable; FOV disabled for this session.");
      return;
    }
    const probeTarget = baseline > 50 ? baseline - 1.5 : baseline + 1.5;
    if (!setLerpFov(baseline, probeTarget, 150)) {
      fovCapability = false;
      log("Adaptive Third-Person Camera: FOV lerp binding unavailable; FOV disabled for this session.");
      return;
    }
    vehicleFovOwned = true;
    fovProbe = { baseline, target: probeTarget, startedAt: now };
    return;
  }

  if (lastAppliedFovTarget !== null && Math.abs(lastAppliedFovTarget - targetFov) < 0.35) {
    return;
  }
  const currentFov = getCameraFov();
  if (!Number.isFinite(currentFov)) return;
  if (setLerpFov(currentFov, targetFov, durationMs)) {
    vehicleFovOwned = true;
    lastAppliedFovTarget = targetFov;
  }
}

function getCameraFov() {
  try {
    if (typeof Camera !== "undefined" && typeof Camera.GetFov === "function") {
      return finiteNumber(Camera.GetFov(), NaN);
    }
  } catch (_) {}
  return finiteNumber(safeNative("GET_CAMERA_FOV"), NaN);
}

function setLerpFov(from, to, durationMs) {
  try {
    if (typeof Camera !== "undefined" && typeof Camera.SetLerpFov === "function") {
      Camera.SetLerpFov(from, to, durationMs, true);
      return true;
    }
  } catch (_) {}
  try {
    native("CAMERA_SET_LERP_FOV", from, to, durationMs, true);
    return true;
  } catch (_) {
    return false;
  }
}

function invokeCameraMethod(method, ...args) {
  try {
    if (typeof Camera !== "undefined" && typeof Camera[method] === "function") {
      Camera[method](...args);
      return true;
    }
  } catch (_) {}
  return false;
}

function resetScriptCamera() {
  invokeCameraMethod("PersistPos", false);
  invokeCameraMethod("PersistTrack", false);
  invokeCameraMethod("PersistFov", false);
  if (!invokeCameraMethod("ResetNewScriptables")) {
    safeNative("CAMERA_RESET_NEW_SCRIPTABLES");
  }
}

function restoreScriptCamera() {
  invokeCameraMethod("PersistPos", false);
  invokeCameraMethod("PersistTrack", false);
  invokeCameraMethod("PersistFov", false);
  if (!invokeCameraMethod("Restore")) {
    safeNative("RESTORE_CAMERA");
  }
}

function restorePedestrianCameraBehindPlayer() {
  if (invokeCameraMethod("SetBehindPlayer")) return true;
  try {
    native("SET_CAMERA_BEHIND_PLAYER");
    return true;
  } catch (_) {
    return false;
  }
}

function restoreScriptCameraJumpcut() {
  invokeCameraMethod("PersistPos", false);
  invokeCameraMethod("PersistTrack", false);
  invokeCameraMethod("PersistFov", false);

  let restored = false;
  if (invokeCameraMethod("RestoreJumpcut")) {
    restored = true;
  } else {
    try {
      native("RESTORE_CAMERA_JUMPCUT");
      restored = true;
    } catch (_) {
      // Older/partial definition sets may omit 02EB. The normal restore is a
      // safe fallback; the explicit behind-player handoff remains authoritative.
      restoreScriptCamera();
    }
  }

  return restorePedestrianCameraBehindPlayer() || restored;
}

function getPlayerInCarCameraMode() {
  try {
    if (typeof Camera !== "undefined" && typeof Camera.GetPlayerInCarMode === "function") {
      return finiteNumber(Camera.GetPlayerInCarMode(), NaN);
    }
  } catch (_) {}
  return finiteNumber(safeNative("GET_PLAYER_IN_CAR_CAMERA_MODE"), NaN);
}

function cameraAnchorChanged(previous, current) {
  if (!previous || !current) return false;

  const previousAnchor = previous.vehicle ? previous.kind : "onFoot";
  const currentAnchor = current.vehicle ? current.kind : "onFoot";
  if (previousAnchor !== currentAnchor) return true;

  // A mission/script can replace the player's vehicle without changing the
  // broad kind (car -> car). Treat a confirmed handle change as a new anchor
  // so velocity and springs are never carried between unrelated vehicles.
  if (previous.vehicle && current.vehicle &&
      previous.vehicleIdentity !== null && current.vehicleIdentity !== null) {
    return previous.vehicleIdentity !== current.vehicleIdentity;
  }
  return false;
}

function beginAnchorTransition(sample, now) {
  vehicleManualStickFrames = 0;
  vehicleManualInputSuppressedUntil = sample.vehicle
    ? now + VEHICLE_MANUAL_ACQUIRE_GRACE_MS
    : 0;
  mouseMovementBaselineX = null;
  mouseMovementBaselineY = null;
  mouseBaselineCalibrateUntil = sample.vehicle
    ? now + VEHICLE_MANUAL_ACQUIRE_GRACE_MS
    : 0;
  previousRawMouseX = null;
  previousRawMouseY = null;
  previousMouseCursorPosition = null;
  relativeMouseAnchor = null;
  relativeMouseSetCursorAvailable = null;
  relativeMouseObservedMotion = false;
  lastRelativeMouseMotionAt = 0;
  mouseGestureUntil = 0;
  cancelNativeMouseBridge();
  vehicleVisualAnchor = null;
  vehicleVisualAnchorVelocity = { x: 0, y: 0, z: 0 };
  vehicleVisualAnchorIdentity = sample.vehicle ? sample.vehicleIdentity : null;
  lastManualInputDiagnosticAt = 0;
  vehicleCameraControl = CameraControl.AUTO;
  vehicleOrbitYaw = null;
  vehicleOrbitPitch = 0;
  // Never carry the previous vehicle's delayed heading into a new anchor.
  // Otherwise the first scripted frame can place the camera in front of the
  // new vehicle until the yaw filter catches up.
  vehicleFollowDirection = sample.forward;
  reverseState = false;
  reverseCandidateSince = 0;
  forwardCandidateSince = 0;
  airborneSince = 0;
  landingUntil = 0;
  vehicleRecenterStartedAt = 0;
  vehicleRecenterFromYaw = null;
  vehicleRecenterFromPitch = 0;
  springAnchorPosition = null;
  lastVehicleGeometryDiagnosticKey = null;
  manualControlActive = false;
  manualFreeUntil = 0;
  manualRecenterUntil = 0;
  anchorTransition = {
    fromAnchorPosition: lastActorSample?.position || sample.position,
    fromAnchorForward: lastActorSample?.forward || sample.forward,
    fromProfile: lastActorSample ? buildProfile(lastActorSample) : null,
    startedAt: now,
    duration: config.anchorTransitionMs,
  };
  springPositionVelocity = scaleVector(springPositionVelocity, 0.15);
  springTargetVelocity = scaleVector(springTargetVelocity, 0.25);
}

function getAnchorTransitionState(now) {
  if (!anchorTransition) return null;
  const elapsed = now - anchorTransition.startedAt;
  const amount = smoothstep(
    0,
    Math.max(1, anchorTransition.duration),
    elapsed
  );
  return { ...anchorTransition, amount };
}

function getMouseBridgeAnchorKey(sample) {
  if (!sample) return "none";
  if (!sample.vehicle) return "onFoot";
  return "vehicle:" + (sample.vehicleIdentity ?? sample.kind ?? "unknown");
}

function isConfidentNativeMouseBridgeGesture(input, sample = null) {
  if (!input) return false;

  // v32 prefers a single-owner scripted camera while a trustworthy direct
  // mouse source is active. Do not suppress the native fallback forever just
  // because relative cursor motion was observed once earlier in the session.
  // Focus changes and game cursor capture can invalidate that path later.
  const now = getGameTimerMs();
  const recentRelativeMouse = input.relativeCursorActive ||
    (lastRelativeMouseMotionAt > 0 && now - lastRelativeMouseMotionAt <= 250);
  if (recentRelativeMouse) return false;

  const rawAxisSeparation = Math.abs(input.rawMouseX - input.rawMouseY);
  const nonDiagonalGesture =
    rawAxisSeparation >= VEHICLE_MOUSE_BRIDGE_RAW_AXIS_SEPARATION &&
    input.rawVariation >= 0.80 &&
    input.mouseMagnitude >= 0.90;

  // Equal-axis raw values such as (3,3) are the known false signal and must
  // never switch camera ownership. Keep only this strict fallback for setups
  // where the relative cursor path is unavailable.
  return nonDiagonalGesture;
}

function enterNativeMouseBridge(sample, now, input) {
  nativeMouseBridgeActive = true;
  nativeMouseBridgeEnteredAt = now;
  nativeMouseBridgeLastGestureAt = now;
  nativeMouseBridgeAnchorKey = getMouseBridgeAnchorKey(sample);
  lastNativeMouseBridgeDiagnosticAt = 0;
  vehicleManualStickFrames = 0;
  log(
    "Adaptive Third-Person Camera scripted -> native mouse bridge" +
      " anchor=" + nativeMouseBridgeAnchorKey +
      " variation=" + input.rawVariation.toFixed(1) +
      " cursorDelta=(" + input.cursorDeltaX.toFixed(1) + "," + input.cursorDeltaY.toFixed(1) + ")"
  );
}

function exitNativeMouseBridge(sample, now) {
  const camera = getCameraState();
  if (sample.vehicle) {
    // Seed the scripted orbit from the native camera position. This preserves
    // the angle chosen with the real GTA mouse-look instead of snapping behind
    // the vehicle when CLEO takes ownership again.
    if (camera?.position) {
      const offset = subtractVector(camera.position, sample.position);
      const horizontalDistance = Math.sqrt(offset.x * offset.x + offset.y * offset.y);
      if (horizontalDistance > 0.25) {
        vehicleOrbitYaw = Math.atan2(offset.y, offset.x);
        const profileValue = buildProfile(sample);
        vehicleOrbitPitch = clamp(
          Math.atan2(offset.z - profileValue.height, horizontalDistance),
          VEHICLE_MIN_ORBIT_PITCH,
          VEHICLE_MAX_ORBIT_PITCH
        );
      } else {
        initializeVehicleOrbit(sample);
      }
    } else {
      initializeVehicleOrbit(sample);
    }
    vehicleCameraControl = CameraControl.MANUAL;
    manualControlActive = true;
    vehicleRecenterStartedAt = 0;
    vehicleRecenterFromYaw = null;
    vehicleRecenterFromPitch = vehicleOrbitPitch;
  }

  manualFreeUntil = now + config.manualFreeMs;
  manualRecenterUntil = now + Math.max(config.manualFreeMs, getRecenterDelay(sample));
  nativeMouseBridgeActive = false;
  nativeMouseBridgeEnteredAt = 0;
  nativeMouseBridgeLastGestureAt = 0;
  nativeMouseBridgeAnchorKey = "";
  nativeMouseBridgeSuppressedUntil = now + (sample.vehicle ? VEHICLE_MOUSE_BRIDGE_REENTRY_COOLDOWN_MS : 180);
  previousRawMouseX = null;
  previousRawMouseY = null;
  mouseMovementBaselineX = null;
  mouseMovementBaselineY = null;
  lastNativeMouseBridgeDiagnosticAt = 0;
  // Leave cameraApplied=false: initializeSpringIfNeeded will seed the spring
  // directly from the native pose on the same frame.
  log("Adaptive Third-Person Camera native mouse bridge -> scripted handoff");
}

function cancelNativeMouseBridge() {
  nativeMouseBridgeActive = false;
  nativeMouseBridgeEnteredAt = 0;
  nativeMouseBridgeLastGestureAt = 0;
  nativeMouseBridgeAnchorKey = "";
  nativeMouseBridgeSuppressedUntil = 0;
  lastNativeMouseBridgeDiagnosticAt = 0;
}

function beginManualOverride(sample, input, now, dt) {
  if (sample.vehicle) {
    const enteringManual =
      vehicleCameraControl === CameraControl.AUTO || vehicleOrbitYaw === null;
    if (enteringManual) {
      initializeVehicleOrbit(sample);
      log("Adaptive Third-Person Camera vehicle camera=AUTO -> MANUAL");
    }
    vehicleCameraControl = CameraControl.MANUAL;
    manualControlActive = true;
    // Any fresh input cancels an in-progress recenter and starts a new hold.
    vehicleRecenterStartedAt = 0;
    vehicleRecenterFromYaw = null;
    vehicleRecenterFromPitch = vehicleOrbitPitch;
  }

  const usingStick = input.stickMagnitude > input.mouseMagnitude;
  const frameDt = clamp(dt || 1 / 60, 0.001, 0.05);
  const yawDelta = usingStick
    ? clamp(input.stickX / 128, -1, 1) *
      MANUAL_STICK_YAW_RADIANS_PER_SECOND * frameDt
    : input.mouseX * MANUAL_MOUSE_YAW_RADIANS_PER_UNIT;
  const pitchDelta = usingStick
    ? clamp(input.stickY / 128, -1, 1) *
      MANUAL_STICK_PITCH_RADIANS_PER_SECOND * frameDt
    : input.mouseY * MANUAL_MOUSE_PITCH_RADIANS_PER_UNIT;

  if (sample.vehicle) {
    // Vehicle manual mode owns the orbit. The vehicle heading must never
    // overwrite this yaw while the user is looking around.
    vehicleOrbitYaw = normalizeAngleRadians(vehicleOrbitYaw + yawDelta);
    vehicleOrbitPitch = clamp(
      vehicleOrbitPitch - pitchDelta,
      VEHICLE_MIN_ORBIT_PITCH,
      VEHICLE_MAX_ORBIT_PITCH
    );
  }

  const freeLookHold = config.manualFreeMs;
  manualFreeUntil = now + freeLookHold;
  manualRecenterUntil = now + Math.max(config.manualFreeMs, getRecenterDelay(sample));
}

function initializeVehicleOrbit(sample) {
  const camera = getCameraState();
  const profileValue = buildProfile(sample);
  if (camera?.position) {
    const offset = subtractVector(camera.position, sample.position);
    const horizontalDistance = Math.sqrt(offset.x * offset.x + offset.y * offset.y);
    if (horizontalDistance > 0.25) {
      vehicleOrbitYaw = Math.atan2(offset.y, offset.x);
      vehicleOrbitPitch = clamp(
        Math.atan2(offset.z - profileValue.height, horizontalDistance),
        VEHICLE_MIN_ORBIT_PITCH,
        VEHICLE_MAX_ORBIT_PITCH
      );
      return;
    }
  }

  // Keep the same orbit side when reversing. Flipping to travel direction
  // here makes a 180-degree camera jump as reverse engages/disengages.
  const autoDirection = sample.forward;
  vehicleOrbitYaw = cameraYawFromViewDirection(autoDirection);
  vehicleOrbitPitch = 0;
}

function getAutoFollowWeight(sample, now) {
  if (sample.vehicle && vehicleOrbitYaw !== null &&
      vehicleCameraControl === CameraControl.MANUAL) {
    if (!config.manualAutoRecenter || (sample.speedKmh || 0) < 5.0) {
      vehicleRecenterStartedAt = 0;
      vehicleRecenterFromYaw = null;
      return 0;
    }
    if (now <= manualFreeUntil || now <= manualRecenterUntil) return 0;

    if (!vehicleRecenterStartedAt) {
      vehicleRecenterStartedAt = now;
      vehicleRecenterFromYaw = vehicleOrbitYaw;
      vehicleRecenterFromPitch = vehicleOrbitPitch;
      log("Adaptive Third-Person Camera vehicle camera=MANUAL -> RECENTER");
    }

    return smoothstep(
      0,
      Math.max(1, config.manualBlendMs),
      now - vehicleRecenterStartedAt
    );
  }

  return 1;
}

function getRecenterDelay(sample) {
  const speed = sample?.speedKmh || 0;
  if (speed < 20) return config.recenterLowSpeedMs;
  if (speed < 100) {
    return lerp(
      config.recenterLowSpeedMs,
      config.recenterNormalSpeedMs,
      clamp((speed - 20) / 80, 0, 1)
    );
  }
  return lerp(
    config.recenterNormalSpeedMs,
    config.recenterHighSpeedMs,
    clamp((speed - 100) / 80, 0, 1)
  );
}

function isHardTeleport(previous, current, elapsedSeconds) {
  const expectedMotion =
    Math.max(previous?.speedMps || 0, current?.speedMps || 0) *
    clamp(elapsedSeconds, 0, 0.5) *
    2;
  return !!previous &&
    !!current &&
    distanceBetween(previous.position, current.position) > 24 + expectedMotion;
}

function deriveAirState(vehicle, kind, verticalSpeed, previous, now) {
  if (!vehicle || !["car", "motorbike", "bicycle"].includes(kind)) {
    airborneSince = 0;
    landingUntil = 0;
    return "grounded";
  }

  const wasAirborne = previous?.airState === "airborne" || previous?.airState === "landing";
  const previousVerticalSpeed = previous?.velocity?.z || 0;
  const enterThreshold = config.airborneEnterVerticalSpeed;
  const exitThreshold = config.airborneExitVerticalSpeed;
  const properAir = isVehicleInAirProper(vehicle);
  const enterSignal = properAir === null
    ? Math.abs(verticalSpeed) >= enterThreshold
    : properAir && Math.abs(verticalSpeed) >= Math.min(enterThreshold, exitThreshold * 1.15);

  if (!wasAirborne) {
    if (enterSignal) {
      if (!airborneSince) airborneSince = now;
      // A single frame over a crest or kerb is not enough to switch the
      // vehicle profile. Rapid grounded/airborne oscillation was moving the
      // target lead at high speed and looked like the camera briefly snapped
      // backwards. Require a short confirmed air interval first.
      if (now - airborneSince >= AIRBORNE_CONFIRM_MS) return "airborne";
      return "grounded";
    }
    airborneSince = 0;
    return "grounded";
  }

  if (!airborneSince) airborneSince = previous?.timestamp || now;
  const airborneLongEnough = now - airborneSince >= config.landingMinAirborneMs;
  const landingSignal =
    airborneLongEnough &&
    previousVerticalSpeed < -exitThreshold &&
    verticalSpeed > previousVerticalSpeed + exitThreshold * 0.35 &&
    verticalSpeed > -exitThreshold &&
    properAir !== true;
  if (landingSignal) landingUntil = now + config.landingDurationMs;
  if (now < landingUntil) return "landing";

  if (properAir === true || Math.abs(verticalSpeed) >= exitThreshold) return "airborne";
  airborneSince = 0;
  return "grounded";
}

function isVehicleInAirProper(vehicle) {
  if (!vehicle) return null;
  try {
    if (typeof vehicle.isInAirProper === "function") {
      return !!vehicle.isInAirProper();
    }
  } catch (_) {}
  const value = safeNative("IS_CAR_IN_AIR_PROPER", vehicle);
  return value === null ? null : !!value;
}

function updateReverseState(sample, now) {
  if (!sample.vehicle || sample.kind !== "car") {
    reverseState = false;
    reverseCandidateSince = 0;
    forwardCandidateSince = 0;
    return false;
  }

  const signedKmh = sample.signedSpeedMps * 3.6;
  if (!reverseState) {
    forwardCandidateSince = 0;
    if (signedKmh <= -config.reverseMinSpeedKmh) {
      if (!reverseCandidateSince) reverseCandidateSince = now;
      if (now - reverseCandidateSince >= config.reverseEnterHoldMs) {
        reverseState = true;
        reverseCandidateSince = 0;
      }
    } else {
      reverseCandidateSince = 0;
    }
  } else if (signedKmh >= config.reverseExitSpeedKmh) {
    reverseCandidateSince = 0;
    if (!forwardCandidateSince) forwardCandidateSince = now;
    if (now - forwardCandidateSince >= config.reverseExitHoldMs) {
      reverseState = false;
      forwardCandidateSince = 0;
    }
  } else {
    forwardCandidateSince = 0;
  }
  return reverseState;
}

function calculateSlipAngle(forward, velocityDirection, speedMps) {
  if (!velocityDirection || speedMps <= 0.1) return 0;
  const cross = Math.abs(cross2D(forward, velocityDirection));
  const dot = clamp(dotProduct(forward, velocityDirection), -1, 1);
  const rawAngle = Math.abs((Math.atan2(cross, dot) * 180) / Math.PI);
  // Straight reverse travel is 180 degrees from vehicle forward, but it is not
  // a 180-degree drift. Fold the angle into 0..90 so forward and reverse both
  // measure lateral slip rather than travel direction.
  return Math.min(rawAngle, Math.abs(180 - rawAngle));
}

function driftVelocityWeight(slipAngleDegrees, speedKmh = Infinity) {
  if (config.driftVelocityInfluence <= 0 || speedKmh < config.driftMinSpeedKmh) return 0;
  return smoothstep(5, 30, slipAngleDegrees) * config.driftVelocityInfluence;
}

function desiredFovFallback() {
  return 70;
}

function readActorSample(actor, now) {
  if (!actor || safeNative("IS_CHAR_DEAD", actor)) return null;

  const vehicleState = readPlayerVehicleState(actor);
  const sittingInVehicle = vehicleState.isSitting && !vehicleState.isOnFoot;
  const inAnyVehicle = vehicleState.interactingWithVehicle;
  const interactionState = resolveInteractionState(vehicleState, now);
  // Do not acquire the vehicle camera during the door animation. Once the
  // state reaches DRIVING, give the game's camera a brief stabilization window
  // before the scripted vehicle anchor takes ownership.
  const vehicleAnchorAvailable = interactionState === "driving" &&
    now - interactionStateStartedAt >= VEHICLE_ANCHOR_ACQUIRE_MS &&
    !vehicleState.isOnFoot &&
    (vehicleState.isSitting || vehicleState.interactingWithVehicle);
  const vehicle = vehicleAnchorAvailable
    ? getPlayerVehicle(actor, vehicleState)
    : null;
  // Hard scope boundary: never sample on-foot input, apply FOV, aim presets,
  // or calculate a scripted pedestrian camera, regardless of legacy INI keys.
  if (!vehicle) return null;

  const entity = vehicle;
  const actorPosition = getCoordinates(actor, false);
  const previousReliablePlayerPosition = lastReliablePlayerPosition;
  const previousReliablePlayerPositionAt = lastReliablePlayerPositionAt;
  if (!isSanePlayerAnchor(
    actorPosition,
    previousReliablePlayerPosition,
    previousReliablePlayerPositionAt,
    now
  )) {
    if (now - lastInvalidPlayerAnchorDiagnosticAt >= 750) {
      lastInvalidPlayerAnchorDiagnosticAt = now;
      log(
        "Adaptive Third-Person Camera rejected transient player origin during vehicle handoff" +
          " actor=" + formatVector(actorPosition) +
          " previous=" + formatVector(previousReliablePlayerPosition) +
          " state=" + interactionState
      );
    }
    return null;
  }
  lastReliablePlayerPosition = { x: actorPosition.x, y: actorPosition.y, z: actorPosition.z };
  lastReliablePlayerPositionAt = now;

  const position = getCoordinates(entity, true);
  // SA:DE/CLEO can briefly keep the broad "in vehicle" state alive while the
  // player is getting out. STORE_CAR_CHAR_IS_IN_NO_SAVE/getCarIsUsing may then
  // expose an invalid/stale vehicle wrapper whose coordinates resolve to
  // (0,0,0). Never let such a value become the scripted camera anchor: release
  // ownership and allow GTA's pedestrian camera to take over instead.
  if (!isSaneVehicleAnchor(position, actorPosition)) {
    if (now - lastInvalidVehicleAnchorDiagnosticAt >= 750) {
      lastInvalidVehicleAnchorDiagnosticAt = now;
      log(
        "Adaptive Third-Person Camera rejected stale vehicle anchor during handoff" +
          " vehicle=" + formatVector(position) +
          " actor=" + formatVector(actorPosition) +
          " state=" + interactionState
      );
    }
    return null;
  }

  const kind = classifyVehicle(actor, vehicle);
  const heading = getEntityHeading(entity, !!vehicle);
  // Do not reconstruct a vehicle's world forward vector from the heading.
  // GTA's heading convention is easy to mirror accidentally; the vehicle
  // wrapper/native already exposes the actual world-space forward axes.
  const forward = getEntityForward(entity, !!vehicle, heading);
  const vehicleIdentity = vehicle ? getEntityIdentity(vehicle) : null;
  const previousSameVehicle = !vehicle || !lastActorSample?.vehicle ||
    vehicleIdentity === null || lastActorSample.vehicleIdentity === null ||
    vehicleIdentity === lastActorSample.vehicleIdentity;
  const previous = lastActorSample &&
      lastActorSample.kind === kind &&
      !!lastActorSample.vehicle === !!vehicle &&
      previousSameVehicle
    ? lastActorSample
    : null;
  const elapsed = previous ? clamp((now - previous.timestamp) / 1000, 0.001, 0.25) : 0;
  const positionVelocity = previous && elapsed > 0
    ? scaleVector(subtractVector(position, previous.position), 1 / elapsed)
    : { x: 0, y: 0, z: 0 };
  const nativeVelocity = readNativeVelocity(entity, !!vehicle);
  const velocity = nativeVelocity || positionVelocity;
  // Direction and profile speed are derived from world-space position delta.
  // The native speed vector remains useful as a fallback/diagnostic source,
  // but its coordinate/scale contract is not documented strongly enough here
  // to treat its magnitude as metres per second. High-speed noise is handled
  // with a frame-rate-independent speed filter below.
  const worldHorizontalVelocity = previous
    ? { x: positionVelocity.x, y: positionVelocity.y, z: 0 }
    : null;
  const horizontalVelocity = worldHorizontalVelocity || { x: velocity.x, y: velocity.y, z: 0 };
  const positionSpeedMps = vectorLength(horizontalVelocity);
  const reportedSpeed = clamp(getEntitySpeed(entity, !!vehicle), 0, 90);
  // Keep world-position delta as the authoritative speed source. The public
  // binding exposes the native vector but does not document a coordinate/scale
  // contract strong enough to use its magnitude as metres per second here.
  // Instead, filter the world-space measurement before it drives the profile.
  const measuredRawSpeedMps = positionSpeedMps > 0.08
    ? positionSpeedMps
    : reportedSpeed;
  const rawSpeedMps = measuredRawSpeedMps;
  const speedTimeConstant = VEHICLE_SPEED_FILTER_TIME_CONSTANT;
  const speedAlpha = previous && elapsed > 0
    ? 1 - Math.exp(-elapsed / speedTimeConstant)
    : 1;
  const speedMps = previous
    ? lerp(previous.speedMps, rawSpeedMps, speedAlpha)
    : rawSpeedMps;
  const cameraSpeedAlpha = previous && elapsed > 0
    ? 1 - Math.exp(-elapsed / VEHICLE_CAMERA_SPEED_FILTER_TIME_CONSTANT)
    : 1;
  const cameraSpeedMps = previous
    ? lerp(previous.cameraSpeedMps ?? previous.speedMps, rawSpeedMps, cameraSpeedAlpha)
    : rawSpeedMps;
  const measuredVelocityDirection = worldHorizontalVelocity &&
    vectorLength(worldHorizontalVelocity) > config.velocityDirectionThresholdMps
    ? normalizeVector(horizontalVelocity)
    : null;
  let stableVelocityDirection =
    measuredVelocityDirection ||
    previous?.stableVelocityDirection ||
    forward;
  if (vehicle && previous?.stableVelocityDirection && measuredVelocityDirection && elapsed > 0) {
    const directionAlpha = 1 - Math.exp(-elapsed / VEHICLE_DIRECTION_FILTER_TIME_CONSTANT);
    stableVelocityDirection = smoothHorizontalDirection(
      previous.stableVelocityDirection,
      measuredVelocityDirection,
      directionAlpha
    );
  }
  const signedDirection = measuredVelocityDirection
    ? dotProduct(measuredVelocityDirection, forward)
    : positionSpeedMps > 0.08
      ? clamp(dotProduct(horizontalVelocity, forward) / positionSpeedMps, -1, 1)
      : 1;
  const signedSpeedMps = speedMps * signedDirection;
  // Camera lead should react to sustained acceleration, not every noisy
  // world-delta speed sample. Use the slower composition speed here.
  const rawAccelerationMps2 = previous && elapsed > 0
    ? clamp(
        (cameraSpeedMps - (previous.cameraSpeedMps ?? previous.speedMps)) / elapsed,
        -14,
        14
      )
    : 0;
  const accelerationAlpha = frameRateIndependentAlpha(
    config.accelerationFilterAlpha,
    elapsed || 1 / 60
  );
  const filteredAccelerationMps2 = previous
    ? lerp(
        previous.filteredAccelerationMps2 || 0,
        rawAccelerationMps2,
        accelerationAlpha
      )
    : 0;
  // World-space yaw rate drives both body follow and bend preview.
  let turnAmount = 0;
  if (previous && elapsed > 0) {
    const previousForward2D = normalizeVector({
      x: previous.forward.x,
      y: previous.forward.y,
      z: 0,
    });
    const currentForward2D = normalizeVector({ x: forward.x, y: forward.y, z: 0 });
    const signedTurnRadians = Math.atan2(
      cross2D(previousForward2D, currentForward2D),
      clamp(dotProduct(previousForward2D, currentForward2D), -1, 1)
    );
    const referenceTurnRateDeg = VEHICLE_CORNER_TURN_RATE_REFERENCE_DEG;
    const rawTurnAmount = clamp(
      signedTurnRadians / elapsed / ((referenceTurnRateDeg * Math.PI) / 180),
      -1,
      1
    );
    const turnTimeConstant = VEHICLE_TURN_FILTER_TIME_CONSTANT;
    const turnAlpha = 1 - Math.exp(-elapsed / turnTimeConstant);
    turnAmount = lerp(previous.turnAmount || 0, rawTurnAmount, turnAlpha);
  }
  const uprightValue = getVehicleUprightValue(vehicle);
  const worldVerticalSpeed = previous ? positionVelocity.z : velocity.z;
  const slipAngleDegrees = calculateSlipAngle(
    forward,
    measuredVelocityDirection,
    positionSpeedMps
  );
  const rawDriftAmount = vehicle
    ? driftVelocityWeight(slipAngleDegrees, cameraSpeedMps * 3.6)
    : 0;
  const driftAlpha = previous && elapsed > 0
    ? 1 - Math.exp(-elapsed / VEHICLE_DRIFT_FILTER_TIME_CONSTANT)
    : 1;
  const cameraDriftAmount = previous && vehicle
    ? lerp(previous.cameraDriftAmount ?? 0, rawDriftAmount, driftAlpha)
    : rawDriftAmount;
  const airState = deriveAirState(
    vehicle,
    kind,
    worldVerticalSpeed,
    previous,
    now
  );

  const sample = {
    actor,
    vehicle,
    vehicleIdentity,
    kind,
    sittingInVehicle,
    inAnyVehicle,
    interactionState,
    position,
    heading,
    forward,
    velocity: previous ? { x: velocity.x, y: velocity.y, z: worldVerticalSpeed } : velocity,
    velocityDirection: measuredVelocityDirection,
    stableVelocityDirection,
    velocitySource: nativeVelocity ? "nativeVector+worldDelta" : "positionDelta",
    rawSpeedMps,
    measuredRawSpeedMps,
    speedMps,
    speedKmh: speedMps * 3.6,
    cameraSpeedMps,
    cameraSpeedKmh: cameraSpeedMps * 3.6,
    signedSpeedMps,
    rawAccelerationMps2,
    filteredAccelerationMps2,
    turnAmount,
    slipAngleDegrees,
    rawDriftAmount,
    cameraDriftAmount,
    orientationInstability: clamp((1 - uprightValue) / 0.45, 0, 1),
    // Same world-space signed yaw rate for body follow and target prediction.
    // No assumption about the handedness of GTA's heading scalar.
    steering: turnAmount * smoothstep(3, 45, speedMps * 3.6),
    uprightValue,
    airState,
    timestamp: now,
    aiming: isAimHeld(),
  };

  sample.reverseActive = updateReverseState(sample, now);
  return sample;
}

function applyCameraDirector(sample, dt, now, autoFollowWeight) {
  const visualAnchor = stabilizeVehicleCameraAnchor(sample, dt);
  const renderSample = sample.vehicle
    ? { ...sample, position: visualAnchor }
    : sample;
  const transition = getAnchorTransitionState(now);
  let profile = buildProfile(sample);
  if (transition?.fromProfile) {
    profile = interpolateProfiles(transition.fromProfile, profile, transition.amount);
  }
  profile.modifiers = {
    ...(profile.modifiers || {}),
    manual: clamp(1 - autoFollowWeight, 0, 1),
  };
  profile.stateName = composeProfileState(profile.baseName, profile.modifiers);

  let geometry = buildCameraGeometry(renderSample, profile, autoFollowWeight, transition);
  geometry = {
    ...geometry,
    desiredPosition: enforceCameraGroundSafety(
      geometry.desiredPosition,
      renderSample.position
    ),
  };
  transportSpringWithVehicleAnchor(renderSample, transition);
  const manualFreeLook = !!sample.vehicle && manualControlActive && autoFollowWeight < 1;
  let collision = resolveCameraCollision(
    geometry.target,
    geometry.desiredPosition,
    now,
    manualFreeLook,
    true,
    sample.vehicle
  );

  // Side probe obstruction is first solved by removing shoulder bias rather
  // than collapsing the entire camera toward the player.
  if (collision.shoulderObstructed && Math.abs(profile.shoulderOffset) > 0.01) {
    const centeredProfile = { ...profile, shoulderOffset: 0 };
    const centeredGeometry = buildCameraGeometry(
      renderSample,
      centeredProfile,
      autoFollowWeight,
      transition
    );
    centeredGeometry.desiredPosition = enforceCameraGroundSafety(
      centeredGeometry.desiredPosition,
      renderSample.position
    );
    const centeredCollision = resolveCameraCollision(
      centeredGeometry.target,
      centeredGeometry.desiredPosition,
      now,
      manualFreeLook,
      true,
      sample.vehicle,
      true
    );
    if (!centeredCollision.emergency || collision.emergency) {
      geometry = centeredGeometry;
      collision = centeredCollision;
      profile = centeredProfile;
    }
  }

  if (collision.emergency) {
    if (!collisionEmergencySince) collisionEmergencySince = now;
    const currentPathClear = !!springPosition &&
      isCameraPathClear(geometry.target, springPosition, sample.vehicle);
    if (
      currentPathClear &&
      now - collisionEmergencySince < COLLISION_EMERGENCY_GRACE_MS
    ) {
      // A single noisy LOS sample must not collapse the driving camera. Keep
      // the already safe pose briefly; a sustained obstruction still reaches
      // the normal collision resolver after the grace period.
      collision = {
        ...collision,
        position: springPosition,
        collided: false,
        emergency: false,
        transientEmergency: true,
      };
    }
  } else {
    collisionEmergencySince = 0;
  }

  collision = {
    ...collision,
    position: enforceCameraGroundSafety(collision.position, renderSample.position),
  };

  if (
    !isSafeCameraPose(sample.position, geometry.desiredPosition, geometry.target) ||
    !isSafeCameraPose(sample.position, collision.position, geometry.target)
  ) {
    log(
      "Adaptive Third-Person Camera rejected invalid geometry" +
        " anchor=" + formatVector(sample.position) +
        " desired=" + formatVector(geometry.desiredPosition) +
        " resolved=" + formatVector(collision.position) +
        " target=" + formatVector(geometry.target)
    );
    releaseCamera();
    return;
  }

  initializeSpringIfNeeded(collision.position, geometry.target, renderSample.position, sample.vehicle);

  // Only snap when the camera's current path is actually blocked. A blocked
  // desired orbit alone must not pull an otherwise safe driving view forward.
  if (
    collision.collided &&
    !isCameraPathClear(geometry.target, springPosition, sample.vehicle)
  ) {
    springPosition = collision.position;
    springPositionVelocity = { x: 0, y: 0, z: 0 };
  }

  // Hard teleports/cutscene transitions should not drag the camera through
  // half the map while the spring catches up.
  if (
    distanceBetween(springPosition, collision.position) > 24 ||
    distanceBetween(springTarget, geometry.target) > 24
  ) {
    springPosition = collision.position;
    springPositionVelocity = { x: 0, y: 0, z: 0 };
    springTarget = geometry.target;
    springTargetVelocity = { x: 0, y: 0, z: 0 };
  }

  const verticalTracking = sample.vehicle
    ? profile.verticalTracking ?? config.verticalTracking
    : 0.86;
  const transitionSpringBoost = transition && transition.amount < 1 ? 1.25 : 1;
  const highSpeedSpringAmount = sample.vehicle
    ? smoothstep(
        VEHICLE_HIGH_SPEED_SPRING_START_KMH,
        VEHICLE_HIGH_SPEED_SPRING_FULL_KMH,
        sample.cameraSpeedKmh ?? sample.speedKmh
      )
    : 0;
  const highSpeedSpringBoost = lerp(
    1,
    VEHICLE_HIGH_SPEED_SPRING_MAX_BOOST,
    highSpeedSpringAmount
  );
  const positionFrequency =
    (collision.collided ? config.collisionFrequencyHz : config.positionFrequencyHz) *
    transitionSpringBoost * highSpeedSpringBoost;
  const positionDampingRatio = collision.collided
    ? config.collisionDampingRatio
    : config.positionDampingRatio;
  const positionResult = springStep(
    springPosition,
    collision.position,
    springPositionVelocity,
    positionFrequency,
    positionDampingRatio,
    verticalTracking,
    dt
  );
  springPosition = positionResult.position;
  springPositionVelocity = positionResult.velocity;

  // Keep the camera elastically attached to the vehicle in vehicle-relative
  // space. At high speed a large offset error becomes a visible pull-back /
  // catch-up jerk even though the anchor translation itself is correct.
  // Clamp only excessive relative lag; normal spring motion is untouched.
  let relativeSpringLag = 0;
  if (sample.vehicle) {
    const currentRelative = subtractVector(springPosition, renderSample.position);
    const desiredRelative = subtractVector(collision.position, renderSample.position);
    const relativeError = subtractVector(desiredRelative, currentRelative);
    relativeSpringLag = vectorLength(relativeError);
    const maxRelativeLag = lerp(
      VEHICLE_HIGH_SPEED_MAX_RELATIVE_LAG_LOW,
      VEHICLE_HIGH_SPEED_MAX_RELATIVE_LAG_HIGH,
      highSpeedSpringAmount
    );
    if (relativeSpringLag > maxRelativeLag && relativeSpringLag > 0.0001) {
      const correction = scaleVector(
        relativeError,
        (relativeSpringLag - maxRelativeLag) / relativeSpringLag
      );
      springPosition = addVector(springPosition, correction);
      springPositionVelocity = scaleVector(springPositionVelocity, 0.55);
      relativeSpringLag = maxRelativeLag;
    }
  }

  const validateSpringPath = collision.collided ||
    now - lastSpringPathValidationAt >= SPRING_PATH_VALIDATION_MS;
  if (validateSpringPath) {
    lastSpringPathValidationAt = now;
    if (!isCameraPathClear(geometry.target, springPosition, sample.vehicle)) {
      springPosition = collision.position;
      springPositionVelocity = { x: 0, y: 0, z: 0 };
    }
  }

  const targetHighSpeedScale = lerp(1.0, 0.78, highSpeedSpringAmount);
  const targetResult = springStep(
    springTarget,
    geometry.target,
    springTargetVelocity,
    config.targetFrequencyHz * transitionSpringBoost * targetHighSpeedScale,
    config.targetDampingRatio,
    sample.vehicle ? verticalTracking : 0.90,
    dt
  );
  springTarget = targetResult.position;
  springTargetVelocity = targetResult.velocity;

  if (!isSafeCameraPose(sample.position, springPosition, springTarget)) {
    const rejectedPosition = springPosition;
    const rejectedTarget = springTarget;
    springPosition = collision.position;
    springPositionVelocity = { x: 0, y: 0, z: 0 };
    springTarget = geometry.target;
    springTargetVelocity = { x: 0, y: 0, z: 0 };
    log(
      "Adaptive Third-Person Camera rejected unsafe pose; reset to profile position" +
        " anchor=" + formatVector(sample.position) +
        " rejectedCamera=" + formatVector(rejectedPosition) +
        " rejectedTarget=" + formatVector(rejectedTarget) +
        " resetCamera=" + formatVector(springPosition) +
        " resetTarget=" + formatVector(springTarget)
    );
  }

  if (sample.vehicle && lastLayoutDiagnosticRevision !== cameraLayoutController.revision) {
    lastLayoutDiagnosticRevision = cameraLayoutController.revision;
    log(
      "Adaptive Third-Person Camera layout geometry" +
        " revision=" + cameraLayoutController.revision +
        " layout=" + VEHICLE_CAMERA_LAYOUT_NAMES[cameraLayoutController.layout] +
        " anchor=" + formatVector(sample.position) +
        " desired=" + formatVector(geometry.desiredPosition) +
        " resolved=" + formatVector(collision.position) +
        " spring=" + formatVector(springPosition) +
        " target=" + formatVector(springTarget)
    );
  }

  if (sample.vehicle) {
    const geometryDiagnosticKey = [
      vehicleCameraControl,
      sample.reverseActive ? "reverse" : "forward",
      cameraLayoutController.layout,
    ].join(":");
    if (geometryDiagnosticKey !== lastVehicleGeometryDiagnosticKey) {
      lastVehicleGeometryDiagnosticKey = geometryDiagnosticKey;
      const expectedBehind = addVector(
        sample.position,
        scaleVector(sample.forward, -profile.distance)
      );
      log(
        "Adaptive Third-Person Camera vehicle geometry check" +
          " mode=" + (vehicleCameraControl === CameraControl.MANUAL ? "MANUAL" : "AUTO") +
          " heading=" + sample.heading.toFixed(2) +
          " forward=" + formatVector(sample.forward) +
          " direction=" + formatVector(geometry.direction) +
          " expectedBehind=" + formatVector(expectedBehind) +
          " desiredOffset=" + formatVector(subtractVector(geometry.desiredPosition, sample.position)) +
          " previewYawDeg=" + (geometry.previewYawDegrees ?? 0).toFixed(2) +
          " cornerIntent=" + (geometry.cornerIntent ?? 0).toFixed(3) +
          " targetLeadScale=" + (geometry.targetLeadScale ?? 1).toFixed(2) +
          " orbitYawDeg=" + (vehicleOrbitYaw === null ? "none" :
            ((vehicleOrbitYaw * 180) / Math.PI).toFixed(2)) +
          " orbitPitchDeg=" + ((vehicleOrbitPitch * 180) / Math.PI).toFixed(2)
      );
    }
  }

  if (!setScriptCameraPose(springPosition, springTarget)) return;

  // The engine already performs the FOV interpolation. A second local spring
  // made zoom changes feel rubbery and added unnecessary latency.
  applyRequestedFov(profile.fov, 180, now);

  if (profile.stateName !== lastStateName) {
    lastStateName = profile.stateName;
    log(
      "Adaptive Third-Person Camera state=" +
        profile.stateName +
        " distance=" +
        profile.distance.toFixed(2) +
        " height=" +
        profile.height.toFixed(2) +
        " fovTarget=" +
        profile.fov.toFixed(0) +
        " speed=" + sample.speedKmh.toFixed(1) +
        " cameraSpeed=" + (sample.cameraSpeedKmh ?? sample.speedKmh).toFixed(1) +
        " rawSpeed=" + ((sample.measuredRawSpeedMps || sample.rawSpeedMps || sample.speedMps) * 3.6).toFixed(1) +
        " velocitySource=" +
        sample.velocitySource +
        " collision=" +
        collision.collided +
        " clearanceScore=" +
        (collision.clearanceScore ?? 7).toFixed(1) +
        " interaction=" +
        sample.interactionState
    );
  }
  if (sample.vehicle &&
      (sample.cameraSpeedKmh ?? sample.speedKmh) >= VEHICLE_HIGH_SPEED_SPRING_START_KMH &&
      now - lastHighSpeedDiagnosticAt >= HIGH_SPEED_DIAGNOSTIC_MS) {
    lastHighSpeedDiagnosticAt = now;
    log(
      "Adaptive Third-Person Camera high-speed stability" +
        " speed=" + sample.speedKmh.toFixed(1) +
        " cameraSpeed=" + (sample.cameraSpeedKmh ?? sample.speedKmh).toFixed(1) +
        " rawSpeed=" + ((sample.measuredRawSpeedMps || sample.rawSpeedMps || sample.speedMps) * 3.6).toFixed(1) +
        " relativeLag=" + relativeSpringLag.toFixed(2) +
        " anchorError=" + distanceBetween(renderSample.position, sample.position).toFixed(2) +
        " springBoost=" + highSpeedSpringBoost.toFixed(2) +
        " collision=" + collision.collided
    );
  }
  cameraApplied = true;
  if (transition && transition.amount >= 1) anchorTransition = null;
}

function buildCameraGeometry(sample, profileValue, autoFollowWeight, transition = null) {
  const anchorPosition = transition
    ? lerpVector(transition.fromAnchorPosition, sample.position, transition.amount)
    : sample.position;
  const anchorForward = transition
    ? normalizeVector(lerpVector(transition.fromAnchorForward, sample.forward, transition.amount))
    : sample.forward;
  const direction = getCameraDirection(sample, profileValue, autoFollowWeight, anchorForward);
  const vehicleRight = { x: direction.y, y: -direction.x, z: 0 };
  const turnLeft = scaleVector(vehicleRight, -1);
  let right = vehicleRight;
  const base = { x: anchorPosition.x, y: anchorPosition.y, z: anchorPosition.z };
  let useVehicleOrbit = sample.vehicle &&
    vehicleCameraControl !== CameraControl.AUTO &&
    vehicleOrbitYaw !== null;
  if (useVehicleOrbit && autoFollowWeight > 0) {
    const recenterFromYaw = vehicleRecenterFromYaw ?? vehicleOrbitYaw;
    const recenterFromPitch = vehicleRecenterStartedAt
      ? vehicleRecenterFromPitch
      : vehicleOrbitPitch;
    vehicleOrbitYaw = smoothAngle(
      recenterFromYaw,
      cameraYawFromViewDirection(direction),
      autoFollowWeight
    );
    vehicleOrbitPitch = lerp(recenterFromPitch, 0, autoFollowWeight);
    if (autoFollowWeight >= 1) {
      vehicleCameraControl = CameraControl.AUTO;
      vehicleOrbitYaw = null;
      vehicleOrbitPitch = 0;
      vehicleRecenterStartedAt = 0;
      vehicleRecenterFromYaw = null;
      vehicleRecenterFromPitch = 0;
      manualControlActive = false;
      log("Adaptive Third-Person Camera vehicle camera=RECENTER -> AUTO");
      useVehicleOrbit = false;
    }
  }
  if (useVehicleOrbit) {
    const orbitViewDirection = {
      x: -Math.cos(vehicleOrbitYaw),
      y: -Math.sin(vehicleOrbitYaw),
      z: 0,
    };
    right = { x: orbitViewDirection.y, y: -orbitViewDirection.x, z: 0 };
  }
  const speedKmh = sample.cameraSpeedKmh ?? sample.speedKmh;
  const speedFactor = clamp(speedKmh / 120, 0, 1);
  const travelDirection = sample.stableVelocityDirection || direction;
  const accelerationFactor = clamp(sample.filteredAccelerationMps2 / 8, -1, 1);

  // v34 predictive corner composition. The camera body continues to trail the
  // vehicle smoothly, but the point it looks at rotates into the bend before
  // the chassis finishes rotating. The preview is based on filtered turn rate
  // and a short speed-scaled horizon, so the road exit becomes visible early
  // without snapping the camera body or changing vehicle heading.
  const vehicleCornerInput = sample.vehicle
    ? clamp((sample.steering || 0) * 0.72 + (sample.turnAmount || 0) * 1.15, -1, 1)
    : 0;
  const cornerSpeedWeight = sample.vehicle
    ? smoothstep(VEHICLE_CORNER_PREVIEW_MIN_KMH, VEHICLE_CORNER_PREVIEW_FULL_KMH, speedKmh)
    : 0;
  const cornerIntent = vehicleCornerInput * cornerSpeedWeight * (sample.reverseActive ? 0 : 1);
  const previewActivationWeight = sample.vehicle
    ? smoothstep(
        VEHICLE_CORNER_PREVIEW_ACTIVATION_MIN_KMH,
        VEHICLE_CORNER_PREVIEW_ACTIVATION_FULL_KMH,
        speedKmh
      )
    : 0;
  const previewHorizonSeconds = sample.vehicle
    ? lerp(
        config.cornerPreviewSeconds,
        config.cornerPreviewSeconds * 0.65,
        smoothstep(15, 125, speedKmh)
      )
    : 0;
  const turnRateDegrees = sample.vehicle
    ? (sample.turnAmount || 0) * VEHICLE_CORNER_TURN_RATE_REFERENCE_DEG
    : 0;
  const steeringPreviewDegrees = sample.vehicle
    ? (sample.steering || 0) * VEHICLE_CORNER_STEERING_PREVIEW_DEG
    : 0;
  const previewYawDegrees = sample.vehicle
    ? clamp(
        (turnRateDegrees * previewHorizonSeconds + steeringPreviewDegrees) *
          previewActivationWeight * (sample.reverseActive ? 0 : 1) *
          (sample.airState === "airborne" ? 0.2 : 1) * (1 - sample.orientationInstability),
        -config.cornerPreviewMaxDegrees,
        config.cornerPreviewMaxDegrees
      )
    : 0;
  const previewYawRadians = (previewYawDegrees * Math.PI) / 180;
  const previewDirection = sample.vehicle
    ? normalizeVector(rotateHorizontal(direction, previewYawRadians))
    : direction;
  const cornerExtraLead = sample.vehicle
    ? Math.abs(cornerIntent) * (profileValue.cornerPreviewLead || 0)
    : 0;
  const cornerLateralLead = sample.vehicle
    ? (profileValue.cornerLateralLead || 0) * cornerIntent
    : 0;

  const autoTargetLead = addVector(
    scaleVector(previewDirection, profileValue.lookAhead + cornerExtraLead),
    addVector(
      scaleVector(travelDirection, profileValue.velocityLead * speedFactor),
      addVector(
        scaleVector(
          turnLeft,
          profileValue.steeringLookAhead * profileValue.steering * speedFactor +
            cornerLateralLead +
            (profileValue.turnLookAhead || 0) * (sample.turnAmount || 0)
        ),
        scaleVector(anchorForward, profileValue.accelerationLead * accelerationFactor)
      )
    )
  );
  // In vehicle manual mode the user owns the orbit position, but the camera
  // still needs a small turn-preview target. Scaling the complete automatic
  // lead by autoFollowWeight used to reduce it to zero for the entire manual
  // free-look window, making it impossible to see an upcoming bend. Keep the
  // normal free-look target centred on the vehicle and add only the dynamic
  // corner component while the user is looking around.
  const cornerPreviewLateral = cornerLateralLead +
    (profileValue.turnLookAhead || 0) * (sample.turnAmount || 0) +
    profileValue.steeringLookAhead * (sample.steering || 0) * speedFactor;
  const cornerPreviewTargetLead = addVector(
    scaleVector(previewDirection, cornerExtraLead),
    scaleVector(turnLeft, cornerPreviewLateral)
  );
  const targetLeadScale = useVehicleOrbit
    ? clamp(config.vehicleManualCornerPreviewWeight, 0, 0.80)
    : 1;
  let targetLead = useVehicleOrbit
    ? scaleVector(cornerPreviewTargetLead, targetLeadScale)
    : autoTargetLead;
  // Bound the whole lateral composition, not each additive effect separately.
  const lateralLead = dotProduct(targetLead, vehicleRight);
  targetLead = addVector(targetLead, scaleVector(vehicleRight,
    clamp(lateralLead, -config.cornerTargetMaxOffset, config.cornerTargetMaxOffset) - lateralLead));
  const shoulder = profileValue.shoulderOffset;
  const target = addVector(
    { x: base.x, y: base.y, z: base.z + profileValue.targetHeight },
    targetLead
  );
  let desiredPosition;
  if (useVehicleOrbit) {
    const pitch = clamp(
      vehicleOrbitPitch,
      VEHICLE_MIN_ORBIT_PITCH,
      VEHICLE_MAX_ORBIT_PITCH
    );
    const horizontalDistance = profileValue.distance * Math.cos(pitch);
    const verticalDistance = profileValue.distance * Math.sin(pitch);
    desiredPosition = addVector(
      {
        x: base.x + Math.cos(vehicleOrbitYaw) * horizontalDistance,
        y: base.y + Math.sin(vehicleOrbitYaw) * horizontalDistance,
        z: base.z + profileValue.height + verticalDistance,
      },
      scaleVector(right, shoulder)
    );
  } else {
    desiredPosition = addVector(
      { x: base.x, y: base.y, z: base.z + profileValue.height },
      addVector(
        scaleVector(direction, -profileValue.distance),
        scaleVector(right, shoulder)
      )
    );
  }
  return {
    direction,
    target,
    desiredPosition,
    previewYawRadians,
    previewYawDegrees,
    cornerIntent,
    targetLeadScale,
  };
}

function buildProfile(sample) {

  const speed = clamp(sample.cameraSpeedKmh ?? sample.speedKmh, 0, 220);
  let result;
  if (sample.kind === "motorbike") {
    const highSpeed = clamp(speed / 140, 0, 1);
    result = profile(
      "Motorbike",
      lerp(config.motorbikeDistance, 5.0, highSpeed),
      lerp(config.motorbikeHeight, 1.7, highSpeed),
      lerp(config.motorbikeFov, 78, highSpeed),
      0.9 + highSpeed * 2.0,
      0.4,
      0.9,
      0
    );
    result.velocityLead = 0.5 + highSpeed * 0.9;
    result.accelerationLead = 0.25;
  } else if (sample.kind === "bicycle") {
    result = profile("Bicycle", config.bicycleDistance, config.bicycleHeight, config.bicycleFov, 1.1, 0.2, 0.25, 0);
    result.velocityLead = 0.45;
    result.accelerationLead = 0.18;
  } else if (sample.kind === "boat") {
    result = profile("Boat", config.boatDistance, config.boatHeight, config.boatFov, 2.0 + speed / 70, 0.0, 0.9, 0);
    result.velocityLead = 0.8;
    result.accelerationLead = 0.25;
  } else if (sample.kind === "helicopter") {
    result = profile("Helicopter", config.helicopterDistance, config.helicopterHeight, config.helicopterFov, 3.0 + speed / 55, 0.0, 0.75, 0);
    result.velocityLead = 1.0;
    result.accelerationLead = 0.3;
  } else if (sample.kind === "aircraft") {
    result = profile("Aircraft", config.aircraftDistance, config.aircraftHeight, config.aircraftFov, 4.0 + speed / 45, 0.0, 0.65, 0);
    result.velocityLead = 1.4;
    result.accelerationLead = 0.45;
  } else {
    result = buildCarProfile(speed, sample.filteredAccelerationMps2);
    result.steering = sample.steering;
  }

  return applyProfileModifiers(result, sample);
}

function applyProfileModifiers(baseProfile, sample) {
  let result = { ...baseProfile, modifiers: { ...(baseProfile.modifiers || {}) } };
  const drift = sample.vehicle ? driftAmount(sample) : 0;
  const airborne = sample.airState === "airborne" ? 1 : 0;
  const landing = sample.airState === "landing" ? 1 : 0;
  const reverse = sample.reverseActive ? 1 : 0;

  if (drift > 0) {
    result.distance += drift * config.driftDistance;
    result.height += drift * 0.18;
    result.velocityLead += drift * 0.20;
    result.lookAhead += drift * 0.15;
    result.fov += drift * config.vehicleDriftFovBoost;
  }

  if (sample.vehicle) {
    result = applyVehicleCameraLayout(result, sample.timestamp);
  }
  if (reverse) {
    result.lookAhead = 0.25;
    result.velocityLead = 0;
    result.steeringLookAhead = 0;
    result.accelerationLead = 0;
    result.cornerPreviewLead = 0;
    result.cornerLateralLead = 0;
  }
  if (airborne) {
    result.verticalTracking = config.airborneVerticalTracking;
    result.lookAhead *= 0.75;
  }
  if (landing) {
    result.verticalTracking = Math.max(config.airborneVerticalTracking, 0.5);
    result.height -= 0.04;
  }
  if (sample.vehicle && sample.orientationInstability > 0) {
    result.verticalTracking = (result.verticalTracking ?? config.verticalTracking) *
      lerp(1, 0.68, sample.orientationInstability);
  }

  result.modifiers.drift = drift;
  result.modifiers.airborne = airborne;
  result.modifiers.landing = landing;
  result.modifiers.reverse = reverse;
  result.modifiers.orientation = sample.orientationInstability || 0;
  result.baseName = result.baseName || result.stateName;
  result.stateName = composeProfileState(result.baseName, result.modifiers);
  return result;
}

function applyVehicleCameraLayout(profileValue, now) {
  const layout = cameraLayoutController.getParameters(now);
  const result = {
    ...profileValue,
    modifiers: {
      ...(profileValue.modifiers || {}),
      layout: cameraLayoutController.layout,
    },
    distance: profileValue.distance * layout.distance,
    height: profileValue.height + layout.height,
    targetHeight: profileValue.targetHeight + layout.targetHeight,
  };
  result.baseName = profileValue.baseName || profileValue.stateName;
  result.stateName = result.baseName + layout.name;
  return result;
}

function buildCarProfile(speedKmh, accelerationMps2) {
  const speed = clamp(speedKmh, 0, 200);
  // Driving composition is intentionally road-biased. The target sits further
  // ahead as speed rises, while steeringLookAhead gives the target lateral room
  // to reveal the inside of a bend instead of staring at the rear quarter panel.
  const slow = profile("CarSlow", config.carSlowDistance, config.carSlowHeight, config.carSlowFov, 1.05, 0, 0.75, 0, 0.77);
  const normal = profile("CarNormal", config.carNormalDistance, config.carNormalHeight, config.carNormalFov, 1.70, 0, 1.30, 0, 0.80);
  const fast = profile("CarFast", config.carFastDistance, config.carFastHeight, config.carFastFov, 2.45, 0, 1.85, 0, 0.84);
  const result = speed < 75
    ? interpolateProfiles(slow, normal, smoothstep(20, 75, speed))
    : interpolateProfiles(normal, fast, smoothstep(75, 145, speed));
  result.baseName = "Car";
  result.stateName = "Car";
  result.velocityLead = 0.50 + clamp(speed / 145, 0, 1) * 0.85;
  result.accelerationLead = 0.30;
  result.cornerPreviewLead = VEHICLE_CORNER_PREVIEW_EXTRA_LEAD_M;
  result.cornerLateralLead = VEHICLE_CORNER_LATERAL_LEAD_M;
  if (accelerationMps2 > 2) {
    const boost = clamp((accelerationMps2 - 2) / 8, 0, 1);
    // Watch-Dogs-style driving reads acceleration mostly through framing/FOV,
    // not a large fore/aft camera step. Keep distance changes deliberately soft.
    result.distance += smoothstep(0, 1, boost) * 0.18;
    result.fov += boost * config.vehicleAccelerationFovBoost;
  } else if (accelerationMps2 < -2.5) {
    const braking = clamp((-accelerationMps2 - 2.5) / 7.5, 0, 1);
    result.distance -= braking * 0.06;
    result.fov -= braking * config.vehicleBrakingFovReduction;
  }
  return result;
}

function profile(
  stateName,
  distance,
  height,
  fov,
  lookAhead,
  shoulderOffset,
  steeringLookAhead,
  steering,
  targetHeight = null
) {
  return {
    stateName,
    baseName: stateName,
    modifiers: {},
    distance,
    height,
    targetHeight: targetHeight ?? (height > 3 ? height * 0.30 : height > 2 ? 0.85 : 0.95),
    fov,
    lookAhead,
    velocityLead: 0,
    accelerationLead: 0,
    turnLookAhead: 0,
    cornerPreviewLead: 0,
    cornerLateralLead: 0,
    verticalTracking: config.verticalTracking,
    shoulderOffset,
    steeringLookAhead,
    steering,
  };
}

function getCameraDirection(sample, profileValue, autoFollowWeight, forwardOverride = sample.forward) {
  let autoDirection = forwardOverride;
  if (sample.stableVelocityDirection && sample.speedMps > config.velocityDirectionThresholdMps) {
    const slipFollow = sample.reverseActive
      ? 0 : clamp(driftAmount(sample) * 0.32, 0, 0.14);
    autoDirection = slipFollow > 0.01
      ? smoothHorizontalDirection(forwardOverride, sample.stableVelocityDirection, slipFollow)
      : forwardOverride;
  }

  if (sample.vehicle) {
    if (!vehicleFollowDirection) {
      vehicleFollowDirection = autoDirection;
    } else {
      const elapsed = lastActorSample
        ? clamp((sample.timestamp - lastActorSample.timestamp) / 1000, 0.001, 0.05)
        : 1 / 60;
      const cornerFollowBoost = 1 + Math.abs(sample.turnAmount || 0) * 0.32;
      const highSpeedFollowBoost = lerp(
        1.0,
        1.16,
        clamp((sample.cameraSpeedKmh ?? sample.speedKmh) / 160, 0, 1)
      ) * cornerFollowBoost;
      const followTimeConstant = config.vehicleYawDelayMs /
        Math.max(0.1, config.vehicleYawFollowStrength * highSpeedFollowBoost) /
        1000;
      const followAlpha = 1 - Math.exp(-elapsed / followTimeConstant);
      // Angle-aware interpolation prevents heading wrap-around from turning
      // into a visible snap. Reverse uses the same continuous heading frame.
      // A previous vehicle or a handoff from the native camera can leave the
      // delayed direction on the opposite side of the car. Do not interpolate
      // through a 180-degree wrong-side view; re-seed from the live heading.
      if (dotProduct(vehicleFollowDirection, autoDirection) < -0.25) {
        vehicleFollowDirection = autoDirection;
      } else {
        vehicleFollowDirection = smoothHorizontalDirection(
          vehicleFollowDirection,
          autoDirection,
          followAlpha
        );
      }
    }
    autoDirection = rotateHorizontal(
      vehicleFollowDirection,
      (sample.steering * config.maxSteeringYawBiasDegrees * Math.PI) / 180
    );
  } else {
    vehicleFollowDirection = null;
  }

  return normalizeVector(autoDirection);
}

function driftAmount(sample) {
  // Use the camera-specific low-pass value so small slip-angle oscillations do
  // not repeatedly move the camera backwards/forwards at motorway speeds.
  if (Number.isFinite(sample.cameraDriftAmount)) {
    return clamp(sample.cameraDriftAmount, 0, 1);
  }
  return driftVelocityWeight(
    sample.slipAngleDegrees,
    sample.cameraSpeedKmh ?? sample.speedKmh
  );
}

function resolveCameraCollision(
  target,
  desiredPosition,
  now,
  manualActive = false,
  allowEmergency = true,
  ownVehicle = null,
  bypassCache = false
) {
  if (!config.collisionEnabled) {
    return { position: desiredPosition, collided: false, clearanceScore: 7 };
  }

  const updateInterval = manualActive
    ? Math.min(config.collisionUpdateMs, MANUAL_COLLISION_UPDATE_MS)
    : config.collisionUpdateMs;
  const movementThreshold = manualActive ? 0.18 : 0.45;
  if (
    !bypassCache &&
    collisionCache &&
    now - collisionCache.timestamp < updateInterval &&
    distanceBetween(collisionCache.target, target) < movementThreshold &&
    distanceBetween(collisionCache.desiredPosition, desiredPosition) < movementThreshold
  ) {
    return collisionCache.result;
  }

  if (isCameraPathClear(target, desiredPosition, ownVehicle)) {
    const result = { position: desiredPosition, collided: false, clearanceScore: 7 };
    collisionCache = { timestamp: now, target, desiredPosition, result };
    return result;
  }

  const direction = normalizeVector(subtractVector(desiredPosition, target));
  const desiredDistance = distanceBetween(target, desiredPosition);
  let clearDistance = 0.35;
  let blockedDistance = desiredDistance;

  // Find the furthest clear center ray first. Envelope probes are only run for
  // the resulting candidate instead of for every possible distance.
  for (let iteration = 0; iteration < 6; iteration += 1) {
    const testDistance = (clearDistance + blockedDistance) * 0.5;
    const candidate = addVector(target, scaleVector(direction, testDistance));
    if (isCameraPathClear(target, candidate, ownVehicle)) {
      clearDistance = testDistance;
    } else {
      blockedDistance = testDistance;
    }
  }

  let selectedCandidate = addVector(
    target,
    scaleVector(
      direction,
      Math.max(0.35, clearDistance - config.collisionSafetyMargin)
    )
  );
  let clearance = getCameraProbeClearance(target, selectedCandidate, ownVehicle);

  // Center, top and bottom are hard requirements. Side probes only request a
  // shoulder reduction; they no longer force the whole camera toward CJ.
  for (let iteration = 0; iteration < 3 && !clearance.accepted; iteration += 1) {
    clearDistance = Math.max(0.35, clearDistance * 0.78);
    selectedCandidate = addVector(target, scaleVector(direction, clearDistance));
    clearance = getCameraProbeClearance(target, selectedCandidate, ownVehicle);
  }

  const emergencyDistance = Math.max(
    0.8,
    Math.min(config.collisionEmergencyDistance, desiredDistance - config.collisionSafetyMargin)
  );
  const emergencyPosition = addVector(
    target,
    scaleVector(direction, emergencyDistance)
  );
  const result = {
    position: clearance.accepted ? selectedCandidate : emergencyPosition,
    collided: true,
    clearanceScore: clearance.score,
    shoulderObstructed: clearance.center && (!clearance.left || !clearance.right),
    emergency: !clearance.accepted && allowEmergency,
  };
  collisionCache = { timestamp: now, target, desiredPosition, result };
  return result;
}

function getCameraProbeClearance(target, cameraPosition, ownVehicle = null) {
  const direction = normalizeVector(subtractVector(cameraPosition, target));
  const right = { x: direction.y, y: -direction.x, z: 0 };
  const radius = config.collisionProbeRadius;
  const offsets = [
    { x: 0, y: 0, z: 0 },
    scaleVector(right, radius),
    scaleVector(right, -radius),
    { x: 0, y: 0, z: radius * 0.85 },
    { x: 0, y: 0, z: -radius * 0.65 },
  ];

  const clear = offsets.map((offset) =>
    isCameraPathClear(target, addVector(cameraPosition, offset), ownVehicle)
  );
  return {
    center: clear[0],
    right: clear[1],
    left: clear[2],
    top: clear[3],
    bottom: clear[4],
    accepted: clear[0] && clear[3] && clear[4],
    score: (clear[0] ? 3 : 0) + clear.slice(1).filter(Boolean).length,
  };
}

function isCameraPathClear(from, to, ownVehicle = null) {
  if (!ownVehicle) return isLineOfSightClear(from, to, false);
  // SA:DE LOS cannot exclude one specific car. A dynamic ray with cars=true
  // can still hit the player's vehicle after starting outside approximate
  // model bounds, collapsing every layout to the same emergency distance.
  // Keep vehicle cameras on the verified static-world pass.
  return isLineOfSightClear(from, to, true);
}

function isLineOfSightClear(from, to, ignoreVehicles = false) {
  const result = safeNative(
    "IS_LINE_OF_SIGHT_CLEAR",
    from.x,
    from.y,
    from.z,
    to.x,
    to.y,
    to.z,
    true,
    !ignoreVehicles,
    false,
    true,
    true
  );
  // If a custom runtime omits this native, do not pin the camera to the
  // player. The official SA:DE definition includes it.
  return result === null ? true : !!result;
}

function stabilizeVehicleCameraAnchor(sample, dt) {
  if (!sample?.vehicle || !isVector(sample.position)) {
    vehicleVisualAnchor = null;
    vehicleVisualAnchorVelocity = { x: 0, y: 0, z: 0 };
    vehicleVisualAnchorIdentity = null;
    return sample?.position;
  }

  const identity = sample.vehicleIdentity;
  const changedVehicle = vehicleVisualAnchorIdentity !== null &&
    identity !== null && vehicleVisualAnchorIdentity !== identity;
  if (!vehicleVisualAnchor || changedVehicle) {
    vehicleVisualAnchor = { ...sample.position };
    vehicleVisualAnchorIdentity = identity;
    const direction = sample.stableVelocityDirection || sample.forward;
    vehicleVisualAnchorVelocity = {
      x: direction.x * (sample.cameraSpeedMps || 0),
      y: direction.y * (sample.cameraSpeedMps || 0),
      z: sample.velocity?.z || 0,
    };
    return vehicleVisualAnchor;
  }

  const frameDt = clamp(dt || 1 / 60, 0.001, 0.05);
  const speedAmount = smoothstep(
    VEHICLE_VISUAL_ANCHOR_START_KMH,
    VEHICLE_VISUAL_ANCHOR_FULL_KMH,
    sample.cameraSpeedKmh ?? sample.speedKmh
  );
  const direction = sample.stableVelocityDirection || sample.forward;
  const measuredVelocity = {
    x: direction.x * (sample.cameraSpeedMps || 0),
    y: direction.y * (sample.cameraSpeedMps || 0),
    z: sample.velocity?.z || 0,
  };
  // These gains are tuned as 60 FPS reference values, but the correction must
  // cover the same amount of real time at every frame rate. Applying the raw
  // value once per frame made the predictor react only half as often at 30 FPS,
  // which showed up as visible catch-up steps at high vehicle speeds.
  const velocityAlpha = frameRateIndependentAlpha(
    lerp(0.62, 0.30, speedAmount),
    frameDt
  );
  vehicleVisualAnchorVelocity = lerpVector(
    vehicleVisualAnchorVelocity,
    measuredVelocity,
    velocityAlpha
  );

  const predicted = addVector(
    vehicleVisualAnchor,
    scaleVector(vehicleVisualAnchorVelocity, frameDt)
  );
  const residual = subtractVector(sample.position, predicted);
  const residualLength = vectorLength(residual);
  if (residualLength > VEHICLE_VISUAL_ANCHOR_RESET_DISTANCE) {
    vehicleVisualAnchor = { ...sample.position };
    vehicleVisualAnchorVelocity = measuredVelocity;
    vehicleVisualAnchorIdentity = identity;
    return vehicleVisualAnchor;
  }

  // Smooth only the noisy per-frame anchor displacement. Prediction keeps the
  // camera travelling with the car, while residual correction prevents the
  // old high-speed "left behind then catch up" behaviour.
  const correctionAlpha = frameRateIndependentAlpha(
    lerp(0.92, 0.42, speedAmount),
    frameDt
  );
  vehicleVisualAnchor = addVector(
    predicted,
    scaleVector(residual, correctionAlpha)
  );

  const anchorError = subtractVector(sample.position, vehicleVisualAnchor);
  const anchorErrorLength = vectorLength(anchorError);
  const maxAnchorError = lerp(
    VEHICLE_VISUAL_ANCHOR_MAX_ERROR_LOW,
    VEHICLE_VISUAL_ANCHOR_MAX_ERROR_HIGH,
    speedAmount
  );
  if (anchorErrorLength > maxAnchorError && anchorErrorLength > 0.0001) {
    vehicleVisualAnchor = subtractVector(
      sample.position,
      scaleVector(anchorError, maxAnchorError / anchorErrorLength)
    );
  }
  vehicleVisualAnchorIdentity = identity;
  return vehicleVisualAnchor;
}

function transportSpringWithVehicleAnchor(sample, transition = null) {
  if (!sample?.vehicle) {
    springAnchorPosition = null;
    return;
  }

  const currentAnchor = sample.position;
  if (!isVector(currentAnchor)) return;

  // During an explicit car<->ped handoff the transition already owns the
  // world-space interpolation. Translating the spring at the same time would
  // apply the anchor motion twice.
  if (transition && transition.amount < 1) {
    springAnchorPosition = { ...currentAnchor };
    return;
  }

  if (!cameraApplied || !springPosition || !springTarget || !springAnchorPosition) {
    springAnchorPosition = { ...currentAnchor };
    return;
  }

  const delta = subtractVector(currentAnchor, springAnchorPosition);
  const deltaLength = vectorLength(delta);
  if (deltaLength > 0.0001) {
    // isHardTeleport() has already rejected implausible anchor jumps before
    // the director runs. Do not impose another fixed 12 m transport cap here:
    // after a long frame at high speed that cap left the world-space spring
    // behind the car, producing the visible "pull back / catch up" jerk.
    springPosition = addVector(springPosition, delta);
    springTarget = addVector(springTarget, delta);
  }

  springAnchorPosition = { ...currentAnchor };
}

function initializeSpringIfNeeded(desiredPosition, desiredTarget, anchor, ownVehicle = null) {
  if (cameraApplied) return;

  const nativeCamera = getCameraState();
  const nativeDistance = nativeCamera?.position
    ? distanceBetween(anchor, nativeCamera.position)
    : Infinity;
  const nativeHeight = nativeCamera?.position
    ? nativeCamera.position.z - anchor.z
    : Infinity;
  const canSeedFromNative = !!nativeCamera &&
    nativeDistance >= 1.0 && nativeDistance <= 15 &&
    nativeHeight >= MIN_CAMERA_RELATIVE_Z && nativeHeight <= 8 &&
    isSafeCameraPose(anchor, nativeCamera.position, nativeCamera.pointAt) &&
    isCameraPathClear(desiredTarget, nativeCamera.position, ownVehicle);

  if (canSeedFromNative) {
    springPosition = nativeCamera.position;
    springTarget = nativeCamera.pointAt;
    log("Adaptive Third-Person Camera seeded spring from native camera.");
  } else {
    springPosition = desiredPosition;
    springTarget = desiredTarget;
  }
  springPositionVelocity = { x: 0, y: 0, z: 0 };
  springTargetVelocity = { x: 0, y: 0, z: 0 };
  resetScriptCamera();
}

function setScriptCameraPose(position, target) {
  try {
    if (!isVector(position) || !isVector(target)) {
      throw new Error("invalid camera vector");
    }
    const targetDistance = distanceBetween(position, target);
    if (targetDistance < 0.25 || targetDistance > 50) {
      throw new Error("invalid camera target distance");
    }

    // This is the only owner of the scripted camera. PersistPos/PersistTrack
    // are intentionally left disabled: toggling them every frame lets the
    // native camera and the fixed camera fight over the rendered transform.
    if (!invokeCameraMethod(
      "SetFixedPosition",
      position.x,
      position.y,
      position.z,
      0,
      0,
      1
    )) {
      native(
        "SET_FIXED_CAMERA_POSITION",
        position.x,
        position.y,
        position.z,
        0,
        0,
        1
      );
    }

    if (!invokeCameraMethod("PointAtPoint", target.x, target.y, target.z, 2)) {
      native("POINT_CAMERA_AT_POINT", target.x, target.y, target.z, 2);
    }
    if (!cameraPoseDiagnosticLogged) {
      cameraPoseDiagnosticLogged = true;
      log(
        "Adaptive Third-Person Camera applied pose camera=" + formatVector(position) +
          " target=" + formatVector(target) +
          " distance=" + targetDistance.toFixed(2)
      );
    }
    return true;
  } catch (_) {
    cameraSessionDisabled = true;
    cameraApplied = true;
    log(
      "Adaptive Third-Person Camera: required camera native failed; disabling the current camera session."
    );
    releaseCamera();
    return false;
  }
}

function releaseCamera(forcePedestrianJumpcut = false) {
  resetNativeVehicleTweak();
  const hadCameraControl =
    cameraApplied || vehicleFovOwned || fovProbe || nativeCameraFovActive;
  anchorTransition = null;
  manualControlActive = false;
  vehicleManualStickFrames = 0;
  vehicleManualInputSuppressedUntil = 0;
  mouseMovementBaselineX = null;
  mouseMovementBaselineY = null;
  mouseBaselineCalibrateUntil = 0;
  previousRawMouseX = null;
  previousRawMouseY = null;
  previousMouseCursorPosition = null;
  relativeMouseAnchor = null;
  relativeMouseSetCursorAvailable = null;
  relativeMouseObservedMotion = false;
  lastRelativeMouseMotionAt = 0;
  mouseGestureUntil = 0;
  cancelNativeMouseBridge();
  vehicleVisualAnchor = null;
  vehicleVisualAnchorVelocity = { x: 0, y: 0, z: 0 };
  vehicleVisualAnchorIdentity = null;
  lastManualInputDiagnosticAt = 0;
  vehicleCameraControl = CameraControl.AUTO;
  vehicleOrbitYaw = null;
  vehicleOrbitPitch = 0;
  vehicleRecenterStartedAt = 0;
  vehicleRecenterFromYaw = null;
  vehicleRecenterFromPitch = 0;
  springAnchorPosition = null;
  manualFreeUntil = 0;
  manualRecenterUntil = 0;
  collisionCache = null;
  collisionEmergencySince = 0;
  fovProbe = null;
  nativeCameraFovActive = false;
  lastSpringPathValidationAt = 0;
  vehicleFollowDirection = null;
  reverseState = false;
  reverseCandidateSince = 0;
  forwardCandidateSince = 0;
  airborneSince = 0;
  landingUntil = 0;
  if (hadCameraControl || forcePedestrianJumpcut) {
    resetScriptCamera();
    if (forcePedestrianJumpcut) restoreScriptCameraJumpcut();
    else restoreScriptCamera();
  }
  if (vehicleFovOwned && Number.isFinite(vehicleSessionFov)) {
    // One restoration only. Subsequent pedestrian frames issue no camera writes.
    const current = getCameraFov();
    setLerpFov(Number.isFinite(current) ? current : vehicleSessionFov, vehicleSessionFov, 0);
  }
  vehicleSessionFov = null;
  vehicleFovOwned = false;
  cameraApplied = false;
  cameraPoseDiagnosticLogged = false;
  lastLayoutDiagnosticRevision = -1;
  lastVehicleGeometryDiagnosticKey = null;
  springPosition = null;
  springTarget = null;
  springPositionVelocity = { x: 0, y: 0, z: 0 };
  springTargetVelocity = { x: 0, y: 0, z: 0 };
  lastStateName = null;
  lastAppliedFovTarget = null;
  nativeCameraFovActive = false;
}

function springStep(current, target, velocity, frequencyHz, dampingRatio, verticalTracking, dt) {
  const tracking = clamp(verticalTracking, 0.18, 1);
  const verticalAlpha = frameRateIndependentAlpha(tracking, dt);
  const effectiveTarget = {
    x: target.x,
    y: target.y,
    z: lerp(current.z, target.z, verticalAlpha),
  };
  const x = dampedScalarStep(
    current.x,
    effectiveTarget.x,
    velocity.x,
    frequencyHz,
    dampingRatio,
    dt
  );
  const y = dampedScalarStep(
    current.y,
    effectiveTarget.y,
    velocity.y,
    frequencyHz,
    dampingRatio,
    dt
  );
  const z = dampedScalarStep(
    current.z,
    effectiveTarget.z,
    velocity.z,
    frequencyHz,
    dampingRatio,
    dt
  );
  return {
    position: { x: x.value, y: y.value, z: z.value },
    velocity: { x: x.velocity, y: y.velocity, z: z.velocity },
  };
}

function dampedScalarStep(current, target, velocity, frequencyHz, dampingRatio, dt) {
  const step = clamp(dt, 0.001, 0.05);
  const omega = Math.max(0.1, frequencyHz) * Math.PI * 2;
  const ratio = Math.max(0.05, dampingRatio);
  const displacement = current - target;

  if (Math.abs(ratio - 1) < 0.001) {
    const decay = Math.exp(-omega * step);
    const temp = (velocity + omega * displacement) * step;
    const nextDisplacement = (displacement + temp) * decay;
    const nextVelocity = (velocity - omega * temp) * decay;
    return { value: target + nextDisplacement, velocity: nextVelocity };
  }

  if (ratio < 1) {
    const dampedOmega = omega * Math.sqrt(1 - ratio * ratio);
    const decay = Math.exp(-ratio * omega * step);
    const sine = Math.sin(dampedOmega * step);
    const cosine = Math.cos(dampedOmega * step);
    const coefficient = (velocity + ratio * omega * displacement) / dampedOmega;
    const nextDisplacement = decay * (displacement * cosine + coefficient * sine);
    const nextVelocity = decay * (
      velocity * cosine -
      (ratio * omega * coefficient + displacement * dampedOmega) * sine
    );
    return { value: target + nextDisplacement, velocity: nextVelocity };
  }

  const root = Math.sqrt(ratio * ratio - 1);
  const rootOne = -omega * (ratio - root);
  const rootTwo = -omega * (ratio + root);
  const coefficientOne = (velocity - rootTwo * displacement) / (rootOne - rootTwo);
  const coefficientTwo = displacement - coefficientOne;
  const decayOne = Math.exp(rootOne * step);
  const decayTwo = Math.exp(rootTwo * step);
  const nextDisplacement = coefficientOne * decayOne + coefficientTwo * decayTwo;
  const nextVelocity = coefficientOne * rootOne * decayOne + coefficientTwo * rootTwo * decayTwo;
  return { value: target + nextDisplacement, velocity: nextVelocity };
}

function readAnyVehicleState(actor) {
  return !!safeNative("IS_CHAR_IN_ANY_CAR", actor) ||
    !!safeNative("IS_CHAR_IN_ANY_BOAT", actor) ||
    !!safeNative("IS_CHAR_IN_ANY_HELI", actor) ||
    !!safeNative("IS_CHAR_IN_ANY_PLANE", actor);
}

function resolveInteractionState(vehicleState, now) {
  const sittingInVehicle = vehicleState.isSitting && !vehicleState.isOnFoot;
  const inAnyVehicle = vehicleState.interactingWithVehicle;
  let nextState = interactionState;
  if (sittingInVehicle) {
    nextState = "driving";
  } else if (vehicleState.isOnFoot && inAnyVehicle) {
    // Latch EXITING once it starts. The broad vehicle-use natives may remain
    // true for several door-animation frames; without this latch the state can
    // oscillate driving -> exiting -> entering.
    nextState = interactionState === "driving" || interactionState === "exiting"
      ? "exiting"
      : "entering";
  } else if (!vehicleState.isOnFoot && inAnyVehicle) {
    // Keep an already latched exit stable if a native flickers for a frame.
    // Otherwise stay DRIVING only if driving had already been established;
    // an entering ped is not promoted until the sitting native confirms it.
    if (interactionState === "exiting") nextState = "exiting";
    else if (interactionState === "driving") nextState = "driving";
    else if (interactionState === "entering" &&
             now - interactionStateStartedAt >= VEHICLE_ENTER_FALLBACK_MS) {
      // Some SA:DE/CLEO combinations intermittently fail to report the
      // sitting native. A long, continuous not-on-foot vehicle interaction is
      // a conservative fallback so the camera cannot remain ENTERING forever.
      nextState = "driving";
    } else nextState = "entering";
  } else {
    nextState = "onFoot";
  }

  if (nextState !== interactionState) {
    interactionState = nextState;
    interactionStateStartedAt = now;
  }
  return interactionState;
}

function readPlayerVehicleState(actor) {
  const onFootNative = safeNative("IS_CHAR_ON_FOOT", actor);
  const onFoot = onFootNative === true || onFootNative === 1;
  const sittingNative = safeNative("IS_CHAR_SITTING_IN_ANY_CAR", actor);
  const sitting = sittingNative === true || sittingNative === 1;
  const interactingWithVehicle = readAnyVehicleState(actor);

  // IS_CHAR_IN_ANY_CAR may keep returning true after the ped has left because
  // it describes a vehicle interaction, not strictly an occupied seat.
  // Conversely, IS_CHAR_SITTING_IN_ANY_CAR is unreliable on some CLEO Redux
  // SA:DE builds. IS_CHAR_ON_FOOT is therefore the authoritative exit signal.
  return {
    onFoot,
    isOnFoot: onFoot,
    sittingNative,
    isSitting: sitting,
    interactingWithVehicle,
  };
}

function getPlayerVehicle(actor, vehicleState = null) {
  // IS_CHAR_IN_ANY_CAR also stays true while the player is opening or
  // closing a door. It is useful as an interaction signal, but it is not
  // sufficient to make the vehicle the camera anchor.
  const state = vehicleState || readPlayerVehicleState(actor);
  if (
    state.isOnFoot ||
    (!state.isSitting && !state.interactingWithVehicle)
  ) return null;

  try {
    if (actor && typeof actor.getCarIsUsing === "function") {
      const vehicle = actor.getCarIsUsing();
      if (isUsableVehicleHandle(vehicle)) return vehicle;
    }
  } catch (_) {}
  const fallback = toHandle(safeNative("STORE_CAR_CHAR_IS_IN_NO_SAVE", actor), Car);
  return isUsableVehicleHandle(fallback) ? fallback : null;
}

function isUsableVehicleHandle(vehicle) {
  if (vehicle === null || vehicle === undefined || vehicle === false) return false;
  if (typeof vehicle === "number") return Number.isFinite(vehicle) && vehicle > 0;

  const identity = getEntityIdentity(vehicle);
  // Some CLEO wrappers do not expose their script handle as a JS property. In
  // that case coordinate/proximity validation in isSaneVehicleAnchor() remains
  // authoritative. If an identity is exposed, zero/negative handles are never
  // valid vehicle anchors.
  return identity === null || identity > 0;
}

function isSanePlayerAnchor(position, previousPosition, previousAt, now) {
  if (!isVector(position)) return false;

  // Some DE/CLEO wrappers briefly return the zero vector for CJ during the
  // vehicle -> pedestrian ownership handoff. If CJ was somewhere else a frame
  // ago, (0,0,0) is a transient read failure and must never validate the car
  // anchor. The short time window keeps genuine teleports compatible.
  const nearOrigin = vectorLength(position) < PLAYER_ORIGIN_GLITCH_RADIUS;
  if (nearOrigin && isVector(previousPosition)) {
    const previousAwayFromOrigin = vectorLength(previousPosition) >=
      PLAYER_ORIGIN_CONTINUITY_DISTANCE;
    const recent = now - previousAt <= PLAYER_ORIGIN_CONTINUITY_GUARD_MS;
    if (previousAwayFromOrigin && recent) return false;
  }
  return true;
}

function isSaneVehicleAnchor(vehiclePosition, actorPosition) {
  if (!isVector(vehiclePosition)) return false;

  // Exact/near world origin is the characteristic invalid-handle result that
  // caused the camera to jump under the map after leaving a car. Do not reject
  // a genuinely nearby origin position solely on coordinates; compare it with
  // the player's ped position when that is available.
  const vehicleNearOrigin = vectorLength(vehiclePosition) < 0.75;
  if (isVector(actorPosition)) {
    const actorNearOrigin = vectorLength(actorPosition) < 4;
    if (vehicleNearOrigin && !actorNearOrigin) return false;

    // While seated or during the door handoff, CJ must remain physically close
    // to the occupied vehicle. A large separation means the returned vehicle is
    // stale/unrelated and is unsafe as a camera anchor.
    if (distanceBetween(vehiclePosition, actorPosition) > 30) return false;
  } else if (vehicleNearOrigin) {
    return false;
  }

  return true;
}

function classifyVehicle(actor, vehicle) {
  if (!vehicle) return "onFoot";
  if (safeNative("IS_CHAR_IN_ANY_PLANE", actor)) return "aircraft";
  if (safeNative("IS_CHAR_IN_ANY_HELI", actor)) return "helicopter";
  if (safeNative("IS_CHAR_IN_ANY_BOAT", actor)) return "boat";
  const model = getVehicleModel(vehicle);
  if (VEHICLE_MODELS.bicycles.has(model)) return "bicycle";
  if (VEHICLE_MODELS.motorcycles.has(model)) return "motorbike";
  return "car";
}

function getCoordinates(entity, vehicle) {
  try {
    if (entity && typeof entity.getCoordinates === "function") {
      const coordinates = entity.getCoordinates();
      if (isVector(coordinates)) return coordinates;
    }
  } catch (_) {}
  const value = safeNative(vehicle ? "GET_CAR_COORDINATES" : "GET_CHAR_COORDINATES", entity);
  return isVector(value) ? value : null;
}

function readNativeVelocity(entity, vehicle) {
  try {
    const value = vehicle && entity && typeof entity.getSpeedVector === "function"
      ? entity.getSpeedVector()
      : !vehicle && entity && typeof entity.getVelocity === "function"
        ? entity.getVelocity()
        : null;
    if (isVector(value)) return value;
  } catch (_) {}

  const value = safeNative(
    vehicle ? "GET_CAR_SPEED_VECTOR" : "GET_CHAR_VELOCITY",
    entity
  );
  return isVector(value) ? value : null;
}

function getEntityIdentity(entity) {
  if (entity === null || entity === undefined) return null;
  if (typeof entity === "number" && Number.isFinite(entity)) return entity;
  if (typeof entity === "object") {
    for (const key of ["handle", "id", "_handle", "scriptHandle", "value"]) {
      try {
        const value = Number(entity[key]);
        if (Number.isFinite(value)) return value;
      } catch (_) {}
    }
  }
  return null;
}

function getEntityHeading(entity, vehicle) {
  try {
    if (entity && typeof entity.getHeading === "function") {
      return finiteNumber(entity.getHeading(), 0);
    }
  } catch (_) {}
  return finiteNumber(
    safeNative(vehicle ? "GET_CAR_HEADING" : "GET_CHAR_HEADING", entity),
    0
  );
}

function getEntityForward(entity, vehicle, heading) {
  if (vehicle) {
    try {
      if (entity &&
          typeof entity.getForwardX === "function" &&
          typeof entity.getForwardY === "function") {
        const x = Number(entity.getForwardX());
        const y = Number(entity.getForwardY());
        const vector = { x, y, z: 0 };
        if (Number.isFinite(x) && Number.isFinite(y) && vectorLength(vector) > 0.25) {
          return normalizeVector(vector);
        }
      }
    } catch (_) {}

    const nativeX = safeNative("GET_CAR_FORWARD_X", entity);
    const nativeY = safeNative("GET_CAR_FORWARD_Y", entity);
    const x = Number(nativeX);
    const y = Number(nativeY);
    const vector = { x, y, z: 0 };
    if (nativeX !== null && nativeX !== undefined &&
        nativeY !== null && nativeY !== undefined &&
        Number.isFinite(x) && Number.isFinite(y) && vectorLength(vector) > 0.25) {
      return normalizeVector(vector);
    }
  }

  return headingVector(heading);
}

function getEntitySpeed(entity, vehicle) {
  try {
    if (entity && typeof entity.getSpeed === "function") {
      return finiteNumber(entity.getSpeed(), 0);
    }
  } catch (_) {}
  return finiteNumber(
    safeNative(vehicle ? "GET_CAR_SPEED" : "GET_CHAR_SPEED", entity),
    0
  );
}

function getVehicleUprightValue(vehicle) {
  if (!vehicle) return 1;
  try {
    if (typeof vehicle.getUprightValue === "function") {
      return finiteNumber(vehicle.getUprightValue(), 1);
    }
  } catch (_) {}
  return finiteNumber(safeNative("GET_CAR_UPRIGHT_VALUE", vehicle), 1);
}


function releaseScriptCameraForNativeOrbit() {
  // FOV interpolation is independent from fixed-position camera ownership.
  // Do not cancel fovProbe here; otherwise the capability probe restarts every
  // frame and native-vehicle dynamic FOV can never become active.
  if (!cameraApplied) return;

  resetScriptCamera();
  restoreScriptCamera();
  cameraApplied = false;
  springPosition = null;
  springTarget = null;
  springPositionVelocity = { x: 0, y: 0, z: 0 };
  springTargetVelocity = { x: 0, y: 0, z: 0 };
  springAnchorPosition = null;
  collisionCache = null;
  lastSpringPathValidationAt = 0;
}

function getNativeVehicleSpeedBucket(speedKmh) {
  const speed = Math.max(0, finiteNumber(speedKmh, 0));
  const enter = NATIVE_VEHICLE_SPEED_BUCKETS;
  const exit = [35, 70, 108, 142];

  while (nativeVehicleSpeedBucket < enter.length &&
      speed >= enter[nativeVehicleSpeedBucket]) {
    nativeVehicleSpeedBucket += 1;
  }
  while (nativeVehicleSpeedBucket > 0 &&
      speed <= exit[nativeVehicleSpeedBucket - 1]) {
    nativeVehicleSpeedBucket -= 1;
  }
  return nativeVehicleSpeedBucket;
}

function getNativeVehicleTweak(sample, now) {
  const layoutIndex = clamp(cameraLayoutController.layout, 0, 2);
  const speedBucket = getNativeVehicleSpeedBucket(
    sample.cameraSpeedKmh ?? sample.speedKmh
  );

  const layoutDistance = [0.86, 1.08, 1.30][layoutIndex];
  const layoutAltitude = [0.95, 1.055, 1.15][layoutIndex];
  const speedDistance = [0.00, 0.055, 0.12, 0.19, 0.26][speedBucket];
  const speedAltitude = [0.00, 0.018, 0.040, 0.064, 0.090][speedBucket];

  let driftBucket = 0;
  let accelerationBucket = 0;
  let airborneBucket = 0;
  if (config.nativeVehicleContextualTweak) {
    driftBucket = Math.round(clamp(driftAmount(sample), 0, 1) * 2);
    const acceleration = finiteNumber(sample.filteredAccelerationMps2, 0);
    accelerationBucket = acceleration > 2.2 ? 1 : acceleration < -3.0 ? -1 : 0;
    airborneBucket = sample.airState === "airborne" ? 1 : 0;
  }

  // Contextual values stay intentionally subtle because 09EF is a model-level
  // native tweak. The game still owns orbit, collision and mouse/right-stick.
  const distance = layoutDistance + speedDistance +
    driftBucket * 0.045 +
    (accelerationBucket > 0 ? 0.045 : accelerationBucket < 0 ? -0.025 : 0);
  const altitude = layoutAltitude + speedAltitude +
    driftBucket * 0.018 + airborneBucket * 0.045;

  return {
    distance,
    altitude,
    angle: 0.12,
    speedBucket,
    driftBucket,
    accelerationBucket,
    airborneBucket,
    layoutIndex,
  };
}

function setNativeVehicleTweak(modelId, distance, altitude, angle) {
  try {
    if (typeof Camera !== "undefined" &&
        typeof Camera.SetVehicleTweak === "function") {
      Camera.SetVehicleTweak(modelId, distance, altitude, angle);
      return true;
    }
  } catch (_) {}

  try {
    native("SET_VEHICLE_CAMERA_TWEAK", modelId, distance, altitude, angle);
    return true;
  } catch (_) {
    return false;
  }
}

function resetNativeVehicleTweak() {
  if (!nativeVehicleTweakActive) return;

  try {
    if (typeof Camera !== "undefined" &&
        typeof Camera.ResetVehicleTweak === "function") {
      Camera.ResetVehicleTweak();
    } else {
      native("RESET_VEHICLE_CAMERA_TWEAK");
    }
  } catch (_) {
    try {
      safeNative("RESET_VEHICLE_CAMERA_TWEAK");
    } catch (_) {}
  }

  nativeVehicleTweakActive = false;
  nativeVehicleTweakModel = -1;
  nativeVehicleTweakKey = "";
  nativeVehicleSpeedBucket = 0;
  lastNativeVehicleTweakAt = 0;
}

function applyNativeVehicleCamera(sample, now) {
  const modelId = getVehicleModel(sample.vehicle);
  if (!Number.isFinite(modelId) || modelId < 0) return;

  const tweak = getNativeVehicleTweak(sample, now);
  const key = [
    modelId,
    tweak.layoutIndex,
    tweak.speedBucket,
    tweak.driftBucket,
    tweak.accelerationBucket,
    tweak.airborneBucket,
  ].join(":");

  if (key === nativeVehicleTweakKey &&
      now - lastNativeVehicleTweakAt < NATIVE_VEHICLE_TWEAK_UPDATE_MS) {
    return;
  }
  if (key === nativeVehicleTweakKey) {
    // Do not continuously rewrite 09EF. The engine owns the camera and its
    // interpolation; reapplying identical values can itself create micro-jank.
    return;
  }

  const previousCapability = nativeVehicleTweakCapability;
  const ok = setNativeVehicleTweak(
    modelId,
    tweak.distance,
    tweak.altitude,
    tweak.angle
  );
  nativeVehicleTweakCapability = ok;

  if (ok) {
    nativeVehicleTweakActive = true;
    nativeVehicleTweakModel = modelId;
    nativeVehicleTweakKey = key;
    lastNativeVehicleTweakAt = now;
    log(
      "Adaptive Third-Person Camera hybrid vehicle camera" +
        " model=" + modelId +
        " layout=" + VEHICLE_CAMERA_LAYOUT_NAMES[tweak.layoutIndex] +
        " speedBucket=" + tweak.speedBucket +
        " driftBucket=" + tweak.driftBucket +
        " accelBucket=" + tweak.accelerationBucket +
        " airborne=" + tweak.airborneBucket +
        " distanceTweak=" + tweak.distance.toFixed(2) +
        " altitudeTweak=" + tweak.altitude.toFixed(2) +
        " angle=" + tweak.angle.toFixed(2)
    );
  } else if (previousCapability !== false) {
    log(
      "Adaptive Third-Person Camera: native vehicle camera tweak unavailable; " +
      "using GTA stock vehicle camera."
    );
  }
}

function applyNativeVehicleDynamicEffects(sample, now) {
  if (!config.nativeVehicleDynamicFov) return;

  // Reuse the same profile system as the scripted camera so entering a car no
  // longer throws away speed/acceleration/drift FOV behavior. Transform/input
  // remain native; only FOV is interpolated here.
  const profileValue = buildProfile(sample);
  const targetFov = clamp(profileValue.fov, 50, 90);
  nativeCameraFovActive = true;
  applyRequestedFov(targetFov, 160, now);
}

function getVehicleModel(vehicle) {
  try {
    if (vehicle && typeof vehicle.getModel === "function") {
      return finiteNumber(vehicle.getModel(), -1);
    }
  } catch (_) {}
  return finiteNumber(safeNative("GET_CAR_MODEL", vehicle), -1);
}

function getCameraState() {
  let position = null;
  let pointAt = null;
  try {
    if (typeof Camera !== "undefined" && typeof Camera.GetActiveCoordinates === "function") {
      position = Camera.GetActiveCoordinates();
    }
    if (typeof Camera !== "undefined" && typeof Camera.GetActivePointAt === "function") {
      pointAt = Camera.GetActivePointAt();
    }
  } catch (_) {}
  position = isVector(position) ? position : safeNative("GET_ACTIVE_CAMERA_COORDINATES");
  pointAt = isVector(pointAt) ? pointAt : safeNative("GET_ACTIVE_CAMERA_POINT_AT");
  if (!isVector(position) || !isVector(pointAt)) return null;
  const forward = normalizeVector(subtractVector(pointAt, position));
  return vectorLength(forward) > 0.01 ? { position, pointAt, forward } : null;
}

function readManualCameraInput(now = getGameTimerMs()) {
  // v27: scripted camera needs a real free-look signal, but SA:DE can expose a
  // stable synthetic +3,+3-ish GET_PC_MOUSE_MOVEMENT value while the physical
  // mouse is idle. Treat that stable vector as a learned bias instead of using
  // it as a gate. Real movement is reconstructed from three independent
  // candidates: raw-minus-bias, frame-to-frame raw variation and OS cursor
  // displacement. The strongest candidate wins immediately; there is no
  // gesture-confirmation latch that can swallow short mouse movements.
  let sticks = {};
  try {
    if (typeof Pad !== "undefined" &&
        typeof Pad.GetPositionOfAnalogueSticks === "function") {
      sticks = Pad.GetPositionOfAnalogueSticks(PAD_ID) || {};
    } else {
      sticks = safeNative("GET_POSITION_OF_ANALOGUE_STICKS", PAD_ID) || {};
    }
  } catch (_) {
    sticks = safeNative("GET_POSITION_OF_ANALOGUE_STICKS", PAD_ID) || {};
  }

  const stickX = finiteNumber(sticks.rightStickX, 0);
  const stickY = finiteNumber(sticks.rightStickY, 0);
  const stickMagnitude = Math.sqrt(stickX * stickX + stickY * stickY);

  let mouse = readUnifiedCameraMovement();
  if (!mouse) {
    const rawMouse = safeNative("GET_PC_MOUSE_MOVEMENT");
    mouse = rawMouse && typeof rawMouse === "object" ? rawMouse : {};
  }

  const rawMouseX = finiteNumber(mouse.deltaX ?? mouse.x, 0);
  const rawMouseY = finiteNumber(mouse.deltaY ?? mouse.y, 0);
  const inversion = isMouseUsingVerticalInversion() ? -1 : 1;
  const rawMouseMagnitude = Math.sqrt(rawMouseX * rawMouseX + rawMouseY * rawMouseY);

  const mouseMirrorsStick = stickMagnitude > 0.5 &&
    Math.abs(rawMouseX - stickX) <= 1.5 &&
    (Math.abs(rawMouseY - stickY) <= 1.5 ||
      Math.abs(rawMouseY + stickY) <= 1.5);

  const oldRawX = previousRawMouseX;
  const oldRawY = previousRawMouseY;
  const rawVariationX = oldRawX === null ? 0 : rawMouseX - oldRawX;
  const rawVariationY = oldRawY === null ? 0 : rawMouseY - oldRawY;
  const rawVariation = Math.sqrt(
    rawVariationX * rawVariationX + rawVariationY * rawVariationY
  );
  previousRawMouseX = rawMouseX;
  previousRawMouseY = rawMouseY;

  let cursorDeltaX = 0;
  let cursorDeltaY = 0;
  let cursorMagnitude = 0;
  let relativeCursorAvailable = false;
  let relativeCursorActive = false;
  const cursor = readMouseCursorPosition();

  // v32 cursor path:
  // 1) always calculate passive frame-to-frame cursor delta first;
  // 2) if an absolute anchor is usable, try to re-center only after actual
  //    movement, rather than calling SetCursorPos every idle frame;
  // 3) if re-centering fails, keep the passive delta instead of dropping the
  //    mouse input completely.
  if (cursor) {
    const previousCursor = previousMouseCursorPosition;
    let passiveDeltaX = previousCursor ? cursor.x - previousCursor.x : 0;
    let passiveDeltaY = previousCursor ? cursor.y - previousCursor.y : 0;
    let passiveMagnitude = Math.sqrt(
      passiveDeltaX * passiveDeltaX + passiveDeltaY * passiveDeltaY
    );
    if (passiveMagnitude > MOUSE_CURSOR_MAX_DELTA_PIXELS) {
      passiveDeltaX = 0;
      passiveDeltaY = 0;
      passiveMagnitude = 0;
    }

    cursorDeltaX = passiveDeltaX;
    cursorDeltaY = passiveDeltaY;
    cursorMagnitude = passiveMagnitude;

    if (RELATIVE_CURSOR_ENABLED) {
      if (!relativeMouseAnchor) {
        relativeMouseAnchor = { x: cursor.x, y: cursor.y };
        // Do not probe by warping the pointer while idle. Some DE/Wine input
        // paths treat that warp as camera input suppression.
        relativeMouseSetCursorAvailable = null;
      }

      if (relativeMouseAnchor) {
        let anchorDeltaX = cursor.x - relativeMouseAnchor.x;
        let anchorDeltaY = cursor.y - relativeMouseAnchor.y;
        let anchorMagnitude = Math.sqrt(
          anchorDeltaX * anchorDeltaX + anchorDeltaY * anchorDeltaY
        );

        if (anchorMagnitude > RELATIVE_CURSOR_REANCHOR_DISTANCE) {
          // Focus changes / alt-tab can move the pointer far away. Adopt the
          // new location without generating a giant camera turn.
          relativeMouseAnchor = { x: cursor.x, y: cursor.y };
          relativeMouseSetCursorAvailable = null;
          cursorDeltaX = 0;
          cursorDeltaY = 0;
          cursorMagnitude = 0;
          previousMouseCursorPosition = cursor;
        } else if (anchorMagnitude >= RELATIVE_CURSOR_ACTIVATION_PIXELS) {
          if (anchorMagnitude > RELATIVE_CURSOR_MAX_DELTA_PIXELS) {
            const scale = RELATIVE_CURSOR_MAX_DELTA_PIXELS / anchorMagnitude;
            anchorDeltaX *= scale;
            anchorDeltaY *= scale;
            anchorMagnitude = RELATIVE_CURSOR_MAX_DELTA_PIXELS;
          }

          const recentered = setMouseCursorPosition(
            relativeMouseAnchor.x,
            relativeMouseAnchor.y
          );
          relativeCursorAvailable = recentered;
          relativeMouseSetCursorAvailable = recentered;

          if (recentered) {
            cursorDeltaX = anchorDeltaX;
            cursorDeltaY = anchorDeltaY;
            cursorMagnitude = anchorMagnitude;
            relativeCursorActive = true;
            relativeMouseObservedMotion = true;
            lastRelativeMouseMotionAt = now;
            // SetCursorPos has moved the OS cursor back to the anchor. Seed the
            // next passive sample from that same location to avoid a fake
            // reverse delta on the next frame.
            previousMouseCursorPosition = {
              x: relativeMouseAnchor.x,
              y: relativeMouseAnchor.y,
            };
          } else {
            // Crucial v32 fallback: preserve the passive movement instead of
            // losing all mouse input when SetCursorPos is unavailable.
            relativeCursorActive = false;
            previousMouseCursorPosition = cursor;
          }
        } else {
          previousMouseCursorPosition = cursor;
        }
      }
    } else {
      previousMouseCursorPosition = cursor;
    }
  }

  const looksLikeIdleDiagonal = !mouseMirrorsStick && stickMagnitude < 0.5 &&
    rawMouseX > 0.5 && rawMouseY > 0.5 &&
    rawMouseMagnitude <= 6.25 &&
    Math.abs(rawMouseX - rawMouseY) <= 0.65;

  if (!mouseMirrorsStick &&
      (mouseMovementBaselineX === null || mouseMovementBaselineY === null)) {
    // Only auto-learn the first sample when it matches the known synthetic
    // diagonal signature. A first real mouse gesture must not become "zero".
    if (looksLikeIdleDiagonal) {
      mouseMovementBaselineX = rawMouseX;
      mouseMovementBaselineY = rawMouseY;
    } else {
      mouseMovementBaselineX = 0;
      mouseMovementBaselineY = 0;
    }
  }

  const baselineX = finiteNumber(mouseMovementBaselineX, 0);
  const baselineY = finiteNumber(mouseMovementBaselineY, 0);
  let mouseX = mouseMirrorsStick ? 0 : rawMouseX - baselineX;
  let mouseY = mouseMirrorsStick ? 0 : (rawMouseY - baselineY) * inversion;

  // A stable synthetic diagonal is bias, not input. Importantly, this is not a
  // prerequisite for accepting movement: any meaningful variation, sign
  // change or cursor displacement bypasses this suppression immediately.
  const idleDiagonalSignature = looksLikeIdleDiagonal &&
    rawVariation <= 0.30 && cursorMagnitude < 1.0 &&
    Math.sqrt(mouseX * mouseX + mouseY * mouseY) <= 0.85;
  if (idleDiagonalSignature) {
    mouseX = 0;
    mouseY = 0;
  }

  // Candidate #2: high-pass component. This catches DE/Wine builds where the
  // absolute opcode value is biased but physical motion still changes it.
  const variationX = mouseMirrorsStick ? 0 : rawVariationX;
  const variationY = mouseMirrorsStick ? 0 : rawVariationY * inversion;
  const variationMagnitude = Math.sqrt(
    variationX * variationX + variationY * variationY
  );
  // A direct mouse gesture is trustworthy if it came from a successful
  // relative-cursor sample, a real frame-to-frame OS cursor movement, or a
  // changing game-level mouse vector. SA:DE/Wine can also expose the synthetic
  // positive diagonal (usually around +3,+3); when the OS cursor did not move,
  // that value must never enter the manual camera path, even if its baseline
  // is still calibrating and the frame-to-frame variation is noisy.
  const syntheticDiagonalWithoutCursor = looksLikeIdleDiagonal &&
    !relativeCursorActive &&
    cursorMagnitude < 1.0;
  const mouseInputReliable = !mouseMirrorsStick && (
    relativeCursorActive ||
    cursorMagnitude >= 1.0 ||
    (variationMagnitude >= 0.32 && !syntheticDiagonalWithoutCursor)
  );
  let bestMagnitude = Math.sqrt(mouseX * mouseX + mouseY * mouseY);
  if (syntheticDiagonalWithoutCursor) {
    mouseX = 0;
    mouseY = 0;
    bestMagnitude = 0;
  }
  if (!syntheticDiagonalWithoutCursor &&
      variationMagnitude >= 0.32 && variationMagnitude > bestMagnitude) {
    mouseX = variationX;
    mouseY = variationY;
    bestMagnitude = variationMagnitude;
  }

  // Candidate #3: v31 WinAPI relative cursor movement. When active this is
  // the authoritative physical-mouse source and wins over the broken game-level
  // diagonal value regardless of magnitude.
  if (!mouseMirrorsStick && relativeCursorActive) {
    const cursorX = clamp(cursorDeltaX, -80, 80) * RELATIVE_CURSOR_TO_MOUSE_UNITS;
    const cursorY = clamp(cursorDeltaY, -80, 80) * RELATIVE_CURSOR_TO_MOUSE_UNITS * inversion;
    mouseX = cursorX;
    mouseY = cursorY;
    bestMagnitude = Math.sqrt(cursorX * cursorX + cursorY * cursorY);
  } else if (!mouseMirrorsStick && cursorMagnitude >= 1.0) {
    const cursorX = clamp(cursorDeltaX, -45, 45) * 0.45;
    const cursorY = clamp(cursorDeltaY, -45, 45) * 0.45 * inversion;
    const candidateMagnitude = Math.sqrt(cursorX * cursorX + cursorY * cursorY);
    if (candidateMagnitude > bestMagnitude) {
      mouseX = cursorX;
      mouseY = cursorY;
      bestMagnitude = candidateMagnitude;
    }
  }

  // Keep pathological spikes from throwing the camera through a half-turn in
  // one frame after alt-tab or focus changes.
  mouseX = clamp(mouseX, -80, 80);
  mouseY = clamp(mouseY, -80, 80);
  let mouseMagnitude = Math.sqrt(mouseX * mouseX + mouseY * mouseY);
  if (mouseMagnitude < 0.20) {
    mouseX = 0;
    mouseY = 0;
    mouseMagnitude = 0;
  }

  // Update the bias only while there is strong evidence that the mouse is
  // actually idle. Never chase the baseline during a real gesture.
  if (!mouseMirrorsStick && looksLikeIdleDiagonal &&
      rawVariation <= 0.22 && cursorMagnitude < 1.0 && mouseMagnitude === 0) {
    const calibrating = now <= mouseBaselineCalibrateUntil;
    const alpha = calibrating ? 0.30 : 0.055;
    mouseMovementBaselineX = lerp(baselineX, rawMouseX, alpha);
    mouseMovementBaselineY = lerp(baselineY, rawMouseY, alpha);
  }

  return {
    mouseX,
    mouseY,
    stickX,
    stickY,
    mouseMagnitude,
    stickMagnitude,
    rawMouseX,
    rawMouseY,
    mouseBaselineX: finiteNumber(mouseMovementBaselineX, 0),
    mouseBaselineY: finiteNumber(mouseMovementBaselineY, 0),
    rawVariation,
    cursorDeltaX,
    cursorDeltaY,
    cursorMagnitude,
    relativeCursorAvailable,
    relativeCursorActive,
    mouseInputReliable,
    syntheticDiagonalSuppressed: syntheticDiagonalWithoutCursor,
    idleDiagonalSignature,
    horizontalMagnitude: Math.max(Math.abs(mouseX), Math.abs(stickX)),
    magnitude: Math.max(mouseMagnitude, stickMagnitude),
    source: stickMagnitude > mouseMagnitude ? "stick" : "mouse",
  };
}

function readMouseCursorPosition() {
  try {
    if (typeof Mouse !== "undefined" && typeof Mouse.GetCursorPos === "function") {
      const cursor = Mouse.GetCursorPos();
      if (cursor && Number.isFinite(cursor.x) && Number.isFinite(cursor.y)) {
        return { x: cursor.x, y: cursor.y };
      }
    }
  } catch (_) {}
  const cursor = safeNative("GET_CURSOR_POS");
  if (cursor && typeof cursor === "object" &&
      Number.isFinite(cursor.x) && Number.isFinite(cursor.y)) {
    return { x: cursor.x, y: cursor.y };
  }
  return null;
}

function setMouseCursorPosition(x, y) {
  const ix = Math.round(x);
  const iy = Math.round(y);
  try {
    if (typeof Mouse !== "undefined" && typeof Mouse.SetCursorPos === "function") {
      const result = Mouse.SetCursorPos(ix, iy);
      if (result !== false) return true;
    }
  } catch (_) {}
  const result = safeNative("SET_CURSOR_POS", ix, iy);
  return result !== null && result !== false;
}

function readUnifiedCameraMovement() {
  try {
    if (typeof Mouse !== "undefined" && typeof Mouse.GetMovement === "function") {
      const movement = Mouse.GetMovement();
      if (movement) {
        return {
          deltaX: finiteNumber(movement.deltaX ?? movement.x, 0),
          deltaY: finiteNumber(movement.deltaY ?? movement.y, 0),
        };
      }
    }
  } catch (_) {}
  return null;
}

function isMouseUsingVerticalInversion() {
  try {
    return typeof Mouse !== "undefined" &&
      typeof Mouse.IsUsingVerticalInversion === "function" &&
      !!Mouse.IsUsingVerticalInversion();
  } catch (_) {
    return false;
  }
}

function isAimHeld() {
  return isKeyPressed(RIGHT_MOUSE_BUTTON) ||
    isButtonPressed(PAD_ID, AIM_BUTTON);
}

function cameraTransitionIsActive() {
  // HAS_CUTSCENE_LOADED only means the resource finished loading; it is not a
  // reliable "cutscene is currently playing" signal. Player.IsControlOn is
  // used by the main ownership guard instead, while fades remain explicit.
  const fading = safeNative("GET_FADING_STATUS");
  return fading !== null && Number(fading) > 0;
}

function isPlayerControlAvailable() {
  try {
    if (player && typeof player.isControlOn === "function") {
      return !!player.isControlOn();
    }
  } catch (_) {}
  const nativeValue = safeNative("IS_PLAYER_CONTROL_ON", player);
  return nativeValue === null ? true : !!nativeValue;
}

function loadConfig() {
  if (typeof IniFile === "undefined" || typeof IniFile.ReadInt !== "function") {
    log("Adaptive Third-Person Camera: IniFiles64 unavailable; using defaults.");
    return false;
  }

  try {
    const version = readConfigInt("meta", "config_version", 0);
    if (version !== CONFIG_VERSION) {
      log("Adaptive Third-Person Camera: unsupported or missing INI version; previous configuration retained.");
      return false;
    }

    // Build the complete candidate off to the side. A malformed field or
    // unexpected API failure can therefore never leave a half-loaded config.
    const nextConfig = { ...DEFAULTS };
    nextConfig.enabled = readConfigBool("mod", "enabled", nextConfig.enabled);
    nextConfig.manualOverride = readConfigBool("camera", "manual_override", nextConfig.manualOverride);
    nextConfig.manualOverrideThreshold = clamp(readConfigInt("camera", "manual_override_threshold", nextConfig.manualOverrideThreshold), 4, 120);
    nextConfig.manualFreeMs = clamp(readConfigInt("camera", "manual_free_ms", nextConfig.manualFreeMs), 450, 3000);
    nextConfig.manualBlendMs = clamp(readConfigInt("camera", "manual_blend_ms", nextConfig.manualBlendMs), 250, 3000);
    nextConfig.recenterLowSpeedMs = clamp(readConfigInt("camera", "recenter_low_speed_ms", nextConfig.recenterLowSpeedMs), 500, 4000);
    nextConfig.recenterNormalSpeedMs = clamp(readConfigInt("camera", "recenter_normal_speed_ms", nextConfig.recenterNormalSpeedMs), 500, 4000);
    nextConfig.recenterHighSpeedMs = clamp(readConfigInt("camera", "recenter_high_speed_ms", nextConfig.recenterHighSpeedMs), 300, 3000);
    nextConfig.anchorTransitionMs = clamp(readConfigInt("camera", "anchor_transition_ms", nextConfig.anchorTransitionMs), 150, 800);
    nextConfig.collisionEnabled = readConfigBool("camera", "collision_enabled", nextConfig.collisionEnabled);
    nextConfig.collisionProbeRadius = clamp(readConfigInt("camera", "collision_probe_radius_cm", nextConfig.collisionProbeRadius * 100), 8, 45) / 100;
    nextConfig.collisionUpdateMs = clamp(readConfigInt("camera", "collision_update_ms", nextConfig.collisionUpdateMs), 20, 80);
    nextConfig.collisionSafetyMargin = clamp(readConfigInt("camera", "collision_safety_margin_cm", nextConfig.collisionSafetyMargin * 100), 8, 40) / 100;
    nextConfig.collisionEmergencyDistance = clamp(readConfigInt("camera", "collision_emergency_distance_cm", nextConfig.collisionEmergencyDistance * 100), 100, 220) / 100;
    nextConfig.positionFrequencyHz = clamp(readConfigInt("camera", "position_frequency_hz_x100", nextConfig.positionFrequencyHz * 100), 250, 900) / 100;
    nextConfig.positionDampingRatio = clamp(readConfigInt("camera", "position_damping_ratio_percent", nextConfig.positionDampingRatio * 100), 70, 180) / 100;
    nextConfig.verticalTracking = clamp(readConfigInt("camera", "vertical_tracking_percent", nextConfig.verticalTracking * 100), 20, 100) / 100;
    nextConfig.airborneVerticalTracking = clamp(readConfigInt("camera", "airborne_vertical_tracking_percent", nextConfig.airborneVerticalTracking * 100), 15, 100) / 100;
    nextConfig.targetFrequencyHz = clamp(readConfigInt("camera", "target_frequency_hz_x100", nextConfig.targetFrequencyHz * 100), 250, 1000) / 100;
    nextConfig.targetDampingRatio = clamp(readConfigInt("camera", "target_damping_ratio_percent", nextConfig.targetDampingRatio * 100), 70, 180) / 100;
    nextConfig.collisionFrequencyHz = clamp(readConfigInt("camera", "collision_frequency_hz_x100", nextConfig.collisionFrequencyHz * 100), 350, 1200) / 100;
    nextConfig.collisionDampingRatio = clamp(readConfigInt("camera", "collision_damping_ratio_percent", nextConfig.collisionDampingRatio * 100), 70, 180) / 100;
    nextConfig.manualAutoRecenter = readConfigBool("vehicle", "manual_auto_recenter", nextConfig.manualAutoRecenter);
    nextConfig.cornerPreviewSeconds = clamp(readConfigInt("vehicle", "corner_preview_ms", nextConfig.cornerPreviewSeconds * 1000), 0, 900) / 1000;
    nextConfig.cornerPreviewMaxDegrees = clamp(readConfigInt("vehicle", "corner_preview_max_deg", nextConfig.cornerPreviewMaxDegrees), 0, 35);
    nextConfig.cornerTargetMaxOffset = clamp(readConfigInt("vehicle", "corner_target_max_offset_cm", nextConfig.cornerTargetMaxOffset * 100), 0, 250) / 100;
    nextConfig.nativeVehicleCamera = readConfigBool("vehicle", "native_camera_backend", nextConfig.nativeVehicleCamera);
    nextConfig.nativeVehicleDynamicFov = readConfigBool("vehicle", "native_dynamic_fov", nextConfig.nativeVehicleDynamicFov);
    nextConfig.nativeVehicleContextualTweak = readConfigBool("vehicle", "native_contextual_tweak", nextConfig.nativeVehicleContextualTweak);
    nextConfig.driftVelocityInfluence = clamp(readConfigInt("vehicle", "drift_velocity_influence_percent", nextConfig.driftVelocityInfluence * 100), 0, 100) / 100;
    nextConfig.driftMinSpeedKmh = clamp(readConfigInt("vehicle", "drift_min_speed_kmh", nextConfig.driftMinSpeedKmh), 5, 40);
    nextConfig.driftDistance = clamp(readConfigInt("vehicle", "drift_distance_cm", nextConfig.driftDistance * 100), 0, 400) / 100;
    nextConfig.vehicleYawDelayMs = clamp(readConfigInt("vehicle", "yaw_follow_delay_ms", nextConfig.vehicleYawDelayMs), 40, 300);
    nextConfig.vehicleYawFollowStrength = clamp(readConfigInt("vehicle", "yaw_follow_strength_percent", nextConfig.vehicleYawFollowStrength * 100), 20, 100) / 100;
    nextConfig.maxSteeringYawBiasDegrees = clamp(readConfigInt("vehicle", "max_steering_yaw_bias_deg", nextConfig.maxSteeringYawBiasDegrees), 0, 15);
    nextConfig.vehicleManualCornerPreviewWeight = clamp(readConfigInt("vehicle", "manual_corner_preview_percent", nextConfig.vehicleManualCornerPreviewWeight * 100), 0, 80) / 100;
    nextConfig.velocityDirectionThresholdMps = clamp(readConfigInt("vehicle", "velocity_direction_threshold_cms", nextConfig.velocityDirectionThresholdMps * 100), 5, 100) / 100;
    nextConfig.reverseMinSpeedKmh = clamp(readConfigInt("vehicle", "reverse_min_speed_kmh", nextConfig.reverseMinSpeedKmh), 1, 20);
    nextConfig.reverseEnterHoldMs = clamp(readConfigInt("vehicle", "reverse_enter_hold_ms", nextConfig.reverseEnterHoldMs), 120, 800);
    nextConfig.reverseExitHoldMs = clamp(readConfigInt("vehicle", "reverse_exit_hold_ms", nextConfig.reverseExitHoldMs), 180, 1000);
    nextConfig.reverseExitSpeedKmh = clamp(readConfigInt("vehicle", "reverse_exit_speed_kmh", nextConfig.reverseExitSpeedKmh), 1, 20);
    nextConfig.accelerationFilterAlpha = clamp(readConfigInt("vehicle", "acceleration_filter_percent", nextConfig.accelerationFilterAlpha * 100), 4, 40) / 100;
    nextConfig.airborneEnterVerticalSpeed = clamp(readConfigInt("vehicle", "airborne_enter_vertical_kmh", nextConfig.airborneEnterVerticalSpeed * 3.6), 5, 25) / 3.6;
    nextConfig.airborneExitVerticalSpeed = clamp(readConfigInt("vehicle", "airborne_exit_vertical_kmh", nextConfig.airborneExitVerticalSpeed * 3.6), 2, 15) / 3.6;
    nextConfig.landingMinAirborneMs = clamp(readConfigInt("vehicle", "landing_min_airborne_ms", nextConfig.landingMinAirborneMs), 100, 800);
    nextConfig.landingDurationMs = clamp(readConfigInt("vehicle", "landing_duration_ms", nextConfig.landingDurationMs), 80, 500);
    nextConfig.vehicleDriftFovBoost = clamp(readConfigInt("vehicle", "drift_fov_boost_deg_x10", nextConfig.vehicleDriftFovBoost * 10), 0, 60) / 10;
    nextConfig.vehicleAccelerationFovBoost = clamp(readConfigInt("vehicle", "acceleration_fov_boost_deg_x10", nextConfig.vehicleAccelerationFovBoost * 10), 0, 60) / 10;
    nextConfig.vehicleBrakingFovReduction = clamp(readConfigInt("vehicle", "braking_fov_reduction_deg_x10", nextConfig.vehicleBrakingFovReduction * 10), 0, 40) / 10;
    readDistanceAndHeightConfig(nextConfig);
    nextConfig.reloadHotkeyEnabled = readConfigBool("input", "reload_hotkey_enabled", nextConfig.reloadHotkeyEnabled);
    nextConfig.toggleHotkeyEnabled = readConfigBool("input", "toggle_hotkey_enabled", nextConfig.toggleHotkeyEnabled);
    validateConfig(nextConfig);
    config = nextConfig;
    log("Adaptive Third-Person Camera configuration loaded.");
    return true;
  } catch (_) {
    log("Adaptive Third-Person Camera: configuration load failed; previous configuration retained.");
    return false;
  }
}

function readDistanceAndHeightConfig(target) {
  target.carSlowDistance = readDistanceCm("car", "slow_distance_cm", target.carSlowDistance);
  target.carSlowHeight = readHeightCm("car", "slow_height_cm", target.carSlowHeight);
  target.carSlowFov = readFov("car", "slow_fov_deg", target.carSlowFov);
  target.carNormalDistance = readDistanceCm("car", "normal_distance_cm", target.carNormalDistance);
  target.carNormalHeight = readHeightCm("car", "normal_height_cm", target.carNormalHeight);
  target.carNormalFov = readFov("car", "normal_fov_deg", target.carNormalFov);
  target.carFastDistance = readDistanceCm("car", "fast_distance_cm", target.carFastDistance);
  target.carFastHeight = readHeightCm("car", "fast_height_cm", target.carFastHeight);
  target.carFastFov = readFov("car", "fast_fov_deg", target.carFastFov);
  target.motorbikeDistance = readDistanceCm("motorbike", "distance_cm", target.motorbikeDistance);
  target.motorbikeHeight = readHeightCm("motorbike", "height_cm", target.motorbikeHeight);
  target.motorbikeFov = readFov("motorbike", "fov_deg", target.motorbikeFov);
  target.bicycleDistance = readDistanceCm("bicycle", "distance_cm", target.bicycleDistance);
  target.bicycleHeight = readHeightCm("bicycle", "height_cm", target.bicycleHeight);
  target.bicycleFov = readFov("bicycle", "fov_deg", target.bicycleFov);
  target.boatDistance = readDistanceCm("boat", "distance_cm", target.boatDistance);
  target.boatHeight = readHeightCm("boat", "height_cm", target.boatHeight);
  target.boatFov = readFov("boat", "fov_deg", target.boatFov);
  target.helicopterDistance = readDistanceCm("helicopter", "distance_cm", target.helicopterDistance);
  target.helicopterHeight = readHeightCm("helicopter", "height_cm", target.helicopterHeight);
  target.helicopterFov = readFov("helicopter", "fov_deg", target.helicopterFov);
  target.aircraftDistance = readDistanceCm("aircraft", "distance_cm", target.aircraftDistance);
  target.aircraftHeight = readHeightCm("aircraft", "height_cm", target.aircraftHeight);
  target.aircraftFov = readFov("aircraft", "fov_deg", target.aircraftFov);
}

function readDistanceCm(section, key, fallbackMeters) {
  return sanitizeDistanceCm(
    readConfigInt(section, key, fallbackMeters * 100),
    fallbackMeters * 100
  ) / 100;
}

function readHeightCm(section, key, fallbackMeters) {
  return sanitizeHeightCm(
    readConfigInt(section, key, fallbackMeters * 100),
    fallbackMeters * 100
  ) / 100;
}

function readFov(section, key, fallback) {
  return sanitizeFov(readConfigInt(section, key, fallback), fallback);
}

function sanitizeDistanceCm(value, fallback) {
  return clampFinite(value, fallback, 100, 1500);
}

function sanitizeHeightCm(value, fallback) {
  return clampFinite(value, fallback, -200, 800);
}

function sanitizeFov(value, fallback) {
  return clampFinite(value, fallback, 40, 90);
}

function clampFinite(value, fallback, minimum, maximum) {
  const numeric = Number(value);
  return clamp(Number.isFinite(numeric) ? numeric : fallback, minimum, maximum);
}

function validateConfig(value) {
  value.reverseExitSpeedKmh = Math.max(
    value.reverseMinSpeedKmh,
    value.reverseExitSpeedKmh
  );
  value.airborneExitVerticalSpeed = Math.min(
    value.airborneEnterVerticalSpeed,
    value.airborneExitVerticalSpeed
  );
}

function readConfigInt(section, key, fallback) {
  try {
    const value = IniFile.ReadInt(CONFIG_PATH, section, key);
    return Number.isFinite(Number(value)) ? Number(value) : fallback;
  } catch (_) {
    return fallback;
  }
}

function readConfigBool(section, key, fallback) {
  return readConfigInt(section, key, fallback ? 1 : 0) !== 0;
}

function toHandle(value, Constructor) {
  if (value === null || value === undefined || value === false || value === -1 || value === 0) return null;
  if (typeof value === "object") return value;
  try {
    return new Constructor(value);
  } catch (_) {
    return null;
  }
}

function safeNative(name, ...args) {
  try {
    return native(name, ...args);
  } catch (_) {
    return null;
  }
}

function isKeyPressed(keyCode) {
  if (keyboardInputCapability === null) {
    keyboardInputCapability = probeInputCapability();
  }
  if (!keyboardInputCapability) return false;

  try {
    if (typeof Pad !== "undefined" && typeof Pad.IsKeyPressed === "function") {
      return !!Pad.IsKeyPressed(keyCode);
    }
  } catch (_) {}
  return !!safeNative("IS_KEY_PRESSED", keyCode);
}

function probeInputCapability() {
  try {
    if (typeof Pad !== "undefined" && typeof Pad.IsKeyPressed === "function") {
      Pad.IsKeyPressed(VK_CAMERA_DISTANCE);
      return true;
    }
  } catch (_) {}

  try {
    native("IS_KEY_PRESSED", VK_CAMERA_DISTANCE);
    return true;
  } catch (_) {
    return false;
  }
}

function isVehicleCameraControlActive() {
  let keyDown = false;
  let keyPressed = false;
  try {
    if (typeof Pad !== "undefined") {
      if (typeof Pad.IsKeyDown === "function") keyDown = !!Pad.IsKeyDown(KEY_V);
      if (typeof Pad.IsKeyPressed === "function") keyPressed = !!Pad.IsKeyPressed(KEY_V);
    }
  } catch (_) {}
  return keyDown ||
    keyPressed ||
    !!safeNative("IS_KEY_DOWN", KEY_V) ||
    !!safeNative("IS_KEY_PRESSED", KEY_V) ||
    isButtonPressed(PAD_ID, CONTROLLER_VIEW_BUTTON);
}

function isButtonPressed(padId, buttonId) {
  try {
    if (typeof Pad !== "undefined" && typeof Pad.IsButtonPressed === "function") {
      return !!Pad.IsButtonPressed(padId, buttonId);
    }
  } catch (_) {}
  return !!safeNative("IS_BUTTON_PRESSED", padId, buttonId);
}

function headingVector(degrees) {
  const angle = (degrees * Math.PI) / 180;
  return { x: Math.sin(angle), y: Math.cos(angle), z: 0 };
}

function cross2D(left, right) {
  return left.x * right.y - left.y * right.x;
}

function isVector(value) {
  return !!value && Number.isFinite(Number(value.x)) && Number.isFinite(Number(value.y)) && Number.isFinite(Number(value.z));
}

function finiteNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function addVector(left, right) {
  return { x: left.x + right.x, y: left.y + right.y, z: left.z + right.z };
}

function subtractVector(left, right) {
  return { x: left.x - right.x, y: left.y - right.y, z: left.z - right.z };
}

function scaleVector(vector, scale) {
  return { x: vector.x * scale, y: vector.y * scale, z: vector.z * scale };
}

function lerpVector(from, to, amount) {
  return addVector(from, scaleVector(subtractVector(to, from), amount));
}

function normalizeVector(vector) {
  const length = vectorLength(vector);
  if (length <= 0.0001) return { x: 0, y: 1, z: 0 };
  return scaleVector(vector, 1 / length);
}

function getGameTimerMs() {
  try {
    if (typeof Clock !== "undefined" && typeof Clock.GetGameTimer === "function") {
      const value = Number(Clock.GetGameTimer());
      if (Number.isFinite(value)) return value;
    }
  } catch (_) {}
  const rawNativeValue = safeNative("GET_GAME_TIMER");
  if (rawNativeValue !== null && rawNativeValue !== undefined) {
    const nativeValue = Number(rawNativeValue);
    if (Number.isFinite(nativeValue)) return nativeValue;
  }
  return Date.now();
}

function getGroundZAt(position) {
  if (!isVector(position)) return null;
  try {
    if (typeof World !== "undefined" && typeof World.GetGroundZFor3DCoord === "function") {
      const value = Number(World.GetGroundZFor3DCoord(position.x, position.y, position.z));
      if (Number.isFinite(value)) return value;
    }
  } catch (_) {}
  const raw = safeNative("GET_GROUND_Z_FOR_3D_COORD", position.x, position.y, position.z);
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (raw && typeof raw === "object") {
    const value = Number(raw.groundZ ?? raw.z);
    if (Number.isFinite(value)) return value;
  }
  return null;
}

function enforceCameraGroundSafety(position, anchor) {
  let safe = enforceMinimumCameraHeight(position, anchor);
  const minimumRaised = safe.z > position.z + 0.001;
  // The actor-relative minimum already protects normal camera poses. Ground Z
  // is an emergency sanity check only, so avoid an extra native query on every
  // ordinary frame.
  if (!minimumRaised && safe.z >= anchor.z + 0.75) return safe;

  const groundZ = getGroundZAt(safe);
  // Ground queries can return a bridge/upper surface in stacked geometry. Only
  // use values reasonably close to the current actor's vertical band.
  if (Number.isFinite(groundZ) &&
      groundZ >= anchor.z - 15 && groundZ <= anchor.z + 4) {
    safe = {
      ...safe,
      z: Math.max(safe.z, groundZ + CAMERA_GROUND_CLEARANCE),
    };
  }
  return safe;
}

function isSafeCameraPose(anchor, position, target) {
  if (!isVector(anchor) || !isVector(position) || !isVector(target)) return false;
  const cameraDistance = distanceBetween(anchor, position);
  const targetDistance = distanceBetween(anchor, target);
  const viewDistance = distanceBetween(position, target);
  return cameraDistance >= 0.5 && cameraDistance <= 30 &&
    targetDistance <= 25 && viewDistance >= 0.25 && viewDistance <= 40 &&
    position.z >= anchor.z + MIN_CAMERA_RELATIVE_Z && position.z <= anchor.z + 25 &&
    target.z >= anchor.z - 3 && target.z <= anchor.z + 25;
}

function enforceMinimumCameraHeight(position, anchor) {
  if (!isVector(position) || !isVector(anchor)) return position;
  return {
    x: position.x,
    y: position.y,
    z: Math.max(position.z, anchor.z + MIN_CAMERA_RELATIVE_Z),
  };
}

function formatVector(vector) {
  if (!isVector(vector)) return "invalid";
  return "(" + vector.x.toFixed(2) + "," + vector.y.toFixed(2) + "," + vector.z.toFixed(2) + ")";
}

function rotateHorizontal(vector, radians) {
  const cosine = Math.cos(radians);
  const sine = Math.sin(radians);
  return normalizeVector({
    x: vector.x * cosine - vector.y * sine,
    y: vector.x * sine + vector.y * cosine,
    z: 0,
  });
}

function normalizeAngleRadians(angle) {
  let result = angle;
  while (result > Math.PI) result -= Math.PI * 2;
  while (result < -Math.PI) result += Math.PI * 2;
  return result;
}

function smoothAngle(current, target, amount) {
  return current + normalizeAngleRadians(target - current) * clamp(amount, 0, 1);
}

function smoothHorizontalDirection(current, target, amount) {
  const currentYaw = Math.atan2(current.y, current.x);
  const targetYaw = Math.atan2(target.y, target.x);
  const yaw = smoothAngle(currentYaw, targetYaw, amount);
  return { x: Math.cos(yaw), y: Math.sin(yaw), z: 0 };
}

function cameraYawFromViewDirection(viewDirection) {
  return Math.atan2(-viewDirection.y, -viewDirection.x);
}

function vectorLength(vector) {
  return Math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z);
}

function dotProduct(left, right) {
  return left.x * right.x + left.y * right.y + left.z * right.z;
}

function distanceBetween(left, right) {
  return vectorLength(subtractVector(left, right));
}

function lerp(from, to, amount) {
  return from + (to - from) * amount;
}

function frameRateIndependentAlpha(alphaAt60Fps, dt) {
  const alpha = clamp(alphaAt60Fps, 0, 1);
  if (alpha >= 1) return 1;
  return 1 - Math.pow(1 - alpha, clamp(dt, 0.001, 0.25) * 60);
}

function interpolateProfiles(left, right, amount) {
  const result = { ...left };
  for (const key of [
    "distance",
    "height",
    "targetHeight",
    "fov",
    "lookAhead",
    "velocityLead",
    "accelerationLead",
    "shoulderOffset",
    "cornerPreviewLead",
    "cornerLateralLead",
    "steeringLookAhead",
    "steering",
  ]) {
    result[key] = lerp(left[key], right[key], amount);
  }
  result.verticalTracking = left.verticalTracking === null || right.verticalTracking === null
    ? (amount < 0.5 ? left.verticalTracking : right.verticalTracking)
    : lerp(left.verticalTracking, right.verticalTracking, amount);
  result.baseName = right.baseName || right.stateName || left.baseName || left.stateName;
  result.modifiers = { ...(right.modifiers || {}) };
  result.stateName = right.stateName || result.baseName;
  return result;
}

function composeProfileState(baseName, modifiers = {}) {
  const labels = [baseName || "Camera"];
  if ((modifiers.drift || 0) > 0.05) labels.push("Drift");
  if ((modifiers.reverse || 0) > 0.5) labels.push("Reverse");
  if ((modifiers.airborne || 0) > 0.5) labels.push("Airborne");
  if ((modifiers.landing || 0) > 0.5) labels.push("Landing");
  if ((modifiers.manual || 0) > 0.05) labels.push("Manual");
  return labels.join("+");
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function smoothstep(minimum, maximum, value) {
  if (maximum <= minimum) return value >= maximum ? 1 : 0;
  const amount = clamp((value - minimum) / (maximum - minimum), 0, 1);
  return amount * amount * (3 - 2 * amount);
}
