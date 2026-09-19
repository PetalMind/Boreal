/// <reference path="./.config/sa.d.ts" />

// Vehicle Speedometer DE for GTA San Andreas: The Definitive Edition.
// Runtime: CLEO Redux x64 + IniFiles64.
//
// The mod deliberately stays on the public CLEO/SA:DE scripting surface. It
// does not read Unreal Engine memory, alter vehicle physics, or replace the
// game's own HUD. The four classes below keep vehicle reads, presentation
// state, drawing, and the frame loop separate so the HUD can grow later.

if (typeof HOST === "undefined" || HOST !== "sa_unreal") {
  exit("Vehicle Speedometer DE supports only GTA San Andreas: The Definitive Edition.");
}

const FORWARD_GEAR_UP_SPEEDS = [18, 40, 65, 95, 130];
const FORWARD_GEAR_DOWN_SPEEDS = [0, 12, 30, 52, 80];

const PLAYER_ID = 0;
const CONFIG_PATH = "./VehicleSpeedometerDE.ini";
const CONFIG_VERSION = 8;
const VK_RELOAD = 122; // F11.

const HUD_VIRTUAL_WIDTH = 640;
const HUD_VIRTUAL_HEIGHT = 448;

const TEXT_KEY_SPEED = "BSPDSPD";
const TEXT_KEY_UNIT = "BSPDUNT";
const TEXT_KEY_DRIVE = "BSPDDRV";

const STATE_HIDDEN = "Hidden";
const STATE_ENTERING = "EnteringVehicle";
const STATE_VISIBLE = "Visible";
const STATE_LEAVING = "LeavingVehicle";

const DEFAULTS = {
  enabled: true,
  speedMultiplier: 3.6,
  maxDisplaySpeed: 240,
  smoothing: 0.14,
  speedUpdateMs: 40,
  accelerationRedlineKmhPerSecond: 80,
  animationMs: 220,
  showDirection: true,
  neutralSpeedKmh: 0.8,
  reverseMinSpeedKmh: 3,
  reverseDotThreshold: 0.35,
  anchorX: 0.955,
  anchorY: 0.81,
  unitOffsetY: 0.045,
  lowerOffsetY: 0.105,
  speedTextScale: 1.10,
  unitTextScale: 0.36,
  driveTextScale: 0.46,
  barWidth: 0.095,
  barHeight: 0.007,
  barGap: 0.004,
  barSegments: 12,
  speedFont: 3,
  reloadHotkeyEnabled: true,
  debug: false,
};

const config = { ...DEFAULTS };
const player = new Player(PLAYER_ID);
const nativeFailureCounts = new Map();

let lastReloadDown = false;
let textStoreFailureLogged = false;
let lastUpdateFailureAt = 0;

class VehicleTracker {
  read(actor, previousDirection) {
    if (!actor || safeNative("IS_CHAR_DEAD", actor) === true) return null;

    const onFoot = safeNative("IS_CHAR_ON_FOOT", actor);
    if (onFoot === true) return null;

    const vehicleType = this.readVehicleType(actor);
    if (!vehicleType) return null;

    const rawVehicle = safeNative("STORE_CAR_CHAR_IS_IN_NO_SAVE", actor);
    const vehicle = toHandle(rawVehicle);
    if (!vehicle) return null;

    const speedVector = this.readSpeedVector(vehicle);
    const speedMps = this.readSpeedMps(vehicle, speedVector);
    const speedKmh = Math.abs(speedMps) * config.speedMultiplier;
    const heading = finiteNumber(safeNative("GET_CAR_HEADING", vehicle), 0);
    const direction = this.readDirection(
      speedKmh,
      speedVector,
      heading,
      previousDirection
    );

    return {
      vehicle,
      type: vehicleType,
      rawSpeed: speedMps,
      speedKmh: clamp(speedKmh, 0, 999),
      direction,
    };
  }

  readVehicleType(actor) {
    if (safeNative("IS_CHAR_IN_ANY_PLANE", actor) === true) return "aircraft";
    if (safeNative("IS_CHAR_IN_ANY_HELI", actor) === true) return "helicopter";
    if (safeNative("IS_CHAR_IN_ANY_BOAT", actor) === true) return "boat";
    if (safeNative("IS_CHAR_IN_ANY_CAR", actor) === true) return "car";
    return null;
  }

