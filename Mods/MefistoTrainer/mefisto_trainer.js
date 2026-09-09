/// <reference path="./.config/sa.d.ts" />

import { itemCatalog, namesFor, vehicleCatalog } from "./MefistoTrainer/catalog.mjs";
import { ItemSpawner } from "./MefistoTrainer/item_spawner.mjs";
import { VehicleSpawner } from "./MefistoTrainer/vehicle_spawner.mjs";

if (HOST !== "sa_unreal") exit("Mefisto Trainer supports only GTA San Andreas: The Definitive Edition.");

const player = new Player(0);
const items = new ItemSpawner();
const vehicles = new VehicleSpawner();
// ImGuiRedux color arguments are normalized floats, not 0-255 channel values.
const accent = [0.27, 0.67, 1.0, 1.0];
const weatherNames = "Extra Sunny,Sunny,Cloudy,Rainy,Foggy,Sandstorm";
const weatherIds = [0, 1, 2, 8, 9, 19];
const navigation = [
  ["[P]", "Player", "player"], ["[W]", "Weapons", "weapons"], ["[V]", "Vehicles", "vehicles"],
  ["[O]", "World", "world"], ["[T]", "Teleport", "teleport"], ["[C]", "Time & Weather", "world"],
  ["[C]", "Camera"], ["[A]", "Target Focus"], ["[...]", "Misc"], ["[D]", "Developer"], ["[S]", "Settings"],
];
const filters = [
  ["All", "all"], ["Favorites", "favorites"], ["Recent", "recent"], ["Cars", "cars"],
  ["Sports", "sports"], ["Bikes", "bikes"], ["Off-road", "off-road"], ["Aircraft", "aircraft"],
  ["Boats", "boats"], ["Emergency", "service"], ["Unique", "unique"],
];

let menuVisible = false, active = "vehicles";
let godMode = false, infiniteArmor = false, infiniteSprint = false, neverWanted = false;
let infiniteAmmo = false, vehicleInvincible = false, wantedLevel = 0, ammo = 500;
let selectedWeapon = 0, selectedVehicleId = 411, filter = "all", search = "";
let selectedWeather = 1, hour = 12, minute = 0, freezeTime = false, savedPosition = null;
let recentIds = [], toast = "", toastUntil = 0;
const favorites = new Set(vehicleCatalog.filter((v) => v.favorite).map((v) => v.id));

log("Mefisto Trainer loaded. Press F5 to open the menu.");
while (true) {
  wait(0);
  if (Pad.IsKeyPressed(116)) {
    menuVisible = !menuVisible;
    log("Mefisto Trainer F5 toggle: " + (menuVisible ? "open" : "closed"));
  }
  const playing = player.isPlaying();
  if (!playing) menuVisible = false;
  const visible = menuVisible && playing;
  ImGui.BeginFrame("MEFISTO_TRAINER_WINDOW");
  ImGui.SetCursorVisible(visible);
  if (playing) {
    const actor = player.getChar();
    applyPersistentOptions(actor);
    if (visible) drawWindow(actor);
  }
  ImGui.EndFrame();
}

function drawWindow(actor) {
  const size = ImGui.GetDisplaySize();
  const width = Math.floor(size.width * 0.75), height = Math.floor(size.height * 0.75);
  ImGui.SetNextWindowPos(Math.floor((size.width - width) / 2), Math.floor((size.height - height) / 2), 1);
  ImGui.SetNextWindowSize(width, height, 1);
  ImGui.SetNextWindowTransparency(0.94);
  ImGui.Begin("MEFISTO TRAINER", true, true, true, false, false);
  const childHeight = Math.max(360, height - 62);
  ImGui.BeginChildEx("MefistoSidebar", 236, childHeight, true, 0);
  drawSidebar();
  ImGui.EndChild();
  ImGui.SameLine();
  ImGui.BeginChildEx("MefistoContent", Math.max(420, width - 566), childHeight, true, 0);
  drawContent(actor);
  ImGui.EndChild();
  ImGui.SameLine();
  ImGui.BeginChildEx("MefistoDetails", 314, childHeight, true, 0);
  drawDetails(actor);
  ImGui.EndChild();
  ImGui.TextDisabled("ENTER  Select    ESC  Back    F  Favorite    R  Spawn Options    F5  Close");
  ImGui.SameLine();
  ImGui.TextDisabled("Mefisto Trainer v1.0");
  ImGui.End();
}

function drawSidebar() {
  ImGui.TextColored("MEFISTO", 0.92, 0.94, 0.97, 1.0);
  ImGui.TextColored("TRAINER", accent[0], accent[1], accent[2], 1.0);
  ImGui.TextDisabled("GTA SAN ANDREAS");
  ImGui.TextDisabled("DEFINITIVE EDITION");
  ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing();
  navigation.forEach((entry) => {
    if (!entry[2]) { ImGui.TextDisabled(entry[0] + "  " + entry[1]); return; }
    const selected = active === entry[2];
    const label = (selected ? "| " : "  ") + entry[0] + "  " + entry[1];
    if (selected) ImGui.ButtonColored(label, accent[0], accent[1], accent[2], 0.88, 218, 28);
    else if (ImGui.Selectable(label, false)) active = entry[2];
  });
  ImGui.Spacing(); ImGui.TextDisabled("F5  Close trainer");
}

