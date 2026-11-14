local _, NS = ...
local SBS = NS.SBS

-- The Perks tab: the perks the build's classes can use, by category, with a checkbox for whether the build has
-- each one, and a detail pane for the selected perk's effect, chosen ability and options. Edits change the build;
-- Apply Build sends them to the character.
local Editor = {}
SBS.PerkEditor = Editor

local S = SBS.Style
local C = S.colors
local Perks

local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
-- the list column ends at LIST_W - 4 (its scroll bar's right edge); the detail pane starts PAD after it, the same
-- gap as between the gear doll or glyph sockets and their panes
local LIST_W, TOOLBAR_H = 330, CONTROL_H + GAP
local LIST_RIGHT = LIST_W - 4
local SEGMENTED_W = 2 * 80 - 1
-- detail pane: the icon row, then the toggle row, then the sections
local ICON_ROW, TOGGLE_Y = 36, PAD + 36 + PAD
local SECTIONS_Y = TOGGLE_Y + CONTROL_H + PAD
local ICON, ICON_GAP = 28, 4
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local CATEGORY_ORDER = { 15, 16, 17, 18, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 13, 19, 0 }
local CATEGORY_NAMES = { [15] = "Offensive", [16] = "Defensive", [17] = "Support", [18] = "Utility", [13] = "Class", [19] = "Misc" }

local panel, current
local state = { selected = nil, filter = "build", search = "" }
Editor.state = state

local function categoryName(cat)
	local key = SBS.CLASS_KEYS[cat]
	return key and (SBS.Window.ClassText({ key }, true) .. " Class") or CATEGORY_NAMES[cat] or "Other"
end

local function spellIcon(id)
	return id and select(3, GetSpellInfo(id)) or QUESTION
end

local function buildMask(build)
	return Perks.ClassMask(build.classes and #build.classes > 0 and build.classes or SBS:PlayerClasses())
end

-- Misc perks are edited in the shared list, every other perk in the build.
local function owner(id)
	return Perks.IsShared(id) and SBS.db.shared or current
end

local function entryFor(id)
	return Perks.Entry(owner(id), id)
end

-- What applying the build would do to each perk, by perk ID. Empty, with `off` set, for a build linked to a spec
-- that isn't active, since the character's perks belong to another spec.
local function planLookup(build)
	local plan = Perks.BuildPlan(build)
	local look = { plan = plan, activate = {}, deactivate = {}, skipped = {}, options = {}, off = not SBS.Window.IsComparing(build) }
	if look.off then plan = { activate = {}, deactivate = {}, skipped = {}, options = {}, spells = {} } end
	for _, id in ipairs(plan.activate) do look.activate[id] = true end
	for _, id in ipairs(plan.deactivate) do look.deactivate[id] = true end
	for _, s in ipairs(plan.skipped) do look.skipped[s.id] = s.reason end
	for _, o in ipairs(plan.options) do look.options[o.id] = true end
	for _, s in ipairs(plan.spells) do look.options[s.id] = true end
	return look
end

local function rowStatus(id, entry, look)
	local status
	if look.off then status = nil
	elseif look.skipped[id] then status = S.Hex(C.muted, "Skipped")
	elseif entry and look.activate[id] then status = S.Hex(C.warn, "To Activate")
	elseif entry then status = S.Hex(C.muted, "Active")
	elseif look.deactivate[id] then status = S.Hex(C.bad, "To Deactivate")
	end
	if entry and look.options[id] and not look.skipped[id] then status = status .. S.Hex(C.warn, ", Options Differ") end
	return status
end

-- The perk's name with the character's rank after it; unlearned perks show 0 in yellow.
local function rowText(perk)
	local rank, maxRank = GetPerkAcquired(perk.id), perk.levels and #perk.levels or 0
	local text = rank and tostring(rank) or "0"
	if maxRank > 0 then text = text .. "/" .. maxRank end
	return perk.name .. "  " .. S.Hex(rank and C.muted or C.warn, text)
end

local function toggle(id)
	local perk = PerkMgrPerks[id]
	if perk and not Perks.Locked(perk) then
		state.selected = id
		PlaySound(Perks.Toggle(owner(id), id) and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
		SBS:Changed()
	end
end

local function selectPerk(id)
	state.selected = id
	SBS.Window.Render()
end

local function rowTooltip(id)
	return function(tt)
		local perk = PerkMgrPerks[id]
		tt:AddLine(perk.name, 1, 1, 1)
		tt:AddLine(categoryName(perk.cat), 0.6, 0.6, 0.66)
		local desc = Perks.Description(id, GetPerkAcquired(id) or 1)
		if desc then tt:AddLine(desc, 1, 1, 1, true) end
		tt:AddLine(Perks.IsShared(id) and "Check to add it to Shared Perks, which every build applies. Click the name for details and options."
			or "Check to add it to the build. Click the name for details and options.", 0.6, 0.6, 0.66, true)
	end
end

-- List ------------------------------------------------------------------------------------------------------

local function visiblePerks(build, mask, look)
	local byCat, first = {}, nil
	for id, perk in pairs(PerkMgrPerks) do
		local entry = entryFor(id)
		local relevant = entry or look.deactivate[id] or id == state.selected
			or ((state.filter == "all" or build.sharedOnly) and Perks.UsableFor(perk, mask))
		local matches = state.search == "" or (perk.name or ""):lower():find(state.search, 1, true)
		-- Misc perks are listed only under Shared Perks, and Shared Perks lists nothing else
		local inMode = Perks.IsShared(id) == (build.sharedOnly == true)
		if relevant and matches and inMode then
			local cat = CATEGORY_NAMES[perk.cat] and perk.cat or SBS.CLASS_KEYS[perk.cat] and perk.cat or 0
			byCat[cat] = byCat[cat] or {}
			table.insert(byCat[cat], perk)
		end
	end
	for _, perks in pairs(byCat) do
		table.sort(perks, function(a, b)
			if (a.sort or 0) ~= (b.sort or 0) then return (a.sort or 0) < (b.sort or 0) end
			return (a.name or ""):upper() < (b.name or ""):upper()
		end)
	end
	for _, cat in ipairs(CATEGORY_ORDER) do
		if byCat[cat] and not first then first = byCat[cat][1].id end
	end
	return byCat, first
end


local function categoryStatus(build, cat, mask)
	local count = cat == Perks.SHARED_CAT and #SBS.db.shared.perks or Perks.CategoryCount(build, cat, mask)
	local index = Perks.LimitIndex(cat)
	local text
	if index == 6 or index == 0 then
		text = S.Hex(C.muted, count)
	else
		local limit = GetPerkLimit(index) or 0
		text = S.Hex(count > limit and C.warn or C.muted, ("%d / %d"):format(count, limit))
	end
	return text
end

-- Whether a set perk counts for the build: it's in the build, or it can't be toggled (like the Buffs perks class
-- unlocks grant) and the character has it.
local function inSet(id)
	local perk = PerkMgrPerks[id]
	return entryFor(id) ~= nil or (perk ~= nil and Perks.Locked(perk) and GetPerkActive(id) and GetPerkAcquired(id) ~= nil) == true
end

-- "5 / 8" for the set's counted perks, green once a bonus is active.
local function setStatus(set)
	local count, total = Perks.SetCount(set, inSet)
	local active = false
	for _, b in ipairs(Perks.SetBonuses(set, inSet)) do active = active or b.active end
	return S.Hex(active and C.good or C.muted, ("%d / %d"):format(count, total))
end

local SET_NOTE = "Bonuses count the set's perks in this build, and perks you can't toggle that your character has."

local function setTooltip(set)
	return function(tt)
		tt:AddLine(set.name, 1, 1, 1)
		for _, b in ipairs(Perks.SetBonuses(set, inSet)) do tt:AddLine(b.text, 1, 1, 1, true) end
		tt:AddLine(SET_NOTE, 0.6, 0.6, 0.66, true)
	end
end

-- A category's perks with each set's members together under the set, sets first in the order their first
-- perk sorts, then the perks in no set.
local function groupBySet(perks)
	local groups, loose, index = {}, {}, {}
	for _, perk in ipairs(perks) do
		local set = Perks.SetOf(perk.id)
		if set then
			if not index[set] then
				groups[#groups + 1] = { set = set, perks = {} }
				index[set] = groups[#groups]
			end
			table.insert(index[set].perks, perk)
		else
			loose[#loose + 1] = perk
		end
	end
	if #loose > 0 then groups[#groups + 1] = { perks = loose } end
	return groups
end

local function renderList(build, mask, look)
	local list = panel.list
	local byCat, first = visiblePerks(build, mask, look)
	if not (state.selected and PerkMgrPerks[state.selected]) then state.selected = first end
	list:Begin()
	for _, cat in ipairs(CATEGORY_ORDER) do
		local perks = byCat[cat]
		if perks then
			list:Add({ text = categoryName(cat), header = true, status = categoryStatus(build, cat, mask),
				tooltip = function(tt)
					tt:AddLine(categoryName(cat), 1, 1, 1)
					tt:AddLine(cat == Perks.SHARED_CAT
						and "Misc perks are kept in one Shared Perks list that every build applies, so each spec gets them. They aren't included in exports."
						or "Perks in this build, and how many your character can have on at once.", 0.8, 0.8, 0.8, true)
				end })
			for _, group in ipairs(groupBySet(perks)) do
				local set = group.set
				if set then
					list:Add({ text = S.Hex(C.set, set.name), indent = 4, status = setStatus(set), tooltip = setTooltip(set) })
				end
				for _, perk in ipairs(group.perks) do
					local id = perk.id
					local entry = entryFor(id)
					local locked = Perks.Locked(perk)
					list:Add({
						text = rowText(perk), icon = spellIcon(perk.icon), indent = set and 16 or 4,
						check = entry ~= nil, checkEnabled = not locked,
						checkTooltip = locked and "This perk can't be turned on or off." or nil,
						onCheck = function() toggle(id) end,
						status = rowStatus(id, entry, look),
						selected = id == state.selected,
						onClick = function() selectPerk(id) end,
						tooltip = rowTooltip(id),
					})
				end
			end
		end
	end
	if list.count == 0 then
		list:Add({ text = S.Hex(C.muted, state.search ~= "" and "No perks match your search."
			or build.sharedOnly and "No Misc perks to show."
			or "This build has no perks yet. Show All Perks to add some.") })
	end
	list:End()
end

-- Detail pane -----------------------------------------------------------------------------------------------

local function pooled(pool, i, make)
	pool[i] = pool[i] or make()
	return pool[i]
end

local function newAbility(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(ICON, ICON)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	S.Panel(b, { 0, 0, 0, 1 }, C.border)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local hover = S.Solid(b, "HIGHLIGHT", { 1, 1, 1, 0.15 })
	hover:SetAllPoints(b.icon)
	b:SetScript("OnClick", function(self, mouse)
		local entry = entryFor(self.perk)
		if entry then
			entry.spell = mouse == "RightButton" and 0 or self.spell
			PlaySound("igMainMenuOptionCheckBoxOn")
			SBS:Changed()
		else
			UIErrorsFrame:AddMessage("Add the perk first.", 1, 0.3, 0.3)
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("spell:" .. self.spell)
		if bit.band(self.flags or 0, 1) ~= 0 then GameTooltip:AddLine("(This ability deals damage)", 1, 0.2, 0.2) end
		if bit.band(self.flags or 0, 2) ~= 0 then GameTooltip:AddLine("(This ability heals)", 0.2, 1, 0.2) end
		GameTooltip:AddLine("Left-click to choose it, right-click to clear the choice.", 0.6, 0.6, 0.66, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

local function newOption(parent, width)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(width, 22)
	S.Highlight(row)
	row.check = S.Check(row, nil, function() row:Click() end)
	row.check:SetPoint("LEFT", 4, 0)
	row.label = S.Text(row, "small")
	row.label:SetPoint("LEFT", row.check, "RIGHT", 8, 0)
	row.label:SetPoint("RIGHT", -4, 0)
	row:SetScript("OnClick", function(self)
		local entry = entryFor(self.perk)
		if entry and Perks.SetOption(entry, self.options, self.index, not self.check.on) then
			PlaySound("igMainMenuOptionCheckBoxOn")
			SBS:Changed()
		elseif not entry then
			UIErrorsFrame:AddMessage("Add the perk first.", 1, 0.3, 0.3)
		end
	end)
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.label:GetText(), 1, 1, 1)
		if self.tip and self.tip ~= "" then GameTooltip:AddLine(self.tip, 1, 0.82, 0, true) end
		if self.group then GameTooltip:AddLine("Only one option in this group can be on; picking it turns the others off.", 0.6, 0.6, 0.66, true) end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function renderDetail(build, mask, look)
	local d = panel.detail
	local id = state.selected
	local perk = id and PerkMgrPerks[id]
	if perk then d.child:Show() d.none:Hide() else d.child:Hide() d.none:Show() end
	if perk then
		local child, width = d.child, d.innerW
		local entry = entryFor(id)
		local shared = Perks.IsShared(id)
		local rank, maxRank = GetPerkAcquired(id), perk.levels and #perk.levels or 0
		d.icon:SetTexture(spellIcon(perk.icon))
		d.name:SetText(perk.name)
		d.sub:SetText(categoryName(perk.cat) .. "   " .. (rank and ("Rank %d/%d on your character"):format(rank, maxRank)
			or S.Hex(C.warn, "Not learned on your character")))

		local locked = Perks.Locked(perk)
		if shared then
			d.toggle:SetLabel(entry and "Remove from Shared" or "Add to Shared")
		else
			d.toggle:SetLabel(entry and "Remove from Build" or "Add to Build")
		end
		d.toggle:SetKind("secondary")
		if locked then d.toggle:Disable() else d.toggle:Enable() end
		d.toggle.tooltipText = locked and "This perk can't be turned on or off."
			or shared and "Misc perks are kept in Shared Perks, which every build applies." or nil
		local onChar = GetPerkActive(id)
		d.state:SetText(rowStatus(id, entry, look) or look.off and "" or (onChar and S.Hex(C.muted, "On for your character")
			or S.Hex(C.muted, "Off for your character")))

		local y = SECTIONS_Y
		local function header(fs, text)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", PAD, -y)
			fs:SetText(text)
			fs:Show()
			y = y + 18
		end
		local function body(fs, text)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", PAD, -y)
			fs:SetWidth(width)
			fs:SetText(text)
			fs:Show()
			y = y + (fs:GetStringHeight() or 14) + PAD
		end

		local desc = Perks.Description(id, rank or 1)
		header(d.effectHead, rank and ("Effect at Rank %d"):format(rank) or "Effect at Rank 1")
		body(d.effect, desc or S.Hex(C.muted, "No description."))

		local set = Perks.SetOf(id)
		if set then
			local count, total = Perks.SetCount(set, inSet)
			header(d.setHead, ("Set: %s   %s"):format(set.name, S.Hex(C.muted, ("%d / %d"):format(count, total))))
			-- the set's counted perks, green when they count, then its bonuses, as the Perk Manager shows them
			local members = {}
			for _, member in ipairs(set.perks or {}) do
				if Perks.SetCounts(member) then members[#members + 1] = member end
			end
			table.sort(members, function(a, b) return PerkMgrPerks[a].name:upper() < PerkMgrPerks[b].name:upper() end)
			local names = {}
			for _, member in ipairs(members) do
				names[#names + 1] = S.Hex(inSet(member) and C.good or C.muted, "    " .. PerkMgrPerks[member].name)
			end
			local lines = { table.concat(names, "\n") }
			for _, b in ipairs(Perks.SetBonuses(set, inSet)) do lines[#lines + 1] = b.text end
			if Perks.SetCounts(id) == false then lines[#lines + 1] = S.Hex(C.muted, "This perk doesn't count toward the set.") end
			lines[#lines + 1] = S.Hex(C.muted, SET_NOTE)
			body(d.set, table.concat(lines, "\n\n"))
		else
			d.setHead:Hide()
			d.set:Hide()
		end

		local abilities = Perks.HasAbility(perk) and Perks.Abilities(id, mask) or {}
		local perRow = math.max(1, math.floor((width + ICON_GAP) / (ICON + ICON_GAP)))
		for i, a in ipairs(abilities) do
			local b = pooled(d.abilities, i, function() return newAbility(child) end)
			b.perk, b.spell, b.flags = id, a.spell, a.flags
			b.icon:SetTexture(spellIcon(a.spell))
			local chosen = entry and entry.spell == a.spell
			b:SetBackdropBorderColor(unpack(chosen and C.accent or C.border))
			b.icon:SetDesaturated(entry ~= nil and not chosen and (entry.spell or 0) ~= 0)
			b:SetAlpha(entry and 1 or 0.5)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", PAD + ((i - 1) % perRow) * (ICON + ICON_GAP), -(y + 36 + math.floor((i - 1) / perRow) * (ICON + ICON_GAP)))
			b:Show()
		end
		for i = #abilities + 1, #d.abilities do d.abilities[i]:Hide() end
		if #abilities > 0 then
			header(d.abilityHead, "Ability")
			local spell = entry and (entry.spell or 0) ~= 0 and entry.spell
			d.abilityNote:ClearAllPoints()
			d.abilityNote:SetPoint("TOPLEFT", PAD, -y)
			d.abilityNote:SetWidth(width)
			d.abilityNote:SetText(spell and ("Chosen: " .. (GetSpellInfo(spell) or spell))
				or S.Hex(C.muted, entry and "None chosen yet." or "Add the perk to choose an ability."))
			d.abilityNote:Show()
			y = y + 18 + math.ceil(#abilities / perRow) * (ICON + ICON_GAP) + PAD
		else
			d.abilityHead:Hide()
			d.abilityNote:Hide()
		end

		local options = Perks.Options(id, mask)
		for i, o in ipairs(options) do
			local row = pooled(d.options, i, function() return newOption(child, width) end)
			row.perk, row.options, row.index, row.tip, row.group = id, options, o.index, o.tip, o.group
			row.label:SetText(o.name)
			row.check:SetChecked(entry and bit.band(entry.opt or 0, bit.lshift(1, o.index - 1)) ~= 0)
			row.check:SetEnabled(entry ~= nil)
			row.label:SetTextColor(unpack(entry and C.text or C.muted))
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", PAD - 4, -(y + 18 + (i - 1) * 22))
			row:Show()
		end
		for i = #options + 1, #d.options do d.options[i]:Hide() end
		if #options > 0 then
			header(d.optionHead, "Options")
			y = y + #options * 22 + PAD
		else
			d.optionHead:Hide()
		end

		local info = Perks.Info(id)
		if #info > 0 then
			header(d.infoHead, "Notes")
			body(d.info, S.Hex(C.muted, table.concat(info, "\n\n")))
		else
			d.infoHead:Hide()
			d.info:Hide()
		end

		child:SetHeight(y)
		d.scroll:UpdateScrollChildRect()
		d.updateBar()
	end
end

-- Toolbar ---------------------------------------------------------------------------------------------------

-- Shared Perks always lists every Misc perk, so it has no In Build / All Perks switch and the search fills the row.
local function renderToolbar()
	local shared = current.sharedOnly == true
	panel.showBuild:SetKind(state.filter == "build" and "selected" or "secondary")
	panel.showAll:SetKind(state.filter == "all" and "selected" or "secondary")
	if shared then panel.showBuild:Hide() panel.showAll:Hide() else panel.showBuild:Show() panel.showAll:Show() end
	panel.search:ClearAllPoints()
	if shared then
		panel.search:SetPoint("TOPLEFT", 0, 0)
		panel.search:SetWidth(LIST_RIGHT)
	else
		panel.search:SetPoint("LEFT", panel.showAll, "RIGHT", GAP, 0)
		panel.search:SetWidth(LIST_RIGHT - SEGMENTED_W - GAP)
	end
end

local function summary(look)
	local plan = look.plan
	local changes = #plan.activate + #plan.deactivate
	local text
	local options = #plan.options + #plan.spells
	if changes + options == 0 then
		text = S.Hex(C.good, current.sharedOnly and "Your Misc Perks Match Shared Perks" or "Your Perks Match This Build")
	else
		-- only the counts that aren't zero, so the line fits the footer
		local parts = {}
		if #plan.activate > 0 then parts[#parts + 1] = #plan.activate .. " to Activate" end
		if #plan.deactivate > 0 then parts[#parts + 1] = #plan.deactivate .. " to Deactivate" end
		if options > 0 then parts[#parts + 1] = S.Count(options, "Option Change") end
		text = table.concat(parts, ", ")
		if changes > 0 and not Perks.Writable() then
			text = text .. "   " .. S.Hex(C.bad, "Needs an Innkeeper")
		end
	end
	return text
end

function Editor.Render(build)
	if build ~= current then state.selected = nil end
	current = build
	Perks = SBS.Perks
	local text
	renderToolbar()
	if PerkMgrPerks then
		local mask = buildMask(build)
		local look = planLookup(build)
		renderList(build, mask, look)
		renderDetail(build, mask, look)
		text = summary(look)
	else
		panel.list:Begin()
		panel.list:Add({ text = S.Hex(C.muted, "Perk data hasn't arrived from the server yet.") })
		panel.list:End()
		state.selected = nil
		renderDetail(build, 0, nil)
	end
	return text
end

-- Construction ----------------------------------------------------------------------------------------------

local function createDetail(width, height)
	local d = CreateFrame("Frame", nil, panel)
	d:SetSize(width, height)
	S.Well(d)
	-- the scrolling detail sits inside the well's frame, however thick the theme draws it
	local wi = 1 + S.metrics.wellInset
	d.scroll = CreateFrame("ScrollFrame", "SynastriaBuildSuitePerkDetail", d, "UIPanelScrollFrameTemplate")
	d.scroll:SetPoint("TOPLEFT", wi, -wi)
	d.scroll:SetPoint("BOTTOMRIGHT", -11 - wi, wi)
	local child = CreateFrame("Frame", nil, d.scroll)
	child:SetSize(width - 12 - 2 * wi, height)
	d.scroll:SetScrollChild(child)
	d.child, d.innerW = child, width - 12 - 2 * wi - 2 * PAD
	d.updateBar = SBS.List.AutoHideBar(d.scroll, "SynastriaBuildSuitePerkDetail")

	d.none = S.Text(d, "small", C.muted)
	d.none:SetPoint("CENTER")
	d.none:SetText("Select a perk to see its details.")

	d.icon = child:CreateTexture(nil, "ARTWORK")
	d.icon:SetSize(ICON_ROW, ICON_ROW)
	d.icon:SetPoint("TOPLEFT", PAD, -PAD)
	d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- name and sub line (about 30px together) centered beside the icon
	d.name = S.Text(child, "large")
	d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", GAP, -3)
	d.name:SetPoint("RIGHT", -PAD, 0)
	d.sub = S.Text(child, "small", C.muted)
	d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
	d.sub:SetPoint("RIGHT", -PAD, 0)
	d.toggle = S.Button(child, "Add to Build", "secondary", 130, function() toggle(state.selected) end)
	d.toggle:SetPoint("TOPLEFT", PAD, -TOGGLE_Y)
	d.state = S.Text(child, "small")
	d.state:SetPoint("LEFT", d.toggle, "RIGHT", GAP, 0)
	d.state:SetPoint("RIGHT", -PAD, 0)

	d.effectHead = S.Text(child, "normal")
	d.effect = S.Text(child, "small")
	d.setHead = S.Text(child, "normal")
	d.set = S.Text(child, "small")
	d.abilityHead = S.Text(child, "normal")
	d.abilityNote = S.Text(child, "small")
	d.optionHead = S.Text(child, "normal")
	d.infoHead = S.Text(child, "normal")
	d.info = S.Text(child, "small")
	d.abilities, d.options = {}, {}
	return d
end

function Editor.Create(parent, width, height)
	Perks = SBS.Perks
	panel = CreateFrame("Frame", nil, parent)
	panel:SetSize(width, height)

	-- a segmented button: the two halves share their middle border
	panel.showBuild = S.Button(panel, "In Build", "selected", 80, function()
		state.filter = "build"
		SBS.Window.Render()
	end, "Show the perks in this build, and any it would turn off.")
	panel.showBuild:SetPoint("TOPLEFT", 0, 0)
	panel.showAll = S.Button(panel, "All Perks", "secondary", 80, function()
		state.filter = "all"
		SBS.Window.Render()
	end, "Show every perk the build's classes can use.")
	panel.showAll:SetPoint("LEFT", panel.showBuild, "RIGHT", -1, 0)
	panel.search = S.Input(panel, "SynastriaBuildSuitePerkSearch", LIST_RIGHT - SEGMENTED_W - GAP, "Search Perks", 40)
	panel.search:SetPoint("LEFT", panel.showAll, "RIGHT", GAP, 0)
	panel.search:HookScript("OnTextChanged", function(self)
		state.search = self:GetText():lower()
		SBS.Window.Render()
	end)

	panel.list = SBS.List.New(panel, "SynastriaBuildSuitePerkList", LIST_W - 14, height - TOOLBAR_H, nil, 14)
	panel.list.scroll:SetPoint("TOPLEFT", 0, -TOOLBAR_H)

	panel.detail = createDetail(width - LIST_RIGHT - PAD, height)
	panel.detail:SetPoint("TOPLEFT", LIST_RIGHT + PAD, 0)
	return panel
end
