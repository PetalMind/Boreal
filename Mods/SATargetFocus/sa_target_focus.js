/// <reference path="./.config/sa.d.ts" />

// SA Target Focus for GTA San Andreas: The Definitive Edition.
// Requires CLEO Redux 1.5+ and ImGuiReduxWin64.
//
// This is deliberately a soft lock. It never fires a weapon, changes the
// player's aim input, or teleports the crosshair to a bone. The camera target
// is blended a little towards a visible hostile ped while the aim button is
// held, so the player remains in control.

log("SA Target Focus initializing. Host: " + HOST);

if (HOST !== "sa_unreal") {
  exit("SA Target Focus supports only GTA San Andreas: The Definitive Edition.");
}

const PLAYER_ID = 0;
const CONFIG_PATH = "./SA_TargetFocus.ini";
const CONFIG_VERSION = 1;
const VK_DEFAULT_OPEN_MENU = 117; // F6; F5 is used by the Mefisto Trainer.
const VK_DEFAULT_TOGGLE_FOCUS = 118; // F7.
const VK_DEFAULT_NEXT_TARGET = 5; // Mouse 4.
const VK_DEFAULT_PREVIOUS_TARGET = 6; // Mouse 5.
const RIGHT_MOUSE_BUTTON = 2;
const AIM_BUTTON = 5; // Left shoulder 2 / LT in the GTA pad layout.
const PAD_ID = 0;
const DEFAULT_MAX_TARGET_DISTANCE = 60.0;
const TARGET_SCAN_RADIUS = 18.0;
const TARGET_SCAN_INTERVAL_MS = 75;
const TARGET_SWITCH_COOLDOWN_MS = 350;
const TARGET_LOST_GRACE_ANGLE = 8.0;
const MANUAL_OVERRIDE_THRESHOLD = 24;
const TARGET_SWITCH_HYSTERESIS_MIN = 0.06;
const TARGET_SWITCH_HYSTERESIS_MAX = 0.24;
const CANDIDATE_ACQUIRE_DELAY_MS = 140;
const LOCK_ACQUIRED_DURATION_MS = 160;
const TARGET_SWITCH_FADE_OUT_MS = 100;
const MARKER_FADE_OUT_MS = 190;
const MARKER_FADE_IN_MS = 120;
const LOST_TARGET_ARROW_MS = 300;

const HUD_NONE = 0;
const HUD_CANDIDATE = 1;
const HUD_LOCKED = 2;

const MODE_FREE_AIM = 0;
const MODE_SOFT_LOCK = 1;
const MODE_CLASSIC_LOCK_ON = 2;

const player = new Player(PLAYER_ID);

const modes = ["Free Aim+", "Soft Lock", "Classic Lock-On"];
const fovNames = ["Narrow (10°)", "Normal (25°)", "Wide (45°)"];
const fovValues = [10, 25, 45];
const targetPointNames = ["Center Mass", "Upper Body", "Dynamic"];
const indicatorNames = ["OFF", "Minimal", "Classic SA", "Modern"];
const targetHighlightNames = ["OFF", "Corners", "Outline", "Classic GTA"];
const breakDelayNames = ["0.0 sec", "0.3 sec", "0.4 sec", "0.5 sec", "1.0 sec"];
const breakDelayValues = [0, 300, 400, 500, 1000];
const presetNames = ["Free Aim+", "Balanced", "Strong Assist", "Classic Lock-On", "Custom"];

const presetProfiles = [
  {
    modeIndex: MODE_FREE_AIM,
    aimAssistPercent: 30,
    stickinessPercent: 25,
    fovIndex: 0,
    frictionPercent: 15,
    cameraSmoothingPercent: 75,
    breakDelayIndex: 1,
    targetPointIndex: 0,
    indicatorIndex: 1,
    targetHighlightIndex: 1,
    showStatusIndicator: true,
  },
  {
    modeIndex: MODE_SOFT_LOCK,
    aimAssistPercent: 55,
    stickinessPercent: 65,
    fovIndex: 1,
    frictionPercent: 35,
    cameraSmoothingPercent: 60,
    breakDelayIndex: 2,
    targetPointIndex: 0,
    indicatorIndex: 1,
    targetHighlightIndex: 1,
    showStatusIndicator: true,
  },
  {
    modeIndex: MODE_SOFT_LOCK,
    aimAssistPercent: 80,
    stickinessPercent: 85,
    fovIndex: 2,
    frictionPercent: 65,
    cameraSmoothingPercent: 45,
    breakDelayIndex: 3,
    targetPointIndex: 0,
    indicatorIndex: 2,
    targetHighlightIndex: 3,
    showStatusIndicator: true,
  },
  {
    modeIndex: MODE_CLASSIC_LOCK_ON,
    aimAssistPercent: 85,
    stickinessPercent: 90,
    fovIndex: 1,
    frictionPercent: 75,
    cameraSmoothingPercent: 35,
    breakDelayIndex: 1,
    targetPointIndex: 0,
    indicatorIndex: 2,
    targetHighlightIndex: 3,
    showStatusIndicator: true,
  },
];

let menuVisible = false;
let openMenuKey = VK_DEFAULT_OPEN_MENU;
let toggleFocusKey = VK_DEFAULT_TOGGLE_FOCUS;
let nextTargetKey = VK_DEFAULT_NEXT_TARGET;
let previousTargetKey = VK_DEFAULT_PREVIOUS_TARGET;
let openMenuWasDown = false;
let toggleFocusWasDown = false;
let enabled = true;
let modeIndex = MODE_SOFT_LOCK;
let fovIndex = 1;
let aimAssistPercent = 55;
let stickinessPercent = 65;
let frictionPercent = 35;
let cameraSmoothingPercent = 60;
let maximumDistanceMeters = DEFAULT_MAX_TARGET_DISTANCE;
let targetPointIndex = 0;
let indicatorIndex = 1;
let targetHighlightIndex = 1;
let showStatusIndicator = true;
let breakDelayIndex = 2;
let selectedPresetIndex = 1;
let includeHostileNPC = true;
let includeEnemyGangs = true;
let includePolice = true;
let includeCivilians = false;
let allowManualOverride = true;
let developerMode = false;
let activeSettingsPage = 0;

let focusTarget = null;
let focusWasApplied = false;
let cameraAnchorTarget = null;
let lostSightAt = 0;
let switchAvailableAt = 0;
let visibleCandidates = [];
let candidateTarget = null;
let candidateSince = 0;
let candidateSnapshot = null;
let lastFocusState = null;
let lastTargetSnapshot = null;
let markerFades = [];
let lockAcquiredAt = 0;
let screenProjectionAvailable = true;
let candidateHandles = [];
let lastCandidateScanAt = 0;
let configDirty = false;
let configSaveDueAt = 0;
let lastFrameAt = Date.now();
let lastDiagnostics = {
  target: null,
  active: false,
  score: null,
  distance: null,
  angle: null,
  visible: false,
  candidateCount: 0,
  scannerTimeMs: 0,
  frameTimeMs: 0,
  correction: 0,
  manualOverride: false,
};

loadConfig();
normalizeHotkeys();

log("SA Target Focus loaded. Hold aim and press F6 for settings.");

while (true) {
  wait(0);

  const frameNow = Date.now();
  lastDiagnostics.frameTimeMs = Math.max(0, frameNow - lastFrameAt);
  lastFrameAt = frameNow;
  saveConfigIfDue(frameNow);

  const openMenuDown = isKeyPressed(openMenuKey);
  if (openMenuDown && !openMenuWasDown) {
    menuVisible = !menuVisible;
  }
  openMenuWasDown = openMenuDown;

  const toggleFocusDown = isKeyPressed(toggleFocusKey);
  if (toggleFocusDown && !toggleFocusWasDown) {
    enabled = !enabled;
    markConfigDirty();
  }
  toggleFocusWasDown = toggleFocusDown;

  ImGui.BeginFrame("SA_TARGET_FOCUS_WINDOW");
  ImGui.SetCursorVisible(menuVisible);

  const playing = player.isPlaying();
  if (!playing) menuVisible = false;
  if (playing && !menuVisible && enabled) {
    const actor = player.getChar();
    if (isAimHeld()) {
      updateFocus(actor);
    } else {
      clearFocus();
      visibleCandidates = [];
    }
  } else {
    clearFocus();
    visibleCandidates = [];
  }

  if (playing && !menuVisible && enabled) {
    drawIndicators();
  }

  if (menuVisible) {
    drawSettingsWindow();
  }

  ImGui.EndFrame();
}

