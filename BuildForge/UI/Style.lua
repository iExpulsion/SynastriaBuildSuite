local _, NS = ...
local BF = NS.BF

-- Flat dark style kit: one accent color, 1px borders, and a few button kinds.
local S = {}
BF.Style = S

local WHITE = "Interface\\Buttons\\WHITE8X8"

S.colors = {
	window = { 0.06, 0.06, 0.08, 0.97 },
	sidebar = { 0.085, 0.085, 0.105, 1 },
	panel = { 0.11, 0.11, 0.135, 1 },
	border = { 0.22, 0.22, 0.27, 1 },
	hover = { 1, 1, 1, 0.06 },
	selected = { 1, 0.5, 0.13, 0.14 },
	accent = { 1, 0.5, 0.13, 1 },
	accentHover = { 1, 0.6, 0.28, 1 },
	text = { 0.93, 0.93, 0.93, 1 },
	muted = { 0.6, 0.6, 0.66, 1 },
	good = { 0.42, 0.86, 0.42, 1 },
	warn = { 1, 0.78, 0.26, 1 },
	bad = { 1, 0.42, 0.42, 1 },
}

function S.Hex(c, text)
	return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, text)
end

function S.Panel(frame, bg, border)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = border and WHITE or nil, edgeSize = 1 })
	frame:SetBackdropColor(unpack(bg))
	if border then frame:SetBackdropBorderColor(unpack(border)) end
end

function S.Solid(parent, layer, color)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(WHITE)
	t:SetVertexColor(unpack(color))
	return t
end

-- 1px line along the bottom (or top) of a frame.
function S.Rule(parent, where)
	local t = S.Solid(parent, "BORDER", S.colors.border)
	t:SetHeight(1)
	t:SetPoint(where .. "LEFT")
	t:SetPoint(where .. "RIGHT")
	return t
end

local hidden = CreateFrame("Frame")
hidden:Hide()

-- Restyles a UIPanelScrollFrameTemplate bar as a thin flat track and thumb. ScrollFrame_OnScrollRangeChanged
-- shows the arrow buttons again on every range change, so they go under a hidden parent instead.
function S.ScrollBar(scroll, scrollName)
	local bar = _G[scrollName .. "ScrollBar"]
	_G[scrollName .. "ScrollBarScrollUpButton"]:SetParent(hidden)
	_G[scrollName .. "ScrollBarScrollDownButton"]:SetParent(hidden)
	bar:SetWidth(6)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
	local track = S.Solid(bar, "BACKGROUND", { 1, 1, 1, 0.04 })
	track:SetAllPoints()
	bar:SetThumbTexture(WHITE)
	local thumb = bar:GetThumbTexture()
	thumb:SetSize(6, 40)
	thumb:SetVertexColor(unpack(S.colors.border))
	bar:HookScript("OnEnter", function() thumb:SetVertexColor(unpack(S.colors.muted)) end)
	bar:HookScript("OnLeave", function() thumb:SetVertexColor(unpack(S.colors.border)) end)
	return bar
end

local FONTS ={ small = "GameFontHighlightSmall", normal = "GameFontHighlight", large = "GameFontHighlightLarge", huge = "GameFontNormalHuge" }

function S.Text(parent, size, color, layer)
	local fs = parent:CreateFontString(nil, layer or "ARTWORK", FONTS[size or "normal"])
	fs:SetTextColor(unpack(color or S.colors.text))
	fs:SetJustifyH("LEFT")
	return fs
end

local BUTTONS = {
	primary = { bg = S.colors.accent, hover = S.colors.accentHover, border = S.colors.accent, text = { 0.08, 0.05, 0.02, 1 }, flat = true },
	secondary = { bg = { 0.17, 0.17, 0.21, 1 }, hover = { 0.23, 0.23, 0.28, 1 }, border = S.colors.border, text = S.colors.text },
	danger = { bg = { 0.17, 0.17, 0.21, 1 }, hover = { 0.36, 0.13, 0.13, 1 }, border = S.colors.border, text = S.colors.bad },
	ghost = { bg = { 0, 0, 0, 0 }, hover = S.colors.hover, border = { 0, 0, 0, 0 }, text = S.colors.muted },
}

local function paint(b)
	local kind = BUTTONS[b.kind]
	local enabled = b:IsEnabled() == 1 or b:IsEnabled() == true
	b:SetBackdropColor(unpack(b.hovered and enabled and kind.hover or kind.bg))
	b:SetBackdropBorderColor(unpack(kind.border))
	local c = enabled and kind.text or S.colors.muted
	b.label:SetTextColor(c[1], c[2], c[3], enabled and 1 or 0.5)
	b.label:SetShadowColor(0, 0, 0, kind.flat and 0 or 1)
end

function S.Button(parent, label, kind, width, onClick, tooltip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 90, 24)
	b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	b.kind = kind or "secondary"
	b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	b.label:SetPoint("CENTER")
	b.label:SetText(label)
	b.tooltipText = tooltip
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		self.hovered = true
		paint(self)
		if self.tooltipText then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self.hovered = false
		paint(self)
		GameTooltip:Hide()
	end)
	b:HookScript("OnEnable", paint)
	b:HookScript("OnDisable", paint)
	function b:SetKind(newKind)
		self.kind = newKind
		paint(self)
	end
	function b:SetLabel(text)
		self.label:SetText(text)
		self:SetWidth(math.max(self.minWidth or 70, self.label:GetStringWidth() + 24))
	end
	b.minWidth = width
	paint(b)
	return b
