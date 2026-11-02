local _, NS = ...
local BF = NS.BF

-- The Talents tab: a calculator for any class's three trees, editing the build directly. Left-click adds a
-- point, right-click removes one, using the rules in TalentCalc.lua.
local Editor = {}
BF.TalentEditor = Editor

local S = BF.Style
local C = S.colors
local Calc

local TIERS, COLUMNS = 11, 4
local HEADER_H, CLASSBAR_H, GAP = 26, 26, 8
local BORDER = {
	locked = { 0.25, 0.25, 0.28, 1 },
	open = { 0.35, 0.8, 0.35, 1 },
	partial = { 0.35, 0.8, 0.35, 1 },
	maxed = C.accent,
}

local panel, current
local state = { class = nil }
Editor.state = state

local function spellIcon(id)
	return select(3, GetSpellInfo(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function buildClasses(build)
	local classes, seen = {}, {}
	for _, key in ipairs(build.classes and #build.classes > 0 and build.classes or BF:PlayerClasses()) do
		if Calc.Trees(key) and not seen[key] then classes[#classes + 1] = key; seen[key] = true end
	end
	for key in pairs(build.talents or {}) do
		if Calc.Trees(key) and not seen[key] then classes[#classes + 1] = key; seen[key] = true end
	end
	return classes
end

-- Live rank on the character, when this class is the one shown in the talent window.
local function liveRank(class, tab, i)
	local rank
	if class == BF.Talents.SelectedClass() and tab <= GetNumTalentTabs(false, false) then
		rank = select(5, GetTalentInfo(tab, i, false, false, BF:ActiveGroup()))
	end
	return rank
end

local function showTooltip(button)
	local class, tab, i = state.class, button.tab, button.index
	local trees = current.talents[class]
	local t = Calc.Trees(class)[tab].talents[i]
	local rank, max = trees[tab][i], #t[3]
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("spell:" .. t[3][math.max(rank, 1)])
	GameTooltip:AddLine(("Rank %d/%d"):format(rank, max), 1, 1, 1)
	if rank > 0 and rank < max then
		GameTooltip:AddLine("Next rank: " .. (GetSpellInfo(t[3][rank + 1]) or "") .. " (rank " .. (rank + 1) .. ")", 0.6, 0.8, 1)
	end
	local canAdd, addReason = Calc.CanAdd(class, trees, tab, i, Calc.MaxPoints(current, class))
	if not canAdd and addReason and rank < max then GameTooltip:AddLine(addReason, 1, 0.4, 0.4, true) end
	local live = liveRank(class, tab, i)
	if live then GameTooltip:AddLine(("Your character: %d/%d"):format(live, max), live == rank and 0.4 or 1, live == rank and 0.85 or 0.8, live == rank and 0.4 or 0.3) end
	GameTooltip:AddLine("Left-click to add a point, right-click to remove one.", 0.6, 0.6, 0.66, true)
	GameTooltip:Show()
end

local function onClick(button, mouse)
	local trees = current.talents[state.class]
	local cap = Calc.MaxPoints(current, state.class)
	local changed, reason
	if mouse == "RightButton" then
		changed = Calc.Remove(state.class, trees, button.tab, button.index)
		if not changed then reason = select(2, Calc.CanRemove(state.class, trees, button.tab, button.index)) end
	else
		changed = Calc.Add(state.class, trees, button.tab, button.index, cap)
		if not changed then reason = select(2, Calc.CanAdd(state.class, trees, button.tab, button.index, cap)) end
	end
	if changed then
		PlaySound("igMainMenuOptionCheckBoxOn")
		BF:Changed()
	elseif reason then
		UIErrorsFrame:AddMessage(reason, 1, 0.3, 0.3)
	end
	if GameTooltip:IsOwned(button) then showTooltip(button) end
end

local function newButton(column, size)
	local b = CreateFrame("Button", nil, column)
	b:SetSize(size, size)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	S.Panel(b, { 0, 0, 0, 1 }, BORDER.locked)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.rankBg = S.Solid(b, "OVERLAY", { 0, 0, 0, 0.85 })
	b.rankBg:SetSize(26, 12)
	b.rankBg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 6, -5)
	b.rank = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.rank:SetPoint("CENTER", b.rankBg, "CENTER", 0, 0)
	local hover = S.Solid(b, "HIGHLIGHT", { 1, 1, 1, 0.15 })
	hover:SetAllPoints(b.icon)
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", showTooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function line(column, layer)
	local t = S.Solid(column, layer or "BORDER", BORDER.locked)
	return t
end

-- Draws a prerequisite between two button centers: down within a column, across within a tier, or across from
-- the source's side and then down into the target.
local function placeArrow(arrow, column, from, to, half)
	local fx, fy, tx, ty = from.x, from.y, to.x, to.y
	arrow.v:ClearAllPoints()
	arrow.h:ClearAllPoints()
	arrow.v:Hide()
	arrow.h:Hide()
	if fx == tx then
		arrow.v:SetPoint("TOPLEFT", column, "TOPLEFT", fx - 1, -(fy + half))
		arrow.v:SetSize(3, math.max(1, ty - fy - 2 * half))
		arrow.v:Show()
	elseif fy == ty then
		local left = math.min(fx, tx) + half
		arrow.h:SetPoint("TOPLEFT", column, "TOPLEFT", left, -(fy - 1))
		arrow.h:SetSize(math.max(1, math.abs(tx - fx) - 2 * half), 3)
		arrow.h:Show()
	else
		local startX = fx < tx and fx + half or fx - half
		arrow.h:SetPoint("TOPLEFT", column, "TOPLEFT", math.min(startX, tx - 1), -(fy - 1))
		arrow.h:SetSize(math.max(1, math.abs(tx - startX) + 2), 3)
		arrow.h:Show()
		arrow.v:SetPoint("TOPLEFT", column, "TOPLEFT", tx - 1, -fy)
		arrow.v:SetSize(3, math.max(1, ty - fy - half))
		arrow.v:Show()
	end
end

local function layoutTree(col, class, tab)
	local tree = Calc.Trees(class)[tab]
	local cellW = col.gridW / COLUMNS
	local cellH = col.gridH / TIERS
	local size = math.floor(math.min(cellW, cellH) - 8)
	col.bg:SetTexture("Interface\\TalentFrame\\" .. tree.background .. "-TopLeft")
	col.icon:SetTexture(tree.icon)
	for i, t in ipairs(tree.talents) do
		local b = col.buttons[i] or newButton(col, size)
		col.buttons[i] = b
		b:SetSize(size, size)
		b.tab, b.index = tab, i
		b.x = (t[2] - 0.5) * cellW
		b.y = HEADER_H + (t[1] - 0.5) * cellH
		b:ClearAllPoints()
		b:SetPoint("CENTER", col, "TOPLEFT", b.x, -b.y)
		b.icon:SetTexture(spellIcon(t[3][1]))
		b:Show()
	end
	for i = #tree.talents + 1, #col.buttons do col.buttons[i]:Hide() end

	for _, a in ipairs(col.arrows) do a.v:Hide(); a.h:Hide(); a.target = nil end
	local n = 0
	for i, t in ipairs(tree.talents) do
		if t[4] then
			n = n + 1
			local a = col.arrows[n] or { v = line(col), h = line(col) }
			col.arrows[n] = a
			a.target, a.source, a.need = i, t[4], t[5]
			placeArrow(a, col, col.buttons[t[4]], col.buttons[i], size / 2)
		end
	end
	col.layoutKey = class .. tab
end

local function paintTree(col, class, tab, trees, cap)
	local tree = Calc.Trees(class)[tab]
	local ranks = trees[tab]
	for i, t in ipairs(tree.talents) do
		local b = col.buttons[i]
		local rank, max = ranks[i], #t[3]
		local look
		if rank >= max then look = "maxed"
		elseif rank > 0 then look = "partial"
		elseif Calc.CanAdd(class, trees, tab, i, cap) then look = "open"
		else look = "locked" end
		b.look = look
		b:SetBackdropBorderColor(unpack(BORDER[look]))
		b.icon:SetDesaturated(look == "locked")
		b.icon:SetAlpha(look == "locked" and 0.55 or 1)
		local show = rank > 0 or look ~= "locked"
		b.rank:SetText(("%d/%d"):format(rank, max))
		b.rank:SetTextColor(unpack(look == "maxed" and C.accentHover or look == "locked" and C.muted or C.good))
		if show then b.rankBg:Show() b.rank:Show() else b.rankBg:Hide() b.rank:Hide() end
	end
	for _, a in ipairs(col.arrows) do
		if a.target then
			local met = (ranks[a.source] or 0) >= a.need
			local c = met and C.accent or BORDER.locked
			a.v:SetVertexColor(unpack(c))
			a.h:SetVertexColor(unpack(c))
		end
	end
	local points = Calc.TreePoints(ranks)
	col.title:SetText(tree.name)
	col.points:SetText(points)
	col.points:SetTextColor(unpack(points > 0 and C.text or C.muted))
end

local function renderClassBar(classes)
	for i, b in ipairs(panel.classButtons) do
		local key = classes[i]
		if key and #classes > 1 then
			b.key = key
			b:SetLabel(BF.Window.ClassText({ key }, true))
			b:SetKind(key == state.class and "primary" or "secondary")
			b:Show()
		else
			b:Hide()
		end
	end
end

function Editor.Render(build)
	current = build
	Calc = Calc or BF.TalentCalc
	local classes = buildClasses(build)
	local summary
	if #classes == 0 then
		for _, col in ipairs(panel.columns) do col:Hide() end
		renderClassBar({})
		summary = S.Hex(C.muted, "No talent data for this build's classes.")
	else
		local found = false
		for _, k in ipairs(classes) do if k == state.class then found = true end end
		if not found then state.class = classes[1] end
		renderClassBar(classes)
		local trees = Calc.Ensure(build, state.class)
		local cap = Calc.MaxPoints(build, state.class)
		local parts = {}
		for tab, col in ipairs(panel.columns) do
			if Calc.Trees(state.class)[tab] then
				if col.layoutKey ~= state.class .. tab then layoutTree(col, state.class, tab) end
				paintTree(col, state.class, tab, trees, cap)
				col:Show()
				parts[#parts + 1] = Calc.TreePoints(trees[tab])
			else
				col:Hide()
			end
		end
		local total = Calc.TotalPoints(trees)
		summary = ("%s  %s   %s"):format(BF.Window.ClassText({ state.class }), table.concat(parts, " / "),
			S.Hex(total == cap and C.good or C.muted, ("%d of %d points"):format(total, cap)))
	end
	return summary
end

function Editor.Create(parent, width, height)
	Calc = BF.TalentCalc
	panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(width, height)

	panel.classButtons = {}
	for i = 1, 3 do
		local b = S.Button(panel, "", "secondary", 90, function(self)
			state.class = self.key
			BF:Changed()
		end)
		b:SetHeight(20)
		if i == 1 then b:SetPoint("TOPLEFT", 0, 0) else b:SetPoint("LEFT", panel.classButtons[i - 1], "RIGHT", 4, 0) end
		panel.classButtons[i] = b
	end

	local top = CLASSBAR_H
	local colW = math.floor((width - 2 * GAP) / 3)
	panel.columns = {}
	for tab = 1, 3 do
		local col = CreateFrame("Frame", nil, panel)
		col:SetSize(colW, height - top)
		col:SetPoint("TOPLEFT", (tab - 1) * (colW + GAP), -top)
		S.Panel(col, { 0.04, 0.04, 0.05, 1 }, C.border)
		col.bg = col:CreateTexture(nil, "BACKGROUND")
		col.bg:SetPoint("TOPLEFT", 1, -HEADER_H)
		col.bg:SetPoint("BOTTOMRIGHT", -1, 1)
		col.bg:SetAlpha(0.35)
		local head = S.Solid(col, "BORDER", C.panel)
		head:SetPoint("TOPLEFT", 1, -1)
		head:SetPoint("TOPRIGHT", -1, -1)
		head:SetHeight(HEADER_H - 1)
		col.icon = col:CreateTexture(nil, "ARTWORK")
		col.icon:SetSize(18, 18)
		col.icon:SetPoint("TOPLEFT", 6, -4)
		col.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		col.title = S.Text(col, "normal")
		col.title:SetPoint("LEFT", col.icon, "RIGHT", 6, 0)
		col.points = S.Text(col, "normal")
		col.points:SetPoint("TOPRIGHT", -8, -6)
		col.gridW = colW
		col.gridH = height - top - HEADER_H - 4
		col.buttons, col.arrows = {}, {}
		panel.columns[tab] = col
	end
	return panel
end