function drawSettingsWindow() {
  ImGui.SetNextWindowPos(28, 90, 2);
  ImGui.SetNextWindowSize(520, 570, 2);
  ImGui.Begin("SA TARGET FOCUS", true, false, true, false, false);

  ImGui.TextColored("TARGET FOCUS", 70, 170, 255, 255);
  ImGui.SameLine();
  ImGui.TextDisabled("Single-player soft aim assist  |  " + keyLabel(openMenuKey) + " close");
  ImGui.Separator();
  ImGui.Spacing();

  const presetBefore = selectedPresetIndex;
  selectedPresetIndex = ImGui.ComboBox("Preset", presetNames.join(","), selectedPresetIndex);
  let presetApplied = false;
  if (selectedPresetIndex !== presetBefore && selectedPresetIndex < presetProfiles.length) {
    applyPreset(selectedPresetIndex);
    presetApplied = true;
  } else if (selectedPresetIndex !== presetBefore) {
    markConfigDirty();
  }

  activeSettingsPage = ImGui.Tabs(
    "TargetFocusTabs",
    "Target Focus,Advanced,Developer"
  );

  if (activeSettingsPage === 0) drawTargetFocusPage(presetApplied);
  if (activeSettingsPage === 1) drawAdvancedPage(presetApplied);
  if (activeSettingsPage === 2) drawDeveloperPage();

  ImGui.Spacing();
  ImGui.Separator();
  ImGui.Spacing();
  ImGui.TextDisabled("Aim: Right Mouse / LT");
  ImGui.TextDisabled("Switch target: Mouse 4/5 or right stick");
  ImGui.TextDisabled("Settings save automatically to SA_TargetFocus.ini");
  ImGui.TextDisabled(focusTarget ? "Status: TARGET LOCKED" : "Status: SEARCHING");
  const hotkeyConflict = getHotkeyConflict();
  if (hotkeyConflict) {
    ImGui.TextColored("Hotkey conflict: " + hotkeyConflict, 255, 166, 64, 255);
  }

  ImGui.End();
}

function drawTargetFocusPage(presetApplied) {
  const before = settingsFingerprint();
  let restoreDefaultsPressed = false;

  enabled = ImGui.Checkbox("Enabled", enabled);
  modeIndex = ImGui.ComboBox("Mode", modes.join(","), modeIndex);
  aimAssistPercent = ImGui.SliderInt("Strength (%)", aimAssistPercent, 0, 100);
  fovIndex = ImGui.ComboBox("Detection FOV", fovNames.join(","), fovIndex);
  stickinessPercent = ImGui.SliderInt("Target Stickiness (%)", stickinessPercent, 0, 100);
  targetPointIndex = ImGui.ComboBox("Target Point", targetPointNames.join(","), targetPointIndex);
  indicatorIndex = ImGui.ComboBox("Visual Style", indicatorNames.join(","), indicatorIndex);
  targetHighlightIndex = ImGui.ComboBox(
    "Target Highlight",
    targetHighlightNames.join(","),
    targetHighlightIndex
  );
  showStatusIndicator = ImGui.Checkbox("Show Status Indicator", showStatusIndicator);

  ImGui.Spacing();
  ImGui.TextDisabled("Only visible peds inside the detection cone are considered.");
  ImGui.TextDisabled("Priority: crosshair 45% | visibility 25% | distance 15% | threat 15%");
  ImGui.TextDisabled("Minimal: crosshair state + subtle target corners.");
  ImGui.Spacing();
  if (ImGui.Button("Reset Targeting", 150, 28)) {
    resetTargetingSettings();
  }
  ImGui.SameLine();
  if (ImGui.Button("Reset Visuals", 150, 28)) {
    resetVisualSettings();
  }
  ImGui.SameLine();
  if (ImGui.Button("Restore Defaults", 150, 28)) {
    restoreDefaults();
    restoreDefaultsPressed = true;
  }

  if (!presetApplied && before !== settingsFingerprint() && !restoreDefaultsPressed) {
    selectedPresetIndex = presetProfiles.length;
    markConfigDirty();
  }
}

function drawAdvancedPage(presetApplied) {
  const before = settingsFingerprint();

  ImGui.Text("ADVANCED TARGETING");
  ImGui.TextDisabled("Tune the assist without exposing internal game details.");
  ImGui.Separator();
  ImGui.Spacing();
  frictionPercent = ImGui.SliderInt("Aim Friction (%)", frictionPercent, 0, 100);
  cameraSmoothingPercent = ImGui.SliderInt(
    "Camera Smoothing (%)",
    cameraSmoothingPercent,
    0,
    100
  );
  maximumDistanceMeters = ImGui.SliderInt(
    "Maximum Distance (m)",
    maximumDistanceMeters,
    10,
    120
  );
  breakDelayIndex = ImGui.ComboBox("Lost Target Delay", breakDelayNames.join(","), breakDelayIndex);
  allowManualOverride = ImGui.Checkbox("Allow Manual Override", allowManualOverride);

  ImGui.Spacing();
  ImGui.Text("TARGETS");
  ImGui.TextDisabled("Mission allies are not selected until targeted or damaged by the player.");
  ImGui.Separator();
  ImGui.Spacing();
  includeHostileNPC = ImGui.Checkbox("Hostile NPC and mission threats", includeHostileNPC);
  includeEnemyGangs = ImGui.Checkbox("Enemy gangs", includeEnemyGangs);
  includePolice = ImGui.Checkbox("Police while pursuing the player", includePolice);
  includeCivilians = ImGui.Checkbox("Civilians", includeCivilians);
  ImGui.Spacing();
  if (ImGui.Button("Reset Targeting", 180, 28)) {
    resetTargetingSettings();
  }
  ImGui.SameLine();
  if (ImGui.Button("Reset Camera", 180, 28)) {
    resetCameraSettings();
  }

  if (!presetApplied && before !== settingsFingerprint()) {
    selectedPresetIndex = presetProfiles.length;
    markConfigDirty();
  }
}

function drawDeveloperPage() {
  ImGui.Text("DEVELOPER MODE");
  ImGui.TextDisabled("Diagnostics are read-only and never affect targeting.");
  ImGui.Separator();
  ImGui.Spacing();
  const before = developerMode;
  developerMode = ImGui.Checkbox("Developer Mode", developerMode);
  if (before !== developerMode) markConfigDirty();

  if (!developerMode) {
    ImGui.TextDisabled("Enable Developer Mode to inspect the live targeting pipeline.");
    return;
  }

  const targetName = lastDiagnostics.active
    ? "PED HANDLE ACTIVE"
    : lastDiagnostics.target
      ? "Last target (not active)"
      : "None";
  const score = lastDiagnostics.score === null ? "Unavailable" : lastDiagnostics.score.toFixed(3);
  const distance =
    lastDiagnostics.distance === null ? "Unavailable" : lastDiagnostics.distance.toFixed(1) + " m";
  const angle = lastDiagnostics.angle === null ? "Unavailable" : lastDiagnostics.angle.toFixed(1) + "°";
  ImGui.Text("Current target: " + targetName);
  ImGui.Text("Distance: " + distance);
  ImGui.Text("Target score: " + score);
  ImGui.Text("Visibility: " + (lastDiagnostics.visible ? "Visible" : "Unavailable"));
  ImGui.Text("Candidates: " + lastDiagnostics.candidateCount);
  ImGui.Text("Crosshair angle: " + angle);
  ImGui.Text("Aim correction: " + lastDiagnostics.correction.toFixed(3));
  ImGui.Text("Manual override: " + (lastDiagnostics.manualOverride ? "Active" : "Inactive"));
  ImGui.Text("Scanner time: " + lastDiagnostics.scannerTimeMs + " ms");
  ImGui.Text("Frame time: " + lastDiagnostics.frameTimeMs + " ms");
  ImGui.Spacing();
  ImGui.TextDisabled(
    "Open menu: " + keyLabel(openMenuKey) + " | Toggle Focus: " + keyLabel(toggleFocusKey)
  );
  ImGui.TextDisabled("Hotkeys can be changed in SA_TargetFocus.ini.");
}

