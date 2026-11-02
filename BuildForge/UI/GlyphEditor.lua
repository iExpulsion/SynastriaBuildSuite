local _, NS = ...
local BF = NS.BF

-- The Glyphs tab: a class bar for multi-class builds (each class has its own glyphs), the class's six sockets,
-- Major and Minor, each bordered by whether the glyph is socketed, in your bags or missing, and a picker listing
-- that class's glyphs for the selected socket. Glyphs are used up when socketed, so BuildForge never sockets
-- them; Open Glyph Frame does that part.
local Editor = {}
BF.GlyphEditor = Editor

local S = BF.Style
local C = S.colors
local Glyphs

local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
local SOCKETS_W, ICON, ROW, SEARCH_H, CLASSBAR_H = 300, 40, 60, S.CONTROL_H + S.GAP, S.CONTROL_H + S.GAP
local COLUMNS = { { title = "Major Glyphs", sockets = { 1, 4, 6 } }, { title = "Minor Glyphs", sockets = { 2, 3, 5 } } }
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local EMPTY = "Interface\\Icons\\INV_Misc_Rune_01"
local LOOK = { socketed = C.good, bags = C.warn, missing = C.badDim, empty = C.border, chosen = C.muted }

local panel, current
local state = { socket = 1, search = "" }
Editor.state = state

