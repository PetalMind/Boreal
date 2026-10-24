Scriptname NordicMinimalUIQuest extends Quest

Float Property PollSeconds = 0.5 Auto
Bool lastCombatState
Bool hudConfigured
GlobalVariable FadeSeconds
GlobalVariable BarsEnabled
GlobalVariable CompassEnabled

Event OnInit()
    FadeSeconds = Game.GetFormFromFile(0x801, "NordicMinimalUISE.esp") as GlobalVariable
    BarsEnabled = Game.GetFormFromFile(0x802, "NordicMinimalUISE.esp") as GlobalVariable
    CompassEnabled = Game.GetFormFromFile(0x803, "NordicMinimalUISE.esp") as GlobalVariable
    UI.InvokeFloat("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicFadeDelay", GetValue(FadeSeconds, 5.0))
    UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicBarsEnabled", IsEnabled(BarsEnabled))
    UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicCompassEnabled", IsEnabled(CompassEnabled))
    RegisterForSingleUpdate(PollSeconds)
EndEvent

Event OnUpdate()
    Actor player = Game.GetPlayer()
    If UI.IsMenuOpen("HUD Menu")
        If !hudConfigured
            UI.InvokeFloat("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicFadeDelay", GetValue(FadeSeconds, 5.0))
            UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicBarsEnabled", IsEnabled(BarsEnabled))
            UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicCompassEnabled", IsEnabled(CompassEnabled))
            hudConfigured = True
        EndIf
    Else
        hudConfigured = False
    EndIf
    If player != None && UI.IsMenuOpen("HUD Menu")
        Bool inCombat = player.IsInCombat()
        If inCombat != lastCombatState
            lastCombatState = inCombat
            UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicCombatActive", inCombat)
        EndIf
    EndIf
    RegisterForSingleUpdate(PollSeconds)
EndEvent

Float Function GetValue(GlobalVariable setting, Float fallback)
    If setting == None
        Return fallback
    EndIf
    Return setting.GetValue()
EndFunction

Bool Function IsEnabled(GlobalVariable setting)
    Return setting != None && setting.GetValue() >= 0.5
EndFunction