function applyPreset(index) {
  const profile = presetProfiles[index];
  if (!profile) return;

  modeIndex = profile.modeIndex;
  aimAssistPercent = profile.aimAssistPercent;
  stickinessPercent = profile.stickinessPercent;
  fovIndex = profile.fovIndex;
  frictionPercent = profile.frictionPercent;
  cameraSmoothingPercent = profile.cameraSmoothingPercent;
  breakDelayIndex = profile.breakDelayIndex;
  targetPointIndex = profile.targetPointIndex;
  indicatorIndex = profile.indicatorIndex;
  targetHighlightIndex = profile.targetHighlightIndex;
  showStatusIndicator = profile.showStatusIndicator;
  selectedPresetIndex = index;
  markConfigDirty();
  log("SA Target Focus preset applied: " + presetNames[index]);
}

function restoreDefaults() {
  applyPreset(1);
  enabled = true;
  includeHostileNPC = true;
  includeEnemyGangs = true;
  includePolice = true;
  includeCivilians = false;
  allowManualOverride = true;
  maximumDistanceMeters = 60;
  targetHighlightIndex = 1;
  showStatusIndicator = true;
  developerMode = false;
  markConfigDirty();
}

function resetTargetingSettings() {
  modeIndex = MODE_SOFT_LOCK;
  aimAssistPercent = 55;
  stickinessPercent = 65;
  fovIndex = 1;
  targetPointIndex = 0;
  maximumDistanceMeters = 60;
  includeHostileNPC = true;
  includeEnemyGangs = true;
  includePolice = true;
  includeCivilians = false;
  selectedPresetIndex = presetProfiles.length;
  markConfigDirty();
}

function resetVisualSettings() {
  indicatorIndex = 1;
  targetHighlightIndex = 1;
  showStatusIndicator = true;
  selectedPresetIndex = presetProfiles.length;
  markConfigDirty();
}

function resetCameraSettings() {
  frictionPercent = 35;
  cameraSmoothingPercent = 60;
  breakDelayIndex = 2;
  allowManualOverride = true;
  selectedPresetIndex = presetProfiles.length;
  markConfigDirty();
}

function settingsFingerprint() {
  return [
    enabled,
    modeIndex,
    fovIndex,
    aimAssistPercent,
    stickinessPercent,
    frictionPercent,
    cameraSmoothingPercent,
    maximumDistanceMeters,
    targetPointIndex,
    indicatorIndex,
    targetHighlightIndex,
    showStatusIndicator,
    breakDelayIndex,
    includeHostileNPC,
    includeEnemyGangs,
    includePolice,
    includeCivilians,
    allowManualOverride,
  ].join("|");
}

function loadConfig() {
  if (typeof IniFile === "undefined" || typeof IniFile.ReadInt !== "function") {
    log("SA Target Focus: IniFiles plugin unavailable; using session defaults.");
    return;
  }

  try {
    const version = IniFile.ReadInt(CONFIG_PATH, "meta", "config_version");
    if (version !== CONFIG_VERSION) {
      saveConfig();
      return;
    }

    selectedPresetIndex = readConfigInt("meta", "preset", selectedPresetIndex);
    enabled = readConfigBool("targeting", "enabled", enabled);
    modeIndex = readConfigInt("targeting", "mode", modeIndex);
    fovIndex = readConfigInt("targeting", "fov", fovIndex);
    aimAssistPercent = readConfigInt("targeting", "strength", aimAssistPercent);
    stickinessPercent = readConfigInt("targeting", "stickiness", stickinessPercent);
    targetPointIndex = readConfigInt("targeting", "target_point", targetPointIndex);
    indicatorIndex = readConfigInt("visual", "indicator", indicatorIndex);
    targetHighlightIndex = readConfigInt("visual", "highlight", targetHighlightIndex);
    showStatusIndicator = readConfigBool("visual", "status_indicator", showStatusIndicator);
    frictionPercent = readConfigInt("camera", "friction", frictionPercent);
    cameraSmoothingPercent = readConfigInt(
      "camera",
      "smoothing",
      cameraSmoothingPercent
    );
    maximumDistanceMeters = readConfigInt("targeting", "max_distance_m", maximumDistanceMeters);
    breakDelayIndex = readConfigInt("targeting", "lost_target_delay", breakDelayIndex);
    allowManualOverride = readConfigBool("camera", "manual_override", allowManualOverride);
    includeHostileNPC = readConfigBool("targets", "hostile_npc", includeHostileNPC);
    includeEnemyGangs = readConfigBool("targets", "enemy_gangs", includeEnemyGangs);
    includePolice = readConfigBool("targets", "police", includePolice);
    includeCivilians = readConfigBool("targets", "civilians", includeCivilians);
    developerMode = readConfigBool("developer", "enabled", developerMode);
    openMenuKey = readConfigInt("input", "open_menu_key", openMenuKey);
    toggleFocusKey = readConfigInt("input", "toggle_focus_key", toggleFocusKey);
    nextTargetKey = readConfigInt("input", "next_target_key", nextTargetKey);
    previousTargetKey = readConfigInt("input", "previous_target_key", previousTargetKey);
    clampConfigValues();
    log("SA Target Focus config loaded from " + CONFIG_PATH);
  } catch (error) {
    log("SA Target Focus: config load failed; using defaults.");
  }
}

function saveConfigIfDue(now) {
  if (!configDirty || now < configSaveDueAt) return;
  saveConfig();
}

function saveConfig() {
  if (typeof IniFile === "undefined" || typeof IniFile.WriteInt !== "function") return;

  clampConfigValues();
  try {
    writeConfigInt("meta", "config_version", CONFIG_VERSION);
    writeConfigInt("meta", "preset", selectedPresetIndex);
    writeConfigInt("targeting", "enabled", enabled ? 1 : 0);
    writeConfigInt("targeting", "mode", modeIndex);
    writeConfigInt("targeting", "fov", fovIndex);
    writeConfigInt("targeting", "strength", aimAssistPercent);
    writeConfigInt("targeting", "stickiness", stickinessPercent);
    writeConfigInt("targeting", "target_point", targetPointIndex);
    writeConfigInt("targeting", "max_distance_m", maximumDistanceMeters);
    writeConfigInt("targeting", "lost_target_delay", breakDelayIndex);
    writeConfigInt("camera", "friction", frictionPercent);
    writeConfigInt("camera", "smoothing", cameraSmoothingPercent);
    writeConfigInt("camera", "manual_override", allowManualOverride ? 1 : 0);
    writeConfigInt("visual", "indicator", indicatorIndex);
    writeConfigInt("visual", "highlight", targetHighlightIndex);
    writeConfigInt("visual", "status_indicator", showStatusIndicator ? 1 : 0);
    writeConfigInt("targets", "hostile_npc", includeHostileNPC ? 1 : 0);
    writeConfigInt("targets", "enemy_gangs", includeEnemyGangs ? 1 : 0);
    writeConfigInt("targets", "police", includePolice ? 1 : 0);
    writeConfigInt("targets", "civilians", includeCivilians ? 1 : 0);
    writeConfigInt("developer", "enabled", developerMode ? 1 : 0);
    writeConfigInt("input", "open_menu_key", openMenuKey);
    writeConfigInt("input", "toggle_focus_key", toggleFocusKey);
    writeConfigInt("input", "next_target_key", nextTargetKey);
    writeConfigInt("input", "previous_target_key", previousTargetKey);
    configDirty = false;
    configSaveDueAt = 0;
  } catch (error) {
    log("SA Target Focus: config save failed; continuing without persistence.");
  }
}

function readConfigInt(section, key, fallback) {
  try {
    const value = IniFile.ReadInt(CONFIG_PATH, section, key);
    return Number.isFinite(value) ? value : fallback;
  } catch (_) {
    return fallback;
  }
}

function readConfigBool(section, key, fallback) {
  return readConfigInt(section, key, fallback ? 1 : 0) !== 0;
}

function writeConfigInt(section, key, value) {
  IniFile.WriteInt(CONFIG_PATH, section, key, Math.trunc(value));
}

function markConfigDirty() {
  configDirty = true;
  configSaveDueAt = Date.now() + 350;
}

