--!nonstrict
--[[
	Movement.Util
	Accès uniforme aux BaseParts et aux Models (position / CFrame) et résolution de "cibles" dynamiques.

	GetCFrame(target)  SetCFrame(target, cf)  GetPosition(target)  SetPosition(target, pos)  (conserve la rotation)
	Resolve(spec)  -> Vector3     spec = Vector3 | BasePart | Model | Attachment | function() -> Vector3
	GetRoot(subject) -> BasePart? BasePart, ou PrimaryPart / HumanoidRootPart d'un Model
	IsMovable(target) -> boolean

	Note : le module Movement positionne les objets de façon cinématique (CFrame). Pour une BasePart,
	mettez Anchored = true (ou laissez le serveur en garder la propriété réseau) sinon la physique s'y oppose.
]]

local Util = {}

function Util.IsMovable(target: any): boolean
	return typeof(target) == "Instance" and (target:IsA("BasePart") or target:IsA("Model"))
end

function Util.GetCFrame(target: Instance): CFrame
	if target:IsA("Model") then
		return target:GetPivot()
	end
	return (target :: any).CFrame
end

function Util.SetCFrame(target: Instance, cframe: CFrame)
	if target:IsA("Model") then
		target:PivotTo(cframe)
	else
		(target :: any).CFrame = cframe
	end
end

function Util.GetPosition(target: Instance): Vector3
	return Util.GetCFrame(target).Position
end

function Util.SetPosition(target: Instance, position: Vector3)
	Util.SetCFrame(target, CFrame.new(position) * Util.GetCFrame(target).Rotation)
end

function Util.Resolve(spec: any): Vector3
	local kind = typeof(spec)
	if kind == "Vector3" then
		return spec
	elseif kind == "function" then
		local value = spec()
		if typeof(value) ~= "Vector3" then
			error("Core.Movement : la fonction de cible doit retourner un Vector3", 0)
		end
		return value
	elseif kind == "Instance" then
		if spec:IsA("Attachment") then
			return spec.WorldPosition
		elseif spec:IsA("BasePart") or spec:IsA("Model") then
			return Util.GetPosition(spec)
		end
	end
	error(("Core.Movement : cible invalide (%s) — attendu Vector3, BasePart, Model, Attachment ou fonction"):format(kind), 0)
end

function Util.GetRoot(subject: Instance): BasePart?
	if typeof(subject) ~= "Instance" then
		return nil
	end
	if subject:IsA("BasePart") then
		return subject
	end
	if subject:IsA("Model") then
		return subject.PrimaryPart or subject:FindFirstChild("HumanoidRootPart")
	end
	return nil
end

return Util
