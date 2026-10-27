#include "PCH.h"

#include "CameraController.h"

#include "Config.h"

#include "RE/T/TESGlobal.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <numbers>

namespace {
	using Clock = std::chrono::steady_clock;
	using CameraUpdateFn = void (*)(RE::PlayerCamera*);
	using HandleLookInputFn = void (*)(RE::ThirdPersonState*, const RE::NiPoint2&);

	CameraUpdateFn originalCameraUpdate{};
	HandleLookInputFn originalHandleLookInput{};
	CameraConfig config{};
	Clock::time_point lastManualLook = Clock::now();
	Clock::time_point lastCameraUpdate = Clock::now();
	Clock::time_point lastMCMConfigRefresh{};
	float baseWorldFOV{};
	float currentWorldFOV{};
	bool hasBaseWorldFOV{};
	bool hasCurrentWorldFOV{};
	bool settingsCaptured{};

	struct SettingSnapshot {
		std::string_view name;
		RE::Setting* setting{};
		float original{};
	};

	std::array<SettingSnapshot, 5> cameraSettings{{
		{ "fOverShoulderPosX:Camera" },
		{ "fOverShoulderPosZ:Camera" },
		{ "fOverShoulderCombatPosX:Camera" },
		{ "fOverShoulderCombatAddY:Camera" },
		{ "fOverShoulderCombatPosZ:Camera" }
	}};

	void RefreshMCMConfig(Clock::time_point a_now)
	{
		if (a_now - lastMCMConfigRefresh < std::chrono::milliseconds(250)) {
			return;
		}
		lastMCMConfigRefresh = a_now;

		auto* dataHandler = RE::TESDataHandler::GetSingleton();
		if (!dataHandler) {
			return;
		}
		const auto* overrides = dataHandler->LookupForm<RE::TESGlobal>(0x812, "ModernThirdPersonCameraSE.esp");
		if (!overrides || overrides->value < 0.5F) {
			return;
		}

		auto readFloat = [dataHandler](std::uint32_t a_formID, float a_fallback, float a_minimum, float a_maximum) {
			const auto* setting = dataHandler->LookupForm<RE::TESGlobal>(a_formID, "ModernThirdPersonCameraSE.esp");
			if (!setting || !std::isfinite(setting->value)) {
				return a_fallback;
			}
			return std::clamp(setting->value, a_minimum, a_maximum);
		};
		auto readBool = [dataHandler](std::uint32_t a_formID, bool a_fallback) {
			const auto* setting = dataHandler->LookupForm<RE::TESGlobal>(a_formID, "ModernThirdPersonCameraSE.esp");
			return setting ? setting->value >= 0.5F : a_fallback;
		};

		config.enabled = readBool(0x801, config.enabled);
		config.normal.x = readFloat(0x802, config.normal.x, -40.0F, 40.0F);
		config.normal.z = readFloat(0x803, config.normal.z, -30.0F, 30.0F);
		config.combat.x = readFloat(0x804, config.combat.x, -40.0F, 40.0F);
		config.combat.y = readFloat(0x805, config.combat.y, -40.0F, 40.0F);
		config.combat.z = readFloat(0x806, config.combat.z, -30.0F, 30.0F);
		config.bow.x = readFloat(0x807, config.bow.x, -40.0F, 40.0F);
		config.bow.y = readFloat(0x808, config.bow.y, -40.0F, 40.0F);
		config.bow.z = readFloat(0x809, config.bow.z, -30.0F, 30.0F);
		config.normalFOV = readFloat(0x80A, config.normalFOV, 50.0F, 110.0F);
		config.combatFOV = readFloat(0x80B, config.combatFOV, 50.0F, 110.0F);
		config.bowFOV = readFloat(0x80C, config.bowFOV, 50.0F, 110.0F);
		config.fovResponse = readFloat(0x80D, config.fovResponse, 0.1F, 20.0F);
		config.zoomSensitivity = readFloat(0x80E, config.zoomSensitivity, 0.1F, 3.0F);
		config.autoRecenter = readBool(0x80F, config.autoRecenter);
		config.recenterDelay = readFloat(0x810, config.recenterDelay, 0.0F, 10.0F);
		config.recenterResponse = readFloat(0x811, config.recenterResponse, 0.1F, 12.0F);
	}

	void SetMCMGlobal(RE::TESDataHandler* a_dataHandler, std::uint32_t a_formID, float a_value)
	{
		if (auto* setting = a_dataHandler->LookupForm<RE::TESGlobal>(a_formID, "ModernThirdPersonCameraSE.esp")) {
			setting->value = a_value;
		}
	}

