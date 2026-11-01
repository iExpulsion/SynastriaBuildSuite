local _, NS = ...
local BF = NS.BF

-- Scrolling list of pooled rows: icon, text, right-aligned status, optional tooltip, click and item drop.
-- "category" rows copy the Achievement window's category buttons (AchievementCategoryTemplate and
-- AchievementFrameCategories_DisplayButton): headers full width, children narrower, dimmed and right-aligned.
local List = {}
BF.List = List

local STYLES = {
	dark = { rowH = 20, header = "GameFontNormal", row = "GameFontHighlightSmall", rightPad = 6 },
	category = { rowH = 24, header = "GameFontNormal", row = "GameFontHighlight", rightPad = 10, category = true },
}
local CATEGORY_BG = "Interface\\AchievementFrame\\UI-Achievement-Category-Background"
local CATEGORY_HIGHLIGHT = "Interface\\AchievementFrame\\UI-Achievement-Category-Highlight"
local HEADER_INSET, CHILD_INSET = 10, 25

local function runTooltip(row)
	if row.tooltip then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		row.tooltip(GameTooltip)
		GameTooltip:Show()
	end
end

local function dropOrClick(row, button)
	local cursor = GetCursorInfo()
	if cursor == "item" and row.onDrop then
		local _, id = GetCursorInfo()
		ClearCursor()
		row.onDrop(id)
	elseif row.onClick then
		row.onClick(row, button)
	end
end

local function newRow(self)
	local style = self.style
	local row = CreateFrame("Button", nil, self.content)
	row:SetHeight(style.rowH)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	if style.category then
		row.background = row:CreateTexture(nil, "BACKGROUND")
		row.background:SetTexture(CATEGORY_BG)
		row.background:SetTexCoord(0, 0.6640625, 0, 1)
		row.background:SetPoint("TOPLEFT")
		row.background:SetPoint("TOPRIGHT")
		row.background:SetHeight(32)
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetTexture(CATEGORY_HIGHLIGHT)
		highlight:SetTexCoord(0, 0.6640625, 0, 1)
		highlight:SetBlendMode("ADD")
		highlight:SetPoint("TOPLEFT")
		highlight:SetPoint("BOTTOMRIGHT", -1, -7)
		row:SetHighlightTexture(highlight)
	else
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.selectedTex = row:CreateTexture(nil, "BACKGROUND")
		row.selectedTex:SetAllPoints()
		row.selectedTex:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		row.selectedTex:SetBlendMode("ADD")
	end

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)

	row.status = row:CreateFontString(nil, "ARTWORK", style.row)
	row.status:SetPoint("RIGHT", -style.rightPad, style.category and 2 or 0)
	row.status:SetJustifyH("RIGHT")

	row.text = row:CreateFontString(nil, "ARTWORK", style.row)
	row.text:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
	row.text:SetJustifyH("LEFT")

	row:SetScript("OnClick", dropOrClick)
	row:SetScript("OnReceiveDrag", function(r) dropOrClick(r, "LeftButton") end)
	row:SetScript("OnEnter", runTooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

function List.New(parent, name, width, height, style)
	local self = setmetatable({ rows = {}, count = 0, style = STYLES[style or "dark"], width = width, name = name }, { __index = List })
	self.scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
	self.scroll:SetSize(width, height)
	self.content = CreateFrame("Frame", nil, self.scroll)
	self.content:SetSize(width, height)
	self.scroll:SetScrollChild(self.content)
	return self
end

-- Moves the scroll bar, e.g. to span a taller pane than the list itself.
function List:DockScrollBar(relativeTo, top, bottom)
	local bar = _G[self.name .. "ScrollBar"]
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", relativeTo, "TOPRIGHT", top[1], top[2])
	bar:SetPoint("BOTTOMLEFT", relativeTo, "BOTTOMRIGHT", bottom[1], bottom[2])
end

function List:Begin()
	self.count = 0
end

-- entry: text, status, icon, header, indent, selected, tooltip(tt), onClick(row, button), onDrop(itemId)
function List:Add(entry)
	local style = self.style
	self.count = self.count + 1
	local row = self.rows[self.count]
	if not row then
		row = newRow(self)
		self.rows[self.count] = row
	end
	row:ClearAllPoints()
	local top = -(self.count - 1) * style.rowH
	local indent = entry.indent or 0

	if style.category then
		row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, top)
		row:SetWidth(self.width - (entry.header and HEADER_INSET or CHILD_INSET))
		local shade = entry.header and 1 or 0.6
		row.background:SetVertexColor(shade, shade, shade)
		if entry.selected then row:LockHighlight() else row:UnlockHighlight() end
	else
		row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, top)
		row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, top)
		if entry.selected then row.selectedTex:Show() else row.selectedTex:Hide() end
	end

	local textX = style.category and 16 or 4
	row.icon:SetPoint("LEFT", textX + indent, 0)
	if entry.icon then
		row.icon:SetTexture(entry.icon)
		row.icon:Show()
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	else
		row.icon:Hide()
		row.text:SetPoint("LEFT", textX + indent, style.category and 2 or 0)
	end
	row.text:SetFontObject(entry.header and style.header or style.row)
	row.text:SetText(entry.text or "")
	row.status:SetText(entry.status or "")

	row.tooltip, row.onClick, row.onDrop = entry.tooltip, entry.onClick, entry.onDrop
	row:Show()
	return row
end

function List:End()
	for i = self.count + 1, #self.rows do self.rows[i]:Hide() end
	self.content:SetHeight(math.max(1, self.count * self.style.rowH))
	self.scroll:UpdateScrollChildRect()
end

function List:Show() self.scroll:Show() end
function List:Hide() self.scroll:Hide() end
