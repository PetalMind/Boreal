/// <reference path="./.config/sa.d.ts" />

// Modern Compass DE v1.0
// GTA San Andreas: The Definitive Edition + CLEO Redux x64 + IniFiles64
// Camera-driven horizontal compass inspired by modern open-world HUDs.

if (HOST !== "sa_unreal") {
  exit("Modern Compass DE supports only GTA San Andreas: The Definitive Edition.");
}

const MOD_NAME = "Modern Compass DE";
const BUILD = "MC-DE-20260920-1";
const PLAYER_ID = 0;
const player = new Player(PLAYER_ID);
const CONFIG_PATH = "./ModernCompassDE.ini";
const CONFIG_VERSION = 1;

const HUD_W = 640;
const HUD_H = 448;
const DEG = Math.PI / 180;

const VK_TOGGLE_DEFAULT = 0x76; // F7
const VK_RELOAD_DEFAULT = 0x77; // F8

const DIRECTION_LABELS = [
  { angle: 0, key: "MCN", label: "N" },
  { angle: 45, key: "MCNE", label: "NE" },
  { angle: 90, key: "MCE", label: "E" },
  { angle: 135, key: "MCSE", label: "SE" },
  { angle: 180, key: "MCS", label: "S" },
  { angle: 225, key: "MCSW", label: "SW" },
  { angle: 270, key: "MCW", label: "W" },
  { angle: 315, key: "MCNW", label: "NW" },
];

const DEFAULTS = {
  enabled: true,
  width: 168,
  height: 27,
  centerX: 320,
  topY: 18,
  visibleHalfAngle: 72,
  minorStepDeg: 15,
  smoothingMs: 72,
  fadeStart: 0.62,
  backgroundAlpha: 38,
  borderAlpha: 45,
  tickAlpha: 150,
  labelAlpha: 220,
  centerAlpha: 245,
  accentR: 205,
  accentG: 235,
  accentB: 245,
  textR: 238,
  textG: 244,
  textB: 248,
  textScaleX: 0.28,
  textScaleY: 0.78,
  showMinorTicks: true,
  showCardinalLabels: true,
  showDegreeReadout: false,
  toggleKey: VK_TOGGLE_DEFAULT,
  reloadKey: VK_RELOAD_DEFAULT,
  debug: false,
};

let config = { ...DEFAULTS };
let runtimeEnabled = true;
let lastToggleDown = false;
let lastReloadDown = false;
let smoothedHeading = null;
let lastFrameAt = Date.now();
let lastGoodHeading = 0;
let renderFaults = 0;
let disabledForSession = false;
let initializedText = false;

registerText();
loadConfig();
log(`${MOD_NAME} loaded. build=${BUILD}; F7 toggle; F8 reload INI.`);

while (true) {
  wait(0);
  const now = Date.now();

  handleInput();

  if (!config.enabled || !runtimeEnabled || disabledForSession) {
    lastFrameAt = now;
    smoothedHeading = null;
    continue;
  }

  if (!isGameplayReady()) {
    lastFrameAt = now;
    smoothedHeading = null;
    continue;
  }

  const heading = readCameraHeading();
  if (heading === null) continue;

  const dt = clamp(now - lastFrameAt, 0, 100);
  lastFrameAt = now;
  smoothedHeading = smoothAngle(smoothedHeading, heading, dt, config.smoothingMs);
  lastGoodHeading = smoothedHeading;

  try {
    renderCompass(smoothedHeading);
    renderFaults = 0;
  } catch (error) {
    renderFaults += 1;
    if (renderFaults <= 3 || config.debug) {
      log(`${MOD_NAME}: renderer error #${renderFaults}: ${error}`);
    }
    if (renderFaults >= 5) {
      disabledForSession = true;
      log(`${MOD_NAME}: renderer disabled for this session after repeated errors.`);
    }
  }
}

function registerText() {
  if (initializedText || typeof FxtStore === "undefined") return;
  try {
    for (const dir of DIRECTION_LABELS) FxtStore.insert(dir.key, dir.label, true);
    FxtStore.insert("MCDGR", "000", true);
    initializedText = true;
  } catch (error) {
    log(`${MOD_NAME}: FXT registration failed: ${error}`);
  }
}

