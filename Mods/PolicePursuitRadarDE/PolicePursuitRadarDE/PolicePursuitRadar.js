/// <reference path="./.config/sa.d.ts" />

// Police Pursuit Radar DE, version 1.2 stabilized HUD/blips.
// Runtime: CLEO Redux x64 + IniFiles64.
//
// The HUD is rendered from normalized screen-space primitives. DRAW_RECT is
// used as the raster primitive for the radar, clipped search area, cones and
// markers; native blips remain an optional compatibility fallback.

if (HOST !== "sa_unreal") {
  exit("Police Pursuit Radar supports only GTA San Andreas: The Definitive Edition.");
}

const PLAYER_ID = 0;
const player = new Player(PLAYER_ID);
const CONFIG_PATH = "./PolicePursuitRadar.ini";
const CONFIG_VERSION = 1;
const VK_RELOAD = 122; // F11
const HUD_FRAME_INTERVAL_MS = 66;
const GAMEPLAY_SETTLE_MS = 5000;

const STATE_IDLE = "IDLE";
const STATE_PURSUIT = "PURSUIT";
const STATE_SEARCHING = "SEARCH";
const STATE_ESCAPED = "ESCAPED";

// Values from the standard San Andreas blip enums.
const BLIP_COLOR_RED = 0;
const BLIP_COLOR_BLUE = 2;
const BLIP_COLOR_YELLOW = 4;
const BLIP_COLOR_DESTINATION = 8;
const BLIP_DISPLAY_MARKER_ONLY = 1;
const BLIP_DISPLAY_BOTH = 3;

const PED_POLICE = 6;
const POLICE_PED_MODELS = new Set([280, 281, 282, 283, 284, 285]);
const POLICE_CAR_MODELS = new Set([407, 420, 427, 428, 432, 490, 528, 596, 597, 598, 599]);
const POLICE_BIKE_MODELS = new Set([523]);
const POLICE_HELICOPTER_MODELS = new Set([417, 425, 447, 469, 487, 488, 497, 548, 563]);
const POLICE_BOAT_MODELS = new Set([430, 446, 452]);

const DEFAULTS = {
  enabled: true,
  maxDistanceM: 420,
  scanIntervalMs: 450,
  discoveryIntervalMs: 1200,
  lostSightDelayMs: 1200,
  searchRadiusBaseM: 55,
  searchRadiusPerStarM: 25,
  showFoot: true,
  showCars: true,
  showBikes: true,
  showBoats: true,
  showHelicopters: true,
  showDirectionBlips: true,
  showSearchLocation: true,
  directionMarkerDistanceM: 12,
  directionUpdateDistanceM: 8,
  directionUpdateIntervalMs: 900,
  maxTrackedUnits: 16,
  maxNativeBlips: 12,
  maxDirectionBlips: 4,
  wantedZeroGraceMs: 800,
  // Keep the game's original minimap useful together with the bounded HUD.
  showNativeBlips: true,
  // The renderer has a strict per-frame budget and a unit limit.
  // The DRAW_RECT renderer remains opt-in until it is replaced with a
  // sprite-based implementation; the native tracker must not block loading.
  hudEnabled: false,
  hudRangeM: 180,
  hudSizePx: 166,
  hudXPercent: 10,
  hudYPercent: 84,
  hudRotateWithPlayer: true,
  hudShowOffRadar: true,
  hudBackgroundAlpha: 28,
  hudRingAlpha: 88,
  searchFillAlpha: 22,
  searchBorderAlpha: 86,
  coneLengthM: 90,
  coneFovDeg: 70,
  coneFillAlpha: 14,
  coneBorderAlpha: 82,
  hudMaxUnits: 6,
  hudDrawBudget: 96,
  debug: false,
  reloadHotkeyEnabled: true,
};

let config = { ...DEFAULTS };
let lastScanAt = 0;
let lastDiscoveryScanAt = 0;
let lastReloadDown = false;
let units = [];
let state = STATE_IDLE;
let wantedLevel = 0;
let lastRawWantedLevel = 0;
let lastPositiveWantedAt = 0;
let lastKnownPlayerPosition = null;
let lastContactAt = 0;
let escapedUntil = 0;
let lastLoggedState = null;
let lastHudFrameAt = 0;
let hudFaultedUntil = 0;
let hudErrorCount = 0;
let hudPermanentlyDisabled = false;
let hudFrameDrawCalls = 0;
let hudBudgetExceeded = false;
let lastHudBudgetLogAt = 0;
let nextUnitKey = 1;
let scanPhase = 0;
const nativeFailureCounts = new Map();
let lastNativeFailureLogAt = 0;
let gameplaySessionActive = false;
let gameplayDetectedAt = 0;

// Each scan keeps a logical key on the unit record. The key is independent of
// the JavaScript wrapper returned by a native query.
let unitBlips = [];
let searchBlip = null;
let searchBlipPosition = null;

log("Police Pursuit Radar DE 1.2 stabilized HUD/blips loaded. Host: " + HOST);
loadConfig();

while (true) {
  wait(0);
  const now = Date.now();
  const actor = getPlayerActor();
  const playing = !!actor;

  if (!playing) {
    if (gameplaySessionActive) resetRuntimeState();
    gameplaySessionActive = false;
    gameplayDetectedAt = 0;
    lastReloadDown = false;
    continue;
  }

  if (!gameplaySessionActive) {
    gameplaySessionActive = true;
    gameplayDetectedAt = now;
    // Do not start a full discovery pass on the first frame after loading.
    lastScanAt = now;
    lastDiscoveryScanAt = now;
    lastHudFrameAt = now;
    log("Police Pursuit Radar gameplay detected; settling runtime.");
  }

  // IS_PLAYER_PLAYING can become true while the save/interior transition is
  // still settling. Avoid all world queries, blips and DRAW_RECT calls here.
  if (now - gameplayDetectedAt < GAMEPLAY_SETTLE_MS) continue;

  if (config.reloadHotkeyEnabled) {
    const reloadDown = !!Pad.IsKeyPressed(VK_RELOAD);
    if (reloadDown && !lastReloadDown) {
      loadConfig();
      log("Police Pursuit Radar configuration reloaded.");
    }
    lastReloadDown = reloadDown;
  }

  if (config.enabled) {
    const playerPosition = getCoordinates(actor, false);
    wantedLevel = readWantedLevel(now);
    if (playerPosition && now - lastScanAt >= config.scanIntervalMs) {
      units = scanPolice(actor, playerPosition, wantedLevel);
      updatePursuitState(playerPosition, units, wantedLevel, now);
      syncBlips(units);
      lastScanAt = now;
    }
  } else {
    resetRuntimeState();
  }

  if (
    config.enabled &&
    config.hudEnabled &&
    !hudPermanentlyDisabled &&
    now >= hudFaultedUntil &&
    now - lastHudFrameAt >= HUD_FRAME_INTERVAL_MS
  ) {
    const playerPosition = getCoordinates(actor, false);
    if (playerPosition) {
      try {
        drawHudRadar(actor, playerPosition, units, now);
        hudErrorCount = 0;
      } catch (error) {
        hudErrorCount += 1;
        hudFaultedUntil = now + 5000;
        if (hudErrorCount >= 3) hudPermanentlyDisabled = true;
        log(
          "Police Pursuit Radar HUD renderer error #" +
            hudErrorCount +
            (hudPermanentlyDisabled ? "; disabled for this session: " : "; retrying: ") +
            error
        );
      }
      lastHudFrameAt = now;
    }
  }
}

