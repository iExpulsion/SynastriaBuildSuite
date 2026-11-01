local _, NS = ...
local BF = NS.BF

BF.SLOT_NAMES = {
	"Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
	"Finger 1", "Finger 2", "Trinket 1", "Trinket 2", "Back", "Main Hand", "Off Hand", "Ranged",
}

function BF:FindBuild(name)
	local found
	if name and name ~= "" then
		local lower = name:lower()
		for key, build in pairs(self.db.builds) do
			if key:lower() == lower then found = build end
		end
	end
	return found
end

function BF:UniqueName(base)
	local name, n = base, 1
	while self.db.builds[name] do
		n = n + 1
		name = ("%s %d"):format(base, n)
	end
	return name
end

-- Tells an open window that builds or the character changed.
function BF:Changed()
	if self.Window and self.Window.Refresh then self.Window.Refresh() end
end

local function itemText(id)
	return select(2, GetItemInfo(id)) or ("item " .. id)
end

function BF:Report(plan)
	local p = plan.perks
	self:Print("Plan for |cffffffff%s|r (spec %d):", plan.build.name, plan.group)
	for _, id in ipairs(p.deactivate) do self:Print("  Perk off: %s", BF.Perks.Name(id)) end
	for _, id in ipairs(p.activate) do self:Print("  Perk on: %s", BF.Perks.Name(id)) end
	if p.needsInnkeeper and not BF.Perks.Writable() then
		self:Print("  |cffff6060Perk activations need the Perk window open at an innkeeper; they'll be skipped.|r")
	end
	if #p.options > 0 then self:Print("  Perk option changes: %d", #p.options) end
	for _, s in ipairs(p.spells) do
		self:Print("  %s ability: %s", BF.Perks.Name(s.id), GetSpellInfo(s.spell) or s.spell)
	end
	for _, s in ipairs(p.skipped) do self:Print("  |cffaaaaaaSkipped %s: %s|r", BF.Perks.Name(s.id), s.reason) end

	for _, entry in ipairs(plan.talents.classes) do
		if #entry.conflicts > 0 then
			self:Print("  |cffff6060%s talents: %d talent(s) have more points than the build; reset talents first.|r", entry.class, #entry.conflicts)
		elseif entry.points > 0 then
			local short = entry.points > entry.unspent and (" |cffff6060(only %d unspent)|r"):format(entry.unspent) or ""
			self:Print("  %s talents: %d point(s) to spend%s", entry.class, entry.points, short)
		end
	end
	for _, s in ipairs(plan.talents.skipped) do self:Print("  |cffaaaaaaSkipped %s talents: %s|r", s.class, s.reason) end

	for _, g in ipairs(plan.glyphs) do self:Print("  Glyph to socket yourself: %s", g.name) end
	if plan.pet then self:Print("  Pet aspects will change") end
	if plan.spec then self:Print("  Spec name: %s", plan.spec) end
end

-- Saves the character's current build under `name`, keeping notes and gear choices of a build it replaces.
function BF:SaveCurrent(name)
	local build, missed = BF.Build.Capture(name)
	local old = self.db.builds[name]
	if old then
		build.notes = old.notes
		build.gear = old.gear
	end
	self.db.builds[name] = build
	self:Print("Saved %s.", name)
	for _, class in ipairs(missed) do
		self:Print("|cffff6060Couldn't read %s talents; select it in the talent window and save again.|r", class)
	end
	self:Changed()
	return build
end

function BF:Rename(build, newName)
	local ok = newName ~= "" and not self.db.builds[newName]
	if ok then
		self.db.builds[build.name] = nil
		build.name = newName
		self.db.builds[newName] = build
		self:Changed()
	elseif newName ~= build.name then
		self:Print("|cffff6060A build named \"%s\" already exists.|r", newName)
	end
	return ok
end

-- Imports a pasted string. Calls onDone(build) once it's stored.
function BF:Import(text, onDone)
	local build, err = BF.Codec.Decode(text)
	if not build then
		self:Print("|cffff6060Import failed: %s.|r", err)
	else
		build.name = build.name or ("Imported " .. date("%Y-%m-%d %H:%M"))
		if not build.classes or #build.classes == 0 then build.classes = BF.Build.InferClasses(build) end
		local function store()
			self.db.builds[build.name] = build
			BF.Dialogs.HideText()
			self:Print("Imported %s.", build.name)
			self:Changed()
			if onDone then onDone(build) end
		end
		if self.db.builds[build.name] then
			BF.Dialogs.Confirm("BUILDFORGE_OVERWRITE", build.name, store)
		else
			store()
		end
	end
end

function BF:ConfirmApply(build)
	self:Report(BF.Build.Plan(build))
	BF.Dialogs.Confirm("BUILDFORGE_APPLY", build.name, function()
		local result = BF.Build.Apply(BF.Build.Plan(build))
		for _, r in ipairs(result.refused) do self:Print("|cffff6060Couldn't add %s (%s).|r", r.name, r.class) end
		self:Print("Applied %s.", build.name)
		self:Changed()
	end)
end

function BF:Export(build)
	BF.Dialogs.ShowExport(build.name, BF.Codec.Encode(build))
end

function BF:EquipGear(build)
	if InCombatLockdown() then
		self:Print("Can't change gear in combat.")
	else
		self:Print("Equipped %d item(s) from bags.", BF.Gear.EquipFromBags(build.gear))
	end
end

function BF:Delete(build)
	BF.Dialogs.Confirm("BUILDFORGE_DELETE", build.name, function()
		self.db.builds[build.name] = nil
		self:Print("Deleted %s.", build.name)
		self:Changed()
	end)
end

local function gear(build)
	for _, row in ipairs(BF.Gear.Status(build.gear)) do
		local parts = {}
		for _, item in ipairs(row.items) do
			local mark = item.equipped and "|cff60ff60worn|r" or item.inBags and "|cffffff60bags|r" or "|cffaaaaaamissing|r"
			local attune = item.attuned and "attuned" or ("%d%%"):format(item.progress or 0)
			parts[#parts + 1] = ("%s %s %s"):format(itemText(item.id), mark, attune)
		end
		BF:Print("  %s: %s", BF.SLOT_NAMES[row.slot] or row.slot, table.concat(parts, ", "))
	end
end

local function list()
	local names = {}
	for name in pairs(BF.db.builds) do names[#names + 1] = name end
	table.sort(names)
	if #names == 0 then BF:Print("No builds yet. /bforge save <name> saves your current one.") end
	for _, name in ipairs(names) do
		local b = BF.db.builds[name]
		local fits = BF.Build.Fits(b) and "" or " |cffaaaaaa(other classes)|r"
		BF:Print("  %s - %s%s", name, table.concat(b.classes or {}, "/"), fits)
	end
end

local function help()
	BF:Print("v%s commands (/bforge alone opens the window):", BF.version)
	BF:Print("  /bforge list | save <name> | apply <name> | export <name> | import")
	BF:Print("  /bforge gear <name> | equip <name> | delete <name> | note <name> <text>")
end

local handlers = {}

handlers[""] = function() BF.Window.Toggle() end
handlers.help = help
handlers.list = list
handlers.import = function() BF.Dialogs.ShowImport(function(text) BF:Import(text) end) end

handlers.save = function(arg)
	if arg == "" then
		BF:Print("Usage: /bforge save <name>")
	elseif BF.db.builds[arg] then
		BF.Dialogs.Confirm("BUILDFORGE_OVERWRITE", arg, function() BF:SaveCurrent(arg) end)
	else
		BF:SaveCurrent(arg)
	end
end

local function withBuild(fn)
	return function(arg)
		local build = BF:FindBuild(arg)
		if build then fn(build) else BF:Print("No build named \"%s\". /bforge list shows them.", arg) end
	end
end

handlers.apply = withBuild(function(build) BF:ConfirmApply(build) end)
handlers.gear = withBuild(gear)
handlers.export = withBuild(function(build) BF:Export(build) end)
handlers.equip = withBuild(function(build) BF:EquipGear(build) end)
handlers.delete = withBuild(function(build) BF:Delete(build) end)

handlers.note = function(arg)
	local name, text = arg:match("^(%S+)%s*(.*)$")
	local build = BF:FindBuild(name)
	if build then
		build.notes = text
		BF:Print("Notes for %s set.", build.name)
		BF:Changed()
	else
		BF:Print("Usage: /bforge note <name> <text>")
	end
end

SLASH_BUILDFORGE1 = "/bforge"
SLASH_BUILDFORGE2 = "/buildforge"
SlashCmdList.BUILDFORGE = function(msg)
	local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local handler = handlers[cmd:lower()]
	if handler then handler(arg) else help() end
end
