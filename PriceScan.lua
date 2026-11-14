-- Craft Profit: its own auction house prices, for when neither TSM nor
-- Auctionator prices here (see Prices.lua). A scan reads the lowest price of
-- everything on the auction house, and how many are up, and saves them for the
-- realm. What vendors sell is learned whenever you visit one. The Prices tab
-- (PricesTab.lua) starts a scan, and it can start by itself at the auction house.
--
-- A saved file only loads up to a limit of unique values, so each realm's prices
-- are saved as one string.
local _, ns = ...

local PriceScan = {}
ns.PriceScan = PriceScan

local format = string.format
local Search = ns.AuctionSearch

local OWNER = "scan" -- the scan's name in the line of auction house questions
-- A scan that found fewer than this share of the items the last full scan did
-- doesn't count as a full one: something cut it short.
local SHRINK_LIMIT = 0.5
-- So does one that found fewer items than this: the list it read wasn't the
-- whole auction house.
local MIN_FULL = 50
-- Prices of items no scan has seen for this many days are forgotten.
local KEEP_DAYS = 30
-- A price this many days old or older has no age to show (see Prices.MaterialAge).
local OLD_DAYS = 21
-- The scan that starts by itself waits this long after the auction house opens,
-- for the window's own first search, and runs at most this often. In seconds.
local AUTO_DELAY, AUTO_EVERY = 2, 3600

