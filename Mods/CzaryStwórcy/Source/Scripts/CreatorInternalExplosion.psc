Scriptname CreatorInternalExplosion extends ActiveMagicEffect

VisualEffect Property BloodBurst Auto
Sound Property BurstSound Auto
Actor victim
Actor caster
Bool detonated = False

Event OnEffectStart(Actor akTarget, Actor akCaster)
    victim = akTarget
    caster = akCaster
    RegisterForSingleUpdate(5.0)
EndEvent

Event OnUpdate()
    If detonated || !victim || !caster || victim.IsDead()
        Return
    EndIf
    detonated = True
    ; Respect quest-essential actors without changing their base records.
    If victim.IsEssential()
        Return
    EndIf
    victim.Kill(caster)
    If victim.IsDead()
        BloodBurst.Play(victim, 3.0)
        BurstSound.Play(victim)
    EndIf
EndEvent

Event OnEffectFinish(Actor akTarget, Actor akCaster)
    UnregisterForUpdate()
EndEvent
