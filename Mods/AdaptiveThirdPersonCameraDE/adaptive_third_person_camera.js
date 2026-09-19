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
const RIGHT_MOUSE_BUTTON = 2;
const PAD_ID = 0;
const AIM_BUTTON = 5;

const VEHICLE_MODELS = {
  motorcycles: new Set([448, 461, 462, 463, 468, 471, 521, 522, 523, 581]),
  bicycles: new Set([481, 509, 510]),
};

const DEFAULTS = {
  enabled: true,
  manualOverride: true,
  manualOverrideThreshold: 24,
  manualFreeMs: 1200,
  manualBlendMs: 800,
  recenterLowSpeedMs: 2000,
  recenterNormalSpeedMs: 1300,
  recenterHighSpeedMs: 800,
  anchorTransitionMs: 320,
  collisionEnabled: true,
  collisionProbeRadius: 0.22,
  collisionUpdateMs: 33,
  reloadHotkeyEnabled: true,
  toggleHotkeyEnabled: true,
  positionStiffness: 72,
  positionDamping: 20,
  verticalTracking: 0.72,
  airborneVerticalTracking: 0.28,
  targetStiffness: 88,
  targetDamping: 22,
  collisionStiffness: 190,
  collisionDamping: 28,
  driftVelocityInfluence: 0.60,
  reverseMinSpeedKmh: 3,
  reverseEnterHoldMs: 280,
  reverseExitHoldMs: 420,
  reverseExitSpeedKmh: 4,
  accelerationFilterAlpha: 0.12,
  airborneEnterVerticalSpeed: 1.5,
  airborneExitVerticalSpeed: 3.0,
  landingDurationMs: 220,
  shoulderSwapCooldownMs: 450,
  // Distances are stored in metres here and as centimetres in the INI file.
  walkDistance: 3.5,
  walkHeight: 1.5,
  walkFov: 66,
  jogDistance: 4.0,
  jogHeight: 1.5,
  jogFov: 70,
  sprintDistance: 4.6,
  sprintHeight: 1.4,
  sprintFov: 74,
  aimDistance: 2.7,
  aimHeight: 1.45,
  aimFov: 58,
  carSlowDistance: 6.2,
  carSlowHeight: 2.2,
  carSlowFov: 71,
  carNormalDistance: 7.2,
  carNormalHeight: 2.25,
  carNormalFov: 75,
  carFastDistance: 8.8,
  carFastHeight: 2.4,
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
let anchorTransition = null;
let shoulderSide = 1;
let lastShoulderSwapAt = 0;
let reverseState = false;
let reverseCandidateSince = 0;
let forwardCandidateSince = 0;
let landingUntil = 0;
let collisionCache = null;
let fovSpringValue = null;
let fovSpringVelocity = 0;
let lastToggleDown = false;
let lastReloadDown = false;
let lastStateName = null;
let fovCapabilityLogged = false;

loadConfig();
log("Adaptive Third-Person Camera loaded. F9 toggles the camera; F11 reloads the INI.");

while (true) {
  wait(0);

  const now = Date.now();
  const dt = clamp((now - lastFrameAt) / 1000, 0.008, 0.05);
  lastFrameAt = now;
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

  if (isHardTeleport(lastActorSample, sample)) {
    releaseCamera();
    lastActorSample = sample;
    log("Adaptive Third-Person Camera safety reset after a large anchor displacement.");
    continue;
  }

  const manualInput = readManualCameraInput();
  if (config.manualOverride && manualInput.magnitude >= config.manualOverrideThreshold) {
    beginManualOverride(sample, now);
    lastActorSample = sample;
    continue;
  }

  if (now < manualFreeUntil) {
    releaseCamera();
    lastActorSample = sample;
    continue;
  }

  applyCameraDirector(sample, dt, now, getAutoFollowWeight(sample, now));
  lastActorSample = sample;
}

function handleHotkeys() {
  if (config.reloadHotkeyEnabled) {
    const reloadDown = isKeyPressed(VK_RELOAD);
    if (reloadDown && !lastReloadDown) {
      loadConfig();
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
      log("Adaptive Third-Person Camera: " + (config.enabled ? "enabled" : "disabled"));
    }
    lastToggleDown = toggleDown;
  }
}

function cameraAnchorChanged(previous, current) {
  if (!previous || !current) return false;

  const previousAnchor = previous.vehicle ? previous.kind : "onFoot";
  const currentAnchor = current.vehicle ? current.kind : "onFoot";
  return previousAnchor !== currentAnchor;
}

function beginAnchorTransition(sample, now) {
  const camera = getCameraState();
  const fallbackTarget = addVector(
    sample.position,
    addVector(scaleVector(sample.forward, 1.0), { x: 0, y: 0, z: 1.0 })
  );
  anchorTransition = {
    fromPosition: camera?.position || springPosition || sample.position,
    fromTarget: camera?.pointAt || springTarget || fallbackTarget,
    startedAt: now,
    duration: config.anchorTransitionMs,
  };
  springPositionVelocity = scaleVector(springPositionVelocity, 0.15);
  springTargetVelocity = scaleVector(springTargetVelocity, 0.25);
}

function getAnchorTransitionTargets(position, target, now) {
  if (!anchorTransition) return { position, target };

  const elapsed = now - anchorTransition.startedAt;
  const amount = smoothstep(
    0,
    Math.max(1, anchorTransition.duration),
    elapsed
  );
  const result = {
    position: lerpVector(anchorTransition.fromPosition, position, amount),
    target: lerpVector(anchorTransition.fromTarget, target, amount),
  };
  if (amount >= 1) anchorTransition = null;
  return result;
}

function beginManualOverride(sample, now) {
  const camera = getCameraState();
  if (camera?.forward) {
    const horizontal = { x: camera.forward.x, y: camera.forward.y, z: 0 };
    if (vectorLength(horizontal) > 0.1) {
      manualCameraDirection = normalizeVector(horizontal);
    }
  }
  manualFreeUntil = now + config.manualFreeMs;
  manualRecenterUntil = manualFreeUntil + getRecenterDelay(sample);
  releaseCamera();
}

function getAutoFollowWeight(sample, now) {
  if (!manualCameraDirection) return 1;
  if (now <= manualRecenterUntil) return 0;
  return smoothstep(
    0,
    Math.max(1, config.manualBlendMs),
    now - manualRecenterUntil
  );
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

function isHardTeleport(previous, current) {
  return !!previous &&
    !!current &&
    distanceBetween(previous.position, current.position) > 24;
}

function deriveAirState(vehicle, kind, verticalSpeed, uprightValue, previous, now) {
  if (!vehicle || !["car", "motorbike", "bicycle"].includes(kind)) {
    landingUntil = 0;
    return "grounded";
  }

  const wasAirborne = previous?.airState === "airborne";
  const isLanding = wasAirborne && verticalSpeed < -config.airborneExitVerticalSpeed;
  if (isLanding) landingUntil = now + config.landingDurationMs;
  if (now < landingUntil) return "landing";

  const tilted = uprightValue < 0.55;
  const movingVertically = Math.abs(verticalSpeed) >= config.airborneEnterVerticalSpeed;
  const remainsAirborne = wasAirborne && verticalSpeed > -config.airborneExitVerticalSpeed;
  return tilted || movingVertically || remainsAirborne ? "airborne" : "grounded";
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

function calculateSlipAngle(forward, velocityDirection, signedSpeedMps) {
  if (!velocityDirection || signedSpeedMps <= 0.1) return 0;
  const cross = Math.abs(cross2D(forward, velocityDirection));
  const dot = clamp(dotProduct(forward, velocityDirection), -1, 1);
  return Math.abs((Math.atan2(cross, dot) * 180) / Math.PI);
}

function driftVelocityWeight(slipAngleDegrees) {
  if (config.driftVelocityInfluence <= 0) return 0;
  return smoothstep(5, 30, slipAngleDegrees) * config.driftVelocityInfluence;
}

function updateFovSpring(target, dt) {
  if (fovSpringValue === null) fovSpringValue = desiredFovFallback();
  const stiffness = 28;
  const damping = 10;
  const acceleration = (target - fovSpringValue) * stiffness - fovSpringVelocity * damping;
  fovSpringVelocity += acceleration * dt;
  fovSpringValue += fovSpringVelocity * dt;
}

function desiredFovFallback() {
  return 70;
}

function readActorSample(actor, now) {
  if (!actor || safeNative("IS_CHAR_DEAD", actor)) return null;

  const sittingNative = safeNative("IS_CHAR_SITTING_IN_ANY_CAR", actor);
  const sittingInVehicle = sittingNative === true || sittingNative === 1;
  const inAnyVehicle = readAnyVehicleState(actor);
  const vehicle = getPlayerVehicle(actor, sittingNative);
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
  const elapsed = previous ? clamp((now - previous.timestamp) / 1000, 0.008, 0.05) : 0;
  const velocity = previous && elapsed > 0
    ? scaleVector(subtractVector(position, previous.position), 1 / elapsed)
    : { x: 0, y: 0, z: 0 };
  const horizontalVelocity = { x: velocity.x, y: velocity.y, z: 0 };
  const derivedSpeedMps = vectorLength(horizontalVelocity);
  const reportedSpeed = vehicle
    ? finiteNumber(safeNative("GET_CAR_SPEED", vehicle), 0)
    : finiteNumber(safeNative("GET_CHAR_SPEED", actor), 0);
  const speedMps = previous
    ? derivedSpeedMps > 0.08 ? derivedSpeedMps : clamp(reportedSpeed, 0, 90)
    : 0;
  const velocityDirection = derivedSpeedMps > 0.12
    ? normalizeVector(horizontalVelocity)
    : null;
  const signedSpeedMps = dotProduct(horizontalVelocity, forward);
  const rawAccelerationMps2 = previous && elapsed > 0
    ? clamp((speedMps - previous.speedMps) / elapsed, -20, 20)
    : 0;
  const filteredAccelerationMps2 = previous
    ? lerp(
        previous.filteredAccelerationMps2 || 0,
        rawAccelerationMps2,
        config.accelerationFilterAlpha
      )
    : 0;
  const uprightValue = vehicle
    ? finiteNumber(safeNative("GET_CAR_UPRIGHT_VALUE", vehicle), 1)
    : 1;
  const airState = deriveAirState(
    vehicle,
    kind,
    velocity.z,
    uprightValue,
    previous,
    now
  );

  const sample = {
    actor,
    vehicle,
    kind,
    sittingInVehicle,
    inAnyVehicle,
    interactionState: getVehicleInteractionState(
      sittingInVehicle,
      inAnyVehicle,
      lastActorSample
    ),
    position,
    heading,
    forward,
    velocity,
    velocityDirection,
    speedMps,
    speedKmh: speedMps * 3.6,
    signedSpeedMps,
    rawAccelerationMps2,
    filteredAccelerationMps2,
    slipAngleDegrees: calculateSlipAngle(forward, velocityDirection, signedSpeedMps),
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
  const profile = buildProfile(sample);
  let geometry = buildCameraGeometry(sample, profile, autoFollowWeight);
  let collision = resolveCameraCollision(geometry.target, geometry.desiredPosition, now);

  if (
    sample.aiming &&
    collision.collided &&
    now - lastShoulderSwapAt >= config.shoulderSwapCooldownMs
  ) {
    const originalShoulderSide = shoulderSide;
    const currentClearance = distanceBetween(geometry.target, collision.position);
    shoulderSide *= -1;
    lastShoulderSwapAt = now;
    const alternateGeometry = buildCameraGeometry(sample, profile, autoFollowWeight);
    const alternateCollision = resolveCameraCollision(
      alternateGeometry.target,
      alternateGeometry.desiredPosition,
      now,
      true
    );
    const alternateClearance = distanceBetween(
      alternateGeometry.target,
      alternateCollision.position
    );
    if (
      alternateCollision.collided &&
      alternateClearance <= currentClearance + 0.05
    ) {
      shoulderSide = originalShoulderSide;
    } else {
      geometry = alternateGeometry;
      collision = alternateCollision;
    }
  }

  const transitionTargets = getAnchorTransitionTargets(
    collision.position,
    geometry.target,
    now
  );
  initializeSpringIfNeeded(transitionTargets.position, transitionTargets.target);

  // Hard teleports/cutscene transitions should not drag the camera through
  // half the map while the spring catches up.
  if (
    distanceBetween(springPosition, transitionTargets.position) > 24 ||
    distanceBetween(springTarget, transitionTargets.target) > 24
  ) {
    springPosition = transitionTargets.position;
    springPositionVelocity = { x: 0, y: 0, z: 0 };
    springTarget = transitionTargets.target;
    springTargetVelocity = { x: 0, y: 0, z: 0 };
  }

  const verticalTracking = sample.vehicle
    ? profile.verticalTracking ?? (
        sample.airState === "airborne"
          ? config.airborneVerticalTracking
          : sample.airState === "landing"
            ? Math.max(config.airborneVerticalTracking, 0.5)
            : config.verticalTracking
      )
    : 0.86;
  const positionResult = springStep(
    springPosition,
    transitionTargets.position,
    springPositionVelocity,
    collision.collided ? config.collisionStiffness : config.positionStiffness,
    collision.collided ? config.collisionDamping : config.positionDamping,
    verticalTracking,
    dt
  );
  springPosition = positionResult.position;
  springPositionVelocity = positionResult.velocity;

  const targetResult = springStep(
    springTarget,
    transitionTargets.target,
    springTargetVelocity,
    config.targetStiffness,
    config.targetDamping,
    sample.vehicle ? verticalTracking : 0.90,
    dt
  );
  springTarget = targetResult.position;
  springTargetVelocity = targetResult.velocity;

  safeNative(
    "SET_FIXED_CAMERA_POSITION",
    springPosition.x,
    springPosition.y,
    springPosition.z,
    0,
    0,
    0
  );
  safeNative("POINT_CAMERA_AT_POINT", springTarget.x, springTarget.y, springTarget.z, 0);

  updateFovSpring(profile.fov, dt);

  if (!fovCapabilityLogged) {
    fovCapabilityLogged = true;
    log(
      "Adaptive Third-Person Camera: profile FOV requested " +
        profile.fov.toFixed(0) +
        " degrees; SA:DE exposes GET_CAMERA_FOV but no supported SET_CAMERA_FOV native, so FOV is not altered."
    );
  }

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
        " collision=" +
        collision.collided +
        " interaction=" +
        sample.interactionState
    );
  }
  cameraApplied = true;
}

function buildCameraGeometry(sample, profileValue, autoFollowWeight) {
  const direction = getCameraDirection(sample, profileValue, autoFollowWeight);
  const right = { x: direction.y, y: -direction.x, z: 0 };
  const base = { x: sample.position.x, y: sample.position.y, z: sample.position.z };
  const speedFactor = clamp(sample.speedKmh / 120, 0, 1);
  const travelDirection = sample.velocityDirection || direction;
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
        scaleVector(sample.forward, profileValue.accelerationLead * accelerationFactor)
      )
    )
  );
  const shoulder = profileValue.shoulderOffset *
    (sample.aiming ? shoulderSide : 1);
  const target = addVector(
    { x: base.x, y: base.y, z: base.z + profileValue.targetHeight },
    targetLead
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
  if (sample.kind === "motorbike") {
    const highSpeed = clamp(speed / 140, 0, 1);
    const result = profile(
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
    return result;
  }
  if (sample.kind === "bicycle") {
    const result = profile("Bicycle", config.bicycleDistance, config.bicycleHeight, config.bicycleFov, 1.1, 0.2, 0.25, 0);
    result.velocityLead = 0.45;
    result.accelerationLead = 0.18;
    return result;
  }
  if (sample.kind === "boat") {
    const result = profile("Boat", config.boatDistance, config.boatHeight, config.boatFov, 2.0 + speed / 70, 0.0, 0.9, 0);
    result.velocityLead = 0.8;
    result.accelerationLead = 0.25;
    return result;
  }
  if (sample.kind === "helicopter") {
    const result = profile("Helicopter", config.helicopterDistance, config.helicopterHeight, config.helicopterFov, 3.0 + speed / 55, 0.0, 0.75, 0);
    result.velocityLead = 1.0;
    result.accelerationLead = 0.3;
    return result;
  }
  if (sample.kind === "aircraft") {
    const result = profile("Aircraft", config.aircraftDistance, config.aircraftHeight, config.aircraftFov, 4.0 + speed / 45, 0.0, 0.65, 0);
    result.velocityLead = 1.4;
    result.accelerationLead = 0.45;
    return result;
  }

  const car = buildCarProfile(speed, sample.reverseActive, sample.filteredAccelerationMps2);
  car.steering = sample.steering;
  if (!sample.reverseActive && speed > 20 && driftAmount(sample) > 0.35) {
    car.stateName = "VehicleDrift";
  }
  if (sample.reverseActive) car.stateName = "VehicleReverse";
  if (sample.airState === "airborne") {
    car.stateName = "VehicleAirborne";
    car.verticalTracking = config.airborneVerticalTracking;
    car.lookAhead *= 0.75;
  } else if (sample.airState === "landing") {
    car.stateName = "VehicleLanding";
    car.verticalTracking = Math.max(config.airborneVerticalTracking, 0.5);
    car.height -= 0.04;
  }
  return car;
}

function buildOnFootProfile(sample) {
  if (sample.aiming) {
    return profile("OnFootAim", config.aimDistance, config.aimHeight, config.aimFov, 0.65, 0.55, 0.55, 0, 1.25);
  }

  const speed = sample.speedMps;
  if (speed < 0.65) {
    return profile("OnFootIdle", config.walkDistance, config.walkHeight, config.walkFov, 0.2, 0.18, 0.75, 0, 1.25);
  }
  if (speed < 2.0) {
    const amount = clamp((speed - 0.65) / 1.35, 0, 1);
    const result = interpolateProfiles(
      profile("OnFootWalk", config.walkDistance, config.walkHeight, config.walkFov, 0.5, 0.20, 0.75, 0, 1.28),
      profile("OnFootJog", config.jogDistance, config.jogHeight, config.jogFov, 1.0, 0.18, 0.72, 0, 1.28),
      amount
    );
    result.stateName = amount > 0.55 ? "OnFootJog" : "OnFootWalk";
    return result;
  }

  const amount = clamp((speed - 2.0) / 2.0, 0, 1);
  const result = interpolateProfiles(
    profile("OnFootJog", config.jogDistance, config.jogHeight, config.jogFov, 1.0, 0.18, 0.72, 0, 1.28),
    profile("OnFootSprint", config.sprintDistance, config.sprintHeight, config.sprintFov, 1.8, 0.12, 0.68, 0, 1.20),
    amount
  );
  result.stateName = amount > 0.35 ? "OnFootSprint" : "OnFootJog";
  return result;
}

function buildCarProfile(speedKmh, reverse, accelerationMps2) {
  const speed = clamp(speedKmh, 0, 200);
  let distance;
  let height;
  let fov;
  if (speed < 50) {
    const amount = speed / 50;
    distance = lerp(config.carSlowDistance, 6.8, amount);
    height = lerp(config.carSlowHeight, 2.2, amount);
    fov = lerp(config.carSlowFov, 72, amount);
  } else if (speed < 100) {
    const amount = (speed - 50) / 50;
    distance = lerp(6.8, config.carNormalDistance, amount);
    height = lerp(2.2, config.carNormalHeight, amount);
    fov = lerp(72, config.carNormalFov, amount);
  } else if (speed < 150) {
    const amount = (speed - 100) / 50;
    distance = lerp(config.carNormalDistance, config.carFastDistance, amount);
    height = lerp(config.carNormalHeight, config.carFastHeight, amount);
    fov = lerp(config.carNormalFov, config.carFastFov, amount);
  } else {
    const amount = clamp((speed - 150) / 50, 0, 1);
    distance = lerp(config.carFastDistance, 9.5, amount);
    height = lerp(config.carFastHeight, 2.45, amount);
    fov = lerp(config.carFastFov, 80, amount);
  }
  const result = profile(
    reverse ? "VehicleReverse" : speed < 35 ? "VehicleSlow" : speed < 105 ? "VehicleNormal" : "VehicleFast",
    distance,
    height,
    fov,
    2.0 + clamp(speed / 200, 0, 1) * 3.0,
    0,
    1.8,
    0
  );
  result.velocityLead = 0.7 + clamp(speed / 120, 0, 1) * 1.1;
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
    distance,
    height,
    targetHeight: targetHeight ?? (height > 3 ? height * 0.30 : height > 2 ? 0.85 : 0.95),
    fov,
    lookAhead,
    velocityLead: 0,
    accelerationLead: 0,
    verticalTracking: null,
    shoulderOffset,
    steeringLookAhead,
    steering,
  };
}

