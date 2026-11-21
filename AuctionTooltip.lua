-- Craftonomics: item tooltips show what a vendor charges and pays for the item,
-- what it sells for with the price you picked (TSM's price type, or Auctionator),
-- TSM's sale rate and trend, its lowest auction against its market value (with a
-- Cheap or Expensive hint), and the auction house deposit for posting it, so you can tell
-- whether it's worth putting up. A material also shows the best craft you can
-- make with it. Each line has its own option.
local _, ns = ...

local format = string.format

-- The auction durations, by the game's number for them: Retail's, or WoW Forever's.
local DURATIONS = ns.QUALITY_CRAFTING and { "12h", "24h", "48h" } or { "2h", "8h", "24h" }

-- TSM's price types, as the tooltip names them.
local TSM_NAMES = {
	dbmarket = "Market Value",
	dbminbuyout = "Lowest Auction",
	[ns.TSM_LOWER] = "Lower of Market and Lowest",
	dbhistorical = "Historical Price",
	dbregionmarketavg = "Region Market Average",
}

-- Items that can't go on the auction house: bound when picked up, quest items,
-- bound to your account.
local UNSELLABLE_BINDS = { [1] = true, [4] = true, [7] = true, [8] = true }

local function money(copper)
	return GetMoneyString(math.floor(copper + 0.5), true)
end

-- Whether the game takes `location` as an item that's there. The game can hand
-- back a location it then refuses even to check, so a refusal counts as no.
local function exists(location)
	return location:IsValid() and C_Item.DoesItemExist(location)
end

-- Where a tooltip's item sits in your bags or bank, or nil (a link, a vendor's item...).
local function locationOf(data)
	local guid = data and data.guid
	if not guid or (issecretvalue and issecretvalue(guid)) or not C_Item.GetItemLocation then return end
	local ok, location = pcall(C_Item.GetItemLocation, guid)
	if not (ok and location) then return end
	local found, there = pcall(exists, location)
	if found and there then return location end
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
	if from == "own" then return "Craftonomics scan" end
	return "TSM " .. (TSM_NAMES[ns.db.saleSource] or ns.db.saleSource)
end

-- Profession icons found so far: professionID -> icon, or false for none.
local professionIcons = {}

