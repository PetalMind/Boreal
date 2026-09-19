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
const VK_TOGGLE = 120; // F9.
const VK_RELOAD = 122; // F11.
const KEY_V = 0x56;
const RIGHT_MOUSE_BUTTON = 2;
const PAD_ID = 0;
const AIM_BUTTON = 6; // GTA action: Aim (controller LT/L2).
const CONTROLLER_VIEW_BUTTON = 13; // Physical Select/Back fallback.

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
let fovSpringValue = null;
let fovSpringVelocity = 0;
let lastToggleDown = false;
let lastReloadDown = false;
let lastVehicleCameraDown = false;
let lastNativeVehicleCameraMode = null;
let lastVehicleLayoutChangeAt = 0;
let vehicleCameraLayout = 1;
let aimBlend = 0;
let aimCameraActive = false;
let fovCapability = null;
let fovProbe = null;
let lastAppliedFovTarget = null;
let lastStateName = null;
let cameraSessionDisabled = false;

loadConfig();
log("Adaptive Third-Person Camera loaded. F9 toggles the camera; F11 reloads the INI.");

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
    releaseCamera();
    lastActorSample = null;
    continue;
  }

  const actor = player.getChar();
  const sample = readActorSample(actor, now);
  if (!sample) {
    releaseCamera();
    lastActorSample = null;
    continue;
  }

  handleVehicleCameraLayout(sample, now);
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
  if (config.manualOverride && manualInput.magnitude >= config.manualOverrideThreshold) {
    beginManualOverride(sample, manualInput, now);
  }

  if (cameraSessionDisabled) {
    releaseCamera();
    lastActorSample = sample;
    continue;
  }

  const autoFollowWeight = now < manualFreeUntil
    ? 0
    : getAutoFollowWeight(sample, now);
  applyCameraDirector(sample, dt, now, autoFollowWeight);
  lastActorSample = sample;
}

