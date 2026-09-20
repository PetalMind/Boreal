/// <reference path="./.config/sa.d.ts" />

// Boreal Phone DE v2.5 — stable iPhone 6s UI + native GTA SA radio + armory shop + vehicle garage for GTA San Andreas: The Definitive Edition.
// Runtime: CLEO Redux x64 + IniFiles64.
//
// Radio uses the game's own GTA SA radio system. No external MP3 files or WinMM backend.

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

// Front-view proportions based on iPhone 6s dimensions (67.1 x 138.3 mm)
// and its 4.7-inch 750 x 1334 display. Width is derived in virtual HUD pixels
// so the body keeps the correct physical aspect ratio instead of looking tall
// and narrow on a 640x448 drawing surface.
const IPHONE_BODY_RATIO = 67.1 / 138.3;
const IPHONE_SCREEN_WIDTH_RATIO = 0.8719;
const IPHONE_SCREEN_HEIGHT_RATIO = 0.7524;
const PHONE_H = 0.700;
const PHONE_W = (PHONE_H * HUD_VIRTUAL_HEIGHT * IPHONE_BODY_RATIO) / HUD_VIRTUAL_WIDTH;
const PHONE_X = 0.965 - PHONE_W;
const PHONE_Y = 0.120;
const SCREEN_W = PHONE_W * IPHONE_SCREEN_WIDTH_RATIO;
const SCREEN_H = PHONE_H * IPHONE_SCREEN_HEIGHT_RATIO;
const SCREEN_X = PHONE_X + (PHONE_W - SCREEN_W) / 2;
const SCREEN_Y = PHONE_Y + PHONE_H * 0.118;
const ROW_X = SCREEN_X + 0.014;
const ROW_W = SCREEN_W - 0.028;

