local _, NS = ...
local SBS = NS.SBS

local Gear = {}
SBS.Gear = Gear

local SHIRT = 4

function Gear.Capture()
	local gear = {}
	for slot = 1, 18 do
		local id = slot ~= SHIRT and GetInventoryItemID("player", slot)
		if id then gear[slot] = { id } end
	end
	return gear
end

-- Where each item sits in the bags: found[id] = { { bag, slot }, ... }, one entry per copy.
local function bagItems()
	local found = {}
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			local id = link and tonumber(link:match("item:(%d+)"))
			if id then
				found[id] = found[id] or {}
				table.insert(found[id], { bag = bag, slot = slot })
			end
		end
	end
	return found
end

-- One row per slot: the build's choices, what's equipped, and which choice to equip from bags (row.equip, with
-- its bag position in row.from). Each copy in the bags goes to one slot only, so the same ring or trinket in both
-- slots needs two copies.
function Gear.Status(wanted)
	local rows, inBags = {}, bagItems()
	for slot, items in pairs(wanted or {}) do
		local equipped = GetInventoryItemID("player", slot)
		local row = { slot = slot, items = {}, equipped = equipped }
		for rank, id in ipairs(items) do
			row.items[rank] = { id = id, equipped = id == equipped, inBags = inBags[id] ~= nil }
			if id == equipped then row.wearing = rank end
		end
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b) return a.slot < b.slot end)
	local used = {}
	for _, row in ipairs(rows) do
		for rank, item in ipairs(row.items) do
			local copies, taken = inBags[item.id], used[item.id] or 0
			if not row.equip and copies and taken < #copies and (not row.wearing or rank < row.wearing) then
				row.equip, row.from = item.id, copies[taken + 1]
				used[item.id] = taken + 1
			end
		end
	end
	return rows
end

