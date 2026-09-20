/// <reference path="./.config/sa.d.ts" />

// Damage Blood & Regeneration DE v2
// GTA San Andreas: The Definitive Edition / CLEO Redux x64 + IniFiles64
//
// Design goals:
// - stable public CLEO/SA:DE scripting surface only;
// - organic procedural blood without external textures;
// - no blood splashes from armour-only damage;
// - bounded drawing cost and hit coalescing to avoid effect spam;
// - regeneration that never exceeds the best observed health ceiling.

if (typeof HOST === "undefined" || HOST !== "sa_unreal") {
  exit("Damage Blood & Regeneration DE supports only GTA San Andreas: The Definitive Edition.");
}

const PLAYER_ID = 0;
const player = new Player(PLAYER_ID);
const CONFIG_PATH = "./DamageBloodRegenDE.ini";
const CONFIG_VERSION = 1;
const VK_RELOAD = 122; // F11

const HUD_VIRTUAL_WIDTH = 640;
const HUD_VIRTUAL_HEIGHT = 448;
const DEFAULT_HEALTH_CEILING = 100;

const DEFAULTS = {
  enabled: true,
  bloodEnabled: true,
  regenerationEnabled: true,
  healthCeiling: DEFAULT_HEALTH_CEILING,
  regenerationDelayMs: 5000,
  regenerationPerSecond: 8,

  bloodFadeDelayMs: 3500,
  bloodFadeMs: 15000,
  pulseDurationMs: 360,
  maxStains: 9,
  drawBudget: 80,
  fullScreenAlpha: 12,
  edgeAlpha: 145,
  minHealthDamage: 0.5,
  stainCooldownMs: 95,
  maxSatelliteDrops: 5,

  debug: false,
};

const config = { ...DEFAULTS };
const nativeFailureCounts = new Map();
const optionalNativeState = new Map();
let lastReloadDown = false;
let lastFrameFailureAt = 0;

const BLOOD_COLORS = {
  almostBlack: { r: 34, g: 0, b: 1 },
  dried: { r: 72, g: 2, b: 3 },
  dark: { r: 108, g: 4, b: 5 },
  fresh: { r: 154, g: 8, b: 10 },
  highlight: { r: 186, g: 18, b: 18 },
};

class DamageBloodModel {
  constructor() {
    this.reset(Date.now());
  }

  reset(now) {
    this.previousHealth = null;
    this.previousArmour = null;
    this.currentHealth = 0;
    this.currentArmour = 0;
    this.maxHealth = config.healthCeiling;
    this.lastDamageAt = now;
    this.lastBloodStainAt = -1000000;
    this.lastUpdateAt = now;
    this.lastRegenerationAt = now;
    this.nextMaxHealthProbeAt = 0;
    this.trauma = 0;
    this.pulse = 0;
    this.regenerationRemainder = 0;
    this.damageCount = 0;
    this.stains = [];
  }

  observe(sample, now) {
    if (!sample || !Number.isFinite(sample.health) || sample.health <= 0) {
      this.reset(now);
      return false;
    }

    const elapsed = this.lastUpdateAt === 0
      ? 0
      : clamp(now - this.lastUpdateAt, 0, 1000);
    this.lastUpdateAt = now;

    // GET_CHAR_MAX_HEALTH does not need to run every frame. Once a second is
    // enough and avoids unnecessary native traffic.
    if (now >= this.nextMaxHealthProbeAt) {
      this.nextMaxHealthProbeAt = now + 1000;
      const observedMax = readOptionalMaxHealth(sample.actor, now);
      if (Number.isFinite(observedMax) && observedMax > 0) {
        this.maxHealth = Math.max(this.maxHealth, observedMax);
      }
    }

    this.maxHealth = Math.max(this.maxHealth, config.healthCeiling, sample.health);

    if (this.previousHealth === null) {
      this.previousHealth = sample.health;
      this.previousArmour = sample.armour;
      this.currentHealth = sample.health;
      this.currentArmour = sample.armour;
      this.lastDamageAt = now;
      return true;
    }

    const healthDrop = Math.max(0, this.previousHealth - sample.health);
    const armourDrop = Number.isFinite(sample.armour) && Number.isFinite(this.previousArmour)
      ? Math.max(0, this.previousArmour - sample.armour)
      : 0;

    if (healthDrop >= config.minHealthDamage || armourDrop >= 0.5) {
      this.registerImpact(healthDrop, armourDrop, now);
    }

    this.currentHealth = sample.health;
    this.currentArmour = sample.armour;
    this.previousHealth = sample.health;
    this.previousArmour = sample.armour;
    this.advance(elapsed, now);
    return true;
  }

