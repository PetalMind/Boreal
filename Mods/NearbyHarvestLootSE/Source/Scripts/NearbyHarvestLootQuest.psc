Scriptname NearbyHarvestLootQuest extends Quest

Int Property FloraFormType = 39 AutoReadOnly

GlobalVariable HarvestPlantsSetting
GlobalVariable LootNearbyCorpsesSetting
GlobalVariable SearchRadiusSetting
Bool isProcessing

Event OnInit()
    LoadSettings()
    RegisterForControl("Activate")
EndEvent

Event OnControlDown(String control)
    If control != "Activate" || isProcessing || Utility.IsInMenuMode()
        Return
    EndIf

    Actor player = Game.GetPlayer()
    ObjectReference target = Game.GetCurrentCrosshairRef()
    If player == None || player.IsDead() || target == None
        Return
    EndIf

    Form targetBase = target.GetBaseObject()
    If targetBase == None
        Return
    EndIf

    Float radius = GetSearchRadius()
    If IsSettingEnabled(HarvestPlantsSetting) && targetBase.GetType() == FloraFormType
        isProcessing = True
        HarvestNearbyPlants(player, target, radius)
        isProcessing = False
    ElseIf IsSettingEnabled(LootNearbyCorpsesSetting)
        Actor targetActor = target as Actor
        If targetActor != None && targetActor.IsDead()
            isProcessing = True
            LootNearbyCorpses(player, targetActor, radius)
            isProcessing = False
        EndIf
    EndIf
EndEvent

Function LoadSettings()
    HarvestPlantsSetting = Game.GetFormFromFile(0x801, "NearbyHarvestLootSE.esp") as GlobalVariable
    LootNearbyCorpsesSetting = Game.GetFormFromFile(0x802, "NearbyHarvestLootSE.esp") as GlobalVariable
    SearchRadiusSetting = Game.GetFormFromFile(0x803, "NearbyHarvestLootSE.esp") as GlobalVariable
EndFunction

Function HarvestNearbyPlants(Actor player, ObjectReference selectedPlant, Float radius)
    ObjectReference[] nearbyPlants = PO3_SKSEFunctions.FindAllReferencesOfFormType(player, FloraFormType, radius)
    If nearbyPlants == None
        Return
    EndIf

    Int index = 0
    While index < nearbyPlants.Length
        ObjectReference plant = nearbyPlants[index]
        If plant != None && plant != selectedPlant && !plant.IsDisabled() && plant.Is3DLoaded() && !plant.IsHarvested() && player.HasLOS(plant)
            plant.Activate(player)
        EndIf
        index += 1
    EndWhile
EndFunction

Function LootNearbyCorpses(Actor player, Actor selectedCorpse, Float radius)
    Actor[] nearbyActors = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    If nearbyActors == None
        Return
    EndIf

    Int index = 0
    While index < nearbyActors.Length
        Actor corpse = nearbyActors[index]
        If corpse != None && corpse != player && corpse != selectedCorpse && !corpse.IsDisabled() && corpse.IsDead() && corpse.IsHostileToActor(player) && corpse.GetDistance(player) <= radius
            corpse.RemoveAllItems(player, False, False)
        EndIf
        index += 1
    EndWhile
EndFunction

Float Function GetSearchRadius()
    If SearchRadiusSetting == None
        Return 512.0
    EndIf

    Float radius = SearchRadiusSetting.GetValue()
    If radius < 128.0
        Return 512.0
    ElseIf radius > 2048.0
        Return 2048.0
    EndIf
    Return radius
EndFunction

Bool Function IsSettingEnabled(GlobalVariable setting)
    Return setting != None && setting.GetValue() >= 0.5
EndFunction
