Scriptname QuestTrackerMCM extends SKI_ConfigBase

GlobalVariable EnabledSetting
GlobalVariable HorizontalPosition
GlobalVariable VerticalPosition
GlobalVariable PanelWidth
GlobalVariable PanelOpacity
GlobalVariable MaximumQuests

Int optionEnabled
Int optionX
Int optionY
Int optionWidth
Int optionOpacity
Int optionMaximum

Event OnConfigInit()
    ModName = "Quest Tracker HUD SE"
    Pages = new String[1]
    Pages[0] = "Lista zadań"
    LoadSettings()
EndEvent

Event OnPageReset(String page)
    If page != "Lista zadań"
        Return
    EndIf

    LoadSettings()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Widok zadań")
    optionEnabled = AddToggleOption("Pokaż listę zaznaczonych zadań", IsEnabled())
    optionMaximum = AddSliderOption("Liczba zadań", GetValue(MaximumQuests, 6.0), "{0}")

    AddHeaderOption("Położenie i wygląd")
    optionX = AddSliderOption("Pozycja pozioma", GetValue(HorizontalPosition, 850.0), "{0}")
    optionY = AddSliderOption("Pozycja pionowa", GetValue(VerticalPosition, 220.0), "{0}")
    optionWidth = AddSliderOption("Szerokość listy", GetValue(PanelWidth, 360.0), "{0}")
    optionOpacity = AddSliderOption("Krycie", GetValue(PanelOpacity, 88.0), "{0}%")
EndEvent

Event OnOptionSelect(Int option)
    If option != optionEnabled
        Return
    EndIf

    If EnabledSetting != None
        EnabledSetting.SetValue(0.0 - EnabledSetting.GetValue() + 1.0)
    EndIf
    SetToggleOptionValue(optionEnabled, IsEnabled())
    ApplyControllerSettings()
EndEvent

Event OnOptionSliderOpen(Int option)
    If option == optionX
        SetSliderDialogStartValue(GetValue(HorizontalPosition, 850.0))
        SetSliderDialogDefaultValue(850.0)
        SetSliderDialogRange(0.0, 1280.0 - GetValue(PanelWidth, 360.0))
        SetSliderDialogInterval(16.0)
    ElseIf option == optionY
        SetSliderDialogStartValue(GetValue(VerticalPosition, 220.0))
        SetSliderDialogDefaultValue(220.0)
        SetSliderDialogRange(0.0, 720.0)
        SetSliderDialogInterval(12.0)
    ElseIf option == optionWidth
        SetSliderDialogStartValue(GetValue(PanelWidth, 360.0))
        SetSliderDialogDefaultValue(360.0)
        SetSliderDialogRange(240.0, 640.0)
        SetSliderDialogInterval(16.0)
    ElseIf option == optionOpacity
        SetSliderDialogStartValue(GetValue(PanelOpacity, 88.0))
        SetSliderDialogDefaultValue(88.0)
        SetSliderDialogRange(30.0, 100.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == optionMaximum
        SetSliderDialogStartValue(GetValue(MaximumQuests, 6.0))
        SetSliderDialogDefaultValue(6.0)
        SetSliderDialogRange(1.0, 12.0)
        SetSliderDialogInterval(1.0)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    If option == optionX
        SetValue(HorizontalPosition, value)
        SetSliderOptionValue(option, value, "{0}")
    ElseIf option == optionY
        SetValue(VerticalPosition, value)
        SetSliderOptionValue(option, value, "{0}")
    ElseIf option == optionWidth
        SetValue(PanelWidth, value)
        SetSliderOptionValue(option, value, "{0}")
    ElseIf option == optionOpacity
        SetValue(PanelOpacity, value)
        SetSliderOptionValue(option, value, "{0}%")
    ElseIf option == optionMaximum
        SetValue(MaximumQuests, value)
        SetSliderOptionValue(option, value, "{0}")
    Else
        Return
    EndIf

    ApplyControllerSettings()
EndEvent

Function LoadSettings()
    EnabledSetting = Game.GetFormFromFile(0x801, "QuestTrackerHUDSE.esp") as GlobalVariable
    HorizontalPosition = Game.GetFormFromFile(0x802, "QuestTrackerHUDSE.esp") as GlobalVariable
    VerticalPosition = Game.GetFormFromFile(0x803, "QuestTrackerHUDSE.esp") as GlobalVariable
    PanelWidth = Game.GetFormFromFile(0x804, "QuestTrackerHUDSE.esp") as GlobalVariable
    PanelOpacity = Game.GetFormFromFile(0x805, "QuestTrackerHUDSE.esp") as GlobalVariable
    MaximumQuests = Game.GetFormFromFile(0x806, "QuestTrackerHUDSE.esp") as GlobalVariable
EndFunction

Bool Function IsEnabled()
    Return EnabledSetting == None || EnabledSetting.GetValue() >= 0.5
EndFunction

Float Function GetValue(GlobalVariable setting, Float fallback)
    If setting == None
        Return fallback
    EndIf
    Return setting.GetValue()
EndFunction

Function SetValue(GlobalVariable setting, Float value)
    If setting != None
        setting.SetValue(value)
    EndIf
EndFunction

Function ApplyControllerSettings()
    QuestTrackerController controller = Game.GetFormFromFile(0x800, "QuestTrackerHUDSE.esp") as QuestTrackerController
    If controller != None
        controller.ApplySettings()
    EndIf
EndFunction
