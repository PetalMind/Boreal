Scriptname AutoPotionPlayerAlias extends ReferenceAlias

Event OnInit()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnPlayerLoadGame()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    AutoPotionQuest controller = GetOwningQuest() as AutoPotionQuest
    If controller != None
        controller.Maintenance()
    EndIf
    AutoPotionMCM configuration = GetOwningQuest() as AutoPotionMCM
    If configuration != None
        configuration.OnGameReload()
    EndIf
EndEvent
