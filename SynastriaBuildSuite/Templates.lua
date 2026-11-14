local _, NS = ...
local SBS = NS.SBS

-- Templates: one tab of a build saved under a name, account-wide, to load into any build. SBS.db.templates[section]
-- [name] = { name, classes, data, ... }. Like an export, a template holds every class's part of the tab; loading
-- replaces only the template's classes' parts, so a one-class template leaves a two-class build's other class
-- alone. A Hunter's pet aspects come with perks. Gear and affixes fit any build.
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

-- The class a perk belongs to, or nil for the general categories any class can take.
local function perkClass(id)
	local perk = PerkMgrPerks and PerkMgrPerks[id]
	return perk and perk.cat <= 11 and SBS.CLASS_KEYS[perk.cat] or nil
end

-- The classes a per-class table (talents, glyphs) has something for, in the build's class order.
local function classesWith(build, byClass, has)
	local list, seen = {}, {}
	for _, class in ipairs(build.classes or {}) do
		if not seen[class] and byClass[class] and has(byClass[class]) then
			seen[class] = true
			list[#list + 1] = class
		end
	end
	return list
end

local function classText(classes)
	return #classes > 0 and SBS.Window.ClassText(classes, true) or "General"
end

-- Per-class sections (build[field][class]) fit a build that has each of the template's classes, and loading
-- replaces only those classes. count(value) sizes one class's part for the summary, in `unit`s; enough(value,
-- build, class) may give a reason it doesn't fit.
local function perClass(field, count, unit, enough)
	local function has(value) return count(value) > 0 end
	return {
		take = function(build)
			local classes = classesWith(build, build[field] or {}, has)
			local data = {}
			for _, class in ipairs(classes) do data[class] = copy(build[field][class]) end
			return #classes > 0 and { classes = classes, data = data } or nil
		end,
		fits = function(t, build)
			local reason
			for _, class in ipairs(t.classes) do
				if not hasClass(build, class) then
					reason = reason or ("Needs " .. className(class))
				elseif enough then
					reason = reason or enough(t.data[class], build, class)
				end
			end
			return reason == nil, reason
		end,
		load = function(t, build)
			build[field] = build[field] or {}
			for _, class in ipairs(t.classes) do build[field][class] = copy(t.data[class]) end
		end,
		describe = function(t)
			local n = 0
			for _, class in ipairs(t.classes) do n = n + count(t.data[class]) end
			return classText(t.classes) .. ", " .. SBS.Style.Count(n, unit)
		end,
	}
end

local function glyphCount(sockets)
	local n = 0
	for _ in pairs(sockets) do n = n + 1 end
	return n
end

KINDS.talents = perClass("talents", SBS.TalentCalc.TotalPoints, "Point", function(trees, build, class)
	local points = SBS.TalentCalc.TotalPoints(trees)
	return points > SBS.TalentCalc.MaxPoints(build, class) and ("Needs %d %s Points"):format(points, className(class)) or nil
end)

KINDS.glyphs = perClass("glyphs", glyphCount, "Glyph")

-- Perks keep every class's perks in one template, like an export. One fits a build whose classes can use each of
-- its perks, and replaces the build's general perks and the class perks of the classes it has perks for.
KINDS.perks = {
	take = function(build)
		local classes, seen = {}, {}
		for _, w in ipairs(build.perks or {}) do
			local class = perkClass(w.id)
			if class and not seen[class] then
				seen[class] = true
				classes[#classes + 1] = class
			end
		end
		return #(build.perks or {}) > 0 and { classes = classes, data = copy(build.perks), pet = build.pet } or nil
	end,
	fits = function(t, build)
		local mask, reason = SBS.Perks.ClassMask(build.classes), nil
		for _, w in ipairs(t.data) do
			local perk = PerkMgrPerks and PerkMgrPerks[w.id]
			if not reason and perk and not SBS.Perks.UsableFor(perk, mask) then
				local class = perkClass(w.id)
				reason = class and ("Needs " .. className(class)) or ("Can't Use " .. (perk.name or "a Perk"))
			end
		end
		return reason == nil, reason
	end,
	load = function(t, build)
		local replaced, kept = {}, {}
		for _, class in ipairs(t.classes) do replaced[class] = true end
		for _, w in ipairs(build.perks or {}) do
			local perk = PerkMgrPerks and PerkMgrPerks[w.id]
			local class = perkClass(w.id)
			local goes = perk ~= nil and (class == nil or replaced[class] == true)
			if not goes then kept[#kept + 1] = w end
		end
		for _, w in ipairs(copy(t.data)) do kept[#kept + 1] = w end
		table.sort(kept, function(a, b) return a.id < b.id end)
		build.perks = kept
		build.perksPending = nil
		if t.pet then build.pet = t.pet end
	end,
	describe = function(t)
		return classText(t.classes) .. ", " .. SBS.Style.Count(#t.data, "Perk")
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

-- Whether the build has anything in the section to save.
function Templates.CanSave(section, build)
	return KINDS[section].take(build) ~= nil
end

-- Saves the build's section under `name`, replacing a template of that name. Returns it, or nil with nothing to save.
function Templates.Save(section, name, build)
	local t = KINDS[section].take(build)
	if t then
		t.name = name
		store(section)[name] = t
	end
	return t
end

function Templates.Fits(section, t, build)
	return KINDS[section].fits(t, build)
end

-- The build fields each section's load can change, kept so the last load can be undone.
local FIELDS = {
	perks = { "perks", "pet", "perksPending" }, talents = { "talents" }, glyphs = { "glyphs" },
	gear = { "gear" }, affixes = { "affixes" },
}

-- Replaces the build's section (for its classes, as above) with the template's, remembering what it had for
-- Undo. Returns whether it fit.
function Templates.Load(section, t, build)
	local ok = KINDS[section].fits(t, build)
	if ok then
		local saved = {}
		for _, field in ipairs(FIELDS[section]) do saved[field] = copy(build[field]) end
		Templates.last = { section = section, build = build, name = t.name, saved = saved }
		KINDS[section].load(t, build)
	end
	return ok
end

-- The name of the template last loaded into this build's section, while it can still be undone.
function Templates.Undoable(section, build)
	local last = Templates.last
	return last and last.section == section and last.build == build and last.name or nil
end

-- Puts the build's section back as it was before the last load. Returns the template's name, or nil.
function Templates.Undo()
	local last = Templates.last
	if last then
		for _, field in ipairs(FIELDS[last.section]) do last.build[field] = last.saved[field] end
		Templates.last = nil
	end
	return last and last.name
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