function clampConfigValues() {
  selectedPresetIndex = clamp(Math.trunc(selectedPresetIndex), 0, presetProfiles.length);
  modeIndex = clamp(Math.trunc(modeIndex), 0, modes.length - 1);
  fovIndex = clamp(Math.trunc(fovIndex), 0, fovValues.length - 1);
  aimAssistPercent = clamp(Math.trunc(aimAssistPercent), 0, 100);
  stickinessPercent = clamp(Math.trunc(stickinessPercent), 0, 100);
  frictionPercent = clamp(Math.trunc(frictionPercent), 0, 100);
  cameraSmoothingPercent = clamp(Math.trunc(cameraSmoothingPercent), 0, 100);
  maximumDistanceMeters = clamp(Math.trunc(maximumDistanceMeters), 10, 120);
  targetPointIndex = clamp(Math.trunc(targetPointIndex), 0, targetPointNames.length - 1);
  indicatorIndex = clamp(Math.trunc(indicatorIndex), 0, indicatorNames.length - 1);
  targetHighlightIndex = clamp(Math.trunc(targetHighlightIndex), 0, targetHighlightNames.length - 1);
  breakDelayIndex = clamp(Math.trunc(breakDelayIndex), 0, breakDelayValues.length - 1);
}

function normalizeHotkeys() {
  if (openMenuKey <= 0) openMenuKey = VK_DEFAULT_OPEN_MENU;
  if (toggleFocusKey <= 0 || toggleFocusKey === openMenuKey) {
    toggleFocusKey = VK_DEFAULT_TOGGLE_FOCUS;
  }
  if (nextTargetKey <= 0 || nextTargetKey === previousTargetKey) {
    nextTargetKey = VK_DEFAULT_NEXT_TARGET;
  }
  if (previousTargetKey <= 0 || previousTargetKey === nextTargetKey) {
    previousTargetKey = VK_DEFAULT_PREVIOUS_TARGET;
  }
}

function keyLabel(keyCode) {
  const knownKeys = {
    5: "Mouse 4",
    6: "Mouse 5",
    116: "F5",
    117: "F6",
    118: "F7",
    119: "F8",
  };
  return knownKeys[keyCode] || "VK " + keyCode;
}

function getHotkeyConflict() {
  const bindings = [
    { name: "Menu", key: openMenuKey },
    { name: "Toggle Focus", key: toggleFocusKey },
    { name: "Next Target", key: nextTargetKey },
    { name: "Previous Target", key: previousTargetKey },
  ];
  for (let leftIndex = 0; leftIndex < bindings.length; leftIndex += 1) {
    for (let rightIndex = leftIndex + 1; rightIndex < bindings.length; rightIndex += 1) {
      const left = bindings[leftIndex];
      const right = bindings[rightIndex];
      if (left.key > 0 && left.key === right.key) {
        return keyLabel(left.key) + " is assigned to " + left.name + " and " + right.name;
      }
    }
  }
  return "";
}

function updateFocus(actor) {
  const camera = getCameraState();
  const playerPosition = getCoordinates(actor);
  if (!camera || !playerPosition) {
    clearFocus();
    visibleCandidates = [];
    candidateHandles = [];
    return;
  }

  const scanStartedAt = Date.now();
  const candidates = collectCandidates(actor, camera, playerPosition);
  lastDiagnostics.scannerTimeMs = Math.max(0, Date.now() - scanStartedAt);
  lastDiagnostics.candidateCount = candidates.length;
  visibleCandidates = candidates.filter(
    (candidate) => candidate.withinFov && candidate.onScreen && candidate.lineOfSight
  );

  const aimInput = readAimInput();
  const requestedSwitch = readTargetSwitchDirection(aimInput);
  let didManualSwitch = false;
  if (requestedSwitch !== 0) {
    const switched = chooseNextTarget(visibleCandidates, camera, requestedSwitch);
    if (switched) {
      lockTarget(switched);
      didManualSwitch = true;
    }
  }

  const current = focusTarget
    ? inspectCandidate(focusTarget, actor, camera, playerPosition)
    : null;
  const best = chooseBestCandidate(candidates);

  lastFocusState = current;
  lastDiagnostics.manualOverride = false;

  if (!focusTarget && best) {
    setCandidateTarget(best);
    if (Date.now() - candidateSince >= CANDIDATE_ACQUIRE_DELAY_MS) {
      lockTarget(best);
    }
  } else if (!focusTarget) {
    clearCandidateTarget();
  } else if (focusTarget && current) {
    if (current.isLost) {
      if (lostSightAt === 0) lostSightAt = Date.now();
      if (Date.now() - lostSightAt >= breakDelayValues[breakDelayIndex]) {
        clearFocus();
      }
    } else {
      lostSightAt = 0;
      const currentScore = scoreCandidate(current);
      const bestScore = best ? scoreCandidate(best) : Number.NEGATIVE_INFINITY;
      const retargetThreshold =
        TARGET_SWITCH_HYSTERESIS_MIN +
        (stickinessPercent / 100) *
          (TARGET_SWITCH_HYSTERESIS_MAX - TARGET_SWITCH_HYSTERESIS_MIN);
      if (
        !didManualSwitch &&
        best &&
        !sameTarget(current, best) &&
        bestScore > currentScore + retargetThreshold
      ) {
        lockTarget(best);
      }
    }
  } else if (focusTarget) {
    if (lostSightAt === 0) lostSightAt = Date.now();
    if (Date.now() - lostSightAt >= breakDelayValues[breakDelayIndex]) {
      clearFocus();
    }
  }

  if (!focusTarget) return;

  const active = inspectCandidate(focusTarget, actor, camera, playerPosition);
  if (!active) {
    lastDiagnostics.active = false;
    lastDiagnostics.visible = false;
    lastDiagnostics.correction = 0;
    return;
  }
  lastFocusState = active;
  applySoftLock(active, camera, aimInput);
  lastDiagnostics.target = focusTarget;
  lastDiagnostics.active = true;
  lastDiagnostics.score = scoreCandidate(active);
  lastDiagnostics.distance = active.distance;
  lastDiagnostics.angle = active.angle;
  lastDiagnostics.visible = active.onScreen && active.lineOfSight;
}

function collectCandidates(actor, camera, playerPosition) {
  const now = Date.now();
  if (candidateHandles.length > 0 && now - lastCandidateScanAt < TARGET_SCAN_INTERVAL_MS) {
    const cached = candidateHandles
      .map((candidate) => inspectCandidate(candidate, actor, camera, playerPosition))
      .filter(Boolean);
    if (focusTarget && !cached.some((candidate) => sameTarget(candidate, { char: focusTarget }))) {
      addCandidate(cached, inspectCandidate(focusTarget, actor, camera, playerPosition));
    }
    return cached;
  }

  const results = [];
  const forward = camera.forward;
  const right = { x: forward.y, y: -forward.x, z: 0 };

  // GET_RANDOM_CHAR_IN_SPHERE_NO_BRAIN returns the nearest ped for the given
  // sample point. Several samples across the camera cone make target search
  // deterministic enough without reading private game pools or memory.
  const sampleCenters = [
    addVector(camera.position, scaleVector(forward, 8)),
    addVector(camera.position, scaleVector(forward, 18)),
    addVector(camera.position, scaleVector(forward, 30)),
    addVector(camera.position, scaleVector(forward, 45)),
    addVector(playerPosition, scaleVector(forward, 12)),
    addVector(addVector(playerPosition, scaleVector(forward, 18)), scaleVector(right, 10)),
    addVector(addVector(playerPosition, scaleVector(forward, 18)), scaleVector(right, -10)),
    addVector(playerPosition, scaleVector(forward, 35)),
    addVector(playerPosition, scaleVector(right, 12)),
    addVector(playerPosition, scaleVector(right, -12)),
  ];

  if (focusTarget) {
    addCandidate(results, inspectCandidate(focusTarget, actor, camera, playerPosition));
  }

  for (const center of sampleCenters) {
    const nearest = safeNative(
      "GET_RANDOM_CHAR_IN_SPHERE_NO_BRAIN",
      center.x,
      center.y,
      center.z,
      TARGET_SCAN_RADIUS
    );
    addCandidate(results, inspectNativeCandidate(nearest, actor, camera, playerPosition));
  }

  candidateHandles = results.map((candidate) => candidate.char);
  lastCandidateScanAt = now;
  return results;
}

function inspectNativeCandidate(value, actor, camera, playerPosition) {
  if (!value || value === -1) return null;
  const candidate = typeof value === "object" ? value : new Char(value);
  return inspectCandidate(candidate, actor, camera, playerPosition);
}

