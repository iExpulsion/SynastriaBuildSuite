local _, NS = ...
local BF = NS.BF

-- Per tab: render(list, build) fills the list and returns a summary line, diff(build) counts what differs
-- from the character (for the tab badge), and actions are the footer buttons.
local Tabs = { render = {}, actions = {}, diff = {} }
BF.Tabs = Tabs

local GREEN, YELLOW, GREY = "|cff6bdb6b", "|cffffc742", "|cff9999a8"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function color(c, text) return c .. text .. "|r" end

local function spellIcon(id)
	return id and select(3, GetSpellInfo(id)) or QUESTION
end

-- Perks

-- (the tab itself is the editor in UI/PerkEditor.lua)

Tabs.diff.perks = function(build)
	local count
	if PerkMgrPerks then
		local plan = BF.Perks.Plan(BF.Perks.Wanted(build))
		count = #plan.activate + #plan.deactivate + #plan.options + #plan.spells
	end
	return count
end

Tabs.actions.perks = {
	{ label = "Use My Perks", tooltip = "Replace this build's perks with the ones active on your character now. Your active Misc perks become the Shared Perks every build uses.", run = function(build)
		local own, misc = BF.Perks.Split(BF.Perks.Capture())
		build.perks = own
		BF.db.shared.perks = {}
		BF.Perks.AddShared(misc)
		BF:Changed()
	end },
}

-- Talents (the tab itself is the calculator in UI/TalentEditor.lua)

-- Only the class shown in the talent window can be compared without switching classes.
Tabs.diff.talents = function(build)
	local class = BF.Talents.SelectedClass()
	local trees = build.talents and build.talents[class]
	local count
	if trees then
		count = 0
		local group = BF:ActiveGroup()
		for tab = 1, GetNumTalentTabs(false, false) do
			local want = trees[tab] or {}
			for i = 1, GetNumTalents(tab, false, false) do
				local rank = select(5, GetTalentInfo(tab, i, false, false, group)) or 0
				if rank ~= (want[i] or 0) then count = count + 1 end
			end
		end
	end
	return count
end

Tabs.actions.talents = {
	{ label = "Use My Talents", tooltip = "Replace this build's talents with your active spec's, for each of your classes.", run = function(build)
		local talents, missed = BF.Talents.Capture()
		build.talents = talents
		build.classes = BF:PlayerClasses()
		for _, class in ipairs(missed) do
			BF:Print("|cffff6060Couldn't read %s talents; select it in the talent window and try again.|r", class)
		end
		BF:Changed()
	end },
	{ label = "Reset Class", tooltip = "Clear every point this build spends in the class shown here.", run = function(build)
		BF.TalentCalc.Reset(build, BF.TalentEditor.state.class)
		BF:Changed()
	end },
}

-- Glyphs

Tabs.render.glyphs = function(list, build)
	local group, missing, count = BF:ActiveGroup(), 0, 0
	local sockets = {}
	for socket in pairs(build.glyphs or {}) do sockets[#sockets + 1] = socket end
	table.sort(sockets)
	for _, socket in ipairs(sockets) do
		local spell = build.glyphs[socket]
		local _, glyphType, have = GetGlyphSocketInfo(socket, group)
		local kind = glyphType == 1 and "Major" or "Minor"
		local status
		count = count + 1
		if have == spell then
			status = color(GREY, "Socketed")
		else
			missing = missing + 1
			status = have and color(YELLOW, "Socket has " .. (GetSpellInfo(have) or have)) or color(YELLOW, "Empty Socket")
		end
		list:Add({
			text = ("%s  %s"):format(color(GREY, kind), GetSpellInfo(spell) or ("Glyph " .. spell)),
			icon = spellIcon(spell), status = status,
			tooltip = function(tt) tt:SetHyperlink("spell:" .. spell) end,
		})
	end
	if count == 0 then return color(GREY, "This build has no glyphs.") end
	return missing == 0 and color(GREEN, "Your glyphs match this build.")
		or ("%d glyph(s) to socket. Glyphs are used up, so BuildForge leaves socketing to you."):format(missing)
end

Tabs.diff.glyphs = function(build)
	return #BF.Glyphs.Plan(build.glyphs)
end

Tabs.actions.glyphs = {
	{ label = "Use My Glyphs", tooltip = "Replace this build's glyphs with the ones socketed in your active spec.", run = function(build)
		build.glyphs = BF.Glyphs.Capture()
		BF:Changed()
	end },
}

-- Gear

-- (the tab itself is the paper doll in UI/GearEditor.lua)

Tabs.diff.gear = function(build)
	local count = 0
	for _, row in ipairs(BF.Gear.Status(build.gear)) do
		if row.wearing ~= 1 then count = count + 1 end
	end
	return count
end

Tabs.actions.gear = {
	{ label = "Equip from Bags", tooltip = "Put on the highest-ranked item you're carrying for each slot.", run = function(build) BF:EquipGear(build) end },
	{ label = "Use My Gear", tooltip = "Replace this build's gear with what you have equipped. Alts are cleared.", run = function(build)
		build.gear = BF.Gear.Capture()
		BF:Changed()
	end },
}