  readSpeedMps(vehicle, speedVector) {
    let reportedSpeed = this.readReportedSpeed(vehicle);
    if (!Number.isFinite(reportedSpeed) && isVector(speedVector)) {
      reportedSpeed = vectorLength(speedVector);
    }
    return Number.isFinite(reportedSpeed) ? reportedSpeed : 0;
  }

  readReportedSpeed(vehicle) {
    try {
      if (typeof Car !== "undefined" && typeof Car.GetSpeed === "function") {
        const value = Number(Car.GetSpeed(vehicle));
        if (Number.isFinite(value)) return value;
      }
    } catch (_) {}

    const value = safeNative("GET_CAR_SPEED", vehicle);
    const number = Number(value);
    return Number.isFinite(number) ? number : NaN;
  }

  readSpeedVector(vehicle) {
    try {
      if (typeof Car !== "undefined" && typeof Car.GetSpeedVector === "function") {
        const value = Car.GetSpeedVector(vehicle);
        if (isVector(value)) return value;
      }
    } catch (_) {}

    const value = safeNative("GET_CAR_SPEED_VECTOR", vehicle);
    return isVector(value) ? value : null;
  }

  readDirection(speedKmh, speedVector, heading, previousDirection) {
    if (!isVector(speedVector)) {
      return previousDirection || "D";
    }

    const horizontal = { x: Number(speedVector.x), y: Number(speedVector.y), z: 0 };
    const length = vectorLength(horizontal);
    if (length < 0.06) return previousDirection || "D";

    const forward = headingVector(heading);
    const dot = (horizontal.x * forward.x + horizontal.y * forward.y) / length;
    return dot <= -config.reverseDotThreshold ? "R" : "D";
  }
}

class SpeedometerModel {
  constructor() {
    this.state = STATE_HIDDEN;
    this.active = false;
    this.opacity = 0;
    this.rawSpeed = 0;
    this.displaySpeed = 0;
    this.direction = "D";
    this.driveState = "N";
    this.gear = "N";
    this.forwardGear = 0;
    this.throttleRatio = 0;
    this.accelerationKmhPerSecond = 0;
    this.previousRawSpeed = 0;
    this.lastSpeedUpdateAt = 0;
    this.lastAnimationAt = 0;
  }

  setVehiclePresent(present, now) {
    if (present === this.active) return;

    this.active = present;
    this.lastAnimationAt = now;
    if (present) {
      this.state = STATE_ENTERING;
    } else if (this.opacity > 0) {
      this.state = STATE_LEAVING;
    } else {
      this.state = STATE_HIDDEN;
    }
  }

  updateSpeed(rawSpeed, direction, now) {
    this.rawSpeed = clamp(finiteNumber(rawSpeed, 0), 0, 999);
    if (direction === "D" || direction === "R") this.direction = direction;
    this.driveState = this.rawSpeed < config.neutralSpeedKmh ? "N" : this.direction;
    if (this.driveState === "N") {
      this.forwardGear = 0;
      this.gear = "N";
    } else if (this.driveState === "R") {
      this.forwardGear = 0;
      this.gear = "R";
    } else {
      this.forwardGear = shiftForwardGear(this.forwardGear, this.rawSpeed);
      this.gear = String(this.forwardGear);
    }

    if (this.lastSpeedUpdateAt === 0) {
      this.lastSpeedUpdateAt = now;
      this.previousRawSpeed = this.rawSpeed;
      return;
    }

    if (now - this.lastSpeedUpdateAt < config.speedUpdateMs) return;

    const elapsed = clamp(now - this.lastSpeedUpdateAt, 1, 250);
    const frameEquivalent = elapsed / 16.6667;
    const alpha = 1 - Math.pow(1 - config.smoothing, frameEquivalent);
    this.displaySpeed += (this.rawSpeed - this.displaySpeed) * alpha;
    const seconds = elapsed / 1000;
    this.accelerationKmhPerSecond =
      (this.rawSpeed - this.previousRawSpeed) / seconds;
    const accelerationRatio = clamp(
      Math.max(this.accelerationKmhPerSecond, 0) /
        config.accelerationRedlineKmhPerSecond,
      0,
      1
    );
    const targetThrottle = accelerationRatio;
    this.throttleRatio += (targetThrottle - this.throttleRatio) * alpha;
    this.previousRawSpeed = this.rawSpeed;
    this.lastSpeedUpdateAt = now;
  }

