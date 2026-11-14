local _, NS = ...
local SBS = NS.SBS

-- The Affixes tab: the build's affix priority on the left, most wanted first, dragged to reorder, with the game's
-- presets. On the right, every affix with its stats (clicking one adds it to the end of the order), or the
-- character's stats, with the ones the order gives highlighted and the change since the last snapshot.
local Editor = {}
SBS.AffixEditor = Editor

local S = SBS.Style
local C = S.colors
local Affixes, Stats

local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
local ORDER_W, PRESET_W, STATS_W, VIEW_W = 300, 120, 110, 80

local panel, current
local state = { slot = 1, search = "", stats = {}, statCount = 0, view = "affixes" }
Editor.state = state
local values, touched = {}, {}

function Editor.ShowingStats()
	return state.view == "stats" and SBS.Window.state.tab == "affixes"
end

-- Tooltips: the affix name in the accent, like an item name, then its stats in the game's bonus-stat green.
local STAT_COLOR = { 0.1, 1, 0.1 }

local function nameLine(tt, text)
	tt:AddLine(text, unpack(C.accent))
end

local function statLines(tt, id)
	local info = Affixes.Info(id)
	local stats = info and info.stats or {}
	if #stats > 0 then
		for _, name in ipairs(stats) do tt:AddLine(name, unpack(STAT_COLOR)) end
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
			move = i, dragLabel = Affixes.Name(id),
			onClick = function(_, mouse)
				if mouse == "RightButton" then
					Affixes.Remove(current, i)
					SBS:Changed()
				else
					selectSlot(i)
				end
			end,
			tooltip = function(tt)
				nameLine(tt, ("%d. %s"):format(i, Affixes.Name(id)))
				statLines(tt, id)
				if differs then
					tt:AddLine(" ")
					tt:AddLine(("Your spec has %s here."):format(now[i] and Affixes.Name(now[i]) or "nothing"), 0.8, 0.8, 0.8, true)
				end
				tt:AddLine(" ")
				tt:AddLine("Drag to change the order. Right-click to remove it.", 0.6, 0.6, 0.66, true)
			end,
		})
	end
	if #order == 0 then
		list:Add({ text = S.Hex(C.muted, "No affixes yet."), sub = "Pick some on the right, or load a preset." })
	end
	list:End()
	enable(panel.remove, order[state.slot] ~= nil)
end

-- Picker ----------------------------------------------------------------------------------------------------

local function renderPicker(order)
	local list = panel.picker
	list:Begin()
	for _, info in ipairs(Affixes.Options()) do
		if Affixes.Matches(info, state.search, state.stats) then
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
					nameLine(tt, info.name)
					statLines(tt, id)
					tt:AddLine(" ")
					tt:AddLine(at and ("Number %d in the order. Click to select it."):format(at)
						or "Click to add it to the end of the order.", 0.6, 0.6, 0.66, true)
				end,
			})
		end
	end
	if list.count == 0 then
		local filtered = state.search ~= "" or state.statCount > 0
		list:Add({ text = S.Hex(C.muted, filtered and "No affixes match your search."
			or "The affix list loads with the game's attunement data.") })
	end
	list:End()
end

local function statsLabel()
	local label = "All Stats"
	if state.statCount == 1 then
		label = next(state.stats)
	elseif state.statCount > 1 then
		label = state.statCount .. " Stats"
	end
	return label
end

local function toggleStat(name)
	if name == "" then
		state.stats, state.statCount = {}, 0
	elseif state.stats[name] then
		state.stats[name] = nil
		state.statCount = state.statCount - 1
	else
		state.stats[name] = true
		state.statCount = state.statCount + 1
	end
	SBS.Window.Render()
end

