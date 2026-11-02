local _, NS = ...
local BF = NS.BF

-- Minimap button: left-click opens the window, right-click opens the build linked to the active spec, drag moves
-- it around the minimap. Position and visibility are saved in BuildForgeDB.minimap. When a LibDataBroker display
-- is installed, a launcher is registered there too.
local MinimapButton = {}
BF.MinimapButton = MinimapButton

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

local function place()
	local angle = math.rad(BF.db.minimap.angle or DEFAULT_ANGLE)
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
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function linkedBuild()
	local name = BF:Links()[BF:ActiveGroup()]
	return name and BF.db.builds[name] and name
end

local function onClick(_, mouse)
	if mouse == "RightButton" then
		local name = linkedBuild()
		if name then
			BF.Window.Open(name)
		else
			BF:Print("No build is linked to %s yet. Apply one, or pick it in a build's Linked to menu.", BF:SpecName(BF:ActiveGroup()))
		end
	else
		BF.Window.Toggle()
	end
end

local function fillTooltip(tt)
	tt:AddLine("BuildForge", 1, 0.5, 0.13)
	local name = linkedBuild()
	tt:AddLine(BF:SpecName(BF:ActiveGroup()) .. ": " .. (name or "no linked build"), 1, 1, 1)
	tt:AddLine("Left-click to open or close the build window.", 0.8, 0.8, 0.8)
	tt:AddLine("Right-click to open the build linked to this spec.", 0.8, 0.8, 0.8)
	tt:AddLine("Drag to move. /bforge minimap hides it.", 0.6, 0.6, 0.66)
end

local function onDragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	BF.db.minimap.angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
	place()
end

local function create()
	button = CreateFrame("Button", "BuildForgeMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
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
		self:SetScript("OnUpdate", onDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	place()
end

local function registerBroker()
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if ldb then
		ldb:NewDataObject("BuildForge", {
			type = "launcher",
			icon = ICON,
			label = "BuildForge",
			OnClick = onClick,
			OnTooltipShow = fillTooltip,
		})
	end
end

function MinimapButton.Refresh()
	if BF.db.minimap.hide then button:Hide() else button:Show() end
end

function MinimapButton.Toggle()
	BF.db.minimap.hide = not BF.db.minimap.hide
	MinimapButton.Refresh()
	BF:Print(BF.db.minimap.hide and "Minimap button hidden. /bforge minimap shows it again." or "Minimap button shown.")
end

function MinimapButton.Frame()
	return button
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
	BF.db.minimap = BF.db.minimap or {}
	create()
	registerBroker()
	MinimapButton.Refresh()
	self:UnregisterEvent("PLAYER_LOGIN")
end)
