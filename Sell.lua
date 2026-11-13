-- Craft Profit: the Sell tab of its auction house window (see ShoppingList.lua).
-- It lists what's in your bags that can be auctioned, your own crafts first. Pick
-- one to see what it's listed for, set the price, amount and how long it lasts,
-- and post it. Every auction is posted by your own click on Post.
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
local ROW_HEIGHT, BAG_ROWS = 22, 8
local LISTING_HEIGHT, LISTING_ROWS = 20, 4
local LINE = 28          -- from one line of the form to the next
local LABEL_WIDTH = 66   -- "Price", "Amount", "Lasts"
local COIN = 14          -- coin icons beside the price boxes
-- How long Post waits for the auction house to say the auction is up, in seconds.
local POST_WAIT = 8
-- Bag items the game hasn't loaded yet are looked at again this often, this many times.
local SCAN_WAIT, SCAN_TRIES = 0.5, 6
-- How long an auction lasts, by the game's number for it: Retail's, or WoW Forever's.
local DURATIONS = ns.QUALITY_CRAFTING and { "12 hours", "24 hours", "48 hours" } or { "2 hours", "8 hours", "24 hours" }

local AWAY_TEXT = "Open the auction house to sell from here."
local EMPTY_TEXT = "Nothing in your bags can be auctioned."
local PICK_TEXT = "Pick something from the list to sell it."

local panel, body, away, emptyText
local bagBox, listingBox, pickedText, sourceText
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
-- Items your saved Best crafts scans say you craft: itemID -> true.
local crafts
local scanTries = 0

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
		text = text .. format("\nYou get: %s after the %d%% cut", exact(math.floor(price * qty * (1 - ns.AH_CUT))),
			ns.AH_CUT * 100)
	end
	totalsText:SetText(text)

	local problem
	if qty < 1 then
		problem = "Enter an amount."
	elseif qty > available then
		problem = format("You only have %d to sell.", available)
	elseif price <= 0 then
		problem = listings and "Enter a price." or nil
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

local function drawDurations()
	for index, button in ipairs(durationButtons) do
		local chosen = index == ns.db.sellDuration
		button:SetNormalFontObject(chosen and "GameFontHighlight" or "GameFontNormal")
		if chosen then button:LockHighlight() else button:UnlockHighlight() end
	end
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
		searchNote = "The auction house didn't answer. Pick the item again to try once more."
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
				searchNote = "The lowest price is less than a vendor pays, so no price was filled in."
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
	selected, pick, listings, priceTouched = entry, nil, nil, false
	setPrice(nil)
	drawListings()
	if not entry then
		available = 0
		amountBox:SetText("")
		searchNote = said
		drawPicked()
		drawBags()
		updateTotals()
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
	end)
	drawPicked()
	drawBags()
	updateTotals()
end

