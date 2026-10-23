-- Craft Profit: the options window (Esc > Options > AddOns > Craft Profit). The
-- main page has what to craft and where prices come from; the rest sit on pages
-- under its "+": Panel, Shopping list, Patron orders and Tooltips.
local _, ns = ...

local Options = {}
ns.Options = Options

local format = string.format
local category
local settings = {} -- key -> the Settings object, for changes made outside the options

function Options.Open()
	if category then Settings.OpenToCategory(category:GetID()) end
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

-- Changes a setting from elsewhere (the Best crafts list), as the options would.
function Options.Set(key, value)
	if settings[key] then settings[key]:SetValue(value) else ns.db[key] = value; onChanged() end
end

function Options.Create()
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory("Craft Profit")
	local db = ns.db
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
		s:SetValueChangedCallback(onChanged)
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
	local strategyTip = "Which rank, and which materials, to craft on the crafting page:\n\n"
	for _, strategy in ipairs(ns.STRATEGIES) do
		strategyChoices[#strategyChoices + 1] = { strategy[1], strategy[2] }
		strategyTip = strategyTip .. strategy[2] .. ": " .. strategy[4] .. "\n\n"
	end
	dropdown("craftStrategy", "Crafting strategy", strategyChoices, strategyTip ..
		"It picks the materials for Use Craft Profit Reagents and the panel's blue row, prices missing materials, " ..
		"decides what the shopping list buys, and ranks the Best crafts list. Patron orders keep their own rule: the " ..
		"cheapest materials that reach the order's minimum quality.\n\nAlso at the bottom of the Best crafts list.")
	checkbox("countProcs", "Count multicraft and resourcefulness",
		"The Best crafts list ranks recipes by what they make on average with procs, and the Most profit strategy " ..
		"picks ranks that way. Your chances come from the game; how big a proc is, from your own crafts.\n\n" ..
		"The panel always shows both: the expected profit, and Without procs under it.\n\n" ..
		"Also in the Best crafts list's Filter menu.")

	header("Minimap button")
	checkbox("minimap", "Show minimap button",
		"Click: your profession window, on the Best crafts list of the profession you opened last. Right-click: a " ..
		"menu with your professions, the crafting strategy and these options. Hover: this session's total.\n\n" ..
		"Also in the minimap's addon menu, and /craftprofit minimap shows or hides it.")

	header("Prices")
	dropdown("provider", "Price addon", {
		{ "auto", "Automatic (TSM, then Auctionator)" },
		{ "tsm", "TradeSkillMaster only" },
		{ "auctionator", "Auctionator only" },
	}, "Where prices come from. Automatic uses TSM and falls back to Auctionator for items TSM has no price for.")
	dropdown("matSource", "TSM price for materials", ns.TSM_SOURCES,
		"What you'd pay for materials. Market value smooths out spikes; lowest auction is what you'd pay right now.")
	dropdown("saleSource", "TSM price for crafted items", ns.TSM_SOURCES,
		"What you'd get for the item you craft.")
	checkbox("scanReminder", "Remind me to scan the auction house",
		"With prices from Auctionator: when its last scan is over a day old, a chat line reminds you when you open " ..
		"the auction house, and when it's over 3 days old, a notice over the Best crafts list when you open it (once a " ..
		"session). The panel's and the list's footers always say how old the scan is, in red once it's a day old.")
	checkbox("useVendor", "Use vendor price for vendor items",
		"Materials a vendor sells (vials, thread...) are priced at the vendor instead of the auction house.")
	checkbox("ahCut", format("Subtract auction house cut (%d%%)", ns.AH_CUT * 100),
		"The auction house keeps 5% of every sale.")

	---------------------------------------------------------------------------
	-- Panel
	---------------------------------------------------------------------------

	startPage("Panel")
	header("Where it shows")
	checkbox("crafting", "Show on the crafting page",
		"Profit for the recipe you have selected: sale price minus materials.")
	checkbox("orders", "Show on crafting orders",
		"Profit for the order you have open: commission minus the materials you supply.")

	header("Look")
	local scaleOptions = Settings.CreateSliderOptions(0.6, 1.5, 0.05)
	scaleOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return format("%d%%", value * 100 + 0.5)
	end)
	Settings.CreateSlider(page, setting("scale", Settings.VarType.Number, "Panel size"), scaleOptions)
	dropdown("precision", "Show amounts down to", {
		{ "gold", "Gold (2,904g)" },
		{ "silver", "Silver (2,903g 83s)" },
		{ "copper", "Copper (2,903g 83s 45c)" },
	}, "Rounds every amount to this coin. Amounts smaller than one coin still show the next coin down.")
	checkbox("locked", "Lock panel position", "Stop the panel from being dragged.")
	button("Panel position", "Reset", function()
		db.pos = nil
		ns.Panel.Place()
	end, "Put the panel back next to the profession window.")

	header("Procs and session total")
	checkbox("procFx", "Animate multicraft & resourcefulness procs",
		"When a craft procs, the bonus gold pops up over the Profit line and the panel flashes gold.")
	checkbox("procSound", "Coin sound on procs",
		"Play a coin sound when a craft procs multicraft or resourcefulness.")
	checkbox("showSession", "Show this session's total",
		"Adds up what every craft made since you logged in on this character. A /reload keeps it. Shown on the " ..
		"panel and at the bottom of the Patron tab's order list.")
	button("Session total", "Reset", ns.Results.ResetSession, "Start the session total from zero.")

	---------------------------------------------------------------------------
	-- Shopping list
	---------------------------------------------------------------------------

	startPage("Shopping list")
	checkbox("shoppingButton", "Show the Shopping list button",
		format("A row under Materials cost for buying what you're short of, and the shopping buttons on the " ..
		"Patron tab: Add profitable, Add all and each order's cart button.\n\n" ..
		"Auctionator: a click opens a menu that adds what's missing for 1, 5, 10 or any number of crafts " ..
		"to an Auctionator shopping list.\n\n" ..
		"TSM: the same menu gives you a search to copy into TSM's Shopping tab, for exactly the ranks " ..
		"and amounts you're missing.\n\n" ..
		"With neither Auctionator nor TSM installed, it's hidden."))
	dropdown("listAddon", "Shop with", ns.LIST_ADDON_CHOICES,
		"When Auctionator and TSM are both installed: add missing materials to Auctionator's shopping list, " ..
		"or get a TSM search to copy. With only one of them, that one is used.\n\n" ..
		"You can also switch it at the bottom of the Shopping list menus.")
	checkbox("listPerCharacter", "One shopping list per character",
		format("Each character gets its own Auctionator list, named after it, like \"%s\".\n\n" ..
			"Can be combined with one list per profession: \"%s - Blacksmithing\".",
			UnitName("player") or "Name", UnitName("player") or "Name"))
	checkbox("listPerProfession", "One shopping list per profession",
		format("Each profession gets its own Auctionator list, like \"Blacksmithing\".\n\n" ..
			"Can be combined with one list per character. With neither, the list is \"%s\".", ns.SHOPPING_LIST))
	checkbox("checkOff", "Check off what you get",
		"Materials come off the Auctionator shopping list as you get them: bought, looted, from the mailbox " ..
		"or crafted. Chat says what came off, and when the list is done.\n\n" ..
		"Only what Craft Profit put on the list. Moving things between your bags and banks doesn't count.")
	button("Auctionator shopping list", "Clear", ns.Shopping.Clear,
		"Empties the shopping list. Ctrl-click the Shopping list button does the same.\n\n" ..
		"With one list per profession, this clears the list of the profession window that's open, " ..
		"or with none open, the lists of all this character's professions.")

	---------------------------------------------------------------------------
	-- Patron orders
	---------------------------------------------------------------------------

	startPage("Patron orders")
	checkbox("patronList", "Show Craft Profit on the Patron tab",
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

	---------------------------------------------------------------------------
	-- Tooltips
	---------------------------------------------------------------------------

	startPage("Tooltips")
	checkbox("rankTooltip", "Show the best rank you can craft",
		"On the tooltip of an item you can craft: the highest rank you can make it at with top-quality materials, " ..
		"using concentration if that reaches a higher rank.\n\n" ..
		"Updates each time you open your profession window.")
	dropdown("rankCharacters", "Show it for", {
		{ "all", "All your characters" },
		{ "current", "This character only" },
	}, "All your characters: one line for each character that knows the recipe, best rank first.\n\n" ..
		"A character shows up once you've opened its profession window, on any version of Craft Profit since 1.7.")
	checkbox("rankConcentration", "Show the concentration it takes",
		"When the best rank needs concentration, add how much.")
	button("Saved characters", "Forget...", ns.Ranks.OpenForgetMenu,
		"Pick a character you deleted, renamed or moved, so its Craft Rank no longer shows on tooltips.\n\n" ..
		"A character you still play comes back once you open its profession window again.")

	Settings.RegisterAddOnCategory(category)
end
