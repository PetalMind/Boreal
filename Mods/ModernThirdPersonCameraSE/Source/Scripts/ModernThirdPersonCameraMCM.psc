Scriptname ModernThirdPersonCameraMCM extends SKI_ConfigBase

GlobalVariable EnabledSetting
GlobalVariable NormalShoulderX
GlobalVariable NormalShoulderZ
GlobalVariable CombatShoulderX
GlobalVariable CombatAddY
GlobalVariable CombatShoulderZ
GlobalVariable BowShoulderX
GlobalVariable BowAddY
GlobalVariable BowShoulderZ
GlobalVariable NormalFOV
GlobalVariable CombatFOV
GlobalVariable BowFOV
GlobalVariable FOVResponse
GlobalVariable ZoomSensitivity
GlobalVariable AutoRecenter
GlobalVariable RecenterDelay
GlobalVariable RecenterResponse
GlobalVariable MCMOverrides

String currentPage
Int optionEnabled
Int optionAutoRecenter
Int optionFOVResponse
Int optionZoomSensitivity
Int optionRecenterDelay
Int optionRecenterResponse
Int optionNormalX
Int optionNormalZ
Int optionNormalFOV
Int optionCombatX
Int optionCombatY
Int optionCombatZ
Int optionCombatFOV
Int optionBowX
Int optionBowY
Int optionBowZ
Int optionBowFOV

Event OnConfigInit()
    ModName = "Modern Third Person Camera SE"
    Pages = new String[4]
    Pages[0] = "Ogólne"
    Pages[1] = "Eksploracja"
    Pages[2] = "Walka"
    Pages[3] = "Łuk"
    LoadSettings()
EndEvent

Event OnPageReset(String page)
    currentPage = page
    LoadSettings()
    SetCursorFillMode(TOP_TO_BOTTOM)

    If page == "Ogólne"
        AddHeaderOption("Kamera")
        optionEnabled = AddToggleOption("Włącz modyfikację kamery", IsEnabled(EnabledSetting))
        optionAutoRecenter = AddToggleOption("Automatycznie centruj kamerę", IsEnabled(AutoRecenter))
        AddHeaderOption("Sterowanie")
        optionZoomSensitivity = AddSliderOption("Czułość zoomu", GetValue(ZoomSensitivity, 1.0), "{0}")
        optionFOVResponse = AddSliderOption("Szybkość zmiany pola widzenia", GetValue(FOVResponse, 3.5), "{0}")
        optionRecenterDelay = AddSliderOption("Opóźnienie centrowania", GetValue(RecenterDelay, 1.1), "{0} s")
        optionRecenterResponse = AddSliderOption("Szybkość centrowania", GetValue(RecenterResponse, 2.4), "{0}")
    ElseIf page == "Eksploracja"
        AddHeaderOption("Pozycja kamery")
        optionNormalX = AddSliderOption("Przesunięcie ramienia", GetValue(NormalShoulderX, 18.0), "{0}")
        optionNormalZ = AddSliderOption("Wysokość ramienia", GetValue(NormalShoulderZ, 2.0), "{0}")
        optionNormalFOV = AddSliderOption("Pole widzenia", GetValue(NormalFOV, 74.0), "{0}°")
    ElseIf page == "Walka"
        AddHeaderOption("Pozycja kamery")
        optionCombatX = AddSliderOption("Przesunięcie ramienia", GetValue(CombatShoulderX, 24.0), "{0}")
        optionCombatY = AddSliderOption("Przesunięcie do przodu", GetValue(CombatAddY, 8.0), "{0}")
        optionCombatZ = AddSliderOption("Wysokość ramienia", GetValue(CombatShoulderZ, 2.0), "{0}")
        optionCombatFOV = AddSliderOption("Pole widzenia", GetValue(CombatFOV, 78.0), "{0}°")
    ElseIf page == "Łuk"
        AddHeaderOption("Pozycja kamery podczas celowania")
        optionBowX = AddSliderOption("Przesunięcie ramienia", GetValue(BowShoulderX, 14.0), "{0}")
        optionBowY = AddSliderOption("Przesunięcie do przodu", GetValue(BowAddY, 10.0), "{0}")
        optionBowZ = AddSliderOption("Wysokość ramienia", GetValue(BowShoulderZ, 1.0), "{0}")
        optionBowFOV = AddSliderOption("Pole widzenia", GetValue(BowFOV, 68.0), "{0}°")
    EndIf
