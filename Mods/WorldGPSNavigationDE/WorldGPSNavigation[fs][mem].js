/// <reference path="./.config/sa.d.ts" />

// World GPS Navigation DE for GTA San Andreas: The Definitive Edition.
// Runtime: CLEO Redux x64 + IniFiles64.
//
// The script deliberately uses the public SA:DE scripting surface. It does
// not write vehicle tasks, change the minimap, patch UE4 memory, or pretend
// that a straight line is a road route. The route is a short, continuously
// rebuilt guide made from the game's nearest car-path nodes.

if (typeof HOST === "undefined" || HOST !== "sa_unreal") {
  exit("World GPS Navigation DE supports only GTA San Andreas: The Definitive Edition.");
}

const PLAYER_ID = 0;
const CONFIG_PATH = "./WorldGPSNavigationDE.ini";
const CONFIG_VERSION = 1;

const VK_F7 = 118;
const VK_F11 = 122;

const ROUTE_SETTLE_MS = 1500;
const ROUTE_REBUILD_MIN_MS = 450;
// IS_CHAR_IN_ANY_CAR becomes true during the door/enter animation on SA:DE.
// Do not touch the vehicle handle until the seated state has been stable for
// several frames; invalid native handles can terminate the game process before
// a JavaScript try/catch gets a chance to run.
const VEHICLE_STABILITY_DELAY_MS = 500;
const VEHICLE_CONTEXT_MAX_DISTANCE_M = 30;
const MAX_MARKERS = 14;
const WAYPOINT_POLL_INTERVAL_MS = 250;
const SUPPORTED_HOST_VERSION = "1.0.113.21181";
const SADE_MAIN_SCRIPT_SIGNATURE_OFFSET = 0x51BEAE0 + 0xF1A8;
const SADE_RADAR_TRACE_OFFSET = 0x542A7B0;
const SADE_RADAR_TRACE_COUNT = 250;
const SADE_RADAR_TRACE_STRIDE = 0x30;
const SADE_RADAR_TRACE_POSITION_OFFSET = 0x08;
const SADE_RADAR_TRACE_SPRITE_OFFSET = 0x28;
const SADE_RADAR_TRACE_FLAGS_OFFSET = 0x29;
const SADE_WAYPOINT_SPRITE = 0x40;
const SADE_RADAR_TRACE_IN_USE_FLAG = 0x02;

const DEFAULTS = {
  enabled: true,
  hideWhenOnFoot: true,
  baseVisibleDistanceM: 62,
  maxVisibleDistanceM: 128,
  speedDistanceGainMPerKmh: 0.38,
  markerSpacingM: 9,
  routeRebuildIntervalMs: 700,
  rebuildDistanceM: 8,
  showDestinationMarker: true,
  showDistanceText: true,
  useManualTarget: false,
  manualTargetX: 0,
  manualTargetY: 0,
  manualTargetZ: 0,
  reloadHotkeyEnabled: true,
  debug: false,
};

const config = { ...DEFAULTS };
const player = new Player(PLAYER_ID);
const nativeFailureCounts = new Map();
const optionalNativeState = new Map();
let waypointMemorySupported = false;
let waypointMemoryUnavailableLogged = false;
let waypointMemoryFailureLogged = false;
let cachedWaypoint = null;
let lastWaypointPollAt = 0;

let lastReloadDown = false;
let lastManualTargetDown = false;
let gameplayDetectedAt = 0;
let lastRouteBuildAt = 0;
let lastRoutePosition = null;
let lastWaypointKey = null;
let route = null;
let worldMarkers = [];
let lastFrameFailureAt = 0;
let vehicleStableSince = 0;

loadConfig();
waypointMemorySupported = detectWaypointMemorySupport();
log("World GPS Navigation DE loaded. F7 captures a manual target when enabled; F11 reloads the INI.");

