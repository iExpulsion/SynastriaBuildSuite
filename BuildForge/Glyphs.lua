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