function drawContent(actor) {
  if (active === "vehicles") drawVehicles(actor);
  if (active === "player") drawPlayer(actor);
  if (active === "weapons") drawWeapons(actor);
  if (active === "world") drawWorld();
  if (active === "teleport") drawTeleport(actor);
}

function header(title, subtitle) {
  ImGui.Text(title); ImGui.TextDisabled(subtitle); ImGui.Spacing();
}

function drawVehicles(actor) {
  header("Vehicles", "Spawn any vehicle in the game");
  search = ImGui.InputText("Search vehicles...");
  if (search === undefined) search = "";
  ImGui.Spacing();
  filters.forEach((f, i) => {
    if (i) ImGui.SameLine();
    if (filter === f[1]) ImGui.ButtonColored(f[0], accent[0], accent[1], accent[2], 0.88, 78, 25);
    else if (ImGui.Button(f[0], 78, 25)) filter = f[1];
  });
  ImGui.Separator(); ImGui.Spacing();
  const list = filteredVehicles();
  if (!list.length) { ImGui.TextDisabled("No vehicles match this search."); return; }
  if (!list.some((v) => v.id === selectedVehicleId)) selectedVehicleId = list[0].id;
  ImGui.Columns(4);
  list.forEach((v) => {
    const selected = v.id === selectedVehicleId;
    if (ImGui.ButtonColored(v.name, selected ? accent[0] : 0.11, selected ? accent[1] : 0.13, selected ? accent[2] : 0.16, 0.96, 136, 58)) selectedVehicleId = v.id;
    ImGui.TextDisabled(v.category);
    if (ImGui.Button("Favorite##favorite_" + v.id, 72, 22)) toggleFavorite(v.id);
    ImGui.NextColumn();
  });
  ImGui.Columns(1);
}

function filteredVehicles() {
  const q = (search || "").toLowerCase().trim();
  return vehicleCatalog.filter((v) => {
    if (q && !(v.name + " " + v.model + " " + v.tags.join(" ")).toLowerCase().includes(q)) return false;
    if (filter === "favorites") return favorites.has(v.id);
    if (filter === "recent") return recentIds.includes(v.id);
    if (filter === "off-road") return v.category === "utility";
    if (filter === "unique") return ["other", "trailers", "trains", "rc"].includes(v.category);
    return filter === "all" || v.category === filter;
  });
}

function drawDetails(actor) {
  if (active !== "vehicles") { ImGui.TextDisabled("Details"); ImGui.Separator(); ImGui.TextDisabled("Select Vehicles to inspect a catalog entry."); return; }
  const v = vehicleCatalog.find((entry) => entry.id === selectedVehicleId) || vehicleCatalog[0];
  ImGui.Text(v.name + (favorites.has(v.id) ? "  [Favorite]" : ""));
  if (ImGui.Button("Favorite##detail_favorite", 90, 22)) toggleFavorite(v.id);
  ImGui.Spacing();
  ImGui.ButtonColored("Vehicle Preview", 0.14, 0.16, 0.20, 0.96, 280, 82);
  ImGui.TextCentered(v.name);
  ImGui.Spacing();
  detail("Model ID", String(v.id)); detail("Category", v.category); detail("Type", v.category === "boats" ? "Boat" : v.category === "aircraft" ? "Aircraft" : "Vehicle"); detail("Model", v.model);
  ImGui.Spacing();
  if (ImGui.ButtonColored("Spawn", accent[0], accent[1], accent[2], 0.88, 280, 38)) spawn(v, actor);
  if (ImGui.Button("Spawn & Enter", 280, 28)) spawn(v, actor);
  if (ImGui.Button("Replace Current Vehicle", 280, 28)) spawn(v, actor);
  if (ImGui.Button("Customize", 280, 28)) notify("Vehicle customization is unavailable in this build.");
  ImGui.Spacing();
  ImGui.Text("Current Vehicle");
  vehicleInvincible = ImGui.Checkbox("Invincible Vehicle", vehicleInvincible);
  if (actor.isInAnyCar() && ImGui.Button("Repair Current Vehicle", 280, 28)) {
    const currentVehicle = actor.storeCarIsInNoSave();
    currentVehicle.fix();
    currentVehicle.setHealth(1000);
    notify("Current vehicle repaired.");
  }
  if (toast && Date.now() < toastUntil) ImGui.TextDisabled(toast);
}

