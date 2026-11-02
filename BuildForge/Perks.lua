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

-- IsHidden's rules for any set of classes, so builds for other classes can be edited. Class perks carry no class
-- mask; their category is the class ID.
function Perks.UsableFor(perk, mask)
	local flags, req, cat = perk.flags or 0, bit.band(perk.req or 0, 0x7FF), perk.cat or 0
	local all = bit.band(flags, 0x8000) ~= 0
	local classOk = bit.band(flags, 0x200) ~= 0 or req == 0
		or (not all and bit.band(req, mask) ~= 0)
		or (all and bit.band(req, mask) == req)
	return classOk
		and bit.band(flags, 0x400) == 0
		and not (bit.band(flags, 0x4000) ~= 0 and GetCustomGameData(29, perk.id) == 0)
		and (cat > 11 or cat == 0 or bit.band(mask, bit.lshift(1, cat - 1)) ~= 0)
end

function Perks.Usable(perk)
	return Perks.UsableFor(perk, CustomGetClassMask())
end

function Perks.ClassMask(classes)
	local mask = 0
	for _, key in ipairs(classes or {}) do
		local id = BF.CLASS_IDS[key]
		if id then mask = bit.bor(mask, bit.lshift(1, id - 1)) end
	end
	return mask
end

function Perks.Locked(perk)
	return bit.band(perk.flags or 0, FLAG_LOCKED) ~= 0
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

