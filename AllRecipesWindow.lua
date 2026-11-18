-- Craft Profit: the All recipes window, on WoW Forever. Every profession's
-- recipes with what a craft would make at today's prices and how the item sells,
-- whether or not a character of yours knows the recipe (see AllRecipes.lua).
local _, ns = ...
if ns.QUALITY_CRAFTING then return end

local AllRecipesWindow = {}
ns.AllRecipesWindow = AllRecipesWindow

local Color, Money = ns.Color, ns.Format.Money
local format = string.format

local WIDTH, HEIGHT = 1040, 640
local SIDE = 12             -- window edge to its content
local FILTERS_TOP = 30      -- window top to the search box and the profession filter
local INSET_TOP = 62        -- window top to the list's box
local INSET_PAD = 8         -- that box's edge to what's in it
local SCROLLBAR_ROOM = 20
local HEADER_HEIGHT = 22
local ROW_HEIGHT = 24
local ICON_SIZE = 20
local CELL_GAP = 8
local SORT_ARROW_ATLAS = "auctionhouse-ui-sortarrow"
local SORT_ARROW_FILE = "Interface\\Buttons\\UI-SortArrow"
local SORT_ARROW_SIZE = 10
local INFO_ICON = "Interface\\Common\\help-i"
local REFRESH_DELAY = 0.2   -- redraws are batched this long
local PRICING = "Pricing every recipe... %d%%"
local NO_PRICES = "None of these recipes' items has an auction price yet.\nPrices: %s"
local NO_MATCH = "Nothing matches the search and the profession."
local HOW = "Every recipe is priced as if you bought all its materials and sold what one craft makes, at "
	.. "today's prices, whether or not one of your characters knows it.\n\nLeft out: items that are bound when "
	.. "picked up, enchants that make no item, and items with no auction price. A recipe that makes a varying "
	.. "number of items counts the average."

local frame, scrollBox, footer, empty, searchBox, professionDropdown
local headers = {}
local professionFilter -- a profession's ID, or nil for all
local sort -- { key, ascending }; nil until the window first opens
local columns = {} -- the columns that show right now (see shownColumns)
local refreshQueued = false

