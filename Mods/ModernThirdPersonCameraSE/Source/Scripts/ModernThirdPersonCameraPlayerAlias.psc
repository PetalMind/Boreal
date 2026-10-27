Scriptname ModernThirdPersonCameraPlayerAlias extends ReferenceAlias

Event OnInit()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnPlayerLoadGame()
    RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
    ModernThirdPersonCameraMCM configuration = GetOwningQuest() as ModernThirdPersonCameraMCM
    If configuration != None
        configuration.OnGameReload()
    EndIf
EndEvent
