Scriptname CreatorInternalExplosion extends ActiveMagicEffect

VisualEffect Property BloodBurst Auto
Sound Property BurstSound Auto
EffectShader Property RedAura Auto
Actor victim
Actor caster
Bool detonated = False

Event OnEffectStart(Actor akTarget, Actor akCaster)
    victim = akTarget
    caster = akCaster
    If !victim || victim.IsDead()
        Return
    EndIf
    RedAura.Play(victim, -1.0)
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
        RedAura.Stop(victim)
    EndIf
EndEvent

Event OnEffectFinish(Actor akTarget, Actor akCaster)
    UnregisterForUpdate()
    If akTarget
        RedAura.Stop(akTarget)
    EndIf
EndEvent

Event OnDeath(Actor akKiller)
    If victim
        RedAura.Stop(victim)
    EndIf
EndEvent
