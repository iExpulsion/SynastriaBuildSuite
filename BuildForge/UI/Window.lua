local _, NS = ...
local BF = NS.BF

-- A double-wide UI panel built like the 3.3.5 Achievement window (Blizzard_AchievementUI.xml): wood border
-- with metal trim, a header plaque above the frame, a parchment category column for the builds, a dark
-- content pane, and Achievement-style tabs hanging below. Sizes and offsets are Blizzard's.
local Window = {}
BF.Window = Window

local W, H = 768, 500
local CAT_W = 175
local CONTENT_W = 504
local HEADER_H, FOOTER_H = 84, 36
local GOLD = { 1, 0.675, 0.125 }
local ART = "Interface\\AchievementFrame\\"
local TABS = {
	{ key = "perks", label = "Perks" },
	{ key = "talents", label = "Talents" },
	{ key = "glyphs", label = "Glyphs" },
	{ key = "gear", label = "Gear" },
	{ key = "notes", label = "Notes" },
}

local frame
local state = { selected = nil, tab = "perks", collapsed = {} }
Window.state = state

local function setShown(f, shown)
	if shown then f:Show() else f:Hide() end
end

local function trackFocus(e)
	e:HookScript("OnEditFocusGained", function(self) self.focused = true end)
	e:HookScript("OnEditFocusLost", function(self) self.focused = false end)
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

local function button(parent, label, width, onClick, tooltip)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		if self.tooltipText then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b.tooltipText = tooltip
	return b
end

local function goldBorder(f)
	f:SetBackdrop({
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 },
	})
	f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
end

local function texture(parent, layer, file, w, h, coords)
	local t = parent:CreateTexture(nil, layer)
	t:SetTexture(ART .. file)
	if w then t:SetSize(w, h) end
	if coords then t:SetTexCoord(unpack(coords)) end
	return t
end

local function selectedBuild()
	return state.selected and BF.db.builds[state.selected]
end

function Window.Select(name)
	state.selected = name
	Window.Render()
end

