#include "SearchAreaRenderer.h"

#include "CRadar.h"
#include "RadarRenderPrimitives.h"

#include <algorithm>
#include <cmath>
#include <vector>

namespace {

constexpr float kPi = 3.14159265358979323846f;

} // namespace

void SearchAreaRenderer::Draw(const PoliceSearchState& searchState,
                              const PolicePursuitRadarSettings& settings,
                              uint32_t now) const {
    if (!settings.searchAreaEnabled || searchState.State() != PursuitState::Searching) {
        return;
    }

    const unsigned int segmentCount = std::max(16u, std::min(128u, settings.searchAreaSegments));
    const CVector center = searchState.LastKnownPlayerPosition();
    const float radius = searchState.SearchRadius();

    CVector2D centerRadar;
    CRadar::TransformRealWorldPointToRadarSpace(centerRadar, CVector2D(center.x, center.y));

    std::vector<CVector2D> ring;
    ring.reserve(segmentCount);
    for (unsigned int index = 0; index < segmentCount; ++index) {
        const float angle = 2.0f * kPi * static_cast<float>(index) / static_cast<float>(segmentCount);
        const CVector worldPoint(
            center.x + std::cos(angle) * radius,
            center.y + std::sin(angle) * radius,
            center.z);
        CVector2D radarPoint;
        CRadar::TransformRealWorldPointToRadarSpace(radarPoint, CVector2D(worldPoint.x, worldPoint.y));
        ring.push_back(radarPoint);
    }

    RadarRenderState renderState;
    if (!renderState.Active()) {
        return;
    }

    RadarColor fill = settings.searchAreaFill;
    const float pulse = 0.9f + 0.1f * std::sin(static_cast<float>(now) * 0.0015f);
    fill.alpha = std::max(0, std::min(255, static_cast<int>(fill.alpha * pulse)));

    for (unsigned int index = 0; index < segmentCount; ++index) {
        const CVector2D triangle[] = {
            centerRadar,
            ring[index],
            ring[(index + 1) % segmentCount]
        };
        RadarRenderPrimitives::DrawClippedRadarPolygon(triangle, 3, fill);
    }

    constexpr float borderHalfWidth = 0.018f;
    for (unsigned int index = 0; index < segmentCount; ++index) {
        const CVector2D& first = ring[index];
        const CVector2D& second = ring[(index + 1) % segmentCount];
        const CVector2D direction = second - first;
        const float length = direction.Magnitude();
        if (length <= 0.0001f) {
            continue;
        }
        const CVector2D normal(-direction.y / length * borderHalfWidth,
                               direction.x / length * borderHalfWidth);
        const CVector2D quad[] = {
            first + normal,
            second + normal,
            second - normal,
            first - normal
        };
        RadarRenderPrimitives::DrawClippedRadarPolygon(quad, 4, settings.searchAreaBorder);
    }

    if (settings.showSearchCenter) {
        CVector2D marker = centerRadar;
        const float distance = CRadar::LimitRadarPoint(marker);
        if (distance <= 1.05f) {
            const CVector2D screen = RadarRenderPrimitives::RadarToScreen(marker);
            const CVector2D points[] = {
                {screen.x - 3.0f, screen.y},
                {screen.x, screen.y - 3.0f},
                {screen.x + 3.0f, screen.y},
                {screen.x, screen.y + 3.0f}
            };
            RadarRenderPrimitives::DrawScreenFan(points, 4, settings.searchAreaBorder);
        }
    }
}

