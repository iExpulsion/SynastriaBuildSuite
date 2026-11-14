local _, NS = ...
local SBS = NS.SBS

-- The Templates sheet for one tab: every template saved for it, with the ones that don't fit the build greyed and
-- why, and a name box to save the tab as a new template, replace one, or rename the selected one.
local Sheet = {}
SBS.TemplateSheet = Sheet

local W, LIST_H, LABEL_W, BUTTON_W = 460, 220, 44, 80
local sheet
local state = { section = nil, build = nil, selected = nil }
Sheet.state = state

local function trimmed()
	return (sheet.name:GetText():gsub("^%s+", ""):gsub("%s+$", ""))
end

local function note(text)
	sheet.note:SetText(text or "")
end

local function enable(b, on)
	if on then b:Enable() else b:Disable() end
end

function Sheet.Render()
	local S, C, T = SBS.Style, SBS.Style.colors, SBS.Templates
	local label = T.Label(state.section)
	sheet.title:SetText(label .. " Templates")
	sheet.sub:SetText(("Saved for every character. Load one into %s, or save its %s as a new one."):format(state.build.name, label:lower()))
	local list, selected = sheet.list, state.selected and T.Get(state.section, state.selected)
	if not selected then state.selected = nil end
	list:Begin()
	for _, t in ipairs(T.List(state.section)) do
		local fits, reason = T.Fits(state.section, t, state.build)
		list:Add({
			text = fits and t.name or S.Hex(C.muted, t.name),
			sub = T.Describe(state.section, t),
			status = not fits and S.Hex(C.muted, reason) or nil,
			selected = t.name == state.selected,
			onClick = function()
				state.selected = t.name
				sheet.name:SetText(t.name)
				sheet.name:UpdatePlaceholder()
				note()
				Sheet.Render()
			end,
		})
	end
	if list.count == 0 then
		list:Add({ text = S.Hex(C.muted, ("No %s templates yet."):format(label:lower())), sub = "Name one below and click Save." })
	end
	list:End()
	local name = trimmed()
	local fits = selected and T.Fits(state.section, selected, state.build)
	enable(sheet.load, fits)
	enable(sheet.save, name ~= "" and T.CanSave(state.section, state.build))
	enable(sheet.rename, selected ~= nil and name ~= "" and name ~= state.selected)
	enable(sheet.delete, selected ~= nil)
	sheet.save.tooltipText = T.CanSave(state.section, state.build)
		and ("Save this build's %s under the name in the box, replacing a template of that name."):format(label:lower())
		or ("This build has no %s to save."):format(label:lower())
end

local function load()
	local T = SBS.Templates
	local t = T.Get(state.section, state.selected)
	if t and T.Load(state.section, t, state.build) then
		sheet:Hide()
		Sheet.Loaded(t)
	end
end

local function save()
	local T, S, C = SBS.Templates, SBS.Style, SBS.Style.colors
	local name = trimmed()
	local function commit()
		T.Save(state.section, name, state.build)
		state.selected = name
		note(S.Hex(C.good, "Saved " .. name))
		Sheet.Render()
	end
	if T.Get(state.section, name) then SBS.Dialogs.Confirm("SBS_TEMPLATE_REPLACE", name, commit) else commit() end
end

local function rename()
	local S, C = SBS.Style, SBS.Style.colors
	local name = trimmed()
	if SBS.Templates.Rename(state.section, state.selected, name) then
		state.selected = name
		note(S.Hex(C.good, "Renamed to " .. name))
	else
		note(S.Hex(C.bad, "A Template Has That Name"))
	end
	Sheet.Render()
end

local function delete()
	local name = state.selected
	SBS.Dialogs.Confirm("SBS_TEMPLATE_DELETE", name, function()
		SBS.Templates.Delete(state.section, name)
		state.selected = nil
		sheet.name:SetText("")
		sheet.name:UpdatePlaceholder()
		note(SBS.Style.Hex(SBS.Style.colors.muted, "Deleted " .. name))
		Sheet.Render()
	end)
end