-- Builds grouped by class combination; groups that fit the character come first and start expanded.
local function groupedBuilds()
	local groups, byKey = {}, {}
	for _, build in pairs(BF.db.builds) do
		local key = table.concat(build.classes or {}, "/")
		local group = byKey[key]
		if not group then
			group = { key = key, classes = build.classes or {}, fits = BF.Build.Fits(build), builds = {} }
			byKey[key] = group
			groups[#groups + 1] = group
		end
		table.insert(group.builds, build)
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
	return c
end

local function renderList()
	local list = frame.list
	local applied = BF.charDB.applied[BF:ActiveGroup()]
	local first, firstFit, total = nil, nil, 0
	list:Begin()
	for _, group in ipairs(groupedBuilds()) do
		local collapsed = isCollapsed(group)
		local label = group.key == "" and "No Class" or Window.ClassText(group.classes, true)
		list:Add({
			text = group.fits and label or ("|cff9d9d9d" .. label .. "|r"),
			status = "|cffbbbbbb" .. #group.builds .. "|r",
			header = true,
			onClick = function()
				state.collapsed[group.key] = not collapsed
				Window.Render()
			end,
			tooltip = not group.fits and function(tt)
				tt:AddLine(label, 1, 1, 1)
				tt:AddLine("Not your classes. These builds can be viewed and shared, but only parts for your classes apply.", 0.8, 0.8, 0.8, true)
			end or nil,
		})
		for _, build in ipairs(group.builds) do
			total = total + 1
			first = first or build
			if group.fits then firstFit = firstFit or build end
			if not collapsed then
				list:Add({
					text = build.name,
					status = build.name == applied and "|cff40c040Applied|r" or nil,
					selected = build.name == state.selected,
					onClick = function() Window.Select(build.name) end,
					tooltip = function(tt)
						tt:AddLine(build.name, 1, 1, 1)
						tt:AddLine(Window.ClassText(build.classes))
						if build.spec and build.spec ~= "" then tt:AddLine("Spec: " .. build.spec, 0.8, 0.8, 0.8) end
						if build.name == applied then tt:AddLine("Last applied to your active spec.", 0.25, 0.75, 0.25) end
					end,
				})
			end
		end
	end
	list:End()

	if not selectedBuild() then
		local pick = firstFit or first
		state.selected = pick and pick.name or nil
	end
	frame.count:SetText(total == 1 and "1 Build" or (total .. " Builds"))
end

-- Selected Achievement tabs drop their label 2px lower than the others.
local function renderTabs()
	local selected = frame.tabIndex[state.tab]
	PanelTemplates_SetTab(frame, selected)
	for i = 1, #TABS do
		local tab = _G["BuildForgeFrameTab" .. i]
		local text = _G["BuildForgeFrameTab" .. i .. "Text"]
		text:ClearAllPoints()
		text:SetPoint("CENTER", tab, "CENTER", 0, i == selected and -5 or -3)
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
			b:SetWidth(math.max(90, b:GetFontString():GetStringWidth() + 24))
			b:SetScript("OnClick", function() action.run(build) end)
			b.tooltipText = action.tooltip
			b:Show()
		else
			b:Hide()
		end
	end
end

local function renderInnkeeper()
	if BF.Perks.Writable() then
		frame.innkeeper:SetText("|cff40c040Perk window open at an innkeeper|r")
	else
		frame.innkeeper:SetText("|cff9d9d9dPerk activations need an innkeeper|r")
	end
end

function Window.Render()
	if frame and frame:IsShown() then
		frame.dirty = false
		renderList()
		renderInnkeeper()
		renderTabs()
		local build = selectedBuild()
		setShown(frame.detail, build ~= nil)
		setShown(frame.emptyText, build == nil)
		for _, b in ipairs(frame.buildButtons) do
			if build then b:Enable() else b:Disable() end
		end
		if build then
			frame.title.committed = build.name
			frame.spec.committed = build.spec or ""
			if not frame.title.focused then frame.title:SetText(build.name) end
			if not frame.spec.focused then frame.spec:SetText(build.spec or "") end
			local extras = build.pet and "  |cffbbbbbb+ pet aspects|r" or ""
			frame.classes:SetText(Window.ClassText(build.classes) .. extras)
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
		else
			for _, b in ipairs(frame.actions) do b:Hide() end
		end
	end
end

-- Coalesces bursts of events (bag updates) into one render per frame.
function Window.Refresh()
	if frame then frame.dirty = true end
end

local function createTitle(parent)
	local e = CreateFrame("EditBox", "BuildForgeTitleBox", parent)
	e:SetSize(300, 24)
	e:SetAutoFocus(false)
	e:SetMaxLetters(40)
	e:SetFontObject(GameFontNormalLarge)
	e:SetScript("OnEscapePressed", function(self)
		self:SetText(self.committed or "")
		self:ClearFocus()
	end)
	e:SetScript("OnEditFocusLost", function(self) self:SetText(self.committed or "") end)
	e:SetScript("OnEnterPressed", function(self)
		local build = selectedBuild()
		local newName = self:GetText():gsub("^%s+", ""):gsub("%s+$", "")
		if build and BF:Rename(build, newName) then
			state.selected = newName
			self.committed = newName
		end
		self:ClearFocus()
		Window.Render()
	end)
	e:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Click to rename, then press Enter.")
		GameTooltip:Show()
	end)
	e:SetScript("OnLeave", function() GameTooltip:Hide() end)
	trackFocus(e)
	return e
end

local function createSpec(parent)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	label:SetText("Spec Name:")
	local e = CreateFrame("EditBox", "BuildForgeSpecBox", parent, "InputBoxTemplate")
	e:SetSize(120, 18)
	e:SetAutoFocus(false)
	e:SetMaxLetters(14)
	e:SetPoint("LEFT", label, "RIGHT", 10, 0)
	e:SetScript("OnEscapePressed", function(self)
		self:SetText(self.committed or "")
		self:ClearFocus()
	end)
	e:SetScript("OnEditFocusLost", function(self) self:SetText(self.committed or "") end)
	e:SetScript("OnEnterPressed", function(self)
		local build = selectedBuild()
		if build then
			build.spec = self:GetText()
			self.committed = build.spec
		end
		self:ClearFocus()
	end)
	trackFocus(e)
	return label, e