while (true) {
  wait(0);
  const now = Date.now();

  if (config.reloadHotkeyEnabled) {
    const reloadDown = isKeyPressed(VK_F11);
    if (reloadDown && !lastReloadDown) {
      loadConfig();
      clearRoute();
      log("World GPS Navigation DE configuration reloaded.");
    }
    lastReloadDown = reloadDown;
  }

  const actor = getPlayerActor();
  if (!actor) {
    if (worldMarkers.length > 0) clearRoute();
    vehicleStableSince = 0;
    gameplayDetectedAt = 0;
    continue;
  }

  if (gameplayDetectedAt === 0) {
    gameplayDetectedAt = now;
    lastRouteBuildAt = now;
  }

  if (!config.enabled || now - gameplayDetectedAt < ROUTE_SETTLE_MS) {
    clearRoute();
    continue;
  }

  if (config.useManualTarget) {
    const manualDown = isKeyPressed(VK_F7);
    if (manualDown && !lastManualTargetDown) {
      const captured = readVehicleContext(actor, now);
      if (captured) {
        const manualTarget = add(captured.position, scale(captured.forward, 60));
        config.manualTargetX = manualTarget.x;
        config.manualTargetY = manualTarget.y;
        config.manualTargetZ = manualTarget.z;
        log("World GPS Navigation: manual target captured 60 m ahead at " + formatPosition(manualTarget));
        clearRoute();
      }
    }
    lastManualTargetDown = manualDown;
  } else {
    lastManualTargetDown = false;
  }

  try {
    const context = readVehicleContext(actor, now);
    if (!context) {
      if (config.hideWhenOnFoot) clearRoute();
      continue;
    }

    const target = readWaypoint(now);
    if (!target) {
      clearRoute();
      continue;
    }

    const targetKey = waypointKey(target);
    const moved = !lastRoutePosition || distance2D(context.position, lastRoutePosition) >= config.rebuildDistanceM;
    const targetChanged = targetKey !== lastWaypointKey;
    const routeExpired = now - lastRouteBuildAt >= config.routeRebuildIntervalMs;

    if (!route || targetChanged || moved && routeExpired || now - lastRouteBuildAt >= ROUTE_REBUILD_MIN_MS && routeExpired) {
      const nextRoute = buildRoute(context, target);
      if (nextRoute) {
        replaceRoute(nextRoute);
        lastRouteBuildAt = now;
        lastRoutePosition = { ...context.position };
        lastWaypointKey = targetKey;
      } else {
        clearRoute();
      }
    }

    if (route) drawRouteText(route);
  } catch (error) {
    if (now - lastFrameFailureAt >= 1000) {
      lastFrameFailureAt = now;
      log("World GPS Navigation DE: frame recovered from error: " + error);
    }
    clearRoute();
  }
}

function getPlayerActor() {
  try {
    if (!player.isPlaying()) return null;
    const actor = player.getChar();
    if (!actor || safeNative("IS_CHAR_DEAD", actor) === true) return null;
    return actor;
  } catch (_) {
    return null;
  }
}

function readVehicleContext(actor, now) {
  const onFoot = safeNative("IS_CHAR_ON_FOOT", actor);
  if (onFoot === true || onFoot === 1) {
    vehicleStableSince = 0;
    return null;
  }

  if (safeNative("IS_CHAR_IN_ANY_CAR", actor) !== true) {
    vehicleStableSince = 0;
    return null;
  }

  // The broad vehicle-interaction native is also true while the ped is
  // opening/closing a door. Require the authoritative seated native and a
  // short continuous stability window before obtaining the Car wrapper.
  const sitting = safeNative("IS_CHAR_SITTING_IN_ANY_CAR", actor);
  if (sitting !== true && sitting !== 1) {
    vehicleStableSince = 0;
    return null;
  }

  if (vehicleStableSince === 0) vehicleStableSince = now;
  if (now - vehicleStableSince < VEHICLE_STABILITY_DELAY_MS) return null;

  const rawVehicle = safeNative("STORE_CAR_CHAR_IS_IN_NO_SAVE", actor);
  const vehicle = toHandle(rawVehicle, typeof Car === "undefined" ? null : Car);
  if (!vehicle) return null;

  const actorPosition = readCoordinates(actor, false);
  const position = readCoordinates(vehicle, true);
  if (!isSaneVehicleContext(position, actorPosition)) return null;

  const heading = finiteNumber(safeNative("GET_CAR_HEADING", vehicle), 0);
  const rawSpeed = finiteNumber(safeNative("GET_CAR_SPEED", vehicle), 0);
  const speedKmh = clamp(Math.abs(rawSpeed) * 3.6, 0, 260);

  return {
    vehicle,
    position,
    heading,
    speedKmh,
    forward: headingVector(heading),
  };
}

