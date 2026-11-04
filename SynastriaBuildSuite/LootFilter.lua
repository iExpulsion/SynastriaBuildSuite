local _, NS = ...
local SBS = NS.SBS

-- Hunt Gear: builds marked build.huntGear get their gear you don't own yet looted by Synastria's loot filter. The
-- addon keeps its own "SBS Gear" rules at the top of the filter, "any condition" rules of up to 8 Specific item
-- conditions set to Loot, and leaves every other rule as it is. The game saves the whole filter at once, so a sync
-- reads every rule, puts ours first and writes them all back the way the Lootfilter window's Apply does, after
-- keeping a copy of the filter it replaced for /sbs lootfilter restore.
local LootFilter = {}
SBS.LootFilter = LootFilter

local MAX_RULES, MAX_CONDITIONS = 32, 8
local PREFIX = "SBS Gear"
-- condition type, operator and rule fields as the filter stores them
local SPECIFIC_ITEM, EQUALS, ANY_CONDITION, LOOT = 20, 1, 1, 3
local RESYNC_AFTER = 2

local function ours(rule)
	return (rule.name or ""):sub(1, #PREFIX) == PREFIX
end

function LootFilter.Available()
	return Custom_GetLootFilter ~= nil and Custom_GetLootFilter() ~= nil
end

-- Every rule as { type, outcome, notify, name, cond = { { type, op, value } } } plus .options, or nil when the
-- server hasn't enabled the filter. type keeps the disabled bit (0x80) so it's written back unchanged.
local function read()
	local count, options = Custom_GetLootFilter()
	local rules
	if count then
		rules = { options = options }
		for i = 1, count do
			local rtype, condCount, outcome, notify, name = Custom_GetLootFilterRule(i)
			if rtype then
				local rule = { type = rtype, outcome = outcome, notify = notify or 0, name = name, cond = {} }
				for j = 1, condCount do
					local ctype, op, value = Custom_GetLootFilterRuleEntry(i, j)
					if ctype then rule.cond[#rule.cond + 1] = { type = ctype, op = op, value = value } end
				end
				rules[#rules + 1] = rule
			end
		end
	end
	return rules
end

-- Writes the whole filter, conditions first, then the rules, then the count that commits them. A condition the
-- server refuses stops the write before the commit, as Apply does. Returns ok, and the refused rule's name.
local function write(rules)
	local refused
	for i, rule in ipairs(rules) do
		for j, c in ipairs(rule.cond) do
			if not refused and Custom_SetLootFilterRuleEntry(i, j, c.type, c.op, c.value) then refused = rule.name or "a rule" end
		end
		if not refused then Custom_SetLootFilterRule(i, rule.type, #rule.cond, rule.outcome, rule.notify or 0, rule.name) end
	end
	if not refused then
		Custom_SetLootFilter(#rules, rules.options)
		-- the Lootfilter window keeps its own copy, which its Apply would write back over ours
		if UpdateLootFilter then UpdateLootFilter() end
	end
	return refused == nil, refused
end

local function owned(id)
	local have = GetItemCount(id, true) > 0
	for slot = 1, 19 do
		if GetInventoryItemID("player", slot) == id then have = true end
	end
	return have
end

-- The gear of every hunted build that you don't have worn, in your bags or in your bank, by build name and then
-- slot and rank, each item once.
function LootFilter.Wanted()
	local names, ids, seen = {}, {}, {}
	for name, build in pairs(SBS.db.builds) do
		if build.huntGear then names[#names + 1] = name end
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local gear = SBS.db.builds[name].gear or {}
		for slot = 1, 18 do
			for _, id in ipairs(gear[slot] or {}) do
				if not seen[id] and not owned(id) then
					seen[id] = true
					ids[#ids + 1] = id
				end
			end
		end
	end
	return ids
end

local function serialize(rules)
	local parts = { tostring(rules.options) }
	for _, rule in ipairs(rules) do
		parts[#parts + 1] = table.concat({ rule.type, rule.outcome, rule.notify or 0, rule.name or "" }, ":")
		for _, c in ipairs(rule.cond) do parts[#parts + 1] = table.concat({ c.type, c.op, c.value }, ",") end
	end
	return table.concat(parts, ";")
end

local function copy(rules)
	local out = { options = rules.options }
	for i, rule in ipairs(rules) do
		local cond = {}
		for j, c in ipairs(rule.cond) do cond[j] = { type = c.type, op = c.op, value = c.value } end
		out[i] = { type = rule.type, outcome = rule.outcome, notify = rule.notify, name = rule.name, cond = cond }
	end
	return out
end

-- The items the SBS Gear rules pick up now.
function LootFilter.Hunted()
	local ids = {}
	for _, rule in ipairs(read() or {}) do
		if ours(rule) then
			for _, c in ipairs(rule.cond) do
				if c.type == SPECIFIC_ITEM then ids[#ids + 1] = c.value end
			end
		end
	end
	return ids
end

-- Rewrites the SBS Gear rules from the hunted builds. Returns a result table: { items, dropped, changed }, or
-- { error = reason }.
function LootFilter.Sync()
	local rules = read()
	local result
	if not rules then
		result = { error = "the loot filter isn't enabled by the server" }
	else
		local kept = {}
		for _, rule in ipairs(rules) do
			if not ours(rule) then kept[#kept + 1] = rule end
		end
		local wanted = LootFilter.Wanted()
		local room = math.max(0, MAX_RULES - #kept) * MAX_CONDITIONS
		local new = { options = rules.options }
		local listed = math.min(#wanted, room)
		for i = 1, listed do
			local n = math.floor((i - 1) / MAX_CONDITIONS) + 1
			new[n] = new[n] or { type = ANY_CONDITION, outcome = LOOT, notify = 0, name = PREFIX .. " " .. n, cond = {} }
			table.insert(new[n].cond, { type = SPECIFIC_ITEM, op = EQUALS, value = wanted[i] })
		end
		for _, rule in ipairs(kept) do new[#new + 1] = rule end
		result = { items = listed, dropped = #wanted - listed, changed = serialize(new) ~= serialize(rules) }
		if result.changed then
			SBS.charDB.lootFilterBackup = copy(rules)
			local ok, refused = write(new)
			if not ok then result = { error = ("the server refused a condition in %s"):format(refused) } end
		end
	end
	return result
end

-- Writes back the filter as it was before the last sync that changed it.
function LootFilter.Restore()
	local backup = SBS.charDB.lootFilterBackup
	local ok = backup ~= nil and LootFilter.Available()
	if ok then ok = write(copy(backup)) end
	return ok
end

-- Syncs and says what happened, in chat and the window's footer.
function LootFilter.SyncAndReport()
	local r = LootFilter.Sync()
	local S = SBS.Style
	local text, color
	if r.error then
		text, color = "Loot Filter Not Changed: " .. r.error, "bad"
		SBS:Print("|cffff6060Loot filter not changed: %s.|r", r.error)
	else
		text, color = r.items == 0 and "No Missing Gear to Hunt" or ("Hunting %s"):format(S.Count(r.items, "Item")), "good"
		SBS:Print(r.items == 0 and "No missing gear to hunt; the SBS Gear rules are cleared." or
			("Loot filter set to pick up %s of missing build gear."):format(S.Count(r.items, "item")))
		if r.dropped > 0 then
			SBS:Print("|cffff6060%s left out: the loot filter has room for 32 rules.|r", S.Count(r.dropped, "item"))
		end
	end
	SBS.Window.Message(S.Hex(S.colors[color], text))
	return r
end

-- An item you were hunting that you now have would keep being looted, so the rules are synced again soon after.
local resyncAt
local watch = CreateFrame("Frame")
watch:RegisterEvent("BAG_UPDATE")
watch:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
watch:SetScript("OnEvent", function()
	if not resyncAt and LootFilter.Available() then
		local found = false
		for _, id in ipairs(LootFilter.Hunted()) do
			if owned(id) then found = true end
		end
		if found then resyncAt = GetTime() + RESYNC_AFTER end
	end
end)
watch:SetScript("OnUpdate", function()
	if resyncAt and GetTime() >= resyncAt and not InCombatLockdown() then
		resyncAt = nil
		LootFilter.Sync()
		SBS:Changed()
	end
end)
