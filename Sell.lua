-- Craft Profit: the Sell tab of its auction house window (see ShoppingList.lua).
-- It lists what's in your bags that can be auctioned: your favorites, your own
-- crafts, then the rest by the game's kind of item. A section's name folds it
-- away, dragging it moves the section up or down, and a right-click on an item
-- makes it a favorite or hides it. Pick
-- one to see what it's listed for, set the price, amount and how long it lasts,
-- and post it. Every auction is posted by your own click on Post. The game's own
-- sell page is filled in with the same item, price, amount and duration, so its
-- Create Auction button posts the same auction, and what you change there is
-- changed here. While that page shows the item, it shows the listings too, so
-- this tab leaves its own listings out and gives the room to your bags.
local _, ns = ...

local Sell = {}
ns.Sell = Sell

local format = string.format
local Color = ns.Color
local Search = ns.AuctionSearch

local OWNER = "sell"     -- this tab's name in the line of auction house questions
local EDGE = 8           -- window edge to a list's frame
local PAD = 14           -- window edge to the text
local TOP = 28           -- under the title bar
local INSET_PAD = 4      -- list frame to the rows
local SCROLLBAR_ROOM = 22
local SEARCH_HEIGHT = 20 -- the search box over the bag list,
local SEARCH_ROOM = 26   -- and the room it takes with the gap under it
local ROW_HEIGHT, BAG_ROWS = 24, 8
local ICON_SIZE = 20     -- a bag line's item icon
local FOLD_SIZE = 14     -- the plus or minus before a section's name
local COUNT_WIDTH = 48   -- the column of amounts at a bag line's right end
local LIST_GAP = 10      -- under the bag list's frame
local LISTING_HEIGHT, LISTING_ROWS = 20, 4
-- How tall the bag list's frame is, and what it gains while this tab's own
-- listings are left out: the gap, the picked item's line and the listings' frame.
local BAG_HEIGHT = BAG_ROWS * ROW_HEIGHT + 2 * INSET_PAD
local LISTING_ROOM = LIST_GAP + 22 + LISTING_ROWS * LISTING_HEIGHT + 2 * INSET_PAD
-- The frame with that room added, cut to whole lines so the last one is never clipped.
local FULL_HEIGHT = math.floor((BAG_HEIGHT + LISTING_ROOM - 2 * INSET_PAD) / ROW_HEIGHT) * ROW_HEIGHT + 2 * INSET_PAD
local LINE = 26          -- from one line of the form to the next
local NOTE_LINE = 16     -- the totals, and the message under them: one line of text each
local LABEL_WIDTH = 66   -- "Price", "Amount", "Lasts"
local COIN = 14          -- coin icons beside the price boxes
-- How long Post waits for the auction house to say the auction is up, in seconds.
local POST_WAIT = 8
-- Bag items the game hasn't loaded yet are looked at again this often, this many times.
local SCAN_WAIT, SCAN_TRIES = 0.5, 6
-- How long an auction lasts, by the game's number for it.
local DURATIONS = ns.AUCTION_DURATIONS

local AWAY_TEXT = "Open the auction house to sell from here."
local EMPTY_TEXT = "Nothing in your bags can be auctioned."
local NO_MATCH_TEXT = "Nothing in your bags matches that."
-- The list's first two sections, and the one for an item whose kind the game doesn't say.
-- The rest are named after the game's kinds of item (Consumable, Tradeskill...).
local FAVORITES, CRAFTS, OTHER = "Favorites", "Your crafts", "Other"
-- A section name's sign: folded away, or open.
local FOLDED_ICON, OPEN_ICON = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"
local PICK_TEXT = "Pick something from the list to sell it."

local panel, body, away, emptyText
local bagBox, listingBox, pickedText, sourceText
-- The frame around the bag list, and everything that shows the picked item's
-- listings (its line, the list, its frame and scroll bar).
local bagInset, listingParts
local goldBox, silverBox, copperBox, eachText, amountBox, ofText
local durationButtons = {}
local totalsText, noteText, postButton, skipButton
-- Prices in copper, or only whole silver, as this auction house takes them.
local usesCopper = false

-- What can be sold, in the list's order, and by key: a stackable item's ID, or
-- any other item's link (so two different pieces of gear are two lines).
local entries, byKey = {}, {}
-- The line that's picked, and what was learned about it when it was picked.
local selected, pick
-- How many of the picked item can be posted.
local available = 0
-- What the picked item is listed for, cheapest first; nil until the answer comes.
local listings
-- What the last search or post has to say, shown under the form.
local searchNote
-- Whether you typed a price yourself: the lowest price doesn't replace it then.
local priceTouched = false
-- The auction being posted, until the auction house says it's up.
local posting
-- Whether the items you hid are listed too.
local showHidden = false
-- The search box over the bag list, and what's typed in it, in lower case ("" for nothing).
local searchBox
local filter = ""
-- Items your saved Best crafts scans say you craft: itemID -> true.
local crafts
local scanTries = 0
-- The key of the item this tab put on the game's own sell page, while it's there.
local nativeKey
-- Why the game's own sell page couldn't be filled in last, for /craftprofit testsell.
local nativeProblem
-- Whether this tab is writing to the game's sell page, or reading from it: one
-- never answers the other.
local pushing, pulling = false, false
-- The game's sell pages this tab already follows: page -> true.
local followed = {}
-- Whether this tab's own listings are showing (nil until the first layout).
local listingsShown
-- While Post hands the auction to the game, and whether the game refused it. What
-- the last refusal looked like is kept for /craftprofit testsell.
local calling, refused, lastRefusal = false, false, nil

-- Copper as exact gold, silver and copper: a price to match can't be rounded.
local function exact(copper)
	return GetMoneyString(copper, true)
end

local function locationOf(entry)
	return ItemLocation:CreateFromBagAndSlot(entry.bag, entry.slot)
end

