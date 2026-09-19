/// <reference path="./.config/sa.d.ts" />

// Adaptive Third-Person Camera for GTA San Andreas: The Definitive Edition.
// Runtime: CLEO Redux x64 + IniFiles64.
//
// The script only uses public SA:DE script natives. It moves a scriptable
// camera behind the player and restores the regular game camera whenever the
// player gives a strong manual camera input. It never changes movement,
// vehicle handling, input bindings or mission state.

if (HOST !== "sa_unreal") {
  exit("Adaptive Third-Person Camera supports only GTA San Andreas: The Definitive Edition.");
}

const PLAYER_ID = 0;
const CONFIG_PATH = "./AdaptiveThirdPersonCamera.ini";
const CONFIG_VERSION = 1;
const MOD_BUILD_ID = "ATC-DE-20260919-13";
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
const IDLE_ACTIVATION_MS = 60000;
const VEHICLE_MANUAL_MOUSE_DEADZONE = 1.5;
const VEHICLE_MANUAL_STICK_DEADZONE = 12;
const VEHICLE_MANUAL_CONFIRM_FRAMES = 1;
const VEHICLE_MIN_ORBIT_PITCH = -0.20;
const VEHICLE_MAX_ORBIT_PITCH = 0.65;
const CameraControl = {
  AUTO: 0,
  MANUAL: 1,
};
const COLLISION_EMERGENCY_GRACE_MS = 220;
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
  manualBlendMs: 650,
  recenterLowSpeedMs: 1800,
  recenterNormalSpeedMs: 1100,
  recenterHighSpeedMs: 650,
  anchorTransitionMs: 320,
  collisionEnabled: true,
  collisionProbeRadius: 0.22,
  collisionUpdateMs: 33,
  reloadHotkeyEnabled: true,
  toggleHotkeyEnabled: true,
  verticalTracking: 0.58,
  airborneVerticalTracking: 0.23,
  positionFrequencyHz: 4.5,
  positionDampingRatio: 1.0,
  targetFrequencyHz: 5.2,
  targetDampingRatio: 1.0,
  collisionFrequencyHz: 7.0,
  collisionDampingRatio: 1.0,
  driftVelocityInfluence: 0.42,
  driftMinSpeedKmh: 22,
  driftDistance: 0.65,
  vehicleYawDelayMs: 120,
  vehicleYawFollowStrength: 0.70,
  maxSteeringYawBiasDegrees: 7,
  reverseMinSpeedKmh: 3,
  reverseEnterHoldMs: 280,
  reverseExitHoldMs: 420,
  reverseExitSpeedKmh: 4,
  accelerationFilterAlpha: 0.12,
  airborneEnterVerticalSpeed: 9 / 3.6,
  airborneExitVerticalSpeed: 4 / 3.6,
  landingMinAirborneMs: 180,
  landingDurationMs: 220,
  collisionSafetyMargin: 0.20,
  collisionEmergencyDistance: 1.45,
  velocityDirectionThresholdMps: 0.35,
  // Distances are stored in metres here and as centimetres in the INI file.
  idleDistance: 3.65,
  idleHeight: 1.65,
  idleFov: 72,
  walkDistance: 3.8,
  walkHeight: 1.62,
  walkFov: 73,
  jogDistance: 4.15,
  jogHeight: 1.58,
  jogFov: 75,
  sprintDistance: 4.55,
  sprintHeight: 1.52,
  sprintFov: 77,
  aimFov: 59,
  carSlowDistance: 5.25,
  carSlowHeight: 1.85,
  carSlowFov: 74,
  carNormalDistance: 5.65,
  carNormalHeight: 1.95,
  carNormalFov: 76,
  carFastDistance: 6.1,
  carFastHeight: 2.05,
  carFastFov: 79,
  motorbikeDistance: 5.6,
  motorbikeHeight: 1.9,
  motorbikeFov: 75,
  bicycleDistance: 4.8,
  bicycleHeight: 1.7,
  bicycleFov: 72,
  boatDistance: 8.6,
  boatHeight: 2.7,
  boatFov: 76,
  helicopterDistance: 12.5,
  helicopterHeight: 4.0,
  helicopterFov: 78,
  aircraftDistance: 15.0,
  aircraftHeight: 5.0,
  aircraftFov: 79,
};

