#pragma once

#include "Config.h"

#include "CVector.h"

class CPed;
class CCopPed;
class CWanted;

struct WantedSnapshot {
    CPed* player = nullptr;
    CWanted* wanted = nullptr;
    CVector playerPosition{};
    unsigned int wantedLevel = 0;
    unsigned char copsInPursuit = 0;
    unsigned char maxCopsInPursuit = 0;
    unsigned char maxCopCarsInPursuit = 0;
    unsigned short chanceOnRoadBlock = 0;
    bool policeBackOff = false;
    bool policeBackOffGarage = false;
    bool everybodyBackOff = false;
    bool swatRequired = false;
    bool fbiRequired = false;
    bool armyRequired = false;

    bool HasWantedLevel() const { return wantedLevel > 0; }
    bool VanillaPoliceActive() const {
        return !policeBackOff && !policeBackOffGarage && !everybodyBackOff;
    }
};

class WantedStateProvider {
public:
    WantedSnapshot Read() const;
    bool ShouldTrack(const WantedSnapshot& snapshot, const PolicePursuitRadarSettings& settings) const;
};
