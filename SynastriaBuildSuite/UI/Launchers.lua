local _, NS = ...
local SBS = NS.SBS

-- The innkeeper gossip line, and the Perk Manager watch that keeps the window's innkeeper status current.
local Launchers = {}
SBS.Launchers = Launchers

local CHECK_EVERY, GIVE_UP_AFTER = 1, 600
-- how long after the gossip line is clicked the Perk Manager it asks for may still arrive
local PARK_WAIT = 10
local watching = false

-- The Perk Manager the gossip line opens has to stay shown for perk activations, but the window covers it, so it's
-- moved off screen and made invisible until it closes. Closing the window closes it too. A Perk Manager that
-- arrives already invisible (Synastria Companion parks it the same way) is left alone.
local park = { wantedUntil = nil, saved = nil }

local function parkPerkManager(f)
	local wanted = park.wantedUntil and GetTime() <= park.wantedUntil
	park.wantedUntil = nil
	if wanted and not park.saved and f:GetAlpha() > 0 then
		local point, rel, relPoint, x, y = f:GetPoint()
		park.saved = { point = point, rel = rel, relPoint = relPoint, x = x, y = y, alpha = f:GetAlpha() }
		f:SetAlpha(0)
		f:ClearAllPoints()
		f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -200, -200)
	end
end

local function unparkPerkManager(f)
	local saved = park.saved
	if saved then
		park.saved = nil
		f:ClearAllPoints()
		if saved.point then
			f:SetPoint(saved.point, saved.rel or UIParent, saved.relPoint, saved.x, saved.y)
		else
			f:SetPoint("CENTER", 0, 0)
		end
		f:SetAlpha(saved.alpha or 1)
	end
end

function Launchers.PerkManagerParked()
	return park.saved ~= nil
end

function Launchers.WindowClosed()
	local f = PerkMgrFrame
	if f and park.saved and f:IsShown() then f:Hide() end
end

-- The server sends the Perk Manager's Lua after login, so this checks until it exists. The window redraws when it
-- opens or closes, since the server opens it after Synastria Build Suite when both come from the gossip line.
function Launchers.Check()
	local perkMgr = PerkMgrFrame
	if perkMgr and not watching then
		perkMgr:HookScript("OnShow", function(f)
			parkPerkManager(f)
			SBS.Window.Render()
		end)
		perkMgr:HookScript("OnHide", function(f)
			unparkPerkManager(f)
			SBS.Window.Render()
		end)
		watching = true
	end
	return watching
end

-- An "Open Synastria Build Suite" line under an innkeeper's "Manage perks" gossip option: it opens the Perk Manager,
-- so perk changes can apply, and Synastria Build Suite with it. The line is client-side and drawn after Blizzard's buttons.
local MANAGE_PERKS = "manage perks"
local gossip

local function managePerksOption(...)
	for i = 1, select("#", ...), 2 do
		if select(i, ...):lower():find(MANAGE_PERKS, 1, true) then return (i + 1) / 2 end
	end
end

local function createGossip()
	local b = CreateFrame("Button", "SynastriaBuildSuiteGossipButton", GossipGreetingScrollChildFrame, "GossipTitleButtonTemplate")
	b:SetText("Open Synastria Build Suite")
	SynastriaBuildSuiteGossipButtonGossipIcon:SetTexture("Interface\\GossipFrame\\GossipGossipIcon")
	b:SetScript("OnClick", function(self)
		park.wantedUntil = GetTime() + PARK_WAIT
		SelectGossipOption(self.option)
		SBS.Window.Open()
	end)
	return b
end

function Launchers.UpdateGossip()
	local option = managePerksOption(GetGossipOptions())
	local last = _G["GossipTitleButton" .. (GossipFrame.buttonIndex - 1)]
	if option and last then
		-- spacing copied from Blizzard's own buttons: the gap in GossipTitleButton2's anchor and the padding
		-- GossipResize leaves around the text
		local _, _, _, gapX, gapY = GossipTitleButton2:GetPoint()
		local padding = last:GetHeight() - last:GetTextHeight()
		gossip = gossip or createGossip()
		gossip.option = option
		gossip:ClearAllPoints()
		gossip:SetPoint("TOPLEFT", last, "BOTTOMLEFT", gapX or 0, gapY or 0)
		gossip:SetHeight(gossip:GetTextHeight() + padding)
		gossip:Show()
		GossipSpacerFrame:SetPoint("TOP", gossip, "BOTTOM")
		GossipGreetingScrollFrame:UpdateScrollChildRect()
	elseif gossip then
		gossip:Hide()
	end
end

hooksecurefunc("GossipFrameUpdate", Launchers.UpdateGossip)

local watcher = CreateFrame("Frame")
local elapsed, total = 0, 0
watcher:SetScript("OnUpdate", function(self, dt)
	elapsed, total = elapsed + dt, total + dt
	if elapsed >= CHECK_EVERY then
		elapsed = 0
		if Launchers.Check() or total > GIVE_UP_AFTER then self:SetScript("OnUpdate", nil) end
	end
end)
