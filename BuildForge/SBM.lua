local _, NS = ...
local BF = NS.BF

-- Reads SynastriaBuildManager (SBM) strings, versions SBM2 and SBM3: one item per line, "SBM3", then the active
-- perk IDs, a "Class:tab:ranks,tab:ranks" line per class, "Sage:" with the chosen spell for perks 1561-1568,
-- "Opts:" with one 0/1 per OPTIONS entry, and "BM:" with the pet aspect mask.
local SBM = {}
BF.SBM = SBM

local SAGE_FIRST = 1561
local SBM2_OPTIONS = 37

-- SBM's option list in its bit order, as { perk name, option name }. SBM2 strings have only the first 37.
local OPTIONS = {
	{ "Automatic Buffs", "DK: Horn of Winter" }, { "Automatic Buffs", "Druid: Mark of the Wild" },
	{ "Automatic Buffs", "Druid: Thorns" }, { "Automatic Buffs", "Mage: Arcane Intellect" },
	{ "Automatic Buffs", "Paladin: Blessing of Kings" }, { "Automatic Buffs", "Priest: Divine Spirit" },
	{ "Automatic Buffs", "Priest: Fortitude" }, { "Automatic Buffs", "Priest: Shadow Protection" },
	{ "Automatic Buffs", "Shaman: Water Breathing" }, { "Automatic Buffs", "Warlock: Detect Invisibility" },
	{ "Automatic Buffs", "Warrior: Commanding Shout" },
	{ "Misc Options", "AH Attunable" }, { "Misc Options", "Notify WG" }, { "Misc Options", "AH Better Affix" },
	{ "Misc Options", "Always Show Affix" }, { "Misc Options", "Notify Leaderboard Update" },
	{ "Misc Options", "Stop crafting if Forged" }, { "Misc Options", "Notify on Forged" },
	{ "Misc Options", "Disable Bulk Craft" }, { "Misc Options", "Don't show attune bars" },
	{ "Misc Options", "Don't allow destroy favorited" }, { "Misc Options", "Limit damage" },
	{ "Misc Options", "No pet display" }, { "Misc Options", "Hide AH without buyout" },
	{ "Misc Options", "AH hide attuned" }, { "Misc Options", "Don't show bounty icon" },
	{ "Misc Options", "Show account attune bar" },
	{ "Tracking", "Only in Northrend" }, { "Tracking", "Minerals" }, { "Tracking", "Herbs" },
	{ "Prestige: Attune Mastery", "Disable for BoE" }, { "Prestige: Attune Mastery", "Excess Only" },
	{ "Prestige: Attune Mastery", "Disable" },
	{ "Prestige: Loot BoE", "Disabled" }, { "Prestige: Loot BoE", "Account" },
	{ "Prestige: Loot BoP", "Disabled" }, { "Prestige: Loot Chance", "Disabled" },
	{ "Automatic Accept Quest", "Disabled" }, { "Automatic Accept Quest", "Only Current Target" },
	{ "Automatic Bank", "Primary bank tab" }, { "Automatic Bank", "First bank bag" },
	{ "Automatic Bank", "Second bank bag" }, { "Automatic Bank", "Third bank bag" },
	{ "Automatic Bank", "Fourth bank bag" }, { "Automatic Bank", "Fifth bank bag" },
	{ "Automatic Bank", "Sixth bank bag" }, { "Automatic Bank", "Seventh bank bag" },
	{ "Automatic Mount", "Disabled" }, { "Automatic Mount", "Randomize" }, { "Automatic Mount", "Ignore Shapeshift" },
	{ "Extra Racial Skill", "Blood Elf" }, { "Extra Racial Skill", "Draenei" }, { "Extra Racial Skill", "Dwarf" },
	{ "Extra Racial Skill", "Gnome" }, { "Extra Racial Skill", "Human" }, { "Extra Racial Skill", "Night Elf" },
	{ "Extra Racial Skill", "Orc" }, { "Extra Racial Skill", "Tauren" }, { "Extra Racial Skill", "Troll" },
	{ "Extra Racial Skill", "Undead" },
	{ "Notify on Forged Drop", "Titanforged+" }, { "Notify on Forged Drop", "Warforged+" },
	{ "Notify on Forged Drop", "Lightforged+" },
	{ "Balance: Druid", "Hide animal form" }, { "Balance: Death Knight", "Hide Lich Form" },
	{ "Balance: Warrior", "Hide red fury" },
	{ "Prestige: Attune Mastery", "Auto DESTROY attuned items" },
	{ "Prestige: Loot BoE", "Prefer Unlearned Affix" }, { "Prestige: Loot BoE", "Affix Over Forge" },
	{ "Automatic Complete Quest", "Disabled" }, { "Automatic Complete Quest", "Notify" },
}

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
	local key = BF.CLASS_IDS[name:upper()] and name:upper()
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

-- Sets SBM's option bits on the build's perk entries; options of perks the string doesn't activate are dropped.
local function applyOptions(build, bits, version)
	local byName = {}
	for _, entry in ipairs(build.perks) do
		local perk = PerkMgrPerks and PerkMgrPerks[entry.id]
		if perk then byName[perk.name] = entry end
	end
	local count = version == 2 and SBM2_OPTIONS or #bits
	for i = 1, math.min(count, #OPTIONS) do
		local entry = byName[OPTIONS[i][1]]
		local info = entry and GetPerkOptionsInfo and GetPerkOptionsInfo(entry.id)
		for index, opt in pairs(info or {}) do
			if opt.n == OPTIONS[i][2] then
				local mask = bit.lshift(1, index - 1)
				local had = bit.band(entry.opt, mask) ~= 0
				if bits:sub(i, i) == "1" then
					entry.opt = bit.bor(entry.opt, mask)
				elseif had then
					entry.opt = entry.opt - mask
				end
			end
		end
	end
end

-- Decodes an SBM string into a build, in the shape Codec.Decode returns.
function SBM.Decode(text)
	local all = lines(text)
	local version = SBM.Version(text)
	local build = { name = "SBM Import", classes = {}, perks = {}, talents = {}, notes = "" }
	local opts
	for i = 2, #all do
		local line = all[i]
		local key, body = line:match("^(%a+):(.*)$")
		local lower = key and key:lower()
		if i == 2 and line:match("^[%d,]+$") then
			for id in line:gmatch("%d+") do
				if tonumber(id) > 0 then build.perks[#build.perks + 1] = { id = tonumber(id), opt = 0, spell = 0 } end
			end
		elseif lower == "sage" then
			local slot = 0
			for spell in body:gmatch("[^;]+") do
				slot = slot + 1
				for _, entry in ipairs(build.perks) do
					if entry.id == SAGE_FIRST + slot - 1 then entry.spell = tonumber(spell) or 0 end
				end
			end
		elseif lower == "opts" then
			opts = body
		elseif lower == "bm" then
			local mask = tonumber(body) or 0
			build.pet = mask > 0 and mask or nil
		else
			local class, tabs = line:match("^([^:]+):(.+)$")
			if class then
				local k = classKey(class)
				build.classes[#build.classes + 1] = k
				build.talents[k] = trees(tabs)
			end
		end
	end
	if opts then applyOptions(build, opts, version) end
	return build
end