local function statsSpec()
	local items = { { value = "", text = "All Stats", tooltip = "Show affixes with any stats." } }
	for _, name in ipairs(Affixes.Stats()) do items[#items + 1] = { value = name, text = name } end
	return {
		items = items, multi = true, placeholder = "Search Stats", emptyText = "No Stats Match",
		isSelected = function(name)
			return (name == "" and state.statCount == 0) or state.stats[name] == true
		end,
		onPick = toggleStat,
	}
end

-- Stats ------------------------------------------------------------------------------------------------------

local function change(row)
	local before = Stats.baseline and Stats.baseline[row.key]
	local delta = before and values[row.key] - before or 0
	local text = ""
	if delta > 0 then
		text = "  " .. S.Hex(C.good, "+" .. delta)
	elseif delta < 0 then
		text = "  " .. S.Hex(C.bad, tostring(delta))
	end
	return text, delta
end

local function shows(row, gives, delta, mana)
	return (not row.mana or mana) and (row.always or gives or delta ~= 0 or values[row.key] ~= 0)
end

local function renderStats(order)
	Stats.Read(values)
	Stats.Touched(order, touched)
	local mana = Stats.HasMana()
	local list = panel.statList
	list:Begin()
	if Stats.baseline then
		list:Add({
			text = S.Hex(C.muted, "Changes Since " .. Stats.baselineAt), status = S.Hex(C.muted, "Reset"),
			onClick = function()
				Stats.ClearSnapshot()
				SBS.Window.Render()
			end,
			tooltip = function(tt)
				tt:AddLine("Changes Since " .. Stats.baselineAt, 1, 1, 1)
				tt:AddLine("Each stat shows how it changed since you last applied an affix order. Click to stop showing changes until the next one.", 0.8, 0.8, 0.8, true)
			end,
		})
	else
		list:Add({ text = S.Hex(C.muted, "Test Affixes to See What Changes") })
	end
	local canRevert = Stats.RevertPlan() ~= nil
	enable(panel.revert, canRevert)
	panel.revert.tooltipText = canRevert and "Send back the affix order you had before the last test or apply. Works near an innkeeper."
		or "Nothing to revert: your order is the one you had before the last test, or you haven't tested one."
	local group
	for _, row in ipairs(Stats.ROWS) do
		local gives = Stats.Gives(row, touched)
		local delta, amount = change(row)
		if shows(row, gives, amount, mana) then
			if row.group ~= group then
				group = row.group
				list:Add({ text = Stats.GROUPS[group], header = true })
			end
			list:Add({
				text = gives and S.Hex(C.accent, row.label) or row.label, indent = 2,
				status = values[row.key] .. delta,
				tooltip = gives and function(tt)
					nameLine(tt, row.label)
					tt:AddLine("Affixes in this build's order give this stat.", 0.8, 0.8, 0.8, true)
				end or nil,
			})
		end
	end
	list:End()
end

local function showView(view)
	state.view = view
	S.Dismiss()
	Stats.Poll()
	SBS.Window.Render()
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
	Affixes, Stats = SBS.Affixes, SBS.Stats
	local order = build.affixes or {}
	if state.slot > math.max(#order, 1) then state.slot = math.max(#order, 1) end
	local now = Affixes.Current()
	local comparing = now ~= nil and SBS.Window.IsComparing(build)
	renderOrder(order, now, comparing)
	local onStats = state.view == "stats"
	if onStats then
		renderStats(order)
	else
		renderPicker(order)
		panel.stats:SetText(statsLabel())
	end
	if onStats then panel.affixView:Hide() else panel.affixView:Show() end
	if onStats then panel.statsView:Show() else panel.statsView:Hide() end
	panel.view:SetLabel(onStats and "Affix List" or "Your Stats")
	panel.view.tooltipText = onStats and "Back to the list of affixes to add to the order."
		or "See your character's stats. The ones this build's affixes give are highlighted, and after an order is applied each stat shows how it changed."
	panel.preset:SetText("Load Preset")
	return summary(order, now)
end

-- Construction ----------------------------------------------------------------------------------------------

function Editor.Create(parent, width, height)
	Affixes, Stats = SBS.Affixes, SBS.Stats
	panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(width, height)

	-- left: the title and preset menu, the order, then the reorder buttons
	local left = CreateFrame("Frame", nil, panel)
	left:SetSize(ORDER_W, height)
	left:SetPoint("TOPLEFT")
	S.Well(left)
	-- the lists sit inside the wells' frames, however thick the theme draws them
	local wi = 1 + S.metrics.wellInset
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
	panel.order = SBS.List.New(left, "SynastriaBuildSuiteAffixOrder", ORDER_W - 20 - 2 * wi, height - listTop - footer)
	panel.order.scroll:SetPoint("TOPLEFT", wi, -listTop)
	panel.order:SetReorder(function(from, to)
		state.slot = Affixes.Move(current, from, to)
		SBS:Changed()
	end)
	panel.remove = S.Button(left, "Remove", "secondary", 76, function()
		Affixes.Remove(current, state.slot)
		SBS:Changed()
	end, "Take the selected affix out of the order.")
	panel.remove:SetPoint("BOTTOMLEFT", PAD, PAD)

	-- right: every affix, with a stat filter and a search box, or the character's stats; the button between them
	-- keeps its spot in both
	local pickW = width - ORDER_W - PAD
	local pick = CreateFrame("Frame", nil, panel)
	pick:SetSize(pickW, height)
	pick:SetPoint("TOPLEFT", ORDER_W + PAD, 0)
	S.Well(pick)
	panel.view = S.Button(pick, "Your Stats", "secondary", VIEW_W, function()
		showView(state.view == "stats" and "affixes" or "stats")
	end)
	panel.view:SetPoint("TOPRIGHT", -PAD, -PAD)

	local affixView = CreateFrame("Frame", nil, pick)
	affixView:SetAllPoints()
	panel.affixView = affixView
	panel.stats = S.PickerButton(affixView, STATS_W, statsSpec)
	panel.stats:SetPoint("TOPLEFT", PAD, -PAD)
	panel.stats.tooltipText = "Show only affixes that give any of the stats you pick."
	panel.search = S.Input(affixView, "SynastriaBuildSuiteAffixSearch", pickW - 2 * PAD - STATS_W - VIEW_W - 2 * GAP,
		"Search Names or Stats", 40)
	panel.search:SetPoint("LEFT", panel.stats, "RIGHT", GAP, 0)
	panel.search:HookScript("OnTextChanged", function(self)
		state.search = self:GetText():lower()
		SBS.Window.Render()
	end)
	panel.picker = SBS.List.New(affixView, "SynastriaBuildSuiteAffixPicker", pickW - 20 - 2 * wi, height - listTop - PAD)
	panel.picker.scroll:SetPoint("TOPLEFT", wi, -listTop)

	local statsView = CreateFrame("Frame", nil, pick)
	statsView:SetAllPoints()
	statsView:Hide()
	panel.statsView = statsView
	panel.revert = S.Button(statsView, "Revert", "secondary", 80, function()
		SBS.Affixes.Apply(Stats.RevertPlan(), true)
		SBS.Window.Message(S.Hex(C.muted, "Reverting Affix Order..."))
	end)
	panel.revert:SetPoint("TOPLEFT", PAD, -PAD)
	panel.statList = SBS.List.New(statsView, "SynastriaBuildSuiteAffixStats", pickW - 20 - 2 * wi, height - listTop - PAD)
	panel.statList.scroll:SetPoint("TOPLEFT", wi, -listTop)
	return panel
end
