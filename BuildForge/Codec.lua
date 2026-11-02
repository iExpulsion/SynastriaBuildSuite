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

local function b36(n)
	n = math.floor(tonumber(n) or 0)
	local s = ""
	repeat
		local r = n % 36
		s = DIGITS:sub(r + 1, r + 1) .. s
		n = (n - r) / 36
	until n == 0
	return s
end

local function num(s)
	return s ~= "" and tonumber(s, 36) or nil
end

-- Talent ranks never pass 5, so two ranks share one base-36 character (6 * first + second).
local TALENT_BASE = 6

local function encodeTree(ranks)
	local last = 0
	for i = 1, #ranks do
		if ranks[i] ~= 0 then last = i end
	end
	local chars = {}
	for i = 1, last, 2 do
		local a = math.min(ranks[i] or 0, TALENT_BASE - 1)
		local b = math.min(ranks[i + 1] or 0, TALENT_BASE - 1)
		local v = a * TALENT_BASE + b
		chars[#chars + 1] = DIGITS:sub(v + 1, v + 1)
	end
	return table.concat(chars)
end

local function decodeTree(s)
	local ranks = {}
	for i = 1, #s do
		local v = num(s:sub(i, i):lower()) or 0
		ranks[#ranks + 1] = math.floor(v / TALENT_BASE)
		ranks[#ranks + 1] = v % TALENT_BASE
	end
	return ranks
end

-- Numbered slots (glyph sockets, gear slots) written in order with "." between, so the slot is the position;
-- trailing empty slots are dropped.
local function encodeSlots(t, count, write)
	local parts, last = {}, 0
	for i = 1, count do
		parts[i] = t[i] and write(t[i]) or ""
		if parts[i] ~= "" then last = i end
	end
	return table.concat(parts, ".", 1, last)
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

local GLYPH_SOCKETS, GEAR_SLOTS = 6, 18

-- Numbers are base 36 throughout. See docs/DESIGN.md for the layout of each field.
function Codec.Encode(build)
	local f = {}
	f[#f + 1] = "n=" .. esc(build.name)
	if build.classes and #build.classes > 0 then
		local ids = {}
		for i, key in ipairs(build.classes) do ids[i] = b36(BF.CLASS_IDS[key]) end
		f[#f + 1] = "c=" .. table.concat(ids)
	end
	-- an empty s= means "same as the build name"
	if build.spec and build.spec ~= "" then
		f[#f + 1] = "s=" .. (build.spec == build.name and "" or esc(build.spec))
	end

	if build.perks and #build.perks > 0 then
		local perks = {}
		for i, p in ipairs(build.perks) do perks[i] = p end
		table.sort(perks, function(a, b) return a.id < b.id end)
		local parts, prev = {}, 0
		for _, p in ipairs(perks) do
			local s = b36(p.id - prev)
			if (p.spell or 0) ~= 0 then
				s = s .. ":" .. b36(p.opt or 0) .. ":" .. b36(p.spell)
			elseif (p.opt or 0) ~= 0 then
				s = s .. ":" .. b36(p.opt)
			end
			parts[#parts + 1] = s
			prev = p.id
		end
		f[#f + 1] = "p=" .. table.concat(parts, ".")
	end

	if build.talents then
		local parts = {}
		for _, class in ipairs(sortedKeys(build.talents)) do
			local trees = {}
			for i, ranks in ipairs(build.talents[class]) do trees[i] = encodeTree(ranks) end
			parts[#parts + 1] = b36(BF.CLASS_IDS[class]) .. ":" .. table.concat(trees, "-")
		end
		if #parts > 0 then f[#f + 1] = "t=" .. table.concat(parts, ",") end
	end

	if build.glyphs then
		local parts = {}
		for _, class in ipairs(sortedKeys(build.glyphs)) do
			local sockets = encodeSlots(build.glyphs[class], GLYPH_SOCKETS, b36)
			if sockets ~= "" then parts[#parts + 1] = b36(BF.CLASS_IDS[class]) .. ":" .. sockets end
		end
		if #parts > 0 then f[#f + 1] = "gl=" .. table.concat(parts, ",") end
	end

	if build.pet then f[#f + 1] = "h=" .. b36(build.pet) end

	local gear = build.gear and encodeSlots(build.gear, GEAR_SLOTS, function(items)
		local ids = {}
		for i, id in ipairs(items) do ids[i] = b36(id) end
		return table.concat(ids, "/")
	end) or ""
	if gear ~= "" then f[#f + 1] = "g=" .. gear end

	if build.notes and build.notes ~= "" then f[#f + 1] = "x=" .. esc(build.notes) end

	return ("!BF%d!%s!"):format(FORMAT, table.concat(f, ";"))
end

local readers = {}

readers.n = function(b, v) b.name = unesc(v) end
readers.s = function(b, v) b.spec = v == "" and true or unesc(v) end
readers.x = function(b, v) b.notes = unesc(v) end
readers.h = function(b, v) b.pet = num(v) end

readers.c = function(b, v)
	b.classes = {}
	for i = 1, #v do
		local key = BF.CLASS_KEYS[num(v:sub(i, i))]
		if key then b.classes[#b.classes + 1] = key end
	end
end

readers.p = function(b, v)
	b.perks = {}
	local id = 0
	for _, entry in ipairs(split(v, ".")) do
		local f = split(entry, ":")
		local delta = num(f[1] or "")
		if delta then
			id = id + delta
			b.perks[#b.perks + 1] = { id = id, opt = num(f[2] or "") or 0, spell = num(f[3] or "") or 0 }
		end
	end
end

readers.t = function(b, v)
	b.talents = {}
	for _, entry in ipairs(split(v, ",")) do
		local id, trees = entry:match("^(%w):(.*)$")
		local class = id and BF.CLASS_KEYS[num(id)]
		if class then
			local t = {}
			for i, tree in ipairs(split(trees, "-")) do t[i] = decodeTree(tree) end
			b.talents[class] = t
		end
	end
end

readers.gl = function(b, v)
	b.glyphs = {}
	for _, entry in ipairs(split(v, ",")) do
		local id, sockets = entry:match("^(%w):(.*)$")
		local class = id and BF.CLASS_KEYS[num(id)]
		if class then
			local g = {}
			for socket, spell in ipairs(split(sockets, ".")) do
				if spell ~= "" then g[socket] = num(spell) end
			end
			b.glyphs[class] = g
		end
	end
end

readers.g = function(b, v)
	b.gear = {}
	for slot, items in ipairs(split(v, ".")) do
		local list = {}
		for _, id in ipairs(split(items, "/")) do list[#list + 1] = num(id) end
		if #list > 0 then b.gear[slot] = list end
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
			if result.spec == true then result.spec = result.name end
		end
	else
		err = "not a BuildForge string"
	end
	return result, err
end
