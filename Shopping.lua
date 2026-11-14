-- Craft Profit: the shopping list button. Adds what you're short of, for one or
-- more crafts, to an Auctionator shopping list or to Craft Profit's own (its
-- window is ShoppingList.lua), or gives you a TSM search for it.
local ADDON_NAME, ns = ...

local Shopping = {}
ns.Shopping = Shopping

local format = string.format

-- Bind types that can be bought on the auction house.
local TRADEABLE = {
	[Enum.ItemBind.None] = true,
	[Enum.ItemBind.OnEquip] = true,
	[Enum.ItemBind.OnUse] = true,
}

local function say(text)
	print(ns.Color("heading", "Craft Profit:") .. " " .. text)
end

local function auctionatorAPI()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.CreateShoppingList and api.ConvertToSearchString then return api end
end

-- Auctionator's API can change or throw, so every call into it is guarded.
local function call(fn, ...)
	if not fn then return end
	local ok, result = pcall(fn, ADDON_NAME, ...)
	if ok then return result end
end

local function tsmLoaded()
	return TSM_API and TSM_API.GetCustomPriceValue and true or false
end

-- Where lists of missing materials go: "auctionator" (its shopping list), "tsm"
-- (a search to copy into TSM's Shopping tab) or "own" (Craft Profit's own list),
-- or nil when shopping is turned off. The "Shop with" choice decides. The TSM
-- search is only ever used when it was chosen: a choice whose addon isn't loaded
-- goes to Auctionator's list when that's loaded, and to "own" when it isn't.
function Shopping.ListTarget()
	if not ns.db.shoppingButton then return end
	local choice = ns.db.listAddon
	if choice == "tsm" and tsmLoaded() then return "tsm" end
	if choice ~= "own" and auctionatorAPI() then return "auctionator" end
	return "own"
end

-- "Shop with" radios at the bottom of a menu: the addons that are loaded and
-- Craft Profit's own list. Left out with neither addon, when there's no choice.
-- The menu redraws for the new choice.
function Shopping.AddShopWithChoice(root)
	local offered = { auctionator = auctionatorAPI() ~= nil, tsm = tsmLoaded(), own = true }
	if not (offered.auctionator or offered.tsm) then return end
	root:CreateDivider()
	root:CreateTitle("Shop with")
	local function isChosen(key) return Shopping.ListTarget() == key end
	local function choose(key)
		ns.db.listAddon = key
		ns.Panel.Refresh()
		ns.Patron.Redraw()
		return MenuResponse and MenuResponse.Refresh
	end
	for _, choice in ipairs(ns.LIST_ADDON_CHOICES) do
		if offered[choice[1]] then root:CreateRadio(choice[2], isChosen, choose, choice[1]) end
	end
end

---------------------------------------------------------------------------
-- Shopping lists
---------------------------------------------------------------------------

-- The profession whose window is open ("Blacksmithing"), or nil.
local function openProfession()
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then return end
	local info = C_TradeSkillUI.GetBaseProfessionInfo()
	local name = info and info.professionName
	if name and name ~= "" then return name end
end

