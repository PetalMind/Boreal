#define GTASA 1
#define PLUGIN_SGV_10US 1
#define RW 1

#include "plugin.h"

#include "CMenuManager.h"
#include "CTheScripts.h"
#include "CTimer.h"
#include "CHud.h"
#include "common.h"

#include "Config.h"
#include "HudRenderer.h"
#include "Logger.h"
#include "PoliceSearchState.h"
#include "PoliceTracker.h"
#include "PoliceVisibilitySystem.h"
#include "RadarRenderer.h"
#include "SearchAreaRenderer.h"
#include "WantedStateProvider.h"

#include <windows.h>

#include <fstream>
#include <string>

namespace {

std::string ModuleDirectory() {
    HMODULE module = nullptr;
    if (!GetModuleHandleExA(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCSTR>(&ModuleDirectory),
            &module)) {
        char currentDirectory[MAX_PATH]{};
        GetCurrentDirectoryA(MAX_PATH, currentDirectory);
        return currentDirectory;
    }

    char modulePath[MAX_PATH]{};
    const DWORD length = GetModuleFileNameA(module, modulePath, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        return ".";
    }
    std::string path(modulePath, length);
    const auto separator = path.find_last_of("\\/");
    return separator == std::string::npos ? "." : path.substr(0, separator);
}

std::string JoinPath(const std::string& directory, const char* fileName) {
    if (directory.empty()) {
        return fileName;
    }
    const char last = directory.back();
    return directory + ((last == '\\' || last == '/') ? "" : "\\") + fileName;
}

} // namespace

class PolicePursuitRadar {
public:
    PolicePursuitRadar() {
        const std::string directory = ModuleDirectory();
        m_configPath = JoinPath(directory, "PolicePursuitRadar.ini");
        m_logger.Initialize(JoinPath(directory, "PolicePursuitRadar.log"));
        ReloadConfig();
        m_logger.Log("Police Pursuit Radar initializing; plugin-sdk lifecycle registered");

        plugin::Events::gameProcessEvent += [this] { OnGameProcess(); };
        plugin::Events::drawRadarOverlayEvent += [this] { OnDrawRadarOverlay(); };
        plugin::Events::drawBlipsEvent += [this] { OnDrawBlips(); };
        plugin::Events::drawHudEvent += [this] { OnDrawHud(); };
        plugin::Events::reInitGameEvent += [this] { ResetRuntimeState(); };
        plugin::Events::shutdownPoolsEvent += [this] { ResetRuntimeState(); };
    }

private:
    void ReloadConfig() {
        Config loaded;
        loaded.Load(m_configPath);
        m_config = loaded;
        for (const auto& warning : m_config.Warnings()) {
            m_logger.Error("Config: %s", warning.c_str());
        }
        m_logger.Log("Configuration loaded from %s", m_configPath.c_str());
    }

    void ResetRuntimeState() {
        m_tracker.Clear();
        m_searchState.Reset();
        m_lastTrackerUpdate = 0;
        m_lastVisibilityUpdate = 0;
        m_hasTrackerUpdate = false;
        m_hasVisibilityUpdate = false;
        m_latestWanted = WantedSnapshot{};
    }

    void CheckGameVersion() {
        if (m_versionChecked) {
            return;
        }
        m_versionChecked = true;
        m_logger.Log("Detected game version: %s", plugin::GetGameVersionName());
        if (!plugin::IsGameVersion10us()) {
            m_unsupportedVersion = true;
            m_logger.Error("Unsupported executable version; only GTA SA 1.0 US x86 is enabled");
        }
    }

    void OnGameProcess() {
        CheckGameVersion();
        if (m_unsupportedVersion) {
            return;
        }

        const auto& settingsBeforeReload = m_config.Settings();
        if (settingsBeforeReload.reloadHotkeyEnabled && (GetAsyncKeyState(settingsBeforeReload.reloadHotkey) & 1)) {
            ReloadConfig();
        }

        const auto& settings = m_config.Settings();
        const uint32_t now = CTimer::m_snTimeInMilliseconds;
        if (!settings.enabled) {
            ResetRuntimeState();
            return;
        }

        m_latestWanted = m_wantedState.Read();
        if (!m_wantedState.ShouldTrack(m_latestWanted, settings)) {
            m_tracker.Clear();
            m_searchState.Update(m_latestWanted, m_tracker.Units(), settings, now);
            return;
        }

        if (!m_hasTrackerUpdate || now - m_lastTrackerUpdate >= settings.trackerUpdateIntervalMs) {
            m_tracker.Update(m_latestWanted, settings, now);
            m_lastTrackerUpdate = now;
            m_hasTrackerUpdate = true;
            if (settings.logTrackedUnits) {
                m_logger.Log("Tracked units: %u; cops in pursuit: %u",
                    static_cast<unsigned int>(m_tracker.Units().size()),
                    m_tracker.PursuitCopCount());
            }
        }

        if (!m_hasVisibilityUpdate || now - m_lastVisibilityUpdate >= settings.visibilityUpdateIntervalMs) {
            m_visibility.Update(m_tracker.Units(), m_latestWanted.player, settings, now);
            m_tracker.RememberVisibleUnits();
            m_lastVisibilityUpdate = now;
            m_hasVisibilityUpdate = true;
        }

        m_searchState.Update(m_latestWanted, m_tracker.Units(), settings, now);
    }

    bool CanDrawRadarLayer() const {
        if (m_unsupportedVersion || !m_config.Settings().enabled) {
            return false;
        }
        CPed* player = FindPlayerPed(0);
        if (!player || player->m_nAreaCode != 0 || CHud::bScriptDontDisplayRadar || CTheScripts::bScriptHasFadedOut) {
            return false;
        }
        if (FrontEndMenuManager.m_bDrawRadarOrMap) {
            return m_config.Settings().showOnPauseMap;
        }
        return !FrontEndMenuManager.m_bMenuActive && !CTimer::m_UserPause && !CTimer::m_CodePause;
    }

    void OnDrawRadarOverlay() {
        if (!CanDrawRadarLayer()) {
            return;
        }
        const auto& settings = m_config.Settings();
        m_searchAreaRenderer.Draw(m_searchState, settings, CTimer::m_snTimeInMilliseconds);
    }

    void OnDrawBlips() {
        if (!CanDrawRadarLayer()) {
            return;
        }
        const auto& settings = m_config.Settings();
        m_radarRenderer.DrawPoliceUnits(m_tracker.Units(), m_searchState, settings, CTimer::m_snTimeInMilliseconds);
    }

    void OnDrawHud() {
        if (!CanDrawRadarLayer()) {
            return;
        }
        const auto& settings = m_config.Settings();
        m_hudRenderer.Draw(m_latestWanted, m_searchState, m_tracker, settings, CTimer::m_snTimeInMilliseconds);
    }

    Logger m_logger;
    Config m_config;
    std::string m_configPath;
    WantedStateProvider m_wantedState;
    PoliceTracker m_tracker;
    PoliceVisibilitySystem m_visibility;
    PoliceSearchState m_searchState;
    RadarRenderer m_radarRenderer;
    SearchAreaRenderer m_searchAreaRenderer;
    HudRenderer m_hudRenderer;
    WantedSnapshot m_latestWanted;
    uint32_t m_lastTrackerUpdate = 0;
    uint32_t m_lastVisibilityUpdate = 0;
    bool m_hasTrackerUpdate = false;
    bool m_hasVisibilityUpdate = false;
    bool m_versionChecked = false;
    bool m_unsupportedVersion = false;
};

PolicePursuitRadar g_policePursuitRadar;