function readWaypoint(now) {
  if (config.useManualTarget) {
    const manual = {
      x: Number(config.manualTargetX),
      y: Number(config.manualTargetY),
      z: Number(config.manualTargetZ),
    };
    if (isVector(manual) && Math.abs(manual.x) + Math.abs(manual.y) > 0.01) {
      return { ...manual, source: "manual" };
    }
    return null;
  }

  if (!waypointMemorySupported) return null;
  if (now - lastWaypointPollAt >= WAYPOINT_POLL_INTERVAL_MS) {
    lastWaypointPollAt = now;
    cachedWaypoint = readWaypointFromMemory();
  }
  return cachedWaypoint ? { ...cachedWaypoint } : null;
}

function detectWaypointMemorySupport() {
  if (typeof Memory === "undefined" || typeof Memory.ReadU8 !== "function" || typeof Memory.ReadFloat !== "function") {
    logWaypointMemoryUnavailable("CLEO memory access is unavailable; the map waypoint cannot be read.");
    return false;
  }

  const hostVersion = typeof CLEO !== "undefined" ? String(CLEO.hostVersion || "") : "";
  if (hostVersion !== SUPPORTED_HOST_VERSION) {
    logWaypointMemoryUnavailable("map waypoint reading is enabled only for SA:DE " + SUPPORTED_HOST_VERSION + " (current build: " + (hostVersion || "unknown") + ").");
    return false;
  }

  try {
    const expected = [0xA4, 0x03, 0x09, 0x4D, 0x41, 0x49, 0x4E];
    for (let index = 0; index < expected.length; index += 1) {
      const actual = Memory.ReadU8(SADE_MAIN_SCRIPT_SIGNATURE_OFFSET + index, false, true);
      if (actual !== expected[index]) {
        logWaypointMemoryUnavailable("the game memory signature does not match the supported SA:DE build.");
        return false;
      }
    }
    log("World GPS Navigation: SA:DE waypoint memory layout verified for " + SUPPORTED_HOST_VERSION + ".");
    return true;
  } catch (error) {
    logWaypointMemoryUnavailable("the game memory signature could not be checked: " + error);
    return false;
  }
}

function logWaypointMemoryUnavailable(reason) {
  if (waypointMemoryUnavailableLogged) return;
  waypointMemoryUnavailableLogged = true;
  log("World GPS Navigation: " + reason + " Route markers remain hidden for safety.");
}

function readWaypointFromMemory() {
  try {
    for (let index = 0; index < SADE_RADAR_TRACE_COUNT; index += 1) {
      const trace = SADE_RADAR_TRACE_OFFSET + index * SADE_RADAR_TRACE_STRIDE;
      const sprite = Memory.ReadU8(trace + SADE_RADAR_TRACE_SPRITE_OFFSET, false, true);
      if (sprite !== SADE_WAYPOINT_SPRITE) continue;

      const flags = Memory.ReadU8(trace + SADE_RADAR_TRACE_FLAGS_OFFSET, false, true);
      if ((flags & SADE_RADAR_TRACE_IN_USE_FLAG) === 0) continue;

      const target = {
        x: Memory.ReadFloat(trace + SADE_RADAR_TRACE_POSITION_OFFSET, false, true),
        y: Memory.ReadFloat(trace + SADE_RADAR_TRACE_POSITION_OFFSET + 4, false, true),
        // SA:DE keeps a placeholder height for a player waypoint. Resolve the
        // destination to the ground below instead of drawing it at that height.
        z: 0,
        source: "SA:DE map waypoint",
      };
      if (!hasWorldCoordinate(target)) continue;
      target.z = resolveGroundZ(target);
      return target;
    }
  } catch (error) {
    waypointMemorySupported = false;
    cachedWaypoint = null;
    if (!waypointMemoryFailureLogged) {
      waypointMemoryFailureLogged = true;
      log("World GPS Navigation: waypoint memory read failed; memory-based guidance disabled for safety: " + error);
    }
  }
  return null;
}

