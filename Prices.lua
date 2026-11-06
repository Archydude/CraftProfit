-- Craft Profit: prices from TradeSkillMaster or Auctionator, or TSM prices
-- another character saved when TSM isn't loaded here (see SavedPrices.lua).
local ADDON_NAME, ns = ...

local Prices = {}
ns.Prices = Prices

local function tsmAvailable()
	return ns.db.provider ~= "auctionator" and TSM_API and TSM_API.GetCustomPriceValue
end

-- Whether TSM's prices come from another character's save: TSM isn't loaded here.
local function savedPrices()
	return ns.db.provider ~= "auctionator" and not (TSM_API and TSM_API.GetCustomPriceValue)
		and ns.SavedPrices.InUse()
end

local function auctionatorAPI()
	if ns.db.provider == "tsm" then return end
	return Auctionator and Auctionator.API and Auctionator.API.v1
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
	local api = auctionatorAPI()
	return (tsmAvailable() and tsmValue("vendorbuy", "i:" .. itemID))
		or (savedPrices() and ns.SavedPrices.Vendor(itemID))
		or (api and auctionatorValue(api.GetVendorPriceByItemID, itemID))
		or (ns.VENDOR_PRICES and ns.VENDOR_PRICES[itemID])
end

-- What a material costs you, in copper (nil if nobody knows): what it costs to
-- buy, or with Craft myself (WoW Forever), what crafting it costs when you know
-- its recipe (see Chains.lua).
function Prices.Material(itemID)
	if ns.Chains.Active() then
		local cost = ns.Chains.CraftCost(itemID)
		if cost then return cost end
	end
	return Prices.Buy(itemID)
end

-- What a material costs on the auction house, in copper (nil if nobody knows).
local function auctionPrice(itemID)
	local api = auctionatorAPI()
	return (tsmAvailable() and tsmValue(ns.db.matSource, "i:" .. itemID))
		or (savedPrices() and ns.SavedPrices.Material(itemID))
		or (api and auctionatorValue(api.GetAuctionPriceByItemID, itemID))
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

-- What a crafted item sells for, in copper. Uses the full link so quality and
-- item level count.
function Prices.Sale(link, itemID)
	if tsmAvailable() then
		local ok, itemString = pcall(TSM_API.ToItemString, link)
		local value = ok and itemString and tsmValue(ns.db.saleSource, itemString)
		if value then return value end
	elseif savedPrices() then
		local value = ns.SavedPrices.Sale(link, itemID)
		if value then return value end
	end
	local api = auctionatorAPI()
	if api then
		return auctionatorValue(api.GetAuctionPriceByItemLink, link)
			or (itemID and auctionatorValue(api.GetAuctionPriceByItemID, itemID))
	end
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

-- Whether TSM is loaded, whatever the price addon option says (for its sales
-- numbers), or another character's save of its prices is used here.
function Prices.HasTSM()
	return (TSM_API ~= nil and TSM_API.GetCustomPriceValue ~= nil)
		or (ns.SavedPrices.InUse() and ns.SavedPrices.Age() ~= nil)
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

-- How many days ago Auctionator last scanned the auction house, with its full scan
-- or its automatic one (0 is within the last day), or false when it never has.
-- Nil when prices don't come from Auctionator (TSM keeps its own up to date, and
-- saved TSM prices have their own age, see Prices.SavedAge).
-- Auctionator keeps those times in its own saved state, not its API, so a change
-- on its side just means no answer.
function Prices.ScanAge()
	if tsmAvailable() or Prices.SavedAge() or not auctionatorAPI() then return end
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
	-- Crafted with Craft myself: its own price isn't used.
	if ns.Chains.Active() and ns.Chains.RecipeFor(itemID) then return end
	return auctionAge("GetAuctionAgeByItemID", itemID)
end

-- A crafted item's price age (see auctionAge).
function Prices.SaleAge(link)
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
		return "TSM (" .. ns.db.matSource .. ")" .. (ns.SavedPrices.Saving() and ", saving for alts..." or "")
	end
	local age, name, source
	if savedPrices() then age, name, source = ns.SavedPrices.Age() end
	if age then
		local label = string.format("%s's TSM (%s)", name, source)
		if age < ns.Reminder.OLD_DAYS then label = label .. ", saved " .. Prices.AgeText(age) end
		return label
	end
	if auctionatorAPI() then return "Auctionator" end
	if ns.db.provider == "tsm" then return "TSM is not loaded" end
	if ns.db.provider == "auctionator" then return "Auctionator is not loaded" end
	return "none - install TSM or Auctionator"
end
