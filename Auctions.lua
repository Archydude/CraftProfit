-- Craft Profit: the My auctions tab of its auction house window (see
-- ShoppingList.lua). It lists your auctions with the lowest price anyone else
-- asks, says which ones are undercut, and cancels them: one auction for each
-- click, as the game only takes a cancel from a click.
local _, ns = ...

local Auctions = {}
ns.Auctions = Auctions

local format = string.format
local Color = ns.Color
local Search = ns.AuctionSearch

local OWNER = "auctions" -- this tab's name in the line of auction house questions
local EDGE = 8           -- window edge to the list's frame
local PAD = 14           -- window edge to the text
local TOP = 28           -- under the title bar
local BOTTOM = 62        -- room for the status line and the buttons
local INSET_PAD = 4      -- list frame to the rows
local SCROLLBAR_ROOM = 22
local ROW_HEIGHT = 40    -- two lines: the item, then the prices
local CANCEL_WIDTH = 64
-- How long a cancel waits for the auction house before the button comes back, in seconds.
local CANCEL_WAIT = 6

local AWAY_TEXT = "Open the auction house to see your auctions."
local EMPTY_TEXT = "You have no auctions up."

-- How each auction stands, in the list's order, with its label.
local STATES = { "undercut", "checking", "unknown", "bidOnly", "lowest", "sold" }
local STATE_ORDER = tInvert(STATES)
local STATE_TEXT = {
	undercut = Color("loss", "Undercut"),
	checking = Color("muted", "Checking..."),
	unknown = Color("muted", "Not checked"),
	bidOnly = Color("muted", "Bid only"),
	lowest = Color("good", "Lowest"),
	sold = Color("heading", "Sold"),
}

local panel, body, away, emptyText, listBox, statusText, nextButton
-- Your auctions, as drawn: { id, itemKey, itemID, link, qty, price, sold, ... }.
local auctions = {}
-- Whether the auction house has said what your auctions are since it opened.
local loaded = false
-- What each item is listed for by others: item key text -> { done, failed, lowest }.
local checks = {}
-- Auctions being cancelled, until the auction house says they're down: id -> true.
local cancelling = {}
-- Something to tell you in place of the status line (the auction house is busy...).
local note

local function exact(copper)
	return GetMoneyString(copper, true)
end

local function keyText(itemKey)
	return table.concat({ itemKey.itemID, itemKey.itemLevel or 0, itemKey.itemSuffix or 0,
		itemKey.battlePetSpeciesID or 0 }, ":")
end

local function stateOf(auction)
	if auction.sold then return "sold" end
	if not auction.price then return "bidOnly" end
	local check = checks[auction.key]
	if not (check and check.done) then return "checking" end
	if check.failed then return "unknown" end
	return (check.lowest and check.lowest < auction.price) and "undercut" or "lowest"
end

local function timeText(seconds)
	if not seconds then return "" end
	if seconds >= 3600 then return format("%dh left", math.floor(seconds / 3600)) end
	return format("%dm left", math.max(1, math.floor(seconds / 60)))
end

---------------------------------------------------------------------------
-- Cancelling
---------------------------------------------------------------------------

local draw

-- Takes one auction down. Called from a click, which is what the game asks for.
-- An auction someone bid on costs gold to cancel, so that one asks first.
local function cancel(auction, confirmed)
	if cancelling[auction.id] then return end
	if not C_AuctionHouse.CanCancelAuction(auction.id) then
		note = "That auction can't be cancelled."
		draw()
		return
	end
	local cost = C_AuctionHouse.GetCancelCost(auction.id) or 0
	if cost > 0 and not confirmed then
		StaticPopup_Show("CRAFTPROFIT_CANCEL_AUCTION", exact(cost), nil, auction)
		return
	end
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then
		note = "The auction house is busy. Click again in a moment."
		draw()
		return
	end
	note = nil
	cancelling[auction.id] = true
	C_AuctionHouse.CancelAuction(auction.id)
	draw()
	local id = auction.id
	C_Timer.After(CANCEL_WAIT, function()
		if cancelling[id] then
			cancelling[id] = nil
			if panel:IsVisible() then draw() end
		end
	end)
end

StaticPopupDialogs["CRAFTPROFIT_CANCEL_AUCTION"] = {
	text = "Someone has bid on this auction, so cancelling it costs %s.\n\nCancel it anyway?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, auction) cancel(auction, true) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3,
}

-- The first undercut auction in the list that isn't on its way down already.
-- Auctions someone bid on are left to their own Cancel button, which asks first.
local function nextUndercut()
	for _, auction in ipairs(auctions) do
		if stateOf(auction) == "undercut" and not cancelling[auction.id] and not auction.bid then return auction end
	end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function rowTooltip(row)
	local auction = row.data
	if not auction then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if auction.link then GameTooltip:SetHyperlink(auction.link) else GameTooltip:SetItemByID(auction.itemID) end
	GameTooltip:Show()
end

local function rowClick(row)
	local auction = row.data
	if auction and auction.link and IsModifiedClick() then HandleModifiedItemClick(auction.link) end
end

