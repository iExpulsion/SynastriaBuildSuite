local _, NS = ...
local SBS = NS.SBS

-- What other addons may use, as SynastriaBuildSuite.API. Look it up when needed, since Build Suite may not be
-- installed or may load later. Fields are only ever added, and version goes up when they are.
local API = { version = 1 }
SBS.API = API

local listeners = {}

-- True while Build Suite's window is open.
function API.IsShown()
	local f = SBS.Window and SBS.Window.Frame()
	return f ~= nil and f:IsShown() ~= nil
end

-- Calls callback(shown) each time Build Suite's window opens or closes.
function API.OnShownChanged(callback)
	listeners[#listeners + 1] = callback
end

function SBS.ShownChanged(shown)
	for _, callback in ipairs(listeners) do
		local ok, err = pcall(callback, shown)
		if not ok then geterrorhandler()(err) end
	end
end
