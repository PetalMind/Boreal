#pragma once

#include "PoliceTracker.h"

#include <cstdint>

enum class PursuitState {
    Idle,
    Pursuit,
    LosingContact,
    Searching,
    Escaped
};

class PoliceSearchState {
public:
    void Update(const WantedSnapshot& wanted,
                const std::vector<TrackedPoliceUnit>& units,
                const PolicePursuitRadarSettings& settings,
                uint32_t now);
    void Reset();

    PursuitState State() const { return m_state; }
    bool PlayerDetected() const { return m_playerDetected; }
    const CVector& LastKnownPlayerPosition() const { return m_lastKnownPlayerPosition; }
    float SearchRadius() const { return m_searchRadius; }
    uint32_t LostContactTimestamp() const { return m_lostContactTimestamp; }

private:
    void EnterPursuit(const CVector& playerPosition, unsigned int wantedLevel, const PolicePursuitRadarSettings& settings);
    bool HasDirectContact(const std::vector<TrackedPoliceUnit>& units) const;
    float RadiusForWantedLevel(unsigned int wantedLevel, const PolicePursuitRadarSettings& settings) const;

    PursuitState m_state = PursuitState::Idle;
    CVector m_lastKnownPlayerPosition{};
    uint32_t m_lostContactTimestamp = 0;
    uint32_t m_escapedTimestamp = 0;
    float m_searchRadius = 0.0f;
    bool m_playerDetected = false;
};