function getCameraDirection(sample, profileValue, autoFollowWeight) {
  let autoDirection = sample.forward;
  if (sample.velocityDirection && sample.speedMps > 0.35) {
    if (!sample.vehicle) {
      autoDirection = sample.velocityDirection;
    } else if (sample.reverseActive) {
      // In reverse the camera sits in front of the car and follows its actual
      // travel direction, rather than snapping through the vehicle heading.
      autoDirection = sample.velocityDirection;
    } else {
      const velocityInfluence = driftVelocityWeight(sample.slipAngleDegrees);
      autoDirection = normalizeVector(
        addVector(
          scaleVector(sample.forward, 1 - velocityInfluence),
          scaleVector(sample.velocityDirection, velocityInfluence)
        )
      );
    }
  } else if (!sample.vehicle) {
    const idleDirection = getIdleCameraDirection(sample.position);
    if (idleDirection) autoDirection = idleDirection;
  }

  if (profileValue.stateName === "OnFootAim") {
    const aimDirection = getAimCameraDirection(sample.position);
    if (aimDirection) autoDirection = aimDirection;
  }

  if (manualCameraDirection && autoFollowWeight < 1) {
    return normalizeVector(
      lerpVector(manualCameraDirection, autoDirection, autoFollowWeight)
    );
  }
  return normalizeVector(autoDirection);
}

