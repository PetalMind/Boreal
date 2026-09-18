#include "PoliceTracker.h"

#include "CCopPed.h"
#include "CPools.h"
#include "CVehicle.h"
#include "eCarMission.h"
#include "eCopType.h"
#include "ePedType.h"
#include "eVehicleType.h"

#include <algorithm>
#include <cmath>

namespace {

bool ContainsPed(CPed* candidate) {
    if (!candidate || !CPools::ms_pPedPool) {
        return false;
    }
    auto* pool = CPools::ms_pPedPool;
    for (int index = 0; index < pool->m_nSize; ++index) {
        if (pool->GetAt(index) == candidate) {
            return true;
        }
    }
    return false;
}

bool ContainsVehicle(CVehicle* candidate) {
    if (!candidate || !CPools::ms_pVehiclePool) {
        return false;
    }
    auto* pool = CPools::ms_pVehiclePool;
    for (int index = 0; index < pool->m_nSize; ++index) {
        if (pool->GetAt(index) == candidate) {
            return true;
        }
    }
    return false;
}

bool IsPolicePed(CPed* ped) {
    return ped && ped->m_nPedType == PED_TYPE_COP;
}

PoliceUnitType TypeForCop(const CCopPed* cop) {
    if (!cop) {
        return PoliceUnitType::Foot;
    }
    switch (cop->m_copType) {
    case COP_TYPE_SWAT1:
    case COP_TYPE_SWAT2:
        return PoliceUnitType::SWAT;
    case COP_TYPE_FBI:
        return PoliceUnitType::FBI;
    case COP_TYPE_ARMY:
        return PoliceUnitType::Army;
    default:
        return PoliceUnitType::Foot;
    }
}

bool IsPursuitMission(eCarMission mission) {
    switch (mission) {
    case MISSION_RAMPLAYER_FARAWAY:
    case MISSION_RAMPLAYER_CLOSE:
    case MISSION_BLOCKPLAYER_FARAWAY:
    case MISSION_BLOCKPLAYER_CLOSE:
    case MISSION_BLOCKPLAYER_HANDBRAKESTOP:
    case MISSION_BLOCKPLAYER_FORWARDANDBACK:
    case MISSION_ATTACKPLAYER:
    case MISSION_COP_HELI_ATTACK:
    case MISSION_POLICE_BIKE:
    case MISSION_POLICE_WAIT_FOR_PLAYER:
    case MISSION_HELI_FOLLOW_ENTITY:
    case MISSION_HELI_KEEP_ENTITY_IN_VIEW:
        return true;
    default:
        return false;
    }
}

PoliceUnitType TypeForVehicle(const CVehicle* vehicle, const CPed* driver) {
    if (vehicle) {
        switch (vehicle->m_nVehicleSubClass) {
        case VEHICLE_HELI:
        case VEHICLE_FHELI:
            return PoliceUnitType::Helicopter;
        case VEHICLE_BIKE:
            return PoliceUnitType::Bike;
        case VEHICLE_BOAT:
            return PoliceUnitType::Boat;
        default:
            return PoliceUnitType::Car;
        }
    }
    return TypeForCop(driver && IsPolicePed(const_cast<CPed*>(driver))
        ? reinterpret_cast<const CCopPed*>(driver)
        : nullptr);
}

bool IsRenderableType(PoliceUnitType type, const PolicePursuitRadarSettings& settings) {
    switch (type) {
    case PoliceUnitType::Foot:
    case PoliceUnitType::SWAT:
    case PoliceUnitType::FBI:
    case PoliceUnitType::Army:
        return settings.showFootPolice;
    case PoliceUnitType::Car:
        return settings.showCars;
    case PoliceUnitType::Bike:
        return settings.showBikes;
    case PoliceUnitType::Boat:
        return settings.showBoats;
    case PoliceUnitType::Helicopter:
        return settings.showHelicopters;
    }
    return false;
}

} // namespace

void PoliceTracker::Clear() {
    m_units.clear();
    m_pursuitCopCount = 0;
}

