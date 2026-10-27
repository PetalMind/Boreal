Scriptname QDJController extends Quest

Int generation
Int backgroundSlot

Event OnInit()
    Initialise()
EndEvent

Function Initialise()
    generation += 1
    ((Self as Quest) as QDJCache).Initialise()
    UnregisterForAllMenus()
    RegisterForMenu("Journal Menu")
    RegisterForSingleUpdate(0.5)
EndFunction

Event OnUpdate()
    If !Utility.IsInMenuMode()
        QDJCache cache = (Self as Quest) as QDJCache
        cache.Initialise()
        ; Resolve changed objectives in the background, never on every menu open.
        Int i = 0
        While i < 4
            cache.Refresh(backgroundSlot)
            backgroundSlot = (backgroundSlot + 1) % 128
            i += 1
        EndWhile
        Int selected = cache.Focus()
        If selected >= 0
            cache.Refresh(selected)
        EndIf
        ((Self as Quest) as QDJCompass).Show(cache.CompassLabel(selected))
    EndIf
    RegisterForSingleUpdate(0.5)
EndEvent

Event OnMenuClose(String menuName)
    generation += 1
EndEvent

Event OnMenuOpen(String menuName)
    generation += 1
    Int session = generation
    QDJCache cache = (Self as Quest) as QDJCache
    cache.Initialise()
    Utility.WaitMenuMode(0.1)
    Int cursor = 0
    Int delivered = 0
    While session == generation && UI.IsMenuOpen("Journal Menu")
        Int count = UI.GetInt("Journal Menu", "_root.QDJCount")
        If count > 0 && count <= 512
            If cursor >= count
                cursor = 0
            EndIf
            String path = "_root.QDJRequests.q" + cursor
            Int formID = UI.GetInt("Journal Menu", path + ".formID")
            Int instanceID = UI.GetInt("Journal Menu", path + ".instance")
            Quest task = Game.GetFormEx(formID) as Quest
            If task != None
                ; Existing entries are restored directly from the saved snapshot.
                Int slot = cache.Remember(task, instanceID)
                If session == generation
                    String[] result = new String[3]
                    result[0] = formID as String
                    result[1] = instanceID as String
                    result[2] = cache.Label(slot)
                    UI.InvokeStringA("Journal Menu", "_root.QDJPage.QDJSetResult", result)
                EndIf
            EndIf
            cursor += 1
            delivered += 1
            If delivered >= count
                ; Poll only for new miscellaneous entries and a changed selection.
                Int focusID = UI.GetInt("Journal Menu", "_root.QDJSelectedFormID")
                Int focusInstance = UI.GetInt("Journal Menu", "_root.QDJSelectedInstance")
                cache.Select(Game.GetFormEx(focusID) as Quest, focusInstance)
                Utility.WaitMenuMode(0.25)
                delivered = 0
            EndIf
        Else
            Utility.WaitMenuMode(0.1)
        EndIf
    EndWhile
EndEvent
