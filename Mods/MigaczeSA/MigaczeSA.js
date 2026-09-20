/// <reference path="./.config/sa.d.ts" />

// Migacze SA v1.0
// GTA San Andreas Classic 1.0 / CLEO Redux JavaScript + CLEO Library.
//
// The script is intentionally observation-only. It does not change vehicle AI,
// route tasks, speed, handling or vehicle ownership. It estimates an active
// turn from the vehicle's heading change and lateral velocity, then renders
// amber coronas at the corresponding side of the front and rear of the car.

if (typeof HOST === "undefined" || HOST !== "sa") {
  exit("Migacze SA supports only classic GTA San Andreas (host sa).");
}

const PLAYER_ID = 0;
const player = new Player(PLAYER_ID);

// These values are deliberately constants so the mod has no dependency on an
// INI plugin. They are the only tuning points needed for a normal installation.
const SETTINGS = Object.freeze({
  scanRadiusM: 260,
  scanIntervalMs: 120,
  staleVehicleMs: 850,
  minimumForwardSpeedMps: 2.0,
  minimumTurnRateDegPerSecond: 8.0,
  minimumLateralSpeedMps: 0.55,
  signalHoldAfterTurnMs: 900,
  blinkPeriodMs: 560,
  coronaSize: 0.20,
  signalColor: { r: 255, g: 145, b: 25 },
  // GTA vehicle local space: X is side-to-side, Y is front-to-back, Z is up.
  sideOffsetM: 0.78,
  frontOffsetM: 1.62,
  rearOffsetM: -1.48,
  lampHeightM: 0.48,
});

const NATIVE_FAILURE = Symbol("native-failure");
const nativeFailureCounts = new Map();
const vehicles = new Map();
let sphereEnumerationAvailable = null;
let poolEnumerationAvailable = null;
let nextScanAt = 0;
let lastFrameFailureAt = 0;

// Aircraft, boats and rail vehicles do not have road-style turn indicators.
// Motorcycles remain included; custom vehicle models are included by default.
const NON_ROAD_VEHICLE_MODELS = new Set([
  417, 425, 430, 446, 447, 452, 453, 454, 460, 464, 465, 469, 472, 473,
  476, 484, 487, 488, 493, 497, 511, 512, 513, 519, 520, 537, 538, 548,
  553, 577, 590, 592, 593, 595,
]);

while (true) {
  wait(0);
  const now = Date.now();

  if (now >= nextScanAt) {
    try {
      scanVehicles(now);
    } catch (error) {
      if (now - lastFrameFailureAt >= 1000) {
        lastFrameFailureAt = now;
        log("Migacze SA: vehicle scan recovered from an error: " + error);
      }
    }
    nextScanAt = now + SETTINGS.scanIntervalMs;
  }

  try {
    drawSignals(now);
  } catch (error) {
    if (now - lastFrameFailureAt >= 1000) {
      lastFrameFailureAt = now;
      log("Migacze SA: render frame recovered from an error: " + error);
    }
  }
}

function scanVehicles(now) {
  const actor = getPlayerActor();
  if (!actor) {
    vehicles.clear();
    return;
  }

  const center = readCoordinates(actor, false);
  if (!isVector(center)) return;

  const found = enumerateVehicles(center);
  const seen = new Set();

  for (const car of found) {
    if (!isVehicleValid(car)) continue;

    const position = readCoordinates(car, true);
    if (!isVector(position) || distance3D(center, position) > SETTINGS.scanRadiusM) {
      continue;
    }

    const key = entityHandle(car);
    if (key === null) continue;

    const model = Math.trunc(finiteNumber(callNative("GET_CAR_MODEL", car), -1));
    if (NON_ROAD_VEHICLE_MODELS.has(model)) continue;

    const heading = finiteNumber(callNative("GET_CAR_HEADING", car), NaN);
    const speed = Math.abs(finiteNumber(callNative("GET_CAR_SPEED", car), 0));
    if (!Number.isFinite(heading)) continue;

    const speedVector = readSpeedVector(car, heading, speed);
    const previous = vehicles.get(key);
    const next = updateVehicleState(previous, car, heading, speed, speedVector, now);
    next.position = position;
    next.lastSeenAt = now;
    vehicles.set(key, next);
    seen.add(key);
  }

  for (const [key, state] of vehicles) {
    if (!seen.has(key) && now - state.lastSeenAt > SETTINGS.staleVehicleMs) {
      vehicles.delete(key);
    }
  }
}

