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

-- `text` in the color of the item's rarity (green, blue, purple...), or as it is
-- while the game hasn't loaded the item.
function Format.RarityColored(itemID, text)
	local rarity = itemID and C_Item.GetItemQualityByID(itemID)
	local hex = rarity and select(4, C_Item.GetItemQualityColor(rarity))
	return hex and ("|c" .. hex .. text .. "|r") or text
end

-- "3x [icon] Name [quality]", the name in its rarity's color. Asks the game to
-- load names it hasn't seen yet; the panel redraws when they arrive.
function Format.Item(itemID, qty)
	local name = C_Item.GetItemNameByID(itemID)
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
