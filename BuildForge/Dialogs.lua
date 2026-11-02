local _, NS = ...
local BF = NS.BF

local Dialogs = {}
BF.Dialogs = Dialogs

local textFrame

-- The stock dialog background is mostly see-through, so fill with a near-opaque dark color instead.
function Dialogs.SetBackdrop(f)
	f:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	f:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
end

local function createTextFrame()
	local f = CreateFrame("Frame", "BuildForgeTextFrame", UIParent)
	f:SetSize(520, 260)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	Dialogs.SetBackdrop(f)
	tinsert(UISpecialFrames, "BuildForgeTextFrame")

	f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	f.title:SetPoint("TOP", 0, -16)

	local scroll = CreateFrame("ScrollFrame", "BuildForgeTextScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 20, -38)
	scroll:SetPoint("BOTTOMRIGHT", -40, 48)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(450)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	scroll:SetScrollChild(edit)
	f.edit = edit

	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(90, 22)
	close:SetPoint("BOTTOMRIGHT", -18, 16)
	close:SetText(CLOSE)
	close:SetScript("OnClick", function() f:Hide() end)

	f.action = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.action:SetSize(90, 22)
	f.action:SetPoint("RIGHT", close, "LEFT", -6, 0)
	f.action:SetText("Import")
	return f
end

local function showText(title, text, onImport)
	textFrame = textFrame or createTextFrame()
	textFrame.title:SetText(title)
	textFrame.edit:SetText(text or "")
	textFrame.edit:SetCursorPosition(0)
	if onImport then
		textFrame.action:SetScript("OnClick", function() onImport(textFrame.edit:GetText()) end)
		textFrame.action:Show()
	else
		textFrame.action:Hide()
	end
	textFrame:Show()
end

function Dialogs.ShowExport(name, text)
	showText("Export: " .. name .. " (click, Ctrl+A, Ctrl+C)", text)
end

function Dialogs.ShowImport(onImport)
	showText("Import a Build (paste, then Import)", "", onImport)
end

function Dialogs.HideText()
	if textFrame then textFrame:Hide() end
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
