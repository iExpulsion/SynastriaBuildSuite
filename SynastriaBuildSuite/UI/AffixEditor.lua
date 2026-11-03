local _, NS = ...
local SBS = NS.SBS

-- The Affixes tab: the build's affix priority on the left, most wanted first, with buttons to reorder it and the
-- game's presets, and every affix on the right with its stats; clicking one adds it to the end of the order.
local Editor = {}
SBS.AffixEditor = Editor

local S = SBS.Style
local C = S.colors
local Affixes

local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
local ORDER_W, PRESET_W = 300, 120

local panel, current
local state = { slot = 1, search = "" }
Editor.state = state

local function statLines(tt, id)
	local info = Affixes.Info(id)
	local stats = info and info.stats or {}
	if #stats > 0 then
		for _, name in ipairs(stats) do tt:AddLine(name, 1, 1, 1) end
	else
		tt:AddLine("No stats", 0.6, 0.6, 0.66)
	end
end

local function selectSlot(slot)
	state.slot = slot
	SBS.Window.Render()
end

local function enable(button, on)
	if on then button:Enable() else button:Disable() end
end

-- Order -----------------------------------------------------------------------------------------------------

local function renderOrder(order, now, comparing)
	panel.orderTitle:SetText(("Priority Order  %s"):format(S.Hex(C.muted, ("%d / %d"):format(#order, Affixes.SLOTS))))
	local list = panel.order
	list:Begin()
	for i, id in ipairs(order) do
		local differs = comparing and now[i] ~= id
		list:Add({
			text = S.Hex(C.muted, i .. ".") .. "  " .. Affixes.Name(id),
			status = differs and S.Hex(C.warn, "Differs") or nil,
			selected = i == state.slot,
			onClick = function(_, mouse)
				if mouse == "RightButton" then
					Affixes.Remove(current, i)
					SBS:Changed()
				else
					selectSlot(i)
				end
			end,
			tooltip = function(tt)
				tt:AddLine(("%d. %s"):format(i, Affixes.Name(id)), 1, 1, 1)
				statLines(tt, id)
				if differs then
					tt:AddLine(" ")
					tt:AddLine(("Your spec has %s here."):format(now[i] and Affixes.Name(now[i]) or "nothing"), 1, 0.82, 0)
				end
				tt:AddLine(" ")
				tt:AddLine("Right-click to remove it.", 0.6, 0.6, 0.66)
			end,
		})
	end
	if #order == 0 then
		list:Add({ text = S.Hex(C.muted, "No affixes yet."), sub = "Pick some on the right, or load a preset." })
	end
	list:End()
	enable(panel.up, order[state.slot] ~= nil and state.slot > 1)
	enable(panel.down, order[state.slot + 1] ~= nil)
	enable(panel.remove, order[state.slot] ~= nil)
end

-- Picker ----------------------------------------------------------------------------------------------------

local function renderPicker(order)
	local list = panel.picker
	list:Begin()
	for _, info in ipairs(Affixes.Options()) do
		if state.search == "" or info.name:lower():find(state.search, 1, true) then
			local id = info.id
			local at = Affixes.Position(order, id)
			list:Add({
				text = info.name, indent = 2,
				status = at and S.Hex(C.accent, "#" .. at) or nil,
				selected = at ~= nil and at == state.slot,
				onClick = function()
					if at then
						selectSlot(at)
					elseif Affixes.Add(current, id) then
						state.slot = #current.affixes
						PlaySound("igMainMenuOptionCheckBoxOn")
						SBS:Changed()
					else
						UIErrorsFrame:AddMessage(("The order holds %d affixes; remove one first."):format(Affixes.SLOTS), 1, 0.3, 0.3)
					end
				end,
				tooltip = function(tt)
					tt:AddLine(info.name, 1, 1, 1)
					statLines(tt, id)
					tt:AddLine(" ")
					tt:AddLine(at and ("Number %d in the order. Click to select it."):format(at)
						or "Click to add it to the end of the order.", 0.6, 0.6, 0.66, true)
				end,
			})
		end
	end
	if list.count == 0 then
		list:Add({ text = S.Hex(C.muted, state.search ~= "" and "No affixes match your search."
			or "The affix list loads with the game's attunement data.") })
	end
	list:End()
end

local function summary(order, now)
	local text
	if #order == 0 then
		text = S.Hex(C.muted, "No Affix Order Yet: Pick Affixes or Load a Preset")
	elseif not now then
		text = S.Hex(C.muted, "Your Spec's Affix Order Can't Be Read")
	elseif Affixes.Diff(order) == 0 then
		text = S.Hex(C.good, "Your Affix Order Matches This Build")
	else
		text = "Affix Order Differs: Apply Build Near an Innkeeper"
	end
	return text
end

function Editor.Render(build)
	current = build
	Affixes = SBS.Affixes
	local order = build.affixes or {}
	if state.slot > math.max(#order, 1) then state.slot = math.max(#order, 1) end
	local now = Affixes.Current()
	local comparing = now ~= nil and SBS.Window.IsComparing(build)
	renderOrder(order, now, comparing)
	renderPicker(order)
	panel.preset:SetText("Load Preset")
	return summary(order, now)
end

-- Construction ----------------------------------------------------------------------------------------------

function Editor.Create(parent, width, height)
	Affixes = SBS.Affixes
	panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(width, height)

	-- left: the title and preset menu, the order, then the reorder buttons
	local left = CreateFrame("Frame", nil, panel)
	left:SetSize(ORDER_W, height)
	left:SetPoint("TOPLEFT")
	S.Panel(left, C.well, C.border)
	panel.preset = S.Dropdown(left, PRESET_W, function(i)
		Affixes.LoadPreset(current, Affixes.PRESETS[i])
		state.slot = 1
		SBS:Changed()
	end)
	panel.preset:SetPoint("TOPRIGHT", -PAD, -PAD)
	local presets = {}
	for i, preset in ipairs(Affixes.PRESETS) do
		presets[i] = { value = i, text = preset.name, tooltip = ("Replace this build's order with the game's %s order."):format(preset.name) }
	end
	panel.preset:SetOptions(presets)
	panel.orderTitle = S.Text(left, "normal")
	panel.orderTitle:SetPoint("LEFT", left, "TOPLEFT", PAD, -(PAD + CONTROL_H / 2))
	local listTop = PAD + CONTROL_H + GAP
	local footer = PAD + CONTROL_H + GAP
	panel.order = SBS.List.New(left, "SynastriaBuildSuiteAffixOrder", ORDER_W - 22, height - listTop - footer)
	panel.order.scroll:SetPoint("TOPLEFT", 1, -listTop)
	local function move(step)
		state.slot = Affixes.Move(current, state.slot, step)
		SBS:Changed()
	end
	panel.up = S.Button(left, "Move Up", "secondary", 80, function() move(-1) end, "Move the selected affix one place up.")
	panel.up:SetPoint("BOTTOMLEFT", PAD, PAD)
	panel.down = S.Button(left, "Move Down", "secondary", 86, function() move(1) end, "Move the selected affix one place down.")
	panel.down:SetPoint("LEFT", panel.up, "RIGHT", GAP, 0)
	panel.remove = S.Button(left, "Remove", "secondary", 76, function()
		Affixes.Remove(current, state.slot)
		SBS:Changed()
	end, "Take the selected affix out of the order.")
	panel.remove:SetPoint("LEFT", panel.down, "RIGHT", GAP, 0)

	-- right: every affix, with a search box
	local pickW = width - ORDER_W - PAD
	local pick = CreateFrame("Frame", nil, panel)
	pick:SetSize(pickW, height)
	pick:SetPoint("TOPLEFT", ORDER_W + PAD, 0)
	S.Panel(pick, C.well, C.border)
	local title = S.Text(pick, "normal")
	title:SetPoint("LEFT", pick, "TOPLEFT", PAD, -(PAD + CONTROL_H / 2))
	title:SetText("All Affixes")
	panel.search = S.Input(pick, "SynastriaBuildSuiteAffixSearch", pickW - 2 * PAD - 90, "Search Affixes", 40)
	panel.search:SetPoint("TOPRIGHT", -PAD, -PAD)
	panel.search:HookScript("OnTextChanged", function(self)
		state.search = self:GetText():lower()
		SBS.Window.Render()
	end)
	panel.picker = SBS.List.New(pick, "SynastriaBuildSuiteAffixPicker", pickW - 22, height - listTop - PAD)
	panel.picker.scroll:SetPoint("TOPLEFT", 1, -listTop)
	return panel
end
