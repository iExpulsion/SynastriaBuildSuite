local _, NS = ...
local SBS = NS.SBS

-- Reads SynastriaPerkManager (SPM) strings: one line of perk IDs, each with an optional ":options" mask in the
-- client's own option bits ("1,25:5,301:1208512398"). They carry perks only; the classes come from the class perks,
-- as SPM itself works them out. Misc perks are left out, as for SBM strings, so Shared Perks stay the player's.
local SPM = {}
SBS.SPM = SPM

-- True when the text is an SPM perk list (digits, colons and commas, starting with a perk ID).
function SPM.Is(text)
	local s = (text or ""):gsub("%s", "")
	return s:match("^%d[%d:,]*$") ~= nil
end

-- Decodes an SPM string into a build, in the shape Codec.Decode returns. Telling Misc and class perks apart needs
-- the perk list from the server, so until it arrives this returns nil and a reason.
function SPM.Decode(text)
	local build, err
	if PerkMgrPerks then
		build = { name = "SPM Import", perks = {}, notes = "" }
		for id, opt in (text or ""):gsub("%s", ""):gmatch("(%d+):?(%d*)") do
			local perk = { id = tonumber(id), opt = tonumber(opt) or 0, spell = 0 }
			if PerkMgrPerks[perk.id] and not SBS.Perks.IsShared(perk.id) then build.perks[#build.perks + 1] = perk end
		end
		build.classes = SBS.Build.InferClasses(build)
	else
		err = "the perk list hasn't loaded yet; try again in a moment"
	end
	return build, err
end
