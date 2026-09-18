#include "RadarRenderPrimitives.h"

#include "CRadar.h"
#include "CSprite2d.h"
#include "RenderWare.h"
#include "common_sdk.h"
#include "d3d9.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace {

unsigned int ColorValue(const RadarColor& color) {
    return RWRGBALONG(
        static_cast<unsigned char>(color.red),
        static_cast<unsigned char>(color.green),
        static_cast<unsigned char>(color.blue),
        static_cast<unsigned char>(color.alpha));
}

RwIm2DVertex MakeVertex(const CVector2D& point, unsigned int color) {
    RwIm2DVertex vertex{};
    vertex.x = point.x;
    vertex.y = point.y;
    vertex.z = CSprite2d::NearScreenZ + 0.0001f;
    vertex.rhw = CSprite2d::RecipNearClip;
    vertex.emissiveColor = color;
    vertex.u = 0.0f;
    vertex.v = 0.0f;
    return vertex;
}

std::vector<CVector2D> ClipPolygonToRadar(const CVector2D* points, size_t count) {
    std::vector<CVector2D> result;
    if (!points || count < 3) {
        return result;
    }

    constexpr float epsilon = 0.0001f;
    auto inside = [](const CVector2D& point) {
        return point.x * point.x + point.y * point.y <= 1.0f;
    };
    auto intersections = [](const CVector2D& start, const CVector2D& end) {
        std::vector<float> values;
        const CVector2D delta = end - start;
        const float a = delta.x * delta.x + delta.y * delta.y;
        const float b = 2.0f * (start.x * delta.x + start.y * delta.y);
        const float c = start.x * start.x + start.y * start.y - 1.0f;
        if (a <= epsilon) {
            return values;
        }
        const float discriminant = b * b - 4.0f * a * c;
        if (discriminant < 0.0f) {
            return values;
        }
        const float root = std::sqrt(discriminant);
        const float first = (-b - root) / (2.0f * a);
        const float second = (-b + root) / (2.0f * a);
        if (first >= -epsilon && first <= 1.0f + epsilon) values.push_back(std::max(0.0f, std::min(1.0f, first)));
        if (second >= -epsilon && second <= 1.0f + epsilon && std::fabs(second - first) > epsilon) values.push_back(std::max(0.0f, std::min(1.0f, second)));
        std::sort(values.begin(), values.end());
        return values;
    };

    for (size_t index = 0; index < count; ++index) {
        const CVector2D& start = points[index];
        const CVector2D& end = points[(index + 1) % count];
        const bool startInside = inside(start);
        const bool endInside = inside(end);
        if (startInside && endInside) {
            result.push_back(end);
        } else if (startInside && !endInside) {
            const auto roots = intersections(start, end);
            if (!roots.empty()) result.push_back(start + (end - start) * roots.front());
        } else if (!startInside && endInside) {
            const auto roots = intersections(start, end);
            if (!roots.empty()) result.push_back(start + (end - start) * roots.back());
            result.push_back(end);
        } else {
            const auto roots = intersections(start, end);
            for (float root : roots) {
                result.push_back(start + (end - start) * root);
            }
        }
    }
    return result;
}

} // namespace