function getPlayerActor() {
  try {
    if (!player.isPlaying()) return null;
    const actor = player.getChar();
    if (!actor || safeNative("IS_CHAR_DEAD", actor)) return null;
    return actor;
  } catch (_) {
    return null;
  }
}

function readWantedLevel(now) {
  const value = safeNative("STORE_WANTED_LEVEL", player);
  const current = clamp(Math.trunc(finiteNumber(value, 0)), 0, 6);
  if (current > 0) {
    lastRawWantedLevel = current;
    lastPositiveWantedAt = now;
    return current;
  }
  if (lastRawWantedLevel > 0 && now - lastPositiveWantedAt < config.wantedZeroGraceMs) {
    return lastRawWantedLevel;
  }
  lastRawWantedLevel = 0;
  return 0;
}

function scanPolice(actor, playerPosition, stars) {
  if (stars <= 0) return [];

  const results = [];
  const discoverNewUnits = Date.now() - lastDiscoveryScanAt >= config.discoveryIntervalMs;

  // Re-check previously found units first. This prevents the single-result
  // sphere native from making an attached blip flicker between scans and lets
  // each active unit keep its stable logical key.
  for (const previous of units) {
    const refreshed = inspectPolice(previous.char, actor, playerPosition, stars);
    if (refreshed) {
      refreshed.key = previous.key;
      refreshed.missedScans = 0;
      addUnit(results, refreshed, previous.key);
    } else {
      addUnit(results, retainUnitForOneScan(previous, playerPosition), previous.key);
    }
  }

  if (discoverNewUnits) {
    const samples = samplePoints(playerPosition, config.maxDistanceM, scanPhase);
    scanPhase = (scanPhase + 1) % 32;
    lastDiscoveryScanAt = Date.now();
    for (const sample of samples) {
      const value = safeNative(
        "GET_RANDOM_CHAR_IN_SPHERE_NO_BRAIN",
        sample.x,
        sample.y,
        sample.z,
        sample.radius
      );
      const police = toHandle(value, Char);
      if (police) addUnit(results, inspectPolice(police, actor, playerPosition, stars));
    }
  }

  return results
    .filter(Boolean)
    .sort(comparePoliceUnits)
    .slice(0, config.maxTrackedUnits);
}

function retainUnitForOneScan(previous, playerPosition) {
  if (!previous || previous.missedScans >= 1) return null;
  if (safeNative("IS_CHAR_DEAD", previous.char)) return null;

  const pedPosition = getCoordinates(previous.char, false);
  if (!pedPosition || distanceBetween(pedPosition, playerPosition) > config.maxDistanceM) {
    return null;
  }

  return {
    ...previous,
    contact: false,
    missedScans: 1,
  };
}

function samplePoints(center, maxDistance, phase) {
  const result = [{ x: center.x, y: center.y, z: center.z, radius: Math.min(115, maxDistance) }];
  // The native returns one nearest ped per sample. A bounded 17-point layout
  // rotates between discovery cycles, while existing units are refreshed more
  // often without querying the whole world every frame.
  const rings = [maxDistance * 0.36, maxDistance * 0.72];
  for (let ring = 0; ring < rings.length; ring += 1) {
    const count = 8;
    for (let index = 0; index < count; index += 1) {
      const angle =
        (Math.PI * 2 * index) / count +
        ring * 0.31 +
        phase * 0.11;
      result.push({
        x: center.x + Math.cos(angle) * rings[ring],
        y: center.y + Math.sin(angle) * rings[ring],
        z: center.z,
        radius: Math.min(105, Math.max(60, maxDistance * 0.24)),
      });
    }
  }
  return result;
}

function inspectPolice(char, actor, playerPosition, stars) {
  if (!char || safeNative("IS_CHAR_DEAD", char)) return null;
  const pedType = finiteNumber(safeNative("GET_PED_TYPE", char), -1);
  const pedModel = finiteNumber(safeNative("GET_CHAR_MODEL", char), -1);
  if (pedType !== PED_POLICE && !POLICE_PED_MODELS.has(pedModel)) return null;

  const pedPosition = getCoordinates(char, false);
  if (!pedPosition || distanceBetween(pedPosition, playerPosition) > config.maxDistanceM) return null;

  let car = null;
  let carModel = -1;
  let position = pedPosition;
  let type = "foot";
  try {
    if (safeNative("IS_CHAR_IN_ANY_CAR", char)) {
      car = toHandle(safeNative("STORE_CAR_CHAR_IS_IN_NO_SAVE", char), Car);
      if (car) {
        carModel = finiteNumber(safeNative("GET_CAR_MODEL", car), -1);
        position = getCoordinates(car, true) || pedPosition;
        type = classifyVehicle(carModel);
      }
    }
  } catch (_) {
    car = null;
  }

  const distance = distanceBetween(position, playerPosition);
  if (distance > config.maxDistanceM) return null;

  const lineOfSight = !!safeNative(
    "IS_LINE_OF_SIGHT_CLEAR",
    position.x,
    position.y,
    position.z + (type === "foot" ? 1.0 : 1.7),
    playerPosition.x,
    playerPosition.y,
    playerPosition.z + 1.0,
    true,
    true,
    true,
    true,
    true
  );
  const spotted = !!safeNative("HAS_CHAR_SPOTTED_CHAR", char, actor);
  const contact = lineOfSight && spotted;
  const heading = car
    ? finiteNumber(safeNative("GET_CAR_HEADING", car), 0)
    : finiteNumber(safeNative("GET_CHAR_HEADING", char), 0);

  return {
    char,
    car,
    type,
    pedModel,
    carModel,
    position,
    heading,
    distance,
    lineOfSight,
    spotted,
    contact,
    stars,
  };
}

