-- Craft Profit: values shared by every file. Change them here, not inline.
local _, ns = ...

-- The auction house keeps 5% of every sale.
ns.AH_CUT = 0.05

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
	useVendor = true,
	ahCut = true,
	procFx = true,        -- animate multicraft / resourcefulness procs
	procSound = true,     -- coin sound on procs
	showSession = true,   -- show the total of this session's crafts
	shoppingButton = true, -- the Shopping list row, and the shopping buttons on the Patron tab
	listAddon = "auctionator", -- with both installed, materials go to: "auctionator" | "tsm"
	listPerCharacter = true,   -- a separate Auctionator list for each character
	listPerProfession = true,  -- and/or for each profession
	checkOff = true,           -- take materials off the Auctionator list as you get them
	patronList = true,    -- Craft Profit's columns, buttons and footer on the Patron tab's order list
	patronSort = false,   -- the Patron tab sorted by profit: "desc" | "asc", or false for Blizzard's sort
	concentrationFor = "profit", -- patron orders that need concentration get it by: "profit" | "knowledge", or "none" of it
	leastConcentration = false, -- orders that need concentration: the qualities that need the least, cheapest of those
	bestMaterials = false, -- "Use Most Profitable Reagents" on the order form and crafting page: put them in every order or recipe you open
	rankTooltip = true,   -- best rank you can craft, on crafted items' tooltips
	rankConcentration = true, -- add the concentration that rank takes
	rankCharacters = "all", -- whose ranks: "all" your characters | "current" one
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

-- Choices for which patron orders get your concentration first.
ns.CONCENTRATION_CHOICES = {
	{ "profit", "Most profit (default)" },
	{ "knowledge", "Knowledge first" },
	{ "none", "Don't use concentration" },
}

-- Choices for where missing materials go when Auctionator and TSM are both installed.
ns.LIST_ADDON_CHOICES = {
	{ "auctionator", "Auctionator shopping list" },
	{ "tsm", "TSM search to copy" },
}

-- The Auctionator shopping list the missing materials button adds to, when the
-- list isn't named after the character or profession.
ns.SHOPPING_LIST = "Crafting"

-- TSM price types offered in the options.
ns.TSM_SOURCES = {
	{ "dbmarket", "Market value (recommended)" },
	{ "dbminbuyout", "Lowest auction right now" },
	{ "dbhistorical", "Historical price" },
	{ "dbregionmarketavg", "Region market average" },
}
