-- Craft Profit: item tooltips show what a vendor charges and pays for the item,
-- what it sells for with the price you picked (TSM's price type, or Auctionator),
-- and the auction house deposit for posting it, so you can tell whether it's
-- worth putting up. Each line has its own option.
local _, ns = ...

local format = string.format

-- The auction durations, by the game's number for them: Retail's, or WoW Forever's.
local DURATIONS = ns.QUALITY_CRAFTING and { "12h", "24h", "48h" } or { "2h", "8h", "24h" }

-- TSM's price types, as the tooltip names them.
local TSM_NAMES = {
	dbmarket = "Market Value",
	dbminbuyout = "Lowest Auction",
	dbhistorical = "Historical Price",
	dbregionmarketavg = "Region Market Average",
}

-- Items that can't go on the auction house: bound when picked up, quest items,
-- bound to your account.
local UNSELLABLE_BINDS = { [1] = true, [4] = true, [7] = true, [8] = true }

local function money(copper)
	return GetMoneyString(math.floor(copper + 0.5), true)
end

-- Where a tooltip's item sits in your bags or bank, or nil (a link, a vendor's item...).
local function locationOf(data)
	local guid = data and data.guid
	if not guid or (issecretvalue and issecretvalue(guid)) or not C_Item.GetItemLocation then return end
	local ok, location = pcall(C_Item.GetItemLocation, guid)
	if ok and location and location:IsValid() and C_Item.DoesItemExist(location) then return location end
end

-- Whether the item can't be posted: bound, or a quest item.
local function unsellable(itemID, location)
	if location and C_Item.IsBound(location) then return true end
	local bind = select(14, C_Item.GetItemInfo(itemID))
	return bind ~= nil and UNSELLABLE_BINDS[bind] == true
end

-- The deposit for `qty` at each duration, or nil when the game won't say.
-- An item in your bags asks as that item; otherwise by its itemID, as the
-- auction house does for stackable goods.
local function deposits(itemID, location, qty)
	local list = {}
	for duration = 1, #DURATIONS do
		local ok, deposit
		if location then
			ok, deposit = pcall(C_AuctionHouse.CalculateItemDeposit, location, duration, qty)
		end
		if not (ok and deposit) then
			ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit, itemID, duration, qty)
		end
		if not (ok and type(deposit) == "number") then return end
		list[duration] = money(deposit)
	end
	return list
end

-- What the price line calls the price: "TSM Market Value" or "Auctionator".
local function sourceName(from)
	if from == "auctionator" then return "Auctionator" end
	return "TSM " .. (TSM_NAMES[ns.db.saleSource] or ns.db.saleSource)
end

local function onItem(tooltip, data)
	local db = ns.db
	if not db or not C_AuctionHouse then return end
	if not (db.tipVendorBuy or db.tipVendorSell or db.tipAuction or db.tipDeposit) then return end
	local itemID = data and data.id
	if type(itemID) ~= "number" or (issecretvalue and issecretvalue(itemID)) then return end
	local location = locationOf(data)
	-- The auction lines only for items you can post.
	local postable = not unsellable(itemID, location)
	local _, link = TooltipUtil.GetDisplayedItem(tooltip)
	if link and issecretvalue and issecretvalue(link) then link = nil end
	local qty = location and C_Item.GetStackCount(location) or 1
	local stack = qty > 1 and format(" (x%d)", qty) or ""

	-- What a vendor charges for one (nil when no vendor sells it, or nobody knows),
	-- and what a vendor pays for one (nil when a vendor won't buy it).
	local vendorBuy = db.tipVendorBuy and ns.Prices.Vendor(itemID) or nil
	local vendorSell = db.tipVendorSell and select(11, C_Item.GetItemInfo(itemID)) or nil
	if vendorSell and vendorSell <= 0 then vendorSell = nil end
	-- Saved TSM prices already have their own line (Show saved TSM prices).
	local price, from
	if postable and db.tipAuction then price, from = ns.Prices.SaleFrom(link or ("item:" .. itemID), itemID) end
	if from == "saved" then price = nil end
	local list = postable and db.tipDeposit and deposits(itemID, location, qty) or nil
	if not (vendorBuy or vendorSell or price or list) then return end

	tooltip:AddLine(" ")
	if vendorBuy then tooltip:AddDoubleLine("Vendor Buy", money(vendorBuy), 1, 0.82, 0, 1, 1, 1) end
	if vendorSell then tooltip:AddDoubleLine("Vendor Sell", money(vendorSell), 1, 0.82, 0, 1, 1, 1) end
	if price then
		tooltip:AddDoubleLine(sourceName(from), money(price), 1, 0.82, 0, 1, 1, 1)
		if qty > 1 then tooltip:AddDoubleLine("  For" .. stack, money(price * qty), 0.53, 0.53, 0.53, 1, 1, 1) end
	end
	if list then
		tooltip:AddDoubleLine("AH Deposit " .. table.concat(DURATIONS, " / ") .. stack, table.concat(list, " / "),
			1, 0.82, 0, 1, 1, 1)
	end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