function classifyVehicle(model) {
  if (POLICE_HELICOPTER_MODELS.has(model)) return "helicopter";
  if (POLICE_BOAT_MODELS.has(model)) return "boat";
  if (POLICE_BIKE_MODELS.has(model)) return "bike";
  if (POLICE_CAR_MODELS.has(model)) return "car";
  return "car";
}

function addUnit(list, unit, preferredKey) {
  if (!unit) return;
  if (preferredKey) unit.key = preferredKey;

  const duplicate = list.find((existing) => samePoliceUnit(existing, unit));
  if (!duplicate) {
    unit.key = unit.key || "police-" + nextUnitKey++;
    list.push(unit);
    return;
  }

  const stableKey = duplicate.key || unit.key || "police-" + nextUnitKey++;
  const stableChar = duplicate.char;
  const stableCar = sameCarEntity(duplicate, unit) ? duplicate.car : unit.car;
  Object.assign(duplicate, unit);
  duplicate.key = stableKey;
  // Keep the canonical wrapper used by the first successful scan. This avoids
  // treating a fresh JS wrapper for the same game handle as a new unit.
  duplicate.char = stableChar;
  duplicate.car = stableCar;
}

function comparePoliceUnits(left, right) {
  if (left.contact !== right.contact) return left.contact ? -1 : 1;
  return left.distance - right.distance;
}

function samePoliceUnit(left, right) {
  if (!left || !right) return false;
  if (left.char === right.char) return true;
  if (left.car && right.car && sameCarEntity(left, right)) return true;

  const samePed = left.type === right.type && left.pedModel === right.pedModel;
  const mergeDistance = left.car || right.car ? 6.0 : 3.0;
  return samePed && distanceBetween(left.position, right.position) < mergeDistance;
}

function sameCarEntity(left, right) {
  if (!left.car || !right.car) return false;
  if (left.car === right.car) return true;
  return (
    left.carModel === right.carModel &&
    distanceBetween(left.position, right.position) < 8.0
  );
}

function updatePursuitState(playerPosition, currentUnits, stars, now) {
  if (stars <= 0) {
    if (state !== STATE_IDLE && state !== STATE_ESCAPED) {
      state = STATE_ESCAPED;
      escapedUntil = now + 900;
      logStateChange();
    } else if (state === STATE_ESCAPED && now >= escapedUntil) {
      resetRuntimeState();
    }
    return;
  }

  if (state === STATE_ESCAPED) {
    state = STATE_IDLE;
    escapedUntil = 0;
  }

  const hasContact = currentUnits.some((unit) => unit.contact);
  if (hasContact) {
    state = STATE_PURSUIT;
    lastKnownPlayerPosition = { ...playerPosition };
    lastContactAt = now;
  } else if (state === STATE_PURSUIT && now - lastContactAt >= config.lostSightDelayMs) {
    if (!lastKnownPlayerPosition) lastKnownPlayerPosition = { ...playerPosition };
    state = STATE_SEARCHING;
  }

  if (config.debug && now - lastScanAt < 20) {
    log(
      "Radar scan: units=" +
        currentUnits.length +
        " contact=" +
        hasContact +
        " state=" +
        state +
        " searchRadius=" +
        getSearchRadius(stars)
    );
  }
  logStateChange();
}

function getSearchRadius(stars) {
  return clamp(config.searchRadiusBaseM + stars * config.searchRadiusPerStarM, 20, 250);
}

function getHudGeometry() {
  const size = clamp(config.hudSizePx, 110, 260);
  return {
    center: {
      x: clamp(config.hudXPercent / 100, 0.04, 0.45),
      y: clamp(config.hudYPercent / 100, 0.55, 0.96),
    },
    radius: {
      // DRAW_RECT uses normalized screen coordinates. These defaults match
      // the usual 16:9 lower-left radar placement and remain editable in INI.
      x: clamp(size / 1920, 0.045, 0.16),
      y: clamp(size / 1080, 0.06, 0.24),
    },
    rangeM: Math.max(60, config.hudRangeM),
  };
}

function drawHudRadar(actor, playerPosition, currentUnits, now) {
  hudFrameDrawCalls = 0;
  hudBudgetExceeded = false;
  const geometry = getHudGeometry();
  const playerHeading = finiteNumber(safeNative("GET_CHAR_HEADING", actor), 0);
  const visibleUnits = prioritizeUnits(currentUnits)
    .filter((unit) => isTypeEnabled(unit.type))
    .slice(0, config.hudMaxUnits);
  const clipRadius = {
    x: geometry.radius.x * 0.965,
    y: geometry.radius.y * 0.965,
  };

  drawFilledEllipse(
    geometry.center,
    geometry.radius,
    0.015,
    0.035,
    0.055,
    alphaValue(config.hudBackgroundAlpha)
  );
  drawCircle(
    geometry.center,
    geometry.radius,
    0.18,
    0.55,
    0.78,
    alphaValue(config.hudRingAlpha),
    2.0
  );
  drawCircle(
    geometry.center,
    { x: geometry.radius.x * 0.66, y: geometry.radius.y * 0.66 },
    0.12,
    0.35,
    0.50,
    0.34,
    1.0
  );

  if (state === STATE_SEARCHING && lastKnownPlayerPosition) {
    drawSearchArea(geometry, playerPosition, playerHeading, clipRadius);
  }

  for (const unit of visibleUnits) {
    drawPoliceCone(geometry, playerPosition, playerHeading, unit, clipRadius);
  }

  for (const unit of visibleUnits) {
    const point = radarPoint(unit.position, playerPosition, playerHeading, geometry);
    if (!point) continue;
    drawUnitMarker(point, unit, geometry, playerPosition, playerHeading);
  }

  if (state === STATE_SEARCHING && lastKnownPlayerPosition) {
    const lastKnown = radarPoint(lastKnownPlayerPosition, playerPosition, playerHeading, geometry);
    if (lastKnown) {
      drawDiamond(
        lastKnown.x,
        lastKnown.y,
        geometry.radius.y * 0.075,
        1.0,
        0.62,
        0.12,
        0.95,
        1.8
      );
    }
  }

  drawPlayerArrow(geometry.center, playerHeading, geometry);
  if (
    hudBudgetExceeded &&
    now - lastHudBudgetLogAt >= 5000
  ) {
    lastHudBudgetLogAt = now;
    log(
      "Police Pursuit Radar HUD draw budget reached: calls=" +
        hudFrameDrawCalls +
        " budget=" +
        config.hudDrawBudget +
        " units=" +
        visibleUnits.length
    );
  }
}

function prioritizeUnits(currentUnits) {
  return currentUnits.slice().sort(comparePoliceUnits);
}