-- The line after `key` in the list, or the one before it at the end.
local function neighbor(key)
	local shown, hidden = {}, {}
	for _, entry in ipairs(entries) do
		if not ns.db.sellHidden[entry.itemID] then
			shown[#shown + 1] = entry
		elseif showHidden then
			hidden[#hidden + 1] = entry
		end
	end
	for _, entry in ipairs(hidden) do shown[#shown + 1] = entry end
	for index, entry in ipairs(shown) do
		if entry.key == key then return shown[index + 1] or shown[index - 1] end
	end
end

local function bagTooltip(row)
	local data = row.data
	local entry = data and data.entry
	if not entry then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetBagItem(entry.bag, entry.slot)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(Color("simulated", "Click: pick it to sell"))
	GameTooltip:AddLine(Color("simulated", ns.db.sellHidden[entry.itemID] and "Right-click: bring it back to the list"
		or "Right-click: hide it from this list"))
	GameTooltip:Show()
end

local function bagClick(row, mouseButton)
	local data = row.data
	if not data then return end
	if data.toggle then
		showHidden = not showHidden
		drawBags()
		return
	end
	local entry = data.entry
	if not entry then return end
	if mouseButton == "RightButton" then
		GameTooltip:Hide()
		ns.db.sellHidden[entry.itemID] = not ns.db.sellHidden[entry.itemID] or nil
		if selected and selected.key == entry.key and ns.db.sellHidden[entry.itemID] then
			choose(nil)
		else
			drawBags()
		end
	elseif IsModifiedClick() then
		HandleModifiedItemClick(entry.link)
	else
		choose(entry)
	end
end

local function drawBag(row, data)
	if not row.text then
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
		row.highlight:SetAllPoints()
		row.highlight:SetColorTexture(1, 1, 1, 0.08)
		row.picked = row:CreateTexture(nil, "BACKGROUND")
		row.picked:SetAllPoints()
		row.picked:SetColorTexture(1, 0.82, 0, 0.18)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetPoint("LEFT", 6, 0)
		row.text:SetPoint("RIGHT", -6, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row:SetScript("OnClick", bagClick)
		row:SetScript("OnEnter", bagTooltip)
		row:SetScript("OnLeave", GameTooltip_Hide)
	end
	row.data = data
	local entry = data.entry
	row.highlight:SetShown(not data.header)
	row.picked:SetShown(entry ~= nil and selected ~= nil and selected.key == entry.key)
	if data.header then
		row.text:SetFontObject("GameFontNormal")
		row.text:SetText(data.header)
	elseif data.toggle then
		row.text:SetFontObject("GameFontHighlight")
		row.text:SetText(Color("muted", showHidden and "Don't list the hidden items"
			or format("%d hidden. Click to list them.", data.count)))
	else
		row.text:SetFontObject("GameFontHighlight")
		local text = ns.Format.Sellable(entry.itemID, entry.link, entry.count)
		row.text:SetText(data.hidden and Color("muted", text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or text)
	end
	if GameTooltip:IsOwned(row) then
		if entry then bagTooltip(row) else GameTooltip:Hide() end
	end
end

-- Your crafts, then everything else, then the hidden items if they're listed.
drawBags = function()
	local mine, others, hidden = {}, {}, {}
	for _, entry in ipairs(entries) do
		if ns.db.sellHidden[entry.itemID] then
			hidden[#hidden + 1] = entry
		elseif entry.craft then
			mine[#mine + 1] = entry
		else
			others[#others + 1] = entry
		end
	end
	local rows = {}
	if #mine > 0 then
		rows[#rows + 1] = { header = "Your crafts" }
		for _, entry in ipairs(mine) do rows[#rows + 1] = { entry = entry } end
	end
	if #others > 0 then
		if #mine > 0 then rows[#rows + 1] = { header = "Everything else in your bags" } end
		for _, entry in ipairs(others) do rows[#rows + 1] = { entry = entry } end
	end
	if #hidden > 0 then
		rows[#rows + 1] = { toggle = true, count = #hidden }
		if showHidden then
			for _, entry in ipairs(hidden) do rows[#rows + 1] = { entry = entry, hidden = true } end
		end
	end
	bagBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
	emptyText:SetShown(#entries == 0)
end

local function byCraftThenName(a, b)
	if a.craft ~= b.craft then return a.craft end
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
								bag = bag, slot = slot, count = 0, craft = crafts[info.itemID] or false,
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
	table.sort(entries, byCraftThenName)
	if selected then
		local same = byKey[selected.key]
		if same then
			selected = same
			available = math.max(C_AuctionHouse.GetAvailablePostCount(locationOf(same)) or 0, 1)
			drawPicked()
			drawBags()
			updateTotals()
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
	postButton:Disable()
	-- The game answers true when it wants the auction confirmed first; it then asks
	-- for that itself (see the post warning below).
	if this.commodity then
		C_AuctionHouse.PostCommodity(this.location, this.duration, this.qty, this.price)
	else
		C_AuctionHouse.PostItem(this.location, this.duration, this.qty, nil, this.price)
	end
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
	return box, inset
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

	local y = -TOP
	local bagInset
	bagBox, bagInset = scrollList(body, y, ROW_HEIGHT, BAG_ROWS, drawBag, width)
	emptyText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	emptyText:SetPoint("CENTER", bagInset, "CENTER")
	emptyText:SetText(EMPTY_TEXT)
	y = y - (BAG_ROWS * ROW_HEIGHT + 2 * INSET_PAD) - 8

	pickedText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	pickedText:SetPoint("TOPLEFT", PAD, y)
	pickedText:SetJustifyH("LEFT")
	pickedText:SetWordWrap(false)
	sourceText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sourceText:SetPoint("TOPRIGHT", -PAD, y)
	pickedText:SetPoint("RIGHT", sourceText, "LEFT", -8, 0)
	y = y - 22

	listingBox = scrollList(body, y, LISTING_HEIGHT, LISTING_ROWS, drawListing, width)
	y = y - (LISTING_ROWS * LISTING_HEIGHT + 2 * INSET_PAD) - 10

	local function changed(_, userInput)
		if userInput then priceTouched = true end
		updateTotals()
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
		end)
		durationButtons[index] = button
	end
	y = y - LINE - 2

	totalsText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	totalsText:SetPoint("TOPLEFT", PAD, y)
	totalsText:SetPoint("RIGHT", -PAD, 0)
	totalsText:SetJustifyH("LEFT")
	totalsText:SetJustifyV("TOP")
	totalsText:SetHeight(32) -- two lines: the deposit, then what you get
	y = y - 36
	noteText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	noteText:SetPoint("TOPLEFT", PAD, y)
	noteText:SetPoint("RIGHT", -PAD, 0)
	noteText:SetJustifyH("LEFT")
	noteText:SetJustifyV("TOP")
	noteText:SetHeight(30)

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

	if not DURATIONS[ns.db.sellDuration] then ns.db.sellDuration = 2 end
	drawDurations()
	panel:SetScript("OnShow", refresh)
	panel:SetScript("OnHide", function()
		Search.Drop(OWNER)
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
events:SetScript("OnEvent", function(_, event, numPosted, total)
	if event == "AUCTION_HOUSE_CLOSED" then
		-- Nothing picked or half posted outlives the auction house.
		selected, pick, listings, posting = nil, nil, nil, nil
		StaticPopup_Hide("CRAFTPROFIT_POST_WARNING")
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
