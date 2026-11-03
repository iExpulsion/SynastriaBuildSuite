local _, NS = ...
local BF = NS.BF

-- The innkeeper gossip line, and the Perk Manager watch that keeps the window's innkeeper status current.
local Launchers = {}
BF.Launchers = Launchers

local CHECK_EVERY, GIVE_UP_AFTER = 1, 600
local watching = false

-- The server sends the Perk Manager's Lua after login, so this checks until it exists. The window redraws when it
-- opens or closes, since the server opens it after BuildForge when both come from the gossip line.
function Launchers.Check()
	local perkMgr = PerkMgrFrame
	if perkMgr and not watching then
		perkMgr:HookScript("OnShow", function() BF.Window.Render() end)
		perkMgr:HookScript("OnHide", function() BF.Window.Render() end)
		watching = true
	end
	return watching
end

-- An "Open BuildForge" line under an innkeeper's "Manage perks" gossip option: it opens the Perk Manager, so
-- perk changes can apply, and BuildForge with it. The line is client-side and drawn after Blizzard's buttons.
local MANAGE_PERKS = "manage perks"
local gossip

local function managePerksOption(...)
	for i = 1, select("#", ...), 2 do
		if select(i, ...):lower():find(MANAGE_PERKS, 1, true) then return (i + 1) / 2 end
	end
end

local function createGossip()
	local b = CreateFrame("Button", "BuildForgeGossipButton", GossipGreetingScrollChildFrame, "GossipTitleButtonTemplate")
	b:SetText("Open BuildForge")
	BuildForgeGossipButtonGossipIcon:SetTexture("Interface\\GossipFrame\\GossipGossipIcon")
	b:SetScript("OnClick", function(self)
		SelectGossipOption(self.option)
		BF.Window.Open()
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
