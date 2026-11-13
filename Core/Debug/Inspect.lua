--!nonstrict
--[[
	Debug.Inspect / Print : affichage lisible de n'importe quelle valeur (tables imbriquées, cycles, Instances, Vector3...).

	Debug.Inspect(value, options?) -> string
		options : Depth (3 : niveaux développés)   MaxItems (40 : entrées affichées par table)   Indent ("  ")
	Debug.Print(...)       print() de chaque valeur via Inspect (les chaînes restent brutes)

	Les clés sont triées (déterministe) ; les tableaux séquentiels s'affichent en liste ; les cycles donnent <cycle>.
]]

local Inspect = {}

local function scalar(value: any, nested: boolean): string?
	local kind = typeof(value)
	if kind == "string" then
		return if nested then string.format("%q", value) else value
	elseif kind == "number" or kind == "boolean" or kind == "nil" then
		return tostring(value)
	elseif kind == "Instance" then
		local ok, name = pcall(function()
			return value:GetFullName()
		end)
		return ("%s<%s>"):format(value.ClassName, if ok then name else "?")
	elseif kind == "function" or kind == "thread" or kind == "userdata" then
		return kind
	elseif kind ~= "table" then
		return tostring(value) -- Vector3, CFrame, Color3, EnumItem...
	end
	return nil
end

local function isArray(t: { [any]: any }): boolean
	local n = #t
	if n == 0 then
		return false
	end
	local count = 0
	for _ in t do
		count += 1
	end
	return count == n
end

local function keyText(key: any): string
	if type(key) == "string" and key:match("^[%a_][%w_]*$") then
		return key
	end
	return "[" .. (scalar(key, true) or tostring(key)) .. "]"
end

local function render(value: any, depth: number, options: any, seen: { [any]: boolean }, level: number): string
	local simple = scalar(value, level > 0)
	if simple then
		return simple
	end

	local meta = getmetatable(value)
	if type(meta) == "table" and type(meta.__tostring) == "function" then
		return tostring(value)
	end
	if seen[value] then
		return "<cycle>"
	end
	if depth <= 0 then
		return "{...}"
	end

	seen[value] = true
	local pad = string.rep(options.Indent, level + 1)
	local closePad = string.rep(options.Indent, level)
	local lines = {}

	if isArray(value) then
		for i, item in value do
			if i > options.MaxItems then
				table.insert(lines, pad .. ("… (+%d)"):format(#value - options.MaxItems))
				break
			end
			table.insert(lines, pad .. render(item, depth - 1, options, seen, level + 1))
		end
	else
		local keys = {}
		for key in value do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then
				return ta < tb
			end
			if ta == "number" or ta == "string" then
				return a < b
			end
			return tostring(a) < tostring(b)
		end)
		for i, key in keys do
			if i > options.MaxItems then
				table.insert(lines, pad .. ("… (+%d)"):format(#keys - options.MaxItems))
				break
			end
			table.insert(lines, pad .. keyText(key) .. " = " .. render(value[key], depth - 1, options, seen, level + 1))
		end
	end
	seen[value] = nil

	if #lines == 0 then
		return "{}"
	end
	return "{\n" .. table.concat(lines, ",\n") .. "\n" .. closePad .. "}"
end

function Inspect.Inspect(value: any, options: any?): string
	local opts = options or {}
	return render(value, if opts.Depth ~= nil then opts.Depth else 3, {
		Indent = opts.Indent or "  ",
		MaxItems = opts.MaxItems or 40,
	}, {}, 0)
end

function Inspect.Print(...: any)
	local parts = table.pack(...)
	local texts = {}
	for i = 1, parts.n do
		texts[i] = Inspect.Inspect(parts[i])
	end
	print(table.concat(texts, " "))
end

return Inspect
