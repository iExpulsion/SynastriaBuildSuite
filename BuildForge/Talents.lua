local _, NS = ...
local BF = NS.BF

local Talents = {}
BF.Talents = Talents

local function isMultiClass()
	return CMCGetClassCount ~= nil and CMCGetClassCount() > 1 and not CMCIsDualSingleClass()
end

-- Shows `class` in the talent API. Returns false if the client didn't switch (see docs/DESIGN.md). The switch
-- refreshes that class's talent info, firing PLAYER_TALENT_UPDATE; `switching` lets the window ignore those.
function Talents.Select(class)
	local ok = true
	if isMultiClass() then
		for i, key in ipairs(BF:PlayerClasses()) do
			if key == class then
				if GetSelectedTalentClassIndex() ~= i then
					Talents.switching = true
					CMCSetSelectedTalents(i)
					Talents.switching = false
				end
				ok = GetSelectedTalentClassIndex() == i
			end
		end
	end
	return ok
end

function Talents.SelectedClass()
	local classes = BF:PlayerClasses()
	return isMultiClass() and classes[GetSelectedTalentClassIndex()] or classes[1]
end

local function readTrees(group)
	local trees = {}
	for tab = 1, GetNumTalentTabs(false, false) do
		local ranks = {}
		for i = 1, GetNumTalents(tab, false, false) do
			ranks[i] = select(5, GetTalentInfo(tab, i, false, false, group)) or 0
		end
		trees[tab] = ranks
	end
	return trees
end

-- Returns talents by class key for spec `group` (the active spec by default), and the classes it couldn't read.
function Talents.Capture(group)
	local shown = Talents.SelectedClass()
	group = group or BF:ActiveGroup()
	local result, missed = {}, {}
	for _, class in ipairs(BF:PlayerClasses()) do
		if Talents.Select(class) then
			result[class] = readTrees(group)
		else
			missed[#missed + 1] = class
		end
	end
	Talents.Select(shown)
	return result, missed
end

-- Per class: the points to add (in tier order), ranks above the build, and classes the character lacks.
function Talents.Plan(wanted)
	local plan = { classes = {}, skipped = {} }
	local group = BF:ActiveGroup()
	local shown = Talents.SelectedClass()
	for class, trees in pairs(wanted or {}) do
		if not BF:HasClass(class) then
			plan.skipped[#plan.skipped + 1] = { class = class, reason = "not one of your classes" }
		elseif not Talents.Select(class) then
			plan.skipped[#plan.skipped + 1] = { class = class, reason = "switch to it in the talent window and apply again" }
		else
			local entry = { class = class, adds = {}, conflicts = {}, points = 0 }
			for tab = 1, GetNumTalentTabs(false, false) do
				local want = trees[tab] or {}
				for i = 1, GetNumTalents(tab, false, false) do
					local name, _, tier, _, rank = GetTalentInfo(tab, i, false, false, group)
					local target = want[i] or 0
					if target > rank then
						entry.adds[#entry.adds + 1] = { tab = tab, index = i, tier = tier, delta = target - rank, name = name }
						entry.points = entry.points + target - rank
					elseif target < rank then
						entry.conflicts[#entry.conflicts + 1] = { tab = tab, index = i, name = name, have = rank, want = target }
					end
				end
			end
			table.sort(entry.adds, function(a, b)
				if a.tier ~= b.tier then return a.tier < b.tier end
				if a.tab ~= b.tab then return a.tab < b.tab end
				return a.index < b.index
			end)
			entry.unspent = GetUnspentTalentPoints(false, false, group) or 0
			plan.classes[#plan.classes + 1] = entry
		end
	end
	Talents.Select(shown)
	return plan
end

-- Points spent in the class shown in the talent window, for the active spec.
function Talents.Spent()
	local spent = 0
	for tab = 1, GetNumTalentTabs(false, false) do
		spent = spent + select(3, GetTalentTabInfo(tab, false, false, BF:ActiveGroup()))
	end
	return spent
end

-- Adds preview points tier by tier and learns them. Returns the talents the client refused.
function Talents.Apply(plan)
	local group, shown = BF:ActiveGroup(), Talents.SelectedClass()
	local refused = {}
	for _, entry in ipairs(plan.classes) do
		if #entry.conflicts == 0 and #entry.adds > 0 and Talents.Select(entry.class) then
			if ResetGroupPreviewTalentPoints then ResetGroupPreviewTalentPoints(false, group) end
			for _, add in ipairs(entry.adds) do
				local before = select(9, GetTalentInfo(add.tab, add.index, false, false, group)) or 0
				AddPreviewTalentPoints(add.tab, add.index, add.delta, false, group)
				local after = select(9, GetTalentInfo(add.tab, add.index, false, false, group)) or 0
				if after - before < add.delta then
					refused[#refused + 1] = { class = entry.class, name = add.name }
				end
			end
			LearnPreviewTalents(false)
		end
	end
	Talents.Select(shown)
	return refused
end
