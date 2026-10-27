Scriptname QDJPlayerAlias extends ReferenceAlias

Event OnPlayerLoadGame()
    (GetOwningQuest() as QDJController).Initialise()
EndEvent
