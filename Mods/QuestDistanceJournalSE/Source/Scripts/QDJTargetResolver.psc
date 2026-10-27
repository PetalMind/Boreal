Scriptname QDJTargetResolver Hidden

ObjectReference Function FindTarget(Quest targetQuest) Global
    String encoded = QDJTargetIndex.GetTargets(targetQuest.GetID())
    If encoded == ""
        Return None
    EndIf
    String[] links = StringUtil.Split(encoded, ";")
    ObjectReference nearest
    ObjectReference firstTarget
    Float nearestDistance = -1.0
    Int i = 0
    While i < links.Length
        String[] pair = StringUtil.Split(links[i], ":")
        Int objective = pair[0] as Int
        Int aliasID = pair[1] as Int
        If aliasID >= 0 && targetQuest.IsObjectiveDisplayed(objective) && !targetQuest.IsObjectiveCompleted(objective) && !targetQuest.IsObjectiveFailed(objective)
            ReferenceAlias targetAlias = targetQuest.GetAlias(aliasID) as ReferenceAlias
            If targetAlias != None
                ObjectReference target = targetAlias.GetReference()
                If target != None
                    If firstTarget == None
                        firstTarget = target
                    EndIf
                    Float distance = ComparableDistance(Game.GetPlayer(), target)
                    If distance >= 0.0 && (nearestDistance < 0.0 || distance < nearestDistance)
                        nearest = target
                        nearestDistance = distance
                    EndIf
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
    If nearest != None
        Return nearest
    EndIf
    Return firstTarget
EndFunction

String Function Signature(Quest targetQuest) Global
    String result = targetQuest.GetCurrentStageID() + ":" + targetQuest.IsCompleted()
    String encoded = QDJTargetIndex.GetTargets(targetQuest.GetID())
    If encoded == ""
        Return result
    EndIf
    result += ":" + encoded
    String[] links = StringUtil.Split(encoded, ";")
    Int i = 0
    While i < links.Length
        String[] pair = StringUtil.Split(links[i], ":")
        Int objective = pair[0] as Int
        result += ":" + targetQuest.IsObjectiveDisplayed(objective) + targetQuest.IsObjectiveCompleted(objective) + targetQuest.IsObjectiveFailed(objective)
        Int aliasID = pair[1] as Int
        If aliasID >= 0 && targetQuest.IsObjectiveDisplayed(objective) && !targetQuest.IsObjectiveCompleted(objective) && !targetQuest.IsObjectiveFailed(objective)
            ReferenceAlias targetAlias = targetQuest.GetAlias(aliasID) as ReferenceAlias
            If targetAlias != None
                ObjectReference target = targetAlias.GetReference()
                If target != None
                    result += ":" + target.GetFormID()
                Else
                    result += ":0"
                EndIf
            EndIf
        EndIf
        i += 1
    EndWhile
    Return result
EndFunction

Float Function ComparableDistance(Actor player, ObjectReference target) Global
    If player == None || target == None
        Return -1.0
    EndIf
    Cell playerCell = player.GetParentCell()
    Cell targetCell = target.GetParentCell()
    If playerCell == None || targetCell == None
        Return -1.0
    EndIf
    If playerCell.IsInterior() || targetCell.IsInterior()
        If playerCell != targetCell
            Return -1.0
        EndIf
    ElseIf player.GetWorldSpace() == None || player.GetWorldSpace() != target.GetWorldSpace()
        Return -1.0
    EndIf
    Float units = player.GetDistance(target)
    If units < 0.0 || units > 100000000.0
        Return -1.0
    EndIf
    Return units * 0.0142875
EndFunction

String Function PlaceName(ObjectReference target) Global
    Location place = target.GetCurrentLocation()
    If place == None
        place = target.GetEditorLocation()
    EndIf
    Location current = place
    String fallback = "Nieznane miejsce"
    If place != None && place.GetName() != ""
        fallback = place.GetName()
    EndIf
    Keyword city = Keyword.GetKeyword("LocTypeCity")
    Keyword town = Keyword.GetKeyword("LocTypeTown")
    Keyword hold = Keyword.GetKeyword("LocTypeHold")
    Int depth = 0
    While current != None && depth < 16
        If (city != None && current.HasKeyword(city)) || (town != None && current.HasKeyword(town))
            If current.GetName() != ""
                Return current.GetName()
            EndIf
        EndIf
        If hold != None && current.HasKeyword(hold) && current.GetName() != ""
            Return fallback + " / " + current.GetName()
        EndIf
        current = PO3_SKSEFunctions.GetParentLocation(current)
        depth += 1
    EndWhile
    Return fallback
EndFunction

String Function FormatDistance(Float meters) Global
    If meters < 1000.0
        Return ((meters + 0.5) as Int) + " m w linii prostej"
    EndIf
    Int tenths = ((meters / 100.0) + 0.5) as Int
    Int whole = tenths / 10
    Int fraction = tenths - whole * 10
    Return whole + "," + fraction + " km w linii prostej"
EndFunction
