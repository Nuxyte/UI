--!nonstrict
--[[
	Physics.Util
	GetRoot(subject) -> BasePart?   BasePart, ou PrimaryPart / HumanoidRootPart d'un Model
	RequireRoot(subject, fnName) -> BasePart   (erreur claire sinon)
	GetPosition(spec) -> Vector3     Vector3 | BasePart | Model | Attachment | function
	GetMass(subject) -> number       masse de l'assemblage
]]

local Util = {}

function Util.GetRoot(subject: any): BasePart?
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

function Util.RequireRoot(subject: any, fnName: string): BasePart
	local root = Util.GetRoot(subject)
	if not root then
		error(("Core.Physics.%s : BasePart ou Model (avec PrimaryPart / HumanoidRootPart) attendu"):format(fnName), 3)
	end
	return root
end

function Util.GetPosition(spec: any): Vector3
	local kind = typeof(spec)
	if kind == "Vector3" then
		return spec
	elseif kind == "function" then
		return spec()
	elseif kind == "Instance" then
		if spec:IsA("Attachment") then
			return spec.WorldPosition
		elseif spec:IsA("BasePart") then
			return spec.Position
		elseif spec:IsA("Model") then
			return spec:GetPivot().Position
		end
	end
	error(("Core.Physics : position invalide (%s) — attendu Vector3, BasePart, Model, Attachment ou fonction"):format(kind), 3)
end

function Util.GetMass(subject: any): number
	local root = Util.GetRoot(subject)
	return if root then root.AssemblyMass else 0
end

return Util