local function create()
	local S, C = SBS.Style, SBS.Style.colors
	-- the theme's dialog padding; the dialog grows by the difference from the kit's, so its contents keep their size
	local PAD, GAP, CONTROL_H = S.metrics.inset, S.GAP, S.CONTROL_H
	local grow = 2 * (PAD - S.PAD)
	local listTop = PAD + 16 + 4 + 12 + PAD
	local nameY = listTop + LIST_H + GAP + CONTROL_H / 2
	S.RefreshFonts()
	local f = CreateFrame("Frame", "SynastriaBuildSuiteTemplateFrame", UIParent)
	f:SetSize(W + grow, nameY + CONTROL_H / 2 + PAD + CONTROL_H + PAD)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	SBS.PixelScale(f)
	S.Frame(f, "popup")
	tinsert(UISpecialFrames, "SynastriaBuildSuiteTemplateFrame")
	f:HookScript("OnHide", S.Dismiss)
	f:Hide()

	f.title = S.Text(f, "large")
	f.title:SetPoint("TOPLEFT", PAD, -PAD)
	f.sub = S.Text(f, "small", C.muted)
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	local close = S.Button(f, "Close", "ghost", 56, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", -PAD, -(PAD - 4))

	local well = CreateFrame("Frame", nil, f)
	well:SetPoint("TOPLEFT", PAD, -listTop)
	well:SetSize(W - 2 * S.PAD, LIST_H)
	S.Well(well)
	local wi = 1 + S.metrics.wellInset
	f.list = SBS.List.New(well, "SynastriaBuildSuiteTemplateList", W - 2 * S.PAD - 20 - 2 * wi, LIST_H - 2 * wi)
	f.list.scroll:SetPoint("TOPLEFT", wi, -wi)

	local nameLabel = S.Text(f, "small", C.muted)
	nameLabel:SetPoint("LEFT", f, "TOPLEFT", PAD, -nameY)
	nameLabel:SetText("Name")
	-- the name box takes the row's spare width, so Rename ends in line with the list and Load
	local nameW = W - 2 * S.PAD - LABEL_W - 2 * (BUTTON_W + GAP)
	f.name = S.Input(f, "SynastriaBuildSuiteTemplateName", nameW, "Template Name", 40)
	f.name:SetPoint("LEFT", f, "TOPLEFT", PAD + LABEL_W, -nameY)
	f.name:HookScript("OnTextChanged", function(_, userInput)
		if userInput then Sheet.Render() end
	end)
	f.save = S.Button(f, "Save", "secondary", BUTTON_W, save)
	f.save:SetPoint("LEFT", f.name, "RIGHT", GAP, 0)
	f.rename = S.Button(f, "Rename", "secondary", BUTTON_W, rename, "Give the selected template the name in the box.")
	f.rename:SetPoint("LEFT", f.save, "RIGHT", GAP, 0)

	-- Delete and Load sit under Save and Rename, the four buttons one block in the corner
	f.load = S.Button(f, "Load", "primary", BUTTON_W, load, "Replace this build's tab with the selected template.")
	f.load:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	f.delete = S.Button(f, "Delete", "danger", BUTTON_W, delete, "Delete the selected template.")
	f.delete:SetPoint("RIGHT", f.load, "LEFT", -GAP, 0)
	f.note = S.Text(f, "small", C.muted)
	f.note:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, PAD + CONTROL_H / 2)
	f.note:SetPoint("RIGHT", f.delete, "LEFT", -PAD, 0)
	return f
end

-- Opens the sheet for `section` of `build`. With `saving` the name box starts with a fresh name based on the
-- build's.
function Sheet.Open(section, build, saving)
	SBS.Style.Dismiss()
	sheet = sheet or create()
	state.section, state.build, state.selected = section, build, nil
	sheet.name:SetText(saving and SBS.Templates.UniqueName(section, build.name) or "")
	sheet.name:UpdatePlaceholder()
	note()
	Sheet.Render()
	sheet:Show()
	sheet:Raise()
end

function Sheet.Hide()
	if sheet then sheet:Hide() end
end

function Sheet.Frame()
	return sheet
end

-- After a template loads, the footer says what happened.
function Sheet.Loaded(t)
	SBS:Changed()
	SBS.Window.Message(SBS.Style.Hex(SBS.Style.colors.good, "Loaded " .. t.name .. ": Undo Is in Templates"))
end

StaticPopupDialogs["SBS_TEMPLATE_REPLACE"] = {
	text = "A template named \"%s\" already exists. Replace it?",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function(self) self.data() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["SBS_TEMPLATE_DELETE"] = {
	text = "Delete template \"%s\"?",
	button1 = DELETE,
	button2 = CANCEL,
	OnAccept = function(self) self.data() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}