function inspectCandidate(candidate, actor, camera, playerPosition) {
  if (!candidate || safeNative("IS_CHAR_DEAD", candidate)) return null;

  const position = getCoordinates(candidate);
  if (!position) return null;

  const distance = distanceBetween(position, playerPosition);
  if (distance > maximumDistanceMeters) return null;

  const pedType = safeNative("GET_PED_TYPE", candidate);
  const currentlyTargeted = !!safeNative("IS_PLAYER_TARGETTING_CHAR", player, candidate);
  const hostile = classifyTarget(candidate, pedType, actor, currentlyTargeted);
  if (!hostile.allowed) return null;

  const aimPoint = getTargetPoint(position);
  const toTarget = subtractVector(aimPoint, camera.position);
  const targetDistance = vectorLength(toTarget);
  if (targetDistance <= 0.01) return null;

  const direction = normalizeVector(toTarget);
  const angle = angleBetween(camera.forward, direction);
  const withinFov = angle <= fovValues[fovIndex];
  const onScreen = !!safeNative("IS_CHAR_ON_SCREEN", candidate);
  const lineOfSight = !!safeNative(
    "IS_LINE_OF_SIGHT_CLEAR",
    camera.position.x,
    camera.position.y,
    camera.position.z,
    aimPoint.x,
    aimPoint.y,
    aimPoint.z,
    true,
    true,
    false,
    true,
    true
  );

  return {
    char: candidate,
    position,
    aimPoint,
    distance,
    angle,
    withinFov,
    onScreen,
    lineOfSight,
    pedType,
    threat: hostile.threat,
    currentlyTargeted,
    isLost:
      !onScreen ||
      !lineOfSight ||
      angle > fovValues[fovIndex] + TARGET_LOST_GRACE_ANGLE,
  };
}

function classifyTarget(candidate, pedType, actor, currentlyTargeted) {
  if (pedType === null || pedType === undefined) return { allowed: false, threat: false };

  const isCivilian = pedType === 4 || pedType === 5 || (pedType >= 17 && pedType <= 19);
  const isGang = pedType >= 7 && pedType <= 16;
  const isCriminal = pedType === 20;
  const isPolice = pedType === 6;
  const isMissionPed = pedType >= 24 && pedType <= 31;

  if (isGang) {
    return { allowed: includeEnemyGangs, threat: true };
  }
  if (isCriminal) {
    return { allowed: includeHostileNPC, threat: true };
  }
  if (isPolice) {
    const wantedLevel = safeNative("STORE_WANTED_LEVEL", player) || 0;
    const seesPlayer = !!safeNative("HAS_CHAR_SPOTTED_CHAR", candidate, actor);
    return {
      allowed: includePolice && (currentlyTargeted || (wantedLevel > 0 && seesPlayer)),
      threat: wantedLevel > 0 && seesPlayer,
    };
  }
  if (isMissionPed) {
    // The DE script API does not expose a general mission relationship query.
    // A mission ped is accepted only after it is already targeted or has been
    // damaged by the player, which avoids pulling mission allies into focus.
    const damagedByPlayer = !!safeNative("HAS_CHAR_BEEN_DAMAGED_BY_CHAR", candidate, actor);
    return {
      allowed: includeHostileNPC && (currentlyTargeted || damagedByPlayer),
      threat: true,
    };
  }
  if (isCivilian) {
    return { allowed: includeCivilians, threat: false };
  }

  return { allowed: includeHostileNPC, threat: false };
}

function chooseBestCandidate(candidates) {
  const eligible = candidates.filter((candidate) =>
    candidate.withinFov && candidate.onScreen && candidate.lineOfSight
  );
  if (eligible.length === 0) return null;

  eligible.sort((left, right) => scoreCandidate(right) - scoreCandidate(left));
  return eligible[0];
}

function scoreCandidate(candidate) {
  const alignment = clamp(1 - candidate.angle / Math.max(1, fovValues[fovIndex]), 0, 1);
  const visibility = candidate.onScreen && candidate.lineOfSight ? 1 : 0;
  const distance = clamp(1 - candidate.distance / Math.max(1, maximumDistanceMeters), 0, 1);
  const threat = candidate.threat ? 1 : 0;
  return alignment * 0.45 + visibility * 0.25 + distance * 0.15 + threat * 0.15;
}

function lockTarget(candidate) {
  if (!candidate || !candidate.char) return;
  const switchingTarget =
    focusTarget && !sameTarget(candidate, { char: focusTarget });
  if (switchingTarget) {
    queueMarkerFade(
      lastTargetSnapshot || createTargetSnapshot(lastFocusState, HUD_LOCKED),
      TARGET_SWITCH_FADE_OUT_MS
    );
    safeNative("SET_CHAR_IS_TARGET_PRIORITY", focusTarget, false);
  }
  focusTarget = candidate.char;
  candidateTarget = null;
  candidateSince = 0;
  candidateSnapshot = null;
  lastTargetSnapshot = createTargetSnapshot(candidate, HUD_LOCKED);
  lockAcquiredAt = Date.now();
  cameraAnchorTarget = null;
  lostSightAt = 0;
  safeNative("SET_CHAR_IS_TARGET_PRIORITY", focusTarget, true);
}

function clearFocus() {
  const hadCandidate = !!candidateTarget;
  if (hadCandidate) {
    queueMarkerFade(candidateSnapshot);
  }
  candidateTarget = null;
  candidateSince = 0;
  candidateSnapshot = null;

  if (!focusTarget) {
    releaseCameraAssist();
    return;
  }

  queueMarkerFade(lastTargetSnapshot || createTargetSnapshot(lastFocusState, HUD_LOCKED));
  if (focusTarget) {
    safeNative("SET_CHAR_IS_TARGET_PRIORITY", focusTarget, false);
  }
  focusTarget = null;
  lastTargetSnapshot = null;
  lastFocusState = null;
  lastDiagnostics.active = false;
  lostSightAt = 0;
  releaseCameraAssist();
}

function setCandidateTarget(candidate) {
  if (!candidate || !candidate.char) return;
  if (candidateTarget && sameTarget(candidate, { char: candidateTarget })) return;

  if (candidateTarget) queueMarkerFade(candidateSnapshot, TARGET_SWITCH_FADE_OUT_MS);
  candidateTarget = candidate.char;
  candidateSince = Date.now();
  candidateSnapshot = createTargetSnapshot(candidate, HUD_CANDIDATE);
}

function clearCandidateTarget() {
  if (!candidateTarget) return;
  queueMarkerFade(candidateSnapshot);
  candidateTarget = null;
  candidateSince = 0;
  candidateSnapshot = null;
}

function queueMarkerFade(snapshot, duration = MARKER_FADE_OUT_MS) {
  if (!snapshot) return;
  const now = Date.now();
  markerFades = markerFades.filter(
    (fade) => now - fade.startedAt < fade.duration
  );
  markerFades.push({
    snapshot,
    startedAt: now,
    duration,
  });
  if (markerFades.length > 8) markerFades.shift();
}

function releaseCameraAssist() {
  cameraAnchorTarget = null;
  if (!focusWasApplied) return;
  safeNative("CAMERA_RESET_NEW_SCRIPTABLES");
  safeNative("RESTORE_CAMERA");
  focusWasApplied = false;
}

