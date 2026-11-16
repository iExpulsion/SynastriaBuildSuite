local _, NS = ...
local SBS = NS.SBS

-- Minimap button (S.MinimapButton): left-click opens the window, right-click opens the build linked to the active
-- spec. Position and visibility are saved in SynastriaBuildSuiteDB.minimap. When a LibDataBroker display is
-- installed, a launcher is registered there too.
local MinimapButton = {}
SBS.MinimapButton = MinimapButton

local ICON = "Interface\\Icons\\INV_Misc_Book_11"
local button

local function linkedBuild()
	local name = SBS:Links()[SBS:ActiveGroup()]
	return name and SBS.db.builds[name] and name
end

local function onClick(_, mouse)
	if mouse == "RightButton" then
		local name = linkedBuild()
		if name then
			SBS.Window.Open(name)
		else
			SBS:Print("No build is linked to %s yet. Apply one, or pick it in a build's Linked to menu.", SBS:SpecName(SBS:ActiveGroup()))
		end
	else
		SBS.Window.Toggle()
	end
end

local function fillTooltip(tt)
	tt:AddLine("Synastria Build Suite", 1, 0.77, 0)
	local name = linkedBuild()
	tt:AddLine(SBS:SpecName(SBS:ActiveGroup()) .. ": " .. (name or "no linked build"), 1, 1, 1)
	tt:AddLine("Left-click to open or close the build window.", 0.8, 0.8, 0.8)
	tt:AddLine("Right-click to open the build linked to this spec.", 0.8, 0.8, 0.8)
end

-- Registered while the addon loads, not at login: displays like ElvUI fill their panels on PLAYER_LOGIN before
-- our handler runs, and a launcher created after that never lands in the panel set to it.
LibStub("LibDataBroker-1.1"):NewDataObject("SynastriaBuildSuite", {
	type = "launcher",
	icon = ICON,
	label = "Synastria Build Suite",
	text = "Build Suite",
	OnClick = onClick,
	OnTooltipShow = fillTooltip,
})

function MinimapButton.Refresh()
	button:Refresh()
end

function MinimapButton.Toggle()
	SBS.db.minimap.hide = not SBS.db.minimap.hide
	button:Refresh()
	SBS:Print(SBS.db.minimap.hide and "Minimap button hidden. /sbs minimap shows it again." or "Minimap button shown.")
end

function MinimapButton.ResetPosition()
	button:ResetPosition()
	SBS:Print("Minimap button moved back to the minimap.")
end

function MinimapButton.Frame()
	return button
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
	SBS.db.minimap = SBS.db.minimap or {}
	button = SBS.Style.MinimapButton({
		name = "SynastriaBuildSuiteMinimapButton", icon = ICON, db = SBS.db.minimap, angle = 200,
		onClick = onClick, tooltip = fillTooltip, hint = "/sbs minimap hides it; /sbs minimap reset puts it back.",
	})
	self:UnregisterEvent("PLAYER_LOGIN")
end)
