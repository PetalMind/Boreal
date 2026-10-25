#include "PCH.h"

#include "Config.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <fstream>
#include <string>
#include <unordered_map>

namespace {
	std::string Trim(std::string a_value)
	{
		a_value.erase(a_value.begin(), std::find_if(a_value.begin(), a_value.end(), [](unsigned char a_char) {
			return !std::isspace(a_char);
		}));
		a_value.erase(std::find_if(a_value.rbegin(), a_value.rend(), [](unsigned char a_char) {
			return !std::isspace(a_char);
		}).base(), a_value.end());
		return a_value;
	}

	std::unordered_map<std::string, std::string> ReadCameraSection(const std::filesystem::path& a_path)
	{
		std::unordered_map<std::string, std::string> values;
		std::ifstream input(a_path);
		if (!input) {
			return values;
		}

		bool inCameraSection = false;
		std::string line;
		while (std::getline(input, line)) {
			line = Trim(std::move(line));
			if (line.empty() || line.front() == ';' || line.front() == '#') {
				continue;
			}
			if (line.front() == '[' && line.back() == ']') {
				inCameraSection = line.substr(1, line.size() - 2) == "Camera";
				continue;
			}
			if (!inCameraSection) {
				continue;
			}

			const auto separator = line.find('=');
			if (separator == std::string::npos) {
				continue;
			}
			values.insert_or_assign(Trim(line.substr(0, separator)), Trim(line.substr(separator + 1)));
		}
		return values;
	}

	float ReadFloat(const std::unordered_map<std::string, std::string>& a_values, std::string_view a_key, float a_default, float a_min, float a_max)
	{
		const auto it = a_values.find(std::string(a_key));
		if (it == a_values.end()) {
			return a_default;
		}
		try {
			std::size_t parsedCharacters = 0;
			const float value = std::stof(it->second, &parsedCharacters);
			if (parsedCharacters != it->second.size() || !std::isfinite(value)) {
				return a_default;
			}
			return std::clamp(value, a_min, a_max);
		} catch (...) {
			return a_default;
		}
	}

	bool ReadBool(const std::unordered_map<std::string, std::string>& a_values, std::string_view a_key, bool a_default)
	{
		const auto it = a_values.find(std::string(a_key));
		if (it == a_values.end()) {
			return a_default;
		}
		std::string value = it->second;
		std::transform(value.begin(), value.end(), value.begin(), [](unsigned char a_char) {
			return static_cast<char>(std::tolower(a_char));
		});
		if (value == "true" || value == "1" || value == "yes" || value == "on") {
			return true;
		}
		if (value == "false" || value == "0" || value == "no" || value == "off") {
			return false;
		}
		return a_default;
	}
}

CameraConfig LoadCameraConfig(const std::filesystem::path& a_path)
{
	const auto values = ReadCameraSection(a_path);
	CameraConfig config;
	config.enabled = ReadBool(values, "Enabled", config.enabled);
	config.normal.x = ReadFloat(values, "NormalShoulderX", config.normal.x, -40.0F, 40.0F);
	config.normal.z = ReadFloat(values, "NormalShoulderZ", config.normal.z, -30.0F, 30.0F);
	config.combat.x = ReadFloat(values, "CombatShoulderX", config.combat.x, -40.0F, 40.0F);
	config.combat.y = ReadFloat(values, "CombatAddY", config.combat.y, -40.0F, 40.0F);
	config.combat.z = ReadFloat(values, "CombatShoulderZ", config.combat.z, -30.0F, 30.0F);
	config.bow.x = ReadFloat(values, "BowShoulderX", config.bow.x, -40.0F, 40.0F);
	config.bow.y = ReadFloat(values, "BowAddY", config.bow.y, -40.0F, 40.0F);
	config.bow.z = ReadFloat(values, "BowShoulderZ", config.bow.z, -30.0F, 30.0F);
	config.normalFOV = ReadFloat(values, "NormalFOV", config.normalFOV, 50.0F, 110.0F);
	config.combatFOV = ReadFloat(values, "CombatFOV", config.combatFOV, 50.0F, 110.0F);
	config.bowFOV = ReadFloat(values, "BowFOV", config.bowFOV, 50.0F, 110.0F);
	config.fovResponse = ReadFloat(values, "FOVResponse", config.fovResponse, 0.1F, 20.0F);
	config.zoomSensitivity = ReadFloat(values, "ZoomSensitivity", config.zoomSensitivity, 0.1F, 3.0F);
	config.autoRecenter = ReadBool(values, "AutoRecenter", config.autoRecenter);
	config.recenterDelay = ReadFloat(values, "RecenterDelay", config.recenterDelay, 0.0F, 10.0F);
	config.recenterResponse = ReadFloat(values, "RecenterResponse", config.recenterResponse, 0.1F, 12.0F);
	return config;
}