-- The slots where the build wants something but none of its choices is worn or left in the bags.
function Gear.Missing(wanted)
	local missing = {}
	for _, row in ipairs(Gear.Status(wanted)) do
		if not row.wearing and not row.equip then missing[#missing + 1] = row end
	end
	return missing
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

-- Class IDs that can use each item subclass, indexed as GetAuctionItemSubClasses lists them. Weapons follow the
-- client's attune check (IsItemTypeValidForClass); armor is 3.3.5's equip rule.
local WEAPON_CLASSES = {
	[1] = { 1, 2, 3, 4, 6, 7 }, [2] = { 1, 2, 3, 6, 7 }, [3] = { 1, 3, 4 }, [4] = { 1, 3, 4 },
	[5] = { 1, 2, 4, 5, 6, 7, 11 }, [6] = { 1, 2, 6, 7, 11 }, [7] = { 1, 2, 3, 6, 11 }, [8] = { 1, 2, 3, 4, 6, 8, 9 },
	[9] = { 1, 2, 3, 6 }, [10] = { 1, 3, 5, 7, 8, 9, 11 }, [11] = { 1, 3, 4, 7, 11 }, [13] = { 1, 3, 4, 5, 7, 8, 9, 11 },
	[14] = { 1, 3, 4 }, [15] = { 1, 3, 4 }, [16] = { 5, 8, 9 },
}
local ARMOR_CLASSES = {
	[3] = { 1, 2, 3, 4, 6, 7, 11 }, [4] = { 1, 2, 3, 6, 7 }, [5] = { 1, 2, 6 }, [6] = { 1, 2, 7 },
	[7] = { 2 }, [8] = { 11 }, [9] = { 7 }, [10] = { 6 },
}
local DUAL_WIELD_CLASSES = { 1, 3, 4, 6, 7 }
local DUAL_WIELD_PERK = 188

local function anyClass(allowed, ids)
	local any = false
	for _, a in ipairs(allowed) do
		for _, id in ipairs(ids) do
			if a == id then any = true end
		end
	end
	return any
end

-- Whether the build's classes can use the item in `slot`: its armor or weapon type, dual wielding (or the Dual
-- Wielding perk) for an off-hand weapon, and the item's own class list. Uncached items and builds with no classes
-- pass. Returns ok, and a reason when not.
function Gear.CanUse(build, id, slot)
	local _, _, _, _, _, itemType, subType, _, equipLoc = GetItemInfo(id)
	local ids = {}
	for _, key in ipairs(build.classes or {}) do ids[#ids + 1] = SBS.CLASS_IDS[key] end
	local who = #ids > 0 and SBS.Window.ClassText(build.classes, true)
	local weapon, armor = GetAuctionItemClasses()
	local rules = itemType == weapon and WEAPON_CLASSES or itemType == armor and ARMOR_CLASSES or {}
	local subs = { GetAuctionItemSubClasses(itemType == weapon and 1 or 2) }
	local rule
	for i, name in ipairs(subs) do
		if name == subType then rule = rules[i] end
	end
	local offHand = slot == 17 and (equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND")
	local perked = false
	for _, p in ipairs(build.perks or {}) do
		if p.id == DUAL_WIELD_PERK then perked = true end
	end
	local classMask = GetItemExtraCustom and GetItemExtraCustom(id)
	local reason
	if not who or not itemType then
		reason = nil
	elseif rule and not anyClass(rule, ids) then
		reason = ("%s can't use %s."):format(who, subType)
	elseif offHand and not perked and not anyClass(DUAL_WIELD_CLASSES, ids) then
		reason = ("%s can't dual wield without the Dual Wielding perk."):format(who)
	elseif classMask and classMask ~= 0 and bit.band(classMask, SBS.Perks.ClassMask(build.classes)) == 0 then
		reason = "That item is for another class."
	end
	return reason == nil, reason
end

-- Adds an item to a slot as its next Alt (or Best, if the slot is empty). Returns ok and a reason when not.
function Gear.Add(build, slot, id)
	build.gear = build.gear or {}
	local usable, refusal = Gear.CanUse(build, id, slot)
	local ok, reason = Gear.Fits(id, slot) and usable and not has(build.gear[slot], id), nil
	if not Gear.Fits(id, slot) then
		reason = ("That item doesn't go in the %s slot."):format(SBS.SLOT_NAMES[slot])
	elseif not usable then
		reason = refusal
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

-- Equips the best owned choice per slot, from its exact bag position so a second copy of a worn ring or trinket
-- isn't taken off the other slot. Returns how many items were equipped.
function Gear.EquipFromBags(wanted)
	local count = 0
	if not InCombatLockdown() and not CursorHasItem() then
		for _, row in ipairs(Gear.Status(wanted)) do
			if row.equip then
				PickupContainerItem(row.from.bag, row.from.slot)
				EquipCursorItem(row.slot)
				count = count + 1
			end
		end
	end
	return count
end

-- Equip on Spec Change ---------------------------------------------------------------------------------------

-- A swap puts the old item where the new one was, so a second pass a moment later catches an item that was worn
-- in the wrong slot of a pair.
local AUTO_DELAY, AUTO_PASSES = 1, 2
local auto = CreateFrame("Frame")
Gear.autoFrame = auto

-- The build linked to the active spec, when it has Equip on Spec Change on.
function Gear.AutoBuild()
	local build = SBS.db.builds[SBS:Links()[SBS:ActiveGroup()] or ""]
	return build and build.equipOnSpec and build or nil
end

local function itemText(id)
	return select(2, GetItemInfo(id)) or ("item " .. id)
end

local function finish()
	local build = auto.build
	auto.build = nil
	if auto.count > 0 then SBS:Print("Equipped %s for %s.", SBS.Style.Count(auto.count, "item"), build.name) end
	local missing = Gear.Missing(build.gear)
	if #missing > 0 then
		local parts = {}
		for _, row in ipairs(missing) do
			parts[#parts + 1] = ("%s (%s)"):format(itemText(row.items[1].id), SBS.SLOT_NAMES[row.slot])
		end
		SBS:Print("|cffffd060Not in your bags for %s:|r %s", build.name, table.concat(parts, ", "))
	end
end

local function step()
	if not InCombatLockdown() then
		local equipped = Gear.EquipFromBags(auto.build.gear)
		auto.count, auto.pass = auto.count + equipped, auto.pass + 1
		if equipped > 0 and auto.pass < AUTO_PASSES then auto.wait = AUTO_DELAY else finish() end
	end
end

-- Puts on a build's gear now, or once combat ends. A newer request replaces a waiting one.
function Gear.AutoEquip(build)
	auto.build, auto.count, auto.pass, auto.wait = build, 0, 0, nil
	if InCombatLockdown() then SBS:Print("Equipping %s's gear after combat.", build.name) end
	step()
end

auto:RegisterEvent("PLAYER_ENTERING_WORLD")
auto:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
auto:RegisterEvent("PLAYER_REGEN_ENABLED")
auto:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_ENABLED" and self.build and not self.wait then
		step()
	elseif event == "ACTIVE_TALENT_GROUP_CHANGED" and self.group and self.group ~= SBS:ActiveGroup() then
		local build = Gear.AutoBuild()
		self.build, self.wait = nil, nil
		if build then Gear.AutoEquip(build) end
	end
	if event ~= "PLAYER_REGEN_ENABLED" then self.group = SBS:ActiveGroup() end
end)
auto:SetScript("OnUpdate", function(self, elapsed)
	if self.wait then
		self.wait = self.wait - elapsed
		if self.wait <= 0 then
			self.wait = nil
			step()
		end
	end
end)
