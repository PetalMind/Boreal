Scriptname SKI_ConfigBase Extends Quest Native

Int Property TOP_TO_BOTTOM = 2 AutoReadOnly
String Property ModName Auto
String[] Property Pages Auto

Event OnConfigInit() Native
Event OnPageReset(String page) Native
Event OnOptionKeyMapChange(Int option, Int keyCode, String conflictControl, String conflictName) Native

Int Function AddHeaderOption(String name, Int flags = 0) Native
Int Function AddKeyMapOption(String name, Int keyCode, Int flags = 0) Native
Function SetCursorFillMode(Int mode) Native
Function SetKeyMapOptionValue(Int option, Int keyCode, Bool noUpdate = False) Native

Event OnConfigOpen() Native
Event OnGameReload() Native
Event OnVersionUpdate(Int version) Native
Event OnOptionSelect(Int option) Native
Event OnOptionDefault(Int option) Native
Event OnOptionSliderOpen(Int option) Native
Event OnOptionSliderAccept(Int option, Float value) Native
Int Function GetVersion() Native
Int Function AddToggleOption(String name, Bool checked, Int flags = 0) Native
Int Function AddSliderOption(String name, Float value, String formatString, Int flags = 0) Native
Int Function AddTextOption(String name, String value, Int flags = 0) Native
Function SetToggleOptionValue(Int option, Bool checked, Bool noUpdate = False) Native
Function SetSliderOptionValue(Int option, Float value, String formatString, Bool noUpdate = False) Native
Function SetSliderDialogStartValue(Float value) Native
Function SetSliderDialogDefaultValue(Float value) Native
Function SetSliderDialogRange(Float minimum, Float maximum) Native
Function SetSliderDialogInterval(Float value) Native
Bool Function ShowMessage(String message, Bool withCancel = True, String acceptLabel = "$Accept", String cancelLabel = "$Cancel") Native
