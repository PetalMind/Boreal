; Compile-time declarations only; never ship as replacement game scripts.
Scriptname Form Native
String Function GetName() Native
Int Function GetFormID() Native
Bool Function HasKeyword(Keyword akKeyword) Native
Function RegisterForMenu(String menuName) Native
Function UnregisterForAllMenus() Native
Function RegisterForSingleUpdate(Float interval) Native
Function RegisterForModEvent(String eventName, String callbackName) Native
Event OnInit()
EndEvent
Event OnMenuOpen(String menuName)
EndEvent
Event OnMenuClose(String menuName)
EndEvent
Event OnUpdate()
EndEvent
