/// <reference path="./.config/sa.d.ts" />

// Police Pursuit Radar DE, version 1.4 entity-lifecycle rewrite.
// Runtime: CLEO Redux x64 + IniFiles64.
//
// Tracking and presentation are deliberately separated. The tracker owns all
// GTA handles/native reads; the HUD receives only a finite RadarModel made of
// normalized screen-space values. Native blips remain the compatibility
// fallback when the custom renderer is disabled or degraded.

if (HOST !== "sa_unreal") {
  exit("Police Pursuit Radar supports only GTA San Andreas: The Definitive Edition.");
}

const PLAYER_ID = 0;
const player = new Player(PLAYER_ID);
const CONFIG_PATH = "./PolicePursuitRadar.ini";
const CONFIG_VERSION = 1;
const VK_RELOAD = 122; // F11
// This CLEO implementation drew a second HUD surface and its first world scan
// crashes SA:DE 1.0.113.21181. The official minimap is an Unreal BP_Radar_Base
// asset and cannot be reshaped by SCM HUD commands. Keep this legacy script
// inert; the replacement must be a version-matched Unreal .pak override.
const LEGACY_CLEO_IMPLEMENTATION_ENABLED = false;
// A safe renderer can be called every game frame. The old 15 FPS throttle was
// masking the cost of a rasterized renderer instead of fixing its cost.
const HUD_FRAME_INTERVAL_MS = 0;
const GAMEPLAY_SETTLE_MS = 5000;
const HUD_RENDER_HARD_BUDGET_MS = 4;
const HUD_PERF_SAMPLE_LIMIT = 30;
// SCM HUD commands use the original virtual screen rather than normalized
// coordinates. Keep the presentation model normalized and convert only at
// the CLEO boundary, like other working SA:DE HUD/menu scripts do.
const HUD_VIRTUAL_WIDTH = 640;
const HUD_VIRTUAL_HEIGHT = 448;
const CUSTOM_HUD_RENDERER_AVAILABLE = true;

const HUD_LEVEL_FULL = "FULL";
const HUD_LEVEL_REDUCED = "REDUCED";
const HUD_LEVEL_MINIMAL = "MINIMAL";
const HUD_LEVEL_NATIVE_ONLY = "NATIVE_ONLY";
const HUD_LEVEL_OFF = "OFF";

const CONTACT_MEMORY_MS = 350;
const UNIT_EVICTION_TTL_MS = 2500;
const POLICE_CONTACT_FOV_DEG = 120;
const LIFECYCLE_VISIBLE = "visible";
const LIFECYCLE_MEMORY = "memory";
const LIFECYCLE_LOST = "lost";

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
  // The custom renderer has a strict per-frame budget and a unit limit.
  hudEnabled: true,
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
  // The rectangular fallback is intentionally capped to a small number of
  // logical primitives. Existing INI values above this are clamped on load.
  hudDrawBudget: 24,
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
let hudRenderLevel = HUD_LEVEL_REDUCED;
let hudRenderSamples = [];
let hudRenderAverageMs = 0;
let hudRenderP95Ms = 0;
let hudRenderMaxMs = 0;
let radarModel = null;
let radarModelState = null;
const radarUnitTransitions = new Map();
let nextUnitKey = 1;
let scanPhase = 0;
const nativeFailureCounts = new Map();
let lastNativeFailureLogAt = 0;
let gameplaySessionActive = false;
let gameplayDetectedAt = 0;
let discoveredTotal = 0;
let evictedTotal = 0;
let lastRegistryLogAt = 0;

// Each scan keeps a logical key on the unit record. The key is independent of
// the JavaScript wrapper returned by a native query.
let unitBlips = [];
let searchBlip = null;
let searchBlipPosition = null;

