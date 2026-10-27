Scriptname NordicMinimalUIPlayerAlias extends ReferenceAlias

Event OnInit()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnPlayerLoadGame()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    NordicMinimalUIQuest controller = GetOwningQuest() as NordicMinimalUIQuest
    If controller != None
        controller.Maintenance()
    EndIf
    NordicMinimalUIMCM configuration = GetOwningQuest() as NordicMinimalUIMCM
    If configuration != None
        configuration.OnGameReload()
    EndIf
EndEvent
