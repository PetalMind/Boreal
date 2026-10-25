#pragma once

#include <filesystem>

struct CameraOffset {
	float x{};
	float y{};
	float z{};
};

struct CameraConfig {
	bool enabled{ true };
	CameraOffset normal{ 18.0F, 0.0F, 2.0F };
	CameraOffset combat{ 24.0F, 8.0F, 2.0F };
	CameraOffset bow{ 14.0F, 10.0F, 1.0F };
	float normalFOV{ 74.0F };
	float combatFOV{ 78.0F };
	float bowFOV{ 68.0F };
	float fovResponse{ 3.5F };
	float zoomSensitivity{ 1.0F };
	bool autoRecenter{ true };
	float recenterDelay{ 1.1F };
	float recenterResponse{ 2.4F };
};

CameraConfig LoadCameraConfig(const std::filesystem::path& a_path);
