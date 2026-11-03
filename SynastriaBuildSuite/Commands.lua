local _, NS = ...
local SBS = NS.SBS

SBS.SLOT_NAMES = {
	"Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
	"Finger 1", "Finger 2", "Trinket 1", "Trinket 2", "Back", "Main Hand", "Off Hand", "Ranged",
}

function SBS:FindBuild(name)
	local found
	if name and name ~= "" then
		local lower = name:lower()
		for key, build in pairs(self.db.builds) do
			if key:lower() == lower then found = build end
		end
	end
	return found
end

function SBS:UniqueName(base)
	local name, n = base, 1
	while self.db.builds[name] do
		n = n + 1
		name = ("%s %d"):format(base, n)
	end
	return name
end

-- Tells an open window that builds or the character changed.
function SBS:Changed()
	if self.Window and self.Window.Refresh then self.Window.Refresh() end
end

local function itemText(id)
	return select(2, GetItemInfo(id)) or ("item " .. id)
end

function SBS:Report(plan)
	local p = plan.perks
	self:Print("Plan for |cffffffff%s|r (spec %d):", plan.build.name, plan.group)
	for _, id in ipairs(p.deactivate) do self:Print("  Perk off: %s", SBS.Perks.Name(id)) end
	for _, id in ipairs(p.activate) do self:Print("  Perk on: %s", SBS.Perks.Name(id)) end
	if p.needsInnkeeper and not SBS.Perks.Writable() then
		self:Print("  |cffff6060Perk activations need the Perk Manager open at an innkeeper; they'll be skipped.|r")
	end
	if #p.options > 0 then self:Print("  Perk option changes: %d", #p.options) end
	for _, s in ipairs(p.spells) do
		self:Print("  %s ability: %s", SBS.Perks.Name(s.id), GetSpellInfo(s.spell) or s.spell)
	end
	for _, s in ipairs(p.skipped) do self:Print("  |cffaaaaaaSkipped %s: %s|r", SBS.Perks.Name(s.id), s.reason) end

	for _, entry in ipairs(plan.talents.classes) do
		if #entry.conflicts > 0 then
			self:Print("  |cffff6060%s talents: %s more points than the build; reset talents first.|r", entry.class,
				SBS.Style.Count(#entry.conflicts, "talent has", "talents have"))
		elseif entry.points > 0 then
			local short = entry.points > entry.unspent and (" |cffff6060(only %d unspent)|r"):format(entry.unspent) or ""
			self:Print("  %s talents: %s to spend%s", entry.class, SBS.Style.Count(entry.points, "point"), short)
		end
	end
	for _, s in ipairs(plan.talents.skipped) do self:Print("  |cffaaaaaaSkipped %s talents: %s|r", s.class, s.reason) end

	for _, g in ipairs(plan.glyphs) do self:Print("  Glyph to socket yourself: %s", g.name) end
	if plan.pet then self:Print("  Pet aspects will change") end
	if plan.spec then self:Print("  Spec name: %s", plan.spec) end
end

-- Stores a captured build; the first save that reads perks also fills an empty Shared Perks list.
local function saveBuild(self, build, missed, readPerks)
	if readPerks and #self.db.shared.perks == 0 then
		local _, misc = SBS.Perks.Split(SBS.Perks.Capture())
		SBS.Perks.AddShared(misc)
	end
	self.db.builds[build.name] = build
	self:Print("Saved %s.", build.name)
	for _, class in ipairs(missed) do
		self:Print("|cffff6060Couldn't read %s talents; select it in the talent window and save again.|r", class)
	end
	self:Changed()
	return build
end

-- Saves the character's current build under `name`, keeping notes and gear choices of a build it replaces.
function SBS:SaveCurrent(name)
	local build, missed = SBS.Build.Capture(name)
	local old = self.db.builds[name]
	if old then
		build.notes = old.notes
		build.gear = old.gear
	end
	return saveBuild(self, build, missed, true)
end

-- Saves a new build for `classes` with the checked sections of the character (see Build.New).
function SBS:SaveNew(name, classes, sections)
	local build, missed = SBS.Build.New(name, classes, sections)
	return saveBuild(self, build, missed, sections.perks)
end

-- Saves every spec on this character as a build linked to it. A spec's linked build is refreshed (keeping its name,
-- notes and gear, and its perks unless the spec is active); other specs get a new build named after the spec.
-- Specs other than the active one can't show their perks, so their new builds fill them in on first switching.
function SBS:SaveAllSpecs()
	local links, active, waiting, saved = self:Links(), self:ActiveGroup(), {}, 0
	if #self.db.shared.perks == 0 then
		local _, misc = SBS.Perks.Split(SBS.Perks.Capture())
		SBS.Perks.AddShared(misc)
	end
	for group = 1, self:SpecCount() do
		local old = links[group] and self.db.builds[links[group]]
		local label = GetCustomGameDataString and GetCustomGameDataString(21, group) or ""
		local name = old and old.name or self:UniqueName(label ~= "" and label or ("Spec " .. group))
		local build, missed = SBS.Build.Capture(name, group)
		if old then
			build.notes, build.gear = old.notes, old.gear
			if group ~= active then build.perks, build.pet, build.perksPending = old.perks, old.pet, old.perksPending end
		end
		if build.perksPending then waiting[#waiting + 1] = "Spec " .. group end
		for _, class in ipairs(missed) do
			self:Print("|cffff6060Couldn't read %s talents for Spec %d; select it in the talent window and try again.|r",
				class, group)
		end
		self.db.builds[name] = build
		links[group] = name
		saved = saved + 1
	end
	self:Print("Saved %s, each linked to its spec.", SBS.Style.Count(saved, "spec"))
	if #waiting > 0 then
		self:Print("Switch to %s to fill in %s perks.", table.concat(waiting, ", "), #waiting > 1 and "their" or "its")
	end
	self:Changed()
	return saved
end

-- Fills in the perks of the active spec's linked build if it's still waiting for them. Called a moment after a
-- spec switch, once the server has sent the new spec's perks.
function SBS:FillPendingSpec()
	local group = self:ActiveGroup()
	local build = self.db.builds[self:Links()[group] or ""]
	if build and build.perksPending then
		SBS.Build.FillPending(build)
		self:Print("Filled in %s's perks from Spec %d.", build.name, group)
		self:Changed()
	end
end

function SBS:Rename(build, newName)
	local ok = newName ~= "" and not self.db.builds[newName]
	if ok then
		self.db.builds[build.name] = nil
		self:RenameLinks(build.name, newName)
		build.name = newName
		self.db.builds[newName] = build
		self:Changed()
	elseif newName ~= build.name then
		self:Print("|cffff6060A build named \"%s\" already exists.|r", newName)
	end
	return ok
end

local function sectionNames(sections)
	local names = {}
	for _, section in ipairs(SBS.Codec.SECTIONS) do
		if sections[section.key] then names[#names + 1] = section.label end
	end
	return table.concat(names, ", ")
end

-- Imports a pasted string, keeping only the chosen sections ({ key = true }, nil for all). With `into`, those
-- sections replace the same sections of that build instead of making a new one; otherwise the new build is
-- called `name` (default: the string's). Calls onDone(build) once stored.
function SBS:Import(text, onDone, sections, into, name)
	local decoded, err = SBS.Codec.Decode(text)
	if not decoded then
		self:Print("|cffff6060Import failed: %s.|r", err)
	else
		local has = SBS.Codec.Has(decoded)
		local build = SBS.Codec.Pick(decoded, sections)
		if into then
			-- only sections the string has replace the build's, so a talents-only string leaves the rest alone
			local replaced = {}
			for _, section in ipairs(SBS.Codec.SECTIONS) do
				if has[section.key] and (not sections or sections[section.key]) then
					replaced[section.key] = true
					for _, field in ipairs(section.fields) do into[field] = build[field] end
				end
			end
			if not into.classes or #into.classes == 0 then into.classes = build.classes end
			SBS.Dialogs.HideText()
			self:Print("Imported %s into %s.", sectionNames(replaced), into.name)
			self:Changed()
			if onDone then onDone(into) end
		else
			build.name = name or build.name or ("Imported " .. date("%Y-%m-%d %H:%M"))
			if not build.classes or #build.classes == 0 then build.classes = SBS.Build.InferClasses(build) end
			local function store()
				self.db.builds[build.name] = build
				SBS.Dialogs.HideText()
				self:Print("Imported %s.", build.name)
				self:Changed()
				if onDone then onDone(build) end
			end
			if self.db.builds[build.name] then
				SBS.Dialogs.Confirm("SBS_OVERWRITE", build.name, store)
			else
				store()
			end
		end
	end
end

function SBS:ConfirmApply(build)
	self:Report(SBS.Build.Plan(build))
	SBS.Dialogs.Confirm("SBS_APPLY", build.name, function()
		local result = SBS.Build.Apply(SBS.Build.Plan(build))
		for _, r in ipairs(result.refused) do self:Print("|cffff6060Couldn't add %s (%s).|r", r.name, r.class) end
		self:Print("Applied %s.", build.name)
		self:Changed()
	end)
end

-- Shared perks are personal setup, so exports leave them out. The export box picks which sections go.
function SBS:Export(build)
	SBS.Dialogs.ShowExport(build)
end

function SBS:EquipGear(build)
	if InCombatLockdown() then
		self:Print("Can't change gear in combat.")
	else
		self:Print("Equipped %s from bags.", SBS.Style.Count(SBS.Gear.EquipFromBags(build.gear), "item"))
	end
end

local function copy(value)
	local out = value
	if type(value) == "table" then
		out = {}
		for k, v in pairs(value) do out[k] = copy(v) end
	end
	return out
end

-- A full copy under a new name ("Name Copy", numbered if taken). It isn't linked to any spec.
function SBS:Duplicate(build)
	local dup = copy(build)
	dup.name = self:UniqueName(build.name .. " Copy")
	-- an unlinked copy has no spec to fill its perks from
	dup.perksPending = nil
	self.db.builds[dup.name] = dup
	self:Print("Duplicated %s as %s.", build.name, dup.name)
	self:Changed()
	return dup
end

function SBS:Delete(build)
	SBS.Dialogs.Confirm("SBS_DELETE", build.name, function()
		self.db.builds[build.name] = nil
		self:RenameLinks(build.name, nil)
		self:Print("Deleted %s.", build.name)
		self:Changed()
	end)
end

local function gear(build)
	for _, row in ipairs(SBS.Gear.Status(build.gear)) do
		local parts = {}
		for _, item in ipairs(row.items) do
			local mark = item.equipped and "|cff60ff60worn|r" or item.inBags and "|cffffff60bags|r" or "|cffaaaaaamissing|r"
			parts[#parts + 1] = ("%s %s"):format(itemText(item.id), mark)
		end
		SBS:Print("  %s: %s", SBS.SLOT_NAMES[row.slot] or row.slot, table.concat(parts, ", "))
	end
end

local function list()
	local names = {}
	for name in pairs(SBS.db.builds) do names[#names + 1] = name end
	table.sort(names)
	if #names == 0 then SBS:Print("No builds yet. /sbs save <name> saves your current one.") end
	for _, name in ipairs(names) do
		local b = SBS.db.builds[name]
		local fits = SBS.Build.Fits(b) and "" or " |cffaaaaaa(other classes)|r"
		SBS:Print("  %s - %s%s", name, table.concat(b.classes or {}, "/"), fits)
	end
end

local function help()
	SBS:Print("v%s commands (/sbs alone opens the window):", SBS.version)
	SBS:Print("  /sbs list | save <name> | specs | apply <name> | export <name> | import")
	SBS:Print("  /sbs gear <name> | equip <name> | delete <name> | note <name> <text> | minimap | reset")
end

local handlers = {}

handlers[""] = function() SBS.Window.Toggle() end
handlers.help = help
handlers.list = list
handlers.specs = function() SBS:SaveAllSpecs() end
handlers.import = function()
	SBS.Dialogs.ShowImport(function(text, sections, _, name) SBS:Import(text, nil, sections, nil, name) end)
end

handlers.save = function(arg)
	if arg == "" then
		SBS:Print("Usage: /sbs save <name>")
	elseif SBS.db.builds[arg] then
		SBS.Dialogs.Confirm("SBS_OVERWRITE", arg, function() SBS:SaveCurrent(arg) end)
	else
		SBS:SaveCurrent(arg)
	end
end

local function withBuild(fn)
	return function(arg)
		local build = SBS:FindBuild(arg)
		if build then fn(build) else SBS:Print("No build named \"%s\". /sbs list shows them.", arg) end
	end
end

handlers.apply = withBuild(function(build) SBS:ConfirmApply(build) end)
handlers.gear = withBuild(gear)
handlers.export = withBuild(function(build) SBS:Export(build) end)
handlers.equip = withBuild(function(build) SBS:EquipGear(build) end)
handlers.delete = withBuild(function(build) SBS:Delete(build) end)

handlers.checktalents = function()
	local problems, class = SBS.TalentCalc.CheckLive()
	if #problems == 0 then
		SBS:Print("Talent data matches the live %s talents.", tostring(class))
	else
		SBS:Print("|cffff6060%d talent data mismatch(es) for %s:|r", #problems, tostring(class))
		for i = 1, math.min(#problems, 10) do SBS:Print("  %s", problems[i]) end
	end
end

handlers.minimap = function() SBS.MinimapButton.Toggle() end
handlers.reset = function()
	SBS.Window.ResetPosition()
	SBS:Print("Window moved back to the center of the screen.")
end

handlers.note = function(arg)
	local name, text = arg:match("^(%S+)%s*(.*)$")
	local build = SBS:FindBuild(name)
	if build then
		build.notes = text
		SBS:Print("Notes for %s set.", build.name)
		SBS:Changed()
	else
		SBS:Print("Usage: /sbs note <name> <text>")
	end
end

SLASH_SBS1 = "/sbs"
SLASH_SBS2 = "/buildsuite"
SlashCmdList.SBS = function(msg)
	local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local handler = handlers[cmd:lower()]
	if handler then handler(arg) else help() end
end

-- The server sends a spec's perks after the switch (and after login), so a pending build is filled a moment later,
-- once the perk list is there.
local PENDING_DELAY = 2
local pendingWatch = CreateFrame("Frame")
pendingWatch:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
pendingWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
pendingWatch:SetScript("OnEvent", function(self) self.wait = PENDING_DELAY end)
pendingWatch:SetScript("OnUpdate", function(self, elapsed)
	if self.wait then
		self.wait = self.wait - elapsed
		if self.wait <= 0 and PerkMgrPerks then
			self.wait = nil
			SBS:FillPendingSpec()
		elseif self.wait <= 0 then
			self.wait = PENDING_DELAY
		end
	end
end)