  registerImpact(healthDrop, armourDrop, now) {
    // Any real hit postpones regeneration, even if armour absorbed it.
    this.lastDamageAt = now;
    this.regenerationRemainder = 0;

    // Armour-only damage should not create blood. This was one of the main
    // visual bugs in the original implementation.
    if (healthDrop < config.minHealthDamage) return;

    const healthRatio = healthDrop / Math.max(1, this.maxHealth);
    const severity = clamp(0.18 + healthRatio * 4.0, 0.18, 1.0);
    const traumaGain = clamp(0.08 + healthRatio * 1.85, 0.08, 0.62);

    this.trauma = clamp(this.trauma + traumaGain, 0, 1);
    this.pulse = Math.max(this.pulse, clamp(0.42 + healthRatio * 3.2, 0.42, 1));
    this.damageCount += 1;

    const last = this.stains.length > 0 ? this.stains[this.stains.length - 1] : null;
    if (last && now - this.lastBloodStainAt < config.stainCooldownMs) {
      // Automatic fire / rapid damage ticks used to flood the overlay with
      // near-identical rectangles. Merge them into the latest impact instead.
      last.severity = clamp(last.severity + severity * 0.52, 0.18, 1);
      last.alpha = clamp(last.alpha + severity * 0.08, 0.58, 1);
      last.ageMs = Math.min(last.ageMs, 90);
      last.hitCount += 1;
    } else {
      this.stains.push(createStain(this.damageCount, now, severity));
      this.lastBloodStainAt = now;
      while (this.stains.length > config.maxStains) this.stains.shift();
    }
  }

  advance(elapsed, now) {
    if (config.pulseDurationMs > 0) {
      this.pulse = Math.max(0, this.pulse - elapsed / config.pulseDurationMs);
    } else {
      this.pulse = 0;
    }

    if (now - this.lastDamageAt > config.bloodFadeDelayMs && config.bloodFadeMs > 0) {
      this.trauma = Math.max(0, this.trauma - elapsed / config.bloodFadeMs);
    }

    for (const stain of this.stains) stain.ageMs += elapsed;
    const stainLifetime = config.bloodFadeDelayMs + config.bloodFadeMs;
    this.stains = this.stains.filter(stain => stain.ageMs < stainLifetime);

    // Respect max_stains immediately after an INI reload.
    while (this.stains.length > config.maxStains) this.stains.shift();
  }

  get healthDeficit() {
    if (!Number.isFinite(this.currentHealth) || this.maxHealth <= 0) return 0;
    return clamp((this.maxHealth - this.currentHealth) / this.maxHealth, 0, 1);
  }

  get injuryStrength() {
    return clamp(Math.max(this.healthDeficit * 0.82, this.trauma * 0.74), 0, 1);
  }

  canRegenerate(now) {
    return config.enabled && config.regenerationEnabled &&
      this.currentHealth > 0 &&
      this.currentHealth < this.maxHealth - 0.01 &&
      now - this.lastDamageAt >= config.regenerationDelayMs;
  }

  regenerate(actor, now) {
    const elapsed = this.lastRegenerationAt === 0
      ? 0
      : clamp(now - this.lastRegenerationAt, 0, 1000);
    this.lastRegenerationAt = now;

    if (!this.canRegenerate(now)) {
      if (this.currentHealth >= this.maxHealth - 0.01) this.regenerationRemainder = 0;
      return;
    }

    this.regenerationRemainder += config.regenerationPerSecond * elapsed / 1000;
    const amount = Math.floor(this.regenerationRemainder);
    if (amount < 1) return;

    this.regenerationRemainder -= amount;
    const targetHealth = Math.min(this.maxHealth, Math.floor(this.currentHealth + amount));
    if (targetHealth <= this.currentHealth) return;

    if (setHealth(actor, targetHealth)) {
      this.currentHealth = targetHealth;
      this.previousHealth = targetHealth;
      if (targetHealth >= this.maxHealth - 0.01) this.regenerationRemainder = 0;
    }
  }
}