	void SeedMCMSettingsFromINI()
	{
		auto* dataHandler = RE::TESDataHandler::GetSingleton();
		if (!dataHandler) {
			return;
		}
		const auto* overrides = dataHandler->LookupForm<RE::TESGlobal>(0x812, "ModernThirdPersonCameraSE.esp");
		if (!overrides || overrides->value >= 0.5F) {
			return;
		}

		SetMCMGlobal(dataHandler, 0x801, config.enabled ? 1.0F : 0.0F);
		SetMCMGlobal(dataHandler, 0x802, config.normal.x);
		SetMCMGlobal(dataHandler, 0x803, config.normal.z);
		SetMCMGlobal(dataHandler, 0x804, config.combat.x);
		SetMCMGlobal(dataHandler, 0x805, config.combat.y);
		SetMCMGlobal(dataHandler, 0x806, config.combat.z);
		SetMCMGlobal(dataHandler, 0x807, config.bow.x);
		SetMCMGlobal(dataHandler, 0x808, config.bow.y);
		SetMCMGlobal(dataHandler, 0x809, config.bow.z);
		SetMCMGlobal(dataHandler, 0x80A, config.normalFOV);
		SetMCMGlobal(dataHandler, 0x80B, config.combatFOV);
		SetMCMGlobal(dataHandler, 0x80C, config.bowFOV);
		SetMCMGlobal(dataHandler, 0x80D, config.fovResponse);
		SetMCMGlobal(dataHandler, 0x80E, config.zoomSensitivity);
		SetMCMGlobal(dataHandler, 0x80F, config.autoRecenter ? 1.0F : 0.0F);
		SetMCMGlobal(dataHandler, 0x810, config.recenterDelay);
		SetMCMGlobal(dataHandler, 0x811, config.recenterResponse);
	}

	enum class Profile {
		kNormal,
		kCombat,
		kBow
	};

	float SmoothFactor(float a_response, float a_deltaTime)
	{
		return std::clamp(1.0F - std::exp(-a_response * a_deltaTime), 0.0F, 1.0F);
	}

	float WrapAngle(float a_angle)
	{
		constexpr float tau = std::numbers::pi_v<float> * 2.0F;
		return std::remainder(a_angle, tau);
	}

	float ShortestAngleDelta(float a_from, float a_to)
	{
		return std::remainder(a_to - a_from, std::numbers::pi_v<float> * 2.0F);
	}

	bool CaptureCameraSettings()
	{
		auto* collection = RE::INISettingCollection::GetSingleton();
		if (!collection) {
			return false;
		}

		for (auto& entry : cameraSettings) {
			entry.setting = collection->GetSetting(entry.name);
			if (!entry.setting || entry.setting->GetType() != RE::Setting::Type::kFloat) {
				SKSE::log::error("Missing float camera setting: {}", entry.name);
				return false;
			}
			entry.original = entry.setting->GetFloat();
		}
		settingsCaptured = true;
		return true;
	}

	void RestoreCameraSettings()
	{
		if (!settingsCaptured) {
			return;
		}
		for (const auto& entry : cameraSettings) {
			entry.setting->data.f = entry.original;
		}
	}

	Profile GetProfile(const RE::PlayerCharacter* a_player, const RE::PlayerCamera* a_camera)
	{
		if (a_player && a_camera && a_camera->bowZoomedIn) {
			const auto* form = a_player->GetEquippedObject(false);
			const auto* weapon = form ? form->As<RE::TESObjectWEAP>() : nullptr;
			if (weapon && (weapon->IsBow() || weapon->IsCrossbow())) {
				return Profile::kBow;
			}
		}
		return a_player && a_player->IsInCombat() ? Profile::kCombat : Profile::kNormal;
	}

	void ApplyCameraProfile(Profile a_profile)
	{
		if (!settingsCaptured) {
			return;
		}
		RestoreCameraSettings();

		const CameraOffset* offset = nullptr;
		switch (a_profile) {
		case Profile::kNormal:
			offset = &config.normal;
			cameraSettings[0].setting->data.f += offset->x;
			cameraSettings[1].setting->data.f += offset->z;
			break;
		case Profile::kCombat:
			offset = &config.combat;
			cameraSettings[2].setting->data.f += offset->x;
			cameraSettings[3].setting->data.f += offset->y;
			cameraSettings[4].setting->data.f += offset->z;
			break;
		case Profile::kBow:
			offset = &config.bow;
			cameraSettings[2].setting->data.f += offset->x;
			cameraSettings[3].setting->data.f += offset->y;
			cameraSettings[4].setting->data.f += offset->z;
			break;
		}
	}

	float GetProfileFOV(Profile a_profile)
	{
		switch (a_profile) {
		case Profile::kNormal:
			return config.normalFOV;
		case Profile::kCombat:
			return config.combatFOV;
		case Profile::kBow:
			return config.bowFOV;
		}
		return config.normalFOV;
	}