function radarPoint(position, playerPosition, playerHeading, geometry) {
  let dx = position.x - playerPosition.x;
  let dy = position.y - playerPosition.y;
  if (config.hudRotateWithPlayer) {
    const angle = (playerHeading * Math.PI) / 180;
    const forwardX = Math.sin(angle);
    const forwardY = Math.cos(angle);
    const rightX = Math.cos(angle);
    const rightY = -Math.sin(angle);
    const localX = dx * rightX + dy * rightY;
    const localY = dx * forwardX + dy * forwardY;
    dx = localX;
    dy = localY;
  }

  const offsetX = (dx / geometry.rangeM) * geometry.radius.x;
  const offsetY = -(dy / geometry.rangeM) * geometry.radius.y;
  const normalizedDistance = Math.sqrt(
    (offsetX * offsetX) / (geometry.radius.x * geometry.radius.x) +
      (offsetY * offsetY) / (geometry.radius.y * geometry.radius.y)
  );
  if (normalizedDistance <= 0.92) {
    return {
      x: geometry.center.x + offsetX,
      y: geometry.center.y + offsetY,
      offRadar: false,
    };
  }
  if (!config.hudShowOffRadar || normalizedDistance <= 0.001) return null;
  const scale = 0.92 / normalizedDistance;
  return {
    x: geometry.center.x + offsetX * scale,
    y: geometry.center.y + offsetY * scale,
    offRadar: true,
  };
}

function drawSearchArea(geometry, playerPosition, playerHeading, clipRadius) {
  const center = radarPoint(lastKnownPlayerPosition, playerPosition, playerHeading, geometry);
  if (!center) return;

  const searchRadius = getSearchRadius(wantedLevel);
  const radius = {
    x: (searchRadius / geometry.rangeM) * geometry.radius.x,
    y: (searchRadius / geometry.rangeM) * geometry.radius.y,
  };
  drawFilledClippedEllipse(
    center,
    radius,
    geometry.center,
    clipRadius,
    1.0,
    0.46,
    0.08,
    alphaValue(config.searchFillAlpha)
  );
  drawClippedEllipseBorder(
    center,
    radius,
    geometry.center,
    clipRadius,
    1.0,
    0.62,
    0.12,
    alphaValue(config.searchBorderAlpha),
    1.8
  );
}

function drawPoliceCone(geometry, playerPosition, playerHeading, unit, clipRadius) {
  const origin = radarPoint(unit.position, playerPosition, playerHeading, geometry);
  if (!origin || origin.offRadar) return;

  const headingPosition = getWorldHeadingPosition(
    unit.position,
    unit.heading,
    clamp(config.coneLengthM, 20, 180)
  );
  const endpoint = radarPoint(headingPosition, playerPosition, playerHeading, geometry);
  if (!endpoint) return;

  const direction = {
    x: endpoint.x - origin.x,
    y: endpoint.y - origin.y,
  };
  const directionLength = Math.sqrt(direction.x * direction.x + direction.y * direction.y);
  if (directionLength < 0.0001) return;
  direction.x /= directionLength;
  direction.y /= directionLength;

  const normal = { x: -direction.y, y: direction.x };
  const halfAngle = (clamp(config.coneFovDeg, 20, 140) * Math.PI) / 360;
  const coneWidth = directionLength * Math.tan(halfAngle);
  const left = {
    x: endpoint.x + normal.x * coneWidth,
    y: endpoint.y + normal.y * coneWidth,
  };
  const right = {
    x: endpoint.x - normal.x * coneWidth,
    y: endpoint.y - normal.y * coneWidth,
  };
  const color = unit.contact
    ? { r: 1.0, g: 0.12, b: 0.08 }
    : { r: 0.22, g: 0.64, b: 1.0 };

  drawFilledClippedTriangle(
    origin,
    left,
    right,
    geometry.center,
    clipRadius,
    color.r,
    color.g,
    color.b,
    alphaValue(config.coneFillAlpha)
  );
  drawLine(
    origin.x,
    origin.y,
    left.x,
    left.y,
    color.r,
    color.g,
    color.b,
    alphaValue(config.coneBorderAlpha),
    1.2
  );
  drawLine(
    origin.x,
    origin.y,
    right.x,
    right.y,
    color.r,
    color.g,
    color.b,
    alphaValue(config.coneBorderAlpha),
    1.2
  );
}

function getWorldHeadingPosition(position, heading, distance) {
  const angle = (finiteNumber(heading, 0) * Math.PI) / 180;
  return {
    x: position.x + Math.sin(angle) * distance,
    y: position.y + Math.cos(angle) * distance,
    z: position.z,
  };
}

function drawUnitMarker(point, unit, geometry, playerPosition, playerHeading) {
  const color = unit.contact
    ? { r: 1.0, g: 0.16, b: 0.10 }
    : unit.type === "helicopter"
      ? { r: 0.42, g: 1.0, b: 0.76 }
      : unit.type === "boat"
        ? { r: 0.24, g: 0.72, b: 1.0 }
        : unit.type === "bike"
          ? { r: 0.88, g: 0.42, b: 1.0 }
          : { r: 0.30, g: 0.72, b: 1.0 };
  const alpha = point.offRadar ? 0.42 : 0.96;
  const markerRadius = {
    x: geometry.radius.x * 0.060,
    y: geometry.radius.y * 0.060,
  };

  if (unit.type === "foot") {
    drawCircle(point, markerRadius, color.r, color.g, color.b, alpha, 1.8);
    drawLine(point.x - markerRadius.x, point.y, point.x + markerRadius.x, point.y, color.r, color.g, color.b, alpha, 1.4);
    return;
  }
  if (unit.type === "helicopter") {
    drawCircle(point, { x: markerRadius.x * 1.45, y: markerRadius.y * 1.45 }, color.r, color.g, color.b, alpha, 1.8);
    drawLine(point.x - markerRadius.x * 0.65, point.y, point.x + markerRadius.x * 0.65, point.y, color.r, color.g, color.b, alpha, 1.5);
    drawLine(point.x, point.y - markerRadius.y * 0.65, point.x, point.y + markerRadius.y * 0.65, color.r, color.g, color.b, alpha, 1.5);
    return;
  }
  if (unit.type === "boat") {
    drawDiamond(point.x, point.y, markerRadius.y * 1.45, color.r, color.g, color.b, alpha, 1.8);
    return;
  }

  const direction = radarDirection(unit, playerPosition, playerHeading, geometry);
  drawChevron(point.x, point.y, direction, color.r, color.g, color.b, alpha, markerRadius.y * 1.7);
}

