local _, NS = ...
local SBS = NS.SBS

-- Scrolling list of pooled flat rows: optional icon, text (with an optional second line), right-aligned status,
-- tooltip, click and item drop. Headers can be collapsible; the selected row gets an accent bar.
local List = {}
SBS.List = List

local S = SBS.Style

local STYLES = {
	content = { rowH = 22, subRowH = 36, header = "small", row = "small" },
	sidebar = { rowH = 22, subRowH = 36, header = "small", row = "normal" },
}

-- A hovered row shows its highlight and, when it can be removed, its remove button in place of its status.
local function setHover(row, on)
	local removable = on and row.onRemove ~= nil
	if on then row.hoverTex:Show() else row.hoverTex:Hide() end
	if removable then row.remove:Show() row.status:Hide() else row.remove:Hide() row.status:Show() end
end

local function runTooltip(row)
	setHover(row, true)
	if row.tooltip then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		row.tooltip(GameTooltip)
		GameTooltip:Show()
	end
end

-- Moving onto the remove button leaves the row; the row stays hovered while the mouse is over either.
local function leave(row)
	if not MouseIsOver(row) then setHover(row, false) end
	GameTooltip:Hide()
end

local function dropOrClick(row, button)
	local cursor = GetCursorInfo()
	if cursor == "item" and row.onDrop then
		local _, id = GetCursorInfo()
		ClearCursor()
		row.onDrop(id)
	elseif row.onClick and not (row.list.reorder and row.list.reorder:Busy()) then
		row.onClick(row, button)
	end
end

local function dragLabel(row) return row.dragLabel end

