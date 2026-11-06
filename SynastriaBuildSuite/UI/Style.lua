-- Vendored from MaterialCraftUI b4a438f. Change it there, then run tools/sync_style.py.
-- MaterialCraftUI: a flat dark style kit for WoW 3.3.5 addons on Material 3 color roles: one accent color, 1px
-- borders, state layers and a few button kinds. Each addon ships its own copy, listed in its .toc, and reads it
-- as NS.Style from its addon table; font objects are named after the addon, so copies never clash.
local ADDON, NS = ...
local S = {}
NS.Style = S

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function rgb(hex, alpha)
	return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, alpha or 1 }
end

-- `over` laid on `base` at `alpha`: Material's state layers (hover 8%, pressed 12%, disabled fill 12%).
local function blend(base, over, alpha)
	local out = {}
	for i = 1, 3 do out[i] = base[i] + (over[i] - base[i]) * alpha end
	out[4] = base[4]
	return out
end

-- Material 3's baseline dark scheme (seed #6750a4). It has no success or warning roles, so those are custom
-- colors.
local DEFAULT_SCHEME = {
	surfaceLowest = rgb("0f0d13"),
	surface = rgb("141218"),
	surfaceLow = rgb("1d1b20"),
	surfaceContainer = rgb("211f26"),
	surfaceHigh = rgb("2b2930"),
	onSurface = rgb("e6e0e9"),
	onSurfaceVariant = rgb("cac4d0"),
	outline = rgb("938f99"),
	outlineVariant = rgb("49454f"),
	primary = rgb("d0bcff"),
	onPrimary = rgb("381e72"),
	error = rgb("f2b8b5"),
	errorContainer = rgb("8c1d18"),
	success = rgb("78dc77"),
	warning = rgb("ffb870"),
}

local M3 = {}
S.colors = {}
local BUTTONS, DISABLED = {}, {}
local qualityColors = {}

local function withAlpha(c, a)
	return { c[1], c[2], c[3], a }
end

-- Text on an accent the scheme didn't give one for: a dark shade of a light accent, a light tint of a dark one.
local function onColor(c)
	local light = 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] > 0.5
	return light and blend(c, { 0, 0, 0 }, 0.75) or blend(c, { 1, 1, 1 }, 0.9)
end

-- Fills S.colors and the button kinds from M3. S.colors is filled in place, so tables addons hold on to stay live
-- and colors they added stay put.
local function build()
	local c = S.colors
	c.window = withAlpha(M3.surface, 0.97)
	c.sidebar = M3.surfaceLow
	c.panel = M3.surfaceContainer
	c.well = M3.surfaceLowest
	c.border = M3.outlineVariant
	c.outline = M3.outline
	c.hover = withAlpha(M3.onSurface, 0.08)
	c.selected = withAlpha(M3.primary, 0.12)
	c.accent = M3.primary
	c.accentHover = blend(M3.primary, M3.onPrimary, 0.08)
	c.onAccent = M3.onPrimary
	c.text = M3.onSurface
	c.heading = M3.primary
	c.muted = M3.onSurfaceVariant
	c.disabled = withAlpha(M3.onSurface, 0.38)
	c.good = M3.success
	c.warn = M3.warning
	c.bad = M3.error
	c.badDim = M3.errorContainer

	-- Filled (primary, one per view), tonal (secondary), text (ghost), and the selected side of a segmented button
	-- (selected: a primary tint with primary text); hover is an 8% layer of the label color.
	local selectedBg = blend(M3.surfaceHigh, M3.primary, 0.16)
	BUTTONS.primary = { bg = M3.primary, hover = c.accentHover, border = M3.primary, text = M3.onPrimary }
	BUTTONS.secondary = { bg = M3.surfaceHigh, hover = blend(M3.surfaceHigh, M3.onSurface, 0.08), border = M3.outlineVariant, text = M3.onSurface }
	BUTTONS.selected = { bg = selectedBg, hover = blend(selectedBg, M3.primary, 0.08), border = blend(M3.outlineVariant, M3.primary, 0.4), text = M3.primary }
	BUTTONS.danger = { bg = M3.surfaceHigh, hover = blend(M3.surfaceHigh, M3.error, 0.08), border = M3.outlineVariant, text = M3.error }
	BUTTONS.ghost = { bg = { 0, 0, 0, 0 }, hover = c.hover, border = { 0, 0, 0, 0 }, text = M3.onSurfaceVariant }
	-- Disabled buttons of every kind look the same, as Material has it: a 12% onSurface fill with 38% onSurface
	-- text, so faded text never sits on a bright fill.
	DISABLED = { bg = blend(M3.surface, M3.onSurface, 0.12), border = M3.outlineVariant, text = c.disabled }
	for q in pairs(qualityColors) do qualityColors[q] = nil end
