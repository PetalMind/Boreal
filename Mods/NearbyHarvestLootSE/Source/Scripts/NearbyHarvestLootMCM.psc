Scriptname NearbyHarvestLootMCM extends SKI_ConfigBase

GlobalVariable HarvestPlantsSetting
GlobalVariable LootNearbyCorpsesSetting
GlobalVariable SearchRadiusSetting
Int optionHarvestPlants
Int optionLootNearbyCorpses
Int optionSearchRadius

Event OnConfigInit()
    ModName = "Nearby Harvest & Loot SE"
    Pages = new String[1]
    Pages[0] = "Ustawienia"
    LoadSettings()
EndEvent

Event OnConfigOpen()
    NearbyHarvestLootQuest controller = Game.GetFormFromFile(0x800, "NearbyHarvestLootSE.esp") as NearbyHarvestLootQuest
    If controller != None
        controller.Maintenance()
    EndIf
EndEvent

Event OnPageReset(String page)
    If page != "Ustawienia"
        Return
    EndIf

    LoadSettings()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Zbieranie i łupienie")
    optionHarvestPlants = AddToggleOption("Zbieraj pobliskie rośliny", IsEnabled(HarvestPlantsSetting))
    optionLootNearbyCorpses = AddToggleOption("Zbieraj łup z pobliskich zwłok", IsEnabled(LootNearbyCorpsesSetting))
    AddHeaderOption("Zasięg")
    optionSearchRadius = AddSliderOption("Promień działania", GetSearchRadius(), "{0} j.u.")
EndEvent

Event OnOptionSelect(Int option)
    If option == optionHarvestPlants
        ToggleSetting(HarvestPlantsSetting)
        SetToggleOptionValue(option, IsEnabled(HarvestPlantsSetting))
    ElseIf option == optionLootNearbyCorpses
        ToggleSetting(LootNearbyCorpsesSetting)
        SetToggleOptionValue(option, IsEnabled(LootNearbyCorpsesSetting))
    EndIf
EndEvent

Event OnOptionSliderOpen(Int option)
    If option == optionSearchRadius
        SetSliderDialogStartValue(GetSearchRadius())
        SetSliderDialogDefaultValue(512.0)
        SetSliderDialogRange(128.0, 2048.0)
        SetSliderDialogInterval(128.0)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    If option == optionSearchRadius
        SetSettingValue(SearchRadiusSetting, value)
        SetSliderOptionValue(option, value, "{0} j.u.")
    EndIf
EndEvent

Function LoadSettings()
    HarvestPlantsSetting = Game.GetFormFromFile(0x801, "NearbyHarvestLootSE.esp") as GlobalVariable
    LootNearbyCorpsesSetting = Game.GetFormFromFile(0x802, "NearbyHarvestLootSE.esp") as GlobalVariable
    SearchRadiusSetting = Game.GetFormFromFile(0x803, "NearbyHarvestLootSE.esp") as GlobalVariable
EndFunction

Float Function GetSearchRadius()
    If SearchRadiusSetting == None
        Return 512.0
    EndIf
    Return SearchRadiusSetting.GetValue()
EndFunction

Bool Function IsEnabled(GlobalVariable setting)
    Return setting != None && setting.GetValue() >= 0.5
EndFunction

Function ToggleSetting(GlobalVariable setting)
    If setting == None
        Return
    EndIf
    If setting.GetValue() >= 0.5
        setting.SetValue(0.0)
    Else
        setting.SetValue(1.0)
    EndIf
EndFunction

Function SetSettingValue(GlobalVariable setting, Float value)
    If setting != None
        setting.SetValue(value)
    EndIf
EndFunction
