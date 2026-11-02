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
		perks = BF.Perks.Plan(BF.Perks.Wanted(build)),
		talents = BF.Talents.Plan(build.talents),
		glyphs = BF.Glyphs.Plan(build.glyphs),
		gear = BF.Gear.Status(build.gear),
		pet = build.pet and isHunter() and GetHunterBM() ~= build.pet and build.pet or nil,
		spec = spec and spec ~= "" and spec ~= specName(group) and spec or nil,
	}
end

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
	BF:Links()[plan.group] = plan.build.name
	return result
end
