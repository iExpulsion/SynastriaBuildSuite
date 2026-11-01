local _, NS = ...
local BF = NS.BF

-- A double-wide UI panel laid out like the 3.3.5 Quest Log: build list on the left, parchment details on the
-- right, tabs under the frame. Sizes and offsets follow QuestLogFrame.xml / QuestLogFrame.lua.
local Window = {}
BF.Window = Window

local W, H = 682, 447
local LIST_X, LIST_Y, LIST_W, LIST_H = 19, -75, 298, 335
local DETAIL_X, DETAIL_Y, DETAIL_W, DETAIL_H = 352, -77, 298, 333
local HEADER_H, SUMMARY_H = 74, 34
local CONTENT_H = DETAIL_H - HEADER_H - SUMMARY_H
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

-- Class names in class colors, or plain for dark text on parchment.
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
	local groups = groupedBuilds()
	local applied = BF.charDB.applied[BF:ActiveGroup()]
	local first, firstFit, total = nil, nil, 0
	list:Begin()
	for _, group in ipairs(groups) do
		local collapsed = isCollapsed(group)
		local label = group.key == "" and "No Class" or Window.ClassText(group.classes)
		list:Add({
			text = label .. (group.fits and "" or " |cff808080(not your classes)|r"),
			status = "|cff808080" .. #group.builds .. "|r",
			header = true, collapsed = collapsed,
			onClick = function()
				state.collapsed[group.key] = not collapsed
				Window.Render()
			end,
		})
		for _, build in ipairs(group.builds) do
			total = total + 1
			first = first or build
			if group.fits then firstFit = firstFit or build end
			if not collapsed then
				local color = group.fits and "" or "|cff9d9d9d"
				list:Add({
					text = color .. build.name .. (color ~= "" and "|r" or ""),
					status = build.name == applied and "|cff40c040Applied|r" or nil,
					indent = 10,
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

local function renderTabs()
	PanelTemplates_SetTab(frame, frame.tabIndex[state.tab])
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
			local extras = build.pet and ", with pet aspects" or ""
			frame.classes:SetText(Window.ClassText(build.classes, true) .. extras)
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
		else
			for _, b in ipairs(frame.actions) do b:Hide() end
		end
	end
end

-- Coalesces bursts of events (bag updates) into one render per frame.
function Window.Refresh()
	if frame then frame.dirty = true end
end

-- The art draws the scroll track down the whole detail pane, so the bar spans it too (as in the Quest Log),
-- even though the list below the header is shorter.
local function dockScrollBar(scrollName, detail)
	local bar = _G[scrollName .. "ScrollBar"]
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", detail, "TOPRIGHT", 6, -16)
	bar:SetPoint("BOTTOMLEFT", detail, "BOTTOMRIGHT", 6, 16)
end

local function createTitle(parent)
	local e = CreateFrame("EditBox", "BuildForgeTitleBox", parent)
	e:SetSize(DETAIL_W - 10, 26)
	e:SetAutoFocus(false)
	e:SetMaxLetters(40)
	e:SetFontObject(QuestTitleFont)
	e:SetTextInsets(0, 0, 0, 0)
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
	local label = parent:CreateFontString(nil, "ARTWORK", "QuestFontNormalSmall")
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

local function createNotes(parent)
	local scroll = CreateFrame("ScrollFrame", "BuildForgeNotesScroll", parent, "UIPanelScrollFrameTemplate")
	scroll:SetSize(DETAIL_W, CONTENT_H)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(QuestFont)
	edit:SetWidth(DETAIL_W - 6)
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

local function createArt(f)
	f.portrait = f:CreateTexture(nil, "BACKGROUND")
	f.portrait:SetSize(60, 60)
	f.portrait:SetPoint("TOPLEFT", 5, -5)

	local left = f:CreateTexture(nil, "BORDER")
	left:SetTexture("Interface\\QuestFrame\\UI-QuestLogDualPane-Left")
	left:SetSize(512, 445)
	left:SetPoint("TOPLEFT")
	left:SetTexCoord(0, 1, 0, 0.86914)
	local right = f:CreateTexture(nil, "BORDER")
	right:SetTexture("Interface\\QuestFrame\\UI-QuestLogDualPane-RIGHT")
	right:SetSize(170, 445)
	right:SetPoint("TOPRIGHT")
	right:SetTexCoord(0, 0.6640625, 0, 0.86914)

	local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetSize(300, 14)
	title:SetPoint("TOP", 0, -15)
	title:SetText("BuildForge")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, -8)
end

local function createTabs(f)
	f.tabIndex = {}
	for i, tab in ipairs(TABS) do
		local b = CreateFrame("Button", "BuildForgeFrameTab" .. i, f, "CharacterFrameTabButtonTemplate")
		b:SetID(i)
		b:SetText(tab.label)
		if i == 1 then
			b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", DETAIL_X - 12, 12)
		else
			b:SetPoint("LEFT", _G["BuildForgeFrameTab" .. (i - 1)], "RIGHT", -16, 0)
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

local function create()
	local f = CreateFrame("Frame", "BuildForgeFrame", UIParent)
	f:SetSize(W, H)
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:Hide()
	UIPanelWindows["BuildForgeFrame"] = { area = "doublewide", pushable = 0, whileDead = 1 }
	createArt(f)

	-- left: build list
	f.count = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	f.count:SetPoint("TOPRIGHT", f, "TOPLEFT", LIST_X + LIST_W, -52)
	f.list = BF.List.New(f, "BuildForgeListScroll", LIST_W, LIST_H)
	f.list.scroll:SetPoint("TOPLEFT", LIST_X, LIST_Y)

	local new = button(f, "New", 72, function()
		local build = BF:SaveCurrent(BF:UniqueName("New Build"))
		Window.Select(build.name)
	end, "Save your character's current perks, talents, glyphs and gear as a new build.")
	new:SetPoint("BOTTOMLEFT", 18, 14)
	local import = button(f, "Import", 72, function()
		BF.Dialogs.ShowImport(function(text)
			BF:Import(text, function(build)
				state.collapsed[table.concat(build.classes or {}, "/")] = false
				Window.Select(build.name)
			end)
		end)
	end, "Paste a BuildForge or SynastriaPerkManager string.")
	import:SetPoint("LEFT", new, "RIGHT", 2, 0)
	local export = button(f, "Export", 72, function() BF:Export(selectedBuild()) end,
		"Copy this build as a one-line string to share.")
	export:SetPoint("LEFT", import, "RIGHT", 2, 0)
	local delete = button(f, "Delete", 72, function() BF:Delete(selectedBuild()) end)
	delete:SetPoint("LEFT", export, "RIGHT", 2, 0)
	f.buildButtons = { export, delete }

	-- right: parchment details
	f.innkeeper = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	f.innkeeper:SetPoint("TOPRIGHT", -34, -52)

	f.emptyText = f:CreateFontString(nil, "ARTWORK", "QuestFont")
	f.emptyText:SetPoint("TOPLEFT", DETAIL_X + 10, DETAIL_Y - 120)
	f.emptyText:SetWidth(DETAIL_W - 20)
	f.emptyText:SetText("No builds yet. Click New to save your character's current build, or Import to paste one.")

	local detail = CreateFrame("Frame", nil, f)
	detail:SetPoint("TOPLEFT", DETAIL_X, DETAIL_Y)
	detail:SetSize(DETAIL_W, DETAIL_H)
	f.detail = detail

	f.title = createTitle(detail)
	f.title:SetPoint("TOPLEFT", 4, -2)
	f.classes = detail:CreateFontString(nil, "ARTWORK", "QuestFontNormalSmall")
	f.classes:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
	f.classes:SetWidth(DETAIL_W - 10)
	f.classes:SetJustifyH("LEFT")
	local specLabel
	specLabel, f.spec = createSpec(detail)
	specLabel:SetPoint("TOPLEFT", f.classes, "BOTTOMLEFT", 0, -10)

	f.content = BF.List.New(detail, "BuildForgeContentScroll", DETAIL_W, CONTENT_H, "parchment")
	f.content.scroll:SetPoint("TOPLEFT", 0, -HEADER_H)
	f.notes = createNotes(detail)
	f.notes:SetPoint("TOPLEFT", 0, -HEADER_H)
	dockScrollBar("BuildForgeContentScroll", detail)
	dockScrollBar("BuildForgeNotesScroll", detail)

	f.summary = detail:CreateFontString(nil, "ARTWORK", "QuestFontNormalSmall")
	f.summary:SetPoint("BOTTOMLEFT", 6, 12)
	f.summary:SetWidth(DETAIL_W - 22)
	f.summary:SetJustifyH("LEFT")

	f.apply = button(f, "Apply", 80, function() BF:ConfirmApply(selectedBuild()) end,
		"List what would change in chat, then ask before changing your character.")
	f.apply:SetPoint("BOTTOMRIGHT", -7, 14)
	table.insert(f.buildButtons, f.apply)
	f.actions = {}
	for i = 1, 2 do
		local b = button(f, "", 90)
		b:SetPoint("RIGHT", i == 1 and f.apply or f.actions[i - 1], "LEFT", -2, 0)
		f.actions[i] = b
	end

	createTabs(f)

	f:SetScript("OnShow", function(self)
		SetPortraitTexture(self.portrait, "player")
		PlaySound("igCharacterInfoOpen")
		Window.Render()
	end)
	f:SetScript("OnHide", function() PlaySound("igCharacterInfoClose") end)
	f:SetScript("OnUpdate", function(self)
		if self.dirty then Window.Render() end
	end)
	for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
		"GLYPH_ADDED", "GLYPH_REMOVED", "GLYPH_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED", "UNIT_PORTRAIT_UPDATE" }) do
		f:RegisterEvent(event)
	end
	f:SetScript("OnEvent", function(self, event, unit)
		if event == "UNIT_PORTRAIT_UPDATE" then
			if unit == "player" then SetPortraitTexture(self.portrait, "player") end
		else
			Window.Refresh()
		end
	end)
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
