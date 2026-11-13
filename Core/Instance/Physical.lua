--!nonstrict
--[[
	Instance.Physical
	Soudures, attachments et contraintes.

	Weld(part0, part1, props?) -> WeldConstraint       (conserve la position relative actuelle)
	WeldAll(model, root?)      -> { WeldConstraint }   soude toutes les BaseParts du modèle à `root`
	                                                    (défaut : PrimaryPart, sinon première BasePart)
	Unweld(part)               détruit les WeldConstraint reliés à la part
	CreateAttachment(parent, name?, cframe?) -> Attachment
	Constrain(className, attachment0, attachment1, props?) -> Constraint
	Hinge(a0, a1, props?)  BallSocket(a0, a1, props?)  Rope(a0, a1, length?, props?)  Spring(a0, a1, props?)

	Exemple
		Core.Instance.Weld(handle, blade)
		local rope = Core.Instance.Rope(attA, attB, 20)
]]

local Physical = {}

function Physical.Weld(part0: BasePart, part1: BasePart, props: { [string]: any }?): WeldConstraint
	if not (typeof(part0) == "Instance" and part0:IsA("BasePart") and typeof(part1) == "Instance" and part1:IsA("BasePart")) then
		error("Core.Instance.Weld : deux BaseParts attendues", 2)
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = "Weld"
	weld.Part0 = part0
	weld.Part1 = part1
	if props then
		for key, value in props do
			weld[key] = value
		end
	end
	if weld.Parent == nil then
		weld.Parent = part0
	end
	return weld
end

function Physical.WeldAll(model: Instance, root: BasePart?): { WeldConstraint }
	local anchor = root
	if anchor == nil and model:IsA("Model") then
		anchor = model.PrimaryPart
	end
	if anchor == nil then
		anchor = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if anchor == nil then
		error("Core.Instance.WeldAll : aucune BasePart trouvée", 2)
	end

	local welds = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= anchor then
			table.insert(welds, Physical.Weld(anchor, descendant))
		end
	end
	return welds
end

function Physical.Unweld(part: BasePart)
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end
	local root = part:FindFirstAncestorOfClass("Model") or workspace
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("WeldConstraint") and (descendant.Part0 == part or descendant.Part1 == part) then
			descendant:Destroy()
		end
	end
end

function Physical.CreateAttachment(parent: Instance, name: string?, cframe: CFrame?): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name or "Attachment"
	if cframe then
		attachment.CFrame = cframe
	end
	attachment.Parent = parent
	return attachment
end

function Physical.Constrain(className: string, attachment0: Attachment, attachment1: Attachment, props: { [string]: any }?): Constraint
	local ok, constraint = pcall(Instance.new, className)
	if not ok or not constraint:IsA("Constraint") then
		if ok then
			constraint:Destroy()
		end
		error(("Core.Instance.Constrain : '%s' n'est pas une contrainte valide"):format(tostring(className)), 2)
	end

	constraint.Attachment0 = attachment0
	constraint.Attachment1 = attachment1

	if props then
		local applied, err = pcall(function()
			for key, value in props do
				constraint[key] = value
			end
		end)
		if not applied then
			constraint:Destroy()
			error(("Core.Instance.Constrain : %s"):format(tostring(err)), 2)
		end
	end

	constraint.Parent = (attachment0.Parent :: Instance)
	return constraint
end

function Physical.Hinge(a0: Attachment, a1: Attachment, props: { [string]: any }?)
	return Physical.Constrain("HingeConstraint", a0, a1, props)
end

function Physical.BallSocket(a0: Attachment, a1: Attachment, props: { [string]: any }?)
	return Physical.Constrain("BallSocketConstraint", a0, a1, props)
end

function Physical.Rope(a0: Attachment, a1: Attachment, length: number?, props: { [string]: any }?)
	local config = { Length = length or (a0.WorldPosition - a1.WorldPosition).Magnitude }
	if props then
		for key, value in props do
			config[key] = value
		end
	end
	return Physical.Constrain("RopeConstraint", a0, a1, config)
end

function Physical.Spring(a0: Attachment, a1: Attachment, props: { [string]: any }?)
	return Physical.Constrain("SpringConstraint", a0, a1, props)
end

return Physical
