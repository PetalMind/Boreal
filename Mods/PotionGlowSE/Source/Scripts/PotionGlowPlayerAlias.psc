Scriptname PotionGlowPlayerAlias extends ReferenceAlias

Event OnInit()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnPlayerLoadGame()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    PotionGlowQuest controller = GetOwningQuest() as PotionGlowQuest
    If controller != None
        controller.Maintenance()
    EndIf

    PotionGlowMCM configuration = GetOwningQuest() as PotionGlowMCM
    If configuration != None
        configuration.OnGameReload()
    EndIf
EndEvent
