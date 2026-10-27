Scriptname QDJController extends Quest

Int generation

Event OnInit()
    Initialise()
EndEvent

Function Initialise()
    generation += 1
    UnregisterForAllMenus()
    RegisterForMenu("Journal Menu")
EndFunction

Event OnMenuClose(String menuName)
    generation += 1
EndEvent

Event OnMenuOpen(String menuName)
    generation += 1
    Int session = generation
    Int cursor = 0
    ; WaitMenuMode continues while the journal pauses the game.
    Utility.WaitMenuMode(0.2)
    While session == generation && UI.IsMenuOpen("Journal Menu")
        Int count = UI.GetInt("Journal Menu", "_root.QDJCount")
        If count > 0 && count <= 512
            If cursor >= count
                cursor = 0
                Utility.WaitMenuMode(0.5)
            EndIf
            String path = "_root.QDJRequests.q" + cursor
            Int formID = UI.GetInt("Journal Menu", path + ".formID")
            Int instanceID = UI.GetInt("Journal Menu", path + ".instance")
            Quest targetQuest = Game.GetFormEx(formID) as Quest
            String label = "Nie można odczytać celu zadania"
            If targetQuest != None && session == generation
                label = QDJTargetResolver.Describe(targetQuest)
            EndIf
            If session == generation && UI.IsMenuOpen("Journal Menu")
                String[] result = new String[3]
                result[0] = formID as String
                result[1] = instanceID as String
                result[2] = label
                UI.InvokeStringA("Journal Menu", "_root.QDJPage.QDJSetResult", result)
            EndIf
            cursor += 1
        EndIf
        Utility.WaitMenuMode(0.05)
    EndWhile
EndEvent
