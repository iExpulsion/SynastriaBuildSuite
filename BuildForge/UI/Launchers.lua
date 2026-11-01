local _, NS = ...
local BF = NS.BF

-- "BuildForge" buttons above the Perk window and the talent frame. The server sends the Perk window's Lua
-- after login and the talent frame may load on demand, so this checks until both exist.
local Launchers = {}
BF.Launchers = Launchers

local CHECK_EVERY, GIVE_UP_AFTER = 1, 600
local attached = {}

local function attach(parentName)
	local parent = _G[parentName]
	if parent and not attached[parentName] then
		local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		b:SetSize(96, 20)
		b:SetText("BuildForge")
		b:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -40, -2)
		b:SetScript("OnClick", function() BF.Window.Toggle() end)
		attached[parentName] = b
	end
	return attached[parentName] ~= nil
end

function Launchers.Check()
	local perks = attach("PerkMgrFrame")
	local talents = attach("PlayerTalentFrame")
	return perks and talents
end

local watcher = CreateFrame("Frame")
local elapsed, total = 0, 0
watcher:SetScript("OnUpdate", function(self, dt)
	elapsed, total = elapsed + dt, total + dt
	if elapsed >= CHECK_EVERY then
		elapsed = 0
		if Launchers.Check() or total > GIVE_UP_AFTER then self:SetScript("OnUpdate", nil) end
	end
end)
