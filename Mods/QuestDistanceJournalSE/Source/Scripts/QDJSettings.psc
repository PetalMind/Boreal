Scriptname QDJSettings Hidden

; Globals work in existing saves without attaching a new quest-script instance.
Bool Function IsAvailable() Global
    Return Setting(0x801) != None && Setting(0x802) != None && Setting(0x803) != None
EndFunction

Int Function GetSortMode() Global
    GlobalVariable settingValue = Setting(0x801)
    If settingValue == None
        Return 0
    EndIf
    Int mode = settingValue.GetValue() as Int
    If mode < 0 || mode > 3
        Return 0
    EndIf
    Return mode
EndFunction

Function SetSortMode(Int value) Global
    GlobalVariable settingValue = Setting(0x801)
    If value >= 0 && value <= 3 && settingValue != None
        settingValue.SetValue(value as Float)
    EndIf
EndFunction

Bool Function TrackedFirst() Global
    GlobalVariable settingValue = Setting(0x802)
    Return settingValue == None || settingValue.GetValue() >= 0.5
EndFunction

Function SetTrackedFirst(Bool value) Global
    SetFlag(0x802, value)
EndFunction

Bool Function ShowDetails() Global
    GlobalVariable settingValue = Setting(0x803)
    Return settingValue == None || settingValue.GetValue() >= 0.5
EndFunction

Function SetShowDetails(Bool value) Global
    SetFlag(0x803, value)
EndFunction

Function SetFlag(Int localID, Bool value) Global
    GlobalVariable settingValue = Setting(localID)
    If settingValue != None
        If value
            settingValue.SetValue(1.0)
        Else
            settingValue.SetValue(0.0)
        EndIf
    EndIf
EndFunction

GlobalVariable Function Setting(Int localID) Global
    Return Game.GetFormFromFile(localID, "QuestDistanceJournalSE.esp") as GlobalVariable
EndFunction