function radarDirection(unit, playerPosition, playerHeading, geometry) {
  const origin = radarPoint(unit.position, playerPosition, playerHeading, geometry);
  const endpoint = radarPoint(
    getWorldHeadingPosition(unit.position, unit.heading, 8),
    playerPosition,
    playerHeading,
    geometry
  );
  if (!origin || !endpoint) return { x: 0, y: -1 };
  const direction = { x: endpoint.x - origin.x, y: endpoint.y - origin.y };
  const length = Math.sqrt(direction.x * direction.x + direction.y * direction.y);
  return length > 0.0001 ? { x: direction.x / length, y: direction.y / length } : { x: 0, y: -1 };
}

function drawPlayerArrow(center, playerHeading, geometry) {
  const angle = config.hudRotateWithPlayer ? 0 : (playerHeading * Math.PI) / 180;
  const forward = { x: Math.sin(angle), y: -Math.cos(angle) };
  const right = { x: Math.cos(angle), y: Math.sin(angle) };
  const tip = {
    x: center.x + forward.x * geometry.radius.x * 0.16,
    y: center.y + forward.y * geometry.radius.y * 0.16,
  };
  const left = {
    x: center.x - forward.x * geometry.radius.x * 0.09 - right.x * geometry.radius.x * 0.08,
    y: center.y - forward.y * geometry.radius.y * 0.09 - right.y * geometry.radius.y * 0.08,
  };
  const other = {
    x: center.x - forward.x * geometry.radius.x * 0.09 + right.x * geometry.radius.x * 0.08,
    y: center.y - forward.y * geometry.radius.y * 0.09 + right.y * geometry.radius.y * 0.08,
  };
  drawLine(tip.x, tip.y, left.x, left.y, 0.86, 0.96, 1.0, 1.0, 2.0);
  drawLine(tip.x, tip.y, other.x, other.y, 0.86, 0.96, 1.0, 1.0, 2.0);
  drawLine(left.x, left.y, other.x, other.y, 0.86, 0.96, 1.0, 1.0, 1.6);
}

function drawChevron(x, y, direction, r, g, b, a, size) {
  const forward = direction || { x: 0, y: -1 };
  const right = { x: -forward.y, y: forward.x };
  const tip = { x: x + forward.x * size * 0.9, y: y + forward.y * size };
  const left = {
    x: x - forward.x * size * 0.6 - right.x * size * 0.6,
    y: y - forward.y * size * 0.6 - right.y * size * 0.6,
  };
  const other = {
    x: x - forward.x * size * 0.6 + right.x * size * 0.6,
    y: y - forward.y * size * 0.6 + right.y * size * 0.6,
  };
  drawLine(tip.x, tip.y, left.x, left.y, r, g, b, a, 2.0);
  drawLine(tip.x, tip.y, other.x, other.y, r, g, b, a, 2.0);
  drawLine(left.x, left.y, other.x, other.y, r, g, b, a, 1.4);
}

function drawDiamond(x, y, size, r, g, b, a, thickness) {
  drawLine(x, y - size, x + size * 0.9, y, r, g, b, a, thickness);
  drawLine(x + size * 0.9, y, x, y + size, r, g, b, a, thickness);
  drawLine(x, y + size, x - size * 0.9, y, r, g, b, a, thickness);
  drawLine(x - size * 0.9, y, x, y - size, r, g, b, a, thickness);
}

function drawFilledEllipse(center, radius, r, g, b, a) {
  const steps = 18;
  const rowHeight = Math.max(0.001, (radius.y * 2) / steps);
  for (let index = -steps; index <= steps; index += 1) {
    const normalized = index / steps;
    const half = Math.sqrt(Math.max(0, 1 - normalized * normalized));
    drawRect(center.x, center.y + normalized * radius.y, radius.x * 2 * half, rowHeight, r, g, b, a);
  }
}

function drawFilledClippedEllipse(center, radius, clipCenter, clipRadius, r, g, b, a) {
  const steps = 24;
  const rowHeight = Math.max(0.001, (radius.y * 2) / steps);
  for (let index = -steps; index <= steps; index += 1) {
    const normalized = index / steps;
    const y = center.y + normalized * radius.y;
    const searchHalf = radius.x * Math.sqrt(Math.max(0, 1 - normalized * normalized));
    const clipHalf = ellipseHalfWidthAtY(y, clipCenter, clipRadius);
    if (clipHalf === null) continue;
    const left = Math.max(0, center.x - searchHalf, clipCenter.x - clipHalf);
    const right = Math.min(1, center.x + searchHalf, clipCenter.x + clipHalf);
    if (right > left) drawRect((left + right) / 2, y, right - left, rowHeight, r, g, b, a);
  }
}

function drawClippedEllipseBorder(center, radius, clipCenter, clipRadius, r, g, b, a, thickness) {
  let previous = null;
  const segments = 32;
  for (let index = 0; index <= segments; index += 1) {
    const angle = (Math.PI * 2 * index) / segments;
    const point = {
      x: center.x + Math.cos(angle) * radius.x,
      y: center.y + Math.sin(angle) * radius.y,
    };
    if (previous && isInsideEllipse(previous, clipCenter, clipRadius) && isInsideEllipse(point, clipCenter, clipRadius)) {
      drawLine(previous.x, previous.y, point.x, point.y, r, g, b, a, thickness);
    }
    previous = point;
  }
}

function drawFilledClippedTriangle(a, b, c, clipCenter, clipRadius, r, g, bl, alpha) {
  const points = [a, b, c];
  const minY = Math.max(0, Math.min(a.y, b.y, c.y));
  const maxY = Math.min(1, Math.max(a.y, b.y, c.y));
  const rows = 18;
  if (maxY <= minY) return;
  const rowHeight = (maxY - minY) / rows;

  for (let row = 0; row < rows; row += 1) {
    const y = minY + rowHeight * (row + 0.5);
    const intersections = [];
    for (let index = 0; index < 3; index += 1) {
      const first = points[index];
      const second = points[(index + 1) % 3];
      if (Math.abs(second.y - first.y) < 0.00001) continue;
      const minimum = Math.min(first.y, second.y);
      const maximum = Math.max(first.y, second.y);
      if (y < minimum || y >= maximum) continue;
      const t = (y - first.y) / (second.y - first.y);
      intersections.push(first.x + (second.x - first.x) * t);
    }
    if (intersections.length < 2) continue;
    const left = Math.max(0, Math.min(intersections[0], intersections[1]));
    const right = Math.min(1, Math.max(intersections[0], intersections[1]));
    const clipHalf = ellipseHalfWidthAtY(y, clipCenter, clipRadius);
    if (clipHalf === null) continue;
    const clippedLeft = Math.max(left, clipCenter.x - clipHalf);
    const clippedRight = Math.min(right, clipCenter.x + clipHalf);
    if (clippedRight > clippedLeft) {
      drawRect((clippedLeft + clippedRight) / 2, y, clippedRight - clippedLeft, rowHeight, r, g, bl, alpha);
    }
  }
}

