--!nonstrict
--[[
	Core.Instance
	Manipulation simplifiée des Instances Roblox. Toutes les fonctions sont à plat
	(`Core.Instance.Create`, `Core.Instance.Weld`...). Les fichiers ci-dessous sont
	aussi `require`ables individuellement.

	Create.lua    Create, Clone, Part, Model, Destroy, DestroyChildren, DestroyChildrenOfClass
	Query.lua     Find, FindByClass, FindAll, FindAncestor, GetByPath, WaitFor, ObserveChildren...
	Metadata.lua  Attributes (GetAttribute, SetAttributes, ObserveAttribute...) et Tags (AddTag, ObserveTag...)
	Physical.lua  Weld, WeldAll, CreateAttachment, Constrain, Hinge, BallSocket, Rope, Spring

	Exemple
		local Part = Core.Instance.Create("Part", {
			Name = "Projectile",
			Size = Vector3.one,
			Position = Vector3.new(0, 10, 0),
			Anchored = false,
			Parent = workspace,
		})
]]

local InstanceModule = {}

local CATEGORIES = {
	Create = require(script.Create),
	Query = require(script.Query),
	Metadata = require(script.Metadata),
	Physical = require(script.Physical),
}

for categoryName, category in CATEGORIES do
	for name, value in category do
		if InstanceModule[name] ~= nil then
			error(("Core.Instance : conflit de nom '%s' (catégorie %s)"):format(name, categoryName))
		end
		InstanceModule[name] = value
	end
end

return table.freeze(InstanceModule)
