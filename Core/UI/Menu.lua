--!nonstrict
--[[
	UI.Menu
	Gestionnaire de menus : ouverture exclusive, historique et retour arrière.

	Menu.Register(name, gui, options?)     options : Style (voir UI.Open)  Duration  Exclusive (true)  StartOpen (false)
	                                                 OnOpen()  OnClose()
	Menu.Open(name)  Menu.Close(name)  Menu.Toggle(name)  Menu.CloseAll()
	Menu.Back() -> boolean                 ferme le menu courant et rouvre le précédent (false si historique vide)
	Menu.IsOpen(name) -> boolean           Menu.GetOpen() -> { name }
	Menu.Unregister(name)
	Menu.Changed (Signal : name, isOpen)

	Un menu Exclusive en ferme les autres menus exclusifs à l'ouverture (et mémorise le précédent pour Back).
	Un menu dont le GuiObject est détruit est désenregistré automatiquement.

	Exemple
		UI.Menu.Register("Shop", shopFrame, { Style = "FromBottom" })
		UI.Menu.Register("Settings", settingsFrame)
		UI.Menu.Open("Shop"); UI.Menu.Open("Settings"); UI.Menu.Back()  -- revient à Shop
]]

local Signal = require(script.Parent.Parent.Utilities.Signal)
local Animate = require(script.Parent.Animate)

local Menu = { Changed = Signal.new() }

local registry = {}
local history = {}

local function get(name: string)
	local entry = registry[name]
	if not entry then
		error(("Core.UI.Menu : menu inconnu '%s'"):format(tostring(name)), 3)
	end
	return entry
end

local function setOpen(name: string, entry, open: boolean)
	if entry.open == open then
		return
	end
	entry.open = open

	local options = { Style = entry.style, Duration = entry.duration }
	if open then
		Animate.Open(entry.gui, options)
	else
		Animate.Close(entry.gui, options)
	end

	local callback = if open then entry.onOpen else entry.onClose
	if callback then
		task.spawn(callback)
	end
	Menu.Changed:Fire(name, open)
end

local function closeExclusive(except: string?, pushHistory: boolean)
	for otherName, other in registry do
		if other.open and other.exclusive and otherName ~= except then
			if pushHistory then
				table.insert(history, otherName)
			end
			setOpen(otherName, other, false)
		end
	end
end

function Menu.Register(name: string, gui: GuiObject, options: any?)
	if registry[name] then
		error(("Core.UI.Menu : '%s' est déjà enregistré"):format(name), 2)
	end
	if typeof(gui) ~= "Instance" or not gui:IsA("GuiObject") then
		error("Core.UI.Menu.Register : GuiObject attendu", 2)
	end

	local opts = options or {}
	local entry = {
		gui = gui,
		style = opts.Style or "Pop",
		duration = opts.Duration,
		exclusive = opts.Exclusive ~= false,
		onOpen = opts.OnOpen,
		onClose = opts.OnClose,
		open = false,
	}
	registry[name] = entry
	gui.Visible = false

	entry.destroyConnection = gui.Destroying:Connect(function()
		Menu.Unregister(name)
	end)

	if opts.StartOpen then
		Menu.Open(name)
	end
end

function Menu.Unregister(name: string)
	local entry = registry[name]
	if not entry then
		return
	end
	registry[name] = nil
	entry.destroyConnection:Disconnect()
	for i = #history, 1, -1 do
		if history[i] == name then
			table.remove(history, i)
		end
	end
end

local function openInternal(name: string, pushHistory: boolean)
	local entry = get(name)
	if entry.open then
		return
	end
	if entry.exclusive then
		closeExclusive(name, pushHistory)
	end
	setOpen(name, entry, true)
end

function Menu.Open(name: string)
	openInternal(name, true)
end

function Menu.Close(name: string)
	setOpen(name, get(name), false)
end

function Menu.Toggle(name: string)
	if get(name).open then
		Menu.Close(name)
	else
		Menu.Open(name)
	end
end

function Menu.CloseAll()
	for name, entry in registry do
		setOpen(name, entry, false)
	end
	table.clear(history)
end

function Menu.Back(): boolean
	while #history > 0 do
		local previous = table.remove(history)
		if registry[previous] then
			closeExclusive(previous, false)
			openInternal(previous, false)
			return true
		end
	end
	closeExclusive(nil, false)
	return false
end

function Menu.IsOpen(name: string): boolean
	return get(name).open
end

function Menu.GetOpen(): { string }
	local list = {}
	for name, entry in registry do
		if entry.open then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

return Menu
