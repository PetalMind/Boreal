Scriptname PotionGlowMCM extends SKI_ConfigBase

Int enabledOption
Int poisonOption
Int sightOption
Int radiusOption
Int intervalOption

Event OnConfigInit()
    ModName = "Potion Glow SE"
    Pages = new String[1]
    Pages[0] = "Podświetlanie"
EndEvent

Event OnPageReset(String page)
    If page != "Podświetlanie" && page != ""
        Return
    EndIf
    SetCursorFillMode(TOP_TO_BOTTOM)
    PotionGlowQuest controller = GetController()
    If controller == None
        AddTextOption("Błąd: quest moda jest niedostępny", "Sprawdź aktywację ESP", 1)
        Return
    EndIf
    AddHeaderOption("Poświata mikstur")
    If !controller.IsAvailable()
        AddTextOption("Brak efektu poświaty", "Włącz Unread Books Glow 2.2.1", 1)
    EndIf
    enabledOption = AddToggleOption("Włącz podświetlanie", controller.Enabled)
    poisonOption = AddToggleOption("Podświetlaj także trucizny", controller.IncludePoisons)
    sightOption = AddToggleOption("Tylko widoczne przedmioty", controller.RequireLineOfSight)
    radiusOption = AddSliderOption("Zasięg", controller.ScanRadius, "{0} j.u.")
    intervalOption = AddSliderOption("Odstęp odświeżania", controller.ScanInterval, "{1} s")
    AddTextOption("Efekt", "Zielona poświata tomów zaklęć", 1)
EndEvent

Event OnOptionSelect(Int option)
    PotionGlowQuest controller = GetController()
    If controller == None
        Return
    EndIf
    If option == enabledOption
        controller.Enabled = !controller.Enabled
        SetToggleOptionValue(option, controller.Enabled)
    ElseIf option == poisonOption
        controller.IncludePoisons = !controller.IncludePoisons
        SetToggleOptionValue(option, controller.IncludePoisons)
    ElseIf option == sightOption
        controller.RequireLineOfSight = !controller.RequireLineOfSight
        SetToggleOptionValue(option, controller.RequireLineOfSight)
    EndIf
    controller.Maintenance()
EndEvent

Event OnOptionSliderOpen(Int option)
    PotionGlowQuest controller = GetController()
    If controller == None
        Return
    EndIf
    If option == radiusOption
        SetSliderDialogStartValue(controller.ScanRadius)
        SetSliderDialogDefaultValue(1200.0)
        SetSliderDialogRange(256.0, 2400.0)
        SetSliderDialogInterval(64.0)
    ElseIf option == intervalOption
        SetSliderDialogStartValue(controller.ScanInterval)
        SetSliderDialogDefaultValue(1.0)
        SetSliderDialogRange(0.5, 3.0)
        SetSliderDialogInterval(0.5)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    PotionGlowQuest controller = GetController()
    If controller == None
        Return
    EndIf
    If option == radiusOption && value >= 256.0 && value <= 2400.0
        controller.ScanRadius = value
        SetSliderOptionValue(option, value, "{0} j.u.")
    ElseIf option == intervalOption && value >= 0.5 && value <= 3.0
        controller.ScanInterval = value
        SetSliderOptionValue(option, value, "{1} s")
    EndIf
    controller.Maintenance()
EndEvent

PotionGlowQuest Function GetController()
    Return Game.GetFormFromFile(0x800, "PotionGlowSE.esp") as PotionGlowQuest
EndFunction
