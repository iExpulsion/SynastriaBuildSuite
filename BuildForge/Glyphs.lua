local _, NS = ...
local BF = NS.BF

local Glyphs = {}
BF.Glyphs = Glyphs

-- Each class has its own glyphs, stored as build.glyphs[class][socket] = spell. Selecting a class in the talent
-- API (BF.Talents.Select) refreshes that class's talent info, glyphs included, so the glyph API reads that class.

local function readSockets(group)
	local glyphs = {}
	for socket = 1, GetNumGlyphSockets and GetNumGlyphSockets() or 6 do
		local enabled, _, spell = GetGlyphSocketInfo(socket, group)
		if enabled and spell then glyphs[socket] = spell end
	end
	return glyphs
end

-- Each class's socketed glyphs in spec `group` (the active spec by default).
function Glyphs.Capture(group)
	local shown = BF.Talents.SelectedClass()
	group = group or BF:ActiveGroup()
	local result = {}
	for _, class in ipairs(BF:PlayerClasses()) do
		local sockets = BF.Talents.Select(class) and readSockets(group)
		if sockets and next(sockets) then result[class] = sockets end
	end
	BF.Talents.Select(shown)
	return result
end

-- Glyphs are used up when socketed, so this only lists what differs, for the classes the character has.
function Glyphs.Plan(wanted)
	local missing, group, shown = {}, BF:ActiveGroup(), BF.Talents.SelectedClass()
	for class, sockets in pairs(wanted or {}) do
		if BF:HasClass(class) and BF.Talents.Select(class) then
			for socket, spell in pairs(sockets) do
				local _, _, have = GetGlyphSocketInfo(socket, group)
				if have ~= spell then
					missing[#missing + 1] = { class = class, socket = socket, spell = spell,
						name = GetSpellInfo(spell) or ("Glyph " .. spell) }
				end
			end
		end
	end
	BF.Talents.Select(shown)
	table.sort(missing, function(a, b)
		if a.class ~= b.class then return a.class < b.class end
		return a.socket < b.socket
	end)
	return missing
end

-- The build's sockets for one class (read only; empty when it has none).
function Glyphs.For(build, class)
	return build.glyphs and build.glyphs[class] or {}
end

-- Opens the talent frame on the active spec's glyph tab. ToggleGlyphFrame goes through Synastria's
-- PlayerTalentFrame_ToggleGlyphFrame, which only searches the stock specs 1-2 (TALENT_SORT_ORDER), so for spec 3
-- and up it opened the talents instead; PlayerTalentFrame_OpenGlyphFrame searches all of them.
function Glyphs.OpenFrame()
	TalentFrame_LoadUI()
	if PlayerTalentFrame_OpenGlyphFrame then
		PlayerTalentFrame_OpenGlyphFrame(BF:ActiveGroup())
	else
		ToggleGlyphFrame()
	end
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

-- Puts a glyph in one of a class's sockets. A glyph can only be socketed once, so it leaves any other socket it
-- was in. Returns ok, and a reason when it doesn't fit.
function Glyphs.Set(build, class, socket, spell)
	local g = Glyphs.Find(spell)
	local info = Glyphs.SOCKETS[socket]
	local ok = g ~= nil and info ~= nil and g.kind == info.kind and g.class == class
	local reason
	if ok then
		build.glyphs = build.glyphs or {}
		local sockets = build.glyphs[class] or {}
		build.glyphs[class] = sockets
		for s, other in pairs(sockets) do
			if other == spell then sockets[s] = nil end
		end
		sockets[socket] = spell
	elseif g and info and g.kind ~= info.kind then
		reason = ("That's a %s glyph; this socket takes %s glyphs."):format(g.kind, info.kind)
	elseif g and info then
		reason = "That glyph is for another class."
	end
	return ok, reason
end

function Glyphs.Clear(build, class, socket)
	local sockets = build.glyphs and build.glyphs[class]
	if sockets then
		sockets[socket] = nil
		if next(sockets) == nil then build.glyphs[class] = nil end
	end
end

-- Per socket of one class: the build's glyph, whether it's socketed in the active spec, and whether its item is in
-- your bags. Socketed is only known for the class shown in the talent window (the second return), since reading
-- another class would mean switching to it.
function Glyphs.Status(build, class)
	local rows, group = {}, BF:ActiveGroup()
	local comparable = class == BF.Talents.SelectedClass()
	local sockets = Glyphs.For(build, class)
	for socket in ipairs(Glyphs.SOCKETS) do
		local spell = sockets[socket]
		local have = comparable and select(3, GetGlyphSocketInfo(socket, group))
		local g = spell and Glyphs.Find(spell)
		rows[socket] = {
			socket = socket, spell = spell, glyph = g,
			socketed = spell ~= nil and have == spell,
			inBags = g ~= nil and GetItemCount(g.item) > 0,
		}
	end
	return rows, comparable
end

-- Glyphs of the class shown in the talent window that aren't socketed; never switches classes.
function Glyphs.ShownMissing(build)
	local n = 0
	for _, row in ipairs(Glyphs.Status(build, BF.Talents.SelectedClass())) do
		if row.spell and not row.socketed then n = n + 1 end
	end
	return n
end
