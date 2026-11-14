-- Craft Profit: its auction house window, and the Shopping list tab in it (the
-- list itself is in Shopping.lua). The Sell and My auctions tabs are in Sell.lua
-- and Auctions.lua. The window opens beside the auction house, and from the
-- minimap button's menu, the Shopping list menus or /craftprofit shop, and a side
-- button on the auction house window opens and closes it there. Away from
-- the auction house it's only the shopping list: the other tabs need the auction
-- house, so they and /craftprofit sell, auctions and prices wait for it. A click on a
-- material shows it at the auction house, with the amount still to buy filled in.
local _, ns = ...

local ShoppingList = {}
ns.ShoppingList = ShoppingList

local format = string.format
local Color = ns.Color

local WIDTH, HEIGHT = 400, 540
-- The tabs, in order, and the window's title on each.
local TAB_KEYS = { "shop", "sell", "auctions", "prices" }
local TAB_LABELS = { shop = "Shopping list", sell = "Sell", auctions = "My auctions", prices = "Prices" }
-- Where each tab but the shopping list is made (ns.Sell.Create...).
local TAB_MODULES = { sell = "Sell", auctions = "Auctions", prices = "PricesTab" }
local TAB_PADDING = 16   -- room beside a tab's label, so it's never cut short
local SIDE = 10          -- window edge to the list's frame
local INSET_TOP = 26     -- under the title bar
local INSET_BOTTOM = 32  -- room for the total
local INSET_PAD = 4      -- list frame to the rows
local SCROLLBAR_ROOM = 22
local ROW_HEIGHT = 24
local DOCK_GAP = 4       -- between the auction house (or its side buttons) and the window
-- The side button on the auction house window: its icon (the addon's logo), where
-- the first side button sits on the window's right edge (other addons put theirs
-- there too), and the gap under the one above.
local SIDE_ICON = "Interface\\AddOns\\CraftProfit\\Media\\logo"
local SIDE_X, SIDE_Y = -2, -52
local SIDE_GAP = 2
local SIDE_RECHECK = 0.5 -- seconds after the auction house opens: other addons' side buttons are up by then
-- How long a click waits for the game to load a material's auction details
-- before it searches by name instead, in seconds.
local INFO_WAIT = 1.5
-- How soon the list is drawn again after item names arrive, in seconds.
local NAMES_WAIT = 0.2
-- While a name on the list is still loading, the list looks again this often (in
-- seconds), this many times: the game doesn't always say when a name has arrived.
local NAME_RETRY, NAME_TRIES = 1, 60

local EMPTY_TEXT = "Nothing on your shopping list.\n\nAdd what you're missing with the Shopping list button under "
	.. "your materials, or from a row of the Best crafts list."

local frame, scrollBox, empty, footer
-- The tab that's showing, and each tab's frame once it has been opened.
local tab, panels = "shop", {}
-- Whether the auction house is open, whether it opened the window (so closing
-- it closes the window too), and whether the window sits beside it.
local atAuctionHouse, openedByAuctionHouse, docked = false, false, false
-- The chat hint on how to open the window: once a session.
local hinted = false
-- The side button on the game's auction house window, once that window has opened.
local sideTab
-- Looking again for names that are still loading: whether a look is due, how many
-- there have been since the names were last all there, and an item still without one.
local nameLookDue, nameLooks, unnamed = false, 0, nil

---------------------------------------------------------------------------
-- Searching the auction house
---------------------------------------------------------------------------
-- This drives Blizzard's own auction house window, which a game update can
-- change, so every step into it is guarded and falls back to a search by name.

-- The material a click is waiting on, while the game loads its auction details.
local pending
-- Why the last click searched by name, for /craftprofit testshop.
local lastProblem

-- Blizzard's auction house window, when it's the one on screen.
local function auctionFrame()
	local auctionHouse = ns.AuctionSearch.GameWindow()
	if auctionHouse and auctionHouse.SelectBrowseResult then return auctionHouse end
end

-- Opens the item's own page, as a click on it in the search results would. The
-- page only searches when it appears, so the results page comes first. Stackable
-- materials get the amount still to buy.
local function showItem(auctionHouse, itemID, qty, isCommodity)
	auctionHouse:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
	auctionHouse:SelectBrowseResult({ itemKey = C_AuctionHouse.MakeItemKey(itemID), minPrice = 0 })
	if isCommodity then
		auctionHouse:TriggerEvent(AuctionHouseFrameMixin.Event.CommoditiesQuantitySelectionChanged, qty)
	end
