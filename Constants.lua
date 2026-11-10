-- Craft Profit: values shared by every file. Change them here, not inline.
local _, ns = ...

-- The auction house keeps 5% of every sale.
ns.AH_CUT = 0.05

-- Whether this game has Dragonflight's crafting: material and item qualities
-- (ranks), multicraft, resourcefulness and concentration. Retail does; WoW
-- Forever (game version 1.x) doesn't, so the crafting strategy and procs stay
-- out of sight there.
ns.QUALITY_CRAFTING = select(4, GetBuildInfo()) >= 100000

-- Panel layout, in pixels before the panel's own scale.
ns.Layout = {
	WIDTH = 380,
	LINE_HEIGHT = 19,                  -- smallest row height
	PAD_TOP = 10,                      -- panel edge to the first row
	PAD_BOTTOM = 10,
	PAD_SIDE = 12,                     -- panel edge to the text
	GAP = 6,                           -- extra space that sets a row apart
	DIVIDER_GAP = 3,                   -- space above and below a divider line
	GEAR_SPACE = 22,                   -- room kept for the options button on the first row
	ICON_SIZE = 18,                    -- item, currency and quality icons in the text
	DEFAULT_POS = { x = 36, y = -60 }, -- from the profession window's top-right corner
}

-- Text colors, as |c codes (alpha + RGB).
ns.Colors = {
	muted = "ff888888",     -- secondary text and notes
	profit = "ff33ff33",
	loss = "ffff4444",
	warning = "ffff6666",   -- "no price" and similar problems
	simulated = "ff66ccff", -- what-if qualities
	heading = "ffffd100",   -- the game's gold
	missing = "ffffaa33",
	good = "ff88ff88",
}

function ns.Color(key, text)
	return "|c" .. ns.Colors[key] .. text .. "|r"
end

-- "profit" for zero or more, "loss" below zero.
function ns.AmountColor(amount)
	return amount >= 0 and "profit" or "loss"
end

-- Saved settings and their defaults.
ns.DEFAULTS = {
	crafting = true,      -- show on the normal crafting page
	orders = true,        -- show on crafting orders
	locked = false,
	scale = 1,
	precision = "silver", -- smallest coin shown: "copper" | "silver" | "gold"
	provider = "auto",    -- "auto" | "tsm" | "auctionator"
	matSource = "dbmarket",
	saleSource = "dbmarket",
	vendorOnAH = false,   -- materials vendors sell are bought on the auction house, not at a vendor
	saveTSMPrices = false, -- characters with TSM save its prices for the ones without it (see SavedPrices.lua)
	saveItems = "recipes", -- which items' prices they save (see ns.SAVE_ITEMS_CHOICES)
	ahCut = true,
	procFx = true,        -- animate multicraft / resourcefulness procs
	procSound = true,     -- coin sound on procs
	showSession = true,   -- show the total of this session's crafts
	shoppingButton = true, -- the Shopping list button, and the shopping buttons on the Patron tab
	listAddon = "auctionator", -- with both installed, materials go to: "auctionator" | "tsm"
	listPerCharacter = true,   -- a separate Auctionator list for each character
	listPerProfession = true,  -- and/or for each profession
	checkOff = true,           -- take materials off the Auctionator list as you get them
	patronList = true,    -- Craft Profit's columns, buttons and footer on the Patron tab's order list
	patronSort = false,   -- the Patron tab sorted by profit: "desc" | "asc", or false for Blizzard's sort
	concentrationFor = "profit", -- patron orders that need concentration get it by: "profit" | "knowledge", or "none" of it
	leastConcentration = false, -- orders that need concentration: the qualities that need the least, cheapest of those
	patronMaterials = "cheapest", -- patron orders' material qualities: "cheapest" | "owned" (see ns.PATRON_MATERIALS_CHOICES)
	patronReach = "materials",    -- reaching an order's minimum quality: "materials" | "concentration" first
	nextLosing = true,    -- the Patron tab's Next order button goes on to orders that lose gold
	bestMaterials = false, -- "Use Craft Profit Reagents" on the order form and crafting page: put them in every order or recipe you open
	craftStrategy = ns.QUALITY_CRAFTING and "highest" or "buy", -- what the crafting page and Best crafts list craft (see ns.STRATEGIES)
	scanReminder = true,  -- remind you to scan the auction house when Auctionator's prices are old
	minimap = true,       -- the minimap button (its position is in minimapIcon, kept by LibDBIcon)
	countProcs = true,    -- multicraft and resourcefulness count in the Best crafts list
	rankTooltip = true,   -- best rank you can craft, on crafted items' tooltips
	priceTooltip = true,  -- saved TSM prices on item tooltips, on characters without TSM
	-- On item tooltips: what a vendor charges and pays, the auction price, the auction house deposit
	tipVendorBuy = true,
	tipVendorSell = true,
	tipAuction = true,
	tipDeposit = true,
	tipSaleRate = true,   -- item tooltips: TSM's sale rate
	rankConcentration = true, -- add the concentration that rank takes
	rankCharacters = "all", -- whose ranks: "all" your characters | "current" one
	bestSort = "profit",  -- the Best crafts list's sort: "profit" | "plain" | "procs" | "cost" | "gold" | "perPoint" | "listed" | "sold" | "crafter" | "name"
	bestSortAscending = false,
	bestAllCharacters = false, -- the Best crafts list shows your other characters' and professions' recipes
	bestProfitableOnly = false, -- the Best crafts list hides recipes that don't make a profit
	bestShowIgnored = false, -- the Best crafts list shows the recipes you ignored, in grey
	ledgerRange = 30,     -- the Ledger window's days
}

