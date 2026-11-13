--!nonstrict
--[[
	Gameplay.Interact : ProximityPrompt avec validation côté SERVEUR (distance, recharge par joueur, règle personnalisée).
	Le client peut déclencher Triggered à distance en falsifiant l'événement : chaque déclenchement est revérifié ici.

	Interact.Create(target, options?) -> handle
		target : BasePart | Attachment | Model (le prompt y est attaché)
		options : Text ("Interagir")   ObjectText   Key (Enum.KeyCode)   HoldTime (0)   Distance (10 : MaxActivationDistance)
		          Cooldown (0 : s par joueur)   RequiresLineOfSight (false)
		          Tolerance (4 : marge de latence ajoutée à Distance pour la validation)
		          Validate(player) -> boolean | string?     false / message => refusé
		          OnTriggered(player)    Once (désactive après la 1re activation valide)
	handle.Triggered (Signal : player)   handle.Rejected (Signal : player, reason)   handle.Prompt
	handle:SetEnabled(bool)   handle:SetText(text)   handle:Remove()

	Raisons de refus : "Disabled" | "NoCharacter" | "TooFar" | "Cooldown" | message de Validate

	Exemple
		Core.Gameplay.Interact.Create(chest, {
			Text = "Ouvrir", HoldTime = 0.5, Cooldown = 3,
			Validate = function(player) return hasKey(player) or "Il faut une clé" end,
			OnTriggered = function(player) giveLoot(player) end,
		})
]]

local Cooldown = require(script.Parent.Cooldown)
local Signal = require(script.Parent.Parent.Utilities.Signal)

local Interact = {}

local function positionOf(target: Instance): Vector3
	if target:IsA("Attachment") then
		return target.WorldPosition
	elseif target:IsA("Model") then
		return target:GetPivot().Position
	end
	return target.Position
end

function Interact.Create(target: Instance, options: any?)
	if typeof(target) ~= "Instance" or not (target:IsA("BasePart") or target:IsA("Attachment") or target:IsA("Model")) then
		error("Core.Gameplay.Interact.Create : BasePart, Attachment ou Model attendu", 2)
	end
	local opts = options or {}
	local distance = opts.Distance or 10
	local tolerance = if opts.Tolerance ~= nil then opts.Tolerance else 4

	local host = target
	if target:IsA("Model") then
		host = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
		if not host then
			error("Core.Gameplay.Interact.Create : le Model ne contient aucune BasePart", 2)
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CoreInteract"
	prompt.ActionText = opts.Text or "Interagir"
	prompt.ObjectText = opts.ObjectText or ""
	prompt.HoldDuration = opts.HoldTime or 0
	prompt.MaxActivationDistance = distance
	prompt.RequiresLineOfSight = opts.RequiresLineOfSight == true
	if opts.Key then
		prompt.KeyboardKeyCode = opts.Key
	end
	prompt.Parent = host

	local handle = { Prompt = prompt, Triggered = Signal.new(), Rejected = Signal.new(), _enabled = true, _removed = false }
	local cooldowns = if (opts.Cooldown or 0) > 0 then Cooldown.Keyed(opts.Cooldown) else nil

	local function reject(player: Player, reason: string)
		handle.Rejected:Fire(player, reason)
	end

	local connection = prompt.Triggered:Connect(function(player: Player)
		if handle._removed or not handle._enabled then
			return reject(player, "Disabled")
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return reject(player, "NoCharacter")
		end
		if (root.Position - positionOf(target)).Magnitude > distance + tolerance then
			return reject(player, "TooFar")
		end
		if opts.Validate then
			local verdict = opts.Validate(player)
			if verdict == false or type(verdict) == "string" then
				return reject(player, if type(verdict) == "string" then verdict else "Validate")
			end
		end
		if cooldowns and not cooldowns:Use(player) then
			return reject(player, "Cooldown")
		end

		if opts.Once then
			handle:SetEnabled(false)
		end
		handle.Triggered:Fire(player)
		if opts.OnTriggered then
			task.spawn(opts.OnTriggered, player)
		end
	end)

	function handle:SetEnabled(enabled: boolean)
		self._enabled = enabled
		prompt.Enabled = enabled
	end

	function handle:SetText(text: string)
		prompt.ActionText = text
	end

	function handle:Remove()
		if self._removed then
			return
		end
		self._removed = true
		connection:Disconnect()
		prompt:Destroy()
		self.Triggered:Destroy()
		self.Rejected:Destroy()
	end

	return handle
end

return Interact