function buildRoute(context, target) {
  const distanceToTarget = distance2D(context.position, target);
  if (!Number.isFinite(distanceToTarget) || distanceToTarget < 2) return null;

  const visibleDistance = clamp(
    config.baseVisibleDistanceM + context.speedKmh * config.speedDistanceGainMPerKmh,
    30,
    config.maxVisibleDistanceM
  );
  const activeDistance = Math.min(visibleDistance, distanceToTarget);
  const routeEnd = distanceToTarget <= visibleDistance
    ? { ...target }
    : add(context.position, scale(normalize2D(subtract(target, context.position)), activeDistance));
  const start = add(context.position, scale(context.forward, 7));
  const span = Math.max(12, distance2D(start, routeEnd));
  const sampleCount = clamp(Math.ceil(span / config.markerSpacingM), 4, MAX_MARKERS - 1);
  const points = [{ ...context.position, kind: "origin" }];

  for (let index = 1; index <= sampleCount; index += 1) {
    const ratio = index / sampleCount;
    const sample = lerp(start, routeEnd, ratio);
    const point = {
      ...sample,
      z: resolveGroundZ(sample),
      kind: "direct",
    };

    const previous = points[points.length - 1];
    if (distance2D(point, previous) >= Math.max(3, config.markerSpacingM * 0.45)) {
      points.push(point);
    }
  }

  if (distance2D(points[points.length - 1], target) <= Math.max(5, config.markerSpacingM * 1.2)) {
    points.push({ ...target, z: resolveGroundZ(target), kind: "destination" });
  }

  const visiblePoints = points.slice(1, MAX_MARKERS);
  if (visiblePoints.length === 0) return null;

  return {
    points: visiblePoints,
    target,
    targetDistanceM: distanceToTarget,
    visibleDistanceM: activeDistance,
  };
}

function replaceRoute(nextRoute) {
  clearWorldMarkers();
  route = nextRoute;

  for (let index = 0; index < route.points.length; index += 1) {
    const point = route.points[index];
    const isDestination = point.kind === "destination" || index === route.points.length - 1 && route.targetDistanceM <= route.visibleDistanceM + 4;
    if (isDestination && !config.showDestinationMarker) continue;

    const color = isDestination ? "Yellow" : index < 3 ? "Blue" : "BlueDark";
    const marker = createWorldMarker(point, color);
    if (marker) worldMarkers.push(marker);
  }

  if (config.debug) {
    log("World GPS Navigation guidance rebuilt: points=" + route.points.length + " source=" + route.target.source + " targetDistanceM=" + Math.round(route.targetDistanceM));
  }
}

function drawRouteText(currentRoute) {
  if (!config.showDistanceText) return;
  if (typeof FxtStore === "undefined" || typeof FxtStore.insert !== "function") return;

  try {
    let text = "";
    if (config.showDistanceText) text += "GPS " + formatDistance(currentRoute.targetDistanceM);
    if (!text) return;

    FxtStore.insert("WGPSINF", text);
    safeNative("SET_TEXT_FONT", 1);
    safeNative("SET_TEXT_SCALE", 0.34, 0.34);
    safeNative("SET_TEXT_COLOUR", 116, 224, 238, 220);
    safeNative("SET_TEXT_PROPORTIONAL", true);
    safeNative("SET_TEXT_BACKGROUND", false);
    safeNative("SET_TEXT_EDGE", 1, 0, 0, 0, 170);
    safeNative("SET_TEXT_CENTRE", true);
    safeNative("SET_TEXT_JUSTIFY", false);
    safeNative("SET_TEXT_RIGHT_JUSTIFY", false);
    safeNative("SET_TEXT_DROPSHADOW", 1, 0, 0, 0, 180);
    safeNative("DISPLAY_TEXT", 320, 32, "WGPSINF");
  } catch (error) {
    if (config.debug) log("World GPS Navigation text failed: " + error);
  }
}

function createWorldMarker(point, color) {
  try {
    if (typeof User3DMarker !== "undefined" && typeof User3DMarker.Create === "function") {
      return User3DMarker.Create(point.x, point.y, point.z + 0.25, color);
    }
  } catch (_) {}

  const result = optionalNative("CREATE_USER_3D_MARKER", point.x, point.y, point.z + 0.25, color);
  return result.ok ? result.value : null;
}

function clearWorldMarkers() {
  for (const marker of worldMarkers) {
    if (!marker) continue;
    try {
      if (typeof marker.remove === "function") {
        marker.remove();
        continue;
      }
    } catch (_) {}
    optionalNative("REMOVE_USER_3D_MARKER", marker);
  }
  worldMarkers = [];
}