end

-- Sets the Material 3 roles the kit is drawn from, by name, as "rrggbb" hex or { r, g, b }; roles left out keep
-- the default scheme, and S.SetTheme() goes back to it. A primary given without an onPrimary gets one worked out.
-- Call it before building any frames: frames take their colors as they're made.
function S.SetTheme(roles)
	for role, color in pairs(DEFAULT_SCHEME) do M3[role] = color end
	for role, color in pairs(roles or {}) do
		if not DEFAULT_SCHEME[role] then error("MaterialCraftUI: unknown theme role " .. tostring(role), 2) end
		M3[role] = type(color) == "string" and rgb((color:gsub("^#", ""))) or { color[1], color[2], color[3], color[4] or 1 }
	end
	if roles and roles.primary and not roles.onPrimary then M3.onPrimary = onColor(M3.primary) end
	build()
end
S.SetTheme()

-- One spacing scale for every panel: PAD inside a panel's edges (the same on all sides), GAP between neighboring
-- controls, and one height for every button, input and dropdown so rows line up.
S.PAD, S.GAP, S.CONTROL_H = 12, 8, 24

-- "1 item", "3 items".
function S.Count(n, singular, plural)
	return ("%d %s"):format(n, n == 1 and singular or (plural or singular .. "s"))
end

-- An item quality's color as { r, g, b, a }, made once per quality since tables ask for it on every redraw.
function S.QualityColor(q)
	local color = qualityColors[q or -1]
	if not color then
		local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
		color = c and { c.r, c.g, c.b, 1 } or S.colors.text
		qualityColors[q or -1] = color
	end
	return color
end

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
	local track = S.Solid(bar, "BACKGROUND", { M3.onSurface[1], M3.onSurface[2], M3.onSurface[3], 0.04 })
	track:SetAllPoints()
	bar:SetThumbTexture(WHITE)
	local thumb = bar:GetThumbTexture()
	thumb:SetSize(6, 40)
	thumb:SetVertexColor(unpack(S.colors.border))
	bar:HookScript("OnEnter", function() thumb:SetVertexColor(unpack(S.colors.outline)) end)
	bar:HookScript("OnLeave", function() thumb:SetVertexColor(unpack(S.colors.border)) end)
	return bar
end

-- The stock fonts' faces and sizes without their drop shadow, which smears dark text on light fills and blurs
-- small text on flat panels. S.SetFont gives a font string or edit box one of them, setting the face and size on
-- it directly as well as the font object: in game, with the stock fonts restyled by ElvUI, a font string given only
-- the object could be left with no font, and SetText then fails with "Font not set". S.FONTS[size] is the object.
local STOCK = { small = "GameFontHighlightSmall", normal = "GameFontHighlight", large = "GameFontHighlightLarge",
	huge = "GameFontNormalHuge", edit = "ChatFontNormal" }
local FALLBACK_SIZE = { small = 10, normal = 12, large = 16, huge = 20, edit = 14 }
S.FONTS = {}
for size in pairs(STOCK) do
	S.FONTS[size] = CreateFont(ADDON .. "Font" .. size:sub(1, 1):upper() .. size:sub(2))
end
local FONTS = S.FONTS
local specs = {}

-- Reads the stock fonts again. UI addons restyle them after this file loads, so windows run it as they're built.
function S.RefreshFonts()
	for size, base in pairs(STOCK) do
		local stock = _G[base]
		local face, height, flags
		if stock then face, height, flags = stock:GetFont() end
		local spec = { face = face or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
			height = (height or 0) > 0 and height or FALLBACK_SIZE[size], flags = flags or "" }
		specs[size] = spec
		local font = FONTS[size]
		font:SetFont(spec.face, spec.height, spec.flags)
		font:SetTextColor(1, 1, 1)
		font:SetShadowOffset(0, 0)
		font:SetShadowColor(0, 0, 0, 0)
	end
end
S.RefreshFonts()

function S.SetFont(region, size)
	local spec = specs[size or "normal"]
	region:SetFontObject(FONTS[size or "normal"])
	region:SetFont(spec.face, spec.height, spec.flags)
	region:SetShadowOffset(0, 0)
end

function S.FontString(parent, size, layer)
	local fs = parent:CreateFontString(nil, layer or "ARTWORK")
	S.SetFont(fs, size)
	return fs
end

function S.Text(parent, size, color, layer)
	local fs = S.FontString(parent, size, layer)
	fs:SetTextColor(unpack(color or S.colors.text))
	fs:SetJustifyH("LEFT")
	return fs
end

local function paint(b)
	local enabled = b:IsEnabled() == 1 or b:IsEnabled() == true
	local kind = enabled and BUTTONS[b.kind] or DISABLED
	b:SetBackdropColor(unpack(b.hovered and enabled and kind.hover or kind.bg))
	b:SetBackdropBorderColor(unpack(kind.border))
	b.label:SetTextColor(unpack(kind.text))
