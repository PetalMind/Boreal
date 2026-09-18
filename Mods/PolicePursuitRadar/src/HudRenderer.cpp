#include "HudRenderer.h"

#include "CFont.h"
#include "CRadar.h"
#include "CRGBA.h"
#include "RenderWare.h"

#include <cstdio>

namespace {

const char* StateName(PursuitState state) {
    switch (state) {
    case PursuitState::Idle: return "IDLE";
    case PursuitState::Pursuit: return "PURSUIT";
    case PursuitState::LosingContact: return "PURSUIT";
    case PursuitState::Searching: return "SEARCHING";
    case PursuitState::Escaped: return "ESCAPED";
    }
    return "IDLE";
}

} // namespace

void HudRenderer::Draw(const WantedSnapshot& wanted,
                       const PoliceSearchState& searchState,
                       const PoliceTracker& tracker,
                       const PolicePursuitRadarSettings& settings,
                       uint32_t now) const {
    if (!settings.showPursuitStatus && !settings.debugEnabled) {
        return;
    }
    if (wanted.wantedLevel == 0 && !settings.debugEnabled) {
        return;
    }

    CVector2D radarBottom;
    CRadar::TransformRadarPointToScreenSpace(radarBottom, CVector2D(0.0f, -1.0f));
    const float widthScale = static_cast<float>(RsGlobal.maximumWidth) / 640.0f;
    const float heightScale = static_cast<float>(RsGlobal.maximumHeight) / 448.0f;

    CFont::SetOrientation(ALIGN_CENTER);
    CFont::SetBackground(false, false);
    CFont::SetProportional(true);
    CFont::SetFontStyle(FONT_SUBTITLES);
    CFont::SetScale(0.32f * widthScale, 0.60f * heightScale);
    CFont::SetDropShadowPosition(1);
    CFont::SetDropColor(CRGBA(0, 0, 0, 220));
    CFont::SetColor(CRGBA(190, 220, 255, 235));

    if (settings.showPursuitStatus && searchState.State() != PursuitState::Idle) {
        CFont::PrintString(radarBottom.x, radarBottom.y + 7.0f * heightScale, StateName(searchState.State()));
    }

    if (!settings.debugEnabled) {
        return;
    }

    char line[160]{};
    const float debugX = radarBottom.x + 65.0f * widthScale;
    float debugY = radarBottom.y - 48.0f * heightScale;
    CFont::SetOrientation(ALIGN_RIGHT);
    CFont::SetScale(0.27f * widthScale, 0.52f * heightScale);
    std::snprintf(line, sizeof(line), "PPR %s  wanted=%u  units=%u", StateName(searchState.State()), wanted.wantedLevel, static_cast<unsigned int>(tracker.Units().size()));
    CFont::PrintString(debugX, debugY, line);
    debugY += 8.0f * heightScale;
    std::snprintf(line, sizeof(line), "detected=%s  pursuit=%u/%u", searchState.PlayerDetected() ? "yes" : "no", tracker.PursuitCopCount(), wanted.maxCopsInPursuit);
    CFont::PrintString(debugX, debugY, line);
    debugY += 8.0f * heightScale;
    const CVector& lastKnown = searchState.LastKnownPlayerPosition();
    std::snprintf(line, sizeof(line), "last=(%.1f, %.1f) radius=%.0f", lastKnown.x, lastKnown.y, searchState.SearchRadius());
    CFont::PrintString(debugX, debugY, line);
    debugY += 8.0f * heightScale;
    std::snprintf(line, sizeof(line), "time=%u", now);
    CFont::PrintString(debugX, debugY, line);
}
