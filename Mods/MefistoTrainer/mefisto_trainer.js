/// <reference path="./.config/sa.d.ts" />

// Mefisto Trainer for GTA San Andreas: The Definitive Edition.
// Requires CLEO Redux 1.5+ and ImGuiReduxWin64.

if (HOST !== "sa_unreal") {
  exit("Mefisto Trainer supports only GTA San Andreas: The Definitive Edition.");
}

const VK_F5 = 116;
const PLAYER_ID = 0;
const player = new Player(PLAYER_ID);

const weapons = [
  { name: "Brass Knuckles", id: 1 },
  { name: "Baseball Bat", id: 5 },
  { name: "Pistol", id: 22 },
  { name: "Silenced Pistol", id: 23 },
  { name: "Desert Eagle", id: 24 },
  { name: "Shotgun", id: 25 },
  { name: "Sawed-Off Shotgun", id: 26 },
  { name: "Combat Shotgun", id: 27 },
  { name: "Micro SMG", id: 28 },
  { name: "SMG", id: 29 },
  { name: "AK-47", id: 30 },
  { name: "M4", id: 31 },
  { name: "Rifle", id: 33 },
  { name: "Sniper Rifle", id: 34 },
  { name: "Rocket Launcher", id: 35 },
];

const weaponNames = weapons.map((weapon) => weapon.name).join(",");
const weatherNames = "Extra Sunny,Sunny,Cloudy,Rainy,Foggy,Sandstorm";
const weatherIds = [0, 1, 2, 8, 9, 19];

let menuVisible = false;
let f5WasDown = false;
let activeTab = 0;
let godMode = false;
let infiniteArmor = false;
let infiniteSprint = false;
let neverWanted = false;
let infiniteAmmo = false;
let vehicleInvincible = false;
let wantedLevel = 0;
let ammoAmount = 500;
let selectedWeapon = 10;
let selectedWeather = 1;
let selectedHour = 12;
let selectedMinute = 0;
let freezeTime = false;
let savedPosition = null;

log("Mefisto Trainer loaded. Press F5 to open the menu.");

while (true) {
  wait(0);

  // Treat F5 as a key press, not as a held state. Otherwise one physical
  // press toggles the menu repeatedly while the key remains down.
  const f5Down = Pad.IsKeyDown(VK_F5);
  if (f5Down && !f5WasDown) {
    menuVisible = !menuVisible;
  }
  f5WasDown = f5Down;

  const gameIsPlaying = player.isPlaying();
  if (!gameIsPlaying) {
    menuVisible = false;
  }
  const trainerVisible = menuVisible && gameIsPlaying;

  // Keep the cursor state and all interactive widgets in the same ImGuiRedux
  // frame. Separate frames can submit different input/cursor state and make
  // the pointer jump, disappear or stop clicking under Wine.
  ImGui.BeginFrame("MEFISTO_TRAINER_WINDOW");
  ImGui.SetCursorVisible(trainerVisible);

  if (gameIsPlaying) {
    const actor = player.getChar();
    applyPersistentOptions(actor);

    if (trainerVisible) {
      drawTrainerWindow(actor);
    }
  }

  ImGui.EndFrame();
}

function drawTrainerWindow(actor) {
  // Keep the window large enough for the longest sections and force the
  // dimensions on every frame so an older cached size cannot clip the menu.
  ImGui.SetNextWindowPos(24, 24, 1);
  ImGui.SetNextWindowSize(760, 680, 1);
  // Do not copy the delayed Begin() return value back into menuVisible. The
  // trainer is closed with F5, so its visibility has one authoritative state.
  ImGui.Begin("MEFISTO TRAINER", true, false, true, false, false);

  ImGui.TextColored("MEFISTO", 52, 199, 89, 255);
  ImGui.SameLine();
  ImGui.TextDisabled("San Andreas: Definitive Edition  |  F5 close");
  ImGui.Separator();
  ImGui.Spacing();

  activeTab = ImGui.Tabs("MefistoTabs", "Player,Weapons,Vehicle,World,Teleport");
  ImGui.Spacing();
  ImGui.BeginChild("MefistoContent");

  if (activeTab === 0) drawPlayerSection(actor);
  if (activeTab === 1) drawWeaponsSection(actor);
  if (activeTab === 2) drawVehicleSection(actor);
  if (activeTab === 3) drawWorldSection();
  if (activeTab === 4) drawTeleportSection(actor);

  ImGui.EndChild();
  ImGui.End();
}

function drawPlayerSection(actor) {
  ImGui.Text("PLAYER");
  ImGui.TextDisabled("Health, stamina and police response");
  ImGui.Separator();
  ImGui.Spacing();

  godMode = ImGui.Checkbox("God Mode", godMode);
  infiniteArmor = ImGui.Checkbox("Infinite Armor", infiniteArmor);
  infiniteSprint = ImGui.Checkbox("Infinite Sprint", infiniteSprint);
  neverWanted = ImGui.Checkbox("Never Wanted", neverWanted);
  ImGui.Spacing();
  wantedLevel = ImGui.SliderInt("Wanted Level", wantedLevel, 0, 6);
  if (ImGui.Button("Apply Wanted Level", 180, 28)) {
    if (wantedLevel === 0) player.clearWantedLevel();
    else player.alterWantedLevel(wantedLevel);
  }
  ImGui.SameLine();
  if (ImGui.Button("Restore Health & Armor", 220, 28)) {
    actor.setHealth(100);
    actor.addArmor(100);
  }
}

