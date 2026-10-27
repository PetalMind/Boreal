Scriptname QDJNavigation Hidden

; Prefer the player's real position. Project an interior only onto actual
; teleport-door entrances indexed from the winning game/plugin records.
ObjectReference[] Function Resolve(Actor player, ObjectReference target) Global
    ObjectReference[] result = new ObjectReference[2]
    If player == None || target == None
        Return result
    EndIf
    If QDJTargetResolver.ComparableDistance(player, target) >= 0.0
        result[0] = player
        result[1] = target
        Return result
    EndIf
    ObjectReference[] origins = Anchors(player)
    ObjectReference[] targets = Anchors(target)
    Int bestPriority = 100
    Float bestDistance = -1.0
    Int i = 0
    While i < origins.Length && origins[i] != None
        Int j = 0
        While j < targets.Length && targets[j] != None
            Float distance = QDJTargetResolver.ComparableDistance(origins[i], targets[j])
            Int priority = 0
            If origins[i] != player
                priority += 2
            EndIf
            If targets[j] != target
                priority += 1
            EndIf
            If distance >= 0.0 && (priority < bestPriority || (priority == bestPriority && (bestDistance < 0.0 || distance < bestDistance)))
                result[0] = origins[i]
                result[1] = targets[j]
                bestPriority = priority
                bestDistance = distance
            EndIf
            j += 1
        EndWhile
        i += 1
    EndWhile
    Return result
EndFunction

ObjectReference[] Function Anchors(ObjectReference reference) Global
    ObjectReference[] result = new ObjectReference[128]
    result[0] = reference
    Cell parentCell = reference.GetParentCell()
    If parentCell == None
        Return result
    EndIf
    Form area = parentCell
    If !parentCell.IsInterior()
        area = reference.GetWorldSpace()
    EndIf
    String encoded = QDJEntranceIndex.Lookup(QDJFormKey.FromForm(area))
    If encoded == ""
        Return result
    EndIf
    String[] keys = StringUtil.Split(encoded, ";")
    Int cursor = 1
    Int i = 0
    While i < keys.Length && cursor < 128
        ObjectReference door = QDJFormKey.ToForm(keys[i]) as ObjectReference
        If door != None
            result[cursor] = door
            cursor += 1
        EndIf
        i += 1
    EndWhile
    Return result
EndFunction

String Function DistanceLabel(Float meters, Int kind) Global
    If meters < 0.0
        Return "Odległość niedostępna"
    EndIf
    String result = ((meters + 0.5) as Int) + " m"
    If kind == 1
        Return result + " do wejścia"
    ElseIf kind == 2
        Return result + " od wyjścia"
    ElseIf kind == 3
        Return result + " między wejściami"
    EndIf
    Return result + " w linii prostej"
EndFunction
