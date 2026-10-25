Scriptname HorseWhistleQuest extends Quest

Int Property DefaultWhistleKey = 34 AutoReadOnly
Float Property MarkerUpdateInterval = 5.0 AutoReadOnly
Float Property SummonDistance = 300.0 AutoReadOnly

GlobalVariable WhistleKeyCode
ObjectReference HorseMarker

Event OnInit()
    Maintenance()
EndEvent

Function Maintenance()
    LoadSettings()
    ApplyWhistleKey(GetWhistleKey())
    RegisterForSingleUpdate(MarkerUpdateInterval)
EndFunction

Event OnKeyDown(Int keyCode)
    If keyCode == GetWhistleKey() && !Utility.IsInMenuMode()
        SummonHorse()
    EndIf
EndEvent

Event OnUpdate()
    Actor horse = Game.GetPlayersLastRiddenHorse()
    If horse != None && !horse.IsDead() && !horse.IsDisabled()
        UpdateMarker(horse)
    EndIf
    RegisterForSingleUpdate(MarkerUpdateInterval)
EndEvent

Function SetWhistleKey(Int keyCode)
    If keyCode < 1 || keyCode > 255
        Return
    EndIf

    If WhistleKeyCode == None
        LoadSettings()
    EndIf
    If WhistleKeyCode != None
        WhistleKeyCode.SetValue(keyCode as Float)
    EndIf
    ApplyWhistleKey(keyCode)
EndFunction

Function SummonHorse()
    Actor player = Game.GetPlayer()
    Actor horse = Game.GetPlayersLastRiddenHorse()
    If player == None
        Return
    EndIf
    If horse == None
        Debug.Notification("Najpierw dosiądź konia.")
        Return
    EndIf
    If horse.IsDead()
        Debug.Notification("Twój ostatnio dosiadany koń nie żyje.")
        Return
    EndIf
    If horse.IsDisabled()
        Debug.Notification("Twój koń jest teraz niedostępny.")
        Return
    EndIf

    If horse.GetDistance(player) > SummonDistance
        horse.MoveTo(player, 0.0, -220.0, 0.0, True)
        Debug.Notification("Przywołano konia.")
    Else
        Debug.Notification("Koń jest już blisko.")
    EndIf
    UpdateMarker(horse)
EndFunction

Function UpdateMarker(Actor horse)
    If HorseMarker == None
        HorseMarker = Game.GetFormFromFile(0x803, "SkyrimHorseWhistleSE.esp") as ObjectReference
    EndIf
    If HorseMarker == None || horse == None
        Return
    EndIf

    HorseMarker.MoveTo(horse, 0.0, 0.0, 0.0, True)
    If !HorseMarker.IsMapMarkerVisible()
        HorseMarker.AddToMap(False)
    EndIf
EndFunction

Function LoadSettings()
    WhistleKeyCode = Game.GetFormFromFile(0x801, "SkyrimHorseWhistleSE.esp") as GlobalVariable
    HorseMarker = Game.GetFormFromFile(0x803, "SkyrimHorseWhistleSE.esp") as ObjectReference
EndFunction

Int Function GetWhistleKey()
    If WhistleKeyCode == None
        LoadSettings()
    EndIf
    If WhistleKeyCode == None
        Return DefaultWhistleKey
    EndIf

    Int keyCode = WhistleKeyCode.GetValue() as Int
    If keyCode < 1 || keyCode > 255
        Return DefaultWhistleKey
    EndIf
    Return keyCode
EndFunction

Function ApplyWhistleKey(Int keyCode)
    If keyCode < 1 || keyCode > 255
        keyCode = DefaultWhistleKey
    EndIf
    UnregisterForAllKeys()
    RegisterForKey(keyCode)
EndFunction
