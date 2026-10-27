Scriptname NordicMinimalUIQuest extends Quest

Float Property PollSeconds = 0.5 Auto
Int Property DefaultRouteKey = 35 AutoReadOnly
Bool lastCombatState
Bool hudConfigured
Bool horsePanelVisible
GlobalVariable FadeSeconds
GlobalVariable BarsEnabled
GlobalVariable CompassEnabled
GlobalVariable RouteKeyCode

Event OnInit()
    Maintenance()
EndEvent

Function Maintenance()
    hudConfigured = False
    horsePanelVisible = False
    FadeSeconds = Game.GetFormFromFile(0x801, "NordicMinimalUISE.esp") as GlobalVariable
    BarsEnabled = Game.GetFormFromFile(0x802, "NordicMinimalUISE.esp") as GlobalVariable
    CompassEnabled = Game.GetFormFromFile(0x803, "NordicMinimalUISE.esp") as GlobalVariable
    RouteKeyCode = Game.GetFormFromFile(0x804, "NordicMinimalUISE.esp") as GlobalVariable
    ApplyRouteKey(GetRouteKey())
    UI.InvokeFloat("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicFadeDelay", GetValue(FadeSeconds, 5.0))
    UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicBarsEnabled", IsEnabled(BarsEnabled))
    UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicCompassEnabled", IsEnabled(CompassEnabled))
    RegisterForSingleUpdate(PollSeconds)
    Debug.Trace("[NordicMinimalUI] HUD controller initialized; version=105")
EndFunction

Event OnKeyDown(Int keyCode)
    If keyCode == GetRouteKey() && keyCode > 0 && !Utility.IsInMenuMode() && !UI.IsTextInputEnabled()
        CastClairvoyance()
    EndIf
EndEvent

Function SetRouteKey(Int keyCode)
    If keyCode < 0 || keyCode > 255
        Return
    EndIf

    If RouteKeyCode == None
        RouteKeyCode = Game.GetFormFromFile(0x804, "NordicMinimalUISE.esp") as GlobalVariable
    EndIf
    If RouteKeyCode != None
        RouteKeyCode.SetValue(keyCode as Float)
    EndIf
    ApplyRouteKey(keyCode)
EndFunction

Int Function GetRouteKey()
    If RouteKeyCode == None
        RouteKeyCode = Game.GetFormFromFile(0x804, "NordicMinimalUISE.esp") as GlobalVariable
    EndIf
    If RouteKeyCode == None
        Return DefaultRouteKey
    EndIf

    Int keyCode = RouteKeyCode.GetValue() as Int
    If keyCode < 0 || keyCode > 255
        Return DefaultRouteKey
    EndIf
    Return keyCode
EndFunction

Function ApplyRouteKey(Int keyCode)
    UnregisterForAllKeys()
    If keyCode > 0 && keyCode <= 255
        RegisterForKey(keyCode)
    EndIf
EndFunction

Function CastClairvoyance()
    Actor player = Game.GetPlayer()
    Spell clairvoyance = Game.GetFormFromFile(0x21143, "Skyrim.esm") as Spell
    If player == None || clairvoyance == None
        Return
    EndIf
    clairvoyance.Cast(player, player)
EndFunction

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
        horsePanelVisible = False
    EndIf
    If player != None && UI.IsMenuOpen("HUD Menu")
        Bool inCombat = player.IsInCombat()
        If inCombat != lastCombatState
            lastCombatState = inCombat
            UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicCombatActive", inCombat)
        EndIf
        UpdateHorsePanel(player)
    EndIf
    RegisterForSingleUpdate(PollSeconds)
EndEvent

Function UpdateHorsePanel(Actor player)
    Actor horse = NordicHorseState.CurrentMount(player)
    If horse == None
        HideHorsePanel()
        Return
    EndIf

    String horseName = horse.GetDisplayName()
    If horseName == ""
        horseName = horse.GetName()
    EndIf
    If horseName == ""
        horseName = "Koń"
    EndIf

    Float health = horse.GetActorValuePercentage("Health")
    Float stamina = horse.GetActorValuePercentage("Stamina")
    UI.InvokeString("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicHorseName", horseName)
    UI.InvokeFloat("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicHorseHealth", health)
    UI.InvokeFloat("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicHorseStamina", stamina)
    UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicHorseVisible", True)
    horsePanelVisible = True
EndFunction

Function HideHorsePanel()
    If horsePanelVisible
        UI.InvokeBool("HUD Menu", "_root.HUDMovieBaseInstance.SetNordicHorseVisible", False)
        horsePanelVisible = False
    EndIf
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
