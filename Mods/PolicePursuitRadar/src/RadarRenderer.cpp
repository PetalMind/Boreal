#include "RadarRenderer.h"

#include "CRadar.h"
#include "RadarRenderPrimitives.h"

#include <algorithm>
#include <cmath>
#include <vector>

namespace {

RadarColor Blend(const RadarColor& first, const RadarColor& second, float amount) {
    amount = std::max(0.0f, std::min(1.0f, amount));
    return {
        static_cast<int>(first.red + (second.red - first.red) * amount),
        static_cast<int>(first.green + (second.green - first.green) * amount),
        static_cast<int>(first.blue + (second.blue - first.blue) * amount),
        static_cast<int>(first.alpha + (second.alpha - first.alpha) * amount)
    };
}

bool EnabledForType(PoliceUnitType type, const PolicePursuitRadarSettings& settings) {
    switch (type) {
    case PoliceUnitType::Foot:
    case PoliceUnitType::SWAT:
    case PoliceUnitType::FBI:
    case PoliceUnitType::Army:
        return settings.showFootPolice;
    case PoliceUnitType::Car:
        return settings.showCars;
    case PoliceUnitType::Bike:
        return settings.showBikes;
    case PoliceUnitType::Boat:
        return settings.showBoats;
    case PoliceUnitType::Helicopter:
        return settings.showHelicopters;
    }
    return false;
}

void DrawCircle(const CVector2D& center, float radius, const RadarColor& color, unsigned int segments = 10) {
    std::vector<CVector2D> points;
    points.reserve(segments);
    constexpr float pi = 3.14159265358979323846f;
    for (unsigned int index = 0; index < segments; ++index) {
        const float angle = 2.0f * pi * static_cast<float>(index) / static_cast<float>(segments);
        points.push_back({
            center.x + std::cos(angle) * radius,
            center.y + std::sin(angle) * radius});
    }
    RadarRenderPrimitives::DrawScreenFan(points.data(), points.size(), color);
}

void DrawChevron(const CVector2D& center, const CVector2D& direction, float scale, const RadarColor& color) {
    const CVector2D normalized = direction.Magnitude() > 0.001f ? direction.Normalized() : CVector2D(0.0f, -1.0f);
    const CVector2D normal(-normalized.y, normalized.x);
    const CVector2D tip = center + normalized * (7.0f * scale);
    const CVector2D left = center - normalized * (4.0f * scale) + normal * (3.5f * scale);
    const CVector2D right = center - normalized * (4.0f * scale) - normal * (3.5f * scale);
    const CVector2D triangle[] = {tip, left, right};
    RadarRenderPrimitives::DrawScreenFan(triangle, 3, color);
}

void DrawDiamond(const CVector2D& center, float scale, const RadarColor& color) {
    const CVector2D points[] = {
        {center.x, center.y - 5.0f * scale},
        {center.x + 5.0f * scale, center.y},
        {center.x, center.y + 5.0f * scale},
        {center.x - 5.0f * scale, center.y}
    };
    RadarRenderPrimitives::DrawScreenFan(points, 4, color);
}

} // namespace

void RadarRenderer::DrawPoliceUnits(const std::vector<TrackedPoliceUnit>& units,
                                    const PoliceSearchState& searchState,
                                    const PolicePursuitRadarSettings& settings,
                                    uint32_t now) const {
    if (!settings.policeBlipsEnabled || units.empty()) {
        return;
    }

    RadarRenderState renderState;
    if (!renderState.Active()) {
        return;
    }

    const float pulsePhase = static_cast<float>(now) * 0.001f * settings.pulseSpeed;
    const float pulse = 0.75f + std::sin(pulsePhase) * 0.25f;

    for (const auto& unit : units) {
        if (!unit.entity || !EnabledForType(unit.type, settings)) {
            continue;
        }

        CVector2D radarPoint;
        CRadar::TransformRealWorldPointToRadarSpace(radarPoint, CVector2D(unit.position.x, unit.position.y));
        const float distance = radarPoint.Magnitude();
        if (distance > 1.0f && !settings.showOffRadarPolice) {
            continue;
        }
        if (distance > 1.0f) {
            CRadar::LimitRadarPoint(radarPoint);
        }
        const CVector2D screenPoint = RadarRenderPrimitives::RadarToScreen(radarPoint);

        RadarColor color = settings.policeColor;
        if (settings.debugEnabled && settings.showPoliceLos) {
            color = unit.canSeePlayer ? RadarColor{80, 255, 100, 255} : RadarColor{255, 70, 70, 255};
        } else if (unit.canSeePlayer) {
            color = settings.policeVisibleColor;
        } else if (unit.activePursuer && searchState.State() == PursuitState::Pursuit && settings.pulseDuringPursuit) {
            color = Blend(settings.policeColor, settings.policeVisibleColor, 0.25f + pulse * 0.35f);
        }

        const float scale = unit.canSeePlayer ? 1.15f : (unit.activePursuer && settings.pulseDuringPursuit ? pulse : 1.0f);
        if (unit.type == PoliceUnitType::Helicopter) {
            DrawCircle(screenPoint, 5.0f * scale, color, 12);
            DrawCircle(screenPoint, 1.6f * scale, settings.policeVisibleColor, 8);
            continue;
        }

        if (unit.type == PoliceUnitType::Foot || unit.type == PoliceUnitType::SWAT ||
            unit.type == PoliceUnitType::FBI || unit.type == PoliceUnitType::Army) {
            DrawCircle(screenPoint, 3.0f * scale, color, 10);
            continue;
        }

        CVector2D radarOrigin;
        CVector2D radarForward;
        CRadar::TransformRealWorldPointToRadarSpace(radarOrigin, CVector2D(unit.position.x, unit.position.y));
        CRadar::TransformRealWorldPointToRadarSpace(
            radarForward,
            CVector2D(unit.position.x + std::cos(unit.heading), unit.position.y + std::sin(unit.heading)));
        const CVector2D screenDirection = RadarRenderPrimitives::RadarToScreen(radarForward)
            - RadarRenderPrimitives::RadarToScreen(radarOrigin);

        if (unit.type == PoliceUnitType::Boat) {
            DrawDiamond(screenPoint, scale, color);
        } else {
            DrawChevron(screenPoint, screenDirection, scale, color);
        }
    }
}
