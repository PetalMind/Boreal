Scriptname SKI_ConfigBase Extends Quest Native

Int Property TOP_TO_BOTTOM = 2 AutoReadOnly
String Property ModName Auto
String[] Property Pages Auto

Event OnConfigInit() Native
Event OnPageReset(String page) Native
Event OnOptionSelect(Int option) Native
Event OnOptionSliderOpen(Int option) Native
Event OnOptionSliderAccept(Int option, Float value) Native

Int Function AddHeaderOption(String optionName, Int flags = 0) Native
Int Function AddToggleOption(String optionName, Bool checked, Int flags = 0) Native
Int Function AddSliderOption(String optionName, Float value, String formatString, Int flags = 0) Native
Function SetCursorFillMode(Int mode) Native
Function SetToggleOptionValue(Int option, Bool checked, Bool noSound = False) Native
Function SetSliderOptionValue(Int option, Float value, String formatString, Bool noSound = False) Native
Function SetSliderDialogStartValue(Float value) Native
Function SetSliderDialogDefaultValue(Float value) Native
Function SetSliderDialogRange(Float minValue, Float maxValue) Native
Function SetSliderDialogInterval(Float value) Native

Event OnConfigOpen() Native
Event OnGameReload() Native

Int Function AddTextOption(String optionName, String value, Int flags = 0) Native
