#include "Config.h"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>

namespace {

std::string Trim(std::string value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return {};
    }
    const auto last = value.find_last_not_of(" \t\r\n");
    value = value.substr(first, last - first + 1);
    return value;
}

std::string Lower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

bool ParseBool(const std::string& value, bool fallback) {
    const auto lower = Lower(Trim(value));
    if (lower == "true" || lower == "1" || lower == "yes" || lower == "on") {
        return true;
    }
    if (lower == "false" || lower == "0" || lower == "no" || lower == "off") {
        return false;
    }
    return fallback;
}

int ParseInt(const std::string& value, int fallback, int minimum, int maximum) {
    try {
        size_t consumed = 0;
        const int parsed = std::stoi(Trim(value), &consumed, 0);
        if (consumed != Trim(value).size()) {
            return fallback;
        }
        return std::max(minimum, std::min(maximum, parsed));
    } catch (...) {
        return fallback;
    }
}

float ParseFloat(const std::string& value, float fallback, float minimum, float maximum) {
    try {
        size_t consumed = 0;
        const std::string trimmed = Trim(value);
        const float parsed = std::stof(trimmed, &consumed);
        if (consumed != trimmed.size()) {
            return fallback;
        }
        return std::max(minimum, std::min(maximum, parsed));
    } catch (...) {
        return fallback;
    }
}

RadarColor ParseColor(const std::string& value, RadarColor fallback) {
    RadarColor result = fallback;
    std::stringstream stream(value);
    std::string component;
    int* components[] = {&result.red, &result.green, &result.blue, &result.alpha};
    int index = 0;
    while (std::getline(stream, component, ',') && index < 4) {
        const int fallbackValue = *components[index];
        *components[index] = ParseInt(component, fallbackValue, 0, 255);
        ++index;
    }
    return index == 4 ? result : fallback;
}

} // namespace

bool Config::Load(const std::string& path) {
    m_warnings.clear();

    std::ifstream file(path);
    if (!file.is_open()) {
        m_warnings.push_back("Configuration file not found; using defaults: " + path);
        return false;
    }

    PolicePursuitRadarSettings loaded;
    std::string section;
    std::string line;
    unsigned int lineNumber = 0;
    while (std::getline(file, line)) {
        ++lineNumber;
        const auto comment = line.find_first_of(";#");
        if (comment != std::string::npos) {
            line.resize(comment);
        }
        line = Trim(line);
        if (line.empty()) {
            continue;
        }
        if (line.front() == '[' && line.back() == ']') {
            section = Lower(Trim(line.substr(1, line.size() - 2)));
            continue;
        }

        const auto separator = line.find('=');
        if (separator == std::string::npos) {
            m_warnings.push_back("Invalid configuration line " + std::to_string(lineNumber));
            continue;
        }
        const std::string key = Lower(Trim(line.substr(0, separator)));
        const std::string value = Trim(line.substr(separator + 1));

        if (section == "general") {
            if (key == "enabled") loaded.enabled = ParseBool(value, loaded.enabled);
            else if (key == "onlywhenwanted") loaded.onlyWhenWanted = ParseBool(value, loaded.onlyWhenWanted);
            else if (key == "showonpausemap") loaded.showOnPauseMap = ParseBool(value, loaded.showOnPauseMap);
            else if (key == "showpursuitstatus") loaded.showPursuitStatus = ParseBool(value, loaded.showPursuitStatus);
        } else if (section == "tracking") {
            if (key == "maxtrackingdistance") loaded.maxTrackingDistance = ParseFloat(value, loaded.maxTrackingDistance, 50.0f, 2500.0f);
            else if (key == "visibilityupdateintervalms") loaded.visibilityUpdateIntervalMs = static_cast<unsigned int>(ParseInt(value, loaded.visibilityUpdateIntervalMs, 16, 2000));
            else if (key == "trackerupdateintervalms") loaded.trackerUpdateIntervalMs = static_cast<unsigned int>(ParseInt(value, loaded.trackerUpdateIntervalMs, 16, 2000));
            else if (key == "lostsightdelayms") loaded.lostSightDelayMs = static_cast<unsigned int>(ParseInt(value, loaded.lostSightDelayMs, 250, 10000));
        } else if (section == "searcharea") {
            if (key == "enabled") loaded.searchAreaEnabled = ParseBool(value, loaded.searchAreaEnabled);
            else if (key == "segments") loaded.searchAreaSegments = static_cast<unsigned int>(ParseInt(value, loaded.searchAreaSegments, 16, 128));
            else if (key.size() == 7 && key.rfind("radius", 0) == 0) {
                const int index = ParseInt(key.substr(6), -1, 1, 6) - 1;
                if (index >= 0 && index < 6) {
                    loaded.searchRadius[static_cast<size_t>(index)] = ParseFloat(value, loaded.searchRadius[static_cast<size_t>(index)], 10.0f, 1500.0f);
                }
            } else if (key == "fillcolor") loaded.searchAreaFill = ParseColor(value, loaded.searchAreaFill);
            else if (key == "bordercolor") loaded.searchAreaBorder = ParseColor(value, loaded.searchAreaBorder);
        } else if (section == "policeblips") {
            if (key == "enabled") loaded.policeBlipsEnabled = ParseBool(value, loaded.policeBlipsEnabled);
            else if (key == "showfootpolice") loaded.showFootPolice = ParseBool(value, loaded.showFootPolice);
            else if (key == "showcars") loaded.showCars = ParseBool(value, loaded.showCars);
            else if (key == "showbikes") loaded.showBikes = ParseBool(value, loaded.showBikes);
            else if (key == "showboats") loaded.showBoats = ParseBool(value, loaded.showBoats);
            else if (key == "showhelicopters") loaded.showHelicopters = ParseBool(value, loaded.showHelicopters);
            else if (key == "showoffradarpolice") loaded.showOffRadarPolice = ParseBool(value, loaded.showOffRadarPolice);
        } else if (section == "visual") {
            if (key == "policecolor") loaded.policeColor = ParseColor(value, loaded.policeColor);
            else if (key == "policevisiblecolor") loaded.policeVisibleColor = ParseColor(value, loaded.policeVisibleColor);
            else if (key == "pulseduringpursuit") loaded.pulseDuringPursuit = ParseBool(value, loaded.pulseDuringPursuit);
            else if (key == "pulsespeed") loaded.pulseSpeed = ParseFloat(value, loaded.pulseSpeed, 0.1f, 10.0f);
        } else if (section == "debug") {
            if (key == "enabled") loaded.debugEnabled = ParseBool(value, loaded.debugEnabled);
            else if (key == "logtrackedunits") loaded.logTrackedUnits = ParseBool(value, loaded.logTrackedUnits);
            else if (key == "showsearchcenter") loaded.showSearchCenter = ParseBool(value, loaded.showSearchCenter);
            else if (key == "showpolicelos") loaded.showPoliceLos = ParseBool(value, loaded.showPoliceLos);
        } else if (section == "input") {
            if (key == "reloadhotkeyenabled") loaded.reloadHotkeyEnabled = ParseBool(value, loaded.reloadHotkeyEnabled);
            else if (key == "reloadhotkey") loaded.reloadHotkey = ParseInt(value, loaded.reloadHotkey, 1, 255);
        }
    }

    m_settings = loaded;
    return true;
}
