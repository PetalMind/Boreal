/// <reference path="./.config/sa_unreal.d.ts" />

// SA Target Focus for GTA San Andreas: The Definitive Edition.
// Requires CLEO Redux 1.5+ and ImGuiReduxWin64.
//
// This is deliberately a soft lock. It never fires a weapon, changes the
// player's aim input, or teleports the crosshair to a bone. The camera target
// is blended a little towards a visible hostile ped while the aim button is
// held, so the player remains in control.

if (HOST !== "sa_unreal") {
  exit("SA Target Focus supports only GTA San Andreas: The Definitive Edition.");
}

const PLAYER_ID = 0;
const VK_F6 = 117;
const RIGHT_MOUSE_BUTTON = 2;
const AIM_BUTTON = 5; // Left shoulder 2 / LT in the GTA pad layout.
const PAD_ID = 0;
const MAX_TARGET_DISTANCE = 65.0;
const TARGET_SCAN_RADIUS = 18.0;
const TARGET_SWITCH_COOLDOWN_MS = 350;
const TARGET_LOST_GRACE_ANGLE = 8.0;

const player = new Player(PLAYER_ID);

const modes = ["Classic", "Soft Lock", "Free Aim+"];
const fovNames = ["Narrow (10°)", "Normal (25°)", "Wide (45°)"];
const fovValues = [10, 25, 45];
const targetPointNames = ["Center Mass", "Upper Body", "Dynamic"];
const indicatorNames = ["OFF", "Minimal", "Classic GTA", "Modern"];
const breakDelayNames = ["0.0 sec", "0.3 sec", "0.5 sec", "1.0 sec"];
const breakDelayValues = [0, 300, 500, 1000];

let menuVisible = false;
let f6WasDown = false;
let enabled = true;
let modeIndex = 1;
let fovIndex = 1;
let aimAssistPercent = 65;
let stickinessPercent = 70;
let frictionPercent = 40;
let targetPointIndex = 0;
let indicatorIndex = 1;
let breakDelayIndex = 2;
let includeHostileNPC = true;
let includeEnemyGangs = true;
let includePolice = true;
let includeCivilians = false;

let focusTarget = null;
let focusWasApplied = false;
let lostSightAt = 0;
let switchAvailableAt = 0;
let visibleCandidates = [];

log("SA Target Focus loaded. Hold aim and press F6 for settings.");

while (true) {
  wait(0);

  const f6Down = isKeyPressed(VK_F6);
  if (f6Down && !f6WasDown) {
    menuVisible = !menuVisible;
  }
  f6WasDown = f6Down;

  ImGui.BeginFrame("SA_TARGET_FOCUS_WINDOW");
  ImGui.SetCursorVisible(menuVisible);

  const playing = player.isPlaying();
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
  ImGui.SetNextWindowSize(540, 650, 2);
  ImGui.Begin("SA TARGET FOCUS", true, false, true, false, false);

  ImGui.TextColored("TARGET FOCUS", 70, 170, 255, 255);
  ImGui.SameLine();
  ImGui.TextDisabled("Single-player soft aim assist  |  F6 close");
  ImGui.Separator();
  ImGui.Spacing();

  enabled = ImGui.Checkbox("Enabled", enabled);
  modeIndex = ImGui.ComboBox("Mode", modes.join(","), modeIndex);
  fovIndex = ImGui.ComboBox("Detection FOV", fovNames.join(","), fovIndex);
  aimAssistPercent = ImGui.SliderInt("Aim Assist Strength", aimAssistPercent, 0, 100);
  stickinessPercent = ImGui.SliderInt("Target Stickiness", stickinessPercent, 0, 100);
  frictionPercent = ImGui.SliderInt("Aim Friction", frictionPercent, 0, 100);
  targetPointIndex = ImGui.ComboBox("Target Point", targetPointNames.join(","), targetPointIndex);
  indicatorIndex = ImGui.ComboBox("Target Indicator", indicatorNames.join(","), indicatorIndex);
  breakDelayIndex = ImGui.ComboBox("Break Lock Delay", breakDelayNames.join(","), breakDelayIndex);

  ImGui.Spacing();
  ImGui.Text("TARGETS");
  ImGui.TextDisabled("Only visible peds inside the detection cone are considered.");
  ImGui.Separator();
  ImGui.Spacing();
  includeHostileNPC = ImGui.Checkbox("Hostile NPC and mission threats", includeHostileNPC);
  includeEnemyGangs = ImGui.Checkbox("Enemy gangs", includeEnemyGangs);
  includePolice = ImGui.Checkbox("Police while pursuing the player", includePolice);
  includeCivilians = ImGui.Checkbox("Civilians", includeCivilians);

  ImGui.Spacing();
  ImGui.Separator();
  ImGui.Spacing();
  ImGui.TextDisabled("Aim: Right Mouse / LT");
  ImGui.TextDisabled("Switch target: horizontal mouse movement / right stick");
  ImGui.TextDisabled("The indicator is drawn in world space to stay compatible with SA DE.");
  ImGui.TextDisabled(focusTarget ? "Status: TARGET LOCKED" : "Status: SEARCHING");

  ImGui.End();
}

