Scriptname AutoPotionMCM extends SKI_ConfigBase

GlobalVariable AutoHealth
GlobalVariable AutoMagicka
GlobalVariable AutoStamina
GlobalVariable HealthThreshold
GlobalVariable MagickaThreshold
GlobalVariable StaminaThreshold
GlobalVariable CooldownSeconds
GlobalVariable OnlyInCombat
GlobalVariable WeakestSufficient

Int optionAutoHealth
Int optionHealthThreshold
Int optionAutoMagicka
Int optionMagickaThreshold
Int optionAutoStamina
Int optionStaminaThreshold
Int optionCooldown
Int optionOnlyInCombat
Int optionWeakestSufficient

Event OnConfigInit()
    ModName = "Auto Potion SE"
    Pages = new String[1]
    Pages[0] = "Ustawienia"
    LoadSettings()
EndEvent

Event OnPageReset(String page)
    If page != "Ustawienia"
        Return
    EndIf

    LoadSettings()
    SetCursorFillMode(TOP_TO_BOTTOM)
    AddHeaderOption("Mikstury")
    optionAutoHealth = AddToggleOption("Automatyczne leczenie", IsEnabled(AutoHealth))
    optionHealthThreshold = AddSliderOption("Próg zdrowia", GetPercent(HealthThreshold, 30.0), "{0}%")
    optionAutoMagicka = AddToggleOption("Automatyczna magicka", IsEnabled(AutoMagicka))
    optionMagickaThreshold = AddSliderOption("Próg magicki", GetPercent(MagickaThreshold, 20.0), "{0}%")
    optionAutoStamina = AddToggleOption("Automatyczna kondycja", IsEnabled(AutoStamina))
    optionStaminaThreshold = AddSliderOption("Próg kondycji", GetPercent(StaminaThreshold, 20.0), "{0}%")
    optionCooldown = AddSliderOption("Cooldown", GetValue(CooldownSeconds, 5.0), "{0} s")
    AddHeaderOption("Zasady używania")
    optionOnlyInCombat = AddToggleOption("Tylko podczas walki", IsEnabled(OnlyInCombat))
    optionWeakestSufficient = AddToggleOption("Najsłabsza wystarczająca mikstura", IsEnabled(WeakestSufficient))
EndEvent

Event OnOptionSelect(Int option)
    If option == optionAutoHealth
        ToggleSetting(AutoHealth)
        SetToggleOptionValue(option, IsEnabled(AutoHealth))
    ElseIf option == optionAutoMagicka
        ToggleSetting(AutoMagicka)
        SetToggleOptionValue(option, IsEnabled(AutoMagicka))
    ElseIf option == optionAutoStamina
        ToggleSetting(AutoStamina)
        SetToggleOptionValue(option, IsEnabled(AutoStamina))
    ElseIf option == optionOnlyInCombat
        ToggleSetting(OnlyInCombat)
        SetToggleOptionValue(option, IsEnabled(OnlyInCombat))
    ElseIf option == optionWeakestSufficient
        ToggleSetting(WeakestSufficient)
        SetToggleOptionValue(option, IsEnabled(WeakestSufficient))
    EndIf
EndEvent

Event OnOptionSliderOpen(Int option)
    If option == optionHealthThreshold
        OpenThresholdSlider(HealthThreshold, 30.0)
    ElseIf option == optionMagickaThreshold
        OpenThresholdSlider(MagickaThreshold, 20.0)
    ElseIf option == optionStaminaThreshold
        OpenThresholdSlider(StaminaThreshold, 20.0)
    ElseIf option == optionCooldown
        SetSliderDialogStartValue(GetValue(CooldownSeconds, 5.0))
        SetSliderDialogDefaultValue(5.0)
        SetSliderDialogRange(1.0, 30.0)
        SetSliderDialogInterval(1.0)
    EndIf
EndEvent

Event OnOptionSliderAccept(Int option, Float value)
    If option == optionHealthThreshold
        SetValue(HealthThreshold, value / 100.0)
        SetSliderOptionValue(option, value, "{0}%")
    ElseIf option == optionMagickaThreshold
        SetValue(MagickaThreshold, value / 100.0)
        SetSliderOptionValue(option, value, "{0}%")
    ElseIf option == optionStaminaThreshold
        SetValue(StaminaThreshold, value / 100.0)
        SetSliderOptionValue(option, value, "{0}%")
    ElseIf option == optionCooldown
        SetValue(CooldownSeconds, value)
        SetSliderOptionValue(option, value, "{0} s")
    EndIf
EndEvent

Function LoadSettings()
    AutoHealth = Game.GetFormFromFile(0x801, "AutoPotionSE.esp") as GlobalVariable
    AutoMagicka = Game.GetFormFromFile(0x802, "AutoPotionSE.esp") as GlobalVariable
    AutoStamina = Game.GetFormFromFile(0x803, "AutoPotionSE.esp") as GlobalVariable
    HealthThreshold = Game.GetFormFromFile(0x804, "AutoPotionSE.esp") as GlobalVariable
    MagickaThreshold = Game.GetFormFromFile(0x805, "AutoPotionSE.esp") as GlobalVariable
    StaminaThreshold = Game.GetFormFromFile(0x806, "AutoPotionSE.esp") as GlobalVariable
    CooldownSeconds = Game.GetFormFromFile(0x807, "AutoPotionSE.esp") as GlobalVariable
    OnlyInCombat = Game.GetFormFromFile(0x808, "AutoPotionSE.esp") as GlobalVariable
    WeakestSufficient = Game.GetFormFromFile(0x809, "AutoPotionSE.esp") as GlobalVariable
EndFunction

Function OpenThresholdSlider(GlobalVariable setting, Float fallback)
    SetSliderDialogStartValue(GetPercent(setting, fallback))
    SetSliderDialogDefaultValue(fallback)
    SetSliderDialogRange(10.0, 80.0)
    SetSliderDialogInterval(5.0)
EndFunction

Float Function GetPercent(GlobalVariable setting, Float fallback)
    Return GetValue(setting, fallback / 100.0) * 100.0
EndFunction

Float Function GetValue(GlobalVariable setting, Float fallback)
    If setting == None
        Return fallback
    EndIf
    Return setting.GetValue()
EndFunction

Bool Function IsEnabled(GlobalVariable setting)
    Return setting != None && setting.GetValue() >= 0.5
EndFunction

Function ToggleSetting(GlobalVariable setting)
    If setting == None
        Return
    EndIf
    If setting.GetValue() >= 0.5
        setting.SetValue(0.0)
    Else
        setting.SetValue(1.0)
    EndIf
EndFunction

Function SetValue(GlobalVariable setting, Float value)
    If setting != None
        setting.SetValue(value)
    EndIf
EndFunction
