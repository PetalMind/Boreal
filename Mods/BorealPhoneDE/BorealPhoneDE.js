/// <reference path="./.config/sa.d.ts" />

// Boreal Phone DE for GTA San Andreas: The Definitive Edition.
// Runtime: CLEO Redux x64 + IniFiles64.
//
// The phone is a small native HUD layer. It deliberately delegates the two
// useful actions to the game: ACTIVATE_SAVE_MENU opens the original save
// screen, while SET_RADIO_CHANNEL changes the game's radio channel.

if (typeof HOST === "undefined" || HOST !== "sa_unreal") {
  exit("Boreal Phone DE supports only GTA San Andreas: The Definitive Edition.");
}

const PLAYER_ID = 0;
const CONFIG_PATH = "./BorealPhoneDE.ini";
const CONFIG_VERSION = 1;

const VK_BACKSPACE = 8;
const VK_RETURN = 13;
const VK_ESCAPE = 27;
const VK_SPACE = 32;
const VK_LEFT = 37;
const VK_UP = 38;
const VK_RIGHT = 39;
const VK_DOWN = 40;
const VK_F8 = 119;
const VK_F11 = 122;
const VK_A = 65;
const VK_D = 68;
const VK_S = 83;
const VK_W = 87;

const PAD_ID = 0;
const PAD_DPAD_UP = 8;
const PAD_DPAD_DOWN = 9;
const PAD_DPAD_LEFT = 10;
const PAD_DPAD_RIGHT = 11;
const PAD_CROSS = 16;
const PAD_CIRCLE = 17;

const HUD_VIRTUAL_WIDTH = 640;
const HUD_VIRTUAL_HEIGHT = 448;

const PHONE_X = 0.685;
const PHONE_Y = 0.075;
const PHONE_W = 0.255;
const PHONE_H = 0.85;
const SCREEN_X = PHONE_X + 0.017;
const SCREEN_Y = PHONE_Y + 0.065;
const SCREEN_W = PHONE_W - 0.034;
const SCREEN_H = PHONE_H - 0.105;
const ROW_X = SCREEN_X + 0.018;
const ROW_W = SCREEN_W - 0.036;

const HOME_ITEMS = [
  { key: "BPHSAVE", label: "ZAPIS GRY" },
  { key: "BPHRADI", label: "RADIO" },
  { key: "BPHQUIT", label: "ZAMKNIJ" },
];

// Values come from the SA:DE RadioChannel enum in the CLEO definition file.
const RADIO_STATIONS = [
  { value: 0, label: "Playback FM" },
  { value: 1, label: "K-Rose" },
  { value: 2, label: "K-DST" },
  { value: 3, label: "Bounce FM" },
  { value: 4, label: "SF-UR" },
  { value: 5, label: "Radio Los Santos" },
  { value: 6, label: "Radio X" },
  { value: 7, label: "CSR 103.9" },
  { value: 8, label: "K-Jah West" },
  { value: 9, label: "Master Sounds 98.3" },
  { value: 10, label: "WCTR" },
  { value: 11, label: "User Tracks" },
  { value: 12, label: "WYLACZ RADIO" },
];

const DEFAULTS = {
  enabled: true,
  openKey: VK_F8,
  freezePlayer: true,
  debug: false,
};

const config = { ...DEFAULTS };
const player = new Player(PLAYER_ID);
const keyStates = new Map();
const buttonStates = new Map();
const nativeFailureCounts = new Map();

let phoneOpen = false;
let phoneView = "home";
let homeSelection = 0;
let radioSelection = 0;
let radioScroll = 0;
let lockedActor = null;
let statusText = "";
let statusUntil = 0;
let textStoreFailureLogged = false;
let lastFrameFailureAt = 0;

loadConfig();
log("Boreal Phone DE loaded. Press F8 to open the phone.");

