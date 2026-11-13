--!nonstrict
--[[
	Animation.Controller : animations nommées pour un personnage (Idle, Run, Attack...).

	Controller.new(subject, definition) -> controller
		definition.Animations = {
			Idle   = 507766388,                                                          -- id seul
			Run    = { Id = 507767714, Looped = true, Group = "Locomotion", Priority = "Movement" },
			Attack = { Id = 522635514, Group = "Action", Priority = "Action", FadeIn = 0.05 },
		}
		definition.Defaults (facultatif) : options appliquées à toutes les animations (écrasées par chaque entrée)
	controller:Play(name, options?) -> handle      options : mêmes que Animation.Play (écrasent la définition)
	controller:Stop(name, fade?)   controller:StopAll(fade?)   controller:IsPlaying(name)   controller:Get(name) -> handle?
	controller:Has(name)   controller:Preload() -> { échecs }   controller:Destroy()
	Signal Played (name, handle)

	Exemple
		local anim = Core.Animation.Controller.new(character, { Animations = { Idle = 111, Run = { Id = 222, Looped = true, Group = "Base" } } })
		anim:Play("Run")
]]

local Signal = require(script.Parent.Parent.Utilities.Signal)
local Tracks = require(script.Parent.Tracks)
local Util = require(script.Parent.Util)

local Controller = {}
Controller.__index = Controller

function Controller.new(subject: any, definition: any)
	if typeof(subject) ~= "Instance" then
		error("Core.Animation.Controller.new : sujet (Instance) requis", 2)
	end
	if type(definition) ~= "table" or type(definition.Animations) ~= "table" or next(definition.Animations) == nil then
		error("Core.Animation.Controller.new : { Animations = { Nom = id | { Id = id, ... } } } requis", 2)
	end

	local entries = {}
	for name, entry in definition.Animations do
		if type(name) ~= "string" then
			error("Core.Animation.Controller.new : les noms d'animation doivent être des chaînes", 2)
		end
		if type(entry) == "table" then
			if entry.Id == nil then
				error(("Core.Animation.Controller.new : '%s' n'a pas d'Id"):format(name), 2)
			end
			entries[name] = entry
		else
			entries[name] = { Id = entry }
		end
	end

	return setmetatable({
		Played = Signal.new(),
		_subject = subject,
		_entries = entries,
		_defaults = definition.Defaults or {},
		_destroyed = false,
	}, Controller)
end

function Controller:_Entry(name: string)
	if self._destroyed then
		error("Core.Animation.Controller : contrôleur détruit", 3)
	end
	local entry = self._entries[name]
	if not entry then
		error(("Core.Animation.Controller : animation inconnue '%s'"):format(tostring(name)), 3)
	end
	return entry
end

function Controller:Has(name: string): boolean
	return self._entries[name] ~= nil
end

function Controller:Play(name: string, options: any?)
	local entry = self:_Entry(name)
	local merged = {}
	for key, value in self._defaults do
		merged[key] = value
	end
	for key, value in entry do
		if key ~= "Id" then
			merged[key] = value
		end
	end
	if options then
		for key, value in options do
			merged[key] = value
		end
	end
	local handle = Tracks.Play(self._subject, entry.Id, merged)
	self.Played:Fire(name, handle)
	return handle
end

function Controller:Get(name: string)
	local entry = self:_Entry(name)
	local id = if typeof(entry.Id) == "Instance" then entry.Id.AnimationId else Util.NormalizeId(entry.Id)
	for _, handle in Tracks.GetPlaying(self._subject) do
		if handle.Id == id then
			return handle
		end
	end
	return nil
end

function Controller:IsPlaying(name: string): boolean
	return self:Get(name) ~= nil
end

function Controller:Stop(name: string, fade: number?)
	local handle = self:Get(name)
	if handle then
		handle:Stop(fade)
	end
end

function Controller:StopAll(fade: number?)
	if self._destroyed then
		error("Core.Animation.Controller : contrôleur détruit", 2)
	end
	for name in self._entries do
		self:Stop(name, fade)
	end
end

function Controller:Preload(): { string }
	local ids = {}
	for _, entry in self._entries do
		table.insert(ids, entry.Id)
	end
	return Tracks.Preload(ids)
end

function Controller:Destroy()
	if self._destroyed then
		return
	end
	for name in self._entries do
		self:Stop(name, 0)
	end
	self._destroyed = true
	self.Played:Destroy()
end

return Controller
