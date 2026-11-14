local _, NS = ...
local SBS = NS.SBS

-- Templates: one tab of a build saved under a name, account-wide, to load into any build. SBS.db.templates[section]
-- [name] = { name, data, ... }. Talents and glyphs are kept per class (the class the tab shows) and load into
-- builds with that class. Perks keep the build's classes and replace only the perks those classes can use, so a
-- two-class build keeps its other class's perks; a Hunter's pet aspects come along. Gear and affixes fit any build.
local Templates = {}
SBS.Templates = Templates

Templates.SECTIONS = {
	{ key = "perks", label = "Perks" }, { key = "talents", label = "Talents" }, { key = "glyphs", label = "Glyphs" },
	{ key = "gear", label = "Gear" }, { key = "affixes", label = "Affixes" },
}
local LABELS = {}
for _, s in ipairs(Templates.SECTIONS) do LABELS[s.key] = s.label end

function Templates.Label(section)
	return LABELS[section]
end

local function copy(v)
	local out = v
	if type(v) == "table" then
		out = {}
		for k, x in pairs(v) do out[k] = copy(x) end
	end
	return out
end

local function store(section)
	local all = SBS.db.templates
	all[section] = all[section] or {}
	return all[section]
end

local function hasClass(build, class)
	local found = false
	for _, key in ipairs(build.classes or {}) do
		if key == class then found = true end
	end
	return found
end

local function className(class)
	return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
end

-- Per section: what a build has to save (nil when there's nothing), whether a template fits a build (and why
-- not), how to load it, and a short summary for lists.
local KINDS = {}

KINDS.perks = {
	take = function(build)
		return #(build.perks or {}) > 0 and { classes = copy(build.classes or {}), data = copy(build.perks), pet = build.pet } or nil
	end,
	fits = function(t, build)
		local missing
		for _, class in ipairs(t.classes) do
			if not hasClass(build, class) then missing = missing or class end
		end
		return missing == nil, missing and ("Needs " .. className(missing))
	end,
	load = function(t, build)
		local mask, kept = SBS.Perks.ClassMask(t.classes), {}
		for _, w in ipairs(build.perks or {}) do
			local perk = PerkMgrPerks and PerkMgrPerks[w.id]
			if perk and not SBS.Perks.UsableFor(perk, mask) then kept[#kept + 1] = w end
		end
		for _, w in ipairs(copy(t.data)) do kept[#kept + 1] = w end
		table.sort(kept, function(a, b) return a.id < b.id end)
		build.perks = kept
		build.perksPending = nil
		if t.pet then build.pet = t.pet end
	end,
	describe = function(t)
		return SBS.Window.ClassText(t.classes, true) .. ", " .. SBS.Style.Count(#t.data, "Perk")
	end,
}

KINDS.talents = {
	take = function(build, class)
		local trees = class and build.talents and build.talents[class]
		return trees and SBS.TalentCalc.TotalPoints(trees) > 0 and { class = class, data = copy(trees) } or nil
	end,
	fits = function(t, build)
		local points = SBS.TalentCalc.TotalPoints(t.data)
		local reason
		if not hasClass(build, t.class) then
			reason = "Needs " .. className(t.class)
		elseif points > SBS.TalentCalc.MaxPoints(build, t.class) then
			reason = ("Needs %d Points"):format(points)
		end
		return reason == nil, reason
	end,
	load = function(t, build)
		build.talents = build.talents or {}
		build.talents[t.class] = copy(t.data)
	end,
	describe = function(t)
		return className(t.class) .. ", " .. SBS.Style.Count(SBS.TalentCalc.TotalPoints(t.data), "Point")
	end,
}

KINDS.glyphs = {
	take = function(build, class)
		local sockets = class and build.glyphs and build.glyphs[class]
		return sockets and next(sockets) and { class = class, data = copy(sockets) } or nil
	end,
	fits = function(t, build)
		local ok = hasClass(build, t.class)
		return ok, not ok and ("Needs " .. className(t.class)) or nil
	end,
	load = function(t, build)
		build.glyphs = build.glyphs or {}
		build.glyphs[t.class] = copy(t.data)
	end,
	describe = function(t)
		local n = 0
		for _ in pairs(t.data) do n = n + 1 end
		return className(t.class) .. ", " .. SBS.Style.Count(n, "Glyph")
	end,
}

KINDS.gear = {
	take = function(build)
		return build.gear and next(build.gear) and { data = copy(build.gear) } or nil
	end,
	fits = function() return true end,
	load = function(t, build) build.gear = copy(t.data) end,
	describe = function(t)
		local n = 0
		for _ in pairs(t.data) do n = n + 1 end
		return SBS.Style.Count(n, "Slot")
	end,
}

KINDS.affixes = {
	take = function(build)
		return build.affixes and #build.affixes > 0 and { data = copy(build.affixes) } or nil
	end,
	fits = function() return true end,
	load = function(t, build) build.affixes = copy(t.data) end,
	describe = function(t)
		return SBS.Style.Count(#t.data, "Affix", "Affixes")
	end,
}

-- The section's templates, sorted by name.
function Templates.List(section)
	local list = {}
	for _, t in pairs(store(section)) do list[#list + 1] = t end
	table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
	return list
end

function Templates.Get(section, name)
	return store(section)[name]
end

-- Whether the build has anything in the section to save; `class` is the class the Talents or Glyphs tab shows.
function Templates.CanSave(section, build, class)
	return KINDS[section].take(build, class) ~= nil
end

-- Saves the build's section under `name`, replacing a template of that name. Returns it, or nil with nothing to save.
function Templates.Save(section, name, build, class)
	local t = KINDS[section].take(build, class)
	if t then
		t.name = name
		store(section)[name] = t
	end
	return t
end

function Templates.Fits(section, t, build)
	return KINDS[section].fits(t, build)
end

-- Replaces the build's section (for its classes, as above) with the template's. Returns whether it fit.
function Templates.Load(section, t, build)
	local ok = KINDS[section].fits(t, build)
	if ok then KINDS[section].load(t, build) end
	return ok
end

function Templates.Describe(section, t)
	return KINDS[section].describe(t)
end

-- Returns false when the new name is empty or already taken.
function Templates.Rename(section, old, new)
	local all = store(section)
	local ok = new ~= "" and all[old] ~= nil and (new == old or all[new] == nil)
	if ok then
		local t = all[old]
		all[old] = nil
		t.name = new
		all[new] = t
	end
	return ok
end

function Templates.Delete(section, name)
	store(section)[name] = nil
end

function Templates.UniqueName(section, base)
	local all, name, n = store(section), base, 1
	while all[name] do
		n = n + 1
		name = ("%s %d"):format(base, n)
	end
	return name
end