while (true) {
  wait(0);
  const now = Date.now();

  if (justPressed(VK_F11)) {
    loadConfig();
    log("Boreal Phone DE configuration reloaded.");
  }

  if (!config.enabled) {
    if (phoneOpen) closePhone();
    continue;
  }

  try {
    handleInput(now);
    if (phoneOpen) {
      if (!getPlayerActor()) {
        closePhone();
      } else {
        renderPhone(now);
      }
    }
  } catch (error) {
    if (now - lastFrameFailureAt >= 1000) {
      lastFrameFailureAt = now;
      log("Boreal Phone DE: frame recovered from error: " + error);
    }
    if (phoneOpen) closePhone();
  }
}

function handleInput(now) {
  if (justPressed(config.openKey)) {
    if (phoneOpen) {
      closePhone();
    } else {
      openPhone();
    }
    return;
  }

  if (!phoneOpen) return;

  if (justPressed(VK_ESCAPE) || justPressed(VK_BACKSPACE) || justPressedButton(PAD_CIRCLE)) {
    if (phoneView === "radio") {
      phoneView = "home";
      homeSelection = 1;
    } else {
      closePhone();
    }
    return;
  }

  if (phoneView === "home") {
    handleHomeInput();
  } else {
    handleRadioInput(now);
  }
}

function handleHomeInput() {
  if (justPressedAny([VK_UP, VK_W]) || justPressedButton(PAD_DPAD_UP)) {
    homeSelection = wrapIndex(homeSelection - 1, HOME_ITEMS.length);
  }
  if (justPressedAny([VK_DOWN, VK_S]) || justPressedButton(PAD_DPAD_DOWN)) {
    homeSelection = wrapIndex(homeSelection + 1, HOME_ITEMS.length);
  }
  if (justPressedAny([VK_RETURN, VK_SPACE]) || justPressedButton(PAD_CROSS)) {
    if (homeSelection === 0) {
      activateSaveMenu();
    } else if (homeSelection === 1) {
      openRadioView();
    } else {
      closePhone();
    }
  }
}

function handleRadioInput(now) {
  if (justPressedAny([VK_UP, VK_W]) || justPressedButton(PAD_DPAD_UP)) {
    radioSelection = wrapIndex(radioSelection - 1, RADIO_STATIONS.length);
    keepRadioSelectionVisible();
  }
  if (justPressedAny([VK_DOWN, VK_S]) || justPressedButton(PAD_DPAD_DOWN)) {
    radioSelection = wrapIndex(radioSelection + 1, RADIO_STATIONS.length);
    keepRadioSelectionVisible();
  }
  // Left/right are accepted as a quick radio action, but do not move the
  // cursor by two items when both directions are held at the same time.
  const leftPressed = justPressed(VK_LEFT) || justPressed(VK_A);
  const rightPressed = justPressed(VK_RIGHT) || justPressed(VK_D);
  if (leftPressed !== rightPressed) {
    radioSelection = wrapIndex(
      radioSelection + (leftPressed ? -1 : 1),
      RADIO_STATIONS.length
    );
    keepRadioSelectionVisible();
  }
  if (justPressedAny([VK_RETURN, VK_SPACE]) || justPressedButton(PAD_CROSS)) {
    applyRadioSelection(now);
  }
}

function openPhone() {
  const actor = getPlayerActor();
  if (!actor) return;

  phoneOpen = true;
  phoneView = "home";
  homeSelection = 0;
  radioSelection = 0;
  radioScroll = 0;
  statusText = "";
  statusUntil = 0;
  lockedActor = actor;

  setPlayerControl(false);
  if (config.freezePlayer) {
    callNative("FREEZE_CHAR_POSITION", lockedActor, true);
  }
}

function closePhone() {
  if (!phoneOpen) return;

  phoneOpen = false;
  phoneView = "home";
  if (config.freezePlayer && lockedActor) {
    callNative("FREEZE_CHAR_POSITION", lockedActor, false);
  }
  lockedActor = null;
  setPlayerControl(true);
}

