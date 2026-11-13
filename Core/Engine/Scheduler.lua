--!nonstrict
--[[
	Engine.Scheduler  (ex-Movement.Driver, déplacé dans le « Core Engine »)
	Moteur partagé : UNE seule connexion Heartbeat pour toutes les tâches par frame ; elle est créée à la première tâche et
	libérée dès que plus rien ne tourne (aucune boucle permanente). Utilisé par Movement, Physics, Gameplay, Animation, Debug.
	`Core.Movement.Driver` reste disponible comme alias (même table).

	Scheduler.Run(target, step, onFinish?, meta?) -> handle
		step(dt) -> boolean?        retourner true termine la tâche ("Completed")
		onFinish(status, handle)    appelé à la fin ("Completed" | "Cancelled") pour nettoyer
		meta (facultatif) : Label (nom pour les statistiques)   Channel (string)   Priority (number, défaut 0)
		                    OnConflict "Replace" (défaut) | "Reject"
		La tâche est annulée automatiquement si `target` (Instance) est détruite ou si step lève une erreur.

	ARBITRAGE — deux tâches avec le même `target` ET le même `Channel` sont en conflit :
		- "Replace" : la nouvelle remplace l'ancienne si Priority >= celle de l'ancienne ; sinon la nouvelle est REJETÉE.
		- "Reject"  : la nouvelle est toujours rejetée tant que l'ancienne tourne.
		Une tâche rejetée est retournée déjà terminée (State "Cancelled", Rejected = true, Reason = "Rejected") et son onFinish est
		appelé : les ressources qu'elle a créées sont nettoyées. Une tâche remplacée a Reason = "Preempted".
		Sans Channel : aucun arbitrage (comportement historique : plusieurs tâches peuvent coexister sur un objet).
		Une tâche en pause garde son Channel.

	handle : :Pause() :Resume() :Cancel() :Wait() :Destroy()
	         .State ("Playing" | "Paused" | "Completed" | "Cancelled")   .Completed (Signal -> statut)
	         .Target  .Label  .Channel  .Priority  .Rejected  .Reason

	Scheduler.GetStats() -> { Active, Paused, Connected, Peak, Started, Completed, Cancelled, Preempted, Rejected, Errors,
	                          Steps, LastFrameMs, MaxFrameMs, ByLabel = { [label] = nombre } }
	Scheduler.GetActive(target?) -> { handle }      (en cours ET en pause)
	Scheduler.CancelAll(target?, channel?) -> number
	Scheduler.ResetStats()
	Scheduler.MetaFrom(options, label) -> meta       lit Channel / Priority / OnConflict dans les options d'un mouvement (validé)
	Scheduler.Claim(target, meta, cancel) / Release(token) / RejectedHandle(target, meta)    pour les mouvements non basés sur Run
]]

local RunService = game:GetService("RunService")
local Signal = require(script.Parent.Parent.Utilities.Signal)

local Scheduler = {}

local active = {}
local paused = {}
local snapshot = {}
local connection: RBXScriptConnection? = nil
local claims = setmetatable({}, { __mode = "k" })

local activeCount, pausedCount = 0, 0
local stats = { Peak = 0, Started = 0, Completed = 0, Cancelled = 0, Preempted = 0, Rejected = 0, Errors = 0, Steps = 0, LastFrameMs = 0, MaxFrameMs = 0 }

local NO_CLAIM = { channel = nil }

local function stepAll(dt: number)
	local startedAt = os.clock()
	local n = 0
	for handle in active do
		n += 1
		snapshot[n] = handle
	end
	for i = 1, n do
		local handle = snapshot[i]
		snapshot[i] = nil
		if active[handle] then
			stats.Steps += 1
			local ok, result = pcall(handle._step, dt)
			if not ok then
				stats.Errors += 1
				warn(("[Core.Scheduler] tâche interrompue : %s"):format(tostring(result)))
				handle.Reason = "Error"
				handle:_finish("Cancelled")
			elseif result == true then
				handle:_finish("Completed")
			end
		end
	end
	local elapsedMs = (os.clock() - startedAt) * 1000
	stats.LastFrameMs = elapsedMs
	if elapsedMs > stats.MaxFrameMs then
		stats.MaxFrameMs = elapsedMs
	end
