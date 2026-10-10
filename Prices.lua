-- Craft Profit: prices from TradeSkillMaster or Auctionator.
local ADDON_NAME, ns = ...

local Prices = {}
ns.Prices = Prices

local function tsmAvailable()
	return ns.db.provider ~= "auctionator" and TSM_API and TSM_API.GetCustomPriceValue
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
-- nobody knows).
function Prices.Vendor(itemID)
	local api = auctionatorAPI()
	return (tsmAvailable() and tsmValue("vendorbuy", "i:" .. itemID))
		or (api and auctionatorValue(api.GetVendorPriceByItemID, itemID))
end

-- What a material costs you, in copper (nil if nobody knows).
function Prices.Material(itemID)
	-- Vendor-sold things (vials, thread...) cost the vendor price.
	local value = ns.db.useVendor and Prices.Vendor(itemID)
	if value then return value end
	local api = auctionatorAPI()
	return (tsmAvailable() and tsmValue(ns.db.matSource, "i:" .. itemID))
		or (api and auctionatorValue(api.GetAuctionPriceByItemID, itemID))
end

-- What a crafted item sells for, in copper. Uses the full link so quality and
-- item level count.
function Prices.Sale(link, itemID)
	if tsmAvailable() then
		local ok, itemString = pcall(TSM_API.ToItemString, link)
		local value = ok and itemString and tsmValue(ns.db.saleSource, itemString)
		if value then return value end
	end
	local api = auctionatorAPI()
	if api then
		return auctionatorValue(api.GetAuctionPriceByItemLink, link)
			or (itemID and auctionatorValue(api.GetAuctionPriceByItemID, itemID))
	end
end

-- How many days ago Auctionator last saw an item on the auction house (0 is
-- today), or false when it's over three weeks or never. nil when prices don't
-- come from Auctionator (TSM keeps its own data).
local function auctionAge(fnName, arg)
	if tsmAvailable() then return end
	local api = auctionatorAPI()
	local fn = api and api[fnName]
	if not fn then return end
	local ok, age = pcall(fn, ADDON_NAME, arg)
	if not ok then return end
	return type(age) == "number" and age or false
end

-- A material's price age (see auctionAge). Vendor prices don't age.
function Prices.MaterialAge(itemID)
	if ns.db.useVendor and Prices.Vendor(itemID) then return end
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

-- Where prices currently come from, for the panel's footer.
function Prices.SourceLabel()
	if tsmAvailable() then return "TSM (" .. ns.db.matSource .. ")" end
	if auctionatorAPI() then return "Auctionator" end
	if ns.db.provider == "tsm" then return "TSM is not loaded" end
	if ns.db.provider == "auctionator" then return "Auctionator is not loaded" end
	return "none - install TSM or Auctionator"
end
