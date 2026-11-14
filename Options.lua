-- Craft Profit: the options window (Esc > Options > AddOns > Craft Profit). The
-- main page has what to craft and where prices come from; the rest sit on pages
-- under its "+": Panel, Shopping list, Patron orders and Tooltips. WoW Forever
-- has no ranks, procs, concentration or crafting orders, so the options for
-- those (and the Patron orders page) aren't there.
local _, ns = ...

local Options = {}
ns.Options = Options

local format = string.format
local category
local settings = {} -- key -> the Settings object, for changes made outside the options

-- The game doesn't let addons open its settings during combat, so a request then waits for the fight to end.
local openAfterCombat = false
local combatWatch = CreateFrame("Frame")
combatWatch:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	openAfterCombat = false
	Options.Open()
end)

function Options.Open()
	if not category then return end
	if InCombatLockdown() then
		if not openAfterCombat then
			openAfterCombat = true
			combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
			print("|cffffd100Craft Profit:|r the options open when you leave combat.")
		end
		return
	end
	Settings.OpenToCategory(category:GetID())
end

-- Any change re-places and redraws the panel. Prices and the concentration
-- choice change the patron orders' picks too.
local function onChanged()
	ns.Planner.Reset()
	ns.Panel.Place()
	ns.Panel.Refresh()
	ns.Patron.Redraw()
	ns.BestCrafts.Reprice(true)
	ns.BestCraftsList.Refresh()
	ns.Minimap.Update()
end

-- Settings that change which TSM prices are saved for your alts: a change saves them again.
local RESAVE = { saveTSMPrices = true, saveItems = true, provider = true, matSource = true, saleSource = true }

-- Changes a setting from elsewhere (the Best crafts list), as the options would.
function Options.Set(key, value)
	if settings[key] then settings[key]:SetValue(value) else ns.db[key] = value; onChanged() end
end

