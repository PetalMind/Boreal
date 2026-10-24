Scriptname NordicMinimalUIMCM extends SKI_ConfigBase

GlobalVariable FadeSeconds
GlobalVariable BarsEnabled
GlobalVariable CompassEnabled
Int optionFade
Int optionBars
Int optionCompass

Event OnConfigInit()
    ModName = "Nordic Minimal UI"
    Pages = new String[1]
    Pages[0] = "HUD i dialogi"
    LoadSettings()
EndEvent

Event OnPageReset(String page)
    If page != "HUD i dialogi"
        Return
    EndIf
    LoadSettings()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Minimalistyczny HUD")
    optionFade = AddSliderOption("Czas zanikania pasków", GetValue(FadeSeconds, 5.0), "{0} s")
    optionBars = AddToggleOption("Paski widoczne po zmianie", IsEnabled(BarsEnabled))
    optionCompass = AddToggleOption("Kompas zawsze widoczny", IsEnabled(CompassEnabled))
EndEvent

Event OnOptionSelect(Int option)
    If option == optionBars
        ToggleSetting(BarsEnabled)
        UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicBarsEnabled", IsEnabled(BarsEnabled))
        SetToggleOptionValue(option, IsEnabled(BarsEnabled))
    ElseIf option == optionCompass
        ToggleSetting(CompassEnabled)
        UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicCompassEnabled", IsEnabled(CompassEnabled))
        SetToggleOptionValue(option, IsEnabled(CompassEnabled))
    EndIf
EndEvent

Event OnOptionSliderOpen(Int option)
    If option == optionFade
        SetSliderDialogStartValue(GetValue(FadeSeconds, 5.0))
        SetSliderDialogDefaultValue(5.0)
        SetSliderDialogRange(1.0, 10.0)
        SetSliderDialogInterval(1.0)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    If option == optionFade
        SetValue(FadeSeconds, value)
        UI.InvokeFloat("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicFadeDelay", value)
        SetSliderOptionValue(option, value, "{0} s")
    EndIf
EndEvent

Function LoadSettings()
    FadeSeconds = Game.GetFormFromFile(0x801, "NordicMinimalUISE.esp") as GlobalVariable
    BarsEnabled = Game.GetFormFromFile(0x802, "NordicMinimalUISE.esp") as GlobalVariable
    CompassEnabled = Game.GetFormFromFile(0x803, "NordicMinimalUISE.esp") as GlobalVariable
EndFunction

Float Function GetValue(GlobalVariable setting, Float fallback)
    If setting == None
        Return fallback
    EndIf
    Return setting.GetValue()
EndFunction

Bool Function IsEnabled(GlobalVariable setting)
    Return setting != None && setting.GetValue() >= 0.5
EndFunction

Function ToggleSetting(GlobalVariable setting)
    If setting == None
        Return
    EndIf
    If IsEnabled(setting)
        setting.SetValue(0.0)
    Else
        setting.SetValue(1.0)
    EndIf
EndFunction

Function SetValue(GlobalVariable setting, Float value)
    If setting != None
        setting.SetValue(value)
    EndIf
EndFunction
