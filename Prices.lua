-- Craftonomics: prices from TradeSkillMaster or Auctionator, TSM prices another
-- character saved when TSM isn't loaded here (see SavedPrices.lua), or Craft
-- Profit's own scan of the auction house (see PriceScan.lua).
local ADDON_NAME, ns = ...

local Prices = {}
ns.Prices = Prices

-- Whether the Price addon option lets TSM's prices in.
local function wantsTSM()
	return ns.db.provider == "auto" or ns.db.provider == "tsm"
end

local function tsmAvailable()
	return wantsTSM() and TSM_API and TSM_API.GetCustomPriceValue
end

-- Whether TSM's prices come from another character's save: TSM isn't loaded here.
local function savedPrices()
	return wantsTSM() and not (TSM_API and TSM_API.GetCustomPriceValue) and ns.SavedPrices.InUse()
end

local function auctionatorAPI()
	if ns.db.provider ~= "auto" and ns.db.provider ~= "auctionator" then return end
	return Auctionator and Auctionator.API and Auctionator.API.v1
end

-- Craftonomics' own scan: the last one asked with Automatic, so it prices what
-- nobody else does, and the only one when it's the Price addon picked.
local function ownScan()
	if ns.db.provider == "auto" or ns.db.provider == "own" then return ns.PriceScan end
end

-- Other addons' APIs can change or throw on items they don't know, so every
-- call into them is guarded. A failed lookup is just "no price".
local function tsmValue(source, itemString)
	local ok, value = pcall(TSM_API.GetCustomPriceValue, source, itemString)
	if ok and value and value > 0 then return value end
end

local function auctionatorValue(fn, arg)
	if not fn then return end
	local ok, value = pcall(fn, ADDON_NAME, arg)
	if ok and value and value > 0 then return value end
end

-- What a vendor sells an item for, in copper (nil if no vendor sells it, or
-- nobody knows). On WoW Forever, common reagents (thread, flux, vials...) are
-- known before a price addon has seen a vendor sell them (Data\Forever.lua).
function Prices.Vendor(itemID)
	local api, own = auctionatorAPI(), ownScan()
	return (tsmAvailable() and tsmValue("vendorbuy", "i:" .. itemID))
		or (savedPrices() and ns.SavedPrices.Vendor(itemID))
		or (api and auctionatorValue(api.GetVendorPriceByItemID, itemID))
		or (own and own.Vendor(itemID))
		or (ns.VENDOR_PRICES and ns.VENDOR_PRICES[itemID])
end

