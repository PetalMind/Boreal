Scriptname CreatorEnergySoulCapture extends ActiveMagicEffect

Bool handled = False

Event OnEffectStart(Actor akTarget, Actor akCaster)
    ; Also covers a lethal hit processed before Papyrus starts this effect.
    CaptureSoul(akTarget, akCaster)
EndEvent

Event OnDeath(Actor akKiller)
    CaptureSoul(GetTargetActor(), GetCasterActor())
EndEvent

Event OnEffectFinish(Actor akTarget, Actor akCaster)
    CaptureSoul(akTarget, akCaster)
EndEvent

Function CaptureSoul(Actor target, Actor caster)
    If handled || !target || !caster
        Return
    EndIf
    handled = True
    If caster != Game.GetPlayer() || !target.IsDead() || target.GetKiller() != caster
        handled = False
        Return
    EndIf

    ; Native trapping selects a suitable empty gem, including reusable gems.
    If caster.TrapSoul(target)
        Return
    EndIf

    ; Black gems can contain both white and black souls. Do not leave a free
    ; gem behind for soulless creatures or a soul that was already captured.
    Form freeGem = Game.GetForm(0x0002E500)
    If freeGem
        caster.AddItem(freeGem, 1, True)
        If !caster.TrapSoul(target)
            caster.RemoveItem(freeGem, 1, True)
        EndIf
    EndIf
EndFunction