function detail(label, value) { ImGui.TextDisabled(label); ImGui.SameLine(); ImGui.Text(value); }
function toggleFavorite(id) { if (favorites.has(id)) favorites.delete(id); else favorites.add(id); }
function notify(message) { toast = message; toastUntil = Date.now() + 2000; }
function spawn(v, actor) { const result = vehicles.spawn(v, actor); recentIds = [v.id, ...recentIds.filter((id) => id !== v.id)].slice(0, 12); notify(result.message); }

function drawPlayer(actor) {
  header("Player", "Personal abilities and police response");
  godMode = ImGui.Checkbox("God Mode", godMode); infiniteArmor = ImGui.Checkbox("Infinite Armor", infiniteArmor);
  infiniteSprint = ImGui.Checkbox("Infinite Sprint", infiniteSprint); neverWanted = ImGui.Checkbox("Never Wanted", neverWanted);
  ImGui.Spacing(); wantedLevel = ImGui.SliderInt("Wanted Level", wantedLevel, 0, 6);
  if (ImGui.Button("Apply Wanted Level", 180, 28)) { if (wantedLevel === 0) player.clearWantedLevel(); else player.alterWantedLevel(wantedLevel); }
  ImGui.SameLine();
  if (ImGui.Button("Restore Health & Armor", 220, 28)) { actor.setHealth(100); actor.addArmor(100); }
}

function drawWeapons(actor) {
  header("Weapons", "Give weapons and configure ammunition");
  ["All", "Melee", "Pistols", "Shotguns", "SMGs", "Rifles", "Heavy", "Explosives"].forEach((name, i) => { if (i) ImGui.SameLine(); ImGui.Button(name, 82, 25); });
  ImGui.Spacing(); selectedWeapon = ImGui.ComboBox("Weapon", namesFor(itemCatalog), selectedWeapon);
  ammo = ImGui.SliderInt("Ammo", ammo, 50, 9999); infiniteAmmo = ImGui.Checkbox("Infinite Ammo", infiniteAmmo);
  if (ImGui.ButtonColored("Give", accent[0], accent[1], accent[2], 0.88, 180, 34)) { items.give(itemCatalog[selectedWeapon], actor, ammo); notify("Weapon given."); }
  ImGui.SameLine(); if (ImGui.Button("Give & Equip", 180, 34)) items.give(itemCatalog[selectedWeapon], actor, ammo);
}

function drawWorld() {
  header("Time & Weather", "Control the world without leaving the game");
  ImGui.Text("Time"); hour = ImGui.SliderInt("Hour", hour, 0, 23); minute = ImGui.SliderInt("Minute", minute, 0, 59); freezeTime = ImGui.Checkbox("Freeze Time", freezeTime);
  if (ImGui.Button("Apply Time", 180, 30)) Clock.SetTimeOfDay(hour, minute);
  ImGui.Spacing(); ImGui.Text("Weather"); selectedWeather = ImGui.ComboBox("Weather", weatherNames, selectedWeather);
  if (ImGui.ButtonColored("Apply Weather", accent[0], accent[1], accent[2], 0.88, 180, 30)) Weather.ForceNow(weatherIds[selectedWeather]);
  ImGui.SameLine(); if (ImGui.Button("Release Weather", 180, 30)) Weather.Release();
}

function drawTeleport(actor) {
  header("Teleport", "Move between known locations or save a position");
  [["Grove Street", 2491.2, -1668.0, 13.3], ["San Fierro", -1985.0, 138.0, 27.7], ["Las Venturas", 1699.0, 1447.0, 10.8], ["Los Santos Airport", 1687.0, -2334.0, 13.5]].forEach((l) => { if (ImGui.Button(l[0], 190, 30)) actor.setCoordinates(l[1], l[2], l[3]); });
  ImGui.Spacing(); if (ImGui.Button("Save Current Position", 220, 30)) savedPosition = actor.getCoordinates(); ImGui.SameLine();
  if (savedPosition && ImGui.Button("Restore Saved Position", 220, 30)) actor.setCoordinates(savedPosition.x, savedPosition.y, savedPosition.z);
}

function applyPersistentOptions(actor) {
  player.setNeverGetsTired(infiniteSprint); actor.setProofs(godMode, godMode, godMode, godMode, godMode);
  if (godMode && actor.getHealth() < 100) actor.setHealth(100); if (infiniteArmor && actor.getArmor() < 100) actor.addArmor(100); if (neverWanted) player.clearWantedLevel();
  if (infiniteAmmo) { const weapon = actor.getCurrentWeapon(); if (weapon > 0) actor.setAmmo(weapon, 9999); }
  if (actor.isInAnyCar()) { const vehicle = actor.storeCarIsInNoSave(); vehicle.setProofs(vehicleInvincible, vehicleInvincible, vehicleInvincible, vehicleInvincible, vehicleInvincible); if (vehicleInvincible && vehicle.getHealth() < 1000) vehicle.setHealth(1000); }
  if (freezeTime) Clock.SetTimeOfDay(hour, minute);
}
