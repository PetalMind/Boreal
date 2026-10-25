#include "PCH.h"

#include "QuestData.h"

namespace {
	struct TrackedQuest
	{
		RE::TESQuest* quest;
		std::vector<std::string_view> objectives;
	};

	std::string EscapeHTML(std::string_view a_text)
	{
		std::string escaped;
		escaped.reserve(a_text.size());

		for (const char character : a_text) {
			switch (character) {
			case '&':
				escaped += "&amp;";
				break;
			case '<':
				escaped += "&lt;";
				break;
			case '>':
				escaped += "&gt;";
				break;
			case '\r':
				break;
			case '\n':
				escaped += "<br/>";
				break;
			default:
				escaped += character;
				break;
			}
		}
		return escaped;
	}

	std::string_view SafeView(const char* a_text)
	{
		return a_text ? std::string_view(a_text) : std::string_view{};
	}
}

RE::BSFixedString QuestData::GetTrackedQuestHTML(RE::StaticFunctionTag*, std::int32_t a_maxQuests)
{
	const auto dataHandler = RE::TESDataHandler::GetSingleton();
	if (!dataHandler) {
		return {};
	}

	std::vector<TrackedQuest> trackedQuests;
	for (auto* quest : dataHandler->GetFormArray<RE::TESQuest>()) {
		if (!quest || !quest->IsActive() || quest->IsCompleted()) {
			continue;
		}

		TrackedQuest trackedQuest{ quest, {} };
		for (const auto* objective : quest->objectives) {
			if (objective && objective->state == RE::QUEST_OBJECTIVE_STATE::kDisplayed) {
				const auto text = SafeView(objective->displayText.c_str());
				if (!text.empty()) {
					trackedQuest.objectives.emplace_back(text);
				}
			}
		}
		if (!trackedQuest.objectives.empty()) {
			trackedQuests.push_back(std::move(trackedQuest));
		}
	}
	std::stable_sort(trackedQuests.begin(), trackedQuests.end(), [](const auto& a_left, const auto& a_right) {
		if (a_left.quest->data.priority != a_right.quest->data.priority) {
			return a_left.quest->data.priority > a_right.quest->data.priority;
		}
		return a_left.quest->GetFormID() < a_right.quest->GetFormID();
	});

	const auto maximum = static_cast<std::size_t>(std::clamp(a_maxQuests, 1, 12));
	std::string html;
	html.reserve(maximum * 256);
	std::size_t displayedCount = 0;

	for (const auto& trackedQuest : trackedQuests) {
		if (displayedCount >= maximum) {
			break;
		}

		const auto title = SafeView(trackedQuest.quest->GetFullName());
		if (!title.empty()) {
			html += "<font face='$EverywhereBoldFont' size='17' color='#E6D6B4'><b>";
			html += EscapeHTML(title);
			html += "</b></font><br/>";
		}
		++displayedCount;

		for (const auto text : trackedQuest.objectives) {
			html += "<font face='$EverywhereFont' size='15' color='#FFFFFF'>&#8226; ";
			html += EscapeHTML(text);
			html += "</font><br/>";
		}
	}

	return RE::BSFixedString(html.c_str());
}
