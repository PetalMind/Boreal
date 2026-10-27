Scriptname HorseWhistlePlayerAlias extends ReferenceAlias

Event OnInit()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnPlayerLoadGame()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    HorseWhistleQuest controller = GetOwningQuest() as HorseWhistleQuest
    If controller != None
        controller.Maintenance()
    EndIf
    HorseWhistleMCM configuration = Game.GetFormFromFile(0x808, "SkyrimHorseWhistleSE.esp") as HorseWhistleMCM
    If configuration != None
        configuration.RestoreMenu()
    EndIf
EndEvent
