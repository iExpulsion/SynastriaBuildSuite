local _, NS = ...
local BF = NS.BF

local Build = {}
BF.Build = Build

local SPEC_NAME_MAX = 14

local function isHunter()
	return GetHunterBM ~= nil and BF:HasClass("HUNTER")
end

local function specName(group)
	return GetCustomGameDataString and GetCustomGameDataString(21, group) or ""
end

-- Captures the character's current build for the active spec.
function Build.Capture(name)
	local talents, missed = BF.Talents.Capture()
	local build = {
		name = name,
		classes = BF:PlayerClasses(),
		spec = specName(BF:ActiveGroup()),
		perks = (BF.Perks.Split(BF.Perks.Capture())),
		talents = talents,
		glyphs = BF.Glyphs.Capture(),
		gear = BF.Gear.Capture(),
		pet = isHunter() and GetHunterBM() or nil,
		notes = "",
	}
	return build, missed
end

-- Replaces the checked sections ({ key = true }) of `build` with the character's, only for the build's classes the
-- character has: talents and glyphs per class, and the perks those classes can use. The parts for the build's
-- other classes stay. A build with no classes takes the character's. Returns classes whose talents couldn't be read.
function Build.CopyCurrent(build, sections)
	if not build.classes or #build.classes == 0 then build.classes = BF:PlayerClasses() end
	local own = {}
	for _, class in ipairs(build.classes) do own[class] = BF:HasClass(class) end
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
		local mine, wanted, perks = CustomGetClassMask(), BF.Perks.ClassMask(build.classes), {}
		for _, p in ipairs(build.perks or {}) do
			local perk = PerkMgrPerks[p.id]
			if perk and not BF.Perks.UsableFor(perk, mine) then perks[#perks + 1] = p end
		end
		for _, p in ipairs((BF.Perks.Split(BF.Perks.Capture()))) do
			local perk = PerkMgrPerks[p.id]
			if perk and BF.Perks.UsableFor(perk, wanted) then perks[#perks + 1] = p end
		end
		table.sort(perks, function(a, b) return a.id < b.id end)
		build.perks = perks
		if own.HUNTER and isHunter() then build.pet = GetHunterBM() end
	end
	if sections.talents then
		local talents, failed = BF.Talents.Capture()
		build.talents = merge(build.talents, talents)
		for _, class in ipairs(failed) do
			if own[class] then missed[#missed + 1] = class end
		end
	end
	if sections.glyphs then build.glyphs = merge(build.glyphs, BF.Glyphs.Capture()) end
	if sections.gear then build.gear = BF.Gear.Capture() end
	return missed
end

-- A build for `classes` copying the checked sections of the character (see CopyCurrent).
function Build.New(name, classes, sections)
	local build = { name = name, classes = classes, spec = "", perks = {}, talents = {}, glyphs = {}, gear = {}, notes = "" }
	if Build.Fits(build) then build.spec = specName(BF:ActiveGroup()) end
	return build, Build.CopyCurrent(build, sections)
end

-- Class keys taken from the build's class perks, for strings that don't list classes.
function Build.InferClasses(build)
	local classes, seen = {}, {}
	for _, p in ipairs(build.perks or {}) do
		local perk = PerkMgrPerks and PerkMgrPerks[p.id]
		local key = perk and BF.CLASS_KEYS[perk.cat]
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
		if not BF:HasClass(class) then fits = false end
	end
	return fits
end

function Build.Plan(build)
	local group = BF:ActiveGroup()
	local spec = build.spec and build.spec:sub(1, SPEC_NAME_MAX)
	return {
		build = build,
		group = group,
		perks = BF.Perks.BuildPlan(build),
		talents = BF.Talents.Plan(build.talents),
		glyphs = BF.Glyphs.Plan(build.glyphs),
		gear = BF.Gear.Status(build.gear),
		pet = build.pet and isHunter() and GetHunterBM() ~= build.pet and build.pet or nil,
		spec = spec and spec ~= "" and spec ~= specName(group) and spec or nil,
	}
end

-- The sidebar's Shared Perks entry: a build with no parts of its own, so applying it only applies the shared
-- Misc perks to the active spec.
Build.SHARED = { name = "Shared Perks", sharedOnly = true, perks = {} }

-- Applies everything the plan can change. Returns a summary for the chat report.
function Build.Apply(plan)
	local result = {
		perksSent = BF.Perks.Apply(plan.perks),
		refused = BF.Talents.Apply(plan.talents),
	}
	if plan.pet then ChangeHunterBM(plan.pet) end
	if plan.spec then
		NotifyServer(6, plan.group, plan.spec)
		SetCustomGameDataString(21, plan.group, plan.spec)
		if UpdateTalentSpecNames then UpdateTalentSpecNames() end
	end
	if not plan.build.sharedOnly then BF:Links()[plan.group] = plan.build.name end
	return result
end
