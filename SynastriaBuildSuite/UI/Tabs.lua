local _, NS = ...
local SBS = NS.SBS

-- Per tab: diff(build) counts what differs from the character (for the tab badge), and actions are the footer
-- buttons, right to left: each tab's Use Current action comes first so it keeps the same spot. Each tab's content
-- is its editor in UI/.
local Tabs = { actions = {}, diff = {} }
SBS.Tabs = Tabs

-- An action's optional usable(build) disables its button, showing unusableTip instead of its tooltip.
local NOT_YOURS = "None of this build's classes are yours, so there's nothing to copy."

local function hasBuildClass(build)
	local any = build.sharedOnly or not build.classes or #build.classes == 0
	for _, class in ipairs(build.classes or {}) do
		if SBS:HasClass(class) then any = true end
	end
	return any
end

-- Perks

-- (the tab itself is the editor in UI/PerkEditor.lua)

Tabs.diff.perks = function(build)
	local count
	if PerkMgrPerks then
		local plan = SBS.Perks.BuildPlan(build)
		count = #plan.activate + #plan.deactivate + #plan.options + #plan.spells
	end
	return count
end

Tabs.actions.perks = {
	{ label = "Use Current Perks", tooltip = "Replace this list with the perks active on your character now: your Misc perks for Shared Perks, and for a build the ones its classes can use. Class perks for its classes you don't have stay.", usable = hasBuildClass, unusableTip = NOT_YOURS, run = function(build)
		if build.sharedOnly then
			local _, misc = SBS.Perks.Split(SBS.Perks.Capture())
			SBS.db.shared.perks = {}
			SBS.Perks.AddShared(misc)
		else
			SBS.Build.CopyCurrent(build, { perks = true })
		end
		SBS:Changed()
	end },
}

-- Talents (the tab itself is the calculator in UI/TalentEditor.lua)

-- Only the class shown in the talent window can be compared without switching classes.
Tabs.diff.talents = function(build)
	local class = SBS.Talents.SelectedClass()
	local trees = build.talents and build.talents[class]
	local count
	if trees then
		count = 0
		local group = SBS:ActiveGroup()
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
		for _, class in ipairs(SBS.Build.CopyCurrent(build, { talents = true })) do
			SBS:Print("|cffff6060Couldn't read %s talents; select it in the talent window and try again.|r", class)
		end
		SBS:Changed()
	end },
	{ label = "Reset Class", tooltip = "Clear every point this build spends in the class shown here.", run = function(build)
		SBS.TalentCalc.Reset(build, SBS.TalentEditor.state.class)
		SBS:Changed()
	end },
}

-- Glyphs (the tab itself is the socket editor in UI/GlyphEditor.lua)

Tabs.diff.glyphs = function(build)
	return SBS.Glyphs.ShownMissing(build)
end

Tabs.actions.glyphs = {
	{ label = "Use Current Glyphs", tooltip = "Replace this build's glyphs with the ones socketed in your active spec, for each of its classes you have.", usable = hasBuildClass, unusableTip = NOT_YOURS, run = function(build)
		SBS.Build.CopyCurrent(build, { glyphs = true })
		SBS:Changed()
	end },
	{ label = "Open Glyph Frame", tooltip = "Open the game's glyph window to socket the glyphs you're carrying.", run = function()
		SBS.Glyphs.OpenFrame()
	end },
}

-- Gear

-- (the tab itself is the paper doll in UI/GearEditor.lua)

Tabs.diff.gear = function(build)
	local count = 0
	for _, row in ipairs(SBS.Gear.Status(build.gear)) do
		if row.wearing ~= 1 then count = count + 1 end
	end
	return count
end

Tabs.actions.gear = {
	{ label = "Use Current Gear", tooltip = "Replace this build's gear with what you have equipped. Alts are cleared.", run = function(build)
		SBS.Build.CopyCurrent(build, { gear = true })
		SBS:Changed()
	end },
	{ label = "Equip from Bags", tooltip = "Put on the highest-ranked item you're carrying for each slot.", run = function(build) SBS:EquipGear(build) end },
}

-- Affixes (the tab itself is the priority list in UI/AffixEditor.lua)

Tabs.diff.affixes = function(build)
	return SBS.Affixes.Diff(build.affixes)
end

Tabs.actions.affixes = {
	{ label = "Use Current Affixes", tooltip = "Replace this build's affix order with your active spec's.", run = function(build)
		SBS.Build.CopyCurrent(build, { affixes = true })
		SBS:Changed()
	end },
	{ label = "Clear Order", tooltip = "Empty this build's affix order. Applying the build then leaves your spec's order alone.", run = function(build)
		build.affixes = {}
		SBS:Changed()
	end },
}
