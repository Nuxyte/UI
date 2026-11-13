--!nonstrict
--[[
	Debug.Verbose / Info / Warn / Error : journal filtré par niveau, avec historique et étiquettes.

	Niveaux : "Debug" < "Info" < "Warn" < "Error" < "Off"   (Config.LogLevel ; Debug.SetLevel pour le changer à chaud)
	Debug.Verbose(...)  Debug.Info(...)  Debug.Warn(...)  Debug.Error(...)     (Error journalise sans lever d'erreur)
		Les arguments sont concaténés ; les non-chaînes passent par Inspect. Un message sous le niveau actif n'est ni
		imprimé ni mis en historique. Sortie : print (Verbose / Info) ou warn (Warn / Error).
	Debug.Logger(tag) -> { Verbose, Info, Warn, Error }     journal étiqueté : "[Core][Combat][WARN] ..."
	Debug.Assert(condition, ...) -> condition               journalise une Error si faux (ne lève pas)
	Debug.SetLevel(level)   Debug.GetLevel()
	Debug.GetHistory(filter?) -> { entrée }     filter : { Level = "Warn" (minimum), Tag = "Combat", Since = os.clock() }
		entrée = { Time, Level, Tag, Message }  (anneau de Config.DebugTools.HistorySize entrées)
	Debug.ClearHistory()   Debug.OnLog (Signal : entrée)   Debug.GetLogCounts() -> { Debug, Info, Warn, Error }
]]

local Config = require(script.Parent.Parent.Config)
local Signal = require(script.Parent.Parent.Utilities.Signal)
local Inspect = require(script.Parent.Inspect)

local Logger = {}

local ORDER = { Debug = 1, Info = 2, Warn = 3, Error = 4, Off = 5 }
local LABEL = { Debug = "DEBUG", Info = "INFO", Warn = "WARN", Error = "ERROR" }

local history = {}
local head, size = 0, 0 -- anneau : head = dernier index écrit
local counts = { Debug = 0, Info = 0, Warn = 0, Error = 0 }

Logger.OnLog = Signal.new()

function Logger.SetLevel(level: string)
	if ORDER[level] == nil then
		error(("Core.Debug.SetLevel : niveau inconnu '%s' (Debug, Info, Warn, Error, Off)"):format(tostring(level)), 2)
	end
	Config.LogLevel = level
end

function Logger.GetLevel(): string
	return Config.LogLevel
end

local function format(...: any): string
	local args = table.pack(...)
	local texts = table.create(args.n)
	for i = 1, args.n do
		texts[i] = Inspect.Inspect(args[i], { Depth = 2 })
	end
	return table.concat(texts, " ")
end

local function record(entry: any)
	local capacity = Config.DebugTools.HistorySize
	head = head % capacity + 1
	history[head] = entry
	size = math.min(size + 1, capacity)
end

local function emit(level: string, tag: string?, ...: any)
	local threshold = ORDER[Config.LogLevel] or ORDER.Info
	if ORDER[level] < threshold then
		return
	end

	local message = format(...)
	local entry = { Time = os.clock(), Level = level, Tag = tag, Message = message }
	counts[level] += 1
	record(entry)

	local prefix = "[Core]" .. (if tag then ("[%s]"):format(tag) else "") .. ("[%s] "):format(LABEL[level])
	if level == "Warn" or level == "Error" then
		warn(prefix .. message)
	else
		print(prefix .. message)
	end
	Logger.OnLog:Fire(entry)
end

function Logger.Verbose(...: any)
	emit("Debug", nil, ...)
end
function Logger.Info(...: any)
	emit("Info", nil, ...)
end
function Logger.Warn(...: any)
	emit("Warn", nil, ...)
end
function Logger.Error(...: any)
	emit("Error", nil, ...)
end

function Logger.Logger(tag: string)
	if type(tag) ~= "string" or tag == "" then
		error("Core.Debug.Logger : étiquette (string) requise", 2)
	end
	return {
		Verbose = function(...)
			emit("Debug", tag, ...)
		end,
		Info = function(...)
			emit("Info", tag, ...)
		end,
		Warn = function(...)
			emit("Warn", tag, ...)
		end,
		Error = function(...)
			emit("Error", tag, ...)
		end,
	}
end

function Logger.Assert(condition: any, ...: any): any
	if not condition then
		if select("#", ...) > 0 then
			emit("Error", "Assert", ...)
		else
			emit("Error", "Assert", "assertion échouée")
		end
	end
	return condition
end

function Logger.GetHistory(filter: any?): { any }
	local capacity = Config.DebugTools.HistorySize
	local minimum = if filter and filter.Level then ORDER[filter.Level] else 0
	if minimum == nil then
		error("Core.Debug.GetHistory : filter.Level inconnu", 2)
	end

	local result = {}
	for i = 1, size do
		-- du plus ancien au plus récent
		local index = (head - size + i - 1) % capacity + 1
		local entry = history[index]
		if
			entry
			and ORDER[entry.Level] >= minimum
			and (not filter or not filter.Tag or entry.Tag == filter.Tag)
			and (not filter or not filter.Since or entry.Time >= filter.Since)
		then
			table.insert(result, entry)
		end
	end
	return result
end

function Logger.ClearHistory()
	table.clear(history)
	head, size = 0, 0
end

function Logger.GetLogCounts()
	return table.clone(counts)
end

return Logger