function updateVehicleState(previous, car, heading, speed, speedVector, now) {
  const state = previous || {
    car,
    heading,
    sampleAt: now,
    turnSide: 0,
    turnUntil: 0,
    lastSeenAt: now,
    position: null,
  };

  state.car = car;
  const elapsedMs = Math.max(1, now - state.sampleAt);
  const headingDelta = previous ? shortestAngleDelta(heading, previous.heading) : 0;
  const turnRate = Math.abs(headingDelta) * 1000 / elapsedMs;
  const lateralSpeed = signedLateralSpeed(heading, speedVector);
  const forwardSpeed = forwardSpeedAlongHeading(heading, speedVector, speed);
  const canSignal = forwardSpeed >= SETTINGS.minimumForwardSpeedMps;
  const hasTurnRate = turnRate >= SETTINGS.minimumTurnRateDegPerSecond;
  const hasLateralMotion = Math.abs(lateralSpeed) >= SETTINGS.minimumLateralSpeedMps;

  if (previous && canSignal && (hasTurnRate || hasLateralMotion)) {
    const side = hasTurnRate
      ? (headingDelta > 0 ? 1 : -1)
      : (lateralSpeed > 0 ? 1 : -1);
    state.turnSide = side;
    state.turnUntil = now + SETTINGS.signalHoldAfterTurnMs;
  } else if (!canSignal || now >= state.turnUntil) {
    state.turnSide = 0;
    state.turnUntil = 0;
  }

  state.heading = heading;
  state.sampleAt = now;
  return state;
}

function drawSignals(now) {
  const blinkOn = Math.floor(now / SETTINGS.blinkPeriodMs) % 2 === 0;
  if (!blinkOn) return;

  for (const state of vehicles.values()) {
    if (!state.car || state.turnSide === 0 || now >= state.turnUntil) continue;
    if (callNative("IS_CAR_ON_SCREEN", state.car) !== true) continue;

    const side = SETTINGS.sideOffsetM * state.turnSide;
    drawCoronaAtOffset(state.car, side, SETTINGS.frontOffsetM);
    drawCoronaAtOffset(state.car, side, SETTINGS.rearOffsetM);
  }
}

function drawCoronaAtOffset(car, sideOffset, longitudinalOffset) {
  const point = callNative(
    "GET_OFFSET_FROM_CAR_IN_WORLD_COORDS",
    car,
    sideOffset,
    longitudinalOffset,
    SETTINGS.lampHeightM
  );
  if (!isVector(point)) return;

  const color = SETTINGS.signalColor;
  // Corona type 0 is the small shiny-star type supported by classic SA. The
  // flare is disabled so a signal does not create a headlight-style flare.
  callNative(
    "DRAW_CORONA",
    point.x,
    point.y,
    point.z,
    SETTINGS.coronaSize,
    0,
    0,
    color.r,
    color.g,
    color.b
  );
}

function enumerateVehicles(center) {
  const sphere = enumerateVehiclesInSphere(center);
  if (sphere !== null) return sphere;

  const pool = enumerateVehiclesFromPool(center);
  return pool || [];
}

function enumerateVehiclesInSphere(center) {
  if (sphereEnumerationAvailable === false) return null;

  const result = new Map();
  let findNext = false;
  try {
    for (let index = 0; index < 128; index += 1) {
      const value = native(
        "GET_RANDOM_CAR_IN_SPHERE_NO_SAVE_RECURSIVE",
        center.x,
        center.y,
        center.z,
        SETTINGS.scanRadiusM,
        findNext,
        true
      );
      const car = extractVehicle(value);
      if (!car) break;
      const key = entityHandle(car);
      if (key !== null) result.set(key, car);
      findNext = true;
    }
    sphereEnumerationAvailable = true;
    return Array.from(result.values());
  } catch (error) {
    sphereEnumerationAvailable = false;
    noteNativeFailure("GET_RANDOM_CAR_IN_SPHERE_NO_SAVE_RECURSIVE", error);
    return null;
  }
}

function enumerateVehiclesFromPool(center) {
  if (poolEnumerationAvailable === false) return null;

  const result = new Map();
  let progress = 0;
  try {
    for (let index = 0; index < 256; index += 1) {
      const value = native("GET_ANY_CAR_NO_SAVE_RECURSIVE", progress);
      const car = extractNamedVehicle(value, ["anyCar", "car", "vehicle", "handle"]);
      const nextProgress = extractNumber(value, ["progress"]);
      if (car && isVehicleValid(car)) {
        const position = readCoordinates(car, true);
        if (isVector(position) && distance3D(center, position) <= SETTINGS.scanRadiusM) {
          const key = entityHandle(car);
          if (key !== null) result.set(key, car);
        }
      }
      if (!Number.isFinite(nextProgress) || nextProgress === progress) break;
      progress = nextProgress;
    }
    poolEnumerationAvailable = true;
    return Array.from(result.values());
  } catch (error) {
    poolEnumerationAvailable = false;
    noteNativeFailure("GET_ANY_CAR_NO_SAVE_RECURSIVE", error);
    return null;
  }
}