local function buildClasses(build)
	local classes, seen = {}, {}
	local function add(key)
		if NS.GlyphData and NS.GlyphData[key] and not seen[key] then
			classes[#classes + 1] = key
			seen[key] = true
		end
	end
	for _, key in ipairs(build.classes and #build.classes > 0 and build.classes or BF:PlayerClasses()) do add(key) end
	for key in pairs(build.glyphs or {}) do add(key) end
	return classes
end

-- Socketed and Missing depend on the active spec, so a build for another spec only shows what's in your bags.
local function lookFor(row, comparing)
	return not row.spell and "empty" or comparing and row.socketed and "socketed" or row.inBags and "bags"
		or comparing and "missing" or "chosen"
end

local STATUS = {
	socketed = S.Hex(C.good, "Socketed"), bags = S.Hex(C.warn, "In Bags"),
	missing = S.Hex(C.bad, "Missing"), empty = S.Hex(C.muted, "Empty"), chosen = "",
}

local function glyphName(row)
	return row.glyph and row.glyph.name or row.spell and (GetSpellInfo(row.spell) or ("Glyph " .. row.spell))
end

local function choose(spell)
	local ok, reason = Glyphs.Set(current, state.class, state.socket, spell)
	if ok then
		PlaySound("igMainMenuOptionCheckBoxOn")
		BF:Changed()
	else
		UIErrorsFrame:AddMessage(reason or "BuildForge doesn't know that glyph.", 1, 0.3, 0.3)
	end
end

-- Sockets ---------------------------------------------------------------------------------------------------

local function socketTooltip(b)
	local row = b.row
	GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
	if row and row.glyph then
		GameTooltip:SetHyperlink("item:" .. row.glyph.item)
	elseif row and row.spell then
		GameTooltip:SetHyperlink("spell:" .. row.spell)
	else
		GameTooltip:AddLine(("%s Socket"):format(Glyphs.SOCKETS[b.socket].kind == "major" and "Major" or "Minor"), 1, 1, 1)
		GameTooltip:AddLine("Empty. Click it, then pick a glyph on the right.", 0.6, 0.6, 0.66, true)
	end
	GameTooltip:AddLine(("Opens at level %d."):format(Glyphs.SOCKETS[b.socket].level), 0.6, 0.6, 0.66)
	if row and row.spell then GameTooltip:AddLine("Right-click to clear this socket.", 0.6, 0.6, 0.66) end
	GameTooltip:Show()
end

local function newSocket(parent, socket, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, ICON + 8)
	b.socket = socket
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local hover = S.Solid(b, "HIGHLIGHT", C.hover)
	hover:SetAllPoints()
	b.selectedBg = S.Solid(b, "BACKGROUND", C.selected)
	b.selectedBg:SetAllPoints()
	b.frame = CreateFrame("Frame", nil, b)
	b.frame:SetSize(ICON, ICON)
	b.frame:SetPoint("LEFT", 4, 0)
	S.Panel(b.frame, { 0, 0, 0, 1 }, C.border)
	b.icon = b.frame:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.name = S.Text(b, "small")
	-- name and status (about 26px together) centered beside the icon
	b.name:SetPoint("TOPLEFT", b.frame, "TOPRIGHT", GAP, -(ICON - 26) / 2)
	b.name:SetWidth(width - ICON - 20)
	b.name:SetHeight(12)
	b.name:SetWordWrap(false)
	b.status = S.Text(b, "small", C.muted)
	b.status:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -4)
	b:SetScript("OnClick", function(self, mouse)
		if mouse == "RightButton" then
			Glyphs.Clear(current, state.class, self.socket)
			BF:Changed()
		else
			state.socket = self.socket
			BF.Window.Render()
		end
	end)
	b:SetScript("OnEnter", socketTooltip)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function renderSockets(rows, comparable)
	local comparing = comparable and BF.Window.IsComparing(current)
	for socket, b in pairs(panel.sockets) do
		local row = rows[socket]
		local look = lookFor(row, comparing)
		b.row = row
		b.icon:SetTexture(row.glyph and (GetItemIcon(row.glyph.item) or QUESTION) or row.spell and QUESTION or EMPTY)
		b.icon:SetDesaturated(not row.spell)
		b.icon:SetAlpha(row.spell and 1 or 0.4)
		b.frame:SetBackdropBorderColor(unpack(LOOK[look]))
		b.name:SetText(glyphName(row) or S.Hex(C.muted, ("Level %d Socket"):format(Glyphs.SOCKETS[socket].level)))
		b.status:SetText(STATUS[look])
		if socket == state.socket then b.selectedBg:Show() else b.selectedBg:Hide() end
	end
end

-- Picker ----------------------------------------------------------------------------------------------------

local function renderPicker(rows)
	local socket = state.socket
	local kind = Glyphs.SOCKETS[socket].kind
	local chosen = rows[socket].spell
	local inSocket = {}
	for s, row in ipairs(rows) do
		if row.spell then inSocket[row.spell] = s end
	end
	panel.pickTitle:SetText(("%s Glyphs for Socket %d"):format(kind == "major" and "Major" or "Minor", socket))
	local list = panel.picker
	list:Begin()
	for _, g in ipairs(Glyphs.Options({ state.class }, kind)) do
		if state.search == "" or g.name:lower():find(state.search, 1, true) then
			local status
			if g.spell == chosen then status = S.Hex(C.accent, "Chosen")
			elseif inSocket[g.spell] then status = S.Hex(C.muted, "In Socket " .. inSocket[g.spell])
			elseif GetItemCount(g.item) > 0 then status = S.Hex(C.warn, "In Bags")
			end
			local spell, item = g.spell, g.item
			list:Add({
				text = g.name, icon = GetItemIcon(item) or QUESTION, indent = 2,
				status = status, selected = spell == chosen,
				onClick = function(_, mouse)
					if IsModifiedClick("CHATLINK") then
						local link = select(2, GetItemInfo(item))
						if link then ChatEdit_InsertLink(link) end
					elseif mouse == "RightButton" and spell == chosen then
						Glyphs.Clear(current, state.class, socket)
						BF:Changed()
					else
						choose(spell)
					end
				end,
				tooltip = function(tt)
					tt:SetHyperlink("item:" .. item)
					tt:AddLine(" ")
					tt:AddLine(("Click to put it in socket %d."):format(socket), 0.6, 0.6, 0.66)
				end,
			})
		end
	end
	if list.count == 0 then
		list:Add({ text = S.Hex(C.muted, state.search ~= "" and "No glyphs match your search."
			or "No glyph data for this class.") })
	end
	list:End()
	if chosen then panel.clear:Enable() else panel.clear:Disable() end
end

local function summary(rows, comparable)
	local count, missing = 0, 0
	for _, row in ipairs(rows) do
		if row.spell then count = count + 1 end
		if row.spell and not row.socketed then missing = missing + 1 end
	end
	local text
	if count == 0 then
		text = S.Hex(C.muted, "No Glyphs Yet: Pick a Socket, Then a Glyph")
	elseif not BF:HasClass(state.class) then
		text = S.Hex(C.muted, ("%s Isn't One of Your Classes"):format(BF.Window.ClassText({ state.class }, true)))
	elseif not comparable then
		text = S.Hex(C.muted, ("Show %s in the Talent Window to Compare"):format(BF.Window.ClassText({ state.class }, true)))
	elseif missing == 0 then
		text = S.Hex(C.good, "Your Glyphs Match This Build")
	else
		text = S.Count(missing, "Glyph") .. " to Socket Yourself"
	end
	return text
end

local function renderClassBar(classes)
	for i, b in ipairs(panel.classButtons) do
		local key = classes[i]
		if key and #classes > 1 then
			b.key = key
			b:SetLabel(BF.Window.ClassText({ key }, true))
			b:SetKind(key == state.class and "selected" or "secondary")
			b:Show()
		else
			b:Hide()
		end
	end
end

-- Moves the sockets below the class bar, or to the top when there's only one class.
local function placeSockets(top)
	if panel.top ~= top then
		panel.top = top
		for _, item in ipairs(panel.placed) do
			item.frame:ClearAllPoints()
			item.frame:SetPoint("TOPLEFT", item.x, -(top + item.y))
		end
	end
end

function Editor.Render(build)
	current = build
	Glyphs = BF.Glyphs
	local classes = buildClasses(build)
	local found = false
	for _, k in ipairs(classes) do if k == state.class then found = true end end
	if not found then state.class = classes[1] or BF:PlayerClasses()[1] end
	renderClassBar(classes)
	placeSockets(#classes > 1 and CLASSBAR_H or 0)
	local rows, comparable = Glyphs.Status(build, state.class)
	renderSockets(rows, comparable)
	renderPicker(rows)
	return summary(rows, comparable)
end

-- Construction ----------------------------------------------------------------------------------------------

function Editor.Create(parent, width, height)
	Glyphs = BF.Glyphs
	panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(width, height)
	panel.sockets, panel.placed = {}, {}

	panel.classButtons = {}
	for i = 1, 3 do
		local b = S.Button(panel, "", "secondary", 90, function(self)
			state.class = self.key
			BF:Changed()
		end)
		if i == 1 then b:SetPoint("TOPLEFT", 0, 0) else b:SetPoint("LEFT", panel.classButtons[i - 1], "RIGHT", -1, 0) end
		panel.classButtons[i] = b
	end

	-- each column: a title line, then its three sockets; PAD between the Major and Minor blocks
	local TITLE_LINE = 14 + GAP
	for c, column in ipairs(COLUMNS) do
		local top = (c - 1) * (TITLE_LINE + #column.sockets * ROW + PAD)
		local title = S.Text(panel, "normal")
		title:SetText(column.title)
		panel.placed[#panel.placed + 1] = { frame = title, x = 4, y = top }
		for i, socket in ipairs(column.sockets) do
			local b = newSocket(panel, socket, SOCKETS_W)
			panel.placed[#panel.placed + 1] = { frame = b, x = 0, y = top + TITLE_LINE + (i - 1) * ROW }
			panel.sockets[socket] = b
		end
	end
	placeSockets(0)

	local pickW = width - SOCKETS_W - PAD
	local pick = CreateFrame("Frame", nil, panel)
	pick:SetSize(pickW, height)
	pick:SetPoint("TOPLEFT", SOCKETS_W + PAD, 0)
	S.Panel(pick, C.well, C.border)
	panel.pickTitle = S.Text(pick, "normal")
	panel.pickTitle:SetPoint("TOPLEFT", PAD, -PAD)
	panel.search = S.Input(pick, "BuildForgeGlyphSearch", pickW - 2 * PAD, "Search Glyphs", 40)
	panel.search:SetPoint("TOPLEFT", PAD, -(PAD + TITLE_LINE))
	panel.search:HookScript("OnTextChanged", function(self)
		state.search = self:GetText():lower()
		BF.Window.Render()
	end)
	local listTop = PAD + TITLE_LINE + SEARCH_H
	panel.picker = BF.List.New(pick, "BuildForgeGlyphPicker", pickW - 22, height - listTop - (PAD + CONTROL_H + GAP))
	panel.picker.scroll:SetPoint("TOPLEFT", 1, -listTop)
	panel.clear = S.Button(pick, "Clear Socket", "secondary", 100, function()
		Glyphs.Clear(current, state.class, state.socket)
		BF:Changed()
	end, "Take the glyph out of the selected socket.")
	panel.clear:SetPoint("BOTTOMLEFT", PAD, PAD)
	return panel
end
