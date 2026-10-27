Scriptname QDJMCM extends SKI_ConfigBase

Int compassOption
Int sortOption
Int trackedOption
Int detailsOption
Int refreshOption

Int Function GetVersion()
    Return 131
EndFunction

Event OnConfigInit()
    ConfigurePages()
EndEvent

Event OnVersionUpdate(Int version)
    ConfigurePages()
EndEvent

Event OnConfigOpen()
    ConfigurePages()
    QDJController controller = Game.GetFormFromFile(0x800, "QuestDistanceJournalSE.esp") as QDJController
    If controller != None
        controller.Initialise()
    EndIf
EndEvent

Function ConfigurePages()
    ModName = "Quest Distance Journal SE"
    Pages = new String[1]
    Pages[0] = "Dziennik i kompas"
EndFunction

Event OnPageReset(String page)
    If page != "Dziennik i kompas"
        Return
    EndIf
    QDJCompass compass = GetCompass()
    If !QDJSettings.IsAvailable() || compass == None
        AddHeaderOption("Konfiguracja jest niedostępna")
        Return
    EndIf
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Lista zadań")
    sortOption = AddMenuOption("Sortowanie", SortName(QDJSettings.GetSortMode()))
    trackedOption = AddToggleOption("Śledzone zadania na początku", QDJSettings.TrackedFirst())
    detailsOption = AddToggleOption("Pokaż miejscowość i metry", QDJSettings.ShowDetails())
    AddHeaderOption("Kompas")
    compassOption = AddToggleOption("Pokaż odległość do śledzonego zadania", compass.CompassEnabled)
    AddHeaderOption("Odświeżanie danych")
    refreshOption = AddTextOption("Przelicz cele i napraw rejestrację", "Odśwież")
    QDJCache cache = Game.GetFormFromFile(0x800, "QuestDistanceJournalSE.esp") as QDJCache
    If cache != None
        AddTextOption("Zadania w pamięci", cache.Count() as String, 1)
    EndIf
EndEvent

Event OnOptionSelect(Int option)
    QDJCompass compass = GetCompass()
    If !QDJSettings.IsAvailable() || compass == None
        Return
    EndIf
    If option == compassOption
        compass.SetEnabled(!compass.CompassEnabled)
        SetToggleOptionValue(option, compass.CompassEnabled)
    ElseIf option == trackedOption
        QDJSettings.SetTrackedFirst(!QDJSettings.TrackedFirst())
        SetToggleOptionValue(option, QDJSettings.TrackedFirst())
    ElseIf option == detailsOption
        QDJSettings.SetShowDetails(!QDJSettings.ShowDetails())
        SetToggleOptionValue(option, QDJSettings.ShowDetails())
    ElseIf option == refreshOption
        QDJCache cache = Game.GetFormFromFile(0x800, "QuestDistanceJournalSE.esp") as QDJCache
        QDJController controller = Game.GetFormFromFile(0x800, "QuestDistanceJournalSE.esp") as QDJController
        If cache != None && controller != None
            cache.Invalidate()
            controller.Initialise()
            ShowMessage("Cele zostaną ponownie odczytane przy otwarciu listy zadań.", False)
        EndIf
    EndIf
EndEvent

Event OnOptionMenuOpen(Int option)
    If option != sortOption
        Return
    EndIf
    String[] modes = new String[4]
    modes[0] = "Miejscowość i odległość"
    modes[1] = "Najbliższe cele"
    modes[2] = "Nazwa zadania"
    modes[3] = "Kolejność gry"
    SetMenuDialogOptions(modes)
    SetMenuDialogStartIndex(QDJSettings.GetSortMode())
    SetMenuDialogDefaultIndex(0)
EndEvent

Event OnOptionMenuAccept(Int option, Int index)
    If option == sortOption && index >= 0 && index <= 3
        QDJSettings.SetSortMode(index)
        SetMenuOptionValue(option, SortName(index))
    EndIf
EndEvent

String Function SortName(Int mode)
    If mode == 1
        Return "Najbliższe cele"
    ElseIf mode == 2
        Return "Nazwa zadania"
    ElseIf mode == 3
        Return "Kolejność gry"
    EndIf
    Return "Miejscowość i odległość"
EndFunction

QDJCompass Function GetCompass()
    Return Game.GetFormFromFile(0x800, "QuestDistanceJournalSE.esp") as QDJCompass
EndFunction