end

-- `template` makes it from a frame template; a secure one keeps the template's own click handler, so onClick is
-- left unset (hook OnClick instead).
function S.Button(parent, label, kind, width, onClick, tooltip, template)
	local b = CreateFrame("Button", nil, parent, template)
	b:SetSize(width or 90, S.CONTROL_H)
	b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	b.kind = kind or "secondary"
	b.label = S.FontString(b, "small")
	b.label:SetPoint("CENTER")
	b.label:SetText(label)
	b.tooltipText = tooltip
	if not template then b:SetScript("OnClick", onClick) end
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
	-- a segmented button's halves overlap by their shared 1px border; the selected half sits one level up so
	-- its tinted border is drawn whole
	function b:SetKind(newKind)
		self.kind = newKind
		self:SetFrameLevel(parent:GetFrameLevel() + (newKind == "selected" and 2 or 1))
		paint(self)
	end
	function b:SetLabel(text)
		self.label:SetText(text)
		self:SetWidth(math.max(self.minWidth or 70, self.label:GetStringWidth() + 24))
	end
	-- changes the label and keeps the width; the button's own SetText would set a text it doesn't show
	function b:SetText(text)
		self.label:SetText(text)
	end
	b.minWidth = width
	paint(b)
	return b
end

local function paintCheck(b)
	if b.on then b.fill:Show() else b.fill:Hide() end
	b.fill:SetAlpha(b.usable and 1 or 0.4)
	b:SetBackdropBorderColor(unpack(b.hovered and b.usable and S.colors.accent or S.colors.outline))
end

-- Square flat checkbox: SetChecked(on) and SetEnabled(on) repaint it; clicks go to onClick(box).
function S.Check(parent, size, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size or 14, size or 14)
	S.Panel(b, S.colors.well, S.colors.outline)
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

local menus, inputs, dismissers = {}, {}, {}