  advanceAnimation(now) {
    if (this.lastAnimationAt === 0) this.lastAnimationAt = now;
    const elapsed = clamp(now - this.lastAnimationAt, 0, 250);
    this.lastAnimationAt = now;

    const target = this.active ? 1 : 0;
    const step = config.animationMs > 0 ? elapsed / config.animationMs : 1;
    if (target > this.opacity) {
      this.opacity = Math.min(target, this.opacity + step);
    } else {
      this.opacity = Math.max(target, this.opacity - step);
    }

    if (this.active && this.opacity >= 0.999) this.state = STATE_VISIBLE;
    if (!this.active && this.opacity <= 0.001) {
      this.opacity = 0;
      this.state = STATE_HIDDEN;
    }
  }

  get speedRatio() {
    return clamp(this.displaySpeed / config.maxDisplaySpeed, 0, 1);
  }

  get offsetY() {
    return (1 - this.opacity) * 0.012;
  }
}

class SpeedometerRenderer {
  render(model) {
    if (!config.enabled || model.opacity <= 0.001 || !updateTextStore(model)) return;
    // DISPLAY_TEXT uses the game's 640x448 virtual HUD space in SA:DE.
    // Passing normalized values directly places the widget near the top-left.
    const rightNorm = clamp(config.anchorX, 0.7, 0.99);
    const speedYNorm = clamp(config.anchorY + model.offsetY, 0.55, 0.95);
    const unitYNorm = speedYNorm + config.unitOffsetY;
    const lowerYNorm = speedYNorm + config.lowerOffsetY;
    const right = rightNorm * HUD_VIRTUAL_WIDTH;
    const speedY = speedYNorm * HUD_VIRTUAL_HEIGHT;
    const unitY = unitYNorm * HUD_VIRTUAL_HEIGHT;
    const lowerY = lowerYNorm * HUD_VIRTUAL_HEIGHT;
    const barLeft = rightNorm - config.barWidth;

    // SA:DE does not expose a reliable RPM channel. This thin accent uses the
    // measured positive acceleration instead of presenting invented RPM data.
    drawSegmentedBar(model.throttleRatio, barLeft, lowerY, model.opacity);

    safeNative("USE_TEXT_COMMANDS", true);
    try {
      configureText(config.speedTextScale, 235, 235, 235, model.opacity * 255, false, true);
      safeNative("DISPLAY_TEXT", right, speedY, TEXT_KEY_SPEED);
      configureText(config.unitTextScale, 180, 180, 180, model.opacity * 210, false, true);
      safeNative("DISPLAY_TEXT", right, unitY, TEXT_KEY_UNIT);
      configureText(config.driveTextScale, 205, 205, 205, model.opacity * 220, false, false);
      safeNative("DISPLAY_TEXT", barLeft - 0.018 * HUD_VIRTUAL_WIDTH,
        lowerY - 0.006 * HUD_VIRTUAL_HEIGHT, TEXT_KEY_DRIVE);
    } finally {
      safeNative("USE_TEXT_COMMANDS", false);
    }
  }
}

class SpeedometerController {
  constructor() {
    this.tracker = new VehicleTracker();
    this.model = new SpeedometerModel();
    this.renderer = new SpeedometerRenderer();
    this.lastDebugAt = 0;
  }

  update(now) {
    const actor = getPlayerActor();
    const sample = config.enabled
      ? this.tracker.read(actor, this.model.direction)
      : null;

    this.model.setVehiclePresent(!!sample, now);
    this.model.updateSpeed(sample ? sample.speedKmh : 0, sample?.direction, now);
    this.model.advanceAnimation(now);
    this.renderer.render(this.model);

    if (config.debug && sample && now - this.lastDebugAt >= 1000) {
      this.lastDebugAt = now;
      log(
        "Vehicle Speedometer sample type=" +
          sample.type +
          " speed=" +
          Math.round(sample.speedKmh) +
          " direction=" +
          sample.direction +
          " gear=" +
          this.model.gear +
          " acceleration=" +
          Math.round(this.model.accelerationKmhPerSecond) +
          " state=" +
          this.model.state
      );
    }
  }
}

