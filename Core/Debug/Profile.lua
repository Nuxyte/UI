--!nonstrict
--[[
	Debug.Measure / Time / Benchmark : mesure de performance (os.clock), sans aucune boucle.

	Debug.Measure(label) -> stop() -> secondes          chronomètre manuel agrégé sous `label`
	Debug.Time(label, fn, ...) -> résultats de fn       mesure fn (même si elle lève une erreur, qui est relancée)
	Debug.Benchmark(fn, iterations?, warmup?) -> { Iterations, Total, Average, Min, Max, PerSecond }
		iterations (1000)   warmup (10 appels non comptés)    fn reçoit l'index de l'itération
	Debug.GetProfile() -> { [label] = { Count, Total, Average, Min, Max, Last } }
	Debug.ResetProfile(label?)
	Debug.ProfileReport(top?) -> string          tableau trié par temps total décroissant

	Exemple
		Core.Debug.Time("pathfinding", computePath, start, goal)
		print(Core.Debug.ProfileReport(5))
]]

local Profile = {}

local entries = {}

local function add(label: string, elapsed: number)
	local entry = entries[label]
	if not entry then
		entry = { Count = 0, Total = 0, Min = math.huge, Max = 0, Last = 0 }
		entries[label] = entry
	end
	entry.Count += 1
	entry.Total += elapsed
	entry.Min = math.min(entry.Min, elapsed)
	entry.Max = math.max(entry.Max, elapsed)
	entry.Last = elapsed
end

function Profile.Measure(label: string)
	if type(label) ~= "string" then
		error("Core.Debug.Measure : label (string) requis", 2)
	end
	local start = os.clock()
	local stopped = false
	return function(): number
		local elapsed = os.clock() - start
		if not stopped then
			stopped = true
			add(label, elapsed)
		end
		return elapsed
	end
end

local function finish(label: string, start: number, ok: boolean, ...: any)
	add(label, os.clock() - start)
	if not ok then
		error((...), 0)
	end
	return ...
end

function Profile.Time(label: string, fn: (...any) -> ...any, ...: any)
	if type(label) ~= "string" or type(fn) ~= "function" then
		error("Core.Debug.Time : (label: string, fn: function, ...)", 2)
	end
	local start = os.clock()
	return finish(label, start, pcall(fn, ...))
end

function Profile.Benchmark(fn: (number) -> (), iterations: number?, warmup: number?)
	if type(fn) ~= "function" then
		error("Core.Debug.Benchmark : fonction requise", 2)
	end
	local count = iterations or 1000
	if count < 1 or count % 1 ~= 0 then
		error("Core.Debug.Benchmark : iterations doit être un entier >= 1", 2)
	end

	for i = 1, warmup or 10 do
		fn(-i)
	end

	local total, min, max = 0, math.huge, 0
	for i = 1, count do
		local start = os.clock()
		fn(i)
		local elapsed = os.clock() - start
		total += elapsed
		min = math.min(min, elapsed)
		max = math.max(max, elapsed)
	end

	return {
		Iterations = count,
		Total = total,
		Average = total / count,
		Min = min,
		Max = max,
		PerSecond = if total > 0 then count / total else math.huge,
	}
end

function Profile.GetProfile()
	local copy = {}
	for label, entry in entries do
		copy[label] = {
			Count = entry.Count,
			Total = entry.Total,
			Average = entry.Total / entry.Count,
			Min = entry.Min,
			Max = entry.Max,
			Last = entry.Last,
		}
	end
	return copy
end

function Profile.ResetProfile(label: string?)
	if label then
		entries[label] = nil
	else
		table.clear(entries)
	end
end

function Profile.ProfileReport(top: number?): string
	local list = {}
	for label, entry in Profile.GetProfile() do
		table.insert(list, { label = label, entry = entry })
	end
	table.sort(list, function(a, b)
		if a.entry.Total ~= b.entry.Total then
			return a.entry.Total > b.entry.Total
		end
		return a.label < b.label
	end)

	local lines = { ("%-24s %8s %10s %10s %10s"):format("Label", "Appels", "Total ms", "Moy ms", "Max ms") }
	for i, item in list do
		if top and i > top then
			break
		end
		local e = item.entry
		table.insert(lines, ("%-24s %8d %10.3f %10.3f %10.3f"):format(item.label, e.Count, e.Total * 1000, e.Average * 1000, e.Max * 1000))
	end
	return table.concat(lines, "\n")
end

return Profile
