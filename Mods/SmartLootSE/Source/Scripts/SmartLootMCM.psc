Scriptname SmartLootMCM extends SKI_ConfigBase

Int optionEnabled
Int optionGold
Int optionGems
Int optionPotions
Int optionIngredients
Int optionArrows
Int optionRadius
Int optionInterval

Event OnConfigInit()
    ModName = "Smart Loot SE"
    Pages = new String[1]
    Pages[0] = "Zbieranie"
EndEvent

Event OnPageReset(String page)
    If page != "Zbieranie"
        Return
    EndIf

    SmartLootQuest controller = GetController()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Automatyczne zbieranie")
    optionEnabled = AddToggleOption("Włącz mod", controller != None && controller.Enabled)
    optionGold = AddToggleOption("Zbieraj złoto", controller != None && controller.CollectGold)
    optionGems = AddToggleOption("Zbieraj klejnoty", controller != None && controller.CollectGems)
    optionPotions = AddToggleOption("Zbieraj mikstury", controller != None && controller.CollectPotions)
    optionIngredients = AddToggleOption("Zbieraj składniki", controller != None && controller.CollectIngredients)
    optionArrows = AddToggleOption("Zbieraj strzały", controller != None && controller.CollectArrows)
    AddHeaderOption("Zasięg i częstotliwość")
    optionRadius = AddSliderOption("Promień zbierania", GetRadius(controller), "{0} j.u.")
    optionInterval = AddSliderOption("Odstęp skanowania", GetInterval(controller), "{0} s")
EndEvent

Event OnOptionSelect(Int option)
    SmartLootQuest controller = GetController()
    If controller == None
        Return
    EndIf

    If option == optionEnabled
        controller.Enabled = !controller.Enabled
        SetToggleOptionValue(option, controller.Enabled)
    ElseIf option == optionGold
        controller.CollectGold = !controller.CollectGold
        SetToggleOptionValue(option, controller.CollectGold)
    ElseIf option == optionGems
        controller.CollectGems = !controller.CollectGems
        SetToggleOptionValue(option, controller.CollectGems)
    ElseIf option == optionPotions
        controller.CollectPotions = !controller.CollectPotions
        SetToggleOptionValue(option, controller.CollectPotions)
    ElseIf option == optionIngredients
        controller.CollectIngredients = !controller.CollectIngredients
        SetToggleOptionValue(option, controller.CollectIngredients)
    ElseIf option == optionArrows
        controller.CollectArrows = !controller.CollectArrows
        SetToggleOptionValue(option, controller.CollectArrows)
    EndIf
EndEvent

Event OnOptionSliderOpen(Int option)
    SmartLootQuest controller = GetController()
    If option == optionRadius
        SetSliderDialogStartValue(GetRadius(controller))
        SetSliderDialogDefaultValue(220.0)
        SetSliderDialogRange(128.0, 512.0)
        SetSliderDialogInterval(32.0)
    ElseIf option == optionInterval
        SetSliderDialogStartValue(GetInterval(controller))
        SetSliderDialogDefaultValue(0.5)
        SetSliderDialogRange(0.25, 2.0)
        SetSliderDialogInterval(0.25)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    SmartLootQuest controller = GetController()
    If controller == None
        Return
    EndIf

    If option == optionRadius
        controller.ScanRadius = value
        SetSliderOptionValue(option, value, "{0} j.u.")
    ElseIf option == optionInterval
        controller.ScanInterval = value
        SetSliderOptionValue(option, value, "{0} s")
    EndIf
EndEvent

SmartLootQuest Function GetController()
    Return Game.GetFormFromFile(0x800, "SmartLoot.esp") as SmartLootQuest
EndFunction

Float Function GetRadius(SmartLootQuest controller)
    If controller == None
        Return 220.0
    EndIf
    Return controller.ScanRadius
EndFunction

Float Function GetInterval(SmartLootQuest controller)
    If controller == None
        Return 0.5
    EndIf
    Return controller.ScanInterval
EndFunction
