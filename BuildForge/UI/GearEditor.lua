local _, NS = ...
local BF = NS.BF

-- The Gear tab: a paper doll of the build's Best item per slot, bordered by whether you're wearing it, and a
-- detail pane listing the selected slot's Best and Alts. Items dropped anywhere on the tab go to their slot.
local Editor = {}
BF.GearEditor = Editor

local S = BF.Style
local C = S.colors
local Gear

local DOLL_W, ICON, ROW, PAD = 320, 36, 42, 12
local LEFT = { 1, 2, 3, 15, 5, 9 }
local RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM = { 16, 17, 18 }
local SLOT_KEYS = {
	"HeadSlot", "NeckSlot", "ShoulderSlot", "ShirtSlot", "ChestSlot", "WaistSlot", "LegsSlot", "FeetSlot",
	"WristSlot", "HandsSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "BackSlot",
	"MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local LOOK = { worn = C.good, bags = C.warn, missing = { 0.5, 0.3, 0.3, 1 }, empty = C.border }

local panel, current
local state = { slot = 1, rank = 1 }
Editor.state = state

local function emptyTexture(slot)
	return select(2, GetInventorySlotInfo(SLOT_KEYS[slot])) or QUESTION
end

local function itemName(id)
	local name, link, quality = GetItemInfo(id)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return color and (color.hex .. name .. "|r") or name or ("Item " .. id), link
end

local function where(item)
	return item.equipped and S.Hex(C.good, "Worn") or item.inBags and S.Hex(C.warn, "In Bags") or S.Hex(C.muted, "Missing")
end

local function lookFor(row)
	local best = row and row.items[1]
	return not best and "empty" or best.equipped and "worn" or best.inBags and "bags" or "missing"
end

local function cursorItem()
	local kind, id = GetCursorInfo()
	if kind == "item" then
		ClearCursor()
		return id
	end
end

-- An item dropped on a slot goes there if it fits, otherwise to whichever slot it belongs in.
local function dropItem(id, slot)
	local ok, reason
	if slot and Gear.Fits(id, slot) then
		ok, reason = Gear.Add(current, slot, id)
		ok = ok and slot
	else
		ok, reason = Gear.AddAnywhere(current, id)
	end
	if ok then
		state.slot, state.rank = ok, #current.gear[ok]
		PlaySound("igMainMenuOptionCheckBoxOn")
		BF:Changed()
	else
		UIErrorsFrame:AddMessage(reason, 1, 0.3, 0.3)
	end
end

local function acceptDrop(slot)
	local id = cursorItem()
	if id then dropItem(id, slot) end
	return id ~= nil
end

-- Paper doll ------------------------------------------------------------------------------------------------

local function slotTooltip(button)
	local row = button.row
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if row then
		GameTooltip:SetHyperlink("item:" .. row.items[1].id)
		GameTooltip:AddLine(" ")
		if #row.items > 1 then GameTooltip:AddLine(S.Count(#row.items - 1, "Alt") .. " for this slot.", 0.6, 0.8, 1) end
		GameTooltip:AddLine("Click to see this slot's items.", 0.6, 0.6, 0.66)
	else
		GameTooltip:AddLine(BF.SLOT_NAMES[button.slot], 1, 1, 1)
		GameTooltip:AddLine("Empty. Drop an item here, or anywhere on this tab.", 0.6, 0.6, 0.66, true)
	end
	GameTooltip:Show()
end

local function newSlot(parent, slot)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(ICON, ICON)
	b.slot = slot
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	S.Panel(b, { 0, 0, 0, 1 }, C.border)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local hover = S.Solid(b, "HIGHLIGHT", { 1, 1, 1, 0.15 })
	hover:SetAllPoints(b.icon)
	b.selected = CreateFrame("Frame", nil, b)
	b.selected:SetPoint("TOPLEFT", -3, 3)
	b.selected:SetPoint("BOTTOMRIGHT", 3, -3)
	S.Panel(b.selected, { 0, 0, 0, 0 }, C.accent)
	b.selected:Hide()
	b.badgeBg = S.Solid(b, "OVERLAY", { 0, 0, 0, 0.85 })
	b.badgeBg:SetSize(20, 12)
	b.badgeBg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
	b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.badge:SetPoint("CENTER", b.badgeBg, "CENTER", 0, 0)
	b:SetScript("OnClick", function(self)
		if not acceptDrop(self.slot) then
			state.slot, state.rank = self.slot, 1
			BF.Window.Render()
		end
	end)
	b:SetScript("OnReceiveDrag", function(self) acceptDrop(self.slot) end)
	b:SetScript("OnEnter", slotTooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function newLabel(parent, alignRight)
	local l = {}
	l.name = S.Text(parent, "small")
	l.status = S.Text(parent, "small", C.muted)
	for _, fs in ipairs({ l.name, l.status }) do
		fs:SetWidth(DOLL_W / 2 - ICON - 12)
		fs:SetHeight(12)
		fs:SetWordWrap(false)
	end
	if alignRight then
		l.name:SetJustifyH("RIGHT")
		l.status:SetJustifyH("RIGHT")
	end
	return l
end

local function renderDoll(rowsBySlot)
	for slot, b in pairs(panel.slots) do
		local row = rowsBySlot[slot]
		b.row = row
		b.icon:SetTexture(row and (GetItemIcon(row.items[1].id) or QUESTION) or emptyTexture(slot))
		b.icon:SetDesaturated(row == nil)
		b.icon:SetAlpha(row and 1 or 0.5)
		b:SetBackdropBorderColor(unpack(LOOK[lookFor(row)]))
		if slot == state.slot then b.selected:Show() else b.selected:Hide() end
		local alts = row and #row.items - 1 or 0
		if alts > 0 then
			b.badge:SetText("+" .. alts)
			b.badgeBg:Show()
			b.badge:Show()
		else
			b.badgeBg:Hide()
			b.badge:Hide()
		end
		local label = panel.labels[slot]
		if label then
			label.name:SetText(row and itemName(row.items[1].id) or S.Hex(C.muted, BF.SLOT_NAMES[slot]))
			label.status:SetText(row and where(row.items[1]) or "Empty")
		end
	end
end

-- Detail pane -----------------------------------------------------------------------------------------------

local function renderDetail(rowsBySlot)
	local d = panel.detail
	local slot = state.slot
	local row = rowsBySlot[slot]
	local items = row and row.items or {}
	if state.rank > #items then state.rank = math.max(1, #items) end
	d.title:SetText(BF.SLOT_NAMES[slot])
	d.sub:SetText(#items == 0 and "No item chosen for this slot."
		or #items == 1 and "1 item." or ("%d items: Best first, then Alts in order."):format(#items))
	local list = d.list
	list:Begin()
	for rank, item in ipairs(items) do
		local name = itemName(item.id)
		local label = rank == 1 and S.Hex(C.good, "Best") or S.Hex(C.warn, "Alt " .. (rank - 1))
		list:Add({
			text = label .. "  " .. name, icon = GetItemIcon(item.id) or QUESTION, indent = 2,
			status = where(item), selected = rank == state.rank,
			onDrop = function(id) dropItem(id, slot) end,
			onClick = function(_, mouse)
				if mouse == "RightButton" then
					Gear.Remove(current, slot, rank)
					BF:Changed()
				elseif IsModifiedClick("CHATLINK") then
					local link = select(2, GetItemInfo(item.id))
					if link then ChatEdit_InsertLink(link) end
				elseif IsControlKeyDown() then
					Gear.MakeBest(current, slot, rank)
					state.rank = 1
					BF:Changed()
				else
					state.rank = rank
					BF.Window.Render()
				end
			end,
			tooltip = function(tt)
				tt:SetHyperlink("item:" .. item.id)
				tt:AddLine(" ")
				tt:AddLine("Right-click removes, Ctrl-click makes it Best, Shift-click links it.", 0.6, 0.6, 0.66, true)
			end,
		})
	end
	list:End()
	if #items > 0 and state.rank > 1 then d.best:Enable() else d.best:Disable() end
	if #items > 0 then d.remove:Enable() else d.remove:Disable() end
end

local function summary(rows)
	local worn, inBags = 0, 0
	for _, row in ipairs(rows) do
		if row.wearing == 1 then worn = worn + 1 elseif row.equip then inBags = inBags + 1 end
	end
	local text
	if #rows == 0 then
		text = S.Hex(C.muted, "No Gear Yet: Drop Items Here or Use My Gear")
	else
		text = ("Wearing the Best Item in %d of %d Slots"):format(worn, #rows)
		if inBags > 0 then text = text .. ", " .. S.Count(inBags, "Better Item") .. " in Your Bags" end
	end
	return text
end

function Editor.Render(build)
	current = build
	Gear = BF.Gear
	local rows = Gear.Status(build.gear)
	local rowsBySlot = {}
	for _, row in ipairs(rows) do rowsBySlot[row.slot] = row end
	renderDoll(rowsBySlot)
	renderDetail(rowsBySlot)
	return summary(rows)
end

-- Construction ----------------------------------------------------------------------------------------------

local function createDetail(width, height)
	local d = CreateFrame("Frame", nil, panel)
	d:SetSize(width, height)
	S.Panel(d, { 0.04, 0.04, 0.05, 1 }, C.border)
	d:EnableMouse(true)
	d:SetScript("OnReceiveDrag", function() acceptDrop(state.slot) end)
	d:SetScript("OnMouseUp", function() acceptDrop(state.slot) end)
	d.title = S.Text(d, "large")
	d.title:SetPoint("TOPLEFT", PAD, -PAD)
	d.sub = S.Text(d, "small", C.muted)
	d.sub:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
	d.sub:SetWidth(width - 2 * PAD)
	d.list = BF.List.New(d, "BuildForgeGearDetail", width - 22, height - 52 - 92)
	d.list.scroll:SetPoint("TOPLEFT", 1, -52)
	d.hint = S.Text(d, "small", C.muted)
	d.hint:SetPoint("BOTTOMLEFT", PAD, 44)
	d.hint:SetWidth(width - 2 * PAD)
	d.hint:SetText("Drop an item anywhere on this tab to add it to its slot. Rings, trinkets and one-hand weapons fill an empty slot of the pair first.")
	d.best = S.Button(d, "Make Best", "secondary", 90, function()
		Gear.MakeBest(current, state.slot, state.rank)
		state.rank = 1
		BF:Changed()
	end, "Move the selected item to the top of this slot.")
	d.best:SetPoint("BOTTOMLEFT", PAD, PAD)
	d.remove = S.Button(d, "Remove", "danger", 80, function()
		Gear.Remove(current, state.slot, state.rank)
		BF:Changed()
	end, "Take the selected item out of this slot.")
	d.remove:SetPoint("LEFT", d.best, "RIGHT", 6, 0)
	return d
end

function Editor.Create(parent, width, height)
	Gear = BF.Gear
	panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(width, height)
	panel:EnableMouse(true)
	panel:SetScript("OnReceiveDrag", function() acceptDrop(nil) end)
	panel:SetScript("OnMouseUp", function() acceptDrop(nil) end)
	panel.slots, panel.labels = {}, {}

	for i, slot in ipairs(LEFT) do
		local b = newSlot(panel, slot)
		b:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
		local l = newLabel(panel)
		l.name:SetPoint("TOPLEFT", b, "TOPRIGHT", 8, -3)
		l.status:SetPoint("TOPLEFT", l.name, "BOTTOMLEFT", 0, -2)
		panel.slots[slot], panel.labels[slot] = b, l
	end
	for i, slot in ipairs(RIGHT) do
		local b = newSlot(panel, slot)
		b:SetPoint("TOPLEFT", DOLL_W - ICON, -(i - 1) * ROW)
		local l = newLabel(panel, true)
		l.name:SetPoint("TOPRIGHT", b, "TOPLEFT", -8, -3)
		l.status:SetPoint("TOPRIGHT", l.name, "BOTTOMRIGHT", 0, -2)
		panel.slots[slot], panel.labels[slot] = b, l
	end
	local bottomY = #RIGHT * ROW + 10
	local spacing = 16
	local startX = (DOLL_W - (#BOTTOM * ICON + (#BOTTOM - 1) * spacing)) / 2
	for i, slot in ipairs(BOTTOM) do
		local b = newSlot(panel, slot)
		b:SetPoint("TOPLEFT", startX + (i - 1) * (ICON + spacing), -bottomY)
		panel.slots[slot] = b
	end

	panel.detail = createDetail(width - DOLL_W - 16, height)
	panel.detail:SetPoint("TOPLEFT", DOLL_W + 16, 0)
	return panel
end