end

local function paintCheck(b)
	if b.on then b.fill:Show() else b.fill:Hide() end
	b.fill:SetAlpha(b.usable and 1 or 0.4)
	b:SetBackdropBorderColor(unpack(b.hovered and b.usable and S.colors.accent or S.colors.border))
end

-- Square flat checkbox: SetChecked(on) and SetEnabled(on) repaint it; clicks go to onClick(box).
function S.Check(parent, size, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size or 14, size or 14)
	S.Panel(b, { 0.04, 0.04, 0.05, 1 }, S.colors.border)
	b.fill = S.Solid(b, "ARTWORK", S.colors.accent)
	b.fill:SetPoint("TOPLEFT", 3, -3)
	b.fill:SetPoint("BOTTOMRIGHT", -3, 3)
	b.fill:Hide()
	b.on, b.usable = false, true
	function b:SetChecked(on) self.on = on and true or false paintCheck(self) end
	function b:SetEnabled(on) self.usable = on and true or false paintCheck(self) end
	b:SetScript("OnEnter", function(self)
		self.hovered = true
		paintCheck(self)
		if self.tooltipText then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self.hovered = false
		paintCheck(self)
		GameTooltip:Hide()
	end)
	b:SetScript("OnClick", function(self)
		if self.usable and onClick then onClick(self) end
	end)
	paintCheck(b)
	return b
end

-- Flat dropdown: a button showing the current choice that opens a menu below it. SetOptions takes
-- { { value, text, tooltip } }; picking one calls onSelect(value) and closes the menu.
function S.Dropdown(parent, width, onSelect)
	local b = S.Button(parent, "", "secondary", width)
	b:SetHeight(20)
	b.label:ClearAllPoints()
	b.label:SetPoint("LEFT", 8, 0)
	b.label:SetPoint("RIGHT", -20, 0)
	b.label:SetJustifyH("LEFT")
	local arrow = b:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	arrow:SetSize(12, 12)
	arrow:SetPoint("RIGHT", -5, -2)
	arrow:SetDesaturated(true)
	arrow:SetVertexColor(unpack(S.colors.muted))

	local menu = CreateFrame("Frame", nil, b)
	menu:SetFrameStrata("DIALOG")
	menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
	menu:SetWidth(width)
	S.Panel(menu, S.colors.panel, S.colors.border)
	menu:EnableMouse(true)
	menu:Hide()
	b.menu, b.items = menu, {}

	function b:SetText(text) self.label:SetText(text) end
	function b:SetOptions(options)
		for i, opt in ipairs(options) do
			local item = self.items[i]
			if not item then
				item = CreateFrame("Button", nil, menu)
				item:SetHeight(20)
				item:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
				item:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 20)
				local hover = S.Solid(item, "HIGHLIGHT", S.colors.hover)
				hover:SetAllPoints()
				item.text = S.Text(item, "small")
				item.text:SetPoint("LEFT", 8, 0)
				item.text:SetPoint("RIGHT", -8, 0)
				item:SetScript("OnClick", function(it)
					menu:Hide()
					onSelect(it.value)
				end)
				item:SetScript("OnEnter", function(it)
					if it.tooltip then
						GameTooltip:SetOwner(it, "ANCHOR_RIGHT")
						GameTooltip:SetText(it.tooltip, nil, nil, nil, nil, true)
						GameTooltip:Show()
					end
				end)
				item:SetScript("OnLeave", function() GameTooltip:Hide() end)
				self.items[i] = item
			end
			item.value, item.tooltip = opt.value, opt.tooltip
			item.text:SetText(opt.text)
			item:Show()
		end
		for i = #options + 1, #self.items do self.items[i]:Hide() end
		menu:SetHeight(#options * 20 + 2)
	end
	b:SetScript("OnClick", function()
		if menu:IsShown() then menu:Hide() else menu:Show() end
	end)
	b:HookScript("OnHide", function() menu:Hide() end)
	return b
end

-- Single-line input with a placeholder shown while it's empty and unfocused. Never takes focus on its own.
function S.Input(parent, name, width, placeholder, maxLetters)
	local e = CreateFrame("EditBox", name, parent)
	e:SetSize(width, 22)
	e:SetAutoFocus(false)
	e:SetMaxLetters(maxLetters or 40)
	e:SetFontObject(GameFontHighlightSmall)
	e:SetTextInsets(8, 8, 0, 0)
	S.Panel(e, { 0.04, 0.04, 0.05, 1 }, S.colors.border)
	e.placeholder = S.Text(e, "small", S.colors.muted)
	e.placeholder:SetPoint("LEFT", 8, 0)
	e.placeholder:SetText(placeholder or "")
	local function update(self)
		if self.focused or self:GetText() ~= "" then self.placeholder:Hide() else self.placeholder:Show() end
		self:SetBackdropBorderColor(unpack(self.focused and S.colors.accent or S.colors.border))
	end
	e:SetScript("OnEditFocusGained", function(self) self.focused = true update(self) end)
	e:SetScript("OnEditFocusLost", function(self) self.focused = false update(self) end)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:HookScript("OnTextChanged", update)
	e.UpdatePlaceholder = update
	update(e)
	return e
end