	void RecenterCamera(RE::PlayerCharacter* a_player, RE::PlayerCamera* a_camera, RE::ThirdPersonState* a_state, float a_deltaTime, Clock::time_point a_now)
	{
		if (!config.autoRecenter || !a_player || !a_camera || !a_state || a_camera->bowZoomedIn || a_state->freeRotationEnabled || a_state->stateNotActive) {
			return;
		}
		if (std::chrono::duration<float>(a_now - lastManualLook).count() < config.recenterDelay) {
			return;
		}

		const float targetYaw = WrapAngle(a_player->data.angle.z + std::numbers::pi_v<float>);
		const float amount = SmoothFactor(config.recenterResponse, a_deltaTime);
		const float yawDelta = ShortestAngleDelta(a_state->currentYaw, targetYaw);
		if (std::abs(yawDelta) < 0.001F) {
			a_state->currentYaw = targetYaw;
			a_state->targetYaw = targetYaw;
			return;
		}

		a_state->targetYaw = targetYaw;
		a_state->currentYaw = WrapAngle(a_state->currentYaw + yawDelta * amount);
		a_state->UpdateRotation();
	}

	void CameraUpdateHook(RE::PlayerCamera* a_camera)
	{
		if (!originalCameraUpdate || !a_camera) {
			return;
		}

		const auto now = Clock::now();
		RefreshMCMConfig(now);
		const float deltaTime = std::clamp(std::chrono::duration<float>(now - lastCameraUpdate).count(), 0.001F, 0.05F);
		lastCameraUpdate = now;

		auto* currentState = a_camera->currentState.get();
		auto* state = currentState && currentState->id == RE::CameraState::kThirdPerson ?
		                   static_cast<RE::ThirdPersonState*>(currentState) :
		                   nullptr;
		auto* player = RE::PlayerCharacter::GetSingleton();
		const bool active = config.enabled && settingsCaptured && state && player;

		if (active) {
			const auto profile = GetProfile(player, a_camera);
			ApplyCameraProfile(profile);
			if (!hasBaseWorldFOV) {
				baseWorldFOV = a_camera->worldFOV;
				hasBaseWorldFOV = true;
			}
			if (!hasCurrentWorldFOV) {
				currentWorldFOV = baseWorldFOV;
				hasCurrentWorldFOV = true;
			}
			a_camera->zoomInput *= config.zoomSensitivity;
			originalCameraUpdate(a_camera);

			const float amount = SmoothFactor(config.fovResponse, deltaTime);
			const float targetFOV = GetProfileFOV(profile);
			currentWorldFOV += (targetFOV - currentWorldFOV) * amount;
			a_camera->worldFOV = currentWorldFOV;

			auto* updatedState = a_camera->currentState.get();
			if (updatedState && updatedState->id == RE::CameraState::kThirdPerson) {
				RecenterCamera(player, a_camera, static_cast<RE::ThirdPersonState*>(updatedState), deltaTime, now);
			}
			return;
		}

		RestoreCameraSettings();
		originalCameraUpdate(a_camera);
		if (hasBaseWorldFOV) {
			a_camera->worldFOV = baseWorldFOV;
			currentWorldFOV = baseWorldFOV;
			hasCurrentWorldFOV = true;
		}
	}

	void HandleLookInputHook(RE::ThirdPersonState* a_state, const RE::NiPoint2& a_input)
	{
		if (std::abs(a_input.x) > 0.001F || std::abs(a_input.y) > 0.001F) {
			lastManualLook = Clock::now();
		}
		if (originalHandleLookInput) {
			originalHandleLookInput(a_state, a_input);
		}
	}

	void InitializeConfig()
	{
		const auto configPath = std::filesystem::current_path() / "Data" / "SKSE" / "Plugins" / "ModernThirdPersonCameraSE.ini";
		config = LoadCameraConfig(configPath);
		SeedMCMSettingsFromINI();
		SKSE::log::info("Loaded camera settings from {}", configPath.string());
	}
}

namespace CameraController {
	void Install()
	{
		InitializeConfig();
		if (!CaptureCameraSettings()) {
			SKSE::log::error("Camera settings could not be captured; camera hooks were not installed");
			return;
		}

		REL::Relocation<std::uintptr_t> cameraVTable{ RE::VTABLE_PlayerCamera[0] };
		originalCameraUpdate = reinterpret_cast<CameraUpdateFn>(cameraVTable.write_vfunc(2, CameraUpdateHook));

		REL::Relocation<std::uintptr_t> stateVTable{ RE::VTABLE_ThirdPersonState[0] };
		originalHandleLookInput = reinterpret_cast<HandleLookInputFn>(stateVTable.write_vfunc(0x0F, HandleLookInputHook));

		SKSE::log::info("Third-person camera hooks installed");
	}
}
