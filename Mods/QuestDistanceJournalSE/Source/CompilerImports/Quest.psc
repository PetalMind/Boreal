; Compile-time declarations only; never ship as replacement game scripts.
Scriptname Quest extends Form Native
Alias Function GetAlias(Int aiAliasID) Native
String Function GetID() Native
Bool Function IsObjectiveDisplayed(Int aiObjective) Native
Bool Function IsObjectiveCompleted(Int aiObjective) Native
Bool Function IsObjectiveFailed(Int aiObjective) Native
Int Function GetCurrentStageID() Native
Bool Function IsActive() Native
Bool Function IsCompleted() Native

; Registered SKSE ModEvent callback signatures. Compile-time prototypes only;
; SKSE dispatches these named events, not Skyrim's native Quest event table.
Event OnJournalReady(String eventName, String text, Float number, Form sender)
EndEvent
Event OnSortChanged(String eventName, String text, Float number, Form sender)
EndEvent
