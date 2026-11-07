local _, NS = ...
local SBS = NS.SBS

-- The Sources sheet over the build pane: the build's gear you don't own yet, grouped by zone and then by where it
-- comes from, so you can see which runs cover the most. Each item's source is its best one in Synastria's loot
-- database, picked as its item tooltips pick them: by chance, skipping unknown zones and the other faction's quests.
local Sources = {}
SBS.Sources = Sources

local S = SBS.Style
local C = S.colors

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local NO_SOURCE = "No Known Source"
-- by chance, as the item tooltips sort them
local SORT_BY_CHANCE = 3
local TAGS = {
	[2] = "Quest", [3] = "Container", [5] = "Craft", [6] = "Craft", [7] = "Fishing", [8] = "Fishing",
	[9] = "Vendor", [10] = "Milling", [11] = "Prospect", [13] = "Skinning", [14] = "Pickpocket",
}

local sheet, current

local function sameFaction(objType, objId)
	local q = objType == 2 and Custom_GetQuestData and Custom_GetQuestData(objId)
	return not q or bit.band(q, 12) == 4
end

-- The item's best source, or nil when the loot database has none it would show.
function Sources.Best(id)
	local count = ItemLocGetSourceCount and ItemLocGetSourceCount(id) or 0
	if count > 0 then ItemLocSetSourceSort(id, SORT_BY_CHANCE) end
	for i = 1, count do
		local srcType, objType, objId, chance, _, name, zone = ItemLocGetSourceAt(id, i)
		if zone and zone ~= "" and zone ~= "?" and sameFaction(objType, objId) then
			local tag = TAGS[srcType]
			return { zone = zone, name = (tag and ("[" .. tag .. "] ") or "") .. (name or "?"), chance = chance }
		end
	end
end

local function byCountThenName(a, b)
	if #a.items ~= #b.items then return #a.items > #b.items end
	return a.name < b.name
end

