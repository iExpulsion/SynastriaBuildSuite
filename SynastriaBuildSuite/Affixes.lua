local _, NS = ...
local SBS = NS.SBS

-- Item affix priority: when an item has more than one of its affixes attuned, the server activates the first one
-- in this order. It has the same 16 slots as the game's Item Affix Manager, belongs to the talent spec, and like
-- perk activations can only be changed at an innkeeper. Builds keep it as a list of affix IDs, most wanted first.
local Affixes = {}
SBS.Affixes = Affixes

Affixes.SLOTS = 16

-- The game's Set Default orders.
Affixes.PRESETS = {
	{ name = "Strength DPS", ids = { 53, 23, 39, 51, 34, 29, 24, 21, 22, 27, 25, 32, 30, 28, 6 } },
	{ name = "Agility DPS", ids = { 53, 21, 22, 39, 25, 34, 28, 50, 23, 26, 29, 27, 31, 33, 6 } },
	{ name = "Tank", ids = { 59, 53, 24, 38, 35, 6, 29, 40, 39, 23, 51, 28, 21, 22, 27 } },
	{ name = "Caster", ids = { 53, 7, 11, 8, 10, 13, 12, 52, 15, 16, 14, 6, 17, 18 } },
}

local catalog, byId

-- The order without empty slots, at most 16 long.
function Affixes.Compact(list)
	local out = {}
	for _, id in ipairs(list or {}) do
		if id and id ~= 0 and #out < Affixes.SLOTS then out[#out + 1] = id end
	end
	return out
end

-- The active spec's order, or nil when the game doesn't offer it.
function Affixes.Current()
	local order
	if GetCustomGameData then
		local slots = {}
		for i = 1, Affixes.SLOTS do slots[i] = GetCustomGameData(19, i) or 0 end
		order = Affixes.Compact(slots)
	end
	return order
end

local function statNames(...)
	local names, seen = {}, {}
	for n = 1, select("#", ...) do
		for _, stat in ipairs(select(n, ...) or {}) do
			local name = GetAttuneStatName and GetAttuneStatName(stat)
			if name and name ~= "" and not seen[name] then
				seen[name] = true
				names[#names + 1] = name
			end
		end
	end
	table.sort(names)
	return names
end

-- Every affix the order can hold, sorted by name: { id, name, stats }. Prefix and suffix affixes with the same
-- index share one ID, as in the game's picker; the list is read once the game's affix table has loaded.
function Affixes.Options()
	if not catalog and ItemAttuneAffix and FindItemAffix then
		local list, ids = {}, {}
		local function add(id, name, stats)
			if name and not ids[id] then
				ids[id] = { id = id, name = name, stats = stats }
				list[#list + 1] = ids[id]
			end
		end
		for i = 0, 63 do
			local a, b = FindItemAffix(i, false), FindItemAffix(i, true)
			if a and b and not a.filterindex and not b.filterindex then
				local name = a.name == b.name and a.name or ((a.name or "?") .. " / " .. (b.name or "?"))
				if a.name2 then name = name .. " / " .. a.name2 end
				if b.name2 then name = name .. " / " .. b.name2 end
				add(a.index + 1, name, statNames(a.stats, b.stats))
			else
				if a then add((a.filterindex or a.index) + 1, a.name, statNames(a.stats)) end
				if b then add((b.filterindex or b.index) + 1, b.name, statNames(b.stats)) end
			end
		end
		table.sort(list, function(x, y) return x.name:upper() < y.name:upper() end)
		catalog, byId = list, ids
	end
	return catalog or {}
end

function Affixes.Info(id)
	Affixes.Options()
	return byId and byId[id]
end

function Affixes.Name(id)
	local info = Affixes.Info(id)
	return info and info.name or ("Affix " .. tostring(id))
end

-- Where the affix sits in the order, or nil.
function Affixes.Position(order, id)
	for i, v in ipairs(order or {}) do
		if v == id then return i end
	end
end

local function same(a, b)
	local equal = #a == #b
	for i = 1, #a do
		if a[i] ~= b[i] then equal = false end
	end
	return equal
end

-- How many slots differ from the active spec's order, or nil when there's nothing to compare.
function Affixes.Diff(order)
	local current = Affixes.Current()
	local count
	if current and order and #order > 0 then
		count = 0
		for i = 1, Affixes.SLOTS do
			if (order[i] or 0) ~= (current[i] or 0) then count = count + 1 end
		end
	end
	return count
end

-- What applying the order would change: { order, current }, or nil when the build has none or it already matches.
function Affixes.Plan(order)
	local current = Affixes.Current()
	local wanted = Affixes.Compact(order)
	return current and #wanted > 0 and not same(wanted, current) and { order = wanted, current = current } or nil
end

-- Sends the order the way the game's Apply button does. Like perk activations it needs an innkeeper, so it's
-- skipped elsewhere. Returns whether it was sent.
function Affixes.Apply(plan)
	local sent = plan ~= nil and SBS.Perks.Writable()
	if sent then
		local slots = {}
		for i = 1, Affixes.SLOTS do slots[i] = plan.order[i] or 0 end
		NotifyServer(4, 0, table.concat(slots, ","))
	end
	return sent
end

-- Editing ---------------------------------------------------------------------------------------------------

function Affixes.Add(build, id)
	build.affixes = build.affixes or {}
	local ok = #build.affixes < Affixes.SLOTS and not Affixes.Position(build.affixes, id)
	if ok then build.affixes[#build.affixes + 1] = id end
	return ok
end

function Affixes.Remove(build, slot)
	if build.affixes and build.affixes[slot] then table.remove(build.affixes, slot) end
end

-- Swaps the slot with its neighbor `step` away (-1 up, 1 down). Returns the slot it moved to.
function Affixes.Move(build, slot, step)
	local list, to = build.affixes or {}, slot + step
	if list[slot] and list[to] then
		list[slot], list[to] = list[to], list[slot]
		slot = to
	end
	return slot
end

function Affixes.LoadPreset(build, preset)
	build.affixes = {}
	for i, id in ipairs(preset.ids) do build.affixes[i] = id end
end

-- The game's Item Affix Manager exports and imports its order as 16 comma-separated IDs (0 for an empty slot).
function Affixes.IsGameString(text)
	local s = (text or ""):gsub("%s", "")
	local ok = s:match("^%d+[%d,]*$") ~= nil
	if ok then
		local count, empty = 0, false
		for v in s:gmatch("%d+") do
			local n = tonumber(v)
			count = count + 1
			if n > 255 then ok = false end
			if n == 0 then empty = true end
		end
		ok = ok and count <= Affixes.SLOTS and (count == Affixes.SLOTS or empty)
	end
	return ok
end

function Affixes.DecodeGameString(text)
	local ids = {}
	for v in (text or ""):gsub("%s", ""):gmatch("%d+") do ids[#ids + 1] = tonumber(v) end
	return { name = "Affix Order", affixes = Affixes.Compact(ids) }
end
