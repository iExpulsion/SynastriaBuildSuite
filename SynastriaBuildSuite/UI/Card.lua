local _, NS = ...
local SBS = NS.SBS

-- The Build Card: a whole build on one screen, laid out to screenshot and post (on Discord, say). Read only; every
-- perk, talent, glyph and item shows its tooltip on hover.
local Card = {}
SBS.Card = Card

local S = SBS.Style
local C = S.colors

local PAD = S.PAD
local PERK_W, TALENT_W, GEAR_W, COL_GAP = 250, 328, 250, 20
local W = PAD + PERK_W + COL_GAP + TALENT_W + COL_GAP + GEAR_W + PAD
local CLOSE_W = 56
local HEADER_H = PAD + 18 + 4 + 12 + PAD
local SECTION_H, LINE_H, SMALL_H, BLOCK_GAP = 22, 16, 13, 14
local GEAR_ROW, GEAR_ICON, GLYPH_ICON = 22, 18, 16
local TREE_HEAD = 20
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame, current
local pools, used = { text = {}, hot = {}, rule = {}, icon = {} }, {}

local function showTip(self)
	if self.tip then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		self.tip(GameTooltip)
		GameTooltip:Show()
	end
end

local function hideTip()
	GameTooltip:Hide()
end

local function acquire(kind, make)
	used[kind] = (used[kind] or 0) + 1
	local item = pools[kind][used[kind]] or make()
	pools[kind][used[kind]] = item
	item:ClearAllPoints()
	item:Show()
	return item
end

local function releaseAll()
	for kind, list in pairs(pools) do
		for _, item in ipairs(list) do item:Hide() end
		used[kind] = 0
	end
end

local function text(x, y, size, color, width, value, justify)
	local fs = acquire("text", function() return frame.body:CreateFontString(nil, "ARTWORK") end)
	S.SetFont(fs, size)
	fs:SetTextColor(unpack(color or C.text))
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	fs:SetWidth(width)
	fs:SetPoint("TOPLEFT", frame.body, "TOPLEFT", x, -y)
	fs:SetText(value)
	return fs
end

-- An invisible area over a row of text that shows the row's tooltip.
local function hot(x, y, width, height, tip)
	local b = acquire("hot", function()
		local h = CreateFrame("Button", nil, frame.body)
		h:SetScript("OnEnter", showTip)
		h:SetScript("OnLeave", hideTip)
		return h
	end)
	b:SetSize(width, height)
	b:SetPoint("TOPLEFT", frame.body, "TOPLEFT", x, -y)
	b.tip = tip
	return b
end

local function rule(x, y, width)
	local t = acquire("rule", function() return S.Solid(frame.body, "BORDER", C.border) end)
	t:SetVertexColor(unpack(C.border))
	t:SetSize(width, 1)
	t:SetPoint("TOPLEFT", frame.body, "TOPLEFT", x, -y)
	return t
end

-- An icon with a 1px border in `border` (dimmed when `dim`), and a rank badge when `rank` is given.
local function icon(x, y, size, texture, tip, border, dim, rank)
	local b = acquire("icon", function()
		local i = CreateFrame("Button", nil, frame.body)
		S.Panel(i, { 0, 0, 0, 1 }, C.border)
		i.icon = i:CreateTexture(nil, "ARTWORK")
		i.icon:SetPoint("TOPLEFT", 1, -1)
		i.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		i.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		i.badge = S.Solid(i, "OVERLAY", { 0, 0, 0, 0.85 })
		i.badge:SetSize(12, 11)
		i.badge:SetPoint("BOTTOMRIGHT", i, "BOTTOMRIGHT", 3, -3)
		i.rank = S.Text(i, "small", C.text, "OVERLAY")
		i.rank:SetPoint("CENTER", i.badge, "CENTER", 0, 0)
		i:SetScript("OnEnter", showTip)
		i:SetScript("OnLeave", hideTip)
		return i
	end)
	b:SetSize(size, size)
	b:SetPoint("TOPLEFT", frame.body, "TOPLEFT", x, -y)
	b:SetBackdropBorderColor(unpack(border or C.border))
	b.icon:SetTexture(texture or QUESTION)
	b.icon:SetDesaturated(dim == true)
	b.icon:SetAlpha(dim and 0.3 or 1)
	b.tip = tip
	if rank then
		b.rank:SetText(rank)
		b.rank:Show()
		b.badge:Show()
	else
		b.rank:Hide()
		b.badge:Hide()
	end
	return b
