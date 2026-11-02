local _, NS = ...
local BF = NS.BF

-- Scrolling list of pooled flat rows: optional icon, text (with an optional second line), right-aligned status,
-- tooltip, click and item drop. Headers can be collapsible; the selected row gets an accent bar.
local List = {}
BF.List = List

local S = BF.Style

local STYLES = {
	content = { rowH = 22, subRowH = 22, header = "GameFontNormalSmall", row = "GameFontHighlightSmall" },
	sidebar = { rowH = 22, subRowH = 36, header = "GameFontNormalSmall", row = "GameFontHighlight" },
}

local function runTooltip(row)
	row.hoverTex:Show()
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
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	row.hoverTex = S.Solid(row, "BACKGROUND", S.colors.hover)
	row.hoverTex:SetAllPoints()
	row.hoverTex:Hide()
	row.selectedTex = S.Solid(row, "BACKGROUND", S.colors.selected)
	row.selectedTex:SetAllPoints()
	row.bar = S.Solid(row, "BORDER", S.colors.accent)
	row.bar:SetWidth(3)
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")

	row.toggle = S.Text(row, "normal", S.colors.muted)
	row.toggle:SetWidth(12)
	row.toggle:SetJustifyH("CENTER")
	row.toggle:SetPoint("LEFT", 8, 0)
	row.check = S.Check(row, 14, function() if row.onCheck then row.onCheck(row) end end)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)

	row.status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.status:SetPoint("RIGHT", -8, 0)
	row.status:SetJustifyH("RIGHT")
	row.text = row:CreateFontString(nil, "ARTWORK", style.row)
	row.text:SetJustifyH("LEFT")
	row.text:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
	row.sub = S.Text(row, "small", S.colors.muted)
	row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
	row.sub:SetPoint("RIGHT", row.status, "LEFT", -6, 0)

	row:SetScript("OnClick", dropOrClick)
	row:SetScript("OnReceiveDrag", function(r) dropOrClick(r, "LeftButton") end)
	row:SetScript("OnEnter", runTooltip)
	row:SetScript("OnLeave", function(r)
		r.hoverTex:Hide()
		GameTooltip:Hide()
	end)
	return row
end

function List.New(parent, name, width, height, style)
	local self = setmetatable({ rows = {}, count = 0, style = STYLES[style or "content"], width = width, name = name }, { __index = List })
	self.scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
	self.scroll:SetSize(width, height)
	self.content = CreateFrame("Frame", nil, self.scroll)
	self.content:SetSize(width, height)
	self.scroll:SetScrollChild(self.content)
	self.updateBar = List.AutoHideBar(self.scroll, name)
	return self
end

-- A flat bar that only shows when there's something to scroll.
function List.AutoHideBar(scroll, scrollName)
	local bar = S.ScrollBar(scroll, scrollName)
	local function update()
		if (scroll:GetVerticalScrollRange() or 0) > 0 then bar:Show() else bar:Hide() end
	end
	scroll:HookScript("OnScrollRangeChanged", update)
	update()
	return update
end

function List:Begin()
	self.count = 0
	self.height = 0
end

-- entry: text, sub, status, icon, header, collapsed (true/false shows +/-), indent, selected,
-- check (true/false shows a checkbox), checkEnabled, checkTooltip, onCheck(row),
-- tooltip(tt), onClick(row, button), onDrop(itemId)
function List:Add(entry)
	local style = self.style
	self.count = self.count + 1
	local row = self.rows[self.count]
	if not row then
		row = newRow(self)
		self.rows[self.count] = row
	end
	local h = entry.sub and style.subRowH or style.rowH
	if entry.header and self.count > 1 then self.height = self.height + 6 end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.height)
	row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.height)
	row:SetHeight(h)
	self.height = self.height + h

	local x = 10 + (entry.indent or 0)
	if entry.collapsed ~= nil then
		row.toggle:SetText(entry.collapsed and "+" or "-")
		row.toggle:Show()
		x = x + 16
	else
		row.toggle:Hide()
	end
	if entry.check ~= nil then
		row.check:ClearAllPoints()
		row.check:SetPoint("LEFT", x, 0)
		row.check:SetChecked(entry.check)
		row.check:SetEnabled(entry.checkEnabled ~= false)
		row.check.tooltipText = entry.checkTooltip
		row.check:Show()
		x = x + 20
	else
		row.check:Hide()
	end
	row.icon:ClearAllPoints()
	row.text:ClearAllPoints()
	row.text:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
	if entry.icon then
		row.icon:SetTexture(entry.icon)
		row.icon:SetPoint("LEFT", x, 0)
		row.icon:Show()
		x = x + 20
	else
		row.icon:Hide()
	end
	if entry.sub then
		row.text:SetPoint("TOPLEFT", x, -5)
		row.sub:SetText(entry.sub)
		row.sub:Show()
	else
		row.text:SetPoint("LEFT", x, 0)
		row.sub:Hide()
	end

	row.text:SetFontObject(entry.header and style.header or style.row)
	row.text:SetText(entry.text or "")
	if not entry.header then row.text:SetTextColor(unpack(S.colors.text)) end
	row.status:SetText(entry.status or "")
	if entry.selected then
		row.selectedTex:Show()
		row.bar:Show()
	else
		row.selectedTex:Hide()
		row.bar:Hide()
	end

	row.tooltip, row.onClick, row.onDrop, row.onCheck = entry.tooltip, entry.onClick, entry.onDrop, entry.onCheck
	row:Show()
	return row
end

function List:End()
	for i = self.count + 1, #self.rows do self.rows[i]:Hide() end
	self.content:SetHeight(math.max(1, self.height))
	self.scroll:UpdateScrollChildRect()
	self.updateBar()
end

function List:Show() self.scroll:Show() end
function List:Hide() self.scroll:Hide() end
