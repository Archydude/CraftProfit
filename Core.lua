-- Craft Profit: startup, saved settings and the slash command.
--
-- Next to the profession window, shows your profit or loss on:
--   * a normal craft:    what the item sells for (minus the AH cut) minus the materials
--   * a crafting order:  the commission you receive minus the materials *you* supply
local ADDON_NAME, ns = ...

-- Fills in defaults and moves settings from older versions forward.
local function loadSettings()
	CraftProfitDB = CraftProfitDB or {}
	local db = CraftProfitDB
	-- Pre-release builds: one TSM price for everything, and a show/hide toggle.
	if db.source then
		db.matSource, db.saleSource, db.source = db.source, db.source, nil
	end
	db.shown = nil
	for key, value in pairs(ns.DEFAULTS) do
		if db[key] == nil then db[key] = value end
	end
	db.session = db.session or { total = 0, crafts = 0 }
	return db
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		-- A fresh login (or another character) starts a new session; /reload keeps
		-- the running total.
		local isInitialLogin = ...
		if isInitialLogin then ns.db.session = { total = 0, crafts = 0 } end
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		return
	end

	local name = ...
	if name == ADDON_NAME then
		ns.db = loadSettings()
		ns.Options.Create()
	end
	-- The profession window loads on demand; attach to it when it appears.
	if name == "Blizzard_Professions" or (name == ADDON_NAME and C_AddOns.IsAddOnLoaded("Blizzard_Professions")) then
		ns.Panel.Init()
	end
	if ns.Panel.Frame() then self:UnregisterEvent("ADDON_LOADED") end
end)

SLASH_CRAFTPROFIT1 = "/craftprofit"
SlashCmdList.CRAFTPROFIT = function() ns.Options.Open() end