function drawWeaponsSection(actor) {
  ImGui.Text("WEAPONS");
  ImGui.TextDisabled("Give a weapon and configure ammunition");
  ImGui.Separator();
  ImGui.Spacing();

  selectedWeapon = ImGui.ComboBox("Weapon", weaponNames, selectedWeapon);
  ammoAmount = ImGui.SliderInt("Ammo", ammoAmount, 50, 9999);
  infiniteAmmo = ImGui.Checkbox("Infinite Ammo", infiniteAmmo);
  ImGui.Spacing();
  if (ImGui.Button("Give Weapon", 160, 28)) {
    const weapon = weapons[selectedWeapon];
    actor.giveWeapon(weapon.id, ammoAmount);
    actor.setCurrentWeapon(weapon.id);
  }
}

function drawVehicleSection(actor) {
  ImGui.Text("VEHICLE");
  ImGui.TextDisabled("Options apply to the current vehicle");
  ImGui.Separator();
  ImGui.Spacing();

  if (!actor.isInAnyCar()) {
    ImGui.TextColored("Enter a vehicle to use these options.", 235, 166, 52, 255);
    return;
  }

  vehicleInvincible = ImGui.Checkbox("Invincible Vehicle", vehicleInvincible);
  const vehicle = actor.storeCarIsInNoSave();

  if (ImGui.Button("Repair Vehicle", 180, 28)) {
    vehicle.fix();
    vehicle.setHealth(1000);
  }
}

function drawWorldSection() {
  ImGui.Text("WORLD");
  ImGui.TextDisabled("Weather and clock controls");
  ImGui.Separator();
  ImGui.Spacing();

  selectedWeather = ImGui.ComboBox("Weather", weatherNames, selectedWeather);
  if (ImGui.Button("Apply Weather", 160, 28)) {
    Weather.ForceNow(weatherIds[selectedWeather]);
  }
  ImGui.SameLine();
  if (ImGui.Button("Release Weather", 160, 28)) {
    Weather.Release();
  }

  selectedHour = ImGui.SliderInt("Hour", selectedHour, 0, 23);
  selectedMinute = ImGui.SliderInt("Minute", selectedMinute, 0, 59);
  freezeTime = ImGui.Checkbox("Freeze Time", freezeTime);
  if (ImGui.Button("Apply Time", 160, 28)) {
    Clock.SetTimeOfDay(selectedHour, selectedMinute);
  }
}

function drawTeleportSection(actor) {
  ImGui.Text("TELEPORT");
  ImGui.TextDisabled("City shortcuts and one temporary position");
  ImGui.Separator();
  ImGui.Spacing();

  if (ImGui.Button("Grove Street", 160, 28)) actor.setCoordinates(2491.2, -1668.0, 13.3);
  ImGui.SameLine();
  if (ImGui.Button("Los Santos Airport", 160, 28)) actor.setCoordinates(1687.0, -2334.0, 13.5);
  if (ImGui.Button("San Fierro", 160, 28)) actor.setCoordinates(-1985.0, 138.0, 27.7);
  ImGui.SameLine();
  if (ImGui.Button("Las Venturas", 160, 28)) actor.setCoordinates(1699.0, 1447.0, 10.8);

  ImGui.Spacing();
  if (ImGui.Button("Save Current Position", 200, 28)) {
    savedPosition = actor.getCoordinates();
  }
  ImGui.SameLine();
  if (savedPosition && ImGui.Button("Restore Saved Position", 200, 28)) {
    actor.setCoordinates(savedPosition.x, savedPosition.y, savedPosition.z);
  }
}

function applyPersistentOptions(actor) {
  player.setNeverGetsTired(infiniteSprint);
  actor.setProofs(godMode, godMode, godMode, godMode, godMode);

  if (godMode && actor.getHealth() < 100) actor.setHealth(100);
  if (infiniteArmor && actor.getArmor() < 100) actor.addArmor(100);
  if (neverWanted) player.clearWantedLevel();

  if (infiniteAmmo) {
    const weapon = actor.getCurrentWeapon();
    if (weapon > 0) actor.setAmmo(weapon, 9999);
  }

  if (actor.isInAnyCar()) {
    const vehicle = actor.storeCarIsInNoSave();
    vehicle.setProofs(
      vehicleInvincible,
      vehicleInvincible,
      vehicleInvincible,
      vehicleInvincible,
      vehicleInvincible
    );
    if (vehicleInvincible && vehicle.getHealth() < 1000) vehicle.setHealth(1000);
  }

  // Keep the in-game clock fixed without pausing simulation, physics or AI.
  if (freezeTime) Clock.SetTimeOfDay(selectedHour, selectedMinute);
}
