local _, NS = ...
local BF = NS.BF

-- Per tab: render(list, build) fills the list and returns a summary line, diff(build) counts what differs
-- from the character (for the tab badge), and actions are the footer buttons.
local Tabs = { render = {}, actions = {}, diff = {} }
BF.Tabs = Tabs

local GREEN, YELLOW, GREY = "|cff6bdb6b", "|cffffc742", "|cff9999a8"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function color(c, text) return c .. text .. "|r" end

local function spellIcon(id)
	return id and select(3, GetSpellInfo(id)) or QUESTION
end

-- Perks

-- (the tab itself is the editor in UI/PerkEditor.lua)

Tabs.diff.perks = function(build)
	local count
	if PerkMgrPerks then
		local plan = BF.Perks.Plan(BF.Perks.Wanted(build))
		count = #plan.activate + #plan.deactivate + #plan.options + #plan.spells
	end
	return count
end

Tabs.actions.perks = {
	{ label = "Use My Perks", tooltip = "Replace this build's perks with the ones active on your character now. Your active Misc perks become the Shared Perks every build uses.", run = function(build)
		local own, misc = BF.Perks.Split(BF.Perks.Capture())
		build.perks = own
		BF.db.shared.perks = {}
		BF.Perks.AddShared(misc)
		BF:Changed()
	end },
}

-- Talents (the tab itself is the calculator in UI/TalentEditor.lua)

-- Only the class shown in the talent window can be compared without switching classes.
Tabs.diff.talents = function(build)
	local class = BF.Talents.SelectedClass()
	local trees = build.talents and build.talents[class]
	local count
	if trees then
		count = 0
		local group = BF:ActiveGroup()
		for tab = 1, GetNumTalentTabs(false, false) do
			local want = trees[tab] or {}
			for i = 1, GetNumTalents(tab, false, false) do
				local rank = select(5, GetTalentInfo(tab, i, false, false, group)) or 0
				if rank ~= (want[i] or 0) then count = count + 1 end
			end
		end
	end
	return count
end

Tabs.actions.talents = {
	{ label = "Use My Talents", tooltip = "Replace this build's talents with your active spec's, for each of your classes.", run = function(build)
		local talents, missed = BF.Talents.Capture()
		build.talents = talents
		build.classes = BF:PlayerClasses()
		for _, class in ipairs(missed) do
			BF:Print("|cffff6060Couldn't read %s talents; select it in the talent window and try again.|r", class)
		end
		BF:Changed()
	end },
	{ label = "Reset Class", tooltip = "Clear every point this build spends in the class shown here.", run = function(build)
		BF.TalentCalc.Reset(build, BF.TalentEditor.state.class)
		BF:Changed()
	end },
}

-- Glyphs