void PoliceTracker::Update(const WantedSnapshot& wanted, const PolicePursuitRadarSettings& settings, uint32_t now) {
    Clear();
    if (!wanted.VanillaPoliceActive() || !wanted.player || !CPools::ms_pPedPool || !CPools::ms_pVehiclePool) {
        return;
    }

    std::vector<CCopPed*> pursuitCops;
    const unsigned int pursuitSlots = std::min<unsigned int>(wanted.copsInPursuit, 10);
    for (unsigned int index = 0; index < pursuitSlots; ++index) {
        CCopPed* cop = wanted.wanted->m_pCopsInPursuit[index];
        if (ContainsPed(reinterpret_cast<CPed*>(cop)) && IsPolicePed(reinterpret_cast<CPed*>(cop))) {
            pursuitCops.push_back(cop);
        }
    }
    m_pursuitCopCount = static_cast<unsigned int>(pursuitCops.size());

    std::vector<CVehicle*> pursuitVehicles;
    auto* vehiclePool = CPools::ms_pVehiclePool;
    for (int index = 0; index < vehiclePool->m_nSize; ++index) {
        CVehicle* vehicle = vehiclePool->GetAt(index);
        if (!vehicle || vehicle->m_nAreaCode != wanted.player->m_nAreaCode) {
            continue;
        }

        CPed* driver = vehicle->m_pDriver;
        const bool driverIsCop = ContainsPed(driver) && IsPolicePed(driver);
        const bool hasPursuitCop = std::any_of(pursuitCops.begin(), pursuitCops.end(), [vehicle](const CCopPed* cop) {
            return reinterpret_cast<const CPed*>(cop)->m_pVehicle == vehicle;
        });
        const bool policeMission = driverIsCop && IsPursuitMission(vehicle->m_autoPilot.m_nCarMission);
        const bool active = vehicle->bIsLawEnforcer || hasPursuitCop || policeMission;
        if (!active || std::find(pursuitVehicles.begin(), pursuitVehicles.end(), vehicle) != pursuitVehicles.end()) {
            continue;
        }

        const PoliceUnitType type = TypeForVehicle(vehicle, driver);
        if (!IsRenderableType(type, settings)) {
            continue;
        }
        pursuitVehicles.push_back(vehicle);
        const int poolRef = CPools::GetVehicleRef(vehicle) | 0x40000000;
        TrackedPoliceUnit tracked;
        tracked.entity = vehicle;
        tracked.type = type;
        tracked.position = vehicle->GetPosition();
        tracked.distanceToPlayer = tracked.position.Distance(wanted.playerPosition);
        tracked.heading = vehicle->GetHeading();
        tracked.activePursuer = true;
        tracked.isLawEnforcer = vehicle->bIsLawEnforcer || driverIsCop;
        tracked.sirenActive = vehicle->bSirenOrAlarm;
        tracked.inVehicle = true;
        tracked.poolRef = poolRef;
        tracked.lastSeenPlayerTime = m_lastSeenByRef[poolRef];
        if (tracked.distanceToPlayer <= settings.maxTrackingDistance) {
            m_units.push_back(tracked);
        }
    }

    for (CCopPed* cop : pursuitCops) {
        CPed* ped = reinterpret_cast<CPed*>(cop);
        if (!ped || ped->m_nAreaCode != wanted.player->m_nAreaCode) {
            continue;
        }

        if (ped->m_pVehicle && ContainsVehicle(ped->m_pVehicle)) {
            continue;
        }

        const PoliceUnitType type = TypeForCop(cop);
        if (!IsRenderableType(type, settings)) {
            continue;
        }
        TrackedPoliceUnit tracked;
        tracked.entity = ped;
        tracked.type = type;
        tracked.position = ped->GetPosition();
        tracked.distanceToPlayer = tracked.position.Distance(wanted.playerPosition);
        tracked.heading = ped->GetHeading();
        tracked.activePursuer = true;
        tracked.isLawEnforcer = true;
        tracked.inVehicle = false;
        tracked.poolRef = CPools::GetPedRef(ped);
        tracked.lastSeenPlayerTime = m_lastSeenByRef[tracked.poolRef];
        if (tracked.distanceToPlayer <= settings.maxTrackingDistance) {
            m_units.push_back(tracked);
        }
    }

    for (auto iterator = m_lastSeenByRef.begin(); iterator != m_lastSeenByRef.end();) {
        const bool stillTracked = std::any_of(m_units.begin(), m_units.end(), [ref = iterator->first](const TrackedPoliceUnit& unit) {
            return unit.poolRef == ref;
        });
        if (!stillTracked && now - iterator->second > 5000) {
            iterator = m_lastSeenByRef.erase(iterator);
        } else {
            ++iterator;
        }
    }
}

void PoliceTracker::RememberVisibleUnits() {
    for (const auto& unit : m_units) {
        if (unit.canSeePlayer && unit.poolRef >= 0) {
            m_lastSeenByRef[unit.poolRef] = unit.lastSeenPlayerTime;
        }
    }
}