-- What a vendor pays for the item, in copper (nil when the game doesn't know yet).
local function vendorPays(link)
	local _, _, _, _, _, _, _, _, _, _, price = C_Item.GetItemInfo(link)
	return price
end

local function myCrafts()
	local ids = {}
	for _, recipe in ipairs(ns.Scans.Mine()) do
		for _, output in pairs(recipe.outputs) do
			if output.itemID then ids[output.itemID] = true end
		end
	end
	return ids
end

---------------------------------------------------------------------------
-- The form
---------------------------------------------------------------------------

local function getPrice()
	return goldBox:GetNumber() * 10000 + silverBox:GetNumber() * 100 + (copperBox and copperBox:GetNumber() or 0)
end

-- Fills in a price, or with nil empties the boxes.
local function setPrice(copper)
	if not copper or copper <= 0 then
		goldBox:SetText("")
		silverBox:SetText("")
		if copperBox then copperBox:SetText("") end
		return
	end
	if not copperBox then copper = math.ceil(copper / 100) * 100 end
	goldBox:SetText(tostring(math.floor(copper / 10000)))
	silverBox:SetText(tostring(math.floor(copper % 10000 / 100)))
	if copperBox then copperBox:SetText(tostring(copper % 100)) end
end

local function depositFor(entry, qty)
	local ok, deposit
	if entry.commodity then
		ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit, entry.itemID, ns.db.sellDuration, qty)
	else
		ok, deposit = pcall(C_AuctionHouse.CalculateItemDeposit, locationOf(entry), ns.db.sellDuration, qty)
	end
	deposit = ok and deposit or 0
	if not usesCopper then deposit = math.ceil(deposit / 100) * 100 end
	return deposit
end

-- The deposit and what you get, what's wrong with the form if anything, and
-- whether Post can be clicked.
local function updateTotals()
	if not selected then
		totalsText:SetText("")
		noteText:SetText(Color("muted", searchNote or PICK_TEXT))
		postButton:Disable()
		skipButton:Disable()
		return
	end
	skipButton:Enable()
	local price, qty = getPrice(), amountBox:GetNumber()
	local deposit = qty >= 1 and depositFor(selected, qty) or 0
	local text = "Deposit: " .. exact(deposit)
	if price > 0 and qty >= 1 then
		text = text .. format("     You get: %s (%d%% cut)", exact(math.floor(price * qty * (1 - ns.AH_CUT))),
			ns.AH_CUT * 100)
	end
	totalsText:SetText(text)

	local problem
	if qty < 1 then
		problem = "Enter an amount."
	elseif qty > available then
		problem = format("You only have %d to sell.", available)
	elseif price <= 0 then
		-- Why none was filled in comes first (none for sale, under vendor price...).
		problem = listings and (searchNote or "Enter a price.") or nil
	elseif deposit > GetMoney() then
		problem = "You can't pay the deposit."
	end
	local vendor = price > 0 and vendorPays(selected.link)
	if problem then
		noteText:SetText(Color("warning", problem))
	elseif vendor and vendor > 0 and price < vendor then
		noteText:SetText(Color("warning", format("That's less than a vendor pays (%s).", exact(vendor))))
	else
		noteText:SetText(searchNote and Color("muted", searchNote) or "")
	end
	postButton:SetEnabled(not problem and price > 0 and not posting)
end

---------------------------------------------------------------------------
-- The game's own sell page
---------------------------------------------------------------------------
-- This drives Blizzard's own auction house window, which a game update can
-- change, so every step into it goes through `guarded`: when one fails, the
-- game's page just isn't filled in and this tab works as before.

-- The game's sell page for that kind of item, and its window, while the window
-- is the one on screen.
local function nativePage(entry)
	local auctionHouse = Search.GameWindow()
	if not (auctionHouse and auctionHouse.SetPostItem) then return end
	return entry.commodity and auctionHouse.CommoditiesSellFrame or auctionHouse.ItemSellFrame, auctionHouse
end

-- Whether the game's sell page holds that line's item: something else you put
-- there yourself is never written over.
local function holds(page, entry)
	local held = page:GetItem()
	if not held then return false end
	local bag, slot = held:GetBagAndSlot()
	return bag == entry.bag and slot == entry.slot
end

-- Whether the game's sell page is showing the picked item, and so its listings.
local function nativeShows()
	if not (selected and nativeKey == selected.key) then return false end
	local ok, shows = pcall(function()
		local page = nativePage(selected)
		return page ~= nil and page:IsVisible() and holds(page, selected)
	end)
	return ok and shows == true
end

-- This tab's own listings only show while the game's page isn't showing the
-- same ones. Without them the bag list takes their room.
local function layout()
	if not bagInset then return end
	local own = selected ~= nil and not nativeShows()
	if own == listingsShown then return end
	listingsShown = own
	bagInset:SetHeight(own and BAG_HEIGHT or FULL_HEIGHT)
	for _, part in ipairs(listingParts) do part:SetShown(own) end
end

local pullNative, syncNative
-- The game's sell page changed and hasn't been looked at yet, and whether that
-- change was the page setting itself up again (its item put back on it, which
-- resets its price and amount) and not something you did.
local syncDue, nativeReset = false, false

-- Follows one of the game's sell pages from now on: what changes on it, and
-- when it shows or hides. Hooks, so the game's own code runs untouched. A change
-- is looked at a moment later: the page resets its fields before it says its
-- item was set, and only then is it clear which of the two it was.
local function follow(page)
	if followed[page] then return end
	followed[page] = true
	hooksecurefunc(page, "UpdatePostState", function()
		if pushing or syncDue then return end
		syncDue = true
		C_Timer.After(0, syncNative)
	end)
	hooksecurefunc(page, "SetItem", function()
		if not pushing then nativeReset = true end
	end)
	page:HookScript("OnShow", layout)
	page:HookScript("OnHide", layout)
end

-- Puts the item on the game's sell page, as a right-click on it in your bags does.
local function putNative(entry)
	nativeKey = nil
	local page, auctionHouse = nativePage(entry)
	if not page then return end
	follow(page)
	pushing = true
	auctionHouse:SetPostItem(locationOf(entry))
	pushing = false
	if holds(page, entry) then nativeKey = entry.key end
end

-- Copies this tab's price, amount and duration to the game's sell page, while
-- it still holds the item this tab put there.
local function fillNative()
	if not (selected and nativeKey == selected.key) then return end
	local page = nativePage(selected)
	if not (page and holds(page, selected)) then return end
	if pulling then return end
	pushing = true
	if page:GetDuration() ~= ns.db.sellDuration then
		page.Duration:SetDuration(ns.db.sellDuration)
		page.Duration.Dropdown:GenerateMenu()
	end
	page.QuantityInput:SetQuantity(amountBox:GetNumber())
	page.PriceInput:SetAmount(getPrice())
	page:UpdatePostState()
	pushing = false
end

-- Takes this tab's item off the game's sell page again.
local function clearNative()
	if not nativeKey then return end
	nativeKey = nil
	local auctionHouse = AuctionHouseFrame
	if auctionHouse and auctionHouse:IsVisible() and auctionHouse.ClearPostItem then auctionHouse:ClearPostItem() end
