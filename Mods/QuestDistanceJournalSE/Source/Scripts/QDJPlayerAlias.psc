Scriptname QDJPlayerAlias extends ReferenceAlias

Event OnInit()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnPlayerLoadGame()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    QDJController controller = GetOwningQuest() as QDJController
    If controller != None
        controller.Initialise()
    EndIf
    QDJMCM configuration = GetOwningQuest() as QDJMCM
    If configuration != None
        configuration.OnGameReload()
    EndIf
EndEvent