local function newRow(self, parent)
	local style = self.style
	local row = CreateFrame("Button", nil, parent or self.content)
	row.list = self
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	if self.reorder and not parent then self.reorder:Attach(row, dragLabel) end

	row.hoverTex = S.Solid(row, "BACKGROUND", S.colors.rowHover)
	row.hoverTex:SetAllPoints()
	row.hoverTex:Hide()
	row.selectedTex = S.Solid(row, "BACKGROUND", S.colors.rowSelected)
	row.selectedTex:SetAllPoints()
	row.bar = S.Solid(row, "BORDER", S.colors.accent)
	row.bar:SetWidth(3)
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")

	row.toggle = S.Text(row, "normal", S.colors.muted)
	row.toggle:SetWidth(12)
	row.toggle:SetJustifyH("CENTER")
	row.check = S.Check(row, nil, function() if row.onCheck then row.onCheck(row) end end)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)

	row.status = S.FontString(row, "small")
	row.status:SetPoint("RIGHT", -S.PAD, 0)
	row.status:SetJustifyH("RIGHT")
	row.text = S.FontString(row, style.row)
	row.text:SetJustifyH("LEFT")
	row.text:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
	row.sub = S.Text(row, "small", S.colors.muted)
	row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
	row.sub:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
	-- a colored header's rule
	row.rule = S.Solid(row, "ARTWORK", S.colors.heading)
	row.rule:SetHeight(1)
	row.rule:SetPoint("BOTTOMLEFT", S.PAD, 0)
	row.rule:SetPoint("BOTTOMRIGHT", -S.PAD, 0)
	row.rule:Hide()

	-- shown on hover for rows added with onRemove, over the status
	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(S.CONTROL_H, S.CONTROL_H)
	row.remove:SetPoint("RIGHT", -S.PAD + 6, 0)
	row.remove.label = S.Text(row.remove, "normal", S.colors.muted)
	row.remove.label:SetPoint("CENTER")
	row.remove.label:SetText("X")
	row.remove:Hide()
	row.remove:SetScript("OnClick", function() if row.onRemove then row.onRemove(row) end end)
	row.remove:SetScript("OnEnter", function(self)
		self.label:SetTextColor(unpack(S.colors.bad))
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(row.removeTip or "Remove", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	row.remove:SetScript("OnLeave", function(self)
		self.label:SetTextColor(unpack(S.colors.muted))
		leave(row)
	end)

	row:SetScript("OnClick", dropOrClick)
	row:SetScript("OnReceiveDrag", function(r) dropOrClick(r, "LeftButton") end)
	row:SetScript("OnEnter", runTooltip)
	row:SetScript("OnLeave", leave)
	return row
end

-- `width` leaves room on the right for the scroll bar; `gutter` is that room, which the rows take over while
-- there's nothing to scroll and the bar is hidden.
function List.New(parent, name, width, height, style, gutter)
	local self = setmetatable({ rows = {}, headers = {}, count = 0, style = STYLES[style or "content"], width = width,
		name = name }, { __index = List })
	self.scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
	self.scroll:SetSize(width, height)
	self.content = CreateFrame("Frame", nil, self.scroll)
	self.content:SetSize(width, height)
	self.scroll:SetScrollChild(self.content)
	self.updateBar = List.AutoHideBar(self.scroll, name, function(shown)
		local w = shown and width or width + (gutter or 0)
		self.scroll:SetWidth(w)
		self.content:SetWidth(w)
	end)
	return self
end

-- The overlay row's copy of the header the list has scrolled past: shown while any of that header is above the
-- top, hidden at the top or above the first header.
local function updateSticky(self)
	local stuck = self.stuck
	local offset = self.scroll:GetVerticalScroll() or 0
	local source
	for i = 1, self.headerCount do
		local row = self.headers[i]
		if row.y < offset then source = row end
	end
	stuck.source = source
	if source then
		S.SetFont(stuck.text, self.style.header)
		stuck.text:SetText(source.text:GetText() or "")
		stuck.text:SetTextColor(source.text:GetTextColor())
		stuck.status:SetText(source.status:GetText() or "")
		if source.rule:IsShown() then
			stuck.rule:SetVertexColor(source.rule:GetVertexColor())
			stuck.rule:Show()
		else
			stuck.rule:Hide()
		end
		stuck:Show()
	else
		stuck:Hide()
	end
end

-- Keeps the header of the section scrolled into on an overlay at the top, with a rule under it, until the next
-- header reaches the top. Clicks and the tooltip go to the header itself.
function List:SetSticky()
	local stuck = newRow(self, self.scroll)
	stuck:SetFrameLevel(self.content:GetFrameLevel() + 3)
	stuck:SetPoint("TOPLEFT", self.scroll, "TOPLEFT")
	stuck:SetPoint("TOPRIGHT", self.scroll, "TOPRIGHT")
	stuck:SetHeight(self.style.rowH)
	stuck.bg = S.Solid(stuck, "BACKGROUND", S.colors.panel)
	stuck.bg:SetDrawLayer("BACKGROUND", -1)
	stuck.bg:SetAllPoints()
	local divider, thickness = S.Divider(stuck, "header")
	divider:SetHeight(thickness)
	divider:SetPoint("BOTTOMLEFT")
	divider:SetPoint("BOTTOMRIGHT")
	stuck.text:ClearAllPoints()
	stuck.text:SetPoint("LEFT", S.PAD, 0)
	stuck.text:SetPoint("RIGHT", stuck.status, "LEFT", -6, 0)
	stuck.selectedTex:Hide()
	stuck.bar:Hide()
	stuck.toggle:Hide()
	stuck.check:Hide()
	stuck.icon:Hide()
	stuck.sub:Hide()
	stuck:SetScript("OnClick", function(r, button)
		if r.source and r.source.onClick then r.source.onClick(r.source, button) end
	end)
	stuck.tooltip = function(tt) if stuck.source and stuck.source.tooltip then stuck.source.tooltip(tt) end end
	stuck:Hide()
	self.stuck = stuck
	self.headerCount = 0
	self.scroll:HookScript("OnVerticalScroll", function() updateSticky(self) end)
end

-- Rows added with a move index can be dragged into a new order; onMove(from, to) gets the drop.
function List:SetReorder(onMove)
	local scroll = self.scroll
	self.reorder = S.Reorder.New({ rows = self.rows, lineParent = self.content, area = scroll, onMove = onMove,
		scroll = function(step)
			local y = scroll:GetVerticalScroll() + step * self.style.rowH
			scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange() or 0, y)))
		end })
	for _, row in ipairs(self.rows) do self.reorder:Attach(row, dragLabel) end
