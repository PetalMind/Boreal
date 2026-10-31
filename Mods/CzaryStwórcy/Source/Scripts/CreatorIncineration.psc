Scriptname CreatorIncineration extends ActiveMagicEffect

EffectShader Property CharredBody Auto
Form Property AshPile Auto
SoulGem Property EmptySoulGem Auto
Bool handled = False

Event OnEffectStart(Actor akTarget, Actor akCaster)
    ProcessDeath(akTarget, akCaster)
EndEvent

Event OnDeath(Actor akKiller)
    ProcessDeath(GetTargetActor(), GetCasterActor())
EndEvent

Event OnEffectFinish(Actor akTarget, Actor akCaster)
    ProcessDeath(akTarget, akCaster)
EndEvent

Function ProcessDeath(Actor target, Actor caster)
    If handled || !target || !caster
        Return
    EndIf
    If !target.IsDead() || target.GetKiller() != caster
        Return
    EndIf
    handled = True
    If !caster.TrapSoul(target)
        ; Native soul trapping also handles soul size and black souls.
        caster.AddItem(EmptySoulGem, 1, True)
        If !caster.TrapSoul(target)
            caster.RemoveItem(EmptySoulGem, 1, True)
        EndIf
    EndIf
    ; Capture the soul before the engine replaces the body with a lootable pile.
    target.SetCriticalStage(3)
    CharredBody.Play(target, 0.5)
    Utility.Wait(0.5)
    target.AttachAshPile(AshPile)
    target.SetAlpha(0.0)
    target.SetCriticalStage(4)
EndFunction