-- The build's missing gear: { zones = { { name, items, sources = { { name, items = { item } } } } }, count }. An
-- item is { id, slot, rank, chance }. Zones and sources with the most items come first; items with no known source
-- go last.
function Sources.Gather(build)
	local zones, byZone, seen, count = {}, {}, {}, 0
	local function add(zoneName, sourceName, item)
		local zone = byZone[zoneName]
		if not zone then
			zone = { name = zoneName, items = {}, sources = {}, bySource = {} }
			byZone[zoneName] = zone
			zones[#zones + 1] = zone
		end
		local source = zone.bySource[sourceName]
		if not source then
			source = { name = sourceName, items = {} }
			zone.bySource[sourceName] = source
			zone.sources[#zone.sources + 1] = source
		end
		source.items[#source.items + 1] = item
		zone.items[#zone.items + 1] = item
	end
	for slot = 1, 18 do
		for rank, id in ipairs(build.gear and build.gear[slot] or {}) do
			if not seen[id] and not SBS.LootFilter.Owned(id) then
				seen[id] = true
				count = count + 1
				local best = Sources.Best(id)
				local item = { id = id, slot = slot, rank = rank, chance = best and best.chance }
				add(best and best.zone or NO_SOURCE, best and best.name or "", item)
			end
		end
	end
	for _, zone in ipairs(zones) do table.sort(zone.sources, byCountThenName) end
	table.sort(zones, function(a, b)
		if (a.name == NO_SOURCE) ~= (b.name == NO_SOURCE) then return b.name == NO_SOURCE end
		return byCountThenName(a, b)
	end)
	return { zones = zones, count = count }
end

local function chanceText(chance)
	local text
	if not chance or chance > 100.5 then text = ""
	elseif chance >= 10 then text = ("%d%%"):format(chance)
	elseif chance >= 1 then text = ("%.1f%%"):format(chance)
	else text = ("%.2f%%"):format(chance)
	end
	return text
end

local function itemName(id)
	local name, _, quality = GetItemInfo(id)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return color and (color.hex .. name .. "|r") or name or ("Item " .. id)
end

local function slotText(item)
	return SBS.SLOT_NAMES[item.slot] .. (item.rank > 1 and (", Alt " .. (item.rank - 1)) or "")
end

function Sources.Render()
	local data = Sources.Gather(current)
	sheet.title:SetText("Gear Sources: " .. current.name)
	local list = sheet.list
	list:Begin()
	for _, zone in ipairs(data.zones) do
		list:Add({ text = zone.name, header = true, status = S.Hex(C.muted, S.Count(#zone.items, "Item")) })
		for _, source in ipairs(zone.sources) do
			if source.name ~= "" then list:Add({ text = source.name, indent = 12 }) end
			for _, item in ipairs(source.items) do
				local id = item.id
				list:Add({
					text = itemName(id), icon = GetItemIcon(id) or QUESTION, indent = 24,
					status = S.Hex(C.muted, slotText(item)) .. "   " .. chanceText(item.chance),
					onClick = function()
						if IsModifiedClick("CHATLINK") then
							local link = select(2, GetItemInfo(id))
							if link then ChatEdit_InsertLink(link) end
						elseif OpenLootDb then
							OpenLootDb(id)
						end
					end,
					tooltip = function(tt)
						tt:SetHyperlink("item:" .. id)
						tt:AddLine(" ")
						tt:AddLine("Click to open it in the Loot Database. Shift-click links it.", 0.6, 0.6, 0.66, true)
					end,
				})
			end
		end
	end
	if data.count == 0 then list:Add({ text = S.Hex(C.good, "You Have Every Item This Build Lists") }) end
	list:End()
	local places = 0
	for _, zone in ipairs(data.zones) do
		if zone.name ~= NO_SOURCE then places = places + 1 end
	end
	sheet.note:SetText(data.count == 0 and "" or ("%s Missing in %s"):format(S.Count(data.count, "Item"), S.Count(places, "Zone")))
end

function Sources.Open(build)
	S.Dismiss()
	current = build
	sheet:Show()
	Sources.Render()
end

function Sources.Close()
	S.Dismiss()
	sheet:Hide()
	SBS.Window.Render()
end

function Sources.Shown()
	return sheet ~= nil and sheet:IsShown()
end

-- Built like the review sheet: a header, the list, and a footer the same height as the window's.
function Sources.Create(parent, width, height)
	local PAD, GAP, CONTROL_H = S.PAD, S.GAP, S.CONTROL_H
	sheet = CreateFrame("Frame", "SynastriaBuildSuiteSources", parent)
	sheet:SetAllPoints()
	sheet:SetFrameLevel(parent:GetFrameLevel() + 20)
	sheet:EnableMouse(true)
	local fill = S.Solid(sheet, "BACKGROUND", { C.window[1], C.window[2], C.window[3], 1 })
	fill:SetPoint("TOPLEFT")
	fill:SetPoint("BOTTOMRIGHT", -1, 1)
	sheet:Hide()

	local headerH = PAD + 16 + 4 + 12 + PAD
	local footerH = PAD + CONTROL_H + PAD
	sheet.title = S.Text(sheet, "large")
	sheet.title:SetPoint("TOPLEFT", PAD, -PAD)
	local sub = S.Text(sheet, "small", C.muted)
	sub:SetPoint("TOPLEFT", sheet.title, "BOTTOMLEFT", 0, -4)
	sub:SetText("Where to find this build's gear you don't own yet, by zone. Click an item to open it in the Loot Database.")
	local rule, ruleH = S.Divider(sheet, "rule")
	rule:SetHeight(ruleH)
	rule:SetPoint("TOPLEFT", 0, -headerH)
	rule:SetPoint("TOPRIGHT", 0, -headerH)

	sheet.list = SBS.List.New(sheet, "SynastriaBuildSuiteSourcesScroll", width - 14, height - headerH - footerH - 2 * GAP)
	sheet.list.scroll:SetPoint("TOPLEFT", 0, -(headerH + GAP))

	local footer, footerRuleH = S.Divider(sheet, "rule")
	footer:SetHeight(footerRuleH)
	footer:SetPoint("BOTTOMLEFT", 0, footerH)
	footer:SetPoint("BOTTOMRIGHT", 0, footerH)
	local close = S.Button(sheet, "Close", "secondary", 80, Sources.Close)
	close:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	sheet.note = S.Text(sheet, "small", C.muted)
	sheet.note:SetPoint("LEFT", sheet, "BOTTOMLEFT", PAD, footerH / 2)
	return sheet
end
