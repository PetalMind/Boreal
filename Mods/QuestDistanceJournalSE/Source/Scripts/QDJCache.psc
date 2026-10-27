Scriptname QDJCache extends Quest

; Quest variables and reference arrays are persisted by Skyrim in each save.
Quest[] savedQuests
Int[] savedInstances
String[] savedSignatures
String[] savedPlaces
String[] savedLabels
ObjectReference[] savedTargets
Location[] savedLocations
Int nextSlot
Int focusSlot = -1

Function Initialise()
    If savedQuests == None
        savedQuests = new Quest[128]
        savedInstances = new Int[128]
        savedSignatures = new String[128]
        savedPlaces = new String[128]
        savedLabels = new String[128]
        savedTargets = new ObjectReference[128]
        savedLocations = new Location[128]
    EndIf
EndFunction

Int Function Find(Quest task, Int instanceID)
    Initialise()
    Int i = 0
    While i < savedQuests.Length
        If savedQuests[i] == task && savedInstances[i] == instanceID
            Return i
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

Int Function Remember(Quest task, Int instanceID)
    Int slot = Find(task, instanceID)
    If slot >= 0
        Return slot
    EndIf
    slot = nextSlot
    nextSlot = (nextSlot + 1) % 128
    If focusSlot == slot
        focusSlot = -1
    EndIf
    savedQuests[slot] = task
    savedInstances[slot] = instanceID
    savedSignatures[slot] = ""
    savedTargets[slot] = None
    savedLocations[slot] = None
    Refresh(slot)
    Return slot
EndFunction

Function Refresh(Int slot)
    If savedQuests == None || slot < 0 || slot >= 128 || savedQuests[slot] == None
        Return
    EndIf
    Quest task = savedQuests[slot]
    String signature = QDJTargetResolver.Signature(task)
    If signature != savedSignatures[slot]
        savedTargets[slot] = QDJTargetResolver.FindTarget(task)
        If savedTargets[slot] != None
            savedPlaces[slot] = QDJTargetResolver.PlaceName(savedTargets[slot])
            savedLocations[slot] = savedTargets[slot].GetCurrentLocation()
        Else
            savedPlaces[slot] = "Cel bez pewnej lokalizacji"
        EndIf
        savedSignatures[slot] = signature
    EndIf
    If savedTargets[slot] != None
        Location currentPlace = savedTargets[slot].GetCurrentLocation()
        If currentPlace != savedLocations[slot]
            savedPlaces[slot] = QDJTargetResolver.PlaceName(savedTargets[slot])
            savedLocations[slot] = currentPlace
        EndIf
    EndIf
    Float distance = QDJTargetResolver.ComparableDistance(Game.GetPlayer(), savedTargets[slot])
    If distance >= 0.0
        savedLabels[slot] = savedPlaces[slot] + " | " + QDJTargetResolver.FormatDistance(distance)
    ElseIf savedTargets[slot] != None
        savedLabels[slot] = savedPlaces[slot] + " | odległość niedostępna"
    Else
        savedLabels[slot] = savedPlaces[slot]
    EndIf
EndFunction

String Function Label(Int slot)
    If slot < 0 || slot >= 128
        Return "Cel bez danych"
    EndIf
    Return savedLabels[slot]
EndFunction

Function Select(Quest task, Int instanceID)
    If task != None && task.IsActive() && !task.IsCompleted()
        focusSlot = Remember(task, instanceID)
    EndIf
EndFunction

Int Function Focus()
    Initialise()
    If focusSlot >= 0 && savedQuests[focusSlot] != None
        If savedQuests[focusSlot].IsActive() && !savedQuests[focusSlot].IsCompleted()
            Return focusSlot
        EndIf
    EndIf
    focusSlot = -1
    Int i = 0
    While i < 128
        If savedQuests[i] != None
            If savedQuests[i].IsActive() && !savedQuests[i].IsCompleted()
                focusSlot = i
                Return i
            EndIf
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

String Function CompassLabel(Int slot)
    If slot < 0 || savedQuests[slot] == None
        Return ""
    EndIf
    Float distance = QDJTargetResolver.ComparableDistance(Game.GetPlayer(), savedTargets[slot])
    If distance >= 0.0
        Return savedQuests[slot].GetName() + " | " + ((distance + 0.5) as Int) + " m"
    EndIf
    Return savedQuests[slot].GetName() + " | odległość niedostępna"
EndFunction