end

-- Types the item's name into the search box and searches. Returns whether it could.
local function searchByName(auctionHouse, itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if not (name and auctionHouse.SearchBar) then return false end
	auctionHouse:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
	auctionHouse.SearchBar:SetSearchText(name)
	auctionHouse.SearchBar:StartSearch()
	return true
end

local function fallBack(auctionHouse, itemID, problem)
	lastProblem = tostring(problem)
	local ok, searched = pcall(searchByName, auctionHouse, itemID)
	if not (ok and searched) then
		ns.Shopping.Say(Color("warning", "Couldn't search the auction house for that."))
	end
end

-- A click on a material: shows it at the auction house.
local function search(itemID, qty)
	local auctionHouse = auctionFrame()
	if not auctionHouse then
		ns.Shopping.Say(atAuctionHouse and "Switch to the game's own auction house window to search from the list."
			or "Open the auction house, then click a material to search for it.")
		return
	end
	local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, C_AuctionHouse.MakeItemKey(itemID))
	if not ok then return fallBack(auctionHouse, itemID, info) end
	if info then
		pending = nil
		local shown, problem = pcall(showItem, auctionHouse, itemID, qty, info.isCommodity)
		if not shown then fallBack(auctionHouse, itemID, problem) end
		return
	end
	-- The game is loading the item's auction details, and says when it has them.
	local waiting = { itemID = itemID, qty = qty }
	pending = waiting
	C_Timer.After(INFO_WAIT, function()
		if pending ~= waiting then return end
		pending = nil
		local current = auctionFrame()
		if current then fallBack(current, itemID, "the item's auction details didn't load") end
	end)
end

-- Testing: why the last click searched by name instead of opening the item.
function ShoppingList.Explain()
	ns.Shopping.Say(lastProblem and ("Testing: the last auction house search went by name: " .. lastProblem)
		or "Testing: no shopping list click has had to search by name.")
	ns.Shopping.Say(unnamed and format("Testing: item %d still has no name after %d looks.", unnamed, nameLooks)
		or "Testing: every name on the shopping list has loaded.")
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
-- Two kinds share a row: a list's name with its Clear button, and a material
-- with what that amount costs.

local function rowTooltip(row)
	local data = row.data
	if not data or data.header then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(data.itemID)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(Color("simulated", "Click: show it at the auction house"))
	GameTooltip:AddLine(Color("simulated", "Right-click: take it off the list"))
	GameTooltip:Show()
end

local function rowClick(row, mouseButton)
	local data = row.data
	if not data or data.header then return end
	if mouseButton == "RightButton" then
		GameTooltip:Hide()
		ns.Shopping.RemoveOwn(data.listName, data.itemID)
	elseif IsModifiedClick() then
		-- Shift-click links it in chat, as on any item.
		local _, link = C_Item.GetItemInfo(data.itemID)
		if link then HandleModifiedItemClick(link) end
	else
		search(data.itemID, data.qty)
	end
end

local function createRow(row)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(1, 1, 1, 0.08)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.amount:SetPoint("RIGHT", -6, 0)
	row.amount:SetJustifyH("RIGHT")
	row.clear = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.clear:SetText("Clear")
	row.clear:SetSize(row.clear:GetFontString():GetUnboundedStringWidth() + 24, ROW_HEIGHT - 4)
	row.clear:SetPoint("RIGHT", -2, 0)
	row.clear:SetScript("OnClick", function() ns.Shopping.ClearOwn(row.data.name) end)
	row:SetScript("OnClick", rowClick)
	row:SetScript("OnEnter", rowTooltip)
	row:SetScript("OnLeave", GameTooltip_Hide)
end

