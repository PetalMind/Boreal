Scriptname HorseWhistleMCM extends SKI_ConfigBase

Int DefaultWhistleKey = 34
GlobalVariable WhistleKeyCode
Int optionWhistleKey

Event OnConfigInit()
    ModName = "Horse Whistle SE"
    Pages = new String[1]
    Pages[0] = "Ustawienia"
    LoadSettings()
EndEvent

Event OnPageReset(String page)
    If page != "Ustawienia"
        Return
    EndIf

    LoadSettings()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Gwizd na konia")
    optionWhistleKey = AddKeyMapOption("Klawisz gwizdu", GetWhistleKey())
EndEvent

Event OnOptionKeyMapChange(Int option, Int keyCode, String conflictControl, String conflictName)
    If option != optionWhistleKey || keyCode < 1 || keyCode > 255
        Return
    EndIf

    If WhistleKeyCode != None
        WhistleKeyCode.SetValue(keyCode as Float)
    EndIf
    SetKeyMapOptionValue(option, keyCode)

    HorseWhistleQuest whistleQuest = Game.GetFormFromFile(0x800, "SkyrimHorseWhistleSE.esp") as HorseWhistleQuest
    If whistleQuest != None
        whistleQuest.SetWhistleKey(keyCode)
    EndIf

    If conflictControl != ""
        Debug.Notification("Klawisz gwizdu współdzieli sterowanie: " + conflictName)
    EndIf
EndEvent

Function LoadSettings()
    WhistleKeyCode = Game.GetFormFromFile(0x801, "SkyrimHorseWhistleSE.esp") as GlobalVariable
EndFunction

Int Function GetWhistleKey()
    If WhistleKeyCode == None
        Return DefaultWhistleKey
    EndIf
    Int keyCode = WhistleKeyCode.GetValue() as Int
    If keyCode < 1 || keyCode > 255
        Return DefaultWhistleKey
    EndIf
    Return keyCode
EndFunction
