local _, NS = ...
local BF = NS.BF

-- The build window: a movable flat panel with a searchable build sidebar on the left and the selected build on
-- the right (header with the main actions, tabs with difference badges, the tab's content and a footer).
-- Sized so Phase 2's three-tree talent editor fits beside the sidebar.
local Window = {}
BF.Window = Window

local S = BF.Style
local C = S.colors

local W, H = 900, 560
local TITLE_H, SIDEBAR_W, BUILD_H, TABS_H, FOOTER_H = 36, 240, 78, 32, 46
local TABS = {
	{ key = "perks", label = "Perks" },
	{ key = "talents", label = "Talents" },
	{ key = "glyphs", label = "Glyphs" },
	{ key = "gear", label = "Gear" },
	{ key = "notes", label = "Notes" },
}

local frame
local state = { selected = nil, tab = "perks", collapsed = {}, search = "" }
Window.state = state

local function setShown(f, shown)
	if shown then f:Show() else f:Hide() end
end

local function className(key)
	return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[key] or key
end

-- Class names in class colors, or plain.
function Window.ClassText(classes, plain)
	local parts = {}
	for _, key in ipairs(classes or {}) do
		local c = not plain and RAID_CLASS_COLORS[key]
		parts[#parts + 1] = c and ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, className(key)) or className(key)
	end
	return table.concat(parts, " / ")
end

local function selectedBuild()
	return state.selected and BF.db.builds[state.selected]
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

-- Builds grouped by class combination; groups that fit the character come first and start expanded.
local function groupedBuilds()
	local groups, byKey = {}, {}
	for _, build in pairs(BF.db.builds) do
		if matches(build) then
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
	local applied = BF.charDB.applied[BF:ActiveGroup()]
	local first, firstFit, shown = nil, nil, 0
	list:Begin()
	for _, group in ipairs(groupedBuilds()) do
		local collapsed = isCollapsed(group)
		local label = group.key == "" and "No Class" or Window.ClassText(group.classes, not group.fits)
		list:Add({
			text = label,
			status = S.Hex(C.muted, #group.builds),
			header = true, collapsed = collapsed,
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
				local sub = (build.spec and build.spec ~= "") and build.spec or Window.ClassText(build.classes, true)
				list:Add({
					text = build.name,
					sub = sub,
					status = build.name == applied and S.Hex(C.good, "Applied") or nil,
					indent = 12,
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
	for i, tab in ipairs(TABS) do
		local b = frame.tabs[i]
		local selected = tab.key == state.tab
		b.label:SetTextColor(unpack(selected and C.text or C.muted))
		setShown(b.underline, selected)
		local diff = BF.Tabs.diff[tab.key] and BF.Tabs.diff[tab.key](build)
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
	local isNotes = state.tab == "notes"
	setShown(frame.notes, isNotes)
	if isNotes then frame.content:Hide() else frame.content:Show() end
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
	frame.innText:SetText(at and "Perk window open at an innkeeper" or "Perk activations need an innkeeper")
	frame.innText:SetTextColor(unpack(at and C.good or C.muted))
end

local function renderBuild(build)
	frame.name.committed = build.name
	frame.spec.committed = build.spec or ""
	if not frame.name.focused then frame.name:SetText(build.name) end
	if not frame.spec.focused then
		frame.spec:SetText(build.spec or "")
		frame.spec:UpdatePlaceholder()
	end
	local extras = build.pet and S.Hex(C.muted, "  (includes pet aspects)") or ""
	frame.classes:SetText(Window.ClassText(build.classes) .. extras)
	renderTabs(build)
	renderActions(build)
	if state.tab == "notes" then
		if not frame.notes.edit.focused then frame.notes.edit:SetText(build.notes or "") end
		frame.summary:SetText(state.message or "")
	else
		frame.content:Begin()
		local summary = BF.Tabs.render[state.tab](frame.content, build)
		frame.content:End()
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

local function importBuild()
	BF.Dialogs.ShowImport(function(text)
		BF:Import(text, function(build)
			state.collapsed[table.concat(build.classes or {}, "/")] = false
			Window.Select(build.name)
		end)
	end)
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

	f.search = S.Input(side, "BuildForgeSearch", SIDEBAR_W - 24, "Search builds", 40)
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
		"Paste a BuildForge or SynastriaPerkManager string.")
	import:SetPoint("LEFT", new, "RIGHT", 6, 0)
end

local function createBuildHeader(main)
	local f = frame
	-- reads as a title until hovered or edited
	f.name = CreateFrame("EditBox", "BuildForgeNameBox", main)
	f.name:SetSize(320, 30)
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
		if build and BF:Rename(build, newName) then
			state.selected = newName
			self.committed = newName
		end
		self:ClearFocus()
		Window.Render()
	end)

	f.classes = S.Text(main, "small")
	f.classes:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 8, -6)

	local specLabel = S.Text(main, "small", C.muted)
	specLabel:SetPoint("LEFT", f.classes, "RIGHT", 18, 0)
	specLabel:SetText("Spec name")
	f.spec = S.Input(main, "BuildForgeSpecBox", 130, "None", 14)
	f.spec:SetHeight(20)
	f.spec:SetPoint("LEFT", specLabel, "RIGHT", 8, 0)
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

	local apply = S.Button(main, "Apply Build", "primary", 110, function()
		BF.Review.Open(selectedBuild())
	end, "Review what would change on your character, then apply it.")
	apply:SetPoint("TOPRIGHT", -16, -16)
	local export = S.Button(main, "Export", "secondary", 70, function() BF:Export(selectedBuild()) end,
		"Copy this build as a one-line string to share.")
	export:SetPoint("RIGHT", apply, "LEFT", -6, 0)
	local delete = S.Button(main, "Delete", "danger", 70, function() BF:Delete(selectedBuild()) end)
	delete:SetPoint("RIGHT", export, "LEFT", -6, 0)
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
	f.content = BF.List.New(main, "BuildForgeContentScroll", bodyW - 20, bodyH)
	f.content.scroll:SetPoint("TOPLEFT", 8, -bodyTop)
	f.notes = createNotes(main, bodyW - 8, bodyH - 22)
	f.notes:SetPoint("TOPLEFT", 16, -bodyTop - 18)

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
