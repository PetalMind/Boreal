#pragma once

#include "Config.h"
#include "PoliceSearchState.h"
#include "PoliceTracker.h"

#include <cstdint>

class RadarRenderer {
public:
    void DrawPoliceUnits(const std::vector<TrackedPoliceUnit>& units,
                         const PoliceSearchState& searchState,
                         const PolicePursuitRadarSettings& settings,
                         uint32_t now) const;
};