function handleHotkeys() {
  if (config.reloadHotkeyEnabled) {
    const reloadDown = isKeyPressed(VK_RELOAD);
    if (reloadDown && !lastReloadDown) {
      loadConfig();
      cameraSessionDisabled = false;
      releaseCamera();
      log("Adaptive Third-Person Camera configuration reloaded.");
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

function handleVehicleCameraLayout(sample, now) {
  if (!sample.vehicle) {
    lastNativeVehicleCameraMode = null;
    lastVehicleCameraDown = false;
    return;
  }

  const nativeMode = getPlayerInCarCameraMode();
  const nativeModeChanged = Number.isFinite(nativeMode) &&
    Number.isFinite(lastNativeVehicleCameraMode) &&
    nativeMode !== lastNativeVehicleCameraMode;
  if (Number.isFinite(nativeMode)) lastNativeVehicleCameraMode = nativeMode;

  // The native mode is the semantic Change Camera signal and therefore also
  // respects controller bindings. V remains a keyboard-only fallback for
  // runtimes where a fixed script camera prevents the native mode changing.
  const cameraDown = isVehicleCameraControlActive();
  const fallbackPressed = cameraDown && !lastVehicleCameraDown;
  const nativeChangeIsNew = nativeModeChanged && now - lastVehicleLayoutChangeAt > 350;
  if (nativeChangeIsNew || fallbackPressed) {
    vehicleCameraLayout = (vehicleCameraLayout + 1) % 3;
    lastVehicleLayoutChangeAt = now;
    const layoutNames = ["Close", "Standard", "Wide"];
    log(
      "Adaptive Third-Person Camera vehicle layout=" +
        layoutNames[vehicleCameraLayout] +
        (nativeChangeIsNew ? " (native camera mode)" : " (V fallback)")
    );
  }
  lastVehicleCameraDown = cameraDown;
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
  safeNative("CAMERA_RESET_NEW_SCRIPTABLES");
  safeNative("RESTORE_CAMERA");
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
  if (speed < 0.65) return config.walkFov;
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
  if (!manualControlActive) {
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
  }

  const yawDelta = input.stickMagnitude > input.mouseMagnitude
    ? input.stickX * 0.055
    : input.mouseX * 0.004;
  const pitchDelta = input.stickMagnitude > input.mouseMagnitude
    ? input.stickY * 0.040
    : input.mouseY * 0.0025;
  manualCameraDirection = rotateHorizontal(manualCameraDirection, yawDelta);
  manualPitchOffset = clamp(manualPitchOffset - pitchDelta, -0.45, 0.45);
  manualFreeUntil = now + config.manualFreeMs;
  manualRecenterUntil = manualFreeUntil + getRecenterDelay(sample);
}

function getAutoFollowWeight(sample, now) {
  if (!manualCameraDirection) return 1;
  if (now <= manualRecenterUntil) return 0;
  const weight = smoothstep(
    0,
    Math.max(1, config.manualBlendMs),
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
  const sittingInVehicle = vehicleState.occupiesVehicle;
  const inAnyVehicle = vehicleState.interactingWithVehicle;
  const vehicle = getPlayerVehicle(actor, vehicleState);
  if (sittingInVehicle && !vehicle) return null;

  const entity = vehicle || actor;
  const position = getCoordinates(entity, !!vehicle);
  if (!position) return null;

  const kind = classifyVehicle(actor, vehicle);
  const heading = vehicle
    ? finiteNumber(safeNative("GET_CAR_HEADING", vehicle), 0)
    : finiteNumber(safeNative("GET_CHAR_HEADING", actor), 0);
  const forward = headingVector(heading);
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
  const horizontalVelocity = { x: velocity.x, y: velocity.y, z: 0 };
  const vectorSpeedMps = vectorLength(horizontalVelocity);
  const reportedSpeed = vehicle
    ? finiteNumber(safeNative("GET_CAR_SPEED", vehicle), 0)
    : finiteNumber(safeNative("GET_CHAR_SPEED", actor), 0);
  const speedMps = vectorSpeedMps > 0.08
    ? vectorSpeedMps
    : clamp(reportedSpeed, 0, 90);
  const measuredVelocityDirection = vectorSpeedMps > config.velocityDirectionThresholdMps
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
  const uprightValue = vehicle
    ? finiteNumber(safeNative("GET_CAR_UPRIGHT_VALUE", vehicle), 1)
    : 1;
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
    interactionState: resolveInteractionState(sittingInVehicle, inAnyVehicle, now),
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
  return sample;
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
  let collision = resolveCameraCollision(
    geometry.target,
    geometry.desiredPosition,
    now,
    false,
    true,
    sample.vehicle
  );

  if (collision.emergency) {
    profile = applyCollisionEmergencyModifier(profile);
    geometry = buildCameraGeometry(sample, profile, autoFollowWeight, transition);
    collision = resolveCameraCollision(
      geometry.target,
      geometry.desiredPosition,
      now,
      true,
      false,
      sample.vehicle
    );
  }

  initializeSpringIfNeeded(collision.position, geometry.target);

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
  const right = { x: direction.y, y: -direction.x, z: 0 };
  const base = { x: anchorPosition.x, y: anchorPosition.y, z: anchorPosition.z };
  const speedFactor = clamp(sample.speedKmh / 120, 0, 1);
  const travelDirection = sample.stableVelocityDirection || direction;
  const accelerationFactor = clamp(sample.filteredAccelerationMps2 / 8, -1, 1);
  const targetLead = addVector(
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
  const shoulder = profileValue.shoulderOffset;
  const manualPitchLead = manualControlActive && autoFollowWeight < 1
    ? { x: 0, y: 0, z: manualPitchOffset * profileValue.distance }
    : { x: 0, y: 0, z: 0 };
  const target = addVector(
    { x: base.x, y: base.y, z: base.z + profileValue.targetHeight },
    addVector(targetLead, manualPitchLead)
  );
  const desiredPosition = addVector(
    { x: base.x, y: base.y, z: base.z + profileValue.height },
    addVector(
      scaleVector(direction, -profileValue.distance),
      scaleVector(right, shoulder)
    )
  );
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
    result = applyVehicleCameraLayout(result);
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

function applyVehicleCameraLayout(profileValue) {
  const layouts = [
    { name: "Close", distance: 0.82, height: -0.15, targetHeight: 0 },
    { name: "Standard", distance: 1.00, height: 0, targetHeight: 0 },
    { name: "Wide", distance: 1.18, height: 0.30, targetHeight: 0 },
  ];
  const layout = layouts[vehicleCameraLayout] || layouts[1];
  const result = {
    ...profileValue,
    modifiers: { ...(profileValue.modifiers || {}), layout: vehicleCameraLayout },
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
    movementProfile = profile("OnFootIdle", config.idleDistance, config.idleHeight, config.idleFov, 0.20, 0.08, 0, 0, 1.25);
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
  const fastEnd = profile("CarFast", 6.45, 2.12, 81, 2.30, 0, 0, 0, 0.85);
  let result = speed < 75
    ? interpolateProfiles(slow, normal, smoothstep(25, 75, speed))
    : interpolateProfiles(normal, fast, smoothstep(75, 140, speed));
  result = interpolateProfiles(result, fastEnd, smoothstep(140, 200, speed));
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
      const velocityInfluence = driftVelocityWeight(sample.slipAngleDegrees, sample.speedKmh);
      autoDirection = normalizeVector(
        addVector(
          scaleVector(forwardOverride, 1 - velocityInfluence),
          scaleVector(sample.stableVelocityDirection, velocityInfluence)
        )
      );
    }
  } else if (!sample.vehicle) {
    const idleDirection = getIdleCameraDirection(sample.position);
    if (idleDirection) autoDirection = idleDirection;
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

  if (manualCameraDirection && autoFollowWeight < 1) {
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

function getIdleCameraDirection(anchor) {
  const camera = getCameraState();
  if (!camera) return null;
  const fromCamera = { x: anchor.x - camera.position.x, y: anchor.y - camera.position.y, z: 0 };
  return vectorLength(fromCamera) > 0.5 ? normalizeVector(fromCamera) : null;
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
  const camera = getCameraState();
  springPosition = camera?.position || desiredPosition;
  springTarget = camera?.pointAt || desiredTarget;
  springPositionVelocity = { x: 0, y: 0, z: 0 };
  springTargetVelocity = { x: 0, y: 0, z: 0 };
  fovSpringValue = finiteNumber(safeNative("GET_CAMERA_FOV"), desiredFovFallback());
  fovSpringVelocity = 0;
  safeNative("CAMERA_RESET_NEW_SCRIPTABLES");
}

function setScriptCameraPose(position, target) {
  try {
    native(
      "SET_FIXED_CAMERA_POSITION",
      position.x,
      position.y,
      position.z,
      0,
      0,
      0
    );
    native("POINT_CAMERA_AT_POINT", target.x, target.y, target.z, 0);
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

function applyCollisionEmergencyModifier(profileValue) {
  const result = {
    ...profileValue,
    modifiers: { ...(profileValue.modifiers || {}), collisionEmergency: 1 },
    distance: Math.min(profileValue.distance, config.collisionEmergencyDistance),
    height: Math.min(profileValue.height, 1.25),
    shoulderOffset: 0,
    lookAhead: 0,
    velocityLead: 0,
    accelerationLead: 0,
    steeringLookAhead: 0,
  };
  result.stateName = composeProfileState(result.baseName, result.modifiers);
  return result;
}

function releaseCamera() {
  anchorTransition = null;
  manualCameraDirection = null;
  manualControlActive = false;
  manualPitchOffset = 0;
  manualFreeUntil = 0;
  manualRecenterUntil = 0;
  collisionCache = null;
  fovSpringValue = null;
  fovSpringVelocity = 0;
  fovProbe = null;
  vehicleFollowDirection = null;
  if (cameraApplied || aimCameraActive || fovProbe) {
    safeNative("CAMERA_RESET_NEW_SCRIPTABLES");
    safeNative("RESTORE_CAMERA");
  }
  cameraApplied = false;
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

function resolveInteractionState(sittingInVehicle, inAnyVehicle, now) {
  let nextState = interactionState;
  if (sittingInVehicle) {
    nextState = "driving";
  } else if (!inAnyVehicle) {
    nextState = "onFoot";
  } else if (interactionState === "driving") {
    // The meaning of this interaction is latched at the first frame in
    // which the ped stops sitting. It cannot turn into "entering" merely
    // because the native remains true for the rest of the door animation.
    nextState = "exiting";
  } else if (interactionState === "onFoot") {
    nextState = "entering";
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
  // it describes the vehicle the ped is using, not strictly a occupied seat.
  // Conversely, IS_CHAR_SITTING_IN_ANY_CAR is unreliable on some CLEO Redux
  // SA:DE builds. IS_CHAR_ON_FOOT is therefore the authoritative exit signal.
  const occupiesVehicle = !onFoot && (sitting || interactingWithVehicle);
  return {
    onFoot,
    sittingNative,
    interactingWithVehicle,
    occupiesVehicle,
  };
}

function getPlayerVehicle(actor, vehicleState = null) {
  // IS_CHAR_IN_ANY_CAR also stays true while the player is opening or
  // closing a door.  That is useful for vehicle scripts, but it is wrong for
  // camera ownership: during the exit animation the camera must stop using
  // the vehicle as its anchor as soon as the ped is no longer seated.
  const state = vehicleState || readPlayerVehicleState(actor);
  if (!state.occupiesVehicle) return null;

  return toHandle(safeNative("STORE_CAR_CHAR_IS_IN_NO_SAVE", actor), Car);
}

function classifyVehicle(actor, vehicle) {
  if (!vehicle) return "onFoot";
  if (safeNative("IS_CHAR_IN_ANY_PLANE", actor)) return "aircraft";
  if (safeNative("IS_CHAR_IN_ANY_HELI", actor)) return "helicopter";
  if (safeNative("IS_CHAR_IN_ANY_BOAT", actor)) return "boat";
  const model = finiteNumber(safeNative("GET_CAR_MODEL", vehicle), -1);
  if (VEHICLE_MODELS.bicycles.has(model)) return "bicycle";
  if (VEHICLE_MODELS.motorcycles.has(model)) return "motorbike";
  return "car";
}

function getCoordinates(entity, vehicle) {
  const value = safeNative(vehicle ? "GET_CAR_COORDINATES" : "GET_CHAR_COORDINATES", entity);
  return isVector(value) ? value : null;
}

function readNativeVelocity(entity, vehicle) {
  try {
    const value = vehicle && typeof Car !== "undefined" && typeof Car.GetSpeedVector === "function"
      ? Car.GetSpeedVector(entity)
      : !vehicle && typeof Char !== "undefined" && typeof Char.GetVelocity === "function"
        ? Char.GetVelocity(entity)
        : null;
    if (isVector(value)) return value;
  } catch (_) {}

  const value = safeNative(
    vehicle ? "GET_CAR_SPEED_VECTOR" : "GET_CHAR_VELOCITY",
    entity
  );
  return isVector(value) ? value : null;
}

function getCameraState() {
  const position = safeNative("GET_ACTIVE_CAMERA_COORDINATES");
  const pointAt = safeNative("GET_ACTIVE_CAMERA_POINT_AT");
  if (!isVector(position) || !isVector(pointAt)) return null;
  const forward = normalizeVector(subtractVector(pointAt, position));
  return vectorLength(forward) > 0.01 ? { position, pointAt, forward } : null;
}

function readManualCameraInput() {
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
    magnitude: Math.max(
      Math.sqrt(mouseX * mouseX + mouseY * mouseY),
      Math.sqrt(stickX * stickX + stickY * stickY)
    ),
  };
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
    return;
  }

  try {
    const version = readConfigInt("meta", "config_version", 0);
    if (version !== CONFIG_VERSION) {
      log("Adaptive Third-Person Camera: unsupported or missing INI version; using defaults.");
      return;
    }
    config.enabled = readConfigBool("mod", "enabled", config.enabled);
    config.manualOverride = readConfigBool("camera", "manual_override", config.manualOverride);
    config.manualOverrideThreshold = clamp(readConfigInt("camera", "manual_override_threshold", config.manualOverrideThreshold), 4, 120);
    config.manualFreeMs = clamp(readConfigInt("camera", "manual_free_ms", config.manualFreeMs), 450, 3000);
    config.manualBlendMs = clamp(readConfigInt("camera", "manual_blend_ms", config.manualBlendMs), 250, 3000);
    config.recenterLowSpeedMs = clamp(readConfigInt("camera", "recenter_low_speed_ms", config.recenterLowSpeedMs), 500, 4000);
    config.recenterNormalSpeedMs = clamp(readConfigInt("camera", "recenter_normal_speed_ms", config.recenterNormalSpeedMs), 500, 4000);
    config.recenterHighSpeedMs = clamp(readConfigInt("camera", "recenter_high_speed_ms", config.recenterHighSpeedMs), 300, 3000);
    config.anchorTransitionMs = clamp(readConfigInt("camera", "anchor_transition_ms", config.anchorTransitionMs), 150, 800);
    config.collisionEnabled = readConfigBool("camera", "collision_enabled", config.collisionEnabled);
    config.collisionProbeRadius = clamp(readConfigInt("camera", "collision_probe_radius_cm", config.collisionProbeRadius * 100), 8, 45) / 100;
    config.collisionUpdateMs = clamp(readConfigInt("camera", "collision_update_ms", config.collisionUpdateMs), 20, 80);
    config.collisionSafetyMargin = clamp(readConfigInt("camera", "collision_safety_margin_cm", config.collisionSafetyMargin * 100), 8, 40) / 100;
    config.collisionEmergencyDistance = clamp(readConfigInt("camera", "collision_emergency_distance_cm", config.collisionEmergencyDistance * 100), 100, 220) / 100;
    config.positionFrequencyHz = clamp(readConfigInt("camera", "position_frequency_hz_x100", config.positionFrequencyHz * 100), 250, 900) / 100;
    config.positionDampingRatio = clamp(readConfigInt("camera", "position_damping_ratio_percent", config.positionDampingRatio * 100), 70, 180) / 100;
    config.verticalTracking = clamp(readConfigInt("camera", "vertical_tracking_percent", config.verticalTracking * 100), 20, 100) / 100;
    config.airborneVerticalTracking = clamp(readConfigInt("camera", "airborne_vertical_tracking_percent", config.airborneVerticalTracking * 100), 15, 100) / 100;
    config.targetFrequencyHz = clamp(readConfigInt("camera", "target_frequency_hz_x100", config.targetFrequencyHz * 100), 250, 1000) / 100;
    config.targetDampingRatio = clamp(readConfigInt("camera", "target_damping_ratio_percent", config.targetDampingRatio * 100), 70, 180) / 100;
    config.collisionFrequencyHz = clamp(readConfigInt("camera", "collision_frequency_hz_x100", config.collisionFrequencyHz * 100), 350, 1200) / 100;
    config.collisionDampingRatio = clamp(readConfigInt("camera", "collision_damping_ratio_percent", config.collisionDampingRatio * 100), 70, 180) / 100;
    config.driftVelocityInfluence = clamp(readConfigInt("vehicle", "drift_velocity_influence_percent", config.driftVelocityInfluence * 100), 0, 100) / 100;
    config.driftMinSpeedKmh = clamp(readConfigInt("vehicle", "drift_min_speed_kmh", config.driftMinSpeedKmh), 5, 40);
    config.driftDistance = clamp(readConfigInt("vehicle", "drift_distance_cm", config.driftDistance * 100), 0, 400) / 100;
    config.vehicleYawDelayMs = clamp(readConfigInt("vehicle", "yaw_follow_delay_ms", config.vehicleYawDelayMs), 40, 300);
    config.vehicleYawFollowStrength = clamp(readConfigInt("vehicle", "yaw_follow_strength_percent", config.vehicleYawFollowStrength * 100), 20, 100) / 100;
    config.maxSteeringYawBiasDegrees = clamp(readConfigInt("vehicle", "max_steering_yaw_bias_deg", config.maxSteeringYawBiasDegrees), 0, 15);
    config.velocityDirectionThresholdMps = clamp(readConfigInt("vehicle", "velocity_direction_threshold_cms", config.velocityDirectionThresholdMps * 100), 5, 100) / 100;
    config.reverseMinSpeedKmh = clamp(readConfigInt("vehicle", "reverse_min_speed_kmh", config.reverseMinSpeedKmh), 1, 20);
    config.reverseEnterHoldMs = clamp(readConfigInt("vehicle", "reverse_enter_hold_ms", config.reverseEnterHoldMs), 120, 800);
    config.reverseExitHoldMs = clamp(readConfigInt("vehicle", "reverse_exit_hold_ms", config.reverseExitHoldMs), 180, 1000);
    config.reverseExitSpeedKmh = clamp(readConfigInt("vehicle", "reverse_exit_speed_kmh", config.reverseExitSpeedKmh), 1, 20);
    config.accelerationFilterAlpha = clamp(readConfigInt("vehicle", "acceleration_filter_percent", config.accelerationFilterAlpha * 100), 4, 40) / 100;
    config.airborneEnterVerticalSpeed = clamp(readConfigInt("vehicle", "airborne_enter_vertical_kmh", config.airborneEnterVerticalSpeed * 3.6), 5, 25) / 3.6;
    config.airborneExitVerticalSpeed = clamp(readConfigInt("vehicle", "airborne_exit_vertical_kmh", config.airborneExitVerticalSpeed * 3.6), 2, 15) / 3.6;
    config.landingMinAirborneMs = clamp(readConfigInt("vehicle", "landing_min_airborne_ms", config.landingMinAirborneMs), 100, 800);
    config.landingDurationMs = clamp(readConfigInt("vehicle", "landing_duration_ms", config.landingDurationMs), 80, 500);
    readDistanceAndHeightConfig();
    config.reloadHotkeyEnabled = readConfigBool("input", "reload_hotkey_enabled", config.reloadHotkeyEnabled);
    config.toggleHotkeyEnabled = readConfigBool("input", "toggle_hotkey_enabled", config.toggleHotkeyEnabled);
    log("Adaptive Third-Person Camera configuration loaded.");
  } catch (_) {
    log("Adaptive Third-Person Camera: configuration load failed; using defaults.");
  }
}

function readDistanceAndHeightConfig() {
  config.idleDistance = readConfigInt("on_foot", "idle_distance_cm", config.idleDistance * 100) / 100;
  config.idleHeight = readConfigInt("on_foot", "idle_height_cm", config.idleHeight * 100) / 100;
  config.idleFov = clamp(readConfigInt("on_foot", "idle_fov_deg", config.idleFov), 40, 90);
  config.walkDistance = readConfigInt("on_foot", "walk_distance_cm", config.walkDistance * 100) / 100;
  config.walkHeight = readConfigInt("on_foot", "walk_height_cm", config.walkHeight * 100) / 100;
  config.walkFov = clamp(readConfigInt("on_foot", "walk_fov_deg", config.walkFov), 40, 90);
  config.jogDistance = readConfigInt("on_foot", "jog_distance_cm", config.jogDistance * 100) / 100;
  config.jogHeight = readConfigInt("on_foot", "jog_height_cm", config.jogHeight * 100) / 100;
  config.jogFov = clamp(readConfigInt("on_foot", "jog_fov_deg", config.jogFov), 40, 90);
  config.sprintDistance = readConfigInt("on_foot", "sprint_distance_cm", config.sprintDistance * 100) / 100;
  config.sprintHeight = readConfigInt("on_foot", "sprint_height_cm", config.sprintHeight * 100) / 100;
  config.sprintFov = clamp(readConfigInt("on_foot", "sprint_fov_deg", config.sprintFov), 40, 90);
  config.aimFov = clamp(readConfigInt("aim", "fov_deg", config.aimFov), 40, 90);
  config.carSlowDistance = Math.max(
    DEFAULTS.carSlowDistance,
    readConfigInt("car", "slow_distance_cm", config.carSlowDistance * 100) / 100
  );
  config.carSlowHeight = readConfigInt("car", "slow_height_cm", config.carSlowHeight * 100) / 100;
  config.carSlowFov = clamp(readConfigInt("car", "slow_fov_deg", config.carSlowFov), 40, 90);
  config.carNormalDistance = Math.max(
    DEFAULTS.carNormalDistance,
    readConfigInt("car", "normal_distance_cm", config.carNormalDistance * 100) / 100
  );
  config.carNormalHeight = readConfigInt("car", "normal_height_cm", config.carNormalHeight * 100) / 100;
  config.carNormalFov = clamp(readConfigInt("car", "normal_fov_deg", config.carNormalFov), 40, 90);
  config.carFastDistance = Math.max(
    DEFAULTS.carFastDistance,
    readConfigInt("car", "fast_distance_cm", config.carFastDistance * 100) / 100
  );
  config.carFastHeight = readConfigInt("car", "fast_height_cm", config.carFastHeight * 100) / 100;
  config.carFastFov = clamp(readConfigInt("car", "fast_fov_deg", config.carFastFov), 40, 90);
  config.motorbikeDistance = readConfigInt("motorbike", "distance_cm", config.motorbikeDistance * 100) / 100;
  config.motorbikeHeight = readConfigInt("motorbike", "height_cm", config.motorbikeHeight * 100) / 100;
  config.motorbikeFov = clamp(readConfigInt("motorbike", "fov_deg", config.motorbikeFov), 40, 90);
  config.bicycleDistance = readConfigInt("bicycle", "distance_cm", config.bicycleDistance * 100) / 100;
  config.bicycleHeight = readConfigInt("bicycle", "height_cm", config.bicycleHeight * 100) / 100;
  config.bicycleFov = clamp(readConfigInt("bicycle", "fov_deg", config.bicycleFov), 40, 90);
  config.boatDistance = readConfigInt("boat", "distance_cm", config.boatDistance * 100) / 100;
  config.boatHeight = readConfigInt("boat", "height_cm", config.boatHeight * 100) / 100;
  config.boatFov = clamp(readConfigInt("boat", "fov_deg", config.boatFov), 40, 90);
  config.helicopterDistance = readConfigInt("helicopter", "distance_cm", config.helicopterDistance * 100) / 100;
  config.helicopterHeight = readConfigInt("helicopter", "height_cm", config.helicopterHeight * 100) / 100;
  config.helicopterFov = clamp(readConfigInt("helicopter", "fov_deg", config.helicopterFov), 40, 90);
  config.aircraftDistance = readConfigInt("aircraft", "distance_cm", config.aircraftDistance * 100) / 100;
  config.aircraftHeight = readConfigInt("aircraft", "height_cm", config.aircraftHeight * 100) / 100;
  config.aircraftFov = clamp(readConfigInt("aircraft", "fov_deg", config.aircraftFov), 40, 90);
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
  try {
    if (typeof Pad !== "undefined" && typeof Pad.IsKeyPressed === "function") {
      return !!Pad.IsKeyPressed(keyCode);
    }
  } catch (_) {}
  return !!safeNative("IS_KEY_PRESSED", keyCode);
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

function rotateHorizontal(vector, radians) {
  const cosine = Math.cos(radians);
  const sine = Math.sin(radians);
  return normalizeVector({
    x: vector.x * cosine - vector.y * sine,
    y: vector.x * sine + vector.y * cosine,
    z: 0,
  });
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
  if ((modifiers.collisionEmergency || 0) > 0.5) labels.push("CollisionEmergency");
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