function handleInput() {
  if (typeof Pad === "undefined" || !Pad || typeof Pad.IsKeyPressed !== "function") return;

  const toggleDown = !!Pad.IsKeyPressed(config.toggleKey);
  if (toggleDown && !lastToggleDown) {
    runtimeEnabled = !runtimeEnabled;
    smoothedHeading = null;
    log(`${MOD_NAME}: ${runtimeEnabled ? "enabled" : "disabled"}.`);
  }
  lastToggleDown = toggleDown;

  const reloadDown = !!Pad.IsKeyPressed(config.reloadKey);
  if (reloadDown && !lastReloadDown) {
    loadConfig();
    disabledForSession = false;
    renderFaults = 0;
    smoothedHeading = null;
  }
  lastReloadDown = reloadDown;
}

function isGameplayReady() {
  try {
    if (!player.isPlaying()) return false;
    const actor = player.getChar();
    if (!actor) return false;
    if (safeNative("IS_CHAR_DEAD", actor)) return false;
    return true;
  } catch (_) {
    return false;
  }
}

function readCameraHeading() {
  let camera = null;
  let pointAt = null;

  try {
    if (typeof Camera !== "undefined" && Camera && typeof Camera.GetActiveCoordinates === "function") {
      camera = Camera.GetActiveCoordinates();
    }
  } catch (_) {}

  try {
    if (typeof Camera !== "undefined" && Camera && typeof Camera.GetActivePointAt === "function") {
      pointAt = Camera.GetActivePointAt();
    }
  } catch (_) {}

  if (!isVector(camera)) camera = safeNative("GET_ACTIVE_CAMERA_COORDINATES");
  if (!isVector(pointAt)) pointAt = safeNative("GET_ACTIVE_CAMERA_POINT_AT");
  if (!isVector(camera) || !isVector(pointAt)) return null;

  const dx = pointAt.x - camera.x;
  const dy = pointAt.y - camera.y;
  const planarLength = Math.sqrt(dx * dx + dy * dy);
  if (!Number.isFinite(planarLength) || planarLength < 0.0001) return lastGoodHeading;

  // GTA SA heading convention: 0=N (+Y), 90=E (+X).
  return normalize360(Math.atan2(dx, dy) / DEG);
}

function renderCompass(heading) {
  if (typeof Hud === "undefined" || !Hud || typeof Hud.DrawRect !== "function") return;
  if (typeof Text === "undefined" || !Text || typeof Text.Display !== "function") return;

  const width = config.width;
  const height = config.height;
  const cx = config.centerX;
  const top = config.topY;
  const cy = top + height * 0.5;
  const left = cx - width * 0.5;
  const right = cx + width * 0.5;

  // Compact glass-like body. Multiple low-alpha layers give depth without sprites.
  drawRect(cx, cy, width, height, 5, 10, 15, config.backgroundAlpha);
  drawRect(cx, top + 0.7, width * 0.88, 1.2, 130, 185, 205, config.borderAlpha);
  drawRect(cx, top + height - 0.7, width * 0.82, 1.0, 80, 120, 140, Math.round(config.borderAlpha * 0.55));

  // Side masks visually soften the ends; these are deliberately opaque enough
  // to make tick/label fade-outs look intentional on bright skies.
  drawRect(left + width * 0.055, cy, width * 0.11, height - 2, 4, 8, 12, Math.round(config.backgroundAlpha * 0.90));
  drawRect(right - width * 0.055, cy, width * 0.11, height - 2, 4, 8, 12, Math.round(config.backgroundAlpha * 0.90));

  if (config.showMinorTicks) renderTicks(heading, cx, top, width, height);
  if (config.showCardinalLabels) renderDirectionLabels(heading, cx, top, width, height);

  // Fixed camera-axis marker. No sprite dependency and only three primitives.
  const markerY = top + 5.3;
  drawRect(cx, markerY, 1.5, 8.0, config.accentR, config.accentG, config.accentB, config.centerAlpha);
  drawRect(cx - 2.0, top + 1.9, 4.0, 1.1, config.accentR, config.accentG, config.accentB, config.centerAlpha);
  drawRect(cx + 2.0, top + 1.9, 4.0, 1.1, config.accentR, config.accentG, config.accentB, config.centerAlpha);

  // Small center notch below labels makes the selected direction readable at a glance.
  drawRect(cx, top + height - 3.0, 6.0, 1.1, config.accentR, config.accentG, config.accentB, Math.round(config.centerAlpha * 0.78));

  if (config.showDegreeReadout) renderDegreeReadout(heading, cx, top, height);
}