function applySoftLock(candidate, camera, aimInput) {
  // Keep the lock alive during the configured grace period, but never keep
  // steering the camera through an obstruction or towards an off-screen ped.
  if (candidate.isLost) {
    lastDiagnostics.visible = false;
    lastDiagnostics.correction = 0;
    releaseCameraAssist();
    return;
  }

  if (
    allowManualOverride &&
    aimInput &&
    aimInput.magnitude >= MANUAL_OVERRIDE_THRESHOLD
  ) {
    lastDiagnostics.manualOverride = true;
    lastDiagnostics.correction = 0;
    releaseCameraAssist();
    return;
  }
  lastDiagnostics.manualOverride = false;

  const strength = aimAssistPercent / 100;
  const proximity = clamp(1 - candidate.angle / Math.max(1, fovValues[fovIndex]), 0, 1);
  const frictionMagnet = proximity * (frictionPercent / 100) * 0.06;
  let correction;

  if (modeIndex === MODE_CLASSIC_LOCK_ON) {
    correction = 0.18 + strength * 0.28 + frictionMagnet;
  } else if (modeIndex === MODE_FREE_AIM) {
    correction = candidate.angle <= 8 ? 0.012 + strength * 0.05 + frictionMagnet : 0;
  } else {
    correction = 0.04 + strength * 0.16 + frictionMagnet;
  }

  // Smoothing controls how much of the requested correction is applied in a
  // frame. Higher values make the assist gentler without changing the target.
  correction *= 0.30 + (1 - cameraSmoothingPercent / 100) * 0.70;
  correction = clamp(correction, 0, 0.48);
  if (correction <= 0) {
    lastDiagnostics.correction = 0;
    return;
  }

  // The regular aiming camera can overwrite POINT_CAMERA_AT_POINT unless it
  // has first been switched to an aiming/scriptable camera. Anchor the camera
  // to the selected ped once per lock, then apply the configured soft blend.
  // CameraMode.AimWeapon is 53 in the SA DE definitions.
  if (cameraAnchorTarget !== focusTarget) {
    safeNative("POINT_CAMERA_AT_CHAR", focusTarget, 53, 0);
    cameraAnchorTarget = focusTarget;
  }

  const currentPoint = getActiveCameraPoint();
  if (!currentPoint) return;

  const blended = lerpVector(currentPoint, candidate.aimPoint, correction);
  safeNative("POINT_CAMERA_AT_POINT", blended.x, blended.y, blended.z, 0);
  safeNative(
    "CAMERA_SET_VECTOR_TRACK",
    camera.position.x,
    camera.position.y,
    camera.position.z,
    blended.x,
    blended.y,
    blended.z,
    16,
    false
  );
  focusWasApplied = true;
  lastDiagnostics.correction = correction;
}

function chooseNextTarget(candidates, camera, direction) {
  if (Date.now() < switchAvailableAt) return null;
  switchAvailableAt = Date.now() + TARGET_SWITCH_COOLDOWN_MS;

  const available = candidates
    .filter((candidate) => candidate.withinFov && candidate.onScreen && candidate.lineOfSight)
    .map((candidate) => ({
      candidate,
      horizontalAngle: signedHorizontalAngle(candidate.aimPoint, camera),
    }))
    .sort((left, right) => left.horizontalAngle - right.horizontalAngle);

  if (available.length === 0) return null;
  if (!focusTarget) return available[direction > 0 ? 0 : available.length - 1].candidate;

  const currentIndex = available.findIndex((item) => sameTarget(item.candidate, { char: focusTarget }));
  if (currentIndex < 0) return available[direction > 0 ? 0 : available.length - 1].candidate;

  if (direction > 0) {
    return available[(currentIndex + 1) % available.length].candidate;
  }
  return available[(currentIndex - 1 + available.length) % available.length].candidate;
}

function readTargetSwitchDirection(aimInput) {
  if (isKeyPressed(nextTargetKey)) return 1;
  if (isKeyPressed(previousTargetKey)) return -1;

  const mouseX = aimInput?.mouseX || 0;
  const stickX = aimInput?.stickX || 0;
  const horizontal = Math.abs(mouseX) >= 12 ? mouseX : stickX;
  if (Math.abs(horizontal) < 28) return 0;
  return horizontal > 0 ? 1 : -1;
}

function readAimInput() {
  const mouse = safeNative("GET_PC_MOUSE_MOVEMENT") || {};
  const sticks = safeNative("GET_POSITION_OF_ANALOGUE_STICKS", PAD_ID) || {};
  const mouseX = finiteNumber(mouse.deltaX);
  const mouseY = finiteNumber(mouse.deltaY);
  const stickX = finiteNumber(sticks.rightStickX);
  const stickY = finiteNumber(sticks.rightStickY);
  return {
    mouseX,
    mouseY,
    stickX,
    stickY,
    magnitude: Math.max(
      Math.sqrt(mouseX * mouseX + mouseY * mouseY),
      Math.sqrt(stickX * stickX + stickY * stickY)
    ),
  };
}

function drawIndicators() {
  const now = Date.now();
  drawMarkerFades(now);
  if (indicatorIndex === 0 || !isAimHeld()) return;

  const active = focusTarget
    ? visibleCandidates.find((candidate) => sameTarget(candidate, { char: focusTarget }))
    : null;
  const pending = candidateTarget
    ? visibleCandidates.find((candidate) => sameTarget(candidate, { char: candidateTarget }))
    : null;
  const display = getHudDisplaySize();
  const state = focusTarget ? HUD_LOCKED : candidateTarget ? HUD_CANDIDATE : HUD_NONE;
  const drawList = getHudDrawList();
  if (!display || !drawList) {
    drawWorldSpaceIndicator(active || pending, active ? HUD_LOCKED : HUD_CANDIDATE);
    return;
  }

  drawReticle(drawList, display, state, now);

  if (active && active.onScreen && active.lineOfSight) {
    const snapshot = createTargetSnapshot(active, HUD_LOCKED);
    if (snapshot) {
      lastTargetSnapshot = snapshot;
      drawTargetMarker(drawList, snapshot, markerFadeInAlpha(now), HUD_LOCKED);
    } else {
      drawWorldSpaceIndicator(active, HUD_LOCKED);
    }
  } else if (pending && pending.onScreen && pending.lineOfSight) {
    const snapshot = createTargetSnapshot(pending, HUD_CANDIDATE);
    if (snapshot) {
      candidateSnapshot = snapshot;
      drawTargetMarker(drawList, snapshot, 0.72, HUD_CANDIDATE);
    } else {
      drawWorldSpaceIndicator(pending, HUD_CANDIDATE);
    }
  }

  if (
    focusTarget &&
    lastFocusState &&
    !lastFocusState.onScreen &&
    lastFocusState.lineOfSight &&
    lostSightAt > 0 &&
    now - lostSightAt <= LOST_TARGET_ARROW_MS
  ) {
    drawLostTargetArrow(drawList, display, lastFocusState, now);
  }
}

function drawWorldSpaceIndicator(candidate, state) {
  if (!candidate || !candidate.aimPoint || targetHighlightIndex === 0) return;

  if (state === HUD_CANDIDATE) {
    drawCorona(candidate.aimPoint, 0.14, 255, 255, 255);
    return;
  }

  if (targetHighlightIndex === 1) {
    drawCorona(candidate.aimPoint, 0.22, 235, 64, 64);
  } else if (targetHighlightIndex === 2) {
    drawCorona(candidate.aimPoint, 0.32, 235, 64, 64);
    drawCorona(candidate.aimPoint, 0.14, 255, 180, 80);
  } else {
    drawCorona(candidate.aimPoint, 0.38, 255, 80, 80);
    drawCorona(candidate.aimPoint, 0.16, 255, 230, 160);
  }
}

function getHudDrawList() {
  try {
    return ImGui.GetForegroundDrawList();
  } catch (_) {
    return null;
  }
}

function getHudDisplaySize() {
  try {
    const display = ImGui.GetDisplaySize();
    if (
      display &&
      Number.isFinite(display.width) &&
      Number.isFinite(display.height) &&
      display.width > 0 &&
      display.height > 0
    ) {
      return display;
    }
  } catch (_) {
    // The HUD is optional. A missing ImGui display size must not stop aiming.
  }
  return null;
}

function drawMarkerFades(now) {
  const remaining = [];
  if (indicatorIndex !== 0) {
    const drawList = getHudDrawList();
    if (drawList) {
      for (const fade of markerFades) {
        const progress = clamp((now - fade.startedAt) / fade.duration, 0, 1);
        if (progress < 1) {
          drawTargetMarker(drawList, fade.snapshot, 1 - progress, fade.snapshot.state);
          remaining.push(fade);
        }
      }
    }
  }
  markerFades = remaining;
}

function markerFadeInAlpha(now) {
  if (!lockAcquiredAt) return 1;
  return clamp((now - lockAcquiredAt) / MARKER_FADE_IN_MS, 0, 1);
}

