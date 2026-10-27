Scriptname AutoPotionQuest extends Quest

Float Property CombatCheckInterval = 0.5 AutoReadOnly
Float Property IdleCheckInterval = 1.0 AutoReadOnly
Int Property AlchemyFormType = 46 AutoReadOnly

GlobalVariable AutoHealth
GlobalVariable AutoMagicka
GlobalVariable AutoStamina
GlobalVariable HealthThreshold
GlobalVariable MagickaThreshold
GlobalVariable StaminaThreshold
GlobalVariable CooldownSeconds
GlobalVariable OnlyInCombat
GlobalVariable WeakestSufficient
MagicEffect RestoreHealth
MagicEffect RestoreMagicka
MagicEffect RestoreStamina

Event OnInit()
    Maintenance()
EndEvent

Function Maintenance()
    LoadSettings()
    RegisterForSingleUpdate(IdleCheckInterval)
EndFunction

Event OnUpdate()
    Actor player = Game.GetPlayer()
    If player == None || player.IsDead()
        RegisterForSingleUpdate(IdleCheckInterval)
        Return
    EndIf

    If IsSettingEnabled(OnlyInCombat) && !player.IsInCombat()
        RegisterForSingleUpdate(IdleCheckInterval)
        Return
    EndIf

    If Utility.IsInMenuMode()
        RegisterForSingleUpdate(CombatCheckInterval)
        Return
    EndIf

    If IsSettingEnabled(AutoHealth) && TryUsePotion(player, "Health", RestoreHealth, HealthThreshold)
        RegisterForSingleUpdate(GetCooldown())
        Return
    EndIf
    If IsSettingEnabled(AutoMagicka) && TryUsePotion(player, "Magicka", RestoreMagicka, MagickaThreshold)
        RegisterForSingleUpdate(GetCooldown())
        Return
    EndIf
    If IsSettingEnabled(AutoStamina) && TryUsePotion(player, "Stamina", RestoreStamina, StaminaThreshold)
        RegisterForSingleUpdate(GetCooldown())
        Return
    EndIf

    RegisterForSingleUpdate(CombatCheckInterval)
EndEvent

Function LoadSettings()
    AutoHealth = Game.GetFormFromFile(0x801, "AutoPotionSE.esp") as GlobalVariable
    AutoMagicka = Game.GetFormFromFile(0x802, "AutoPotionSE.esp") as GlobalVariable
    AutoStamina = Game.GetFormFromFile(0x803, "AutoPotionSE.esp") as GlobalVariable
    HealthThreshold = Game.GetFormFromFile(0x804, "AutoPotionSE.esp") as GlobalVariable
    MagickaThreshold = Game.GetFormFromFile(0x805, "AutoPotionSE.esp") as GlobalVariable
    StaminaThreshold = Game.GetFormFromFile(0x806, "AutoPotionSE.esp") as GlobalVariable
    CooldownSeconds = Game.GetFormFromFile(0x807, "AutoPotionSE.esp") as GlobalVariable
    OnlyInCombat = Game.GetFormFromFile(0x808, "AutoPotionSE.esp") as GlobalVariable
    WeakestSufficient = Game.GetFormFromFile(0x809, "AutoPotionSE.esp") as GlobalVariable
    RestoreHealth = Game.GetFormFromFile(0x3EB15, "Skyrim.esm") as MagicEffect
    RestoreMagicka = Game.GetFormFromFile(0x3EB17, "Skyrim.esm") as MagicEffect
    RestoreStamina = Game.GetFormFromFile(0x3EB16, "Skyrim.esm") as MagicEffect
EndFunction

Bool Function TryUsePotion(Actor player, String actorValueName, MagicEffect restoreEffect, GlobalVariable thresholdSetting)
    If restoreEffect == None || thresholdSetting == None
        Return False
    EndIf
    If player.GetActorValuePercentage(actorValueName) > thresholdSetting.GetValue()
        Return False
    EndIf

    Float missingAmount = player.GetActorValueMax(actorValueName) - player.GetActorValue(actorValueName)
    If missingAmount <= 0.0
        Return False
    EndIf

    Form[] inventory = PO3_SKSEFunctions.AddItemsOfTypeToArray(player, AlchemyFormType, False, False, False)
    If inventory == None
        Return False
    EndIf

    Potion bestPotion
    Float bestAmount = 0.0
    Int index = 0
    While index < inventory.Length
        Potion candidate = inventory[index] as Potion
        If candidate != None
            Float amount = GetRestorationAmount(candidate, restoreEffect)
            If amount > 0.0 && IsBetterPotion(amount, bestAmount, missingAmount)
                bestPotion = candidate
                bestAmount = amount
            EndIf
        EndIf
        index += 1
    EndWhile

    If bestPotion == None || player.GetItemCount(bestPotion) <= 0
        Return False
    EndIf
    player.EquipItem(bestPotion, False, True)
    Return True
EndFunction

Float Function GetRestorationAmount(Potion potion, MagicEffect restoreEffect)
    Float total = 0.0
    Int effectIndex = 0
    Int effectCount = potion.GetNumEffects()
    While effectIndex < effectCount
        If potion.GetNthEffectMagicEffect(effectIndex) == restoreEffect
            Float magnitude = potion.GetNthEffectMagnitude(effectIndex)
            If magnitude > 0.0
                total += magnitude
            EndIf
        EndIf
        effectIndex += 1
    EndWhile
    Return total
EndFunction

Bool Function IsBetterPotion(Float candidateAmount, Float currentAmount, Float missingAmount)
    If !IsSettingEnabled(WeakestSufficient)
        Return candidateAmount > currentAmount
    EndIf
    Bool candidateIsSufficient = candidateAmount >= missingAmount
    Bool currentIsSufficient = currentAmount >= missingAmount
    If candidateIsSufficient
        Return !currentIsSufficient || candidateAmount < currentAmount
    EndIf
    Return !currentIsSufficient && candidateAmount > currentAmount
EndFunction

Bool Function IsSettingEnabled(GlobalVariable setting)
    Return setting != None && setting.GetValue() >= 0.5
EndFunction

Float Function GetCooldown()
    If CooldownSeconds == None
        Return 5.0
    EndIf
    Float cooldown = CooldownSeconds.GetValue()
    If cooldown < 0.5
        Return 0.5
    EndIf
    Return cooldown
EndFunction
