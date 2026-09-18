/// <reference path="./.config/sa.d.ts" />

// Police Pursuit Radar for GTA San Andreas: The Definitive Edition.
// Runtime: CLEO Redux x64 + ImGuiReduxWin64 + IniFiles64.
//
// The DE scripting API does not expose the classic CWanted pursuit pool or
// the native radar renderer. This script therefore uses supported native
// commands to discover police peds, follows their current vehicles, checks
// line of sight, and draws a self-contained radar layer over the HUD radar.

if (HOST !== "sa_unreal") {
  exit("Police Pursuit Radar supports only GTA San Andreas: The Definitive Edition.");
}

if (typeof ImGui === "undefined") {
  exit("Police Pursuit Radar requires ImGuiReduxWin64.cleo.");
}

const PLAYER_ID = 0;
const player = new Player(PLAYER_ID);
const CONFIG_PATH = "./PolicePursuitRadar.ini";
const CONFIG_VERSION = 1;
const VK_RELOAD = 122; // F11
const IMGUI_COLOR_MAX = 255;

const STATE_IDLE = "IDLE";
const STATE_PURSUIT = "PURSUIT";
const STATE_LOSING_CONTACT = "LOSING CONTACT";
const STATE_SEARCHING = "SEARCHING";
const STATE_ESCAPED = "ESCAPED";

const PED_POLICE = 6;
const POLICE_PED_MODELS = new Set([280, 281, 282, 283, 284, 285]);
const POLICE_CAR_MODELS = new Set([407, 420, 427, 428, 432, 490, 528, 596, 597, 598, 599]);
const POLICE_BIKE_MODELS = new Set([523]);
const POLICE_HELICOPTER_MODELS = new Set([417, 425, 447, 469, 487, 488, 497, 548, 563]);
const POLICE_BOAT_MODELS = new Set([430, 446, 452]);

const DEFAULTS = {
  enabled: true,
  maxDistanceM: 420,
  scanIntervalMs: 260,
  lostSightDelayMs: 1200,
  searchRadiusBaseM: 55,
  searchRadiusPerStarM: 25,
  radarRangeM: 180,
  radarSizePx: 166,
  radarX: 0.105,
  radarY: 0.835,
  rotateWithPlayer: true,
  showOffRadar: true,
  showFoot: true,
  showCars: true,
  showBikes: true,
  showBoats: true,
  showHelicopters: true,
  showStatus: true,
  debug: false,
  reloadHotkeyEnabled: true,
};

let config = { ...DEFAULTS };
let configPersistenceUnavailable = false;
let lastScanAt = 0;
let lastReloadDown = false;
let units = [];
let state = STATE_IDLE;
let wantedLevel = 0;
let lastKnownPosition = null;
let lastContactAt = 0;
let escapedUntil = 0;
let lastLoggedState = null;
let warnedDrawFailure = false;

log("Police Pursuit Radar DE loaded. Host: " + HOST);
loadConfig();