log("Police Pursuit Radar DE 1.4 entity-lifecycle rewrite loaded. Host: " + HOST);
if (!LEGACY_CLEO_IMPLEMENTATION_ENABLED) {
  exit("Police Pursuit Radar DE legacy CLEO implementation disabled; install the Unreal radar asset package instead.");
}
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
    if (now - lastScanAt >= config.scanIntervalMs) {
      const playerPosition = getCoordinates(actor, false);
      if (playerPosition) {
        wantedLevel = readWantedLevel(now);
        const playerHeading = readPlayerHeading(actor);
        units = scanPolice(actor, playerPosition, wantedLevel, now);
        updatePursuitState(playerPosition, units, wantedLevel, now);
        updateRadarModel(playerPosition, playerHeading, units, now);
        syncBlips(units);
        lastScanAt = now;
      }
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
    if (radarModel) {
      try {
        radarModel = buildRadarModel(now);
        drawHudRadar(radarModel, now);
        hudErrorCount = 0;
      } catch (error) {
        hudErrorCount += 1;
        hudFaultedUntil = now + 5000;
        degradeHudRenderer("exception");
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

function scanPolice(actor, playerPosition, stars, now) {
  if (stars <= 0) {
    releaseTrackedUnits(units);
    return [];
  }

  const previousUnits = units;
  const results = [];
  const discoverNewUnits = now - lastDiscoveryScanAt >= config.discoveryIntervalMs;

  // Re-check previously found units first. This prevents the single-result
  // sphere native from making an attached blip flicker between scans and lets
  // each active unit keep its stable logical key.
  for (const previous of previousUnits) {
    const refreshed = inspectPolice(previous.char, actor, playerPosition, stars, now);
    if (refreshed) {
      if (isObservationConsistent(previous, refreshed)) {
        const merged = mergeUnitObservation(previous, refreshed, now);
        if (!shouldEvictUnit(merged, now)) addUnit(results, merged, previous.key);
      } else {
        // A recycled handle is a new entity. Do not carry its key, contact or
        // blips into the new observation; final-unit cleanup releases the old
        // record after this scan.
        addUnit(results, refreshed);
      }
    } else {
      addUnit(results, retainUnitForOneScan(previous, playerPosition, now), previous.key);
    }
  }

  if (discoverNewUnits) {
    const samples = samplePoints(playerPosition, config.maxDistanceM, scanPhase);
    scanPhase = (scanPhase + 1) % 32;
    lastDiscoveryScanAt = now;
    for (const sample of samples) {
      // NO_SAVE is intentional: discovery observes the population without
      // putting ambient peds into script/mission ownership.
      const value = safeNative(
        "GET_RANDOM_CHAR_IN_AREA_OFFSET_NO_SAVE",
        sample.x,
        sample.y,
        sample.z,
        sample.radius,
        sample.radius,
        sample.radius
      );
      const police = toHandle(value, Char);
      if (police) addUnit(results, inspectPolice(police, actor, playerPosition, stars, now));
    }
  }

  const finalUnits = results
    .filter(Boolean)
    .sort(comparePoliceUnits)
    .slice(0, config.maxTrackedUnits);
  const finalKeys = new Set(finalUnits.map((unit) => unit.key));
  for (const previous of previousUnits) {
    if (previous.key && !finalKeys.has(previous.key)) releaseTrackedEntity(previous);
  }
  return finalUnits;
}

function retainUnitForOneScan(previous, playerPosition, now) {
  if (!previous || previous.missedScans >= 1) return null;
  if (!isCharValid(previous.char)) return null;

  const pedPosition = getCoordinates(previous.char, false);
  if (!pedPosition || distanceBetween(pedPosition, playerPosition) > config.maxDistanceM) {
    return null;
  }

  const retained = mergeUnitObservation(previous, {
    ...previous,
    position: pedPosition,
    distance: distanceBetween(pedPosition, playerPosition),
    contact: false,
    seenNow: false,
    spotted: false,
    missedScans: 1,
  }, now);
  return shouldEvictUnit(retained, now) ? null : retained;
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

function inspectPolice(char, actor, playerPosition, stars, now) {
  if (!isCharValid(char)) return null;
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
  const heading = car
    ? finiteNumber(safeNative("GET_CAR_HEADING", car), 0)
    : finiteNumber(safeNative("GET_CHAR_HEADING", char), 0);
  const inFieldOfView = isTargetInHeadingFov(position, heading, playerPosition, POLICE_CONTACT_FOV_DEG);
  const seenNow = lineOfSight && inFieldOfView && spotted;

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
    seenNow,
    contact: seenNow,
    lifecycle: seenNow ? LIFECYCLE_VISIBLE : LIFECYCLE_LOST,
    lastSeenAt: seenNow ? now : 0,
    lastValidAt: now,
    firstSeenAt: now,
    missedScans: 0,
    stars,
  };
}

function mergeUnitObservation(previous, observation, now) {
  if (!observation) return null;
  const seenNow = !!observation.seenNow;
  const lastSeenAt = seenNow ? now : finiteNumber(previous && previous.lastSeenAt, 0);
  const sinceLastSeen = lastSeenAt > 0 ? now - lastSeenAt : Number.POSITIVE_INFINITY;
  const lifecycle = seenNow
    ? LIFECYCLE_VISIBLE
    : sinceLastSeen <= CONTACT_MEMORY_MS
      ? LIFECYCLE_MEMORY
      : LIFECYCLE_LOST;
  return {
    ...observation,
    key: previous && previous.key ? previous.key : observation.key,
    firstSeenAt: previous && previous.firstSeenAt ? previous.firstSeenAt : now,
    lastValidAt: now,
    lastSeenAt,
    seenNow,
    contact: seenNow,
    lifecycle,
    missedScans: observation.missedScans || 0,
  };
}

function isObservationConsistent(previous, current) {
  if (!previous || !current) return false;
  if (previous.pedModel !== current.pedModel) return false;
  if (previous.carModel >= 0 && current.carModel >= 0 && previous.carModel !== current.carModel) {
    return false;
  }
  return distanceBetween(previous.position, current.position) <= Math.max(80, config.maxDistanceM * 0.5);
}

function shouldEvictUnit(unit, now) {
  if (!unit || unit.lifecycle !== LIFECYCLE_LOST) return false;
  const anchor = unit.lastSeenAt || unit.firstSeenAt || now;
  return now - anchor > UNIT_EVICTION_TTL_MS;
}

function isCharValid(char) {
  if (!char) return false;
  const exists = safeNative("DOES_CHAR_EXIST", char);
  if (exists === false) return false;
  return !safeNative("IS_CHAR_DEAD", char);
}

function isTargetInHeadingFov(origin, heading, target, fovDegrees) {
  const dx = target.x - origin.x;
  const dy = target.y - origin.y;
  const distance = Math.sqrt(dx * dx + dy * dy);
  if (distance < 0.001) return true;
  const angle = (finiteNumber(heading, 0) * Math.PI) / 180;
  const forwardX = Math.sin(angle);
  const forwardY = Math.cos(angle);
  const dot = (dx * forwardX + dy * forwardY) / distance;
  return dot >= Math.cos((clamp(fovDegrees, 30, 180) * Math.PI) / 360);
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
    if (!preferredKey) discoveredTotal += 1;
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
  if (left.char === right.char) return left.pedModel === right.pedModel;
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

  const hasContact = currentUnits.some((unit) => unit.seenNow);
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
      x: clamp(size / 1920, 0.045, 0.16),
      y: clamp(size / 1080, 0.06, 0.24),
    },
    rangeM: Math.max(60, config.hudRangeM),
  };
}

function readPlayerHeading(actor) {
  return finiteNumber(safeNative("GET_CHAR_HEADING", actor), 0);
}

function updateRadarModel(playerPosition, playerHeading, currentUnits, now) {
  const geometry = getHudGeometry();
  const visibleUnits = prioritizeUnits(currentUnits)
    .filter((unit) => isTypeEnabled(unit.type))
    .slice(0, config.hudMaxUnits);
  const visibleKeys = new Set();

  for (const unit of visibleUnits) {
    const key = unit.key || "police-model-" + nextUnitKey++;
    const point = radarPoint(unit.position, playerPosition, playerHeading, geometry);
    if (!point) continue;

    const target = {
      x: point.x,
      y: point.y,
      rotation: relativeHeading(unit.heading, playerHeading),
      icon: unit.type,
      state: unit.contact ? "CONTACT" : "TRACKED",
      alpha: point.offRadar ? 0.42 : 0.96,
      offRadar: point.offRadar,
      // These values are part of the presentation contract. The reduced
      // rectangle renderer does not draw a cone, but a future sprite renderer
      // can use them without touching tracking or GTA handles.
      coneRotation: relativeHeading(unit.heading, playerHeading),
      coneScale: clamp(config.coneLengthM / geometry.rangeM, 0.1, 1),
    };
    const transition = radarUnitTransitions.get(key);
    const previous = transition
      ? interpolateRadarUnit(transition, now)
      : target;
    radarUnitTransitions.set(key, {
      previous,
      target,
      updatedAt: now,
      durationMs: Math.max(100, config.scanIntervalMs),
    });
    visibleKeys.add(key);
  }

  for (const [key, transition] of radarUnitTransitions) {
    if (!visibleKeys.has(key) && now - transition.updatedAt > config.scanIntervalMs * 3) {
      radarUnitTransitions.delete(key);
    }
  }

  const search = state === STATE_SEARCHING && lastKnownPlayerPosition
    ? createSearchPresentation(lastKnownPlayerPosition, playerPosition, playerHeading, geometry)
    : null;
  const lastKnown = search ? { x: search.x, y: search.y, alpha: 0.95 } : null;

  radarModelState = {
    timestamp: now,
    geometry,
    player: {
      x: geometry.center.x,
      y: geometry.center.y,
      rotation: config.hudRotateWithPlayer ? 0 : finiteNumber(playerHeading, 0),
    },
    unitKeys: Array.from(visibleKeys),
    search,
    lastKnown,
    status: state,
  };
  radarModel = buildRadarModel(now);
}

function buildRadarModel(now) {
  if (!radarModelState) return null;
  return {
    timestamp: now,
    geometry: radarModelState.geometry,
    player: radarModelState.player,
    units: radarModelState.unitKeys
      .map((key) => {
        const transition = radarUnitTransitions.get(key);
        return transition ? interpolateRadarUnit(transition, now) : null;
      })
      .filter(Boolean),
    search: radarModelState.search,
    lastKnown: radarModelState.lastKnown,
    status: radarModelState.status,
  };
}

function interpolateRadarUnit(transition, now) {
  const duration = Math.max(1, transition.durationMs);
  const progress = clamp((now - transition.updatedAt) / duration, 0, 1);
  const from = transition.previous || transition.target;
  const to = transition.target;
  return {
    x: lerp(from.x, to.x, progress),
    y: lerp(from.y, to.y, progress),
    rotation: interpolateAngle(from.rotation, to.rotation, progress),
    icon: to.icon,
    state: to.state,
    alpha: lerp(from.alpha, to.alpha, progress),
    offRadar: progress < 0.5 ? from.offRadar : to.offRadar,
    coneRotation: interpolateAngle(from.coneRotation, to.coneRotation, progress),
    coneScale: lerp(from.coneScale, to.coneScale, progress),
  };
}

function createSearchPresentation(position, playerPosition, playerHeading, geometry) {
  const point = radarPoint(position, playerPosition, playerHeading, geometry);
  if (!point) return null;
  const radius = getSearchRadius(wantedLevel);
  return {
    x: point.x,
    y: point.y,
    width: clamp((radius / geometry.rangeM) * geometry.radius.x * 2, 0.012, geometry.radius.x * 1.8),
    height: clamp((radius / geometry.rangeM) * geometry.radius.y * 2, 0.016, geometry.radius.y * 1.8),
    alpha: alphaValue(config.searchFillAlpha),
    borderAlpha: alphaValue(config.searchBorderAlpha),
  };
}

function radarPoint(position, playerPosition, playerHeading, geometry) {
  let dx = finiteNumber(position.x, 0) - finiteNumber(playerPosition.x, 0);
  let dy = finiteNumber(position.y, 0) - finiteNumber(playerPosition.y, 0);
  if (config.hudRotateWithPlayer) {
    const angle = (finiteNumber(playerHeading, 0) * Math.PI) / 180;
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
  const limitX = geometry.radius.x * 0.92;
  const limitY = geometry.radius.y * 0.92;
  const outsideX = Math.abs(offsetX) > limitX;
  const outsideY = Math.abs(offsetY) > limitY;
  if (!outsideX && !outsideY) {
    return {
      x: geometry.center.x + offsetX,
      y: geometry.center.y + offsetY,
      offRadar: false,
    };
  }
  if (!config.hudShowOffRadar) return null;
  const scale = Math.max(Math.abs(offsetX) / limitX, Math.abs(offsetY) / limitY, 0.0001);
  return {
    x: geometry.center.x + offsetX / scale,
    y: geometry.center.y + offsetY / scale,
    offRadar: true,
  };
}

function relativeHeading(unitHeading, playerHeading) {
  return normalizeAngle(
    config.hudRotateWithPlayer
      ? finiteNumber(unitHeading, 0) - finiteNumber(playerHeading, 0)
      : finiteNumber(unitHeading, 0)
  );
}

function normalizeAngle(value) {
  let result = finiteNumber(value, 0) % 360;
  if (result < -180) result += 360;
  if (result > 180) result -= 360;
  return result;
}

function interpolateAngle(from, to, progress) {
  return normalizeAngle(normalizeAngle(from) + normalizeAngle(to - from) * progress);
}

function lerp(from, to, progress) {
  return finiteNumber(from, 0) + (finiteNumber(to, 0) - finiteNumber(from, 0)) * progress;
}

function drawHudRadar(model, now) {
  hudFrameDrawCalls = 0;
  hudBudgetExceeded = false;
  const startedAt = readHudClock();

  try {
    if (hudRenderLevel !== HUD_LEVEL_NATIVE_ONLY && hudRenderLevel !== HUD_LEVEL_OFF) {
      renderRectangularRadar(model, hudRenderLevel);
    }
  } finally {
    const elapsed = Math.max(0, readHudClock() - startedAt);
    recordHudRenderTime(elapsed);
    if (elapsed > HUD_RENDER_HARD_BUDGET_MS) {
      degradeHudRenderer("render time " + elapsed.toFixed(2) + " ms");
    }
    if (hudBudgetExceeded && now - lastHudBudgetLogAt >= 5000) {
      lastHudBudgetLogAt = now;
      log(
        "Police Pursuit Radar HUD logical draw budget reached: calls=" +
          hudFrameDrawCalls +
          " budget=" +
          config.hudDrawBudget +
          " units=" +
          model.units.length
      );
    }
  }
}

function renderRectangularRadar(model, level) {
  const geometry = model.geometry;
  const left = geometry.center.x - geometry.radius.x;
  const top = geometry.center.y - geometry.radius.y;
  const width = geometry.radius.x * 2;
  const height = geometry.radius.y * 2;

  // One background primitive replaces the previous 37-row ellipse.
  drawHudRect(
    geometry.center.x,
    geometry.center.y,
    width,
    height,
    0.015,
    0.035,
    0.055,
    alphaValue(config.hudBackgroundAlpha)
  );

  if (level !== HUD_LEVEL_MINIMAL) {
    drawHudRect(geometry.center.x, top, width, 0.0025, 0.18, 0.55, 0.78, alphaValue(config.hudRingAlpha));
    drawHudRect(geometry.center.x, top + height, width, 0.0025, 0.18, 0.55, 0.78, alphaValue(config.hudRingAlpha));
    drawHudRect(left, geometry.center.y, 0.0025, height, 0.18, 0.55, 0.78, alphaValue(config.hudRingAlpha));
    drawHudRect(left + width, geometry.center.y, 0.0025, height, 0.18, 0.55, 0.78, alphaValue(config.hudRingAlpha));
  }

  if (level !== HUD_LEVEL_MINIMAL && model.search) {
    drawHudRect(
      model.search.x,
      model.search.y,
      model.search.width,
      model.search.height,
      1.0,
      0.46,
      0.08,
      model.search.alpha
    );
  }

  if (level !== HUD_LEVEL_MINIMAL && model.lastKnown) {
    drawHudRect(model.lastKnown.x, model.lastKnown.y, 0.008, 0.008, 1.0, 0.62, 0.12, model.lastKnown.alpha);
  }

  const maximumUnits = level === HUD_LEVEL_MINIMAL ? 3 : config.hudMaxUnits;
  for (const unit of model.units.slice(0, maximumUnits)) {
    drawRadarUnitMarker(unit, geometry);
  }

  // The player marker is intentionally one primitive. Direction is retained
  // in model.player.rotation for the future sprite renderer.
  drawHudRect(
    model.player.x,
    model.player.y,
    geometry.radius.x * 0.10,
    geometry.radius.y * 0.10,
    0.86,
    0.96,
    1.0,
    1.0
  );
}

function drawRadarUnitMarker(unit, geometry) {
  const color = radarUnitColor(unit);
  const base = unit.offRadar ? 0.70 : 1.0;
  const sizeX = geometry.radius.x * (unit.icon === "helicopter" ? 0.090 : 0.065);
  const sizeY = geometry.radius.y * (unit.icon === "helicopter" ? 0.075 : 0.055);
  drawHudRect(unit.x, unit.y, sizeX, sizeY, color.r, color.g, color.b, base * unit.alpha);
}

function radarUnitColor(unit) {
  if (unit.state === "CONTACT") return { r: 1.0, g: 0.16, b: 0.10 };
  if (unit.icon === "helicopter") return { r: 0.42, g: 1.0, b: 0.76 };
  if (unit.icon === "boat") return { r: 0.24, g: 0.72, b: 1.0 };
  if (unit.icon === "bike") return { r: 0.88, g: 0.42, b: 1.0 };
  return { r: 0.30, g: 0.72, b: 1.0 };
}

function readHudClock() {
  if (typeof performance !== "undefined" && performance && typeof performance.now === "function") {
    return performance.now();
  }
  return Date.now();
}

function recordHudRenderTime(elapsed) {
  hudRenderSamples.push(elapsed);
  if (hudRenderSamples.length > HUD_PERF_SAMPLE_LIMIT) hudRenderSamples.shift();
  const ordered = hudRenderSamples.slice().sort((left, right) => left - right);
  hudRenderAverageMs = ordered.reduce((sum, value) => sum + value, 0) / ordered.length;
  hudRenderP95Ms = ordered[Math.max(0, Math.ceil(ordered.length * 0.95) - 1)];
  hudRenderMaxMs = ordered[ordered.length - 1];
}

function degradeHudRenderer(reason) {
  const previous = hudRenderLevel;
  if (hudRenderLevel === HUD_LEVEL_FULL) hudRenderLevel = HUD_LEVEL_REDUCED;
  else if (hudRenderLevel === HUD_LEVEL_REDUCED) hudRenderLevel = HUD_LEVEL_MINIMAL;
  else if (hudRenderLevel === HUD_LEVEL_MINIMAL) hudRenderLevel = HUD_LEVEL_NATIVE_ONLY;
  else if (hudRenderLevel === HUD_LEVEL_NATIVE_ONLY) hudRenderLevel = HUD_LEVEL_OFF;
  if (previous !== hudRenderLevel) {
    log("Police Pursuit Radar HUD degraded: " + previous + " -> " + hudRenderLevel + " (" + reason + ").");
  }
  if (hudRenderLevel === HUD_LEVEL_OFF) hudPermanentlyDisabled = true;
}

function prioritizeUnits(currentUnits) {
  return currentUnits.slice().sort(comparePoliceUnits);
}

function alphaValue(percent) {
  return clamp(finiteNumber(percent, 0), 0, 100) / 100;
}

function drawHudRect(x, y, width, height, r, g, b, a) {
  if (hudFrameDrawCalls >= config.hudDrawBudget) {
    hudBudgetExceeded = true;
    return;
  }
  hudFrameDrawCalls += 1;
  // Hud.DrawRect expects the game's 640x448 virtual screen. Passing the
  // normalized 0..1 model directly produced sub-pixel geometry and was the
  // material difference from stable CLEO Redux HUD implementations.
  Hud.DrawRect(
    clamp(finiteNumber(x, 0), 0, 1) * HUD_VIRTUAL_WIDTH,
    clamp(finiteNumber(y, 0), 0, 1) * HUD_VIRTUAL_HEIGHT,
    Math.max(1, finiteNumber(width, 0.001) * HUD_VIRTUAL_WIDTH),
    Math.max(1, finiteNumber(height, 0.001) * HUD_VIRTUAL_HEIGHT),
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
  const now = Date.now();
  if (!config.showNativeBlips || wantedLevel <= 0 || state === STATE_ESCAPED) {
    clearBlips();
    logRegistryStats(currentUnits, now);
    return;
  }

  const nativeUnits = prioritizeUnits(currentUnits)
    .filter((unit) => isTypeEnabled(unit.type))
    .filter((unit) => isContactBlipEligible(unit, now))
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
  logRegistryStats(currentUnits, now);
}

function isContactBlipEligible(unit, now) {
  if (!unit) return false;
  if (unit.seenNow) return true;
  return (
    unit.lifecycle === LIFECYCLE_MEMORY &&
    unit.lastSeenAt > 0 &&
    now - unit.lastSeenAt <= CONTACT_MEMORY_MS
  );
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
  const color = unit.seenNow || unit.lifecycle === LIFECYCLE_MEMORY
    ? BLIP_COLOR_RED
    : BLIP_COLOR_BLUE;
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

function releaseTrackedEntity(unit) {
  if (!unit) return;
  // Discovery uses *_NO_SAVE and therefore never takes script ownership of
  // ambient peds or vehicles. Calling MARK_* here can release an entity owned
  // by the game while another system is still using it. Dropping our wrapper
  // and its blips is the complete cleanup for a read-only observation.
  evictedTotal += 1;
}

function releaseTrackedUnits(trackedUnits) {
  for (const unit of trackedUnits || []) releaseTrackedEntity(unit);
}

function logRegistryStats(currentUnits, now) {
  if (!config.debug || now - lastRegistryLogAt < 10000) return;
  lastRegistryLogAt = now;
  const visible = currentUnits.filter((unit) => unit.lifecycle === LIFECYCLE_VISIBLE).length;
  const memory = currentUnits.filter((unit) => unit.lifecycle === LIFECYCLE_MEMORY).length;
  const lost = currentUnits.filter((unit) => unit.lifecycle === LIFECYCLE_LOST).length;
  log(
    "Police Pursuit Radar registry: registry=" +
      currentUnits.length +
      " visible=" +
      visible +
      " memory=" +
      memory +
      " lost=" +
      lost +
      " nativeBlips=" +
      unitBlips.length +
      " directionBlips=" +
      unitBlips.filter((record) => !!record.directionBlip).length +
      " discoveredTotal=" +
      discoveredTotal +
      " evictedTotal=" +
      evictedTotal +
      " wanted=" +
      wantedLevel +
      " contact=" +
      currentUnits.some((unit) => unit.seenNow) +
      " state=" +
      state
  );
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
    const requestedHudEnabled = updateConfigValue("hud", "enabled", DEFAULTS.hudEnabled ? 1 : 0) !== 0;
    config.hudEnabled = CUSTOM_HUD_RENDERER_AVAILABLE && requestedHudEnabled;
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
    config.hudDrawBudget = clamp(updateConfigValue("hud", "draw_budget", DEFAULTS.hudDrawBudget), 8, 24);
    config.debug = updateConfigValue("visual", "debug", DEFAULTS.debug ? 1 : 0) !== 0;
    config.reloadHotkeyEnabled = updateConfigValue("input", "reload_hotkey_enabled", DEFAULTS.reloadHotkeyEnabled ? 1 : 0) !== 0;
    hudFaultedUntil = 0;
    hudErrorCount = 0;
    hudPermanentlyDisabled = false;
    resetHudPresentationState();
    log("Police Pursuit Radar configuration loaded.");
  } catch (_) {
    log("Police Pursuit Radar: config load failed; using defaults.");
  }
}

function resetRuntimeState() {
  clearBlips();
  releaseTrackedUnits(units);
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
  discoveredTotal = 0;
  evictedTotal = 0;
  lastRegistryLogAt = 0;
  resetHudPresentationState();
}

function resetHudPresentationState() {
  radarModel = null;
  radarModelState = null;
  radarUnitTransitions.clear();
  hudRenderLevel = HUD_LEVEL_REDUCED;
  hudRenderSamples = [];
  hudRenderAverageMs = 0;
  hudRenderP95Ms = 0;
  hudRenderMaxMs = 0;
  hudFrameDrawCalls = 0;
  hudBudgetExceeded = false;
  lastHudBudgetLogAt = 0;
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
