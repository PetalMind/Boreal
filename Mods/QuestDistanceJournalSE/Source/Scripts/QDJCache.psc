Scriptname QDJCache extends Quest

Form[] cachedQuests
Int[] savedInstances
String[] savedSignatures
String[] savedPlaces
String[] savedLabels
String[] savedTitles
ObjectReference[] savedTargets
Location[] savedLocations
Form[] cachedOrigins
Form[] cachedEndpoints
Cell[] savedPlayerCells
Cell[] savedTargetCells
Int[] savedDistanceKinds
Int nextSlot
Int focusSlot = -1
Int cacheVersion

Function Initialise()
    ; Saves can retain a partially allocated cache after interrupted upgrades.
    ; Repair each array independently before allowing any indexed access.
    If !cachedQuests
        cachedQuests = Utility.CreateFormArray(128, None)
    EndIf
    If !savedInstances
        savedInstances = new Int[128]
    EndIf
    If !savedSignatures
        savedSignatures = new String[128]
    EndIf
    If !savedPlaces
        savedPlaces = new String[128]
    EndIf
    If !savedLabels
        savedLabels = new String[128]
    EndIf
    If !savedTitles
        savedTitles = new String[128]
    EndIf
    If !savedTargets
        savedTargets = new ObjectReference[128]
    EndIf
    If !savedLocations
        savedLocations = new Location[128]
    EndIf
    If !cachedOrigins
        cachedOrigins = Utility.CreateFormArray(128, None)
    EndIf
    If !cachedEndpoints
        cachedEndpoints = Utility.CreateFormArray(128, None)
    EndIf
    If !savedPlayerCells
        savedPlayerCells = new Cell[128]
    EndIf
    If !savedTargetCells
        savedTargetCells = new Cell[128]
    EndIf
    If !savedDistanceKinds
        savedDistanceKinds = new Int[128]
    EndIf
    If !IsReady()
        Debug.Trace("[QDJ] Cache allocation incomplete; retrying on next update.", 2)
        Return
    EndIf
    If cacheVersion < 132
        Invalidate()
        cacheVersion = 132
    EndIf
EndFunction

Bool Function IsReady()
    If !cachedQuests
        Return False
    EndIf
    If !savedInstances
        Return False
    EndIf
    If !savedSignatures
        Return False
    EndIf
    If !savedPlaces
        Return False
    EndIf
    If !savedLabels
        Return False
    EndIf
    If !savedTitles
        Return False
    EndIf
    If !savedTargets
        Return False
    EndIf
    If !savedLocations
        Return False
    EndIf
    If !cachedOrigins
        Return False
    EndIf
    If !cachedEndpoints
        Return False
    EndIf
    If !savedPlayerCells
        Return False
    EndIf
    If !savedTargetCells
        Return False
    EndIf
    If !savedDistanceKinds
        Return False
    EndIf
    Return True
EndFunction

Function Invalidate()
    If !savedSignatures
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
        If cachedQuests[i] != None && !(cachedQuests[i] as Quest).IsCompleted()
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
        If cachedQuests[i] == task && savedInstances[i] == instanceID
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
        cachedQuests[slot] = task
        savedInstances[slot] = instanceID
        savedSignatures[slot] = ""
        savedTargets[slot] = None
        savedLocations[slot] = None
        cachedOrigins[slot] = None
        cachedEndpoints[slot] = None
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
    If !IsReady() || slot < 0 || slot >= 128 || cachedQuests[slot] == None
        Return
    EndIf
    Quest task = cachedQuests[slot] as Quest
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
        cachedOrigins[slot] = None
        cachedEndpoints[slot] = None
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
    If changed || playerCell != savedPlayerCells[slot] || targetCell != savedTargetCells[slot] || cachedEndpoints[slot] == None
        ObjectReference[] route = QDJNavigation.Resolve(player, target)
        cachedOrigins[slot] = route[0]
        cachedEndpoints[slot] = route[1]
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
    Return QDJTargetResolver.ComparableDistance(cachedOrigins[slot] as ObjectReference, cachedEndpoints[slot] as ObjectReference)
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
    If focusSlot >= 0 && cachedQuests[focusSlot] != None
        If (cachedQuests[focusSlot] as Quest).IsActive() && !(cachedQuests[focusSlot] as Quest).IsCompleted()
            Return focusSlot
        EndIf
    EndIf
    focusSlot = -1
    Int i = 0
    While i < 128
        If cachedQuests[i] != None
            If (cachedQuests[i] as Quest).IsActive() && !(cachedQuests[i] as Quest).IsCompleted()
                focusSlot = i
                Return i
            EndIf
        EndIf
        i += 1
    EndWhile
    Return -1
EndFunction

String Function CompassLabel(Int slot)
    If !IsReady() || slot < 0 || cachedQuests[slot] == None
        Return ""
    EndIf
    String title = savedTitles[slot]
    If title == ""
        title = "Wybrane zadanie"
    EndIf
    Return title + " | " + QDJNavigation.DistanceLabel(Distance(slot), savedDistanceKinds[slot])
EndFunction