end

local function createNotes(parent, width, height)
	local scroll = CreateFrame("ScrollFrame", "BuildForgeNotesScroll", parent, "UIPanelScrollFrameTemplate")
	scroll:SetSize(width, height)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(GameFontHighlight)
	edit:SetWidth(width - 6)
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

-- The wood and metal frame, copied piece by piece from AchievementFrame.
local function createArt(f)
	f:SetBackdrop({ edgeFile = ART .. "UI-Achievement-WoodBorder", tile = true, tileSize = 32, edgeSize = 64,
		insets = { left = 5, right = 5, top = 5, bottom = 5 } })

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\TutorialFrame\\TutorialFrameBackground")
	bg:SetPoint("TOPLEFT", 16, -16)
	bg:SetPoint("BOTTOMRIGHT", -16, 16)

	local side = H - 64
	texture(f, "ARTWORK", "UI-Achievement-MetalBorder-Left", 16, side, { 0, 1, 0, 0.87 }):SetPoint("LEFT", 14, 0)
	texture(f, "ARTWORK", "UI-Achievement-MetalBorder-Left", 16, side, { 1, 0, 0.87, 0 }):SetPoint("RIGHT", -13, 0)
	local bottom = texture(f, "ARTWORK", "UI-Achievement-MetalBorder-Top", nil, nil, { 0, 0.87, 1, 0 })
	bottom:SetHeight(16)
	bottom:SetPoint("BOTTOMLEFT", 28, 13)
	bottom:SetPoint("BOTTOMRIGHT", -28, 13)
	local top = texture(f, "ARTWORK", "UI-Achievement-MetalBorder-Top", nil, nil, { 0.87, 0, 0, 1 })
	top:SetHeight(16)
	top:SetPoint("TOPLEFT", 28, -12)
	top:SetPoint("TOPRIGHT", -28, -12)

	local parchment = texture(f, "ARTWORK", "UI-Achievement-Parchment")
	parchment:SetWidth(195)
	parchment:SetPoint("TOPLEFT", 25, -23)
	parchment:SetPoint("BOTTOMLEFT", 25, 23)

	texture(f, "OVERLAY", "UI-Achievement-MetalBorder-Joint", 32, 32, { 1, 0, 1, 0 }):SetPoint("TOPLEFT", 9, -7)
	texture(f, "OVERLAY", "UI-Achievement-MetalBorder-Joint", 32, 32, { 0, 1, 1, 0 }):SetPoint("TOPRIGHT", -8, -7)
	texture(f, "OVERLAY", "UI-Achievement-MetalBorder-Joint", 32, 32, { 1, 0, 0, 1 }):SetPoint("BOTTOMLEFT", 9, 8)
	texture(f, "OVERLAY", "UI-Achievement-MetalBorder-Joint", 32, 32, { 0, 1, 0, 1 }):SetPoint("BOTTOMRIGHT", -8, 8)
	texture(f, "OVERLAY", "UI-Achievement-WoodBorder-Corner", 64, 64, { 0, 1, 0, 1 }):SetPoint("TOPLEFT", 4, -2)
	texture(f, "OVERLAY", "UI-Achievement-WoodBorder-Corner", 64, 64, { 1, 0, 0, 1 }):SetPoint("TOPRIGHT", -4, -2)
	texture(f, "OVERLAY", "UI-Achievement-WoodBorder-Corner", 64, 64, { 0, 1, 1, 0 }):SetPoint("BOTTOMLEFT", 4, 3)
	texture(f, "OVERLAY", "UI-Achievement-WoodBorder-Corner", 64, 64, { 1, 0, 1, 0 }):SetPoint("BOTTOMRIGHT", -4, 3)

	-- header plaque above the frame, with the title and build count where Achievements shows points
	local header = CreateFrame("Frame", nil, f)
	header:SetSize(726, 106)
	header:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 26, -39)
	header:EnableMouse(true)
	local hl = texture(header, "BACKGROUND", "UI-Achievement-Header", 512, 106, { 0, 1, 0, 0.4140625 })
	hl:SetPoint("BOTTOMLEFT")
	local hr = texture(header, "BACKGROUND", "UI-Achievement-Header", 215, 100, { 0, 0.419921875, 0.4140625, 0.8046875 })
	hr:SetPoint("BOTTOMLEFT", hl, "BOTTOMRIGHT", 0, -6)
	local plaque = texture(header, "BORDER", "UI-Achievement-Header", 133, 39, { 0.419921875, 0.6796875, 0.4140625, 0.56640625 })
	plaque:SetPoint("BOTTOM", header, "BOTTOM", 20, 16)
	local title = header:CreateFontString(nil, "BORDER", "GameFontNormal")
	title:SetSize(200, 12)
	title:SetPoint("TOP", plaque, "TOP", 0, 7)
	title:SetText("BuildForge")
	f.count = header:CreateFontString(nil, "BORDER", "GameFontHighlight")
	f.count:SetPoint("TOP", plaque, "TOP", 0, -13)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 3, 4)