EndEvent

Event OnOptionSelect(Int option)
    If currentPage == "Ogólne" && option == optionEnabled
        ToggleSetting(EnabledSetting)
        SetToggleOptionValue(option, IsEnabled(EnabledSetting))
    ElseIf currentPage == "Ogólne" && option == optionAutoRecenter
        ToggleSetting(AutoRecenter)
        SetToggleOptionValue(option, IsEnabled(AutoRecenter))
    EndIf
EndEvent

Event OnOptionSliderOpen(Int option)
    If currentPage == "Ogólne" && option == optionZoomSensitivity
        OpenSlider(GetValue(ZoomSensitivity, 1.0), 1.0, 0.1, 3.0, 0.1)
    ElseIf currentPage == "Ogólne" && option == optionFOVResponse
        OpenSlider(GetValue(FOVResponse, 3.5), 3.5, 0.1, 20.0, 0.1)
    ElseIf currentPage == "Ogólne" && option == optionRecenterDelay
        OpenSlider(GetValue(RecenterDelay, 1.1), 1.1, 0.0, 10.0, 0.1)
    ElseIf currentPage == "Ogólne" && option == optionRecenterResponse
        OpenSlider(GetValue(RecenterResponse, 2.4), 2.4, 0.1, 12.0, 0.1)
    ElseIf currentPage == "Eksploracja" && option == optionNormalX
        OpenSlider(GetValue(NormalShoulderX, 18.0), 18.0, -40.0, 40.0, 1.0)
    ElseIf currentPage == "Eksploracja" && option == optionNormalZ
        OpenSlider(GetValue(NormalShoulderZ, 2.0), 2.0, -30.0, 30.0, 1.0)
    ElseIf currentPage == "Eksploracja" && option == optionNormalFOV
        OpenSlider(GetValue(NormalFOV, 74.0), 74.0, 50.0, 110.0, 1.0)
    ElseIf currentPage == "Walka" && option == optionCombatX
        OpenSlider(GetValue(CombatShoulderX, 24.0), 24.0, -40.0, 40.0, 1.0)
    ElseIf currentPage == "Walka" && option == optionCombatY
        OpenSlider(GetValue(CombatAddY, 8.0), 8.0, -40.0, 40.0, 1.0)
    ElseIf currentPage == "Walka" && option == optionCombatZ
        OpenSlider(GetValue(CombatShoulderZ, 2.0), 2.0, -30.0, 30.0, 1.0)
    ElseIf currentPage == "Walka" && option == optionCombatFOV
        OpenSlider(GetValue(CombatFOV, 78.0), 78.0, 50.0, 110.0, 1.0)
    ElseIf currentPage == "Łuk" && option == optionBowX
        OpenSlider(GetValue(BowShoulderX, 14.0), 14.0, -40.0, 40.0, 1.0)
    ElseIf currentPage == "Łuk" && option == optionBowY
        OpenSlider(GetValue(BowAddY, 10.0), 10.0, -40.0, 40.0, 1.0)
    ElseIf currentPage == "Łuk" && option == optionBowZ
        OpenSlider(GetValue(BowShoulderZ, 1.0), 1.0, -30.0, 30.0, 1.0)
    ElseIf currentPage == "Łuk" && option == optionBowFOV
        OpenSlider(GetValue(BowFOV, 68.0), 68.0, 50.0, 110.0, 1.0)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    If currentPage == "Ogólne" && option == optionZoomSensitivity
        SaveSetting(ZoomSensitivity, value, option, "{0}")
    ElseIf currentPage == "Ogólne" && option == optionFOVResponse
        SaveSetting(FOVResponse, value, option, "{0}")
    ElseIf currentPage == "Ogólne" && option == optionRecenterDelay
        SaveSetting(RecenterDelay, value, option, "{0} s")
    ElseIf currentPage == "Ogólne" && option == optionRecenterResponse
        SaveSetting(RecenterResponse, value, option, "{0}")
    ElseIf currentPage == "Eksploracja" && option == optionNormalX
        SaveSetting(NormalShoulderX, value, option, "{0}")
    ElseIf currentPage == "Eksploracja" && option == optionNormalZ
        SaveSetting(NormalShoulderZ, value, option, "{0}")
    ElseIf currentPage == "Eksploracja" && option == optionNormalFOV
        SaveSetting(NormalFOV, value, option, "{0}°")
    ElseIf currentPage == "Walka" && option == optionCombatX
        SaveSetting(CombatShoulderX, value, option, "{0}")
    ElseIf currentPage == "Walka" && option == optionCombatY
        SaveSetting(CombatAddY, value, option, "{0}")
    ElseIf currentPage == "Walka" && option == optionCombatZ
        SaveSetting(CombatShoulderZ, value, option, "{0}")
    ElseIf currentPage == "Walka" && option == optionCombatFOV
        SaveSetting(CombatFOV, value, option, "{0}°")
    ElseIf currentPage == "Łuk" && option == optionBowX
        SaveSetting(BowShoulderX, value, option, "{0}")
    ElseIf currentPage == "Łuk" && option == optionBowY
        SaveSetting(BowAddY, value, option, "{0}")
    ElseIf currentPage == "Łuk" && option == optionBowZ
        SaveSetting(BowShoulderZ, value, option, "{0}")
    ElseIf currentPage == "Łuk" && option == optionBowFOV
        SaveSetting(BowFOV, value, option, "{0}°")
    EndIf