function ellipseHalfWidthAtY(y, center, radius) {
  if (radius.x <= 0 || radius.y <= 0) return null;
  const normalizedY = (y - center.y) / radius.y;
  if (Math.abs(normalizedY) > 1) return null;
  return radius.x * Math.sqrt(Math.max(0, 1 - normalizedY * normalizedY));
}

function isInsideEllipse(point, center, radius) {
  const dx = (point.x - center.x) / radius.x;
  const dy = (point.y - center.y) / radius.y;
  return dx * dx + dy * dy <= 1.001;
}

function drawCircle(center, radius, r, g, b, a, thickness) {
  let previous = null;
  const segments = 24;
  for (let index = 0; index <= segments; index += 1) {
    const angle = (Math.PI * 2 * index) / segments;
    const point = {
      x: center.x + Math.cos(angle) * radius.x,
      y: center.y + Math.sin(angle) * radius.y,
    };
    if (previous) drawLine(previous.x, previous.y, point.x, point.y, r, g, b, a, thickness);
    previous = point;
  }
}

function drawLine(x1, y1, x2, y2, r, g, b, a, thickness) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const length = Math.sqrt(dx * dx + dy * dy);
  const steps = Math.max(1, Math.ceil(length / 0.010));
  for (let index = 0; index <= steps; index += 1) {
    const t = index / steps;
    drawRect(
      x1 + dx * t,
      y1 + dy * t,
      Math.max(0.0015, thickness / 1920),
      Math.max(0.0025, thickness / 1080),
      r,
      g,
      b,
      a
    );
  }
}

function alphaValue(percent) {
  return clamp(finiteNumber(percent, 0), 0, 100) / 100;
}

function drawRect(x, y, width, height, r, g, b, a) {
  if (hudFrameDrawCalls >= config.hudDrawBudget) {
    hudBudgetExceeded = true;
    return;
  }
  hudFrameDrawCalls += 1;
  // Let the frame-level guard catch renderer failures. Swallowing this
  // exception here would make the automatic HUD pause impossible.
  native(
    "DRAW_RECT",
    clamp(finiteNumber(x, 0), 0, 1),
    clamp(finiteNumber(y, 0), 0, 1),
    Math.max(0.001, finiteNumber(width, 0.001)),
    Math.max(0.001, finiteNumber(height, 0.001)),
    nativeColor(r),
    nativeColor(g),
    nativeColor(b),
    nativeColor(a)
  );
}

function nativeColor(value) {
  return Math.round(clamp(finiteNumber(value, 0), 0, 1) * 255);
}

function syncBlips(currentUnits) {
  if (!config.showNativeBlips || wantedLevel <= 0 || state === STATE_ESCAPED) {
    clearBlips();
    return;
  }

  const nativeUnits = prioritizeUnits(currentUnits)
    .filter((unit) => isTypeEnabled(unit.type))
    .slice(0, config.maxNativeBlips);
  const activeKeys = new Set();
  for (let index = 0; index < nativeUnits.length; index += 1) {
    const unit = nativeUnits[index];

    const key = unit.key;
    if (!key) continue;
    activeKeys.add(key);
    const recordIndex = unitBlips.findIndex((entry) => entry.key === key);
    let record = recordIndex >= 0 ? unitBlips[recordIndex] : null;
    if (!record || !sameTrackedTarget(record, unit)) {
      if (record) {
        removeUnitBlips(record);
      }
      const replacement = {
        key,
        target: null,
        targetKind: null,
        targetCarModel: -1,
        targetPosition: null,
        blip: null,
        directionBlip: null,
        directionPosition: null,
        directionUpdatedAt: 0,
      };
      if (recordIndex >= 0) {
        unitBlips[recordIndex] = replacement;
      } else {
        unitBlips.push(replacement);
      }
      record = replacement;
    }

    if (record.blip && !isBlipAlive(record.blip)) record.blip = null;
    if (!record.blip) {
      record.blip = addTrackingBlip(unit);
      if (record.blip) {
        record.target = unit.car || unit.char;
        record.targetKind = unit.car ? "car" : "char";
        record.targetCarModel = unit.carModel;
      }
    }
    record.targetPosition = { ...unit.position };
    styleTrackingBlip(record.blip, unit);
    syncDirectionBlip(record, unit, index < config.maxDirectionBlips);
  }

  for (let index = unitBlips.length - 1; index >= 0; index -= 1) {
    const record = unitBlips[index];
    if (!activeKeys.has(record.key)) {
      removeUnitBlips(record);
      unitBlips.splice(index, 1);
    }
  }

  syncSearchBlip();
}

function addTrackingBlip(unit) {
  const value = unit.car
    ? safeNative("ADD_BLIP_FOR_CAR", unit.car)
    : safeNative("ADD_BLIP_FOR_CHAR", unit.char);
  if (!value) {
    noteNativeFailure(unit.car ? "ADD_BLIP_FOR_CAR" : "ADD_BLIP_FOR_CHAR", "empty result");
  }
  return toHandle(value, Blip);
}

function sameTrackedTarget(record, unit) {
  const kind = unit.car ? "car" : "char";
  if (!record.target) return false;
  if (record.targetKind !== kind) return false;
  if (kind === "char") return true;
  if (record.target === unit.car) return true;
  return (
    record.targetCarModel === unit.carModel &&
    record.targetPosition &&
    distanceBetween(record.targetPosition, unit.position) < 12.0
  );
}

function styleTrackingBlip(blip, unit) {
  if (!blip) return;
  const color = unit.contact || state === STATE_PURSUIT ? BLIP_COLOR_RED : BLIP_COLOR_BLUE;
  safeNative("CHANGE_BLIP_COLOUR", blip, color);
  safeNative("CHANGE_BLIP_DISPLAY", blip, BLIP_DISPLAY_BOTH);
  safeNative("CHANGE_BLIP_SCALE", blip, 1);
}

