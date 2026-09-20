/// <reference path="./.config/sa.d.ts" />

// Boreal Phone DE for GTA San Andreas: The Definitive Edition.
// Runtime: CLEO Redux x64 + IniFiles64.
//
// Native HUD phone: save menu, vehicle radio, and Ammu-Nation purchases.

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
  { key: "BPHARMS", label: "ZBROJOWNIA" },
  { key: "BPHCHEAT", label: "CHEATY" },
  { key: "BPHQUIT", label: "ZAMKNIJ" },
];

// Base Ammu-Nation prices and ammo bundles (not the Las Venturas +20% tariff).
// Source: https://www.igrandtheftauto.com/gtasa/guides/ammu-nation
// This remote shop intentionally does not impose story unlocks.
const ARMORY = [
  { label: "PISTOLETY", items: [
    { label: "9mm", weapon: 22, price: 200, ammo: 30 },
    { label: "9mm z tlumikiem", weapon: 23, price: 600, ammo: 30 },
    { label: "Desert Eagle", weapon: 24, price: 1200, ammo: 15 },
  ] },
  { label: "PISTOLETY MASZYNOWE", items: [
    { label: "Tec-9", weapon: 32, price: 300, ammo: 60 },
    { label: "Micro SMG", weapon: 28, price: 500, ammo: 60 },
    { label: "SMG", weapon: 29, price: 2000, ammo: 90 },
  ] },
  { label: "STRZELBY", items: [
    { label: "Shotgun", weapon: 25, price: 600, ammo: 15 },
    { label: "Sawnoff Shotgun", weapon: 26, price: 800, ammo: 12 },
    { label: "Combat Shotgun", weapon: 27, price: 1000, ammo: 10 },
  ] },
  { label: "KARABINY", items: [
    { label: "AK-47", weapon: 30, price: 3500, ammo: 120 },
    { label: "M4", weapon: 31, price: 4500, ammo: 150 },
    { label: "Rifle", weapon: 33, price: 1000, ammo: 20 },
    { label: "Sniper Rifle", weapon: 34, price: 5000, ammo: 10 },
  ] },
  { label: "MATERIALY WYBUCHOWE", items: [
    { label: "Granaty", weapon: 16, price: 300, ammo: 5 },
    { label: "Ladunek z detonatorem", weapon: 39, price: 2000, ammo: 1 },
  ] },
  { label: "OCHRONA", items: [
    { label: "Kamizelka", price: 200, armor: true },
  ] },
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
const keyEdges = new Map();
const buttonEdges = new Map();
const nativeFailureCounts = new Map();

let phoneOpen = false;
let phoneView = "home";
let homeSelection = 0;
let radioSelection = 0;
let radioScroll = 0;
let categorySelection = 0;
let productSelection = 0;
let pendingPurchase = null;
let purchaseFault = false;
let actorFrozen = false;
let missionWasActive = false;
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
  pollInput();

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
    updatePurchase(now);
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
    cancelPurchase();
    if (phoneView === "radio") {
      phoneView = "home";
      homeSelection = 1;
    } else if (phoneView === "confirm") {
      phoneView = "products";
    } else if (phoneView === "products") {
      phoneView = "categories";
    } else if (phoneView === "categories") {
      phoneView = "home";
      homeSelection = 2;
    } else if (phoneView === "cheats") {
      phoneView = "home";
      homeSelection = 3;
    } else {
      closePhone();
    }
    return;
  }

  if (phoneView === "home") {
    handleHomeInput();
  } else if (phoneView === "radio") {
    handleRadioInput(now);
  } else if (phoneView === "cheats") {
    handleCheatInput(now);
  } else {
    handleArmoryInput(now);
  }
}