end

-- The game's sell page lost the picked item (it empties itself after its own
-- Create Auction): it goes back on while you still have some.
local function restoreNative()
	if not (selected and nativeKey == selected.key) then return end
	local page = nativePage(selected)
	if page and not page:GetItem() then
		putNative(selected)
		fillNative()
	end
end

-- Back on this tab with something picked: the game's window goes back to its
-- sell page for it, if it was looking at something else.
local function showPicked()
	if not (selected and nativeKey == selected.key) then return end
	local page, auctionHouse = nativePage(selected)
	if not page or page:IsVisible() then return end
	if holds(page, selected) then
		auctionHouse:SetDisplayMode(selected.commodity and AuctionHouseFrameDisplayMode.CommoditiesSell
			or AuctionHouseFrameDisplayMode.ItemSell)
	elseif not page:GetItem() then
		putNative(selected)
		fillNative()
	end
end

local function guarded(step, ...)
	local ok, problem = pcall(step, ...)
	pushing = false
	if not ok then nativeProblem = tostring(problem) end
end

-- Testing: why the game's own sell page couldn't be filled in.
function Sell.Explain()
	ns.Shopping.Say(nativeProblem and ("Testing: the game's sell page couldn't be filled in: " .. nativeProblem)
		or "Testing: filling in the game's sell page hasn't failed.")
	ns.Shopping.Say(lastRefusal and ("Testing: the game refused the last Post click (" .. lastRefusal .. ").")
		or "Testing: the game hasn't refused a Post click.")
end

local function drawDurations()
	for index, button in ipairs(durationButtons) do
		local chosen = index == ns.db.sellDuration
		button:SetNormalFontObject(chosen and "GameFontHighlight" or "GameFontNormal")
		if chosen then button:LockHighlight() else button:UnlockHighlight() end
	end
end

-- The game's sell page changed (a listing was clicked there, or something was
-- typed): its price, amount and duration become this tab's, so both always post
-- the same auction.
pullNative = function(page)
	if pushing or pulling or not nativeShows() then return end
	if page ~= nativePage(selected) then return end
	local price, qty, duration = page.PriceInput:GetAmount(), page.QuantityInput:GetQuantity(), page:GetDuration()
	pulling = true
	if price ~= getPrice() then
		priceTouched = true -- your choice over there: the lowest listing doesn't replace it
		setPrice(price)
	end
	if qty >= 1 and qty ~= amountBox:GetNumber() then amountBox:SetText(tostring(qty)) end
	if durationButtons[duration] and duration ~= ns.db.sellDuration then
		ns.db.sellDuration = duration
		drawDurations()
	end
	pulling = false
	updateTotals()
end

-- A moment after the game's sell page changed. When the page set itself up
-- again, this tab's price and amount go back on it; otherwise the change was
-- yours, and it becomes this tab's.
syncNative = function()
	syncDue = false
	local reset = nativeReset
	nativeReset = false
	if reset then
		guarded(fillNative)
	elseif selected then
		local ok, problem = pcall(function() pullNative((nativePage(selected))) end)
		if not ok then
			pulling = false
			nativeProblem = tostring(problem)
		end
	end
	layout()
end

---------------------------------------------------------------------------
-- What the picked item is listed for
---------------------------------------------------------------------------

local function listingClick(row)
	local data = row.data
	if not data then return end
	priceTouched = true
	setPrice(data.price)
	updateTotals()
end

local function listingTooltip(row)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Click: use this price", 1, 1, 1)
	GameTooltip:Show()
end

local function drawListing(row, data)
	if not row.text then
		row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
		row.highlight:SetAllPoints()
		row.highlight:SetColorTexture(1, 1, 1, 0.08)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetPoint("LEFT", 6, 0)
		row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.detail:SetPoint("RIGHT", -6, 0)
		row:SetScript("OnClick", listingClick)
		row:SetScript("OnEnter", listingTooltip)
		row:SetScript("OnLeave", GameTooltip_Hide)
	end
	row.data = data
	row.text:SetText(exact(data.price))
	local detail
	if pick and pick.equipment then
		detail = format("item level %d", data.itemLevel or 0)
	elseif selected and selected.commodity then
		detail = format("%s for sale", BreakUpLargeNumbers(data.qty))
	else
		detail = data.qty > 1 and format("%d for sale", data.qty) or ""
	end
	if data.mine then detail = (detail ~= "" and (detail .. ", ") or "") .. Color("good", "yours") end
	row.detail:SetText(Color("muted", detail))
end

local function drawListings()
	listingBox:SetDataProvider(CreateDataProvider(listings or {}))
end