function syncDirectionBlip(record, unit, allowed) {
  if (!config.showDirectionBlips || !allowed) {
    removeBlip(record.directionBlip);
    record.directionBlip = null;
    record.directionPosition = null;
    record.directionUpdatedAt = 0;
    return;
  }

  const now = Date.now();
  if (record.directionBlip && !isBlipAlive(record.directionBlip)) {
    record.directionBlip = null;
    record.directionPosition = null;
    record.directionUpdatedAt = 0;
  }
  const nextPosition = getDirectionPosition(unit);
  if (
    record.directionBlip &&
    record.directionPosition &&
    (
      distanceBetween(record.directionPosition, nextPosition) < config.directionUpdateDistanceM ||
      now - record.directionUpdatedAt < config.directionUpdateIntervalMs
    )
  ) {
    safeNative(
      "CHANGE_BLIP_COLOUR",
      record.directionBlip,
      state === STATE_PURSUIT ? BLIP_COLOR_RED : BLIP_COLOR_YELLOW
    );
    return;
  }

  removeBlip(record.directionBlip);
  const directionBlip = addCoordinateBlip(
    nextPosition,
    state === STATE_PURSUIT ? BLIP_COLOR_RED : BLIP_COLOR_YELLOW,
    BLIP_DISPLAY_MARKER_ONLY
  );
  record.directionBlip = directionBlip;
  record.directionPosition = directionBlip ? nextPosition : null;
  record.directionUpdatedAt = now;
}

function getDirectionPosition(unit) {
  const angle = (finiteNumber(unit.heading, 0) * Math.PI) / 180;
  const distance = clamp(config.directionMarkerDistanceM, 3, 40);
  return {
    x: unit.position.x + Math.sin(angle) * distance,
    y: unit.position.y + Math.cos(angle) * distance,
    z: unit.position.z,
  };
}

function syncSearchBlip() {
  const shouldShow = config.showSearchLocation && state === STATE_SEARCHING && lastKnownPlayerPosition;
  if (!shouldShow) {
    removeBlip(searchBlip);
    searchBlip = null;
    searchBlipPosition = null;
    return;
  }

  if (searchBlip && !isBlipAlive(searchBlip)) {
    searchBlip = null;
    searchBlipPosition = null;
  }

  if (
    !searchBlip ||
    !searchBlipPosition ||
    distanceBetween(searchBlipPosition, lastKnownPlayerPosition) > 0.5
  ) {
    removeBlip(searchBlip);
    searchBlip = addCoordinateBlip(
      lastKnownPlayerPosition,
      BLIP_COLOR_YELLOW,
      BLIP_DISPLAY_BOTH
    );
    searchBlipPosition = { ...lastKnownPlayerPosition };
  }
}

function addCoordinateBlip(position, color, display) {
  // The old coordinate form accepts color/display directly. The fallback is
  // useful on definitions that expose only the newer three-argument form.
  let value = safeNative(
    "ADD_BLIP_FOR_COORD_OLD",
    position.x,
    position.y,
    position.z,
    color,
    display
  );
  if (!value) {
    value = safeNative("ADD_BLIP_FOR_COORD", position.x, position.y, position.z);
  }
  const blip = toHandle(value, Blip);
  if (!blip) noteNativeFailure("ADD_BLIP_FOR_COORD", "empty result");
  if (blip) {
    safeNative("CHANGE_BLIP_COLOUR", blip, color);
    safeNative("CHANGE_BLIP_DISPLAY", blip, display);
    safeNative("CHANGE_BLIP_SCALE", blip, 1);
  }
  return blip;
}

function removeUnitBlips(record) {
  removeBlip(record.blip);
  removeBlip(record.directionBlip);
  record.blip = null;
  record.directionBlip = null;
}

function clearBlips() {
  for (const record of unitBlips) removeUnitBlips(record);
  unitBlips = [];
  removeBlip(searchBlip);
  searchBlip = null;
  searchBlipPosition = null;
}

function removeBlip(blip) {
  if (!blip) return;
  safeNative("REMOVE_BLIP", blip);
}

function isBlipAlive(blip) {
  if (!blip) return false;
  const result = safeNative("DOES_BLIP_EXIST", blip);
  // If the validation native itself fails, keep the current handle and avoid
  // creating a replacement every scan. The next real blip operation still
  // records the failure through safeNative.
  return result === null ? true : !!result;
}

function isTypeEnabled(type) {
  if (type === "foot") return config.showFoot;
  if (type === "car") return config.showCars;
  if (type === "bike") return config.showBikes;
  if (type === "boat") return config.showBoats;
  if (type === "helicopter") return config.showHelicopters;
  return true;
}

function updateConfigValue(section, key, fallback) {
  if (typeof IniFile === "undefined" || typeof IniFile.ReadInt !== "function") return fallback;
  try {
    return finiteNumber(IniFile.ReadInt(CONFIG_PATH, section, key), fallback);
  } catch (_) {
    return fallback;
  }
}

