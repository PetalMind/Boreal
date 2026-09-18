#pragma once

#include "Config.h"

#include "CVector2D.h"

#include <cstddef>

class RadarRenderState {
public:
    RadarRenderState();
    ~RadarRenderState();

    RadarRenderState(const RadarRenderState&) = delete;
    RadarRenderState& operator=(const RadarRenderState&) = delete;

    bool Active() const { return m_active; }

private:
    bool m_active = false;
    void* m_oldTexture = nullptr;
    unsigned int m_oldSourceBlend = 0;
    unsigned int m_oldDestinationBlend = 0;
    unsigned int m_oldVertexAlpha = 0;
    unsigned int m_oldZTest = 0;
    unsigned int m_oldZWrite = 0;
    void* m_device = nullptr;
    unsigned long m_oldScissorEnabled = 0;
    struct RectStorage {
        long left = 0;
        long top = 0;
        long right = 0;
        long bottom = 0;
    } m_oldScissorRect;
};

namespace RadarRenderPrimitives {

void DrawScreenFan(const CVector2D* points, size_t count, const RadarColor& color);
void DrawClippedRadarPolygon(const CVector2D* radarPoints, size_t count, const RadarColor& color);
CVector2D RadarToScreen(const CVector2D& radarPoint);

} // namespace RadarRenderPrimitives

