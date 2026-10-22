Scriptname SKI_ConfigBase Extends Quest Native

Int Property TOP_TO_BOTTOM = 1 AutoReadOnly
Int Property OPTION_FLAG_DISABLED = 1 AutoReadOnly
String Property ModName Auto
String[] Property Pages Auto

Event OnConfigInit() Native
Event OnPageReset(String page) Native
Event OnOptionMenuOpen(Int option) Native
Event OnOptionMenuAccept(Int option, Int index) Native

Int Function AddHeaderOption(String optionName, Int flags = 0) Native
Int Function AddMenuOption(String optionName, String value, Int flags = 0) Native
Int Function AddTextOption(String optionName, String value, Int flags = 0) Native
Function SetCursorFillMode(Int mode) Native
Function SetMenuDialogStartIndex(Int value) Native
Function SetMenuDialogDefaultIndex(Int value) Native
Function SetMenuDialogOptions(String[] options) Native
Function ForcePageReset() Native