while (true) {
  wait(0);
  const now = Date.now();
  const actor = getPlayerActor();
  const playing = !!actor;

  if (config.reloadHotkeyEnabled) {
    const reloadDown = !!Pad.IsKeyPressed(VK_RELOAD);
    if (reloadDown && !lastReloadDown) {
      loadConfig();
      log("Police Pursuit Radar configuration reloaded.");
    }
    lastReloadDown = reloadDown;
  }

  if (playing && config.enabled) {
    const playerPosition = getCoordinates(actor, false);
    wantedLevel = readWantedLevel();
    if (playerPosition && now - lastScanAt >= config.scanIntervalMs) {
      units = scanPolice(actor, playerPosition, wantedLevel);
      updatePursuitState(playerPosition, units, wantedLevel, now);
      lastScanAt = now;
    }
  } else {
    resetRuntimeState();
  }

  ImGui.BeginFrame("POLICE_PURSUIT_RADAR_DE");
  ImGui.SetCursorVisible(false);
  if (playing && config.enabled) {
    const playerPosition = getCoordinates(actor, false);
    if (playerPosition) drawRadar(actor, playerPosition, units, now);
  }
  ImGui.EndFrame();
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

function readWantedLevel() {
  const value = safeNative("STORE_WANTED_LEVEL", player);
  return clamp(Math.trunc(finiteNumber(value, 0)), 0, 6);
}

function scanPolice(actor, playerPosition, stars) {
  if (stars <= 0) return [];

  const results = [];
  const samples = samplePoints(playerPosition, config.maxDistanceM);

  // Keep handles already seen in the previous scan. This prevents the
  // nearest-ped sampler from making a marker flicker when police move.
  for (const previous of units) {
    addUnit(results, inspectPolice(previous.char, actor, playerPosition, stars));
  }

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

  return results
    .filter(Boolean)
    .sort((left, right) => left.distance - right.distance)
    .slice(0, 24);
}

function samplePoints(center, maxDistance) {
  const result = [{ x: center.x, y: center.y, z: center.z, radius: Math.min(115, maxDistance) }];
  const rings = [maxDistance * 0.28, maxDistance * 0.58, maxDistance * 0.86];
  for (let ring = 0; ring < rings.length; ring += 1) {
    const count = ring === 2 ? 16 : 10;
    for (let index = 0; index < count; index += 1) {
      const angle = (Math.PI * 2 * index) / count + ring * 0.31;
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
  if (!pedPosition) return null;
  const pedDistance = distanceBetween(pedPosition, playerPosition);
  if (pedDistance > config.maxDistanceM) return null;

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

function addUnit(list, unit) {
  if (!unit) return;
  const duplicate = list.find((existing) =>
    existing.type === unit.type && distanceBetween(existing.position, unit.position) < 5.0
  );
  if (!duplicate) list.push(unit);
  else if (unit.contact && !duplicate.contact) Object.assign(duplicate, unit);
}

function updatePursuitState(playerPosition, currentUnits, stars, now) {
  if (stars <= 0) {
    if (state !== STATE_IDLE && state !== STATE_ESCAPED) {
      state = STATE_ESCAPED;
      escapedUntil = now + 600;
      logStateChange();
    } else if (state === STATE_ESCAPED && now >= escapedUntil) {
      resetRuntimeState();
    }
    return;
  }

  const hasContact = currentUnits.some((unit) => unit.contact);
  const searchRadius = getSearchRadius(stars);
  if (hasContact) {
    state = STATE_PURSUIT;
    lastKnownPosition = { ...playerPosition };
    lastContactAt = now;
  } else if (state === STATE_PURSUIT && now - lastContactAt < config.lostSightDelayMs) {
    state = STATE_LOSING_CONTACT;
  } else {
    if (!lastKnownPosition) lastKnownPosition = { ...playerPosition };
    state = STATE_SEARCHING;
  }

  if (config.debug && now - lastScanAt < 20) {
    log("Radar scan: units=" + currentUnits.length + " contact=" + hasContact + " radius=" + searchRadius);
  }
  logStateChange();
}

function getSearchRadius(stars) {
  return clamp(
    config.searchRadiusBaseM + stars * config.searchRadiusPerStarM,
    50,
    config.radarRangeM * 1.5
  );
}

function drawRadar(actor, playerPosition, currentUnits, now) {
  const display = safeDisplaySize();
  const drawList = safeDrawList();
  if (!display || !drawList) return;

  const size = clamp(config.radarSizePx, 110, 240);
  const center = {
    x: clamp(display.width * config.radarX, size * 0.65, display.width - size * 0.65),
    y: clamp(display.height * config.radarY, size * 0.65, display.height - size * 0.65),
  };
  const radiusPx = size * 0.5;
  const rangeM = Math.max(60, config.radarRangeM);
  const heading = finiteNumber(safeNative("GET_CHAR_HEADING", actor), 0);

  drawFilledCircle(drawList, center, radiusPx, 0.015, 0.035, 0.055, 0.48);
  drawCircle(drawList, center, radiusPx, 0.18, 0.55, 0.78, 0.86, 2.0);
  drawCircle(drawList, center, radiusPx * 0.66, 0.12, 0.35, 0.50, 0.32, 1.0);
  drawLine(drawList, center.x - radiusPx, center.y, center.x + radiusPx, center.y, 0.18, 0.55, 0.78, 0.22, 1.0);
  drawLine(drawList, center.x, center.y - radiusPx, center.x, center.y + radiusPx, 0.18, 0.55, 0.78, 0.22, 1.0);

  if (state === STATE_SEARCHING || state === STATE_LOSING_CONTACT) {
    drawSearchArea(drawList, center, playerPosition, heading, rangeM, radiusPx);
  }

  for (const unit of currentUnits) {
    if (!isTypeEnabled(unit.type)) continue;
    const point = radarPoint(unit.position, playerPosition, heading, rangeM, center, radiusPx);
    if (!point) continue;
    drawUnitMarker(drawList, point, unit, radiusPx, now);
  }

  if (lastKnownPosition && (state === STATE_SEARCHING || state === STATE_LOSING_CONTACT)) {
    const lastKnown = radarPoint(lastKnownPosition, playerPosition, heading, rangeM, center, radiusPx);
    if (lastKnown) drawDiamond(drawList, lastKnown.x, lastKnown.y, 7, 1.0, 0.62, 0.12, 0.95, 1.8);
  }

  drawPlayerArrow(drawList, center, heading);
  if (config.showStatus) {
    const status = state + "  *" + wantedLevel + "  " + currentUnits.length;
    drawText(drawList, center.x - radiusPx, center.y + radiusPx + 8, 0.80, 0.91, 0.98, 0.92, status);
    if (state === STATE_SEARCHING && lastKnownPosition) {
      drawText(drawList, center.x - radiusPx, center.y + radiusPx + 24, 1.0, 0.66, 0.20, 0.86, "LAST KNOWN POSITION");
    }
  }
}

function drawSearchArea(drawList, center, playerPosition, heading, rangeM, radiusPx) {
  if (!lastKnownPosition) return;
  const searchRadius = getSearchRadius(wantedLevel);
  const points = [];
  for (let index = 0; index <= 48; index += 1) {
    const angle = (Math.PI * 2 * index) / 48;
    points.push(radarPoint({
      x: lastKnownPosition.x + Math.cos(angle) * searchRadius,
      y: lastKnownPosition.y + Math.sin(angle) * searchRadius,
      z: lastKnownPosition.z,
    }, playerPosition, heading, rangeM, center, radiusPx));
  }
  for (let index = 1; index < points.length; index += 1) {
    const left = points[index - 1];
    const right = points[index];
    if (!left || !right) continue;
    drawLine(drawList, left.x, left.y, right.x, right.y, 1.0, 0.55, 0.12, 0.82, 1.7);
  }
}

function radarPoint(position, playerPosition, heading, rangeM, center, radiusPx) {
  let dx = position.x - playerPosition.x;
  let dy = position.y - playerPosition.y;
  if (config.rotateWithPlayer) {
    const angle = (heading * Math.PI) / 180;
    const forwardX = Math.sin(angle);
    const forwardY = Math.cos(angle);
    const rightX = Math.cos(angle);
    const rightY = -Math.sin(angle);
    const localX = dx * rightX + dy * rightY;
    const localY = dx * forwardX + dy * forwardY;
    dx = localX;
    dy = localY;
  }

  const px = center.x + (dx / rangeM) * radiusPx;
  const py = center.y - (dy / rangeM) * radiusPx;
  const deltaX = px - center.x;
  const deltaY = py - center.y;
  const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
  const limit = radiusPx - 8;
  if (distance <= limit) return { x: px, y: py, offRadar: false };
  if (!config.showOffRadar || distance <= 0.001) return null;
  return { x: center.x + (deltaX / distance) * limit, y: center.y + (deltaY / distance) * limit, offRadar: true };
}

function drawUnitMarker(drawList, point, unit, radarRadius, now) {
  const pulse = 0.88 + Math.sin(now / 170) * 0.12;
  const color = markerColor(unit);
  const alpha = point.offRadar ? 0.38 : pulse;
  if (unit.type === "foot") {
    drawCircle(drawList, point, 5, color.r, color.g, color.b, alpha, 1.8);
    drawLine(drawList, point.x - 3, point.y, point.x + 3, point.y, color.r, color.g, color.b, alpha, 1.4);
  } else if (unit.type === "helicopter") {
    drawCircle(drawList, point, 7, color.r, color.g, color.b, alpha, 1.8);
    drawLine(drawList, point.x - 2, point.y, point.x + 2, point.y, color.r, color.g, color.b, alpha, 1.5);
    drawLine(drawList, point.x, point.y - 2, point.x, point.y + 2, color.r, color.g, color.b, alpha, 1.5);
  } else if (unit.type === "boat") {
    drawDiamond(drawList, point.x, point.y, 7, color.r, color.g, color.b, alpha, 1.8);
  } else {
    drawChevron(drawList, point.x, point.y, unit.heading, color.r, color.g, color.b, alpha, unit.type === "bike" ? 6 : 8);
  }
  if (config.debug && !unit.contact) {
    drawLine(drawList, point.x - 4, point.y - 4, point.x + 4, point.y + 4, 1.0, 0.15, 0.12, 0.8, 1.0);
  }
}

function markerColor(unit) {
  if (config.debug && !unit.lineOfSight) return { r: 1.0, g: 0.15, b: 0.12 };
  if (unit.contact) return { r: 0.18, g: 1.0, b: 0.45 };
  if (unit.type === "foot") return { r: 1.0, g: 0.82, b: 0.20 };
  if (unit.type === "helicopter") return { r: 0.42, g: 1.0, b: 0.76 };
  if (unit.type === "boat") return { r: 0.24, g: 0.72, b: 1.0 };
  if (unit.type === "bike") return { r: 0.88, g: 0.42, b: 1.0 };
  return { r: 0.30, g: 0.72, b: 1.0 };
}

function drawPlayerArrow(drawList, center, heading) {
  const angle = config.rotateWithPlayer ? 0 : (-heading * Math.PI) / 180;
  const forward = { x: Math.sin(angle), y: -Math.cos(angle) };
  const right = { x: Math.cos(angle), y: Math.sin(angle) };
  const tip = { x: center.x + forward.x * 10, y: center.y + forward.y * 10 };
  const left = { x: center.x - forward.x * 6 - right.x * 5, y: center.y - forward.y * 6 - right.y * 5 };
  const other = { x: center.x - forward.x * 6 + right.x * 5, y: center.y - forward.y * 6 + right.y * 5 };
  drawLine(drawList, tip.x, tip.y, left.x, left.y, 0.86, 0.96, 1.0, 1.0, 2.0);
  drawLine(drawList, tip.x, tip.y, other.x, other.y, 0.86, 0.96, 1.0, 1.0, 2.0);
  drawLine(drawList, left.x, left.y, other.x, other.y, 0.86, 0.96, 1.0, 1.0, 1.6);
}

function drawChevron(drawList, x, y, heading, r, g, b, a, size) {
  const angle = ((config.rotateWithPlayer ? 0 : -heading) * Math.PI) / 180;
  const forward = { x: Math.sin(angle), y: -Math.cos(angle) };
  const right = { x: Math.cos(angle), y: Math.sin(angle) };
  const tip = { x: x + forward.x * size, y: y + forward.y * size };
  const left = { x: x - forward.x * size * 0.65 - right.x * size * 0.65, y: y - forward.y * size * 0.65 - right.y * size * 0.65 };
  const other = { x: x - forward.x * size * 0.65 + right.x * size * 0.65, y: y - forward.y * size * 0.65 + right.y * size * 0.65 };
  drawLine(drawList, tip.x, tip.y, left.x, left.y, r, g, b, a, 2.0);
  drawLine(drawList, tip.x, tip.y, other.x, other.y, r, g, b, a, 2.0);
  drawLine(drawList, left.x, left.y, other.x, other.y, r, g, b, a, 1.4);
}

function drawDiamond(drawList, x, y, size, r, g, b, a, thickness) {
  drawLine(drawList, x, y - size, x + size, y, r, g, b, a, thickness);
  drawLine(drawList, x + size, y, x, y + size, r, g, b, a, thickness);
  drawLine(drawList, x, y + size, x - size, y, r, g, b, a, thickness);
  drawLine(drawList, x - size, y, x, y - size, r, g, b, a, thickness);
}

function drawFilledCircle(drawList, center, radius, r, g, b, a) {
  for (let offset = -radius; offset <= radius; offset += 3) {
    const half = Math.sqrt(Math.max(0, radius * radius - offset * offset));
    drawLine(drawList, center.x - half, center.y + offset, center.x + half, center.y + offset, r, g, b, a, 3.0);
  }
}

function drawCircle(drawList, center, radius, r, g, b, a, thickness) {
  let previous = null;
  for (let index = 0; index <= 48; index += 1) {
    const angle = (Math.PI * 2 * index) / 48;
    const point = { x: center.x + Math.cos(angle) * radius, y: center.y + Math.sin(angle) * radius };
    if (previous) drawLine(drawList, previous.x, previous.y, point.x, point.y, r, g, b, a, thickness);
    previous = point;
  }
}

function isTypeEnabled(type) {
  if (type === "foot") return config.showFoot;
  if (type === "car") return config.showCars;
  if (type === "bike") return config.showBikes;
  if (type === "boat") return config.showBoats;
  if (type === "helicopter") return config.showHelicopters;
  return true;
}

function safeDrawList() {
  try {
    return ImGui.GetForegroundDrawList();
  } catch (_) {
    if (!warnedDrawFailure) {
      log("Police Pursuit Radar: ImGui foreground draw list is unavailable.");
      warnedDrawFailure = true;
    }
    return null;
  }
}

function safeDisplaySize() {
  try {
    const size = ImGui.GetDisplaySize();
    if (!size || !Number.isFinite(size.width) || !Number.isFinite(size.height)) return null;
    return size;
  } catch (_) {
    return null;
  }
}

function drawLine(drawList, x1, y1, x2, y2, r, g, b, a, thickness) {
  try {
    ImGui.AddLine(
      drawList,
      x1,
      y1,
      x2,
      y2,
      imguiColor(r),
      imguiColor(g),
      imguiColor(b),
      imguiColor(a),
      thickness
    );
  } catch (_) {}
}

function drawText(drawList, x, y, r, g, b, a, text) {
  try {
    ImGui.AddText(
      drawList,
      x,
      y,
      imguiColor(r),
      imguiColor(g),
      imguiColor(b),
      imguiColor(a),
      text
    );
  } catch (_) {}
}

// ImGuiRedux draw-list commands use 0..255 channels. The radar's visual
// primitives intentionally use normalized 0..1 values, so convert them at
// this single boundary before crossing into the plugin API.
function imguiColor(value) {
  return Math.round(clamp(finiteNumber(value, 0), 0, 1) * IMGUI_COLOR_MAX);
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
    configPersistenceUnavailable = true;
    log("Police Pursuit Radar: IniFiles64 unavailable; using defaults.");
    return;
  }
  try {
    const version = updateConfigValue("meta", "config_version", CONFIG_VERSION);
    if (version !== CONFIG_VERSION) {
      log("Police Pursuit Radar: unsupported config version; using defaults.");
      return;
    }
    config.enabled = updateConfigValue("radar", "enabled", DEFAULTS.enabled ? 1 : 0) !== 0;
    config.maxDistanceM = clamp(updateConfigValue("tracking", "max_distance_m", DEFAULTS.maxDistanceM), 80, 900);
    config.scanIntervalMs = clamp(updateConfigValue("tracking", "scan_interval_ms", DEFAULTS.scanIntervalMs), 100, 2000);
    config.lostSightDelayMs = clamp(updateConfigValue("tracking", "lost_sight_delay_ms", DEFAULTS.lostSightDelayMs), 250, 10000);
    config.searchRadiusBaseM = clamp(updateConfigValue("search", "radius_base_m", DEFAULTS.searchRadiusBaseM), 20, 150);
    config.searchRadiusPerStarM = clamp(updateConfigValue("search", "radius_per_star_m", DEFAULTS.searchRadiusPerStarM), 0, 80);
    config.radarRangeM = clamp(updateConfigValue("radar", "range_m", DEFAULTS.radarRangeM), 60, 500);
    config.radarSizePx = clamp(updateConfigValue("radar", "size_px", DEFAULTS.radarSizePx), 110, 240);
    config.radarX = clamp(updateConfigValue("radar", "screen_x_percent", DEFAULTS.radarX * 100) / 100, 0.05, 0.40);
    config.radarY = clamp(updateConfigValue("radar", "screen_y_percent", DEFAULTS.radarY * 100) / 100, 0.60, 0.96);
    config.rotateWithPlayer = updateConfigValue("radar", "rotate_with_player", DEFAULTS.rotateWithPlayer ? 1 : 0) !== 0;
    config.showOffRadar = updateConfigValue("radar", "show_off_radar", DEFAULTS.showOffRadar ? 1 : 0) !== 0;
    config.showFoot = updateConfigValue("units", "show_foot", DEFAULTS.showFoot ? 1 : 0) !== 0;
    config.showCars = updateConfigValue("units", "show_cars", DEFAULTS.showCars ? 1 : 0) !== 0;
    config.showBikes = updateConfigValue("units", "show_bikes", DEFAULTS.showBikes ? 1 : 0) !== 0;
    config.showBoats = updateConfigValue("units", "show_boats", DEFAULTS.showBoats ? 1 : 0) !== 0;
    config.showHelicopters = updateConfigValue("units", "show_helicopters", DEFAULTS.showHelicopters ? 1 : 0) !== 0;
    config.showStatus = updateConfigValue("visual", "show_status", DEFAULTS.showStatus ? 1 : 0) !== 0;
    config.debug = updateConfigValue("visual", "debug", DEFAULTS.debug ? 1 : 0) !== 0;
    config.reloadHotkeyEnabled = updateConfigValue("input", "reload_hotkey_enabled", DEFAULTS.reloadHotkeyEnabled ? 1 : 0) !== 0;
    log("Police Pursuit Radar configuration loaded.");
  } catch (error) {
    configPersistenceUnavailable = true;
    log("Police Pursuit Radar: config load failed; using defaults.");
  }
}

function resetRuntimeState() {
  units = [];
  wantedLevel = 0;
  state = STATE_IDLE;
  lastKnownPosition = null;
  lastContactAt = 0;
  escapedUntil = 0;
  lastScanAt = 0;
}

function logStateChange() {
  if (state === lastLoggedState) return;
  lastLoggedState = state;
  log("Police Pursuit Radar state: " + state);
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
  } catch (_) {
    return null;
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