end

-- A flat bar that only shows when there's something to scroll; onToggle(shown), if given, runs with each update.
function List.AutoHideBar(scroll, scrollName, onToggle)
	local bar = S.ScrollBar(scroll, scrollName)
	local function update()
		local shown = (scroll:GetVerticalScrollRange() or 0) > 0
		if shown then bar:Show() else bar:Hide() end
		if onToggle then onToggle(shown) end
	end
	scroll:HookScript("OnScrollRangeChanged", update)
	update()
	return update
end

function List:Begin()
	self.count = 0
	self.height = 0
	self.headerCount = 0
end

-- entry: text, sub, status, icon, header, color (a header's text and rule color), collapsed (true/false shows +/-),
-- indent, selected,
-- check (true/false shows a checkbox), checkEnabled, checkTooltip, onCheck(row),
-- tooltip(tt), onClick(row, button), onDrop(itemId), move (the index it drags from, with SetReorder),
-- dragLabel (the text by the cursor while it's dragged), and onRemove(row) with removeTip (an X shown over the
-- status while the row is hovered)
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
	row.y = self.height
	self.height = self.height + h
	if entry.header then
		self.headerCount = self.headerCount + 1
		self.headers[self.headerCount] = row
	end

	local x = S.PAD + (entry.indent or 0)
	if entry.collapsed ~= nil then
		row.toggle:SetText(entry.collapsed and "+" or "-")
		row.toggle:ClearAllPoints()
		row.toggle:SetPoint("LEFT", x - 2, 0)
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
		-- two lines (about 24px of text) centered in the taller row
		row.text:SetPoint("TOPLEFT", x, -(style.subRowH - 24) / 2)
		row.sub:SetText(entry.sub)
		row.sub:Show()
	else
		row.text:SetPoint("LEFT", x, 0)
		row.sub:Hide()
	end

	S.SetFont(row.text, entry.header and style.header or style.row)
	row.text:SetText(entry.text or "")
	-- rows are reused, so both kinds set their color; a header left to its font would keep a build row's white
	row.text:SetTextColor(unpack(entry.header and (entry.color or S.colors.heading) or S.colors.text))
	if entry.header and entry.color then
		row.rule:SetVertexColor(unpack(entry.color))
		row.rule:Show()
	else
		row.rule:Hide()
	end
	row.status:SetText(entry.status or "")
	if entry.selected then
		row.selectedTex:Show()
		row.bar:Show()
	else
		row.selectedTex:Hide()
		row.bar:Hide()
	end

	row.tooltip, row.onClick, row.onDrop, row.onCheck = entry.tooltip, entry.onClick, entry.onDrop, entry.onCheck
	row.onRemove, row.removeTip = entry.onRemove, entry.removeTip
	-- rows are reused, so a redraw under the mouse keeps the hover the new entry should have
	setHover(row, row:IsShown() and MouseIsOver(row) or false)
	row.moveIndex, row.dragLabel = entry.move, entry.dragLabel
	row:Show()
	return row
end

function List:End()
	for i = self.count + 1, #self.rows do self.rows[i]:Hide() end
	self.content:SetHeight(math.max(1, self.height))
	self.scroll:UpdateScrollChildRect()
	self.updateBar()
	if self.stuck then updateSticky(self) end
end

function List:Show() self.scroll:Show() end
function List:Hide() self.scroll:Hide() end
