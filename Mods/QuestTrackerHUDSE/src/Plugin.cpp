#include "PCH.h"

#include "QuestData.h"

namespace {
	void StartControllerQuest(SKSE::MessagingInterface::Message* a_message)
	{
		if (!a_message || a_message->type != SKSE::MessagingInterface::kDataLoaded) {
			return;
		}

		const auto dataHandler = RE::TESDataHandler::GetSingleton();
		const auto quest = dataHandler ? dataHandler->LookupForm<RE::TESQuest>(0x800, "QuestTrackerHUDSE.esp") : nullptr;
		if (quest && !quest->IsRunning()) {
			quest->Start();
		}
	}

	bool RegisterPapyrus(RE::BSScript::IVirtualMachine* a_vm)
	{
		if (!a_vm) {
			return false;
		}
		a_vm->RegisterFunction("GetTrackedQuestHTML", "QuestTrackerNative", QuestData::GetTrackedQuestHTML);
		return true;
	}
}

SKSEPluginLoad(const SKSE::LoadInterface* a_skse)
{
	SKSE::Init(a_skse);
	const auto papyrus = SKSE::GetPapyrusInterface();
	const auto messaging = SKSE::GetMessagingInterface();
	return papyrus && messaging && papyrus->Register(RegisterPapyrus) && messaging->RegisterListener(StartControllerQuest);
}
