local _, NS = ...
local BF = NS.BF

-- Scrolling list of pooled rows: icon, text, right-aligned status, optional tooltip, click and item drop.
-- The "parchment" style uses the dark quest fonts for the Quest Log's detail pane.
local List = {}
BF.List = List
List.ROW_H = 20

local FONTS = {
	dark = { header = "GameFontNormal", row = "GameFontHighlightSmall" },
	parchment = { header = "QuestFont", row = "QuestFontNormalSmall" },
}
local MINUS, PLUS = "Interface\\Buttons\\UI-MinusButton-UP", "Interface\\Buttons\\UI-PlusButton-UP"

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
	local row = CreateFrame("Button", nil, self.content)
	row:SetHeight(List.ROW_H)
	row:SetPoint("LEFT", self.content, "LEFT")
	row:SetPoint("RIGHT", self.content, "RIGHT")
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.selectedTex = row:CreateTexture(nil, "BACKGROUND")
	row.selectedTex:SetAllPoints()
	row.selectedTex:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	row.selectedTex:SetBlendMode("ADD")

	row.toggle = row:CreateTexture(nil, "ARTWORK")
	row.toggle:SetSize(16, 16)
	row.toggle:SetPoint("LEFT", 3, 0)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)

	row.status = row:CreateFontString(nil, "ARTWORK", self.fonts.row)
	row.status:SetPoint("RIGHT", -4, 0)
	row.status:SetJustifyH("RIGHT")

	row.text = row:CreateFontString(nil, "ARTWORK", self.fonts.row)
	row.text:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
	row.text:SetJustifyH("LEFT")

	row:SetScript("OnClick", dropOrClick)
	row:SetScript("OnReceiveDrag", function(r) dropOrClick(r, "LeftButton") end)
	row:SetScript("OnEnter", runTooltip)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

function List.New(parent, name, width, height, style)
	local self = setmetatable({ rows = {}, count = 0, fonts = FONTS[style or "dark"] }, { __index = List })
	self.scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
	self.scroll:SetSize(width, height)
	self.content = CreateFrame("Frame", nil, self.scroll)
	self.content:SetSize(width, height)
	self.scroll:SetScrollChild(self.content)
	return self
end

function List:Begin()
	self.count = 0
end

-- entry: text, status, icon, header, collapsed (true/false shows a +/- toggle), indent, selected,
-- tooltip(tt), onClick(row, button), onDrop(itemId)
function List:Add(entry)
	self.count = self.count + 1
	local row = self.rows[self.count]
	if not row then
		row = newRow(self)
		self.rows[self.count] = row
	end
	row:SetPoint("TOP", self.content, "TOP", 0, -(self.count - 1) * List.ROW_H)

	local indent = entry.indent or 0
	if entry.collapsed ~= nil then
		row.toggle:SetTexture(entry.collapsed and PLUS or MINUS)
		row.toggle:Show()
		indent = indent + 18
	else
		row.toggle:Hide()
	end
	row.icon:SetPoint("LEFT", 4 + indent, 0)
	if entry.icon then
		row.icon:SetTexture(entry.icon)
		row.icon:Show()
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	else
		row.icon:Hide()
		row.text:SetPoint("LEFT", 4 + indent, 0)
	end
	row.text:SetFontObject(entry.header and self.fonts.header or self.fonts.row)
	row.text:SetText(entry.text or "")
	row.status:SetText(entry.status or "")
	if entry.selected then row.selectedTex:Show() else row.selectedTex:Hide() end

	row.tooltip, row.onClick, row.onDrop = entry.tooltip, entry.onClick, entry.onDrop
	row:Show()
	return row
end

function List:End()
	for i = self.count + 1, #self.rows do self.rows[i]:Hide() end
	self.content:SetHeight(math.max(1, self.count * List.ROW_H))
	self.scroll:UpdateScrollChildRect()
end

function List:Show() self.scroll:Show() end
function List:Hide() self.scroll:Hide() end
