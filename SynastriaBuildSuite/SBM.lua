local _, NS = ...
local SBS = NS.SBS

-- Reads SynastriaBuildManager (SBM) strings, versions SBM2 and SBM3: one item per line, "SBM3", then the active
-- perk IDs, a "Class:tab:ranks,tab:ranks" line per class, "Sage:" with the chosen spell for perks 1561-1568,
-- "Opts:" with SBM's option bits and "BM:" with the pet aspect mask. Misc perks are left out, and so are the
-- option bits, which are all Misc perk options: Shared Perks stay under the user's control.
local SBM = {}
SBS.SBM = SBM

local SAGE_FIRST = 1561

local function lines(text)
	local out = {}
	for raw in (text or ""):gmatch("[^\r\n]+") do
		local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" then out[#out + 1] = line end
	end
	return out
end

-- The SBM version (2 or 3) when the text is an SBM string.
function SBM.Version(text)
	local first = lines(text)[1]
	return first == "SBM3" and 3 or first == "SBM2" and 2 or nil
end

-- A class key for SBM's class names, which are class tokens ("DEATHKNIGHT") or, for dual-class characters, the
-- talent window's localized names ("Death Knight").
local function classKey(name)
	local key = SBS.CLASS_IDS[name:upper()] and name:upper()
	for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
		if localized == name then key = token end
	end
	for token, localized in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
		if localized == name then key = token end
	end
	return key or name:upper():gsub("%s", "")
end

-- "1:0035,3:5" as three trees of ranks by talent index.
local function trees(body)
	local out = { {}, {}, {} }
	for tab, ranks in body:gmatch("(%d+):(%d+)") do
		local tree = {}
		for i = 1, #ranks do tree[i] = tonumber(ranks:sub(i, i)) end
		out[tonumber(tab)] = tree
	end
	return out
end

local function parse(all)
	local build = { name = "SBM Import", classes = {}, perks = {}, talents = {}, notes = "" }
	for i = 2, #all do
		local line = all[i]
		local key, body = line:match("^(%a+):(.*)$")
		local lower = key and key:lower()
		if i == 2 and line:match("^[%d,]+$") then
			for id in line:gmatch("%d+") do
				local perk = { id = tonumber(id), opt = 0, spell = 0 }
				if perk.id > 0 and not SBS.Perks.IsShared(perk.id) then build.perks[#build.perks + 1] = perk end
			end
		elseif lower == "sage" then
			local slot = 0
			for spell in body:gmatch("[^;]+") do
				slot = slot + 1
				for _, entry in ipairs(build.perks) do
					if entry.id == SAGE_FIRST + slot - 1 then entry.spell = tonumber(spell) or 0 end
				end
			end
		elseif lower == "bm" then
			local mask = tonumber(body) or 0
			build.pet = mask > 0 and mask or nil
		elseif lower ~= "opts" then
			local class, tabs = line:match("^([^:]+):(.+)$")
			if class then
				local k = classKey(class)
				build.classes[#build.classes + 1] = k
				build.talents[k] = trees(tabs)
			end
		end
	end
	return build
end

-- Decodes an SBM string into a build, in the shape Codec.Decode returns. Telling Misc perks apart needs the perk
-- list from the server, so until it arrives this returns nil and a reason.
function SBM.Decode(text)
	local build, err
	if PerkMgrPerks then
		build = parse(lines(text))
	else
		err = "the perk list hasn't loaded yet; try again in a moment"
	end
	return build, err
end
