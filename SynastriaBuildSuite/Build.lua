local _, NS = ...
local SBS = NS.SBS

local Build = {}
SBS.Build = Build

local SPEC_NAME_MAX = 14

local function isHunter()
	return GetHunterBM ~= nil and SBS:HasClass("HUNTER")
end

local function specName(group)
	return GetCustomGameDataString and GetCustomGameDataString(21, group) or ""
end

-- Captures the character's build for spec `group` (the active spec by default). Perks, pet aspects and the affix
-- order can only be read for the active spec, so another spec's build is marked perksPending until the player
-- switches to it.
function Build.Capture(name, group)
	group = group or SBS:ActiveGroup()
	local active = group == SBS:ActiveGroup()
	local talents, missed = SBS.Talents.Capture(group)
	local build = {
		name = name,
		classes = SBS:PlayerClasses(),
		spec = specName(group),
		perks = active and (SBS.Perks.Split(SBS.Perks.Capture())) or {},
		talents = talents,
		glyphs = SBS.Glyphs.Capture(group),
		gear = SBS.Gear.Capture(),
		pet = active and isHunter() and GetHunterBM() or nil,
		affixes = active and SBS.Affixes.Current() or nil,
		perksPending = not active or nil,
		notes = "",
	}
	return build, missed
end

-- Fills in a perksPending build's perks, pet aspects and affix order from the active spec.
function Build.FillPending(build)
	build.perks = (SBS.Perks.Split(SBS.Perks.Capture()))
	build.pet = isHunter() and GetHunterBM() or nil
	build.affixes = SBS.Affixes.Current()
	build.perksPending = nil
end

-- Replaces the checked sections ({ key = true }) of `build` with the character's, only for the build's classes the
-- character has: talents and glyphs per class, and the perks those classes can use. The parts for the build's
-- other classes stay. A build with no classes takes the character's. Returns classes whose talents couldn't be read.
function Build.CopyCurrent(build, sections)
	if not build.classes or #build.classes == 0 then build.classes = SBS:PlayerClasses() end
	local own = {}
	for _, class in ipairs(build.classes) do own[class] = SBS:HasClass(class) end
	local function merge(old, current)
		local out = {}
		for class, value in pairs(old or {}) do
			if not own[class] then out[class] = value end
		end
		for class, value in pairs(current) do
			if own[class] then out[class] = value end
		end
		return out
	end
	local missed = {}
	if sections.perks then
		local mine, wanted, perks = CustomGetClassMask(), SBS.Perks.ClassMask(build.classes), {}
		for _, p in ipairs(build.perks or {}) do
			local perk = PerkMgrPerks[p.id]
			if perk and not SBS.Perks.UsableFor(perk, mine) then perks[#perks + 1] = p end
		end
		for _, p in ipairs((SBS.Perks.Split(SBS.Perks.Capture()))) do
			local perk = PerkMgrPerks[p.id]
			if perk and SBS.Perks.UsableFor(perk, wanted) then perks[#perks + 1] = p end
		end
		table.sort(perks, function(a, b) return a.id < b.id end)
		build.perks = perks
		build.perksPending = nil
		if own.HUNTER and isHunter() then build.pet = GetHunterBM() end
	end
	if sections.talents then
		local talents, failed = SBS.Talents.Capture()
		build.talents = merge(build.talents, talents)
		for _, class in ipairs(failed) do
			if own[class] then missed[#missed + 1] = class end
		end
	end
	if sections.glyphs then build.glyphs = merge(build.glyphs, SBS.Glyphs.Capture()) end
	if sections.gear then build.gear = SBS.Gear.Capture() end
	if sections.affixes then build.affixes = SBS.Affixes.Current() end
	return missed
end

-- A build for `classes` copying the checked sections of the character (see CopyCurrent).
function Build.New(name, classes, sections)
	local build = { name = name, classes = classes, spec = "", perks = {}, talents = {}, glyphs = {}, gear = {}, notes = "" }
	if Build.Fits(build) then build.spec = specName(SBS:ActiveGroup()) end
	return build, Build.CopyCurrent(build, sections)
end

-- Class keys taken from the build's class perks, for strings that don't list classes.
function Build.InferClasses(build)
	local classes, seen = {}, {}
	for _, p in ipairs(build.perks or {}) do
		local perk = PerkMgrPerks and PerkMgrPerks[p.id]
		local key = perk and SBS.CLASS_KEYS[perk.cat]
		if key and not seen[key] then
			seen[key] = true
			classes[#classes + 1] = key
		end
	end
	return classes
end

-- True if every class the build needs is one of the character's.
function Build.Fits(build)
	local fits = true
	for _, class in ipairs(build.classes or {}) do
		if not SBS:HasClass(class) then fits = false end
	end
	return fits
end

function Build.Plan(build)
	local group = SBS:ActiveGroup()
	local spec = build.spec and build.spec:sub(1, SPEC_NAME_MAX)
	return {
		build = build,
		group = group,
		perks = SBS.Perks.BuildPlan(build),
		talents = SBS.Talents.Plan(build.talents),
		glyphs = SBS.Glyphs.Plan(build.glyphs),
		gear = SBS.Gear.Status(build.gear),
		affixes = not build.sharedOnly and SBS.Affixes.Plan(build.affixes) or nil,
		pet =build.pet and isHunter() and GetHunterBM() ~= build.pet and build.pet or nil,
		spec = spec and spec ~= "" and spec ~= specName(group) and spec or nil,
	}
end

-- The sidebar's Shared Perks entry: a build with no parts of its own, so applying it only applies the shared
-- Misc perks to the active spec.
Build.SHARED = { name = "Shared Perks", sharedOnly = true, perks = {} }

-- Applies everything the plan can change. Returns a summary for the chat report.
function Build.Apply(plan)
	local perksSent, optionsChanged, optionsUnchanged = SBS.Perks.Apply(plan.perks)
	local result = {
		perksSent = perksSent,
		optionsChanged = optionsChanged,
		optionsUnchanged = optionsUnchanged,
		refused = SBS.Talents.Apply(plan.talents),
		affixesSent = SBS.Affixes.Apply(plan.affixes),
	}
	if plan.pet then ChangeHunterBM(plan.pet) end
	if plan.spec then
		NotifyServer(6, plan.group, plan.spec)
		SetCustomGameDataString(21, plan.group, plan.spec)
		if UpdateTalentSpecNames then UpdateTalentSpecNames() end
	end
	if not plan.build.sharedOnly then SBS:Links()[plan.group] = plan.build.name end
	return result
end
