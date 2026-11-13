--!nonstrict
--[[
	Gameplay.StateMachine : machine à états événementielle (aucune boucle : tout passe par :Transition).

	StateMachine.new(definition) -> machine
		definition : Initial = "Idle"
		             States  = {
		                 Idle = { Enter = function(previous, ...) end, Exit = function(next, ...) end, Allow = { "Walk", "Jump" } },
		                 ...
		             }
		Allow absent => toutes les transitions sont permises depuis cet état.
	machine:Get() -> string       machine:Is(name)      machine:Can(name) -> boolean      machine:GetPrevious()
	machine:Transition(name, ...) -> boolean    false si interdit ; erreur si l'état n'existe pas. Les arguments vont à Enter / Exit.
	machine:Force(name, ...)                    transition sans contrôle d'Allow
	Signal Changed(new, old)       machine:Destroy()

	Une erreur dans Enter / Exit est signalée par warn() et n'empêche pas la transition.
	Une transition lancée depuis Enter / Exit est exécutée après la transition en cours (file d'attente).
]]

local Signal = require(script.Parent.Parent.Utilities.Signal)

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(definition: any)
	if type(definition) ~= "table" or type(definition.States) ~= "table" or definition.States[definition.Initial] == nil then
		error("Core.Gameplay.StateMachine.new : { Initial = 'Nom', States = { Nom = {...} } } requis (Initial doit exister)", 2)
	end
	for name, state in definition.States do
		if type(state) ~= "table" then
			error(("Core.Gameplay.StateMachine.new : l'état '%s' doit être une table"):format(tostring(name)), 2)
		end
		if state.Allow then
			for _, target in state.Allow do
				if definition.States[target] == nil then
					error(("Core.Gameplay.StateMachine.new : '%s' autorise l'état inconnu '%s'"):format(tostring(name), tostring(target)), 2)
				end
			end
		end
	end

	local self = setmetatable({
		Changed = Signal.new(),
		_states = definition.States,
		_current = definition.Initial,
		_previous = nil,
		_busy = false,
		_queue = {},
	}, StateMachine)

	local enter = definition.States[definition.Initial].Enter
	if enter then
		local ok, err = pcall(enter, nil)
		if not ok then
			warn(("[Core.Gameplay] StateMachine Enter('%s') : %s"):format(definition.Initial, tostring(err)))
		end
	end
	return self
end

function StateMachine:Get(): string
	return self._current
end

function StateMachine:GetPrevious(): string?
	return self._previous
end

function StateMachine:Is(name: string): boolean
	return self._current == name
end

function StateMachine:Can(name: string): boolean
	local target = self._states[name]
	if target == nil then
		return false
	end
	local allow = self._states[self._current].Allow
	return allow == nil or table.find(allow, name) ~= nil
end

function StateMachine:_Run(name: string, ...: any)
	local old = self._current
	local oldState, newState = self._states[old], self._states[name]

	self._busy = true
	if oldState.Exit then
		local ok, err = pcall(oldState.Exit, name, ...)
		if not ok then
			warn(("[Core.Gameplay] StateMachine Exit('%s') : %s"):format(old, tostring(err)))
		end
	end
	self._previous, self._current = old, name
	if newState.Enter then
		local ok, err = pcall(newState.Enter, old, ...)
		if not ok then
			warn(("[Core.Gameplay] StateMachine Enter('%s') : %s"):format(name, tostring(err)))
		end
	end
	self.Changed:Fire(name, old)
	self._busy = false

	-- transitions demandées pendant Enter / Exit
	local nextRequest = table.remove(self._queue, 1)
	if nextRequest then
		if nextRequest.force or self:Can(nextRequest.name) then
			self:_Run(nextRequest.name, table.unpack(nextRequest.args, 1, nextRequest.n))
		end
	end
end

function StateMachine:_Request(name: string, force: boolean, ...: any): boolean
	if self._states[name] == nil then
		error(("Core.Gameplay.StateMachine : état inconnu '%s'"):format(tostring(name)), 3)
	end
	if self._busy then
		table.insert(self._queue, { name = name, force = force, args = { ... }, n = select("#", ...) })
		return true
	end
	if not force and not self:Can(name) then
		return false
	end
	self:_Run(name, ...)
	return true
end

function StateMachine:Transition(name: string, ...: any): boolean
	return self:_Request(name, false, ...)
end

function StateMachine:Force(name: string, ...: any)
	self:_Request(name, true, ...)
end

function StateMachine:Destroy()
	self.Changed:Destroy()
	table.clear(self._queue)
end

return StateMachine
