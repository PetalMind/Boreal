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

const DEFAULTS = {
  enabled: true,
  hideWhenOnFoot: true,
  baseVisibleDistanceM: 62,
  maxVisibleDistanceM: 128,
  speedDistanceGainMPerKmh: 0.38,
  markerSpacingM: 9,
  routeRebuildIntervalMs: 700,
  rebuildDistanceM: 8,
  maxNodeSearchDistanceM: 32,
  nodeSearchCount: 5,
  showDestinationMarker: true,
  showTurnText: true,
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

let lastReloadDown = false;
let lastManualTargetDown = false;
let gameplayDetectedAt = 0;
let lastRouteBuildAt = 0;
let lastRoutePosition = null;
let lastWaypointKey = null;
let route = null;
let worldMarkers = [];
let waypointCapabilityWarningLogged = false;
let lastFrameFailureAt = 0;
let vehicleStableSince = 0;

loadConfig();
log("World GPS Navigation DE loaded. F7 captures the current vehicle position as a manual target; F11 reloads the INI.");

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

    const target = readWaypoint();
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

function readWaypoint() {
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

  let activeResult = optionalNative("IS_WAYPOINT_ACTIVE");
  if (!activeResult.ok) activeResult = optionalNative("IS_WAYPOINT_ACTIVE_FOR_PLAYER", PLAYER_ID);
  if (activeResult.ok && !truthyNativeValue(activeResult.value)) return null;

  const coordinateNames = ["GET_WAYPOINT_COORDS", "_GET_WAYPOINT_COORDS"];
  for (const name of coordinateNames) {
    const result = optionalNative(name);
    const coordinates = normalizeVector(result.value);
    if (result.ok && coordinates && hasWorldCoordinate(coordinates)) {
      return { ...coordinates, source: name };
    }
  }

  // Some hosts expose the selected map point as a regular coordinate blip.
  // These calls are optional because the current public SA:DE definition file
  // does not list the GTA V-style blip enumeration natives.
  const blip = readWaypointBlip();
  if (blip) return { ...blip, source: "blip" };

  if (!waypointCapabilityWarningLogged) {
    waypointCapabilityWarningLogged = true;
    log("World GPS Navigation: no public SA:DE waypoint getter is available in this CLEO runtime; route markers remain hidden until the waypoint bridge is exposed.");
  }
  return null;
}

function readWaypointBlip() {
  const spriteCandidates = [8, 0];
  for (const sprite of spriteCandidates) {
    const first = optionalNative("GET_FIRST_BLIP_INFO_ID", sprite);
    if (!first.ok || !first.value) continue;

    const coordinates = normalizeVector(optionalNative("GET_BLIP_INFO_ID_COORD", first.value).value);
    if (coordinates && hasWorldCoordinate(coordinates)) return coordinates;
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
  let previous = start;
  let usedRoadNodes = 0;

  for (let index = 1; index <= sampleCount; index += 1) {
    const ratio = index / sampleCount;
    const sample = lerp(start, routeEnd, ratio);
    const roadNode = findRoadNode(sample, previous, context.forward);
    const candidate = roadNode || sample;
    const point = {
      ...candidate,
      z: resolveGroundZ(candidate),
      kind: roadNode ? "road" : "direct",
    };

    if (roadNode) usedRoadNodes += 1;
    if (distance2D(point, previous) >= Math.max(3, config.markerSpacingM * 0.45)) {
      points.push(point);
      previous = point;
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
    usedRoadNodes,
    nextTurn: findNextTurn(points),
  };
}

function findRoadNode(sample, previous, forward) {
  let best = null;
  let bestScore = Number.POSITIVE_INFINITY;
  const searchCount = clamp(Math.round(config.nodeSearchCount), 1, 8);

  for (let index = 0; index < searchCount; index += 1) {
    const value = safeNative("GET_NTH_CLOSEST_CAR_NODE", sample.x, sample.y, sample.z, index);
    const candidate = normalizeVector(value);
    if (!candidate || !hasWorldCoordinate(candidate)) continue;

    const fromPrevious = distance2D(candidate, previous);
    if (fromPrevious > config.maxNodeSearchDistanceM * 2.2) continue;

    const progress = dot2D(subtract(candidate, previous), forward);
    const sampleDistance = distance2D(candidate, sample);
    const backwardsPenalty = progress < -2 ? 18 : 0;
    const score = sampleDistance + fromPrevious * 0.08 + backwardsPenalty;
    if (score < bestScore) {
      bestScore = score;
      best = candidate;
    }
  }

  if (!best || distance2D(best, sample) > config.maxNodeSearchDistanceM) return null;
  return best;
}

function findNextTurn(points) {
  let travelled = 0;
  for (let index = 1; index < points.length - 1; index += 1) {
    const incoming = subtract(points[index], points[index - 1]);
    const outgoing = subtract(points[index + 1], points[index]);
    const incomingLength = length2D(incoming);
    const outgoingLength = length2D(outgoing);
    if (incomingLength < 3 || outgoingLength < 3) {
      travelled += incomingLength;
      continue;
    }

    const cosine = clamp(dot2D(incoming, outgoing) / (incomingLength * outgoingLength), -1, 1);
    const angle = Math.acos(cosine) * 180 / Math.PI;
    const cross = incoming.x * outgoing.y - incoming.y * outgoing.x;
    if (angle >= 28) {
      return {
        direction: cross >= 0 ? "RIGHT" : "LEFT",
        distanceM: Math.max(0, travelled),
        angle,
      };
    }
    travelled += incomingLength;
  }
  return null;
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
    log("World GPS Navigation route rebuilt: points=" + route.points.length + " roadNodes=" + route.usedRoadNodes + " targetDistanceM=" + Math.round(route.targetDistanceM));
  }
}

function drawRouteText(currentRoute) {
  if (!config.showTurnText && !config.showDistanceText) return;
  if (typeof FxtStore === "undefined" || typeof FxtStore.insert !== "function") return;

  try {
    let text = "";
    if (config.showDistanceText) text += "GPS " + formatDistance(currentRoute.targetDistanceM);
    if (config.showTurnText && currentRoute.nextTurn) {
      if (text) text += "  ";
      text += currentRoute.nextTurn.direction + " " + formatDistance(currentRoute.nextTurn.distanceM);
    }
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
    config.maxNodeSearchDistanceM = clamp(readConfigInt("route", "max_node_search_distance_m", DEFAULTS.maxNodeSearchDistanceM), 12, 70);
    config.nodeSearchCount = clamp(readConfigInt("route", "node_search_count", DEFAULTS.nodeSearchCount), 1, 8);
    config.showDestinationMarker = readConfigBool("visual", "show_destination_marker", DEFAULTS.showDestinationMarker);
    config.showTurnText = readConfigBool("visual", "show_turn_text", DEFAULTS.showTurnText);
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
  if (Number.isFinite(Number(point.z)) && Math.abs(Number(point.z)) > 0.05) return Number(point.z);
  const result = safeNative("GET_GROUND_Z_FOR_3D_COORD", point.x, point.y, 1000);
  if (Number.isFinite(Number(result))) return Number(result);
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

function truthyNativeValue(value) {
  return value === true || value === 1 || value === "1" || value === "true";
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

function dot2D(left, right) {
  return left.x * right.x + left.y * right.y;
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
