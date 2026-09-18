#pragma once

#include "Config.h"
#include "PoliceSearchState.h"

#include <cstdint>

class SearchAreaRenderer {
public:
    void Draw(const PoliceSearchState& searchState,
              const PolicePursuitRadarSettings& settings,
              uint32_t now) const;
};

