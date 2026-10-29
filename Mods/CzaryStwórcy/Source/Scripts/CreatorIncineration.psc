Scriptname CreatorIncineration extends ActiveMagicEffect

EffectShader Property CharredBody Auto
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
    ; Keep the body and its inventory, rather than replacing it with an ash pile.
    CharredBody.Play(target, -1.0)
    If !caster.TrapSoul(target)
        ; Native soul trapping also handles soul size and black souls.
        caster.AddItem(EmptySoulGem, 1, True)
        If !caster.TrapSoul(target)
            caster.RemoveItem(EmptySoulGem, 1, True)
        EndIf
    EndIf
EndFunction
