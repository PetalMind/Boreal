Scriptname HorseWhistleQuest extends Quest

Int Property DefaultWhistleKey = 34 AutoReadOnly
Float Property MarkerUpdateInterval = 5.0 AutoReadOnly
Float Property SummonDistance = 300.0 AutoReadOnly

GlobalVariable WhistleKeyCode
GlobalVariable WhistleSoundEnabled
GlobalVariable WhistleVolume
ObjectReference HorseMarker
Sound WhistleSound
Float lastWhistleTime = -10.0

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
    If keyCode != -1 && (keyCode < 1 || keyCode > 281)
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
    Float now = Utility.GetCurrentRealTime()
    If now >= lastWhistleTime && now - lastWhistleTime < 1.5
        Return
    EndIf
    lastWhistleTime = now
    PlayWhistle()
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

Function PlayWhistle()
    LoadSettings()
    If WhistleSound == None || Game.GetPlayer() == None
        Return
    EndIf
    If WhistleSoundEnabled != None && WhistleSoundEnabled.GetValue() < 0.5
        Return
    EndIf
    Int instance = WhistleSound.Play(Game.GetPlayer())
    If instance >= 0
        Float volume = 0.8
        If WhistleVolume != None
            volume = WhistleVolume.GetValue()
        EndIf
        If volume < 0.0
            volume = 0.0
        ElseIf volume > 1.0
            volume = 1.0
        EndIf
        Sound.SetInstanceVolume(instance, volume)
    EndIf
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
    WhistleSound = Game.GetFormFromFile(0x804, "SkyrimHorseWhistleSE.esp") as Sound
    WhistleSoundEnabled = Game.GetFormFromFile(0x806, "SkyrimHorseWhistleSE.esp") as GlobalVariable
    WhistleVolume = Game.GetFormFromFile(0x807, "SkyrimHorseWhistleSE.esp") as GlobalVariable
EndFunction

Int Function GetWhistleKey()
    If WhistleKeyCode == None
        LoadSettings()
    EndIf
    If WhistleKeyCode == None
        Return DefaultWhistleKey
    EndIf

    Int keyCode = WhistleKeyCode.GetValue() as Int
    If keyCode != -1 && (keyCode < 1 || keyCode > 281)
        Return DefaultWhistleKey
    EndIf
    Return keyCode
EndFunction

Function ApplyWhistleKey(Int keyCode)
    If keyCode != -1 && (keyCode < 1 || keyCode > 281)
        keyCode = DefaultWhistleKey
    EndIf
    UnregisterForAllKeys()
    If keyCode > 0
        RegisterForKey(keyCode)
    EndIf
EndFunction
