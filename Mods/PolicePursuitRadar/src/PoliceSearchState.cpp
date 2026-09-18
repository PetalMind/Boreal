#include "PoliceSearchState.h"

#include <algorithm>

void PoliceSearchState::Reset() {
    m_state = PursuitState::Idle;
    m_lastKnownPlayerPosition = CVector{};
    m_lostContactTimestamp = 0;
    m_escapedTimestamp = 0;
    m_searchRadius = 0.0f;
    m_playerDetected = false;
}

void PoliceSearchState::EnterPursuit(const CVector& playerPosition,
                                     unsigned int wantedLevel,
                                     const PolicePursuitRadarSettings& settings) {
    m_state = PursuitState::Pursuit;
    m_playerDetected = true;
    m_lastKnownPlayerPosition = playerPosition;
    m_lostContactTimestamp = 0;
    m_searchRadius = RadiusForWantedLevel(wantedLevel, settings);
}

bool PoliceSearchState::HasDirectContact(const std::vector<TrackedPoliceUnit>& units) const {
    return std::any_of(units.begin(), units.end(), [](const TrackedPoliceUnit& unit) {
        return unit.activePursuer && unit.canSeePlayer;
    });
}

float PoliceSearchState::RadiusForWantedLevel(unsigned int wantedLevel,
                                              const PolicePursuitRadarSettings& settings) const {
    const unsigned int index = std::min(6u, std::max(1u, wantedLevel)) - 1;
    return settings.searchRadius[index];
}

void PoliceSearchState::Update(const WantedSnapshot& wanted,
                               const std::vector<TrackedPoliceUnit>& units,
                               const PolicePursuitRadarSettings& settings,
                               uint32_t now) {
    if (!wanted.player || !wanted.wanted || !wanted.HasWantedLevel() || !wanted.VanillaPoliceActive()) {
        if (m_state != PursuitState::Idle && m_state != PursuitState::Escaped) {
            m_state = PursuitState::Escaped;
            m_escapedTimestamp = now;
            m_playerDetected = false;
        } else if (m_state == PursuitState::Escaped && now - m_escapedTimestamp >= 450) {
            Reset();
        }
        return;
    }

    const bool directContact = HasDirectContact(units);
    m_playerDetected = directContact;

    switch (m_state) {
    case PursuitState::Idle:
        if (directContact) {
            EnterPursuit(wanted.playerPosition, wanted.wantedLevel, settings);
        }
        break;
    case PursuitState::Escaped:
        if (directContact) {
            EnterPursuit(wanted.playerPosition, wanted.wantedLevel, settings);
        } else if (now - m_escapedTimestamp >= 450) {
            Reset();
        }
        break;
    case PursuitState::Pursuit:
        if (directContact) {
            m_lastKnownPlayerPosition = wanted.playerPosition;
            m_searchRadius = RadiusForWantedLevel(wanted.wantedLevel, settings);
        } else {
            m_state = PursuitState::LosingContact;
            m_lostContactTimestamp = now;
        }
        break;
    case PursuitState::LosingContact:
        if (directContact) {
            EnterPursuit(wanted.playerPosition, wanted.wantedLevel, settings);
        } else if (now - m_lostContactTimestamp >= settings.lostSightDelayMs) {
            m_state = PursuitState::Searching;
            m_playerDetected = false;
            m_searchRadius = RadiusForWantedLevel(wanted.wantedLevel, settings);
        }
        break;
    case PursuitState::Searching:
        if (directContact) {
            EnterPursuit(wanted.playerPosition, wanted.wantedLevel, settings);
        }
        break;
    }
}
