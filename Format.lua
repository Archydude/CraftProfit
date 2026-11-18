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
	local unit
	if ns.QUALITY_CRAFTING then
		local precision = ns.db.precision
		unit = (precision == "gold" and amount >= 10000 and 10000) or (precision ~= "copper" and amount >= 100 and 100)
	else
		-- WoW Forever's prices are small, so always the two biggest coins: 4g 12s, or 1s 4c.
		unit = amount >= 10000 and 100 or nil
	end
	if unit then amount = math.floor(amount / unit + 0.5) * unit end
	local text = GetMoneyString(amount, true)
	return copper < 0 and ("-" .. text) or text
end

-- The colors a sale rate runs through: red at 0%, yellow at 50%, green at 100%.
local RATE_LOW, RATE_MID, RATE_HIGH = { 1, 0.27, 0.27 }, { 1, 0.82, 0 }, { 0.2, 1, 0.2 }

-- TSM's sale rate (0.42 for 42%) as "42%", colored from red for one that
-- hardly sells to green for one that always does.
function Format.SaleRate(rate)
	local share = math.min(math.max(rate, 0), 1)
	local from, to, part = RATE_LOW, RATE_MID, share * 2
	if share > 0.5 then from, to, part = RATE_MID, RATE_HIGH, share * 2 - 1 end
	local function mix(index) return math.floor((from[index] + (to[index] - from[index]) * part) * 255 + 0.5) end
	return format("|cff%02x%02x%02x%.0f%%|r", mix(1), mix(2), mix(3), rate * 100)
end

-- TSM's trend (-20 for 20% below the historical price, see Prices.Trend) as
-- "-20%" in red, or "+14%" in green from zero up: TSM's own colors, with a sign
-- where TSM draws an arrow.
function Format.Trend(trend)
	if trend < 0 then return ns.Color("loss", format("%.0f%%", trend)) end
	return ns.Color("profit", format("%s%.0f%%", trend > 0 and "+" or "", trend))
end

-- `text` in the color of the item's rarity (green, blue, purple...), or as it is
-- while the game hasn't loaded the item.
function Format.RarityColored(itemID, text)
	local rarity = itemID and C_Item.GetItemQualityByID(itemID)
	local hex = rarity and select(4, C_Item.GetItemQualityColor(rarity))
	return hex and ("|c" .. hex .. text .. "|r") or text
end

-- An item's name, or nil while the game hasn't loaded it. Both of the game's ways
-- to read it are tried, as either can have it first.
function Format.ItemName(itemID)
	local name = C_Item.GetItemNameByID(itemID) or C_Item.GetItemInfo(itemID)
	return name
end

-- "3x [icon] Name [quality]", the name in its rarity's color. Asks the game to
-- load names it hasn't seen yet; the panel redraws when they arrive.
function Format.Item(itemID, qty)
	local name = Format.ItemName(itemID)
	if name then
		name = Format.RarityColored(itemID, name)
	else
		C_Item.RequestLoadItemDataByID(itemID)
		name = "Loading..."
	end
	local quality = ns.Blizzard.ReagentQualityMarkup(itemID)
	return format("%dx %s%s%s", qty, icon(C_Item.GetItemIconByID(itemID)), name, quality and (" " .. quality) or "")
end

-- As Format.Item, for anything that can be auctioned: a caged battle pet goes by
-- its link, since its item is only the cage.
function Format.Sellable(itemID, link, qty)
	if itemID == ns.PET_CAGE_ITEM and link then return format("%dx %s", qty, link) end
	return Format.Item(itemID, qty)
end

-- "30x [icon] Artisan's Moxie".
function Format.Currency(currencyInfo, qty)
	return format("%dx %s%s", qty, icon(currencyInfo.iconFileID), currencyInfo.name or "?")
end