class BloodRenderer {
  render(model, now) {
    if (!config.enabled || !config.bloodEnabled) return;

    const injury = model.injuryStrength;
    if (injury <= 0.001 && model.pulse <= 0.001 && model.stains.length === 0) return;

    let drawCalls = 0;
    const draw = (x, y, width, height, color, alpha) => {
      if (drawCalls >= config.drawBudget) return false;
      const safeAlpha = clamp(Math.round(alpha), 0, 255);
      if (safeAlpha <= 0 || width <= 0 || height <= 0) return false;
      drawCalls += 1;
      drawHudRect(x, y, width, height, color.r, color.g, color.b, safeAlpha);
      return true;
    };

    // The old version used a heavy red frame. This softer two-stage vignette
    // communicates low health without looking like a rectangular UI element.
    if (injury > 0.06) {
      const broad = 0.028 + injury * 0.065;
      const narrow = broad * 0.38;
      const broadAlpha = config.edgeAlpha * injury * 0.12;
      const narrowAlpha = config.edgeAlpha * injury * 0.20;

      draw(0.5, broad / 2, 1, broad, BLOOD_COLORS.almostBlack, broadAlpha);
      draw(0.5, 1 - broad / 2, 1, broad, BLOOD_COLORS.almostBlack, broadAlpha);
      draw(broad / 2, 0.5, broad, 1, BLOOD_COLORS.almostBlack, broadAlpha);
      draw(1 - broad / 2, 0.5, broad, 1, BLOOD_COLORS.almostBlack, broadAlpha);

      draw(0.5, narrow / 2, 1, narrow, BLOOD_COLORS.dried, narrowAlpha);
      draw(0.5, 1 - narrow / 2, 1, narrow, BLOOD_COLORS.dried, narrowAlpha);
      draw(narrow / 2, 0.5, narrow, 1, BLOOD_COLORS.dried, narrowAlpha);
      draw(1 - narrow / 2, 0.5, narrow, 1, BLOOD_COLORS.dried, narrowAlpha);

      if (config.fullScreenAlpha > 0) {
        draw(0.5, 0.5, 1, 1, BLOOD_COLORS.almostBlack,
          config.fullScreenAlpha * injury * 0.52);
      }
    }

    // Short impact response. Kept intentionally subtle so it does not wash the
    // entire image bright red on every damage tick.
    if (model.pulse > 0.001) {
      const pulseWave = 0.74 + Math.sin(now / 48) * 0.26;
      draw(0.5, 0.5, 1, 1, BLOOD_COLORS.fresh,
        model.pulse * pulseWave * 32);
    }

    for (const stain of model.stains) {
      if (drawCalls >= config.drawBudget) break;
      drawStain(stain, model.pulse, draw);
    }
  }
}

class DamageBloodController {
  constructor() {
    this.model = new DamageBloodModel();
    this.renderer = new BloodRenderer();
  }

  update(now) {
    if (!config.enabled) {
      this.model.reset(now);
      return;
    }

    const actor = getPlayerActor();
    if (!actor) {
      this.model.reset(now);
      return;
    }

    const sample = readPlayerVitals(actor, now);
    if (!sample || sample.health <= 0) {
      this.model.reset(now);
      return;
    }

    this.model.observe(sample, now);
    this.model.regenerate(actor, now);
    this.renderer.render(this.model, now);
  }
}

loadConfig();
const controller = new DamageBloodController();
log("Damage Blood & Regeneration DE v2 loaded. F11 reloads the INI.");