Tabs.render.glyphs = function(list, build)
	local group, missing, count = BF:ActiveGroup(), 0, 0
	local sockets = {}
	for socket in pairs(build.glyphs or {}) do sockets[#sockets + 1] = socket end
	table.sort(sockets)
	for _, socket in ipairs(sockets) do
		local spell = build.glyphs[socket]
		local _, glyphType, have = GetGlyphSocketInfo(socket, group)
		local kind = glyphType == 1 and "Major" or "Minor"
		local status
		count = count + 1
		if have == spell then
			status = color(GREY, "Socketed")
		else
			missing = missing + 1
			status = have and color(YELLOW, "Socket has " .. (GetSpellInfo(have) or have)) or color(YELLOW, "Empty Socket")
		end
		list:Add({
			text = ("%s  %s"):format(color(GREY, kind), GetSpellInfo(spell) or ("Glyph " .. spell)),
			icon = spellIcon(spell), status = status,
			tooltip = function(tt) tt:SetHyperlink("spell:" .. spell) end,
		})
	end
	if count == 0 then return color(GREY, "This build has no glyphs.") end
	return missing == 0 and color(GREEN, "Your glyphs match this build.")
		or ("%d glyph(s) to socket. Glyphs are used up, so BuildForge leaves socketing to you."):format(missing)
end

Tabs.diff.glyphs = function(build)
	return #BF.Glyphs.Plan(build.glyphs)
end

Tabs.actions.glyphs = {
	{ label = "Use My Glyphs", tooltip = "Replace this build's glyphs with the ones socketed in your active spec.", run = function(build)
		build.glyphs = BF.Glyphs.Capture()
		BF:Changed()
	end },
}

-- Gear

local SLOT_FOR = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- True if the item can go in the slot, or its type isn't known yet (uncached item).
function Tabs.FitsSlot(id, slot)
	local equipLoc = select(9, GetItemInfo(id))
	local fits = equipLoc == nil
	for _, s in ipairs(equipLoc and SLOT_FOR[equipLoc] or {}) do
		if s == slot then fits = true end
	end
	return fits
end

local function addItem(build, slot, id)
	build.gear = build.gear or {}
	local items = build.gear[slot] or {}
	local present = false
	for _, existing in ipairs(items) do
		if existing == id then present = true end
	end
	if not Tabs.FitsSlot(id, slot) then
		BF:Print("|cffff6060That item doesn't go in the %s slot.|r", BF.SLOT_NAMES[slot])
	elseif not present then
		items[#items + 1] = id
		build.gear[slot] = items
		BF:Changed()
	end
end

local function itemClick(build, slot, rank)
	return function(_, mouseButton)
		local items = build.gear[slot]
		if mouseButton == "RightButton" then
			table.remove(items, rank)
			if #items == 0 then build.gear[slot] = nil end
			BF:Changed()
		elseif IsControlKeyDown() and rank > 1 then
			table.insert(items, 1, table.remove(items, rank))
			BF:Changed()
		elseif IsModifiedClick("CHATLINK") then
			local link = select(2, GetItemInfo(items[rank]))
			if link then ChatEdit_InsertLink(link) end
		end
	end
end

Tabs.render.gear = function(list, build)
	local rowsBySlot = {}
	for _, row in ipairs(BF.Gear.Status(build.gear)) do rowsBySlot[row.slot] = row end
	local worn, slots, inBags = 0, 0, 0
	for slot = 1, 18 do
		if slot ~= 4 then
			local row = rowsBySlot[slot]
			local slotName = color(GREY, BF.SLOT_NAMES[slot])
			local onDrop = function(id) addItem(build, slot, id) end
			if not row then
				list:Add({ text = slotName, status = color(GREY, "Drop an Item Here"), onDrop = onDrop })
			else
				slots = slots + 1
				if row.wearing == 1 then worn = worn + 1 elseif row.equip then inBags = inBags + 1 end
				for rank, item in ipairs(row.items) do
					local name, link = GetItemInfo(item.id)
					local where = item.equipped and color(GREEN, "Worn") or item.inBags and color(YELLOW, "In Bags") or color(GREY, "Missing")
					local label = rank == 1 and color(GREEN, "Best") or color(YELLOW, "Alt " .. (rank - 1))
					list:Add({
						text = (rank == 1 and slotName or "") .. "  " .. label .. "  " .. (link or name or ("Item " .. item.id)),
						indent = rank == 1 and 0 or 40,
						icon = GetItemIcon(item.id) or QUESTION,
						status = where,
						onDrop = onDrop,
						onClick = itemClick(build, slot, rank),
						tooltip = function(tt)
							tt:SetHyperlink("item:" .. item.id)
							tt:AddLine(" ")
							tt:AddLine("Best is the item to aim for; Alts are stand-ins in order of preference. Equip from Bags puts on the highest-ranked one you carry.", 0.6, 0.8, 1, true)
							tt:AddLine("Drop an item here to add an Alt. Right-click removes, Ctrl-click makes it Best.", 0.6, 0.8, 1, true)
						end,
					})
				end
			end
		end
	end
	if slots == 0 then return color(GREY, "Drag items onto a slot, or use your equipped gear.") end
	local summary = ("Wearing the Best item in %d of %d slots."):format(worn, slots)
	if inBags > 0 then summary = summary .. (" %d higher-ranked item(s) in your bags."):format(inBags) end
	return summary
end

Tabs.diff.gear = function(build)
	local count = 0
	for _, row in ipairs(BF.Gear.Status(build.gear)) do
		if row.wearing ~= 1 then count = count + 1 end
	end
	return count
end

Tabs.actions.gear = {
	{ label = "Equip from Bags", tooltip = "Put on the highest-ranked item you're carrying for each slot.", run = function(build) BF:EquipGear(build) end },
	{ label = "Use My Gear", tooltip = "Replace this build's gear with what you have equipped. Alts are cleared.", run = function(build)
		build.gear = BF.Gear.Capture()
		BF:Changed()
	end },
}