function handleHomeInput() {
  if (justPressedAny([VK_UP, VK_W, VK_LEFT, VK_A]) ||
      justPressedButton(PAD_DPAD_UP) || justPressedButton(PAD_DPAD_LEFT)) {
    homeSelection = wrapIndex(homeSelection - 1, HOME_ITEMS.length);
  }
  if (justPressedAny([VK_DOWN, VK_S, VK_RIGHT, VK_D]) ||
      justPressedButton(PAD_DPAD_DOWN) || justPressedButton(PAD_DPAD_RIGHT)) {
    homeSelection = wrapIndex(homeSelection + 1, HOME_ITEMS.length);
  }
  if (justPressedAny([VK_RETURN, VK_SPACE]) || justPressedButton(PAD_CROSS)) {
    if (homeSelection === 0) {
      activateSaveMenu();
    } else if (homeSelection === 1) {
      openRadioView();
    } else if (homeSelection === 2) {
      phoneView = "categories";
      categorySelection = 0;
      statusText = "";
    } else if (homeSelection === 3) {
      phoneView = "cheats";
      statusText = "";
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
  missionWasActive = callNative("CAN_PLAYER_START_MISSION", player).value !== true;

  setPlayerControl(false);
  if (config.freezePlayer) {
    actorFrozen = callNative("FREEZE_CHAR_POSITION", lockedActor, true).ok;
  }
}

function closePhone() {
  if (!phoneOpen) return;

  phoneOpen = false;
  cancelPurchase();
  phoneView = "home";
  missionWasActive = false;
  if (actorFrozen && lockedActor) {
    callNative("FREEZE_CHAR_POSITION", lockedActor, false);
  }
  lockedActor = null;
  actorFrozen = false;
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

function readNativeNumber(name, field, ...args) {
  const result = callNative(name, ...args);
  if (!result.ok) return null;
  const value = typeof result.value === "number" ? result.value : result.value?.[field];
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function wallet() {
  return readNativeNumber("STORE_SCORE", "money", PLAYER_ID);
}

function selectedProduct() {
  return ARMORY[categorySelection].items[productSelection];
}

function handleArmoryInput(now) {
  if (pendingPurchase) return;
  const previous = justPressedAny([VK_UP, VK_W, VK_LEFT, VK_A]) || justPressedButton(PAD_DPAD_UP);
  const next = justPressedAny([VK_DOWN, VK_S, VK_RIGHT, VK_D]) || justPressedButton(PAD_DPAD_DOWN);
  const direction = Number(next) - Number(previous);
  if (phoneView === "categories") {
    categorySelection = wrapIndex(categorySelection + direction, ARMORY.length);
  } else if (phoneView === "products") {
    productSelection = wrapIndex(productSelection + direction, ARMORY[categorySelection].items.length);
  }
  if (!justPressedAny([VK_RETURN, VK_SPACE]) && !justPressedButton(PAD_CROSS)) return;
  statusText = "";
  if (phoneView === "categories") {
    productSelection = 0;
    phoneView = "products";
  } else if (phoneView === "products") {
    phoneView = "confirm";
  } else if (phoneView === "confirm") {
    beginPurchase(now);
  }
}

function handleCheatInput(now) {
  if (!justPressedAny([VK_RETURN, VK_SPACE]) && !justPressedButton(PAD_CROSS)) return;
  if (!missionWasActive) {
    setStatus("BRAK AKTYWNEJ MISJI", now);
    return;
  }
  // SA:DE exposes cleanup and pass registration, but not the mission's
  // internal success callback. Cleanup is therefore intentionally explicit.
  const finished = callNative("MISSION_HAS_FINISHED");
  if (!finished.ok) {
    setStatus("CHEAT NIEDOSTEPNY", now);
    return;
  }
  callNative("REGISTER_MISSION_PASSED", "MISSION_PASSED");
  callNative("PLAY_MISSION_PASSED_TUNE", 1);
  missionWasActive = false;
  setStatus("MISJA UKONCZONA", now);
}

function snapshotSlot(actor, weapon) {
  const slot = readNativeNumber("GET_WEAPONTYPE_SLOT", "slot", weapon);
  if (slot === null) throw new Error("Weapon slot unavailable");
  const result = callNative("GET_CHAR_WEAPON_IN_SLOT", actor, slot);
  const value = result.value;
  if (!result.ok || !value || !Number.isInteger(value.weaponType) ||
      !Number.isInteger(value.weaponAmmo) || !Number.isInteger(value.weaponModel)) {
    throw new Error("Weapon inventory unavailable");
  }
  return { slot, weapon: value.weaponType, ammo: value.weaponAmmo, model: value.weaponModel };
}

function beginPurchase(now) {
  if (purchaseFault) {
    setStatus("SKLEP ZABLOKOWANY~n~SPRAWDZ LOG CLEO", now);
    return;
  }
  const actor = getPlayerActor();
  const item = selectedProduct();
  const money = wallet();
  if (!actor || money === null) {
    setStatus("BRAK DANYCH GRACZA", now);
    return;
  }
  if (money < item.price) {
    setStatus("BRAKUJE $" + (item.price - money), now);
    return;
  }
  const purchase = { actor, item, models: [], grants: [], startedAt: now };
  pendingPurchase = purchase;
  try {
    if (item.armor) {
      const armor = readNativeNumber("GET_CHAR_ARMOUR", "armor", actor);
      const maximum = readNativeNumber("GET_PLAYER_MAX_ARMOUR", "maxArmour", PLAYER_ID);
      if (armor === null || maximum === null || maximum <= 0) throw new Error("Armor unavailable");
      if (armor >= maximum) {
        cancelPurchase();
        setStatus("KAMIZELKA JEST PELNA", now);
        return;
      }
    } else {
      const weapons = [{ weapon: item.weapon, ammo: item.ammo }];
      // Satchel charges also need the remote detonator in its separate slot.
      if (item.weapon === 39) weapons.push({ weapon: 40, ammo: 1 });
      for (const grant of weapons) {
        const before = snapshotSlot(actor, grant.weapon);
        const model = readNativeNumber("GET_WEAPONTYPE_MODEL", "modelId", grant.weapon);
        if (model === null || model <= 0) throw new Error("Weapon model unavailable");
        if (before.weapon === grant.weapon && before.ammo + grant.ammo > 99999) {
          cancelPurchase();
          setStatus("LIMIT AMUNICJI", now);
          return;
        }
        purchase.grants.push({ ...grant, before });
        for (const modelId of [model, before.model]) {
          if (modelId > 0 && !purchase.models.includes(modelId)) {
            purchase.models.push(modelId);
            if (!callNative("REQUEST_MODEL", modelId).ok) throw new Error("Model request failed");
          }
        }
      }
    }
    setStatus("PRZYGOTOWYWANIE ZAKUPU", now);
  } catch (error) {
    log("Boreal Phone armory preparation: " + error);
    cancelPurchase();
    setStatus("ZAKUP NIEDOSTEPNY~n~NIE POBRANO PIENIEDZY", now);
  }
}

function cancelPurchase() {
  if (!pendingPurchase) return;
  for (const model of pendingPurchase.models) callNative("MARK_MODEL_AS_NO_LONGER_NEEDED", model);
  pendingPurchase = null;
}

function updatePurchase(now) {
  const purchase = pendingPurchase;
  if (!purchase) return;
  if (!phoneOpen || !getPlayerActor()) {
    cancelPurchase();
    return;
  }
  if (now - purchase.startedAt > 5000) {
    cancelPurchase();
    setStatus("MODEL NIEDOSTEPNY~n~NIE POBRANO PIENIEDZY", now);
    return;
  }
  if (purchase.models.some(model => callNative("HAS_MODEL_LOADED", model).value !== true)) return;
  // Recheck everything after streaming. No waits occur inside the transaction.
  const { actor, item } = purchase;
  const money = wallet();
  if (money === null || money < item.price) {
    cancelPurchase();
    setStatus(money === null ? "SALDO NIEDOSTEPNE" : "ZA MALO PIENIEDZY", now);
    return;
  }
  let armorBefore = null;
  let armorTarget = null;
  let charged = false;
  let mutated = false;
  try {
    if (item.armor) {
      armorBefore = readNativeNumber("GET_CHAR_ARMOUR", "armor", actor);
      armorTarget = readNativeNumber("GET_PLAYER_MAX_ARMOUR", "maxArmour", PLAYER_ID);
      if (armorBefore === null || armorTarget === null || armorTarget <= armorBefore) {
        throw new Error("Armor no longer needs replenishing");
      }
    }
    for (const grant of purchase.grants) {
      const current = snapshotSlot(actor, grant.weapon);
      if (current.weapon !== grant.before.weapon || current.ammo !== grant.before.ammo) {
        throw new Error("Inventory changed while streaming");
      }
    }
    callNative("ADD_SCORE", PLAYER_ID, -item.price);
    const afterDebit = wallet();
    if (afterDebit !== money - item.price) {
      if (afterDebit !== money) purchaseFault = true;
      throw new Error("Cannot confirm wallet debit");
    }
    charged = true;
    mutated = true;
    if (item.armor) {
      callNative("ADD_ARMOUR_TO_CHAR", actor, armorTarget - armorBefore);
      if (readNativeNumber("GET_CHAR_ARMOUR", "armor", actor) !== armorTarget) {
        throw new Error("Armor delivery failed");
      }
    } else {
      for (const grant of purchase.grants) {
        callNative("GIVE_WEAPON_TO_CHAR", actor, grant.weapon, grant.ammo);
        const after = snapshotSlot(actor, grant.weapon);
        const expected = (grant.before.weapon === grant.weapon ? grant.before.ammo : 0) + grant.ammo;
        if (after.weapon !== grant.weapon || after.ammo < expected) throw new Error("Weapon delivery failed");
      }
    }
    phoneView = "products";
    setStatus("KUPIONO: -$" + item.price, now);
  } catch (error) {
    log("Boreal Phone armory transaction: " + error);
    if (mutated) {
      // Restore the original slot, including a replaced weapon and its ammo.
      if (item.armor) {
        const armorNow = readNativeNumber("GET_CHAR_ARMOUR", "armor", actor);
        if (armorNow !== null) callNative("ADD_ARMOUR_TO_CHAR", actor, armorBefore - armorNow);
        if (readNativeNumber("GET_CHAR_ARMOUR", "armor", actor) !== armorBefore) purchaseFault = true;
      } else {
        for (const grant of purchase.grants) {
          callNative("REMOVE_WEAPON_FROM_CHAR", actor, grant.weapon);
          if (grant.before.weapon !== 0) {
            callNative("GIVE_WEAPON_TO_CHAR", actor, grant.before.weapon, 0);
            callNative("SET_CHAR_AMMO", actor, grant.before.weapon, grant.before.ammo);
          }
          try {
            const restored = snapshotSlot(actor, grant.weapon);
            if (restored.weapon !== grant.before.weapon || restored.ammo !== grant.before.ammo) purchaseFault = true;
          } catch (_) { purchaseFault = true; }
        }
      }
    }
    if (charged) {
      callNative("ADD_SCORE", PLAYER_ID, item.price);
      if (wallet() !== money) purchaseFault = true;
    }
    setStatus(purchaseFault ? "BLAD STANU GRY~n~SPRAWDZ LOG CLEO" : "ZAKUP ANULOWANY~n~SALDO BEZ ZMIAN", now);
  } finally {
    cancelPurchase();
  }
}

// All geometry uses normalized layout coordinates and is converted exactly once
// at the native boundary. SA:DE DRAW_RECT and DISPLAY_TEXT share 640x448.
function renderPhone(now) {
  updateTextStore(now);
  callNative("USE_TEXT_COMMANDS", true);
  try {
    drawHudRect(PHONE_X + PHONE_W / 2 + 0.006, PHONE_Y + PHONE_H / 2 + 0.008,
      PHONE_W + 0.014, PHONE_H + 0.012, 0, 0, 0, 170);
    drawHudRect(PHONE_X + PHONE_W / 2, PHONE_Y + PHONE_H / 2,
      PHONE_W, PHONE_H, 48, 49, 55, 255);
    drawHudRect(PHONE_X + PHONE_W / 2, PHONE_Y + PHONE_H / 2,
      PHONE_W - 0.004, PHONE_H - 0.008, 10, 11, 15, 255);
    drawHudRect(SCREEN_X + SCREEN_W / 2, SCREEN_Y + SCREEN_H / 2,
      SCREEN_W, SCREEN_H, 22, 21, 32, 255);
    // Graphic wallpaper: stepped purple/cyan shapes, no external textures.
    for (let i = 0; i < 7; i += 1) {
      drawHudRect(SCREEN_X + SCREEN_W - 0.010 - i * 0.014,
        SCREEN_Y + 0.20 + i * 0.056, 0.019, 0.14, 48, 33, 76, 180);
    }
    drawHudRect(SCREEN_X + 0.024, SCREEN_Y + 0.49, 0.048, 0.005, 0, 210, 209, 255);
    drawHudRect(SCREEN_X + 0.012, SCREEN_Y + 0.502, 0.024, 0.005, 0, 210, 209, 255);
    drawHudRect(PHONE_X + PHONE_W / 2, PHONE_Y + 0.029, 0.052, 0.005, 80, 82, 88, 255);
    drawHudRect(PHONE_X + PHONE_W / 2, PHONE_Y + PHONE_H - 0.018,
      0.048, 0.004, 148, 150, 163, 255);
    drawText("BPHINFO", ROW_X, SCREEN_Y + 0.013, 0.30, 198, 203, 219, 255, false);
    drawText("BPHNTTL", ROW_X, SCREEN_Y + 0.057,
      phoneView === "home" || phoneView === "radio" ? 0.64 : 0.44, 255, 255, 255, 255, false);
    if (phoneView === "home") renderHomeView();
    else if (phoneView === "radio") renderRadioView();
    else if (phoneView === "cheats") renderCheatView();
    else renderArmoryView();
    drawHudRect(SCREEN_X + SCREEN_W / 2, SCREEN_Y + SCREEN_H - 0.040,
      SCREEN_W, 0.080, 12, 13, 19, 255);
    drawText(phoneView === "home" ? "BPHHELP" : phoneView === "radio" ? "BPHBACK" : phoneView === "cheats" ? "BPHSHELLP" : "BPHSHOP",
      SCREEN_X + SCREEN_W / 2, SCREEN_Y + SCREEN_H - 0.056,
      0.29, 207, 214, 229, 255, true);
    if (statusText && now < statusUntil) {
      drawHudRect(SCREEN_X + SCREEN_W / 2, SCREEN_Y + SCREEN_H - 0.124,
        SCREEN_W - 0.015, 0.070, 12, 62, 65, 255);
      drawText("BPHSTAT", SCREEN_X + SCREEN_W / 2, SCREEN_Y + SCREEN_H - 0.145,
        0.29, 220, 255, 248, 255, true);
    }
  } finally {
    callNative("USE_TEXT_COMMANDS", false);
  }
}

function renderHomeView() {
  drawText("BPHSUB", ROW_X, SCREEN_Y + 0.126, 0.30, 159, 167, 189, 255, false);
  // Two-column launcher; the lower row holds the armory and close action.
  drawAppTile(0, ROW_X + 0.042, SCREEN_Y + 0.265, [25, 181, 184]);
  drawAppTile(1, ROW_X + ROW_W - 0.042, SCREEN_Y + 0.265, [225, 62, 111]);
  drawText("BPHSAVE", ROW_X + 0.042, SCREEN_Y + 0.333, 0.33, 244, 247, 252, 255, true);
  drawText("BPHRADI", ROW_X + ROW_W - 0.042, SCREEN_Y + 0.333, 0.33, 244, 247, 252, 255, true);
  drawAppTile(2, ROW_X + 0.042, SCREEN_Y + 0.465, [205, 132, 27]);
  drawAppTile(3, SCREEN_X + SCREEN_W / 2, SCREEN_Y + 0.465, [210, 72, 68]);
  drawAppTile(4, ROW_X + ROW_W - 0.042, SCREEN_Y + 0.465, [65, 70, 88]);
  drawText("BPHARMS", ROW_X + 0.042, SCREEN_Y + 0.533, 0.29, 244, 247, 252, 255, true);
  drawText("BPHCHEAT", SCREEN_X + SCREEN_W / 2, SCREEN_Y + 0.533, 0.27, 244, 247, 252, 255, true);
  drawText("BPHQUIT", ROW_X + ROW_W - 0.042, SCREEN_Y + 0.533, 0.29, 244, 247, 252, 255, true);
}

function drawAppTile(index, x, y, color) {
  const selected = homeSelection === index;
  if (selected) drawHudRect(x, y, 0.090, 0.143, 245, 255, 255, 255);
  drawHudRect(x, y, 0.081, 0.129, ...color, 255);
  if (index === 0) {
    // Floppy-disk outline with label and storage window.
    drawHudRect(x, y, 0.040, 0.069, 255, 255, 255, 255);
    drawHudRect(x, y - 0.020, 0.024, 0.026, ...color, 255);
    drawHudRect(x + 0.006, y - 0.020, 0.006, 0.018, 255, 255, 255, 255);
    drawHudRect(x, y + 0.021, 0.028, 0.020, ...color, 255);
  } else if (index === 1) {
    // Music note, drawn from native primitives.
    drawHudRect(x - 0.010, y, 0.006, 0.058, 255, 255, 255, 255);
    drawHudRect(x + 0.014, y - 0.007, 0.006, 0.058, 255, 255, 255, 255);
    drawHudRect(x + 0.002, y - 0.028, 0.030, 0.010, 255, 255, 255, 255);
    drawHudRect(x - 0.016, y + 0.027, 0.018, 0.014, 255, 255, 255, 255);
    drawHudRect(x + 0.008, y + 0.020, 0.018, 0.014, 255, 255, 255, 255);
  } else if (index === 2) {
    // Armor vest silhouette.
    drawHudRect(x, y + 0.005, 0.038, 0.058, 255, 255, 255, 255);
    drawHudRect(x - 0.014, y - 0.027, 0.010, 0.022, 255, 255, 255, 255);
    drawHudRect(x + 0.014, y - 0.027, 0.010, 0.022, 255, 255, 255, 255);
    drawHudRect(x, y + 0.001, 0.028, 0.005, ...color, 255);
    drawHudRect(x, y + 0.017, 0.028, 0.005, ...color, 255);
  } else if (index === 3) {
    drawHudRect(x - 0.018, y, 0.006, 0.046, 255, 255, 255, 255);
    drawHudRect(x + 0.018, y, 0.006, 0.046, 255, 255, 255, 255);
    drawHudRect(x, y - 0.021, 0.043, 0.006, 255, 255, 255, 255);
    drawHudRect(x, y + 0.021, 0.043, 0.006, 255, 255, 255, 255);
    drawHudRect(x, y, 0.006, 0.047, 255, 255, 255, 255);
  } else {
    drawHudRect(x - 0.012, y, 0.005, 0.059, 255, 255, 255, 255);
    drawHudRect(x + 0.004, y - 0.027, 0.032, 0.005, 255, 255, 255, 255);
    drawHudRect(x + 0.004, y + 0.027, 0.032, 0.005, 255, 255, 255, 255);
    drawHudRect(x + 0.014, y, 0.034, 0.006, 255, 255, 255, 255);
  }
}

function renderRadioView() {
  drawText("BPHRADT", ROW_X, SCREEN_Y + 0.126, 0.30, 244, 126, 168, 255, false);
  const visibleCount = 6;
  for (let row = 0; row < visibleCount; row += 1) {
    const stationIndex = radioScroll + row;
    if (stationIndex >= RADIO_STATIONS.length) break;
    const y = SCREEN_Y + 0.197 + row * 0.063;
    const selected = stationIndex === radioSelection;
    drawHudRect(ROW_X + ROW_W / 2, y + 0.019, ROW_W, 0.056,
      selected ? 226 : 31, selected ? 61 : 31, selected ? 111 : 44, 255);
    drawText(radioTextKey(stationIndex), ROW_X + 0.009, y + 0.005,
      0.32, 255, 255, 255, 255, false);
  }
  const trackY = SCREEN_Y + 0.207;
  drawHudRect(SCREEN_X + SCREEN_W - 0.006, trackY + 0.175, 0.002, 0.35, 62, 59, 77, 255);
  drawHudRect(SCREEN_X + SCREEN_W - 0.006,
    trackY + 0.075 + (radioScroll / (RADIO_STATIONS.length - visibleCount)) * 0.20,
    0.003, 0.15, 242, 94, 145, 255);
}

function renderArmoryView() {
  drawText("BPHCASH", ROW_X, SCREEN_Y + 0.126, 0.30, 255, 204, 115, 255, false);
  if (phoneView === "confirm") {
    drawText("BPHITEM", ROW_X, SCREEN_Y + 0.206, 0.35, 255, 255, 255, 255, false);
    drawText("BPHCOST", ROW_X, SCREEN_Y + 0.285, 0.40, 255, 204, 115, 255, false);
    drawText("BPHAMMO", ROW_X, SCREEN_Y + 0.348, 0.29, 207, 214, 229, 255, false);
    drawText("BPHWARN", ROW_X, SCREEN_Y + 0.403, 0.27, 207, 214, 229, 255, false);
    drawHudRect(SCREEN_X + SCREEN_W / 2, SCREEN_Y + 0.535, ROW_W, 0.068, 205, 132, 27, 255);
    drawText("BPHBUY", SCREEN_X + SCREEN_W / 2, SCREEN_Y + 0.518, 0.33, 255, 255, 255, 255, true);
    return;
  }
  const categories = phoneView === "categories";
  const entries = categories ? ARMORY : ARMORY[categorySelection].items;
  const selection = categories ? categorySelection : productSelection;
  for (let index = 0; index < entries.length; index += 1) {
    const y = SCREEN_Y + 0.197 + index * (categories ? 0.063 : 0.085);
    const selected = index === selection;
    drawHudRect(ROW_X + ROW_W / 2, y + 0.020, ROW_W, categories ? 0.056 : 0.078,
      selected ? 153 : 31, selected ? 94 : 31, selected ? 16 : 44, 255);
    drawText("BPHA" + index, ROW_X + 0.009, y + (categories ? 0.005 : -0.009),
      0.29, 255, 255, 255, 255, false);
    if (!categories) drawText("BPHP" + index, ROW_X + 0.009, y + 0.026,
      0.27, 255, 218, 155, 255, false);
  }
}

function renderCheatView() {
  drawText("BPHCHEATINFO", ROW_X, SCREEN_Y + 0.126, 0.30, 255, 126, 126, 255, false);
  drawHudRect(ROW_X + ROW_W / 2, SCREEN_Y + 0.245, ROW_W, 0.104,
    missionWasActive ? 160 : 46, missionWasActive ? 45 : 46, missionWasActive ? 45 : 60, 255);
  drawText("BPHFINISH", ROW_X + 0.012, SCREEN_Y + 0.211, 0.36, 255, 255, 255, 255, false);
  drawText("BPHMISSIONSTATE", ROW_X + 0.012, SCREEN_Y + 0.277, 0.27,
    missionWasActive ? 255 : 190, missionWasActive ? 207 : 195, missionWasActive ? 207 : 210, 255, false);
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
    putText("BPHNTTL", phoneView === "home" ? "TELEFON" : phoneView === "radio" ? "RADIO" : phoneView === "cheats" ? "CHEATY" : "ZBROJOWNIA");
    putText("BPHINFO", "bOS / PERSONAL");
    putText("BPHSUB", "TWOJE APLIKACJE");
    putText("BPHHELP", "ENTER: WYBIERZ~n~F8 / ESC: ZAMKNIJ");
    putText("BPHBACK", "ENTER: WLACZ~n~ESC: POWROT");
    putText("BPHSAVE", "ZAPIS GRY");
    putText("BPHRADI", "RADIO");
    putText("BPHQUIT", "ZAMKNIJ");
    putText("BPHARMS", "ZBROJOWNIA");
    putText("BPHCHEAT", "CHEATY");
    putText("BPHRADT", "RADIO W POJEZDZIE");
    putText("BPHSHOP", phoneView === "confirm" ? "ENTER: KUP~n~ESC: ANULUJ" : "ENTER: WYBIERZ~n~ESC: POWROT");
    putText("BPHCHEATINFO", "NARZEDZIA MISJI");
    putText("BPHFINISH", "UKONCZ MISJE");
    putText("BPHMISSIONSTATE", missionWasActive ? "AKTYWNA - ENTER ABY ZAKONCZYC" : "BRAK AKTYWNEJ MISJI");
    putText("BPHSHELLP", "ENTER: WYKONAJ~n~ESC: POWROT");
    if (phoneView !== "home" && phoneView !== "radio") {
      const money = wallet();
      putText("BPHCASH", money === null ? "SALDO NIEDOSTEPNE" : "SALDO: $" + money);
      const entries = phoneView === "categories" ? ARMORY : ARMORY[categorySelection].items;
      entries.forEach((entry, index) => {
        putText("BPHA" + index, entry.label);
        putText("BPHP" + index, entry.price ? "$" + entry.price + " / " + (entry.armor ? "PELNY PANCERZ" : entry.ammo + " SZT.") : "");
      });
      const item = phoneView === "categories" ? entries[categorySelection].items[0] : selectedProduct();
      putText("BPHITEM", item.label);
      putText("BPHCOST", "CENA: $" + item.price);
      putText("BPHAMMO", item.armor ? "UZUPELNIENIE PANCERZA" : "AMUNICJA: " + item.ammo + " SZT.");
      putText("BPHWARN", item.armor ? "DO MAKSIMUM POSTACI" : "INNA BRON W TYM SLOCIE~n~ZOSTANIE ZASTAPIONA");
      putText("BPHBUY", pendingPurchase ? "LADOWANIE..." : "POTWIERDZ ZAKUP");
    }
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
  callNative("SET_TEXT_FONT", 1);
  callNative("SET_TEXT_SCALE", scale * 2.6, scale * 2.6);
  callNative("SET_TEXT_WRAPX", (SCREEN_X + SCREEN_W - 0.010) * HUD_VIRTUAL_WIDTH);
  callNative("SET_TEXT_CENTRE_SIZE", (SCREEN_W - 0.024) * HUD_VIRTUAL_WIDTH);
  callNative("SET_TEXT_COLOUR", red, green, blue, alpha);
  callNative("SET_TEXT_PROPORTIONAL", true);
  callNative("SET_TEXT_BACKGROUND", false);
  callNative("SET_TEXT_EDGE", 0, 0, 0, 0, 0);
  callNative("SET_TEXT_CENTRE", centered === true);
  callNative("SET_TEXT_JUSTIFY", false);
  callNative("SET_TEXT_RIGHT_JUSTIFY", false);
  callNative("SET_TEXT_DROPSHADOW", 0, 0, 0, 0, 0);
  callNative("DISPLAY_TEXT", x * HUD_VIRTUAL_WIDTH, y * HUD_VIRTUAL_HEIGHT, key);
}

function drawHudRect(x, y, width, height, red, green, blue, alpha) {
  callNative("DRAW_RECT", x * HUD_VIRTUAL_WIDTH, y * HUD_VIRTUAL_HEIGHT,
    width * HUD_VIRTUAL_WIDTH, height * HUD_VIRTUAL_HEIGHT, red, green, blue, alpha);
}

function keepRadioSelectionVisible() {
  const visibleCount = 6;
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
  return keyEdges.get(keyCode) === true;
}

function justPressedButton(button) {
  return buttonEdges.get(button) === true;
}

// Sample every key once, including while hidden. Short-circuit expressions
// and switching screens must not leave stale pressed states behind.
function pollInput() {
  for (const key of new Set([config.openKey, VK_F11, VK_ESCAPE, VK_BACKSPACE,
    VK_RETURN, VK_SPACE, VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, VK_W, VK_A, VK_S, VK_D])) {
    const down = isKeyDown(key);
    keyEdges.set(key, down && keyStates.get(key) !== true);
    keyStates.set(key, down);
  }
  for (const button of [PAD_DPAD_UP, PAD_DPAD_DOWN, PAD_DPAD_LEFT,
    PAD_DPAD_RIGHT, PAD_CROSS, PAD_CIRCLE]) {
    const down = isButtonDown(button);
    buttonEdges.set(button, down && buttonStates.get(button) !== true);
    buttonStates.set(button, down);
  }
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
