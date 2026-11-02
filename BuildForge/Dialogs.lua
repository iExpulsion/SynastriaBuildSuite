local _, NS = ...
local BF = NS.BF

local Dialogs = {}
BF.Dialogs = Dialogs

-- The export / import box: a row of section checkboxes (Perks, Talents, Glyphs, Gear, Notes) over the string.
-- Export re-encodes as sections are toggled and remembers the choice; import shows which sections the pasted
-- string has and imports only the checked ones, as a new build or into the selected build.
local box

local W, H, PAD = 560, 340, 16

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
		t.label:SetTextColor(unpack(available[t.key] and BF.Style.colors.text or BF.Style.colors.muted))
	end
end

local function refreshExport()
	local text = BF.Codec.Encode(BF.Codec.Pick(box.build, chosen()))
	box.edit:SetText(text)
	box.edit:SetCursorPosition(0)
	box.note:SetText(("%d characters."):format(#text))
end

local function refreshImport()
	local decoded, err = BF.Codec.Decode(box.edit:GetText())
	local text = box.edit:GetText():gsub("%s", "")
	local has = decoded and BF.Codec.Has(decoded) or {}
	setToggles(has, has)
	box.decoded = decoded
	local S, C = BF.Style, BF.Style.colors
	if decoded then
		local who = decoded.classes and #decoded.classes > 0 and BF.Window.ClassText(decoded.classes, true) or "no classes listed"
		box.note:SetText(S.Hex(C.good, (decoded.name or "Perk string") .. ": ") .. who)
		-- the string's name, made unique so importing never replaces a build by accident, until the user types one
		if not box.nameEdited then
			box.name:SetText(BF:UniqueName(decoded.name or "Imported Build"))
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
		BF.db.exportSections = chosen()
		refreshExport()
	end
end

local function newToggle(parent, section)
	local S = BF.Style
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(84, 20)
	row.key = section.key
	row.check = S.Check(row, 14, function() row:Click() end)
	row.check:SetPoint("LEFT", 0, 0)
	row.label = S.Text(row, "small")
	row.label:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
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
	local S, C = BF.Style, BF.Style.colors
	local f = CreateFrame("Frame", "BuildForgeTextFrame", UIParent)
	f:SetSize(W, H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S.Panel(f, { C.window[1], C.window[2], C.window[3], 1 }, C.border)
	tinsert(UISpecialFrames, "BuildForgeTextFrame")

	f.title = S.Text(f, "large")
	f.title:SetPoint("TOPLEFT", PAD, -PAD)
	f.sub = S.Text(f, "small", C.muted)
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	local close = S.Button(f, "Close", "ghost", 56, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", -8, -10)

	local include = S.Text(f, "small", C.muted)
	include:SetPoint("TOPLEFT", PAD, -62)
	include:SetText("Include")
	f.toggles = {}
	for i, section in ipairs(BF.Codec.SECTIONS) do
		local t = newToggle(f, section)
		t:SetPoint("LEFT", include, "RIGHT", 12 + (i - 1) * 88, 0)
		f.toggles[i] = t
	end

	local well = CreateFrame("Frame", nil, f)
	well:SetPoint("TOPLEFT", PAD, -84)
	well:SetPoint("BOTTOMRIGHT", -PAD, 52)
	f.well = well

	f.nameLabel = S.Text(f, "small", C.muted)
	f.nameLabel:SetPoint("BOTTOMLEFT", PAD, 60)
	f.nameLabel:SetText("Name")
	f.name = S.Input(f, "BuildForgeImportName", 240, "Build Name", 40)
	f.name:SetPoint("LEFT", f.nameLabel, "RIGHT", 10, 0)
	f.name:HookScript("OnTextChanged", function(_, userInput)
		if userInput then box.nameEdited = true end
	end)
	f.nameHint = S.Text(f, "small", C.muted)
	f.nameHint:SetPoint("LEFT", f.name, "RIGHT", 10, 0)
	f.nameHint:SetText("For Import as New.")
	S.Panel(well, { 0.04, 0.04, 0.05, 1 }, C.border)
	well:EnableMouse(true)
	local scroll = CreateFrame("ScrollFrame", "BuildForgeTextScroll", well, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -16, 8)
	BF.List.AutoHideBar(scroll, "BuildForgeTextScroll")
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(W - 2 * PAD - 32)
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
			box.note:SetText(S.Hex(C.good, "Copied. Paste it anywhere with Ctrl+V."))
		end
	end)
	scroll:SetScrollChild(edit)
	well:SetScript("OnMouseDown", function() edit:SetFocus() end)
	f.edit = edit
	f.placeholder = S.Text(well, "normal", C.muted)
	f.placeholder:SetPoint("CENTER")
	f.placeholder:SetText("Click here, then press Ctrl+V.")

	f.note = S.Text(f, "small", C.muted)
	f.note:SetPoint("BOTTOMLEFT", PAD, 20)
	f.primary = S.Button(f, "Import as New", "primary", 110, function()
		local name = box.name:GetText():gsub("^%s+", ""):gsub("%s+$", "")
		if box.onImport then box.onImport(box.edit:GetText(), chosen(), false, name ~= "" and name or nil) end
	end, "Make a new build from the checked sections, under the name above.")
	f.primary:SetPoint("BOTTOMRIGHT", -PAD, 14)
	f.secondary = S.Button(f, "Into Build", "secondary", 110, function()
		if box.onImport then box.onImport(box.edit:GetText(), chosen(), true) end
	end)
	f.secondary:SetPoint("RIGHT", f.primary, "LEFT", -6, 0)
	f.note:SetPoint("RIGHT", f.secondary, "LEFT", -12, 0)
	f.selectAll = S.Button(f, "Select All", "primary", 100, function()
		box.edit:SetFocus()
		box.edit:HighlightText()
		box.note:SetText(S.Hex(C.warn, "Selected. Press Ctrl+C to copy."))
	end, "Select the whole string, ready for Ctrl+C.")
	f.selectAll:SetPoint("BOTTOMRIGHT", -PAD, 14)
	return f
end

-- Shows the build as a string, with the sections last chosen for export.
function Dialogs.ShowExport(build)
	box = box or create()
	box.mode, box.build, box.onImport = "export", build, nil
	box.title:SetText("Export: " .. build.name)
	box.sub:SetText("Select All, then Ctrl+C to copy. Uncheck what you'd rather not share.")
	local remembered = BF.db.exportSections
	local checked = {}
	for _, section in ipairs(BF.Codec.SECTIONS) do checked[section.key] = not remembered or remembered[section.key] == true end
	setToggles(BF.Codec.Has(build), checked)
	box.primary:Hide()
	box.secondary:Hide()
	box.selectAll:Show()
	box.placeholder:Hide()
	for _, w in ipairs({ box.nameLabel, box.name, box.nameHint }) do w:Hide() end
	box.well:SetPoint("BOTTOMRIGHT", -PAD, 52)
	refreshExport()
	box:Show()
end

-- Asks for a string; onImport(text, sections, into, name) runs with the checked sections, `into` true when the
-- user chose to import into `targetName` (the selected build) rather than as a new build named `name`.
function Dialogs.ShowImport(onImport, targetName)
	box = box or create()
	box.mode, box.build, box.onImport = "import", nil, onImport
	box.title:SetText("Import a Build")
	box.sub:SetText("Paste a BuildForge or SynastriaPerkManager string, then pick the sections to bring in.")
	box.selectAll:Hide()
	box.placeholder:Show()
	for _, w in ipairs({ box.nameLabel, box.name, box.nameHint }) do w:Show() end
	box.well:SetPoint("BOTTOMRIGHT", -PAD, 84)
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

StaticPopupDialogs["BUILDFORGE_APPLY"] = {
	text = "Apply build \"%s\" to your active spec? The changes are listed in chat.",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function(self) self.data() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["BUILDFORGE_OVERWRITE"] = {
	text = "A build named \"%s\" already exists. Replace it?",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function(self) self.data() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["BUILDFORGE_DELETE"] = {
	text = "Delete build \"%s\"?",
	button1 = DELETE,
	button2 = CANCEL,
	OnAccept = function(self) self.data() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["BUILDFORGE_SHARED"] = {
	text = "This build includes %s Misc perk(s). Add them to your Shared Perks, which every build applies?",
	button1 = ACCEPT,
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
