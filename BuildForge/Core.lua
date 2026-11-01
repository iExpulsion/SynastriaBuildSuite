local ADDON, NS = ...

local BF = { version = GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version") or "dev" }
NS.BF = BF
_G.BuildForge = BF

BF.CLASS_KEYS = {
	[1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST",
	[6] = "DEATHKNIGHT", [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID",
}
BF.CLASS_IDS = {}
for id, key in pairs(BF.CLASS_KEYS) do BF.CLASS_IDS[key] = id end

function BF:Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage("|cffff8020BuildForge|r: " .. msg)
end

-- The character's classes in pick order, as class keys.
function BF:PlayerClasses()
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

function BF:HasClass(key)
	for _, k in ipairs(self:PlayerClasses()) do
		if k == key then return true end
	end
	return false
end

function BF:ActiveGroup()
	return GetActiveTalentGroup and GetActiveTalentGroup(false, false) or 1
end

local frame = CreateFrame("Frame")
BF.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == ADDON then
		BuildForgeDB = BuildForgeDB or {}
		BuildForgeDB.builds = BuildForgeDB.builds or {}
		BuildForgeCharDB = BuildForgeCharDB or {}
		BuildForgeCharDB.applied = BuildForgeCharDB.applied or {}
		BF.db, BF.charDB = BuildForgeDB, BuildForgeCharDB
		self:UnregisterEvent("ADDON_LOADED")
	end
end)
