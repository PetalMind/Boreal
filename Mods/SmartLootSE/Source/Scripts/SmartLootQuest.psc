Scriptname SmartLootQuest extends Quest

Float Property ScanInterval = 0.5 AutoReadOnly
Float Property ScanRadius = 220.0 AutoReadOnly

; Skyrim TESForm type IDs: MISC, INGR, AMMO and ALCH.
Int Property FormTypeMisc = 32 AutoReadOnly
Int Property FormTypeIngredient = 30 AutoReadOnly
Int Property FormTypeAmmo = 42 AutoReadOnly
Int Property FormTypeAlchemy = 46 AutoReadOnly

Form Property GoldForm Auto
Keyword Property GemKeyword Auto
Keyword Property PotionKeyword Auto

Event OnInit()
    GoldForm = Game.GetFormFromFile(15, "Skyrim.esm")
    GemKeyword = Game.GetFormFromFile(595177, "Skyrim.esm") as Keyword
    PotionKeyword = Game.GetFormFromFile(577004, "Skyrim.esm") as Keyword
    RegisterForSingleUpdate(ScanInterval)
EndEvent

Event OnUpdate()
    Actor player = Game.GetPlayer()
    If player != None && !player.IsDead() && !player.IsInCombat() && !Utility.IsInMenuMode()
        ScanCategory(player, FormTypeMisc)
        ScanCategory(player, FormTypeAlchemy)
        ScanCategory(player, FormTypeIngredient)
        ScanCategory(player, FormTypeAmmo)
    EndIf
    RegisterForSingleUpdate(ScanInterval)
EndEvent

Function ScanCategory(Actor player, Int formType)
    ObjectReference[] nearby = PO3_SKSEFunctions.FindAllReferencesOfFormType(player, formType, ScanRadius)
    If nearby == None
        Return
    EndIf

    Int index = nearby.Length
    While index > 0
        index -= 1
        ObjectReference item = nearby[index]
        If item != None && !item.IsDisabled() && player.HasLOS(item) && IsEligible(item, formType)
            If !PO3_SKSEFunctions.IsQuestItem(item)
                item.Activate(player)
            EndIf
        EndIf
    EndWhile
EndFunction

Bool Function IsEligible(ObjectReference item, Int formType)
    Form baseForm = item.GetBaseObject()
    If baseForm == None
        Return False
    EndIf

    If formType == FormTypeMisc
        Return baseForm == GoldForm || (GemKeyword != None && baseForm.HasKeyword(GemKeyword))
    ElseIf formType == FormTypeAlchemy
        Return PotionKeyword != None && baseForm.HasKeyword(PotionKeyword)
    ElseIf formType == FormTypeIngredient
        Return True
    ElseIf formType == FormTypeAmmo
        Ammo arrow = baseForm as Ammo
        Return arrow != None && !arrow.IsBolt()
    EndIf

    Return False
EndFunction
