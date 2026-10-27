Scriptname SmartLootPlayerAlias extends ReferenceAlias

Event OnInit()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnPlayerLoadGame()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    SmartLootQuest controller = GetOwningQuest() as SmartLootQuest
    If controller != None
        controller.Maintenance()
    EndIf

    SmartLootMCM configuration = GetOwningQuest() as SmartLootMCM
    If configuration != None
        configuration.OnGameReload()
    EndIf
EndEvent
