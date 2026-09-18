#pragma once

#include "Config.h"
#include "WantedStateProvider.h"

#include <cstdint>
#include <unordered_map>
#include <vector>

class CEntity;

enum class PoliceUnitType {
    Foot,
    Car,
    Bike,
    Boat,
    Helicopter,
    SWAT,
    FBI,
    Army
};

struct TrackedPoliceUnit {
    CEntity* entity = nullptr;
    PoliceUnitType type = PoliceUnitType::Foot;
    CVector position{};
    float distanceToPlayer = 0.0f;
    float heading = 0.0f;
    bool activePursuer = false;
    bool canSeePlayer = false;
    bool isLawEnforcer = false;
    bool sirenActive = false;
    bool inVehicle = false;
    int poolRef = -1;
    uint32_t lastSeenPlayerTime = 0;
};

class PoliceTracker {
public:
    void Update(const WantedSnapshot& wanted, const PolicePursuitRadarSettings& settings, uint32_t now);
    void RememberVisibleUnits();
    void Clear();

    std::vector<TrackedPoliceUnit>& Units() { return m_units; }
    const std::vector<TrackedPoliceUnit>& Units() const { return m_units; }
    unsigned int PursuitCopCount() const { return m_pursuitCopCount; }

private:
    std::vector<TrackedPoliceUnit> m_units;
    std::unordered_map<int, uint32_t> m_lastSeenByRef;
    unsigned int m_pursuitCopCount = 0;
};
