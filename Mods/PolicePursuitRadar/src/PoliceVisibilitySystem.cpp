#include "PoliceVisibilitySystem.h"

#include "CEntity.h"
#include "CPed.h"
#include "CWorld.h"

#include <algorithm>
#include <vector>

void PoliceVisibilitySystem::Update(std::vector<TrackedPoliceUnit>& units,
                                    CPed* player,
                                    const PolicePursuitRadarSettings& settings,
                                    uint32_t now) {
    for (auto& unit : units) {
        unit.canSeePlayer = false;
    }
    if (!player) {
        return;
    }

    std::vector<size_t> candidates;
    candidates.reserve(units.size());
    for (size_t index = 0; index < units.size(); ++index) {
        if (units[index].activePursuer && units[index].distanceToPlayer <= settings.maxTrackingDistance) {
            candidates.push_back(index);
        }
    }
    std::stable_sort(candidates.begin(), candidates.end(), [&units](size_t left, size_t right) {
        if (units[left].activePursuer != units[right].activePursuer) {
            return units[left].activePursuer;
        }
        return units[left].distanceToPlayer < units[right].distanceToPlayer;
    });

    // Active pursuit units are prioritized, but a very large modpack scene
    // cannot turn this into dozens of raycasts per update.
    constexpr size_t kMaximumLineOfSightChecks = 8;
    const size_t checks = std::min(kMaximumLineOfSightChecks, candidates.size());
    for (size_t candidate = 0; candidate < checks; ++candidate) {
        auto& unit = units[candidates[candidate]];
        if (CanUnitSeePlayer(unit, player)) {
            unit.canSeePlayer = true;
            unit.lastSeenPlayerTime = now;
        }
    }
}

bool PoliceVisibilitySystem::CanUnitSeePlayer(const TrackedPoliceUnit& unit, CPed* player) const {
    if (!unit.entity || !player) {
        return false;
    }

    CEntity* entity = unit.entity;
    if (entity->m_nAreaCode != player->m_nAreaCode) {
        return false;
    }

    CVector origin = unit.position;
    CVector target = player->GetPosition();
    origin.z += unit.inVehicle ? 1.35f : 1.10f;
    target.z += 1.05f;

    return CWorld::GetIsLineOfSightClear(
        origin,
        target,
        true,  // buildings
        true,  // vehicles
        true,  // peds
        true,  // objects
        false, // dummies
        false, // see-through materials do not block the view
        true   // use the same camera-ignore behavior as the game LOS helper
    );
}