end

local function createTabs(f)
	-- The Achievement tab template ships in a load-on-demand Blizzard addon.
	local template = LoadAddOn("Blizzard_AchievementUI") and "AchievementFrameTabButtonTemplate" or "CharacterFrameTabButtonTemplate"
	f.tabIndex = {}
	for i, tab in ipairs(TABS) do
		local b = CreateFrame("Button", "BuildForgeFrameTab" .. i, f, template)
		b:SetID(i)
		b:SetText(tab.label)
		if i == 1 then
			b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 11, -30)
		else
			b:SetPoint("LEFT", _G["BuildForgeFrameTab" .. (i - 1)], "RIGHT", -5, 0)
		end
		b:SetScript("OnClick", function()
			PlaySound("igCharacterInfoTab")
			state.tab = tab.key
			Window.Render()
		end)
		f.tabIndex[tab.key] = i
	end
	PanelTemplates_SetNumTabs(f, #TABS)
end

local function createCategories(f)
	local cats = CreateFrame("Frame", nil, f)
	cats:SetWidth(CAT_W)
	cats:SetPoint("TOPLEFT", 21, -19)
	cats:SetPoint("BOTTOMLEFT", 21, 20)
	goldBorder(cats)

	local buttonsH = 32
	f.list = BF.List.New(cats, "BuildForgeListScroll", CAT_W, H - 39 - 10 - buttonsH, "category")
	f.list.scroll:SetPoint("TOPLEFT", 0, -5)
	f.list:DockScrollBar(f.list.scroll, { 1, -14 }, { 1, 12 })

	local new = button(cats, "New", 82, function()
		local build = BF:SaveCurrent(BF:UniqueName("New Build"))
		Window.Select(build.name)
	end, "Save your character's current perks, talents, glyphs and gear as a new build.")
	new:SetPoint("BOTTOMLEFT", 6, 7)
	local import = button(cats, "Import", 82, function()
		BF.Dialogs.ShowImport(function(text)
			BF:Import(text, function(build)
				state.collapsed[table.concat(build.classes or {}, "/")] = false
				Window.Select(build.name)
			end)
		end)
	end, "Paste a BuildForge or SynastriaPerkManager string.")
	import:SetPoint("LEFT", new, "RIGHT", 0, 0)
	return cats
end

local function createContent(f, cats)
	local pane = CreateFrame("Frame", nil, f)
	pane:SetWidth(CONTENT_W)
	pane:SetPoint("TOPLEFT", cats, "TOPRIGHT", 22, 0)
	pane:SetPoint("BOTTOM", cats, "BOTTOM")
	goldBorder(pane)
	local bg = texture(pane, "BACKGROUND", "UI-Achievement-AchievementBackground")
	bg:SetPoint("TOPLEFT", 3, -3)
	bg:SetPoint("BOTTOMRIGHT", -3, 3)

	f.emptyText = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	f.emptyText:SetPoint("TOP", 0, -120)
	f.emptyText:SetWidth(CONTENT_W - 80)
	f.emptyText:SetText("No builds yet. Click New to save your character's current build, or Import to paste one.")

	local detail = CreateFrame("Frame", nil, pane)
	detail:SetAllPoints()
	f.detail = detail

	f.title = createTitle(detail)
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.classes = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.classes:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
	local specLabel
	specLabel, f.spec = createSpec(detail)
	specLabel:SetPoint("TOPLEFT", f.classes, "BOTTOMLEFT", 0, -12)

	f.innkeeper = detail:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	f.innkeeper:SetPoint("TOPRIGHT", -12, -14)
	local delete = button(detail, "Delete", 74, function() BF:Delete(selectedBuild()) end)
	delete:SetPoint("TOPRIGHT", -10, -34)
	local export = button(detail, "Export", 74, function() BF:Export(selectedBuild()) end,
		"Copy this build as a one-line string to share.")
	export:SetPoint("RIGHT", delete, "LEFT", -2, 0)

	local divider = texture(detail, "ARTWORK", "UI-Achievement-HorizontalShadow")
	divider:SetHeight(16)
	divider:SetPoint("TOPLEFT", 6, -HEADER_H + 10)
	divider:SetPoint("TOPRIGHT", -6, -HEADER_H + 10)

	local listH = H - 39 - HEADER_H - FOOTER_H
	f.content = BF.List.New(detail, "BuildForgeContentScroll", CONTENT_W - 16, listH)
	f.content.scroll:SetPoint("TOPLEFT", 8, -HEADER_H)
	f.content:DockScrollBar(pane, { 1, -16 }, { 1, 12 })
	f.notes = createNotes(detail, CONTENT_W - 24, listH)
	f.notes:SetPoint("TOPLEFT", 12, -HEADER_H)
	BF.List.DockBar("BuildForgeNotesScroll", pane, { 1, -16 }, { 1, 12 })
	BF.List.AutoHideBar(f.notes, "BuildForgeNotesScroll")

	f.summary = detail:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	f.summary:SetPoint("BOTTOMLEFT", 14, 14)
	f.summary:SetJustifyH("LEFT")

	f.apply = button(detail, "Apply", 80, function() BF:ConfirmApply(selectedBuild()) end,
		"List what would change in chat, then ask before changing your character.")
	f.apply:SetPoint("BOTTOMRIGHT", -10, 9)
	f.actions = {}
	for i = 1, 2 do
		local b = button(detail, "", 90)
		b:SetPoint("RIGHT", i == 1 and f.apply or f.actions[i - 1], "LEFT", -2, 0)
		f.actions[i] = b
	end
	f.summary:SetPoint("RIGHT", f.actions[2], "LEFT", -8, 0)
	f.buildButtons = { export, delete, f.apply }
end

local function create()
	local f = CreateFrame("Frame", "BuildForgeFrame", UIParent)
	f:SetSize(W, H)
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:Hide()
	UIPanelWindows["BuildForgeFrame"] = { area = "doublewide", pushable = 0, width = 840, xoffset = 80, whileDead = 1 }
	createArt(f)
	createContent(f, createCategories(f))
	createTabs(f)

	f:SetScript("OnShow", function()
		PlaySound("AchievementMenuOpen")
		Window.Render()
	end)
	f:SetScript("OnHide", function() PlaySound("AchievementMenuClose") end)
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
	ShowUIPanel(frame)
	Window.Render()
end

function Window.Toggle()
	if frame and frame:IsShown() then HideUIPanel(frame) else Window.Open() end
end

function Window.Frame()
	return frame
end