EndEvent

Function LoadSettings()
    EnabledSetting = Game.GetFormFromFile(0x801, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    NormalShoulderX = Game.GetFormFromFile(0x802, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    NormalShoulderZ = Game.GetFormFromFile(0x803, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    CombatShoulderX = Game.GetFormFromFile(0x804, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    CombatAddY = Game.GetFormFromFile(0x805, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    CombatShoulderZ = Game.GetFormFromFile(0x806, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    BowShoulderX = Game.GetFormFromFile(0x807, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    BowAddY = Game.GetFormFromFile(0x808, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    BowShoulderZ = Game.GetFormFromFile(0x809, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    NormalFOV = Game.GetFormFromFile(0x80A, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    CombatFOV = Game.GetFormFromFile(0x80B, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    BowFOV = Game.GetFormFromFile(0x80C, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    FOVResponse = Game.GetFormFromFile(0x80D, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    ZoomSensitivity = Game.GetFormFromFile(0x80E, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    AutoRecenter = Game.GetFormFromFile(0x80F, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    RecenterDelay = Game.GetFormFromFile(0x810, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    RecenterResponse = Game.GetFormFromFile(0x811, "ModernThirdPersonCameraSE.esp") as GlobalVariable
    MCMOverrides = Game.GetFormFromFile(0x812, "ModernThirdPersonCameraSE.esp") as GlobalVariable
EndFunction

Float Function GetValue(GlobalVariable setting, Float fallback)
    If setting == None
        Return fallback
    EndIf
    Return setting.GetValue()
EndFunction

Bool Function IsEnabled(GlobalVariable setting)
    Return setting == None || setting.GetValue() >= 0.5
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
    EnableMCMOverrides()
EndFunction

Function OpenSlider(Float value, Float defaultValue, Float minimum, Float maximum, Float interval)
    SetSliderDialogStartValue(value)
    SetSliderDialogDefaultValue(defaultValue)
    SetSliderDialogRange(minimum, maximum)
    SetSliderDialogInterval(interval)
EndFunction

Function SaveSetting(GlobalVariable setting, Float value, Int option, String formatString)
    If setting != None
        setting.SetValue(value)
        EnableMCMOverrides()
    EndIf
    SetSliderOptionValue(option, value, formatString)
EndFunction

Function EnableMCMOverrides()
    If MCMOverrides != None
        MCMOverrides.SetValue(1.0)
    EndIf
EndFunction
