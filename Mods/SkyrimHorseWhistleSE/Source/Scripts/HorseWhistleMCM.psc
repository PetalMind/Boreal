Scriptname HorseWhistleMCM extends SKI_ConfigBase

Int DefaultWhistleKey = 34
GlobalVariable WhistleKeyCode
GlobalVariable SoundEnabled
GlobalVariable SoundVolume
Int optionWhistleKey
Int optionSound
Int optionVolume
Int optionPreview

Int Function GetVersion()
    Return 120
EndFunction

Event OnConfigInit()
    ConfigurePages()
EndEvent

Event OnVersionUpdate(Int version)
    ConfigurePages()
EndEvent

Function ConfigurePages()
    ModName = "Horse Whistle SE"
    Pages = new String[1]
    Pages[0] = "Gwizd i sterowanie"
    LoadSettings()
EndFunction

Event OnConfigOpen()
    ConfigurePages()
    HorseWhistleQuest controller = GetController()
    If controller != None
        controller.Maintenance()
    EndIf
EndEvent

Event OnPageReset(String page)
    If page != "Gwizd i sterowanie"
        Return
    EndIf
    LoadSettings()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Przywoływanie konia")
    optionWhistleKey = AddKeyMapOption("Klawisz gwizdu", GetWhistleKey())
    AddHeaderOption("Dźwięk gwizdania")
    optionSound = AddToggleOption("Odtwarzaj gwizd", IsSoundEnabled())
    optionVolume = AddSliderOption("Głośność gwizdu", GetVolume() * 100.0, "{0}%")
    optionPreview = AddTextOption("Odsłuch gwizdu", "Odtwórz")
EndEvent

Event OnOptionKeyMapChange(Int option, Int keyCode, String conflictControl, String conflictName)
    If option != optionWhistleKey || (keyCode != -1 && (keyCode < 1 || keyCode > 281))
        Return
    EndIf
    If conflictControl != "" || conflictName != ""
        If !ShowMessage("Ten klawisz jest już używany: " + conflictControl + " " + conflictName + ". Przypisać go także do gwizdu?", True, "Przypisz", "Anuluj")
            Return
        EndIf
    EndIf
    HorseWhistleQuest controller = GetController()
    If controller == None
        ShowMessage("Skrypt przywoływania konia jest niedostępny. Konfiguracja nie została zmieniona.", False)
        Return
    EndIf
    controller.SetWhistleKey(keyCode)
    SetKeyMapOptionValue(option, controller.GetWhistleKey())
EndEvent

Event OnOptionSelect(Int option)
    If option == optionSound && SoundEnabled != None
        If IsSoundEnabled()
            SoundEnabled.SetValue(0.0)
        Else
            SoundEnabled.SetValue(1.0)
        EndIf
        SetToggleOptionValue(option, IsSoundEnabled())
    ElseIf option == optionPreview
        HorseWhistleQuest controller = GetController()
        If controller != None
            controller.PlayWhistle()
        EndIf
    EndIf
EndEvent

Event OnOptionSliderOpen(Int option)
    If option == optionVolume
        SetSliderDialogStartValue(GetVolume() * 100.0)
        SetSliderDialogDefaultValue(80.0)
        SetSliderDialogRange(0.0, 100.0)
        SetSliderDialogInterval(5.0)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    If option == optionVolume && SoundVolume != None
        If value < 0.0
            value = 0.0
        ElseIf value > 100.0
            value = 100.0
        EndIf
        SoundVolume.SetValue(value / 100.0)
        SetSliderOptionValue(option, value, "{0}%")
    EndIf
EndEvent

Event OnOptionDefault(Int option)
    If option == optionWhistleKey
        HorseWhistleQuest controller = GetController()
        If controller != None
            controller.SetWhistleKey(DefaultWhistleKey)
            SetKeyMapOptionValue(option, DefaultWhistleKey)
        EndIf
    ElseIf option == optionSound && SoundEnabled != None
        SoundEnabled.SetValue(1.0)
        SetToggleOptionValue(option, True)
    ElseIf option == optionVolume && SoundVolume != None
        SoundVolume.SetValue(0.8)
        SetSliderOptionValue(option, 80.0, "{0}%")
    EndIf
EndEvent

Function LoadSettings()
    WhistleKeyCode = Game.GetFormFromFile(0x801, "SkyrimHorseWhistleSE.esp") as GlobalVariable
    SoundEnabled = Game.GetFormFromFile(0x806, "SkyrimHorseWhistleSE.esp") as GlobalVariable
    SoundVolume = Game.GetFormFromFile(0x807, "SkyrimHorseWhistleSE.esp") as GlobalVariable
EndFunction

HorseWhistleQuest Function GetController()
    Return Game.GetFormFromFile(0x800, "SkyrimHorseWhistleSE.esp") as HorseWhistleQuest
EndFunction

Int Function GetWhistleKey()
    If WhistleKeyCode == None
        Return DefaultWhistleKey
    EndIf
    Int keyCode = WhistleKeyCode.GetValue() as Int
    If keyCode != -1 && (keyCode < 1 || keyCode > 281)
        Return DefaultWhistleKey
    EndIf
    Return keyCode
EndFunction

Bool Function IsSoundEnabled()
    Return SoundEnabled == None || SoundEnabled.GetValue() >= 0.5
EndFunction

Float Function GetVolume()
    If SoundVolume == None
        Return 0.8
    EndIf
    Return SoundVolume.GetValue()
EndFunction
