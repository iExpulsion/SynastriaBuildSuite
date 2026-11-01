local _, NS = ...
local BF = NS.BF

local Tabs = { render = {}, actions = {} }
BF.Tabs = Tabs

local GREEN, YELLOW, RED, GREY = "|cff60ff60", "|cffffd040", "|cffff6060", "|cffaaaaaa"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function color(c, text) return c .. text .. "|r" end

local function spellIcon(id)
	return id and select(3, GetSpellInfo(id)) or QUESTION
end

-- Perks

local CATEGORY_ORDER = { 15, 16, 17, 18, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 13, 19 }
local CATEGORY_NAMES = { [15] = "Offensive", [16] = "Defensive", [17] = "Support", [18] = "Utility", [13] = "Class", [19] = "Misc" }

local function categoryName(cat)
	local key = BF.CLASS_KEYS[cat]
	return key and (BF.Window.ClassText({ key }) .. " Class") or CATEGORY_NAMES[cat] or "Other"
end

local function perkTooltip(id, wanted, status)
	return function(tt)
		local perk = PerkMgrPerks and PerkMgrPerks[id]
		tt:AddLine(BF.Perks.Name(id), 1, 1, 1)
		if perk then
			tt:AddLine(categoryName(perk.cat))
			local rank = GetPerkAcquired(id) or 0
			tt:AddLine(("Rank %d/%d"):format(rank, perk.levels and #perk.levels or 0), 0.8, 0.8, 0.8)
			local options = wanted and wanted.opt ~= 0 and GetPerkOptionsInfo and GetPerkOptionsInfo(id)
			for i, opt in ipairs(options or {}) do
				if bit.band(wanted.opt, bit.lshift(1, i - 1)) ~= 0 then tt:AddLine("Option: " .. (opt.n or i), 0.6, 0.8, 1) end
			end
			if wanted and (wanted.spell or 0) ~= 0 then
				tt:AddLine("Ability: " .. (GetSpellInfo(wanted.spell) or wanted.spell), 0.6, 0.8, 1)
			end
		end
		if status then tt:AddLine(status, 1, 0.8, 0.3, true) end
	end
end

Tabs.render.perks = function(list, build)
	local summary
	if not PerkMgrPerks then
		list:Add({ text = color(GREY, "Perk data hasn't arrived from the server yet.") })
	else
		local plan = BF.Perks.Plan(build.perks)
		local activate, skipped, optionsDiffer, spellDiffers = {}, {}, {}, {}
		for _, id in ipairs(plan.activate) do activate[id] = true end
		for _, s in ipairs(plan.skipped) do skipped[s.id] = s.reason end
		for _, o in ipairs(plan.options) do optionsDiffer[o.id] = true end
		for _, s in ipairs(plan.spells) do spellDiffers[s.id] = true end

		local byCat = {}
		for _, w in ipairs(build.perks or {}) do
			local perk = PerkMgrPerks[w.id]
			local cat = perk and perk.cat or 0
			byCat[cat] = byCat[cat] or {}
			table.insert(byCat[cat], w)
		end

		local order = {}
		for _, cat in ipairs(CATEGORY_ORDER) do order[#order + 1] = cat end
		order[#order + 1] = 0
		for _, cat in ipairs(order) do
			local perks = byCat[cat]
			if perks then
				list:Add({ text = categoryName(cat), header = true })
				table.sort(perks, function(a, b) return BF.Perks.Name(a.id) < BF.Perks.Name(b.id) end)
				for _, w in ipairs(perks) do
					local perk = PerkMgrPerks[w.id]
					local status
					if skipped[w.id] then status = color(GREY, skipped[w.id])
					elseif activate[w.id] then status = color(YELLOW, "To Activate")
					else status = color(GREEN, "Active") end
					if optionsDiffer[w.id] or spellDiffers[w.id] then status = status .. color(YELLOW, ", Options Differ") end
					list:Add({
						text = BF.Perks.Name(w.id), status = status, indent = 8,
						icon = perk and spellIcon(perk.icon) or QUESTION,
						tooltip = perkTooltip(w.id, w, skipped[w.id]),
					})
				end
			end
		end

		if #plan.deactivate > 0 then
			list:Add({ text = "Active but Not in This Build", header = true })
			for _, id in ipairs(plan.deactivate) do
				list:Add({
					text = BF.Perks.Name(id), status = color(RED, "To Deactivate"), indent = 8,
					icon = spellIcon(PerkMgrPerks[id].icon),
					tooltip = perkTooltip(id, nil, "Applying this build turns this perk off."),
				})
			end
		end

		local changes = #plan.activate + #plan.deactivate
		if changes + #plan.options + #plan.spells == 0 then
			summary = color(GREEN, "Your perks match this build.")
		else
			summary = ("%d to activate, %d to deactivate, %d option change(s)."):format(#plan.activate, #plan.deactivate, #plan.options + #plan.spells)
			if changes > 0 and not BF.Perks.Writable() then
				summary = summary .. color(RED, " Activations need the Perk window at an innkeeper.")
			end
		end
	end
	return summary
end

Tabs.actions.perks = {
	{ label = "Use My Current Perks", run = function(build)
		build.perks = BF.Perks.Capture()
		BF:Changed()
	end },
}

-- Talents

local function treePoints(trees)
	local totals = {}
	for i = 1, 3 do
		local sum = 0
		for _, r in ipairs(trees[i] or {}) do sum = sum + r end
		totals[i] = sum
	end
	return totals
end

local function talentClasses(build)
	local order, seen = {}, {}
	for _, key in ipairs(build.classes or {}) do
		if build.talents and build.talents[key] then order[#order + 1] = key; seen[key] = true end
	end
	for key in pairs(build.talents or {}) do
		if not seen[key] then order[#order + 1] = key end
	end
	return order
end

Tabs.render.talents = function(list, build)
	local shown = BF.Talents.SelectedClass()
	local group = BF:ActiveGroup()
	local toSpend, conflicts = 0, 0
	for _, class in ipairs(talentClasses(build)) do
		local trees = build.talents[class]
		local totals = treePoints(trees)
		local status = not BF:HasClass(class) and color(GREY, "Not Your Class") or nil
		list:Add({ text = ("%s  %d / %d / %d"):format(BF.Window.ClassText({ class }), totals[1], totals[2], totals[3]), status = status, header = true })

		if class == shown then
			for tab = 1, GetNumTalentTabs(false, false) do
				local tabName = GetTalentTabInfo(tab, false, false, group)
				list:Add({ text = color("|cffffd100", tabName or ("Tree " .. tab)), indent = 8 })
				local want = trees[tab] or {}
				for i = 1, GetNumTalents(tab, false, false) do
					local name, icon, _, _, rank, maxRank = GetTalentInfo(tab, i, false, false, group)
					local target = want[i] or 0
					if target > 0 or rank > 0 then
						local status
						if rank == target then status = color(GREEN, ("%d/%d"):format(rank, maxRank))
						elseif rank < target then status = color(YELLOW, ("%d, build has %d"):format(rank, target)); toSpend = toSpend + target - rank
						else status = color(RED, ("%d, build has %d"):format(rank, target)); conflicts = conflicts + 1 end
						list:Add({
							text = name, icon = icon, status = status, indent = 16,
							tooltip = function(tt) tt:SetTalent(tab, i, false, false, group) end,
						})
					end
				end
			end
		elseif BF:HasClass(class) then
			list:Add({ text = color(GREY, "Select this class in the talent window to see its talents."), indent = 8 })
		end
	end

	local summary
	if not build.talents or next(build.talents) == nil then
		summary = color(GREY, "This build has no talents.")
	elseif conflicts > 0 then
		summary = color(RED, ("%d talent(s) have more points than the build. Reset talents to apply it."):format(conflicts))
	elseif toSpend > 0 then
		local unspent = GetUnspentTalentPoints(false, false, group) or 0
		summary = ("%d point(s) to spend, %d unspent."):format(toSpend, unspent)
		if unspent < toSpend then summary = summary .. color(RED, " Not enough points yet; applying spends what it can.") end
	else
		summary = color(GREEN, "Your talents match this build.")
	end
	return summary
end

Tabs.actions.talents = {
	{ label = "Use My Current Talents", run = function(build)
		local talents, missed = BF.Talents.Capture()
		build.talents = talents
		build.classes = BF:PlayerClasses()
		for _, class in ipairs(missed) do
			BF:Print("|cffff6060Couldn't read %s talents; select it in the talent window and try again.|r", class)
		end
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
			status = color(GREEN, "Socketed")
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

Tabs.actions.glyphs = {
	{ label = "Use My Current Glyphs", run = function(build)
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
					local attune = item.attuned and color(GREEN, "Attuned") or color(GREY, ("%d%%"):format(item.progress or 0))
					list:Add({
						text = (rank == 1 and slotName or color(GREY, "  or")) .. "  " .. (link or name or ("Item " .. item.id)),
						icon = GetItemIcon(item.id) or QUESTION,
						status = where .. "  " .. attune,
						onDrop = onDrop,
						onClick = itemClick(build, slot, rank),
						tooltip = function(tt)
							tt:SetHyperlink("item:" .. item.id)
							tt:AddLine("Drop an item here to add an alternative. Right-click removes it, Ctrl-click makes it the top choice.", 0.6, 0.8, 1, true)
						end,
					})
				end
			end
		end
	end
	if slots == 0 then return color(GREY, "Drag items onto a slot, or use your equipped gear.") end
	local summary = ("%d of %d slots wear the top choice."):format(worn, slots)
	if inBags > 0 then summary = summary .. (" %d better item(s) in your bags."):format(inBags) end
	return summary
end

Tabs.actions.gear = {
	{ label = "Equip from Bags", run = function(build) BF:EquipGear(build) end },
	{ label = "Use My Equipped Gear", run = function(build)
		build.gear = BF.Gear.Capture()
		BF:Changed()
	end },
}
