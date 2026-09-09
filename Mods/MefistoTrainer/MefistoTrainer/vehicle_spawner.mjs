const MODEL_LOAD_TIMEOUT_MS = 5000;
const SPAWN_FORWARD_OFFSET = 8.0;
const SPAWN_VERTICAL_OFFSET = 1.0;
const UNLOCKED_DOORS = 1;

export class VehicleSpawner {
  constructor() {
    this.lastSpawnedVehicle = null;
  }

  spawn(vehicleEntry, actor) {
    if (!vehicleEntry || !actor) {
      return { vehicle: null, message: "No vehicle or player actor was supplied." };
    }

    const modelId = vehicleEntry.id;
    Streaming.RequestModel(modelId);

    const deadline = Date.now() + MODEL_LOAD_TIMEOUT_MS;
    while (!Streaming.HasModelLoaded(modelId) && Date.now() < deadline) {
      wait(0);
    }

    if (!Streaming.HasModelLoaded(modelId)) {
      return {
        vehicle: null,
        message: `Model ${vehicleEntry.model} (${modelId}) did not load in time.`,
      };
    }

    const spawnPosition = actor.getOffsetInWorldCoords(
      0,
      SPAWN_FORWARD_OFFSET,
      SPAWN_VERTICAL_OFFSET
    );
    const vehicle = Car.Create(
      modelId,
      spawnPosition.x,
      spawnPosition.y,
      spawnPosition.z
    );

    if (!vehicle) {
      Streaming.MarkModelAsNoLongerNeeded(modelId);
      return {
        vehicle: null,
        message: `The game did not create ${vehicleEntry.name}.`,
      };
    }

    vehicle.setHeading(actor.getHeading());
    vehicle.lockDoors(UNLOCKED_DOORS);
    vehicle.setEngineOn(true);
    actor.warpIntoCar(vehicle);

    this.lastSpawnedVehicle = vehicle;
    Streaming.MarkModelAsNoLongerNeeded(modelId);

    return {
      vehicle,
      message: `Spawned ${vehicleEntry.name} (${vehicleEntry.model}).`,
    };
  }

  deleteLastSpawned() {
    if (!this.lastSpawnedVehicle) {
      return false;
    }

    this.lastSpawnedVehicle.delete();
    this.lastSpawnedVehicle = null;
    return true;
  }
}
