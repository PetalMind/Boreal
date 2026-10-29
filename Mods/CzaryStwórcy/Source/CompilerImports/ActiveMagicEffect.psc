Scriptname ActiveMagicEffect Hidden
Actor Function GetTargetActor() Native
Actor Function GetCasterActor() Native
Function RegisterForSingleUpdate(Float afInterval) Native
Function UnregisterForUpdate() Native
Event OnEffectStart(Actor akTarget, Actor akCaster)
EndEvent
Event OnEffectFinish(Actor akTarget, Actor akCaster)
EndEvent
Event OnDeath(Actor akKiller)
EndEvent
Event OnUpdate()
EndEvent