local function cancelTooltip(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Cancel this auction", 1, 1, 1)
	GameTooltip:AddLine("It comes back in the mail. You don't get its deposit back.", nil, nil, nil, true)
	GameTooltip:Show()
end

local function createRow(row)
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(1, 1, 1, 0.08)
	row.cancel = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.cancel:SetSize(CANCEL_WIDTH, 22)
	row.cancel:SetPoint("RIGHT", -4, 0)
	row.cancel:SetScript("OnClick", function() cancel(row.data) end)
	row.cancel:SetScript("OnEnter", cancelTooltip)
	row.cancel:SetScript("OnLeave", GameTooltip_Hide)
	row.state = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.state:SetPoint("TOPRIGHT", row.cancel, "TOPLEFT", -8, 6)
	row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.time:SetPoint("BOTTOMRIGHT", row.cancel, "BOTTOMLEFT", -8, -6)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("TOPLEFT", 6, -3)
	row.name:SetPoint("RIGHT", row.state, "LEFT", -6, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.prices = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.prices:SetPoint("BOTTOMLEFT", 6, 5)
	row.prices:SetPoint("RIGHT", row.time, "LEFT", -6, 0)
	row.prices:SetJustifyH("LEFT")
	row.prices:SetWordWrap(false)
	row:SetScript("OnClick", rowClick)
	row:SetScript("OnEnter", rowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
end

local function drawRow(row, auction)
	if not row.name then createRow(row) end
	row.data = auction
	local state = stateOf(auction)
	row.name:SetText(ns.Format.Sellable(auction.itemID, auction.link, auction.qty))
	row.state:SetText(STATE_TEXT[state])
	row.time:SetText(Color("muted", auction.sold and "" or timeText(auction.seconds)))
	local prices
	if auction.price then
		prices = "Yours " .. exact(auction.price)
		local check = checks[auction.key]
		if not auction.sold and check and check.done and not check.failed then
			prices = prices .. (check.lowest and ("  ·  lowest other " .. exact(check.lowest)) or "  ·  no others")
		end
	else
		prices = auction.bid and ("Bid " .. exact(auction.bid)) or ""
	end
	row.prices:SetText(Color("muted", prices))
	row.cancel:SetShown(not auction.sold)
	row.cancel:SetEnabled(not cancelling[auction.id])
	row.cancel:SetText(cancelling[auction.id] and "..." or "Cancel")
	if GameTooltip:IsOwned(row) then rowTooltip(row) end
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

local function byStateThenName(a, b)
	local stateA, stateB = STATE_ORDER[stateOf(a)], STATE_ORDER[stateOf(b)]
	if stateA ~= stateB then return stateA < stateB end
	if a.name ~= b.name then return a.name < b.name end
	if (a.price or 0) ~= (b.price or 0) then return (a.price or 0) < (b.price or 0) end
	return a.id < b.id
end

-- Draws the list, the status line and the Cancel next undercut button.
draw = function()
	table.sort(auctions, byStateThenName)
	listBox:SetDataProvider(CreateDataProvider(auctions), ScrollBoxConstants.RetainScrollPosition)
	emptyText:SetShown(loaded and #auctions == 0)
	local undercut, checking, up = 0, 0, 0
	for _, auction in ipairs(auctions) do
		local state = stateOf(auction)
		if state == "undercut" then undercut = undercut + 1 elseif state == "checking" then checking = checking + 1 end
		if not auction.sold then up = up + 1 end
	end
	local text
	if note then
		text = Color("warning", note)
	elseif not loaded then
		text = Color("muted", "Reading your auctions...")
	elseif #auctions == 0 then
		text = ""
	else
		text = format("%d up", up)
		if checking > 0 then text = text .. format("  ·  checking %d", checking) end
		text = text .. format("  ·  %d undercut", undercut)
	end
	statusText:SetText(text)
	nextButton:SetText(undercut > 0 and format("Cancel next undercut (%d)", undercut) or "Cancel next undercut")
	nextButton:SetEnabled(nextUndercut() ~= nil)
end

-- An item's listings came back (nil when the auction house didn't answer): the
-- lowest price that isn't yours or another of your characters'.
local function onChecked(key, check, results)
	if checks[key] ~= check then return end -- asked again since
	check.done = true
	if not results then
		check.failed = true
	else
		for _, row in ipairs(results.rows) do
			if not row.mine then
				check.lowest = row.price
				break
			end
		end
	end
	if panel:IsVisible() then draw() end
end

-- Reads your auctions from the game, and asks what others list each item for
-- (once for each item, until Check again).
local function rebuild()
	loaded = true
	auctions = {}
	for _, info in ipairs(Search.ReadOwned()) do
		local itemKey = info.itemKey
		local auction = { id = info.auctionID, itemKey = itemKey, itemID = itemKey.itemID, link = info.itemLink,
			qty = info.quantity or 1, price = info.buyoutAmount, bid = info.bidAmount,
			sold = info.status == Enum.AuctionStatus.Sold, seconds = info.timeLeftSeconds,
			key = keyText(itemKey), name = C_Item.GetItemNameByID(itemKey.itemID) or "" }
		auctions[#auctions + 1] = auction
		if not auction.sold and auction.price and not checks[auction.key] then
			local key, check = auction.key, {}
			checks[key] = check
			Search.Request(OWNER, itemKey, false, function(results) onChecked(key, check, results) end)
		end
	end
	draw()
end

-- Asks the auction house for your auctions again.
local function ask()
	Search.Owned(OWNER, function()
		if panel:IsVisible() then rebuild() end
	end)
end

local function refresh()
	local open = Search.IsOpen()
	body:SetShown(open)
	away:SetShown(not open)
	if open then
		note = nil
		ask()
		draw()
	end
end

-- Makes the tab's frame inside the window. Called once, the first time the tab
-- is opened.
function Auctions.Create(parent, width)
	panel = CreateFrame("Frame", nil, parent)
	panel:SetAllPoints()
	panel:Hide()
	away = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	away:SetPoint("CENTER")
	away:SetWidth(width - 80)
	away:SetText(AWAY_TEXT)
	body = CreateFrame("Frame", nil, panel)
	body:SetAllPoints()

	local inset = CreateFrame("Frame", nil, body, "InsetFrameTemplate")
	inset:SetPoint("TOPLEFT", EDGE, -TOP)
	inset:SetPoint("BOTTOMRIGHT", -EDGE, BOTTOM)
	listBox = CreateFrame("Frame", nil, body, "WowScrollBoxList")
	listBox:SetPoint("TOPLEFT", inset, "TOPLEFT", INSET_PAD, -INSET_PAD)
	listBox:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -SCROLLBAR_ROOM, INSET_PAD)
	local scrollBar = CreateFrame("EventFrame", nil, body, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", drawRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(listBox, scrollBar, view)
	emptyText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	emptyText:SetPoint("CENTER", inset, "CENTER")
	emptyText:SetText(EMPTY_TEXT)

	statusText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	statusText:SetPoint("BOTTOMLEFT", PAD, 40)
	statusText:SetPoint("RIGHT", -PAD, 0)
	statusText:SetJustifyH("LEFT")
	statusText:SetWordWrap(false)

	local again = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
	again:SetText("Check again")
	again:SetSize(110, 24)
	again:SetPoint("BOTTOMRIGHT", -PAD, 10)
	again:SetScript("OnClick", function()
		Search.Drop(OWNER)
		checks, note = {}, nil
		ask()
		draw()
	end)
	nextButton = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
	nextButton:SetHeight(24)
	nextButton:SetPoint("BOTTOMLEFT", PAD, 10)
	nextButton:SetPoint("RIGHT", again, "LEFT", -8, 0)
	nextButton:SetScript("OnClick", function()
		local auction = nextUndercut()
		if auction then cancel(auction) end
	end)
	nextButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Cancel next undercut", 1, 1, 1)
		GameTooltip:AddLine("Cancels one undercut auction for each click. They come back in the mail, and you " ..
			"don't get their deposits back.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	nextButton:SetScript("OnLeave", GameTooltip_Hide)

	panel:SetScript("OnShow", refresh)
	panel:SetScript("OnHide", function() GameTooltip:Hide() end)
	return panel
end

-- Testing: what the game says about your first auctions, to check the prices
-- this tab compares.
function Auctions.Explain()
	local say = ns.Shopping.Say
	if not Search.IsOpen() then return say("Testing: open the auction house first.") end
	local list = Search.ReadOwned()
	say(format("Testing: the game lists %d auctions of yours. Last problem: %s.", #list, tostring(Search.lastProblem)))
	for index = 1, math.min(#list, 5) do
		local info = list[index]
		local check = checks[keyText(info.itemKey)]
		say(format("  #%d item %d x%s: buyout %s, bid %s, status %s, lowest other %s", info.auctionID, info.itemKey.itemID,
			tostring(info.quantity), tostring(info.buyoutAmount), tostring(info.bidAmount), tostring(info.status),
			tostring(check and check.lowest)))
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("OWNED_AUCTIONS_UPDATED")
events:RegisterEvent("AUCTION_CANCELED")
events:SetScript("OnEvent", function(_, event, auctionID)
	if event == "AUCTION_HOUSE_CLOSED" then
		-- What was read and asked is as old as this visit to the auction house.
		auctions, checks, cancelling, loaded = {}, {}, {}, false
		StaticPopup_Hide("CRAFTPROFIT_CANCEL_AUCTION")
	end
	if not panel then return end
	if event == "AUCTION_CANCELED" then
		-- It's down: off the list, without asking for everything again.
		cancelling[auctionID] = nil
		for index, auction in ipairs(auctions) do
			if auction.id == auctionID then
				table.remove(auctions, index)
				break
			end
		end
		if panel:IsVisible() then draw() end
	elseif not panel:IsVisible() then
		return
	elseif event == "OWNED_AUCTIONS_UPDATED" then
		if Search.IsOpen() then rebuild() end
	else
		-- A moment later, once the auction house is known to be open or closed.
		C_Timer.After(0, function()
			if panel:IsVisible() then refresh() end
		end)
	end
end)
