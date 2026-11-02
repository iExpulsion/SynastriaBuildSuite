local _, NS = ...
local BF = NS.BF

-- The build window: a movable flat panel with a searchable build sidebar on the left and the selected build on
-- the right (header with the main actions, tabs with difference badges, the tab's content and a footer).
-- Sized so Phase 2's three-tree talent editor fits beside the sidebar.
local Window = {}
BF.Window = Window

local S = BF.Style
local C = S.colors

local W, H = 900, 640
local TITLE_H, SIDEBAR_W, BUILD_H, TABS_H, FOOTER_H = 36, 240, 78, 32, 46
local TABS = {
	{ key = "perks", label = "Perks" },
	{ key = "talents", label = "Talents" },
	{ key = "glyphs", label = "Glyphs" },
	{ key = "gear", label = "Gear" },
	{ key = "notes", label = "Notes" },
}

local frame
local SPECS_KEY = "\1specs"
local CLASSES_W = 150
-- Tabs whose comparison depends on the active spec (gear and bags are the same in every spec).
local PER_SPEC = { perks = true, talents = true, glyphs = true }
-- The editor module behind each tab except Notes.
local EDITORS = { perks = "PerkEditor", talents = "TalentEditor", glyphs = "GlyphEditor", gear = "GearEditor" }
local state = { selected = nil, tab = "perks", collapsed = {}, search = "" }
Window.state = state

local function setShown(f, shown)
	if shown then f:Show() else f:Hide() end
end

local function className(key)
	return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[key] or key
end

-- Synastria's name and color for a two-class pair: the name from BF:ComboName, or else from the client (as its
-- Character window does, with the pair packed as first class ID << 8 | second), and the client's color.
local function comboName(classes)
	local a, b = BF.CLASS_IDS[classes[1]], BF.CLASS_IDS[classes[2]]
	local name, r, g, bl
	if #classes == 2 and a and b then
		local pack = a * 256 + b
		name = BF:ComboName(classes[1], classes[2]) or (CMCGetClassNameFromPack and CMCGetClassNameFromPack(pack))
		if CMCGetClassNameColor then r, g, bl = CMCGetClassNameColor(pack) end
	end
	return name ~= "" and name or nil, r, g, bl
end