end

-- A section title with an optional note on its right, over a rule. Returns the y below it.
local function heading(x, y, width, label, note)
	text(x, y, "normal", C.heading, width, label)
	if note then text(x, y + 1, "small", C.muted, width, note, "RIGHT") end
	rule(x, y + 16, width)
	return y + SECTION_H
end

local function spellIcon(id)
	return id and select(3, GetSpellInfo(id)) or QUESTION
end

local function itemTip(id)
	return function(tt) tt:SetHyperlink("item:" .. id) end
end

-- Perks ------------------------------------------------------------------------------------------------------

local function perkGroups(build)
	local Editor = SBS.PerkEditor
	local groups = {}
	for _, entry in ipairs(build.perks or {}) do
		local perk = PerkMgrPerks and PerkMgrPerks[entry.id]
		local cat = perk and Editor.CategoryOf(perk) or 0
		groups[cat] = groups[cat] or {}
		table.insert(groups[cat], { entry = entry, perk = perk, name = SBS.Perks.Name(entry.id) })
	end
	for _, list in pairs(groups) do
		table.sort(list, function(a, b)
			local sa, sb = a.perk and a.perk.sort or 0, b.perk and b.perk.sort or 0
			if sa ~= sb then return sa < sb end
			return a.name:upper() < b.name:upper()
		end)
	end
	return groups
end