function activateSaveMenu() {
  // Close first so the phone's control lock cannot interfere with the game's
  // own save screen. ACTIVATE_SAVE_MENU is the real native save flow.
  closePhone();
  const result = callNative("ACTIVATE_SAVE_MENU");
  if (!result.ok && typeof showTextBox === "function") {
    showTextBox("Boreal Phone: save menu is unavailable on this build.");
  }
}

function openRadioView() {
  phoneView = "radio";
  const current = callNative("GET_RADIO_CHANNEL");
  const currentValue = normalizeRadioChannel(current.value);
  radioSelection = RADIO_STATIONS.findIndex((station) => station.value === currentValue);
  if (radioSelection < 0) radioSelection = 0;
  radioScroll = 0;
  keepRadioSelectionVisible();
}

function applyRadioSelection(now) {
  const station = RADIO_STATIONS[radioSelection];
  const actor = getPlayerActor();
  if (!actor || callNative("IS_CHAR_IN_ANY_CAR", actor).value !== true) {
    setStatus("RADIO DOSTEPNE W POJEZDZIE", now);
    return;
  }

  const result = callNative("SET_RADIO_CHANNEL", station.value);
  if (!result.ok) {
    setStatus("RADIO NIEOBSLUGIWANE", now);
    return;
  }
  setStatus("USTAWIONO: " + station.label.toUpperCase(), now);
}

function setStatus(value, now) {
  statusText = value;
  statusUntil = now + 2400;
}

function renderPhone(now) {
  updateTextStore(now);

  drawHudRect(0.5, 0.5, 1, 1, 0, 0, 0, 70);
  drawHudRect(PHONE_X + PHONE_W / 2 + 0.008, PHONE_Y + PHONE_H / 2 + 0.012,
    PHONE_W + 0.016, PHONE_H + 0.016, 0, 0, 0, 180);
  drawHudRect(PHONE_X + PHONE_W / 2, PHONE_Y + PHONE_H / 2,
    PHONE_W, PHONE_H, 18, 22, 30, 255);
  drawHudRect(SCREEN_X + SCREEN_W / 2, SCREEN_Y + SCREEN_H / 2,
    SCREEN_W, SCREEN_H, 5, 10, 16, 255);

  drawHudRect(PHONE_X + PHONE_W / 2, PHONE_Y + 0.029, 0.065, 0.008, 65, 72, 84, 255);
  drawHudRect(PHONE_X + PHONE_W - 0.031, PHONE_Y + 0.029, 0.008, 0.008, 64, 203, 174, 255);

  if (phoneView === "home") {
    renderHomeView();
  } else {
    renderRadioView();
  }

  if (statusText && now < statusUntil) {
    drawText("BPHSTAT", SCREEN_X + SCREEN_W / 2, PHONE_Y + PHONE_H - 0.082,
      0.34, 86, 219, 188, 255, true);
  }
}

function renderHomeView() {
  drawText("BPHNTTL", SCREEN_X + SCREEN_W / 2, SCREEN_Y + 0.045,
    0.62, 238, 242, 246, 255, true);
  drawText("BPHINFO", SCREEN_X + SCREEN_W / 2, SCREEN_Y + 0.092,
    0.30, 130, 143, 158, 255, true);

  for (let index = 0; index < HOME_ITEMS.length; index += 1) {
    drawMenuRow(index, HOME_ITEMS[index].key, SCREEN_Y + 0.155 + index * 0.095,
      index === homeSelection);
  }

  drawText("BPHHELP", SCREEN_X + SCREEN_W / 2, PHONE_Y + PHONE_H - 0.041,
    0.29, 134, 147, 161, 255, true);
}

