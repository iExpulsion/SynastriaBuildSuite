local _, NS = ...
local SBS = NS.SBS

local Dialogs = {}
SBS.Dialogs = Dialogs

-- The export / import box: a row of section checkboxes (Perks, Talents, Glyphs, Gear, Affixes, Notes) over the string.
-- Export re-encodes as sections are toggled and remembers the choice; import shows which sections the pasted
-- string has and imports only the checked ones, as a new build or into the selected build.
local box

local W, H, TOGGLE_W = 560, 340, 72

local function chosen()
	local sections = {}
	for _, t in ipairs(box.toggles) do
		if t.check.on and t.check.usable then sections[t.key] = true end
	end
	return sections
end

local function setToggles(available, checked)
	for _, t in ipairs(box.toggles) do
		t.check:SetEnabled(available[t.key])
		t.check:SetChecked(available[t.key] and checked[t.key])
		t.label:SetTextColor(unpack(available[t.key] and SBS.Style.colors.text or SBS.Style.colors.muted))
	end
end

local function refreshExport()
	local text = SBS.Codec.Encode(SBS.Codec.Pick(box.build, chosen()))
	box.edit:SetText(text)
	box.edit:SetCursorPosition(0)
	box.note:SetText(SBS.Style.Count(#text, "Character"))
end

local function refreshImport()
	local decoded, err = SBS.Codec.Decode(box.edit:GetText())
	local text = box.edit:GetText():gsub("%s", "")
	local has = decoded and SBS.Codec.Has(decoded) or {}
	setToggles(has, has)
	box.decoded = decoded
	local S, C = SBS.Style, SBS.Style.colors
	if decoded then
		local who = decoded.classes and #decoded.classes > 0 and SBS.Window.ClassText(decoded.classes, true) or "no classes listed"
		box.note:SetText(S.Hex(C.good, (decoded.name or "Unnamed build") .. ": ") .. who)
		-- the string's name, made unique so importing never replaces a build by accident, until the user types one
		if not box.nameEdited then
			box.name:SetText(SBS:UniqueName(decoded.name or "Imported Build"))
			box.name:UpdatePlaceholder()
		end
	else
		box.note:SetText(text == "" and "" or S.Hex(C.bad, err))
	end
	if decoded then box.primary:Enable() box.secondary:Enable() else box.primary:Disable() box.secondary:Disable() end
end

local function toggled(row)
	row.check:SetChecked(not row.check.on)
	if box.mode == "export" then
		SBS.db.exportSections = chosen()
		refreshExport()
	end
end

local function newToggle(parent, section)
	local S = SBS.Style
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(TOGGLE_W, S.CONTROL_H)
	row.key = section.key
	row.check = S.Check(row, 14, function() row:Click() end)
	row.check:SetPoint("LEFT", 0, 0)
	row.label = S.Text(row, "small")
	row.label:SetPoint("LEFT", row.check, "RIGHT", S.GAP, 0)
	row.label:SetText(section.label)
	row:SetScript("OnClick", function(self)
		if self.check.usable then toggled(self) end
	end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self.check.usable and ("Include %s."):format(section.label)
			or (box.mode == "export" and "This build has none." or "The string has none."), nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function create()
	local S, C = SBS.Style, SBS.Style.colors
	local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
	-- rows top to bottom: title and sub line, the Include row, the string, (import: the Name row), the buttons
	local includeY = PAD + 16 + 4 + 12 + GAP + CONTROL_H / 2
	local wellTop = includeY + CONTROL_H / 2 + GAP
	local footerH = PAD + CONTROL_H + PAD
	S.RefreshFonts()
	local f = CreateFrame("Frame", "SynastriaBuildSuiteTextFrame", UIParent)
	f.pad = PAD
	f.wellBottom = { export = footerH, import = footerH + CONTROL_H + PAD }
	f:SetSize(W, H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S.Panel(f, { C.window[1], C.window[2], C.window[3], 1 }, C.border)
	tinsert(UISpecialFrames, "SynastriaBuildSuiteTextFrame")
	f:HookScript("OnHide", S.Dismiss)

	f.title = S.Text(f, "large")
	f.title:SetPoint("TOPLEFT", PAD, -PAD)
	f.sub = S.Text(f, "small", C.muted)
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	-- the close button's box lines up with the title's middle
	local close = S.Button(f, "Close", "ghost", 56, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", -PAD, -(PAD - 4))

	local include = S.Text(f, "small", C.muted)
	include:SetPoint("LEFT", f, "TOPLEFT", PAD, -includeY)
	include:SetText("Include")
	f.toggles = {}
	for i, section in ipairs(SBS.Codec.SECTIONS) do
		local t = newToggle(f, section)
		t:SetPoint("LEFT", include, "RIGHT", PAD + (i - 1) * (TOGGLE_W + GAP), 0)
		f.toggles[i] = t
	end

	local well = CreateFrame("Frame", nil, f)
	well:SetPoint("TOPLEFT", PAD, -wellTop)
	well:SetPoint("BOTTOMRIGHT", -PAD, f.wellBottom.export)
	f.well = well

	-- import only: the Name row, centered between the string and the buttons
	f.nameLabel = S.Text(f, "small", C.muted)
	f.nameLabel:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, footerH + CONTROL_H / 2)
	f.nameLabel:SetText("Name")
	f.name = S.Input(f, "SynastriaBuildSuiteImportName", 240, "Build Name", 40)
	f.name:SetPoint("LEFT", f.nameLabel, "RIGHT", GAP, 0)
	f.name:HookScript("OnTextChanged", function(_, userInput)
		if userInput then box.nameEdited = true end
	end)
	f.nameHint = S.Text(f, "small", C.muted)
	f.nameHint:SetPoint("LEFT", f.name, "RIGHT", GAP, 0)
	f.nameHint:SetText("For Import as New.")
	S.Panel(well, C.well, C.border)
	well:EnableMouse(true)
	local scroll = CreateFrame("ScrollFrame", "SynastriaBuildSuiteTextScroll", well, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", PAD, -PAD)
	scroll:SetPoint("BOTTOMRIGHT", -PAD - 10, PAD)
	SBS.List.AutoHideBar(scroll, "SynastriaBuildSuiteTextScroll")
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	S.SetFont(edit, "edit")
	edit:SetWidth(W - 4 * PAD - 10)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if box.mode == "import" then
			refreshImport()
		elseif userInput then
			refreshExport()
		end
		if box.mode == "import" and self:GetText() == "" then box.placeholder:Show() else box.placeholder:Hide() end
	end)
	-- 3.3.5 gives addons no clipboard access, so the best is selecting the text and confirming the Ctrl+C
	edit:SetScript("OnKeyDown", function(_, key)
		if box.mode == "export" and key == "C" and IsControlKeyDown() then
			box.note:SetText(S.Hex(C.good, "Copied: Paste It Anywhere with Ctrl+V"))
		end
	end)
	scroll:SetScrollChild(edit)
	S.TrackInput(edit)
	well:SetScript("OnMouseDown", function() edit:SetFocus() end)
	f.edit = edit
	f.placeholder = S.Text(well, "normal", C.muted)
	f.placeholder:SetPoint("CENTER")
	f.placeholder:SetText("Click here, then press Ctrl+V.")

	f.note = S.Text(f, "small", C.muted)
	f.note:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, footerH / 2)
	f.primary = S.Button(f, "Import as New", "primary", 110, function()
		local name = box.name:GetText():gsub("^%s+", ""):gsub("%s+$", "")
		if box.onImport then box.onImport(box.edit:GetText(), chosen(), false, name ~= "" and name or nil) end
	end, "Make a new build from the checked sections, under the name above.")
	f.primary:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	f.secondary = S.Button(f, "Into Build", "secondary", 110, function()
		if box.onImport then box.onImport(box.edit:GetText(), chosen(), true) end
	end)
	f.secondary:SetPoint("RIGHT", f.primary, "LEFT", -GAP, 0)
	f.note:SetPoint("RIGHT", f.secondary, "LEFT", -PAD, 0)
	f.selectAll = S.Button(f, "Select All", "primary", 100, function()
		box.edit:SetFocus()
		box.edit:HighlightText()
		box.note:SetText(S.Hex(C.warn, "Selected: Press Ctrl+C to Copy"))
	end, "Select the whole string, ready for Ctrl+C.")
	f.selectAll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	return f
end

-- Shows the build as a string, with the sections last chosen for export.
function Dialogs.ShowExport(build)
	SBS.Style.Dismiss()
	box = box or create()
	box.mode, box.build, box.onImport = "export", build, nil
	box.title:SetText("Export: " .. build.name)
	box.sub:SetText("Select All, then Ctrl+C to copy. Uncheck what you'd rather not share.")
	local remembered = SBS.db.exportSections
	local checked = {}
	for _, section in ipairs(SBS.Codec.SECTIONS) do checked[section.key] = not remembered or remembered[section.key] == true end
	setToggles(SBS.Codec.Has(build), checked)
	box.primary:Hide()
	box.secondary:Hide()
	box.selectAll:Show()
	box.placeholder:Hide()
	for _, w in ipairs({ box.nameLabel, box.name, box.nameHint }) do w:Hide() end
	box.well:SetPoint("BOTTOMRIGHT", -box.pad, box.wellBottom.export)
	refreshExport()
	box:Show()
end

-- Asks for a string; onImport(text, sections, into, name) runs with the checked sections, `into` true when the
-- user chose to import into `targetName` (the selected build) rather than as a new build named `name`.
function Dialogs.ShowImport(onImport, targetName)
	SBS.Style.Dismiss()
	box = box or create()
	box.mode, box.build, box.onImport = "import", nil, onImport
	box.title:SetText("Import a Build")
	box.sub:SetText("Paste a Synastria Build Suite, SBM, SPM or affix order string, then pick the sections to bring in.")
	box.selectAll:Hide()
	box.placeholder:Show()
	for _, w in ipairs({ box.nameLabel, box.name, box.nameHint }) do w:Show() end
	box.well:SetPoint("BOTTOMRIGHT", -box.pad, box.wellBottom.import)
	box.nameEdited = false
	box.name:SetText("")
	box.name:UpdatePlaceholder()
	box.primary:Show()
	box.secondary:SetLabel(targetName and ("Into " .. targetName) or "Into Build")
	box.secondary.tooltipText = targetName and ("Replace those sections of %s with the string's."):format(targetName) or nil
	if targetName then box.secondary:Show() else box.secondary:Hide() end
	box.edit:SetText("")
	refreshImport()
	box:Show()
end

function Dialogs.HideText()
	if box then box:Hide() end
end

function Dialogs.Frame()
	return box
end

-- The New Build sheet: one or two classes, any class, and which sections of the character to copy. Only sections
-- that apply to the chosen classes are copied; with none checked the build starts blank.
local sheet

local COPY = {
	{ key = "perks", label = "Perks" }, { key = "talents", label = "Talents" },
	{ key = "glyphs", label = "Glyphs" }, { key = "gear", label = "Gear" }, { key = "affixes", label = "Affixes" },
}
local NEW_W, LABEL_W, PICK_W = 540, 56, 150
Dialogs.SAVE_SPECS_TIP = "Save every spec on this character as a build linked to it, or refresh the ones already "
	.. "linked. Other specs' perks fill in when you switch to them."
local NOT_YOURS = "Not one of your classes, so there's nothing of it to copy. Perk values, ranks and category "
	.. "limits will show your character's."

local function sheetClasses()
	return { sheet.first, sheet.second }
end

local function ownsAny(classes)
	local any = false
	for _, class in ipairs(classes) do
		if SBS:HasClass(class) then any = true end
	end
	return any
end

local function copyUsable(key)
	return key == "gear" or key == "affixes" or ownsAny(sheetClasses())
end

local function copied()
	local sections = {}
	for _, c in ipairs(COPY) do
		if sheet.wanted[c.key] and copyUsable(c.key) then sections[c.key] = true end
	end
	return sections
end

local function refreshSheet()
	local S, C = SBS.Style, SBS.Style.colors
	sheet.firstPick:SetText(SBS.Window.ClassText({ sheet.first }))
	sheet.secondPick:SetText(sheet.second and SBS.Window.ClassText({ sheet.second }) or "None")
	local sections, names = copied(), {}
	for _, t in ipairs(sheet.toggles) do
		local usable = copyUsable(t.key)
		t.check:SetEnabled(usable)
		t.check:SetChecked(sections[t.key])
		t.label:SetTextColor(unpack(usable and C.text or C.muted))
		if sections[t.key] then names[#names + 1] = t.text end
	end
	local list = #names > 1 and (table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]) or names[1]
	sheet.note:SetText(list and ("Copies " .. list) or S.Hex(C.good, "Blank Build"))
end

local function newCopyToggle(parent, c)
	local S = SBS.Style
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(TOGGLE_W, S.CONTROL_H)
	row.key, row.text = c.key, c.label
	row.check = S.Check(row, 14, function() row:Click() end)
	row.check:SetPoint("LEFT", 0, 0)
	row.label = S.Text(row, "small")
	row.label:SetPoint("LEFT", row.check, "RIGHT", S.GAP, 0)
	row.label:SetText(c.label)
	row:SetScript("OnClick", function(self)
		if copyUsable(self.key) then
			sheet.wanted[self.key] = not sheet.wanted[self.key]
			refreshSheet()
		end
	end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(copyUsable(self.key) and ("Copy your character's %s."):format(c.label:lower())
			or "Neither class is yours, so there's nothing to copy.", nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function classOptions(withNone)
	local options = {}
	if withNone then options[1] = { value = false, text = "None", tooltip = "A single-class build." } end
	for id = 1, 11 do
		local key = SBS.CLASS_KEYS[id]
		if key then
			options[#options + 1] = { value = key, text = SBS.Window.ClassText({ key }),
				tooltip = not SBS:HasClass(key) and NOT_YOURS or nil }
		end
	end
	return options
end

local function createSheet()
	local S, C = SBS.Style, SBS.Style.colors
	local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
	-- rows top to bottom: title and sub line, Classes, Copy, Name, the buttons
	local classesY = PAD + 16 + 4 + 12 + PAD + CONTROL_H / 2
	local copyY = classesY + CONTROL_H + GAP
	local nameY = copyY + CONTROL_H + GAP
	S.RefreshFonts()
	local f = CreateFrame("Frame", "SynastriaBuildSuiteNewFrame", UIParent)
	f:SetSize(NEW_W, nameY + CONTROL_H / 2 + PAD + CONTROL_H + PAD)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S.Panel(f, { C.window[1], C.window[2], C.window[3], 1 }, C.border)
	tinsert(UISpecialFrames, "SynastriaBuildSuiteNewFrame")
	f:HookScript("OnHide", S.Dismiss)

	f.title = S.Text(f, "large")
	f.title:SetPoint("TOPLEFT", PAD, -PAD)
	f.title:SetText("New Build")
	f.sub = S.Text(f, "small", C.muted)
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	f.sub:SetText("Copy parts of your character, or leave them unchecked to start blank.")

	local function rowLabel(text, y)
		local label = S.Text(f, "small", C.muted)
		label:SetPoint("LEFT", f, "TOPLEFT", PAD, -y)
		label:SetText(text)
		return label
	end
	rowLabel("Classes", classesY)
	f.firstPick = S.Dropdown(f, PICK_W, function(key)
		sheet.first = key
		refreshSheet()
	end)
	f.firstPick:SetPoint("LEFT", f, "TOPLEFT", PAD + LABEL_W, -classesY)
	f.firstPick:SetOptions(classOptions(false))
	f.secondPick = S.Dropdown(f, PICK_W, function(key)
		sheet.second = key or nil
		refreshSheet()
	end)
	f.secondPick:SetPoint("LEFT", f.firstPick, "RIGHT", GAP, 0)
	f.secondPick:SetOptions(classOptions(true))

	rowLabel("Copy", copyY)
	f.toggles = {}
	for i, c in ipairs(COPY) do
		local t = newCopyToggle(f, c)
		t:SetPoint("LEFT", f, "TOPLEFT", PAD + LABEL_W + (i - 1) * (TOGGLE_W + GAP), -copyY)
		f.toggles[i] = t
	end

	rowLabel("Name", nameY)
	f.name = S.Input(f, "SynastriaBuildSuiteNewName", PICK_W * 2 + GAP, "Build Name", 40)
	f.name:SetPoint("LEFT", f, "TOPLEFT", PAD + LABEL_W, -nameY)

	f.create = S.Button(f, "Create Build", "primary", 100, function()
		local name = sheet.name:GetText():gsub("^%s+", ""):gsub("%s+$", "")
		sheet.onCreate(name ~= "" and name or SBS:UniqueName("New Build"), sheetClasses(), copied())
	end, "Save the new build and open it.")
	f.create:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	local cancel = S.Button(f, "Cancel", "secondary", 70, function() f:Hide() end)
	cancel:SetPoint("RIGHT", f.create, "LEFT", -GAP, 0)
	f.note = S.Text(f, "small", C.muted)
	f.note:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, PAD + CONTROL_H / 2)
	f.note:SetPoint("RIGHT", cancel, "LEFT", -PAD, 0)
	-- kept apart from the Copy row and its note, in the top corner with the sheet's padding on both sides
	f.saveSpecs = S.Button(f, "Add Current Specs", "secondary", 120, function()
		f:Hide()
		sheet.onSaveSpecs()
	end, Dialogs.SAVE_SPECS_TIP)
	f.saveSpecs:SetPoint("TOPRIGHT", -PAD, -PAD)
	return f
end

-- Opens the sheet set to the character's classes with every section checked; onCreate(name, classes, sections)
-- runs on Create Build, onSaveSpecs() on Add Current Specs.
function Dialogs.ShowNew(onCreate, onSaveSpecs)
	SBS.Style.Dismiss()
	sheet = sheet or createSheet()
	local mine = SBS:PlayerClasses()
	sheet.first, sheet.second, sheet.onCreate, sheet.onSaveSpecs = mine[1], mine[2], onCreate, onSaveSpecs
	sheet.wanted = {}
	for _, c in ipairs(COPY) do sheet.wanted[c.key] = true end
	sheet.name:SetText(SBS:UniqueName("New Build"))
	sheet.name:UpdatePlaceholder()
	refreshSheet()
	sheet:Show()
end

function Dialogs.HideNew()
	if sheet then sheet:Hide() end
end

function Dialogs.NewFrame()
	return sheet
end

StaticPopupDialogs["SBS_APPLY"] = {
	text = "Apply build \"%s\" to your active spec? The changes are listed in chat.",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function(self) self.data() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["SBS_OVERWRITE"] = {
	text = "A build named \"%s\" already exists. Replace it?",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function(self) self.data() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["SBS_DELETE"] = {
	text = "Delete build \"%s\"?",
	button1 = DELETE,
	button2 = CANCEL,
	OnAccept = function(self) self.data() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}


function Dialogs.Confirm(which, name, onAccept)
	local popup = StaticPopup_Show(which, name)
	if popup then popup.data = onAccept end
end
