local _, NS = ...
local BF = NS.BF

-- Talent calculator rules over NS.TalentData, the same as the 3.3.5 talent frame: 5 points per tier, ranks
-- capped, prerequisites at their required rank, and a point can't be removed if something else depends on it.
local Calc = {}
BF.TalentCalc = Calc

Calc.MAX_POINTS = 71
Calc.POINTS_PER_TIER = 5

function Calc.Trees(class)
	return NS.TalentData and NS.TalentData[class]
end

-- The build's ranks for a class, created and padded to every talent so the editor can index them directly.
function Calc.Ensure(build, class)
	build.talents = build.talents or {}
	local trees = build.talents[class] or {}
	build.talents[class] = trees
	for tab, tree in ipairs(Calc.Trees(class) or {}) do
		local ranks = trees[tab] or {}
		for i = 1, #tree.talents do ranks[i] = ranks[i] or 0 end
		trees[tab] = ranks
	end
	return trees
end

function Calc.TreePoints(ranks)
	local sum = 0
	for _, r in ipairs(ranks or {}) do sum = sum + r end
	return sum
end

function Calc.TotalPoints(trees)
	local sum = 0
	for _, ranks in ipairs(trees or {}) do sum = sum + Calc.TreePoints(ranks) end
	return sum
end

local function pointsBelowTier(tree, ranks, tier)
	local sum = 0
	for i, t in ipairs(tree.talents) do
		if t[1] < tier then sum = sum + (ranks[i] or 0) end
	end
	return sum
end

-- Whether one more point can go into talent i of tree tab, and why not.
function Calc.CanAdd(class, trees, tab, i)
	local tree = Calc.Trees(class)[tab]
	local t, ranks = tree.talents[i], trees[tab]
	local rank = ranks[i] or 0
	local need = (t[1] - 1) * Calc.POINTS_PER_TIER
	local ok, reason = true, nil
	if rank >= #t[3] then
		ok, reason = false, "Maximum rank"
	elseif Calc.TotalPoints(trees) >= Calc.MAX_POINTS then
		ok, reason = false, ("All %d points are spent"):format(Calc.MAX_POINTS)
	elseif Calc.TreePoints(ranks) < need then
		ok, reason = false, ("Requires %d points in %s"):format(need, tree.name)
	elseif t[4] and (ranks[t[4]] or 0) < t[5] then
		local reqName = GetSpellInfo(tree.talents[t[4]][3][1]) or "the talent above"
		ok, reason = false, ("Requires %d point%s in %s"):format(t[5], t[5] == 1 and "" or "s", reqName)
	end
	return ok, reason
end

-- Whether a point can come out of talent i without breaking a dependent talent or a higher tier.
function Calc.CanRemove(class, trees, tab, i)
	local tree = Calc.Trees(class)[tab]
	local ranks = trees[tab]
	local rank = ranks[i] or 0
	local ok, reason = rank > 0, nil
	if ok then
		for j, other in ipairs(tree.talents) do
			if other[4] == i and (ranks[j] or 0) > 0 and rank - 1 < other[5] then
				ok, reason = false, ("%s depends on it"):format(GetSpellInfo(other[3][1]) or "Another talent")
			end
		end
	end
	if ok then
		local tier = tree.talents[i][1]
		ranks[i] = rank - 1
		for j, other in ipairs(tree.talents) do
			if ok and other[1] > tier and (ranks[j] or 0) > 0
				and pointsBelowTier(tree, ranks, other[1]) < (other[1] - 1) * Calc.POINTS_PER_TIER then
				ok, reason = false, "Talents in a higher tier need these points"
			end
		end
		ranks[i] = rank
	end
	return ok, reason
end

function Calc.Add(class, trees, tab, i)
	local ok = Calc.CanAdd(class, trees, tab, i)
	if ok then trees[tab][i] = trees[tab][i] + 1 end
	return ok
end

function Calc.Remove(class, trees, tab, i)
	local ok = Calc.CanRemove(class, trees, tab, i)
	if ok then trees[tab][i] = trees[tab][i] - 1 end
	return ok
end

function Calc.Reset(build, class)
	build.talents = build.talents or {}
	build.talents[class] = nil
	return Calc.Ensure(build, class)
end

-- Compares the data file with the live talent API for the class shown in the talent window. Returns mismatches.
function Calc.CheckLive()
	local class = BF.Talents.SelectedClass()
	local trees = Calc.Trees(class)
	local problems = {}
	if not trees then
		problems[1] = "no talent data for " .. tostring(class)
	else
		for tab = 1, GetNumTalentTabs(false, false) do
			local tree = trees[tab]
			local count = GetNumTalents(tab, false, false)
			if not tree or #tree.talents ~= count then
				problems[#problems + 1] = ("tree %d: %d talents live, %d in data"):format(tab, count, tree and #tree.talents or 0)
			else
				for i = 1, count do
					local name, _, tier, column, _, maxRank = GetTalentInfo(tab, i)
					local t = tree.talents[i]
					if tier ~= t[1] or column ~= t[2] or maxRank ~= #t[3] or name ~= GetSpellInfo(t[3][1]) then
						problems[#problems + 1] = ("tree %d talent %d: live %s %d/%d (%d ranks), data %s %d/%d (%d ranks)"):format(
							tab, i, tostring(name), tier or 0, column or 0, maxRank or 0,
							tostring(GetSpellInfo(t[3][1])), t[1], t[2], #t[3])
					end
				end
			end
		end
	end
	return problems, class
end
