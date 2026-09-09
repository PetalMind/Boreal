import { itemCatalog } from "./catalog.mjs";

export class ItemCatalog {
  constructor(entries = itemCatalog) {
    this.entries = entries;
  }

  names() {
    return this.entries.map((item) => item.name).join(",");
  }

  get(index) {
    return this.entries[index] || null;
  }
}

