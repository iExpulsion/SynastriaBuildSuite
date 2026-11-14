local _, NS = ...
local SBS = NS.SBS

-- The build window: a movable flat panel with a searchable build sidebar on the left and the selected build on
-- the right (header with the main actions, tabs with difference badges, the tab's content and a footer).
-- Sized so Phase 2's three-tree talent editor fits beside the sidebar.
local Window = {}
SBS.Window = Window

local S = SBS.Style
local C = S.colors

local W, H = 900, 640
local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
-- the header is two control rows, the footer one, each with PAD around it
local TITLE_H, SIDEBAR_W, TABS_H = 36, 240, 32
local BUILD_H = PAD + CONTROL_H + GAP + CONTROL_H + GAP
local FOOTER_H = PAD + CONTROL_H + PAD
local TABS = {
	{ key = "perks", label = "Perks" },
	{ key = "talents", label = "Talents" },
	{ key = "glyphs", label = "Glyphs" },
	{ key = "gear", label = "Gear" },
	{ key = "affixes", label = "Affixes" },
	{ key = "notes", label = "Notes" },
}

local frame
local SPECS_KEY = "\1specs"
local CLASSES_W = 150
-- Tabs whose comparison depends on the active spec (gear and bags are the same in every spec).
local PER_SPEC = { perks = true, talents = true, glyphs = true, affixes = true }
-- The editor module behind each tab except Notes.
local EDITORS = { perks = "PerkEditor", talents = "TalentEditor", glyphs = "GlyphEditor", gear = "GearEditor",
	affixes = "AffixEditor" }
local state = { selected = nil, tab = "perks", collapsed = {}, search = "" }
Window.state = state

local function setShown(f, shown)
	if shown then f:Show() else f:Hide() end
end

local function className(key)
	return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[key] or key
end

-- Synastria's name and color for a two-class pair: the name from SBS:ComboName, or else from the client (as its
-- Character window does, with the pair packed as first class ID << 8 | second), and the client's color, or the
-- first class's color when the client has none.
local function comboName(classes)
	local a, b = SBS.CLASS_IDS[classes[1]], SBS.CLASS_IDS[classes[2]]
	local name, r, g, bl
	if #classes == 2 and a and b then
		local pack = a * 256 + b
		name = SBS:ComboName(classes[1], classes[2]) or (CMCGetClassNameFromPack and CMCGetClassNameFromPack(pack))
		if CMCGetClassNameColor then r, g, bl = CMCGetClassNameColor(pack) end
		local first = RAID_CLASS_COLORS[classes[1]]
		if not (r and g and bl) and first then r, g, bl = first.r, first.g, first.b end
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
	return state.selected == SHARED and SBS.Build.SHARED or state.selected and SBS.db.builds[state.selected]
end

-- The spec to switch to for a build, when it's linked and none of its specs is active.
function Window.SpecToSwitch(build)
	local groups = SBS:LinkedSpecs(build.name)
	local target = groups[1]
	for _, g in ipairs(groups) do if g == SBS:ActiveGroup() then target = nil end end
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
		Window.Message(S.Hex(C.muted, "Switching to " .. SBS:SpecName(group) .. "..."))
	end
end

function Window.Select(name)
	S.Dismiss()
	state.selected = name
	state.message = nil
	if frame then
		frame.review:Hide()
		frame.sources:Hide()
	end
	SBS.TemplateSheet.Hide()
	Window.Render()
end

-- Sidebar --------------------------------------------------------------------------------------------------

local function matches(build)
	local q = state.search
	return q == "" or build.name:lower():find(q, 1, true) ~= nil or (build.spec or ""):lower():find(q, 1, true) ~= nil
end

