Scriptname QDJPlayerAlias extends ReferenceAlias

Event OnInit()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnPlayerLoadGame()
    (GetOwningQuest() as QDJController).Initialise()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    QDJMCM configuration = GetOwningQuest() as QDJMCM
    If configuration != None
        configuration.OnGameReload()
    EndIf
EndEvent
