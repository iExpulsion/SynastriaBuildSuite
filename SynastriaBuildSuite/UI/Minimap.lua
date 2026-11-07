local _, NS = ...
local SBS = NS.SBS

-- Minimap button: left-click opens the window, right-click opens the build linked to the active spec, drag moves
-- it around the minimap and Shift-drag anywhere on screen. Position and visibility are saved in SynastriaBuildSuiteDB.minimap. When a LibDataBroker display
-- is installed, a launcher is registered there too.
local MinimapButton = {}
SBS.MinimapButton = MinimapButton

local ICON = "Interface\\Icons\\INV_Misc_Book_11"
local DEFAULT_ANGLE = 200
local button

-- Which quadrants of each minimap shape are round, in the order GetMinimapShape addons use.
local SHAPES = {
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- Shift-drag frees the button: it moves to UIParent at a saved spot (db.minimap.free), so it stays up even when
-- the minimap is hidden. A plain drag puts it back on the minimap's edge.
local function place()
	local free = SBS.db.minimap.free
	local parent = free and UIParent or Minimap
	if button:GetParent() ~= parent then
		button:SetParent(parent)
		button:SetFrameStrata("MEDIUM")
		button:SetFrameLevel(8)
	end
	button:ClearAllPoints()
	if free then
		button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", free.x, free.y)
	else
		local angle = math.rad(SBS.db.minimap.angle or DEFAULT_ANGLE)
		local x, y = math.cos(angle), math.sin(angle)
		local quadrant = 1 + (x < 0 and 1 or 0) + (y > 0 and 2 or 0)
		local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
		local radius = Minimap:GetWidth() / 2 + 5
		if (SHAPES[shape] or SHAPES.ROUND)[quadrant] then
			x, y = x * radius, y * radius
		else
			local diagonal = math.sqrt(2 * radius * radius) - 10
			x = math.max(-radius, math.min(x * diagonal, radius))
			y = math.max(-radius, math.min(y * diagonal, radius))
		end
		button:SetPoint("CENTER", Minimap, "CENTER", x, y)
	end
end

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

local function fillBrokerTooltip(tt)
	tt:AddLine("Synastria Build Suite", 1, 0.77, 0)
	local name = linkedBuild()
	tt:AddLine(SBS:SpecName(SBS:ActiveGroup()) .. ": " .. (name or "no linked build"), 1, 1, 1)
	tt:AddLine("Left-click to open or close the build window.", 0.8, 0.8, 0.8)
	tt:AddLine("Right-click to open the build linked to this spec.", 0.8, 0.8, 0.8)
end

local function fillTooltip(tt)
	fillBrokerTooltip(tt)
	tt:AddLine("Drag to move it around the minimap, Shift-drag to place it anywhere.", 0.6, 0.6, 0.66)
	tt:AddLine("/sbs minimap hides it; /sbs minimap reset puts it back.", 0.6, 0.6, 0.66)
end

-- Ends on the mouse release itself: a reparent mid-drag can cost the OnDragStop.
local function onDragUpdate(self)
	if IsMouseButtonDown("LeftButton") then
		local px, py = GetCursorPosition()
		if SBS.db.minimap.free then
			local scale = UIParent:GetEffectiveScale()
			SBS.db.minimap.free.x, SBS.db.minimap.free.y = px / scale, py / scale
		else
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			SBS.db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
		end
		place()
	else
		self:SetScript("OnUpdate", nil)
	end
end

local function create()
	button = CreateFrame("Button", "SynastriaBuildSuiteMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetClampedToScreen(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetTexture(ICON)
	button.icon:SetSize(17, 17)
	button.icon:SetPoint("TOPLEFT", 7, -6)
	button.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		fillTooltip(GameTooltip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		SBS.db.minimap.free = IsShiftKeyDown() and (SBS.db.minimap.free or {}) or nil
		self:SetScript("OnUpdate", onDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	place()
end

-- Registered while the addon loads, not at login: displays like ElvUI fill their panels on PLAYER_LOGIN before
-- our handler runs, and a launcher created after that never lands in the panel set to it.
LibStub("LibDataBroker-1.1"):NewDataObject("SynastriaBuildSuite", {
	type = "launcher",
	icon = ICON,
	label = "Synastria Build Suite",
	text = "Build Suite",
	OnClick = onClick,
	OnTooltipShow = fillBrokerTooltip,
})

function MinimapButton.Refresh()
	if SBS.db.minimap.hide then button:Hide() else button:Show() end
end

function MinimapButton.Toggle()
	SBS.db.minimap.hide = not SBS.db.minimap.hide
	MinimapButton.Refresh()
	SBS:Print(SBS.db.minimap.hide and "Minimap button hidden. /sbs minimap shows it again." or "Minimap button shown.")
end

function MinimapButton.ResetPosition()
	SBS.db.minimap.free, SBS.db.minimap.angle = nil, nil
	place()
	SBS:Print("Minimap button moved back to the minimap.")
end

function MinimapButton.Frame()
	return button
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
	SBS.db.minimap = SBS.db.minimap or {}
	create()
	MinimapButton.Refresh()
	self:UnregisterEvent("PLAYER_LOGIN")
end)