-- Class names in class colors, or plain: Synastria's name for a two-class pair, otherwise each class, with a class
-- picked twice shown once with a count.
function Window.ClassText(classes, plain)
	local combo, r, g, b = comboName(classes or {})
	if combo then
		return (not plain and r) and ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, combo) or combo
	end
	local order, copies = {}, {}
	for _, key in ipairs(classes or {}) do
		if not copies[key] then order[#order + 1] = key end
		copies[key] = (copies[key] or 0) + 1
	end
	local parts = {}
	for _, key in ipairs(order) do
		local c = not plain and RAID_CLASS_COLORS[key]
		local name = className(key) .. (copies[key] > 1 and (" x" .. copies[key]) or "")
		parts[#parts + 1] = c and ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name) or name
	end
	return table.concat(parts, " / ")
end

-- state.selected is a build name, or SHARED for the Shared Perks entry.
local SHARED = "\1shared"

local function selectedBuild()
	return state.selected == SHARED and BF.Build.SHARED or state.selected and BF.db.builds[state.selected]
end

-- The spec to switch to for a build, when it's linked and none of its specs is active.
function Window.SpecToSwitch(build)
	local groups = BF:LinkedSpecs(build.name)
	local target = groups[1]
	for _, g in ipairs(groups) do if g == BF:ActiveGroup() then target = nil end end
	return target
end

-- Perks, talents and glyphs belong to the active spec, so a build linked to another spec isn't compared with the
-- character: the tabs drop their badges and statuses until that spec is active. Archived builds always compare.
function Window.IsComparing(build)
	return Window.SpecToSwitch(build) == nil
end

function Window.InactiveNote(build)
	local target = Window.SpecToSwitch(build)
	return S.Hex(C.warn, ("Spec %d Isn't Active, so Nothing Is Compared"):format(target))
end

function Window.SwitchSpec(group)
	if InCombatLockdown() then
		Window.Message(S.Hex(C.bad, "Can't Switch Specs in Combat"))
	else
		SetActiveTalentGroup(group)
		Window.Message(S.Hex(C.muted, "Switching to " .. BF:SpecName(group) .. "..."))
	end
end

function Window.Select(name)
	state.selected = name
	state.message = nil
	if frame then frame.review:Hide() end
	Window.Render()
end

-- Sidebar --------------------------------------------------------------------------------------------------

local function matches(build)
	local q = state.search
	return q == "" or build.name:lower():find(q, 1, true) ~= nil or (build.spec or ""):lower():find(q, 1, true) ~= nil
end

-- This character's specs that have a linked build, in spec order: { group, build }.
local function linkedSpecs()
	local rows, links = {}, BF:Links()
	for g = 1, BF:SpecCount() do
		local build = links[g] and BF.db.builds[links[g]]
		if build and matches(build) then rows[#rows + 1] = { group = g, build = build } end
	end
	return rows
end

-- The other builds, grouped by class combination; groups that fit the character come first and start expanded.
local function groupedBuilds()
	local groups, byKey = {}, {}
	for _, build in pairs(BF.db.builds) do
		if matches(build) and #BF:LinkedSpecs(build.name) == 0 then
			local key = table.concat(build.classes or {}, "/")
			local group = byKey[key]
			if not group then
				group = { key = key, classes = build.classes or {}, fits = BF.Build.Fits(build), builds = {} }
				byKey[key] = group
				groups[#groups + 1] = group
			end
			table.insert(group.builds, build)
		end
	end
	for _, group in ipairs(groups) do
		table.sort(group.builds, function(a, b) return a.name:lower() < b.name:lower() end)
	end
	table.sort(groups, function(a, b)
		if a.fits ~= b.fits then return a.fits end
		return a.key < b.key
	end)
	return groups
end

local function isCollapsed(group)
	local c = state.collapsed[group.key]
	if c == nil then c = not group.fits end
	return c and state.search == ""
end

local function renderSidebar()
	local list = frame.list
	local first, firstFit, shown = nil, nil, 0
	list:Begin()

	if matches(BF.Build.SHARED) then
		list:Add({
			text = "Shared Perks", sub = "Misc perks, in every build",
			status = S.Hex(C.muted, #BF.db.shared.perks),
			selected = state.selected == SHARED,
			onClick = function() Window.Select(SHARED) end,
			tooltip = function(tt)
				tt:AddLine("Shared Perks", 1, 1, 1)
				tt:AddLine("Misc perks belong to each spec, so they're kept in one list that every build applies along with its own perks. Apply them here to fill in a spec on their own.", 0.8, 0.8, 0.8, true)
			end,
		})
	end

	local specs = linkedSpecs()
	if #specs > 0 then
		local collapsed = state.collapsed[SPECS_KEY] == true and state.search == ""
		list:Add({
			text = "Your Specs", header = true, collapsed = collapsed,
			status = S.Hex(C.muted, #specs),
			onClick = function()
				state.collapsed[SPECS_KEY] = not collapsed
				Window.Render()
			end,
			tooltip = function(tt)
				tt:AddLine("Your Specs", 1, 1, 1)
				tt:AddLine("Builds linked to this character's talent specs, in spec order. Apply a build, or pick a spec in its Linked to menu, to add it here.", 0.8, 0.8, 0.8, true)
			end,
		})
		for _, row in ipairs(specs) do
			local build, active = row.build, row.group == BF:ActiveGroup()
			if active or not firstFit then firstFit = build end
			first = first or build
			if not collapsed then
				shown = shown + 1
				local spec = build.spec or ""
				list:Add({
					text = S.Hex(active and C.good or C.muted, row.group) .. "   " .. build.name,
					sub = spec ~= "" and spec ~= build.name and spec or nil,
					status = active and S.Hex(C.good, "Active") or nil,
					indent = 12,
					selected = build.name == state.selected,
					onClick = function() Window.Select(build.name) end,
				})
			end
		end
	end

	-- under a Saved Builds heading, class groups sit one step in so they read as part of it
	local groups = groupedBuilds()
	local nested = #specs > 0 and #groups > 0
	if nested then
		local saved = 0
		for _, group in ipairs(groups) do saved = saved + #group.builds end
		list:Add({
			text = "Saved Builds", header = true, indent = 16,
			status = S.Hex(C.muted, saved),
			tooltip = function(tt)
				tt:AddLine("Saved Builds", 1, 1, 1)
				tt:AddLine("Builds not linked to a spec on this character: templates, shared builds and other classes'. Applying one links it to your active spec.", 0.8, 0.8, 0.8, true)
			end,
		})
	end
	for _, group in ipairs(groups) do
		local collapsed = isCollapsed(group)
		local label = group.key == "" and "No Class" or Window.ClassText(group.classes, not group.fits)
		list:Add({
			text = label,
			status = S.Hex(C.muted, #group.builds),
			header = true, collapsed = collapsed, indent = nested and 12 or 0,
			onClick = function()
				state.collapsed[group.key] = not collapsed
				Window.Render()
			end,
			tooltip = not group.fits and function(tt)
				tt:AddLine(Window.ClassText(group.classes), 1, 1, 1)
				tt:AddLine("Not your classes. You can view and share these builds; only the parts for your classes apply.", 0.8, 0.8, 0.8, true)
			end or nil,
		})
		for _, build in ipairs(group.builds) do
			first = first or build
			if group.fits then firstFit = firstFit or build end
			if not collapsed then
				shown = shown + 1
				local spec = build.spec or ""
				list:Add({
					text = build.name,
					sub = spec ~= "" and spec ~= build.name and spec or nil,
					indent = nested and 24 or 12,
					selected = build.name == state.selected,
					onClick = function() Window.Select(build.name) end,
				})
			end
		end
	end
	list:End()

	if not selectedBuild() then
		local pick = firstFit or first
		state.selected = pick and pick.name or nil
	end
	setShown(frame.noMatches, state.search ~= "" and first == nil)
end

-- Main pane ------------------------------------------------------------------------------------------------

local function renderTabs(build)
	local comparing = Window.IsComparing(build)
	for i, tab in ipairs(TABS) do
		local b = frame.tabs[i]
		local selected = tab.key == state.tab
		setShown(b, not build.sharedOnly or tab.key == "perks")
		b.label:SetTextColor(unpack(selected and C.text or C.muted))
		setShown(b.underline, selected)
		local diff = (comparing or not PER_SPEC[tab.key]) and BF.Tabs.diff[tab.key] and BF.Tabs.diff[tab.key](build)
		if diff and diff > 0 then
			b.badge:SetText(diff)
			b.badgeBg:SetWidth(b.badge:GetStringWidth() + 10)
			b.badgeBg:Show()
			b.badge:Show()
		else
			b.badgeBg:Hide()
			b.badge:Hide()
		end
		b:SetWidth(b.label:GetStringWidth() + (diff and diff > 0 and (b.badge:GetStringWidth() + 26) or 0) + 28)
	end
	setShown(frame.notes, state.tab == "notes")
	for key, editor in pairs(frame.editors) do setShown(editor, key == state.tab) end
end

local function renderActions(build)
	local actions = BF.Tabs.actions[state.tab] or {}
	for i, b in ipairs(frame.actions) do
		local action = actions[i]
		if action then
			b:SetLabel(action.label)
			b:SetScript("OnClick", function() action.run(build) end)
			b.tooltipText = action.tooltip
			b:Show()
		else
			b:Hide()
		end
	end
end

local function renderInnkeeper()
	local at = BF.Perks.Writable()
	frame.innDot:SetVertexColor(unpack(at and C.good or C.muted))
	frame.innText:SetText(at and "Perk Manager Open at an Innkeeper" or "Perk Activations Need an Innkeeper")
	frame.innText:SetTextColor(unpack(at and C.good or C.muted))
end

local function renderSpecLink(build)
	local count = build.sharedOnly and 1 or BF:SpecCount()
	local groups = BF:LinkedSpecs(build.name)
	local options = { { value = 0, text = "Not Linked", tooltip = "Don't tie this build to a spec on this character." } }
	for g = 1, count do
		local other = BF:Links()[g]
		local tip = other and other ~= build.name and ("Linked to " .. other .. " now; picking it moves that link here.") or nil
		options[#options + 1] = { value = g, text = BF:SpecName(g) .. (g == BF:ActiveGroup() and " (Active)" or ""), tooltip = tip }
	end
	frame.specLink:SetOptions(options)
	local label = #groups == 0 and "Not Linked" or BF:SpecName(groups[1])
	if #groups > 1 then label = label .. (" +%d"):format(#groups - 1) end
	frame.specLink:SetText(label)
	frame.specLinkLabel:SetText(#groups == 0 and "Assign to" or "Linked to")
	setShown(frame.specLink, count > 1)
	setShown(frame.specLinkLabel, count > 1)
	local target = Window.SpecToSwitch(build)
	frame.apply.target = target
	frame.apply:SetLabel(target and ("Switch to Spec %d"):format(target) or build.sharedOnly and "Apply Perks" or "Apply Build")
	frame.apply.tooltipText = target and "Activate this build's spec. It takes a few seconds and can't be done in combat."
		or build.sharedOnly and "Turn your active spec's Misc perks on or off to match Shared Perks. Other perks aren't touched."
		or "Review what would change on your character, then apply it."
	setShown(frame.specActive, count > 1 and #groups > 0 and target == nil)
end

local function renderBuild(build)
	frame.name.committed = build.name
	frame.spec.committed = build.spec or ""
	if not frame.name.focused then frame.name:SetText(build.name) end
	if not frame.spec.focused then
		frame.spec:SetText(build.spec or "")
		frame.spec:UpdatePlaceholder()
	end
	local shared = build.sharedOnly == true
	if shared then state.tab = "perks" end
	-- GetStringWidth is limited by the current width, so open it up before measuring; then cap the classes so they
	-- can never push Spec Name and Linked to off the header
	frame.classes:SetWidth(1000)
	frame.classes:SetText(shared and S.Hex(C.muted, "Misc perks every build applies, in every spec. Not included in exports.")
		or Window.ClassText(build.classes))
	local width = frame.classes:GetStringWidth() + 4
	frame.classes:SetWidth(shared and width or math.min(width, CLASSES_W))
	frame.name:EnableMouse(not shared)
	for _, w in ipairs({ frame.spec, frame.specLabel, frame.export, frame.duplicate, frame.delete }) do setShown(w, not shared) end
	renderSpecLink(build)
	renderTabs(build)
	renderActions(build)
	if state.tab == "notes" then
		if not frame.notes.edit.focused then frame.notes.edit:SetText(build.notes or "") end
		frame.summary:SetText(state.message or "")
	else
		local summary = BF[EDITORS[state.tab]].Render(build)
		if PER_SPEC[state.tab] and not Window.IsComparing(build) then summary = Window.InactiveNote(build) end
		frame.summary:SetText(state.message or summary or "")
	end
end

function Window.Render()
	if frame and frame:IsShown() then
		frame.dirty = false
		renderSidebar()
		renderInnkeeper()
		local build = selectedBuild()
		setShown(frame.main, build ~= nil)
		setShown(frame.empty, build == nil and next(BF.db.builds) == nil)
		if build then renderBuild(build) end
		if frame.review:IsShown() then BF.Review.Render() end
	end
end

-- Coalesces bursts of events (bag updates) into one render per frame.
function Window.Refresh()
	if frame then frame.dirty = true end
end

-- Shows a one-off status message in the footer until the next tab or build change.
function Window.Message(text)
	state.message = text
	Window.Render()
end

-- Construction ---------------------------------------------------------------------------------------------

local function newBuild()
	local build = BF:SaveCurrent(BF:UniqueName("New Build"))
	state.search = ""
	frame.search:SetText("")
	Window.Select(build.name)
end

-- Import offers to bring sections into the selected build as well as making a new one.
local function importBuild()
	local target = selectedBuild()
	if target and target.sharedOnly then target = nil end
	BF.Dialogs.ShowImport(function(text, sections, into, name)
		BF:Import(text, function(build)
			state.collapsed[table.concat(build.classes or {}, "/")] = false
			Window.Select(build.name)
		end, sections, into and target or nil, name)
	end, target and target.name)
end

local function savePosition(f)
	local point, _, relPoint, x, y = f:GetPoint()
	BF.db.window = { point = point, relPoint = relPoint, x = x, y = y }
end

local function createTitleBar(f)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(TITLE_H)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() f:StartMoving() end)
	bar:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		savePosition(f)
	end)
	S.Rule(bar, "BOTTOM")

	local title = S.Text(bar, "normal")
	title:SetPoint("LEFT", 14, 0)
	title:SetText(S.Hex(C.accent, "Build") .. "Forge")
	local version = S.Text(bar, "small", C.muted)
	version:SetPoint("LEFT", title, "RIGHT", 8, -1)
	version:SetText("v" .. BF.version)

	local close = S.Button(bar, "Close", "ghost", 56, function() f:Hide() end)
	close:SetPoint("RIGHT", -8, 0)

	f.innText = S.Text(bar, "small", C.muted)
	f.innText:SetPoint("RIGHT", close, "LEFT", -12, 0)
	f.innDot = S.Solid(bar, "ARTWORK", C.muted)
	f.innDot:SetSize(8, 8)
	f.innDot:SetPoint("RIGHT", f.innText, "LEFT", -6, 0)
end

local function createSidebar(f)
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", 0, -TITLE_H)
	side:SetPoint("BOTTOMLEFT")
	side:SetWidth(SIDEBAR_W)
	S.Panel(side, C.sidebar)
	local edge = S.Solid(side, "BORDER", C.border)
	edge:SetWidth(1)
	edge:SetPoint("TOPRIGHT")
	edge:SetPoint("BOTTOMRIGHT")

	f.search = S.Input(side, "BuildForgeSearch", SIDEBAR_W - 24, "Search Builds", 40)
	f.search:SetPoint("TOPLEFT", 12, -12)
	f.search:HookScript("OnTextChanged", function(self)
		state.search = self:GetText():lower()
		Window.Render()
	end)

	local listH = H - TITLE_H - 46 - 48
	f.list = BF.List.New(side, "BuildForgeListScroll", SIDEBAR_W - 22, listH, "sidebar")
	f.list.scroll:SetPoint("TOPLEFT", 0, -46)

	f.noMatches = S.Text(side, "small", C.muted)
	f.noMatches:SetPoint("TOP", 0, -64)
	f.noMatches:SetText("No builds match your search.")

	local half = (SIDEBAR_W - 30) / 2
	local new = S.Button(side, "New Build", "primary", half, newBuild,
		"Save your character's current perks, talents, glyphs and gear as a new build.")
	new:SetPoint("BOTTOMLEFT", 12, 12)
	local import = S.Button(side, "Import", "secondary", half, importBuild,
		"Paste a BuildForge string.")
	import:SetPoint("LEFT", new, "RIGHT", 6, 0)
end

local function createBuildHeader(main)
	local f = frame
	-- reads as a title until hovered or edited
	f.name = CreateFrame("EditBox", "BuildForgeNameBox", main)
	f.name:SetSize(280, 30)
	f.name:SetAutoFocus(false)
	f.name:SetMaxLetters(40)
	f.name:SetFontObject(GameFontHighlightLarge)
	f.name:SetTextInsets(8, 8, 0, 0)
	f.name:SetPoint("TOPLEFT", 16, -14)
	S.Panel(f.name, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
	f.name:SetScript("OnEditFocusGained", function(self)
		self.focused = true
		self:SetBackdropColor(0.04, 0.04, 0.05, 1)
		self:SetBackdropBorderColor(unpack(C.accent))
	end)
	f.name:SetScript("OnEditFocusLost", function(self)
		self.focused = false
		self:SetText(self.committed or "")
		self:SetBackdropColor(0, 0, 0, 0)
		self:SetBackdropBorderColor(0, 0, 0, 0)
	end)
	f.name:SetScript("OnEnter", function(self)
		if not self.focused then self:SetBackdropBorderColor(unpack(C.border)) end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Click to rename, then press Enter.")
		GameTooltip:Show()
	end)
	f.name:SetScript("OnLeave", function(self)
		if not self.focused then self:SetBackdropBorderColor(0, 0, 0, 0) end
		GameTooltip:Hide()
	end)
	f.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.name:SetScript("OnEnterPressed", function(self)
		local build = selectedBuild()
		local newName = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
		if build and not build.sharedOnly and BF:Rename(build, newName) then
			state.selected = newName
			self.committed = newName
		end
		self:ClearFocus()
		Window.Render()
	end)

	f.classes = S.Text(main, "small")
	f.classes:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 8, -6)
	f.classes:SetHeight(12)
	f.classes:SetWordWrap(false)

	f.specLabel = S.Text(main, "small", C.muted)
	f.specLabel:SetPoint("LEFT", f.classes, "RIGHT", 18, 0)
	f.specLabel:SetText("Spec Name")
	f.spec = S.Input(main, "BuildForgeSpecBox", 110, "None", 14)
	f.spec:SetHeight(20)
	f.spec:SetPoint("LEFT", f.specLabel, "RIGHT", 8, 0)
	f.spec:SetScript("OnEscapePressed", function(self)
		self:SetText(self.committed or "")
		self:ClearFocus()
	end)
	f.spec:SetScript("OnEnterPressed", function(self)
		local build = selectedBuild()
		if build then
			build.spec = self:GetText()
			self.committed = build.spec
		end
		self:ClearFocus()
		Window.Render()
	end)

	f.specLinkLabel = S.Text(main, "small", C.muted)
	f.specLinkLabel:SetPoint("LEFT", f.spec, "RIGHT", 16, 0)
	f.specLinkLabel:SetText("Linked to")
	f.specLink = S.Dropdown(main, 140, function(group)
		local build = selectedBuild()
		if build then BF:LinkSpec(build.name, group ~= 0 and group or nil) end
		Window.Render()
	end)
	f.specLink:SetPoint("LEFT", f.specLinkLabel, "RIGHT", 8, 0)
	f.specLink.tooltipText = "The talent spec on this character this build is for. Applying a build links it to the active spec."
	f.specActive = S.Text(main, "small", C.good)
	f.specActive:SetPoint("LEFT", f.specLink, "RIGHT", 10, 0)
	f.specActive:SetText("Active Spec")

	-- Apply Build, or Switch to Spec N for a build whose spec isn't active (applying it here would overwrite
	-- the spec you're in)
	f.apply = S.Button(main, "Apply Build", "primary", 110, function(self)
		if self.target then Window.SwitchSpec(self.target) else BF.Review.Open(selectedBuild()) end
	end)
	f.apply:SetPoint("TOPRIGHT", -16, -16)
	f.export = S.Button(main, "Export", "secondary", 70, function() BF:Export(selectedBuild()) end,
		"Copy this build as a one-line string to share.")
	f.export:SetPoint("RIGHT", f.apply, "LEFT", -6, 0)
	f.duplicate = S.Button(main, "Duplicate", "secondary", 80, function()
		local dup = BF:Duplicate(selectedBuild())
		state.collapsed[table.concat(dup.classes or {}, "/")] = false
		Window.Select(dup.name)
	end, "Make a copy of this build to try changes on. The copy isn't linked to a spec.")
	f.duplicate:SetPoint("RIGHT", f.export, "LEFT", -6, 0)
	f.delete = S.Button(main, "Delete", "danger", 70, function() BF:Delete(selectedBuild()) end)
	f.delete:SetPoint("RIGHT", f.duplicate, "LEFT", -6, 0)
end

local function createTabBar(main)
	local f = frame
	local bar = CreateFrame("Frame", nil, main)
	bar:SetPoint("TOPLEFT", 0, -BUILD_H)
	bar:SetPoint("TOPRIGHT", 0, -BUILD_H)
	bar:SetHeight(TABS_H)
	S.Rule(bar, "BOTTOM")
	f.tabs = {}
	for i, tab in ipairs(TABS) do
		local b = CreateFrame("Button", nil, bar)
		b:SetHeight(TABS_H)
		if i == 1 then b:SetPoint("BOTTOMLEFT", 8, 0) else b:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", 0, 0) end
		b.label = S.Text(b, "normal", C.muted)
		b.label:SetPoint("LEFT", 14, 0)
		b.label:SetText(tab.label)
		b.badgeBg = S.Solid(b, "ARTWORK", { 1, 0.5, 0.13, 0.25 })
		b.badgeBg:SetHeight(14)
		b.badgeBg:SetPoint("LEFT", b.label, "RIGHT", 6, 0)
		b.badge = S.Text(b, "small", C.accentHover, "OVERLAY")
		b.badge:SetPoint("CENTER", b.badgeBg, "CENTER", 0, 0)
		b.underline = S.Solid(b, "OVERLAY", C.accent)
		b.underline:SetHeight(2)
		b.underline:SetPoint("BOTTOMLEFT", 6, 0)
		b.underline:SetPoint("BOTTOMRIGHT", -6, 0)
		local hover = S.Solid(b, "HIGHLIGHT", C.hover)
		hover:SetAllPoints()
		b:SetScript("OnClick", function()
			PlaySound("igCharacterInfoTab")
			state.tab = tab.key
			state.message = nil
			Window.Render()
		end)
		f.tabs[i] = b
	end
end

local function createNotes(main, width, height)
	local box = CreateFrame("Frame", nil, main)
	box:SetSize(width, height)
	S.Panel(box, { 0.04, 0.04, 0.05, 1 }, C.border)
	local scroll = CreateFrame("ScrollFrame", "BuildForgeNotesScroll", box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(GameFontHighlight)
	edit:SetWidth(width - 44)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	edit:SetScript("OnEditFocusGained", function(self) self.focused = true end)
	edit:SetScript("OnEditFocusLost", function(self) self.focused = false end)
	edit:SetScript("OnTextChanged", function(self, userInput)
		local build = selectedBuild()
		if userInput and build then build.notes = self:GetText() end
	end)
	scroll:SetScrollChild(edit)
	BF.List.AutoHideBar(scroll, "BuildForgeNotesScroll")
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function() edit:SetFocus() end)
	local hint = S.Text(box, "small", C.muted)
	hint:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 0, 4)
	hint:SetText("Saved as you type, and included in exports.")
	box.edit = edit
	return box
end

local function createMain(f)
	local main = CreateFrame("Frame", nil, f)
	main:SetPoint("TOPLEFT", SIDEBAR_W, -TITLE_H)
	main:SetPoint("BOTTOMRIGHT")
	f.main = main

	createBuildHeader(main)
	createTabBar(main)

	local bodyTop = BUILD_H + TABS_H + 8
	local bodyH = H - TITLE_H - bodyTop - FOOTER_H
	local bodyW = W - SIDEBAR_W - 24
	f.notes = createNotes(main, bodyW - 8, bodyH - 22)
	f.notes:SetPoint("TOPLEFT", 16, -bodyTop - 18)
	f.editors = {}
	for key, module in pairs(EDITORS) do
		f.editors[key] = BF[module].Create(main, bodyW - 8, bodyH - 4)
		f.editors[key]:SetPoint("TOPLEFT", 16, -bodyTop)
	end

	local footer = CreateFrame("Frame", nil, main)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_H)
	S.Rule(footer, "TOP")
	f.actions = {}
	for i = 1, 2 do
		local b = S.Button(footer, "", "secondary", 90)
		if i == 1 then b:SetPoint("RIGHT", -16, 0) else b:SetPoint("RIGHT", f.actions[i - 1], "LEFT", -6, 0) end
		f.actions[i] = b
	end
	f.summary = S.Text(footer, "small", C.muted)
	f.summary:SetPoint("LEFT", 16, 0)
	f.summary:SetPoint("RIGHT", f.actions[2], "LEFT", -12, 0)
end

local function createEmpty(f)
	local empty = CreateFrame("Frame", nil, f)
	empty:SetPoint("TOPLEFT", SIDEBAR_W, -TITLE_H)
	empty:SetPoint("BOTTOMRIGHT")
	local title = S.Text(empty, "large")
	title:SetPoint("CENTER", 0, 50)
	title:SetJustifyH("CENTER")
	title:SetText("No Builds Yet")
	local body = S.Text(empty, "normal", C.muted)
	body:SetPoint("TOP", title, "BOTTOM", 0, -10)
	body:SetWidth(360)
	body:SetJustifyH("CENTER")
	body:SetText("Save your character's current perks, talents, glyphs and gear as a build, or import one someone shared with you.")
	local new = S.Button(empty, "New Build", "primary", 110, newBuild)
	new:SetPoint("TOPRIGHT", body, "BOTTOM", -4, -16)
	local import = S.Button(empty, "Import", "secondary", 110, importBuild)
	import:SetPoint("TOPLEFT", body, "BOTTOM", 4, -16)
	f.empty = empty
end

local function create()
	local f = CreateFrame("Frame", "BuildForgeFrame", UIParent)
	frame = f
	f:SetSize(W, H)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	local pos = BF.db.window
	if pos then f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y) else f:SetPoint("CENTER", 0, 40) end
	S.Panel(f, C.window, C.border)
	tinsert(UISpecialFrames, "BuildForgeFrame")
	f:Hide()

	createTitleBar(f)
	createSidebar(f)
	createMain(f)
	createEmpty(f)
	f.review = BF.Review.Create(f.main, W - SIDEBAR_W, H - TITLE_H)

	f:SetScript("OnShow", function()
		PlaySound("igCharacterInfoOpen")
		Window.Render()
	end)
	f:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose")
		f.review:Hide()
	end)
	f:SetScript("OnUpdate", function(self)
		if self.dirty then Window.Render() end
	end)
	for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
		"GLYPH_ADDED", "GLYPH_REMOVED", "GLYPH_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
		f:RegisterEvent(event)
	end
	f:SetScript("OnEvent", Window.Refresh)
	return f
end

function Window.Open(name)
	frame = frame or create()
	if name then state.selected = name end
	frame:Show()
	Window.Render()
end

function Window.Toggle()
	if frame and frame:IsShown() then frame:Hide() else Window.Open() end
end

function Window.Frame()
	return frame
end
