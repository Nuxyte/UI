--!nonstrict
--[[
	Core.Networking  (alias Core.Net)
	Communication client <-> serveur typée, validée et limitée. Le même code `require` fonctionne des deux côtés ;
	le comportement dépend de RunService:IsServer().

	PRINCIPE DE SÉCURITÉ : tout ce qui arrive d'un client est validé (schéma) et limité (rate limit) AVANT d'atteindre
	vos handlers. Les handlers ne reçoivent donc que des données déjà conformes. Ne faites JAMAIS confiance au client
	pour une action importante : le serveur décide (ex. le client envoie "acheter Sword", le serveur vérifie l'argent).

	EVENTS
		local Hit = Net.Event("Hit", { Schema = { "Instance" }, RateLimit = { Rate = 10, Burst = 20 } })
		-- serveur
		Hit:Connect(function(player, target) ... end)
		Hit:Fire(player, ...)   Hit:FireAll(...)   Hit:FireExcept(player, ...)   Hit:FireMany(players, ...)
		-- client
		Hit:Connect(function(...) end)      Hit:Fire(...)  -- vers le serveur (schéma vérifié localement : erreur si invalide)
		options : Schema (voir Validator), RateLimit = { Rate, Burst } | false
		Hit:Once(fn)  Hit:Wait()

	FUNCTIONS (requête/réponse avec timeout, sans risque de blocage éternel)
		local Buy = Net.Function("Buy", { Schema = { "string" } })
		Buy:SetHandler(function(player, itemName) return { Ok = true } end)     -- serveur (UNE valeur de retour)
		local ok, result = Buy:Invoke("Sword")                                  -- client (yield) -> ok, valeur | message d'erreur
		options : Schema, RateLimit, Timeout (défaut Config.Networking.InvokeTimeout)
		Les erreurs du handler ne fuitent pas vers le client (il reçoit false, "server error").
		Invoke côté serveur vers un client : Buy:Invoke(player, ...) -- la réponse du client est NON FIABLE.

	STATE (données répliquées serveur -> clients, par lots à chaque frame)
		local Stats = Net.State("GameStats", { Scope = "Global", Initial = { Round = 1 } })
		Stats:Set("Round", 2)    Stats:Get("Round")    Stats:Remove("Round")    Stats:GetAll()      -- serveur
		local Private = Net.State("Wallet", { Scope = "Player" })
		Private:Set(player, "Coins", 10)    Private:Get(player, "Coins")                           -- serveur (privé au joueur)
		-- client
		Stats:Get("Round")   Stats:GetAll()   Stats:IsReady()   Stats:WaitReady()
		Stats.Changed:Connect(function(key, new, old) end)   Stats:Observe("Round", function(value) end)
		-- serveur : Stats.Changed(key, new, old) ; Scope Player : Changed(player, key, new, old)
		Un client rejoignant tard reçoit un snapshot complet ; les mises à jour reçues pendant le chargement sont rejouées.

	SÉCURITÉ (0.2.0)
		- Les envois serveur -> client (Fire, FireAll, FireExcept, FireMany, Invoke) sont validés avec le même Schema : un bug serveur
		  qui enverrait des données hors schéma lève une erreur au lieu de partir silencieusement.
		- Déclarer deux fois un même nom avec des options différentes (Schema, RateLimit, Timeout, Scope, Initial) lève une erreur ;
		  redéclarer avec les MÊMES options, ou appeler Net.Event("Nom") sans options, retourne l'instance existante.
		  (Les fonctions du Schema sont comparées par identité : réutilisez la même table de schéma.)
		- Net.State : Initial est validé comme Set (clés = chaînes non vides, valeurs réplicables) ; Initial avec Scope Player est refusé.
		- Budget global par joueur (Config.Networking.GlobalRate / GlobalBurst) en plus des limiteurs par chaîne : répartir des
		  requêtes sur de nombreuses chaînes ne contourne plus la limite. Dépassement => violation "budget global dépassé".
		- Limites qui subsistent : un exploit peut quand même envoyer des données CONFORMES au schéma ; la validité métier
		  (argent, distance, cooldown...) reste de la responsabilité de vos handlers. Net.Function:Invoke(player, ...) : un client
		  qui ne répond jamais laisse un thread suspendu (limite de RemoteFunction:InvokeClient) ; le timeout libère l'appelant, pas ce thread.

	AUTRES
		Net.Violation:Connect(function(player, channelName, reason) end)   -- toute requête rejetée
		Net.Violations(player) -> number
		Config.Networking.MaxViolations > 0 => kick automatique
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local Signal = require(script.Parent.Utilities.Signal)
local Validator = require(script.Validator)
local RateLimiter = require(script.RateLimiter)

local IS_SERVER = RunService:IsServer()

local Net = {
	IsServer = IS_SERVER,
	Validator = Validator,
	RateLimiter = RateLimiter,
	Violation = Signal.new(),
}

local DEFAULTS = {
	RemotesFolder = "CoreRemotes",
	DefaultRate = 30,
	DefaultBurst = 60,
	MaxViolations = 0,
	InvokeTimeout = 10,
	WaitTimeout = 10,
	GlobalRate = 120, -- budget total de requêtes entrantes par joueur (toutes chaînes confondues) ; false / 0 = désactivé
	GlobalBurst = 240,
}

local function setting(name: string): any
	local section = Config.Networking
	local value = section and section[name]
	if value == nil then
		return DEFAULTS[name]
	end
	return value
end

local function serverOnly(what: string)
	if not IS_SERVER then
		error(("Core.Net : %s est réservé au serveur"):format(what), 3)
	end
end

-- Remotes ------------------------------------------------------------------

local folderCache: Instance? = nil

local function getFolder(): Instance
	if folderCache and folderCache.Parent then
		return folderCache
	end

	local name = setting("RemotesFolder")
	local folder = ReplicatedStorage:FindFirstChild(name)
	if not folder then
		if IS_SERVER then
			folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = ReplicatedStorage
		else
			folder = ReplicatedStorage:WaitForChild(name, setting("WaitTimeout"))
		end
	end
	if not folder then
		error(("Core.Net : dossier de remotes '%s' introuvable (le serveur a-t-il créé un canal ?)"):format(name), 3)
	end

	folderCache = folder
	return folder
end

local function getRemote(className: string, name: string): Instance
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if remote then
		return remote
	end

	if IS_SERVER then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	remote = folder:WaitForChild(name, setting("WaitTimeout"))
	if not remote then
		error(("Core.Net : remote '%s' introuvable côté client (créez le canal côté serveur d'abord)"):format(name), 3)
	end
	return remote
end

-- Sécurité (serveur) --------------------------------------------------------

local violations: { [Instance]: number } = {}
local limiters: { any } = {}
local states: { [string]: any } = {}

local function violate(player: Instance, channelName: string, reason: string)
	local count = (violations[player] or 0) + 1
	violations[player] = count

	if Config.Debug then
		warn(("[Core.Net] violation de %s sur '%s' : %s"):format(player.Name, channelName, tostring(reason)))
	end
	Net.Violation:Fire(player, channelName, reason)

	local max = setting("MaxViolations")
	if max > 0 and count >= max then
		pcall(function()
			player:Kick("Activité réseau suspecte.")
		end)
	end
end

local function makeLimiter(option: any): any
	if option == false then
		return nil
	end
	local rate = setting("DefaultRate")
	local burst = setting("DefaultBurst")
	if type(option) == "table" then
		rate = option.Rate or rate
		burst = option.Burst or (option.Rate and option.Rate * 2) or burst
	end
	local limiter = RateLimiter.new(rate, burst)
	table.insert(limiters, limiter)
	return limiter
end

local globalLimiter: any = nil
local globalDisabled = false

local function globalAllow(player: Instance): boolean
	if globalDisabled then
		return true
	end
	if not globalLimiter then
		local rate = setting("GlobalRate")
		if not rate or rate <= 0 then
			globalDisabled = true
			return true
		end
		globalLimiter = RateLimiter.new(rate, setting("GlobalBurst") or rate * 2)
		table.insert(limiters, globalLimiter)
	end
	return globalLimiter:Allow(player)
end

local function guard(channel: any, player: any, ...: any): boolean
	if typeof(player) ~= "Instance" then
		return false
	end
	if not globalAllow(player) then
		violate(player, channel.Name, "budget global dépassé")
		return false
	end
	if channel._limiter and not channel._limiter:Allow(player) then
		violate(player, channel.Name, "rate limit dépassé")
		return false
	end
	if channel._schema then
		local ok, err = Validator.Validate(channel._schema, table.pack(...))
		if not ok then
			violate(player, channel.Name, err)
			return false
		end
	end
	return true
end

-- Empreinte déterministe d'une valeur d'options (tables triées ; fonctions par identité).
local function fingerprint(value: any, depth: number?): string
	local level = depth or 0
	local kind = type(value)
	if kind == "table" then
		if level > 8 then
			return "{...}"
		end
		local keys = {}
		for key in value do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then
				return ta < tb
			end
			if ta == "number" or ta == "string" then
				return a < b
			end
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, key in keys do
			table.insert(parts, tostring(key) .. "=" .. fingerprint(value[key], level + 1))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif kind == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

-- Même nom redéclaré : options identiques (ou absentes) => on réutilise ; différentes => erreur explicite.
local function reuseOrConflict(kind: string, existing: any, options: any?, relevant: { string })
	if options == nil then
		return existing
	end
	local picked = {}
	for _, key in relevant do
		picked[key] = options[key]
	end
	local print_ = fingerprint(picked)
	if print_ ~= existing._signature then
		error(
			("Core.Net.%s '%s' : déjà déclaré avec des options différentes (déclaration d'origine : %s). "):format(kind, existing.Name, existing._declaredAt or "?")
				.. "Utilisez les mêmes options, ou Net." .. kind .. "(nom) sans options pour récupérer l'instance existante.",
			3
		)
	end
	return existing
end

local function declaration(options: any?, relevant: { string }): (string, string)
	local picked = {}
	for _, key in relevant do
		picked[key] = (options or {})[key]
	end
	local ok, source, line = pcall(debug.info, 3, "sl")
	local where = if ok and source then ("%s:%s"):format(tostring(source), tostring(line)) else "?"
	return fingerprint(picked), where
end

local function validateOutgoing(channel: any, ...: any)
	if channel._schema then
		local ok, err = Validator.Validate(channel._schema, table.pack(...))
		if not ok then
			error(("Core.Net '%s' : %s"):format(channel.Name, err), 3)
		end
	end
end

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(player)
		violations[player] = nil
		for _, limiter in limiters do
			limiter:Remove(player)
		end
		for _, state in states do
			state:_RemovePlayer(player)
		end
	end)
end

function Net.Violations(player: Instance): number
	return violations[player] or 0
end

-- Invoke avec timeout -----------------------------------------------------

local function withTimeout(timeout: number, fn: () -> any): (boolean, any)
	local thread = coroutine.running()
	local finished, resumed, waiting = false, false, false
	local result = nil

	task.spawn(function()
		local packed = table.pack(pcall(fn))
		if resumed then
			return
		end
		finished = true
		result = packed
		if waiting then
			resumed = true
			task.spawn(thread)
		end
	end)

	if not finished then
		waiting = true
		local timer = task.delay(timeout, function()
			if not resumed then
				resumed = true
				task.spawn(thread)
			end
		end)
		coroutine.yield()
		pcall(task.cancel, timer)
	end

	if result == nil then
		return false, "timeout"
	end
	if not result[1] then
		return false, tostring(result[2])
	end
	return true, result[2]
end

-- Event ---------------------------------------------------------------------

local Event = {}
Event.__index = Event
local events: { [string]: any } = {}

function Net.Event(name: string, options: any?)
	if type(name) ~= "string" or name == "" then
		error("Core.Net.Event : nom (string) requis", 2)
	end
	if events[name] then
		return reuseOrConflict("Event", events[name], options, { "Schema", "RateLimit" })
	end

	local opts = options or {}
	local signature, declaredAt = declaration(options, { "Schema", "RateLimit" })
	local self = setmetatable({
		Name = name,
		_signature = signature,
		_declaredAt = declaredAt,
		_schema = opts.Schema,
		_signal = Signal.new(),
		_limiter = IS_SERVER and makeLimiter(opts.RateLimit) or nil,
		_remote = getRemote("RemoteEvent", "E_" .. name),
	}, Event)

	if IS_SERVER then
		self._remote.OnServerEvent:Connect(function(player, ...)
			if guard(self, player, ...) then
				self._signal:Fire(player, ...)
			end
		end)
	else
		self._remote.OnClientEvent:Connect(function(...)
			self._signal:Fire(...)
		end)
	end

	events[name] = self
	return self
end

function Event:Connect(fn: (...any) -> ())
	return self._signal:Connect(fn)
end

function Event:Once(fn: (...any) -> ())
	return self._signal:Once(fn)
end

function Event:Wait(): ...any
	return self._signal:Wait()
end

--- Serveur : Fire(player, ...)  —  Client : Fire(...) vers le serveur.
function Event:Fire(...: any)
	if IS_SERVER then
		local player = ...
		if typeof(player) ~= "Instance" then
			error("Core.Net.Event:Fire côté serveur : Fire(player, ...) — ou FireAll(...)", 2)
		end
		validateOutgoing(self, select(2, ...))
		self._remote:FireClient(...)
	else
		validateOutgoing(self, ...)
		self._remote:FireServer(...)
	end
end

function Event:FireAll(...: any)
	serverOnly("Event:FireAll")
	validateOutgoing(self, ...)
	self._remote:FireAllClients(...)
end

function Event:FireExcept(except: Instance, ...: any)
	serverOnly("Event:FireExcept")
	validateOutgoing(self, ...)
	for _, player in Players:GetPlayers() do
		if player ~= except then
			self._remote:FireClient(player, ...)
		end
	end
end

function Event:FireMany(playerList: { Instance }, ...: any)
	serverOnly("Event:FireMany")
	if type(playerList) ~= "table" then
		error("Core.Net.Event:FireMany : liste de joueurs requise", 2)
	end
	validateOutgoing(self, ...)
	for _, player in playerList do
		self._remote:FireClient(player, ...)
	end
end

-- Function ------------------------------------------------------------------

local Func = {}
Func.__index = Func
local functions: { [string]: any } = {}

function Net.Function(name: string, options: any?)
	if type(name) ~= "string" or name == "" then
		error("Core.Net.Function : nom (string) requis", 2)
	end
	if functions[name] then
		return reuseOrConflict("Function", functions[name], options, { "Schema", "RateLimit", "Timeout" })
	end

	local opts = options or {}
	local signature, declaredAt = declaration(options, { "Schema", "RateLimit", "Timeout" })
	local self = setmetatable({
		Name = name,
		_signature = signature,
		_declaredAt = declaredAt,
		_schema = opts.Schema,
		_timeout = opts.Timeout,
		_handler = nil,
		_limiter = IS_SERVER and makeLimiter(opts.RateLimit) or nil,
		_remote = getRemote("RemoteFunction", "F_" .. name),
	}, Func)

	local function run(...)
		local handler = self._handler
		if not handler then
			return { Ok = false, Error = "no handler" }
		end
		local ok, result = pcall(handler, ...)
		if not ok then
			warn(("[Core.Net] erreur dans le handler de '%s' : %s"):format(name, tostring(result)))
			return { Ok = false, Error = "server error" }
		end
		return { Ok = true, Value = result }
	end

	if IS_SERVER then
		self._remote.OnServerInvoke = function(player, ...)
			if not guard(self, player, ...) then
				return { Ok = false, Error = "rejected" }
			end
			return run(player, ...)
		end
	else
		self._remote.OnClientInvoke = function(...)
			return run(...)
		end
	end

	functions[name] = self
	return self
end

function Func:SetHandler(fn: (...any) -> any)
	assert(type(fn) == "function", "Core.Net.Function:SetHandler : fonction requise")
	self._handler = fn
end

--- Client : Invoke(...)  —  Serveur : Invoke(player, ...)  ->  (ok, valeur | erreur)
function Func:Invoke(...: any): (boolean, any)
	local args = table.pack(...)
	local timeout = self._timeout or setting("InvokeTimeout")
	local ok, reply

	if IS_SERVER then
		if typeof(args[1]) ~= "Instance" then
			error("Core.Net.Function:Invoke côté serveur : Invoke(player, ...)", 2)
		end
		validateOutgoing(self, select(2, ...))
		ok, reply = withTimeout(timeout, function()
			return self._remote:InvokeClient(table.unpack(args, 1, args.n))
		end)
	else
		validateOutgoing(self, ...)
		ok, reply = withTimeout(timeout, function()
			return self._remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
	end

	if not ok then
		return false, reply
	end
	if type(reply) ~= "table" then
		return false, "invalid reply"
	end
	if reply.Ok then
		return true, reply.Value
	end
	return false, tostring(reply.Error)
end

-- State ---------------------------------------------------------------------

local State = {}
State.__index = State

local GLOBAL = {}

local function replicable(value: any, depth: number): boolean
	local kind = typeof(value)
	if kind == "function" or kind == "thread" then
		return false
	end
	if kind == "table" then
		if depth > 6 or getmetatable(value) ~= nil then
			return false
		end
		for k, v in value do
			if type(k) ~= "string" and type(k) ~= "number" then
				return false
			end
			if not replicable(v, depth + 1) then
				return false
			end
		end
	end
	return true
end

function Net.State(name: string, options: any?)
	if type(name) ~= "string" or name == "" then
		error("Core.Net.State : nom (string) requis", 2)
	end
	if states[name] then
		return reuseOrConflict("State", states[name], options, { "Scope", "Initial" })
	end

	local opts = options or {}
	local scope = opts.Scope or "Global"
	if scope ~= "Global" and scope ~= "Player" then
		error("Core.Net.State : Scope doit valoir 'Global' ou 'Player'", 2)
	end
	if opts.Initial ~= nil then
		if type(opts.Initial) ~= "table" then
			error(("Core.Net.State '%s' : Initial doit être une table { clé = valeur }"):format(name), 2)
		end
		if scope == "Player" then
			error(("Core.Net.State '%s' : Initial n'est pas supporté avec Scope 'Player' (utilisez Set(player, clé, valeur))"):format(name), 2)
		end
		for key, value in opts.Initial do
			if type(key) ~= "string" or key == "" then
				error(("Core.Net.State '%s' : Initial : les clés doivent être des chaînes non vides (reçu %s)"):format(name, tostring(key)), 2)
			end
			if value == nil or not replicable(value, 1) then
				error(("Core.Net.State '%s' : Initial['%s'] n'est pas réplicable (fonction, thread, clé invalide ou metatable)"):format(name, key), 2)
			end
		end
	end
	local signature, declaredAt = declaration(options, { "Scope", "Initial" })

	local self = setmetatable({
		Name = name,
		_signature = signature,
		_declaredAt = declaredAt,
		Scope = scope,
		Changed = Signal.new(),
		Ready = Signal.new(),
		_channel = Net.Event("_S_" .. name, { RateLimit = false }),
		_snapshot = Net.Function("_Snap_" .. name),
		_data = {},
		_dirty = {},
		_flushScheduled = false,
		_ready = false,
		_buffer = {},
	}, State)

	states[name] = self

	if IS_SERVER then
		if scope == "Global" then
			for key, value in opts.Initial or {} do
				self._data[GLOBAL] = self._data[GLOBAL] or {}
				self._data[GLOBAL][key] = value
			end
		end
		self._snapshot:SetHandler(function(player)
			local owner = if scope == "Global" then GLOBAL else player
			return table.clone(self._data[owner] or {})
		end)
	else
		self._channel:Connect(function(set, removed)
			if type(set) ~= "table" or type(removed) ~= "table" then
				return
			end
			if self._ready then
				self:_Apply(set, removed)
			else
				table.insert(self._buffer, { set, removed })
			end
		end)
		task.spawn(function()
			self:_Request()
		end)
	end

	return self
end

-- client ---

function State:_Apply(set, removed)
	local data = self._data
	for key, value in set do
		local old = data[key]
		data[key] = value
		if old ~= value or type(value) == "table" then
			self.Changed:Fire(key, value, old)
		end
	end
	for _, key in removed do
		local old = data[key]
		if old ~= nil then
			data[key] = nil
			self.Changed:Fire(key, nil, old)
		end
	end
end

function State:_Request()
	for attempt = 1, 4 do
		local ok, snapshot = self._snapshot:Invoke()
		if ok and type(snapshot) == "table" then
			self._ready = true
			self:_Apply(snapshot, {})
			for _, entry in self._buffer do
				self:_Apply(entry[1], entry[2])
			end
			table.clear(self._buffer)
			self.Ready:Fire()
			return
		end
		task.wait(attempt)
	end
	warn(("[Core.Net] State '%s' : snapshot impossible à obtenir"):format(self.Name))
end

function State:IsReady(): boolean
	return self._ready
end

function State:WaitReady()
	if not self._ready then
		self.Ready:Wait()
	end
end

function State:Observe(key: string, callback: (any) -> ())
	local connection = self.Changed:Connect(function(changedKey, value)
		if changedKey == key then
			callback(value)
		end
	end)
	local current = self._data[key]
	if current ~= nil then
		task.spawn(callback, current)
	end
	return connection
end

-- serveur ---

local function resolveOwner(self, ...): (any, string?, any)
	if self.Scope == "Player" then
		local player, key, value = ...
		if typeof(player) ~= "Instance" then
			error(("Core.Net.State '%s' (Scope Player) : le premier argument doit être le joueur"):format(self.Name), 4)
		end
		return player, key, value
	end
	local key, value = ...
	return GLOBAL, key, value
end

function State:_Flush()
	self._flushScheduled = false
	local dirty = self._dirty
	self._dirty = {}

	for owner, entry in dirty do
		if next(entry.set) ~= nil or #entry.removed > 0 then
			if owner == GLOBAL then
				self._channel:FireAll(entry.set, entry.removed)
			elseif owner.Parent ~= nil then
				self._channel:Fire(owner, entry.set, entry.removed)
			end
		end
	end
end

function State:_Mark(owner, key, value)
	local entry = self._dirty[owner]
	if not entry then
		entry = { set = {}, removed = {} }
		self._dirty[owner] = entry
	end

	if value == nil then
		entry.set[key] = nil
		table.insert(entry.removed, key)
	else
		entry.set[key] = value
		local index = table.find(entry.removed, key)
		if index then
			table.remove(entry.removed, index)
		end
	end

	if not self._flushScheduled then
		self._flushScheduled = true
		task.defer(function()
			self:_Flush()
		end)
	end
end

function State:Set(...: any)
	serverOnly("State:Set")
	local owner, key, value = resolveOwner(self, ...)
	if type(key) ~= "string" or key == "" then
		error(("Core.Net.State '%s' : la clé doit être une chaîne non vide"):format(self.Name), 2)
	end
	if value ~= nil and not replicable(value, 1) then
		error(("Core.Net.State '%s' : la valeur de '%s' n'est pas réplicable (fonction/thread)"):format(self.Name, key), 2)
	end

	local data = self._data[owner]
	if not data then
		data = {}
		self._data[owner] = data
	end

	local old = data[key]
	if value == nil and old == nil then
		return
	end
	if value ~= nil and old == value and type(value) ~= "table" then
		return
	end

	data[key] = value
	if self.Scope == "Player" then
		self.Changed:Fire(owner, key, value, old)
	else
		self.Changed:Fire(key, value, old)
	end
	self:_Mark(owner, key, value)
end

function State:Remove(...: any)
	local owner, key = resolveOwner(self, ...)
	if owner == GLOBAL then
		self:Set(key, nil)
	else
		self:Set(owner, key, nil)
	end
end

function State:Get(...: any): any
	if IS_SERVER then
		local owner, key = resolveOwner(self, ...)
		local data = self._data[owner]
		return data and data[key]
	end
	return self._data[(...)]
end

function State:GetAll(player: Instance?): { [string]: any }
	if IS_SERVER then
		local owner = if self.Scope == "Player" then player else GLOBAL
		if owner == nil then
			error(("Core.Net.State '%s' : GetAll(player) requis pour Scope Player"):format(self.Name), 2)
		end
		return table.clone(self._data[owner] or {})
	end
	return table.clone(self._data)
end

function State:_RemovePlayer(player: Instance)
	self._data[player] = nil
	self._dirty[player] = nil
end

return Net