function renderRadioView() {
  drawText("BPHRADT", SCREEN_X + SCREEN_W / 2, SCREEN_Y + 0.043,
    0.55, 238, 242, 246, 255, true);

  const visibleCount = 10;
  for (let row = 0; row < visibleCount; row += 1) {
    const stationIndex = radioScroll + row;
    if (stationIndex >= RADIO_STATIONS.length) break;
    drawMenuRow(row, radioTextKey(stationIndex), SCREEN_Y + 0.115 + row * 0.052,
      stationIndex === radioSelection, 0.31);
  }

  drawText("BPHBACK", SCREEN_X + SCREEN_W / 2, PHONE_Y + PHONE_H - 0.041,
    0.29, 134, 147, 161, 255, true);
}

function drawMenuRow(row, textKey, y, selected, textScale) {
  const scale = textScale || 0.39;
  drawHudRect(ROW_X + ROW_W / 2, y + 0.019, ROW_W, 0.052,
    selected ? 37 : 15, selected ? 115 : 23, selected ? 112 : 31,
    selected ? 245 : 220);
  drawHudRect(ROW_X + ROW_W / 2, y + 0.019, ROW_W - 0.006, 0.046,
    selected ? 26 : 8, selected ? 77 : 14, selected ? 77 : 20,
    selected ? 245 : 235);
  drawText(textKey, ROW_X + 0.014, y + 0.009, scale,
    selected ? 240 : 205, selected ? 255 : 213, selected ? 234 : 222, 255, false);
}

function updateTextStore(now) {
  if (typeof FxtStore === "undefined" || !FxtStore || typeof FxtStore.insert !== "function") {
    if (!textStoreFailureLogged) {
      textStoreFailureLogged = true;
      log("Boreal Phone DE: FxtStore is unavailable; phone labels are disabled.");
    }
    return;
  }

  try {
    putText("BPHNTTL", phoneView === "home" ? "TELEFON" : "RADIO");
    putText("BPHINFO", "BOREAL PHONE");
    putText("BPHHELP", "GORA/DOL  ENTER  ESC");
    putText("BPHBACK", "ESC  POWROT");
    putText("BPHSAVE", "ZAPIS GRY");
    putText("BPHRADI", "RADIO");
    putText("BPHQUIT", "ZAMKNIJ");
    putText("BPHRADT", "RADIO");
    putText("BPHSTAT", statusText);
    for (let index = 0; index < RADIO_STATIONS.length; index += 1) {
      putText(radioTextKey(index), RADIO_STATIONS[index].label);
    }
  } catch (error) {
    if (!textStoreFailureLogged) {
      textStoreFailureLogged = true;
      log("Boreal Phone DE: FxtStore update failed: " + error);
    }
  }
}

function putText(key, value) {
  FxtStore.insert(key, value || "");
}

function drawText(key, x, y, scale, red, green, blue, alpha, centered) {
  callNative("USE_TEXT_COMMANDS", true);
  callNative("SET_TEXT_FONT", 2);
  callNative("SET_TEXT_SCALE", scale, scale);
  callNative("SET_TEXT_COLOUR", red, green, blue, alpha);
  callNative("SET_TEXT_PROPORTIONAL", true);
  callNative("SET_TEXT_BACKGROUND", false);
  callNative("SET_TEXT_EDGE", 1, 0, 0, 0, alpha);
  callNative("SET_TEXT_CENTRE", centered === true);
  callNative("SET_TEXT_JUSTIFY", false);
  callNative("SET_TEXT_RIGHT_JUSTIFY", false);
  callNative("SET_TEXT_DROPSHADOW", 2, 0, 0, 0, alpha);
  callNative("DISPLAY_TEXT", x * HUD_VIRTUAL_WIDTH, y * HUD_VIRTUAL_HEIGHT, key);
  callNative("USE_TEXT_COMMANDS", false);
}

function drawHudRect(x, y, width, height, red, green, blue, alpha) {
  callNative("DRAW_RECT", x, y, width, height, red, green, blue, alpha);
}

