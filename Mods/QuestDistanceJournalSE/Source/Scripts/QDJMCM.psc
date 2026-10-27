Scriptname QDJMCM extends SKI_ConfigBase

Int compassOption

Event OnConfigInit()
    ModName = "Quest Distance Journal SE"
    Pages = new String[1]
    Pages[0] = "Kompas"
EndEvent

Event OnPageReset(String page)
    If page != "Kompas"
        Return
    EndIf

    QDJCompass compass = GetCompass()
    Bool enabled = True
    If compass != None
        enabled = compass.CompassEnabled
    EndIf
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Odległość do zadania")
    compassOption = AddToggleOption("Pokaż cel aktywnego zadania pod kompasem", enabled)
EndEvent

Event OnOptionSelect(Int option)
    If option != compassOption
        Return
    EndIf

    QDJCompass compass = GetCompass()
    If compass == None
        Return
    EndIf

    compass.SetEnabled(!compass.CompassEnabled)
    SetToggleOptionValue(option, compass.CompassEnabled)
EndEvent

QDJCompass Function GetCompass()
    Return Game.GetFormFromFile(0x800, "QuestDistanceJournalSE.esp") as QDJCompass
EndFunction