-- A profession's icon, or nil when the game doesn't say. The number can be the
-- profession's own (Engineering) or one of its parts' (an expansion's), which
-- has its parent's icon. Failing that, it's looked up among your professions.
local function professionIcon(professionID)
	if not professionID then return end
	local icon = professionIcons[professionID]
	if icon ~= nil then return icon or nil end
	local texture, info = C_TradeSkillUI.GetTradeSkillTexture, C_TradeSkillUI.GetProfessionInfoBySkillLineID
	local ok, found = pcall(texture or error, professionID)
	icon = ok and found or nil
	local okInfo, part = pcall(info or error, professionID)
	local parent = okInfo and part and part.parentProfessionID
	if not icon and parent and parent > 0 then
		ok, found = pcall(texture or error, parent)
		icon = ok and found or nil
	end
	if not icon and GetProfessions and GetProfessionInfo then
		for _, index in ipairs({ GetProfessions() }) do
			local _, mine, _, _, _, _, skillLine = GetProfessionInfo(index)
			if skillLine == professionID or (parent and skillLine == parent) then icon = mine end
		end
	end
	professionIcons[professionID] = icon or false
	return icon
end

local function onItem(tooltip, data)
	local db = ns.db
	if not db or not C_AuctionHouse then return end
	if not (db.tipVendorBuy or db.tipVendorSell or db.tipAuction or db.tipDeposit or db.tipSaleRate or db.tipTrend
		or db.tipLowest or db.tipBestCraft) then
		return
	end
	local itemID = data and data.id
	if type(itemID) ~= "number" or (issecretvalue and issecretvalue(itemID)) then return end
	local location = locationOf(data)
	-- The auction lines only for items you can post.
	local postable = not unsellable(itemID, location)
	local _, link = TooltipUtil.GetDisplayedItem(tooltip)
	if link and issecretvalue and issecretvalue(link) then link = nil end
	-- A recipe's tooltip also shows the item it makes, and on a vendor the game can
	-- hand back that item's link instead of the recipe's: price the recipe itself.
	if link and C_Item.GetItemInfoInstant(link) ~= itemID then link = nil end
	local count = location and C_Item.GetStackCount(location) or 1
	-- A stack in your bags shows the whole stack's amounts only while Shift is held.
	-- Nothing here redraws the tooltip when Shift changes: the game redraws a bag
	-- item's tooltip several times a second by itself. Redrawing it from addon code
	-- (tooltip:RefreshData()) was taken out in case it's what blocked using an item
	-- from the bags ("tried to call the protected function" on a right-click).
	local qty = (count > 1 and IsShiftKeyDown()) and count or 1
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
	-- The share of its auctions that sell, from TSM (nil without TSM).
	local rate = postable and db.tipSaleRate and ns.Prices.SaleRate(link or ("item:" .. itemID)) or nil
	-- How far its market value is from its historical price, from TSM (nil without TSM).
	local trend
	if postable and db.tipTrend then trend = ns.Prices.Trend(link or ("item:" .. itemID)) end
	-- How far its lowest auction is from its market value, from TSM (nil without
	-- TSM, or with no auction up).
	local lowest
	if postable and db.tipLowest then lowest = ns.Prices.LowestVsMarket(link or ("item:" .. itemID)) end
	-- For a material: the most profitable recipe this character knows that takes it.
	-- Only when it makes gold: the best of recipes that all lose it is nothing to craft.
	local best = db.tipBestCraft and ns.BestCrafts.BestWith(itemID) or nil
	if best and (best.profit <= 0 or best.score <= 0) then best = nil end
	if not (vendorBuy or vendorSell or price or list or rate or trend or lowest or best) then return end

	tooltip:AddLine(" ")
	if vendorBuy then tooltip:AddDoubleLine("Vendor Buy", money(vendorBuy), 1, 0.82, 0, 1, 1, 1) end
	if vendorSell then
		tooltip:AddDoubleLine("Vendor Sell", money(vendorSell), 1, 0.82, 0, 1, 1, 1)
		if qty > 1 then tooltip:AddDoubleLine("  For" .. stack, money(vendorSell * qty), 0.53, 0.53, 0.53, 1, 1, 1) end
	end
	if price then
		tooltip:AddDoubleLine(sourceName(from), money(price), 1, 0.82, 0, 1, 1, 1)
		if qty > 1 then tooltip:AddDoubleLine("  For" .. stack, money(price * qty), 0.53, 0.53, 0.53, 1, 1, 1) end
	end
	if rate then tooltip:AddDoubleLine("TSM Sale Rate", ns.Format.SaleRate(rate), 1, 0.82, 0, 1, 1, 1) end
	if trend then tooltip:AddDoubleLine("TSM Trend", ns.Format.Trend(trend), 1, 0.82, 0, 1, 1, 1) end
	if lowest then
		tooltip:AddDoubleLine("TSM Lowest vs Market", ns.Format.LowestVsMarket(lowest), 1, 0.82, 0, 1, 1, 1)
	end
	if list then
		tooltip:AddDoubleLine("AH Deposit " .. table.concat(DURATIONS, " / ") .. stack, table.concat(list, " / "),
			1, 0.82, 0, 1, 1, 1)
	end
	if best then
		-- What one craft of the last recipe in the chain makes.
		tooltip:AddDoubleLine("Best Craft", ns.Color("profit", "+" .. money(best.profit)), 1, 0.82, 0, 1, 1, 1)
		-- Under it, the chain of crafts that gets there, each set in further than the
		-- one before: its profession's icon and what it makes (by the item's own
		-- name once the game has it).
		for index, step in ipairs(best.steps) do
			local name = step.itemID and ns.Format.ItemName(step.itemID)
			name = name and ns.Format.RarityColored(step.itemID, name) or step.name
			local icon = professionIcon(step.professionID)
			tooltip:AddLine(string.rep("  ", index) .. (icon and format("|T%s:0|t ", icon) or "") .. name, 1, 1, 1)
		end
		-- With TSM: how well what it makes sells. Always, never, or while Shift is held.
		local shown = db.tipBestRate == "always" or (db.tipBestRate ~= "never" and IsShiftKeyDown())
		if best.saleRate and shown then
			tooltip:AddDoubleLine("  TSM Sale Rate", ns.Format.SaleRate(best.saleRate), 0.53, 0.53, 0.53, 1, 1, 1)
		end
	end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