function clearRoute() {
  clearWorldMarkers();
  route = null;
  lastRoutePosition = null;
  lastWaypointKey = null;
}

function optionalNative(name, ...args) {
  const state = optionalNativeState.get(name);
  if (state === "unsupported") return { ok: false, value: null };

  try {
    const value = native(name, ...args);
    optionalNativeState.set(name, "supported");
    return { ok: true, value };
  } catch (error) {
    optionalNativeState.set(name, "unsupported");
    if (config.debug) log("World GPS Navigation optional native unavailable: " + name + " " + error);
    return { ok: false, value: null };
  }
}

function safeNative(name, ...args) {
  try {
    return native(name, ...args);
  } catch (error) {
    const count = (nativeFailureCounts.get(name) || 0) + 1;
    nativeFailureCounts.set(name, count);
    if (config.debug && count === 1) log("World GPS Navigation native failure: " + name + " " + error);
    return null;
  }
}

function loadConfig() {
  if (typeof IniFile === "undefined" || typeof IniFile.ReadInt !== "function") {
    log("World GPS Navigation DE: IniFiles64 unavailable; using defaults.");
    return;
  }

  try {
    const version = readConfigInt("meta", "config_version", CONFIG_VERSION);
    if (version !== CONFIG_VERSION) {
      log("World GPS Navigation DE: unsupported INI version; using defaults.");
      return;
    }

    config.enabled = readConfigBool("mod", "enabled", DEFAULTS.enabled);
    config.hideWhenOnFoot = readConfigBool("mod", "hide_when_on_foot", DEFAULTS.hideWhenOnFoot);
    config.baseVisibleDistanceM = clamp(readConfigInt("route", "base_visible_distance_m", DEFAULTS.baseVisibleDistanceM), 30, 100);
    config.maxVisibleDistanceM = clamp(readConfigInt("route", "max_visible_distance_m", DEFAULTS.maxVisibleDistanceM), 40, 180);
    config.speedDistanceGainMPerKmh = clamp(readConfigInt("route", "speed_distance_gain_m_per_kmh_x100", DEFAULTS.speedDistanceGainMPerKmh * 100) / 100, 0, 2);
    config.markerSpacingM = clamp(readConfigInt("route", "marker_spacing_m", DEFAULTS.markerSpacingM), 5, 18);
    config.routeRebuildIntervalMs = clamp(readConfigInt("route", "rebuild_interval_ms", DEFAULTS.routeRebuildIntervalMs), 300, 3000);
    config.rebuildDistanceM = clamp(readConfigInt("route", "rebuild_distance_m", DEFAULTS.rebuildDistanceM), 3, 30);
    config.showDestinationMarker = readConfigBool("visual", "show_destination_marker", DEFAULTS.showDestinationMarker);
    config.showDistanceText = readConfigBool("visual", "show_distance_text", DEFAULTS.showDistanceText);
    config.useManualTarget = readConfigBool("manual_target", "enabled", DEFAULTS.useManualTarget);
    config.manualTargetX = readConfigInt("manual_target", "x", DEFAULTS.manualTargetX);
    config.manualTargetY = readConfigInt("manual_target", "y", DEFAULTS.manualTargetY);
    config.manualTargetZ = readConfigInt("manual_target", "z", DEFAULTS.manualTargetZ);
    config.reloadHotkeyEnabled = readConfigBool("input", "reload_hotkey_enabled", DEFAULTS.reloadHotkeyEnabled);
    config.debug = readConfigBool("debug", "enabled", DEFAULTS.debug);
  } catch (error) {
    log("World GPS Navigation DE: configuration read failed; using defaults: " + error);
  }
}

function readConfigInt(section, key, fallback) {
  try {
    const value = Number(IniFile.ReadInt(CONFIG_PATH, section, key));
    return Number.isFinite(value) ? value : fallback;
  } catch (_) {
    return fallback;
  }
}

function readConfigBool(section, key, fallback) {
  return readConfigInt(section, key, fallback ? 1 : 0) !== 0;
}

function isKeyPressed(keyCode) {
  try {
    if (typeof Pad !== "undefined" && typeof Pad.IsKeyPressed === "function") {
      return !!Pad.IsKeyPressed(keyCode);
    }
  } catch (_) {}
  return safeNative("IS_KEY_PRESSED", keyCode) === true;
}