function renderTicks(heading, cx, top, width, height) {
  const halfAngle = config.visibleHalfAngle;
  const halfWidth = width * 0.5;
  const step = Math.max(5, config.minorStepDeg);
  const startAngle = Math.floor((heading - halfAngle) / step) * step;
  const endAngle = Math.ceil((heading + halfAngle) / step) * step;

  for (let angle = startAngle; angle <= endAngle; angle += step) {
    const worldAngle = normalize360(angle);
    const relative = shortestDelta(worldAngle, heading);
    if (Math.abs(relative) > halfAngle) continue;

    const norm = relative / halfAngle;
    const x = cx + norm * halfWidth;
    const fade = edgeFade(Math.abs(norm));
    if (fade <= 0.02) continue;

    const isCardinal = nearlyMultiple(worldAngle, 45, 0.1);
    const isMainCardinal = nearlyMultiple(worldAngle, 90, 0.1);
    const tickHeight = isMainCardinal ? 6.5 : isCardinal ? 5.0 : 3.0;
    const tickWidth = isMainCardinal ? 1.25 : 0.75;
    const alpha = Math.round(config.tickAlpha * fade * (isMainCardinal ? 1.0 : isCardinal ? 0.82 : 0.52));

    drawRect(x, top + height - 6.1, tickWidth, tickHeight, 210, 226, 234, alpha);
  }
}

function renderDirectionLabels(heading, cx, top, width, height) {
  const halfAngle = config.visibleHalfAngle;
  const halfWidth = width * 0.5;
  const y = top + 12.4;

  for (const dir of DIRECTION_LABELS) {
    const relative = shortestDelta(dir.angle, heading);
    if (Math.abs(relative) > halfAngle) continue;

    const norm = relative / halfAngle;
    const x = cx + norm * halfWidth;
    const fade = edgeFade(Math.abs(norm));
    if (fade <= 0.03) continue;

    const proximity = 1 - clamp(Math.abs(relative) / 28, 0, 1);
    const isNorth = dir.angle === 0;
    const alpha = Math.round(clamp(config.labelAlpha * fade + proximity * 28, 0, 255));
    const r = isNorth ? config.accentR : config.textR;
    const g = isNorth ? config.accentG : config.textG;
    const b = isNorth ? config.accentB : config.textB;
    const scaleBoost = 1 + proximity * 0.08;

    drawText(dir.key, x, y, r, g, b, alpha, config.textScaleX * scaleBoost, config.textScaleY * scaleBoost);
  }
}

function renderDegreeReadout(heading, cx, top, height) {
  try {
    const value = String(Math.round(normalize360(heading))).padStart(3, "0");
    FxtStore.insert("MCDGR", value, true);
    drawText("MCDGR", cx, top + height + 3.0, 185, 205, 214, 150, 0.22, 0.58);
  } catch (_) {}
}

function drawText(key, x, y, r, g, b, a, scaleX, scaleY) {
  Text.SetCenter(true);
  Text.SetProportional(true);
  Text.SetScale(scaleX, scaleY);
  Text.SetColor(clamp255(r), clamp255(g), clamp255(b), clamp255(a));
  Text.SetFont(2);
  if (typeof Text.SetEdge === "function") Text.SetEdge(1, 0, 0, 0, Math.round(a * 0.48));
  else if (typeof Text.SetDropshadow === "function") Text.SetDropshadow(1, 0, 0, 0, Math.round(a * 0.45));
  Text.Display(x, y, key);
}

function drawRect(x, y, w, h, r, g, b, a) {
  if (a <= 0 || w <= 0 || h <= 0) return;
  Hud.DrawRect(
    clamp(x, 0, HUD_W),
    clamp(y, 0, HUD_H),
    Math.max(0.5, w),
    Math.max(0.5, h),
    clamp255(r),
    clamp255(g),
    clamp255(b),
    clamp255(a)
  );
}

function edgeFade(normalizedDistance) {
  const d = clamp(normalizedDistance, 0, 1);
  if (d <= config.fadeStart) return 1;
  const t = (d - config.fadeStart) / Math.max(0.01, 1 - config.fadeStart);
  // Smoothstep inverted: visually softer than linear fade.
  const smooth = t * t * (3 - 2 * t);
  return 1 - smooth;
}

function smoothAngle(current, target, dtMs, smoothingMs) {
  if (current === null || !Number.isFinite(current)) return normalize360(target);
  const tau = Math.max(1, smoothingMs);
  const alpha = 1 - Math.exp(-Math.max(0, dtMs) / tau);
  return normalize360(current + shortestDelta(target, current) * alpha);
}

function shortestDelta(target, current) {
  let delta = normalize360(target) - normalize360(current);
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  return delta;
}

function normalize360(value) {
  let result = finite(value, 0) % 360;
  if (result < 0) result += 360;
  return result;
}

function nearlyMultiple(value, divisor, epsilon) {
  const remainder = normalize360(value) % divisor;
  return remainder < epsilon || divisor - remainder < epsilon;
}