-- The list materials go to: one per character and/or per profession, as the
-- options say ("Snir - Blacksmithing"), or "Crafting" with neither.
-- `profession` defaults to the open one; with none, the profession is left out.
-- `character` defaults to this one.
function Shopping.ListName(profession, character)
	local parts = {}
	if ns.db.listPerCharacter then parts[#parts + 1] = character or UnitName("player") end
	if ns.db.listPerProfession then parts[#parts + 1] = profession or openProfession() end
	if #parts == 0 then return ns.SHOPPING_LIST end
	return table.concat(parts, " - ")
end

-- How chat and tooltips name a list: Auctionator's "Snir - Blacksmithing"
-- shopping list, or the "Snir - Blacksmithing" shopping list for Craft Profit's
-- own. `listName` defaults to the current list.
function Shopping.ListPhrase(listName)
	return format(Shopping.ListTarget() == "auctionator" and "Auctionator's \"%s\" shopping list"
		or "the \"%s\" shopping list", listName or Shopping.ListName())
end

-- The lists Clear empties: `listName` when given; else the current one, or with
-- one list per profession and no profession window open, the lists of all this
-- character's professions.
local function listsToClear(listName)
	if listName then return { listName } end
	local names = {}
	if ns.db.listPerProfession and not openProfession() then
		for _, index in pairs({ GetProfessions() }) do
			local name = GetProfessionInfo(index)
			if name then names[#names + 1] = Shopping.ListName(name) end
		end
	end
	if #names == 0 then names[1] = Shopping.ListName() end
	return names
end

---------------------------------------------------------------------------
-- Auctionator shopping list
---------------------------------------------------------------------------

-- One list line per material and quality, so adding the same one again adds up
-- the amount.
local function termKey(term)
	return format("%s|%s|%s", term.searchString:lower(), tostring(term.tier), tostring(term.isExact))
end

-- The lines of a shopping list, and the ones Auctionator could read by termKey.
-- The API only makes whole lists, so changing one means reading it, changing the
-- lines and writing it back (writeList).
local function readList(api, listName)
	local lines, byKey = {}, {}
	for _, searchString in ipairs(call(api.GetShoppingListItems, listName) or {}) do
		local line = { text = searchString }
		local term = call(api.ConvertFromSearchString, searchString)
		if type(term) == "table" and type(term.searchString) == "string" then
			line.term = term
			byKey[termKey(term)] = line
		end
		lines[#lines + 1] = line
	end
	return lines, byKey
end

-- Writes the lines back, leaving out the ones marked gone. A line whose amount
-- changed has its text cleared, so it's rebuilt from its term. Returns whether
-- it worked.
local function writeList(api, listName, lines)
	local searchStrings = {}
	for _, line in ipairs(lines) do
		if not line.gone then
			local text = line.text or call(api.ConvertToSearchString, line.term)
			if not text then return false end
			searchStrings[#searchStrings + 1] = text
		end
	end
	return (pcall(api.CreateShoppingList, ADDON_NAME, listName, searchStrings))
end

-- Adds { { name, tier, qty } ... } to the shopping list, keeping what's on it.
-- Returns whether it worked.
local function addToList(api, items, listName)
	local lines, byKey = readList(api, listName)
	for _, item in ipairs(items) do
		local term = { searchString = item.name, isExact = true, tier = item.tier, quantity = item.qty }
		local line = byKey[termKey(term)]
		if line then
			line.term.quantity = (line.term.quantity or 0) + item.qty
			line.text = nil -- rebuilt below with the new amount
		else
			line = { term = term }
			byKey[termKey(term)] = line
			lines[#lines + 1] = line
		end
	end
	return writeList(api, listName, lines)
end

-- The list line for an item ({ name, tier }), or nil.
local function lineFor(byKey, item)
	local line = byKey[termKey({ searchString = item.name, isExact = true, tier = item.tier })]
	if line and not line.gone then return line end
end

-- Takes { { name, tier, qty, link, itemID } ... } off the shopping list, lowering
-- amounts and dropping lines that reach zero. Returns what came off ({ { link,
-- qty, itemID, gone } }, gone when its whole line went) and how many lines are
-- left, or nil when Auctionator couldn't update the list.
local function removeFromList(api, items, listName)
	local lines, byKey = readList(api, listName)
	local removed, left = {}, #lines
	for _, item in ipairs(items) do
		local line = lineFor(byKey, item)
		if line then
			local have = line.term.quantity
			if not have or have <= item.qty then
				line.gone = true
				left = left - 1
				removed[#removed + 1] = { link = item.link, qty = have or item.qty, itemID = item.itemID, gone = true }
			else
				line.term.quantity = have - item.qty
				line.text = nil -- rebuilt with the new amount
				removed[#removed + 1] = { link = item.link, qty = item.qty, itemID = item.itemID }
			end
		end
	end
	if #removed == 0 then return removed, left end
	if not writeList(api, listName, lines) then return end
	return removed, left
end

-- "5x [Item], 2x [Item]" for the chat messages.
local function itemList(items)
	local parts = {}
	for _, item in ipairs(items) do parts[#parts + 1] = format("%dx %s", item.qty, item.link) end
	return table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Checking off what you get
---------------------------------------------------------------------------
-- With the "Check off what you get" option on, materials come off the list as
-- your count of them goes up: bought, looted, from the mailbox, crafted. The count
-- is the one "missing" uses (bags, bank, warband bank), so moving things between
-- them changes nothing.
--
-- ns.db.listItems[listName][itemID] = { name, tier }: the lines Craft Profit put on
-- each Auctionator list, saved, since a list outlives the session. Lines you add
-- yourself in Auctionator are left alone, and an entry goes once its line is gone.
-- Craft Profit's own lists (below) are checked off the same way.

-- How many of each listed item you had when last counted (itemID -> count), this
-- session. Only a rise since then is checked off: what you use up just lowers it.
local lastCount = {}

-- After a loading screen, counts are only taken, not checked off, for this long:
-- the bags and banks may still be filling in.
local SETTLE_SECONDS = 5
local settledAt = math.huge

-- Remembers what was just added to a list ({ { itemID, name, tier } ... }).
local function track(listName, items)
	local tracked = ns.db.listItems[listName] or {}
	ns.db.listItems[listName] = tracked
	for _, item in ipairs(items) do
		tracked[item.itemID] = { name = item.name, tier = item.tier }
		-- Counted fresh: an item that came off a list earlier isn't counted anymore.
		lastCount[item.itemID] = ns.Model.Owned(item.itemID)
	end
end

local function forgetList(listName)
	ns.db.listItems[listName] = nil
end

---------------------------------------------------------------------------
-- Craft Profit's own shopping list
---------------------------------------------------------------------------
-- ns.db.ownLists[listName][itemID] = how many are still to buy. Saved for all your
-- characters, under the same names as the Auctionator lists. A list that empties
-- is dropped. ShoppingList.lua is its window.

local function ownChanged()
	ns.ShoppingList.Refresh()
end

-- An item's link for the chat messages, or its name while the link hasn't loaded.
local function itemLink(itemID)
	local name, link = C_Item.GetItemInfo(itemID)
	return link or name or format("item %d", itemID)
end

-- Adds { { itemID, qty } ... } to one of Craft Profit's own lists.
local function addToOwn(listName, items)
	local list = ns.db.ownLists[listName] or {}
	ns.db.ownLists[listName] = list
	for _, item in ipairs(items) do
		list[item.itemID] = (list[item.itemID] or 0) + item.qty
		-- Counted fresh, so only what you get from now on is checked off.
		lastCount[item.itemID] = ns.Model.Owned(item.itemID)
	end
	ownChanged()
end

-- Takes { { itemID, qty } ... } off one of Craft Profit's own lists, lowering
-- amounts and dropping lines that reach zero. Returns what came off ({ { itemID,
-- qty, link, gone } }, gone when its whole line went) and how many lines are left.
local function removeFromOwn(listName, items)
	local list = ns.db.ownLists[listName]
	local removed, left = {}, 0
	if not list then return removed, left end
	local byID = {} -- an item named twice in `items` comes off as one
	for _, item in ipairs(items) do
		local have = list[item.itemID]
		if have then
			local take = math.min(have, item.qty)
			list[item.itemID] = have > take and have - take or nil
			local entry = byID[item.itemID]
			if not entry then
				entry = { itemID = item.itemID, qty = 0, link = itemLink(item.itemID) }
				byID[item.itemID] = entry
				removed[#removed + 1] = entry
			end
			entry.qty, entry.gone = entry.qty + take, have <= take
		end
	end
	for _ in pairs(list) do left = left + 1 end
	if left == 0 then ns.db.ownLists[listName] = nil end
	if #removed > 0 then ownChanged() end
	return removed, left
end

-- Empties these own lists, and says so in chat.
local function clearOwn(names)
	local cleared = {}
	for _, name in ipairs(names) do
		if ns.db.ownLists[name] then
			ns.db.ownLists[name] = nil
			cleared[#cleared + 1] = format("\"%s\"", name)
		end
	end
	if #cleared > 0 then
		ownChanged()
		say(format("Cleared the %s shopping list%s.", table.concat(cleared, ", "), #cleared > 1 and "s" or ""))
	else
		say(#names > 1 and "Your Craft Profit shopping lists are already empty."
			or format("The \"%s\" shopping list is already empty.", names[1]))
	end
end

-- Empties one of Craft Profit's own lists: the Clear button beside its name.
function Shopping.ClearOwn(listName)
	clearOwn({ listName })
end

-- Takes a whole line off one of Craft Profit's own lists: a right-click on it.
function Shopping.RemoveOwn(listName, itemID)
	local list = ns.db.ownLists[listName]
	if list and list[itemID] then removeFromOwn(listName, { { itemID = itemID, qty = list[itemID] } }) end
end

-- Whether any of Craft Profit's own lists has something on it.
function Shopping.OwnHasItems()
	return next(ns.db.ownLists) ~= nil
end

-- Every list this character's materials can go to: one per profession and/or the
-- one without a profession, as the options say.
local function myLists()
	local names, seen = {}, {}
	local function add(name)
		if not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	if ns.db.listPerProfession then
		for _, index in pairs({ GetProfessions() }) do
			local profession = GetProfessionInfo(index)
			if profession then add(Shopping.ListName(profession)) end
		end
	end
	add(Shopping.ListName())
	return names
end

-- Takes what you got (itemID -> amount) off one list. Uses up `gained`, so an item
-- on two lists isn't checked off twice. Entries whose line is gone are forgotten.
local function checkOffList(api, listName, tracked, gained)
	local _, byKey = readList(api, listName)
	local items = {}
	for itemID, info in pairs(tracked) do
		if not lineFor(byKey, info) then
			tracked[itemID] = nil
		elseif (gained[itemID] or 0) > 0 then
			local _, link = C_Item.GetItemInfo(itemID)
			items[#items + 1] = { itemID = itemID, name = info.name, tier = info.tier, qty = gained[itemID], link = link or info.name }
		end
	end
	if not next(tracked) then forgetList(listName) end
	if #items == 0 then return end
	local removed, left = removeFromList(api, items, listName)
	if not removed or #removed == 0 then return end
	for _, item in ipairs(removed) do
		gained[item.itemID] = gained[item.itemID] - item.qty
		if item.gone then tracked[item.itemID] = nil end
	end
	if not next(tracked) then forgetList(listName) end
	say(format("Checked off Auctionator's \"%s\" shopping list: %s.%s", listName, itemList(removed),
		left == 0 and " That's everything on it." or ""))
end

-- The same for one of Craft Profit's own lists.
local function checkOffOwn(listName, gained)
	local items = {}
	for itemID in pairs(ns.db.ownLists[listName] or {}) do
		if (gained[itemID] or 0) > 0 then items[#items + 1] = { itemID = itemID, qty = gained[itemID] } end
	end
	if #items == 0 then return end
	local removed, left = removeFromOwn(listName, items)
	for _, item in ipairs(removed) do gained[item.itemID] = gained[item.itemID] - item.qty end
	say(format("Checked off the \"%s\" shopping list: %s.%s", listName, itemList(removed),
		left == 0 and " That's everything on it." or ""))
end

-- Checks off what you got since the last count, on this character's lists:
-- Craft Profit's own, and Auctionator's when it's loaded. `settling`: only take
-- the counts.
local function checkOff(settling)
	if not (ns.db and ns.db.checkOff) then
		lastCount = {} -- start over when it's turned back on
		return
	end
	local api = auctionatorAPI()
	settling = settling or GetTime() < settledAt
	local lists, gained, anyGained = myLists(), {}, false
	local function count(itemID)
		if gained[itemID] ~= nil then return end
		local now, before = ns.Model.Owned(itemID), lastCount[itemID]
		lastCount[itemID] = now
		gained[itemID] = (not settling and before and now > before) and now - before or 0
		anyGained = anyGained or gained[itemID] > 0
	end
	for _, listName in ipairs(lists) do
		for itemID in pairs(ns.db.ownLists[listName] or {}) do count(itemID) end
		for itemID in pairs(api and ns.db.listItems[listName] or {}) do count(itemID) end
	end
	if not anyGained then return end
	for _, listName in ipairs(lists) do
		checkOffOwn(listName, gained)
		local tracked = api and ns.db.listItems[listName]
		if tracked then checkOffList(api, listName, tracked, gained) end
	end
end

-- Craft Profit's own lists that have something on them, this character's first:
-- { { name, mine, items = { { itemID, qty } ... } } ... }, the items by name.
function Shopping.OwnLists()
	local mine = {}
	for _, name in ipairs(myLists()) do mine[name] = true end
	local function byName(a, b)
		local nameA, nameB = C_Item.GetItemNameByID(a.itemID) or "", C_Item.GetItemNameByID(b.itemID) or ""
		if nameA ~= nameB then return nameA < nameB end
		return a.itemID < b.itemID
	end
	local lists = {}
	for name, amounts in pairs(ns.db.ownLists) do
		local list = { name = name, mine = mine[name] or false, items = {} }
		for itemID, qty in pairs(amounts) do list.items[#list.items + 1] = { itemID = itemID, qty = qty } end
		if #list.items > 0 then
			table.sort(list.items, byName)
			lists[#lists + 1] = list
		end
	end
	table.sort(lists, function(a, b)
		if a.mine ~= b.mine then return a.mine end
		return a.name < b.name
	end)
	return lists
end

---------------------------------------------------------------------------
-- Lists from before the rename
---------------------------------------------------------------------------
-- Up to 1.18 the lists were named "Craft Profit - Snir - Blacksmithing", or just
-- "Craft Profit". Each login moves every old list, any character's, onto today's
-- name, adding up amounts the new list already has, and takes its check-off
-- tracking along.

local OLD_LIST = "Craft Profit"

local function newListName(oldName)
	if oldName == OLD_LIST then return ns.SHOPPING_LIST end
	local prefix = OLD_LIST .. " - "
	if oldName:sub(1, #prefix) == prefix then return oldName:sub(#prefix + 1) end
end

-- Auctionator's API can neither list nor delete lists, so this uses its list
-- manager. Nil when that's changed.
local function listManager()
	local manager = Auctionator.Shopping and Auctionator.Shopping.ListManager
	if manager and manager.GetCount and manager.GetByIndex and manager.Delete then return manager end
end

-- The names of all of Auctionator's shopping lists.
local function allListNames()
	local names, manager = {}, listManager()
	if not manager then return names end
	local ok, count = pcall(manager.GetCount, manager)
	for index = 1, ok and count or 0 do
		local listOK, list = pcall(manager.GetByIndex, manager, index)
		local name = listOK and list and list.GetName and list:GetName()
		if type(name) == "string" then names[#names + 1] = name end
	end
	return names
end

-- Deletes the list, or empties it when Auctionator's list manager has changed.
-- Returns whether it's gone.
local function deleteList(api, listName)
	local manager = listManager()
	if manager and pcall(manager.Delete, manager, listName) then return true end
	pcall(api.CreateShoppingList, ADDON_NAME, listName, {})
	return false
end

-- Returns whether the old list is gone.
local function moveList(api, oldName, newName)
	local searchStrings = call(api.GetShoppingListItems, oldName)
	if searchStrings then
		if #searchStrings > 0 then
			local lines, byKey = readList(api, newName)
			for _, searchString in ipairs(searchStrings) do
				local term = call(api.ConvertFromSearchString, searchString)
				local line = type(term) == "table" and type(term.searchString) == "string" and byKey[termKey(term)]
				if not line then
					lines[#lines + 1] = { text = searchString }
				elseif line.term.quantity and term.quantity then
					line.term.quantity = line.term.quantity + term.quantity
					line.text = nil -- rebuilt with the new amount
				end
			end
			if not writeList(api, newName, lines) then return false end
		end
	end
	local tracked = ns.db.listItems[oldName]
	if tracked then
		local into = ns.db.listItems[newName] or {}
		for itemID, item in pairs(tracked) do into[itemID] = into[itemID] or item end
		ns.db.listItems[newName] = into
		ns.db.listItems[oldName] = nil
	end
	return searchStrings ~= nil and deleteList(api, oldName)
end

local function moveOldLists()
	local api = auctionatorAPI()
	if not (api and ns.db) then return end
	local oldNames, seen = {}, {}
	local function add(name)
		if not seen[name] and newListName(name) then
			seen[name] = true
			oldNames[#oldNames + 1] = name
		end
	end
	for _, name in ipairs(allListNames()) do add(name) end
	for name in pairs(ns.db.listItems) do add(name) end
	local moved = 0
	for _, oldName in ipairs(oldNames) do
		if moveList(api, oldName, newListName(oldName)) then moved = moved + 1 end
	end
	if moved > 0 then
		say(format("Renamed %d Auctionator shopping %s: \"%s\" is no longer part of the name.",
			moved, moved == 1 and "list" or "lists", OLD_LIST))
	end
end

local counter = CreateFrame("Frame")
counter:RegisterEvent("PLAYER_ENTERING_WORLD")
counter:RegisterEvent("BAG_UPDATE_DELAYED")
counter:SetScript("OnEvent", function(_, event, isInitialLogin, isReload)
	if event == "PLAYER_ENTERING_WORLD" then
		if isInitialLogin or isReload then moveOldLists() end
		settledAt = GetTime() + SETTLE_SECONDS
		C_Timer.After(SETTLE_SECONDS, function() checkOff(true) end)
	end
	checkOff()
end)

-- Sorts the missing materials into auction house, vendor and can't-buy once their
-- item info has loaded, then calls andThen(auction, vendor, bound), each a list of
-- { itemID, name, link, tier, qty }.
local function sortMissing(missing, andThen)
	local container = ContinuableContainer:Create()
	for _, material in ipairs(missing) do
		container:AddContinuable(Item:CreateFromItemID(material.itemID))
	end
	container:ContinueOnLoad(function()
		local auction, vendor, bound = {}, {}, {}
		for _, material in ipairs(missing) do
			local name, link, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(material.itemID)
			local tier = C_TradeSkillUI.GetItemReagentQualityByItemInfo(material.itemID)
			local item = {
				itemID = material.itemID, name = name, link = link or name, qty = material.qty,
				tier = tier and tier > 0 and tier or nil,
			}
			if not name then
				-- Never loaded; nothing to search for.
			elseif ns.Prices.BuysAtVendor(material.itemID) then
				vendor[#vendor + 1] = item
			elseif bindType and not TRADEABLE[bindType] then
				bound[#bound + 1] = item
			else
				auction[#auction + 1] = item
			end
		end
		andThen(auction, vendor, bound)
	end)
end

-- One missing material in a tooltip, with a warning under it when it's bought on
-- the auction house but a vendor sells it for less ("Buy vendor items on the
-- auction house" on).
function Shopping.AddMissingLine(tip, itemID, qty)
	tip:AddLine(ns.Format.Item(itemID, qty), 1, 1, 1)
	local atVendor, onAH = ns.Prices.VendorCheaper(itemID)
	if atVendor then
		tip:AddLine(ns.Color("warning", format("   Cheaper at a vendor: %s (auction house %s)",
			ns.Format.Money(atVendor), ns.Format.Money(onAH))))
	end
end

-- The materials no auction house search covers, listed in chat. With "Buy vendor
-- items on the auction house" on, also the ones on the list that a vendor sells
-- for less.
local function sayUnbuyable(vendor, bound, auction)
	if #vendor > 0 then say("Buy from a vendor: " .. itemList(vendor) .. ".") end
	if #bound > 0 then say("Not on the auction house (soulbound): " .. itemList(bound) .. ".") end
	local cheaper = {}
	for _, item in ipairs(auction or {}) do
		local atVendor, onAH = ns.Prices.VendorCheaper(item.itemID)
		if atVendor then
			cheaper[#cheaper + 1] = format("%s (%s at a vendor, %s on the auction house)", item.link,
				ns.Format.Money(atVendor), ns.Format.Money(onAH))
		end
	end
	if #cheaper > 0 then say(ns.Color("warning", "Cheaper at a vendor: ") .. table.concat(cheaper, ", ") .. ".") end
end

-- Adds the auction house materials to the list.
-- `forText` says what they're for in chat: "5 crafts", "3 patron orders".
local function sendToAuctionator(api, missing, forText, listName)
	-- Picked now: the window may close before the items load.
	listName = listName or Shopping.ListName()
	sortMissing(missing, function(auction, vendor, bound)
		if #auction > 0 then
			if addToList(api, auction, listName) then
				track(listName, auction)
				say(format("Added to Auctionator's \"%s\" shopping list, for %s: %s.",
					listName, forText, itemList(auction)))
			else
				say(ns.Color("warning", "Auctionator couldn't update the shopping list."))
			end
		end
		sayUnbuyable(vendor, bound, auction)
	end)
end

-- The same, to Craft Profit's own list.
local function sendToOwn(missing, forText, listName)
	-- Picked now: the window may close before the items load.
	listName = listName or Shopping.ListName()
	sortMissing(missing, function(auction, vendor, bound)
		if #auction > 0 then
			addToOwn(listName, auction)
			say(format("Added to the \"%s\" shopping list, for %s: %s.", listName, forText, itemList(auction)))
			ns.ShoppingList.Added()
		end
		sayUnbuyable(vendor, bound, auction)
	end)
end

-- The popup with a TSM search to copy. It can't be edited, so a stray key
-- doesn't break it.
StaticPopupDialogs.CRAFTPROFIT_TSM_SEARCH = {
	text = "TSM search for %s\n\nPress Ctrl+C to copy it, then paste it into the search box on TSM's Shopping tab.",
	button1 = CLOSE,
	hasEditBox = true,
	editBoxWidth = 320,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnShow = function(self, data)
		local editBox = self.GetEditBox and self:GetEditBox() or self.editBox
		editBox:SetMaxLetters(0)
		editBox:SetText(data or self.data or "")
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	EditBoxOnTextChanged = function(editBox, data)
		local search = data or editBox:GetParent().data
		if search and editBox:GetText() ~= search then
			editBox:SetText(search)
			editBox:HighlightText()
		end
	end,
	EditBoxOnEnterPressed = function(editBox) editBox:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
}

-- Shows a TSM Shopping search for the auction house materials. Each rank of a
-- material is its own item, so "i:<itemID>" buys exactly that rank, and "/x<qty>"
-- stops at the amount needed; ";" puts several in one search.
local function copyTSMSearch(missing, forText)
	sortMissing(missing, function(auction, vendor, bound)
		if #auction > 0 then
			local parts = {}
			for _, item in ipairs(auction) do parts[#parts + 1] = format("i:%d/x%d", item.itemID, item.qty) end
			say(format("TSM search for %s: %s.", forText, itemList(auction)))
			StaticPopup_Show("CRAFTPROFIT_TSM_SEARCH", forText, nil, table.concat(parts, ";"))
		end
		sayUnbuyable(vendor, bound, auction)
	end)
end

-- Empties the shopping list (see listsToClear): Craft Profit's own when that's
-- where materials go, else Auctionator's. Auctionator's API can't delete a list,
-- so an empty one is left behind; the next add fills it again.
function Shopping.Clear(listName)
	if Shopping.ListTarget() == "own" then return clearOwn(listsToClear(listName)) end
	local api = auctionatorAPI()
	if not api then
		say(ns.Color("warning", "Auctionator is not loaded."))
		return
	end
	local names, cleared, failed = listsToClear(listName), {}, false
	for _, name in ipairs(names) do
		local items = call(api.GetShoppingListItems, name)
		if items and #items > 0 then
			if pcall(api.CreateShoppingList, ADDON_NAME, name, {}) then
				cleared[#cleared + 1] = format("\"%s\"", name)
				forgetList(name)
			else
				failed = true
			end
		else
			forgetList(name)
		end
	end
	if failed then say(ns.Color("warning", "Auctionator couldn't clear the shopping list.")) end
	if #cleared > 0 then
		say(format("Cleared Auctionator's %s shopping list%s.", table.concat(cleared, ", "), #cleared > 1 and "s" or ""))
	elseif not failed then
		say(#names > 1 and "Your Craft Profit shopping lists are already empty."
			or format("Auctionator's \"%s\" shopping list is already empty.", names[1]))
	end
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------

-- Craft counts the menu always offers.
local PRESET_CRAFTS = { 1, 5, 10 }
local MAX_CRAFTS = 999

-- The last count typed into "Other amount...", offered in the menu until you
-- log out or /reload.
local customCrafts

-- "1 craft", "5 crafts".
function Shopping.CraftsText(crafts)
	return format("%d craft%s", crafts, crafts == 1 and "" or "s")
end

-- How many items a missing list adds up to.
function Shopping.Total(missing)
	local total = 0
	for _, material in ipairs(missing) do total = total + material.qty end
	return total
end

-- Whether materials go to a list that keeps them, Auctionator's or Craft
-- Profit's own, and not to a TSM search: a list can be cleared (Ctrl-click on the
-- button), and what was added can be taken back off.
function Shopping.CanClear()
	local target = Shopping.ListTarget()
	return target == "auctionator" or target == "own"
end

Shopping.Say = say

-- Adds missing materials ({ { itemID, qty } ... }) to the shopping list.
-- `forText` says what they're for in chat: "5 crafts", "3 patron orders".
-- `listName` defaults to the current list.
function Shopping.AddMissing(missing, forText, listName)
	if #missing == 0 then
		say(format("Nothing missing for %s.", forText))
		return
	end
	local target = Shopping.ListTarget()
	if target == "tsm" then
		copyTSMSearch(missing, forText)
	elseif target == "auctionator" then
		sendToAuctionator(auctionatorAPI(), missing, forText, listName)
	elseif target == "own" then
		sendToOwn(missing, forText, listName)
	else
		say(ns.Color("warning", "The shopping list is turned off in the options."))
	end
end

-- Takes materials ({ { itemID, qty } ... }) back off the shopping list.
-- `forText` says what they were for in chat.
function Shopping.RemoveMissing(missing, forText)
	if Shopping.ListTarget() == "own" then
		local listName = Shopping.ListName()
		local removed = removeFromOwn(listName, missing)
		if #removed == 0 then
			say(format("Nothing on the shopping list for %s.", forText))
		else
			say(format("Removed from the \"%s\" shopping list, for %s: %s.", listName, forText, itemList(removed)))
		end
		return
	end
	local api = auctionatorAPI()
	if not api then
		say(ns.Color("warning", "Auctionator is not loaded."))
		return
	end
	local container = ContinuableContainer:Create()
	for _, material in ipairs(missing) do
		container:AddContinuable(Item:CreateFromItemID(material.itemID))
	end
	local listName = Shopping.ListName()
	container:ContinueOnLoad(function()
		local items = {}
		for _, material in ipairs(missing) do
			local name, link = C_Item.GetItemInfo(material.itemID)
			if name then
				local tier = C_TradeSkillUI.GetItemReagentQualityByItemInfo(material.itemID)
				items[#items + 1] = { name = name, link = link or name, qty = material.qty, tier = tier and tier > 0 and tier or nil }
			end
		end
		local removed = removeFromList(api, items, listName)
		if not removed then
			say(ns.Color("warning", "Auctionator couldn't update the shopping list."))
		elseif #removed == 0 then
			say(format("Nothing on the shopping list for %s.", forText))
		else
			say(format("Removed from Auctionator's \"%s\" shopping list, for %s: %s.",
				listName, forText, itemList(removed)))
		end
	end)
end

local function addForCrafts(model, crafts)
	Shopping.AddMissing(model.missingFor(crafts), Shopping.CraftsText(crafts), model.listName)
end

-- The typed count from "Other amount...", remembered for the menu.
local function acceptCustom(text, model)
	local crafts = tonumber(text)
	if not crafts or crafts < 1 then return end
	crafts = math.min(math.floor(crafts), MAX_CRAFTS)
	customCrafts = crafts
	addForCrafts(model, crafts)
end

-- The popup's edit box (its name changed between game versions).
local function popupEditBox(popup)
	return popup.GetEditBox and popup:GetEditBox() or popup.editBox
end

-- "Other amount...": asks for a number of crafts.
StaticPopupDialogs.CRAFTPROFIT_CRAFTS = {
	text = "Buy materials for how many crafts?",
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = #tostring(MAX_CRAFTS),
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnShow = function(self)
		local editBox = popupEditBox(self)
		editBox:SetNumeric(true)
		editBox:SetText(tostring(customCrafts or ""))
		editBox:HighlightText()
	end,
	OnAccept = function(self, model)
		acceptCustom(popupEditBox(self):GetText(), model)
	end,
	EditBoxOnEnterPressed = function(editBox, model)
		acceptCustom(editBox:GetText(), model)
		editBox:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
}

-- The menu a click on the button opens.
-- The menu of craft counts for `model`, added to `root`: a menu or a submenu.
function Shopping.AddCraftCounts(root, model)
	local tsm = Shopping.ListTarget() == "tsm"
	root:CreateTitle(tsm and "Copy a TSM search" or format("Add to \"%s\" list", model.listName or Shopping.ListName()))

	local counts = { unpack(PRESET_CRAFTS) }
	if customCrafts and not tContains(counts, customCrafts) then
		counts[#counts + 1] = customCrafts
		table.sort(counts)
	end
	for _, crafts in ipairs(counts) do
		local total = Shopping.Total(model.missingFor(crafts))
		local note = total > 0 and format("(%d missing)", total) or "(nothing missing)"
		local button = root:CreateButton(format("For %s %s", Shopping.CraftsText(crafts), ns.Color("muted", note)),
			function() addForCrafts(model, crafts) end)
		button:SetEnabled(total > 0)
	end
	root:CreateButton("Other amount...", function() StaticPopup_Show("CRAFTPROFIT_CRAFTS", nil, nil, model) end)

	if not tsm then
		root:CreateDivider()
		if Shopping.ListTarget() == "own" then root:CreateButton("Show shopping list", ns.ShoppingList.Show) end
		root:CreateButton("Clear shopping list", function() Shopping.Clear(model.listName) end)
	end
	Shopping.AddShopWithChoice(root)
end

local function openMenu(owner, model)
	GameTooltip:Hide()
	MenuUtil.CreateContextMenu(owner, function(_, root) Shopping.AddCraftCounts(root, model) end)
end

-- What a click on the panel's button does: adds what's missing for one craft.
-- Right-click (`menu`) opens the menu of craft counts, Ctrl-click (`ctrl`) clears
-- the shopping list. `owner` is the button, for the menu to open from.
-- `model.listName` is the list, when it isn't the current one.
function Shopping.Click(model, owner, menu, ctrl)
	if ctrl and Shopping.CanClear() then
		Shopping.Clear(model.listName)
	elseif not Shopping.ListTarget() then
		return
	elseif menu then
		openMenu(owner, model)
	else
		addForCrafts(model, 1)
	end
end