function readCoordinates(entity, vehicle) {
  const result = safeNative(vehicle ? "GET_CAR_COORDINATES" : "GET_CHAR_COORDINATES", entity);
  return normalizeVector(result);
}

function resolveGroundZ(point) {
  const result = safeNative("GET_GROUND_Z_FOR_3D_COORD", point.x, point.y, 1000);
  if (result !== null && result !== undefined && typeof result !== "boolean" && Number.isFinite(Number(result))) {
    return Number(result);
  }
  if (result && Number.isFinite(Number(result.groundZ))) return Number(result.groundZ);
  return Number(point.z) || 0;
}

function toHandle(value, Constructor) {
  if (value === null || value === undefined || value === false || value === -1 || value === 0) return null;
  if (typeof value === "object") return value;
  if (!Constructor) return null;
  try {
    return new Constructor(value);
  } catch (_) {
    return null;
  }
}

function isSaneVehicleContext(vehiclePosition, actorPosition) {
  if (!isVector(vehiclePosition) || !isVector(actorPosition)) return false;

  // A stale/invalid vehicle wrapper commonly resolves to the world origin.
  // Never let that become the navigation anchor while CJ is elsewhere.
  const vehicleNearOrigin = Math.sqrt(
    vehiclePosition.x * vehiclePosition.x +
    vehiclePosition.y * vehiclePosition.y +
    vehiclePosition.z * vehiclePosition.z
  ) < 0.75;
  const actorNearOrigin = Math.sqrt(
    actorPosition.x * actorPosition.x +
    actorPosition.y * actorPosition.y +
    actorPosition.z * actorPosition.z
  ) < 4;
  if (vehicleNearOrigin && !actorNearOrigin) return false;

  return distance3D(vehiclePosition, actorPosition) <= VEHICLE_CONTEXT_MAX_DISTANCE_M;
}

function normalizeVector(value) {
  if (isVector(value)) return { x: Number(value.x), y: Number(value.y), z: Number(value.z) };
  if (value && isVector(value.position)) return normalizeVector(value.position);
  if (value && isVector(value.coordinates)) return normalizeVector(value.coordinates);
  return null;
}

function isVector(value) {
  return !!value && Number.isFinite(Number(value.x)) && Number.isFinite(Number(value.y)) && Number.isFinite(Number(value.z));
}

function hasWorldCoordinate(value) {
  return isVector(value) && Math.abs(value.x) + Math.abs(value.y) > 0.01 && Math.abs(value.x) < 100000 && Math.abs(value.y) < 100000;
}

function waypointKey(target) {
  return [target.x, target.y, target.z].map((value) => Math.round(Number(value) * 2) / 2).join(":");
}

function headingVector(degrees) {
  const radians = degrees * Math.PI / 180;
  return { x: Math.sin(radians), y: Math.cos(radians), z: 0 };
}

function formatPosition(position) {
  return Number(position.x).toFixed(1) + "," + Number(position.y).toFixed(1) + "," + Number(position.z).toFixed(1);
}

function formatDistance(distance) {
  const value = Math.max(0, Math.round(Number(distance)));
  return value >= 1000 ? (value / 1000).toFixed(1) + "km" : value + "m";
}

function add(left, right) {
  return { x: left.x + right.x, y: left.y + right.y, z: left.z + right.z };
}

function subtract(left, right) {
  return { x: left.x - right.x, y: left.y - right.y, z: left.z - right.z };
}

function scale(value, multiplier) {
  return { x: value.x * multiplier, y: value.y * multiplier, z: value.z * multiplier };
}

function lerp(left, right, ratio) {
  return {
    x: left.x + (right.x - left.x) * ratio,
    y: left.y + (right.y - left.y) * ratio,
    z: left.z + (right.z - left.z) * ratio,
  };
}

function normalize2D(value) {
  const length = length2D(value);
  if (length < 0.001) return { x: 0, y: 0, z: 0 };
  return { x: value.x / length, y: value.y / length, z: 0 };
}

function length2D(value) {
  return Math.sqrt(value.x * value.x + value.y * value.y);
}

function distance2D(left, right) {
  return length2D(subtract(left, right));
}

function distance3D(left, right) {
  const x = left.x - right.x;
  const y = left.y - right.y;
  const z = left.z - right.z;
  return Math.sqrt(x * x + y * y + z * z);
}

function finiteNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}
