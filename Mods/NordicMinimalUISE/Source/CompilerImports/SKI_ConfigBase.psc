Scriptname SKI_ConfigBase Extends Quest Native

Int Property TOP_TO_BOTTOM = 1 AutoReadOnly
String Property ModName Auto
String[] Property Pages Auto

Event OnConfigInit() Native
Event OnPageReset(String page) Native
Event OnOptionSelect(Int option) Native
Event OnOptionSliderOpen(Int option) Native
Event OnOptionSliderAccept(Int option, Float value) Native
Event OnOptionKeyMapChange(Int option, Int keyCode, String conflictControl, String conflictName) Native

Int Function AddHeaderOption(String optionName, Int flags = 0) Native
Int Function AddToggleOption(String optionName, Bool checked, Int flags = 0) Native
Int Function AddSliderOption(String optionName, Float value, String formatString, Int flags = 0) Native
Int Function AddKeyMapOption(String optionName, Int keyCode, Int flags = 0) Native
Function SetCursorFillMode(Int mode) Native
Function SetToggleOptionValue(Int option, Bool checked, Bool noSound = False) Native
Function SetSliderOptionValue(Int option, Float value, String formatString, Bool noSound = False) Native
Function SetKeyMapOptionValue(Int option, Int keyCode, Bool noUpdate = False) Native
Function SetSliderDialogStartValue(Float value) Native
Function SetSliderDialogDefaultValue(Float value) Native
Function SetSliderDialogRange(Float minValue, Float maxValue) Native
Function SetSliderDialogInterval(Float value) Native