function Options.Create()
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory("Craft Profit")
	local db = ns.db
	local quality = ns.QUALITY_CRAFTING -- false on WoW Forever
	-- The page settings go on: the main page, then each page under its "+".
	local page, pageLayout = category, layout

	local function startPage(name)
		page, pageLayout = Settings.RegisterVerticalLayoutSubcategory(category, name)
	end

	local function header(name)
		pageLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
	end

	local function setting(key, varType, name)
		local s = Settings.RegisterAddOnSetting(page, "CRAFTPROFIT_" .. key:upper(), key, db, varType, name, ns.DEFAULTS[key])
		s:SetValueChangedCallback(function(...)
			onChanged(...)
			if key == "saveTSMPrices" and not db.saveTSMPrices then
				ns.SavedPrices.Forget()
			elseif RESAVE[key] then
				ns.SavedPrices.Save(true)
			end
		end)
		settings[key] = s
		return s
	end

	local function checkbox(key, name, tooltip)
		Settings.CreateCheckbox(page, setting(key, Settings.VarType.Boolean, name), tooltip)
	end

	local function dropdown(key, name, choices, tooltip)
		local function getOptions()
			local container = Settings.CreateControlTextContainer()
			for _, choice in ipairs(choices) do container:Add(choice[1], choice[2]) end
			return container:GetData()
		end
		Settings.CreateDropdown(page, setting(key, Settings.VarType.String, name), getOptions, tooltip)
	end

	local function button(name, text, onClick, tooltip)
		pageLayout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
	end

	---------------------------------------------------------------------------
	-- The main page: what to craft and where prices come from
	---------------------------------------------------------------------------

	header("Crafting")
	local strategyChoices = {}
	local strategyTip = quality and "Which rank, and which materials, to craft on the crafting page:\n\n"
		or "Where the materials you're missing come from:\n\n"
	for _, strategy in ipairs(ns.STRATEGIES) do
		strategyChoices[#strategyChoices + 1] = { strategy[1], strategy[2] }
		strategyTip = strategyTip .. strategy[2] .. ": " .. strategy[4] .. "\n\n"
	end
	dropdown("craftStrategy", "Crafting strategy", strategyChoices, strategyTip .. (quality and
		"It picks the materials for Use Craft Profit Reagents and the panel's blue row, prices missing materials, " ..
		"decides what the shopping list buys, and ranks the Best crafts list. Patron orders keep their own rule: the " ..
		"cheapest materials that reach the order's minimum quality." or
		"It prices your materials, decides what the shopping list buys, and ranks the Best crafts list.") ..
		"\n\nAlso on the panel when a recipe is open, and at the bottom of the Best crafts list.")
	-- Procs only exist with Dragonflight's crafting.
	if quality then
		checkbox("countProcs", "Count procs in profits",
			"The Best crafts list ranks recipes by what they make on average with procs. The Patron tab shows and sorts orders by what they make on average with " ..
			"resourcefulness, the customer's materials included (the customer gets the item, so multicraft doesn't " ..
			"count). Your chances come from the " ..
			"game; how big a proc is, from your own crafts.\n\n" ..
			"The panel always shows both: the expected profit, and Without procs under it.\n\n" ..
			"Also in the Best crafts list's Filter menu.")
	end

	header("Minimap button")
	checkbox("minimap", "Show minimap button",
		"Click: your profession window, on the Best crafts list of the profession you opened last. Right-click: a " ..
		"menu with your professions, the Ledger, the crafting strategy and these options. Hover: this session's total.\n\n" ..
		"Also in the minimap's addon menu, and /craftprofit minimap shows or hides it.")

	header("Prices")
	dropdown("provider", "Price addon", {
		{ "auto", "Automatic (TSM first)" },
		{ "tsm", "TradeSkillMaster only" },
		{ "auctionator", "Auctionator only" },
		{ "own", "Craft Profit's scan only" },
	}, "Where prices come from. Automatic uses TSM, falls back to Auctionator for items TSM has no price for, " ..
		"and to Craft Profit's own scan of the auction house for what neither prices. With neither installed, " ..
		"Craft Profit's scan prices everything.\n\n" ..
		"The scan runs from the Prices tab of Craft Profit's window at the auction house (/craftprofit prices).")
	checkbox("autoScan", "Scan when I open the auction house",
		"Craft Profit's own price scan starts by itself when you open the auction house.\n\n" ..
		"Only while your prices come from that scan (not from TSM or Auctionator), and at most once an hour. " ..
		"Chat says when it starts and when it's done.\n\n" ..
		"Off: you start it with Scan now on the Prices tab, or /craftprofit scan.")
	dropdown("matSource", "TSM price for materials", ns.TSM_SOURCES,
		"What you'd pay for materials. Market value smooths out spikes; lowest auction is what you'd pay right now. " ..
		"The lower of the two can show materials cheaper than you can buy them right now.")
	dropdown("saleSource", "TSM price for crafted items", ns.TSM_SOURCES,
		"What you'd get for the item you craft. The lower of market value and the lowest auction is the careful " ..
		"choice: you'd have to match a cheaper auction to sell now, and high listings that aren't selling don't count.")
	checkbox("scanReminder", "Remind me of old prices",
		"With prices from Auctionator or Craft Profit's scan: when the last scan is over a day old, a chat line reminds you when you open " ..
		"the auction house, and when it's over 3 days old, a notice over the Best crafts list when you open it (once a " ..
		"session). The panel's and the list's footers always say how old the scan is, in red once it's a day old.\n\n" ..
		"With TSM prices saved by another character: the same reminders, to log in on a character with TSM.")
	checkbox("vendorOnAH", "Buy vendor items on the auction house",
		"Materials a vendor sells (thread, flux, vials...) are priced at their auction house price and go on the " ..
		"shopping list.\n\nOff: they're priced at the vendor, and the shopping list says in chat to buy them there.\n\n" ..
		"When the auction house asks more than a vendor, the tooltips of what's missing say so, and so does chat " ..
		"when the shopping list gets it.")
	checkbox("ahCut", format("Subtract auction house cut (%d%%)", ns.AH_CUT * 100),
		"The auction house keeps 5% of every sale.")

	header("TSM prices for alts")
	checkbox("saveTSMPrices", "Save TSM prices for alts",
		"Each time a character with TSM logs in, its prices are kept for your characters that don't load TSM. " ..
		"Turn TSM off on your crafting alts, and they still get TSM prices. The bottom of the panel says whose " ..
		"prices they are and how old.\n\n" ..
		"Gear prices only count on the realm they were saved on and its connected realms; other prices count " ..
		"on every realm. Prices over 2 weeks old aren't used.\n\n" ..
		"Turning it off deletes the saved prices, for all your characters.")
	local saveTip = "Which items' prices are saved:\n\n"
	for _, choice in ipairs(ns.SAVE_ITEMS_CHOICES) do
		saveTip = saveTip .. choice[2] .. ": " .. choice[3] .. "\n\n"
	end
	dropdown("saveItems", "Save prices for", ns.SAVE_ITEMS_CHOICES, saveTip ..
		"Items an alt has no price for get one the next time a character with TSM logs in.")

	---------------------------------------------------------------------------
	-- Panel
	---------------------------------------------------------------------------

	startPage("Panel")
	header("Where it shows")
	checkbox("crafting", "Show on the crafting page",
		"Profit for the recipe you have selected: sale price minus materials.")
	if quality then
		checkbox("orders", "Show on crafting orders",
			"Profit for the order you have open: commission minus the materials you supply.")
	end

	header("Look")
	local scaleOptions = Settings.CreateSliderOptions(0.6, 1.5, 0.05)
	scaleOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return format("%d%%", value * 100 + 0.5)
	end)
	Settings.CreateSlider(page, setting("scale", Settings.VarType.Number, "Panel size"), scaleOptions)
	-- WoW Forever always shows the two biggest coins (see Format.Money).
	if quality then
		dropdown("precision", "Show amounts down to", {
			{ "gold", "Gold (2,904g)" },
			{ "silver", "Silver (2,903g 83s)" },
			{ "copper", "Copper (2,903g 83s 45c)" },
		}, "Rounds every amount to this coin. Amounts smaller than one coin still show the next coin down.")
	end
	checkbox("locked", "Lock panel position", "Stop the panel from being dragged.")
	button("Panel position", "Reset", function()
		db.pos = nil
		ns.Panel.Place()
	end, "Put the panel back next to the profession window.")

	if quality then
		header("Procs and session total")
		checkbox("procFx", "Animate procs",
			"When a craft procs, the bonus gold pops up over the Profit line and the panel flashes gold.")
		checkbox("procSound", "Coin sound on procs",
			"Play a coin sound when a craft procs multicraft or resourcefulness.")
	else
		header("Session total")
	end
	checkbox("showSession", "Show this session's total",
		"Adds up what every craft made since you logged in on this character. A /reload keeps it. Shown on the " ..
		(quality and "panel and at the bottom of the Patron tab's order list." or "panel."))
	button("Session total", "Reset", ns.Results.ResetSession, "Start the session total from zero.")

	---------------------------------------------------------------------------
	-- Shopping list
	---------------------------------------------------------------------------

	startPage("Shopping list")
	checkbox("shoppingButton", "Show Shopping list button",
		"A button under your materials for buying what you're short of" ..
		(quality and ", and the shopping buttons on the Patron tab: Add profitable, Add all and each order's cart "
			.. "button.\n\n" or ".\n\n") ..
		"Auctionator: a click opens a menu that adds what's missing for 1, 5, 10 or any number of crafts " ..
		"to an Auctionator shopping list.\n\n" ..
		"TSM: the same menu gives you a search to copy into TSM's Shopping tab, for exactly the " ..
		(quality and "ranks and " or "") .. "amounts you're missing.\n\n" ..
		"Craft Profit's own list: the same menu adds them to a list of its own. Its window opens beside the " ..
		"auction house, where a click on a material shows it with the amount you still need. " ..
		"It's used when neither Auctionator nor TSM is installed.")
	dropdown("listAddon", "Shop with", ns.LIST_ADDON_CHOICES,
		"Where missing materials go: Auctionator's shopping list, a TSM search to copy, or Craft Profit's " ..
		"own shopping list.\n\n" ..
		"A choice whose addon isn't installed uses the one that is, and with neither, Craft Profit's own list.\n\n" ..
		"You can also switch it at the bottom of the Shopping list menus.")
	checkbox("listPerCharacter", "One list per character",
		format("Each character gets its own list, named after it, like \"%s\".\n\n" ..
			"Can be combined with one list per profession: \"%s - Blacksmithing\".",
			UnitName("player") or "Name", UnitName("player") or "Name"))
	checkbox("listPerProfession", "One list per profession",
		format("Each profession gets its own list, like \"Blacksmithing\".\n\n" ..
			"Can be combined with one list per character. With neither, the list is \"%s\".", ns.SHOPPING_LIST))
	checkbox("checkOff", "Check off what you get",
		"Materials come off the shopping list, Auctionator's or Craft Profit's own, as you get them: bought, " ..
		"looted, from the mailbox or crafted. Chat says what came off, and when the list is done.\n\n" ..
		"Only what Craft Profit put on the list. Moving things between your bags and banks doesn't count.")
	button("Shopping list", "Clear", function() ns.Shopping.Clear() end,
		"Empties the shopping list. Ctrl-click the Shopping list button does the same.\n\n" ..
		"With one list per profession, this clears the list of the profession window that's open, " ..
		"or with none open, the lists of all this character's professions.")
	header("Auction house window")
	checkbox("auctionWindow", "Open at the auction house",
		"Craft Profit's own window opens beside the auction house. It has four tabs:\n\n" ..
		"Shopping list: what you still have to buy. A click on a material shows it at the auction house.\n\n" ..
		"Sell: what's in your bags that can be auctioned, with what each is listed for. Set the price, the " ..
		"amount and how long it lasts, and post it. The game's own sell page is filled in with the same " ..
		"auction, and a price, amount or duration you change there is changed here too.\n\n" ..
		"My auctions: your auctions, which of them are undercut, and a button that cancels those. The " ..
		"game's own Auctions tab opens beside it.\n\n" ..
		"Prices: when the auction house was last scanned for prices, and the button that scans it.\n\n" ..
		"It opens by itself when Craft Profit's shopping list has something on it, or when Auctionator " ..
		"isn't installed.\n\n" ..
		"Off: it only opens from the button below, the Shopping list menus, or /craftprofit shop, sell, " ..
		"auctions and prices.")
	button("Craft Profit's window", "Show", function() ns.ShoppingList.Show(ns.db.auctionTab) end,
		"Opens the window on the tab you last used. /craftprofit shop, sell, auctions and prices each open " ..
		"it on their own tab. Selling, your auctions and scanning need the auction house open.")

	---------------------------------------------------------------------------
	-- Patron orders
	---------------------------------------------------------------------------

	if quality then
		startPage("Patron orders")
		-- Every crafting order's own choices, separate from the crafting strategy.
		header("Crafting orders")
		for _, setting in ipairs({
			{ "patronMaterials", ns.PATRON_MATERIALS_TITLE, ns.PATRON_MATERIALS_CHOICES,
				"Which material qualities crafting orders use (patron, public, guild and personal), for their profit, " ..
				"Ready and what's missing, the shopping list and the Patron tab's craft button. The crafting page " ..
				"keeps the crafting strategy." },
			{ "patronReach", ns.PATRON_REACH_TITLE, ns.PATRON_REACH_CHOICES,
				"How an order with a minimum quality gets there, when both better materials and concentration would." },
		}) do
			local tip = setting[4] .. "\n\n"
			for _, choice in ipairs(setting[3]) do tip = tip .. choice[2] .. ": " .. choice[3] .. "\n\n" end
			dropdown(setting[1], setting[2], setting[3], tip .. "Also on the panel of an open order, and under the " ..
				"Patron tab's list.")
		end
		header("Patron tab")
		checkbox("patronList", "Show on the Patron tab",
			"The Patron tab's order list shows each order's profit or loss, its rewards and what materials you're " ..
			"missing, with buttons to shop for it and to start, craft and complete it. Buttons above the list shop for the profitable " ..
			"orders or all of them; under it, the concentration they use and the session total.\n\n" ..
			"Off: Blizzard's own columns (Patron Name, Commission, Reagents).")
		dropdown("concentrationFor", "Spend concentration on", ns.CONCENTRATION_CHOICES,
			"On the Patron tab, orders that only reach their minimum quality with concentration share what " ..
			"you have. They get it in this order until it runs out; the rest show their profit in grey and \"No concentration\".\n\n" ..
			"Most profit: the most gold per concentration point first.\n\n" ..
			"Knowledge first: orders that reward profession knowledge first, then the rest by profit.\n\n" ..
			"Don't use concentration: patron orders never spend it. Orders that need it to reach their minimum " ..
			"quality show \"No concentration\", get no cart or craft button, and Add profitable and Add all skip them; " ..
			"on their order form, Use Craft Profit Reagents leaves the materials alone. The crafting page isn't affected.\n\n" ..
			"You can also switch it with the gear at the bottom of the Patron tab.")
		checkbox("leastConcentration", ns.LEAST_CONCENTRATION, ns.LEAST_CONCENTRATION_TIP ..
			"\n\nAlso picks the materials for Use Craft Profit Reagents on the order form and the crafting page. " ..
			"Patron orders don't use concentration while Spend concentration on is set to Don't use concentration. " ..
			"You can also switch it with the gear at the bottom of the Patron tab.")
		checkbox("nextLosing", ns.NEXT_LOSING, ns.NEXT_LOSING_TIP ..
			"\n\nYou can also switch it with the gear at the bottom of the Patron tab.")
	end

	---------------------------------------------------------------------------
	-- Tooltips
	---------------------------------------------------------------------------

	startPage("Tooltips")
	if quality then
		checkbox("rankTooltip", "Show your best rank",
			"On the tooltip of an item you can craft: the highest rank you can make it at with top-quality materials, " ..
			"using concentration if that reaches a higher rank.\n\n" ..
			"Updates each time you open your profession window.")
		dropdown("rankCharacters", "Show it for", {
			{ "all", "All your characters" },
			{ "current", "This character only" },
		}, "All your characters: one line for each character that knows the recipe, best rank first.\n\n" ..
			"A character shows up once you've opened its profession window, on any version of Craft Profit since 1.7.")
		checkbox("rankConcentration", "Show its concentration",
			"When the best rank needs concentration, add how much.")
		button("Saved characters", "Forget...", ns.Ranks.OpenForgetMenu,
			"Pick a character you deleted, renamed or moved, so its Craft Rank no longer shows on tooltips.\n\n" ..
			"A character you still play comes back once you open its profession window again.")
	end
	checkbox("tipVendorBuy", "Show vendor buy price",
		"On item tooltips: Vendor Buy, what a vendor charges for one. Only for items a vendor sells, once your " ..
		"price addon has seen one sell it" .. (quality and "." or " (common crafting reagents are always known)."))
	checkbox("tipVendorSell", "Show vendor sell price",
		"On item tooltips: Vendor Sell, what a vendor pays you for one.")
	checkbox("tipAuction", "Show auction price",
		"On item tooltips: what the item sells for on the auction house, with the price you picked (the TSM " ..
		"price for crafted items on the main page, or Auctionator's). For a stack in your bags, also what the " ..
		"whole stack sells for.\n\nNot on items you can't post, like soulbound ones.")
	checkbox("tipDeposit", "Show AH deposit",
		"On item tooltips: the auction house deposit for posting the item for " ..
		(quality and "12, 24 or 48" or "2, 8 or 24") .. " hours, for the whole " ..
		"stack when it's in your bags. You get it back when the item sells and lose it when it doesn't, so a " ..
		"deposit near the price means it's hardly worth posting.\n\nNot on items you can't post, like soulbound ones.")
	checkbox("tipSaleRate", "Show sale rate",
		"On item tooltips, with TSM: TSM Sale Rate, the share of the item's auctions that sell" ..
		(quality and ", across your region." or ". On WoW Forever your region is one server, so it's your own market.") ..
		" A high rate means it sells; a low one that most auctions expire.\n\nNot on items you can't post, like soulbound ones.")
	checkbox("priceTooltip", "Show saved TSM prices",
		"On characters without TSM that use TSM prices saved by another character (see Save TSM prices for alts, " ..
		"on the main page): one line with the item's price, as Craft Profit prices it, and whose " ..
		"prices they are and how old.\n\nOnly items in those saved prices show it.")

	Settings.RegisterAddOnCategory(category)
end
