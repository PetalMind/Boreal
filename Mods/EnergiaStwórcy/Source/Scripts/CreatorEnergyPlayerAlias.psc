Scriptname CreatorEnergyPlayerAlias extends ReferenceAlias

Event OnInit()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnPlayerLoadGame()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    CreatorEnergyMCM configuration = GetOwningQuest() as CreatorEnergyMCM
    If configuration != None
        configuration.OnGameReload()
    EndIf
EndEvent
