Scriptname PotionGlowQuest extends Quest

Bool Property Enabled = True Auto
Bool Property IncludePoisons = False Auto
Bool Property RequireLineOfSight = True Auto
Float Property ScanRadius = 1200.0 Auto
Float Property ScanInterval = 1.0 Auto

EffectShader glow
ObjectReference[] highlighted
Bool scanning
Bool refreshRequested

Event OnInit()
    Maintenance()
EndEvent

Function Maintenance()
    refreshRequested = True
    RegisterForSingleUpdate(0.1)
EndFunction

Bool Function IsAvailable()
    Return Game.GetFormFromFile(0x135C9, "UnreadBooksGlow.esp") as EffectShader != None
EndFunction

Event OnUpdate()
    ; MCM and load events only request refresh; one update owns all shader state.
    If scanning
        RegisterForSingleUpdate(ScanInterval)
        Return
    EndIf
    scanning = True
    If refreshRequested
        ClearHighlights()
        glow = Game.GetFormFromFile(0x135C9, "UnreadBooksGlow.esp") as EffectShader
        refreshRequested = False
    EndIf
    If highlighted == None
        highlighted = new ObjectReference[128]
    EndIf
    Actor player = Game.GetPlayer()
    If !Enabled || glow == None || player == None || player.IsDead()
        ClearHighlights()
    ElseIf !Utility.IsInMenuMode()
        UpdateHighlights(player)
    EndIf
    scanning = False
    RegisterForSingleUpdate(ScanInterval)
EndEvent

Function UpdateHighlights(Actor player)
    ObjectReference[] nearby = PO3_SKSEFunctions.FindAllReferencesOfFormType(player, 46, ScanRadius)
    ObjectReference[] selected = new ObjectReference[128]
    Int count = 0
    Int index = 0
    If nearby != None
        While index < nearby.Length && count < 128
            ObjectReference item = nearby[index]
            If IsEligible(item, player)
                selected[count] = item
                count += 1
            EndIf
            index += 1
        EndWhile
    EndIf
    index = 0
    While index < highlighted.Length
        ObjectReference previous = highlighted[index]
        If previous != None && selected.Find(previous) < 0
            glow.Stop(previous)
        EndIf
        index += 1
    EndWhile
    index = 0
    While index < count
        ObjectReference item = selected[index]
        If highlighted.Find(item) < 0
            glow.Play(item)
        EndIf
        index += 1
    EndWhile
    highlighted = selected
EndFunction

Bool Function IsEligible(ObjectReference item, Actor player)
    If item == None || item.IsDeleted() || item.IsDisabled() || !item.Is3DLoaded() || item.GetContainer() != None
        Return False
    EndIf
    Potion potionItem = item.GetBaseObject() as Potion
    If potionItem == None || potionItem.IsFood()
        Return False
    EndIf
    If !IncludePoisons && potionItem.IsPoison()
        Return False
    EndIf
    Return !RequireLineOfSight || player.HasLOS(item)
EndFunction

Function ClearHighlights()
    If highlighted != None && glow != None
        Int index = 0
        While index < highlighted.Length
            If highlighted[index] != None
                glow.Stop(highlighted[index])
            EndIf
            index += 1
        EndWhile
    EndIf
    highlighted = new ObjectReference[128]
EndFunction
