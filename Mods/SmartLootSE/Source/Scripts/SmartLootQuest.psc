Scriptname SmartLootQuest extends Quest

Bool Property Enabled = True Auto
Bool Property CollectGold = True Auto
Bool Property CollectGems = True Auto
Bool Property CollectPotions = True Auto
Bool Property CollectIngredients = True Auto
Bool Property CollectArrows = True Auto
Float Property ScanInterval = 0.5 Auto
Float Property ScanRadius = 220.0 Auto

; Skyrim TESForm type IDs: MISC, INGR, AMMO and ALCH.
Int Property FormTypeMisc = 32 AutoReadOnly
Int Property FormTypeIngredient = 30 AutoReadOnly
Int Property FormTypeAmmo = 42 AutoReadOnly
Int Property FormTypeAlchemy = 46 AutoReadOnly

Form Property GoldForm Auto
Keyword Property GemKeyword Auto
Keyword Property PotionKeyword Auto

Event OnInit()
    LoadForms()
    RegisterForSingleUpdate(ScanInterval)
EndEvent

Function Maintenance()
    LoadForms()
    RegisterForSingleUpdate(0.1)
EndFunction

Function LoadForms()
    GoldForm = Game.GetFormFromFile(15, "Skyrim.esm")
    GemKeyword = Game.GetFormFromFile(595177, "Skyrim.esm") as Keyword
    PotionKeyword = Game.GetFormFromFile(577004, "Skyrim.esm") as Keyword
EndFunction

Event OnUpdate()
    Actor player = Game.GetPlayer()
    If Enabled && player != None && !player.IsDead() && !player.IsInCombat() && !Utility.IsInMenuMode()
        If CollectGold || CollectGems
            ScanCategory(player, FormTypeMisc)
        EndIf
        If CollectPotions
            ScanCategory(player, FormTypeAlchemy)
        EndIf
        If CollectIngredients
            ScanCategory(player, FormTypeIngredient)
        EndIf
        If CollectArrows
            ScanCategory(player, FormTypeAmmo)
        EndIf
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
        Return (CollectGold && baseForm == GoldForm) || (CollectGems && GemKeyword != None && baseForm.HasKeyword(GemKeyword))
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