-- Runs fn whenever S.Dismiss does, for other things that shouldn't outlive their view.
function S.OnDismiss(fn)
	dismissers[#dismissers + 1] = fn
end

-- A popup that closes like a dropdown menu: on a click outside it and its popup.owner, and on S.Dismiss.
function S.TrackPopup(popup)
	menus[#menus + 1] = popup
end

function S.CloseMenus()
	for _, menu in ipairs(menus) do menu:Hide() end
end

-- Edit boxes S.Dismiss and outside clicks clear. S.Input tracks its own; the other edit boxes call this once their
-- scripts are set. `area` is what counts as clicking on it, for a box inside a larger panel (default: the box).
function S.TrackInput(e, area)
	e:HookScript("OnEditFocusGained", function(self) self.focused = true end)
	e:HookScript("OnEditFocusLost", function(self) self.focused = false end)
	e.clickArea = area
	inputs[#inputs + 1] = e
end

-- Closes every dropdown menu and takes keyboard focus from every edit box. Neither goes away when its view is
-- covered or replaced (a menu only hides with its dropdown, and a hidden edit box keeps the keyboard), so views
-- that do that (switching tabs, opening a dialog, closing the window) call this.
function S.Dismiss()
	S.CloseMenus()
	for _, e in ipairs(inputs) do
		if e.focused then e:ClearFocus() end
	end
	for _, fn in ipairs(dismissers) do fn() end
end

-- A mouse press anywhere else closes an open menu and takes focus from an edit box. The client has no event for
-- presses outside a frame, so this watches for a button going down while either is open.
function S.ClickedAway()
	for _, menu in ipairs(menus) do
		if menu:IsShown() and not MouseIsOver(menu) and not MouseIsOver(menu.owner) then menu:Hide() end
	end
	for _, e in ipairs(inputs) do
		if e.focused and not MouseIsOver(e.clickArea or e) then e:ClearFocus() end
	end
end

local wasDown = false
local clicks = CreateFrame("Frame")
clicks:SetScript("OnUpdate", function()
	local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
	if down and not wasDown then S.ClickedAway() end
	wasDown = down
end)

-- A section heading in a navigation list: small dim text with a rule running from it to the right edge, so it
-- reads as a divider rather than one of the entries under it.
function S.SectionHeading(parent, text, x, y, rightInset)
	local label = S.Text(parent, "small", S.colors.outline)
	label:SetPoint("TOPLEFT", x, y)
	label:SetText(text)
	local line = S.Solid(parent, "BORDER", S.colors.border)
	line:SetHeight(1)
	line:SetPoint("LEFT", label, "RIGHT", 6, 0)
	line:SetPoint("RIGHT", parent, "RIGHT", -(rightInset or x), 0)
	return label, line
end

-- Gives a button a dropdown's arrow and left-aligned label, for buttons that open a list (a menu or a picker).
function S.AddArrow(b)
	b.label:ClearAllPoints()
	b.label:SetPoint("LEFT", 8, 0)
	b.label:SetPoint("RIGHT", -24, 0)
	b.label:SetJustifyH("LEFT")
	local arrow = b:CreateTexture(nil, "OVERLAY")
	-- Blizzard's sort arrow, cropped and sized as its auction column headers do (the arrow fills the left 9/16 of
	-- the texture); its point sits near the top of that box, so it's dropped 2px to line up with the label's middle
	arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
	arrow:SetTexCoord(0, 0.5625, 0, 1)
	arrow:SetSize(9, 8)
	arrow:SetPoint("RIGHT", -10, -2)
	arrow:SetDesaturated(true)
	arrow:SetVertexColor(unpack(S.colors.muted))
	b.arrow = arrow
	return b
end

-- Flat dropdown: a button showing the current choice that opens a menu below it. SetOptions takes
-- { { value, text, tooltip } }; picking one calls onSelect(value) and closes the menu. Opening one closes the others.
function S.Dropdown(parent, width, onSelect)
	local b = S.AddArrow(S.Button(parent, "", "secondary", width))

	local menu = CreateFrame("Frame", nil, b)
	-- above DIALOG, so the menu covers the controls of the dialog it opens from
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -2)
	menu:SetWidth(width)
	S.Panel(menu, S.colors.panel, S.colors.border)
	menu:EnableMouse(true)
	menu:Hide()
	menus[#menus + 1] = menu
	menu.owner = b
	b.menu, b.items = menu, {}

	function b:SetText(text) self.label:SetText(text) end
	function b:SetOptions(options)
		for i, opt in ipairs(options) do
			local item = self.items[i]
			if not item then
				item = CreateFrame("Button", nil, menu)
				item:SetHeight(S.CONTROL_H)
				item:SetPoint("TOPLEFT", 1, -1 - (i - 1) * S.CONTROL_H)
				item:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * S.CONTROL_H)
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
		menu:SetHeight(#options * S.CONTROL_H + 2)
	end
	b:SetScript("OnClick", function()
		local open = menu:IsShown()
		S.CloseMenus()
		if not open then menu:Show() end
	end)
	b:HookScript("OnHide", function() menu:Hide() end)
	return b
end

-- Input with a placeholder shown while it's empty and unfocused. Never takes focus on its own. With lines above 1
-- it's a taller box whose text wraps; Enter still finishes, and GetText turns any line break into a space.
function S.Input(parent, name, width, placeholder, maxLetters, lines)
	local e = CreateFrame("EditBox", name, parent)
	local tall = (lines or 1) > 1
	S.SetFont(e, "small")
	e:SetSize(width, tall and (lines * 13 + 12) or S.CONTROL_H)
	e:SetAutoFocus(false)
	e:SetMaxLetters(maxLetters or 40)
	S.Panel(e, S.colors.well, S.colors.border)
	e.placeholder = S.Text(e, "small", S.colors.muted)
	if tall then
		e:SetMultiLine(true)
		e:SetTextInsets(8, 8, 6, 6)
		e.placeholder:SetPoint("TOPLEFT", 8, -6)
		e.placeholder:SetPoint("TOPRIGHT", -8, -6)
		local getText = e.GetText
		e.GetText = function(self) return ((getText(self) or ""):gsub("[\r\n]", " ")) end
		e:SetScript("OnEnterPressed", e.ClearFocus)
	else
		e:SetTextInsets(8, 8, 0, 0)
		e.placeholder:SetPoint("LEFT", 8, 0)
		e.placeholder:SetPoint("RIGHT", -8, 0)
	end
	e.placeholder:SetJustifyH("LEFT")
	e.placeholder:SetWordWrap(false)
	e.placeholder:SetText(placeholder or "")
	-- the soft border at rest, the stronger outline on hover, the accent while focused
	local function update(self)
		if self.focused or self:GetText() ~= "" then self.placeholder:Hide() else self.placeholder:Show() end
		self:SetBackdropBorderColor(unpack(self.focused and S.colors.accent or self.hovered and S.colors.outline or S.colors.border))
	end
	e:SetScript("OnEditFocusGained", function(self) self.focused = true update(self) end)
	e:SetScript("OnEditFocusLost", function(self) self.focused = false update(self) end)
	e:SetScript("OnEnter", function(self) self.hovered = true update(self) end)
	e:SetScript("OnLeave", function(self) self.hovered = false update(self) end)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:HookScript("OnTextChanged", update)
	e.UpdatePlaceholder = update
	update(e)
	inputs[#inputs + 1] = e
	return e
end
