local _, NS = ...
local SBS = NS.SBS

-- Item affix priority: when an item has more than one of its affixes attuned, the server activates the first one
-- in this order. It has the same 16 slots as the game's Item Affix Manager, belongs to the talent spec, and can
-- only be changed near an innkeeper. Builds keep it as a list of affix IDs, most wanted first.
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

-- An affix version's stats, biggest first (NS.AffixSizes, from the client's suffix data); equal or unknown sizes
-- keep the game's order.
local function bySize(afx)
	local sizes, order = NS.AffixSizes and NS.AffixSizes[afx.ex] or {}, {}
	for i in ipairs(afx.stats or {}) do order[i] = i end
	table.sort(order, function(x, y)
		local sx, sy = sizes[x] or 0, sizes[y] or 0
		if sx ~= sy then return sx > sy end
		return x < y
	end)
	return order
end

-- The stat names of one affix's versions (prefix and suffix share an ID), biggest first. Sizes only compare within
-- a version, so each stat goes by its best place in either one, then by which version lists it first.
local function statNames(...)
	local rank, first, names = {}, {}, {}
	for n = 1, select("#", ...) do
		local afx = select(n, ...)
		if afx then
			for place, i in ipairs(bySize(afx)) do
				local name = GetAttuneStatName and GetAttuneStatName(afx.stats[i])
				if name and name ~= "" then
					if not rank[name] then
						names[#names + 1] = name
						first[name] = #names
					end
					rank[name] = math.min(rank[name] or place, place)
				end
			end
		end
	end
	table.sort(names, function(a, b)
		if rank[a] ~= rank[b] then return rank[a] < rank[b] end
		return first[a] < first[b]
	end)
	return names
end

-- Each stat's share of an item's affix budget, as a whole percent, from the random suffix version (negative ex):
-- on the same item a bigger share is more of that stat, whichever suffix it's on. Property versions have none.
local function shares(afx)
	local sizes, out = afx and afx.ex and afx.ex < 0 and NS.AffixSizes and NS.AffixSizes[afx.ex], {}
	for i, stat in ipairs(sizes and afx.stats or {}) do
		local name = GetAttuneStatName and GetAttuneStatName(stat)
		if name and sizes[i] then out[name] = math.floor(sizes[i] / 100 + 0.5) end
	end
	return out
end

-- Every affix the order can hold, sorted by name: { id, name, stats, shares, key } (key is what search matches).
-- Prefix and suffix affixes with the same index share one ID, as in the game's picker; the list is read once the
-- game's affix table has loaded.
function Affixes.Options()
	if not catalog and ItemAttuneAffix and FindItemAffix then
		local list, ids = {}, {}
		local function add(id, name, stats, share)
			if name and not ids[id] then
				-- one line per term, so a search can't match across a name and a stat
				local key = (name .. "\n" .. table.concat(stats, "\n")):lower()
				ids[id] = { id = id, name = name, stats = stats, shares = share, key = key }
				list[#list + 1] = ids[id]
			end
		end
		for i = 0, 63 do
			local a, b = FindItemAffix(i, false), FindItemAffix(i, true)
			if a and b and not a.filterindex and not b.filterindex then
				local name = a.name == b.name and a.name or ((a.name or "?") .. " / " .. (b.name or "?"))
				if a.name2 then name = name .. " / " .. a.name2 end
				if b.name2 then name = name .. " / " .. b.name2 end
				add(a.index + 1, name, statNames(a, b), shares(a))
			else
				if a then add((a.filterindex or a.index) + 1, a.name, statNames(a), shares(a)) end
				if b then add((b.filterindex or b.index) + 1, b.name, statNames(b), shares(b)) end
			end
		end
		table.sort(list, function(x, y) return x.name:upper() < y.name:upper() end)
		catalog, byId = list, ids
	end
	return catalog or {}
end

-- Every affix, those giving the biggest share of `stat` first; affixes without a share for it follow by name.
function Affixes.ByShare(stat)
	local list = {}
	for i, info in ipairs(Affixes.Options()) do list[i] = info end
	table.sort(list, function(x, y)
		local a, b = x.shares[stat] or -1, y.shares[stat] or -1
		if a ~= b then return a > b end
		return x.name:upper() < y.name:upper()
	end)
	return list
end

-- Every stat some affix gives, sorted.
function Affixes.Stats()
	local names, seen = {}, {}
	for _, info in ipairs(Affixes.Options()) do
		for _, name in ipairs(info.stats) do
			if not seen[name] then
				seen[name] = true
				names[#names + 1] = name
			end
		end
	end
	table.sort(names)
	return names
end

local function givesAny(info, stats)
	for _, name in ipairs(info.stats) do
		if stats[name] then return true end
	end
	return false
end

-- Whether the affix's name or one of its stats contains the lowercase search text, and, when a set of stat names
-- is given and not empty, it gives at least one of them.
function Affixes.Matches(info, search, stats)
	local text = search == "" or info.key:find(search, 1, true) ~= nil
	return text and (stats == nil or next(stats) == nil or givesAny(info, stats))
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

-- Near an innkeeper the server answers by casting "Changing Affix Choices"; away from one it says so in chat.
-- After sending, both are watched for a while (the cast takes a few seconds) to tell the window how it went.
local REFUSED, CAST, WATCH_FOR, POLL_EVERY, POLL_FOR = "near an innkeeper", "affix", 30, 1, 10
local watchUntil, sentOrder, pollUntil, nextPoll = 0, nil, nil, nil

-- Sends the order the way the game's Apply button does. The server only takes it near an innkeeper, which the
-- client can't check, so it's always sent and the server decides. The stats and the order being replaced are
-- remembered first, except when reverting to that snapshot. Returns whether it was sent.
function Affixes.Apply(plan, keepSnapshot)
	local sent = plan ~= nil
	if sent then
		local slots = {}
		for i = 1, Affixes.SLOTS do slots[i] = plan.order[i] or 0 end
		if not keepSnapshot then SBS.Stats.Snapshot(plan.current) end
		NotifyServer(4, 0, table.concat(slots, ","))
		watchUntil, sentOrder = GetTime() + WATCH_FOR, plan.order
	end
	return sent
end

local function finish(text, color)
	watchUntil = 0
	local S = SBS.Style
	SBS.Window.Message(S.Hex(S.colors[color], text))
end

-- The server updates the order Current reads some time after the cast finishes, with no event of its own, so the
-- window redraws every second until the order matches what was sent, for up to 10 seconds on a slow connection.
local watch = CreateFrame("Frame")
watch:RegisterEvent("CHAT_MSG_SYSTEM")
watch:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
watch:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
watch:RegisterEvent("UNIT_SPELLCAST_FAILED")
watch:SetScript("OnEvent", function(_, event, unitOrMsg, spell)
	local watching = GetTime() < watchUntil
	-- the player's casts fire this all the time, so the name is only read while watching
	local ours = watching and unitOrMsg == "player" and (spell or ""):lower():find(CAST, 1, true) ~= nil
	if watching and event == "CHAT_MSG_SYSTEM" and (unitOrMsg or ""):lower():find(REFUSED, 1, true) then
		finish("Affix Order Not Changed: Apply Again Near an Innkeeper", "warn")
	elseif watching and ours and event == "UNIT_SPELLCAST_SUCCEEDED" then
		pollUntil, nextPoll = GetTime() + POLL_FOR, GetTime() + POLL_EVERY
		finish("Affix Order Changed", "good")
	elseif watching and ours then
		finish("Affix Order Not Changed: The Cast Was Interrupted", "warn")
	end
end)
watch:SetScript("OnUpdate", function()
	local now = GetTime()
	if pollUntil and now >= nextPoll then
		SBS:Changed()
		local current = Affixes.Current()
		if (current and same(current, sentOrder)) or now >= pollUntil then
			pollUntil = nil
		else
			nextPoll = now + POLL_EVERY
		end
	end
end)

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

-- Moves the affix in slot `from` to slot `to`, shifting the ones between. Returns the slot it ends up in.
function Affixes.Move(build, from, to)
	local list = build.affixes or {}
	if list[from] and list[to] then
		table.insert(list, to, table.remove(list, from))
		from = to
	end
	return from
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