---------------------------------------------------------------------------
-- Columns: key, header, tip (what the header's tooltip says), width, sort (the
-- row's field it sorts by, or a function), text. The first is the name and takes
-- the room the others leave. left: its text starts at the left. ascending: the
-- first click sorts it A to Z. shown: a function that says whether it shows.
---------------------------------------------------------------------------

local function moneyOrDash(amount)
	return amount and Money(amount) or Color("muted", "-")
end

-- Green or red by the amount as it shows: a loss of under half a copper reads 0, in green.
local function netText(row)
	if not row.net then return Color("muted", "-") end
	local net = math.floor(row.net + 0.5)
	return Color(ns.AmountColor(net), Money(net))
end

local function soldText(row)
	local sold = row.soldPerDay
	if not sold then return Color("muted", "-") end
	if sold >= 100 then return BreakUpLargeNumbers(math.floor(sold + 0.5)) end
	return sold < 0.05 and "<0.1" or format("%.1f", sold)
end

local function grossTip()
	return ns.db.ahCut
		and format("What the items one craft makes sell for, after the %d%% auction house cut.", ns.AH_CUT * 100)
		or "What the items one craft makes sell for."
end

local COLUMNS = {
	{ key = "name", header = "Item", tip = "What the recipe makes, with how many when one craft makes more than one.",
		sort = function(row) return row.name:lower() end, ascending = true },
	{ key = "profession", header = "Profession", tip = "The profession the recipe belongs to.", width = 120,
		sort = "profession", left = true, ascending = true, text = function(row) return row.profession end },
	{ key = "cost", header = "Materials", width = 104, sort = "cost",
		tip = "What the materials for one craft cost to buy: at a vendor when one sells them, otherwise on the "
			.. "auction house. A dash when one of them has no price.",
		text = function(row) return moneyOrDash(row.cost) end },
	{ key = "gross", header = "Gross Profit", width = 104, sort = "gross", tip = grossTip,
		text = function(row) return moneyOrDash(row.gross) end },
	{ key = "net", header = "Net Profit", width = 104, sort = "net", tip = "Gross Profit minus Materials.", text = netText },
	{ key = "saleRate", header = "TSM Sale Rate", width = 112, sort = "saleRate", shown = ns.Prices.HasSaleRate,
		tip = "Of the auctions posted for this item, the share that sells, from TSM: a high rate means it sells, a "
			.. "low one that most expire.",
		text = function(row) return row.saleRate and ns.Format.SaleRate(row.saleRate) or Color("muted", "-") end },
	{ key = "soldPerDay", header = "Sold per Day", width = 104, sort = "soldPerDay", shown = ns.Prices.HasTSM,
		tip = "How many of this item sell in a day, on average, from TSM.", text = soldText },
}

-- The columns that show: all of them with TSM, the ones that need no TSM without.
local function shownColumns()
	local list = {}
	for _, column in ipairs(COLUMNS) do
		if not column.shown or column.shown() then list[#list + 1] = column end
	end
	return list
end

-- Where each column sits in a row `width` wide; the name takes what the others leave.
local function columnPlaces(width)
	local places, right = {}, width - 4
	for i = #columns, 2, -1 do
		local column = columns[i]
		places[i] = { x = right - column.width, width = column.width }
		right = right - column.width - CELL_GAP
	end
	local nameX = 4 + ICON_SIZE + 6
	places[1] = { x = nameX, width = right - nameX }
	return places
end

-- The sort in use: yours, or to start with, what sells most (the most profit
-- without TSM). A column that no longer shows gives way to that too.
local function currentSort()
	local key = sort and sort.key
	for _, column in ipairs(columns) do
		if column.key == key then return sort, column end
	end
	sort = { key = ns.Prices.HasTSM() and "soldPerDay" or "net", ascending = false }
	for _, column in ipairs(columns) do
		if column.key == sort.key then return sort, column end
	end
end

local function sortRows(rows)
	local order, column = currentSort()
	local valueOf = column.sort
	local function read(row)
		if type(valueOf) == "function" then return valueOf(row) end
		return row[valueOf]
	end
	table.sort(rows, function(a, b)
		local av, bv = read(a), read(b)
		-- Rows without the number go last, whichever way it sorts.
		if (av == nil) ~= (bv == nil) then return av ~= nil end
		if av == bv then
			if a.name ~= b.name then return a.name < b.name end
			return a.recipeID < b.recipeID
		end
		if order.ascending then return av < bv end
		return av > bv
	end)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

-- "Bronze Bar x2": the item, and how many when one craft makes more than one.
local function nameText(row)
	local text = ns.Format.RarityColored(row.itemID, row.name)
	if row.made == 1 then return text end
	return text .. " " .. Color("muted", "x" .. tostring(row.made))
end

local function addPair(left, right)
	GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
end

local function showRowTooltip(button)
	local row = button.row
	if not row then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(ns.Format.RarityColored(row.itemID, row.name))
	if row.recipeName and row.recipeName ~= row.name then
		GameTooltip:AddLine(format("%s (%s)", row.recipeName, row.profession), 1, 1, 1)
	else
		GameTooltip:AddLine(row.profession, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Materials for one craft")
	for _, material in ipairs(row.materials) do
		local price = ns.Prices.Buy(material.itemID)
		addPair(ns.Format.Item(material.itemID, material.qty),
			price and Money(price * material.qty) or Color("warning", "no price"))
	end
	GameTooltip:AddLine(" ")
	addPair("Materials", row.cost and Money(row.cost) or Color("warning", "not all priced"))
	addPair(row.made == 1 and "Sells for" or format("Sells for (%s x %s)", tostring(row.made), Money(row.each)),
		Money(row.each * row.made))
	if ns.db.ahCut then
		addPair(format("Auction house cut (%d%%)", ns.AH_CUT * 100), Money(row.gross - row.each * row.made))
	end
	addPair("Gross Profit", Money(row.gross))
	addPair("Net Profit", netText(row))
	if ns.Prices.HasSaleRate() then
		addPair("TSM Sale Rate", row.saleRate and ns.Format.SaleRate(row.saleRate) or Color("muted", "-"))
	end
	if ns.Prices.HasTSM() then addPair("Sold per Day", soldText(row)) end
	GameTooltip:Show()
end

local function createRow(button)
	button.cells = {}
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(ICON_SIZE, ICON_SIZE)
	button.icon:SetPoint("LEFT", 4, 0)
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.stripe = button:CreateTexture(nil, "BACKGROUND")
	button.stripe:SetAllPoints()
	button.stripe:SetColorTexture(1, 1, 1, 0.035)
	button:SetScript("OnEnter", showRowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
end

local function cellOf(button, index)
	local cell = button.cells[index]
	if not cell then
		cell = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		cell:SetWordWrap(false)
		button.cells[index] = cell
	end
	return cell
end

local function drawRow(button, row)
	if not button.cells then createRow(button) end
	button.row = row
	local places = columnPlaces(scrollBox:GetWidth())
	for i, cell in ipairs(button.cells) do cell:SetShown(i <= #columns) end
	for i, column in ipairs(columns) do
		local cell = cellOf(button, i)
		cell:Show()
		cell:ClearAllPoints()
		cell:SetPoint("LEFT", button, "LEFT", places[i].x, 0)
		cell:SetWidth(places[i].width)
		cell:SetJustifyH((i == 1 or column.left) and "LEFT" or "RIGHT")
		cell:SetText(i == 1 and nameText(row) or column.text(row))
	end
	button.stripe:SetShown(row.stripe == true)
	button.icon:SetTexture(C_Item.GetItemIconByID(row.itemID))
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function showHeaderTip(header)
	local column = header.column
	if not column then return end
	GameTooltip:SetOwner(header, "ANCHOR_TOP")
	GameTooltip:SetText(column.header)
	GameTooltip:AddLine(type(column.tip) == "function" and column.tip() or column.tip, 1, 1, 1, true)
	GameTooltip:AddLine("Click to sort.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function createHeader()
	local header = CreateFrame("Button", nil, frame)
	header.text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	header.text:SetAllPoints()
	header.arrow = header:CreateTexture(nil, "OVERLAY")
	header.arrow:SetSize(SORT_ARROW_SIZE, SORT_ARROW_SIZE)
	if C_Texture.GetAtlasInfo(SORT_ARROW_ATLAS) then
		header.arrow:SetAtlas(SORT_ARROW_ATLAS)
	else
		header.arrow:SetTexture(SORT_ARROW_FILE)
	end
	header:SetScript("OnClick", function(self)
		local column = self.column
		if not column then return end
		if sort and sort.key == column.key then
			sort.ascending = not sort.ascending
		else
			sort = { key = column.key, ascending = column.ascending == true }
		end
		AllRecipesWindow.Render()
	end)
	header:SetScript("OnEnter", showHeaderTip)
	header:SetScript("OnLeave", GameTooltip_Hide)
	return header
end

local function drawHeaders()
	local places = columnPlaces(scrollBox:GetWidth())
	for _, header in ipairs(headers) do header:Hide() end
	local order = currentSort()
	for i, column in ipairs(columns) do
		local header = headers[i]
		if not header then
			header = createHeader()
			headers[i] = header
		end
		local left = i == 1 or column.left
		header:ClearAllPoints()
		header:SetPoint("BOTTOMLEFT", scrollBox, "TOPLEFT", places[i].x, 0)
		header:SetSize(places[i].width, HEADER_HEIGHT)
		header.column = column
		header.text:SetJustifyH(left and "LEFT" or "RIGHT")
		local sorted = order.key == column.key
		header.text:SetText(sorted and Color("heading", column.header) or column.header)
		header.arrow:SetShown(sorted)
		if sorted then
			if order.ascending then header.arrow:SetTexCoord(0, 1, 1, 0) else header.arrow:SetTexCoord(0, 1, 0, 1) end
			header.arrow:ClearAllPoints()
			local textWidth = header.text:GetStringWidth()
			if left then
				header.arrow:SetPoint("LEFT", header, "LEFT", textWidth + 3, 0)
			else
				header.arrow:SetPoint("RIGHT", header, "RIGHT", -textWidth - 3, 0)
			end
		end
		header:Show()
	end
end

-- The recipes with a price that the profession and the search leave, and how
-- many recipes have no price at all.
local function inView(rows)
	local search = searchBox:GetText():lower()
	local list, unpriced = {}, 0
	for _, row in ipairs(rows) do
		if not row.each then
			unpriced = unpriced + 1
		elseif (not professionFilter or row.professionID == professionFilter)
			and (search == "" or row.name:lower():find(search, 1, true)
				or (row.recipeName and row.recipeName:lower():find(search, 1, true))) then
			list[#list + 1] = row
		end
	end
	return list, unpriced
end

-- What TSM would add, for the footer; nil with TSM loaded.
local function tsmNote()
	if ns.Prices.HasSaleRate() then return end
	if ns.Prices.HasTSM() then return "TSM Sale Rate needs TSM on this character" end
	return "TSM Sale Rate and Sold per Day need TSM"
end

local function footerText(shown, priced, unpriced)
	local parts = { priced == shown and format("%s recipes", BreakUpLargeNumbers(shown))
		or format("%s of %s recipes", BreakUpLargeNumbers(shown), BreakUpLargeNumbers(priced)) }
	if unpriced > 0 then parts[#parts + 1] = format("%s more have no auction price", BreakUpLargeNumbers(unpriced)) end
	parts[#parts + 1] = "Prices: " .. ns.Prices.SourceLabel()
	parts[#parts + 1] = tsmNote()
	return Color("muted", table.concat(parts, " · "))
end

-- Shows `text` in place of the list.
local function showInstead(text)
	scrollBox:SetDataProvider(CreateDataProvider({}))
	empty:SetText(text)
	empty:Show()
end

function AllRecipesWindow.Render()
	refreshQueued = false
	if not (frame and frame:IsShown()) then return end
	columns = shownColumns()
	drawHeaders()
	professionDropdown:GenerateMenu()
	local rows = ns.AllRecipes.Rows()
	if not rows then return end
	local list, unpriced = inView(rows)
	local priced = #rows - unpriced
	sortRows(list)
	for index, row in ipairs(list) do row.stripe = index % 2 == 0 end
	footer:SetText(footerText(#list, priced, unpriced))
	if #list == 0 then
		showInstead(priced == 0 and format(NO_PRICES, ns.Prices.SourceLabel()) or NO_MATCH)
		return
	end
	empty:Hide()
	scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)
end

-- A redraw swaps the rows' frames, so it waits for a click or a menu in progress.
local function renderWhenIdle()
	if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") or Menu.GetManager():GetOpenMenu() then
		C_Timer.After(REFRESH_DELAY, renderWhenIdle)
		return
	end
	AllRecipesWindow.Render()
end

local function refresh()
	if refreshQueued or not (frame and frame:IsShown()) then return end
	refreshQueued = true
	C_Timer.After(REFRESH_DELAY, renderWhenIdle)
end

-- Pricing moved on: how far it is, then the list once every recipe is priced.
local function onPriced(pricing)
	if not (frame and frame:IsShown()) then return end
	if pricing.finished then
		AllRecipesWindow.Render()
	else
		empty:SetText(format(PRICING, pricing.total > 0 and pricing.done / pricing.total * 100 or 0))
	end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function professionMenu(_, root)
	root:CreateRadio("All professions", function() return professionFilter == nil end, function()
		professionFilter = nil
		AllRecipesWindow.Render()
	end)
	for _, profession in ipairs(ns.AllRecipes.Professions()) do
		root:CreateRadio(profession.name, function() return professionFilter == profession.id end, function()
			professionFilter = profession.id
			AllRecipesWindow.Render()
		end)
	end
end

local function showNote(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("How this is worked out")
	GameTooltip:AddLine(HOW, 1, 1, 1, true)
	GameTooltip:Show()
end

local function createList()
	scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", INSET_PAD, -(INSET_PAD + HEADER_HEIGHT))
	scrollBox:SetPoint("BOTTOMRIGHT", frame.Inset, "BOTTOMRIGHT", -SCROLLBAR_ROOM, INSET_PAD)
	local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", drawRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	local headerBar = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	headerBar:SetPoint("BOTTOMLEFT", scrollBox, "TOPLEFT", 0, 0)
	headerBar:SetPoint("BOTTOMRIGHT", scrollBox, "TOPRIGHT", 0, 0)
	headerBar:SetHeight(HEADER_HEIGHT)
	headerBar:SetColorTexture(0, 0, 0, 0.5)

	empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	empty:SetPoint("CENTER", scrollBox, "CENTER")
	empty:SetWidth(WIDTH - 200)
end

local function create()
	frame = CreateFrame("Frame", "CraftProfitAllRecipes", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(frame)
	frame:SetTitle("All recipes")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "CraftProfitAllRecipes")
	frame.Inset:ClearAllPoints()
	frame.Inset:SetPoint("TOPLEFT", SIDE - 4, -INSET_TOP)
	frame.Inset:SetPoint("BOTTOMRIGHT", -(SIDE - 4), 32)

	searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	searchBox:SetSize(220, 20)
	searchBox:SetPoint("TOPLEFT", SIDE + 6, -(FILTERS_TOP + 2))
	searchBox:SetAutoFocus(false)
	searchBox:HookScript("OnTextChanged", refresh)

	professionDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	professionDropdown:SetWidth(170)
	professionDropdown:SetPoint("TOPRIGHT", -SIDE, -FILTERS_TOP)
	professionDropdown:SetupMenu(professionMenu)

	createList()

	footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	footer:SetPoint("BOTTOMLEFT", SIDE + 4, 10)

	local info = CreateFrame("Button", nil, frame)
	info:SetSize(20, 20)
	info:SetPoint("LEFT", footer, "RIGHT", 6, 0)
	info:SetNormalTexture(INFO_ICON)
	info:SetScript("OnEnter", showNote)
	info:SetScript("OnLeave", GameTooltip_Hide)

	-- Item names arrive from the game after first use.
	frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	frame:SetScript("OnEvent", function(_, _, itemID)
		if ns.AllRecipes.NameArrived(itemID) then refresh() end
	end)
	-- Only the packed recipes stay when it closes.
	frame:SetScript("OnHide", function()
		ns.AllRecipes.Release()
		scrollBox:SetDataProvider(CreateDataProvider({}))
		GameTooltip:Hide()
	end)
end

-- Opens the window and prices every recipe again, at the prices of this moment.
function AllRecipesWindow.Show()
	if not frame then create() end
	frame:Show()
	footer:SetText(Color("muted", "Prices: " .. ns.Prices.SourceLabel()))
	showInstead(format(PRICING, 0))
	ns.AllRecipes.Price(onPriced)
	-- The column names, while the recipes are priced.
	AllRecipesWindow.Render()
end

function AllRecipesWindow.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		AllRecipesWindow.Show()
	end
end