-- This character's specs that have a linked build, in spec order: { group, build }.
local function linkedSpecs()
	local rows, links = {}, SBS:Links()
	for g = 1, SBS:SpecCount() do
		local build = links[g] and SBS.db.builds[links[g]]
		if build and matches(build) then rows[#rows + 1] = { group = g, build = build } end
	end
	return rows
end

-- The other builds, grouped by class combination; groups that fit the character come first and start expanded.
local function groupedBuilds()
	local groups, byKey = {}, {}
	for _, build in pairs(SBS.db.builds) do
		if matches(build) and #SBS:LinkedSpecs(build.name) == 0 then
			local key = table.concat(build.classes or {}, "/")
			local group = byKey[key]
			if not group then
				group = { key = key, classes = build.classes or {}, fits = SBS.Build.Fits(build), builds = {} }
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

	if matches(SBS.Build.SHARED) then
		list:Add({
			text = "Shared Perks", sub = "Misc perks, in every build",
			status = S.Hex(C.muted, #SBS.db.shared.perks),
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
			local build, active = row.build, row.group == SBS:ActiveGroup()
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
		local label = group.key == "" and "No Class" or Window.ClassText(group.classes)
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
		setShown(b, not build.sharedOnly or tab.key == "perks")
		b:SetSelected(tab.key == state.tab)
		local diff = (comparing or not PER_SPEC[tab.key]) and SBS.Tabs.diff[tab.key] and SBS.Tabs.diff[tab.key](build)
		if diff and diff > 0 then
			b.badge:SetText(diff)
			b.badgeBg:SetWidth(b.badge:GetStringWidth() + 10)
			b.badgeBg:Show()
			b.badge:Show()
		else
			b.badgeBg:Hide()
			b.badge:Hide()
		end
		local badgeW = diff and diff > 0 and (GAP + b.badge:GetStringWidth() + 10) or 0
		b:SetWidth(b.label:GetStringWidth() + badgeW + 2 * S.metrics.tabPad)
	end
	setShown(frame.notes, state.tab == "notes")
	for key, editor in pairs(frame.editors) do setShown(editor, key == state.tab) end
end

-- The Templates menu: load any template that fits the build, save this tab as one, or open the sheet to manage them.
local function renderTemplates(build)
	local T = SBS.Templates
	local section = state.tab
	local shown = EDITORS[section] ~= nil and not build.sharedOnly
	setShown(frame.templates, shown)
	if shown then
		local options, label = {}, T.Label(section)
		local undo = T.Undoable(section, build)
		if undo then
			options[1] = { value = "undo", text = "Undo Load: " .. undo,
				tooltip = ("Put this build's %s back as they were before loading %s."):format(label:lower(), undo) }
		end
		for _, t in ipairs(T.List(section)) do
			if T.Fits(section, t, build) then
				options[#options + 1] = { value = { load = t.name }, text = "Load: " .. t.name, tooltip = T.Describe(section, t) }
			end
		end
		options[#options + 1] = { value = "save", text = ("Save %s as Template..."):format(label),
			tooltip = ("Save this build's %s under a name, to load into any build."):format(label:lower()) }
		options[#options + 1] = { value = "manage", text = "Manage Templates...",
			tooltip = ("Every %s template: load, rename or delete them."):format(label:lower()) }
		frame.templates:SetOptions(options)
		frame.templates:SetText("Templates")
	end
end

local function pickTemplate(value)
	local build, section = selectedBuild(), state.tab
	local T = SBS.Templates
	local t = type(value) == "table" and T.Get(section, value.load)
	if t then
		if T.Load(section, t, build) then SBS.TemplateSheet.Loaded(t) end
	elseif value == "undo" then
		local name = T.Undo()
		SBS:Changed()
		Window.Message(S.Hex(C.muted, "Undid Loading " .. name))
	else
		SBS.TemplateSheet.Open(section, build, value == "save")
	end
end

local function renderActions(build)
	local actions = SBS.Tabs.actions[state.tab] or {}
	-- the summary runs up to the last button shown, so a tab with fewer buttons gives it more room
	local last = frame.actions[math.max(1, math.min(#actions, #frame.actions))]
	frame.summary:SetPoint("RIGHT", last, "LEFT", -PAD, 0)
	for i, b in ipairs(frame.actions) do
		local action = actions[i]
		if action then
			local usable = not action.usable or action.usable(build)
			b:SetLabel(action.label)
			b:SetScript("OnClick", function() action.run(build) end)
			b.tooltipText = usable and action.tooltip or action.unusableTip
			if usable then b:Enable() else b:Disable() end
			b:Show()
		else
			b:Hide()
		end
	end
end

local function renderInnkeeper()
	local at = SBS.Perks.Writable()
	frame.innDot:SetVertexColor(unpack(at and C.good or C.warn))
	frame.innText:SetText(at and "Perk Manager Open at an Innkeeper" or "Perk Activations Need an Innkeeper")
	frame.innText:SetTextColor(unpack(at and C.good or C.muted))
end

local function renderSpecLink(build)
	local count = build.sharedOnly and 1 or SBS:SpecCount()
	local groups = SBS:LinkedSpecs(build.name)
	local options = { { value = 0, text = "Not Linked", tooltip = "Don't tie this build to a spec on this character." } }
	for g = 1, count do
		local other = SBS:Links()[g]
		local tip = other and other ~= build.name and ("Linked to " .. other .. " now; picking it moves that link here.") or nil
		options[#options + 1] = { value = g, text = SBS:SpecName(g) .. (g == SBS:ActiveGroup() and " (Active)" or ""), tooltip = tip }
	end
	frame.specLink:SetOptions(options)
	local label = #groups == 0 and "Not Linked" or SBS:SpecName(groups[1])
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
	renderTemplates(build)
	renderActions(build)
	if state.tab == "notes" then
		if not frame.notes.edit.focused then frame.notes.edit:SetText(build.notes or "") end
		frame.summary:SetText(state.message or S.Hex(C.muted, "Saved as You Type, Included in Exports"))
	else
		local summary = SBS[EDITORS[state.tab]].Render(build)
		if PER_SPEC[state.tab] and not Window.IsComparing(build) then summary = Window.InactiveNote(build) end
		local pendingSpec = build.perksPending and SBS:LinkedSpecs(build.name)[1]
		if pendingSpec and (state.tab == "perks" or state.tab == "affixes") then
			summary = S.Hex(C.warn, ("%s Fill In When You Switch to Spec %d"):format(state.tab == "perks" and "Perks"
				or "Affixes", pendingSpec))
		end
		frame.summary:SetText(state.message or summary or "")
	end
end

function Window.Render()
	if frame and frame:IsShown() then
		frame.dirty, frame.eventDirty = false, false
		renderSidebar()
		renderInnkeeper()
		local build = selectedBuild()
		setShown(frame.main, build ~= nil)
		setShown(frame.empty, build == nil and next(SBS.db.builds) == nil)
		if build then renderBuild(build) end
		if frame.review:IsShown() then SBS.Review.Render() end
		if frame.sources:IsShown() then SBS.Sources.Render() end
	end
end

-- Coalesces changes into one render on the next frame.
function Window.Refresh()
	if frame and not SBS.Talents.switching then frame.dirty = true end
end

-- Game events (bag updates come in bursts while looting or vendoring) render at most a few times a second, since
-- a render rebuilds every tab's comparison.
local EVENT_RENDER_EVERY = 0.25
local function eventRefresh()
	if frame and not SBS.Talents.switching then frame.eventDirty = true end
end

-- Stat events matter only while the Affixes tab shows the character's stats, and only when a shown value moved
-- (buffs change them all the time). true: a unit event, which counts only for the player.
local STAT_EVENTS = { UNIT_STATS = true, UNIT_ATTACK_POWER = true, UNIT_RANGED_ATTACK_POWER = true,
	UNIT_RESISTANCES = true, UNIT_MAXHEALTH = true, UNIT_MAXMANA = true, COMBAT_RATING_UPDATE = false,
	PLAYER_DAMAGE_DONE_MODS = false }

local function onEvent(_, event, unit)
	local stat = STAT_EVENTS[event]
	if stat == nil or ((not stat or unit == "player") and SBS.AffixEditor.ShowingStats() and SBS.Stats.Poll()) then
		eventRefresh()
	end
end

-- Shows a one-off status message in the footer until the next tab or build change.
function Window.Message(text)
	state.message = text
	Window.Render()
end

-- Construction ---------------------------------------------------------------------------------------------

local function saveSpecs()
	SBS:SaveAllSpecs()
	state.search = ""
	frame.search:SetText("")
	Window.Select(SBS:Links()[SBS:ActiveGroup()])
end

local function newBuild()
	SBS.Dialogs.ShowNew(function(name, classes, sections)
		local function create()
			SBS.Dialogs.HideNew()
			local build = SBS:SaveNew(name, classes, sections)
			state.search = ""
			frame.search:SetText("")
			state.collapsed[table.concat(classes, "/")] = false
			Window.Select(build.name)
		end
		if SBS.db.builds[name] then SBS.Dialogs.Confirm("SBS_OVERWRITE", name, create) else create() end
	end, saveSpecs)
end

-- Import offers to bring sections into the selected build as well as making a new one.
local function importBuild()
	local target = selectedBuild()
	if target and target.sharedOnly then target = nil end
	SBS.Dialogs.ShowImport(function(text, sections, into, name)
		SBS:Import(text, function(build)
			state.collapsed[table.concat(build.classes or {}, "/")] = false
			Window.Select(build.name)
		end, sections, into and target or nil, name)
	end, target and target.name)
end

local function savePosition(f)
	SBS.SnapPosition(f)
	local point, _, relPoint, x, y = f:GetPoint()
	SBS.db.window = { point = point, relPoint = relPoint, x = x, y = y }
end

-- The default spot is the style kit's, top middle of the screen, shared with Companion and Rotation Assist.
local function placeDefault(f)
	S.PlaceWindow(f)
	SBS.SnapPosition(f)
end

function Window.ResetPosition()
	SBS.db.window = nil
	if frame then
		placeDefault(frame)
		Window.Render()
	end
end

-- The theme picker: every skin the kit has, with who made it on hover. A change applies after a reload.
local function createThemePicker(bar, anchor)
	local label = S.Text(bar, "small", C.muted)
	label:SetPoint("LEFT", anchor, "RIGHT", 2 * GAP, 0)
	label:SetText("Theme")
	local options, inUse = {}, nil
	for _, skin in ipairs(S.Skins()) do
		options[#options + 1] = { value = skin.key, text = skin.label, tooltip = skin.credit }
		if skin.key == S.Skin() then inUse = skin.label end
	end
	local picker
	picker = S.Dropdown(bar, 96, function(key)
		SBS.SetSkin(key)
		for _, opt in ipairs(options) do
			if opt.value == key then picker:SetText(opt.text) end
		end
	end)
	picker:SetOptions(options)
	picker:SetText(inUse or "")
	picker:SetPoint("LEFT", label, "RIGHT", GAP, 0)
	return picker
end

-- The size picker: the window's scale on top of the UI scale, for big screens.
local function createSizePicker(bar, anchor)
	local label = S.Text(bar, "small", C.muted)
	label:SetPoint("LEFT", anchor, "RIGHT", 2 * GAP, 0)
	label:SetText("Size")
	local options = {}
	for _, scale in ipairs(SBS.WINDOW_SCALES) do
		options[#options + 1] = { value = scale, text = SBS.ScaleLabel(scale) }
	end
	local picker = S.Dropdown(bar, 64, function(scale) SBS.SetWindowScale(scale) end)
	picker:SetOptions(options)
	picker:SetPoint("LEFT", label, "RIGHT", GAP, 0)
	return picker
end

-- The pixel snapping box: crisp borders, or exactly the UI scale.
local function createSnapBox(bar, anchor)
	local box = S.Check(bar, nil, function() SBS.SetPixelScale(not SBS.db.pixelScale) end)
	box:SetPoint("LEFT", anchor, "RIGHT", 2 * GAP, 0)
	local label = S.Text(bar, "small", C.muted)
	label:SetPoint("LEFT", box, "RIGHT", 6, 0)
	label:SetText("Snap to Pixels")
	box:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Snap to Pixels", 1, 1, 1)
		GameTooltip:AddLine("Lines the window up with whole screen pixels so its borders stay crisp. It can make the "
			.. "window a little larger or smaller than the rest of your UI; turn it off to match the UI scale exactly.",
			nil, nil, nil, true)
		GameTooltip:Show()
	end)
	box:HookScript("OnLeave", function() GameTooltip:Hide() end)
	return box
end

-- Shows the window size and pixel snapping as saved, after either changes from the title bar or a command.
local function paintSettings()
	frame.sizePicker:SetText(SBS.ScaleLabel(SBS.db.windowScale))
	frame.snapBox:SetChecked(SBS.db.pixelScale)
end

-- After the window scale or pixel snapping changes: a window at the default spot goes back to it at its new size,
-- a moved one saves where it now is in its new units, and whatever is placed over it by screen position follows.
function Window.Rescaled()
	if frame then
		if SBS.db.window then savePosition(frame) else placeDefault(frame) end
		paintSettings()
		Window.Render()
	end
end

local function createTitleBar(f, edge)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", edge, -edge)
	bar:SetPoint("TOPRIGHT", -edge, -edge)
	bar:SetHeight(TITLE_H)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	-- anything placed by screen position over the window (the glyph Socket buttons) goes while it moves
	bar:SetScript("OnDragStart", function()
		S.Dismiss()
		f:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		savePosition(f)
		Window.Render()
	end)
	S.Rule(bar, "BOTTOM")

	local title = S.Text(bar, "normal")
	title:SetPoint("LEFT", PAD, 0)
	title:SetText("Synastria " .. S.Hex(C.accent, "Build Suite"))
	local version = S.Text(bar, "small", C.muted)
	version:SetPoint("LEFT", title, "RIGHT", GAP, 0)
	version:SetText("v" .. SBS.version)
	f.sizePicker = createSizePicker(bar, createThemePicker(bar, version))
	f.snapBox = createSnapBox(bar, f.sizePicker)

	-- the close button's box sits as far from the right edge as from the top and bottom
	local inset = (TITLE_H - CONTROL_H) / 2
	local close = S.Button(bar, "Close", "ghost", 56, function() f:Hide() end)
	close:SetPoint("RIGHT", -inset, 0)

	f.innText = S.Text(bar, "small", C.muted)
	f.innText:SetPoint("RIGHT", close, "LEFT", -GAP, 0)
	f.innDot = S.Solid(bar, "ARTWORK", C.muted)
	f.innDot:SetSize(8, 8)
	f.innDot:SetPoint("RIGHT", f.innText, "LEFT", -GAP, 0)
end

local function createSidebar(f, edge)
	local side = CreateFrame("Frame", nil, f)
	side:SetPoint("TOPLEFT", edge, -edge - TITLE_H)
	side:SetPoint("BOTTOMLEFT", edge, edge)
	side:SetWidth(SIDEBAR_W)
	side:SetHeight(H - TITLE_H)
	S.Sidebar(side)
	-- the list rows sit in from the sidebar's sides by the skin's frame around it
	local inset = S.metrics.navInset

	f.search = S.Input(side, "SynastriaBuildSuiteSearch", SIDEBAR_W - 2 * PAD, "Search Builds", 40)
	f.search:SetPoint("TOPLEFT", PAD, -PAD)
	f.search:HookScript("OnTextChanged", function(self)
		state.search = self:GetText():lower()
		Window.Render()
	end)

	-- the list runs from below the search box to the footer, which lines up with the build pane's footer
	local listTop = PAD + CONTROL_H + GAP
	f.list = SBS.List.New(side, "SynastriaBuildSuiteListScroll", SIDEBAR_W - 14 - 2 * inset,
		H - TITLE_H - listTop - FOOTER_H, "sidebar")
	f.list.scroll:SetPoint("TOPLEFT", inset, -listTop)

	f.noMatches = S.Text(side, "small", C.muted)
	f.noMatches:SetPoint("TOP", 0, -(listTop + PAD))
	f.noMatches:SetText("No builds match your search.")

	local footer = CreateFrame("Frame", nil, side)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_H)
	S.Rule(footer, "TOP")
	local half = (SIDEBAR_W - 2 * PAD - GAP) / 2
	local new = S.Button(footer, "New Build", "secondary", half, newBuild,
		"Make a build from any part of your character, a blank one for any class, or one for every spec.")
	new:SetPoint("LEFT", PAD, 0)
	f.newBuild = new
	local import = S.Button(footer, "Import", "secondary", half, importBuild,
		"Paste a Synastria Build Suite, SynastriaBuildManager, SynastriaPerkManager or affix order string.")
	import:SetPoint("LEFT", new, "RIGHT", GAP, 0)
end

local function createBuildHeader(main)
	local f = frame
	-- two rows of controls, each element centered on its row: name and actions, then classes and spec
	local row1 = CreateFrame("Frame", nil, main)
	row1:SetPoint("TOPLEFT", PAD, -PAD)
	row1:SetPoint("TOPRIGHT", -PAD, -PAD)
	row1:SetHeight(CONTROL_H)
	local row2 = CreateFrame("Frame", nil, main)
	row2:SetPoint("TOPLEFT", row1, "BOTTOMLEFT", 0, -GAP)
	row2:SetPoint("TOPRIGHT", row1, "BOTTOMRIGHT", 0, -GAP)
	row2:SetHeight(CONTROL_H)

	-- reads as a title until hovered or edited; its text lines up with the rows below
	f.name = CreateFrame("EditBox", "SynastriaBuildSuiteNameBox", main)
	f.name:SetSize(280, CONTROL_H)
	f.name:SetAutoFocus(false)
	f.name:SetMaxLetters(40)
	S.SetFont(f.name, "large")
	f.name:SetTextInsets(GAP, GAP, 0, 0)
	f.name:SetPoint("LEFT", row1, "LEFT", -GAP, 0)
	S.Panel(f.name, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
	f.name:SetScript("OnEditFocusGained", function(self)
		self.focused = true
		self:SetBackdropColor(unpack(C.well))
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
		if build and not build.sharedOnly and SBS:Rename(build, newName) then
			state.selected = newName
			self.committed = newName
		end
		self:ClearFocus()
		Window.Render()
	end)
	S.TrackInput(f.name)

	f.classes = S.Text(main, "small")
	f.classes:SetPoint("LEFT", row2, "LEFT", 0, 0)
	f.classes:SetHeight(12)
	f.classes:SetWordWrap(false)

	f.specLabel = S.Text(main, "small", C.muted)
	f.specLabel:SetPoint("LEFT", f.classes, "RIGHT", 2 * GAP, 0)
	f.specLabel:SetText("Spec Name")
	f.spec = S.Input(main, "SynastriaBuildSuiteSpecBox", 110, "None", 14)
	f.spec:SetPoint("LEFT", f.specLabel, "RIGHT", GAP, 0)
	-- like the name, it saves only on Enter: Esc or clicking away puts back the saved spec name
	f.spec:SetScript("OnEscapePressed", f.spec.ClearFocus)
	f.spec:HookScript("OnEditFocusLost", function(self) self:SetText(self.committed or "") end)
	f.spec:SetScript("OnEnterPressed", function(self)
		local build = selectedBuild()
		if build then
			build.spec = self:GetText()
			self.committed = build.spec
		end
		self:ClearFocus()
		Window.Render()
	end)

	-- the spec link sits flush right under the actions, laid out right to left so hiding the tag moves nothing
	f.specLink = S.Dropdown(main, 140, function(group)
		local build = selectedBuild()
		if build then SBS:LinkSpec(build.name, group ~= 0 and group or nil) end
		Window.Render()
	end)
	f.specLink:SetPoint("RIGHT", row2, "RIGHT", 0, 0)
	f.specLink.tooltipText = "The talent spec on this character this build is for. Applying a build links it to the active spec."
	f.specLinkLabel = S.Text(main, "small", C.muted)
	f.specLinkLabel:SetPoint("RIGHT", f.specLink, "LEFT", -GAP, 0)
	f.specLinkLabel:SetText("Linked to")
	f.specActive = S.Text(main, "small", C.good)
	f.specActive:SetPoint("RIGHT", f.specLinkLabel, "LEFT", -2 * GAP, 0)
	f.specActive:SetText("Active Spec")

	-- Apply Build, or Switch to Spec N for a build whose spec isn't active (applying it here would overwrite
	-- the spec you're in)
	f.apply = S.Button(main, "Apply Build", "primary", 110, function(self)
		if self.target then Window.SwitchSpec(self.target) else SBS.Review.Open(selectedBuild()) end
	end)
	f.apply:SetPoint("RIGHT", row1, "RIGHT", 0, 0)
	f.export = S.Button(main, "Export", "secondary", 70, function() SBS:Export(selectedBuild()) end,
		"Copy this build as a one-line string to share.")
	f.export:SetPoint("RIGHT", f.apply, "LEFT", -GAP, 0)
	f.duplicate = S.Button(main, "Duplicate", "secondary", 80, function()
		local dup = SBS:Duplicate(selectedBuild())
		state.collapsed[table.concat(dup.classes or {}, "/")] = false
		Window.Select(dup.name)
	end, "Make a copy of this build to try changes on. The copy isn't linked to a spec.")
	f.duplicate:SetPoint("RIGHT", f.export, "LEFT", -GAP, 0)
	f.delete = S.Button(main, "Delete", "danger", 70, function() SBS:Delete(selectedBuild()) end)
	f.delete:SetPoint("RIGHT", f.duplicate, "LEFT", -GAP, 0)
end

local function createTabBar(main)
	local f = frame
	local bar = CreateFrame("Frame", nil, main)
	bar:SetPoint("TOPLEFT", 0, -BUILD_H)
	bar:SetPoint("TOPRIGHT", 0, -BUILD_H)
	bar:SetHeight(TABS_H)
	S.Rule(bar, "BOTTOM", "tabs")
	f.tabs = {}
	for i, tab in ipairs(TABS) do
		local b = CreateFrame("Button", nil, bar)
		b:SetHeight(TABS_H)
		-- the first tab's label starts at PAD, in line with the header text above
		if i == 1 then b:SetPoint("BOTTOMLEFT", 0, 0) else b:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", 0, 0) end
		S.Tab(b, tab.label)
		b.badgeBg = S.Solid(b, "ARTWORK", { C.accent[1], C.accent[2], C.accent[3], 0.25 })
		b.badgeBg:SetHeight(14)
		b.badgeBg:SetPoint("LEFT", b.label, "RIGHT", GAP, 0)
		b.badge = S.Text(b, "small", C.accentHover, "OVERLAY")
		b.badge:SetPoint("CENTER", b.badgeBg, "CENTER", 0, 0)
		b:SetScript("OnClick", function()
			PlaySound("igCharacterInfoTab")
			S.Dismiss()
			state.tab = tab.key
			state.message = nil
			Window.Render()
		end)
		f.tabs[i] = b
	end
	-- the menu opens leftward from the button's right edge, wide enough for its Save line
	f.templates = S.Dropdown(bar, 100, pickTemplate)
	f.templates:SetPoint("RIGHT", bar, "RIGHT", -PAD, 0)
	f.templates.menu:SetWidth(220)
	f.templates.menu:ClearAllPoints()
	f.templates.menu:SetPoint("TOPRIGHT", f.templates, "BOTTOMRIGHT", 0, -2)
	f.templates.tooltipText = "Save this tab as a template, or load one into this build."
end

local function createNotes(main, width, height)
	local box = CreateFrame("Frame", nil, main)
	box:SetSize(width, height)
	S.Well(box)
	-- the text sits inside the well's frame, however thick the theme draws it
	local pad = PAD + S.metrics.wellInset
	local scroll = CreateFrame("ScrollFrame", "SynastriaBuildSuiteNotesScroll", box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", pad, -pad)
	scroll:SetPoint("BOTTOMRIGHT", -pad - 10, pad)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	S.SetFont(edit, "normal")
	edit:SetWidth(width - 2 * pad - 10)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	edit:SetScript("OnEditFocusGained", function(self) self.focused = true end)
	edit:SetScript("OnEditFocusLost", function(self) self.focused = false end)
	edit:SetScript("OnTextChanged", function(self, userInput)
		local build = selectedBuild()
		if userInput and build then build.notes = self:GetText() end
	end)
	scroll:SetScrollChild(edit)
	S.TrackInput(edit, box)
	SBS.List.AutoHideBar(scroll, "SynastriaBuildSuiteNotesScroll")
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function() edit:SetFocus() end)
	box.edit = edit
	return box
end

local function createMain(f, edge)
	local main = CreateFrame("Frame", nil, f)
	main:SetPoint("TOPLEFT", edge + SIDEBAR_W, -edge - TITLE_H)
	main:SetPoint("BOTTOMRIGHT", -edge, edge)
	f.main = main

	createBuildHeader(main)
	createTabBar(main)

	-- the tab's body sits PAD inside the pane on every side, between the tab bar and the footer
	local bodyTop = BUILD_H + TABS_H + PAD
	local bodyW = W - SIDEBAR_W - 2 * PAD
	local bodyH = H - TITLE_H - bodyTop - FOOTER_H - PAD
	f.notes = createNotes(main, bodyW, bodyH)
	f.notes:SetPoint("TOPLEFT", PAD, -bodyTop)
	f.editors = {}
	for key, module in pairs(EDITORS) do
		f.editors[key] = SBS[module].Create(main, bodyW, bodyH)
		f.editors[key]:SetPoint("TOPLEFT", PAD, -bodyTop)
	end

	local footer = CreateFrame("Frame", nil, main)
	footer:SetPoint("BOTTOMLEFT")
	footer:SetPoint("BOTTOMRIGHT")
	footer:SetHeight(FOOTER_H)
	S.Rule(footer, "TOP")
	f.actions = {}
	for i = 1, 3 do
		-- the first slot fits the longest Use Current label, so the button beside it never moves
		local b = S.Button(footer, "", "secondary", i == 1 and 140 or 90)
		if i == 1 then b:SetPoint("RIGHT", -PAD, 0) else b:SetPoint("RIGHT", f.actions[i - 1], "LEFT", -GAP, 0) end
		f.actions[i] = b
	end
	f.summary = S.Text(footer, "small", C.muted)
	f.summary:SetPoint("LEFT", PAD, 0)
end

local function createEmpty(f, edge)
	local empty = CreateFrame("Frame", nil, f)
	empty:SetPoint("TOPLEFT", edge + SIDEBAR_W, -edge - TITLE_H)
	empty:SetPoint("BOTTOMRIGHT", -edge, edge)
	local title = S.Text(empty, "large")
	title:SetPoint("CENTER", 0, 50)
	title:SetJustifyH("CENTER")
	title:SetText("No Builds Yet")
	local body = S.Text(empty, "normal", C.muted)
	body:SetPoint("TOP", title, "BOTTOM", 0, -10)
	body:SetWidth(360)
	body:SetJustifyH("CENTER")
	body:SetText("Save every spec on this character as builds, make one from any part of your character or blank for any class, or import one someone shared with you.")
	f.emptySaveSpecs = S.Button(empty, "Add Current Specs", "primary", 120, saveSpecs, SBS.Dialogs.SAVE_SPECS_TIP)
	f.emptySaveSpecs:SetPoint("TOP", body, "BOTTOM", 0, -16)
	local new = S.Button(empty, "New Build", "secondary", 110, newBuild)
	new:SetPoint("RIGHT", f.emptySaveSpecs, "LEFT", -8, 0)
	local import = S.Button(empty, "Import", "secondary", 110, importBuild)
	import:SetPoint("LEFT", f.emptySaveSpecs, "RIGHT", 8, 0)
	f.empty = empty
end

local function create()
	S.RefreshFonts()
	local f = CreateFrame("Frame", "SynastriaBuildSuiteFrame", UIParent)
	frame = f
	-- the theme's border (S.metrics.edge) goes around the same content area, so every screen keeps its size
	local edge = S.metrics.edge
	f:SetSize(W + 2 * edge, H + 2 * edge)
	-- the game's panel layer, with the bags and the auction house: whichever was clicked or opened last is on top
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	SBS.PixelScale(f)
	local pos = SBS.db.window
	if pos then
		f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
		SBS.SnapPosition(f)
	else
		placeDefault(f)
	end
	S.Frame(f, "window")
	tinsert(UISpecialFrames, "SynastriaBuildSuiteFrame")
	f:Hide()

	createTitleBar(f, edge)
	paintSettings()
	createSidebar(f, edge)
	createMain(f, edge)
	createEmpty(f, edge)
	f.review = SBS.Review.Create(f.main, W - SIDEBAR_W, H - TITLE_H)
	f.sources = SBS.Sources.Create(f.main, W - SIDEBAR_W, H - TITLE_H)

	f:SetScript("OnShow", function()
		PlaySound("igCharacterInfoOpen")
		Window.Render()
	end)
	f:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose")
		f.review:Hide()
		f.sources:Hide()
		SBS.TemplateSheet.Hide()
		S.Dismiss()
		SBS.Launchers.WindowClosed()
	end)
	f:SetScript("OnUpdate", function(self)
		SBS.GlyphEditor.KeepButtonsAbove(self)
		local now = GetTime()
		local eventDue = self.eventDirty and now >= (self.nextEventRender or 0)
		if self.dirty or eventDue then
			if eventDue then self.nextEventRender = now + EVENT_RENDER_EVERY end
			Window.Render()
		end
	end)
	for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
		"GLYPH_ADDED", "GLYPH_REMOVED", "GLYPH_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
		f:RegisterEvent(event)
	end
	for event in pairs(STAT_EVENTS) do f:RegisterEvent(event) end
	f:SetScript("OnEvent", onEvent)
	return f
end

function Window.Open(name)
	frame = frame or create()
	if name then state.selected = name end
	frame:Show()
	frame:Raise()
	Window.Render()
end

function Window.Toggle()
	if frame and frame:IsShown() then frame:Hide() else Window.Open() end
end

function Window.Frame()
	return frame
end