local function drawRow(row, data)
	if not row.text then createRow(row) end
	row.data = data
	local header = data.header == true
	row.clear:SetShown(header)
	row.highlight:SetShown(not header)
	row.text:ClearAllPoints()
	row.text:SetPoint("LEFT", 6, 0)
	row.text:SetPoint("RIGHT", header and row.clear or row.amount, "LEFT", -6, 0)
	if header then
		row.text:SetFontObject("GameFontNormal")
		row.text:SetText(data.name)
		row.amount:SetText("")
	else
		row.text:SetFontObject("GameFontHighlight")
		row.text:SetText(ns.Format.Item(data.itemID, data.qty))
		row.amount:SetText(data.cost and ns.Format.Money(data.cost) or Color("muted", "no price"))
	end
	if GameTooltip:IsOwned(row) then
		if header then GameTooltip:Hide() else rowTooltip(row) end
	end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- Beside the auction house while it's open, past its side buttons, else in the
-- middle of the screen until you drag it. Only moved when that changes, so a
-- dragged window stays.
local function place()
	local auctionHouse = atAuctionHouse and auctionFrame()
	if auctionHouse and not docked then
		docked = true
		frame:ClearAllPoints()
		local side = sideTab and sideTab:IsShown() and (sideTab:GetWidth() + SIDE_X) or 0
		frame:SetPoint("TOPLEFT", auctionHouse, "TOPRIGHT", side + DOCK_GAP, 0)
	elseif docked and not auctionHouse then
		docked = false
		frame:ClearAllPoints()
		frame:SetPoint("CENTER")
	end
end

---------------------------------------------------------------------------
-- The side button on the auction house window
---------------------------------------------------------------------------
-- Other addons (All The Things) put their side buttons in the same place, and
-- share a frame for it, AuctionHouseFrameTabSideBar: its Tabs lists the buttons
-- top to bottom, and selTab is the one whose window is open. Craft Profit's joins
-- it when it's there, so the buttons stack and only one window is open at a time.
-- It's another addon's arrangement, so every step into it is guarded.

-- The shared frame and this button's place in its list, when another addon made it.
local function sideBar()
	local bar = AuctionHouseFrameTabSideBar
	if type(bar) == "table" and type(bar.Tabs) == "table" then return bar, tIndexOf(bar.Tabs, sideTab) end
end

-- The button is lit while the window is open. With the shared frame, the other
-- addon's window closes when this one opens, as this one does for it.
local function syncSideTab()
	if not sideTab then return end
	local open = frame ~= nil and frame:IsShown() and atAuctionHouse
	sideTab:SetChecked(open)
	pcall(function()
		local bar, mine = sideBar()
		if not (bar and mine) then return end
		if open then
			local other = bar.Tabs[bar.selTab or 0]
			if other and other ~= sideTab then other:GetScript("OnMouseUp")(other) end
			bar.selTab = mine
		elseif bar.selTab == mine then
			bar.selTab = 0
		end
	end)
end

local function sideTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Craft Profit")
	GameTooltip:AddLine("Your shopping list, selling, your auctions and the price scan.", 1, 1, 1, true)
	GameTooltip:Show()
end

local function createSideTab(auctionHouse)
	sideTab = CreateFrame("Frame", nil, auctionHouse, "LargeSideTabButtonTemplate")
	sideTab.Icon:SetTexture(SIDE_ICON)
	sideTab:SetFillToInterior(true)
	sideTab:SetChecked(false)
	sideTab:SetCustomOnMouseUpHandler(function(_, button, upInside)
		-- Another addon's side button asks this way for the window to close, for its own to open.
		if button == nil then
			if frame then frame:Hide() end
			return
		end
		if button ~= "LeftButton" or upInside == false then return end
		if frame and frame:IsShown() then
			frame:Hide()
		else
			openedByAuctionHouse = true
			ShoppingList.Show(ns.db.auctionTab)
		end
	end)
	sideTab:SetScript("OnEnter", sideTooltip)
	sideTab:SetScript("OnLeave", GameTooltip_Hide)
end

-- Makes the button the first time, and puts it under the other addons' buttons,
-- or in the first place when there are none.
local function placeSideTab()
	local auctionHouse = AuctionHouseFrame
	if not (auctionHouse and atAuctionHouse) then return end
	if not sideTab then
		if not pcall(createSideTab, auctionHouse) or not sideTab then return end
	end
	local parent, above = auctionHouse, nil
	pcall(function()
		local bar, mine = sideBar()
		if not bar then return end
		if not mine then
			bar.Tabs[#bar.Tabs + 1] = sideTab
			mine = #bar.Tabs
		end
		parent, above = bar, bar.Tabs[mine - 1]
	end)
	sideTab:SetParent(parent)
	sideTab:ClearAllPoints()
	if above then
		sideTab:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -SIDE_GAP)
	else
		sideTab:SetPoint("TOPLEFT", parent, "TOPRIGHT", SIDE_X, SIDE_Y)
	end
	sideTab:Show()
	syncSideTab()