function loadConfig() {
  if (typeof IniFile === "undefined" || typeof IniFile.ReadInt !== "function") {
    log("Police Pursuit Radar: IniFiles64 unavailable; using defaults.");
    return;
  }
  try {
    const version = updateConfigValue("meta", "config_version", CONFIG_VERSION);
    if (version !== CONFIG_VERSION) {
      log("Police Pursuit Radar: unsupported config version; using defaults.");
      return;
    }
    config.enabled = updateConfigValue("mod", "enabled", DEFAULTS.enabled ? 1 : 0) !== 0;
    config.maxDistanceM = clamp(updateConfigValue("tracking", "max_distance_m", DEFAULTS.maxDistanceM), 80, 900);
    config.scanIntervalMs = clamp(updateConfigValue("tracking", "scan_interval_ms", DEFAULTS.scanIntervalMs), 100, 2000);
    config.discoveryIntervalMs = clamp(updateConfigValue("tracking", "discovery_interval_ms", DEFAULTS.discoveryIntervalMs), 600, 5000);
    config.lostSightDelayMs = clamp(updateConfigValue("tracking", "lost_sight_delay_ms", DEFAULTS.lostSightDelayMs), 250, 10000);
    config.wantedZeroGraceMs = clamp(updateConfigValue("tracking", "wanted_zero_grace_ms", DEFAULTS.wantedZeroGraceMs), 0, 3000);
    config.maxTrackedUnits = clamp(updateConfigValue("tracking", "max_tracked_units", DEFAULTS.maxTrackedUnits), 6, 16);
    config.searchRadiusBaseM = clamp(updateConfigValue("search", "radius_base_m", DEFAULTS.searchRadiusBaseM), 20, 150);
    config.searchRadiusPerStarM = clamp(updateConfigValue("search", "radius_per_star_m", DEFAULTS.searchRadiusPerStarM), 0, 80);
    config.showFoot = updateConfigValue("blips", "show_foot", DEFAULTS.showFoot ? 1 : 0) !== 0;
    config.showCars = updateConfigValue("blips", "show_cars", DEFAULTS.showCars ? 1 : 0) !== 0;
    config.showBikes = updateConfigValue("blips", "show_bikes", DEFAULTS.showBikes ? 1 : 0) !== 0;
    config.showBoats = updateConfigValue("blips", "show_boats", DEFAULTS.showBoats ? 1 : 0) !== 0;
    config.showHelicopters = updateConfigValue("blips", "show_helicopters", DEFAULTS.showHelicopters ? 1 : 0) !== 0;
    config.showDirectionBlips = updateConfigValue("blips", "show_direction_blips", DEFAULTS.showDirectionBlips ? 1 : 0) !== 0;
    config.showSearchLocation = updateConfigValue("blips", "show_search_location", DEFAULTS.showSearchLocation ? 1 : 0) !== 0;
    config.directionMarkerDistanceM = clamp(updateConfigValue("blips", "direction_marker_distance_m", DEFAULTS.directionMarkerDistanceM), 3, 40);
    config.directionUpdateDistanceM = clamp(updateConfigValue("blips", "direction_update_distance_m", DEFAULTS.directionUpdateDistanceM), 3, 30);
    config.directionUpdateIntervalMs = clamp(updateConfigValue("blips", "direction_update_interval_ms", DEFAULTS.directionUpdateIntervalMs), 250, 5000);
    config.maxNativeBlips = clamp(updateConfigValue("blips", "max_native_blips", DEFAULTS.maxNativeBlips), 4, 12);
    config.maxDirectionBlips = clamp(updateConfigValue("blips", "max_direction_blips", DEFAULTS.maxDirectionBlips), 0, 4);
    config.showNativeBlips = updateConfigValue("blips", "show_native_blips", DEFAULTS.showNativeBlips ? 1 : 0) !== 0;
    config.hudEnabled = updateConfigValue("hud", "enabled", DEFAULTS.hudEnabled ? 1 : 0) !== 0;
    config.hudRangeM = clamp(updateConfigValue("hud", "range_m", DEFAULTS.hudRangeM), 60, 500);
    config.hudSizePx = clamp(updateConfigValue("hud", "size_px", DEFAULTS.hudSizePx), 110, 260);
    config.hudXPercent = clamp(updateConfigValue("hud", "screen_x_percent", DEFAULTS.hudXPercent), 4, 45);
    config.hudYPercent = clamp(updateConfigValue("hud", "screen_y_percent", DEFAULTS.hudYPercent), 55, 96);
    config.hudRotateWithPlayer = updateConfigValue("hud", "rotate_with_player", DEFAULTS.hudRotateWithPlayer ? 1 : 0) !== 0;
    config.hudShowOffRadar = updateConfigValue("hud", "show_off_radar", DEFAULTS.hudShowOffRadar ? 1 : 0) !== 0;
    config.hudBackgroundAlpha = clamp(updateConfigValue("hud", "background_alpha_percent", DEFAULTS.hudBackgroundAlpha), 0, 100);
    config.hudRingAlpha = clamp(updateConfigValue("hud", "ring_alpha_percent", DEFAULTS.hudRingAlpha), 0, 100);
    config.searchFillAlpha = clamp(updateConfigValue("hud", "search_fill_alpha_percent", DEFAULTS.searchFillAlpha), 0, 100);
    config.searchBorderAlpha = clamp(updateConfigValue("hud", "search_border_alpha_percent", DEFAULTS.searchBorderAlpha), 0, 100);
    config.coneLengthM = clamp(updateConfigValue("hud", "cone_length_m", DEFAULTS.coneLengthM), 20, 180);
    config.coneFovDeg = clamp(updateConfigValue("hud", "cone_fov_deg", DEFAULTS.coneFovDeg), 20, 140);
    config.coneFillAlpha = clamp(updateConfigValue("hud", "cone_fill_alpha_percent", DEFAULTS.coneFillAlpha), 0, 100);
    config.coneBorderAlpha = clamp(updateConfigValue("hud", "cone_border_alpha_percent", DEFAULTS.coneBorderAlpha), 0, 100);
    config.hudMaxUnits = clamp(updateConfigValue("hud", "max_units", DEFAULTS.hudMaxUnits), 2, 6);
    config.hudDrawBudget = clamp(updateConfigValue("hud", "draw_budget", DEFAULTS.hudDrawBudget), 32, 120);
    config.debug = updateConfigValue("visual", "debug", DEFAULTS.debug ? 1 : 0) !== 0;
    config.reloadHotkeyEnabled = updateConfigValue("input", "reload_hotkey_enabled", DEFAULTS.reloadHotkeyEnabled ? 1 : 0) !== 0;
    hudFaultedUntil = 0;
    hudErrorCount = 0;
    hudPermanentlyDisabled = false;
    log("Police Pursuit Radar configuration loaded.");
  } catch (_) {
    log("Police Pursuit Radar: config load failed; using defaults.");
  }
}

function resetRuntimeState() {
  clearBlips();
  units = [];
  wantedLevel = 0;
  lastRawWantedLevel = 0;
  lastPositiveWantedAt = 0;
  state = STATE_IDLE;
  lastKnownPlayerPosition = null;
  lastContactAt = 0;
  escapedUntil = 0;
  lastScanAt = 0;
  lastDiscoveryScanAt = 0;
  scanPhase = 0;
}

function logStateChange() {
  if (state === lastLoggedState) return;
  lastLoggedState = state;
  if (state === STATE_SEARCHING && lastKnownPlayerPosition) {
    log(
      "Police Pursuit Radar state: " +
        state +
        " lastKnownPlayerPosition=" +
        lastKnownPlayerPosition.x.toFixed(1) +
        "," +
        lastKnownPlayerPosition.y.toFixed(1) +
        "," +
        lastKnownPlayerPosition.z.toFixed(1)
    );
  } else {
    log("Police Pursuit Radar state: " + state);
  }
}

function getCoordinates(entity, vehicle) {
  const result = safeNative(vehicle ? "GET_CAR_COORDINATES" : "GET_CHAR_COORDINATES", entity);
  return isVector(result) ? result : null;
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
  } catch (error) {
    noteNativeFailure(name, error);
    return null;
  }
}

function noteNativeFailure(name, detail) {
  const count = (nativeFailureCounts.get(name) || 0) + 1;
  nativeFailureCounts.set(name, count);
  if (name === "DRAW_RECT") return;

  const now = Date.now();
  if (count === 1 || now - lastNativeFailureLogAt >= 5000) {
    lastNativeFailureLogAt = now;
    log(
      "Police Pursuit Radar native failure: " +
        name +
        " count=" +
        count +
        (detail ? " detail=" + detail : "")
    );
  }
}

function isVector(value) {
  return !!value && Number.isFinite(Number(value.x)) && Number.isFinite(Number(value.y)) && Number.isFinite(Number(value.z));
}

function finiteNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function distanceBetween(left, right) {
  const x = left.x - right.x;
  const y = left.y - right.y;
  const z = left.z - right.z;
  return Math.sqrt(x * x + y * y + z * z);
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}
