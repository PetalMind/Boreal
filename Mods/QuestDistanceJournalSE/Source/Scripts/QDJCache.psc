Scriptname QDJCache extends Quest

Quest[] savedQuests
Int[] savedInstances
String[] savedSignatures
String[] savedPlaces
String[] savedLabels
String[] savedTitles
ObjectReference[] savedTargets
Location[] savedLocations
ObjectReference[] savedOrigins
ObjectReference[] savedEndpoints
Cell[] savedPlayerCells
Cell[] savedTargetCells
Int[] savedDistanceKinds
Int nextSlot
Int focusSlot = -1
Int cacheVersion

Function Initialise()
    ; Saves can retain a partially allocated cache after interrupted upgrades.
    ; Repair each array independently before allowing any indexed access.
    If savedQuests == None
        savedQuests = new Quest[128]
    EndIf
    If savedInstances == None
        savedInstances = new Int[128]
    EndIf
    If savedSignatures == None
        savedSignatures = new String[128]
    EndIf
    If savedPlaces == None
        savedPlaces = new String[128]
    EndIf
    If savedLabels == None
        savedLabels = new String[128]
    EndIf
    If savedTitles == None
        savedTitles = new String[128]
    EndIf
    If savedTargets == None
        savedTargets = new ObjectReference[128]
    EndIf
    If savedLocations == None
        savedLocations = new Location[128]
    EndIf
    If savedOrigins == None
        savedOrigins = new ObjectReference[128]
    EndIf
    If savedEndpoints == None
        savedEndpoints = new ObjectReference[128]
    EndIf
    If savedPlayerCells == None
        savedPlayerCells = new Cell[128]
    EndIf
    If savedTargetCells == None
        savedTargetCells = new Cell[128]
    EndIf
    If savedDistanceKinds == None
        savedDistanceKinds = new Int[128]
    EndIf
    If !IsReady()
        Debug.Trace("[QDJ] Cache allocation incomplete; retrying on next update.", 2)
        Return
    EndIf
    If cacheVersion < 131
        Invalidate()
        cacheVersion = 131
    EndIf
EndFunction

Bool Function IsReady()
    If savedQuests == None
        Return False
    EndIf
    If savedInstances == None
        Return False
    EndIf
    If savedSignatures == None
        Return False
    EndIf
    If savedPlaces == None
        Return False
    EndIf
    If savedLabels == None
        Return False
    EndIf
    If savedTitles == None
        Return False
    EndIf
    If savedTargets == None
        Return False
    EndIf
    If savedLocations == None
        Return False
    EndIf
    If savedOrigins == None
        Return False
    EndIf
    If savedEndpoints == None
        Return False
    EndIf
    If savedPlayerCells == None
        Return False
    EndIf
    If savedTargetCells == None
        Return False
    EndIf
    If savedDistanceKinds == None
        Return False
    EndIf
    Return True
EndFunction

Function Invalidate()
    If savedSignatures == None
        Return
    EndIf
    Int i = 0
    While i < savedSignatures.Length
        savedSignatures[i] = ""
        savedPlayerCells[i] = None
        savedTargetCells[i] = None
        i += 1
    EndWhile
EndFunction

Int Function Count()
    Initialise()
    If !IsReady()
        Return 0
    EndIf
    Int total = 0
    Int i = 0
    While i < 128
        If savedQuests[i] != None && !savedQuests[i].IsCompleted()
            total += 1
        EndIf
        i += 1
    EndWhile
    Return total
EndFunction

Int Function Find(Quest task, Int instanceID)
    Initialise()
    If !IsReady()
        Return -1
    EndIf
    Int i = 0
    While i < 128
        If savedQuests[i] == task && savedInstances[i] == instanceID
            Return i
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

Int Function Remember(Quest task, Int instanceID, String title = "")
    Initialise()
    If !IsReady() || task == None
        Return -1
    EndIf
    Int slot = Find(task, instanceID)
    If slot < 0
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
        savedOrigins[slot] = None
        savedEndpoints[slot] = None
        savedPlayerCells[slot] = None
        savedTargetCells[slot] = None
        savedTitles[slot] = task.GetName()
    EndIf
    If title != ""
        savedTitles[slot] = title
    EndIf
    Refresh(slot)
    Return slot
EndFunction

Function Refresh(Int slot)
    If !IsReady() || slot < 0 || slot >= 128 || savedQuests[slot] == None
        Return
    EndIf
    Quest task = savedQuests[slot]
    String signature = QDJTargetResolver.Signature(task)
    Bool changed = signature != savedSignatures[slot]
    If changed
        savedTargets[slot] = QDJTargetResolver.FindTarget(task)
        savedSignatures[slot] = signature
        savedLocations[slot] = None
    EndIf
    ObjectReference target = savedTargets[slot]
    Actor player = Game.GetPlayer()
    If target == None || player == None
        savedOrigins[slot] = None
        savedEndpoints[slot] = None
        savedPlaces[slot] = "Lokalizacja celu niedostępna"
        savedLabels[slot] = savedPlaces[slot] + " | odległość niedostępna"
        Return
    EndIf
    Location currentPlace = target.GetCurrentLocation()
    If changed || currentPlace != savedLocations[slot] || savedPlaces[slot] == ""
        savedPlaces[slot] = QDJTargetResolver.PlaceName(target)
        savedLocations[slot] = currentPlace
    EndIf
    Cell playerCell = player.GetParentCell()
    Cell targetCell = target.GetParentCell()
    If changed || playerCell != savedPlayerCells[slot] || targetCell != savedTargetCells[slot] || savedEndpoints[slot] == None
        ObjectReference[] route = QDJNavigation.Resolve(player, target)
        savedOrigins[slot] = route[0]
        savedEndpoints[slot] = route[1]
        savedPlayerCells[slot] = playerCell
        savedTargetCells[slot] = targetCell
        Int kind = 0
        If route[0] != player
            kind += 2
        EndIf
        If route[1] != target
            kind += 1
        EndIf
        savedDistanceKinds[slot] = kind
    EndIf
    savedLabels[slot] = savedPlaces[slot] + " | " + QDJNavigation.DistanceLabel(Distance(slot), savedDistanceKinds[slot])
EndFunction

Float Function Distance(Int slot)
    If !IsReady() || slot < 0 || slot >= 128
        Return -1.0
    EndIf
    Return QDJTargetResolver.ComparableDistance(savedOrigins[slot], savedEndpoints[slot])
EndFunction

String Function Place(Int slot)
    If !IsReady() || slot < 0 || slot >= 128
        Return ""
    EndIf
    If savedTargets[slot] == None
        Return ""
    EndIf
    Return savedPlaces[slot]
EndFunction

String Function Label(Int slot)
    If !IsReady() || slot < 0 || slot >= 128
        Return "Lokalizacja i odległość niedostępne"
    EndIf
    Return savedLabels[slot]
EndFunction

Function Select(Quest task, Int instanceID)
    If task != None && task.IsActive() && !task.IsCompleted()
        Int slot = Find(task, instanceID)
        If slot < 0
            slot = Remember(task, instanceID)
        EndIf
        focusSlot = slot
    EndIf
EndFunction

Int Function Focus()
    Initialise()
    If !IsReady()
        Return -1
    EndIf
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
    If !IsReady() || slot < 0 || savedQuests[slot] == None
        Return ""
    EndIf
    String title = savedTitles[slot]
    If title == ""
        title = "Wybrane zadanie"
    EndIf
    Return title + " | " + QDJNavigation.DistanceLabel(Distance(slot), savedDistanceKinds[slot])
EndFunction
