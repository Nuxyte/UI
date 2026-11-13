--!nonstrict
--[[
	UI.Util
	EnsureScale(gui, name?) -> UIScale     UIScale unique par nom (créé au besoin) : permet d'animer l'échelle sans toucher à Size
	IsPointInside(gui, point: Vector2) -> boolean   point en pixels écran (mêmes coordonnées que AbsolutePosition)
]]

local Util = {}

function Util.EnsureScale(gui: Instance, name: string?): Instance
	local scaleName = name or "_CoreScale"
	local scale = gui:FindFirstChild(scaleName)
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = scaleName
		scale.Parent = gui
	end
	return scale
end

function Util.IsPointInside(gui: GuiObject, point: Vector2): boolean
	local position, size = gui.AbsolutePosition, gui.AbsoluteSize
	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

return Util
