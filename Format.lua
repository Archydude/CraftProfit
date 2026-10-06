-- Craft Profit: turning numbers and items into panel text.
local _, ns = ...

local Format = {}
ns.Format = Format

local format = string.format

local function icon(texture)
	return texture and format("|T%s:%d|t ", texture, ns.Layout.ICON_SIZE) or ""
end

-- Copper as gold/silver/copper text, rounded to the coin chosen in the options.
-- Amounts smaller than that coin keep the next one down, so they never show as zero.
function Format.Money(copper)
	copper = math.floor(copper + 0.5)
	local amount = math.abs(copper)
	local precision = ns.db.precision
	local unit = (precision == "gold" and amount >= 10000 and 10000)
		or (precision ~= "copper" and amount >= 100 and 100)
	if unit then amount = math.floor(amount / unit + 0.5) * unit end
	local text = GetMoneyString(amount, true)
	return copper < 0 and ("-" .. text) or text
end

-- "3x [icon] Name [quality]". Asks the game to load names it hasn't seen yet;
-- the panel redraws when they arrive.
function Format.Item(itemID, qty)
	local name = C_Item.GetItemNameByID(itemID)
	if not name then
		C_Item.RequestLoadItemDataByID(itemID)
		name = "Loading..."
	end
	local quality = ns.Blizzard.ReagentQualityMarkup(itemID)
	return format("%dx %s%s%s", qty, icon(C_Item.GetItemIconByID(itemID)), name, quality and (" " .. quality) or "")
end

-- "30x [icon] Artisan's Moxie".
function Format.Currency(currencyInfo, qty)
	return format("%dx %s%s", qty, icon(currencyInfo.iconFileID), currencyInfo.name or "?")
end
