Scriptname NordicHorseState Hidden

Actor Function CurrentMount(Actor player) Global
    If player == None || !player.IsOnMount()
        Return None
    EndIf
    Actor mount = PO3_SKSEFunctions.GetMount(player)
    If mount == None
        Actor lastHorse = Game.GetPlayersLastRiddenHorse()
        If lastHorse != None && PO3_SKSEFunctions.GetRider(lastHorse) == player
            mount = lastHorse
        EndIf
    EndIf
    If mount == None || mount.IsDead() || mount.IsDisabled()
        Return None
    EndIf
    Return mount
EndFunction
