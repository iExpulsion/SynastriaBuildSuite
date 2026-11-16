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

-- The saved skin, window size and pixel snapping (S.Settings) go on once saved data is loaded (Core's handler runs
-- first), before anything is built; frames take their look when they're made.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name == ADDON then
		S.Settings.Use(SBS.db, { theme = YELLOW, name = "Synastria Build Suite",
			onRescaled = function() SBS.Window.Rescaled() end })
		self:UnregisterEvent("ADDON_LOADED")
	end
end)

SBS.WINDOW_SCALES = S.Settings.SCALES
SBS.ScaleLabel = S.Settings.ScaleLabel
SBS.SetWindowScale = S.Settings.SetWindowScale
SBS.PixelScale = S.Settings.PixelScale
SBS.SnapPosition = S.Settings.SnapPosition
SBS.SetPixelScale = S.Settings.SetPixelScale
SBS.SetSkin = S.Settings.SetSkin
