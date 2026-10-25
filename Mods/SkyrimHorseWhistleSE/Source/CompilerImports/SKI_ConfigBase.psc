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