-- Patron order rewards that give profession knowledge: itemID -> points each.
ns.KNOWLEDGE_ITEMS = {
	[246330] = 1, -- Flicker
	[246331] = 2, -- Glimmer
}

-- The "Optimize concentration" option, in the Patron tab's gear menu and the options.
ns.LEAST_CONCENTRATION = "Optimize concentration"
ns.LEAST_CONCENTRATION_TIP = "Orders that only reach their minimum quality with concentration use the material " ..
	"qualities that need the least of it, and the cheapest of those. The materials cost more, but your " ..
	"concentration lasts for more orders.\n\nOff: the cheapest materials that reach it, whatever concentration they take."

-- The "Next order: include orders that lose gold" option, in the Patron tab's gear menu and the options.
ns.NEXT_LOSING = "Next order: include orders that lose gold"
ns.NEXT_LOSING_TIP = "Once the orders that make a profit are done, the Next order button goes on to the ones you " ..
	"have everything for that lose gold, smallest loss first: for their knowledge or other rewards.\n\n" ..
	"Off: it stops after the profitable ones. Their own hammer still does any order."

-- Choices for which patron orders get your concentration first.
ns.CONCENTRATION_CHOICES = {
	{ "profit", "Most profit (default)" },
	{ "knowledge", "Knowledge first" },
	{ "none", "Don't use concentration" },
}

-- Crafting orders' own choices (every order, the Patron tab's included): which
-- material qualities they use, and how they reach their minimum quality.
-- { key, label, tooltip }.
ns.PATRON_MATERIALS_TITLE = "Order materials"
ns.PATRON_MATERIALS_CHOICES = {
	{ "cheapest", "Cheapest (default)", "The cheapest qualities that reach the order's minimum quality, whether you own " ..
		"them or buy them." },
	{ "owned", "Use what I own", "Qualities you own first. Only what you're short of is bought, at the cheapest " ..
		"quality that still reaches the minimum." },
}
ns.PATRON_REACH_TITLE = "Reach the minimum with"
ns.PATRON_REACH_CHOICES = {
	{ "materials", "Better materials (default)", "Higher-rank materials first; concentration only when no " ..
		"materials reach the minimum." },
	{ "concentration", "Concentration", "Concentration with lower-rank materials first; better materials only when " ..
		"you're out of concentration, or Spend concentration on is set to Don't use concentration." },
}

-- A choice's name without "(default)".
function ns.ChoiceName(choice)
	return (choice[2]:gsub(" %(default%)$", ""))
end

-- A dropdown menu for one of those settings: a radio for each choice, with its
-- explanation as its tooltip. Picking one changes it everywhere it shows.
function ns.ChoiceMenu(key, title, choices)
	return function(_, root)
		root:CreateTitle(title)
		for _, choice in ipairs(choices) do
			local radio = root:CreateRadio(choice[2], function(value) return ns.db[key] == value end,
				function(value) ns.Options.Set(key, value) end, choice[1])
			radio:SetTooltip(function(tooltip)
				GameTooltip_SetTitle(tooltip, choice[2])
				tooltip:AddLine(choice[3], 1, 1, 1, true)
			end)
		end
	end
end

-- What such a dropdown shows for its choice: the name, after `prefix` if given.
function ns.ChoiceText(choices, prefix)
	return function(selection)
		for _, choice in ipairs(choices) do
			if choice[1] == selection.data then return (prefix or "") .. ns.ChoiceName(choice) end
		end
	end