-- CraftProfitDB.scanPrices[realm] = {
--   time = when the last full scan ended, count = how many items it found,
--   prices = "key,price,listed,day;..." with the lowest price in copper, how many
--     were up in the last full scan (0 when it didn't see the item), and the day
--     the item was last seen (days since 1970),
-- }
-- A key is the itemID, "itemID@itemLevel" for gear (as SavedPrices.SaleKey), or
-- "p" and the species for a caged battle pet.
-- CraftProfitDB.vendorSeen[itemID] = what a vendor sells one for, in copper.
local realm, save
local prices, counts, days -- key -> lowest price, how many are up, day last seen
-- The scan that's running: { items, rows, pages, seen, today, auto, disturbed }.
-- `rows` is how many lines of the auction house's list it has read, `items` how
-- many different items those were.
local state
-- What the last scan had to say, for the Prices tab.
local lastMessage
-- Who to tell when a scan starts, moves on or ends.
local listeners = {}

local function today()
	return math.floor(time() / 86400)
end

-- This realm's name for the save: connected realms share an auction house, so
-- they share the first of their names. Where factions have their own auction
-- house (not Retail), the faction is part of it.
local function realmName()
	local here = GetNormalizedRealmName()
	if not here then return end
	local first = here
	for _, name in ipairs(GetAutoCompleteRealms() or {}) do
		name = name:gsub("[%s%-]", "")
		if name < first then first = name end
	end
	if not ns.QUALITY_CRAFTING then first = first .. "-" .. (UnitFactionGroup("player") or "") end
	return first
end

-- Unpacks this realm's saved prices, the first time they're needed.
local function load()
	if prices then return true end
	realm = realm or realmName()
	if not realm then return false end
	CraftProfitDB.scanPrices = CraftProfitDB.scanPrices or {}
	save = CraftProfitDB.scanPrices[realm]
	prices, counts, days = {}, {}, {}
	if save and type(save.prices) == "string" then
		for key, price, listed, day in save.prices:gmatch("([^,;]+),(%d+),(%d+),(%d+)") do
			prices[key], counts[key], days[key] = tonumber(price), tonumber(listed), tonumber(day)
		end
	end
	return true
end

local function pack()
	local lines = {}
	for key, price in pairs(prices) do
		lines[#lines + 1] = format("%s,%.0f,%.0f,%.0f", key, price, counts[key] or 0, days[key] or 0)
	end
	save = save or {}
	save.prices = table.concat(lines, ";")
	CraftProfitDB.scanPrices[realm] = save
end

local function tell()
	for _, listener in ipairs(listeners) do listener() end
end

-- Prices changed: everything that shows one draws again.
local function redraw()
	ns.Panel.Refresh()
	ns.BestCraftsList.Refresh()
	ns.ShoppingList.Refresh()
end

---------------------------------------------------------------------------
-- Reading prices
---------------------------------------------------------------------------

-- Whether a scan has ever saved prices for this realm.
function PriceScan.HasPrices()
	return load() and next(prices) ~= nil
end

-- What a material is listed for, in copper (nil when no scan has seen it).
function PriceScan.Material(itemID)
	return load() and prices[tostring(itemID)] or nil
end

-- What a crafted item is listed for, in copper: gear by its item level.
function PriceScan.Sale(link, itemID)
	if not load() then return end
	local key = ns.SavedPrices.SaleKey(link, itemID)
	return key and prices[key] or nil
end

-- What a vendor sells one for, in copper, from the vendors you've visited.
function PriceScan.Vendor(itemID)
	local seen = CraftProfitDB.vendorSeen
	return seen and seen[itemID] or nil
end

-- How many seconds ago the last full scan ended, or nil when there never was one.
function PriceScan.Seconds()
	if not load() or not (save and save.time) then return end
	return math.max(time() - save.time, 0)
end

-- How many days ago the last full scan ended (0 is within a day), or false when
-- there never was one.
function PriceScan.Age()
	local seconds = PriceScan.Seconds()
	return seconds and math.floor(seconds / 86400) or false
end

-- How many items the last full scan found.
function PriceScan.Count()
	return load() and save and save.count or 0
end

local function keyAge(key)
	local day = key and days[key]
	if not day then return false end
	local age = today() - day
	return age < OLD_DAYS and math.max(age, 0) or false
end

-- How many days ago a scan last saw the material (0 is today), or false when
-- that's over three weeks or never.
function PriceScan.MaterialAge(itemID)
	return load() and keyAge(tostring(itemID)) or false
end

-- The same for a crafted item.
function PriceScan.SaleAge(link)
	return load() and keyAge(ns.SavedPrices.SaleKey(link)) or false
end

-- How many of an item were up in the last full scan, and how many days ago that
-- was; nil when no scan has seen it.
function PriceScan.Listed(link)
	if not load() then return end
	local key = ns.SavedPrices.SaleKey(link)
	if not (key and days[key]) then return end
	return counts[key] or 0, PriceScan.Age() or 0
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------

-- Notes one price under a key: the lowest of everything seen under it this scan.
local function note(key, price, listed)
	if state.seen[key] then
		if price < prices[key] then prices[key] = price end
		counts[key] = counts[key] + listed
	else
		state.seen[key] = true
		-- Gear is counted once, by its own ID, not once more for each item level.
		if not key:find("@", 1, true) then state.items = state.items + 1 end
		prices[key], counts[key], days[key] = price, listed, state.today
	end
end

-- Reads one page of the auction house's list, from its line `from` on.
local function read(results, from)
	state.pages = state.pages + 1
	for index = from or 1, #results do
		local result = results[index]
		state.rows = state.rows + 1
		local itemKey, price = result.itemKey, result.minPrice
		if itemKey and price and price > 0 then
			local listed = result.totalQuantity or 0
			if (itemKey.battlePetSpeciesID or 0) > 0 then
				note("p" .. itemKey.battlePetSpeciesID, price, listed)
			else
				-- Gear has a price for each item level. The item's own ID gets the lowest of
				-- them, which is what a material lookup asks for.
				if (itemKey.itemLevel or 0) > 0 then note(itemKey.itemID .. "@" .. itemKey.itemLevel, price, listed) end
				note(tostring(itemKey.itemID), price, listed)
			end
		end
	end
	tell()
end

-- Ends the scan. A full one replaces how many of everything are up, forgets
-- prices nobody has listed for a month, and is the one scans are dated by.
-- `problem` is why it isn't full, when it isn't.
local function finish(problem)
	if not state then return end
	local done = state
	state = nil
	Search.Drop(OWNER)
	Search.onBrowseAdded, Search.onBrowseReplaced = nil, nil
	if not problem and done.disturbed then
		problem = "Another search got in the way, so some items were missed. Scan again for the rest."
	end
	if not problem and done.items < SHRINK_LIMIT * (save and save.count or 0) then
		problem = "The scan found far fewer items than the last one, so it wasn't counted. Scan again."
	elseif not problem and done.items < MIN_FULL then
		problem = "The scan found very few items, so it wasn't counted. Scan again."
	end
	if not problem then
		for key, day in pairs(days) do
			if not done.seen[key] then
				if done.today - day > KEEP_DAYS then
					prices[key], counts[key], days[key] = nil, nil, nil
				else
					counts[key] = 0
				end
			end
		end
		save = save or {}
		save.time, save.count = time(), done.items
	end
	if done.items > 0 then pack() end
	lastMessage = problem or format("Scan done: %s items.", BreakUpLargeNumbers(done.items))
	if done.auto or not problem then
		ns.Shopping.Say(problem and ns.Color("warning", "Price scan: " .. problem)
			or format("Price scan done: %s items.", BreakUpLargeNumbers(done.items)))
	end
	redraw()
	tell()
end

local nextPage

local function onPage(arrived)
	if not state then return end
	if arrived then return nextPage() end
	-- No page came: either that was all of it, or the auction house stopped answering.
	if C_AuctionHouse.HasFullBrowseResults() then finish() else finish("The auction house stopped answering.") end
end

nextPage = function()
	if C_AuctionHouse.HasFullBrowseResults() then return finish() end
	Search.Browse(OWNER, true, onPage)
end

-- The auction house's list was replaced while the scan ran. If the game says so
-- when the same list only grew, the new lines are read; a shorter list is
-- another search, and the scan can't be a full one any more.
local function onReplaced()
	if not state then return end
	local results = C_AuctionHouse.GetBrowseResults()
	if #results < state.rows then
		state.disturbed = true
		state.rows = 0
		read(results)
	elseif #results > state.rows then
		read(results, state.rows + 1)
	end
end

-- Starts a scan. Returns whether it did, and why not otherwise. `auto` is the
-- scan that starts by itself.
function PriceScan.Start(auto)
	if state then return false, "A scan is already running." end
	if not Search.IsOpen() then return false, "Open the auction house to scan." end
	if not load() then return false, "The game hasn't said which realm this is yet. Try again in a moment." end
	state = { items = 0, rows = 0, pages = 0, seen = {}, today = today(), auto = auto or false, disturbed = false }
	lastMessage = nil
	Search.Browse(OWNER, false, function(results)
		if not state then return end
		if not results then return finish("The auction house didn't answer.") end
		-- From here on every page of the list is read, whoever asked for it.
		Search.onBrowseReplaced = onReplaced
		Search.onBrowseAdded = function(added)
			if state then read(added) end
		end
		read(results)
		nextPage()
	end)
	if auto then ns.Shopping.Say("Scanning the auction house for prices...") end
	tell()
	return true
end

-- Stops the scan that's running. The prices it read so far are kept.
function PriceScan.Stop()
	if state then finish("The scan was stopped. The prices it read so far are kept.") end
end

-- The scan that's running, as { items, pages }, or nil; and what the last one said.
function PriceScan.State()
	return state, lastMessage
end

-- `listener` is called when a scan starts, reads a page or ends.
function PriceScan.Watch(listener)
	listeners[#listeners + 1] = listener
end

-- Whether the scan that starts by itself is due: the option is on, prices come
-- from Craft Profit's own scan, and the last one is old enough.
local function autoDue()
	if not ns.db.autoScan or ns.Prices.Scanner() ~= "own" then return false end
	local seconds = PriceScan.Seconds()
	return not seconds or seconds >= AUTO_EVERY
end

-- Testing: where the scan stands.
function PriceScan.Explain()
	local say = ns.Shopping.Say
	load()
	local known = 0
	for _ in pairs(prices or {}) do known = known + 1 end
	say(format("Testing: realm %s, %d prices known, last full scan %s (%s items). Price source: %s.", tostring(realm),
		known, tostring(save and save.time and date("%Y-%m-%d %H:%M", save.time)), tostring(save and save.count),
		tostring(ns.Prices.Scanner())))
	if state then
		say(format("  Scanning: %d items, %d lines in %d pages, disturbed %s.", state.items, state.rows, state.pages,
			tostring(state.disturbed)))
	end
	say(format("  Last message: %s. Last problem: %s.", tostring(lastMessage), tostring(Search.lastProblem)))
end

---------------------------------------------------------------------------
-- Vendors
---------------------------------------------------------------------------

-- Notes what the vendor you're at sells for gold, with no limit on how many.
local function readVendor()
	CraftProfitDB.vendorSeen = CraftProfitDB.vendorSeen or {}
	local seen = CraftProfitDB.vendorSeen
	for index = 1, GetMerchantNumItems() do
		local info = C_MerchantFrame.GetItemInfo(index)
		local link = GetMerchantItemLink(index)
		local itemID = link and C_Item.GetItemInfoInstant(link)
		if info and itemID and not info.hasExtendedCost and (info.price or 0) > 0 and info.numAvailable == -1 then
			seen[itemID] = math.floor(info.price / math.max(info.stackCount or 1, 1) + 0.5)
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("MERCHANT_SHOW")
events:SetScript("OnEvent", function(_, event)
	if event == "MERCHANT_SHOW" then
		readVendor()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		if state then finish("The scan stopped when the auction house closed. The prices it read so far are kept.") end
	else
		C_Timer.After(AUTO_DELAY, function()
			if Search.IsOpen() and not state and ns.db and autoDue() then PriceScan.Start(true) end
		end)
	end
end)
