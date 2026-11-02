local _, NS = ...
local BF = NS.BF

local Codec = {}
BF.Codec = Codec

local FORMAT = 1
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
-- Whitespace is escaped too, because Decode drops raw whitespace that chat line wrapping adds.
local RESERVED = "[%%;,:!/=|%s]"

local function esc(s)
	return (tostring(s or ""):gsub(RESERVED, function(c) return ("%%%02X"):format(c:byte()) end))
end

local function unesc(s)
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function split(s, sep)
	local out = {}
	if s ~= "" then
		local start = 1
		while true do
			local i = s:find(sep, start, true)
			out[#out + 1] = s:sub(start, (i or 0) - 1)
			if not i then break end
			start = i + 1
		end
	end
	return out
end

local function encodeTree(ranks)
	local last = 0
	for i = 1, #ranks do
		if ranks[i] ~= 0 then last = i end
	end
	local chars = {}
	for i = 1, last do
		local r = ranks[i]
		chars[i] = DIGITS:sub(r + 1, r + 1)
	end
	return table.concat(chars)
end

local function decodeTree(s)
	local ranks = {}
	for i = 1, #s do
		local pos = DIGITS:find(s:sub(i, i):lower(), 1, true)
		ranks[i] = pos and pos - 1 or 0
	end
	return ranks
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	return keys
end

-- The parts of a build that export and import can include or leave out. Name, classes and spec name always go.
-- Hunter pet aspects travel with perks.
Codec.SECTIONS = {
	{ key = "perks", label = "Perks", fields = { "perks", "pet" } },
	{ key = "talents", label = "Talents", fields = { "talents" } },
	{ key = "glyphs", label = "Glyphs", fields = { "glyphs" } },
	{ key = "gear", label = "Gear", fields = { "gear" } },
	{ key = "notes", label = "Notes", fields = { "notes" } },
}

local function filled(value)
	return value ~= nil and value ~= "" and not (type(value) == "table" and next(value) == nil)
end

-- Which sections the build has anything in, as { key = true }.
function Codec.Has(build)
	local has = {}
	for _, section in ipairs(Codec.SECTIONS) do
		for _, field in ipairs(section.fields) do
			if filled(build[field]) then has[section.key] = true end
		end
	end
	return has
end

-- A copy of the build with only the chosen sections ({ key = true }); nil keeps them all.
function Codec.Pick(build, sections)
	local out = { name = build.name, classes = build.classes, spec = build.spec }
	for _, section in ipairs(Codec.SECTIONS) do
		if not sections or sections[section.key] then
			for _, field in ipairs(section.fields) do out[field] = build[field] end
		end
	end
	return out
end

function Codec.Encode(build)
	local f = {}
	f[#f + 1] = "n=" .. esc(build.name)
	if build.classes and #build.classes > 0 then
		f[#f + 1] = "c=" .. table.concat(build.classes, ",")
	end
	if build.spec and build.spec ~= "" then f[#f + 1] = "s=" .. esc(build.spec) end

	if build.perks and #build.perks > 0 then
		local parts = {}
		for _, p in ipairs(build.perks) do
			local s = tostring(p.id)
			if (p.spell or 0) ~= 0 then
				s = s .. ":" .. (p.opt or 0) .. ":" .. p.spell
			elseif (p.opt or 0) ~= 0 then
				s = s .. ":" .. p.opt
			end
			parts[#parts + 1] = s
		end
		f[#f + 1] = "p=" .. table.concat(parts, ",")
	end

	if build.talents then
		local parts = {}
		for _, class in ipairs(sortedKeys(build.talents)) do
			local trees = {}
			for i, ranks in ipairs(build.talents[class]) do trees[i] = encodeTree(ranks) end
			parts[#parts + 1] = class .. ":" .. table.concat(trees, "-")
		end
		if #parts > 0 then f[#f + 1] = "t=" .. table.concat(parts, ",") end
	end

	if build.glyphs then
		local parts = {}
		for _, socket in ipairs(sortedKeys(build.glyphs)) do
			parts[#parts + 1] = socket .. ":" .. build.glyphs[socket]
		end
		if #parts > 0 then f[#f + 1] = "gl=" .. table.concat(parts, ",") end
	end

	if build.pet then f[#f + 1] = "h=" .. build.pet end

	if build.gear then
		local parts = {}
		for _, slot in ipairs(sortedKeys(build.gear)) do
			parts[#parts + 1] = slot .. ":" .. table.concat(build.gear[slot], "/")
		end
		if #parts > 0 then f[#f + 1] = "g=" .. table.concat(parts, ",") end
	end

	if build.notes and build.notes ~= "" then f[#f + 1] = "x=" .. esc(build.notes) end

	return ("!BF%d!%s!"):format(FORMAT, table.concat(f, ";"))
end

local readers = {}

readers.n = function(b, v) b.name = unesc(v) end
readers.s = function(b, v) b.spec = unesc(v) end
readers.x = function(b, v) b.notes = unesc(v) end
readers.h = function(b, v) b.pet = tonumber(v) end

readers.c = function(b, v)
	b.classes = {}
	for _, key in ipairs(split(v, ",")) do
		if BF.CLASS_IDS[key] then b.classes[#b.classes + 1] = key end
	end
end

readers.p = function(b, v)
	b.perks = {}
	for _, entry in ipairs(split(v, ",")) do
		local f = split(entry, ":")
		local id = tonumber(f[1])
		if id then
			b.perks[#b.perks + 1] = { id = id, opt = tonumber(f[2]) or 0, spell = tonumber(f[3]) or 0 }
		end
	end
end

readers.t = function(b, v)
	b.talents = {}
	for _, entry in ipairs(split(v, ",")) do
		local class, trees = entry:match("^(%u+):(.*)$")
		if class and BF.CLASS_IDS[class] then
			local t = {}
			for i, tree in ipairs(split(trees, "-")) do t[i] = decodeTree(tree) end
			b.talents[class] = t
		end
	end
end

readers.gl = function(b, v)
	b.glyphs = {}
	for _, entry in ipairs(split(v, ",")) do
		local socket, spell = entry:match("^(%d+):(%d+)$")
		if socket then b.glyphs[tonumber(socket)] = tonumber(spell) end
	end
end

readers.g = function(b, v)
	b.gear = {}
	for _, entry in ipairs(split(v, ",")) do
		local slot, items = entry:match("^(%d+):(.*)$")
		if slot then
			local list = {}
			for _, id in ipairs(split(items, "/")) do list[#list + 1] = tonumber(id) end
			if #list > 0 then b.gear[tonumber(slot)] = list end
		end
	end
end

-- Returns the build table, or nil and an error message.
function Codec.Decode(text)
	text = (text or ""):gsub("%s", "")
	local fmt, body = text:match("^!BF(%d+)!(.*)!$")
	local result, err
	if fmt then
		if tonumber(fmt) > FORMAT then
			err = "this build was exported by a newer BuildForge; update to import it"
		else
			result = {}
			for _, field in ipairs(split(body, ";")) do
				local key, value = field:match("^(%w+)=(.*)$")
				if key and readers[key] then readers[key](result, value) end
			end
		end
	else
		err = "not a BuildForge string"
	end
	return result, err
end