function keepRadioSelectionVisible() {
  const visibleCount = 10;
  if (radioSelection < radioScroll) radioScroll = radioSelection;
  if (radioSelection >= radioScroll + visibleCount) {
    radioScroll = radioSelection - visibleCount + 1;
  }
  radioScroll = Math.max(0, Math.min(radioScroll, RADIO_STATIONS.length - visibleCount));
}

function radioTextKey(index) {
  return "BPHR" + String(index).padStart(2, "0");
}

function normalizeRadioChannel(value) {
  if (Number.isFinite(Number(value))) return Number(value);
  if (value && Number.isFinite(Number(value.channel))) return Number(value.channel);
  return 0;
}

function wrapIndex(value, length) {
  return ((value % length) + length) % length;
}

function getPlayerActor() {
  try {
    if (!player.isPlaying()) return null;
    const actor = player.getChar();
    if (!actor || callNative("IS_CHAR_DEAD", actor).value === true) return null;
    return actor;
  } catch (_) {
    return null;
  }
}

function setPlayerControl(enabled) {
  const playerResult = callNative("SET_PLAYER_CONTROL", player, enabled);
  if (!playerResult.ok) {
    callNative("SET_PLAYER_CONTROL", PLAYER_ID, enabled);
  }
}

function justPressedAny(keys) {
  let result = false;
  for (const key of keys) {
    if (justPressed(key)) result = true;
  }
  return result;
}

function justPressed(keyCode) {
  const down = isKeyDown(keyCode);
  const wasDown = keyStates.get(keyCode) === true;
  keyStates.set(keyCode, down);
  return down && !wasDown;
}

function justPressedButton(button) {
  const down = isButtonDown(button);
  const wasDown = buttonStates.get(button) === true;
  buttonStates.set(button, down);
  return down && !wasDown;
}

function isKeyDown(keyCode) {
  try {
    if (typeof Pad !== "undefined" && typeof Pad.IsKeyPressed === "function") {
      return !!Pad.IsKeyPressed(keyCode);
    }
  } catch (_) {}
  const result = callNative("IS_KEY_PRESSED", keyCode);
  return result.ok && result.value === true;
}

function isButtonDown(button) {
  try {
    if (typeof Pad !== "undefined" && typeof Pad.IsButtonPressed === "function") {
      return !!Pad.IsButtonPressed(PAD_ID, button);
    }
  } catch (_) {}
  const result = callNative("IS_BUTTON_PRESSED", PAD_ID, button);
  return result.ok && result.value === true;
}

function callNative(name, ...args) {
  try {
    return { ok: true, value: native(name, ...args) };
  } catch (error) {
    const count = (nativeFailureCounts.get(name) || 0) + 1;
    nativeFailureCounts.set(name, count);
    if (count === 1 || config.debug) {
      log("Boreal Phone DE native failure: " + name + " " + error);
    }
    return { ok: false, value: undefined };
  }
}

function loadConfig() {
  if (typeof IniFile === "undefined" || typeof IniFile.ReadInt !== "function") {
    log("Boreal Phone DE: IniFiles64 unavailable; using defaults.");
    return;
  }

  try {
    const version = readConfigInt("meta", "config_version", CONFIG_VERSION);
    if (version !== CONFIG_VERSION) {
      log("Boreal Phone DE: unsupported INI version; using defaults.");
      return;
    }
    config.enabled = readConfigBool("mod", "enabled", DEFAULTS.enabled);
    config.openKey = clamp(readConfigInt("input", "open_key", DEFAULTS.openKey), 32, 255);
    config.freezePlayer = readConfigBool("input", "freeze_player", DEFAULTS.freezePlayer);
    config.debug = readConfigBool("debug", "enabled", DEFAULTS.debug);
  } catch (error) {
    log("Boreal Phone DE: configuration read failed; using defaults: " + error);
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

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}
