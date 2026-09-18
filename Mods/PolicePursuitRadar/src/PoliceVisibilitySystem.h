#pragma once

#include "PoliceTracker.h"

#include <cstdint>

class PoliceVisibilitySystem {
public:
    void Update(std::vector<TrackedPoliceUnit>& units,
                CPed* player,
                const PolicePursuitRadarSettings& settings,
                uint32_t now);

private:
    bool CanUnitSeePlayer(const TrackedPoliceUnit& unit, CPed* player) const;
};