const HOME_ITEMS = [
  { key: "BPHSAVE", label: "ZAPIS GRY" },
  { key: "BPHRADI", label: "RADIO" },
  { key: "BPHARMS", label: "EKWIPUNEK" },
  { key: "BPHCHT", label: "NARZEDZIA" },
  { key: "BPHCARS", label: "SAMOCHODY" },
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

// Vehicle garage. Prices are a Boreal Phone gameplay economy rather than
// replacements for any vanilla dealership values. Ownership is persisted in
// BorealPhoneDE.ini and survives script/game restarts.
const VEHICLE_CATALOG = [
  { label: "SPORTOWE", items: [
    { label: "Infernus", model: 411, price: 95000 },
    { label: "Turismo", model: 451, price: 90000 },
    { label: "Bullet", model: 541, price: 85000 },
    { label: "Cheetah", model: 415, price: 80000 },
    { label: "Super GT", model: 506, price: 70000 },
  ] },
  { label: "TUNING", items: [
    { label: "Elegy", model: 562, price: 45000 },
    { label: "Sultan", model: 560, price: 50000 },
    { label: "Jester", model: 559, price: 48000 },
    { label: "Uranus", model: 558, price: 42000 },
    { label: "Flash", model: 565, price: 35000 },
  ] },
  { label: "MUSCLE", items: [
    { label: "Banshee", model: 429, price: 65000 },
    { label: "Phoenix", model: 603, price: 55000 },
    { label: "Buffalo", model: 402, price: 45000 },
    { label: "Sabre", model: 475, price: 30000 },
    { label: "Clover", model: 542, price: 28000 },
  ] },
  { label: "SEDANY", items: [
    { label: "Sentinel", model: 405, price: 26000 },
    { label: "Admiral", model: 445, price: 24000 },
    { label: "Premier", model: 426, price: 22000 },
    { label: "Washington", model: 421, price: 25000 },
    { label: "Merit", model: 551, price: 32000 },
  ] },
  { label: "TERENOWE", items: [
    { label: "Huntley", model: 579, price: 50000 },
    { label: "Landstalker", model: 400, price: 38000 },
    { label: "Mesa", model: 500, price: 30000 },
    { label: "Rancher", model: 489, price: 42000 },
    { label: "Sandking", model: 495, price: 65000 },
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
let radioRequestedStation = -1;
let radioRequestPending = false;
let radioCurrentStation = -1;
let radioLastPoll = 0;
let categorySelection = 0;
let productSelection = 0;
let categoryScroll = 0;
let productScroll = 0;
let carCategorySelection = 0;
let carVehicleSelection = 0;
let carCategoryScroll = 0;
let carVehicleScroll = 0;
let pendingVehicleAction = null;
let summonedVehicle = null;
const ownedVehicles = new Set();
let pendingPurchase = null;
let purchaseFault = false;
let actorFrozen = false;
let missionWasActive = false;
let lockedActor = null;
let statusText = "";
let statusUntil = 0;
let textStoreFailureLogged = false;
let lastFrameFailureAt = 0;
let textStoreLastTick = -1;
let textStoreLastSignature = "";

loadConfig();
log("Boreal Phone DE v2.5 loaded. Press F8 to open the phone.");

while (true) {
  wait(0);
  const now = Date.now();
  pollInput();
  updateNativeRadio(now);
  updatePurchase(now);
  updateVehicleAction(now);

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
    if (phoneOpen) closePhone();
    else openPhone();
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
    } else if (phoneView === "carConfirm") {
      phoneView = "carProducts";
    } else if (phoneView === "carProducts") {
      phoneView = "carCategories";
    } else if (phoneView === "carCategories") {
      phoneView = "home";
      homeSelection = 4;
    } else if (phoneView === "cheats") {
      phoneView = "home";
      homeSelection = 3;
    } else {
      closePhone();
    }
    return;
  }

  if (phoneView === "home") handleHomeInput();
  else if (phoneView === "radio") handleRadioInput(now);
  else if (phoneView === "cheats") handleCheatInput(now);
  else if (phoneView === "carCategories" || phoneView === "carProducts" || phoneView === "carConfirm") handleVehicleInput(now);
  else handleArmoryInput(now);
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
    if (homeSelection === 0) activateSaveMenu();
    else if (homeSelection === 1) openRadioView();
    else if (homeSelection === 2) {
      phoneView = "categories";
      categorySelection = 0;
      categoryScroll = 0;
      productSelection = 0;
      productScroll = 0;
      statusText = "";
    } else if (homeSelection === 3) {
      phoneView = "cheats";
      statusText = "";
    } else if (homeSelection === 4) {
      phoneView = "carCategories";
      carCategorySelection = 0;
      carCategoryScroll = 0;
      carVehicleSelection = 0;
      carVehicleScroll = 0;
      statusText = "";
    } else closePhone();
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
  const leftPressed = justPressed(VK_LEFT) || justPressed(VK_A) || justPressedButton(PAD_DPAD_LEFT);
  const rightPressed = justPressed(VK_RIGHT) || justPressed(VK_D) || justPressedButton(PAD_DPAD_RIGHT);
  if (leftPressed !== rightPressed) {
    radioSelection = wrapIndex(radioSelection + (leftPressed ? -1 : 1), RADIO_STATIONS.length);
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
  categoryScroll = 0;
  productScroll = 0;
  carCategoryScroll = 0;
  carVehicleScroll = 0;
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
  cancelVehicleAction();
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
  const actor = getPlayerActor();
  const inCar = actor && callNative("IS_CHAR_IN_ANY_CAR", actor).value === true;
  if (radioRequestedStation >= 0) {
    radioSelection = RADIO_STATIONS.findIndex((station) => station.value === radioRequestedStation);
  } else if (inCar) {
    const current = callNative("GET_RADIO_CHANNEL");
    const currentValue = normalizeRadioChannel(current.value);
    radioSelection = RADIO_STATIONS.findIndex((station) => station.value === currentValue);
  }
  if (radioSelection < 0) radioSelection = 0;
  radioScroll = 0;
  keepRadioSelectionVisible();
}

function applyRadioSelection(now) {
  const station = RADIO_STATIONS[radioSelection];
  radioRequestedStation = station.value;
  radioRequestPending = true;

  const actor = getPlayerActor();
  const inCar = actor && callNative("IS_CHAR_IN_ANY_CAR", actor).value === true;
  if (!inCar) {
    setStatus(station.value === 12 ? "RADIO WYLACZY SIE PO WEJSCIU DO AUTA" :
      "WYBRANO: " + station.label.toUpperCase() + "~n~URUCHOMI SIE W POJEZDZIE", now);
    return;
  }

  applyPendingNativeRadio(now);
}

function applyPendingNativeRadio(now) {
  if (!radioRequestPending || radioRequestedStation < 0) return false;
  const result = callNative("SET_RADIO_CHANNEL", radioRequestedStation);
  if (!result.ok) {
    setStatus("NATYWNE RADIO NIEDOSTEPNE", now);
    return false;
  }
  radioCurrentStation = radioRequestedStation;
  radioRequestPending = false;
  const station = RADIO_STATIONS.find((item) => item.value === radioRequestedStation);
  setStatus(radioRequestedStation === 12 ? "RADIO WYLACZONE" :
    "USTAWIONO: " + (station ? station.label.toUpperCase() : "RADIO"), now);
  return true;
}

function updateNativeRadio(now) {
  if (!config.enabled) return;
  if (now - radioLastPoll < 300) return;
  radioLastPoll = now;
  const actor = getPlayerActor();
  if (!actor) return;
  const inCar = callNative("IS_CHAR_IN_ANY_CAR", actor).value === true;
  if (!inCar) return;

  if (radioRequestPending) {
    applyPendingNativeRadio(now);
    return;
  }

  const current = callNative("GET_RADIO_CHANNEL");
  if (current.ok) radioCurrentStation = normalizeRadioChannel(current.value);
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
  try {
    if (player && typeof player.storeScore === "function") {
      const value = Number(player.storeScore());
      if (Number.isFinite(value)) return value;
    }
  } catch (error) {
    if (config.debug) log("Boreal Phone wallet class API failed: " + error);
  }
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
    keepCategorySelectionVisible();
  } else if (phoneView === "products") {
    productSelection = wrapIndex(productSelection + direction, ARMORY[categorySelection].items.length);
    keepProductSelectionVisible();
  }
  if (!justPressedAny([VK_RETURN, VK_SPACE]) && !justPressedButton(PAD_CROSS)) return;
  statusText = "";
  if (phoneView === "categories") {
    productSelection = 0;
    productScroll = 0;
    phoneView = "products";
    keepProductSelectionVisible();
  } else if (phoneView === "products") {
    phoneView = "confirm";
  } else if (phoneView === "confirm") {
    beginPurchase(now);
  }
}

function snapshotSlot(actor, weapon) {
  const slot = (typeof Weapon !== "undefined" && Weapon && typeof Weapon.GetSlot === "function")
    ? Number(Weapon.GetSlot(weapon)) : null;
  if (slot === null || !Number.isFinite(slot)) throw new Error("Weapon slot unavailable");

  // Prefer the typed CLEO Redux API. It is less brittle than interpreting the
  // raw return shape of native(GET_CHAR_WEAPON_IN_SLOT) on SA:DE.
  if (actor && typeof actor.getWeaponInSlot === "function") {
    const value = actor.getWeaponInSlot(slot);
    if (value && Number.isInteger(Number(value.weaponType)) &&
        Number.isInteger(Number(value.weaponAmmo)) && Number.isInteger(Number(value.weaponModel))) {
      return {
        slot,
        weapon: Number(value.weaponType),
        ammo: Number(value.weaponAmmo),
        model: Number(value.weaponModel),
      };
    }
  }

  const result = callNative("GET_CHAR_WEAPON_IN_SLOT", actor, slot);
  const value = result.value;
  if (!result.ok || !value || !Number.isInteger(Number(value.weaponType)) ||
      !Number.isInteger(Number(value.weaponAmmo)) || !Number.isInteger(Number(value.weaponModel))) {
    throw new Error("Weapon inventory unavailable");
  }
  return {
    slot,
    weapon: Number(value.weaponType),
    ammo: Number(value.weaponAmmo),
    model: Number(value.weaponModel),
  };
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
      const maximum = 100; // ADD_ARMOUR_TO_CHAR is capped at 100 in SA:DE.
      if (armor === null) throw new Error("Armor unavailable");
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
        const model = (typeof Weapon !== "undefined" && Weapon && typeof Weapon.GetModel === "function")
          ? Number(Weapon.GetModel(grant.weapon)) : null;
        if (model === null || !Number.isFinite(model) || model <= 0) throw new Error("Weapon model unavailable");
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

  const { actor, item } = purchase;
  const money = wallet();
  if (money === null || money < item.price) {
    cancelPurchase();
    setStatus(money === null ? "SALDO NIEDOSTEPNE" : "ZA MALO PIENIEDZY", now);
    return;
  }

  let armorBefore = null;
  let charged = false;
  let deliveryStarted = false;
  try {
    if (item.armor) {
      armorBefore = (actor && typeof actor.getArmor === "function")
        ? Number(actor.getArmor()) : readNativeNumber("GET_CHAR_ARMOUR", "armor", actor);
      if (!Number.isFinite(armorBefore) || armorBefore >= 100) {
        throw new Error("Armor no longer needs replenishing");
      }
    }

    // Make sure the weapon slot did not change while models were streaming.
    for (const grant of purchase.grants) {
      const current = snapshotSlot(actor, grant.weapon);
      if (current.weapon !== grant.before.weapon || current.ammo !== grant.before.ammo) {
        throw new Error("Inventory changed while streaming");
      }
    }

    // The old implementation required STORE_SCORE to reflect ADD_SCORE in the
    // very same frame. SA:DE can expose the old value briefly, causing a false
    // rollback. The typed Player API is authoritative, so debit once and only
    // refund if the item delivery itself fails.
    if (player && typeof player.addScore === "function") {
      player.addScore(-item.price);
    } else {
      const debit = callNative("ADD_SCORE", PLAYER_ID, -item.price);
      if (!debit.ok) throw new Error("Wallet debit command failed");
    }
    charged = true;
    deliveryStarted = true;

    if (item.armor) {
      const amount = Math.max(0, 100 - armorBefore);
      if (actor && typeof actor.addArmor === "function") actor.addArmor(amount);
      else if (!callNative("ADD_ARMOUR_TO_CHAR", actor, amount).ok) throw new Error("Armor delivery command failed");

      const armorAfter = (actor && typeof actor.getArmor === "function")
        ? Number(actor.getArmor()) : readNativeNumber("GET_CHAR_ARMOUR", "armor", actor);
      if (!Number.isFinite(armorAfter) || armorAfter < 99) throw new Error("Armor delivery failed");
    } else {
      for (const grant of purchase.grants) {
        const sameWeapon = grant.before.weapon === grant.weapon;

        if (sameWeapon && actor && typeof actor.addAmmo === "function") {
          actor.addAmmo(grant.weapon, grant.ammo);
        } else if (actor && typeof actor.giveWeapon === "function") {
          actor.giveWeapon(grant.weapon, grant.ammo);
        } else if (!callNative("GIVE_WEAPON_TO_CHAR", actor, grant.weapon, grant.ammo).ok) {
          throw new Error("Weapon delivery command failed");
        }

        const after = snapshotSlot(actor, grant.weapon);
        const expectedAmmo = sameWeapon ? grant.before.ammo + grant.ammo : grant.ammo;
        // Detonator ammo is implementation-defined; ownership of weapon 40 is
        // sufficient. Other weapons must contain at least the purchased bundle.
        if (after.weapon !== grant.weapon || (grant.weapon !== 40 && after.ammo < expectedAmmo)) {
          throw new Error("Weapon delivery failed: weapon=" + grant.weapon +
            " expectedAmmo=" + expectedAmmo + " actualWeapon=" + after.weapon + " actualAmmo=" + after.ammo);
        }
      }
    }

    phoneView = "products";
    setStatus("KUPIONO: -$" + item.price, now);
    if (config.debug) log("Boreal Phone armory purchase OK: " + item.label + " price=" + item.price);
  } catch (error) {
    log("Boreal Phone armory transaction: " + error);

    // Roll back inventory only after delivery began. Use the typed Char API
    // where available so restoration matches the API used for the purchase.
    if (deliveryStarted) {
      try {
        if (item.armor && armorBefore !== null) {
          const armorNow = (actor && typeof actor.getArmor === "function")
            ? Number(actor.getArmor()) : readNativeNumber("GET_CHAR_ARMOUR", "armor", actor);
          if (Number.isFinite(armorNow) && armorNow > armorBefore) {
            // ADD_ARMOUR_TO_CHAR cannot subtract. SET_CHAR_ARMOUR is not part of
            // the supplied API, so only mark a fault if armor delivery partially
            // succeeded and cannot be restored exactly.
            purchaseFault = true;
          }
        } else {
          for (const grant of purchase.grants) {
            try {
              if (actor && typeof actor.removeWeapon === "function") actor.removeWeapon(grant.weapon);
              else callNative("REMOVE_WEAPON_FROM_CHAR", actor, grant.weapon);

              if (grant.before.weapon !== 0) {
                if (actor && typeof actor.giveWeapon === "function") actor.giveWeapon(grant.before.weapon, 1);
                else callNative("GIVE_WEAPON_TO_CHAR", actor, grant.before.weapon, 1);

                if (actor && typeof actor.setAmmo === "function") actor.setAmmo(grant.before.weapon, grant.before.ammo);
                else callNative("SET_CHAR_AMMO", actor, grant.before.weapon, grant.before.ammo);
              }
            } catch (restoreError) {
              purchaseFault = true;
              log("Boreal Phone armory restore failed: " + restoreError);
            }
          }
        }
      } catch (restoreError) {
        purchaseFault = true;
        log("Boreal Phone armory rollback failed: " + restoreError);
      }
    }

    if (charged) {
      try {
        if (player && typeof player.addScore === "function") player.addScore(item.price);
        else callNative("ADD_SCORE", PLAYER_ID, item.price);
      } catch (refundError) {
        purchaseFault = true;
        log("Boreal Phone armory refund failed: " + refundError);
      }
    }

    setStatus(purchaseFault ? "BLAD STANU GRY~n~SPRAWDZ LOG CLEO" : "ZAKUP ANULOWANY~n~SALDO BEZ ZMIAN", now);
  } finally {
    cancelPurchase();
  }
}

function selectedVehicle() {
  return VEHICLE_CATALOG[carCategorySelection].items[carVehicleSelection];
}

function vehicleOwnershipKey(model) {
  return "model_" + model;
}

function isVehicleOwned(model) {
  return ownedVehicles.has(Number(model));
}

function setVehicleOwned(model, owned) {
  const numeric = Number(model);
  if (!Number.isFinite(numeric)) return false;
  if (typeof IniFile === "undefined" || !IniFile || typeof IniFile.WriteInt !== "function") return false;
  try {
    const ok = IniFile.WriteInt(owned ? 1 : 0, CONFIG_PATH, "garage", vehicleOwnershipKey(numeric));
    if (ok !== true) return false;
    if (owned) ownedVehicles.add(numeric);
    else ownedVehicles.delete(numeric);
    return true;
  } catch (error) {
    log("Boreal Phone garage persistence failed: " + error);
    return false;
  }
}

function loadVehicleOwnership() {
  ownedVehicles.clear();
  if (typeof IniFile === "undefined" || !IniFile || typeof IniFile.ReadInt !== "function") return;
  for (const category of VEHICLE_CATALOG) {
    for (const item of category.items) {
      try {
        if (Number(IniFile.ReadInt(CONFIG_PATH, "garage", vehicleOwnershipKey(item.model))) !== 0) {
          ownedVehicles.add(item.model);
        }
      } catch (_) {}
    }
  }
}

function handleVehicleInput(now) {
  if (pendingVehicleAction) return;
  const previous = justPressedAny([VK_UP, VK_W, VK_LEFT, VK_A]) || justPressedButton(PAD_DPAD_UP);
  const next = justPressedAny([VK_DOWN, VK_S, VK_RIGHT, VK_D]) || justPressedButton(PAD_DPAD_DOWN);
  const direction = Number(next) - Number(previous);

  if (phoneView === "carCategories") {
    carCategorySelection = wrapIndex(carCategorySelection + direction, VEHICLE_CATALOG.length);
    keepCarCategorySelectionVisible();
  } else if (phoneView === "carProducts") {
    carVehicleSelection = wrapIndex(carVehicleSelection + direction, VEHICLE_CATALOG[carCategorySelection].items.length);
    keepCarVehicleSelectionVisible();
  }

  if (!justPressedAny([VK_RETURN, VK_SPACE]) && !justPressedButton(PAD_CROSS)) return;
  statusText = "";

  if (phoneView === "carCategories") {
    carVehicleSelection = 0;
    carVehicleScroll = 0;
    phoneView = "carProducts";
    keepCarVehicleSelectionVisible();
    return;
  }

  if (phoneView === "carProducts") {
    const item = selectedVehicle();
    if (isVehicleOwned(item.model)) beginVehicleAction("summon", item, now);
    else phoneView = "carConfirm";
    return;
  }

  if (phoneView === "carConfirm") beginVehicleAction("purchase", selectedVehicle(), now);
}

function beginVehicleAction(type, item, now) {
  if (pendingVehicleAction || !item) return;
  const actor = getPlayerActor();
  if (!actor) {
    setStatus("BRAK DANYCH GRACZA", now);
    return;
  }

  if (type === "purchase") {
    const money = wallet();
    if (money === null) {
      setStatus("SALDO NIEDOSTEPNE", now);
      return;
    }
    if (money < item.price) {
      setStatus("BRAKUJE $" + (item.price - money), now);
      return;
    }
  }

  pendingVehicleAction = { type, item, actor, startedAt: now };
  const requested = callNative("REQUEST_MODEL", item.model);
  if (!requested.ok) {
    pendingVehicleAction = null;
    setStatus("MODEL AUTA NIEDOSTEPNY", now);
    return;
  }
  setStatus(type === "purchase" ? "PRZYGOTOWYWANIE ZAKUPU" : "PRZYZYWANIE POJAZDU", now);
}

function cancelVehicleAction() {
  if (!pendingVehicleAction) return;
  callNative("MARK_MODEL_AS_NO_LONGER_NEEDED", pendingVehicleAction.item.model);
  pendingVehicleAction = null;
}

function cleanupPreviousSummonedVehicle(actor) {
  if (!summonedVehicle) return;
  try {
    if (typeof Car === "undefined" || !Car || typeof Car.DoesExist !== "function" || !Car.DoesExist(summonedVehicle)) {
      summonedVehicle = null;
      return;
    }
    if (actor && typeof actor.isInCar === "function" && actor.isInCar(summonedVehicle)) return;
    let occupied = false;
    try {
      if (typeof summonedVehicle.getNumberOfPassengers === "function" && summonedVehicle.getNumberOfPassengers() > 0) occupied = true;
      if (!occupied && typeof summonedVehicle.getDriver === "function" && typeof Char !== "undefined" && Char && typeof Char.DoesExist === "function") {
        const driver = summonedVehicle.getDriver();
        if (driver && Char.DoesExist(driver)) occupied = true;
      }
    } catch (_) {}
    if (occupied) {
      if (typeof summonedVehicle.markAsNoLongerNeeded === "function") summonedVehicle.markAsNoLongerNeeded();
      summonedVehicle = null;
      return;
    }
    if (typeof summonedVehicle.delete === "function") summonedVehicle.delete();
  } catch (_) {}
  summonedVehicle = null;
}

function spawnOwnedVehicle(actor, item) {
  if (typeof Car === "undefined" || !Car || typeof Car.Create !== "function") throw new Error("Car.Create unavailable");
  let spawn = null;
  let heading = 0;
  if (actor && typeof actor.getOffsetInWorldCoords === "function") {
    spawn = actor.getOffsetInWorldCoords(0, 5.5, 0.6);
  }
  if (!spawn && actor && typeof actor.getCoordinates === "function") {
    const c = actor.getCoordinates();
    spawn = { x: c.x, y: c.y + 5.5, z: c.z + 0.6 };
  }
  if (!spawn || !Number.isFinite(Number(spawn.x)) || !Number.isFinite(Number(spawn.y)) || !Number.isFinite(Number(spawn.z))) {
    throw new Error("Spawn coordinates unavailable");
  }
  if (actor && typeof actor.getHeading === "function") heading = Number(actor.getHeading()) || 0;

  cleanupPreviousSummonedVehicle(actor);
  const car = Car.Create(item.model, spawn.x, spawn.y, spawn.z);
  if (!car) throw new Error("Vehicle creation failed");
  if (typeof car.setHeading === "function") car.setHeading(heading);
  if (typeof car.setHealth === "function") car.setHealth(1000);
  if (typeof car.setDirtLevel === "function") car.setDirtLevel(0);
  if (typeof car.setEngineOn === "function") car.setEngineOn(false);
  summonedVehicle = car;
  // Release mission ownership so the game may clean the vehicle naturally
  // after the player leaves the area. We keep the live handle only for replacing
  // the previous Boreal-summoned vehicle while it still exists.
  if (typeof car.markAsNoLongerNeeded === "function") car.markAsNoLongerNeeded();
  return car;
}

function updateVehicleAction(now) {
  const action = pendingVehicleAction;
  if (!action) return;
  if (!phoneOpen || !getPlayerActor()) {
    cancelVehicleAction();
    return;
  }
  if (now - action.startedAt > 5000) {
    cancelVehicleAction();
    setStatus("MODEL AUTA NIEDOSTEPNY", now);
    return;
  }
  const loaded = callNative("HAS_MODEL_LOADED", action.item.model);
  if (!loaded.ok || loaded.value !== true) return;

  const actor = getPlayerActor();
  const item = action.item;
  let charged = false;
  let moneyBefore = null;
  try {
    if (action.type === "purchase") {
      if (isVehicleOwned(item.model)) {
        action.type = "summon";
      } else {
        moneyBefore = wallet();
        if (moneyBefore === null || moneyBefore < item.price) throw new Error("Wallet changed");
        callNative("ADD_SCORE", PLAYER_ID, -item.price);
        const afterDebit = wallet();
        if (afterDebit !== moneyBefore - item.price) throw new Error("Cannot confirm vehicle debit");
        charged = true;
        if (!setVehicleOwned(item.model, true)) throw new Error("Cannot persist vehicle ownership");
      }
    }

    let outside = true;
    try {
      if (actor && typeof actor.getAreaVisible === "function") outside = Number(actor.getAreaVisible()) === 0;
    } catch (_) {}

    if (outside) {
      spawnOwnedVehicle(actor, item);
      phoneView = "carProducts";
      setStatus((action.type === "purchase" && charged ? "KUPIONO I PRZYZWANO: " : "PRZYZWANO: ") + item.label.toUpperCase(), now);
    } else {
      phoneView = "carProducts";
      setStatus(charged ? "KUPIONO: " + item.label.toUpperCase() + "~n~WYJDZ NA ZEWNATRZ ABY PRZYZWAC" :
        "WYJDZ NA ZEWNATRZ ABY PRZYZWAC", now);
    }
  } catch (error) {
    log("Boreal Phone vehicle action: " + error);
    if (charged && moneyBefore !== null && !isVehicleOwned(item.model)) {
      // Ownership was not recorded, so the transaction is not valid: refund.
      callNative("ADD_SCORE", PLAYER_ID, item.price);
      setStatus("ZAKUP ANULOWANY~n~SALDO BEZ ZMIAN", now);
    } else if (charged && isVehicleOwned(item.model)) {
      // The purchase is already safely persisted. A later spawn failure must
      // not silently undo the user's garage ownership.
      setStatus("KUPIONO: " + item.label.toUpperCase() + "~n~NIE UDALO SIE PRZYZWAC", now);
      phoneView = "carProducts";
    } else {
      setStatus("NIE UDALO SIE PRZYZWAC AUTA", now);
    }
  } finally {
    callNative("MARK_MODEL_AS_NO_LONGER_NEEDED", item.model);
    pendingVehicleAction = null;
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

// All geometry uses normalized layout coordinates and is converted exactly once
// at the native boundary. Rounded helpers operate in virtual pixels so circles
// stay circular and corner radii stay visually consistent.
function renderPhone(now) {
  updateTextStore(now);
  callNative("USE_TEXT_COMMANDS", true);
  try {
    renderIPhoneShell();

    if (phoneView === "home") {
      renderHomeView();
    } else {
      renderAppHeader();
      if (phoneView === "radio") renderRadioView();
      else if (phoneView === "cheats") renderCheatView();
      else if (phoneView === "carCategories" || phoneView === "carProducts" || phoneView === "carConfirm") renderVehicleView();
      else renderArmoryView();
    }

    renderPhoneStatusBar();
    renderPhoneHint();

    if (statusText && now < statusUntil) {
      const toastY = SCREEN_Y + SCREEN_H - pxY(50);
      drawSoftRect(SCREEN_X + SCREEN_W / 2, toastY,
        SCREEN_W - pxX(16), pxY(38), 9, 24, 24, 29, 238);
      drawText("BPHSTAT", SCREEN_X + SCREEN_W / 2, toastY - pxY(9),
        0.20, 255, 255, 255, 255, true);
    }
  } finally {
    callNative("USE_TEXT_COMMANDS", false);
  }
}

function renderIPhoneShell() {
  const cx = PHONE_X + PHONE_W / 2;
  const cy = PHONE_Y + PHONE_H / 2;
  const right = PHONE_X + PHONE_W;

  // Stable renderer: every rounded-looking element below uses a fixed small
  // number of DRAW_RECT calls. Avoid scanline circles/rounded rectangles in
  // SA:DE; hundreds of native draw calls per frame can destabilise UE4.

  // Hardware buttons.
  drawHudRect(PHONE_X - pxX(1.5), PHONE_Y + pxY(76), pxX(3), pxY(15), 74, 75, 79, 255);
  drawHudRect(PHONE_X - pxX(1.5), PHONE_Y + pxY(103), pxX(3), pxY(24), 74, 75, 79, 255);
  drawHudRect(PHONE_X - pxX(1.5), PHONE_Y + pxY(136), pxX(3), pxY(24), 74, 75, 79, 255);
  drawHudRect(right + pxX(1.5), PHONE_Y + pxY(101), pxX(3), pxY(33), 74, 75, 79, 255);

  // Shadow + space-gray aluminium + front glass. drawSoftRect is 3 calls.
  drawSoftRect(cx + pxX(3.5), cy + pxY(4), PHONE_W + pxX(7), PHONE_H + pxY(8), 7,
    0, 0, 0, 105);
  drawSoftRect(cx, cy, PHONE_W, PHONE_H, 6, 93, 94, 98, 255);
  drawSoftRect(cx, cy, PHONE_W - pxX(4), PHONE_H - pxY(4), 5, 8, 8, 10, 255);

  // Retina display.
  drawHudRect(SCREEN_X + SCREEN_W / 2, SCREEN_Y + SCREEN_H / 2,
    SCREEN_W + pxX(1.2), SCREEN_H + pxY(1.2), 0, 0, 0, 255);
  if (phoneView === "home") renderPhoneWallpaper();
  else drawHudRect(SCREEN_X + SCREEN_W / 2, SCREEN_Y + SCREEN_H / 2,
    SCREEN_W, SCREEN_H, 19, 20, 25, 255);

  // Earpiece, camera, proximity sensor.
  const speakerY = PHONE_Y + pxY(17);
  drawSoftRect(cx, speakerY, pxX(31), pxY(4), 1.2, 50, 50, 54, 255);
  drawSoftRect(cx - pxX(24), speakerY, pxX(5.5), pxY(5.5), 1.6, 26, 29, 35, 255);
  drawHudRect(cx - pxX(24), speakerY, pxX(2.2), pxY(2.2), 52, 67, 92, 255);
  drawHudRect(cx, PHONE_Y + pxY(8), pxX(3.0), pxY(3.0), 39, 39, 43, 255);

  // Touch ID button: compact squircle rings, no rasterised circles.
  const homeY = PHONE_Y + PHONE_H - pxY(20);
  drawSoftRect(cx, homeY, pxX(25), pxY(25), 5, 108, 109, 114, 255);
  drawSoftRect(cx, homeY, pxX(21), pxY(21), 4, 17, 17, 19, 255);
  drawSoftRect(cx - pxX(0.6), homeY - pxY(0.6), pxX(16), pxY(16), 3, 11, 11, 13, 255);
}

function renderPhoneWallpaper() {
  // Low-cost iOS-9-era inspired wallpaper. Full-width bands avoid the large
  // scanline-generated blobs visible in v2 and keep the frame budget stable.
  const cx = SCREEN_X + SCREEN_W / 2;
  const h = SCREEN_H / 5;
  drawHudRect(cx, SCREEN_Y + h * 0.5, SCREEN_W, h, 20, 30, 55, 255);
  drawHudRect(cx, SCREEN_Y + h * 1.5, SCREEN_W, h, 27, 57, 93, 255);
  drawHudRect(cx, SCREEN_Y + h * 2.5, SCREEN_W, h, 45, 74, 108, 255);
  drawHudRect(cx, SCREEN_Y + h * 3.5, SCREEN_W, h, 67, 57, 101, 255);
  drawHudRect(cx, SCREEN_Y + h * 4.5, SCREEN_W, h, 38, 37, 69, 255);
  drawHudRect(cx, SCREEN_Y + pxY(13), SCREEN_W, pxY(26), 5, 8, 14, 54);
}

function renderPhoneStatusBar() {
  const light = phoneView === "home";
  const c = light ? [255, 255, 255] : [220, 222, 229];
  const baseY = SCREEN_Y + pxY(6.2);

  // Signal bars: 4 fixed rectangles.
  for (let index = 0; index < 4; index += 1) {
    const h = 2.4 + index * 1.35;
    drawHudRect(SCREEN_X + pxX(7 + index * 3.2), baseY + pxY(4.4 - h / 2),
      pxX(1.7), pxY(h), c[0], c[1], c[2], 235);
  }

  drawText("BPHCLK", SCREEN_X + SCREEN_W / 2, SCREEN_Y + pxY(1.0),
    0.225, c[0], c[1], c[2], 245, true);

  // Battery outline + terminal + charge fill.
  const bx = SCREEN_X + SCREEN_W - pxX(10.5);
  const by = baseY + pxY(3.1);
  drawHudRect(bx, by, pxX(13), pxY(6.1), c[0], c[1], c[2], 215);
  drawHudRect(bx, by, pxX(10.3), pxY(3.6), light ? 20 : 19, light ? 30 : 20, light ? 55 : 25, 255);
  drawHudRect(bx - pxX(2.1), by, pxX(5.2), pxY(3.1), 100, 198, 94, 255);
  drawHudRect(bx + pxX(7.2), by, pxX(1.5), pxY(2.5), c[0], c[1], c[2], 220);
}

function renderAppHeader() {
  const barY = SCREEN_Y + pxY(29);
  drawHudRect(SCREEN_X + SCREEN_W / 2, barY,
    SCREEN_W, pxY(31), 27, 28, 34, 248);
  drawHudRect(SCREEN_X + SCREEN_W / 2, barY + pxY(15.5),
    SCREEN_W, pxY(1), 57, 58, 66, 255);
  drawText("BPHNTTL", SCREEN_X + SCREEN_W / 2, barY - pxY(7),
    0.285, 250, 250, 252, 255, true);
}

function renderPhoneHint() {
  const key = phoneView === "home" ? "BPHHELP" :
    phoneView === "radio" ? "BPHBACK" : phoneView === "cheats" ? "BPHCHLP" :
    (phoneView === "carCategories" || phoneView === "carProducts" || phoneView === "carConfirm") ? "BVHINT" : "BPHSHOP";
  const y = SCREEN_Y + SCREEN_H - pxY(11);
  drawText(key, SCREEN_X + SCREEN_W / 2, y,
    0.18, phoneView === "home" ? 238 : 177,
    phoneView === "home" ? 239 : 179,
    phoneView === "home" ? 244 : 188, 235, true);
}

function renderHomeView() {
  const iconSize = 27;
  const iconY = SCREEN_Y + pxY(68);
  const screenPixels = SCREEN_W * HUD_VIRTUAL_WIDTH;
  const gap = (screenPixels - iconSize * 4) / 5;

  for (let index = 0; index < 4; index += 1) {
    const x = SCREEN_X + pxX(gap + iconSize / 2 + index * (iconSize + gap));
    drawAppTile(index, x, iconY);
    drawText(HOME_ITEMS[index].key, x, iconY + pxY(18.5),
      0.205, 250, 250, 252, 255, true);
  }

  // Second iOS-style row: the garage app lives on the grid, not in the dock.
  const carsX = SCREEN_X + pxX(gap + iconSize / 2);
  const carsY = iconY + pxY(57);
  drawAppTile(4, carsX, carsY);
  drawText("BPHCARS", carsX, carsY + pxY(18.5), 0.205, 250, 250, 252, 255, true);

  const dockY = SCREEN_Y + SCREEN_H - pxY(36);
  drawSoftRect(SCREEN_X + SCREEN_W / 2, dockY,
    SCREEN_W - pxX(12), pxY(49), 5, 224, 226, 234, 92);
  drawAppTile(5, SCREEN_X + SCREEN_W / 2, dockY - pxY(3));
  drawText("BPHQUIT", SCREEN_X + SCREEN_W / 2, dockY + pxY(15),
    0.205, 250, 250, 252, 255, true);
}

function drawAppTile(index, x, y) {
  const selected = homeSelection === index;
  const size = 27;
  const colors = [
    [60, 184, 104],
    [232, 80, 121],
    [239, 159, 62],
    [103, 91, 183],
    [54, 141, 213],
    [93, 98, 108],
  ];
  const c = colors[index];

  if (selected) {
    drawSoftRect(x, y, pxX(size + 6), pxY(size + 6), 4.8, 238, 244, 255, 245);
    drawSoftRect(x, y, pxX(size + 3), pxY(size + 3), 4.2, 55, 138, 245, 255);
  }
  drawSoftRect(x, y, pxX(size), pxY(size), 4, c[0], c[1], c[2], 255);

  // Simple glyphs: intentionally low primitive count.
  if (index === 0) {
    drawHudRect(x, y, pxX(12), pxY(14), 255, 255, 255, 246);
    drawHudRect(x, y - pxY(4), pxX(7), pxY(2), c[0], c[1], c[2], 255);
    drawHudRect(x, y + pxY(4), pxX(7), pxY(5), c[0], c[1], c[2], 255);
  } else if (index === 1) {
    drawHudRect(x + pxX(3), y - pxY(2), pxX(2.4), pxY(13), 255, 255, 255, 250);
    drawHudRect(x - pxX(1), y - pxY(7), pxX(10), pxY(2.5), 255, 255, 255, 250);
    drawSoftRect(x - pxX(3), y + pxY(5), pxX(5.5), pxY(5.5), 1.2, 255, 255, 255, 250);
  } else if (index === 2) {
    drawSoftRect(x, y + pxY(2), pxX(13), pxY(11), 2.2, 255, 255, 255, 245);
    drawHudRect(x, y - pxY(5), pxX(7), pxY(4), 255, 255, 255, 245);
    drawHudRect(x, y - pxY(4), pxX(4), pxY(3), c[0], c[1], c[2], 255);
  } else if (index === 3) {
    drawHudRect(x, y, pxX(15), pxY(2.5), 255, 255, 255, 245);
    drawHudRect(x, y, pxX(2.5), pxY(15), 255, 255, 255, 245);
    drawSoftRect(x, y, pxX(9), pxY(9), 2, 255, 255, 255, 245);
    drawSoftRect(x, y, pxX(4), pxY(4), 1, c[0], c[1], c[2], 255);
  } else if (index === 4) {
    // Compact front-view car glyph.
    drawHudRect(x, y + pxY(2), pxX(16), pxY(7), 255, 255, 255, 245);
    drawHudRect(x, y - pxY(3), pxX(10), pxY(5), 255, 255, 255, 245);
    drawHudRect(x - pxX(5.5), y + pxY(6), pxX(3.2), pxY(3.2), 30, 35, 42, 255);
    drawHudRect(x + pxX(5.5), y + pxY(6), pxX(3.2), pxY(3.2), 30, 35, 42, 255);
  } else {
    drawSoftRect(x, y, pxX(13), pxY(13), 3, 255, 255, 255, 245);
    drawSoftRect(x, y, pxX(8), pxY(8), 2, c[0], c[1], c[2], 255);
    drawHudRect(x, y - pxY(5), pxX(2.3), pxY(6), 255, 255, 255, 255);
  }
}

function renderRadioView() {
  drawText("BPHRADT", ROW_X, SCREEN_Y + 0.118, 0.27, 244, 126, 168, 255, false);
  const visibleCount = 5;
  for (let row = 0; row < visibleCount; row += 1) {
    const stationIndex = radioScroll + row;
    if (stationIndex >= RADIO_STATIONS.length) break;
    const y = SCREEN_Y + 0.171 + row * 0.052;
    const selected = stationIndex === radioSelection;
    const current = RADIO_STATIONS[stationIndex].value === radioCurrentStation;
    const pending = radioRequestPending && RADIO_STATIONS[stationIndex].value === radioRequestedStation;
    drawHudRect(ROW_X + ROW_W / 2, y + 0.017, ROW_W, 0.045,
      selected ? 178 : 31, selected ? 48 : 31, selected ? 102 : 44, 255);
    if (current || pending) {
      drawHudRect(ROW_X + 0.004, y + 0.017, 0.004, 0.028,
        pending ? 242 : 92, pending ? 168 : 214, pending ? 64 : 122, 255);
    }
    drawText(radioTextKey(stationIndex), ROW_X + 0.011, y + 0.003,
      0.255, 255, 255, 255, 255, false);
  }

  const actor = getPlayerActor();
  const inCar = actor && callNative("IS_CHAR_IN_ANY_CAR", actor).value === true;
  const panelY = SCREEN_Y + 0.466;
  drawSoftRect(SCREEN_X + SCREEN_W / 2, panelY, SCREEN_W - pxX(10), 0.080,
    3.8, 24, 25, 31, 248);
  drawText("BPHNOW", ROW_X + 0.008, panelY - 0.025, 0.185, 163, 166, 177, 255, false);
  drawText("BPHPLAY", ROW_X + 0.008, panelY + 0.002, 0.225, 255, 255, 255, 255, false);

  const trackY = SCREEN_Y + 0.180;
  const maxScroll = Math.max(1, RADIO_STATIONS.length - visibleCount);
  const trackHeight = 0.250;
  const thumbHeight = trackHeight * (visibleCount / RADIO_STATIONS.length);
  drawHudRect(SCREEN_X + SCREEN_W - 0.006, trackY + trackHeight / 2, 0.002, trackHeight, 62, 59, 77, 255);
  drawHudRect(SCREEN_X + SCREEN_W - 0.006,
    trackY + thumbHeight / 2 + (radioScroll / maxScroll) * (trackHeight - thumbHeight),
    0.003, thumbHeight, 242, 94, 145, 255);
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
  const scroll = categories ? categoryScroll : productScroll;
  const visibleCount = categories ? 5 : 4;
  const rowStep = categories ? 0.063 : 0.085;
  const rowHeight = categories ? 0.056 : 0.078;
  const labelYOffset = categories ? 0.005 : -0.009;
  const end = Math.min(entries.length, scroll + visibleCount);
  for (let visibleRow = 0; scroll + visibleRow < end; visibleRow += 1) {
    const index = scroll + visibleRow;
    const y = SCREEN_Y + 0.197 + visibleRow * rowStep;
    const selected = index === selection;
    drawHudRect(ROW_X + ROW_W / 2, y + 0.020, ROW_W, rowHeight,
      selected ? 153 : 31, selected ? 94 : 31, selected ? 16 : 44, 255);
    drawText("BPHA" + index, ROW_X + 0.009, y + labelYOffset,
      0.29, 255, 255, 255, 255, false);
    if (!categories) drawText("BPHP" + index, ROW_X + 0.009, y + 0.026,
      0.27, 255, 218, 155, 255, false);
  }
  if (entries.length > visibleCount) {
    const trackX = SCREEN_X + SCREEN_W - 0.006;
    const trackTop = SCREEN_Y + 0.217;
    const trackHeight = categories ? 0.300 : 0.255;
    const thumbHeight = trackHeight * (visibleCount / entries.length);
    const maxScroll = Math.max(1, entries.length - visibleCount);
    const thumbCenterY = trackTop + thumbHeight / 2 + (scroll / maxScroll) * (trackHeight - thumbHeight);
    drawHudRect(trackX, trackTop + trackHeight / 2, 0.002, trackHeight, 62, 59, 77, 255);
    drawHudRect(trackX, thumbCenterY, 0.003, thumbHeight, 205, 132, 27, 255);
  }
}

function renderVehicleView() {
  drawText("BVCASH", ROW_X, SCREEN_Y + 0.126, 0.30, 112, 196, 255, 255, false);

  if (phoneView === "carConfirm") {
    drawText("BVITEM", ROW_X, SCREEN_Y + 0.206, 0.35, 255, 255, 255, 255, false);
    drawText("BVCOST", ROW_X, SCREEN_Y + 0.285, 0.40, 112, 196, 255, 255, false);
    drawText("BVACT", ROW_X, SCREEN_Y + 0.348, 0.29, 207, 214, 229, 255, false);
    drawText("BVWARN", ROW_X, SCREEN_Y + 0.403, 0.27, 207, 214, 229, 255, false);
    drawHudRect(SCREEN_X + SCREEN_W / 2, SCREEN_Y + 0.535, ROW_W, 0.068, 42, 118, 181, 255);
    drawText("BVBUY", SCREEN_X + SCREEN_W / 2, SCREEN_Y + 0.518, 0.33, 255, 255, 255, 255, true);
    return;
  }

  const categories = phoneView === "carCategories";
  const entries = categories ? VEHICLE_CATALOG : VEHICLE_CATALOG[carCategorySelection].items;
  const selection = categories ? carCategorySelection : carVehicleSelection;
  const scroll = categories ? carCategoryScroll : carVehicleScroll;
  const visibleCount = categories ? 5 : 4;
  const rowStep = categories ? 0.063 : 0.085;
  const rowHeight = categories ? 0.056 : 0.078;
  const end = Math.min(entries.length, scroll + visibleCount);

  for (let visibleRow = 0; scroll + visibleRow < end; visibleRow += 1) {
    const index = scroll + visibleRow;
    const y = SCREEN_Y + 0.197 + visibleRow * rowStep;
    const selected = index === selection;
    drawHudRect(ROW_X + ROW_W / 2, y + 0.020, ROW_W, rowHeight,
      selected ? 34 : 31, selected ? 109 : 31, selected ? 170 : 44, 255);
    drawText(categories ? "BVC" + index : "BVN" + index, ROW_X + 0.009,
      y + (categories ? 0.005 : -0.009), 0.29, 255, 255, 255, 255, false);
    if (!categories) drawText("BVP" + index, ROW_X + 0.009, y + 0.026,
      0.27, isVehicleOwned(entries[index].model) ? 129 : 167,
      isVehicleOwned(entries[index].model) ? 224 : 205,
      isVehicleOwned(entries[index].model) ? 149 : 255, 255, false);
  }

  if (entries.length > visibleCount) {
    const trackX = SCREEN_X + SCREEN_W - 0.006;
    const trackTop = SCREEN_Y + 0.217;
    const trackHeight = categories ? 0.300 : 0.255;
    const thumbHeight = trackHeight * (visibleCount / entries.length);
    const maxScroll = Math.max(1, entries.length - visibleCount);
    const thumbCenterY = trackTop + thumbHeight / 2 + (scroll / maxScroll) * (trackHeight - thumbHeight);
    drawHudRect(trackX, trackTop + trackHeight / 2, 0.002, trackHeight, 62, 59, 77, 255);
    drawHudRect(trackX, thumbCenterY, 0.003, thumbHeight, 54, 141, 213, 255);
  }
}

function renderCheatView() {
  drawText("BPHTOOL", ROW_X, SCREEN_Y + 0.126, 0.30, 255, 126, 126, 255, false);
  drawHudRect(ROW_X + ROW_W / 2, SCREEN_Y + 0.245, ROW_W, 0.104,
    missionWasActive ? 160 : 46, missionWasActive ? 45 : 46, missionWasActive ? 45 : 60, 255);
  drawText("BPHFIN", ROW_X + 0.012, SCREEN_Y + 0.211, 0.36, 255, 255, 255, 255, false);
  drawText("BPHMST", ROW_X + 0.012, SCREEN_Y + 0.277, 0.27,
    missionWasActive ? 255 : 190, missionWasActive ? 207 : 195, missionWasActive ? 207 : 210, 255, false);
}

function updateTextStore(now) {
  const tick = Math.floor(now / 500);
  const signature = [phoneView, homeSelection, radioSelection, radioScroll,
    radioRequestedStation, radioRequestPending ? 1 : 0, radioCurrentStation,
    categorySelection, categoryScroll, productSelection, productScroll, pendingPurchase ? 1 : 0,
    carCategorySelection, carCategoryScroll, carVehicleSelection, carVehicleScroll,
    pendingVehicleAction ? pendingVehicleAction.type : "", ownedVehicles.size,
    missionWasActive ? 1 : 0, statusText].join("|");
  if (tick === textStoreLastTick && signature === textStoreLastSignature) return;
  textStoreLastTick = tick;
  textStoreLastSignature = signature;

  if (typeof FxtStore === "undefined" || !FxtStore || typeof FxtStore.insert !== "function") {
    if (!textStoreFailureLogged) {
      textStoreFailureLogged = true;
      log("Boreal Phone DE: FxtStore is unavailable; phone labels are disabled.");
    }
    return;
  }

  try {
    const clock = new Date();
    putText("BPHCLK", String(clock.getHours()).padStart(2, "0") + ":" + String(clock.getMinutes()).padStart(2, "0"));
    putText("BPHNTTL", phoneView === "home" ? "Telefon" : phoneView === "radio" ? "Radio" : phoneView === "cheats" ? "Narzedzia" :
      (phoneView === "carCategories" || phoneView === "carProducts" || phoneView === "carConfirm") ? "Samochody" : "Ekwipunek");
    putText("BPHINFO", "bOS / PERSONAL");
    putText("BPHSUB", "TWOJE APLIKACJE");
    putText("BPHHELP", "ENTER wybierz   F8 zamknij");
    putText("BPHBACK", phoneView === "radio" ? "ENTER ustaw   ESC wstecz" : "ESC wstecz");
    putText("BPHSHOP", phoneView === "confirm" ? "ENTER potwierdz   ESC anuluj" : "ENTER wybierz   ESC wstecz");
    putText("BPHSAVE", "Zapis");
    putText("BPHRADI", "Radio");
    putText("BPHQUIT", "Zamknij");
    putText("BPHARMS", "Ekwip.");
    putText("BPHCHT", "Narzedz.");
    putText("BPHCARS", "Samochody");
    putText("BPHRADT", "NATYWNE RADIO GTA SA");
    putText("BPHNOW", "STATUS");
    const actor = getPlayerActor();
    const inCar = actor && callNative("IS_CHAR_IN_ANY_CAR", actor).value === true;
    if (inCar) {
      const currentStation = RADIO_STATIONS.find((station) => station.value === radioCurrentStation);
      putText("BPHPLAY", radioRequestPending ? "USTAWIANIE..." :
        (currentStation ? currentStation.label : "RADIO GOTOWE"));
    } else {
      const requested = RADIO_STATIONS.find((station) => station.value === radioRequestedStation);
      putText("BPHPLAY", requested && radioRequestPending ? "OCZEKUJE: " + requested.label : "POZA POJAZDEM");
    }
    if (phoneView === "categories" || phoneView === "products" || phoneView === "confirm") {
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
    if (phoneView === "carCategories" || phoneView === "carProducts" || phoneView === "carConfirm") {
      const money = wallet();
      putText("BVCASH", money === null ? "SALDO NIEDOSTEPNE" : "SALDO: $" + money);
      VEHICLE_CATALOG.forEach((category, index) => putText("BVC" + index, category.label));
      const vehicles = VEHICLE_CATALOG[carCategorySelection].items;
      vehicles.forEach((item, index) => {
        putText("BVN" + index, item.label);
        putText("BVP" + index, isVehicleOwned(item.model) ? "POSIADANY" : "$" + item.price);
      });
      const item = selectedVehicle();
      putText("BVITEM", item.label);
      putText("BVCOST", "CENA: $" + item.price);
      putText("BVACT", "AUTO TRAFI DO GARAZU");
      putText("BVWARN", "ZAKUP JEST STALY~n~POJAZD MOZESZ PRZYZYWAC PONOWNIE");
      putText("BVBUY", pendingVehicleAction ? "LADOWANIE..." : "POTWIERDZ ZAKUP");
      putText("BVHINT", phoneView === "carConfirm" ? "ENTER kup   ESC anuluj" :
        (phoneView === "carProducts" && isVehicleOwned(item.model) ? "ENTER przyzwij   ESC wstecz" : "ENTER wybierz   ESC wstecz"));
    } else {
      putText("BVHINT", "ENTER wybierz   ESC wstecz");
    }
    putText("BPHTOOL", "NARZEDZIA MISJI");
    putText("BPHFIN", "UKONCZ MISJE");
    putText("BPHMST", missionWasActive ? "AKTYWNA - ENTER ABY ZAKONCZYC" : "BRAK AKTYWNEJ MISJI");
    putText("BPHCHLP", "ENTER wykonaj   ESC wstecz");
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
  if (key.length > 7) throw new Error("FXT key too long: " + key);
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

function pxX(pixels) {
  return pixels / HUD_VIRTUAL_WIDTH;
}

function pxY(pixels) {
  return pixels / HUD_VIRTUAL_HEIGHT;
}

function drawRectPx(x, y, width, height, red, green, blue, alpha) {
  callNative("DRAW_RECT", x, y, width, height, red, green, blue, alpha);
}

// Fixed-cost rounded approximation: exactly three rectangles, no scanline
// loops. The corner cut is small enough to read as an iOS-style squircle at
// HUD scale while remaining safe for SA:DE's renderer.
function drawSoftRect(x, y, width, height, radiusPx, red, green, blue, alpha) {
  const rX = pxX(Math.max(0, Math.min(radiusPx, width * HUD_VIRTUAL_WIDTH / 4)));
  const rY = pxY(Math.max(0, Math.min(radiusPx, height * HUD_VIRTUAL_HEIGHT / 4)));
  drawHudRect(x, y, Math.max(pxX(0.5), width - rX * 2), height, red, green, blue, alpha);
  drawHudRect(x, y, width, Math.max(pxY(0.5), height - rY * 2), red, green, blue, alpha);
  drawHudRect(x, y, Math.max(pxX(0.5), width - rX), Math.max(pxY(0.5), height - rY), red, green, blue, alpha);
}

function keepCategorySelectionVisible() {
  const visibleCount = 5;
  if (categorySelection < categoryScroll) categoryScroll = categorySelection;
  if (categorySelection >= categoryScroll + visibleCount) {
    categoryScroll = categorySelection - visibleCount + 1;
  }
  categoryScroll = Math.max(0, Math.min(categoryScroll, Math.max(0, ARMORY.length - visibleCount)));
}

function keepProductSelectionVisible() {
  const visibleCount = 4;
  const total = ARMORY[categorySelection].items.length;
  if (productSelection < productScroll) productScroll = productSelection;
  if (productSelection >= productScroll + visibleCount) {
    productScroll = productSelection - visibleCount + 1;
  }
  productScroll = Math.max(0, Math.min(productScroll, Math.max(0, total - visibleCount)));
}

function keepCarCategorySelectionVisible() {
  const visibleCount = 5;
  if (carCategorySelection < carCategoryScroll) carCategoryScroll = carCategorySelection;
  if (carCategorySelection >= carCategoryScroll + visibleCount) carCategoryScroll = carCategorySelection - visibleCount + 1;
  carCategoryScroll = Math.max(0, Math.min(carCategoryScroll, Math.max(0, VEHICLE_CATALOG.length - visibleCount)));
}

function keepCarVehicleSelectionVisible() {
  const visibleCount = 4;
  const total = VEHICLE_CATALOG[carCategorySelection].items.length;
  if (carVehicleSelection < carVehicleScroll) carVehicleScroll = carVehicleSelection;
  if (carVehicleSelection >= carVehicleScroll + visibleCount) carVehicleScroll = carVehicleSelection - visibleCount + 1;
  carVehicleScroll = Math.max(0, Math.min(carVehicleScroll, Math.max(0, total - visibleCount)));
}

function keepRadioSelectionVisible() {
  const visibleCount = 5;
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
  loadVehicleOwnership();
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
