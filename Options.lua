-- Craft Profit: the options window (Esc > Options > AddOns > Craft Profit).
local _, ns = ...

local Options = {}
ns.Options = Options

local format = string.format
local category

function Options.Open()
	if category then Settings.OpenToCategory(category:GetID()) end
end

-- Any change re-places and redraws the panel. Prices and the concentration
-- choice change the patron orders' picks too.
local function onChanged()
	ns.Planner.Reset()
	ns.Panel.Place()
	ns.Panel.Refresh()
end

function Options.Create()
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory("Craft Profit")
	local db = ns.db

	local function setting(key, varType, name)
		local s = Settings.RegisterAddOnSetting(category, "CRAFTPROFIT_" .. key:upper(), key, db, varType, name, ns.DEFAULTS[key])
		s:SetValueChangedCallback(onChanged)
		return s
	end

	local function checkbox(key, name, tooltip)
		Settings.CreateCheckbox(category, setting(key, Settings.VarType.Boolean, name), tooltip)
	end

	local function dropdown(key, name, choices, tooltip)
		local function getOptions()
			local container = Settings.CreateControlTextContainer()
			for _, choice in ipairs(choices) do container:Add(choice[1], choice[2]) end
			return container:GetData()
		end
		Settings.CreateDropdown(category, setting(key, Settings.VarType.String, name), getOptions, tooltip)
	end

	local function button(name, text, onClick, tooltip)
		layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
	end

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Display"))
	checkbox("crafting", "Show on the crafting page",
		"Profit for the recipe you have selected: sale price minus materials.")
	checkbox("orders", "Show on crafting orders",
		"Profit for the order you have open: commission minus the materials you supply.")
	checkbox("locked", "Lock panel position", "Stop the panel from being dragged.")

	local scaleOptions = Settings.CreateSliderOptions(0.6, 1.5, 0.05)
	scaleOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return format("%d%%", value * 100 + 0.5)
	end)
	Settings.CreateSlider(category, setting("scale", Settings.VarType.Number, "Panel size"), scaleOptions)

	checkbox("procFx", "Animate multicraft & resourcefulness procs",
		"When a craft procs, the bonus gold pops up over the Profit line and the panel flashes gold.")
	checkbox("procSound", "Coin sound on procs",
		"Play a coin sound when a craft procs multicraft or resourcefulness.")

	checkbox("showSession", "Show this session's total",
		"Adds up what every craft made since you logged in on this character. A /reload keeps it.")
	button("Session total", "Reset", ns.Results.ResetSession, "Start the session total from zero.")

	dropdown("precision", "Show amounts down to", {
		{ "gold", "Gold (2,904g)" },
		{ "silver", "Silver (2,903g 83s)" },
		{ "copper", "Copper (2,903g 83s 45c)" },
	}, "Rounds every amount to this coin. Amounts smaller than one coin still show the next coin down.")

	button("Panel position", "Reset", function()
		db.pos = nil
		ns.Panel.Place()
	end, "Put the panel back next to the profession window.")

	checkbox("shoppingButton", "Show the Shopping list button",
		format("A row under Materials cost for buying what you're short of, and the Shopping list button " ..
		"on the Patron orders tab.\n\n" ..
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

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Patron orders"))
	dropdown("concentrationFor", "Spend concentration on", ns.CONCENTRATION_CHOICES,
		"In the Patron orders list, orders that only reach their minimum quality with concentration share what " ..
		"you have. They get it in this order until it runs out; the rest say \"not enough concentration\".\n\n" ..
		"Most profit: the most gold per concentration point first.\n\n" ..
		"Knowledge first: orders that reward profession knowledge first, then the rest by profit.\n\n" ..
		"You can also switch it at the bottom of the Patron orders list.")
	checkbox("leastConcentration", ns.LEAST_CONCENTRATION, ns.LEAST_CONCENTRATION_TIP ..
		"\n\nAlso picks the materials for Use Most Profitable Reagents on the order form and the crafting page. " ..
		"You can also switch it at the bottom of the Patron orders list.")

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Tooltips"))
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

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Prices"))
	dropdown("provider", "Price addon", {
		{ "auto", "Automatic (TSM, then Auctionator)" },
		{ "tsm", "TradeSkillMaster only" },
		{ "auctionator", "Auctionator only" },
	}, "Where prices come from. Automatic uses TSM and falls back to Auctionator for items TSM has no price for.")
	dropdown("matSource", "TSM price for materials", ns.TSM_SOURCES,
		"What you'd pay for materials. Market value smooths out spikes; lowest auction is what you'd pay right now.")
	dropdown("saleSource", "TSM price for crafted items", ns.TSM_SOURCES,
		"What you'd get for the item you craft.")
	checkbox("useVendor", "Use vendor price for vendor items",
		"Materials a vendor sells (vials, thread...) are priced at the vendor instead of the auction house.")
	checkbox("ahCut", format("Subtract auction house cut (%d%%)", ns.AH_CUT * 100),
		"The auction house keeps 5% of every sale.")

	Settings.RegisterAddOnCategory(category)
end
