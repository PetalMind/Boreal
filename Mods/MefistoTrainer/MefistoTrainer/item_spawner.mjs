export class ItemSpawner {
  give(itemEntry, actor, ammo) {
    if (!itemEntry || !actor) return false;

    // typeId is the gameplay/script weapon identifier. modelId is metadata for
    // the visual model and is deliberately not passed to giveWeapon().
    actor.giveWeapon(itemEntry.typeId, ammo);
    actor.setCurrentWeapon(itemEntry.typeId);
    return true;
  }
}

