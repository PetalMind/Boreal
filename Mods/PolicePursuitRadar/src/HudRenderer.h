#pragma once

#include "Config.h"
#include "PoliceSearchState.h"
#include "PoliceTracker.h"
#include "WantedStateProvider.h"

#include <cstdint>

class HudRenderer {
public:
    void Draw(const WantedSnapshot& wanted,
              const PoliceSearchState& searchState,
              const PoliceTracker& tracker,
              const PolicePursuitRadarSettings& settings,
              uint32_t now) const;
};

