import vehicleData from "./Data/vehicles.json";
import itemData from "./Data/items.json";

export const vehicleCatalog = vehicleData
  .filter((vehicle) => vehicle && Number.isInteger(vehicle.id) && vehicle.model)
  .map((vehicle) => ({
    id: vehicle.id,
    model: vehicle.model,
    name: vehicle.name || vehicle.model,
    category: vehicle.category || "other",
    favorite: vehicle.favorite === true,
    tags: Array.isArray(vehicle.tags) ? vehicle.tags : [],
    source: vehicle.source || "vehicles.ide",
  }));

export const itemCatalog = itemData
  .filter(
    (item) =>
      item &&
      Number.isInteger(item.typeId) &&
      typeof item.name === "string" &&
      item.name.length > 0
  )
  .map((item) => ({
    typeId: item.typeId,
    modelId: Number.isInteger(item.modelId) ? item.modelId : null,
    name: item.name,
    category: item.category || "other",
    favorite: item.favorite === true,
    tags: Array.isArray(item.tags) ? item.tags : [],
  }));

export function namesFor(entries) {
  return entries.map((entry) => entry.name).join(",");
}

export function byCategory(entries, category) {
  if (category === "all") return entries;
  return entries.filter((entry) => entry.category === category);
}

