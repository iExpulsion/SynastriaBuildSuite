local _, NS = ...
local BF = NS.BF

-- Per tab: diff(build) counts what differs from the character (for the tab badge), and actions are the footer
-- buttons. Each tab's content is its editor in UI/.
local Tabs = { actions = {}, diff = {} }
BF.Tabs = Tabs

-- An action's optional usable(build) disables its button, showing unusableTip instead of its tooltip.
local NOT_YOURS = "None of this build's classes are yours, so there's nothing to copy."

local function hasBuildClass(build)
	local any = build.sharedOnly or not build.classes or #build.classes == 0
	for _, class in ipairs(build.classes or {}) do
		if BF:HasClass(class) then any = true end
	end
	return any
end

-- Perks

-- (the tab itself is the editor in UI/PerkEditor.lua)

Tabs.diff.perks = function(build)
	local count
	if PerkMgrPerks then
		local plan = BF.Perks.BuildPlan(build)
		count = #plan.activate + #plan.deactivate + #plan.options + #plan.spells
	end
	return count
end

Tabs.actions.perks = {
	{ label = "Use Current Perks", tooltip = "Replace this list with the perks active on your character now: your Misc perks for Shared Perks, and for a build the ones its classes can use. Class perks for its classes you don't have stay.", usable = hasBuildClass, unusableTip = NOT_YOURS, run = function(build)
		if build.sharedOnly then
			local _, misc = BF.Perks.Split(BF.Perks.Capture())
			BF.db.shared.perks = {}
			BF.Perks.AddShared(misc)
		else
			BF.Build.CopyCurrent(build, { perks = true })
		end
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
	{ label = "Use Current Talents", tooltip = "Replace this build's talents with your active spec's, for each of its classes you have.", usable = hasBuildClass, unusableTip = NOT_YOURS, run = function(build)
		for _, class in ipairs(BF.Build.CopyCurrent(build, { talents = true })) do
			BF:Print("|cffff6060Couldn't read %s talents; select it in the talent window and try again.|r", class)
		end
		BF:Changed()
	end },
	{ label = "Reset Class", tooltip = "Clear every point this build spends in the class shown here.", run = function(build)
		BF.TalentCalc.Reset(build, BF.TalentEditor.state.class)
		BF:Changed()
	end },
}

-- Glyphs (the tab itself is the socket editor in UI/GlyphEditor.lua)

Tabs.diff.glyphs = function(build)
	return BF.Glyphs.ShownMissing(build)
end

Tabs.actions.glyphs = {
	{ label = "Open Glyph Frame", tooltip = "Open the game's glyph window to socket the glyphs you're carrying.", run = function()
		BF.Glyphs.OpenFrame()
	end },
	{ label = "Use Current Glyphs", tooltip = "Replace this build's glyphs with the ones socketed in your active spec, for each of its classes you have.", usable = hasBuildClass, unusableTip = NOT_YOURS, run = function(build)
		BF.Build.CopyCurrent(build, { glyphs = true })
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
	{ label = "Use Current Gear", tooltip = "Replace this build's gear with what you have equipped. Alts are cleared.", run = function(build)
		BF.Build.CopyCurrent(build, { gear = true })
		BF:Changed()
	end },
}
