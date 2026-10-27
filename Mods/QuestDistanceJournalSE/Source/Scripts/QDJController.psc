Scriptname QDJController extends Quest

Int generation
Int processingGeneration = -1
Int backgroundSlot

Event OnInit()
    Initialise()
EndEvent

Function Initialise()
    generation += 1
    QDJCache cache = (Self as Quest) as QDJCache
    cache.Initialise()
    Debug.Trace("[QDJ] Controller initialized; cache ready=" + cache.IsReady() + "; version=132")
    UnregisterForAllMenus()
    RegisterForMenu("Journal Menu")
    RegisterForModEvent("QDJ_Ready", "OnJournalReady")
    RegisterForModEvent("QDJ_SortChanged", "OnSortChanged")
    RegisterForSingleUpdate(0.5)
    If UI.IsMenuOpen("Journal Menu")
        UI.SetBool("Journal Menu", "_root.QDJConnected", False)
    EndIf
EndFunction

Event OnUpdate()
    If !Utility.IsInMenuMode()
        QDJCache cache = (Self as Quest) as QDJCache
        cache.Initialise()
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
    PumpJournal()
EndEvent

Event OnJournalReady(String eventName, String text, Float number, Form sender)
    If UI.IsMenuOpen("Journal Menu")
        ConfigureJournal()
        UI.SetBool("Journal Menu", "_root.QDJConnected", True)
    EndIf
    PumpJournal()
EndEvent

Event OnSortChanged(String eventName, String text, Float number, Form sender)
    QDJSettings.SetSortMode(number as Int)
EndEvent

Function ConfigureJournal()
    String[] args = new String[3]
    args[0] = QDJSettings.GetSortMode() as String
    args[1] = QDJSettings.TrackedFirst() as String
    args[2] = QDJSettings.ShowDetails() as String
    UI.InvokeStringA("Journal Menu", "_root.QDJPage.QDJConfigure", args)
EndFunction

Function PumpJournal()
    If !UI.IsMenuOpen("Journal Menu") || processingGeneration == generation
        Return
    EndIf
    Int session = generation
    processingGeneration = session
    QDJCache cache = (Self as Quest) as QDJCache
    cache.Initialise()
    If !cache.IsReady()
        processingGeneration = -1
        Return
    EndIf
    Utility.WaitMenuMode(0.1)
    Int cursor = 0
    Int revision = -1
    Bool configured = False
    While session == generation && UI.IsMenuOpen("Journal Menu")
        If UI.GetInt("Journal Menu", "_root.QDJBridgeVersion") >= 130
            If !configured
                ConfigureJournal()
                UI.SetBool("Journal Menu", "_root.QDJConnected", True)
                configured = True
            EndIf
            Int currentRevision = UI.GetInt("Journal Menu", "_root.QDJRequestRevision")
            If currentRevision != revision
                revision = currentRevision
                cursor = 0
            EndIf
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
                    Int slot = cache.Remember(task, instanceID, UI.GetString("Journal Menu", path + ".title"))
                    If session == generation
                        String[] result = new String[5]
                        result[0] = formID as String
                        result[1] = instanceID as String
                        result[2] = cache.Label(slot)
                        result[3] = cache.Place(slot)
                        result[4] = cache.Distance(slot) as String
                        UI.InvokeStringA("Journal Menu", "_root.QDJPage.QDJSetResult", result)
                    EndIf
                Else
                    String[] unavailable = new String[5]
                    unavailable[0] = formID as String
                    unavailable[1] = instanceID as String
                    unavailable[2] = "Dane tego zadania są niedostępne"
                    unavailable[3] = ""
                    unavailable[4] = "-1"
                    UI.InvokeStringA("Journal Menu", "_root.QDJPage.QDJSetResult", unavailable)
                EndIf
                cursor += 1
                Int focusID = UI.GetInt("Journal Menu", "_root.QDJSelectedFormID")
                Int focusInstance = UI.GetInt("Journal Menu", "_root.QDJSelectedInstance")
                cache.Select(Game.GetFormEx(focusID) as Quest, focusInstance)
                If cursor >= count
                    Utility.WaitMenuMode(0.25)
                Else
                    Utility.WaitMenuMode(0.01)
                EndIf
            Else
                Utility.WaitMenuMode(0.1)
            EndIf
        Else
            Utility.WaitMenuMode(0.1)
        EndIf
    EndWhile
    If processingGeneration == session
        processingGeneration = -1
    EndIf
EndFunction
