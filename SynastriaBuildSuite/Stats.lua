local _, NS = ...
local SBS = NS.SBS

-- The character's stats as the character sheet shows them, for the Affixes tab. An affix order changes which
-- attuned affixes count, and with them these numbers, so a snapshot is taken whenever an order is sent and the tab
-- shows each stat's change since then. Each row's attune ID is the stat as GetAttuneStatName numbers it, which is
-- how an affix's stats are matched to a row.
local Stats = {}
SBS.Stats = Stats

local function round(v)
	return math.floor((v or 0) + 0.5)
end

local function attribute(index)
	return function() return select(2, UnitStat("player", index)) end
end

local function rating(name, fallback)
	return function() return GetCombatRating(_G[name] or fallback) end
end

local function resistance(school)
	return function() return select(2, UnitResistance("player", school)) end
end

local function attackPower(fn)
	return function()
		local base, plus, minus = fn("player")
		return (base or 0) + (plus or 0) + (minus or 0)
	end
end

local function spellPower()
	local best = 0
	for school = 2, 7 do best = math.max(best, GetSpellBonusDamage(school) or 0) end
	return math.max(best, GetSpellBonusHealing() or 0)
end

local function manaRegen()
	return (GetManaRegen() or 0) * 5
end

Stats.GROUPS = { "Attributes", "Physical", "Spell", "Shared Ratings", "Defense", "Resistances" }

-- key, label, group (index into GROUPS), attune stat ID, read; `always` rows show even at 0, `mana` rows only for
-- characters with mana.
Stats.ROWS = {
	{ key = "health", label = "Health", group = 1, attune = 1, always = true, read = function() return UnitHealthMax("player") end },
	{ key = "mana", label = "Mana", group = 1, attune = 0, mana = true, read = function() return UnitPowerMax("player", 0) end },
	{ key = "str", label = "Strength", group = 1, attune = 4, always = true, read = attribute(1) },
	{ key = "agi", label = "Agility", group = 1, attune = 3, always = true, read = attribute(2) },
	{ key = "sta", label = "Stamina", group = 1, attune = 7, always = true, read = attribute(3) },
	{ key = "int", label = "Intellect", group = 1, attune = 5, always = true, read = attribute(4) },
	{ key = "spi", label = "Spirit", group = 1, attune = 6, always = true, read = attribute(5) },
	{ key = "ap", label = "Attack Power", group = 2, attune = 38, read = attackPower(UnitAttackPower) },
	{ key = "rap", label = "Ranged Attack Power", group = 2, attune = 39, read = attackPower(UnitRangedAttackPower) },
	{ key = "expertise", label = "Expertise Rating", group = 2, attune = 37, read = rating("CR_EXPERTISE", 24) },
	{ key = "arpen", label = "Armor Penetration", group = 2, attune = 44, read = rating("CR_ARMOR_PENETRATION", 25) },
	{ key = "sp", label = "Spell Power", group = 3, attune = 45, read = spellPower },
	{ key = "spellpen", label = "Spell Penetration", group = 3, attune = 47, read = function() return GetSpellPenetration() end },
	{ key = "mp5", label = "Mana Regen (5s)", group = 3, attune = 43, mana = true, read = manaRegen },
	{ key = "hit", label = "Hit Rating", group = 4, attune = 31, read = rating("CR_HIT_MELEE", 6) },
	{ key = "crit", label = "Crit Rating", group = 4, attune = 32, read = rating("CR_CRIT_MELEE", 9) },
	{ key = "haste", label = "Haste Rating", group = 4, attune = 36, read = rating("CR_HASTE_MELEE", 18) },
	{ key = "armor", label = "Armor", group = 5, attune = 49, always = true, read = function() return select(2, UnitArmor("player")) end },
	{ key = "defense", label = "Defense Rating", group = 5, attune = 12, read = rating("CR_DEFENSE_SKILL", 2) },
	{ key = "dodge", label = "Dodge Rating", group = 5, attune = 13, read = rating("CR_DODGE", 3) },
	{ key = "parry", label = "Parry Rating", group = 5, attune = 14, read = rating("CR_PARRY", 4) },
	{ key = "block", label = "Block Rating", group = 5, attune = 15, read = rating("CR_BLOCK", 5) },
	{ key = "blockvalue", label = "Block Value", group = 5, attune = 48, read = function() return GetShieldBlock() end },
	{ key = "resil", label = "Resilience Rating", group = 5, attune = 35, read = rating("CR_CRIT_TAKEN_MELEE", 15) },
	{ key = "holy", label = "Holy Resistance", group = 6, attune = 50, read = resistance(1) },
	{ key = "fire", label = "Fire Resistance", group = 6, attune = 51, read = resistance(2) },
	{ key = "nature", label = "Nature Resistance", group = 6, attune = 52, read = resistance(3) },
	{ key = "frost", label = "Frost Resistance", group = 6, attune = 53, read = resistance(4) },
	{ key = "shadow", label = "Shadow Resistance", group = 6, attune = 54, read = resistance(5) },
	{ key = "arcane", label = "Arcane Resistance", group = 6, attune = 55, read = resistance(6) },
}

-- Every row's value, rounded, written into `into`.
function Stats.Read(into)
	for _, row in ipairs(Stats.ROWS) do into[row.key] = round(row.read()) end
	return into
end

function Stats.HasMana()
	return (UnitPowerMax("player", 0) or 0) > 0
end

-- Remembers the stats now; the tab shows each one's change from here until the next snapshot or Clear.
function Stats.Snapshot()
	Stats.baseline = Stats.Read(Stats.baseline or {})
	Stats.baselineAt = date("%H:%M")
end

function Stats.ClearSnapshot()
	Stats.baseline, Stats.baselineAt = nil, nil
end

-- The stat names (as GetAttuneStatName gives them) that any affix in the order gives, written into `into`.
function Stats.Touched(order, into)
	wipe(into)
	for _, id in ipairs(order or {}) do
		local info = SBS.Affixes.Info(id)
		for _, name in ipairs(info and info.stats or {}) do into[name] = true end
	end
	return into
end

function Stats.Gives(row, touched)
	local name = GetAttuneStatName and GetAttuneStatName(row.attune)
	return name ~= nil and touched[name] == true
end

-- Stat events fire for every buff and aura that moves a number, so the window only redraws when a value it shows
-- has changed. Reads into reused tables; returns whether anything changed.
local latest, shown = {}, {}
function Stats.Poll()
	Stats.Read(latest)
	local changed = false
	for key, value in pairs(latest) do
		if shown[key] ~= value then
			changed = true
			shown[key] = value
		end
	end
	return changed
end
