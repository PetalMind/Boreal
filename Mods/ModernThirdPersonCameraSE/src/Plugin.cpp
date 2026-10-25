#include "PCH.h"

#include "CameraController.h"

namespace {
	void OnSKSEMessage(SKSE::MessagingInterface::Message* a_message)
	{
		if (a_message && a_message->type == SKSE::MessagingInterface::kDataLoaded) {
			CameraController::Install();
		}
	}

	void InitializeLogging()
	{
		auto logsFolder = SKSE::log::log_directory();
		if (!logsFolder) {
			SKSE::stl::report_and_fail("SKSE log directory is unavailable");
		}
		std::filesystem::create_directories(*logsFolder);
		auto logFile = *logsFolder / "ModernThirdPersonCameraSE.log";
		auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(logFile.string(), true);
		auto logger = std::make_shared<spdlog::logger>("ModernThirdPersonCameraSE", std::move(sink));
		spdlog::set_default_logger(std::move(logger));
		spdlog::set_level(spdlog::level::info);
		spdlog::flush_on(spdlog::level::warn);
	}
}

SKSEPluginLoad(const SKSE::LoadInterface* a_skse)
{
	SKSE::Init(a_skse);
	InitializeLogging();
	SKSE::log::info("Modern Third Person Camera SE loaded");
	SKSE::GetMessagingInterface()->RegisterListener(OnSKSEMessage);
	return true;
}