function drawReticle(drawList, display, state, now) {
  const centerX = display.width / 2;
  const centerY = display.height / 2;
  const color = state === HUD_LOCKED ? { r: 235, g: 64, b: 64 } : { r: 255, g: 255, b: 255 };
  const alpha = state === HUD_NONE ? 145 : state === HUD_CANDIDATE ? 185 : 220;

  drawHudLine(drawList, centerX - 5, centerY, centerX + 5, centerY, color, alpha, 1.25);
  drawHudLine(drawList, centerX, centerY - 5, centerX, centerY + 5, color, alpha, 1.25);

  if (state === HUD_CANDIDATE) {
    drawParenthesisReticle(drawList, centerX, centerY, color, alpha);
  } else if (state === HUD_LOCKED) {
    drawBracketReticle(drawList, centerX, centerY, color, alpha);
  }

  if (indicatorIndex === 3) {
    const confidence = state === HUD_LOCKED
      ? 1
      : state === HUD_CANDIDATE
        ? clamp((now - candidateSince) / CANDIDATE_ACQUIRE_DELAY_MS, 0.18, 1)
        : 0;
    drawConfidenceRing(drawList, centerX, centerY, 23, confidence, color, alpha - 25);
  }

  if (state === HUD_LOCKED && now - lockAcquiredAt < LOCK_ACQUIRED_DURATION_MS) {
    const progress = clamp((now - lockAcquiredAt) / LOCK_ACQUIRED_DURATION_MS, 0, 1);
    drawLockAcquiredAnimation(drawList, centerX, centerY, progress);
  }

  if (showStatusIndicator) {
    const status = state === HUD_LOCKED ? "◉" : state === HUD_CANDIDATE ? "◎" : "○";
    const statusColor = state === HUD_LOCKED
      ? { r: 235, g: 64, b: 64 }
      : { r: 255, g: 255, b: 255 };
    drawHudText(drawList, centerX + 26, centerY - 7, statusColor, state === HUD_NONE ? 115 : 190, status);
  }
}

function drawParenthesisReticle(drawList, centerX, centerY, color, alpha) {
  drawHudLine(drawList, centerX - 14, centerY - 6, centerX - 17, centerY, color, alpha, 1.2);
  drawHudLine(drawList, centerX - 17, centerY, centerX - 14, centerY + 6, color, alpha, 1.2);
  drawHudLine(drawList, centerX + 14, centerY - 6, centerX + 17, centerY, color, alpha, 1.2);
  drawHudLine(drawList, centerX + 17, centerY, centerX + 14, centerY + 6, color, alpha, 1.2);
}

function drawBracketReticle(drawList, centerX, centerY, color, alpha) {
  const left = centerX - 16;
  const right = centerX + 16;
  const top = centerY - 8;
  const bottom = centerY + 8;
  drawHudLine(drawList, left, top, left + 5, top, color, alpha, 1.4);
  drawHudLine(drawList, left, top, left, bottom, color, alpha, 1.4);
  drawHudLine(drawList, left, bottom, left + 5, bottom, color, alpha, 1.4);
  drawHudLine(drawList, right - 5, top, right, top, color, alpha, 1.4);
  drawHudLine(drawList, right, top, right, bottom, color, alpha, 1.4);
  drawHudLine(drawList, right - 5, bottom, right, bottom, color, alpha, 1.4);
}

function drawLockAcquiredAnimation(drawList, centerX, centerY, progress) {
  const distance = 30 - progress * 14;
  const inner = 13 - progress * 3;
  const color = { r: 255, g: 180, b: 80 };
  for (const sx of [-1, 1]) {
    for (const sy of [-1, 1]) {
      const startX = centerX + sx * distance;
      const startY = centerY + sy * distance * 0.7;
      const endX = centerX + sx * inner;
      const endY = centerY + sy * inner * 0.7;
      drawHudLine(drawList, startX, startY, endX, endY, color, 210, 1.25);
    }
  }
}

function drawConfidenceRing(drawList, centerX, centerY, radius, progress, color, alpha) {
  if (progress <= 0) return;
  const segments = 24;
  const visibleSegments = Math.ceil(segments * progress);
  for (let index = 0; index < visibleSegments; index += 1) {
    const start = -Math.PI / 2 + (index / segments) * Math.PI * 2;
    const end = -Math.PI / 2 + (Math.min(index + 1, segments * progress) / segments) * Math.PI * 2;
    drawHudLine(
      drawList,
      centerX + Math.cos(start) * radius,
      centerY + Math.sin(start) * radius,
      centerX + Math.cos(end) * radius,
      centerY + Math.sin(end) * radius,
      color,
      alpha,
      1.15
    );
  }
}

function drawTargetMarker(drawList, snapshot, opacity, state) {
  if (!snapshot || opacity <= 0) return;
  const bounds = snapshot.bounds;
  const center = snapshot.center;
  if (!bounds && !center) return;

  const color = state === HUD_LOCKED ? { r: 235, g: 64, b: 64 } : { r: 255, g: 255, b: 255 };
  const alpha = Math.round(clamp(opacity, 0, 1) * (state === HUD_LOCKED ? 210 : 105));
  const markerBounds = bounds || {
    left: center.x - 14,
    top: center.y - 22,
    right: center.x + 14,
    bottom: center.y + 22,
  };

  if (snapshot.visualStyle === 2 || snapshot.highlightIndex === 3) {
    drawClassicTargetMarker(drawList, markerBounds, color, alpha);
    return;
  }
  if (snapshot.highlightIndex === 1 || snapshot.highlightIndex === 2) {
    if (snapshot.highlightIndex === 1) {
      drawTargetCorners(drawList, markerBounds, color, alpha);
    } else {
      drawTargetOutline(drawList, markerBounds, color, alpha);
    }
  }
}

function drawTargetCorners(drawList, bounds, color, alpha) {
  const length = clamp(Math.min(bounds.right - bounds.left, bounds.bottom - bounds.top) * 0.28, 7, 20);
  drawHudLine(drawList, bounds.left, bounds.top, bounds.left + length, bounds.top, color, alpha, 1.25);
  drawHudLine(drawList, bounds.left, bounds.top, bounds.left, bounds.top + length, color, alpha, 1.25);
  drawHudLine(drawList, bounds.right - length, bounds.top, bounds.right, bounds.top, color, alpha, 1.25);
  drawHudLine(drawList, bounds.right, bounds.top, bounds.right, bounds.top + length, color, alpha, 1.25);
  drawHudLine(drawList, bounds.left, bounds.bottom - length, bounds.left, bounds.bottom, color, alpha, 1.25);
  drawHudLine(drawList, bounds.left, bounds.bottom, bounds.left + length, bounds.bottom, color, alpha, 1.25);
  drawHudLine(drawList, bounds.right - length, bounds.bottom, bounds.right, bounds.bottom, color, alpha, 1.25);
  drawHudLine(drawList, bounds.right, bounds.bottom - length, bounds.right, bounds.bottom, color, alpha, 1.25);
}

function drawTargetOutline(drawList, bounds, color, alpha) {
  drawHudLine(drawList, bounds.left, bounds.top, bounds.right, bounds.top, color, alpha, 1.0);
  drawHudLine(drawList, bounds.right, bounds.top, bounds.right, bounds.bottom, color, alpha, 1.0);
  drawHudLine(drawList, bounds.right, bounds.bottom, bounds.left, bounds.bottom, color, alpha, 1.0);
  drawHudLine(drawList, bounds.left, bounds.bottom, bounds.left, bounds.top, color, alpha, 1.0);
}

function drawClassicTargetMarker(drawList, bounds, color, alpha) {
  const centerX = (bounds.left + bounds.right) / 2;
  const top = bounds.top - 10;
  drawHudLine(drawList, centerX - 7, top, centerX, top + 7, color, alpha, 1.35);
  drawHudLine(drawList, centerX, top + 7, centerX + 7, top, color, alpha, 1.35);
}

function drawLostTargetArrow(drawList, display, candidate, now) {
  const edge = getLostTargetEdge(display, candidate);
  if (!edge) return;
  const centerX = display.width / 2;
  const centerY = display.height / 2;
  const direction = normalizeScreenVector(centerX - edge.x, centerY - edge.y);
  const tip = { x: edge.x + direction.x * 8, y: edge.y + direction.y * 8 };
  const perpendicular = { x: -direction.y, y: direction.x };
  const base = { x: edge.x - direction.x * 3, y: edge.y - direction.y * 3 };
  const color = { r: 255, g: 180, b: 80 };
  const alpha = Math.round(220 * (1 - clamp((now - lostSightAt) / LOST_TARGET_ARROW_MS, 0, 1)));
  drawHudLine(
    drawList,
    tip.x,
    tip.y,
    base.x + perpendicular.x * 5,
    base.y + perpendicular.y * 5,
    color,
    alpha,
    1.4
  );
  drawHudLine(
    drawList,
    tip.x,
    tip.y,
    base.x - perpendicular.x * 5,
    base.y - perpendicular.y * 5,
    color,
    alpha,
    1.4
  );
}