end

-- Crafting strategies: which rank and materials the crafting page and the Best
-- crafts list craft. key, name, short name, and what it does. WoW Forever has no
-- ranks, so there they say where missing materials come from (see Chains.lua).
ns.STRATEGIES = ns.QUALITY_CRAFTING and {
	{ "highest", "Highest rank, cheapest materials", "Highest rank",
		"The highest rank you can make, with the cheapest materials that reach it." },
	{ "owned", "Use what I own", "What I own",
		"The highest rank you have every material for. Short for all of them: the highest rank you can make, spending the least gold on what you're missing. The Best crafts list only shows what you can craft now." },
	{ "cheapest", "Cheapest materials", "Cheapest",
		"The cheapest materials, whatever rank they make. For skill-ups, first crafts and knowledge." },
} or {
	{ "buy", "Buy missing", "Buy missing",
		"Materials you're missing are bought at their auction house price." },
	{ "craft", "Craft myself", "Craft myself",
		"Materials you know the recipe for are crafted, down to what has to be bought: they cost what their own " ..
		"materials cost, and the shopping list buys those instead. Recipes from all this character's professions " ..
		"count, once you've opened that profession's Best crafts list." },
}

-- The current crafting strategy's entry in ns.STRATEGIES.
function ns.Strategy()
	for _, strategy in ipairs(ns.STRATEGIES) do
		if strategy[1] == ns.db.craftStrategy then return strategy end
	end
	return ns.STRATEGIES[1]
end

-- The crafting strategy dropdowns' menu (under the Best crafts list and on the
-- panel): one choice per strategy, with what it does in its tooltip.
function ns.StrategyMenu(_, root)
	for _, strategy in ipairs(ns.STRATEGIES) do
		local key = strategy[1]
		local radio = root:CreateRadio(strategy[2], function() return ns.db.craftStrategy == key end,
			function() ns.Options.Set("craftStrategy", key) end, key)
		radio:SetTooltip(function(tip)
			GameTooltip_SetTitle(tip, strategy[2])
			GameTooltip_AddNormalLine(tip, strategy[4])
		end)
	end
end

-- What a strategy dropdown shows for the picked strategy: its short name.
function ns.StrategyText(selection)
	for _, strategy in ipairs(ns.STRATEGIES) do
		if strategy[1] == selection.data then return strategy[3] end
	end
end

-- Choices for where missing materials go when Auctionator and TSM are both installed.
ns.LIST_ADDON_CHOICES = {
	{ "auctionator", "Auctionator shopping list" },
	{ "tsm", "TSM search to copy" },
}

-- The Auctionator shopping list the missing materials button adds to, when the
-- list isn't named after the character or profession.
ns.SHOPPING_LIST = "Crafting"

-- Which items' TSM prices are saved for your alts: key, name, and what it saves.
ns.SAVE_ITEMS_CHOICES = {
	{ "recipes", "Your recipes", "The materials and crafts of your characters' recipes, once you've opened their " ..
		"Best crafts list. The smallest save." },
	{ "crafting", "All crafting items", "Your recipes, plus every material, reagent, consumable, gem, enchant, " ..
		"recipe and decor item TSM has auction prices for." },
	{ "all", "Everything TSM has", "Your recipes, plus every item TSM has auction prices for on your realm, gear " ..
		"at each item level included. The biggest save." },
}

-- Kinds of item "All crafting items" saves, by item class. Housing is decor,
-- on game versions that have it.
ns.CRAFTING_CLASSES = {}
for _, class in ipairs({ "Consumable", "Gem", "Reagent", "Tradegoods", "ItemEnhancement", "Recipe", "Housing" }) do
	local classID = Enum.ItemClass[class]
	if classID then ns.CRAFTING_CLASSES[classID] = true end
end

-- The lower of market value and the lowest auction, as a TSM price.
ns.TSM_LOWER = "min(dbmarket, dbminbuyout)"

-- TSM price types offered in the options.
ns.TSM_SOURCES = {
	{ "dbmarket", "Market value (recommended)" },
	{ "dbminbuyout", "Lowest auction right now" },
	{ ns.TSM_LOWER, "Lower of market and lowest" }, -- short: the closed dropdown cuts long names
	{ "dbhistorical", "Historical price" },
	{ "dbregionmarketavg", "Region market average" },
}

-- A TSM price as footers and tooltips name it: its own name, shorter for the
-- lower of two.
function ns.TSMSourceText(source)
	if source == ns.TSM_LOWER then return "lower of dbmarket, dbminbuyout" end
	return source
end
