Scriptname SmartBooksTomesPlayerAlias extends ReferenceAlias

Event OnInit()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnPlayerLoadGame()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    SmartBooksTomesMCM configuration = GetOwningQuest() as SmartBooksTomesMCM
    If configuration != None
        configuration.OnGameReload()
    EndIf
EndEvent
