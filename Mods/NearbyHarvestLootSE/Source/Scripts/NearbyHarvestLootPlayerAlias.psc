Scriptname NearbyHarvestLootPlayerAlias extends ReferenceAlias

Event OnInit()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnPlayerLoadGame()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    NearbyHarvestLootQuest controller = GetOwningQuest() as NearbyHarvestLootQuest
    If controller != None
        controller.Maintenance()
    EndIf
    NearbyHarvestLootMCM configuration = GetOwningQuest() as NearbyHarvestLootMCM
    If configuration != None
        configuration.OnGameReload()
    EndIf
EndEvent
