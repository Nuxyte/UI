--!nonstrict
--[[
	Instance.Create
	Création / clonage / destruction d'Instances.

	Create(className, props?, children?) -> Instance
		props : toutes les propriétés Roblox + clés spéciales :
			Parent      assigné EN DERNIER (meilleure performance, évite les réplications inutiles)
			Children    { Instance, ... }
			Attributes  { Nom = valeur }
			Tags        { "Tag1", "Tag2" }
			PrimaryPart (Model) assigné après l'ajout des enfants
		Si une propriété est invalide, l'Instance est détruite et une erreur claire est levée.
	Clone(instance, props?) -> Instance      (mêmes clés spéciales que Create)
	Part(props?) -> Part       défauts : Anchored = true, surfaces lisses, TopSurface/BottomSurface = Smooth
	Model(props?, children?) -> Model
	Destroy(instance, delay?) -> boolean     nil-safe ; delay via Debris
	DestroyChildren(parent, predicate?)       détruit les enfants (filtrables)
	DestroyChildrenOfClass(parent, className)

	Exemple
		local part = Core.Instance.Create("Part", {
			Name = "Projectile", Size = Vector3.one, Position = Vector3.new(0, 10, 0),
			Anchored = false, Parent = workspace,
			Attributes = { Damage = 25 }, Tags = { "Projectile" },
		})
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Create = {}

local DEFERRED = { Parent = true, Children = true, Attributes = true, Tags = true, PrimaryPart = true }

local function applyProperties(instance: Instance, props: { [string]: any })
	for key, value in props do
		if type(key) ~= "string" then
			error("propriété invalide : les clés doivent être des chaînes", 0)
		end
		if not DEFERRED[key] then
			local ok, err = pcall(function()
				(instance :: any)[key] = value
			end)
			if not ok then
				error(("impossible de définir '%s' sur %s : %s"):format(key, instance.ClassName, tostring(err)), 0)
			end
		end
	end
end

local function applyDeferred(instance: Instance, props: { [string]: any }, children: { Instance }?)
	local childList = children or props.Children
	if childList then
		if type(childList) ~= "table" then
			error("Children doit être une table d'Instances", 0)
		end
		for _, child in childList do
			if typeof(child) ~= "Instance" then
				error(("Children contient une valeur non-Instance (%s)"):format(typeof(child)), 0)
			end
			child.Parent = instance
		end
	end

	if props.PrimaryPart ~= nil then
		(instance :: any).PrimaryPart = props.PrimaryPart
	end

	if props.Attributes then
		for name, value in props.Attributes do
			instance:SetAttribute(name, value)
		end
	end

	if props.Tags then
		for _, tag in props.Tags do
			CollectionService:AddTag(instance, tag)
		end
	end

	if props.Parent ~= nil then
		instance.Parent = props.Parent
	end
end

local function build(instance: Instance, props: { [string]: any }?, children: { Instance }?, caller: string)
	local config = props or {}
	if type(config) ~= "table" then
		instance:Destroy()
		error(("Core.Instance.%s : `props` doit être une table"):format(caller), 3)
	end

	local ok, err = pcall(function()
		applyProperties(instance, config)
		applyDeferred(instance, config, children)
	end)
	if not ok then
		instance:Destroy()
		error(("Core.Instance.%s : %s"):format(caller, tostring(err)), 3)
	end
	return instance
end

function Create.Create(className: string, props: { [string]: any }?, children: { Instance }?): Instance
	if type(className) ~= "string" then
		error("Core.Instance.Create : `className` doit être une chaîne", 2)
	end
	local ok, instance = pcall(Instance.new, className)
	if not ok then
		error(("Core.Instance.Create : classe inconnue ou non créable '%s'"):format(className), 2)
	end
	return build(instance, props, children, "Create")
end

function Create.Clone(instance: Instance, props: { [string]: any }?): Instance
	if typeof(instance) ~= "Instance" then
		error("Core.Instance.Clone : Instance attendue", 2)
	end
	local copy = instance:Clone()
	if copy == nil then
		error(("Core.Instance.Clone : %s n'est pas clonable (Archivable = false)"):format(instance:GetFullName()), 2)
	end
	return build(copy, props, nil, "Clone")
end

function Create.Part(props: { [string]: any }?): Part
	local config = { Anchored = true, TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth }
	if props then
		for key, value in props do
			config[key] = value
		end
	end
	return Create.Create("Part", config) :: Part
end

function Create.Model(props: { [string]: any }?, children: { Instance }?): Model
	return Create.Create("Model", props, children) :: Model
end

--- Détruit une Instance sans erreur si nil / déjà détruite. `delay` via Debris.
function Create.Destroy(instance: Instance?, delay: number?): boolean
	if typeof(instance) ~= "Instance" then
		return false
	end
	if delay and delay > 0 then
		Debris:AddItem(instance, delay)
		return true
	end
	return (pcall(instance.Destroy, instance))
end

function Create.DestroyChildren(parent: Instance, predicate: ((Instance) -> boolean)?)
	if predicate == nil then
		parent:ClearAllChildren()
		return
	end
	for _, child in parent:GetChildren() do
		if predicate(child) then
			child:Destroy()
		end
	end
end

function Create.DestroyChildrenOfClass(parent: Instance, className: string)
	for _, child in parent:GetChildren() do
		if child:IsA(className) then
			child:Destroy()
		end
	end
end

return Create
