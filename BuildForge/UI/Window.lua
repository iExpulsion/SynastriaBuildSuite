local _, NS = ...
local BF = NS.BF

local Window = {}
BF.Window = Window

local W, H = 780, 500
local LIST_W, PANE_X = 200, 252
local PANE_W = W - PANE_X - 42
local TABS = {
	{ key = "perks", label = "Perks" },
	{ key = "talents", label = "Talents" },
	{ key = "glyphs", label = "Glyphs" },
	{ key = "gear", label = "Gear" },
	{ key = "notes", label = "Notes" },
}

local frame
local state = { selected = nil, tab = "perks", showAll = false }
Window.state = state

local function setShown(f, shown)
	if shown then f:Show() else f:Hide() end
end

local function trackFocus(e)
	e:HookScript("OnEditFocusGained", function(self) self.focused = true end)
	e:HookScript("OnEditFocusLost", function(self) self.focused = false end)
end

function Window.ClassText(classes)
	local parts = {}
	for _, key in ipairs(classes or {}) do
		local c = RAID_CLASS_COLORS[key]
		local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[key] or key
		parts[#parts + 1] = c and ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name) or name
	end
	return table.concat(parts, " / ")
end

local function button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function editBox(parent, name, width, maxLetters)
	local e = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
	e:SetSize(width, 20)
	e:SetAutoFocus(false)
	e:SetMaxLetters(maxLetters)
	e:SetScript("OnEscapePressed", function(self)
		self:SetText(self.committed or "")
		self:ClearFocus()
	end)
	e:SetScript("OnEditFocusLost", function(self) self:SetText(self.committed or "") end)
	trackFocus(e)
	return e
end

local function sortedBuilds()
	local fits, others = {}, {}
	for _, build in pairs(BF.db.builds) do
		if BF.Build.Fits(build) then fits[#fits + 1] = build else others[#others + 1] = build end
	end
	local byName = function(a, b) return a.name:lower() < b.name:lower() end
	table.sort(fits, byName)
	table.sort(others, byName)
	return fits, others
end

local function selectedBuild()
	return state.selected and BF.db.builds[state.selected]
end

function Window.Select(name)
	state.selected = name
	Window.Render()
end

local function renderList()
	local list = frame.list
	local fits, others = sortedBuilds()
	local applied = BF.charDB.applied[BF:ActiveGroup()]
	list:Begin()
	local function add(build)
		local mark = build.name == applied and " |cff60ff60(applied)|r" or ""
		list:Add({
			text = build.name .. mark,
			selected = build.name == state.selected,
			onClick = function() Window.Select(build.name) end,
			tooltip = function(tt)
				tt:AddLine(build.name, 1, 1, 1)
				tt:AddLine(Window.ClassText(build.classes))
				if build.spec and build.spec ~= "" then tt:AddLine("Spec: " .. build.spec, 0.8, 0.8, 0.8) end
			end,
		})
	end
	for _, build in ipairs(fits) do add(build) end
	if state.showAll and #others > 0 then
		list:Add({ text = "Other Classes", header = true })
		for _, build in ipairs(others) do add(build) end
	end
	list:End()

	if not selectedBuild() or (not state.showAll and not BF.Build.Fits(selectedBuild())) then
		state.selected = fits[1] and fits[1].name or (state.showAll and others[1] and others[1].name) or nil
	end
	setShown(frame.emptyText, #fits == 0 and (#others == 0 or not state.showAll))
	if #fits == 0 and #others > 0 and not state.showAll then
		frame.emptyText:SetText(("No builds for your classes. %d for other classes: tick Show Other Classes."):format(#others))
	else
		frame.emptyText:SetText("No builds yet. Click Save Current to save your character's build.")
	end
end

local function renderTabs()
	for i, tab in ipairs(TABS) do
		local b = frame.tabs[i]
		if tab.key == state.tab then PanelTemplates_SelectTab(b) else PanelTemplates_DeselectTab(b) end
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
			b:SetText(action.label)
			b:SetWidth(math.max(110, b:GetFontString():GetStringWidth() + 24))
			b:SetScript("OnClick", function() action.run(build) end)
			b:Show()
		else
			b:Hide()
		end
	end
end

function Window.Render()
	if frame and frame:IsShown() then
		frame.dirty = false
		renderList()
		local build = selectedBuild()
		setShown(frame.pane, build ~= nil)
		if build then
			frame.name.committed = build.name
			frame.spec.committed = build.spec or ""
			if not frame.name.focused then frame.name:SetText(build.name) end
			if not frame.spec.focused then frame.spec:SetText(build.spec or "") end
			local extras = build.pet and "  |cffaaaaaa+ pet aspects|r" or ""
			frame.classes:SetText(Window.ClassText(build.classes) .. extras)
			renderTabs()
			renderActions(build)
			if state.tab == "notes" then
				if not frame.notes.edit.focused then frame.notes.edit:SetText(build.notes or "") end
				frame.summary:SetText("")
			else
				frame.content:Begin()
				local summary = BF.Tabs.render[state.tab](frame.content, build)
				frame.content:End()
				frame.summary:SetText(summary or "")
			end
		end
	end
end

-- Coalesces bursts of events (bag updates) into one render per frame.
function Window.Refresh()
	if frame then frame.dirty = true end
end

local function createNotes(parent)
	local scroll = CreateFrame("ScrollFrame", "BuildForgeNotesScroll", parent, "UIPanelScrollFrameTemplate")
	scroll:SetSize(PANE_W - 24, H - 230)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(PANE_W - 30)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	edit:SetScript("OnTextChanged", function(self, userInput)
		local build = selectedBuild()
		if userInput and build then build.notes = self:GetText() end
	end)
	trackFocus(edit)
	scroll:SetScrollChild(edit)
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
	scroll.edit = edit
	return scroll
end

local function create()
	local f = CreateFrame("Frame", "BuildForgeFrame", UIParent)
	f:SetSize(W, H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	BF.Dialogs.SetBackdrop(f)
	tinsert(UISpecialFrames, "BuildForgeFrame")

	local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("BuildForge")
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	-- build list
	f.list = BF.List.New(f, "BuildForgeListScroll", LIST_W, H - 140)
	f.list.scroll:SetPoint("TOPLEFT", 20, -44)

	local showAll = CreateFrame("CheckButton", "BuildForgeShowAll", f, "OptionsSmallCheckButtonTemplate")
	showAll:SetPoint("TOPLEFT", f.list.scroll, "BOTTOMLEFT", -4, -4)
	_G["BuildForgeShowAllText"]:SetText("Show Other Classes")
	showAll:SetScript("OnClick", function(self)
		state.showAll = self:GetChecked() and true or false
		Window.Render()
	end)

	local save = button(f, "Save Current", 108, function()
		local build = BF:SaveCurrent(BF:UniqueName("New Build"))
		Window.Select(build.name)
	end)
	save:SetPoint("BOTTOMLEFT", 18, 18)
	local import = button(f, "Import", 100, function()
		BF.Dialogs.ShowImport(function(text)
			BF:Import(text, function(build)
				if not BF.Build.Fits(build) then
					state.showAll = true
					showAll:SetChecked(true)
				end
				Window.Select(build.name)
			end)
		end)
	end)
	import:SetPoint("LEFT", save, "RIGHT", 4, 0)

	f.emptyText = f:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	f.emptyText:SetPoint("TOPLEFT", PANE_X, -60)
	f.emptyText:SetWidth(PANE_W)
	f.emptyText:SetJustifyH("LEFT")

	-- build pane
	local pane = CreateFrame("Frame", nil, f)
	pane:SetPoint("TOPLEFT", PANE_X, -40)
	pane:SetPoint("BOTTOMRIGHT", -20, 14)
	f.pane = pane

	local apply = button(pane, "Apply", 80, function() BF:ConfirmApply(selectedBuild()) end)
	apply:SetPoint("TOPRIGHT", 0, -2)
	local export = button(pane, "Export", 80, function() BF:Export(selectedBuild()) end)
	export:SetPoint("RIGHT", apply, "LEFT", -4, 0)
	local delete = button(pane, "Delete", 80, function() BF:Delete(selectedBuild()) end)
	delete:SetPoint("TOPRIGHT", apply, "BOTTOMRIGHT", 0, -4)

	-- row 1: name and classes, row 2: spec name; both stop short of the buttons on the right
	f.name = editBox(pane, "BuildForgeNameBox", 200, 40)
	f.name:SetPoint("TOPLEFT", 8, -4)
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

	local specLabel = pane:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	specLabel:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", -6, -10)
	specLabel:SetText("Spec Name")
	f.spec = editBox(pane, "BuildForgeSpecBox", 120, 14)
	f.spec:SetPoint("LEFT", specLabel, "RIGHT", 12, 0)
	f.spec:SetScript("OnEnterPressed", function(self)
		local build = selectedBuild()
		if build then
			build.spec = self:GetText()
			self.committed = build.spec
		end
		self:ClearFocus()
	end)

	f.classes = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.classes:SetPoint("LEFT", f.name, "RIGHT", 10, 0)
	f.classes:SetPoint("RIGHT", export, "LEFT", -8, 0)
	f.classes:SetJustifyH("LEFT")

	f.tabs = {}
	for i, tab in ipairs(TABS) do
		local b = CreateFrame("Button", "BuildForgeTab" .. i, pane, "TabButtonTemplate")
		b:SetText(tab.label)
		PanelTemplates_TabResize(b, 0)
		if i == 1 then b:SetPoint("TOPLEFT", 0, -62) else b:SetPoint("LEFT", f.tabs[i - 1], "RIGHT", -4, 0) end
		b:SetScript("OnClick", function()
			state.tab = tab.key
			Window.Render()
		end)
		f.tabs[i] = b
	end

	f.content = BF.List.New(pane, "BuildForgeContentScroll", PANE_W - 24, H - 230)
	f.content.scroll:SetPoint("TOPLEFT", 4, -92)
	f.notes = createNotes(pane)
	f.notes:SetPoint("TOPLEFT", 4, -92)

	f.summary = pane:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	f.summary:SetPoint("BOTTOMLEFT", 6, 36)
	f.summary:SetPoint("RIGHT", -6, 0)
	f.summary:SetJustifyH("LEFT")

	f.actions = {}
	for i = 1, 2 do
		local b = button(pane, "", 110)
		if i == 1 then b:SetPoint("BOTTOMRIGHT", 0, 4) else b:SetPoint("RIGHT", f.actions[i - 1], "LEFT", -4, 0) end
		f.actions[i] = b
	end

	f:SetScript("OnShow", Window.Render)
	f:SetScript("OnUpdate", function(self)
		if self.dirty then Window.Render() end
	end)
	for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
		"GLYPH_ADDED", "GLYPH_REMOVED", "GLYPH_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
		f:RegisterEvent(event)
	end
	f:SetScript("OnEvent", Window.Refresh)
	f:Hide()
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
