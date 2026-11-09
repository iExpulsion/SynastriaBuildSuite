local ADDON, NS = ...

local SBS = { version = GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version") or "dev" }
NS.SBS = SBS
_G.SynastriaBuildSuite = SBS

SBS.CLASS_KEYS = {
	[1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST",
	[6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID",
}
SBS.CLASS_IDS = {}
for id, key in pairs(SBS.CLASS_KEYS) do SBS.CLASS_IDS[key] = id end

-- Synastria's names for two-class pairs, from its GlueXML AccountLogin.lua (SL_DUAL_CLASSES). Looked up by
-- SBS:ComboName in either order.
local COMBOS = {
	Champion = { "WARRIOR", "PALADIN" }, Soldier = { "WARRIOR", "HUNTER" }, Blademaster = { "WARRIOR", "ROGUE" },
	Crusader = { "WARRIOR", "PRIEST" }, Butcher = { "WARRIOR", "DEATHKNIGHT" }, Ravager = { "WARRIOR", "SHAMAN" },
	Battlemage = { "WARRIOR", "MAGE" }, Vanquisher = { "WARRIOR", "WARLOCK" }, Barbarian = { "WARRIOR", "DRUID" },
	Avenger = { "PALADIN", "HUNTER" }, Agent = { "PALADIN", "ROGUE" }, Martyr = { "PALADIN", "PRIEST" },
	Enforcer = { "PALADIN", "DEATHKNIGHT" }, Sentinel = { "PALADIN", "SHAMAN" }, Inquisitor = { "PALADIN", "MAGE" },
	Warden = { "PALADIN", "WARLOCK" }, Guardian = { "PALADIN", "DRUID" },
	Scout = { "HUNTER", "ROGUE" }, Seer = { "HUNTER", "PRIEST" }, Slayer = { "HUNTER", "DEATHKNIGHT" },
	Tempest = { "HUNTER", "SHAMAN" }, Arcanist = { "HUNTER", "MAGE" }, Trickster = { "HUNTER", "WARLOCK" },
	Ranger = { "HUNTER", "DRUID" },
	Herald = { "ROGUE", "PRIEST" }, Assassin = { "ROGUE", "DEATHKNIGHT" }, Ninja = { "ROGUE", "SHAMAN" },
	Spellblade = { "ROGUE", "MAGE" }, Voidstalker = { "ROGUE", "WARLOCK" }, Spy = { "ROGUE", "DRUID" },
	Wraith = { "PRIEST", "DEATHKNIGHT" }, Oracle = { "PRIEST", "SHAMAN" }, Mystic = { "PRIEST", "MAGE" },
	Siren = { "PRIEST", "WARLOCK" }, Empath = { "PRIEST", "DRUID" },
	Summoner = { "DEATHKNIGHT", "SHAMAN" }, Lich = { "DEATHKNIGHT", "MAGE" }, Necromancer = { "DEATHKNIGHT", "WARLOCK" },
	Dreadweaver = { "DEATHKNIGHT", "DRUID" },
	Elementalist = { "SHAMAN", "MAGE" }, Harbinger = { "SHAMAN", "WARLOCK" }, Sage = { "SHAMAN", "DRUID" },
	Sorcerer = { "MAGE", "WARLOCK" }, Conjurer = { "MAGE", "DRUID" },
	Witch = { "WARLOCK", "DRUID" },
}
local comboByPair = {}
for combo, pair in pairs(COMBOS) do
	comboByPair[pair[1] .. "/" .. pair[2]] = combo
	comboByPair[pair[2] .. "/" .. pair[1]] = combo
end

-- The combo name for two class keys, or nil (same-class pairs have none here).
function SBS:ComboName(a, b)
	return a and b and comboByPair[a .. "/" .. b]
end

function SBS:Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage("|cffffc400Synastria Build Suite|r:" .. msg)
end

-- Synastria's own functions and data come in after addons load, in a different order on login and on /reload.
-- SynastriaSafeInvoke calls the named global once both are there; SBS.ready stays nil on clients without it.
function SynastriaBuildSuite_OnReady()
	SBS.ready = true
end
if SynastriaSafeInvoke then SynastriaSafeInvoke("SynastriaBuildSuite_OnReady") end

-- GetItemInfo's returns, also for items the client hasn't cached yet where Synastria's lookup exists.
function SBS.ItemInfo(id)
	return (GetItemInfoCustom or GetItemInfo)(id)
end

-- The character's classes in pick order, as class keys.
function SBS:PlayerClasses()
	local classes = {}
	local count = CMCGetClassCount and CMCGetClassCount() or 0
	if count >= 1 then
		for i = 1, count do
			local id = CMCGetClassAt(i)
			classes[#classes + 1] = (CMCGetClassKey and CMCGetClassKey(id)) or self.CLASS_KEYS[id]
		end
	else
		classes[1] = select(2, UnitClass("player"))
	end
	return classes
end

function SBS:HasClass(key)
	for _, k in ipairs(self:PlayerClasses()) do
		if k == key then return true end
	end
	return false
end

function SBS:ActiveGroup()
	return GetActiveTalentGroup and GetActiveTalentGroup(false, false) or 1
end

-- Talent specs (Synastria allows up to 8) ------------------------------------------------------------------

function SBS:SpecCount()
	return GetNumTalentGroups and GetNumTalentGroups(false, false) or 1
end

function SBS:SpecName(group)
	local name = GetCustomGameDataString and GetCustomGameDataString(21, group) or ""
	return ("Spec %d"):format(group) .. ((name and name ~= "") and (": " .. name) or "")
end

local function charKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- This character's spec-to-build links. Kept in the account file so renames and deletes reach every character.
function SBS:Links()
	local key = charKey()
	self.db.links[key] = self.db.links[key] or {}
	return self.db.links[key]
end

-- The specs on this character linked to a build, lowest first.
function SBS:LinkedSpecs(name)
	local groups = {}
	for group, linked in pairs(self:Links()) do
		if linked == name and group <= self:SpecCount() then groups[#groups + 1] = group end
	end
	table.sort(groups)
	return groups
end

-- Links a build to one spec (replacing its other links), or unlinks it when group is nil.
function SBS:LinkSpec(name, group)
	local links = self:Links()
	for g, linked in pairs(links) do
		if linked == name then links[g] = nil end
	end
	if group then links[group] = name end
	self:Changed()
end

function SBS:RenameLinks(old, new)
	for _, links in pairs(self.db.links) do
		for g, linked in pairs(links) do
			if linked == old then links[g] = new end
		end
	end
end

local frame = CreateFrame("Frame")
SBS.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == ADDON then
		SynastriaBuildSuiteDB = SynastriaBuildSuiteDB or {}
		SynastriaBuildSuiteDB.builds = SynastriaBuildSuiteDB.builds or {}
		SynastriaBuildSuiteDB.shared = SynastriaBuildSuiteDB.shared or { perks = {} }
		SynastriaBuildSuiteDB.links = SynastriaBuildSuiteDB.links or {}
		SynastriaBuildSuiteCharDB = SynastriaBuildSuiteCharDB or {}
		SBS.db, SBS.charDB = SynastriaBuildSuiteDB, SynastriaBuildSuiteCharDB
		self:UnregisterEvent("ADDON_LOADED")
	end
end)
