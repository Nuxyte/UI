--!nonstrict
--[[
	Core.Tween
	Tweening unifié, deux moteurs choisis automatiquement :
	  - NATIF  (TweenService) pour les Instances avec un easing Roblox : le plus performant.
	  - LOGICIEL (une seule connexion Heartbeat, active uniquement tant qu'un tween tourne) pour :
	    Models, tables Lua, valeurs personnalisées, easing en fonction, OnUpdate.

	Appel simple
		Core.Tween(target, props, options?) -> TweenHandle     (démarre immédiatement)
		options : nombre (durée) ou table :
			Duration (0.5)   Easing ("QuadOut" | Enum.EasingStyle | function)   Direction (si Enum)
			Delay (0)        Repeat (0 = une fois, -1 = infini)   Yoyo (aller-retour par cycle)
			Reverse (joue de la valeur cible vers la valeur actuelle)
			OnStart()   OnUpdate(alpha)   OnComplete()   Native (false = force le moteur logiciel)

	Créer sans démarrer
		Core.Tween.Create(target, props, options?) -> TweenHandle    puis handle:Play()

	TweenHandle
		:Play()  :Pause()  :Resume()  :Cancel()  :Wait()  :Destroy()
		.Completed (Signal -> "Completed" | "Cancelled")   .State   .Target
		Le nettoyage est automatique : fin du tween, Cancel, ou destruction de la cible.

	Valeurs personnalisées
		Core.Tween.Value(from, to, options, onUpdate(value, alpha)) -> TweenHandle
			from/to : number, Vector2, Vector3, Color3, CFrame, UDim, UDim2, NumberRange, Rect

	Tables Lua
		Core.Tween(stats, { Health = 0 }, 2)          -- tween d'une table (moteur logiciel)

	Models (moteur logiciel)
		props supportées : CFrame (ou Pivot), Position, Scale

	Séquences / parallèle
		Core.Tween.Sequence():Append(...):Join(...):Delay(1):Call(fn):Play()   (voir Sequence.lua)
		Core.Tween.Parallel({ {part, {...}, 1}, {frame, {...}, 0.5} })  -> Sequence jouée en parallèle
		Core.Tween.Chain({ {...}, {...} })                              -> Sequence jouée l'une après l'autre
		(chaque spec : { Target=, Props=, Options= } ou { target, props, options })

	Divers
		Core.Tween.Cancel(target)       annule tous les tweens en cours sur la cible
		Core.Tween.Easing               module d'easing (fonctions pures)

	Notes
		- Rotation sur un BasePart avec un Vector3 est converti en Orientation.
		- Alias : Core.Tween.To = Core.Tween(...)
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local Signal = require(script.Parent.Utilities.Signal)
local Easing = require(script.Easing)
local Sequence = require(script.Sequence)

local Tween = {}
Tween.Easing = Easing

-- Interpolation générique ------------------------------------------------

local LERP_METHOD = { Vector2 = true, Vector3 = true, Color3 = true, CFrame = true, UDim2 = true }

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function lerpValue(a: any, b: any, t: number): any
	local kind = typeof(a)
	if kind == "number" then
		return lerpNumber(a, b, t)
	elseif LERP_METHOD[kind] then
		return a:Lerp(b, t)
	elseif kind == "UDim" then
		return UDim.new(lerpNumber(a.Scale, b.Scale, t), lerpNumber(a.Offset, b.Offset, t))
	elseif kind == "NumberRange" then
		return NumberRange.new(lerpNumber(a.Min, b.Min, t), lerpNumber(a.Max, b.Max, t))
	elseif kind == "Rect" then
		return Rect.new(a.Min:Lerp(b.Min, t), a.Max:Lerp(b.Max, t))
	end
	-- Types non interpolables (bool, string, Enum...) : bascule à la fin.
	return if t >= 1 then b else a
end

-- Accès aux propriétés ---------------------------------------------------

local function isModel(target: any): boolean
	return typeof(target) == "Instance" and target:IsA("Model")
end

local MODEL_PROPS = { CFrame = true, Pivot = true, Position = true, Scale = true }

local function getProp(target: any, name: string): any
	if isModel(target) then
		if name == "CFrame" or name == "Pivot" then
			return target:GetPivot()
		elseif name == "Position" then
			return target:GetPivot().Position
		elseif name == "Scale" then
			return target:GetScale()
		end
		error(("Core.Tween : propriété '%s' non supportée sur un Model (CFrame, Position, Scale)"):format(name), 0)
	end
	return target[name]
end

local function setProp(target: any, name: string, value: any)
	if isModel(target) then
		if name == "CFrame" or name == "Pivot" then
			target:PivotTo(value)
		elseif name == "Position" then
			target:PivotTo(CFrame.new(value) * target:GetPivot().Rotation)
		elseif name == "Scale" then
			target:ScaleTo(value)
		end
		return
	end
	target[name] = value
end

-- Validation -------------------------------------------------------------

local function normalizeProps(target: any, props: any): { [string]: any }
	if type(props) ~= "table" then
		error("Core.Tween : `props` doit être une table { Propriété = valeurCible }", 4)
	end
	if next(props) == nil then
		error("Core.Tween : `props` est vide, rien à animer", 4)
	end

	local targetType = typeof(target)
	if targetType ~= "Instance" and targetType ~= "table" then
		error(("Core.Tween : cible invalide (%s) — attendu Instance ou table"):format(targetType), 4)
	end
	local result = {}
	for name, value in props do
		if type(name) ~= "string" then
			error("Core.Tween : les noms de propriétés doivent être des chaînes", 4)
		end

		local key = name
		if targetType == "Instance" and name == "Rotation" and typeof(value) == "Vector3" and target:IsA("BasePart") then
			key = "Orientation"
		end
		if isModel(target) and not MODEL_PROPS[key] then
			error(("Core.Tween : propriété '%s' non supportée sur un Model (CFrame, Position, Scale)"):format(key), 4)
		end

		local ok, current = pcall(getProp, target, key)
		if not ok then
			local className = if targetType == "Instance" then target.ClassName else "table"
			error(("Core.Tween : '%s' n'est pas une propriété valide de %s"):format(key, className), 4)
		end
		if current == nil then
			error(("Core.Tween : la propriété '%s' vaut nil, impossible de l'animer"):format(key), 4)
		end
		if typeof(current) ~= typeof(value) then
			error(
				("Core.Tween : '%s' attend un %s, reçu un %s"):format(key, typeof(current), typeof(value)),
				4
			)
		end

		result[key] = value
	end
	return result
end

local function normalizeOptions(options: any): any
	local source
	if options == nil then
		source = {}
	elseif type(options) == "number" then
		source = { Duration = options }
	elseif type(options) == "table" then
		source = options
	else
		error("Core.Tween : `options` doit être un nombre (durée) ou une table", 4)
	end

	local defaults = Config.Tween

	local duration = source.Duration
	if duration == nil then
		duration = defaults.DefaultDuration
	end
	local delay = source.Delay or 0
	local repeatCount = source.Repeat or 0

	if type(duration) ~= "number" or duration < 0 then
		error("Core.Tween : Duration doit être un nombre >= 0", 4)
	end
	if type(delay) ~= "number" or delay < 0 then
		error("Core.Tween : Delay doit être un nombre >= 0", 4)
	end
	if type(repeatCount) ~= "number" then
		error("Core.Tween : Repeat doit être un nombre (-1 = infini)", 4)
	end
	for _, callbackName in { "OnStart", "OnUpdate", "OnComplete" } do
		local callback = source[callbackName]
		if callback ~= nil and type(callback) ~= "function" then
			error(("Core.Tween : %s doit être une fonction"):format(callbackName), 4)
		end
	end

	local easing = Easing.Parse(source.Easing or defaults.DefaultEasing, source.Direction)

	return {
		Duration = duration,
		Delay = delay,
		Repeat = if repeatCount < 0 then -1 else math.floor(repeatCount),
		Yoyo = (source.Yoyo or source.Reverses) == true,
		Reverse = source.Reverse == true,
		Easing = easing,
		OnStart = source.OnStart,
		OnUpdate = source.OnUpdate,
		OnComplete = source.OnComplete,
		Native = source.Native,
	}
end

-- Moteur logiciel : une seule connexion Heartbeat, active à la demande ----

local active = {} -- set de handles logiciels en lecture
local snapshot = {}
local heartbeat: RBXScriptConnection? = nil

local function stepAll(dt: number)
	local n = 0
	for handle in active do
		n += 1
		snapshot[n] = handle
	end
	for i = 1, n do
		local handle = snapshot[i]
		snapshot[i] = nil
		if active[handle] then
			handle:_step(dt)
		end
	end
	if next(active) == nil and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

local function deactivate(handle: any)
	active[handle] = nil
	if heartbeat and next(active) == nil then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

local function activate(handle: any)
	active[handle] = true
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(stepAll)
	end
end

-- Registre par cible (clés faibles) pour Tween.Cancel(target) ------------

local running = setmetatable({}, { __mode = "k" })

local function register(target: any, handle: any)
	local set = running[target]
	if not set then
		set = {}
		running[target] = set
	end
	set[handle] = true
end

local function unregister(target: any, handle: any)
	local set = running[target]
	if set then
		set[handle] = nil
		if next(set) == nil then
			running[target] = nil
		end
	end
end

-- TweenHandle ------------------------------------------------------------

local Handle = {}
Handle.__index = Handle

local function newHandle(target: any, props: { [string]: any }, opts: any)
	local useNative = typeof(target) == "Instance"
		and not isModel(target)
		and opts.Native ~= false
		and opts.Easing.Style ~= nil
		and opts.OnUpdate == nil

	if opts.Native == true and not useNative then
		error("Core.Tween : Native = true impossible pour cette cible / cet easing / OnUpdate", 4)
	end

	return setmetatable({
		Target = target,
		State = "Idle",
		Completed = Signal.new(),
		_props = props,
		_opts = opts,
		_native = useNative,
		_tween = nil,
		_tweenConnection = nil,
		_destroyConnection = nil,
	}, Handle)
end

function Handle:_release()
	if self._tweenConnection then
		self._tweenConnection:Disconnect()
		self._tweenConnection = nil
	end
	if self._tween then
		self._tween:Cancel()
		self._tween:Destroy()
		self._tween = nil
	end
	if self._destroyConnection then
		self._destroyConnection:Disconnect()
		self._destroyConnection = nil
	end
	deactivate(self)
	unregister(self.Target, self)
end

function Handle:_finish(status: string)
	if self.State ~= "Playing" and self.State ~= "Paused" then
		return
	end
	self.State = status
	self:_release()

	self.Completed:Fire(status)
	self.Completed:DisconnectAll()

	if status == "Completed" and self._opts.OnComplete then
		task.spawn(self._opts.OnComplete)
	end
end

function Handle:_start()
	local target, props, opts = self.Target, self._props, self._opts

	if typeof(target) == "Instance" then
		self._destroyConnection = target.Destroying:Connect(function()
			self:_finish("Cancelled")
		end)
	end
	register(target, self)

	if self._native then
		local goal = props
		if opts.Reverse then
			goal = {}
			for name, value in props do
				goal[name] = target[name]
				target[name] = value
			end
		end

		local info = TweenInfo.new(
			opts.Duration,
			opts.Easing.Style,
			opts.Easing.Direction,
			opts.Repeat,
			opts.Yoyo,
			opts.Delay
		)
		local ok, tween = pcall(TweenService.Create, TweenService, target, info, goal)
		if not ok then
			self:_release()
			error(("Core.Tween : TweenService a refusé le tween : %s"):format(tostring(tween)), 0)
		end

		self._tween = tween
		self._tweenConnection = tween.Completed:Connect(function(playbackState)
			if self._tween ~= tween then
				return
			end
			self:_finish(if playbackState == Enum.PlaybackState.Completed then "Completed" else "Cancelled")
		end)

		self.State = "Playing"
		if opts.OnStart then
			task.spawn(opts.OnStart)
		end
		tween:Play()
		return
	end

	-- Moteur logiciel
	local from, to = {}, {}
	for name, goalValue in props do
		local current = getProp(target, name)
		if opts.Reverse then
			from[name], to[name] = goalValue, current
			setProp(target, name, goalValue)
		else
			from[name], to[name] = current, goalValue
		end
	end

	self._from, self._to = from, to
	self._elapsed = 0
	self._forward = true
	self._cycles = 0
	self._delayLeft = opts.Delay

	self.State = "Playing"
	if opts.OnStart then
		task.spawn(opts.OnStart)
	end
	activate(self)
end

function Handle:_apply(progress: number)
	local opts = self._opts
	local eased = opts.Easing.Fn(progress)
	local forward = self._forward

	for name, fromValue in self._from do
		local toValue = self._to[name]
		local a, b = fromValue, toValue
		if not forward then
			a, b = toValue, fromValue
		end

		local value
		if eased == 1 then
			value = b
		elseif eased == 0 then
			value = a
		else
			value = lerpValue(a, b, eased)
		end
		setProp(self.Target, name, value)
	end

	if opts.OnUpdate then
		opts.OnUpdate(eased)
	end
end

function Handle:_step(dt: number)
	if self.State ~= "Playing" then
		return
	end

	local ok, err = pcall(function()
		if self._delayLeft > 0 then
			self._delayLeft -= dt
			if self._delayLeft > 0 then
				return
			end
			dt = -self._delayLeft
			self._delayLeft = 0
		end

		local opts = self._opts
		self._elapsed += dt
		local progress = if opts.Duration <= 0 then 1 else math.min(self._elapsed / opts.Duration, 1)
		self:_apply(progress)

		if progress < 1 then
			return
		end

		-- Fin d'une demi-course / d'un cycle.
		self._elapsed = 0
		if opts.Yoyo and self._forward then
			self._forward = false
			return
		end

		self._forward = true
		if opts.Repeat == -1 or self._cycles < opts.Repeat then
			self._cycles += 1
			return
		end

		self:_finish("Completed")
	end)

	if not ok then
		warn(("[Core.Tween] tween interrompu : %s"):format(tostring(err)))
		self:_finish("Cancelled")
	end
end

--- Démarre (ou redémarre) le tween. Reprend si en pause.
function Handle:Play()
	if self.State == "Playing" then
		return self
	end
	if self.State == "Paused" then
		return self:Resume()
	end
	-- Note : les connexions à .Completed sont libérées à chaque fin ; reconnectez-les avant un rejeu.
	self:_start()
	return self
end

function Handle:Pause()
	if self.State ~= "Playing" then
		return self
	end
	self.State = "Paused"
	if self._tween then
		self._tween:Pause()
	else
		deactivate(self)
	end
	return self
end

function Handle:Resume()
	if self.State ~= "Paused" then
		return self
	end
	self.State = "Playing"
	if self._tween then
		self._tween:Play()
	else
		activate(self)
	end
	return self
end

--- Arrête le tween ; les propriétés restent à leur valeur actuelle.
function Handle:Cancel()
	self:_finish("Cancelled")
	return self
end

--- Attend la fin du tween (yield). Retourne "Completed" ou "Cancelled".
function Handle:Wait(): string
	if self.State == "Completed" or self.State == "Cancelled" then
		return self.State
	end
	if self.State == "Idle" then
		error("TweenHandle:Wait : le tween n'a pas été lancé (appelez :Play() d'abord)", 2)
	end
	return self.Completed:Wait()
end

function Handle:Destroy()
	self:Cancel()
	self.Completed:Destroy()
end

-- API publique -----------------------------------------------------------

function Tween.Create(target: any, props: { [string]: any }, options: any?)
	local opts = normalizeOptions(options)
	local checked = normalizeProps(target, props)
	return newHandle(target, checked, opts)
end

function Tween.To(target: any, props: { [string]: any }, options: any?)
	local handle = Tween.Create(target, props, options)
	handle:Play()
	return handle
end

--- Tween d'une valeur seule : onUpdate(valeurCourante, alpha) est appelé à chaque frame.
function Tween.Value(from: any, to: any, options: any?, onUpdate: ((any, number) -> ())?)
	if typeof(from) ~= typeof(to) then
		error(("Core.Tween.Value : from (%s) et to (%s) doivent avoir le même type"):format(typeof(from), typeof(to)), 2)
	end

	local proxy = { Value = from }
	local source = if type(options) == "table" then table.clone(options) elseif type(options) == "number" then { Duration = options } else {}
	local userUpdate = source.OnUpdate
	source.OnUpdate = function(alpha: number)
		if onUpdate then
			onUpdate(proxy.Value, alpha)
		end
		if userUpdate then
			userUpdate(alpha)
		end
	end
	source.Native = nil

	local handle = Tween.Create(proxy, { Value = to }, source)
	handle:Play()
	return handle
end

--- Annule tous les tweens en cours sur `target`.
function Tween.Cancel(target: any)
	local set = running[target]
	if not set then
		return
	end
	for handle in table.clone(set) do
		handle:Cancel()
	end
end

local function toSpec(spec: any): any
	if type(spec) ~= "table" then
		error("Core.Tween : une spec doit être une table", 3)
	end
	local target = spec.Target or spec[1]
	local props = spec.Props or spec[2]
	local options = spec.Options or spec[3]
	if target == nil or props == nil then
		error("Core.Tween : spec invalide, attendu { Target, Props, Options? }", 3)
	end
	return { Target = target, Props = props, Options = options }
end

local function newSequence()
	local function makeDelay(seconds: number)
		return Tween.Create({ Value = 0 }, { Value = 1 }, { Duration = seconds, Easing = "Linear", Native = false })
	end
	return Sequence.new(Tween.Create, makeDelay)
end

function Tween.Sequence()
	return newSequence()
end

--- Joue plusieurs tweens en parallèle. Retourne la séquence (déjà lancée).
function Tween.Parallel(specs: { any })
	local sequence = newSequence()
	for _, raw in specs do
		local spec = toSpec(raw)
		sequence:Join(spec.Target, spec.Props, spec.Options)
	end
	return sequence:Play()
end

--- Joue plusieurs tweens l'un après l'autre. Retourne la séquence (déjà lancée).
function Tween.Chain(specs: { any })
	local sequence = newSequence()
	for _, raw in specs do
		local spec = toSpec(raw)
		sequence:Append(spec.Target, spec.Props, spec.Options)
	end
	return sequence:Play()
end

setmetatable(Tween, {
	__call = function(_, target: any, props: { [string]: any }, options: any?)
		return Tween.To(target, props, options)
	end,
})

return Tween
