local _, NS = ...
local BF = NS.BF

local Perks = {}
BF.Perks = Perks

local FLAG_LOCKED = 0x80
local MAX_OPTION = 32

-- Limit index GetPerkLimit takes for a perk category (6 = Misc, no limit).
function Perks.LimitIndex(cat)
	if cat == 15 then return 1
	elseif cat == 16 then return 2
	elseif cat == 17 then return 3
	elseif cat == 18 then return 4
	elseif cat == 19 then return 6
	elseif (cat > 0 and cat <= 11) or cat == 13 then return 5
	end
	return 0
end

-- Same rule as the client's IsSameCategory: each class counts on its own, cat 13 counts with every class.
function Perks.SameCategory(a, b)
	return a ~= 0 and b ~= 0 and (a == b
		or (a == 13 and (b <= 11 or b == 13))
		or (b == 13 and a <= 11))
end

-- Same rule as the client's IsPerkHidden.
function Perks.IsHidden(perk)
	local flags, req = perk.flags or 0, bit.band(perk.req or 0, 0x7FF)
	local wrongClass = false
	if bit.band(flags, 0x200) == 0 and req ~= 0 then
		if bit.band(flags, 0x8000) == 0 then
			wrongClass = not CustomIsClassMask(req)
		else
			wrongClass = bit.band(req, CustomGetClassMask()) ~= req
		end
	end
	return wrongClass
		or bit.band(flags, 0x400) ~= 0
		or (bit.band(flags, 0x4000) ~= 0 and GetCustomGameData(29, perk.id) == 0)
end

-- Class perks carry no class mask; their category is the class ID.
function Perks.Usable(perk)
	local cat = perk.cat or 0
	return not Perks.IsHidden(perk) and (cat > 11 or cat == 0 or CustomIsClassMask(bit.lshift(1, cat - 1)))
end

function Perks.Writable()
	return PerkMgrFrame ~= nil and PerkMgrFrame:IsShown() and not PerkMgrReadOnly
end

function Perks.Capture()
	local list = {}
	for id, perk in pairs(PerkMgrPerks or {}) do
		if GetPerkActive(id) and Perks.Usable(perk) then
			local spell = GetDruidSpec and GetDruidSpec(id) or 0
			list[#list + 1] = { id = id, opt = GetPerkOptions(id) or 0, spell = spell or 0 }
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

local function countActive(active, cat)
	local n = 0
	for id in pairs(active) do
		local p = PerkMgrPerks[id]
		if Perks.SameCategory(cat, p.cat) and not Perks.IsHidden(p) then n = n + 1 end
	end
	return n
end

-- What applying `wanted` (a build's perk list) would change, without changing anything.
function Perks.Plan(wanted)
	local plan = { deactivate = {}, activate = {}, options = {}, spells = {}, skipped = {} }
	local want, active = {}, {}

	for _, w in ipairs(wanted or {}) do
		local perk = PerkMgrPerks[w.id]
		if not perk then
			plan.skipped[#plan.skipped + 1] = { id = w.id, reason = "unknown perk" }
		elseif not Perks.Usable(perk) then
			plan.skipped[#plan.skipped + 1] = { id = w.id, reason = "not available to your classes" }
		else
			want[w.id] = w
		end
	end

	for id in pairs(PerkMgrPerks) do
		if GetPerkActive(id) then active[id] = true end
	end

	for id in pairs(active) do
		local perk = PerkMgrPerks[id]
		if not want[id] and Perks.Usable(perk) then
			if bit.band(perk.flags or 0, FLAG_LOCKED) ~= 0 then
				plan.skipped[#plan.skipped + 1] = { id = id, reason = "can't be turned off" }
			else
				plan.deactivate[#plan.deactivate + 1] = id
				active[id] = nil
			end
		end
	end

	local ids = {}
	for id in pairs(want) do ids[#ids + 1] = id end
	table.sort(ids)

	for _, id in ipairs(ids) do
		local perk, w = PerkMgrPerks[id], want[id]
		if not active[id] then
			local limitIndex = Perks.LimitIndex(perk.cat)
			local limit = GetPerkLimit(limitIndex) or 0
			if bit.band(perk.flags or 0, FLAG_LOCKED) ~= 0 then
				plan.skipped[#plan.skipped + 1] = { id = id, reason = "can't be turned on" }
			elseif limitIndex ~= 6 and countActive(active, perk.cat) >= limit then
				plan.skipped[#plan.skipped + 1] = { id = id, reason = "category full" }
			else
				plan.activate[#plan.activate + 1] = id
				active[id] = true
			end
		end

		local have = GetPerkOptions(id) or 0
		if (perk.options or 0) ~= 0 and w.opt ~= have then
			local diff = bit.bxor(w.opt, have)
			for i = 1, MAX_OPTION do
				local mask = bit.lshift(1, i - 1)
				if bit.band(diff, mask) ~= 0 then
					plan.options[#plan.options + 1] = { id = id, index = i, on = bit.band(w.opt, mask) ~= 0 }
				end
			end
		end

		if (w.spell or 0) ~= 0 and GetDruidSpec and GetDruidSpec(id) ~= w.spell then
			plan.spells[#plan.spells + 1] = { id = id, spell = w.spell }
		end
	end

	-- Turn options off before on, so a group's new choice isn't undone by clearing the old one.
	table.sort(plan.options, function(a, b)
		if a.on ~= b.on then return not a.on end
		if a.id ~= b.id then return a.id < b.id end
		return a.index < b.index
	end)

	plan.needsInnkeeper = #plan.deactivate + #plan.activate > 0
	return plan
end

-- Options and chosen abilities apply anywhere; activations only with the Perk window open at an innkeeper.
-- Returns true when activations were sent.
function Perks.Apply(plan)
	local writable = Perks.Writable()
	if writable then
		for _, id in ipairs(plan.deactivate) do
			NotifyServer(2, 2, tostring(id))
			SetCustomGameData(3, id, 0)
		end
		for _, id in ipairs(plan.activate) do
			NotifyServer(2, 1, tostring(id))
			SetCustomGameData(3, id, 1)
		end
	end
	for _, o in ipairs(plan.options) do
		ChangePerkOption(o.id, o.index, o.on)
	end
	for _, s in ipairs(plan.spells) do
		ChangeDruidSpec(s.id, s.spell)
	end
	if UpdatePerkMgr then UpdatePerkMgr() end
	return writable
end

function Perks.Name(id)
	local perk = PerkMgrPerks and PerkMgrPerks[id]
	return perk and perk.name or ("Perk " .. id)
end