function updateFocus(actor) {
  const camera = getCameraState();
  const playerPosition = getCoordinates(actor);
  if (!camera || !playerPosition) {
    clearFocus();
    visibleCandidates = [];
    return;
  }

  const candidates = collectCandidates(actor, camera, playerPosition);
  visibleCandidates = candidates.filter((candidate) => candidate.withinFov && candidate.lineOfSight);

  const requestedSwitch = readTargetSwitchDirection();
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

  if (!focusTarget && best) {
    lockTarget(best);
  } else if (focusTarget && current) {
    if (current.isLost) {
      if (lostSightAt === 0) lostSightAt = Date.now();
      if (Date.now() - lostSightAt >= breakDelayValues[breakDelayIndex]) {
        clearFocus();
      }
    } else {
      lostSightAt = 0;
      const currentScore = scoreCandidate(current);
      const bestScore = best ? scoreCandidate(best) : Number.POSITIVE_INFINITY;
      const retargetThreshold = 0.35 + (stickinessPercent / 100) * 1.7;
      if (
        !didManualSwitch &&
        best &&
        !sameTarget(current, best) &&
        bestScore + retargetThreshold < currentScore
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
  if (!active) return;
  applySoftLock(active, camera);
}

function collectCandidates(actor, camera, playerPosition) {
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
    addVector(playerPosition, scaleVector(forward, 12)),
    addVector(addVector(playerPosition, scaleVector(forward, 18)), scaleVector(right, 10)),
    addVector(addVector(playerPosition, scaleVector(forward, 18)), scaleVector(right, -10)),
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

    const random = safeNative(
      "GET_RANDOM_CHAR_IN_SPHERE",
      center.x,
      center.y,
      center.z,
      TARGET_SCAN_RADIUS,
      true,
      true,
      true
    );
    addCandidate(results, inspectNativeCandidate(random, actor, camera, playerPosition));
  }

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
  if (distance > MAX_TARGET_DISTANCE) return null;

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

  eligible.sort((left, right) => scoreCandidate(left) - scoreCandidate(right));
  return eligible[0];
}

function scoreCandidate(candidate) {
  const angleScore = (candidate.angle / Math.max(1, fovValues[fovIndex])) * 5.0;
  const distanceScore = Math.min(1.5, candidate.distance / MAX_TARGET_DISTANCE);
  const hostilityBonus = candidate.threat ? 1.2 : 0;
  const currentBonus = sameTarget(candidate, { char: focusTarget })
    ? (stickinessPercent / 100) * 1.7
    : 0;
  const targetBonus = candidate.currentlyTargeted ? 0.45 : 0;
  return angleScore + distanceScore - hostilityBonus - currentBonus - targetBonus;
}

function lockTarget(candidate) {
  if (!candidate || !candidate.char) return;
  if (focusTarget && !sameTarget(candidate, { char: focusTarget })) {
    safeNative("SET_CHAR_IS_TARGET_PRIORITY", focusTarget, false);
  }
  focusTarget = candidate.char;
  lostSightAt = 0;
  safeNative("SET_CHAR_IS_TARGET_PRIORITY", focusTarget, true);
}

function clearFocus() {
  if (focusTarget) {
    safeNative("SET_CHAR_IS_TARGET_PRIORITY", focusTarget, false);
  }
  focusTarget = null;
  lostSightAt = 0;
  if (focusWasApplied) {
    safeNative("CAMERA_RESET_NEW_SCRIPTABLES");
    safeNative("RESTORE_CAMERA");
    focusWasApplied = false;
  }
}

function applySoftLock(candidate, camera) {
  if (candidate.isLost && !focusWasApplied) return;

  const strength = aimAssistPercent / 100;
  const proximity = clamp(1 - candidate.angle / Math.max(1, fovValues[fovIndex]), 0, 1);
  const frictionMagnet = proximity * (frictionPercent / 100) * 0.06;
  let correction;

  if (modeIndex === 0) {
    correction = 0.18 + strength * 0.28 + frictionMagnet;
  } else if (modeIndex === 2) {
    correction = candidate.angle <= 8 ? 0.012 + strength * 0.05 + frictionMagnet : 0;
  } else {
    correction = 0.04 + strength * 0.16 + frictionMagnet;
  }

  correction = clamp(correction, 0, 0.48);
  if (correction <= 0) return;

  const currentPoint = getActiveCameraPoint();
  if (!currentPoint) return;

  const blended = lerpVector(currentPoint, candidate.aimPoint, correction);
  safeNative("POINT_CAMERA_AT_POINT", blended.x, blended.y, blended.z, 0);
  focusWasApplied = true;
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

function readTargetSwitchDirection() {
  const mouse = safeNative("GET_PC_MOUSE_MOVEMENT");
  const sticks = safeNative("GET_POSITION_OF_ANALOGUE_STICKS", PAD_ID);
  const mouseX = mouse?.deltaX || 0;
  const stickX = sticks?.rightStickX || 0;
  const horizontal = Math.abs(mouseX) >= 12 ? mouseX : stickX;
  if (Math.abs(horizontal) < 28) return 0;
  return horizontal > 0 ? 1 : -1;
}

function drawIndicators() {
  if (indicatorIndex === 0) return;

  for (const candidate of visibleCandidates) {
    if (sameTarget(candidate, { char: focusTarget })) continue;
    if (indicatorIndex === 1) continue;
    drawCorona(candidate.aimPoint, 0.14, 255, 255, 255);
  }

  if (!focusTarget) return;
  const active = visibleCandidates.find((candidate) => sameTarget(candidate, { char: focusTarget }));
  if (!active) return;

  if (indicatorIndex === 1) {
    drawCorona(active.aimPoint, 0.22, 235, 64, 64);
  } else if (indicatorIndex === 2) {
    drawCorona(active.aimPoint, 0.34, 235, 64, 64);
    drawCorona(active.aimPoint, 0.16, 255, 180, 80);
  } else {
    drawCorona(active.aimPoint, 0.26, 255, 80, 80);
    drawCorona(active.aimPoint, 0.10, 255, 230, 160);
  }
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