end

-- Draws every list that has something on it, and the total.
function ShoppingList.Refresh()
	if not (frame and frame:IsShown()) or tab ~= "shop" then return end
	local rows, total, unpriced = {}, 0, 0
	unnamed = nil
	for _, list in ipairs(ns.Shopping.OwnLists()) do
		rows[#rows + 1] = { header = true, name = list.name }
		for _, item in ipairs(list.items) do
			if not ns.Format.ItemName(item.itemID) then unnamed = item.itemID end
			local price = ns.Prices.Buy(item.itemID)
			local cost = price and price * item.qty
			if cost then total = total + cost else unpriced = unpriced + 1 end
			rows[#rows + 1] = { listName = list.name, itemID = item.itemID, qty = item.qty, cost = cost }
		end
	end
	scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
	empty:SetShown(#rows == 0)
	local text = ""
	if total > 0 then
		text = "Total: " .. ns.Format.Money(total)
		if unpriced > 0 then text = text .. Color("muted", format("  (%d with no price)", unpriced)) end
	end
	footer:SetText(text)
	-- A name is still loading: look again soon, whether or not the game says it arrived.
	if not unnamed then
		nameLooks = 0
	elseif not nameLookDue and nameLooks < NAME_TRIES then
		nameLookDue = true
		nameLooks = nameLooks + 1
		C_Timer.After(NAME_RETRY, function()
			nameLookDue = false
			ShoppingList.Refresh()
		end)
	end
end

-- Shows one tab's frame, making it the first time. Away from the auction house
-- Sell and My auctions say to open it.
local function setTab(key)
	tab = key
	-- Away from the auction house it's always the shopping list, which isn't a choice to remember.
	if atAuctionHouse then ns.db.auctionTab = key end
	if not panels[key] then
		panels[key] = ns[TAB_MODULES[key]].Create(frame, WIDTH, HEIGHT)
	end
	for name, panel in pairs(panels) do panel:SetShown(name == key) end
	frame.Inset:SetShown(key == "shop")
	frame:SetTitle(TAB_LABELS[key])
	PanelTemplates_SetTab(frame, tIndexOf(TAB_KEYS, key))
	-- The selected tab's label uses another font, so every tab measures again.
	for _, button in ipairs(frame.Tabs) do
		PanelTemplates_TabResize(button, TAB_PADDING)
		-- The other tabs all need the auction house, so there's nothing to switch to away from it.
		button:SetShown(atAuctionHouse)
	end
	ShoppingList.Refresh()
end

local function createTabs()
	for index, key in ipairs(TAB_KEYS) do
		local button = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
		button:SetID(index)
		button:SetText(TAB_LABELS[key])
		button:SetNormalFontObject("GameFontNormal")
		button:SetHighlightFontObject("GameFontHighlight")
		button:SetDisabledFontObject("GameFontHighlight")
		button:SetScript("OnClick", function() setTab(key) end)
		PanelTemplates_TabResize(button, TAB_PADDING)
	end
	frame.Tabs[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
	PanelTemplates_SetNumTabs(frame, #TAB_KEYS)
end

local function create()
	frame = CreateFrame("Frame", "CraftProfitShoppingList", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(frame)
	frame:SetTitle(TAB_LABELS.shop)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		docked = false -- dragged away from the auction house: it stays where you put it
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "CraftProfitShoppingList")
	frame.Inset:ClearAllPoints()
	frame.Inset:SetPoint("TOPLEFT", SIDE - 4, -INSET_TOP)
	frame.Inset:SetPoint("BOTTOMRIGHT", -(SIDE - 4), INSET_BOTTOM)

	-- The Shopping list tab: everything on it sits in one frame, shown with the tab.
	local shop = CreateFrame("Frame", nil, frame)
	shop:SetAllPoints()
	panels.shop = shop
	scrollBox = CreateFrame("Frame", nil, shop, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", INSET_PAD, -INSET_PAD)
	scrollBox:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -SCROLLBAR_ROOM, INSET_PAD)
	local scrollBar = CreateFrame("EventFrame", nil, shop, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", drawRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	empty = shop:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	empty:SetPoint("CENTER", scrollBox, "CENTER")
	empty:SetWidth(WIDTH - 80)
	empty:SetText(EMPTY_TEXT)

	footer = shop:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	footer:SetPoint("BOTTOMLEFT", SIDE + 4, 10)

	createTabs()

	-- Item names arrive from the server after first use; many can arrive at once.
	local namesDue = false
	frame:SetScript("OnEvent", function()
		if namesDue then return end
		namesDue = true
		C_Timer.After(NAMES_WAIT, function()
			namesDue = false
			ShoppingList.Refresh()
		end)
	end)
	frame:SetScript("OnShow", function(self)
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		syncSideTab()
	end)
	frame:SetScript("OnHide", function(self)
		self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
		openedByAuctionHouse = false
		nameLooks = 0
		scrollBox:SetDataProvider(CreateDataProvider({}))
		GameTooltip:Hide()
		syncSideTab()
	end)
end

-- Opens the window on a tab: "shop" (when none is named), "sell", "auctions" or
-- "prices". Away from the auction house it's always the shopping list.
function ShoppingList.Show(key)
	-- A menu passes its own things here, so only a tab's name counts.
	key = (atAuctionHouse and TAB_LABELS[key]) and key or "shop"
	if not frame then create() end
	place()
	frame:Show()
	setTab(key)
end

-- Opens the window on that tab, or closes it when that tab is already showing.
function ShoppingList.Toggle(key)
	key = TAB_LABELS[key] and key or "shop"
	if key ~= "shop" and not atAuctionHouse then
		ns.Shopping.Say(format("Open the auction house to use the %s tab.", TAB_LABELS[key]))
		return
	end
	if frame and frame:IsShown() and tab == key then frame:Hide() else ShoppingList.Show(key) end
end

-- Materials were just added: at the auction house the window opens for them.
-- Elsewhere, chat says once how to open it.
function ShoppingList.Added()
	if frame and frame:IsShown() then return end
	if atAuctionHouse then
		openedByAuctionHouse = true
		ShoppingList.Show()
	elseif not hinted then
		hinted = true
		ns.Shopping.Say(Color("muted", "/craftprofit shop shows your shopping list. It opens by itself at the auction house."))
	end
end

---------------------------------------------------------------------------
-- The auction house opening and closing
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("ITEM_KEY_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event, itemID)
	if event == "AUCTION_HOUSE_SHOW" then
		atAuctionHouse = true
		-- A moment later: the auction house window itself is opening on this event.
		C_Timer.After(0, function()
			if not atAuctionHouse then return end
			placeSideTab() -- before the window, which docks past it
			if frame and frame:IsShown() then
				place()
				setTab(tab) -- the other tabs are back
			elseif ns.db.auctionWindow and auctionFrame() then
				-- Only beside the game's own window: it doesn't open over another addon's.
				-- With something to buy, the shopping list. With nothing, the window still
				-- opens for selling, unless Auctionator is there to do that.
				if ns.Shopping.ListTarget() == "own" and ns.Shopping.OwnHasItems() then
					openedByAuctionHouse = true
					ShoppingList.Show("shop")
				elseif not Auctionator then
					openedByAuctionHouse = true
					ShoppingList.Show(ns.db.auctionTab ~= "shop" and ns.db.auctionTab or "sell")
				end
			end
		end)
		-- Again a moment later: another addon may only now have put its side button up.
		C_Timer.After(SIDE_RECHECK, placeSideTab)
	elseif event == "AUCTION_HOUSE_CLOSED" then
		atAuctionHouse, pending = false, nil
		syncSideTab()
		if frame and frame:IsShown() then
			if openedByAuctionHouse then
				frame:Hide()
			else
				-- You opened it yourself: it stays, as only the shopping list.
				place()
				setTab("shop")
			end
		end
	elseif pending and pending.itemID == itemID then
		local waiting = pending
		pending = nil
		search(waiting.itemID, waiting.qty)
	end
end)
