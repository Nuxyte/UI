--!strict
--[[
	String : utilitaires de chaînes et de formatage de nombres / durées.

	API
		Trim(s)  Split(s, separator, plain?)  StartsWith(s, prefix)  EndsWith(s, suffix)
		Capitalize(s)  PadLeft(s, length, char?)  PadRight(s, length, char?)  Truncate(s, max, suffix?)
		Commas(n)           1234567    -> "1,234,567"
		Abbreviate(n, d?)   1500       -> "1.5K"   (K, M, B, T, Qa, Qi)
		FormatTime(seconds) 3725       -> "1:02:05"   (65 -> "1:05")
		Pluralize(n, singular, plural?)

	Exemple
		String.Abbreviate(2_500_000) --> "2.5M"
]]

local String = {}

function String.Trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

function String.Split(s: string, separator: string, plain: boolean?): { string }
	assert(separator ~= "", "String.Split : séparateur vide")
	local result: { string } = {}
	local usePlain = plain ~= false
	local position = 1
	while true do
		local from, to = string.find(s, separator, position, usePlain)
		if not from then
			table.insert(result, string.sub(s, position))
			break
		end
		table.insert(result, string.sub(s, position, from - 1))
		position = to + 1
	end
	return result
end

function String.StartsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

function String.EndsWith(s: string, suffix: string): boolean
	return suffix == "" or string.sub(s, -#suffix) == suffix
end

function String.Capitalize(s: string): string
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

function String.PadLeft(s: string, length: number, char: string?): string
	local pad = char or " "
	local missing = length - #s
	if missing <= 0 then
		return s
	end
	return string.rep(pad, missing) .. s
end

function String.PadRight(s: string, length: number, char: string?): string
	local pad = char or " "
	local missing = length - #s
	if missing <= 0 then
		return s
	end
	return s .. string.rep(pad, missing)
end

function String.Truncate(s: string, max: number, suffix: string?): string
	local tail = suffix or "..."
	if #s <= max then
		return s
	end
	return string.sub(s, 1, math.max(max - #tail, 0)) .. tail
end

function String.Commas(n: number): string
	local negative = n < 0
	local integer, fraction = math.modf(math.abs(n))
	local digits = string.format("%d", integer)
	local formatted = string.reverse(string.gsub(string.reverse(digits), "(%d%d%d)", "%1,"))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	if fraction > 0 then
		formatted ..= string.sub(string.format("%.2f", fraction), 2)
	end
	return (if negative then "-" else "") .. formatted
end

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

function String.Abbreviate(n: number, decimals: number?): string
	local places = decimals or 1
	local absolute = math.abs(n)
	if absolute < 1000 then
		return tostring(math.round(n * 10 ^ places) / 10 ^ places)
	end

	local index = math.min(math.floor(math.log10(absolute) / 3), #SUFFIXES)
	local scaled = n / 10 ^ (index * 3)
	local rounded = math.round(scaled * 10 ^ places) / 10 ^ places
	-- 999.96K arrondi à 1000K -> passe à l'unité supérieure.
	if math.abs(rounded) >= 1000 and index < #SUFFIXES then
		index += 1
		rounded = math.round(n / 10 ^ (index * 3) * 10 ^ places) / 10 ^ places
	end
	return tostring(rounded) .. SUFFIXES[index]
end

function String.FormatTime(seconds: number): string
	local total = math.max(math.floor(seconds), 0)
	local h = total // 3600
	local m = (total % 3600) // 60
	local s = total % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

function String.Pluralize(n: number, singular: string, plural: string?): string
	if n == 1 then
		return singular
	end
	return plural or (singular .. "s")
end

return String
