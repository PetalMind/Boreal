#include "WantedStateProvider.h"

#include "CPlayerPed.h"
#include "CWanted.h"
#include "common.h"

WantedSnapshot WantedStateProvider::Read() const {
    WantedSnapshot snapshot;
    snapshot.player = FindPlayerPed(0);
    if (snapshot.player) {
        snapshot.playerPosition = snapshot.player->GetPosition();
    }

    snapshot.wanted = FindPlayerWanted(0);
    if (!snapshot.wanted) {
        return snapshot;
    }

    const CWanted& wanted = *snapshot.wanted;
    snapshot.wantedLevel = wanted.m_nWantedLevel;
    snapshot.copsInPursuit = wanted.m_nCopsInPursuit;
    snapshot.maxCopsInPursuit = wanted.m_nMaxCopsInPursuit;
    snapshot.maxCopCarsInPursuit = wanted.m_nMaxCopCarsInPursuit;
    snapshot.chanceOnRoadBlock = wanted.m_nChanceOnRoadBlock;
    snapshot.policeBackOff = wanted.m_bPoliceBackOff;
    snapshot.policeBackOffGarage = wanted.m_bPoliceBackOffGarage;
    snapshot.everybodyBackOff = wanted.m_bEverybodyBackOff;
    snapshot.swatRequired = wanted.m_bSwatRequired;
    snapshot.fbiRequired = wanted.m_bFbiRequired;
    snapshot.armyRequired = wanted.m_bArmyRequired;
    return snapshot;
}

bool WantedStateProvider::ShouldTrack(const WantedSnapshot& snapshot, const PolicePursuitRadarSettings& settings) const {
    if (!snapshot.player || !snapshot.wanted) {
        return false;
    }
    if (settings.onlyWhenWanted && !snapshot.HasWantedLevel()) {
        return false;
    }
    if (!snapshot.HasWantedLevel() && snapshot.copsInPursuit == 0) {
        return false;
    }
    return snapshot.VanillaPoliceActive();
}