end

local function add(handle)
	if not active[handle] then
		active[handle] = true
		activeCount += 1
		if activeCount > stats.Peak then
			stats.Peak = activeCount
		end
	end
	if not connection then
		connection = RunService.Heartbeat:Connect(stepAll)
	end
end

local function remove(handle)
	if active[handle] then
		active[handle] = nil
		activeCount -= 1
	end
	if connection and next(active) == nil then
		connection:Disconnect()
		connection = nil
	end
end

-- Arbitrage ------------------------------------------------------------------

function Scheduler.Claim(target: any, meta: any?, cancel: (string) -> ())
	local channel = meta and meta.Channel
	if channel == nil or typeof(target) ~= "Instance" then
		return NO_CLAIM
	end

	local priority = meta.Priority or 0
	local existing = claims[target] and claims[target][channel]
	if existing then
		if meta.OnConflict == "Reject" or priority < existing.priority then
			stats.Rejected += 1
			return nil
		end
		stats.Preempted += 1
		existing.cancel("Preempted") -- libère l'ancien jeton (et peut retirer la table de la cible)
	end

	-- Relu APRÈS l'annulation : Release() a pu supprimer la table de la cible.
	local byChannel = claims[target]
	if not byChannel then
		byChannel = {}
		claims[target] = byChannel
	end

	local token = { target = target, channel = channel, priority = priority, cancel = cancel }
	byChannel[channel] = token
	return token
end

function Scheduler.Release(token: any)
	if not token or token == NO_CLAIM then
		return
	end
	local byChannel = claims[token.target]
	if byChannel and byChannel[token.channel] == token then
		byChannel[token.channel] = nil
		if next(byChannel) == nil then
			claims[token.target] = nil
		end
	end
end

function Scheduler.MetaFrom(options: any?, label: string?)
	local opts = options or {}
	if opts.Channel ~= nil and type(opts.Channel) ~= "string" then
		error("Core.Movement : Channel doit être une chaîne", 3)
	end
	if opts.Priority ~= nil and type(opts.Priority) ~= "number" then
		error("Core.Movement : Priority doit être un nombre", 3)
	end
	if opts.OnConflict ~= nil and opts.OnConflict ~= "Replace" and opts.OnConflict ~= "Reject" then
		error("Core.Movement : OnConflict doit valoir 'Replace' ou 'Reject'", 3)
	end
	return { Label = label, Channel = opts.Channel, Priority = opts.Priority, OnConflict = opts.OnConflict }
end

-- Handle ---------------------------------------------------------------------

local Handle = {}
Handle.__index = Handle

function Handle:_finish(status: string)
	if self.State ~= "Playing" and self.State ~= "Paused" then
		return
	end
	if self.State == "Paused" then
		paused[self] = nil
		pausedCount -= 1
	end
	self.State = status
	remove(self)
	if status == "Completed" then
		stats.Completed += 1
	else
		stats.Cancelled += 1
	end
	Scheduler.Release(self._token)
	self._token = nil
	if self._destroyConnection then
		self._destroyConnection:Disconnect()
		self._destroyConnection = nil
	end
	if self._onFinish then
		local ok, err = pcall(self._onFinish, status, self)
		if not ok then
			warn(("[Core.Scheduler] erreur de nettoyage : %s"):format(tostring(err)))
		end
	end
	self.Completed:Fire(status)
	self.Completed:DisconnectAll()
end

function Handle:Pause()
	if self.State == "Playing" then
		self.State = "Paused"
		remove(self)
		paused[self] = true
		pausedCount += 1
	end
	return self
end

function Handle:Resume()
	if self.State == "Paused" then
		paused[self] = nil
		pausedCount -= 1
		self.State = "Playing"
		add(self)
	end
	return self
