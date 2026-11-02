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
