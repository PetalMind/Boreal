Scriptname CreatorEnergyMCM extends SKI_ConfigBase

GlobalVariable SoulCaptureEnabled
GlobalVariable FreeBlackGemEnabled
Int optionSoulCapture
Int optionFreeGem

Event OnConfigInit()
    ModName = "Energia Stwórcy"
    Pages = new String[1]
    Pages[0] = "Przechwytywanie dusz"
    LoadSettings()
EndEvent

Event OnPageReset(String page)
    If page != "Przechwytywanie dusz"
        Return
    EndIf

    LoadSettings()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Zachowanie czaru")
    optionSoulCapture = AddToggleOption("Przechwytuj dusze pokonanych przeciwników", IsEnabled(SoulCaptureEnabled))
    optionFreeGem = AddToggleOption("Dodawaj czarny klejnot, gdy brakuje pustego", IsEnabled(FreeBlackGemEnabled))
EndEvent

Event OnOptionSelect(Int option)
    If option == optionSoulCapture
        ToggleSetting(SoulCaptureEnabled)
        SetToggleOptionValue(option, IsEnabled(SoulCaptureEnabled))
    ElseIf option == optionFreeGem
        ToggleSetting(FreeBlackGemEnabled)
        SetToggleOptionValue(option, IsEnabled(FreeBlackGemEnabled))
    EndIf
EndEvent

Function LoadSettings()
    SoulCaptureEnabled = Game.GetFormFromFile(0x808, "CreatorEnergy.esp") as GlobalVariable
    FreeBlackGemEnabled = Game.GetFormFromFile(0x809, "CreatorEnergy.esp") as GlobalVariable
EndFunction

Bool Function IsEnabled(GlobalVariable setting)
    Return setting == None || setting.GetValue() >= 0.5
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