function driftAmount(sample) {
  return driftVelocityWeight(sample.slipAngleDegrees) / Math.max(0.001, config.driftVelocityInfluence);
}

function steeringAmount(sample) {
  if (!sample.vehicle || !lastActorSample || lastActorSample.kind !== sample.kind) return 0;
  const elapsed = clamp((sample.timestamp - lastActorSample.timestamp) / 1000, 0.008, 0.05);
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

function getAimCameraDirection(anchor) {
  const camera = getCameraState();
  if (!camera) return null;
  const forward = { x: camera.forward.x, y: camera.forward.y, z: 0 };
  return vectorLength(forward) > 0.5 ? normalizeVector(forward) : getIdleCameraDirection(anchor);
}

function resolveCameraCollision(target, desiredPosition, now, forceRefresh = false) {
  if (!config.collisionEnabled) {
    return { position: desiredPosition, collided: false };
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

  if (isLineOfSightClear(target, desiredPosition)) {
    const result = { position: desiredPosition, collided: false };
    collisionCache = { timestamp: now, target, desiredPosition, result };
    return result;
  }

  let lastClear = null;
  for (let index = 1; index <= 8; index += 1) {
    const amount = index / 8;
    const candidate = lerpVector(target, desiredPosition, amount);
    if (!isCameraProbeClear(target, candidate)) break;
    lastClear = candidate;
  }

  const result = {
    position: lastClear || lerpVector(target, desiredPosition, 0.08),
    collided: true,
  };
  collisionCache = { timestamp: now, target, desiredPosition, result };
  return result;
}

function isCameraProbeClear(target, cameraPosition) {
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

  return offsets.every((offset) =>
    isLineOfSightClear(target, addVector(cameraPosition, offset))
  );
}

function isLineOfSightClear(from, to) {
  const result = safeNative(
    "IS_LINE_OF_SIGHT_CLEAR",
    from.x,
    from.y,
    from.z,
    to.x,
    to.y,
    to.z,
    true,
    true,
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

function releaseCamera() {
  anchorTransition = null;
  collisionCache = null;
  fovSpringValue = null;
  fovSpringVelocity = 0;
  if (cameraApplied) {
    safeNative("CAMERA_RESET_NEW_SCRIPTABLES");
    safeNative("RESTORE_CAMERA");
  }
  cameraApplied = false;
  springPosition = null;
  springTarget = null;
  springPositionVelocity = { x: 0, y: 0, z: 0 };
  springTargetVelocity = { x: 0, y: 0, z: 0 };
  lastStateName = null;
}

function springStep(current, target, velocity, stiffness, damping, verticalTracking, dt) {
  const verticalStiffness = stiffness * clamp(verticalTracking, 0.18, 1);
  const verticalDamping = damping * lerp(1.25, 1.0, clamp(verticalTracking, 0, 1));
  const acceleration = {
    x: (target.x - current.x) * stiffness - velocity.x * damping,
    y: (target.y - current.y) * stiffness - velocity.y * damping,
    z: (target.z - current.z) * verticalStiffness - velocity.z * verticalDamping,
  };
  const nextVelocity = addVector(velocity, scaleVector(acceleration, dt));
  const nextPosition = addVector(current, scaleVector(nextVelocity, dt));
  return { position: nextPosition, velocity: nextVelocity };
}

function readAnyVehicleState(actor) {
  return !!safeNative("IS_CHAR_IN_ANY_CAR", actor) ||
    !!safeNative("IS_CHAR_IN_ANY_BOAT", actor) ||
    !!safeNative("IS_CHAR_IN_ANY_HELI", actor) ||
    !!safeNative("IS_CHAR_IN_ANY_PLANE", actor);
}

function getVehicleInteractionState(sittingInVehicle, inAnyVehicle, previous) {
  if (sittingInVehicle) return "driving";
  if (!inAnyVehicle) return "onFoot";
  return previous?.sittingInVehicle ? "exiting" : "entering";
}

function getPlayerVehicle(actor, sittingNative = null) {
  // IS_CHAR_IN_ANY_CAR also stays true while the player is opening or
  // closing a door.  That is useful for vehicle scripts, but it is wrong for
  // camera ownership: during the exit animation the camera must stop using
  // the vehicle as its anchor as soon as the ped is no longer seated.
  const sitting = sittingNative === null
    ? safeNative("IS_CHAR_SITTING_IN_ANY_CAR", actor)
    : sittingNative;
  if (sitting === false || sitting === 0) return null;

  // Keep a conservative compatibility fallback for a runtime that does not
  // expose the sitting-state native. The official SA:DE definition does.
  if (sitting === null) {
    const inVehicle =
      !!safeNative("IS_CHAR_IN_ANY_CAR", actor) ||
      !!safeNative("IS_CHAR_IN_ANY_BOAT", actor) ||
      !!safeNative("IS_CHAR_IN_ANY_HELI", actor) ||
      !!safeNative("IS_CHAR_IN_ANY_PLANE", actor);
    if (!inVehicle) return null;
  }

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

function getCameraState() {
  const position = safeNative("GET_ACTIVE_CAMERA_COORDINATES");
  const pointAt = safeNative("GET_ACTIVE_CAMERA_POINT_AT");
  if (!isVector(position) || !isVector(pointAt)) return null;
  const forward = normalizeVector(subtractVector(pointAt, position));
  return vectorLength(forward) > 0.01 ? { position, pointAt, forward } : null;
}

function readManualCameraInput() {
  const mouse = safeNative("GET_PC_MOUSE_MOVEMENT") || {};
  const sticks = safeNative("GET_POSITION_OF_ANALOGUE_STICKS", PAD_ID) || {};
  const mouseX = finiteNumber(mouse.deltaX, 0);
  const mouseY = finiteNumber(mouse.deltaY, 0);
  const stickX = finiteNumber(sticks.rightStickX, 0);
  const stickY = finiteNumber(sticks.rightStickY, 0);
  return {
    magnitude: Math.max(
      Math.sqrt(mouseX * mouseX + mouseY * mouseY),
      Math.sqrt(stickX * stickX + stickY * stickY)
    ),
  };
}

function isAimHeld() {
  return !!safeNative("IS_KEY_PRESSED", RIGHT_MOUSE_BUTTON) ||
    !!safeNative("IS_BUTTON_PRESSED", PAD_ID, AIM_BUTTON);
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
    config.positionStiffness = clamp(readConfigInt("camera", "position_stiffness", config.positionStiffness), 20, 220);
    config.positionDamping = clamp(readConfigInt("camera", "position_damping", config.positionDamping), 5, 60);
    config.verticalTracking = clamp(readConfigInt("camera", "vertical_tracking_percent", config.verticalTracking * 100), 20, 100) / 100;
    config.airborneVerticalTracking = clamp(readConfigInt("camera", "airborne_vertical_tracking_percent", config.airborneVerticalTracking * 100), 15, 100) / 100;
    config.targetStiffness = clamp(readConfigInt("camera", "target_stiffness", config.targetStiffness), 20, 240);
    config.targetDamping = clamp(readConfigInt("camera", "target_damping", config.targetDamping), 5, 70);
    config.collisionStiffness = clamp(readConfigInt("camera", "collision_stiffness", config.collisionStiffness), 40, 360);
    config.collisionDamping = clamp(readConfigInt("camera", "collision_damping", config.collisionDamping), 8, 90);
    config.driftVelocityInfluence = clamp(readConfigInt("vehicle", "drift_velocity_influence_percent", config.driftVelocityInfluence * 100), 0, 100) / 100;
    config.reverseMinSpeedKmh = clamp(readConfigInt("vehicle", "reverse_min_speed_kmh", config.reverseMinSpeedKmh), 1, 20);
    config.reverseEnterHoldMs = clamp(readConfigInt("vehicle", "reverse_enter_hold_ms", config.reverseEnterHoldMs), 120, 800);
    config.reverseExitHoldMs = clamp(readConfigInt("vehicle", "reverse_exit_hold_ms", config.reverseExitHoldMs), 180, 1000);
    config.reverseExitSpeedKmh = clamp(readConfigInt("vehicle", "reverse_exit_speed_kmh", config.reverseExitSpeedKmh), 1, 20);
    config.accelerationFilterAlpha = clamp(readConfigInt("vehicle", "acceleration_filter_percent", config.accelerationFilterAlpha * 100), 4, 40) / 100;
    config.airborneEnterVerticalSpeed = clamp(readConfigInt("vehicle", "airborne_enter_speed_kmh", config.airborneEnterVerticalSpeed * 3.6), 3, 20) / 3.6;
    config.airborneExitVerticalSpeed = clamp(readConfigInt("vehicle", "airborne_exit_speed_kmh", config.airborneExitVerticalSpeed * 3.6), 4, 25) / 3.6;
    config.landingDurationMs = clamp(readConfigInt("vehicle", "landing_duration_ms", config.landingDurationMs), 80, 500);
    config.shoulderSwapCooldownMs = clamp(readConfigInt("aim", "shoulder_swap_cooldown_ms", config.shoulderSwapCooldownMs), 250, 1200);
    readDistanceAndHeightConfig();
    config.reloadHotkeyEnabled = readConfigBool("input", "reload_hotkey_enabled", config.reloadHotkeyEnabled);
    config.toggleHotkeyEnabled = readConfigBool("input", "toggle_hotkey_enabled", config.toggleHotkeyEnabled);
    log("Adaptive Third-Person Camera configuration loaded.");
  } catch (_) {
    log("Adaptive Third-Person Camera: configuration load failed; using defaults.");
  }
}

function readDistanceAndHeightConfig() {
  config.walkDistance = readConfigInt("on_foot", "walk_distance_cm", config.walkDistance * 100) / 100;
  config.walkHeight = readConfigInt("on_foot", "walk_height_cm", config.walkHeight * 100) / 100;
  config.walkFov = clamp(readConfigInt("on_foot", "walk_fov_deg", config.walkFov), 40, 90);
  config.jogDistance = readConfigInt("on_foot", "jog_distance_cm", config.jogDistance * 100) / 100;
  config.jogHeight = readConfigInt("on_foot", "jog_height_cm", config.jogHeight * 100) / 100;
  config.jogFov = clamp(readConfigInt("on_foot", "jog_fov_deg", config.jogFov), 40, 90);
  config.sprintDistance = readConfigInt("on_foot", "sprint_distance_cm", config.sprintDistance * 100) / 100;
  config.sprintHeight = readConfigInt("on_foot", "sprint_height_cm", config.sprintHeight * 100) / 100;
  config.sprintFov = clamp(readConfigInt("on_foot", "sprint_fov_deg", config.sprintFov), 40, 90);
  config.aimDistance = readConfigInt("aim", "distance_cm", config.aimDistance * 100) / 100;
  config.aimHeight = readConfigInt("aim", "height_cm", config.aimHeight * 100) / 100;
  config.aimFov = clamp(readConfigInt("aim", "fov_deg", config.aimFov), 40, 90);
  config.carSlowDistance = readConfigInt("car", "slow_distance_cm", config.carSlowDistance * 100) / 100;
  config.carSlowHeight = readConfigInt("car", "slow_height_cm", config.carSlowHeight * 100) / 100;
  config.carSlowFov = clamp(readConfigInt("car", "slow_fov_deg", config.carSlowFov), 40, 90);
  config.carNormalDistance = readConfigInt("car", "normal_distance_cm", config.carNormalDistance * 100) / 100;
  config.carNormalHeight = readConfigInt("car", "normal_height_cm", config.carNormalHeight * 100) / 100;
  config.carNormalFov = clamp(readConfigInt("car", "normal_fov_deg", config.carNormalFov), 40, 90);
  config.carFastDistance = readConfigInt("car", "fast_distance_cm", config.carFastDistance * 100) / 100;
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
  return !!safeNative("IS_KEY_PRESSED", keyCode);
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

function interpolateProfiles(left, right, amount) {
  const result = { ...left };
  for (const key of ["distance", "height", "targetHeight", "fov", "lookAhead", "shoulderOffset", "steeringLookAhead", "steering"]) {
    result[key] = lerp(left[key], right[key], amount);
  }
  return result;
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function smoothstep(minimum, maximum, value) {
  if (maximum <= minimum) return value >= maximum ? 1 : 0;
  const amount = clamp((value - minimum) / (maximum - minimum), 0, 1);
  return amount * amount * (3 - 2 * amount);
}