loadConfig();
const controller = new SpeedometerController();
log("Vehicle Speedometer DE loaded. Host: " + HOST);

while (true) {
  wait(0);
  const now = Date.now();

  if (config.reloadHotkeyEnabled) {
    const reloadDown = isKeyPressed(VK_RELOAD);
    if (reloadDown && !lastReloadDown) {
      loadConfig();
      log("Vehicle Speedometer DE configuration reloaded.");
    }
    lastReloadDown = reloadDown;
  }

  try {
    controller.update(now);
  } catch (error) {
    // A transient native/handle failure must not terminate the CLEO script.
    // Hide this frame and let the next frame reacquire the vehicle.
    if (now - lastUpdateFailureAt >= 1000) {
      lastUpdateFailureAt = now;
      log("Vehicle Speedometer DE: frame update recovered from error: " + error);
    }
    controller.model.setVehiclePresent(false, now);
    controller.model.advanceAnimation(now);
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

function updateTextStore(model) {
  if (typeof FxtStore === "undefined" || !FxtStore || typeof FxtStore.insert !== "function") {
    if (!textStoreFailureLogged) {
      textStoreFailureLogged = true;
      log("Vehicle Speedometer DE: FxtStore is unavailable; text HUD is disabled.");
    }
    return false;
  }

  try {
    FxtStore.insert(TEXT_KEY_SPEED, formatSpeed(model.displaySpeed));
    FxtStore.insert(TEXT_KEY_UNIT, "KM/H");
    FxtStore.insert(
      TEXT_KEY_DRIVE,
      config.showDirection && model.driveState === "R" ? "R" : "D"
    );
    return true;
  } catch (error) {
    if (!textStoreFailureLogged) {
      textStoreFailureLogged = true;
      log("Vehicle Speedometer DE: FxtStore update failed: " + error);
    }
    return false;
  }
}

function configureText(scale, red, green, blue, alpha, centered, rightJustified) {
  safeNative("SET_TEXT_FONT", config.speedFont);
  safeNative("SET_TEXT_SCALE", scale, scale);
  safeNative("SET_TEXT_COLOUR", red, green, blue, clamp(Math.round(alpha), 0, 255));
  // Fixed-width digits keep the changing speed from visibly jumping sideways.
  safeNative("SET_TEXT_PROPORTIONAL", false);
  safeNative("SET_TEXT_BACKGROUND", false);
  safeNative("SET_TEXT_EDGE", 2, 0, 0, 0, clamp(Math.round(alpha), 0, 255));
  safeNative("SET_TEXT_CENTRE", centered);
  safeNative("SET_TEXT_JUSTIFY", false);
  safeNative("SET_TEXT_RIGHT_JUSTIFY", rightJustified);
  safeNative("SET_TEXT_DROPSHADOW", 2, 0, 0, 0, clamp(Math.round(alpha), 0, 255));
}

function drawSegmentedBar(ratio, left, centerY, opacity) {
  const count = Math.max(4, Math.round(config.barSegments));
  const gap = Math.max(0.001, config.barGap);
  const width = Math.max(0.02, config.barWidth);
  const segmentWidth = (width - gap * (count - 1)) / count;
  const filled = Math.round(clamp(ratio, 0, 1) * count);

  for (let index = 0; index < count; index += 1) {
    const active = index < filled;
    const redline = index >= Math.ceil(count * 0.82);
    const color = active
      ? redline
        ? { r: 190, g: 76, b: 63 }
        : { r: 213, g: 213, b: 200 }
      : { r: 64, g: 64, b: 62 };
    drawHudRect(
      left + index * (segmentWidth + gap) + segmentWidth / 2,
      centerY,
      segmentWidth,
      config.barHeight,
      color.r,
      color.g,
      color.b,
      opacity * (active ? 210 : 100)
    );
  }
}

function drawHudRect(x, y, width, height, red, green, blue, alpha) {
  const safeX = clamp(finiteNumber(x, 0), 0, 1);
  const safeY = clamp(finiteNumber(y, 0), 0, 1);
  const safeWidth = Math.max(0.001, finiteNumber(width, 0.001));
  const safeHeight = Math.max(0.001, finiteNumber(height, 0.001));
  const safeAlpha = clamp(Math.round(alpha), 0, 255);
  if (safeAlpha <= 0) return;

  try {
    if (typeof Hud !== "undefined" && typeof Hud.DrawRect === "function") {
      Hud.DrawRect(
        safeX * HUD_VIRTUAL_WIDTH,
        safeY * HUD_VIRTUAL_HEIGHT,
        safeWidth * HUD_VIRTUAL_WIDTH,
        safeHeight * HUD_VIRTUAL_HEIGHT,
        clamp(Math.round(red), 0, 255),
        clamp(Math.round(green), 0, 255),
        clamp(Math.round(blue), 0, 255),
        safeAlpha
      );
      return;
    }
  } catch (_) {}

  safeNative(
    "DRAW_RECT",
    safeX,
    safeY,
    safeWidth,
    safeHeight,
    clamp(Math.round(red), 0, 255),
    clamp(Math.round(green), 0, 255),
    clamp(Math.round(blue), 0, 255),
    safeAlpha
  );
}

function shiftForwardGear(currentGear, speedKmh) {
  let gear = clamp(Math.round(finiteNumber(currentGear, 1)), 1, 6);
  const speed = Math.max(0, finiteNumber(speedKmh, 0));

  while (gear < 6 && speed >= FORWARD_GEAR_UP_SPEEDS[gear - 1]) {
    gear += 1;
  }
  while (gear > 1 && speed < FORWARD_GEAR_DOWN_SPEEDS[gear - 2]) {
    gear -= 1;
  }
  return gear;
}

function loadConfig() {
  if (typeof IniFile === "undefined" || typeof IniFile.ReadInt !== "function") {
    log("Vehicle Speedometer DE: IniFiles64 unavailable; using defaults.");
    return;
  }

  try {
    const version = readConfigInt("meta", "config_version", CONFIG_VERSION);
    if (version !== CONFIG_VERSION && version !== 5 && version !== 6 && version !== 7) {
      log("Vehicle Speedometer DE: unsupported INI version; using defaults.");
      return;
    }

    config.enabled = readConfigBool("mod", "enabled", DEFAULTS.enabled);
    config.speedMultiplier = clamp(
      readConfigInt("units", "speed_multiplier_x100", DEFAULTS.speedMultiplier * 100) / 100,
      0.1,
      10
    );
    config.maxDisplaySpeed = clamp(
      readConfigInt("units", "max_display_speed_kmh", DEFAULTS.maxDisplaySpeed),
      40,
      999
    );
    config.smoothing = clamp(
      readConfigInt("speed", "smoothing_percent", DEFAULTS.smoothing * 100) / 100,
      0.02,
      0.5
    );
    config.speedUpdateMs = clamp(
      readConfigInt("speed", "update_interval_ms", DEFAULTS.speedUpdateMs),
      20,
      100
    );
    config.accelerationRedlineKmhPerSecond = clamp(
      readConfigInt(
        "speed",
        "acceleration_redline_kmh_per_second",
        DEFAULTS.accelerationRedlineKmhPerSecond
      ),
      20,
      250
    );
    config.neutralSpeedKmh = clamp(
      readConfigInt(
        "speed",
        "neutral_speed_kmh_x100",
        DEFAULTS.neutralSpeedKmh * 100
      ) / 100,
      0.1,
      3
    );
    config.reverseMinSpeedKmh = clamp(
      readConfigInt("speed", "reverse_min_speed_kmh", DEFAULTS.reverseMinSpeedKmh),
      1,
      20
    );
    config.reverseDotThreshold = clamp(
      readConfigInt("speed", "reverse_dot_threshold_percent", DEFAULTS.reverseDotThreshold * 100) / 100,
      0.1,
      0.9
    );
    config.animationMs = clamp(
      readConfigInt("animation", "duration_ms", DEFAULTS.animationMs),
      100,
      500
    );
    config.showDirection = readConfigBool("visual", "show_direction", DEFAULTS.showDirection);
    // Older geometry belongs to the removed panel. Preserve driving/preferences,
    // but migrate its layout to the new defaults, including on F11 reload.
    if (version < CONFIG_VERSION) {
      for (const key of [
        "anchorX",
        "anchorY",
        "unitOffsetY",
        "lowerOffsetY",
        "speedTextScale",
        "unitTextScale",
        "driveTextScale",
        "barWidth",
        "barHeight",
        "barGap",
        "barSegments",
        "speedFont",
      ]) {
        config[key] = DEFAULTS[key];
      }
    } else {
    config.anchorX = clamp(readConfigInt("layout", "anchor_x_percent", DEFAULTS.anchorX * 1000) / 1000, 0.7, 0.99);
    config.anchorY = clamp(readConfigInt("layout", "anchor_y_percent", DEFAULTS.anchorY * 1000) / 1000, 0.55, 0.95);
    config.unitOffsetY = clamp(readConfigInt("layout", "unit_offset_y_percent", DEFAULTS.unitOffsetY * 1000) / 1000, 0.01, 0.1);
    config.lowerOffsetY = clamp(readConfigInt("layout", "lower_offset_y_percent", DEFAULTS.lowerOffsetY * 1000) / 1000, 0.04, 0.2);
    config.speedTextScale = clamp(
      readConfigInt("layout", "speed_text_scale_x100", DEFAULTS.speedTextScale * 100) / 100,
      0.5,
      2
    );
    config.unitTextScale = clamp(readConfigInt("layout", "unit_text_scale_x100", DEFAULTS.unitTextScale * 100) / 100, 0.2, 1);
    config.driveTextScale = clamp(readConfigInt("layout", "drive_text_scale_x100", DEFAULTS.driveTextScale * 100) / 100, 0.2, 1);
    config.barWidth = clamp(readConfigInt("layout", "bar_width_percent", DEFAULTS.barWidth * 1000) / 1000, 0.04, 0.2);
    config.barHeight = clamp(readConfigInt("layout", "bar_height_percent", DEFAULTS.barHeight * 1000) / 1000, 0.003, 0.02);
    config.barGap = clamp(readConfigInt("layout", "bar_gap_percent", DEFAULTS.barGap * 1000) / 1000, 0.001, 0.02);
    config.barSegments = clamp(readConfigInt("layout", "bar_segments", DEFAULTS.barSegments), 4, 20);
    config.speedFont = clamp(readConfigInt("layout", "font", DEFAULTS.speedFont), 0, 3);
    }
    config.reloadHotkeyEnabled = readConfigBool(
      "input",
      "reload_hotkey_enabled",
      DEFAULTS.reloadHotkeyEnabled
    );
    config.debug = readConfigBool("debug", "enabled", DEFAULTS.debug);
    log("Vehicle Speedometer DE configuration loaded.");
  } catch (error) {
    log("Vehicle Speedometer DE: configuration load failed; using defaults. " + error);
  }
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

function toHandle(value) {
  if (value === null || value === undefined || value === false || value === -1) return null;
  if (typeof value === "object") return value;
  if (typeof Car === "undefined") return null;
  try {
    return new Car(value);
  } catch (_) {
    return null;
  }
}

function safeNative(name, ...args) {
  try {
    return native(name, ...args);
  } catch (error) {
    const count = (nativeFailureCounts.get(name) || 0) + 1;
    nativeFailureCounts.set(name, count);
    if (count === 1 && config.debug) {
      log("Vehicle Speedometer native failure: " + name + " " + error);
    }
    return null;
  }
}

function isKeyPressed(keyCode) {
  try {
    if (typeof Pad !== "undefined" && typeof Pad.IsKeyPressed === "function") {
      return !!Pad.IsKeyPressed(keyCode);
    }
  } catch (_) {}
  return safeNative("IS_KEY_PRESSED", keyCode) === true;
}

function headingVector(degrees) {
  const angle = (degrees * Math.PI) / 180;
  return { x: Math.sin(angle), y: Math.cos(angle), z: 0 };
}

function isVector(value) {
  return !!value &&
    Number.isFinite(Number(value.x)) &&
    Number.isFinite(Number(value.y)) &&
    Number.isFinite(Number(value.z));
}

function vectorLength(value) {
  if (!isVector(value)) return 0;
  return Math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z);
}

function finiteNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function formatSpeed(value) {
  return String(Math.round(clamp(finiteNumber(value, 0), 0, 999)));
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}