function isVector(value) {
  return !!value && Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);
}

function safeNative(name, ...args) {
  try {
    return native(name, ...args);
  } catch (_) {
    return null;
  }
}

function readInt(section, key, fallback) {
  if (typeof IniFile === "undefined" || !IniFile || typeof IniFile.ReadInt !== "function") return fallback;
  try {
    return finite(IniFile.ReadInt(CONFIG_PATH, section, key), fallback);
  } catch (_) {
    return fallback;
  }
}

function loadConfig() {
  const next = { ...DEFAULTS };
  if (typeof IniFile === "undefined" || !IniFile || typeof IniFile.ReadInt !== "function") {
    config = next;
    log(`${MOD_NAME}: IniFiles64 unavailable; using built-in defaults.`);
    return;
  }

  try {
    const version = readInt("meta", "config_version", CONFIG_VERSION);
    if (version !== CONFIG_VERSION) {
      config = next;
      log(`${MOD_NAME}: unsupported INI version ${version}; using defaults.`);
      return;
    }

    next.enabled = readInt("mod", "enabled", 1) !== 0;
    next.width = clamp(readInt("layout", "width", DEFAULTS.width), 100, 260);
    next.height = clamp(readInt("layout", "height", DEFAULTS.height), 18, 48);
    next.centerX = clamp(readInt("layout", "center_x", DEFAULTS.centerX), 120, 520);
    next.topY = clamp(readInt("layout", "top_y", DEFAULTS.topY), 4, 120);
    next.visibleHalfAngle = clamp(readInt("layout", "visible_half_angle", DEFAULTS.visibleHalfAngle), 45, 120);
    next.minorStepDeg = clamp(readInt("layout", "minor_step_deg", DEFAULTS.minorStepDeg), 5, 30);
    next.smoothingMs = clamp(readInt("motion", "smoothing_ms", DEFAULTS.smoothingMs), 0, 300);
    next.fadeStart = clamp(readInt("visual", "edge_fade_start_percent", Math.round(DEFAULTS.fadeStart * 100)), 20, 90) / 100;
    next.backgroundAlpha = clamp(readInt("visual", "background_alpha", DEFAULTS.backgroundAlpha), 0, 255);
    next.borderAlpha = clamp(readInt("visual", "border_alpha", DEFAULTS.borderAlpha), 0, 255);
    next.tickAlpha = clamp(readInt("visual", "tick_alpha", DEFAULTS.tickAlpha), 0, 255);
    next.labelAlpha = clamp(readInt("visual", "label_alpha", DEFAULTS.labelAlpha), 0, 255);
    next.centerAlpha = clamp(readInt("visual", "center_alpha", DEFAULTS.centerAlpha), 0, 255);
    next.accentR = clamp(readInt("colors", "accent_r", DEFAULTS.accentR), 0, 255);
    next.accentG = clamp(readInt("colors", "accent_g", DEFAULTS.accentG), 0, 255);
    next.accentB = clamp(readInt("colors", "accent_b", DEFAULTS.accentB), 0, 255);
    next.textR = clamp(readInt("colors", "text_r", DEFAULTS.textR), 0, 255);
    next.textG = clamp(readInt("colors", "text_g", DEFAULTS.textG), 0, 255);
    next.textB = clamp(readInt("colors", "text_b", DEFAULTS.textB), 0, 255);
    next.textScaleX = clamp(readInt("text", "scale_x_percent", Math.round(DEFAULTS.textScaleX * 100)), 12, 60) / 100;
    next.textScaleY = clamp(readInt("text", "scale_y_percent", Math.round(DEFAULTS.textScaleY * 100)), 30, 130) / 100;
    next.showMinorTicks = readInt("features", "show_minor_ticks", 1) !== 0;
    next.showCardinalLabels = readInt("features", "show_cardinal_labels", 1) !== 0;
    next.showDegreeReadout = readInt("features", "show_degree_readout", 0) !== 0;
    next.toggleKey = clamp(readInt("input", "toggle_vk", VK_TOGGLE_DEFAULT), 1, 255);
    next.reloadKey = clamp(readInt("input", "reload_vk", VK_RELOAD_DEFAULT), 1, 255);
    next.debug = readInt("debug", "enabled", 0) !== 0;

    config = next;
    log(`${MOD_NAME}: configuration loaded.`);
  } catch (error) {
    config = next;
    log(`${MOD_NAME}: INI load failed; defaults restored: ${error}`);
  }
}

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, finite(value, min)));
}

function clamp255(value) {
  return Math.round(clamp(value, 0, 255));
}