function getLostTargetEdge(display, candidate) {
  const projected = worldToScreen(candidate.aimPoint, display);
  const margin = 28;
  if (projected) {
    return {
      x: clamp(projected.x, margin, display.width - margin),
      y: clamp(projected.y, margin, display.height - margin),
    };
  }

  const camera = getCameraState();
  if (!camera || !candidate.position) return null;
  const relative = subtractVector(candidate.position, camera.position);
  const forward = normalizeVector({ x: camera.forward.x, y: camera.forward.y, z: 0 });
  const right = { x: forward.y, y: -forward.x, z: 0 };
  const horizontal = dotProduct(relative, right);
  const depth = dotProduct(relative, forward);
  if (Math.abs(horizontal) >= Math.abs(depth) * (display.width / Math.max(1, display.height))) {
    return { x: horizontal >= 0 ? display.width - margin : margin, y: display.height / 2 };
  }
  return { x: display.width / 2, y: depth >= 0 ? margin : display.height - margin };
}

function createTargetSnapshot(candidate, state) {
  if (!candidate || !candidate.position || !candidate.aimPoint) return null;
  const display = getHudDisplaySize();
  if (!display) return null;
  const center = worldToScreen(candidate.aimPoint, display);
  const bounds = getTargetScreenBounds(candidate.position, center, display);
  if (!center && !bounds) return null;
  return {
    center: center || { x: (bounds.left + bounds.right) / 2, y: (bounds.top + bounds.bottom) / 2 },
    bounds,
    state,
    highlightIndex: targetHighlightIndex,
    visualStyle: indicatorIndex,
  };
}

function getTargetScreenBounds(position, center, display) {
  if (!center) return null;
  const top = worldToScreen({ x: position.x, y: position.y, z: position.z + 1.8 }, display);
  const bottom = worldToScreen({ x: position.x, y: position.y, z: position.z + 0.2 }, display);
  const height = top && bottom ? clamp(Math.abs(bottom.y - top.y), 28, 190) : 48;
  const width = clamp(height * 0.42, 18, 78);
  const topY = top ? Math.min(top.y, bottom ? bottom.y : top.y) : center.y - height / 2;
  const bottomY = bottom ? Math.max(bottom.y, top ? top.y : bottom.y) : center.y + height / 2;
  return {
    left: center.x - width / 2,
    top: topY,
    right: center.x + width / 2,
    bottom: bottomY,
  };
}

function worldToScreen(point, display) {
  if (!screenProjectionAvailable) return null;

  let result;
  try {
    result = native(
      "GET_SCREEN_COORD_FROM_WORLD_COORD",
      point.x,
      point.y,
      point.z
    );
  } catch (_) {
    screenProjectionAvailable = false;
    return null;
  }
  if (!result || typeof result !== "object") {
    screenProjectionAvailable = false;
    return null;
  }

  const nested = result.screen || result.coordinates || result;
  const rawX = finiteNumberOrNull(nested.x ?? nested.screenX ?? nested.screen_x);
  const rawY = finiteNumberOrNull(nested.y ?? nested.screenY ?? nested.screen_y);
  if (rawX === null || rawY === null) {
    screenProjectionAvailable = false;
    return null;
  }

  if (Math.abs(rawX) <= 1.5 && Math.abs(rawY) <= 1.5) {
    return { x: rawX * display.width, y: rawY * display.height };
  }
  return { x: rawX, y: rawY };
}

function drawHudLine(drawList, x1, y1, x2, y2, color, alpha, thickness) {
  try {
    ImGui.AddLine(drawList, x1, y1, x2, y2, color.r, color.g, color.b, alpha, thickness);
  } catch (_) {
    // Keep the gameplay loop alive if an older ImGuiRedux build lacks draw-list support.
  }
}

function drawHudText(drawList, x, y, color, alpha, value) {
  try {
    ImGui.AddText(drawList, x, y, color.r, color.g, color.b, alpha, value);
  } catch (_) {
    // Text is supplementary; the crosshair and target marker remain functional.
  }
}

function normalizeScreenVector(x, y) {
  const length = Math.sqrt(x * x + y * y);
  if (length <= 0.0001) return { x: 0, y: -1 };
  return { x: x / length, y: y / length };
}

function drawCorona(point, size, r, g, b) {
  safeNative("DRAW_CORONA", point.x, point.y, point.z, size, 9, 0, r, g, b);
}

function getCameraState() {
  const position = safeNative("GET_ACTIVE_CAMERA_COORDINATES");
  const pointAt = safeNative("GET_ACTIVE_CAMERA_POINT_AT");
  if (!isVector(position) || !isVector(pointAt)) return null;

  const forward = normalizeVector(subtractVector(pointAt, position));
  if (vectorLength(forward) <= 0.01) return null;
  return { position, pointAt, forward };
}

function getActiveCameraPoint() {
  const point = safeNative("GET_ACTIVE_CAMERA_POINT_AT");
  return isVector(point) ? point : null;
}

function getCoordinates(char) {
  const coordinates = safeNative("GET_CHAR_COORDINATES", char);
  return isVector(coordinates) ? coordinates : null;
}

function getTargetPoint(position) {
  if (targetPointIndex === 1) {
    return { x: position.x, y: position.y, z: position.z + 1.15 };
  }
  if (targetPointIndex === 2) {
    // A stable dynamic point is more natural than a fixed head lock: standing
    // peds receive an upper-torso point while crouched/downed peds stay lower.
    return { x: position.x, y: position.y, z: position.z + 0.95 };
  }
  return { x: position.x, y: position.y, z: position.z + 0.72 };
}

function sameTarget(left, right) {
  if (!left?.char || !right?.char) return false;
  if (left.char === right.char) return true;

  const leftPosition = left.position || getCoordinates(left.char);
  const rightPosition = right.position || getCoordinates(right.char);
  if (!leftPosition || !rightPosition) return false;
  return distanceBetween(leftPosition, rightPosition) < 0.45;
}

function signedHorizontalAngle(point, camera) {
  const toTarget = normalizeVector({
    x: point.x - camera.position.x,
    y: point.y - camera.position.y,
    z: 0,
  });
  const forward = normalizeVector({ x: camera.forward.x, y: camera.forward.y, z: 0 });
  const right = { x: forward.y, y: -forward.x, z: 0 };
  return Math.atan2(dotProduct(toTarget, right), dotProduct(toTarget, forward));
}

function addCandidate(results, candidate) {
  if (!candidate || !candidate.position) return;
  if (results.some((existing) => sameTarget(existing, candidate))) return;
  results.push(candidate);
}

function isAimHeld() {
  return !!safeNative("IS_KEY_PRESSED", RIGHT_MOUSE_BUTTON) ||
    !!safeNative("IS_BUTTON_PRESSED", PAD_ID, AIM_BUTTON);
}

function isKeyPressed(keyCode) {
  return !!safeNative("IS_KEY_PRESSED", keyCode);
}

function safeNative(command, ...args) {
  try {
    return native(command, ...args);
  } catch (_) {
    return null;
  }
}

function finiteNumber(value) {
  return Number.isFinite(value) ? value : 0;
}

function finiteNumberOrNull(value) {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : null;
}

function isVector(value) {
  return value && Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);
}

function addVector(left, right) {
  return { x: left.x + right.x, y: left.y + right.y, z: left.z + right.z };
}

function subtractVector(left, right) {
  return { x: left.x - right.x, y: left.y - right.y, z: left.z - right.z };
}

function scaleVector(vector, scale) {
  return { x: vector.x * scale, y: vector.y * scale, z: vector.z * scale };
}

function lerpVector(from, to, amount) {
  return addVector(from, scaleVector(subtractVector(to, from), amount));
}

function vectorLength(vector) {
  return Math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z);
}

function normalizeVector(vector) {
  const length = vectorLength(vector);
  if (length <= 0.0001) return { x: 0, y: 0, z: 0 };
  return scaleVector(vector, 1 / length);
}

function dotProduct(left, right) {
  return left.x * right.x + left.y * right.y + left.z * right.z;
}

function angleBetween(left, right) {
  const cosine = clamp(dotProduct(normalizeVector(left), normalizeVector(right)), -1, 1);
  return Math.acos(cosine) * 180 / Math.PI;
}

function distanceBetween(left, right) {
  return vectorLength(subtractVector(left, right));
}

function clamp(value, minimum, maximum) {
  return Math.min(maximum, Math.max(minimum, value));
}
