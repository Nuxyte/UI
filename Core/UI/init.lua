--!nonstrict
--[[
	Core.UI   (CLIENT UNIQUEMENT — à utiliser depuis un LocalScript)
	Outils d'interface. Fonctions à plat (`Core.UI.Notify`) ; les fichiers sont aussi `require`ables séparément.

	Create.lua       Create, Frame, Label, Button, Image, ScreenGui, GetPlayerGui
	Animate.lua      Open, Close, Toggle, IsOpen, Transition, Punch
	Interaction.lua  BindButton, Hover, Draggable, Tooltip
	Widgets.lua      Notify, ProgressBar
	Util.lua         EnsureScale, IsPointInside
	Menu             UI.Menu.Register / Open / Close / Back ...          (gestion de menus)
	Responsive       UI.Responsive.Scale / Observe / GetBreakpoint ...   (interface adaptative)
	LoadingScreen    UI.LoadingScreen.Show / SetProgress / Preload / Hide

	Exemple
		local UI = Core.UI
		UI.Notify("Hello World!")
		local screen = UI.ScreenGui("Main")
		local play = UI.Button({ Text = "Jouer", Size = UDim2.fromOffset(160, 48), Corner = 8, Parent = screen })
		UI.BindButton(play, { OnClick = function() print("clic") end })
]]

local RunService = game:GetService("RunService")

if RunService:IsServer() then
	error("Core.UI : module réservé au client (LocalScript)", 2)
end

local UI = {}

local FLAT = {
	Create = require(script.Create),
	Animate = require(script.Animate),
	Interaction = require(script.Interaction),
	Widgets = require(script.Widgets),
	Util = require(script.Util),
}

for fileName, module in FLAT do
	for name, value in module do
		if UI[name] ~= nil then
			error(("Core.UI : conflit de nom '%s' (%s)"):format(name, fileName))
		end
		UI[name] = value
	end
end

UI.Menu = require(script.Menu)
UI.Responsive = require(script.Responsive)
UI.LoadingScreen = require(script.Loading)

return table.freeze(UI)
