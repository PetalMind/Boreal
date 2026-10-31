Scriptname QDJCache extends Quest

Form[] cachedQuests
Int[] cacheInstances
String[] cacheSignatures
String[] cachePlaces
String[] cacheLabels
String[] cacheTitles
Form[] cacheTargets
Form[] cacheLocations
Form[] cachedOrigins
Form[] cachedEndpoints
Form[] cachePlayerCells
Form[] cacheTargetCells
Int[] cacheDistanceKinds
Int nextSlot
Int focusSlot = -1
Int cacheVersion

Function Initialise()
    ; Rebuilt cache fields do not reuse broken typed arrays from older saves.
    ; Form arrays use SKSE allocation; specific references are cast on read.
    ; Repair each array independently before allowing any indexed access.
    If !cachedQuests
        cachedQuests = Utility.CreateFormArray(128, None)
    EndIf
    If !cacheInstances
        cacheInstances = new Int[128]
    EndIf
    If !cacheSignatures
        cacheSignatures = new String[128]
    EndIf
    If !cachePlaces
        cachePlaces = new String[128]
    EndIf
    If !cacheLabels
        cacheLabels = new String[128]
    EndIf
    If !cacheTitles
        cacheTitles = new String[128]
    EndIf
    If !cacheTargets
        cacheTargets = Utility.CreateFormArray(128, None)
    EndIf
    If !cacheLocations
        cacheLocations = Utility.CreateFormArray(128, None)
    EndIf
    If !cachedOrigins
        cachedOrigins = Utility.CreateFormArray(128, None)
    EndIf
    If !cachedEndpoints
        cachedEndpoints = Utility.CreateFormArray(128, None)
    EndIf
    If !cachePlayerCells
        cachePlayerCells = Utility.CreateFormArray(128, None)
    EndIf
    If !cacheTargetCells
        cacheTargetCells = Utility.CreateFormArray(128, None)
    EndIf
    If !cacheDistanceKinds
        cacheDistanceKinds = new Int[128]
    EndIf
    If !IsReady()
        Debug.Trace("[QDJ] Cache allocation incomplete; retrying on next update.", 2)
        Return
    EndIf
    If cacheVersion < 133
        Invalidate()
        cacheVersion = 133
    EndIf
EndFunction

Bool Function IsReady()
    If !cachedQuests
        Return False
    EndIf
    If !cacheInstances
        Return False
    EndIf
    If !cacheSignatures
        Return False
    EndIf
    If !cachePlaces
        Return False
    EndIf
    If !cacheLabels
        Return False
    EndIf
    If !cacheTitles
        Return False
    EndIf
    If !cacheTargets
        Return False
    EndIf
    If !cacheLocations
        Return False
    EndIf
    If !cachedOrigins
        Return False
    EndIf
    If !cachedEndpoints
        Return False
    EndIf
    If !cachePlayerCells
        Return False
    EndIf
    If !cacheTargetCells
        Return False
    EndIf
    If !cacheDistanceKinds
        Return False
    EndIf
    Return True
EndFunction

Function Invalidate()
    If !cacheSignatures
        Return
    EndIf
    Int i = 0
    While i < cacheSignatures.Length
        cacheSignatures[i] = ""
        cachePlayerCells[i] = None
        cacheTargetCells[i] = None
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
        If cachedQuests[i] == task && cacheInstances[i] == instanceID
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
        cacheInstances[slot] = instanceID
        cacheSignatures[slot] = ""
        cacheTargets[slot] = None
        cacheLocations[slot] = None
        cachedOrigins[slot] = None
        cachedEndpoints[slot] = None
        cachePlayerCells[slot] = None
        cacheTargetCells[slot] = None
        cacheTitles[slot] = task.GetName()
    EndIf
    If title != ""
        cacheTitles[slot] = title
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
    Bool changed = signature != cacheSignatures[slot]
    If changed
        cacheTargets[slot] = QDJTargetResolver.FindTarget(task)
        cacheSignatures[slot] = signature
        cacheLocations[slot] = None
    EndIf
    ObjectReference target = cacheTargets[slot] as ObjectReference
    Actor player = Game.GetPlayer()
    If target == None || player == None
        cachedOrigins[slot] = None
        cachedEndpoints[slot] = None
        cachePlaces[slot] = "Lokalizacja celu niedostępna"
        cacheLabels[slot] = cachePlaces[slot] + " | odległość niedostępna"
        Return
    EndIf
    Location currentPlace = target.GetCurrentLocation()
    If changed || currentPlace != cacheLocations[slot] || cachePlaces[slot] == ""
        cachePlaces[slot] = QDJTargetResolver.PlaceName(target)
        cacheLocations[slot] = currentPlace
    EndIf
    Cell playerCell = player.GetParentCell()
    Cell targetCell = target.GetParentCell()
    If changed || playerCell != cachePlayerCells[slot] || targetCell != cacheTargetCells[slot] || cachedEndpoints[slot] == None
        ObjectReference[] route = QDJNavigation.Resolve(player, target)
        cachedOrigins[slot] = route[0]
        cachedEndpoints[slot] = route[1]
        cachePlayerCells[slot] = playerCell
        cacheTargetCells[slot] = targetCell
        Int kind = 0
        If route[0] != player
            kind += 2
        EndIf
        If route[1] != target
            kind += 1
        EndIf
        cacheDistanceKinds[slot] = kind
    EndIf
    cacheLabels[slot] = cachePlaces[slot] + " | " + QDJNavigation.DistanceLabel(Distance(slot), cacheDistanceKinds[slot])
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
    If cacheTargets[slot] == None
        Return ""
    EndIf
    Return cachePlaces[slot]
EndFunction

String Function Label(Int slot)
    If !IsReady() || slot < 0 || slot >= 128
        Return "Lokalizacja i odległość niedostępne"
    EndIf
    Return cacheLabels[slot]
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
    String title = cacheTitles[slot]
    If title == ""
        title = "Wybrane zadanie"
    EndIf
    Return title + " | " + QDJNavigation.DistanceLabel(Distance(slot), cacheDistanceKinds[slot])
EndFunction
