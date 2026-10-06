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
	missingTarget = "auto", -- missing materials button: "auto" | "auctionator" | "blizzard" | "off"
}

-- The Auctionator shopping list the missing materials button adds to.
ns.SHOPPING_LIST = "Craft Profit"

-- TSM price types offered in the options.
ns.TSM_SOURCES = {
	{ "dbmarket", "Market value (recommended)" },
	{ "dbminbuyout", "Lowest auction right now" },
	{ "dbhistorical", "Historical price" },
	{ "dbregionmarketavg", "Region market average" },
}