end

function Handle:Cancel()
	self:_finish("Cancelled")
	return self
end

function Handle:Wait(): string
	if self.State == "Completed" or self.State == "Cancelled" then
		return self.State
	end
	return self.Completed:Wait()
end

function Handle:Destroy()
	self:Cancel()
	self.Completed:Destroy()
end

local function newHandle(target: any, step: any, onFinish: any, meta: any?)
	return setmetatable({
		Target = target,
		State = "Playing",
		Completed = Signal.new(),
		Label = meta and meta.Label,
		Channel = meta and meta.Channel,
		Priority = meta and meta.Priority or 0,
		Rejected = false,
		Reason = nil,
		_step = step,
		_onFinish = onFinish,
		_destroyConnection = nil,
		_token = nil,
	}, Handle)
end

--- Handle déjà terminé (State "Cancelled", Rejected = true) pour les mouvements refusés par l'arbitrage.
function Scheduler.RejectedHandle(target: any, meta: any?)
	local handle = newHandle(target, nil, nil, meta)
	handle.Rejected = true
	handle.Reason = "Rejected"
	handle:_finish("Cancelled")
	return handle
end

function Scheduler.Run(target: any, step: (number) -> boolean?, onFinish: ((string, any) -> ())?, meta: any?)
	local handle = newHandle(target, step, onFinish, meta)

	if meta and meta.Channel ~= nil then
		local token = Scheduler.Claim(target, meta, function(reason: string)
			handle.Reason = reason
			handle:Cancel()
		end)
		if not token then
			handle.Rejected = true
			handle.Reason = "Rejected"
			handle:_finish("Cancelled") -- nettoie les ressources déjà créées par l'appelant
			stats.Started += 1
			return handle
		end
		handle._token = token
	end

	stats.Started += 1
	if typeof(target) == "Instance" then
		handle._destroyConnection = target.Destroying:Connect(function()
			handle.Reason = "TargetDestroyed"
			handle:_finish("Cancelled")
		end)
	end

	add(handle)
	return handle
end

-- Statistiques / contrôle -----------------------------------------------------

function Scheduler.GetStats()
	local byLabel = {}
	for handle in active do
		local label = handle.Label or "?"
		byLabel[label] = (byLabel[label] or 0) + 1
	end
	for handle in paused do
		local label = handle.Label or "?"
		byLabel[label] = (byLabel[label] or 0) + 1
	end
	return {
		Active = activeCount,
		Paused = pausedCount,
		Connected = connection ~= nil,
		Peak = stats.Peak,
		Started = stats.Started,
		Completed = stats.Completed,
		Cancelled = stats.Cancelled,
		Preempted = stats.Preempted,
		Rejected = stats.Rejected,
		Errors = stats.Errors,
		Steps = stats.Steps,
		LastFrameMs = stats.LastFrameMs,
		MaxFrameMs = stats.MaxFrameMs,
		ByLabel = byLabel,
	}
end

function Scheduler.ResetStats()
	stats.Peak = activeCount
	stats.Started, stats.Completed, stats.Cancelled, stats.Preempted = 0, 0, 0, 0
	stats.Rejected, stats.Errors, stats.Steps, stats.LastFrameMs, stats.MaxFrameMs = 0, 0, 0, 0, 0
end

function Scheduler.GetActive(target: any?): { any }
	local list = {}
	for handle in active do
		if target == nil or handle.Target == target then
			table.insert(list, handle)
		end
	end
	for handle in paused do
		if target == nil or handle.Target == target then
			table.insert(list, handle)
		end
	end
	return list
end

function Scheduler.CancelAll(target: any?, channel: string?): number
	local cancelled = 0
	for _, handle in Scheduler.GetActive(target) do
		if channel == nil or handle.Channel == channel then
			handle.Reason = "CancelAll"
			handle:Cancel()
			cancelled += 1
		end
	end
	return cancelled
end

return Scheduler
