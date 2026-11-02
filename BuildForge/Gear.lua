local _, NS = ...
local BF = NS.BF

local Gear = {}
BF.Gear = Gear

local SHIRT = 4

function Gear.Capture()
	local gear = {}
	for slot = 1, 18 do
		local id = slot ~= SHIRT and GetInventoryItemID("player", slot)
		if id then gear[slot] = { id } end
	end
	return gear
end

local function bagItems()
	local found = {}
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			local id = link and tonumber(link:match("item:(%d+)"))
			if id then found[id] = true end
		end
	end
	return found
end

-- One row per slot: the build's choices, what's equipped, and which choice to equip from bags.
function Gear.Status(wanted)
	local rows, inBags = {}, bagItems()
	for slot, items in pairs(wanted or {}) do
		local equipped = GetInventoryItemID("player", slot)
		local row = { slot = slot, items = {}, equipped = equipped }
		for rank, id in ipairs(items) do
			row.items[rank] = { id = id, equipped = id == equipped, inBags = inBags[id] or false }
			if id == equipped then row.wearing = rank end
		end
		for rank, item in ipairs(row.items) do
			if not row.equip and item.inBags and (not row.wearing or rank < row.wearing) then row.equip = item.id end
		end
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b) return a.slot < b.slot end)
	return rows
end

-- Editing a build's gear ------------------------------------------------------------------------------------

local SLOT_FOR = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- The slots an item can go in; nil while the item isn't cached yet, empty if it can't be equipped.
function Gear.SlotsFor(id)
	local equipLoc = select(9, GetItemInfo(id))
	return equipLoc and (SLOT_FOR[equipLoc] or {})
end

-- True if the item can go in the slot, or its type isn't known yet (uncached item).
function Gear.Fits(id, slot)
	local slots = Gear.SlotsFor(id)
	local fits = slots == nil
	for _, s in ipairs(slots or {}) do
		if s == slot then fits = true end
	end
	return fits
end

local function has(items, id)
	for _, existing in ipairs(items or {}) do
		if existing == id then return true end
	end
	return false
end

-- Adds an item to a slot as its next Alt (or Best, if the slot is empty). Returns ok and a reason when not.
function Gear.Add(build, slot, id)
	build.gear = build.gear or {}
	local ok, reason = Gear.Fits(id, slot) and not has(build.gear[slot], id), nil
	if not Gear.Fits(id, slot) then
		reason = ("That item doesn't go in the %s slot."):format(BF.SLOT_NAMES[slot])
	elseif not ok then
		reason = "That item is already in this slot."
	else
		local items = build.gear[slot] or {}
		items[#items + 1] = id
		build.gear[slot] = items
	end
	return ok, reason
end

-- Picks the slot for an item dropped anywhere: its only slot, or for rings, trinkets and one-hand weapons a slot
-- of the pair that doesn't have it yet (two copies of a non-unique item can fill both), preferring an empty one.
-- Returns the slot, or nil and a reason.
function Gear.SlotFor(build, id)
	local slots = Gear.SlotsFor(id)
	local gear = build.gear or {}
	local slot, open, reason
	if slots == nil then
		reason = "That item hasn't loaded yet; try again in a moment."
	elseif #slots == 0 then
		reason = "That item can't be equipped."
	else
		for _, s in ipairs(slots) do
			if not has(gear[s], id) then
				open = open or s
				if not gear[s] and not slot then slot = s end
			end
		end
		slot = slot or open
		if not slot then reason = "That item is already in " .. (#slots > 1 and "both slots." or "this slot.") end
	end
	return slot, reason
end

function Gear.AddAnywhere(build, id)
	local slot, reason = Gear.SlotFor(build, id)
	local ok = slot ~= nil
	if ok then ok, reason = Gear.Add(build, slot, id) end
	return ok and slot, reason
end

function Gear.Remove(build, slot, rank)
	local items = build.gear and build.gear[slot]
	if items and items[rank] then
		table.remove(items, rank)
		if #items == 0 then build.gear[slot] = nil end
	end
end

function Gear.MakeBest(build, slot, rank)
	local items = build.gear and build.gear[slot]
	if items and items[rank] and rank > 1 then table.insert(items, 1, table.remove(items, rank)) end
end

-- Equips the best owned choice per slot. Returns how many items were equipped.
function Gear.EquipFromBags(wanted)
	local count = 0
	if not InCombatLockdown() then
		for _, row in ipairs(Gear.Status(wanted)) do
			if row.equip then
				EquipItemByName(row.equip, row.slot)
				count = count + 1
			end
		end
	end
	return count
end
