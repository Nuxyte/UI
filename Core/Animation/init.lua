--!nonstrict
--[[
	Core.Animation
	Util.lua        GetAnimator, NormalizeId
	Tracks.lua      Play, Stop, StopAll, GetPlaying, Preload       AnimationTracks (cache, groupes exclusifs, marqueurs)
	Controller.lua  Core.Animation.Controller.new(subject, { Animations = { ... } })     animations nommées
	Procedural.lua  Core.Animation.Procedural.Play(model, clip)    animation par clés sans asset (Motor6D.Transform)

	Dépend de Core.Engine.Scheduler et Core.Tween.Easing (Procedural uniquement).

	Exemple
		local Animation = Core.Animation
		local run = Animation.Play(character, 507767714, { Looped = true, Group = "Locomotion" })
		local anim = Animation.Controller.new(character, { Animations = { Idle = 111, Attack = { Id = 222, Group = "Action" } } })
		anim:Play("Attack")
]]

local Animation = {}

for fileName, module in { Util = require(script.Util), Tracks = require(script.Tracks) } do
	for name, value in module do
		if Animation[name] ~= nil then
			error(("Core.Animation : conflit de nom '%s' (%s)"):format(name, fileName))
		end
		Animation[name] = value
	end
end

Animation.Controller = require(script.Controller)
Animation.Procedural = require(script.Procedural)

return table.freeze(Animation)