RadarRenderState::RadarRenderState() {
    m_oldTexture = plugin::GetRenderRaster(rwRENDERSTATETEXTURERASTER);
    m_oldSourceBlend = plugin::GetRenderState(rwRENDERSTATESRCBLEND);
    m_oldDestinationBlend = plugin::GetRenderState(rwRENDERSTATEDESTBLEND);
    m_oldVertexAlpha = plugin::GetRenderState(rwRENDERSTATEVERTEXALPHAENABLE);
    m_oldZTest = plugin::GetRenderState(rwRENDERSTATEZTESTENABLE);
    m_oldZWrite = plugin::GetRenderState(rwRENDERSTATEZWRITEENABLE);

    plugin::SetRenderRaster(nullptr);
    plugin::SetRenderState(rwRENDERSTATESRCBLEND, rwBLENDSRCALPHA);
    plugin::SetRenderState(rwRENDERSTATEDESTBLEND, rwBLENDINVSRCALPHA);
    plugin::SetRenderState(rwRENDERSTATEVERTEXALPHAENABLE, TRUE);
    plugin::SetRenderState(rwRENDERSTATEZTESTENABLE, FALSE);
    plugin::SetRenderState(rwRENDERSTATEZWRITEENABLE, FALSE);

    auto* device = reinterpret_cast<IDirect3DDevice9*>(GetD3DDevice());
    if (device) {
        m_device = device;
        device->GetRenderState(D3DRS_SCISSORTESTENABLE, &m_oldScissorEnabled);
        RECT oldRect{};
        device->GetScissorRect(&oldRect);
        m_oldScissorRect.left = oldRect.left;
        m_oldScissorRect.top = oldRect.top;
        m_oldScissorRect.right = oldRect.right;
        m_oldScissorRect.bottom = oldRect.bottom;

        CVector2D topLeft;
        CVector2D bottomRight;
        CRadar::TransformRadarPointToScreenSpace(topLeft, CVector2D(-1.0f, 1.0f));
        CRadar::TransformRadarPointToScreenSpace(bottomRight, CVector2D(1.0f, -1.0f));
        RECT radarRect{};
        radarRect.left = static_cast<LONG>(std::min(topLeft.x, bottomRight.x));
        radarRect.top = static_cast<LONG>(std::min(topLeft.y, bottomRight.y));
        radarRect.right = static_cast<LONG>(std::max(topLeft.x, bottomRight.x));
        radarRect.bottom = static_cast<LONG>(std::max(topLeft.y, bottomRight.y));
        device->SetRenderState(D3DRS_SCISSORTESTENABLE, TRUE);
        device->SetScissorRect(&radarRect);
    }

    m_active = true;
}

RadarRenderState::~RadarRenderState() {
    if (!m_active) {
        return;
    }

    plugin::SetRenderRaster(reinterpret_cast<RwRaster*>(m_oldTexture));
    plugin::SetRenderState(rwRENDERSTATESRCBLEND, m_oldSourceBlend);
    plugin::SetRenderState(rwRENDERSTATEDESTBLEND, m_oldDestinationBlend);
    plugin::SetRenderState(rwRENDERSTATEVERTEXALPHAENABLE, m_oldVertexAlpha);
    plugin::SetRenderState(rwRENDERSTATEZTESTENABLE, m_oldZTest);
    plugin::SetRenderState(rwRENDERSTATEZWRITEENABLE, m_oldZWrite);

    auto* device = reinterpret_cast<IDirect3DDevice9*>(m_device);
    if (device) {
        RECT oldRect{
            m_oldScissorRect.left,
            m_oldScissorRect.top,
            m_oldScissorRect.right,
            m_oldScissorRect.bottom};
        device->SetScissorRect(&oldRect);
        device->SetRenderState(D3DRS_SCISSORTESTENABLE, m_oldScissorEnabled);
    }
}

namespace RadarRenderPrimitives {

CVector2D RadarToScreen(const CVector2D& radarPoint) {
    CVector2D screen;
    CRadar::TransformRadarPointToScreenSpace(screen, radarPoint);
    return screen;
}

void DrawScreenFan(const CVector2D* points, size_t count, const RadarColor& color) {
    if (!points || count < 3 || count > 128) {
        return;
    }

    std::array<RwIm2DVertex, 128> vertices{};
    const unsigned int packedColor = ColorValue(color);
    for (size_t index = 0; index < count; ++index) {
        vertices[index] = MakeVertex(points[index], packedColor);
    }
    RwIm2DRenderPrimitive(rwPRIMTYPETRIFAN, vertices.data(), static_cast<RwInt32>(count));
}

void DrawClippedRadarPolygon(const CVector2D* radarPoints, size_t count, const RadarColor& color) {
    if (!radarPoints || count < 3 || count > 8) {
        return;
    }

    const auto clipped = ClipPolygonToRadar(radarPoints, count);
    if (clipped.size() < 3 || clipped.size() > 128) {
        return;
    }

    std::array<CVector2D, 128> screenPoints{};
    for (size_t index = 0; index < clipped.size(); ++index) {
        screenPoints[index] = RadarToScreen(clipped[index]);
    }
    DrawScreenFan(screenPoints.data(), clipped.size(), color);
}

} // namespace RadarRenderPrimitives
