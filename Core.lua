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
	-- Up to 1.10 the button had a choice of where to send materials, Blizzard's
	-- recipe tracker included. Now it's on or off, plus which auction addon.
	if db.missingTarget then
		if db.missingTarget == "off" then db.shoppingButton = false end
		if db.missingTarget == "auctionator" or db.missingTarget == "tsm" then db.listAddon = db.missingTarget end
		db.missingTarget = nil
	end
	-- Up to 2.6 there was a "Most profit" crafting strategy.
	if db.craftStrategy == "profit" then db.craftStrategy = "highest" end
	for key, value in pairs(ns.DEFAULTS) do
		if db[key] == nil then db[key] = value end
	end
	db.session = db.session or { total = 0, crafts = 0 }
	db.tsmOrders = db.tsmOrders or {} -- the Patron tab's running TSM search (see Patron.lua)
	db.listItems = db.listItems or {} -- what Craft Profit put on each shopping list (see Shopping.lua)
	db.bestHidden = db.bestHidden or {} -- kinds of item the Best crafts list hides: group key -> true
	db.bestIgnored = db.bestIgnored or {} -- recipes the Best crafts list hides: recipeID -> true
	db.bestPinned = db.bestPinned or {} -- recipes at the top of the Best crafts list: recipeID -> true
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
		if isInitialLogin then
			ns.db.session = { total = 0, crafts = 0 }
			ns.db.tsmOrders = {}
		end
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		return
	end

	local name = ...
	if name == ADDON_NAME then
		ns.db = loadSettings()
		ns.Ranks.Init()
		ns.Sales.Init()
		ns.Procs.Init()
		ns.Minimap.Init()
		ns.Options.Create()
	end
	-- The profession window loads on demand; attach to it when it appears.
	if name == "Blizzard_Professions" or (name == ADDON_NAME and C_AddOns.IsAddOnLoaded("Blizzard_Professions")) then
		ns.Panel.Init()
		ns.Patron.Init()
		ns.Best.Init()
		ns.Craft.Init()
		ns.BestCraftsList.Init()
	end
	if ns.Panel.Frame() then self:UnregisterEvent("ADDON_LOADED") end
end)

SLASH_CRAFTPROFIT1 = "/craftprofit"
SlashCmdList.CRAFTPROFIT = function(msg)
	-- Testing: /craftprofit testquality <rank> (or "off") pretends every patron
	-- order needs at least that rank, to see orders you can't reach.
	local command, value = (msg or ""):lower():match("^%s*(%S+)%s*(%S*)")
	if command == "testquality" then
		local rank = tonumber(value)
		ns.Planner.SetTestMinQuality(rank)
		ns.Shopping.Say(rank and string.format("Testing: every patron order now needs at least rank %d. /reload or /craftprofit testquality off to stop.", rank)
			or "Testing off: patron orders use their real minimum quality.")
		return
	end
	if command == "testconcentration" then
		-- Testing: pretend you have this much concentration.
		local amount = tonumber(value)
		ns.Planner.testConcentration = amount
		ns.Shopping.Say(amount and string.format("Testing: pretending you have %d concentration. /reload or /craftprofit testconcentration off to stop.", amount)
			or "Testing off: your real concentration is used.")
		return
	end
	if command == "testproc" then
		-- Testing: shows the proc animation without crafting.
		local where = ns.Results.TestProc()
		ns.Shopping.Say(where and string.format("Testing: a made-up resourcefulness proc on the %s.",
			where == "list" and "Patron tab" or "panel")
			or "Testing: open your profession window (or its Patron tab) first.")
		return
	end
	if command == "testprocs" then
		-- Testing: the open recipe's multicraft and resourcefulness, as the game sends them.
		if not ns.Procs.Explain() then ns.Shopping.Say("Testing: pick a recipe on the crafting page first.") end
		return
	end
	if command == "testnotice" then
		-- Testing: the Best crafts list's old prices notice, now.
		if not ns.BestCraftsList.TestNotice() then ns.Shopping.Say("Testing: open the Best crafts list first.") end
		return
	end
	if command == "minimap" then
		ns.Options.Set("minimap", not ns.db.minimap)
		ns.Shopping.Say(ns.db.minimap and "Minimap button shown." or "Minimap button hidden. /craftprofit minimap shows it again.")
		return
	end
	if command == "best" then
		if not ns.BestCraftsList.Show() then
			ns.Shopping.Say("Open your profession window on its recipes first.")
		end
		return
	end
	if command == "testrank" then
		-- Testing: the open order next to Craft Rank's numbers for its recipe.
		if not ns.Ranks.Explain() then ns.Shopping.Say("Testing: open a crafting order first.") end
		return
	end
	ns.Options.Open()
end