const player = new Player(PLAYER_ID);
let config = { ...DEFAULTS };
let cameraApplied = false;
let springPosition = null;
let springPositionVelocity = { x: 0, y: 0, z: 0 };
let springTarget = null;
let springTargetVelocity = { x: 0, y: 0, z: 0 };
let lastActorSample = null;
let lastFrameAt = Date.now();
let manualFreeUntil = 0;
let manualRecenterUntil = 0;
let manualCameraDirection = null;
let manualControlActive = false;
let manualPitchOffset = 0;
let vehicleManualInputFrames = 0;
let vehicleCameraControl = CameraControl.AUTO;
let vehicleOrbitYaw = null;
let vehicleOrbitPitch = 0;
let stationarySince = 0;
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
let fovSpringValue = null;
let fovSpringVelocity = 0;
let lastToggleDown = false;
let lastReloadDown = false;
let lastCameraDistanceDown = false;
let lastVehicleCameraDown = false;
let keyboardInputCapability = null;
let cameraPoseDiagnosticLogged = false;
let lastLayoutDiagnosticRevision = -1;
let lastVehicleGeometryDiagnosticKey = null;
const cameraLayoutController = {
  layout: 1,
  observedNativeMode: null,
  source: "default",
  transition: null,
  revision: 0,

  requestNext(source) {
    const now = Date.now();
    const current = this.getParameters(now);
    this.layout = (this.layout + 1) % VEHICLE_CAMERA_LAYOUT_NAMES.length;
    this.source = source;
    this.transition = { from: current, startedAt: now };
    this.revision += 1;
    log(
      "Adaptive Third-Person Camera vehicle layout=" +
        VEHICLE_CAMERA_LAYOUT_NAMES[this.layout] +
        " (" + source + "; script profile only)"
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
let aimBlend = 0;
let aimCameraActive = false;
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
    "; F5 cycles vehicle layouts; F9 toggles the camera; F11 reloads the INI."
);

while (true) {
  wait(0);

  const now = Date.now();
  const rawDt = Math.max(0, (now - lastFrameAt) / 1000);
  const dt = clamp(rawDt, 0.001, 0.05);
  lastFrameAt = now;
  if (rawDt > 0.08) {
    springPositionVelocity = scaleVector(springPositionVelocity, 0.10);
    springTargetVelocity = scaleVector(springTargetVelocity, 0.10);
    fovSpringVelocity *= 0.10;
  }
  handleHotkeys();

  if (!config.enabled || !player.isPlaying() || cameraTransitionIsActive()) {
    cameraLayoutController.resetInputState();
    releaseCamera();
    lastActorSample = null;
    continue;
  }

  const actor = player.getChar();
  const sample = readActorSample(actor, now);
  if (!sample) {
    cameraLayoutController.resetInputState();
    releaseCamera();
    lastActorSample = null;
    continue;
  }

  handleVehicleCameraLayout(sample);
  updateAimCameraState(sample, dt);

  if (!sample.vehicle && (sample.aiming || aimBlend > 0 || aimCameraActive)) {
    applyNativeAimCamera();
    lastActorSample = sample;
    continue;
  }

  if (cameraAnchorChanged(lastActorSample, sample)) {
    const previousAnchor = lastActorSample.vehicle ? lastActorSample.kind : "onFoot";
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

  const manualInput = readManualCameraInput();
  const vehicleCameraIntent = !!sample.vehicle &&
    (Math.abs(manualInput.mouseX) >= VEHICLE_MANUAL_MOUSE_DEADZONE ||
      Math.abs(manualInput.mouseY) >= VEHICLE_MANUAL_MOUSE_DEADZONE ||
      Math.abs(manualInput.stickX) >= VEHICLE_MANUAL_STICK_DEADZONE ||
      Math.abs(manualInput.stickY) >= VEHICLE_MANUAL_STICK_DEADZONE);
  vehicleManualInputFrames = vehicleCameraIntent
    ? Math.min(VEHICLE_MANUAL_CONFIRM_FRAMES, vehicleManualInputFrames + 1)
    : 0;
  const manualInputActive = sample.vehicle
    ? vehicleManualInputFrames >= VEHICLE_MANUAL_CONFIRM_FRAMES
    : config.manualOverride && manualInput.magnitude >= config.manualOverrideThreshold;
  if (manualInputActive) {
    if (!sample.vehicle) {
      // Manual camera movement is activity too. Restart the full idle delay so
      // sway cannot resume immediately after the user releases the mouse.
      stationarySince = now;
      sample.idleElapsedMs = 0;
      sample.idleActive = false;
    }
    beginManualOverride(sample, manualInput, now);
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
  const fallbackPressed = cameraDown && !lastVehicleCameraDown;
  if (distanceHotkeyPressed) cameraLayoutController.requestNext("F5");
  else if (fallbackPressed) cameraLayoutController.requestNext("V/controller fallback");
  lastVehicleCameraDown = cameraDown;
  lastCameraDistanceDown = distanceHotkeyDown;
}

function updateAimCameraState(sample, dt) {
  const aimingOnFoot = !sample.vehicle && sample.aiming;
  const durationSeconds = (aimingOnFoot ? 180 : 230) / 1000;
  aimBlend = clamp(
    aimBlend + (aimingOnFoot ? 1 : -1) * dt / durationSeconds,
    0,
    1
  );

  if (aimingOnFoot && !aimCameraActive) {
    releaseScriptCameraForAim();
    aimCameraActive = true;
  } else if (!aimingOnFoot && aimCameraActive && aimBlend <= 0) {
    applyRequestedFov(getOnFootFov(sample), 230, Date.now());
    aimCameraActive = false;
  }
}

function releaseScriptCameraForAim() {
  if (!cameraApplied) return;
  resetScriptCamera();
  restoreScriptCamera();
  cameraApplied = false;
  springPosition = null;
  springTarget = null;
  springPositionVelocity = { x: 0, y: 0, z: 0 };
  springTargetVelocity = { x: 0, y: 0, z: 0 };
  collisionCache = null;
  fovProbe = null;
}

function applyNativeAimCamera() {
  applyRequestedFov(config.aimFov, 180, Date.now());
}

function getOnFootFov(sample) {
  const speed = sample?.speedMps || 0;
  if (speed < 0.65) return config.idleFov;
  if (speed < 2.0) return config.jogFov;
  return config.sprintFov;
}

function applyRequestedFov(targetFov, durationMs, now) {
  if (fovCapability === false) return;

  if (fovProbe) {
    if (now - fovProbe.startedAt < 220) return;
    const measured = getCameraFov();
    fovCapability = Number.isFinite(measured) &&
      Math.abs(measured - fovProbe.baseline) >= 1;
    log(
      "Adaptive Third-Person Camera: FOV lerp capability=" +
        (fovCapability ? "available" : "unavailable")
    );
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
    const probeTarget = baseline > 50 ? baseline - 5 : baseline + 5;
    if (!setLerpFov(baseline, probeTarget, 150)) {
      fovCapability = false;
      log("Adaptive Third-Person Camera: FOV lerp binding unavailable; FOV disabled for this session.");
      return;
    }
    fovProbe = { baseline, target: probeTarget, startedAt: now };
    return;
  }

  if (lastAppliedFovTarget !== null && Math.abs(lastAppliedFovTarget - targetFov) < 0.35) {
    return;
  }
  const currentFov = getCameraFov();
  if (!Number.isFinite(currentFov)) return;
  if (setLerpFov(currentFov, targetFov, durationMs)) {
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
  return previousAnchor !== currentAnchor;
}

function beginAnchorTransition(sample, now) {
  vehicleManualInputFrames = 0;
  vehicleCameraControl = CameraControl.AUTO;
  vehicleOrbitYaw = null;
  vehicleOrbitPitch = 0;
  lastVehicleGeometryDiagnosticKey = null;
  // A manual orbit belongs to its previous anchor. Carrying vehicle free-look
  // into the on-foot countdown leaves OnFootStand in Manual and can look like
  // an IDLE rotation even though the idle timer has not elapsed.
  manualCameraDirection = null;
  manualControlActive = false;
  manualPitchOffset = 0;
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

function beginManualOverride(sample, input, now) {
  if (sample.vehicle) {
    if (vehicleCameraControl === CameraControl.AUTO || vehicleOrbitYaw === null) {
      initializeVehicleOrbit(sample);
    }
    vehicleCameraControl = CameraControl.MANUAL;
    manualControlActive = true;
  } else if (!manualControlActive) {
    const camera = getCameraState();
    if (camera?.forward) {
      const horizontal = { x: camera.forward.x, y: camera.forward.y, z: 0 };
      if (vectorLength(horizontal) > 0.1) {
        manualCameraDirection = normalizeVector(horizontal);
      }
    }
    manualCameraDirection = manualCameraDirection || sample.forward;
    manualPitchOffset = 0;
    manualControlActive = true;
    collisionCache = null;
  }

  const yawDelta = input.stickMagnitude > input.mouseMagnitude
    ? input.stickX * 0.055
    : input.mouseX * 0.004;
  const pitchDelta = input.stickMagnitude > input.mouseMagnitude
    ? input.stickY * 0.040
    : input.mouseY * 0.0025;
  if (sample.vehicle) {
    // Vehicle manual mode owns the orbit. The vehicle heading must never
    // overwrite this yaw while the user is looking around.
    vehicleOrbitYaw = normalizeAngleRadians(vehicleOrbitYaw + yawDelta);
    vehicleOrbitPitch = clamp(
      vehicleOrbitPitch - pitchDelta,
      VEHICLE_MIN_ORBIT_PITCH,
      VEHICLE_MAX_ORBIT_PITCH
    );
  } else {
    manualCameraDirection = rotateHorizontal(manualCameraDirection, yawDelta);
    manualPitchOffset = clamp(manualPitchOffset - pitchDelta, -0.45, 0.45);
  }
  if (sample.vehicle) {
    // Vehicle free-look never expires. Auto-follow must not take control back
    // between two mouse samples, during a drift, or after a profile change.
    // The orbit is reset only when the vehicle anchor is released/changed.
    manualFreeUntil = Number.POSITIVE_INFINITY;
    manualRecenterUntil = Number.POSITIVE_INFINITY;
  } else {
    const freeLookHold = config.manualFreeMs;
    manualFreeUntil = now + freeLookHold;
    manualRecenterUntil = manualFreeUntil + getRecenterDelay(sample);
  }
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

  const autoDirection = sample.reverseActive
    ? sample.stableVelocityDirection || sample.forward
    : sample.forward;
  vehicleOrbitYaw = cameraYawFromViewDirection(autoDirection);
  vehicleOrbitPitch = 0;
}

function getAutoFollowWeight(sample, now) {
  if (sample.vehicle && vehicleOrbitYaw !== null &&
      vehicleCameraControl === CameraControl.MANUAL) {
    // Persistent vehicle free-look: never force the camera back behind the
    // car while the player is driving.
    return 0;
  }

  if (now <= manualFreeUntil) return 0;
  if (!manualCameraDirection) return 1;
  if (now <= manualRecenterUntil) return 0;
  const weight = smoothstep(
    0,
    Math.max(1, sample.vehicle ? VEHICLE_MANUAL_BLEND_MS : config.manualBlendMs),
    now - manualRecenterUntil
  );
  if (weight >= 1) {
    manualCameraDirection = null;
    manualControlActive = false;
    manualPitchOffset = 0;
  }
  return weight;
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

  if (!wasAirborne) {
    if (Math.abs(verticalSpeed) >= enterThreshold) {
      if (!previous || !airborneSince) airborneSince = now;
      return "airborne";
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
    verticalSpeed > -exitThreshold;
  if (landingSignal) landingUntil = now + config.landingDurationMs;
  if (now < landingUntil) return "landing";

  if (Math.abs(verticalSpeed) >= exitThreshold) return "airborne";
  airborneSince = 0;
  return "grounded";
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
  return Math.abs((Math.atan2(cross, dot) * 180) / Math.PI);
}

function driftVelocityWeight(slipAngleDegrees, speedKmh = Infinity) {
  if (config.driftVelocityInfluence <= 0 || speedKmh < config.driftMinSpeedKmh) return 0;
  return smoothstep(5, 30, slipAngleDegrees) * config.driftVelocityInfluence;
}

function updateFovSpring(target, dt) {
  if (fovSpringValue === null) fovSpringValue = desiredFovFallback();
  const result = dampedScalarStep(
    fovSpringValue,
    target,
    fovSpringVelocity,
    2.4,
    1.0,
    dt
  );
  fovSpringValue = result.value;
  fovSpringVelocity = result.velocity;
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
  // IS_CHAR_SITTING_IN_ANY_CAR can be false for part of the enter animation
  // and on some CLEO builds even while driving. Keep the camera on the car
  // whenever the ped is not on foot and a vehicle interaction is reported;
  // IS_CHAR_ON_FOOT remains the hard exit boundary.
  const vehicleAnchorAvailable = !vehicleState.isOnFoot &&
    (vehicleState.isSitting || vehicleState.interactingWithVehicle);
  const vehicle = vehicleAnchorAvailable
    ? getPlayerVehicle(actor, vehicleState)
    : null;
  if (vehicleAnchorAvailable && !vehicle) return null;

  const entity = vehicle || actor;
  const position = getCoordinates(entity, !!vehicle);
  if (!position) return null;

  const kind = classifyVehicle(actor, vehicle);
  const heading = getEntityHeading(entity, !!vehicle);
  // Do not reconstruct a vehicle's world forward vector from the heading.
  // GTA's heading convention is easy to mirror accidentally; the vehicle
  // wrapper/native already exposes the actual world-space forward axes.
  const forward = getEntityForward(entity, !!vehicle, heading);
  const previous = lastActorSample &&
      lastActorSample.kind === kind &&
      !!lastActorSample.vehicle === !!vehicle
    ? lastActorSample
    : null;
  const elapsed = previous ? clamp((now - previous.timestamp) / 1000, 0.001, 0.25) : 0;
  const positionVelocity = previous && elapsed > 0
    ? scaleVector(subtractVector(position, previous.position), 1 / elapsed)
    : { x: 0, y: 0, z: 0 };
  const nativeVelocity = readNativeVelocity(entity, !!vehicle);
  const velocity = nativeVelocity || positionVelocity;
  // The vehicle speed-vector binding is useful for magnitude, but its axis
  // space is not guaranteed by every CLEO host. Position delta is always in
  // world coordinates and is therefore the only vehicle direction source.
  const worldHorizontalVelocity = previous
    ? { x: positionVelocity.x, y: positionVelocity.y, z: 0 }
    : null;
  const horizontalVelocity = worldHorizontalVelocity || { x: velocity.x, y: velocity.y, z: 0 };
  const vectorSpeedMps = vectorLength(horizontalVelocity);
  const reportedSpeed = getEntitySpeed(entity, !!vehicle);
  const speedMps = vectorSpeedMps > 0.08
    ? vectorSpeedMps
    : clamp(reportedSpeed, 0, 90);
  const measuredVelocityDirection = worldHorizontalVelocity &&
    vectorLength(worldHorizontalVelocity) > config.velocityDirectionThresholdMps
    ? normalizeVector(horizontalVelocity)
    : null;
  const stableVelocityDirection =
    measuredVelocityDirection ||
    previous?.stableVelocityDirection ||
    forward;
  const signedSpeedMps = dotProduct(horizontalVelocity, forward);
  const rawAccelerationMps2 = previous && elapsed > 0
    ? clamp((speedMps - previous.speedMps) / elapsed, -20, 20)
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
  const uprightValue = getVehicleUprightValue(vehicle);
  const airState = deriveAirState(
    vehicle,
    kind,
    velocity.z,
    previous,
    now
  );

  const sample = {
    actor,
    vehicle,
    kind,
    sittingInVehicle,
    inAnyVehicle,
    interactionState,
    position,
    heading,
    forward,
    velocity,
    velocityDirection: measuredVelocityDirection,
    stableVelocityDirection,
    velocitySource: nativeVelocity ? "native" : "positionDelta",
    speedMps,
    speedKmh: speedMps * 3.6,
    signedSpeedMps,
    rawAccelerationMps2,
    filteredAccelerationMps2,
    slipAngleDegrees: calculateSlipAngle(forward, measuredVelocityDirection, vectorSpeedMps),
    orientationInstability: clamp((1 - uprightValue) / 0.45, 0, 1),
    steering: steeringAmount({
      vehicle,
      kind,
      heading,
      speedKmh: speedMps * 3.6,
      timestamp: now,
    }),
    uprightValue,
    airState,
    timestamp: now,
    aiming: isAimHeld(),
  };

  sample.reverseActive = updateReverseState(sample, now);
  sample.idleElapsedMs = updateStationaryState(sample, now);
  sample.idleActive = sample.idleElapsedMs >= IDLE_ACTIVATION_MS;
  return sample;
}

function updateStationaryState(sample, now) {
  const positionChanged = lastActorSample &&
    distanceBetween(lastActorSample.position, sample.position) > 0.08;
  const stationary = !sample.vehicle &&
    sample.speedMps < 0.20 &&
    !positionChanged;
  if (!stationary) {
    stationarySince = 0;
    return 0;
  }
  if (!stationarySince) stationarySince = now;
  return Math.max(0, now - stationarySince);
}

function applyCameraDirector(sample, dt, now, autoFollowWeight) {
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

  let geometry = buildCameraGeometry(sample, profile, autoFollowWeight, transition);
  const manualFreeLook = !!sample.vehicle && manualControlActive && autoFollowWeight < 1;
  let collision = resolveCameraCollision(
    geometry.target,
    geometry.desiredPosition,
    now,
    manualFreeLook,
    true,
    sample.vehicle
  );

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
    position: enforceMinimumCameraHeight(collision.position, sample.position),
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

  initializeSpringIfNeeded(collision.position, geometry.target);

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
  const positionFrequency =
    (collision.collided ? config.collisionFrequencyHz : config.positionFrequencyHz) *
    transitionSpringBoost;
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

  if (
    collision.collided &&
    !isCameraPathClear(geometry.target, springPosition, sample.vehicle)
  ) {
    springPosition = collision.position;
    springPositionVelocity = { x: 0, y: 0, z: 0 };
  }

  const targetResult = springStep(
    springTarget,
    geometry.target,
    springTargetVelocity,
    config.targetFrequencyHz * transitionSpringBoost,
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
          " orbitYawDeg=" + (vehicleOrbitYaw === null ? "none" :
            ((vehicleOrbitYaw * 180) / Math.PI).toFixed(2)) +
          " orbitPitchDeg=" + ((vehicleOrbitPitch * 180) / Math.PI).toFixed(2)
      );
    }
  }

  if (!setScriptCameraPose(springPosition, springTarget)) return;

  updateFovSpring(profile.fov, dt);
  applyRequestedFov(fovSpringValue, 180, now);

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
        " fovSpring=" +
        fovSpringValue.toFixed(1) +
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
  let right = { x: direction.y, y: -direction.x, z: 0 };
  const base = { x: anchorPosition.x, y: anchorPosition.y, z: anchorPosition.z };
  let useVehicleOrbit = sample.vehicle &&
    vehicleCameraControl !== CameraControl.AUTO &&
    vehicleOrbitYaw !== null;
  if (useVehicleOrbit && autoFollowWeight > 0) {
    vehicleOrbitYaw = smoothAngle(
      vehicleOrbitYaw,
      cameraYawFromViewDirection(direction),
      autoFollowWeight
    );
    vehicleOrbitPitch = lerp(vehicleOrbitPitch, 0, autoFollowWeight);
    if (autoFollowWeight >= 1) {
      vehicleCameraControl = CameraControl.AUTO;
      vehicleOrbitYaw = null;
      vehicleOrbitPitch = 0;
      manualControlActive = false;
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
  const speedFactor = clamp(sample.speedKmh / 120, 0, 1);
  const travelDirection = sample.stableVelocityDirection || direction;
  const accelerationFactor = clamp(sample.filteredAccelerationMps2 / 8, -1, 1);
  const autoTargetLead = addVector(
    scaleVector(direction, profileValue.lookAhead),
    addVector(
      scaleVector(travelDirection, profileValue.velocityLead * speedFactor),
      addVector(
        scaleVector(
          right,
          profileValue.steeringLookAhead * profileValue.steering * speedFactor
        ),
        scaleVector(anchorForward, profileValue.accelerationLead * accelerationFactor)
      )
    )
  );
  const targetLead = scaleVector(
    autoTargetLead,
    useVehicleOrbit ? autoFollowWeight : 1
  );
  const shoulder = profileValue.shoulderOffset;
  const manualPitchLead = !sample.vehicle && manualControlActive && autoFollowWeight < 1
    ? { x: 0, y: 0, z: manualPitchOffset * profileValue.distance }
    : { x: 0, y: 0, z: 0 };
  const target = addVector(
    { x: base.x, y: base.y, z: base.z + profileValue.targetHeight },
    addVector(targetLead, manualPitchLead)
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
  return { direction, target, desiredPosition };
}

function buildProfile(sample) {
  if (!sample.vehicle) return buildOnFootProfile(sample);

  const speed = clamp(sample.speedKmh, 0, 220);
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
  }

  if (sample.vehicle) {
    result = applyVehicleCameraLayout(result, sample.timestamp);
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

function buildOnFootProfile(sample) {
  const speed = sample.speedMps;
  let movementProfile;
  if (speed < 0.65) {
    movementProfile = sample.idleActive
      ? profile("OnFootIdle", config.idleDistance, config.idleHeight, config.idleFov, 0, 0, 0, 0, 1.25)
      : profile("OnFootStand", config.idleDistance, config.idleHeight, config.idleFov, 0, 0, 0, 0, 1.25);
  } else if (speed < 2.0) {
    const amount = clamp((speed - 0.65) / 1.35, 0, 1);
    movementProfile = interpolateProfiles(
      profile("OnFootWalk", config.walkDistance, config.walkHeight, config.walkFov, 0.35, 0.10, 0, 0, 1.24),
      profile("OnFootJog", config.jogDistance, config.jogHeight, config.jogFov, 0.60, 0.10, 0, 0, 1.22),
      amount
    );
    movementProfile.baseName = amount > 0.55 ? "OnFootJog" : "OnFootWalk";
    movementProfile.stateName = movementProfile.baseName;
  } else {
    const amount = clamp((speed - 2.0) / 2.0, 0, 1);
    movementProfile = interpolateProfiles(
      profile("OnFootJog", config.jogDistance, config.jogHeight, config.jogFov, 0.60, 0.10, 0, 0, 1.22),
      profile("OnFootSprint", config.sprintDistance, config.sprintHeight, config.sprintFov, 0.95, 0.06, 0, 0, 1.18),
      amount
    );
    movementProfile.baseName = amount > 0.35 ? "OnFootSprint" : "OnFootJog";
    movementProfile.stateName = movementProfile.baseName;
  }

  return movementProfile;
}

function buildCarProfile(speedKmh, accelerationMps2) {
  const speed = clamp(speedKmh, 0, 200);
  const slow = profile("CarSlow", config.carSlowDistance, config.carSlowHeight, config.carSlowFov, 0.70, 0, 0, 0, 0.75);
  const normal = profile("CarNormal", config.carNormalDistance, config.carNormalHeight, config.carNormalFov, 1.25, 0, 0, 0, 0.78);
  const fast = profile("CarFast", config.carFastDistance, config.carFastHeight, config.carFastFov, 1.80, 0, 0, 0, 0.82);
  const result = speed < 75
    ? interpolateProfiles(slow, normal, smoothstep(25, 75, speed))
    : interpolateProfiles(normal, fast, smoothstep(75, 140, speed));
  result.baseName = "Car";
  result.stateName = "Car";
  result.velocityLead = 0.45 + clamp(speed / 140, 0, 1) * 0.75;
  result.accelerationLead = 0.35;
  if (accelerationMps2 > 2) {
    const boost = clamp((accelerationMps2 - 2) / 8, 0, 1);
    result.distance += 0.2 + boost * 0.3;
    result.fov += boost * 2;
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
    verticalTracking: stateName.startsWith("OnFoot") ? 0.86 : config.verticalTracking,
    shoulderOffset,
    steeringLookAhead,
    steering,
  };
}

function getCameraDirection(sample, profileValue, autoFollowWeight, forwardOverride = sample.forward) {
  let autoDirection = forwardOverride;
  if (sample.stableVelocityDirection && sample.speedMps > config.velocityDirectionThresholdMps) {
    if (!sample.vehicle) {
      autoDirection = sample.stableVelocityDirection;
    } else if (sample.reverseActive) {
      // In reverse the camera sits in front of the car and follows its actual
      // travel direction, rather than snapping through the vehicle heading.
      autoDirection = sample.stableVelocityDirection;
    } else {
      // In forward vehicle AUTO mode the camera must remain behind the car's
      // actual forward axis. Slip/velocity affects the target lead below, but
      // must not move the camera to the side during a turn or drift.
      autoDirection = forwardOverride;
    }
  }

  if (sample.vehicle && !sample.reverseActive) {
    if (!vehicleFollowDirection) {
      vehicleFollowDirection = autoDirection;
    } else {
      const elapsed = lastActorSample
        ? clamp((sample.timestamp - lastActorSample.timestamp) / 1000, 0.001, 0.05)
        : 1 / 60;
      const followTimeConstant = config.vehicleYawDelayMs /
        Math.max(0.1, config.vehicleYawFollowStrength) /
        1000;
      const followAlpha = 1 - Math.exp(-elapsed / followTimeConstant);
      vehicleFollowDirection = normalizeVector(
        lerpVector(vehicleFollowDirection, autoDirection, followAlpha)
      );
    }
    autoDirection = rotateHorizontal(
      vehicleFollowDirection,
      (sample.steering * config.maxSteeringYawBiasDegrees * Math.PI) / 180
    );
  } else if (!sample.vehicle || sample.reverseActive) {
    vehicleFollowDirection = null;
  }

  if (!sample.vehicle && manualCameraDirection && autoFollowWeight < 1) {
    return normalizeVector(
      lerpVector(manualCameraDirection, autoDirection, autoFollowWeight)
    );
  }
  return normalizeVector(autoDirection);
}

function driftAmount(sample) {
  return driftVelocityWeight(sample.slipAngleDegrees, sample.speedKmh) /
    Math.max(0.001, config.driftVelocityInfluence);
}

function steeringAmount(sample) {
  if (!sample.vehicle || !lastActorSample || lastActorSample.kind !== sample.kind) return 0;
  const elapsed = clamp((sample.timestamp - lastActorSample.timestamp) / 1000, 0.001, 0.05);
  const delta = normalizeHeadingDelta(sample.heading - lastActorSample.heading);
  const speedFactor = clamp(sample.speedKmh / 75, 0, 1);
  return clamp((delta / elapsed / 110) * speedFactor, -1, 1);
}

function normalizeHeadingDelta(delta) {
  let result = delta;
  while (result > 180) result -= 360;
  while (result < -180) result += 360;
  return result;
}

function resolveCameraCollision(
  target,
  desiredPosition,
  now,
  forceRefresh = false,
  allowEmergency = true,
  ownVehicle = null
) {
  if (!config.collisionEnabled) {
    return { position: desiredPosition, collided: false, clearanceScore: 7 };
  }

  if (
    !forceRefresh &&
    collisionCache &&
    now - collisionCache.timestamp < config.collisionUpdateMs &&
    distanceBetween(collisionCache.target, target) < 0.45 &&
    distanceBetween(collisionCache.desiredPosition, desiredPosition) < 0.45
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

function initializeSpringIfNeeded(desiredPosition, desiredTarget) {
  if (cameraApplied) return;
  // Never seed the spring from the current game camera. It may still contain
  // an invalid native/top-down pose left by an older build and can place the
  // scripted camera below the map before the spring converges.
  springPosition = desiredPosition;
  springTarget = desiredTarget;
  springPositionVelocity = { x: 0, y: 0, z: 0 };
  springTargetVelocity = { x: 0, y: 0, z: 0 };
  fovSpringValue = finiteNumber(safeNative("GET_CAMERA_FOV"), desiredFovFallback());
  fovSpringVelocity = 0;
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

function releaseCamera() {
  const hadCameraControl = cameraApplied || aimCameraActive || fovProbe;
  anchorTransition = null;
  manualCameraDirection = null;
  manualControlActive = false;
  manualPitchOffset = 0;
  vehicleManualInputFrames = 0;
  vehicleCameraControl = CameraControl.AUTO;
  vehicleOrbitYaw = null;
  vehicleOrbitPitch = 0;
  manualFreeUntil = 0;
  manualRecenterUntil = 0;
  collisionCache = null;
  collisionEmergencySince = 0;
  fovSpringValue = null;
  fovSpringVelocity = 0;
  fovProbe = null;
  vehicleFollowDirection = null;
  stationarySince = 0;
  if (hadCameraControl) {
    resetScriptCamera();
    restoreScriptCamera();
  }
  cameraApplied = false;
  cameraPoseDiagnosticLogged = false;
  lastLayoutDiagnosticRevision = -1;
  lastVehicleGeometryDiagnosticKey = null;
  springPosition = null;
  springTarget = null;
  springPositionVelocity = { x: 0, y: 0, z: 0 };
  springTargetVelocity = { x: 0, y: 0, z: 0 };
  lastStateName = null;
  aimBlend = 0;
  aimCameraActive = false;
  lastAppliedFovTarget = null;
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
    // The broad vehicle-use natives can stay true during the door animation.
    // The previous logical state decides whether this is an enter or exit;
    // it is never inferred from the current frame alone.
    nextState = interactionState === "driving" ? "exiting" : "entering";
  } else if (!vehicleState.isOnFoot && inAnyVehicle) {
    // If the seated native is unavailable or temporarily false, the
    // on-foot/native interaction pair is the only reliable fallback. Do not
    // misclassify a still-seated player as exiting before IS_CHAR_ON_FOOT
    // becomes true.
    nextState = interactionState === "driving" ? "driving" : "entering";
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
      if (vehicle) return vehicle;
    }
  } catch (_) {}
  return toHandle(safeNative("STORE_CAR_CHAR_IS_IN_NO_SAVE", actor), Car);
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

function readManualCameraInput() {
  const unifiedMovement = readUnifiedCameraMovement();
  if (unifiedMovement) {
    const inversion = isMouseUsingVerticalInversion() ? -1 : 1;
    const mouseX = unifiedMovement.deltaX;
    const mouseY = unifiedMovement.deltaY * inversion;
    return {
      mouseX,
      mouseY,
      stickX: 0,
      stickY: 0,
      mouseMagnitude: Math.sqrt(mouseX * mouseX + mouseY * mouseY),
      stickMagnitude: 0,
      horizontalMagnitude: Math.abs(mouseX),
      magnitude: Math.sqrt(mouseX * mouseX + mouseY * mouseY),
    };
  }

  const usingJoypad = isPcUsingJoypad();
  const mouse = usingJoypad ? {} : safeNative("GET_PC_MOUSE_MOVEMENT") || {};
  const sticks = usingJoypad
    ? safeNative("GET_POSITION_OF_ANALOGUE_STICKS", PAD_ID) || {}
    : {};
  const mouseX = finiteNumber(mouse.deltaX, 0);
  const inversion = isMouseUsingVerticalInversion() ? -1 : 1;
  const mouseY = finiteNumber(mouse.deltaY, 0) * inversion;
  const stickX = finiteNumber(sticks.rightStickX, 0);
  const stickY = finiteNumber(sticks.rightStickY, 0);
  return {
    mouseX,
    mouseY,
    stickX,
    stickY,
    mouseMagnitude: Math.sqrt(mouseX * mouseX + mouseY * mouseY),
    stickMagnitude: Math.sqrt(stickX * stickX + stickY * stickY),
    horizontalMagnitude: Math.max(Math.abs(mouseX), Math.abs(stickX)),
    magnitude: Math.max(
      Math.sqrt(mouseX * mouseX + mouseY * mouseY),
      Math.sqrt(stickX * stickX + stickY * stickY)
    ),
  };
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

function isPcUsingJoypad() {
  try {
    if (typeof Game !== "undefined" && typeof Game.IsPcUsingJoypad === "function") {
      return !!Game.IsPcUsingJoypad();
    }
  } catch (_) {}
  return !!safeNative("IS_PC_USING_JOYPAD");
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
  if (safeNative("HAS_CUTSCENE_LOADED") === true) return true;
  const fading = safeNative("GET_FADING_STATUS");
  return fading !== null && Number(fading) > 0;
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
    nextConfig.driftVelocityInfluence = clamp(readConfigInt("vehicle", "drift_velocity_influence_percent", nextConfig.driftVelocityInfluence * 100), 0, 100) / 100;
    nextConfig.driftMinSpeedKmh = clamp(readConfigInt("vehicle", "drift_min_speed_kmh", nextConfig.driftMinSpeedKmh), 5, 40);
    nextConfig.driftDistance = clamp(readConfigInt("vehicle", "drift_distance_cm", nextConfig.driftDistance * 100), 0, 400) / 100;
    nextConfig.vehicleYawDelayMs = clamp(readConfigInt("vehicle", "yaw_follow_delay_ms", nextConfig.vehicleYawDelayMs), 40, 300);
    nextConfig.vehicleYawFollowStrength = clamp(readConfigInt("vehicle", "yaw_follow_strength_percent", nextConfig.vehicleYawFollowStrength * 100), 20, 100) / 100;
    nextConfig.maxSteeringYawBiasDegrees = clamp(readConfigInt("vehicle", "max_steering_yaw_bias_deg", nextConfig.maxSteeringYawBiasDegrees), 0, 15);
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
  target.idleDistance = readDistanceCm("on_foot", "idle_distance_cm", target.idleDistance);
  target.idleHeight = readHeightCm("on_foot", "idle_height_cm", target.idleHeight);
  target.idleFov = readFov("on_foot", "idle_fov_deg", target.idleFov);
  target.walkDistance = readDistanceCm("on_foot", "walk_distance_cm", target.walkDistance);
  target.walkHeight = readHeightCm("on_foot", "walk_height_cm", target.walkHeight);
  target.walkFov = readFov("on_foot", "walk_fov_deg", target.walkFov);
  target.jogDistance = readDistanceCm("on_foot", "jog_distance_cm", target.jogDistance);
  target.jogHeight = readHeightCm("on_foot", "jog_height_cm", target.jogHeight);
  target.jogFov = readFov("on_foot", "jog_fov_deg", target.jogFov);
  target.sprintDistance = readDistanceCm("on_foot", "sprint_distance_cm", target.sprintDistance);
  target.sprintHeight = readHeightCm("on_foot", "sprint_height_cm", target.sprintHeight);
  target.sprintFov = readFov("on_foot", "sprint_fov_deg", target.sprintFov);
  target.aimFov = readFov("aim", "fov_deg", target.aimFov);
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
  if (value === null || value === undefined || value === false || value === -1) return null;
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
