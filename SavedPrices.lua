-- Craft Profit: TSM's prices, saved for your characters that don't load TSM.
-- When a character with TSM logs in, the materials and crafts in every
-- character's saved scans (see Scans.lua) are priced and saved for its realm,
-- with the items that characters without TSM had no price for, and, if the
-- option says so, the crafting items or all the items TSM has auction data for.
-- Those characters price from the save (see Prices.lua).
--
-- Which items TSM has data for comes from TSM's own data as the game loads it
-- (see onTSMData); their prices still come through TSM's API, like every other
-- price in Craft Profit.
--
-- A saved file only loads up to a limit of unique values, so each realm's prices
-- are saved as one string.
local _, ns = ...

local SavedPrices = {}
ns.SavedPrices = SavedPrices

local format = string.format

-- Saved prices older than this many days aren't used.
local MAX_DAYS = 14
-- Seconds after login before pricing, so TSM's own work after login goes first.
local LOGIN_DELAY = 30
-- Seconds to wait for the game to load items it didn't have yet.
local ITEM_DELAY = 3
-- Milliseconds of pricing per frame, so the game doesn't stutter.
local FRAME_BUDGET = 2
-- Seconds between checks while you're in combat, when pricing waits.
local COMBAT_WAIT = 2
-- A save with fewer than this share of the prices of the one it would replace
-- (with the same Save prices for choice) is kept out: TSM was missing data.
local SHRINK_LIMIT = 0.5
-- At most this many items wait for a character with TSM to price them.
local MAX_WANTED = 2000

