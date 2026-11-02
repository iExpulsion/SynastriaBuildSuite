local _, NS = ...
local BF = NS.BF

local Glyphs = {}
BF.Glyphs = Glyphs

function Glyphs.Capture()
	local glyphs, group = {}, BF:ActiveGroup()
	for socket = 1, GetNumGlyphSockets and GetNumGlyphSockets() or 6 do
		local enabled, _, spell = GetGlyphSocketInfo(socket, group)
		if enabled and spell then glyphs[socket] = spell end
	end
	return glyphs
end

-- Glyphs are used up when socketed, so this only lists what differs.
function Glyphs.Plan(wanted)
	local missing, group = {}, BF:ActiveGroup()
	for socket, spell in pairs(wanted or {}) do
		local _, _, have = GetGlyphSocketInfo(socket, group)
		if have ~= spell then
			missing[#missing + 1] = { socket = socket, spell = spell, name = GetSpellInfo(spell) or ("Glyph " .. spell) }
		end
	end
	table.sort(missing, function(a, b) return a.socket < b.socket end)
	return missing
end

-- Editing a build's glyphs ----------------------------------------------------------------------------------

-- The stock 3.3.5 sockets: which kind of glyph each takes and the level it opens at.
Glyphs.SOCKETS = {
	{ kind = "major", level = 15 }, { kind = "minor", level = 15 }, { kind = "minor", level = 50 },
	{ kind = "major", level = 30 }, { kind = "minor", level = 70 }, { kind = "major", level = 80 },
}

local bySpell

-- The data entry for a glyph spell: { spell, item, name, class = key, kind = "major" | "minor" }.
function Glyphs.Find(spell)
	if not bySpell then
		bySpell = {}
		for class, kinds in pairs(NS.GlyphData or {}) do
			for kind, list in pairs(kinds) do
				for _, g in ipairs(list) do
					bySpell[g[1]] = { spell = g[1], item = g[2], name = g[3], class = class, kind = kind }
				end
			end
		end
	end
	return bySpell[spell]
end

-- The glyphs of one kind the classes can use, by class in the order given.
function Glyphs.Options(classes, kind)
	local out, seen = {}, {}
	for _, class in ipairs(classes) do
		local data = NS.GlyphData and NS.GlyphData[class]
		if data and not seen[class] then
			seen[class] = true
			for _, g in ipairs(data[kind] or {}) do
				out[#out + 1] = Glyphs.Find(g[1])
			end
		end
	end
	return out
end

-- Puts a glyph in a socket. A glyph can only be socketed once, so it leaves any other socket it was in.
-- Returns ok, and a reason when it doesn't fit.
function Glyphs.Set(build, socket, spell)
	local g = Glyphs.Find(spell)
	local info = Glyphs.SOCKETS[socket]
	local ok = g ~= nil and info ~= nil and g.kind == info.kind
	local reason
	if ok then
		build.glyphs = build.glyphs or {}
		for s, other in pairs(build.glyphs) do
			if other == spell then build.glyphs[s] = nil end
		end
		build.glyphs[socket] = spell
	elseif g and info then
		reason = ("That's a %s glyph; this socket takes %s glyphs."):format(g.kind, info.kind)
	end
	return ok, reason
end

function Glyphs.Clear(build, socket)
	if build.glyphs then build.glyphs[socket] = nil end
end

-- Per socket: the build's glyph, whether it's socketed in the active spec, and whether its item is in your bags.
function Glyphs.Status(build)
	local rows, group = {}, BF:ActiveGroup()
	for socket in ipairs(Glyphs.SOCKETS) do
		local spell = build.glyphs and build.glyphs[socket]
		local _, _, have = GetGlyphSocketInfo(socket, group)
		local g = spell and Glyphs.Find(spell)
		rows[socket] = {
			socket = socket, spell = spell, glyph = g,
			socketed = spell ~= nil and have == spell,
			inBags = g ~= nil and GetItemCount(g.item) > 0,
		}
	end
	return rows
end