-- The perk's chosen ability and the options set on it, as one line, or nil.
local function perkChoices(entry, mask)
	local parts = {}
	if (entry.spell or 0) ~= 0 then parts[#parts + 1] = GetSpellInfo(entry.spell) or ("Spell " .. entry.spell) end
	if (entry.opt or 0) ~= 0 and PerkMgrPerks and PerkMgrPerks[entry.id] then
		for _, o in ipairs(SBS.Perks.Options(entry.id, mask)) do
			if bit.band(entry.opt, bit.lshift(1, o.index - 1)) ~= 0 then parts[#parts + 1] = o.name end
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

local function perkTip(row)
	return function(tt)
		local Editor = SBS.PerkEditor
		tt:AddLine(row.name, 1, 1, 1)
		if row.perk then
			tt:AddLine(Editor.CategoryName(Editor.CategoryOf(row.perk)), 0.6, 0.6, 0.66)
			local desc = SBS.Perks.Description(row.entry.id, GetPerkAcquired(row.entry.id) or 1)
			if desc then tt:AddLine(desc, 1, 1, 1, true) end
		end
	end
end

local function categoryLabel(cat, count)
	local limit = cat >= 15 and cat <= 18 and GetPerkLimit and GetPerkLimit(SBS.Perks.LimitIndex(cat))
	local tally = limit and limit > 0 and ("%d/%d"):format(count, limit) or tostring(count)
	return ("%s  %s"):format(SBS.PerkEditor.CategoryName(cat), S.Hex(C.muted, tally))
end

local function drawPerks(build, x, y)
	local Editor = SBS.PerkEditor
	local groups = perkGroups(build)
	local mask = SBS.Perks.ClassMask(build.classes and #build.classes > 0 and build.classes or SBS:PlayerClasses())
	y = heading(x, y, PERK_W, "Perks", S.Count(#(build.perks or {}), "Perk"))
	for _, cat in ipairs(Editor.CATEGORY_ORDER) do
		local list = groups[cat]
		if list then
			text(x, y, "small", Editor.CategoryColor(cat) or C.heading, PERK_W, categoryLabel(cat, #list))
			y = y + LINE_H
			for _, row in ipairs(list) do
				text(x + 8, y, "normal", C.text, PERK_W - 8, row.name)
				local choices = perkChoices(row.entry, mask)
				local rowH = LINE_H + (choices and SMALL_H or 0)
				if choices then text(x + 16, y + LINE_H - 1, "small", C.muted, PERK_W - 16, choices) end
				hot(x, y, PERK_W, rowH, perkTip(row))
				y = y + rowH
			end
			y = y + 4
		end
	end
	return y
end

-- Talents ----------------------------------------------------------------------------------------------------

-- The build's classes that spend talent points, build classes first.
local function talentClasses(build)
	local Calc = SBS.TalentCalc
	local classes, seen = {}, {}
	local function consider(class)
		local trees = build.talents and build.talents[class]
		if not seen[class] and Calc.Trees(class) and trees and Calc.TotalPoints(trees) > 0 then
			classes[#classes + 1] = class
		end
		seen[class] = true
	end
	for _, class in ipairs(build.classes or {}) do consider(class) end
	local rest = {}
	for class in pairs(build.talents or {}) do rest[#rest + 1] = class end
	table.sort(rest)
	for _, class in ipairs(rest) do consider(class) end
	return classes
end

local function talentSplit(class, trees)
	local Calc = SBS.TalentCalc
	local parts = {}
	for tab in ipairs(Calc.Trees(class)) do parts[#parts + 1] = Calc.TreePoints(trees[tab]) end
	return table.concat(parts, " / ")
end

local function talentTip(t, rank)
	return function(tt)
		tt:SetHyperlink("spell:" .. t[3][math.max(rank, 1)])
		tt:AddLine(("Rank %d/%d"):format(rank, #t[3]), 1, 1, 1)
	end
end

local function drawTrees(class, trees, x, y, cell)
	local Calc = SBS.TalentCalc
	local data = Calc.Trees(class)
	local treeW = 4 * cell
	local gap = math.floor((TALENT_W - #data * treeW) / math.max(#data - 1, 1))
	local tiers = 0
	for _, tree in ipairs(data) do
		for _, t in ipairs(tree.talents) do tiers = math.max(tiers, t[1]) end
	end
	for tab, tree in ipairs(data) do
		local tx = x + (tab - 1) * (treeW + gap)
		local ranks = trees[tab] or {}
		local points = Calc.TreePoints(ranks)
		icon(tx, y, 14, tree.icon)
		text(tx + 18, y + 1, "small", points > 0 and C.text or C.muted, treeW - 18, tree.name)
		text(tx, y + 1, "small", points > 0 and C.accent or C.muted, treeW, points, "RIGHT")
		for i, t in ipairs(tree.talents) do
			local rank, max = ranks[i] or 0, #t[3]
			local border = rank >= max and C.accent or rank > 0 and C.good or C.border
			icon(tx + (t[2] - 1) * cell + 2, y + TREE_HEAD + (t[1] - 1) * cell + 2, cell - 4, spellIcon(t[3][1]),
				talentTip(t, rank), border, rank == 0, rank > 0 and rank or nil)
		end
	end
	return y + TREE_HEAD + tiers * cell
end

local function drawTalents(build, x, y)
	local classes = talentClasses(build)
	if #classes > 0 then
		local single = #classes == 1
		local note = single and (SBS.Window.ClassText({ classes[1] }) .. "  " .. talentSplit(classes[1], build.talents[classes[1]])) or nil
		y = heading(x, y, TALENT_W, "Talents", note)
		local cell = single and 26 or 22
		for _, class in ipairs(classes) do
			local trees = build.talents[class]
			if not single then
				text(x, y, "normal", C.text, TALENT_W, SBS.Window.ClassText({ class }) .. "  " .. S.Hex(C.muted, talentSplit(class, trees)))
				y = y + LINE_H + 2
			end
			y = drawTrees(class, trees, x, y, cell) + 6
		end
	end
	return y
end

-- Glyphs -----------------------------------------------------------------------------------------------------

local function glyphClasses(build)
	local classes, seen = {}, {}
	for _, class in ipairs(build.classes or {}) do
		if not seen[class] and next(SBS.Glyphs.For(build, class)) then classes[#classes + 1] = class end
		seen[class] = true
	end
	for class, sockets in pairs(build.glyphs or {}) do
		if not seen[class] and next(sockets) then classes[#classes + 1] = class end
		seen[class] = true
	end
	return classes
end

local function drawGlyphs(build, x, y)
	local classes = glyphClasses(build)
	if #classes > 0 then
		y = heading(x, y, TALENT_W, "Glyphs")
		local half = math.floor((TALENT_W - PAD) / 2)
		for _, class in ipairs(classes) do
			if #classes > 1 then
				text(x, y, "small", C.text, TALENT_W, SBS.Window.ClassText({ class }))
				y = y + LINE_H
			end
			local sockets = SBS.Glyphs.For(build, class)
			local rowY = { major = y + SMALL_H + 2, minor = y + SMALL_H + 2 }
			text(x, y, "small", C.muted, half, "Major")
			text(x + half + PAD, y, "small", C.muted, half, "Minor")
			for socket, info in ipairs(SBS.Glyphs.SOCKETS) do
				local spell = sockets[socket]
				if spell then
					local g = SBS.Glyphs.Find(spell)
					local gx = info.kind == "major" and x or x + half + PAD
					local gy = rowY[info.kind]
					local name = g and g.name or GetSpellInfo(spell) or ("Glyph " .. spell)
					local tip = g and itemTip(g.item) or function(tt) tt:SetHyperlink("spell:" .. spell) end
					icon(gx, gy, GLYPH_ICON, g and GetItemIcon(g.item) or spellIcon(spell), tip)
					text(gx + GLYPH_ICON + 6, gy + 2, "small", C.text, half - GLYPH_ICON - 6, (name:gsub("^Glyph of ", "")))
					hot(gx + GLYPH_ICON, gy, half - GLYPH_ICON, GLYPH_ICON, tip)
					rowY[info.kind] = gy + GLYPH_ICON + 4
				end
			end
			y = math.max(rowY.major, rowY.minor) + 2
		end
	end
	return y
end

-- Gear, affixes and notes ------------------------------------------------------------------------------------

local function drawGear(build, x, y)
	local count = 0
	for _ in pairs(build.gear or {}) do count = count + 1 end
	if count > 0 then
		y = heading(x, y, GEAR_W, "Gear")
		for slot = 1, 18 do
			local items = build.gear[slot]
			local id = items and items[1]
			if id then
				local name, _, quality, _, _, _, _, _, _, texture = SBS.ItemInfo(id)
				local alts = #items - 1
				icon(x, y, GEAR_ICON, texture or GetItemIcon(id), itemTip(id))
				text(x + GEAR_ICON + 6, y + 3, "normal", S.QualityColor(quality), GEAR_W - GEAR_ICON - 6 - (alts > 0 and 44 or 0),
					name or ("Item " .. id))
				if alts > 0 then text(x, y + 4, "small", C.muted, GEAR_W, "+" .. S.Count(alts, "Alt"), "RIGHT") end
				hot(x + GEAR_ICON, y, GEAR_W - GEAR_ICON, GEAR_ICON, itemTip(id))
				y = y + GEAR_ROW
			end
		end
		y = y + BLOCK_GAP - 4
	end
	return y
end

local function drawAffixes(build, x, y, width)
	local order = build.affixes or {}
	if #order > 0 then
		y = heading(x, y, width, "Affix Priority")
		local perColumn = math.ceil(#order / 2)
		local half = math.floor((width - PAD) / 2)
		for i, id in ipairs(order) do
			local column = i > perColumn and 1 or 0
			local row = (i - 1) % perColumn
			text(x + column * (half + PAD), y + row * (SMALL_H + 2), "small", C.text, half,
				S.Hex(C.muted, i .. ".") .. " " .. SBS.Affixes.Name(id))
		end
		y = y + perColumn * (SMALL_H + 2) + BLOCK_GAP
	end
	return y
end

local function drawNotes(build, x, y, width)
	local notes = (build.notes or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if notes ~= "" then
		y = heading(x, y, width, "Notes")
		frame.notes:ClearAllPoints()
		frame.notes:SetPoint("TOPLEFT", frame.body, "TOPLEFT", x, -y)
		frame.notes:SetWidth(width)
		frame.notes:SetText(notes)
		frame.notes:Show()
		y = y + frame.notes:Measure() + BLOCK_GAP
	else
		frame.notes:Hide()
	end
	return y
end

-- Window -----------------------------------------------------------------------------------------------------

function Card.Render()
	local build = current
	releaseAll()
	frame.title:SetText(build.name)
	local who = build.classes and #build.classes > 0 and SBS.Window.ClassText(build.classes) or S.Hex(C.muted, "No Class")
	local spec = build.spec or ""
	frame.sub:SetText(spec ~= "" and spec ~= build.name and (who .. S.Hex(C.muted, "   Spec: ") .. spec) or who)

	-- Only columns with something in them are drawn, left to right, and the card is as wide as they are.
	local hasPerks = #(build.perks or {}) > 0
	local hasTalents = #talentClasses(build) > 0 or #glyphClasses(build) > 0
	local gearCount = 0
	for _ in pairs(build.gear or {}) do gearCount = gearCount + 1 end
	local hasGear = gearCount > 0
	local notes = (build.notes or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local hasExtras = #(build.affixes or {}) > 0 or notes ~= ""

	local x, bottom, columns = 0, 0, {}
	local function column(width)
		local col = { x = x, width = width, y = 0 }
		columns[#columns + 1] = col
		x = x + width + COL_GAP
		return col
	end
	if hasPerks then
		local col = column(PERK_W)
		col.y = drawPerks(build, col.x, 0)
		bottom = col.y
	end
	-- affixes and notes go under whichever right-hand column ends higher, or in a column of their own
	local sides = {}
	if hasTalents then
		local col = column(TALENT_W)
		col.y = drawGlyphs(build, col.x, drawTalents(build, col.x, 0) + BLOCK_GAP - 6)
		sides[#sides + 1] = col
	end
	if hasGear then
		local col = column(GEAR_W)
		col.y = drawGear(build, col.x, 0)
		sides[#sides + 1] = col
	end
	if hasExtras and #sides == 0 then sides[1] = column(GEAR_W) end
	local function place(draw)
		local best = sides[1]
		for _, col in ipairs(sides) do
			if col.y < best.y then best = col end
		end
		local start = best.y > 0 and best.y + BLOCK_GAP or 0
		best.y = draw(build, best.x, start, best.width) - BLOCK_GAP
	end
	if hasExtras then
		place(drawAffixes)
		place(drawNotes)
	else
		frame.notes:Hide()
	end
	for _, col in ipairs(columns) do bottom = math.max(bottom, col.y) end
	if #columns == 0 then
		text(0, 0, "small", C.muted, PERK_W, "Nothing to Show")
		bottom = LINE_H
	end

	-- never narrower than the header's title, brand and Close button side by side
	local header = (frame.title:GetStringWidth() or 0) + (frame.brand:GetStringWidth() or 0) + CLOSE_W + 3 * S.GAP
	local bodyW = math.ceil(math.max(x - COL_GAP, header, (frame.sub:GetStringWidth() or 0)))
	local bodyH = math.ceil(bottom)
	frame.body:SetSize(bodyW, bodyH)
	frame:SetSize(2 * frame.edge + PAD + bodyW + PAD, 2 * frame.edge + HEADER_H + PAD + bodyH + PAD)
end

-- `sections` ({ key = true }, as the export box picks them) limits what's shown; nil shows everything.
function Card.Open(build, sections)
	frame = frame or Card.Create()
	current = SBS.Codec.Pick(build, sections)
	frame:Show()
	frame:Raise()
	Card.Render()
	-- wrapped notes know their height only once drawn, so lay out again on the next frame
	frame.relayout = true
end

function Card.Hide()
	if frame then frame:Hide() end
end

function Card.Frame()
	return frame
end

function Card.Create()
	S.RefreshFonts()
	local f = CreateFrame("Frame", "SynastriaBuildSuiteCard", UIParent)
	frame = f
	local edge = S.metrics.edge
	f.edge = edge
	f:SetSize(W + 2 * edge, 400)
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
	end)
	SBS.PixelScale(f)
	f:SetPoint("CENTER")
	S.Frame(f, "window")
	tinsert(UISpecialFrames, "SynastriaBuildSuiteCard")
	f:Hide()

	local left, top = edge + PAD, edge + PAD
	f.title = S.Text(f, "large")
	f.title:SetPoint("TOPLEFT", left, -top)
	f.sub = S.Text(f, "small")
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	local close = S.Button(f, "Close", "ghost", CLOSE_W, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", -(edge + PAD), -(edge + (HEADER_H - S.CONTROL_H) / 2))
	local brand = S.Text(f, "small", C.muted)
	f.brand = brand
	brand:SetPoint("RIGHT", close, "LEFT", -S.GAP, 0)
	brand:SetText("Synastria " .. S.Hex(C.accent, "Build Suite") .. S.Hex(C.muted, " v" .. SBS.version))
	local divider, dividerH = S.Divider(f, "rule")
	divider:SetHeight(dividerH)
	divider:SetPoint("TOPLEFT", edge, -(edge + HEADER_H))
	divider:SetPoint("TOPRIGHT", -edge, -(edge + HEADER_H))

	f.body = CreateFrame("Frame", nil, f)
	f.body:SetPoint("TOPLEFT", left, -(edge + HEADER_H + PAD))
	f.body:SetSize(W - 2 * PAD, 1)
	f.notes = S.Wrapped(f.body, "small", C.text)
	f.pools = pools

	f:SetScript("OnShow", function() PlaySound("igCharacterInfoOpen") end)
	f:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose")
		GameTooltip:Hide()
	end)
	f:SetScript("OnUpdate", function(self)
		if self.relayout then
			self.relayout = false
			Card.Render()
		end
	end)
	return f
end
