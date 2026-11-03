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

-- A build for `classes` copying the checked sections ({ key = true }) of the character: only the perks, talents
-- and glyphs those classes can use, and nothing for classes the character doesn't have.
function Build.New(name, classes, sections)
	local own = {}
	for _, class in ipairs(classes) do own[class] = BF:HasClass(class) end
	local function ownOnly(byClass)
		local out = {}
		for class, value in pairs(byClass) do
			if own[class] then out[class] = value end
		end
		return out
	end
	local build = { name = name, classes = classes, spec = "", perks = {}, talents = {}, glyphs = {}, gear = {}, notes = "" }
	if Build.Fits(build) then build.spec = specName(BF:ActiveGroup()) end
	local missed = {}
	if sections.perks then
		local mask = BF.Perks.ClassMask(classes)
		for _, p in ipairs((BF.Perks.Split(BF.Perks.Capture()))) do
			local perk = PerkMgrPerks[p.id]
			if perk and BF.Perks.UsableFor(perk, mask) then build.perks[#build.perks + 1] = p end
		end
		build.pet = own.HUNTER and isHunter() and GetHunterBM() or nil
	end
	if sections.talents then
		local talents, failed = BF.Talents.Capture()
		build.talents = ownOnly(talents)
		for _, class in ipairs(failed) do
			if own[class] then missed[#missed + 1] = class end
		end
	end
	if sections.glyphs then build.glyphs = ownOnly(BF.Glyphs.Capture()) end
	if sections.gear then build.gear = BF.Gear.Capture() end
	return build, missed
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
