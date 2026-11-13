--!nonstrict
--[[
	Animation.Util
	GetAnimator(subject, create?) -> Animator?    Animator | Humanoid | AnimationController | Model les contenant
		create (false) : crée l'Animator manquant (à faire du côté qui possède le personnage : serveur pour un PNJ,
		client pour le joueur local si l'animation doit lui appartenir)
	NormalizeId(source) -> string                 123 | "123" | "rbxassetid://123" -> "rbxassetid://123"
]]

local Util = {}

function Util.NormalizeId(source: any): string
	if type(source) == "number" then
		return "rbxassetid://" .. tostring(math.floor(source))
	elseif type(source) == "string" and source ~= "" then
		if source:match("^%d+$") then
			return "rbxassetid://" .. source
		end
		return source
	end
	error("Core.Animation : id d'animation invalide (number ou string attendu)", 3)
end

local function animatorOf(host: Instance, create: boolean): Animator?
	local animator = host:FindFirstChildOfClass("Animator")
	if not animator and create then
		animator = Instance.new("Animator")
		animator.Parent = host
	end
	return animator
end

function Util.GetAnimator(subject: any, create: boolean?): Animator?
	if typeof(subject) ~= "Instance" then
		error("Core.Animation : sujet invalide (Model, Humanoid, AnimationController ou Animator attendu)", 3)
	end
	if subject:IsA("Animator") then
		return subject
	end
	local host = subject
	if subject:IsA("Model") then
		host = subject:FindFirstChildOfClass("Humanoid") or subject:FindFirstChildOfClass("AnimationController")
		if not host then
			return nil
		end
	elseif not (subject:IsA("Humanoid") or subject:IsA("AnimationController")) then
		error("Core.Animation : sujet invalide (Model, Humanoid, AnimationController ou Animator attendu)", 3)
	end
	return animatorOf(host, create == true)
end

return Util