-- What a material costs you, in copper (nil if nobody knows): what it costs to
-- buy, or what crafting it costs when the crafting strategy crafts it (WoW
-- Forever's Craft myself and Cheapest way, see Chains.lua).
function Prices.Material(itemID)
	return ns.Chains.Cost(itemID) or Prices.Buy(itemID)
end

-- With both Auctionator's prices and Craftonomics' scan in use, whether the
-- scan's come first: the "Price with" choice. Either way the other one prices
-- what the first doesn't.
local function ownFirst()
	return ns.db.ahPrice == "own"
end

-- What a material costs on the auction house, in copper (nil if nobody knows).
local function auctionPrice(itemID)
	local api, own = auctionatorAPI(), ownScan()
	local value = (tsmAvailable() and tsmValue(ns.db.matSource, "i:" .. itemID))
		or (savedPrices() and ns.SavedPrices.Material(itemID))
	if value then return value end
	if ownFirst() then
		return (own and own.Material(itemID)) or (api and auctionatorValue(api.GetAuctionPriceByItemID, itemID)) or nil
	end
	return (api and auctionatorValue(api.GetAuctionPriceByItemID, itemID)) or (own and own.Material(itemID)) or nil
end

-- Whether materials a vendor sells are bought from a vendor: unless "Buy vendor
-- items on the auction house" is on.
function Prices.BuysAtVendor(itemID)
	return not ns.db.vendorOnAH and Prices.Vendor(itemID) ~= nil
end

-- What buying a material costs, in copper (nil if nobody knows), whatever the
-- crafting strategy. Vendor-sold things (vials, thread...) cost the vendor price,
-- or with "Buy vendor items on the auction house", their auction price (the
-- vendor's while the auction house has none).
function Prices.Buy(itemID)
	local vendor = Prices.Vendor(itemID)
	if vendor and not ns.db.vendorOnAH then return vendor end
	return auctionPrice(itemID) or vendor
		-- Price addons may not know vellums, and a vendor always has them.
		or (itemID == ns.VELLUM_ITEM and ns.VELLUM_PRICE or nil)
end

-- With "Buy vendor items on the auction house" on: when the auction house asks
-- more for a material than a vendor does, both prices. Nil otherwise.
function Prices.VendorCheaper(itemID)
	if not ns.db.vendorOnAH then return end
	local vendor = Prices.Vendor(itemID)
	local auction = vendor and auctionPrice(itemID)
	if auction and auction > vendor then return vendor, auction end
end

-- What a crafted item sells for, in copper, and where that price came from:
-- "tsm", "saved" (TSM prices saved for alts), "auctionator" or "own" (Craft
-- Profit's scan). Uses the full link so quality and item level count.
function Prices.SaleFrom(link, itemID)
	if tsmAvailable() then
		local ok, itemString = pcall(TSM_API.ToItemString, link)
		local value = ok and itemString and tsmValue(ns.db.saleSource, itemString)
		if value then return value, "tsm" end
	elseif savedPrices() then
		local value = ns.SavedPrices.Sale(link, itemID)
		if value then return value, "saved" end
	end
	local api, own = auctionatorAPI(), ownScan()
	-- Craftonomics' scan before Auctionator's prices when that's the choice.
	local value = own and ownFirst() and own.Sale(link, itemID)
	if value then return value, "own" end
	if api then
		value = auctionatorValue(api.GetAuctionPriceByItemLink, link)
			or (itemID and auctionatorValue(api.GetAuctionPriceByItemID, itemID))
		if value then return value, "auctionator" end
	end
	value = own and own.Sale(link, itemID)
	if value then return value, "own" end
end

-- What a crafted item sells for, in copper (see Prices.SaleFrom).
function Prices.Sale(link, itemID)
	return (Prices.SaleFrom(link, itemID))
end

-- What disenchanting an item gives on average, in copper, and whose number it
-- is: "tsm" or "auctionator". Only uncommon to epic weapons and armor can be
-- disenchanted (TSM's number for anything else is what milling or prospecting
-- it gives). Nil for the rest, without either addon, and when neither can price
-- what it gives. Uses the full link so the item's level counts.
function Prices.Disenchant(link)
	local classID = link and select(6, C_Item.GetItemInfoInstant(link))
	if classID ~= Enum.ItemClass.Weapon and classID ~= Enum.ItemClass.Armor then return end
	local quality = C_Item.GetItemQualityByID(link)
	if not quality or quality < Enum.ItemQuality.Uncommon or quality > Enum.ItemQuality.Epic then return end
	if tsmAvailable() then
		local ok, itemString = pcall(TSM_API.ToItemString, link)
		local value = ok and itemString and tsmValue("destroy", itemString)
		if value then return value, "tsm" end
	end
	local api = auctionatorAPI()
	local value = api and auctionatorValue(api.GetDisenchantPriceByItemLink, link)
	if value then return value, "auctionator" end
end

-- What an item disenchants into, from Craftonomics' own table (ns.DISENCHANTS,
-- WoW Forever only), as lines like "80%  1-2 Strange Dust". Nil without a row for
-- the item's kind, quality and level.
local function ownDisenchants(link)
	local classID = ns.DISENCHANTS and select(6, C_Item.GetItemInfoInstant(link))
	local byQuality = classID and ns.DISENCHANTS[classID]
	local rows = byQuality and byQuality[C_Item.GetItemQualityByID(link) or 0]
	local level = rows and (C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo)(link)
	if not level then return end
	for _, row in ipairs(rows) do
		if level >= row[1] and level <= row[2] then
			local lines = {}
			for index = 3, #row do
				local chance, fewest, most, itemID = unpack(row[index])
				local name = ns.Format.ItemName(itemID)
				if name then
					name = ns.Format.RarityColored(itemID, name)
				else
					C_Item.RequestLoadItemDataByID(itemID)
					name = "Loading..."
				end
				lines[#lines + 1] = string.format("|cffffffff%s%%|r  %s %s", tostring(chance),
					fewest == most and tostring(fewest) or (fewest .. "-" .. most), name)
			end
			return lines
		end
	end
end

-- What an item disenchants into, as lines like "80%  1-2 Strange Dust": the
-- chance of each material and how many it gives. From Craftonomics' own table on
-- WoW Forever; for what that doesn't have, from Auctionator, which lists it
-- where it shows it on its own tooltips. That isn't part of Auctionator's API,
-- so a change on its side just means no list. Nil when neither has it.
function Prices.DisenchantsInto(link)
	local own = ownDisenchants(link)
	if own then return own end
	local list = Auctionator and Auctionator.Enchant and Auctionator.Enchant.GetDisenchantBreakdown
	if not list then return end
	local info = { C_Item.GetItemInfo(link) }
	if #info == 0 then return end
	local ok, lines = pcall(list, link, info)
	if not ok or type(lines) ~= "table" then return end
	local found = {}
	for _, line in ipairs(lines) do
		if type(line) == "string" then found[#found + 1] = strtrim(line) end
	end
	return #found > 0 and found or nil
end

-- Caps each rank's sale price at the price of every rank above it: nobody pays
-- more for rank 3 than for a better rank 5, so a higher listing for rank 3 is one
-- that doesn't sell. `sales` is rank -> price (nil without a price). Returns
-- rank -> capped price, and rank -> the higher rank that set the cap, for the
-- ranks it lowered.
function Prices.CapRanks(sales, maxRank)
	local capped, cappedBy = {}, {}
	local lowest, lowestRank
	for rank = maxRank, 1, -1 do
		local price = sales[rank]
		if price then
			if lowest and lowest < price then
				capped[rank], cappedBy[rank] = lowest, lowestRank
			else
				capped[rank] = price
				lowest, lowestRank = price, rank
			end
		end
	end
	return capped, cappedBy
end

-- How many of an item were up for sale the last day Auctionator scanned it, and
-- how many days ago that was (0 is today); nil when it has no count. This reads
-- Auctionator's own price history, which isn't part of its API, so every step
-- is guarded and a change on its side just means no count.
function Prices.Listed(link)
	if Prices.Scanner() == "own" then return ns.PriceScan.Listed(link) end
	local db = Auctionator and Auctionator.Database
	local utilities = db and Auctionator.Utilities
	if not (db and db.GetPriceHistory and utilities and Auctionator.Constants) then return end
	local ok, count, age = pcall(function()
		local keys
		utilities.DBKeyFromLink(link, function(found) keys = found end)
		keys = keys or { utilities.BasicDBKeyFromLink(link) }
		local today = math.floor((time() - Auctionator.Constants.SCAN_DAY_0) / 86400)
		for _, key in ipairs(keys) do
			-- Newest day first.
			for _, day in ipairs(db:GetPriceHistory(key)) do
				if day.available then return day.available, today - tonumber(day.rawDay) end
			end
		end
	end)
	if ok then return count, age end
end

-- What putting `qty` of an item on the auction house costs as a deposit, for the
-- game's duration number `duration`, in copper, or nil when the game won't say.
-- You get it back when the auction sells, and lose it when it runs out unsold.
function Prices.Deposit(itemID, duration, qty)
	if not (C_AuctionHouse and C_AuctionHouse.CalculateCommodityDeposit) then return end
	local ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, duration, qty)
	if ok and type(deposit) == "number" and deposit > 0 then return deposit end
end

-- Whether TSM is loaded, whatever the price addon option says (for its sales
-- numbers), or another character's save of its prices is used here.
function Prices.HasTSM()
	return (TSM_API ~= nil and TSM_API.GetCustomPriceValue ~= nil)
		or (ns.SavedPrices.InUse() and ns.SavedPrices.Age() ~= nil)
end

-- Whose scan of the auction house the prices here are as old as: "auctionator",
-- "own" (Craftonomics'), or nil with TSM's prices, which need none.
function Prices.Scanner()
	if tsmAvailable() or Prices.SavedAge() then return end
	local api, own = auctionatorAPI(), ownScan()
	-- With both, the one whose prices come first, once Craftonomics has scanned.
	if api and not (own and ownFirst() and own.HasPrices()) then return "auctionator" end
	if own then return "own" end
end

-- Whether Craftonomics' scan may start by itself: its prices are in use, TSM's
-- aren't (they need no scan), and scanning is Craftonomics' part, or its scan is
-- the only price addon picked.
function Prices.ScansItself()
	if tsmAvailable() or Prices.SavedAge() or not ownScan() then return false end
	return ns.db.provider == "own" or ns.UsesOwn("ahPrice")
end

-- How many days ago the saved TSM prices used here were saved, and the name of
-- the character who saved them. Nil when prices don't come from a save.
function Prices.SavedAge()
	if not savedPrices() then return end
	local age, name = ns.SavedPrices.Age()
	return age, name
end

-- How many sell per day across the region, from TSM, or nil without TSM or a
-- number. TSM rounds to whole numbers, so it's asked for a thousand times the
-- number and divided back.
function Prices.SoldPerDay(link)
	if not Prices.HasTSM() then return end
	if not (TSM_API and TSM_API.GetCustomPriceValue) then return ns.SavedPrices.SoldPerDay(link) end
	local ok, itemString = pcall(TSM_API.ToItemString, link)
	if not (ok and itemString) then return end
	local value = tsmValue("dbregionsoldperday*1000", itemString)
	if value then return value / 1000 end
	return tsmValue("dbregionsoldperday", itemString)
end

-- Whether TSM's region sale rate takes the place of Sells/day and Listed (in the
-- Best crafts list and on the panel): on WoW Forever, and only with TSM loaded.
-- There TSM's sale rate pools every ruleset of the region (Normal, PvP...) into one
-- number. Elsewhere the sale rate shows beside them (see Prices.HasSaleRate).
function Prices.ShowsSaleRate()
	return not ns.QUALITY_CRAFTING and TSM_API ~= nil and TSM_API.GetCustomPriceValue ~= nil
end

-- Whether TSM's sale rate can be shown at all: only with TSM loaded on this
-- character (saved TSM prices don't carry it).
function Prices.HasSaleRate()
	return TSM_API ~= nil and TSM_API.GetCustomPriceValue ~= nil
end

-- The share of an item's auctions that sell across the region, from TSM (0.42
-- for 42%), or nil without TSM or a number. Asked for a thousand times, like
-- Prices.SoldPerDay, since TSM rounds to whole numbers.
function Prices.SaleRate(link)
	if not (TSM_API and TSM_API.GetCustomPriceValue) then return end
	local ok, itemString = pcall(TSM_API.ToItemString, link)
	if not (ok and itemString) then return end
	local value = tsmValue("dbregionsalerate*1000", itemString)
	return value and value / 1000
end

-- Whether TSM's trend can be shown at all: only with TSM loaded on this
-- character (saved TSM prices don't carry the historical price).
function Prices.HasTrend()
	return TSM_API ~= nil and TSM_API.GetCustomPriceValue ~= nil
end

-- How far an item's market value on your realm is from its historical price,
-- from TSM, in whole percent (-20 for 20% below it), or nil without TSM or
-- either price. The number TSM's own tooltip shows beside its market value,
-- rounded the same way, whatever TSM price type prices are taken from here.
function Prices.Trend(link)
	local market, historical = Prices.MarketAndHistorical(link)
	if not historical then return end
	return math.floor((market - historical) * 100 / historical + 0.5)
end

-- An item's market value on your realm and its historical price, from TSM, in
-- copper: both, or nothing without TSM or either price. What the trend is made of.
function Prices.MarketAndHistorical(link)
	if not (TSM_API and TSM_API.GetCustomPriceValue) then return end
	local ok, itemString = pcall(TSM_API.ToItemString, link)
	if not (ok and itemString) then return end
	local market = tsmValue("dbmarket", itemString)
	local historical = market and tsmValue("dbhistorical", itemString)
	if not historical then return end
	return market, historical
end

-- How far an item's lowest auction on your realm is from its market value, from
-- TSM, in whole percent (-18 for 18% below it), or nil without TSM or either
-- price (no lowest auction when nobody has one up).
function Prices.LowestVsMarket(link)
	if not (TSM_API and TSM_API.GetCustomPriceValue) then return end
	local ok, itemString = pcall(TSM_API.ToItemString, link)
	if not (ok and itemString) then return end
	local market = tsmValue("dbmarket", itemString)
	local lowest = market and tsmValue("dbminbuyout", itemString)
	if not lowest then return end
	return math.floor((lowest - market) * 100 / market + 0.5)
end

-- How many days ago Auctionator last saw an item on the auction house (0 is
-- today), or false when it's over three weeks or never. nil when prices don't
-- come from Auctionator (TSM keeps its own data).
local function auctionAge(fnName, arg)
	if tsmAvailable() or Prices.SavedAge() then return end
	local api = auctionatorAPI()
	local fn = api and api[fnName]
	if not fn then return end
	local ok, age = pcall(fn, ADDON_NAME, arg)
	if not ok then return end
	return type(age) == "number" and age or false
end

-- How many days ago the auction house was last scanned, by Auctionator (its full
-- scan or its automatic one) or by Craftonomics (0 is within the last day), or
-- false when it never was. Nil when prices come from neither (TSM keeps its own
-- up to date, and saved TSM prices have their own age, see Prices.SavedAge).
-- Auctionator keeps those times in its own saved state, not its API, so a change
-- on its side just means no answer.
function Prices.ScanAge()
	local scanner = Prices.Scanner()
	if scanner == "own" then return ns.PriceScan.Age() end
	if scanner ~= "auctionator" then return end
	local state = Auctionator.SavedState
	if type(state) ~= "table" then return end
	local last = 0
	for _, key in ipairs({ "TimeOfLastReplicateScan", "TimeOfLastBrowseScan", "TimeOfLastGetAllScan" }) do
		if type(state[key]) == "number" and state[key] > last then last = state[key] end
	end
	if last == 0 then return false end
	return math.floor((time() - last) / 86400)
end

-- "yesterday", "3 days ago" or "never" for a scan age (see Prices.ScanAge).
function Prices.ScanAgeText(age)
	if age == false then return "never" end
	return Prices.AgeText(age)
end

-- A material's price age (see auctionAge). Vendor prices don't age.
function Prices.MaterialAge(itemID)
	if Prices.BuysAtVendor(itemID) then return end
	-- Crafted (Craft myself, Cheapest way): its own price isn't used.
	if ns.Chains.Crafted(itemID) then return end
	if Prices.Scanner() == "own" then return ns.PriceScan.MaterialAge(itemID) end
	return auctionAge("GetAuctionAgeByItemID", itemID)
end

-- A crafted item's price age (see auctionAge).
function Prices.SaleAge(link)
	if Prices.Scanner() == "own" then return ns.PriceScan.SaleAge(link) end
	return auctionAge("GetAuctionAgeByItemLink", link)
end

-- "today", "yesterday", "3 days ago" or "over 3 weeks ago" for a price age, or nil.
function Prices.AgeText(age)
	if age == nil then return end
	if age == false then return "over 3 weeks ago" end
	if age == 0 then return "today" end
	return age == 1 and "yesterday" or string.format("%d days ago", age)
end

-- Where prices currently come from, for the panel's footer. Saved TSM prices say
-- whose they are, and how old while that's recent (old ones say it in red after
-- this, see Reminder.FooterText).
function Prices.SourceLabel()
	if tsmAvailable() then
		return "TSM (" .. ns.TSMSourceText(ns.db.matSource) .. ")" .. (ns.SavedPrices.Saving() and ", saving for alts..." or "")
	end
	local age, name, source
	if savedPrices() then age, name, source = ns.SavedPrices.Age() end
	if age then
		local label = string.format("%s's TSM (%s)", name, ns.TSMSourceText(source))
		if age < ns.Reminder.OLD_DAYS then label = label .. ", saved " .. Prices.AgeText(age) end
		return label
	end
	if auctionatorAPI() then return "Auctionator" end
	if ownScan() then
		return ns.PriceScan.HasPrices() and "Craftonomics' scan" or "none yet - scan at the auction house"
	end
	if ns.db.provider == "tsm" then return "TSM is not loaded" end
	return "Auctionator is not loaded"
end