-- CraftProfitDB.tsmPrices[realm] = {
--   time = when it was saved, character = who saved it ("Name-Realm"),
--   matSource, saleSource = the TSM prices it used for materials and crafts,
--   items = the Save prices for choice it was made with (see ns.SAVE_ITEMS_CHOICES),
--   count = how many items it has a price for,
--   prices = "key,material,vendor,sale,soldPerDay;..." in copper, sold per day
--     times a thousand, each empty when TSM had none,
-- }
-- A key is the itemID, or "itemID@itemLevel" for gear, whose price depends on its level.
-- CraftProfitDB.tsmWanted = { key -> the item's link, or its itemID for a material }
local saved, wanted
local wantedCount = 0

function SavedPrices.Init()
	CraftProfitDB.tsmPrices = CraftProfitDB.tsmPrices or {}
	CraftProfitDB.tsmWanted = CraftProfitDB.tsmWanted or {}
	saved, wanted = CraftProfitDB.tsmPrices, CraftProfitDB.tsmWanted
	for _ in pairs(wanted) do wantedCount = wantedCount + 1 end
end

local function tsmLoaded()
	return TSM_API and TSM_API.GetCustomPriceValue and TSM_API.ToItemString and true or false
end

-- Whether this character prices from the saved prices: the option is on and TSM isn't loaded.
function SavedPrices.InUse()
	return ns.db.saveTSMPrices and not tsmLoaded()
end

-- "Area 52" and "Area52" are the same realm, and "Azjol-Nerub" and "AzjolNerub".
local function realmKey(realm)
	return realm and (realm:gsub("[%s%-]", ""))
end

---------------------------------------------------------------------------
-- TSM's item list, on characters with TSM
---------------------------------------------------------------------------

-- TSM's auction data for this realm and the region, as text, while the game
-- loads it. Kept only to list its items (see tsmItems); TSM keeps the same text.
local tsmData = {}
-- TSM's kinds of auction data that list items: the region's commodities and
-- this realm's other items.
local TSM_ITEM_DATA = { AUCTIONDB_COMMODITY_DATA = "region", AUCTIONDB_NON_COMMODITY_DATA = "realm" }

-- Realm names with only letters and digits, to match TSM's spelling of them.
local function bareRealm(realm)
	return type(realm) == "string" and (realm:gsub("[^%w]", "")) or nil
end

local function onTSMData(tag, realmOrRegion, data)
	local kind = TSM_ITEM_DATA[tag]
	if not kind or type(data) ~= "string" then return end
	if kind == "realm" and bareRealm(realmOrRegion) ~= bareRealm(GetRealmName()) then return end
	tsmData[#tsmData + 1] = data
end

-- TSM hands its data to this function as the game loads TradeSkillMaster_AppHelper,
-- which loads after Craft Profit. Without it (TSM changed, or isn't loaded), saves
-- of more than your recipes save just your recipes.
if type(TSM_APPHELPER_LOAD_DATA) == "function" then
	hooksecurefunc("TSM_APPHELPER_LOAD_DATA", onTSMData)
end

-- Every item in TSM's auction data, one per call: its key (see SaleKey), the
-- itemID, and TSM's name for it ("i:12345", or "i:12345::i639" for gear at an
-- item level); nil after the last. Battle pets and other kinds are left out.
local function tsmItems()
	local index, nextText = 0, nil
	return function()
		while true do
			local text = nextText and nextText()
			if text then
				local id = text:match("^(%d+)$") or text:match("^i:(%d+)$")
				if id then return id, tonumber(id), "i:" .. id end
				local gearID, level = text:match("^i:(%d+)::i(%d+)$")
				if gearID then return gearID .. "@" .. level, tonumber(gearID), text end
			else
				index = index + 1
				if not tsmData[index] then return end
				-- Each item's data starts with "{itemString," ({173202,... or {"i:258947::i260",...).
				nextText = tsmData[index]:gmatch('{"?([^,"{}]+)"?,')
			end
		end
	end
end

-- Whether a Save prices for choice keeps an item from TSM's list. "crafting":
-- crafting items, not gear. "all": everything.
local function keeps(choice, itemID, gear)
	if choice == "all" then return true end
	if choice ~= "crafting" or gear then return false end
	local classID = select(6, C_Item.GetItemInfoInstant(itemID))
	return classID ~= nil and ns.CRAFTING_CLASSES[classID] == true
end

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------

local saleKeys = {} -- link -> key

-- The key an item's sale price is saved under: its itemID, plus its item level
-- for gear. Nil when the game hasn't loaded the item yet.
function SavedPrices.SaleKey(link, itemID)
	if not link then return itemID and tostring(itemID) end
	local key = saleKeys[link]
	if key then return key end
	local id, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
	id = id or itemID
	if not id then return end
	if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
		local level = C_Item.GetDetailedItemLevelInfo(link)
		if not level then return end
		key = id .. "@" .. level
	else
		key = tostring(id)
	end
	saleKeys[link] = key
	return key
end

---------------------------------------------------------------------------
-- Reading, on characters without TSM
---------------------------------------------------------------------------

-- The saves this character can price from, newest first (see usable).
local sources

-- Every save under MAX_DAYS old, newest first: { saved = the save, home = whether
-- it's from this realm or one connected to it, map = its prices once unpacked }.
-- Gear only uses saves from home; materials sell across the region.
local function usable()
	if sources then return sources end
	local here = realmKey(GetNormalizedRealmName())
	if not here then return {} end
	local home = { [here] = true }
	for _, realm in ipairs(GetAutoCompleteRealms() or {}) do home[realmKey(realm)] = true end
	local list = {}
	local oldest = time() - MAX_DAYS * 86400
	for realm, save in pairs(saved) do
		if type(save.prices) == "string" and (save.time or 0) >= oldest then
			list[#list + 1] = { saved = save, home = home[realm] or false }
		end
	end
	table.sort(list, function(a, b) return a.saved.time > b.saved.time end)
	sources = list
	return list
end

-- A save's prices: key -> { material, vendor, sale, soldPerDay }.
local function mapOf(source)
	if not source.map then
		local map = {}
		for key, material, vendor, sale, sold in source.saved.prices:gmatch("([^,;]+),([^,;]*),([^,;]*),([^,;]*),([^,;]*)") do
			map[key] = { tonumber(material), tonumber(vendor), tonumber(sale), tonumber(sold) }
		end
		source.map = map
	end
	return source.map
end

-- Keeps an item with no saved price for the next character with TSM to price.
-- Only items Craft Profit prices are wanted, not every item you hover, so these
-- stay few: an item missing from TSM's auction data can still have a vendor price.
local function want(key, value)
	if wanted[key] or wantedCount >= MAX_WANTED then return end
	wanted[key] = value
	wantedCount = wantedCount + 1
end

-- The saved prices of `key` and the save they're from, or nil when no save has
-- it, and then it's wanted with `value` (see CraftProfitDB.tsmWanted) if that's
-- given. A save that has it without a price means TSM had none, so it isn't
-- wanted again.
local function lookup(key, value)
	local gear = key:find("@", 1, true)
	for _, source in ipairs(usable()) do
		if source.home or not gear then
			local values = mapOf(source)[key]
			if values then return values, source end
		end
	end
	if value then want(key, value) end
end

function SavedPrices.Material(itemID)
	local values = lookup(tostring(itemID), itemID)
	return values and values[1]
end

function SavedPrices.Vendor(itemID)
	local values = lookup(tostring(itemID), itemID)
	return values and values[2]
end

function SavedPrices.Sale(link, itemID)
	local key = SavedPrices.SaleKey(link, itemID)
	local values = key and lookup(key, link or itemID)
	return values and values[3]
end

function SavedPrices.SoldPerDay(link)
	local key = SavedPrices.SaleKey(link)
	local values = key and lookup(key, link)
	return values and values[4] and values[4] / 1000
end

-- How many days ago a save was made, and the name of who made it.
local function ageOf(save)
	return math.floor((time() - save.time) / 86400), (save.character or "?"):match("^[^-]+")
end

-- How many days ago the newest save this character prices from was made, the
-- name of who made it, and the TSM price it used for materials. Nil without one.
function SavedPrices.Age()
	local list = usable()
	local source = list[1]
	for _, candidate in ipairs(list) do
		if candidate.home then source = candidate break end
	end
	if not source then return end
	local age, name = ageOf(source.saved)
	return age, name, source.saved.matSource or "dbmarket"
end

---------------------------------------------------------------------------
-- Item tooltips, on characters without TSM
---------------------------------------------------------------------------

-- One line with the item's saved TSM price, as Craft Profit prices it: gear at
-- its sale price, anything else at a vendor's price (with the vendor option on)
-- or its material price, or its sale price without one. Which TSM price that
-- is ("dbmarket", "vendorbuy"...), then whose prices they are and how old, in
-- grey (red once old).
local function onItem(tooltip, data)
	if not (saved and ns.db and ns.db.priceTooltip and ns.db.provider ~= "auctionator" and SavedPrices.InUse()) then
		return
	end
	local itemID = data and data.id
	if type(itemID) ~= "number" or (issecretvalue and issecretvalue(itemID)) then return end
	local _, link = TooltipUtil.GetDisplayedItem(tooltip)
	if link and issecretvalue and issecretvalue(link) then link = nil end

	local price, source, priceType
	local key = SavedPrices.SaleKey(link, itemID)
	local values, from = lookup(tostring(itemID))
	if values and not (key and key:find("@", 1, true)) then
		source = from
		if not ns.db.vendorOnAH and values[2] then
			price, priceType = values[2], "vendorbuy"
		elseif values[1] then
			price, priceType = values[1], from.saved.matSource or "dbmarket"
		end
	end
	if not price and key then
		values, from = lookup(key)
		if values and values[3] then
			-- Saves from before they kept it used the price you've picked.
			price, source, priceType = values[3], from, from.saved.saleSource or ns.db.saleSource
		end
	end
	if not price then return end

	local age, name = ageOf(source.saved)
	local whose = ns.Color(age >= ns.Reminder.OLD_DAYS and "warning" or "muted",
		format("(%s, %s)", name, ns.Prices.AgeText(age)))
	-- Down to the copper, like the other prices on item tooltips.
	tooltip:AddDoubleLine(format("TSM %s %s", priceType, whose), GetMoneyString(math.floor(price + 0.5), true),
		1, 0.82, 0, 1, 1, 1)
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)

---------------------------------------------------------------------------
-- Saving, on characters with TSM
---------------------------------------------------------------------------

local running, again, retried = false, false, false
-- Which save is running: the pricing of an older one, or of one deleted while
-- it ran, stops at its next step.
local runID = 0

local function tsmValue(source, itemString)
	local ok, value = pcall(TSM_API.GetCustomPriceValue, source, itemString)
	if ok and value and value > 0 then return value end
end

-- A whole number of copper as text. "%d" only takes up to about 214,748 gold in
-- the game, and some items sell for more, so it's "%.0f".
local function copper(value)
	return value and format("%.0f", value) or ""
end

-- One key's saved line (see CraftProfitDB.tsmPrices), and whether TSM had any
-- price for it. The sale price is for `link`, or for TSM's name for the item
-- (`tsmName`, see tsmItems).
local function priceKey(key, link, tsmName)
	local itemID = key:match("^%d+")
	local itemString = "i:" .. itemID
	local material, vendor
	if not key:find("@", 1, true) then
		material = tsmValue(ns.db.matSource, itemString)
		vendor = tsmValue("vendorbuy", itemString)
	end
	if link then
		local ok, fromLink = pcall(TSM_API.ToItemString, link)
		if ok and fromLink then itemString = fromLink end
	elseif tsmName then
		itemString = tsmName
	end
	local sale
	if itemString ~= "i:" .. itemID or ns.db.saleSource ~= ns.db.matSource then
		sale = tsmValue(ns.db.saleSource, itemString)
	else
		sale = material
	end
	-- Only what's on the auction house sells there. TSM rounds to whole numbers,
	-- so it's asked for a thousand times the number.
	local sold
	if material or sale then
		sold = tsmValue("dbregionsoldperday*1000", itemString)
		if not sold then
			sold = tsmValue("dbregionsoldperday", itemString)
			sold = sold and sold * 1000
		end
	end
	local line = table.concat({ key, copper(material), copper(vendor), copper(sale), copper(sold) }, ",")
	return line, (material or vendor or sale) ~= nil
end

-- Every item of your recipes and the wanted list to price: key -> its link, or
-- false for a material known by itemID. Also whether some gear wasn't loaded yet
-- (asked for, to try again shortly).
local function collect()
	local items, waiting = {}, false
	local function addMaterial(itemID)
		local key = tostring(itemID)
		if items[key] == nil then items[key] = false end
	end
	local function addSale(link, itemID)
		local key = SavedPrices.SaleKey(link, itemID)
		if key then
			items[key] = link or items[key] or false
		elseif itemID then
			C_Item.RequestLoadItemDataByID(itemID)
			waiting = true
		end
	end
	for _, entry in ipairs(ns.Scans.Entries()) do
		for _, output in pairs(entry.outputs) do addSale(output.link, output.itemID) end
		for _, slot in ipairs(entry.slots) do
			for _, option in ipairs(slot.options) do addMaterial(option.itemID) end
		end
		for _, other in ipairs(entry.others) do
			for _, itemID in ipairs(other.itemIDs) do addMaterial(itemID) end
		end
	end
	for key, value in pairs(wanted) do
		if type(value) == "string" then items[key] = value else addMaterial(value) end
	end
	return items, waiting
end

local start
local announce, againAnnounce = false, false -- whether this save (and the next) say so in chat
local startedAt

-- The footers say "saving for alts" while a save runs.
local function redrawFooters()
	ns.Panel.Refresh()
	ns.BestCraftsList.Refresh()
end

-- Saves the prices: replaces this realm's save, unless TSM had no price at all
-- (its prices weren't loaded) or far fewer than the save it would replace, and
-- forgets the wanted items it priced. `count` is how many items it has a price
-- for; `noList`, whether the choice wanted TSM's item list and there was none.
local function finish(items, lines, count, choice, noList)
	running = false
	local me, myKey = ns.Ranks.Me()
	local realm = realmKey(me and me.realm or GetNormalizedRealmName())
	local old = realm and saved[realm]
	local shrank = old and old.items == choice and (old.count or 0) > 0 and count < old.count * SHRINK_LIMIT
	local seconds = math.floor(GetTime() - startedAt + 0.5)
	if count == 0 then
		if announce then ns.Shopping.Say("TSM has no prices yet, so your alts keep the TSM prices saved before.") end
	elseif shrank then
		-- Said even when the save itself is quiet: something is wrong on TSM's side.
		ns.Shopping.Say(format("TSM had prices for %s items, far fewer than the %s saved before, so your alts keep " ..
			"those. Check that the TSM desktop app is running.", BreakUpLargeNumbers(count), BreakUpLargeNumbers(old.count)))
	elseif announce then
		ns.Shopping.Say(format("Saved TSM prices of %s items for your alts (%d seconds).", BreakUpLargeNumbers(count), seconds)
			.. (noList and " TSM's item list wasn't there, so only your recipes' items were saved." or ""))
	end
	if count > 0 and realm and not shrank then
		saved[realm] = { time = time(), character = myKey, matSource = ns.db.matSource,
			saleSource = ns.db.saleSource, items = choice, count = count, prices = table.concat(lines, ";") }
		for key in pairs(items) do
			if wanted[key] then wanted[key], wantedCount = nil, wantedCount - 1 end
		end
		local oldest = time() - MAX_DAYS * 86400
		for other, save in pairs(saved) do
			if (save.time or 0) < oldest then saved[other] = nil end
		end
		sources = nil
	end
	redrawFooters()
	if again then
		again = false
		SavedPrices.Save(againAnnounce)
	end
end

-- Prices every item a couple of milliseconds a frame, waiting while you're in
-- combat: your recipes' and the wanted ones, then, when the option says so, the
-- items in TSM's auction data (see tsmItems). Of those, only the ones TSM has a
-- price for are kept.
local function price(items, run)
	local keys = {}
	for key in pairs(items) do keys[#keys + 1] = key end
	local choice = ns.db.saveItems
	local nextItem = choice ~= "recipes" and tsmItems() or nil
	local noList = nextItem ~= nil and #tsmData == 0
	local lines, index, count = {}, 1, 0
	-- A frame's worth of pricing; true when there's more to do.
	local function work()
		local stop = debugprofilestop() + FRAME_BUDGET
		while debugprofilestop() < stop do
			if index <= #keys then
				local key = keys[index]
				local line, priced = priceKey(key, items[key] or nil)
				lines[#lines + 1] = line
				if priced then count = count + 1 end
				index = index + 1
			else
				local key, itemID, tsmName
				if nextItem then key, itemID, tsmName = nextItem() end
				if not key then
					finish(items, lines, count, choice, noList)
					return false
				end
				if items[key] == nil and keeps(choice, itemID, key:find("@", 1, true)) then
					items[key] = false -- once, if TSM lists it twice
					local line, priced = priceKey(key, nil, tsmName)
					if priced then
						lines[#lines + 1] = line
						count = count + 1
					end
				end
			end
		end
		return true
	end
	-- An error stops the save (the last one stays) and shows as usual, and the
	-- next save can still run.
	local function step()
		if run ~= runID then return end -- deleted while it ran (see SavedPrices.Forget)
		if InCombatLockdown() then
			C_Timer.After(COMBAT_WAIT, step)
			return
		end
		local ok, more = pcall(work)
		if not ok then
			running = false
			redrawFooters()
			geterrorhandler()(more)
		elseif more then
			C_Timer.After(0, step)
		end
	end
	step()
end

function start(run)
	if run ~= runID then return end
	local items, waiting = collect()
	if waiting and not retried then
		retried = true
		C_Timer.After(ITEM_DELAY, function() start(run) end)
		return
	end
	price(items, run)
end

-- After a Best crafts scan: saves the new recipes' prices. Saves of TSM's whole
-- list (which has the materials already) wait for the next login rather than
-- price it all again each time you spend knowledge.
function SavedPrices.ScanSaved()
	if ns.db.saveItems == "recipes" then SavedPrices.Save() end
end

-- Whether a save is running.
function SavedPrices.Saving()
	return running
end

-- Saves TSM's prices for your characters without TSM, if TSM is loaded here and
-- the option is on. Called on login, after a Best crafts scan and when an option
-- about it changes (`fromOptions`). Chat says when it starts and ends, for a
-- change in the options and for saves of every item, which take a while.
function SavedPrices.Save(fromOptions)
	if not (saved and ns.db.saveTSMPrices and ns.db.provider ~= "auctionator" and tsmLoaded()) then return end
	local say = fromOptions == true or ns.db.saveItems ~= "recipes"
	if running then
		again, againAnnounce = true, againAnnounce or say
		return
	end
	running, retried, announce, againAnnounce, startedAt = true, false, say, false, GetTime()
	runID = runID + 1
	if say then ns.Shopping.Say("Saving TSM prices for your alts...") end
	redrawFooters()
	start(runID)
end

-- When the option is turned off: deletes every saved price and the wanted
-- list, and stops a save that's running. Characters without TSM stop using
-- them right away.
function SavedPrices.Forget()
	if not saved then return end
	runID = runID + 1
	running, again = false, false
	local had = next(saved) ~= nil or next(wanted) ~= nil
	wipe(saved)
	wipe(wanted)
	wantedCount = 0
	sources = nil
	redrawFooters()
	if had then ns.Shopping.Say("Deleted the TSM prices saved for your alts.") end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	C_Timer.After(LOGIN_DELAY, function() SavedPrices.Save() end)
end)
