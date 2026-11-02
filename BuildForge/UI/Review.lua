local _, NS = ...
local BF = NS.BF

-- "Review Changes" sheet over the build pane: lists everything Apply would change, by section, before anything
-- is sent. Replaces the chat report and popup for applies started from the window.
local Review = {}
BF.Review = Review

local S = BF.Style
local C = S.colors

local sheet, current

local function lines(plan)
	local out = {}
	local function add(text, status, header, tooltip) out[#out + 1] = { text = text, status = status, header = header, indent = header and 0 or 12, tooltip = tooltip } end

	local target = BF.Window.SpecToSwitch(plan.build)
	if target then
		add("Spec", nil, true)
		add(S.Hex(C.warn, ("This build is linked to %s; you're in %s."):format(BF:SpecName(target), BF:SpecName(plan.group))),
			nil, false, function(tt)
				tt:AddLine("Wrong spec?", 1, 1, 1)
				tt:AddLine("Perks, talents and glyphs belong to the active spec. Switch Spec first, or apply here to link this spec too.", 0.8, 0.8, 0.8, true)
			end)
	end

	local p = plan.perks
	if #p.activate + #p.deactivate + #p.options + #p.spells + #p.skipped > 0 then
		add("Perks", nil, true)
		if p.needsInnkeeper and not BF.Perks.Writable() then
			add(S.Hex(C.warn, "Turning perks on or off needs the Perk window open at an innkeeper."), nil, false, function(tt)
				tt:AddLine("Away from an innkeeper", 1, 1, 1)
				tt:AddLine("Those changes are skipped. Options and chosen abilities still apply; apply again at an innkeeper for the rest.", 0.8, 0.8, 0.8, true)
			end)
		end
		for _, id in ipairs(p.activate) do add(BF.Perks.Name(id), S.Hex(C.good, "Turn On")) end
		for _, id in ipairs(p.deactivate) do add(BF.Perks.Name(id), S.Hex(C.bad, "Turn Off")) end
		local optionsByPerk = {}
		for _, o in ipairs(p.options) do optionsByPerk[o.id] = (optionsByPerk[o.id] or 0) + 1 end
		for id, n in pairs(optionsByPerk) do add(BF.Perks.Name(id), S.Hex(C.warn, n == 1 and "1 Option" or (n .. " Options"))) end
		for _, s in ipairs(p.spells) do add(BF.Perks.Name(s.id), S.Hex(C.warn, "Ability: " .. (GetSpellInfo(s.spell) or s.spell))) end
		for _, s in ipairs(p.skipped) do add(S.Hex(C.muted, BF.Perks.Name(s.id)), S.Hex(C.muted, "Skipped: " .. s.reason)) end
	end

	local t = plan.talents
	local talentLines = {}
	for _, entry in ipairs(t.classes) do
		local name = BF.Window.ClassText({ entry.class })
		if #entry.conflicts > 0 then
			talentLines[#talentLines + 1] = { name, S.Hex(C.bad, ("%d talent(s) above the build: reset talents first"):format(#entry.conflicts)),
				function(tt)
					tt:AddLine("Talents can only be added", 1, 1, 1)
					tt:AddLine("Your spec has more points in these talents than the build. Unlearn your talents at a class trainer and BuildForge reopens this review, ready to apply. Or use Use My Talents on the Talents tab if your spec is the one to keep.", 0.8, 0.8, 0.8, true)
				end }
			for _, c in ipairs(entry.conflicts) do
				talentLines[#talentLines + 1] = { S.Hex(C.muted, "    " .. (c.name or "Talent")),
					S.Hex(C.bad, ("You have %d, build has %d"):format(c.have, c.want)) }
			end
		elseif entry.points > 0 then
			local short = entry.points > entry.unspent and S.Hex(C.bad, (" (only %d unspent)"):format(entry.unspent)) or ""
			talentLines[#talentLines + 1] = { name, S.Hex(C.good, ("Spend %d point(s)"):format(entry.points)) .. short }
		end
	end
	for _, s in ipairs(t.skipped) do talentLines[#talentLines + 1] = { BF.Window.ClassText({ s.class }), S.Hex(C.muted, "Skipped: " .. s.reason) } end
	if #talentLines > 0 then
		add("Talents", nil, true)
		for _, l in ipairs(talentLines) do add(l[1], l[2], false, l[3]) end
	end

	if #plan.glyphs > 0 then
		add("Glyphs", nil, true)
		for _, g in ipairs(plan.glyphs) do add(g.name, S.Hex(C.muted, "Socket Yourself")) end
	end

	if plan.pet or plan.spec then
		add("Other", nil, true)
		if plan.pet then add("Hunter pet aspects", S.Hex(C.good, "Change")) end
		if plan.spec then add("Spec name", S.Hex(C.good, plan.spec)) end
	end
	return out
end

-- Whether applying would send anything (glyphs and skipped items are information only).
local function hasChanges(plan)
	local p = plan.perks
	local talents = false
	for _, entry in ipairs(plan.talents.classes) do
		if #entry.conflicts == 0 and entry.points > 0 then talents = true end
	end
	local perks = #p.options + #p.spells > 0 or (p.needsInnkeeper and BF.Perks.Writable())
	return perks or talents or plan.pet ~= nil or plan.spec ~= nil
end

function Review.Render()
	local plan = BF.Build.Plan(current)
	for _, entry in ipairs(plan.talents.classes) do
		if #entry.conflicts > 0 then Review.pending = current.name end
	end
	sheet.title:SetText("Review Changes: " .. current.name)
	sheet.list:Begin()
	local rows = lines(plan)
	for _, l in ipairs(rows) do sheet.list:Add(l) end
	if #rows == 0 then sheet.list:Add({ text = S.Hex(C.good, "Your character already matches this build.") }) end
	sheet.list:End()
	local changes = hasChanges(plan)
	if changes then sheet.confirm:Enable() else sheet.confirm:Disable() end
	sheet.switch.target = BF.Window.SpecToSwitch(current)
	if sheet.switch.target then sheet.switch:Show() else sheet.switch:Hide() end
	sheet.note:SetText(changes and "Gear isn't changed here: use Equip from Bags on the Gear tab." or "Nothing to apply.")
end

function Review.Open(build)
	current = build
	sheet:Show()
	Review.Render()
end

function Review.Close()
	sheet:Hide()
end

local function confirm()
	local build = current
	Review.pending = nil
	local result = BF.Build.Apply(BF.Build.Plan(build))
	local problems = #result.refused
	for _, r in ipairs(result.refused) do BF:Print("|cffff6060Couldn't add %s (%s).|r", r.name, r.class) end
	Review.Close()
	BF:Print("Applied %s.", build.name)
	BF:Changed()
	BF.Window.Message(problems > 0 and S.Hex(C.warn, ("Applied, but %d talent(s) were refused; see chat."):format(problems))
		or S.Hex(C.good, "Applied " .. build.name .. "."))
end

-- Talents can only be added, so a build whose talents conflict waits for a trainer reset. CONFIRM_TALENT_WIPE
-- fires when the trainer offers it; once the spent points drop to 0, the review opens again for that build (or
-- the build linked to this spec).
local resetWatch = CreateFrame("Frame")
resetWatch:RegisterEvent("CONFIRM_TALENT_WIPE")
resetWatch:RegisterEvent("PLAYER_TALENT_UPDATE")
resetWatch:RegisterEvent("CHARACTER_POINTS_CHANGED")
resetWatch:SetScript("OnEvent", function(_, event)
	if event == "CONFIRM_TALENT_WIPE" then
		Review.wiping = true
	elseif Review.wiping and BF.Talents.Spent() == 0 then
		Review.wiping = false
		local name = Review.pending or BF:Links()[BF:ActiveGroup()]
		local build = name and BF.db.builds[name]
		Review.pending = nil
		if build then
			BF.Window.Open(build.name)
			Review.Open(build)
			BF:Print("Talents reset. Review %s and click Apply Changes.", build.name)
		end
	end
end)

function Review.Create(parent, width, height)
	sheet = CreateFrame("Frame", "BuildForgeReview", parent)
	sheet:SetAllPoints()
	sheet:SetFrameLevel(parent:GetFrameLevel() + 20)
	sheet:EnableMouse(true)
	S.Panel(sheet, { C.window[1], C.window[2], C.window[3], 1 })
	sheet:Hide()

	sheet.title = S.Text(sheet, "large")
	sheet.title:SetPoint("TOPLEFT", 20, -18)
	local sub = S.Text(sheet, "small", C.muted)
	sub:SetPoint("TOPLEFT", sheet.title, "BOTTOMLEFT", 0, -6)
	sub:SetText("Nothing changes until you click Apply Changes.")
	local rule = S.Solid(sheet, "BORDER", C.border)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 0, -64)
	rule:SetPoint("TOPRIGHT", 0, -64)

	sheet.list = BF.List.New(sheet, "BuildForgeReviewScroll", width - 40, height - 64 - 58)
	sheet.list.scroll:SetPoint("TOPLEFT", 8, -72)

	local footer = S.Solid(sheet, "BORDER", C.border)
	footer:SetHeight(1)
	footer:SetPoint("BOTTOMLEFT", 0, 46)
	footer:SetPoint("BOTTOMRIGHT", 0, 46)
	sheet.confirm = S.Button(sheet, "Apply Changes", "primary", 120, confirm)
	sheet.confirm:SetPoint("BOTTOMRIGHT", -16, 11)
	local cancel = S.Button(sheet, "Cancel", "secondary", 80, Review.Close)
	cancel:SetPoint("RIGHT", sheet.confirm, "LEFT", -6, 0)
	sheet.switch = S.Button(sheet, "Switch Spec", "secondary", 100, function(self)
		Review.Close()
		BF.Window.SwitchSpec(self.target)
	end, "Activate the build's linked spec, then apply again.")
	sheet.switch:SetPoint("RIGHT", cancel, "LEFT", -6, 0)
	sheet.note = S.Text(sheet, "small", C.muted)
	sheet.note:SetPoint("BOTTOMLEFT", 16, 17)
	return sheet
end