-- What applying `wanted` (a build's perk list) would change, without changing anything. `inScope(id)`, when given,
-- limits which active perks may be turned off (Shared Perks only touch Misc perks).
function Perks.Plan(wanted, inScope)
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
		if not want[id] and Perks.Usable(perk) and (not inScope or inScope(id)) then
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

-- Options and chosen abilities apply anywhere; activations only with the Perk Manager open at an innkeeper.
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

-- Shared perks ----------------------------------------------------------------------------------------------
-- Misc perks (category 19) live in one account-wide list, BuildForgeDB.shared, that every build applies.

Perks.SHARED_CAT = 19

function Perks.IsShared(id)
	local perk = PerkMgrPerks and PerkMgrPerks[id]
	return perk ~= nil and perk.cat == Perks.SHARED_CAT
end

-- Splits a perk list into a build's own perks and Misc perks.
function Perks.Split(list)
	local own, shared = {}, {}
	for _, w in ipairs(list or {}) do
		if Perks.IsShared(w.id) then shared[#shared + 1] = w else own[#own + 1] = w end
	end
	return own, shared
end

-- Adds perks to the shared list, keeping entries it already has. Returns how many were new.
function Perks.AddShared(list)
	local shared = BF.db.shared.perks
	local added = 0
	for _, w in ipairs(list) do
		if not Perks.Entry(BF.db.shared, w.id) then
			shared[#shared + 1] = { id = w.id, opt = w.opt or 0, spell = w.spell or 0 }
			added = added + 1
		end
	end
	table.sort(shared, function(a, b) return a.id < b.id end)
	return added
end

-- Moves Misc perks saved in a build (older builds, or ones imported before the perk list arrived) into the
-- shared list. Needs the perk list from the server, so it runs whenever a build is about to be used.
function Perks.MoveShared(build)
	if PerkMgrPerks and build.perks then
		local own, shared = Perks.Split(build.perks)
		if #shared > 0 then
			Perks.AddShared(shared)
			build.perks = own
		end
	end
end

-- The perk plan for a build: its own perks plus the shared ones. The Shared Perks entry (`sharedOnly`) plans the
-- shared list alone and leaves every other perk as it is.
function Perks.BuildPlan(build)
	return Perks.Plan(Perks.Wanted(build), build.sharedOnly and Perks.IsShared or nil)
end

-- What applying a build wants: its own perks plus the shared ones.
function Perks.Wanted(build)
	Perks.MoveShared(build)
	local list = {}
	for _, w in ipairs(build.perks or {}) do list[#list + 1] = w end
	for _, w in ipairs(BF.db.shared.perks) do list[#list + 1] = w end
	return list
end

-- Editing a build -------------------------------------------------------------------------------------------

function Perks.Entry(build, id)
	for _, w in ipairs(build.perks or {}) do
		if w.id == id then return w end
	end
end

-- Adds the perk (starting from the character's own options and ability) or removes it. Returns whether it's in.
function Perks.Toggle(build, id)
	build.perks = build.perks or {}
	local entry = Perks.Entry(build, id)
	if entry then
		for i, w in ipairs(build.perks) do
			if w == entry then
				table.remove(build.perks, i)
				break
			end
		end
	else
		entry = { id = id, opt = GetPerkOptions(id) or 0, spell = GetDruidSpec and GetDruidSpec(id) or 0 }
		build.perks[#build.perks + 1] = entry
		table.sort(build.perks, function(a, b) return a.id < b.id end)
	end
	return Perks.Entry(build, id) ~= nil
end

-- Perks in the build that share a limit with `cat`.
function Perks.CategoryCount(build, cat, mask)
	local n = 0
	for _, w in ipairs(build.perks or {}) do
		local p = PerkMgrPerks[w.id]
		if p and Perks.SameCategory(cat, p.cat) and Perks.UsableFor(p, mask) then n = n + 1 end
	end
	return n
end

-- The options a build can set: the client's toggles for these classes, not its one-off action buttons. `group`
-- options are pick-one; a group of 256 or more always keeps one picked. `index` is the option's bit, 1-based.
function Perks.Options(id, mask)
	local list = {}
	local perk = PerkMgrPerks[id]
	local info = perk and (perk.options or 0) ~= 0 and GetPerkOptionsInfo and GetPerkOptionsInfo(id)
	if info then
		for i = 1, MAX_OPTION do
			local opt = info[i]
			if opt and opt.n ~= "NULL" and not opt.b
				and (not opt.cl or bit.band(mask, bit.lshift(1, opt.cl - 1)) ~= 0)
				and (not opt.cond or opt.cond()) then
				list[#list + 1] = { index = i, name = opt.n, tip = opt.t, group = opt.grp, required = (opt.grp or 0) >= 256 }
			end
		end
	end
	return list
end

-- Sets one option on a build entry, clearing the rest of its group like ChangePerkOption. Returns whether it changed.
function Perks.SetOption(entry, options, index, on)
	local target
	for _, o in ipairs(options) do
		if o.index == index then target = o end
	end
	local before = entry.opt or 0
	local opt, mask = before, bit.lshift(1, index - 1)
	if target and on then
		for _, o in ipairs(options) do
			local m = bit.lshift(1, o.index - 1)
			if target.group and o.group == target.group and o.index ~= index and bit.band(opt, m) ~= 0 then opt = opt - m end
		end
		opt = bit.bor(opt, mask)
	elseif target and not target.required and bit.band(opt, mask) ~= 0 then
		opt = opt - mask
	end
	entry.opt = opt
	return opt ~= before
end

local ABILITY_PERK_FIRST, ABILITY_PERK_LAST = 1561, 1568

function Perks.HasAbility(perk)
	return bit.band(perk.flags or 0, 0x10000) ~= 0
end

-- Abilities perk `id` can grant to these classes, as {spell, flags}; flags 1 = deals damage, 2 = heals.
function Perks.Abilities(id, mask)
	local list = {}
	if id >= ABILITY_PERK_FIRST and id <= ABILITY_PERK_LAST then
		local perkMask = bit.lshift(1, id - ABILITY_PERK_FIRST)
		for _, a in ipairs(NS.AbilityData or {}) do
			if (a[2] == 0 or bit.band(mask, bit.lshift(1, a[2] - 1)) ~= 0) and bit.band(a[3], perkMask) ~= 0 then
				list[#list + 1] = { spell = a[1], flags = a[4] }
			end
		end
	end
	return list
end

local DESC_COLORS = { text = "|cffffffff", symbol = "|cff8080ff", symbol2 = "|cffffffff" }

-- The perk's effect at a rank, built the way the Perk Manager builds it (GeneratePerkDescription is local there).
function Perks.Description(id, rank)
	local perk = PerkMgrPerks[id]
	local level = perk and perk.levels and (perk.levels[rank] or perk.levels[1])
	local text
	if level and CustomGenerateDescription then
		local raw = (IsPerkDouble and IsPerkDouble(perk) and level.amounts2 or level.amounts) or {}
		local amounts = {}
		for i = 1, 5 do
			amounts[i] = GetModifiedPerkValue and GetModifiedPerkValue(raw[i] or 0, id, i) or raw[i] or 0
		end
		amounts[6] = GetCustomGameData(29, id)
		text = CustomGenerateDescription(perk.desc or "", amounts, DESC_COLORS)
	end
	return text
end

-- Perk sets ------------------------------------------------------------------------------------------------
-- PerkMgrSets[id] = { id, name, perks = { perk IDs }, bonus = { { count, desc, amounts, amounts2, perkid } } }.
-- Each set's perks sit in one category. Perks flagged 0x800 belong to a set but don't count toward its bonuses.

local FLAG_SET_UNCOUNTED = 0x800
local setOf, setOfSource

function Perks.SetOf(id)
	if PerkMgrSets and setOfSource ~= PerkMgrSets then
		setOf, setOfSource = {}, PerkMgrSets
		for _, set in pairs(PerkMgrSets) do
			for _, perkId in ipairs(set.perks or {}) do setOf[perkId] = set end
		end
	end
	return setOf and setOf[id]
end

local function counts(id)
	local perk = PerkMgrPerks[id]
	return perk ~= nil and bit.band(perk.flags or 0, FLAG_SET_UNCOUNTED) == 0
end
Perks.SetCounts = counts

-- How many of the set's counted perks `has(id)` says are in, out of how many there are.
function Perks.SetCount(set, has)
	local count, total = 0, 0
	for _, id in ipairs(set.perks or {}) do
		if counts(id) then
			total = total + 1
			if has(id) then count = count + 1 end
		end
	end
	return count, total
end

local SET_COLORS = {
	[true] = { text = "|cff60ff60", symbol = "|cff60ff60", symbol2 = "|cff60ff60" },
	[false] = { text = "|cff808080", symbol = "|cff808080", symbol2 = "|cff808080" },
}

-- Some bonuses scale with the ranks of the set's perks: the share of extra ranks learned, over the counted perks
-- `has` says are in.
local function rankScale(set, has)
	local learned, possible, any = 0, 0, false
	for _, id in ipairs(set.perks or {}) do
		local rank = counts(id) and has(id) and GetPerkAcquired(id)
		if rank then
			any = true
			learned = learned + (rank - 1)
			possible = possible + (#(PerkMgrPerks[id].levels or {}) - 1)
		end
	end
	return learned > 0 and math.max(0, math.min(1, learned / possible)) or any and 1 or 0
end

-- The set's bonuses as { count, active, text }, active once `has` covers `count` perks. The text is built the way
-- the Perk Manager does it (GenerateSetDescription is local there), green when active and gray when not.
function Perks.SetBonuses(set, has)
	local count = Perks.SetCount(set, has)
	local scale = rankScale(set, has)
	local out = {}
	for _, b in ipairs(set.bonus or {}) do
		if b.desc and b.desc ~= "" then
			local active = count >= (b.count or 0)
			local raw = (IsPerkDouble(b.perkid, true) and b.amounts2 or b.amounts) or {}
			local amounts = {}
			for i = 1, 5 do amounts[i] = GetModifiedPerkValue(raw[i] or 0, b.perkid, i) end
			amounts[6] = scale
			local colors = SET_COLORS[active]
			out[#out + 1] = { count = b.count or 0, active = active,
				text = colors.text .. ("(%d) "):format(b.count or 0) .. CustomGenerateDescription(b.desc, amounts, colors) .. "|r" }
		end
	end
	return out
end

-- The Perk Manager's "Additional information" notes, by perk.info bit (ProcessInfo is local there).
local INFO = {
	[0x1] = "This amount is based on your character level.",
	[0x8] = "Resource means mana, energy, rage, runic power or focus.",
	[0x10] = "Pets also include totems, minions and guardians.",
	[0x20] = "Slower weapons have higher chance to proc.",
	[0x40] = "Ally means party member or anyone you summoned.",
	[0x80] = "Enemy means anyone you are currently in combat with.",
	[0x100] = "Enemies with breakable crowd control effect are not targeted.",
	[0x200] = "This does not work in battlegrounds, arena or duel.",
	[0x400] = "This does not count as a healing effect.",
	[0x800] = "Effects that increase regeneration do not count as generating resources.",
	[0x1000] = "This effect does not stack.",
	[0x2000] = "Highest amount is selected at any given moment.",
	[0x4000] = "This effect does not cause any threat.",
	[0x8000] = "This doesn't work for pets.",
	[0x10000] = "This effect does not stack if applied from multiple characters.",
	[0x20000] = "Only applied when manually using the ability.",
	[0x40000] = "Same target can be chosen more than once.",
	[0x80000] = "Slower weapons have higher effect.",
	[0x100000] = "You need to have learned the ability for this effect to work.",
	[0x200000] = "This can not critically hit.",
	[0x400000] = "Ability means skill, spell, talent or item, but NOT perk.",
}
local CHANCE_NOTE = "Chance above 100 per-cent means it can happen more than once."

function Perks.Info(id)
	local perk = PerkMgrPerks[id]
	local lines = {}
	local info = perk and perk.info or 0
	local first = perk and perk.levels and perk.levels[1] and perk.levels[1].amounts
	for bitValue = 0, 22 do
		local flag = bit.lshift(1, bitValue)
		if flag == 2 then
			if bit.band(info, 2) ~= 0 or (bit.band(info, 4) ~= 0 and first and (first[1] or 0) > 100) then
				lines[#lines + 1] = CHANCE_NOTE
			end
		elseif bit.band(info, flag) ~= 0 and INFO[flag] then
			lines[#lines + 1] = INFO[flag]
		end
	end
	for _, x in ipairs(GetPerkInfoInfo and GetPerkInfoInfo(id) or {}) do
		if x and x.t and x.t ~= "" then lines[#lines + 1] = x.t end
	end
	return lines
end
