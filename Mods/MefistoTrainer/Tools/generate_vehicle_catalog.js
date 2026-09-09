#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

function usage() {
  console.error(
    "Usage: node generate_vehicle_catalog.js <vehicles.ide> <vehicles.json> [vehicle_metadata.json]"
  );
  process.exit(64);
}

function readJson(filePath, fallback) {
  if (!filePath || !fs.existsSync(filePath)) return fallback;
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function titleCaseModel(model) {
  return model
    .replace(/[_-]+/g, " ")
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

function inferCategory(type, vehicleClass, model) {
  const normalizedType = type.toLowerCase();
  const normalizedModel = model.toLowerCase();

  if (normalizedType === "boat") return "boats";
  if (["plane", "heli"].includes(normalizedType)) return "aircraft";
  if (["bike", "bmx", "quad"].includes(normalizedType)) return "bikes";
  if (normalizedType === "trailer") return "trailers";
  if (normalizedType === "train") return "trains";
  if (normalizedModel.startsWith("rc") || normalizedType === "rc") return "rc";
  if (["police", "cop", "fire", "ambul", "swat", "enforcer", "taxi"].some((token) => normalizedModel.includes(token))) {
    return "service";
  }
  if (["truck", "mtruck", "forklift", "tractor"].includes(normalizedType) || vehicleClass === "worker") {
    return "utility";
  }
  if (["banshee", "bullet", "cheetah", "comet", "elegy", "infernus", "jester", "supergt", "sultan", "turismo", "zr350"].includes(normalizedModel)) {
    return "sports";
  }
  return "cars";
}

function parseVehiclesIde(contents, metadata) {
  const vehicles = [];
  let inCarsSection = false;

  for (const rawLine of contents.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    if (line.toLowerCase() === "cars") {
      inCarsSection = true;
      continue;
    }
    if (inCarsSection && line.toLowerCase() === "end") break;
    if (!inCarsSection) continue;

    const fields = line.split(",").map((field) => field.trim());
    const id = Number.parseInt(fields[0], 10);
    if (!Number.isInteger(id) || fields.length < 8) continue;

    const model = fields[1].toLowerCase();
    const type = fields[3].toLowerCase();
    const vehicleClass = fields[7].toLowerCase();
    const custom = metadata[String(id)] || {};

    vehicles.push({
      id,
      model,
      name: custom.displayName || titleCaseModel(model),
      category: custom.category || inferCategory(type, vehicleClass, model),
      favorite: custom.favorite === true,
      tags: Array.isArray(custom.tags) ? custom.tags : [],
      source: "vehicles.ide",
      ide: {
        txd: fields[2],
        type,
        handling: fields[4],
        gameName: fields[5],
        animations: fields[6],
        class: vehicleClass,
        frequency: Number.parseInt(fields[8], 10) || 0,
        flags: fields[9] || "0",
        componentRules: fields[10] || "0",
        wheelId: fields[11] || null,
        wheelScaleFront: fields[12] || null,
        wheelScaleRear: fields[13] || null,
        unknown: fields[14] || null,
      },
    });
  }

  return vehicles.sort((left, right) => left.id - right.id);
}

if (process.argv.length < 4) usage();

const inputPath = path.resolve(process.argv[2]);
const outputPath = path.resolve(process.argv[3]);
const metadataPath = process.argv[4]
  ? path.resolve(process.argv[4])
  : path.resolve(__dirname, "../Data/vehicle_metadata.json");

if (!fs.existsSync(inputPath)) {
  console.error(`vehicles.ide was not found: ${inputPath}`);
  process.exit(66);
}

const metadata = readJson(metadataPath, {});
const vehicles = parseVehiclesIde(fs.readFileSync(inputPath, "utf8"), metadata);
if (vehicles.length === 0) {
  console.error(`No vehicle records were found in: ${inputPath}`);
  process.exit(65);
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(vehicles, null, 2)}\n`);
console.log(`Generated ${vehicles.length} vehicle records from ${inputPath}`);

