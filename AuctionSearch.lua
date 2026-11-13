-- Craft Profit: asking the auction house what an item is listed for, and for
-- your own auctions, for the Sell and My auctions tabs (Sell.lua, Auctions.lua).
-- The auction house answers one question at a time, so the questions wait in a
-- line here. Nothing is posted, bought or cancelled from this file.
local _, ns = ...

local Search = {}
ns.AuctionSearch = Search

-- How long an answer may take before the question is given up, in seconds: for
-- one item, and for a page of the whole auction house's list.
local RESULT_WAIT, BROWSE_WAIT = 6, 20
-- How soon the line is tried again while the auction house is busy, in seconds.
local BUSY_WAIT = 0.5
-- Listings read from one answer: the cheapest ones are all that's needed.
local MAX_ROWS = 40

local open = false
local queue, active = {}, nil
local retryDue = false
-- Why the last question failed, for /craftprofit testauctions.
Search.lastProblem = nil

local function priceSorts()
	return {
		{ sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false },
		{ sortOrder = Enum.AuctionHouseSortOrder.Bid, reverseSort = false },
	}
end

local function ownedSorts()
	return {
		{ sortOrder = Enum.AuctionHouseSortOrder.Name, reverseSort = false },
		{ sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
	}
end

local function byPrice(a, b) return a.price < b.price end

-- A stackable item's listings, cheapest first: { price (each), qty, mine }.
local function readCommodity(itemID)
	local rows = {}
	for index = 1, math.min(C_AuctionHouse.GetNumCommoditySearchResults(itemID), MAX_ROWS) do
		local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
		if info then
			rows[#rows + 1] = { price = info.unitPrice, qty = info.quantity,
				mine = info.containsOwnerItem or info.containsAccountItem or false }
		end
	end
	table.sort(rows, byPrice)
	return rows
end

-- Any other item's listings with a buyout, cheapest first:
-- { price, qty, mine, itemLevel }.
local function readItem(itemKey)
	local rows = {}
	for index = 1, math.min(C_AuctionHouse.GetNumItemSearchResults(itemKey), MAX_ROWS) do
		local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
		if info and info.buyoutAmount then
			rows[#rows + 1] = { price = info.buyoutAmount, qty = info.quantity, itemLevel = info.itemKey.itemLevel,
				mine = info.containsOwnerItem or info.containsAccountItem or false }
		end
	end
	table.sort(rows, byPrice)
	return rows
end

-- Your auctions, as the game lists them.
function Search.ReadOwned()
	local list = {}
	for index = 1, C_AuctionHouse.GetNumOwnedAuctions() do
		local info = C_AuctionHouse.GetOwnedAuctionInfo(index)
		if info then list[#list + 1] = info end
	end
	return list
end

local pump

-- The question at the front of the line is answered (results) or given up (nil).
local function finish(job, results)
	if active ~= job then return end
	active = nil
	if job.callback and not job.dropped then xpcall(job.callback, geterrorhandler(), results) end
	pump()
end

local function send(job)
	if job.browse == "start" then
		-- Everything on the auction house: an empty search with no filters.
		C_AuctionHouse.SendBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
	elseif job.browse then
		C_AuctionHouse.RequestMoreBrowseResults()
	elseif job.owned then
		C_AuctionHouse.QueryOwnedAuctions(ownedSorts())
	elseif job.sell then
		C_AuctionHouse.SendSellSearchQuery(job.itemKey, priceSorts(), true)
	else
		C_AuctionHouse.SendSearchQuery(job.itemKey, priceSorts(), true)
	end
end

-- Sends the next question, when the auction house is ready for one.
pump = function()
	if active or not open or not queue[1] then return end
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then
		-- The game says when it's ready again; this is for the times it doesn't.
		if not retryDue then
			retryDue = true
			C_Timer.After(BUSY_WAIT, function()
				retryDue = false
				pump()
			end)
		end
		return
	end
	local job = table.remove(queue, 1)
	active = job
	local ok, problem = pcall(send, job)
	if not ok then
		Search.lastProblem = tostring(problem)
		return finish(job, nil)
	end
	C_Timer.After(job.browse and BROWSE_WAIT or RESULT_WAIT, function()
		if active == job then
			Search.lastProblem = "the auction house didn't answer"
			finish(job, nil)
		end
	end)
end

local function add(job)
	if not open then return end
	queue[#queue + 1] = job
	pump()
end

-- Asks what an item is listed for. `sell` asks the way the game's own sell page
-- does (gear of every item level). `callback` gets { commodity, rows }, or nil
-- when the auction house didn't answer. `owner` names who asked, for Search.Drop.
function Search.Request(owner, itemKey, sell, callback)
	add({ owner = owner, itemKey = itemKey, sell = sell, callback = callback })
end

-- Asks for your auctions again. `callback` gets true once the game has them
-- (read them with Search.ReadOwned), or nil when the auction house didn't answer.
function Search.Owned(owner, callback)
	add({ owner = owner, owned = true, callback = callback })
end

-- Asks for the list of everything on the auction house (see PriceScan.lua): its
-- first page, or with `more` its next one. `callback` gets the first page's
-- lines, or true once a next page has arrived, or nil when none came. Every page
-- that arrives, whoever asked for it, goes to Search.onBrowseAdded while that's
-- set, and Search.onBrowseReplaced is told when another list takes its place.
function Search.Browse(owner, more, callback)
	add({ owner = owner, browse = more and "more" or "start", callback = callback })
end

-- Forgets the questions `owner` still has waiting.
function Search.Drop(owner)
	for index = #queue, 1, -1 do
		if queue[index].owner == owner then table.remove(queue, index) end
	end
	if active and active.owner == owner then active.dropped = true end
end

-- How many questions `owner` still has waiting.
function Search.Waiting(owner)
	local count = (active and active.owner == owner and not active.dropped) and 1 or 0
	for _, job in ipairs(queue) do
		if job.owner == owner then count = count + 1 end
	end
	return count
end

-- Whether the auction house is open.
function Search.IsOpen()
	return open
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
events:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
events:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
events:RegisterEvent("OWNED_AUCTIONS_UPDATED")
events:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
events:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
events:RegisterEvent("AUCTION_HOUSE_BROWSE_FAILURE")
events:SetScript("OnEvent", function(_, event, arg)
	if event == "AUCTION_HOUSE_SHOW" then
		open = true
	elseif event == "AUCTION_HOUSE_CLOSED" then
		open, queue, active = false, {}, nil
		Search.onBrowseAdded, Search.onBrowseReplaced = nil, nil
	elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
		pump()
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
		if active and active.browse == "start" then
			finish(active, C_AuctionHouse.GetBrowseResults())
		elseif Search.onBrowseReplaced then
			Search.onBrowseReplaced()
		end
	elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
		if Search.onBrowseAdded and type(arg) == "table" then Search.onBrowseAdded(arg) end
		if active and active.browse == "more" then finish(active, true) end
	elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
		if active and active.browse then
			Search.lastProblem = "the auction house couldn't list everything"
			finish(active, nil)
		end
	elseif not active or active.browse then
		return
	elseif event == "OWNED_AUCTIONS_UPDATED" then
		if active.owned then finish(active, true) end
	elseif active.owned then
		return
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
		if arg == active.itemKey.itemID then finish(active, { commodity = true, rows = readCommodity(arg) }) end
	elseif type(arg) == "table" and arg.itemID == active.itemKey.itemID then
		finish(active, { commodity = false, rows = readItem(active.itemKey) })
	end
end)
