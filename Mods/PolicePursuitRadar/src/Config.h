#pragma once

#include <array>
#include <string>
#include <vector>

struct RadarColor {
    int red = 255;
    int green = 255;
    int blue = 255;
    int alpha = 255;
};

struct PolicePursuitRadarSettings {
    bool enabled = true;
    bool onlyWhenWanted = true;
    bool showOnPauseMap = false;
    bool showPursuitStatus = true;

    float maxTrackingDistance = 650.0f;
    unsigned int visibilityUpdateIntervalMs = 150;
    unsigned int trackerUpdateIntervalMs = 100;
    unsigned int lostSightDelayMs = 1200;

    bool searchAreaEnabled = true;
    unsigned int searchAreaSegments = 64;
    std::array<float, 6> searchRadius{{120.0f, 170.0f, 230.0f, 300.0f, 380.0f, 480.0f}};
    RadarColor searchAreaFill{80, 140, 255, 45};
    RadarColor searchAreaBorder{100, 170, 255, 150};

    bool policeBlipsEnabled = true;
    bool showFootPolice = true;
    bool showCars = true;
    bool showBikes = true;
    bool showBoats = true;
    bool showHelicopters = true;
    bool showOffRadarPolice = false;

    RadarColor policeColor{60, 140, 255, 230};
    RadarColor policeVisibleColor{255, 80, 80, 255};
    bool pulseDuringPursuit = true;
    float pulseSpeed = 3.0f;

    bool debugEnabled = false;
    bool logTrackedUnits = false;
    bool showSearchCenter = false;
    bool showPoliceLos = false;

    bool reloadHotkeyEnabled = true;
    int reloadHotkey = 0x7A; // VK_F11
};

class Config {
public:
    bool Load(const std::string& path);

    const PolicePursuitRadarSettings& Settings() const { return m_settings; }
    const std::vector<std::string>& Warnings() const { return m_warnings; }

private:
    PolicePursuitRadarSettings m_settings;
    std::vector<std::string> m_warnings;
};

