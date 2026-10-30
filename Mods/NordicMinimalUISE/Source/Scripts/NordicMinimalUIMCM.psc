Scriptname NordicMinimalUIMCM extends SKI_ConfigBase

GlobalVariable FadeSeconds
GlobalVariable BarsEnabled
GlobalVariable CompassEnabled
GlobalVariable DotSize
GlobalVariable DotOpacity
GlobalVariable DotMotion
GlobalVariable RouteKeyCode
Int optionDotSize
Int optionDotOpacity
Int optionDotMotion
Int optionFade
Int optionBars
Int optionCompass
Int optionRouteKey
Int DefaultRouteKey = 35

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
    AddHeaderOption("Celownik")
    optionDotSize = AddSliderOption("Rozmiar kropki", GetValue(DotSize, 100.0), "{0}%")
    optionDotOpacity = AddSliderOption("Krycie kropki", GetValue(DotOpacity, 100.0), "{0}%")
    optionDotMotion = AddToggleOption("Delikatna animacja kropki", IsEnabled(DotMotion))
    AddHeaderOption("Nawigacja")
    optionRouteKey = AddKeyMapOption("Klawisz Jasnowidzenia", GetRouteKey())
EndEvent

Event OnOptionSelect(Int option)
    If option == optionDotMotion
        ToggleSetting(DotMotion)
        UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicDotMotion", IsEnabled(DotMotion))
        SetToggleOptionValue(option, IsEnabled(DotMotion))
    ElseIf option == optionBars
        ToggleSetting(BarsEnabled)
        UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicBarsEnabled", IsEnabled(BarsEnabled))
        SetToggleOptionValue(option, IsEnabled(BarsEnabled))
    ElseIf option == optionCompass
        ToggleSetting(CompassEnabled)
        UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicCompassEnabled", IsEnabled(CompassEnabled))
        SetToggleOptionValue(option, IsEnabled(CompassEnabled))
    EndIf
EndEvent

Event OnOptionKeyMapChange(Int option, Int keyCode, String conflictControl, String conflictName)
    If option != optionRouteKey || keyCode < 0 || keyCode > 255
        Return
    EndIf

    SetValue(RouteKeyCode, keyCode as Float)
    SetKeyMapOptionValue(option, keyCode)

    NordicMinimalUIQuest routeQuest = Game.GetFormFromFile(0x805, "NordicMinimalUISE.esp") as NordicMinimalUIQuest
    If routeQuest != None
        routeQuest.SetRouteKey(keyCode)
    EndIf

    If conflictControl != ""
        Debug.Notification("Klawisz Jasnowidzenia współdzieli sterowanie: " + conflictName)
    EndIf
EndEvent

Event OnOptionSliderOpen(Int option)
    If option == optionDotSize || option == optionDotOpacity
        If option == optionDotSize
            SetSliderDialogStartValue(GetValue(DotSize, 100.0))
            SetSliderDialogRange(50.0, 200.0)
        Else
            SetSliderDialogStartValue(GetValue(DotOpacity, 100.0))
            SetSliderDialogRange(25.0, 100.0)
        EndIf
        SetSliderDialogDefaultValue(100.0)
        SetSliderDialogInterval(5.0)
    ElseIf option == optionFade
        SetSliderDialogStartValue(GetValue(FadeSeconds, 5.0))
        SetSliderDialogDefaultValue(5.0)
        SetSliderDialogRange(1.0, 10.0)
        SetSliderDialogInterval(1.0)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    If option == optionDotSize
        value = ClampCrosshairValue(value, 50.0, 200.0)
        SetValue(DotSize, value)
        UI.InvokeFloat("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicDotSize", value)
        SetSliderOptionValue(option, value, "{0}%")
    ElseIf option == optionDotOpacity
        value = ClampCrosshairValue(value, 25.0, 100.0)
        SetValue(DotOpacity, value)
        UI.InvokeFloat("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicDotOpacity", value)
        SetSliderOptionValue(option, value, "{0}%")
    ElseIf option == optionFade
        SetValue(FadeSeconds, value)
        UI.InvokeFloat("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicFadeDelay", value)
        SetSliderOptionValue(option, value, "{0} s")
    EndIf
EndEvent

Function LoadSettings()
    FadeSeconds = Game.GetFormFromFile(0x801, "NordicMinimalUISE.esp") as GlobalVariable
    BarsEnabled = Game.GetFormFromFile(0x802, "NordicMinimalUISE.esp") as GlobalVariable
    CompassEnabled = Game.GetFormFromFile(0x803, "NordicMinimalUISE.esp") as GlobalVariable
    RouteKeyCode = Game.GetFormFromFile(0x804, "NordicMinimalUISE.esp") as GlobalVariable
    DotSize = Game.GetFormFromFile(0x808, "NordicMinimalUISE.esp") as GlobalVariable
    DotOpacity = Game.GetFormFromFile(0x809, "NordicMinimalUISE.esp") as GlobalVariable
    DotMotion = Game.GetFormFromFile(0x80A, "NordicMinimalUISE.esp") as GlobalVariable
EndFunction

Int Function GetRouteKey()
    If RouteKeyCode == None
        Return DefaultRouteKey
    EndIf

    Int keyCode = RouteKeyCode.GetValue() as Int
    If keyCode < 0 || keyCode > 255
        Return DefaultRouteKey
    EndIf
    Return keyCode
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

Float Function ClampCrosshairValue(Float value, Float minimum, Float maximum)
    If value < minimum
        Return minimum
    ElseIf value > maximum
        Return maximum
    EndIf
    Return value
EndFunction