function readSpeedVector(car, heading, speed) {
  const vector = normalizeVector(callNative("GET_CAR_SPEED_VECTOR", car));
  if (isVector(vector)) return vector;

  const forward = headingVector(heading);
  return {
    x: forward.x * speed,
    y: forward.y * speed,
    z: 0,
  };
}

function forwardSpeedAlongHeading(heading, speedVector, fallbackSpeed) {
  if (!isVector(speedVector)) return fallbackSpeed;
  const forward = headingVector(heading);
  return speedVector.x * forward.x + speedVector.y * forward.y;
}

function signedLateralSpeed(heading, speedVector) {
  if (!isVector(speedVector)) return 0;
  const angle = (heading * Math.PI) / 180;
  const right = { x: Math.cos(angle), y: -Math.sin(angle) };
  return speedVector.x * right.x + speedVector.y * right.y;
}

function getPlayerActor() {
  try {
    if (!player.isPlaying()) return null;
    const actor = player.getChar();
    if (!actor || callNative("IS_CHAR_DEAD", actor) === true) return null;
    return actor;
  } catch (_) {
    return null;
  }
}

function readCoordinates(entity, vehicle) {
  return normalizeVector(
    callNative(vehicle ? "GET_CAR_COORDINATES" : "GET_CHAR_COORDINATES", entity)
  );
}

function isVehicleValid(car) {
  if (!car) return false;
  if (callNative("DOES_VEHICLE_EXIST", car) === false) return false;
  return callNative("IS_CAR_DEAD", car) !== true;
}

function extractVehicle(value) {
  return extractNamedVehicle(value, ["handle", "car", "vehicle", "anyCar"]);
}

function extractNamedVehicle(value, keys) {
  if (value === null || value === undefined || value === false || value === -1) return null;
  if (typeof value === "object") {
    for (const key of keys) {
      if (value[key] !== undefined && value[key] !== null) {
        return toHandle(value[key]);
      }
    }
    if (entityHandle(value) !== null) return toHandle(value);
    return null;
  }
  return toHandle(value);
}

function extractNumber(value, keys) {
  if (value === null || value === undefined) return NaN;
  if (typeof value === "object") {
    for (const key of keys) {
      const number = Number(value[key]);
      if (Number.isFinite(number)) return number;
    }
    return NaN;
  }
  if (typeof value === "symbol") return NaN;
  const number = Number(value);
  return Number.isFinite(number) ? number : NaN;
}

function toHandle(value) {
  if (value === null || value === undefined || value === false || value === -1 || value === 0) {
    return null;
  }
  if (typeof value === "object") return value;
  try {
    return typeof Car === "undefined" ? null : new Car(value);
  } catch (_) {
    return null;
  }
}

function entityHandle(entity) {
  if (entity === null || entity === undefined) return null;
  if (typeof entity === "symbol") return null;
  for (const key of ["handle", "id", "value", "__handle"]) {
    const number = Number(entity[key]);
    if (Number.isFinite(number)) return number;
  }
  const number = Number(entity);
  return Number.isFinite(number) ? number : null;
}

function callNative(name, ...args) {
  try {
    return native(name, ...args);
  } catch (error) {
    noteNativeFailure(name, error);
    return NATIVE_FAILURE;
  }
}

function noteNativeFailure(name, detail) {
  const count = (nativeFailureCounts.get(name) || 0) + 1;
  nativeFailureCounts.set(name, count);
  if (count === 1) log("Migacze SA native failure: " + name + " " + detail);
}

function normalizeVector(value) {
  if (value === null || value === undefined || typeof value === "symbol") return null;
  if (isVector(value)) {
    return { x: Number(value.x), y: Number(value.y), z: Number(value.z) };
  }
  if (Array.isArray(value) && value.length >= 3) {
    const vector = { x: Number(value[0]), y: Number(value[1]), z: Number(value[2]) };
    return isVector(vector) ? vector : null;
  }
  return null;
}

function isVector(value) {
  return !!value && typeof value === "object"
    && Number.isFinite(Number(value.x))
    && Number.isFinite(Number(value.y))
    && Number.isFinite(Number(value.z));
}

function headingVector(degrees) {
  const angle = (degrees * Math.PI) / 180;
  return { x: Math.sin(angle), y: Math.cos(angle) };
}

function shortestAngleDelta(current, previous) {
  let delta = current - previous;
  while (delta > 180) delta -= 360;
  while (delta < -180) delta += 360;
  return delta;
}

function distance3D(left, right) {
  const x = left.x - right.x;
  const y = left.y - right.y;
  const z = left.z - right.z;
  return Math.sqrt(x * x + y * y + z * z);
}

function finiteNumber(value, fallback) {
  if (typeof value === "symbol") return fallback;
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}
