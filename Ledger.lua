-- Craft Profit: the ledger's records. What you crafted, sold, posted and used up,
-- kept packed as text so a long history stays small in the saved variables, and
-- only unpacked while the Ledger window is open. Which sale paid for which craft
-- isn't kept: Ledger.Analyze works that out each time, oldest craft first.
local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

local format = string.format

local KEEP_DAYS = 90       -- days kept in full; older ones are rolled up by month
local DAY = 86400
local SEP = "\t"
local PRICE_SLACK = 1      -- copper a sale's price may differ from what was posted
local CRAFT_SLACK = 3600   -- seconds a sale may seem to come before its craft (a mail's time is rough)
local MONEY_FLOOR = 1      -- rounding of the amounts saved, in copper

-- Kinds of craft. "craft" sells later; an order counts as sold, for what it paid,
-- when it's done.
Ledger.KINDS = {
	craft = "Regular crafts",
	patron = "Patron orders",
	personal = "Personal orders",
	guild = "Guild orders",
	public = "Public orders",
}
Ledger.KIND_ORDER = { "craft", "patron", "personal", "guild", "public" }

-- CraftProfitDB.ledger = {
--   names = { "Name-Realm" or "Tailoring" ... }, shared by the records below,
--   items = itemID -> name, of what you've crafted,
--   days = day number -> { crafts, sales, posts, used }, each a string of lines:
--     crafts: time, character, profession, recipeID, itemID, rank, qty, kind,
--             value of one item then, materials cost, forecast profit with average
--             procs, profit at craft, forecast profit without procs, what procs really
--             added (older crafts stop at profit at craft), 1 when the materials
--             cost isn't known (crafted with the panel on something else)
--     sales:  time, character, item name, qty, gold after the cut, price of one
--     posts:  time, character, itemID, rank, qty, price of one, item name
--     used:   time, itemID, qty (your own crafts used up as materials), 1 when the
--             craft they went into counted them at what they cost to make
--     bought: time, character, itemID, rank, qty, gold spent, market price of one
--             then, "auction" or "vendor", item name
--   months = "2026-10" -> { crafts, items, cost, profit, spent }, for days past KEEP_DAYS,
--   seeded = the sales from before the ledger are in,
-- }
local saved
local demo -- made-up records in place of saved, for testing (see Ledger.ToggleDemo)
local nameIndex = {} -- name -> its place in saved.names
local onChange = nop

function Ledger.Watch(changed)
	onChange = changed
end

---------------------------------------------------------------------------
-- Packing
---------------------------------------------------------------------------

local function split(line)
	local parts, count, start = {}, 0, 1
	while true do
		local stop = line:find(SEP, start, true)
		count = count + 1
		parts[count] = line:sub(start, stop and stop - 1 or -1)
		if not stop then return parts end
		start = stop + 1
	end
end

local function whole(amount)
	return math.floor((amount or 0) / MONEY_FLOOR + 0.5) * MONEY_FLOOR
end

local function dayOf(t)
	return math.floor(t / DAY)
end

-- A name's place in saved.names, adding it the first time.
local function indexOf(name)
	name = name or "?"
	local index = nameIndex[name]
	if not index then
		index = #saved.names + 1
		saved.names[index] = name
		nameIndex[name] = index
	end
	return index
end

local function append(list, t, ...)
	local day = saved.days[dayOf(t)]
	if not day then
		day = {}
		saved.days[dayOf(t)] = day
	end
	local fields = { t, ... }
	for i = 1, select("#", ...) + 1 do fields[i] = tostring(fields[i]) end
	day[list] = (day[list] or "") .. table.concat(fields, SEP) .. "\n"
end

-- Calls fn with the fields of each line of `text`.
local function eachLine(text, fn)
	if not text then return end
	for line in text:gmatch("[^\n]+") do fn(split(line)) end
end

local function parseCraft(names, fields)
	local character, profession = tonumber(fields[2]), tonumber(fields[3])
	local itemID = tonumber(fields[5])
	local recipeID, cost = tonumber(fields[4]), tonumber(fields[10])
	-- Before this was saved, a craft with no recipe had no panel to take a cost from.
	local noCost = fields[15] == "1" or (fields[15] == nil and recipeID == 0 and itemID > 0 and cost == 0)
	return {
		t = tonumber(fields[1]), character = names[character], profession = names[profession],
		recipeID = recipeID, itemID = itemID > 0 and itemID or nil, rank = tonumber(fields[6]),
		qty = tonumber(fields[7]), kind = fields[8], unit = tonumber(fields[9]), cost = cost,
		forecast = tonumber(fields[11]), profit = tonumber(fields[12]),
		plain = tonumber(fields[13]), bonus = tonumber(fields[14]), noCost = noCost or nil,
	}
end

local function parseBought(names, fields)
	return { t = tonumber(fields[1]), character = names[tonumber(fields[2])], itemID = tonumber(fields[3]),
		rank = tonumber(fields[4]), qty = tonumber(fields[5]), spent = tonumber(fields[6]), market = tonumber(fields[7]),
		source = fields[8], name = fields[9] }
end

-- Everything in the saved days, unpacked and oldest first: crafts, sales, posts,
-- used, bought.
function Ledger.Unpack(db)
	local crafts, sales, posts, used, bought = {}, {}, {}, {}, {}
	local names = db.names
	for _, day in pairs(db.days) do
		eachLine(day.crafts, function(fields)
			local craft = parseCraft(names, fields)
			-- Older records hold imbues and poisons, which aren't crafts (see RecordCraft).
			if craft.itemID or craft.recipeID > 0 then crafts[#crafts + 1] = craft end
		end)
		eachLine(day.sales, function(fields)
			sales[#sales + 1] = { t = tonumber(fields[1]), character = names[tonumber(fields[2])], name = fields[3],
				qty = tonumber(fields[4]), money = tonumber(fields[5]), unit = tonumber(fields[6]) }
		end)
		eachLine(day.posts, function(fields)
			posts[#posts + 1] = { t = tonumber(fields[1]), character = names[tonumber(fields[2])], itemID = tonumber(fields[3]),
				rank = tonumber(fields[4]), qty = tonumber(fields[5]), unit = tonumber(fields[6]), name = fields[7] }
		end)
		eachLine(day.used, function(fields)
			used[#used + 1] = { t = tonumber(fields[1]), itemID = tonumber(fields[2]), qty = tonumber(fields[3]),
				atCost = fields[4] == "1" }
		end)
		eachLine(day.bought, function(fields) bought[#bought + 1] = parseBought(names, fields) end)
	end
	local function byTime(a, b) return a.t < b.t end
	table.sort(crafts, byTime)
	table.sort(sales, byTime)
	table.sort(posts, byTime)
	table.sort(used, byTime)
	table.sort(bought, byTime)
	return crafts, sales, posts, used, bought
end

---------------------------------------------------------------------------
-- Working out what sold
---------------------------------------------------------------------------

-- Where to start looking in `list` (oldest first): past the ones at its start with
-- nothing left, which stay that way. Kept on the list, so a long history isn't
-- gone through from the top for every sale.
local function firstLeft(list)
	local first = list.first or 1
	while list[first] and list[first].left <= 0 do first = first + 1 end
	list.first = first
	return first
end

-- Takes up to `qty` from the oldest crafts in `list` made by time `t` that still
-- have some left, of `rank` when it's known. take(craft, amount) does the rest.
-- Returns how many it couldn't place.
local function fromOldest(list, t, rank, qty, take)
	if not list then return qty end
	for index = firstLeft(list), #list do
		local craft = list[index]
		if qty <= 0 or craft.t > t then break end
		if craft.left > 0 and (not rank or rank == 0 or craft.rank == rank) then
			local amount = math.min(craft.left, qty)
			craft.left = craft.left - amount
			qty = qty - amount
			take(craft, amount)
		end
	end
	return qty
end

-- The post a sale came from: the same item name and price, posted before it, with
-- some left. Mails only name the item, so this is what says which rank sold.
local function findPost(posts, sale)
	for index = firstLeft(posts), #posts do
		local post = posts[index]
		if post.t > sale.t then return end
		if post.left > 0 and post.name == sale.name and math.abs(post.unit - sale.unit) <= PRICE_SLACK then
			return post
		end
	end
end

-- Spreads sales and materials used over the crafts, oldest first. Each regular
-- craft with an item gets left, sold, money (after the cut), used and soldDays.
-- A sale no craft accounts for counts toward what you bought of it (resold and
-- resoldMoney on each purchase). Returns the crafts, oldest first, what sold with
-- neither on record ({ qty, money }), and the purchases, oldest first.
function Ledger.Analyze(db)
	local crafts, sales, posts, used, bought = Ledger.Unpack(db)
	local byItem, byName, boughtByName = {}, {}, {}
	for _, entry in ipairs(bought) do
		entry.left, entry.resold, entry.resoldMoney = entry.qty, 0, 0
		local list = boughtByName[entry.name]
		if not list then
			list = {}
			boughtByName[entry.name] = list
		end
		list[#list + 1] = entry
	end
	for _, craft in ipairs(crafts) do
		craft.left, craft.sold, craft.money, craft.used, craft.soldDays = 0, 0, 0, 0, 0
		craft.usedAtCost = 0
		if craft.kind == "craft" and craft.itemID then
			craft.left = craft.qty
			local list = byItem[craft.itemID]
			if not list then
				list = {}
				byItem[craft.itemID] = list
			end
			list[#list + 1] = craft
			local name = db.items[craft.itemID]
			if name then
				local named = byName[name]
				if not named then
					named = {}
					byName[name] = named
				end
				named[#named + 1] = craft
			end
		end
	end
	for _, post in ipairs(posts) do post.left = post.qty end

	-- In time order, so what was used up and what sold take from the same crafts.
	local events = {}
	for _, sale in ipairs(sales) do events[#events + 1] = sale end
	for _, entry in ipairs(used) do
		entry.isUsed = true
		events[#events + 1] = entry
	end
	table.sort(events, function(a, b) return a.t < b.t end)

	local other = { qty = 0, money = 0 }
	for _, event in ipairs(events) do
		if event.isUsed then
			fromOldest(byItem[event.itemID], event.t, nil, event.qty, function(craft, amount)
				craft.used = craft.used + amount
				if event.atCost then craft.usedAtCost = craft.usedAtCost + amount end
			end)
		else
			local post = findPost(posts, event)
			local list, rank = byName[event.name], nil
			if post then
				post.left = math.max(post.left - event.qty, 0)
				list, rank = byItem[post.itemID] or list, post.rank
			end
			local each = event.money / event.qty
			-- A mail's time is rough, so a sale may seem to come a little before its craft.
			local by = event.t + CRAFT_SLACK
			local unplaced = fromOldest(list, by, rank, event.qty, function(craft, amount)
				craft.sold = craft.sold + amount
				craft.money = craft.money + each * amount
				craft.soldDays = craft.soldDays + amount * math.max(event.t - craft.t, 0) / DAY
			end)
			unplaced = fromOldest(boughtByName[event.name], by, rank, unplaced, function(entry, amount)
				entry.resold = entry.resold + amount
				entry.resoldMoney = entry.resoldMoney + each * amount
			end)
			other.qty = other.qty + unplaced
			other.money = other.money + each * unplaced
		end
	end

	-- What's known so far of each craft. Procs are luck, so the forecast leaves them
	-- out and so does what it's compared with. Older crafts only have the forecast
	-- with procs, and hasProcs false.
	for _, craft in ipairs(crafts) do
		craft.hasProcs = craft.plain ~= nil
		local forecast, bonus = craft.plain or craft.forecast, craft.bonus or 0
		if craft.kind == "craft" and craft.itemID then
			local share = craft.cost / craft.qty
			local done = craft.sold + craft.used
			craft.pending = craft.left * craft.unit
			if craft.noCost then
				-- What it sold for is known, what it cost isn't: no profit to show.
				craft.earned, craft.expected, craft.procGain = 0, 0, 0
			else
				-- Used in another craft counts as sold to it. For what it was worth then, when
				-- that craft's cost counted it at that; when it counted it at what it cost
				-- to make, the gain is all in that craft's profit and there's none here.
				local worth = craft.used - craft.usedAtCost
				craft.earned = craft.money + (craft.unit - share) * worth - share * craft.sold
				local priced = craft.unit > 0 and (craft.unit - share) * craft.qty or 0
				craft.expected = forecast ~= 0 and forecast or priced
				craft.procGain = bonus * done / craft.qty
				-- Compared with what the panel said, so only when it was open, and only
				-- what was sold or used for what it was worth.
				local compared = craft.sold + worth
				if forecast ~= 0 and compared > 0 then
					craft.compareActual = craft.earned - craft.procGain
					craft.compareForecast = forecast * compared / craft.qty
				end
			end
		else
			craft.earned = craft.profit
			craft.pending = 0
			craft.expected = forecast
			craft.procGain = bonus
			if forecast ~= 0 then
				craft.compareActual, craft.compareForecast = craft.profit - bonus, forecast
			end
			if craft.kind ~= "craft" then
				craft.sold = craft.qty
				craft.money = craft.profit + craft.cost
				if forecast ~= 0 then craft.unit = (forecast + math.max(craft.cost + bonus, 0)) / craft.qty end
			end
		end
		-- What resourcefulness returns can beat what you put in: a gain, already in
		-- the profit, not negative spending.
		craft.cost = math.max(craft.cost, 0)
	end
	return crafts, other, bought
end

-- One row per item and rank in `bought`: { itemID, rank, name, source, qty, spent,
-- unitPaid, unitMarket and vsMarket (against the market price, where there was
-- one), resold, resoldMoney, resaleProfit }.
function Ledger.BoughtItems(bought)
	local groups, list = {}, {}
	for _, entry in ipairs(bought) do
		local key = format("%d:%d", entry.itemID, entry.rank)
		local group = groups[key]
		if not group then
			group = { itemID = entry.itemID, rank = entry.rank, name = entry.name, source = entry.source, qty = 0, spent = 0,
				resold = 0, resoldMoney = 0, resoldCost = 0, marketQty = 0, marketPaid = 0, marketWorth = 0 }
			groups[key] = group
			list[#list + 1] = group
		end
		group.qty = group.qty + entry.qty
		group.spent = group.spent + entry.spent
		group.resold = group.resold + entry.resold
		group.resoldMoney = group.resoldMoney + entry.resoldMoney
		group.resoldCost = group.resoldCost + entry.spent / entry.qty * entry.resold
		if entry.market > 0 then
			group.marketQty = group.marketQty + entry.qty
			group.marketPaid = group.marketPaid + entry.spent
			group.marketWorth = group.marketWorth + entry.market * entry.qty
		end
	end
	for _, group in ipairs(list) do
		group.unitPaid = group.spent / group.qty
		if group.marketWorth > 0 then
			group.unitMarket = group.marketWorth / group.marketQty
			group.vsMarket = (group.marketPaid - group.marketWorth) / group.marketWorth
		end
		if group.resold > 0 then group.resaleProfit = group.resoldMoney - group.resoldCost end
	end
	return list
end

-- Totals for a list of crafts: { crafts, items, cost, earned, pending, unsold,
-- sold, money, expected, procs, actual, forecast, unknown }. Expected is the profit
-- forecast for all of them, procs what they really added; actual and forecast only
-- count what's done, without procs, so they can be compared. Unknown is how many
-- have no materials cost on record, and so no profit.
function Ledger.Summarize(crafts)
	local total = { crafts = 0, items = 0, cost = 0, earned = 0, pending = 0, unsold = 0, sold = 0, money = 0,
		expected = 0, procs = 0, actual = 0, forecast = 0, unknown = 0, used = 0 }
	for _, craft in ipairs(crafts) do
		total.crafts = total.crafts + 1
		total.used = total.used + craft.used
		if craft.noCost then total.unknown = total.unknown + 1 end
		total.items = total.items + craft.qty
		total.cost = total.cost + craft.cost
		total.earned = total.earned + craft.earned
		total.pending = total.pending + craft.pending
		total.unsold = total.unsold + craft.left
		total.sold = total.sold + craft.sold
		total.money = total.money + craft.money
		total.expected = total.expected + craft.expected
		total.procs = total.procs + craft.procGain
		if craft.compareForecast then
			total.actual = total.actual + craft.compareActual
			total.forecast = total.forecast + craft.compareForecast
		end
	end
	return total
end

-- How far a total landed from its forecast, as a share (-0.09 is 9% under). Nil
-- with nothing to compare.
function Ledger.Off(total)
	if total.forecast == 0 then return end
	return (total.actual - total.forecast) / math.abs(total.forecast)
end

-- `crafts` with the ones in the same minute merged into one, when they're the same
-- item and rank, by the same character, of the same type. `count` says how many
-- each stands for, and `unit` is their average.
function Ledger.Merge(crafts)
	local merged, list = {}, {}
	for _, craft in ipairs(crafts) do
		local key = format("%d:%s:%d:%d:%s:%s:%s", math.floor(craft.t / 60), tostring(craft.itemID), craft.recipeID, craft.rank,
			tostring(craft.character), craft.kind, tostring(craft.noCost))
		local row = merged[key]
		if not row then
			row = {}
			for field, value in pairs(craft) do row[field] = value end
			row.count, row.unit = 1, craft.unit * craft.qty
			merged[key] = row
			list[#list + 1] = row
		else
			row.count = row.count + 1
			row.unit = row.unit + craft.unit * craft.qty
			for _, field in ipairs({ "qty", "cost", "forecast", "profit", "left", "sold", "money", "used", "usedAtCost", "soldDays", "earned", "pending",
				"expected", "procGain" }) do
				row[field] = (row[field] or 0) + (craft[field] or 0)
			end
		end
	end
	for _, row in ipairs(list) do row.unit = row.unit / row.qty end
	return list
end

-- One row per item, rank and kind of craft in `crafts`, since a patron order and a
-- personal one for the same item pay nothing alike: { itemID, rank, kind, recipeID,
-- counts as Summarize, plus, per item, unitForecast, unitProcs and unitProfit (of
-- what's done; unitProcs only from crafts that saved it),
-- unitPrice (the sale price or an order's pay expected), unitCost and unitSold, days
-- (to sell, for regular crafts), and margin (the share of what sold that was profit,
-- 0.26 is 26%) }.
function Ledger.Items(crafts)
	local groups, list = {}, {}
	for _, craft in ipairs(crafts) do
		if craft.itemID then
			local key = format("%d:%d:%s", craft.itemID, craft.rank, craft.kind)
			local group = groups[key]
			if not group then
				group = { itemID = craft.itemID, rank = craft.rank, kind = craft.kind, recipeID = craft.recipeID, made = {} }
				groups[key] = group
				list[#list + 1] = group
			end
			group.made[#group.made + 1] = craft
		end
	end
	for _, group in ipairs(list) do
		local total = Ledger.Summarize(group.made)
		for key, value in pairs(total) do group[key] = value end
		local soldForecast, soldDays, madeForecast, priced, soldCost, listed, done = 0, 0, 0, 0, 0, 0, 0
		local procsDone, procsGain = 0, 0
		-- Only crafts with a cost on record count toward cost, profit and margin.
		local costed, costedMoney = 0, 0
		for _, craft in ipairs(group.made) do
			soldForecast = soldForecast + craft.unit * craft.sold
			if not craft.noCost then
				soldCost = soldCost + craft.cost / craft.qty * craft.sold
				-- What was used at its cost made nothing here, so it isn't in the average.
				done = done + craft.sold + craft.used - craft.usedAtCost
				costed = costed + craft.qty
				costedMoney = costedMoney + craft.money
			end
			if craft.hasProcs and not craft.noCost then
				procsDone = procsDone + craft.sold + craft.used
				procsGain = procsGain + craft.procGain
			end
			soldDays = soldDays + craft.soldDays
			if craft.kind == "craft" then listed = listed + craft.sold end
			if craft.unit > 0 then
				madeForecast = madeForecast + craft.unit * craft.qty
				priced = priced + craft.qty
			end
		end
		-- What sold is what to compare with, once anything has.
		if priced > 0 then group.unitPrice = madeForecast / priced end
		if total.expected ~= 0 and costed > 0 then group.unitForecast = total.expected / costed end
		if done > 0 then group.unitProfit = total.earned / done end
		if procsDone > 0 then group.unitProcs = procsGain / procsDone end
		if costed > 0 then group.unitCost = total.cost / costed end
		if listed > 0 then group.days = soldDays / listed end
		if total.sold > 0 then
			group.unitSold = total.money / total.sold
			group.unitPrice = soldForecast / total.sold
			if costedMoney > 0 then group.margin = (costedMoney - soldCost) / costedMoney end
		end
		group.made = nil
	end
	return list
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local function me()
	local _, key = ns.Ranks.Me()
	return key or format("%s-%s", UnitName("player") or "?", GetNormalizedRealmName() or "?")
end

-- The rank in an item's link, or `fallback`: crafted items carry it in the link,
-- ranked materials are a separate item each.
local function rankOf(link, fallback)
	local ok, rank = pcall(C_TradeSkillUI.GetItemCraftedQualityByItemInfo, link)
	if ok and rank and rank > 0 then return rank end
	ok, rank = pcall(C_TradeSkillUI.GetItemReagentQualityByItemInfo, link)
	if ok and rank and rank > 0 then return rank end
	return fallback or 0
end

-- The item's name in a link, without the rank's icon.
local function nameIn(link)
	local name = link and link:match("%[(.-)%]")
	return name and strtrim((name:gsub("|A.-|a", "")))
end

local function kindOf(model)
	if not model or model.kind ~= "order" then return "craft" end
	local types = Enum.CraftingOrderType
	if model.orderType == types.Npc then return "patron" end
	if model.orderType == types.Personal then return "personal" end
	if model.orderType == types.Guild then return "guild" end
	return "public"
end

-- The kind of a craft with no model, from how it was started (see Results.lua).
local function kindStarted(started)
	if not (started and started.orderID and C_CraftingOrders) then return "craft" end
	local order = C_CraftingOrders.GetClaimedOrder()
	return kindOf({ kind = "order", orderType = order and order.orderType })
end

-- A craft that just finished: the game's result, the model on screen and what
-- Results worked out. With the panel hidden or on another recipe there's no model:
-- no forecast and no materials cost, and `started` says what's known of the craft.
function Ledger.RecordCraft(data, model, result, started)
	if not saved then return end
	local t = time()
	local link = data.hyperlink ~= "" and data.hyperlink or nil
	local itemID = data.itemID
	-- An enchant on a vellum makes the scroll the panel priced.
	if data.isEnchant then
		link = model and model.output and model.output.link
		itemID = link and C_Item.GetItemInfoInstant(link)
	end
	-- A recraft, or a recipe that makes nothing to sell.
	if model and model.kind == "craft" and not model.output then link = nil end
	if not link then itemID = nil end
	-- A shaman's imbue or a rogue's poison reports as an enchant, with no recipe open.
	if not (itemID or model) then return end
	local kind = model and kindOf(model) or kindStarted(started)
	local qty = math.max(data.quantity or 1, 1)
	local unit = result and result.unit
	if not unit and link and kind == "craft" then
		local price = ns.Prices.Sale(link, itemID)
		unit = price and (ns.db.ahCut and price * (1 - ns.AH_CUT) or price)
	end
	local cost = model and (model.realCost or 0) - (result and result.savedValue or 0) or 0
	local actual = result and result.actual or 0
	local recipeID = model and model.recipeID or (started and started.recipeID) or 0
	local profession = recipeID > 0 and C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	if itemID then saved.items[itemID] = saved.items[itemID] or nameIn(link) end

	append("crafts", t, indexOf(me()), indexOf(profession and profession.professionName), recipeID, itemID or 0,
		rankOf(link, data.craftingQuality), qty, kind, whole(unit), whole(cost),
		whole(model and ns.Model.Shown(model)), whole(actual), whole(model and model.total), whole(result and result.bonus),
		model and 0 or 1)

	-- Your own crafts used as materials aren't waiting to sell.
	local returned = {}
	for _, entry in ipairs(data.resourcesReturned or {}) do
		local id = entry.reagent and entry.reagent.itemID
		if id then returned[id] = (returned[id] or 0) + (entry.quantity or 0) end
	end
	for _, material in ipairs(model and model.materials or {}) do
		if saved.items[material.itemID] then
			local spent = material.qty - (returned[material.itemID] or 0)
			-- With Craft myself, this craft's cost counted it at what it costs to make.
			local atCost = ns.Chains.Active() and ns.Chains.CraftCost(material.itemID) ~= nil
			if spent > 0 then append("used", t, material.itemID, spent, atCost and 1 or 0) end
		end
	end
	onChange()
end

-- A sale from the mailbox (see Sales.lua).
function Ledger.RecordSale(sale)
	if not saved or (sale.qty or 0) <= 0 then return end
	local keep = ns.db.ahCut and (1 - ns.AH_CUT) or 1
	append("sales", sale.t, indexOf(me()), sale.name, sale.qty, whole(sale.net or sale.money * keep),
		whole(sale.money / sale.qty))
	onChange()
end

-- Something you put on the auction house. Only your own crafts matter.
local function recordPost(location, qty, unit)
	if not (saved and location and unit and (qty or 0) > 0) then return end
	local ok, link = pcall(C_Item.GetItemLink, location)
	if not (ok and link) then return end
	local itemID = C_Item.GetItemInfoInstant(link)
	if not (itemID and saved.items[itemID]) then return end
	append("posts", time(), indexOf(me()), itemID, rankOf(link), qty, whole(unit), nameIn(link) or saved.items[itemID])
end

-- Something you bought. `spent` is the gold it took; nil leaves it out.
local function recordBought(itemID, link, qty, spent, source)
	if not (saved and itemID and spent and spent > 0 and (qty or 0) > 0) then return end
	append("bought", time(), indexOf(me()), itemID, rankOf(link or itemID), qty, whole(spent),
		whole(ns.Prices.Buy(itemID)), source, nameIn(link) or C_Item.GetItemNameByID(itemID) or "?")
	onChange()
end

-- The commodity purchase under way: { itemID, qty, total }. The game names the
-- price in between starting it and confirming it.
local commodity
-- Single items you bid on: auctionID -> { link, itemID, amount }, until they're won.
local bids = {}

local function watchPurchases(events)
	if not C_AuctionHouse then return end
	hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function(itemID, qty)
		commodity = { itemID = itemID, qty = qty }
	end)
	hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, qty)
		if commodity and commodity.itemID == itemID then commodity.qty = qty end
	end)
	hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, amount)
		local ok, info = pcall(C_AuctionHouse.GetAuctionInfoByID, auctionID)
		local link = ok and info and info.itemLink
		local itemID = link and C_Item.GetItemInfoInstant(link) or (ok and info and info.itemKey and info.itemKey.itemID)
		if itemID then bids[auctionID] = { link = link, itemID = itemID, amount = amount } end
	end)
	events:RegisterEvent("COMMODITY_PRICE_UPDATED")
	events:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
	events:RegisterEvent("COMMODITY_PURCHASE_FAILED")
	events:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED")

	hooksecurefunc("BuyMerchantItem", function(index, qty)
		local info = C_MerchantFrame.GetItemInfo(index)
		local link = GetMerchantItemLink(index)
		if not (info and link) or info.hasExtendedCost or info.price <= 0 then return end
		-- Only materials: what a vendor sells otherwise has nothing to do with crafting.
		local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
		if classID ~= Enum.ItemClass.Tradegoods then return end
		local stack = math.max(info.stackCount, 1)
		qty = qty or stack
		recordBought(itemID, link, qty, info.price / stack * qty, "vendor")
	end)
end

local function onPurchaseEvent(event, ...)
	if event == "COMMODITY_PRICE_UPDATED" then
		local _, total = ...
		if commodity then commodity.total = total end
	elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
		if commodity then recordBought(commodity.itemID, nil, commodity.qty, commodity.total, "auction") end
		commodity = nil
	elseif event == "COMMODITY_PURCHASE_FAILED" then
		commodity = nil
	else
		local auctionID = ...
		local bid = bids[auctionID]
		if bid then recordBought(bid.itemID, bid.link, 1, bid.amount, "auction") end
		bids[auctionID] = nil
	end
end

local function watchPosts()
	if not C_AuctionHouse then return end
	hooksecurefunc(C_AuctionHouse, "PostItem", function(location, _, qty, bid, buyout)
		recordPost(location, qty, buyout or bid)
	end)
	hooksecurefunc(C_AuctionHouse, "PostCommodity", function(location, _, qty, unit)
		recordPost(location, qty, unit)
	end)
end

---------------------------------------------------------------------------
-- Keeping it small
---------------------------------------------------------------------------

-- Days past KEEP_DAYS become their month's totals; `now` is today's time. Profit is
-- what each craft had made by then: its sales go with it, so it's worked out first.
function Ledger.RollUp(db, now)
	local oldest = dayOf(now) - KEEP_DAYS
	local due = false
	for day in pairs(db.days) do
		if day < oldest then
			due = true
			break
		end
	end
	if not due then return end

	local function totalsOf(t)
		local month = date("%Y-%m", t)
		local totals = db.months[month]
		if not totals then
			totals = { crafts = 0, items = 0, cost = 0, profit = 0, spent = 0 }
			db.months[month] = totals
		end
		return totals
	end
	local crafts, _, bought = Ledger.Analyze(db)
	for _, craft in ipairs(crafts) do
		if dayOf(craft.t) < oldest then
			local totals = totalsOf(craft.t)
			totals.crafts = totals.crafts + 1
			totals.items = totals.items + craft.qty
			totals.cost = totals.cost + craft.cost
			totals.profit = totals.profit + whole(craft.earned)
		end
	end
	for _, entry in ipairs(bought) do
		if dayOf(entry.t) < oldest then
			local totals = totalsOf(entry.t)
			totals.spent = totals.spent + entry.spent
		end
	end
	for day in pairs(db.days) do
		if day < oldest then db.days[day] = nil end
	end
end

-- The months past KEEP_DAYS, newest first: { month ("2026-08"), crafts, items, cost,
-- profit, spent }.
function Ledger.Months()
	local records = demo or saved
	local list = {}
	for month, totals in pairs(records and records.months or {}) do
		list[#list + 1] = { month = month, crafts = totals.crafts, items = totals.items, cost = totals.cost,
			profit = totals.profit, spent = totals.spent }
	end
	table.sort(list, function(a, b) return a.month > b.month end)
	return list
end

-- Forgets every record, for all your characters. Sales from before stay out: seeded
-- stays set, so what the mailbox told us doesn't come back.
function Ledger.Clear()
	saved.names, saved.items, saved.days, saved.months = {}, {}, {}, {}
	wipe(nameIndex)
	onChange()
end

-- An item's name, from the game or from when you crafted it.
function Ledger.ItemName(itemID)
	local records = demo or saved
	return (records and records.items[itemID]) or C_Item.GetItemNameByID(itemID) or "?"
end

-- Everything for the Ledger window, unpacked (see Ledger.Analyze).
function Ledger.Load()
	if demo or saved then return Ledger.Analyze(demo or saved) end
	return {}, { qty = 0, money = 0 }, {}
end

-- Turns the made-up records on or off, and says which. Nothing of it is saved.
function Ledger.ToggleDemo()
	if demo then
		demo = nil
		return false
	end
	local names = { "Demo-Realm", "Demoalt-Realm", "Tailoring", "Alchemy" }
	local items = {
		{ 2996, "Bolt of Linen Cloth", 3, 500000, 2500000, 60 }, -- itemID, name, profession, worth, cost, how often it sells
		{ 2997, "Bolt of Woolen Cloth", 3, 1200000, 900000, 95 },
		{ 118, "Minor Healing Potion", 4, 300000, 1200000, 30 },
	}
	demo = { names = names, items = {}, days = {}, months = {} }
	local now = time()
	local function add(t, list, ...)
		local day = demo.days[dayOf(t)] or {}
		demo.days[dayOf(t)] = day
		day[list] = (day[list] or "") .. table.concat({ t, ... }, SEP) .. "\n"
	end
	for back = 1, 40 do
		local t = now - back * DAY
		for index, item in ipairs(items) do
			demo.items[item[1]] = item[2]
			local qty = 10
			add(t, "crafts", index % 2 + 1, item[3], 0, item[1], 0, qty, "craft", item[4], item[5],
				item[4] * qty - item[5], item[4] * qty - item[5])
			-- Sells later, for a bit less the more often it sells.
			if back > 2 and (back * 10 + index * 7) % 100 < item[6] then
				local sold = t + 2 * DAY
				local price = math.floor(item[4] * (0.75 + (back % 5) * 0.08))
				add(sold, "sales", 1, item[2], qty, price * qty, math.floor(price / 0.95))
			end
		end
		if back % 3 == 0 then add(t, "crafts", 1, 3, 0, 2996, 0, 1, "patron", 0, 800000, 5000000, 4200000) end
		if back % 7 == 0 then add(t, "crafts", 2, 4, 0, 118, 0, 1, "personal", 0, 300000, 1000000, 1000000) end
		add(t, "bought", 1, 2589, 0, 20, 400000 + back * 3000, 21000, "auction", "Linen Cloth")
		if back % 4 == 0 then add(t, "bought", 2, 2320, 0, 5, 50000, 12000, "vendor", "Coarse Thread") end
	end
	return true
end

function Ledger.Init()
	CraftProfitDB.ledger = CraftProfitDB.ledger or { names = {}, items = {}, days = {}, months = {} }
	saved = CraftProfitDB.ledger
	for index, name in ipairs(saved.names) do nameIndex[name] = index end
	watchPosts()
	local events = CreateFrame("Frame")
	watchPurchases(events)
	events:RegisterEvent("PLAYER_LOGIN")
	events:SetScript("OnEvent", function(_, event, ...)
		if event ~= "PLAYER_LOGIN" then
			onPurchaseEvent(event, ...)
			return
		end
		Ledger.RollUp(saved, time())
		-- The sales the mailbox already told us about count from the start.
		if not saved.seeded then
			saved.seeded = true
			for _, sale in ipairs(CraftProfitDB.sales and CraftProfitDB.sales.list or {}) do Ledger.RecordSale(sale) end
		end
	end)
end
