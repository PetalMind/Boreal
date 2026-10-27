; Compile-time declarations only; never ship as replacement game scripts.
Scriptname Form Native
String Function GetName() Native
Bool Function HasKeyword(Keyword akKeyword) Native
Function RegisterForMenu(String menuName) Native
Function UnregisterForAllMenus() Native
Event OnInit()
EndEvent
Event OnMenuOpen(String menuName)
EndEvent
Event OnMenuClose(String menuName)
EndEvent