-- The auction house answered (or didn't) for the picked item: its listings, and
-- the lowest one as the price, unless you typed one or a vendor pays more.
local function onListings(results)
	listings = results and results.rows or {}
	drawListings()
	if not results then
		searchNote = "The auction house didn't answer. Pick the item again."
	elseif #listings == 0 then
		searchNote = "None for sale right now."
	else
		searchNote = nil
		local best
		for _, row in ipairs(listings) do
			if not pick.equipment or pick.anyLevel or row.itemLevel == pick.itemLevel then
				best = row
				break
			end
		end
		if not best then
			searchNote = "None of your item level for sale right now."
		elseif not priceTouched then
			local vendor = vendorPays(selected.link)
			if vendor and vendor > 0 and best.price < vendor then
				searchNote = "The lowest price is under vendor price: none filled in."
			else
				setPrice(best.price)
			end
		end
	end
	updateTotals()
end

---------------------------------------------------------------------------
-- The list of what's in your bags
---------------------------------------------------------------------------

local drawBags

local function drawPicked()
	if not selected then
		pickedText:SetText("")
		sourceText:SetText("")
		eachText:SetText("")
		ofText:SetText("")
		return
	end
	pickedText:SetText(ns.Format.Sellable(selected.itemID, selected.link, selected.count))
	local price, source = ns.Prices.SaleFrom(selected.link, selected.itemID)
	local names = { auctionator = "Auctionator", own = "Last scan" }
	sourceText:SetText(price and Color("muted", format("%s: %s", names[source] or "TSM", ns.Format.Money(price))) or "")
	eachText:SetText(Color("muted", (selected.commodity and available > 1) and "each" or ""))
	ofText:SetText(Color("muted", format("of %d", available)))
end

-- Picks a line to sell (nil for none): the amount is all you have, and the
-- auction house is asked what it's listed for.
local function choose(entry, said)
	Search.Drop(OWNER)
	local before = selected and selected.key
	selected, pick, listings, priceTouched = entry, nil, nil, false
	-- A newly picked item starts on your default posting time, when you set one.
	local default = tonumber(ns.db.sellDefault)
	if entry and entry.key ~= before and default and DURATIONS[default] then
		ns.db.sellDuration = default
		drawDurations()
	end
	setPrice(nil)
	drawListings()
	if not entry then
		available = 0
		amountBox:SetText("")
		searchNote = said
		drawPicked()
		drawBags()
		updateTotals()
		guarded(clearNative)
		layout()
		return
	end
	local location = locationOf(entry)
	available = math.max(C_AuctionHouse.GetAvailablePostCount(location) or 0, 1)
	amountBox:SetText(tostring(available))
	local itemKey = C_AuctionHouse.GetItemKeyFromItem(location)
	-- Whether it's gear: the auction house says, once it has loaded the item.
	local info = C_AuctionHouse.GetItemKeyInfo(itemKey)
	local equipment
	if info then equipment = info.isEquipment else equipment = C_Item.IsEquippableItem(entry.link) end
	pick = { key = entry.key, equipment = equipment or false }
	if pick.equipment then
		-- Gear is compared with every item level of it, as the game's own sell page
		-- does, and priced from the ones of its own level (any level for green items).
		pick.itemLevel = C_Item.GetCurrentItemLevel(location)
		pick.anyLevel = C_Item.GetItemQuality(location) == Enum.ItemQuality.Uncommon
		itemKey.itemLevel, itemKey.itemSuffix = 0, 0
	end
	searchNote = (said and (said .. " ") or "") .. "Checking prices..."
	local key = entry.key
	Search.Request(OWNER, itemKey, pick.equipment, function(results)
		if selected and selected.key == key then onListings(results) end
	end, entry.commodity)
	drawPicked()
	drawBags()
	updateTotals()
	guarded(putNative, entry)
	guarded(fillNative)
	layout()
end

-- A name without the icons it can carry: an item's link has its quality icon
-- inside the brackets, after the name.
local function withoutIcons(name)
	return strtrim((name:gsub("|A.-|a", ""):gsub("|T.-|t", "")))
end

-- An item's name as plain text ("" while the game has none). A caged pet's is in
-- its link, as its item is only the cage; so is any item's the game hasn't loaded.
local function plainName(entry)
	local name = entry.itemID ~= ns.PET_CAGE_ITEM and ns.Format.ItemName(entry.itemID) or entry.link:match("%[(.-)%]")
	return name and withoutIcons(name) or ""
end

-- Whether the line is one the search box asks for: any part of its name, in any case.
local function matches(entry)
	return filter == "" or plainName(entry):lower():find(filter, 1, true) ~= nil
end

-- The section a line is in: a favorite is only there, not also under its kind.
local function sectionOf(entry)
	if ns.db.sellFavorites[entry.itemID] then return FAVORITES end
	if entry.craft then return CRAFTS end
	return entry.kind or OTHER
end

-- The list as it's shown: its sections in order ({ name, entries }, the lines by
-- name), and the hidden items. The sections are in the order you dragged them
-- into; until you do, and for a section that's new since, it's favorites, your
-- crafts, then the kinds by name. What the search box doesn't ask for is left
-- out of both.
local function sections()
	local byName, list, hidden = {}, {}, {}
	for _, entry in ipairs(entries) do
		if not matches(entry) then
			-- searched away
		elseif ns.db.sellHidden[entry.itemID] then
			hidden[#hidden + 1] = entry
		else
			local name = sectionOf(entry)
			local section = byName[name]
			if not section then
				section = { name = name, entries = {} }
				byName[name] = section
				list[#list + 1] = section
			end
			section.entries[#section.entries + 1] = entry
		end
	end
	local order, first = ns.db.sellOrder, { [FAVORITES] = 1, [CRAFTS] = 2 }
	local function place(name)
		return tIndexOf(order, name) or (#order + (first[name] or 3))
	end
	table.sort(list, function(a, b)
		local placeA, placeB = place(a.name), place(b.name)
		if placeA ~= placeB then return placeA < placeB end
		return a.name < b.name
	end)
	return list, hidden
end

-- Whether a section is folded away. A search shows what it finds anyway.
local function folded(name)
	return filter == "" and ns.db.sellFolded[name] == true
end

---------------------------------------------------------------------------
-- Dragging a section to another place
---------------------------------------------------------------------------

-- The section whose name is being dragged, while the mouse button is down.
local dragging
local dragWatch = CreateFrame("Frame")

-- The section the mouse is over: its name's line or any of its items.
local function sectionUnderMouse()
	local found
	bagBox:ForEachFrame(function(row)
		if row.data and row.data.section and row:IsMouseOver() then found = row.data.section end
	end)
	return found
end

-- While dragging: the section it would land on is lit.
local function markDrop()
	local target = dragging and sectionUnderMouse()
	if target == dragging then target = nil end
	bagBox:ForEachFrame(function(row)
		if row.drop then row.drop:SetShown(target ~= nil and row.data ~= nil and row.data.section == target) end
	end)
end

-- Puts one section where another is: above it when it came from below, under
-- it when it came from above. The order is first written down as it is now.
local function moveSection(moved, target)
	local order = ns.db.sellOrder
	if #order == 0 then order[1], order[2] = FAVORITES, CRAFTS end
	for _, section in ipairs((sections())) do
		if not tContains(order, section.name) then order[#order + 1] = section.name end
	end
	local from, to = tIndexOf(order, moved), tIndexOf(order, target)
	if not (from and to) then return end
	table.remove(order, from)
	table.insert(order, to, moved)
end

local function startDrag(row)
	dragging = row.data.header
	GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
	GameTooltip:SetText("Move " .. dragging, 1, 1, 1)
	GameTooltip:AddLine(Color("simulated", "Drop it on the section it goes next to"))
	GameTooltip:Show()
	dragWatch:SetScript("OnUpdate", markDrop)
end

-- The mouse button is up: the section moves, if it's over another one.
local function stopDrag()
	if not dragging then return end
	local moved, target = dragging, sectionUnderMouse()
	dragging = nil
	dragWatch:SetScript("OnUpdate", nil)
	GameTooltip:Hide()
	if target and target ~= moved then moveSection(moved, target) end
	drawBags()
end

-- The tab went away mid-drag: nothing moves.
local function cancelDrag()
	dragging = nil
	dragWatch:SetScript("OnUpdate", nil)
end

-- The line after `key` in the list as it's shown, or the one before it at the end.
local function neighbor(key)
	local list, hidden = sections()
	local shown = {}
	for _, section in ipairs(list) do
		if not folded(section.name) then
			for _, entry in ipairs(section.entries) do shown[#shown + 1] = entry end
		end
	end
	if showHidden then
		for _, entry in ipairs(hidden) do shown[#shown + 1] = entry end
	end
	for index, entry in ipairs(shown) do
		if entry.key == key then return shown[index + 1] or shown[index - 1] end
	end
end

local function bagTooltip(row)
	if dragging then return end -- the tooltip is saying what's being moved
	local data = row.data
	if data and data.header then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(data.header, 1, 1, 1)
		GameTooltip:AddLine(Color("simulated", data.folded and "Click: open it" or "Click: fold it away"))
		GameTooltip:AddLine(Color("simulated", "Drag: move it up or down the list"))
		GameTooltip:Show()
		return
	end
	local entry = data and data.entry
	if not entry then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetBagItem(entry.bag, entry.slot)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(Color("simulated", "Click: pick it to sell"))
	GameTooltip:AddLine(Color("simulated", ns.db.sellHidden[entry.itemID] and "Right-click: bring it back to the list"
		or "Right-click: make it a favorite, or hide it"))
	GameTooltip:Show()
end

-- A right-click on an item: favorite it, or hide it from the list.
local function bagMenu(row, entry)
	GameTooltip:Hide()
	local itemID = entry.itemID
	MenuUtil.CreateContextMenu(row, function(_, root)
		if not ns.db.sellHidden[itemID] then
			root:CreateButton(ns.db.sellFavorites[itemID] and "Remove from favorites" or "Add to favorites", function()
				ns.db.sellFavorites[itemID] = not ns.db.sellFavorites[itemID] or nil
				drawBags()
			end)
		end
		root:CreateButton(ns.db.sellHidden[itemID] and "Bring back to the list" or "Hide from this list", function()
			ns.db.sellHidden[itemID] = not ns.db.sellHidden[itemID] or nil
			if selected and selected.key == entry.key and ns.db.sellHidden[itemID] then
				choose(nil)
			else
				drawBags()
			end
		end)
	end)
end

local function bagClick(row, mouseButton)
	local data = row.data
	if not data then return end
	if data.toggle then
		showHidden = not showHidden
		drawBags()
		return
	end
	if data.header then
		-- A section's name folds it away or opens it again. A search shows everything it finds.
		if filter == "" then
			ns.db.sellFolded[data.header] = not ns.db.sellFolded[data.header] or nil
			drawBags()
		end
		return
	end
	local entry = data.entry
	if not entry then return end
	if mouseButton == "RightButton" then
		bagMenu(row, entry)
	elseif IsModifiedClick() then
		HandleModifiedItemClick(entry.link)
	else
		choose(entry)
	end
end

-- A bag line's parts: the item's icon, its name, and the amount in a column of
-- its own at the right, so names and amounts each line up down the list.
local function createBagRow(row)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.stripe:SetColorTexture(1, 1, 1, 0.035)
	row.picked = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.picked:SetAllPoints()
	row.picked:SetColorTexture(1, 0.82, 0, 0.2)
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(1, 1, 1, 0.08)
	-- On the section a dragged one would land on.
	row.drop = row:CreateTexture(nil, "BACKGROUND", nil, 2)
	row.drop:SetAllPoints()
	row.drop:SetColorTexture(0.3, 0.6, 1, 0.25)
	row.drop:Hide()
	-- Under a section's name.
	row.rule = row:CreateTexture(nil, "ARTWORK")
	row.rule:SetHeight(1)
	row.rule:SetPoint("BOTTOMLEFT", 4, 3)
	row.rule:SetPoint("BOTTOMRIGHT", -4, 3)
	row.rule:SetColorTexture(1, 0.82, 0, 0.3)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ICON_SIZE, ICON_SIZE)
	row.icon:SetPoint("LEFT", 6, 0)
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- without the icon's own border
	row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.count:SetPoint("RIGHT", -8, 0)
	row.count:SetWidth(COUNT_WIDTH)
	row.count:SetJustifyH("RIGHT")
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row:SetScript("OnClick", bagClick)
	row:SetScript("OnEnter", bagTooltip)
	row:SetScript("OnLeave", function()
		if not dragging then GameTooltip:Hide() end
	end)
	-- Only a section's name is dragged (see drawBag).
	row:SetScript("OnDragStart", function(self)
		if self.data and self.data.header then startDrag(self) end
	end)
	row:SetScript("OnDragStop", stopDrag)
end

-- The item's name in its rarity's color with its quality after it, or plain for
-- a hidden item. A caged pet goes by its link: its item is only the cage.
local function bagName(entry, plain)
	local name = plainName(entry)
	if name == "" then name = "Loading..." end
	if entry.itemID == ns.PET_CAGE_ITEM then
		if not plain then name = entry.link end -- its rarity is the link's color
	elseif not plain then
		name = ns.Format.RarityColored(entry.itemID, name)
	end
	-- The quality icon goes on once: the game's for a material, or else the one in the link.
	local quality = ns.Blizzard.ReagentQualityMarkup(entry.itemID) or entry.link:match("%[.-(|A.-|a)%]")
	return name .. (quality and (" " .. quality) or "")
end

local function drawBag(row, data)
	if not row.text then createBagRow(row) end
	row.data = data
	local entry = data.entry
	row.picked:SetShown(entry ~= nil and selected ~= nil and selected.key == entry.key)
	row.stripe:SetShown(data.stripe == true)
	row.rule:SetShown(data.header ~= nil)
	row.drop:Hide()
	-- A section's name can be dragged; an item's line can't, so a click on it is never taken for a drag.
	if data.header then row:RegisterForDrag("LeftButton") else row:RegisterForDrag() end
	-- An item's line and a section's name both have a sign, a text and a number.
	local columns = entry ~= nil or data.header ~= nil
	row.icon:SetShown(columns)
	row.count:SetShown(columns)
	row.text:ClearAllPoints()
	if columns then
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.text:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
	else
		row.text:SetPoint("LEFT", 6, 0)
		row.text:SetPoint("RIGHT", -6, 0)
	end
	if data.header then
		row.text:SetFontObject("GameFontNormal")
		row.text:SetText(data.header)
		row.icon:SetTexture(data.folded and FOLDED_ICON or OPEN_ICON)
		row.icon:SetTexCoord(0, 1, 0, 1)
		row.icon:SetSize(FOLD_SIZE, FOLD_SIZE)
		row.icon:SetDesaturated(false)
		row.icon:SetAlpha(1)
		row.count:SetText(Color("muted", tostring(data.count)))
	elseif data.toggle then
		row.text:SetFontObject("GameFontHighlight")
		row.text:SetText(Color("muted", showHidden and "Don't list the hidden items"
			or format("%d hidden. Click to list them.", data.count)))
	else
		row.text:SetFontObject("GameFontHighlight")
		row.icon:SetTexture(entry.icon or C_Item.GetItemIconByID(entry.itemID))
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- without the icon's own border
		row.icon:SetSize(ICON_SIZE, ICON_SIZE)
		row.icon:SetDesaturated(data.hidden == true)
		row.icon:SetAlpha(data.hidden and 0.6 or 1)
		local count = BreakUpLargeNumbers(entry.count)
		if data.hidden then
			row.text:SetText(Color("muted", bagName(entry, true)))
			row.count:SetText(Color("muted", count))
		else
			row.text:SetText(bagName(entry))
			row.count:SetText(count)
		end
	end
	if GameTooltip:IsOwned(row) and not dragging then
		if entry or data.header then bagTooltip(row) else GameTooltip:Hide() end
	end
end

-- Each section under its name (with how many lines it has, and none of them when
-- it's folded away), then the hidden items if they're listed.
drawBags = function()
	local list, hidden = sections()
	local rows, found = {}, #hidden
	-- Every other line of a section is striped, starting again under each section's name.
	local function add(lines, isHidden, sectionName)
		for index, entry in ipairs(lines) do
			rows[#rows + 1] = { entry = entry, hidden = isHidden, stripe = index % 2 == 0, section = sectionName }
		end
	end
	for _, section in ipairs(list) do
		found = found + #section.entries
		local isFolded = folded(section.name)
		rows[#rows + 1] = { header = section.name, folded = isFolded, count = #section.entries, section = section.name }
		if not isFolded then add(section.entries, nil, section.name) end
	end
	if #hidden > 0 then
		rows[#rows + 1] = { toggle = true, count = #hidden }
		if showHidden then add(hidden, true) end
	end
	bagBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
	emptyText:SetText(#entries == 0 and EMPTY_TEXT or NO_MATCH_TEXT)
	emptyText:SetShown(found == 0)
end

local function byName(a, b)
	if a.name ~= b.name then return a.name < b.name end
	return a.key < b.key
end

local function postedText(this)
	return format("Posted %s.", ns.Format.Sellable(this.itemID, this.link, this.qty))
end

-- Reads the bags again. The picked item stays picked while you still have it;
-- once it's gone (posted, most likely) the next line is picked.
local function scan()
	crafts = crafts or myCrafts()
	local after = selected and neighbor(selected.key)
	entries, byKey = {}, {}
	local unknown = false
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and info.hyperlink and not info.isBound then
				local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
				if C_AuctionHouse.IsSellItemValid(location, false) then
					local status = C_AuctionHouse.GetItemCommodityStatus(location)
					if status == Enum.ItemCommodityStatus.Unknown then
						unknown = true
					else
						local commodity = status == Enum.ItemCommodityStatus.Commodity
						local key = commodity and tostring(info.itemID) or info.hyperlink
						local entry = byKey[key]
						if not entry then
							entry = { key = key, itemID = info.itemID, link = info.hyperlink, commodity = commodity,
								bag = bag, slot = slot, count = 0, craft = crafts[info.itemID] or false, icon = info.iconFileID,
								kind = select(2, C_Item.GetItemInfoInstant(info.itemID)),
								name = C_Item.GetItemNameByID(info.itemID) or "" }
							byKey[key] = entry
							entries[#entries + 1] = entry
						end
						entry.count = entry.count + (info.stackCount or 1)
					end
				end
			end
		end
	end
	table.sort(entries, byName)
	if selected then
		local same = byKey[selected.key]
		if same then
			selected = same
			available = math.max(C_AuctionHouse.GetAvailablePostCount(locationOf(same)) or 0, 1)
			drawPicked()
			drawBags()
			updateTotals()
			guarded(restoreNative)
			layout()
		else
			local said = posting and posting.key == selected.key and postedText(posting) or nil
			choose(after and byKey[after.key] or nil, said)
		end
	else
		drawBags()
		updateTotals()
	end
	-- The game is still loading some items: look again shortly.
	if unknown and scanTries < SCAN_TRIES then
		scanTries = scanTries + 1
		C_Timer.After(SCAN_WAIT, function()
			if panel:IsVisible() and Search.IsOpen() then scan() end
		end)
	end
end

---------------------------------------------------------------------------
-- Posting
---------------------------------------------------------------------------

local function stopPosting()
	posting = nil
	if panel then updateTotals() end
end

-- Gives up on a post the auction house never answered, so Post comes back.
-- Several of one item go up one at a time, and each one that does starts the wait again.
local function watch(this)
	C_Timer.After(POST_WAIT, function()
		if posting ~= this or this.confirming then return end
		if this.seen and GetTime() - this.seen < POST_WAIT then return watch(this) end
		stopPosting()
	end)
end

-- Post was clicked: puts the auction up. The game only takes this from a click.
local function post()
	if not selected or posting then return end
	local entry = selected
	if C_Container.GetContainerItemID(entry.bag, entry.slot) ~= entry.itemID then
		scan()
		return
	end
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then
		searchNote = "The auction house is busy. Try again in a moment."
		updateTotals()
		return
	end
	local this = { key = entry.key, itemID = entry.itemID, link = entry.link, commodity = entry.commodity,
		location = locationOf(entry), duration = ns.db.sellDuration, qty = amountBox:GetNumber(), price = getPrice() }
	if this.qty < 1 or this.qty > available or this.price <= 0 then return end
	posting = this
	-- The game answers true when it wants the auction confirmed first; it then asks
	-- for that itself (see the post warning below). Nothing else happens between the
	-- click and this call: the game can refuse a click it doesn't count as yours, and
	-- says so while the call runs (see ADDON_ACTION_BLOCKED below).
	calling, refused = true, false
	if this.commodity then
		C_AuctionHouse.PostCommodity(this.location, this.duration, this.qty, this.price)
	else
		C_AuctionHouse.PostItem(this.location, this.duration, this.qty, nil, this.price)
	end
	calling = false
	if refused then
		local native = nativeKey == this.key
		lastRefusal = format("in combat: %s, on the game's sell page: %s", tostring(InCombatLockdown()), tostring(native))
		searchNote = native and "The game didn't take that click. Use Create Auction instead."
			or "The game didn't take that click. Try Post again."
		stopPosting()
		return
	end
	updateTotals() -- Post greys out until the auction is up
	watch(this)
end

-- The auction is up: on to the next line.
local function posted()
	local this = posting
	posting = nil
	if not panel then return end
	if selected and selected.key == this.key then
		choose(neighbor(this.key), postedText(this))
	else
		updateTotals()
	end
end

StaticPopupDialogs["CRAFTPROFIT_POST_WARNING"] = {
	text = "%s",
	button1 = ACCEPT,
	button2 = CANCEL,
	OnAccept = function()
		local this = posting
		if not this then return end
		this.confirming = false
		if this.commodity then
			C_AuctionHouse.ConfirmPostCommodity(this.location, this.duration, this.qty, this.price)
		else
			C_AuctionHouse.ConfirmPostItem(this.location, this.duration, this.qty, nil, this.price)
		end
		watch(this)
	end,
	OnCancel = function() stopPosting() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3,
}

-- The game wants this auction confirmed. Its own question only knows the game's
-- sell page, so it's swapped for one that confirms the auction posted from here.
local function askToConfirm()
	if not posting then return end
	posting.confirming = true
	StaticPopup_Hide("AUCTION_HOUSE_POST_WARNING")
	StaticPopup_Show("CRAFTPROFIT_POST_WARNING", CONFIRM_AUCTION_POSTING_TEXT or "Post this auction?")
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local function refresh()
	local open = Search.IsOpen()
	body:SetShown(open)
	away:SetShown(not open)
	if open then
		crafts, scanTries = nil, 0
		if not selected then choose(nil) end
		scan()
		-- A price check that was dropped when the tab was left is asked again.
		if selected and not listings then choose(selected) end
		guarded(showPicked)
		layout()
	end
end

local function numberBox(parent, width, letters)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(letters)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	return box
end

local function label(parent, text, y)
	local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fontString:SetPoint("TOPLEFT", PAD, y - 5)
	fontString:SetText(text)
	return fontString
end

local function coin(parent, box, name)
	local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fontString:SetPoint("LEFT", box, "RIGHT", 2, 0)
	fontString:SetText(format("|TInterface\\MoneyFrame\\UI-%sIcon:%d:%d|t", name, COIN, COIN))
	return fontString
end

local function scrollList(parent, y, rowHeight, rows, draw, width)
	local inset = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
	inset:SetPoint("TOPLEFT", EDGE, y)
	inset:SetSize(width - 2 * EDGE, rows * rowHeight + 2 * INSET_PAD)
	local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	box:SetPoint("TOPLEFT", inset, "TOPLEFT", INSET_PAD, -INSET_PAD)
	box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -SCROLLBAR_ROOM, INSET_PAD)
	local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(rowHeight)
	view:SetElementInitializer("Button", draw)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	return box, inset, bar
end

-- The tab is made by three functions, not one: Lua lets a function use at most
-- 60 of this file's variables, and one function making all of it goes past that
-- (the file then doesn't load at all). Keep each of them well under it.

-- The search box, the bag list and the picked item's listings, from `y` down.
-- Returns where the form starts.
local function createLists(width, y)
	-- The search box: the bag list follows what's typed, a letter at a time.
	searchBox = CreateFrame("EditBox", nil, body, "SearchBoxTemplate")
	searchBox:SetPoint("TOPLEFT", EDGE + 6, y)
	searchBox:SetPoint("RIGHT", -EDGE - 2, 0)
	searchBox:SetHeight(SEARCH_HEIGHT)
	searchBox:SetAutoFocus(false)
	searchBox:SetMaxLetters(40)
	searchBox:SetFontObject("GameFontHighlight")
	if searchBox.Instructions then searchBox.Instructions:SetFontObject("GameFontDisable") end
	searchBox:HookScript("OnTextChanged", function(self)
		local typed = strtrim(self:GetText()):lower()
		if typed == filter then return end
		filter = typed
		drawBags()
	end)
	y = y - SEARCH_ROOM
	bagBox, bagInset = scrollList(body, y, ROW_HEIGHT, BAG_ROWS, drawBag, width)
	emptyText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	emptyText:SetPoint("CENTER", bagInset, "CENTER")
	emptyText:SetText(EMPTY_TEXT)
	y = y - BAG_HEIGHT - LIST_GAP

	pickedText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	pickedText:SetPoint("TOPLEFT", PAD, y)
	pickedText:SetJustifyH("LEFT")
	pickedText:SetWordWrap(false)
	sourceText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sourceText:SetPoint("TOPRIGHT", -PAD, y)
	pickedText:SetPoint("RIGHT", sourceText, "LEFT", -8, 0)
	y = y - 22

	local listingInset, listingBar
	listingBox, listingInset, listingBar = scrollList(body, y, LISTING_HEIGHT, LISTING_ROWS, drawListing, width)
	listingParts = { pickedText, sourceText, listingBox, listingInset, listingBar }
	return y - (LISTING_ROWS * LISTING_HEIGHT + 2 * INSET_PAD) - 10
end

-- The price, amount and duration, with the totals and the note under them, from
-- `y` down.
local function createForm(y)
	local function changed(_, userInput)
		if userInput then priceTouched = true end
		updateTotals()
		if not pulling then guarded(fillNative) end
	end
	label(body, "Price", y)
	goldBox = numberBox(body, 70, 7)
	goldBox:SetPoint("TOPLEFT", PAD + LABEL_WIDTH, y)
	silverBox = numberBox(body, 30, 2)
	silverBox:SetPoint("LEFT", coin(body, goldBox, "Gold"), "RIGHT", 10, 0)
	local lastCoin = coin(body, silverBox, "Silver")
	if usesCopper then
		copperBox = numberBox(body, 30, 2)
		copperBox:SetPoint("LEFT", lastCoin, "RIGHT", 10, 0)
		lastCoin = coin(body, copperBox, "Copper")
	end
	eachText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	eachText:SetPoint("LEFT", lastCoin, "RIGHT", 8, 0)
	y = y - LINE

	label(body, "Amount", y)
	amountBox = numberBox(body, 70, 6)
	amountBox:SetPoint("TOPLEFT", PAD + LABEL_WIDTH, y)
	ofText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ofText:SetPoint("LEFT", amountBox, "RIGHT", 8, 0)
	local all = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
	all:SetText("All")
	all:SetSize(50, 22)
	all:SetPoint("LEFT", ofText, "RIGHT", 10, 0)
	all:SetScript("OnClick", function()
		if selected then amountBox:SetText(tostring(available)) end
		updateTotals()
	end)
	y = y - LINE

	-- Tab walks through the boxes, as on the game's own sell page.
	local boxes = { goldBox, silverBox, copperBox or amountBox, copperBox and amountBox or nil }
	for index, box in ipairs(boxes) do
		box:SetScript("OnTextChanged", changed)
		box:SetScript("OnTabPressed", function() boxes[index % #boxes + 1]:SetFocus() end)
	end

	label(body, "Lasts", y)
	for index, text in ipairs(DURATIONS) do
		local button = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
		button:SetText(text)
		button:SetSize(88, 22)
		button:SetPoint("TOPLEFT", PAD + LABEL_WIDTH - 4 + (index - 1) * 92, y)
		button:SetScript("OnClick", function()
			ns.db.sellDuration = index
			drawDurations()
			updateTotals()
			guarded(fillNative)
		end)
		durationButtons[index] = button
	end
	y = y - LINE - 2

	totalsText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	totalsText:SetPoint("TOPLEFT", PAD, y)
	totalsText:SetPoint("RIGHT", -PAD, 0)
	totalsText:SetJustifyH("LEFT")
	totalsText:SetJustifyV("TOP")
	totalsText:SetWordWrap(false)
	totalsText:SetHeight(NOTE_LINE) -- one line: the deposit, then what you get
	y = y - NOTE_LINE - 2
	noteText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	noteText:SetPoint("TOPLEFT", PAD, y)
	noteText:SetPoint("RIGHT", -PAD, 0)
	noteText:SetJustifyH("LEFT")
	noteText:SetJustifyV("TOP")
	noteText:SetWordWrap(false) -- every message is written to fit one line
	noteText:SetHeight(NOTE_LINE)
end

-- Post and Skip, along the bottom.
local function createButtons()
	skipButton = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
	skipButton:SetText("Skip")
	skipButton:SetSize(80, 24)
	skipButton:SetPoint("BOTTOMRIGHT", -PAD, 10)
	skipButton:SetScript("OnClick", function()
		if selected then choose(neighbor(selected.key)) end
	end)
	postButton = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
	postButton:SetText("Post")
	postButton:SetHeight(24)
	postButton:SetPoint("BOTTOMLEFT", PAD, 10)
	postButton:SetPoint("RIGHT", skipButton, "LEFT", -8, 0)
	postButton:SetScript("OnClick", post)
end

-- Makes the tab's frame inside the window. Called once, the first time the tab
-- is opened.
function Sell.Create(parent, width)
	usesCopper = C_AuctionHouse.SupportsCopperValues ~= nil and C_AuctionHouse.SupportsCopperValues() == true
	panel = CreateFrame("Frame", nil, parent)
	panel:SetAllPoints()
	panel:Hide()
	away = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	away:SetPoint("CENTER")
	away:SetWidth(width - 80)
	away:SetText(AWAY_TEXT)
	body = CreateFrame("Frame", nil, panel)
	body:SetAllPoints()
	createForm(createLists(width, -TOP))
	createButtons()

	-- Never chosen here: the game's own choice, so filling in the game's sell page
	-- doesn't change what you set there.
	if not DURATIONS[ns.db.sellDuration] then
		local own = tonumber(GetCVar("auctionHouseDurationDropdown"))
		ns.db.sellDuration = DURATIONS[own] and own or 2
	end
	drawDurations()
	layout()
	panel:SetScript("OnShow", refresh)
	panel:SetScript("OnHide", function()
		Search.Drop(OWNER)
		cancelDrag()
		GameTooltip:Hide()
	end)
	return panel
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
events:RegisterEvent("AUCTION_HOUSE_POST_WARNING")
events:RegisterEvent("AUCTION_HOUSE_POST_ERROR")
events:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
events:RegisterEvent("AUCTION_MULTISELL_UPDATE")
events:RegisterEvent("AUCTION_MULTISELL_FAILURE")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, numPosted, total)
	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		-- The game refused something. While Post's own call runs, that's the post.
		if calling then refused = true end
		return
	end
	if event == "AUCTION_HOUSE_CLOSED" then
		-- Nothing picked or half posted outlives the auction house.
		selected, pick, listings, posting, nativeKey = nil, nil, nil, nil, nil
		-- A search is as old as this visit to the auction house.
		if searchBox then searchBox:SetText("") end
		StaticPopup_Hide("CRAFTPROFIT_POST_WARNING")
		layout()
	end
	if event == "AUCTION_HOUSE_AUCTION_CREATED" then
		-- Several of one item (not a stack) go up one at a time: the last one ends it.
		if posting then
			posting.created = (posting.created or 0) + 1
			posting.seen = GetTime()
			if posting.commodity or posting.created >= posting.qty then posted() end
		end
	elseif event == "AUCTION_MULTISELL_UPDATE" then
		if posting and not posting.commodity then
			posting.seen = GetTime()
			if numPosted >= total then
				posted()
			else
				searchNote = format("Posting %d of %d...", numPosted, total)
				updateTotals()
			end
		end
	elseif event == "AUCTION_MULTISELL_FAILURE" then
		if posting then
			searchNote = "The auction house stopped before all of them were up."
			stopPosting()
		end
	elseif event == "AUCTION_HOUSE_POST_WARNING" then
		-- A moment later: the game is putting up its own question on this event.
		if posting then C_Timer.After(0, askToConfirm) end
	elseif event == "AUCTION_HOUSE_POST_ERROR" or event == "AUCTION_HOUSE_SHOW_ERROR" then
		if posting then
			searchNote = "The auction house didn't take that."
			stopPosting()
		end
	elseif not (panel and panel:IsVisible()) then
		return
	elseif event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_HOUSE_CLOSED" then
		-- A moment later, once the auction house is known to be open or closed.
		C_Timer.After(0, function()
			if panel:IsVisible() then refresh() end
		end)
	elseif not Search.IsOpen() then
		return
	elseif event == "BAG_UPDATE_DELAYED" then
		scan()
	elseif selected then
		updateTotals()
	end
end)