while (true) {
  wait(0);
  const now = Date.now();

  if (isKeyPressed(VK_RELOAD)) {
    if (!lastReloadDown) {
      loadConfig();
      log("Damage Blood & Regeneration DE configuration reloaded.");
    }
    lastReloadDown = true;
  } else {
    lastReloadDown = false;
  }

  try {
    controller.update(now);
  } catch (error) {
    if (now - lastFrameFailureAt >= 1000) {
      lastFrameFailureAt = now;
      log("Damage Blood & Regeneration DE: frame recovered from error: " + error);
    }
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

function readPlayerVitals(actor, now) {
  const health = Number(safeNative("GET_CHAR_HEALTH", actor));
  if (!Number.isFinite(health)) return null;

  const armourResult = optionalNative("GET_CHAR_ARMOUR", now, actor);
  const armour = armourResult.ok && Number.isFinite(Number(armourResult.value))
    ? Number(armourResult.value)
    : NaN;
  return { actor, health, armour };
}

function readOptionalMaxHealth(actor, now) {
  const result = optionalNative("GET_CHAR_MAX_HEALTH", now, actor);
  if (!result.ok) return NaN;
  const value = Number(result.value);
  return Number.isFinite(value) && value > 0 ? value : NaN;
}

function setHealth(actor, health) {
  const result = callNative("SET_CHAR_HEALTH", actor, Math.max(1, Math.round(health)));
  return result.ok;
}

function createStain(index, now, severity) {
  const seed = hashSeed(index, now);
  const edge = seeded(seed, 0, 4);
  const archetype = seeded(seed, 1, 3); // 0 splash, 1 smear, 2 drip

  const baseWidth = 0.030 + random01(seed, 2) * 0.040;
  const baseHeight = 0.034 + random01(seed, 3) * 0.055;
  const scale = 0.74 + severity * 0.88;
  const width = baseWidth * scale;
  const height = baseHeight * scale;
  const margin = 0.016 + random01(seed, 4) * 0.048;
  const across = 0.10 + random01(seed, 5) * 0.80;

  let x = 0.5;
  let y = 0.5;
  let inwardX = 0;
  let inwardY = 0;

  if (edge === 0) { // top
    x = across;
    y = margin;
    inwardY = 1;
  } else if (edge === 1) { // right
    x = 1 - margin;
    y = across;
    inwardX = -1;
  } else if (edge === 2) { // bottom
    x = across;
    y = 1 - margin;
    inwardY = -1;
  } else { // left
    x = margin;
    y = across;
    inwardX = 1;
  }

  // Tangent vector for smears running along the edge.
  const tangentX = -inwardY;
  const tangentY = inwardX;

  return {
    x,
    y,
    width,
    height,
    inwardX,
    inwardY,
    tangentX,
    tangentY,
    archetype,
    severity,
    ageMs: 0,
    createdAt: now,
    alpha: 0.68 + random01(seed, 6) * 0.25,
    seed,
    hitCount: 1,
  };
}

function drawStain(stain, pulse, draw) {
  const opacity = stainOpacity(stain);
  if (opacity <= 0.001) return;

  const settle = clamp(stain.ageMs / 130, 0.68, 1);
  const severity = clamp(stain.severity, 0.18, 1);
  const dryProgress = clamp(
    stain.ageMs / Math.max(1, config.bloodFadeDelayMs + config.bloodFadeMs * 0.62),
    0,
    1
  );

  const baseColor = mixColor(BLOOD_COLORS.fresh, BLOOD_COLORS.dried, dryProgress);
  const darkColor = mixColor(BLOOD_COLORS.dark, BLOOD_COLORS.almostBlack, dryProgress * 0.78);
  const highlightColor = mixColor(BLOOD_COLORS.highlight, BLOOD_COLORS.dark, dryProgress);
  const alpha = 220 * opacity * stain.alpha * (0.58 + severity * 0.42) * (0.93 + pulse * 0.07);
  const w = stain.width * settle;
  const h = stain.height * settle;

  if (stain.archetype === 0) {
    drawSplash(stain, w, h, baseColor, darkColor, highlightColor, alpha, draw);
  } else if (stain.archetype === 1) {
    drawSmear(stain, w, h, baseColor, darkColor, alpha, draw);
  } else {
    drawDrip(stain, w, h, baseColor, darkColor, highlightColor, alpha, draw);
  }
}

function drawSplash(stain, w, h, baseColor, darkColor, highlightColor, alpha, draw) {
  drawOrganicBlob(stain.x, stain.y, w, h, baseColor, darkColor, alpha, draw, stain.seed);

  const satellites = 2 + Math.min(
    config.maxSatelliteDrops,
    Math.floor(stain.severity * config.maxSatelliteDrops)
  );

  for (let i = 0; i < satellites; i += 1) {
    const along = 0.45 + random01(stain.seed, 20 + i * 4) * 1.45;
    const side = (random01(stain.seed, 21 + i * 4) - 0.5) * (0.75 + along * 0.32);
    const radius = (0.0022 + random01(stain.seed, 22 + i * 4) * 0.0055) *
      (0.72 + stain.severity * 0.55);

    const x = stain.x + stain.inwardX * h * along + stain.tangentX * w * side;
    const y = stain.y + stain.inwardY * h * along + stain.tangentY * h * side;
    const color = i % 3 === 0 ? highlightColor : baseColor;
    drawTinyDrop(x, y, radius, color, alpha * (0.48 + random01(stain.seed, 23 + i * 4) * 0.30), draw);
  }
}

function drawSmear(stain, w, h, baseColor, darkColor, alpha, draw) {
  const sign = seeded(stain.seed, 40, 2) === 0 ? -1 : 1;
  const tx = stain.tangentX * sign;
  const ty = stain.tangentY * sign;
  const length = w * (1.30 + random01(stain.seed, 41) * 1.10);

  drawOrganicBlob(stain.x, stain.y, w * 0.82, h * 0.92, baseColor, darkColor, alpha, draw, stain.seed);

  draw(
    stain.x + tx * length * 0.34,
    stain.y + ty * length * 0.34,
    Math.abs(tx) > 0 ? length * 0.76 : w * 0.24,
    Math.abs(ty) > 0 ? length * 0.76 : h * 0.23,
    baseColor,
    alpha * 0.62
  );

  draw(
    stain.x + tx * length * 0.68,
    stain.y + ty * length * 0.68,
    Math.abs(tx) > 0 ? length * 0.42 : w * 0.13,
    Math.abs(ty) > 0 ? length * 0.42 : h * 0.12,
    darkColor,
    alpha * 0.38
  );

  const crumbs = 2 + Math.floor(stain.severity * 2);
  for (let i = 0; i < crumbs; i += 1) {
    const t = 0.25 + random01(stain.seed, 45 + i * 3) * 0.90;
    const lateral = (random01(stain.seed, 46 + i * 3) - 0.5) * h * 0.55;
    const x = stain.x + tx * length * t + stain.inwardX * lateral;
    const y = stain.y + ty * length * t + stain.inwardY * lateral;
    const r = 0.002 + random01(stain.seed, 47 + i * 3) * 0.0037;
    drawTinyDrop(x, y, r, baseColor, alpha * 0.44, draw);
  }
}

function drawDrip(stain, w, h, baseColor, darkColor, highlightColor, alpha, draw) {
  drawOrganicBlob(stain.x, stain.y, w * 0.92, h * 0.86, baseColor, darkColor, alpha, draw, stain.seed);

  const length = h * (1.10 + random01(stain.seed, 60) * 1.70) * (0.72 + stain.severity * 0.50);
  const thickness = Math.max(0.0024, w * (0.07 + random01(stain.seed, 61) * 0.08));
  const x = stain.x + stain.inwardX * length * 0.50;
  const y = stain.y + stain.inwardY * length * 0.50;

  draw(
    x,
    y,
    Math.abs(stain.inwardX) > 0 ? length : thickness,
    Math.abs(stain.inwardY) > 0 ? length : thickness,
    darkColor,
    alpha * 0.55
  );

  const tipX = stain.x + stain.inwardX * length;
  const tipY = stain.y + stain.inwardY * length;
  drawTinyDrop(tipX, tipY, thickness * 1.45, baseColor, alpha * 0.72, draw);

  if (stain.severity > 0.48) {
    const side = (seeded(stain.seed, 62, 2) === 0 ? -1 : 1) * w * 0.24;
    const sideX = stain.x + stain.tangentX * side + stain.inwardX * h * 0.65;
    const sideY = stain.y + stain.tangentY * side + stain.inwardY * h * 0.65;
    drawTinyDrop(sideX, sideY, thickness * 0.88, highlightColor, alpha * 0.48, draw);
  }
}

function drawOrganicBlob(x, y, w, h, baseColor, darkColor, alpha, draw, seed) {
  // Five overlapping slices approximate an irregular rounded blot while still
  // using only the extremely reliable DrawRect path.
  draw(x, y, w * 0.76, h * 0.86, baseColor, alpha * 0.90);
  draw(x - w * 0.24, y + h * 0.02, w * 0.34, h * 0.58, baseColor, alpha * 0.72);
  draw(x + w * 0.25, y - h * 0.08, w * 0.31, h * 0.51, darkColor, alpha * 0.68);
  draw(x - w * 0.04, y - h * 0.32, w * 0.53, h * 0.30, baseColor, alpha * 0.63);
  draw(x + w * 0.05, y + h * 0.34, w * (0.39 + random01(seed, 80) * 0.14), h * 0.24,
    darkColor, alpha * 0.54);
}

function drawTinyDrop(x, y, radius, color, alpha, draw) {
  // Two orthogonal rectangles make tiny droplets appear less square without
  // spending three or four draw calls on every satellite.
  draw(x, y, radius * 2.0, radius * 1.12, color, alpha);
  draw(x, y, radius * 1.10, radius * 1.95, color, alpha * 0.86);
}

function stainOpacity(stain) {
  const fadeStart = config.bloodFadeDelayMs;
  if (stain.ageMs <= fadeStart) return 1;
  if (config.bloodFadeMs <= 0) return 0;
  const t = clamp((stain.ageMs - fadeStart) / config.bloodFadeMs, 0, 1);
  // Smoothstep: keeps the stain stable initially and avoids a linear-looking
  // disappearance at the end.
  return 1 - (t * t * (3 - 2 * t));
}

function hashSeed(index, now) {
  const a = (index * 1103515245 + 12345) >>> 0;
  const b = (Math.floor(now / 17) * 2654435761) >>> 0;
  return (a ^ b ^ 0x85ebca6b) >>> 0;
}

function random01(seed, salt) {
  return seeded(seed, salt, 1000000) / 999999;
}

function seeded(seed, salt, maximum) {
  if (!Number.isFinite(maximum) || maximum <= 0) return 0;
  let value = (seed ^ Math.imul((salt + 1) >>> 0, 0x9e3779b9)) >>> 0;
  value = (Math.imul(value, 1664525) + 1013904223) >>> 0;
  value ^= value >>> 16;
  return (value >>> 0) % maximum;
}

function mixColor(a, b, amount) {
  const t = clamp(amount, 0, 1);
  return {
    r: Math.round(a.r + (b.r - a.r) * t),
    g: Math.round(a.g + (b.g - a.g) * t),
    b: Math.round(a.b + (b.b - a.b) * t),
  };
}

function drawHudRect(x, y, width, height, red, green, blue, alpha) {
  const safeWidth = clamp(Number(width), 0.001, 1.2);
  const safeHeight = clamp(Number(height), 0.001, 1.2);
  const safeX = clamp(Number(x), -0.1, 1.1);
  const safeY = clamp(Number(y), -0.1, 1.1);
  const safeAlpha = clamp(Math.round(alpha), 0, 255);
  if (safeAlpha <= 0) return;

  try {
    if (typeof Hud !== "undefined" && Hud && typeof Hud.DrawRect === "function") {
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
    safeX * HUD_VIRTUAL_WIDTH,
    safeY * HUD_VIRTUAL_HEIGHT,
    safeWidth * HUD_VIRTUAL_WIDTH,
    safeHeight * HUD_VIRTUAL_HEIGHT,
    clamp(Math.round(red), 0, 255),
    clamp(Math.round(green), 0, 255),
    clamp(Math.round(blue), 0, 255),
    safeAlpha
  );
}

function loadConfig() {
  if (typeof IniFile === "undefined" || typeof IniFile.ReadInt !== "function") {
    log("Damage Blood & Regeneration DE: IniFiles64 unavailable; using defaults.");
    return;
  }

  try {
    const version = readConfigInt("meta", "config_version", CONFIG_VERSION);
    if (version !== CONFIG_VERSION) {
      log("Damage Blood & Regeneration DE: unsupported INI version; using defaults.");
      return;
    }

    config.enabled = readConfigBool("mod", "enabled", DEFAULTS.enabled);
    config.bloodEnabled = readConfigBool("blood", "enabled", DEFAULTS.bloodEnabled);
    config.regenerationEnabled = readConfigBool(
      "regeneration",
      "enabled",
      DEFAULTS.regenerationEnabled
    );

    config.healthCeiling = clamp(
      readConfigInt("regeneration", "fallback_health_ceiling", DEFAULTS.healthCeiling),
      50,
      1000
    );
    config.regenerationDelayMs = clamp(
      readConfigInt("regeneration", "delay_ms", DEFAULTS.regenerationDelayMs),
      500,
      120000
    );
    config.regenerationPerSecond = clamp(
      readConfigInt("regeneration", "health_per_second_x10", DEFAULTS.regenerationPerSecond * 10) / 10,
      0.5,
      100
    );

    config.bloodFadeDelayMs = clamp(
      readConfigInt("blood", "fade_delay_ms", DEFAULTS.bloodFadeDelayMs),
      0,
      120000
    );
    config.bloodFadeMs = clamp(
      readConfigInt("blood", "fade_ms", DEFAULTS.bloodFadeMs),
      500,
      120000
    );
    config.pulseDurationMs = clamp(
      readConfigInt("blood", "pulse_duration_ms", DEFAULTS.pulseDurationMs),
      100,
      3000
    );
    config.maxStains = clamp(readConfigInt("blood", "max_stains", DEFAULTS.maxStains), 1, 20);
    config.drawBudget = clamp(readConfigInt("blood", "draw_budget", DEFAULTS.drawBudget), 24, 120);
    config.fullScreenAlpha = clamp(
      readConfigInt("blood", "full_screen_alpha", DEFAULTS.fullScreenAlpha),
      0,
      80
    );
    config.edgeAlpha = clamp(readConfigInt("blood", "edge_alpha", DEFAULTS.edgeAlpha), 0, 255);
    config.minHealthDamage = clamp(
      readConfigInt("blood", "min_health_damage_x10", DEFAULTS.minHealthDamage * 10) / 10,
      0.1,
      25
    );
    config.stainCooldownMs = clamp(
      readConfigInt("blood", "stain_cooldown_ms", DEFAULTS.stainCooldownMs),
      0,
      1000
    );
    config.maxSatelliteDrops = clamp(
      readConfigInt("blood", "max_satellite_drops", DEFAULTS.maxSatelliteDrops),
      0,
      8
    );

    config.debug = readConfigBool("debug", "enabled", DEFAULTS.debug);
  } catch (error) {
    log("Damage Blood & Regeneration DE: configuration load failed; keeping previous values: " + error);
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

function optionalNative(name, now, ...args) {
  const state = optionalNativeState.get(name);
  if (state && now < state.retryAt) return { ok: false, value: null };

  try {
    const value = native(name, ...args);
    optionalNativeState.set(name, { failures: 0, retryAt: 0 });
    return { ok: true, value };
  } catch (error) {
    const failures = state ? state.failures + 1 : 1;
    // Do not permanently blacklist a command after one transient failure.
    // Back off progressively instead and retry later.
    const backoffMs = failures >= 3 ? 60000 : 5000;
    optionalNativeState.set(name, { failures, retryAt: now + backoffMs });
    if (config.debug && (failures === 1 || failures === 3)) {
      log("Damage Blood & Regeneration optional native unavailable: " + name + " " + error);
    }
    return { ok: false, value: null };
  }
}

function callNative(name, ...args) {
  try {
    return { ok: true, value: native(name, ...args) };
  } catch (error) {
    const count = (nativeFailureCounts.get(name) || 0) + 1;
    nativeFailureCounts.set(name, count);
    if (config.debug && count === 1) {
      log("Damage Blood & Regeneration native failure: " + name + " " + error);
    }
    return { ok: false, value: null };
  }
}

function safeNative(name, ...args) {
  return callNative(name, ...args).value;
}

function isKeyPressed(keyCode) {
  try {
    if (typeof Pad !== "undefined" && Pad && typeof Pad.IsKeyPressed === "function") {
      return !!Pad.IsKeyPressed(keyCode);
    }
  } catch (_) {}
  return safeNative("IS_KEY_PRESSED", keyCode) === true;
}

function clamp(value, minimum, maximum) {
  const number = Number(value);
  if (!Number.isFinite(number)) return minimum;
  return Math.max(minimum, Math.min(maximum, number));
}
