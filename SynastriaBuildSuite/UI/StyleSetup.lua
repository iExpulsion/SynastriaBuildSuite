local ADDON, NS = ...
local SBS = NS.SBS

-- The style kit (UI/Style.lua, vendored from MaterialCraftUI) puts itself on the addon table, and its skins
-- (UI/Skins) register with it.
local S = NS.Style
SBS.Style = S

-- The shared yellow theme of these addons: the Material 3 dark scheme for seed #ffc400, with surfaces from the
-- Neutral scheme, primary from the Fidelity scheme and error from the baseline. Skins with a scheme of their own,
-- such as Cognac and Classic, use theirs instead.
local YELLOW = {
	surfaceLowest = "0f0e0c", surface = "151311", surfaceLow = "1d1b19", surfaceContainer = "211f1d",
	surfaceHigh = "2c2a27", onSurface = "e7e1dd", onSurfaceVariant = "cbc6c1", outline = "94908c",
	outlineVariant = "494643", primary = "ffc400", onPrimary = "3f2e00", error = "ffb4ab", errorContainer = "93000a",
}
S.SetTheme(YELLOW)

-- the Perk Manager's set name green, kept so sets read as they do in the client
S.colors.set = { 0.13, 1, 0.13, 1 }

local function known(key)
	for _, skin in ipairs(S.Skins()) do
		if skin.key == key then return true end
	end
	return false
end

-- The saved skin goes on once saved data is loaded (Core's handler runs first), before anything is built; frames
-- take their look when they're made.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name == ADDON then
		if not known(SBS.db.skin) then SBS.db.skin = "material" end
		if SBS.db.pixelScale == nil then SBS.db.pixelScale = true end
		if SBS.db.windowScale == nil then SBS.db.windowScale = 1 end
		S.UseSkin(SBS.db.skin, YELLOW)
		S.SetWindowScale(SBS.db.windowScale)
		self:UnregisterEvent("ADDON_LOADED")
	end
end)

StaticPopupDialogs.SYNASTRIA_BUILD_SUITE_RELOAD = {
	text = "Synastria Build Suite switches to the %s theme after a reload. Reload now?",
	button1 = "Reload",
	button2 = "Later",
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- Saves a skin for the next load and offers to reload. Returns false for a skin that doesn't exist.
function SBS.SetSkin(key)
	local ok = known(key)
	if ok and key ~= SBS.db.skin then
		SBS.db.skin = key
		local label = key
		for _, skin in ipairs(S.Skins()) do
			if skin.key == key then label = skin.label end
		end
		StaticPopup_Show("SYNASTRIA_BUILD_SUITE_RELOAD", label)
	end
	return ok
end

-- Build Suite's window and dialogs are pixel-scaled (S.PixelScale) unless the player turned it off, so their edges
-- and 1px borders land on whole screen pixels. SBS.PixelScale registers one as it's made.
local pixelFrames = {}

function SBS.PixelScale(frame)
	pixelFrames[#pixelFrames + 1] = frame
	S.PixelScale(frame, SBS.db.pixelScale)
	return frame
end

-- Snaps a window's position to whole pixels, when pixel scaling is on.
function SBS.SnapPosition(frame)
	if SBS.db.pixelScale then S.SnapPosition(frame) end
end

function SBS.SetPixelScale(on)
	SBS.db.pixelScale = on
	for _, frame in ipairs(pixelFrames) do
		S.PixelScale(frame, on)
		SBS.SnapPosition(frame)
	end
	SBS.Window.Rescaled()
end

-- the sizes offered for the window and dialogs
SBS.WINDOW_SCALES = { 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2 }
local MIN_SCALE, MAX_SCALE = 0.5, 3

function SBS.ScaleLabel(scale)
	return ("%d%%"):format(math.floor(scale * 100 + 0.5))
end

-- Sets the size of the window and dialogs and keeps the window's saved spot. Returns false when out of range.
function SBS.SetWindowScale(scale)
	local ok = type(scale) == "number" and scale >= MIN_SCALE and scale <= MAX_SCALE
	if ok then
		SBS.db.windowScale = scale
		S.SetWindowScale(scale)
		SBS.Window.Rescaled()
	end
	return ok
end
