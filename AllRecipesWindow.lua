-- Craft Profit: the All recipes window. Every profession's recipes with what a
-- craft would make at today's prices and how the item sells, whether or not a
-- character of yours knows the recipe (see AllRecipes.lua). On WoW Forever an
-- enchant, which makes nothing to sell, is listed with what its materials cost.
-- On Retail it lists one expansion at a time, at the rank you pick.
local _, ns = ...

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
local NO_PRICES = "None of these recipes' items or materials has a price yet.\nPrices: %s"
local NO_MATCH = "Nothing matches the search and the filters."
local CHECK_SIZE = 24       -- the Only profitable checkbox
local FILTERS_BUTTON_WIDTH = 96 -- the Filters button: room for "Filters (3)"
local FILTERS_WIDTH = 326  -- the box of filters the button opens,
local FILTERS_PAD = 12      -- its edge to what's in it,
local FILTER_LINE = 30      -- from one of its lines to the next,
local FILTERS_HEIGHT = 2 * FILTERS_PAD + 3 * FILTER_LINE + 28 -- its three lines and the Clear button
local FILTER_BOX_X = 118    -- where its number boxes start, right of their names
local RATE_BOX_WIDTH = 36   -- a sale rate box: up to "100"
local GOLD_BOX_WIDTH = 56   -- the lowest net profit's gold box,
local COIN_BOX_WIDTH = 30   -- and its silver and copper boxes
local FILTERS_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local HOW = "Every recipe is priced as if you bought all its materials and sold what one craft makes, at "
	.. "today's prices, whether or not one of your characters knows it.\n\n"
	.. (ns.QUALITY_CRAFTING
		and "Nobody's skill is there to say which rank a craft would come out at, so you pick: the highest rank "
			.. "with the best materials, or the lowest rank with the cheapest. A skilled crafter often reaches the "
			.. "highest rank with cheaper materials than that. Multicraft, resourcefulness and concentration aren't "
			.. "counted. An enchant is priced as the scroll it makes.\n\n"
		or "An enchant makes nothing to sell: it's listed with what its materials cost.\n\n")
	.. "Left out: items that are bound when picked up, and items with no auction price. A recipe that makes a "
	.. "varying number of items counts the average."
-- Retail: the ranks recipes can be priced at (ns.db.recipesRank).
local RANK_CHOICES = {
	{ "highest", "Highest rank, best materials" },
	{ "lowest", "Lowest rank, cheapest materials" },
}
local EXPANSION_WIDTH = 190 -- the expansion dropdown: room for "Wrath of the Lich King"
local RANK_WIDTH = 250      -- the rank dropdown: room for "Lowest rank, cheapest materials"

local frame, scrollBox, footer, empty, searchBox, professionDropdown
local expansionDropdown, rankDropdown -- Retail only
-- The Filters button beside the search box and the box it opens, with what's in
-- it: Only profitable, the lowest net profit's gold, silver and copper boxes, and
-- the lowest and highest TSM sale rate.
local filtersButton, filtersBox, profitableCheck, rateMinBox, rateMaxBox
local netBoxes = {}
local rateParts = {}   -- the sale rate's line: its boxes and the texts around them (only with TSM)
local filterBoxes = {} -- every number box, in the order Tab goes through them
local drawFilters      -- see The filters, below
local headers = {}
local professionFilter -- a profession's ID, or nil for all
local MAX_SORTS = 3 -- how many columns the list sorts by at once
-- A sorted column's name, by its place in the sort: gold, light blue, light green.
local SORT_COLORS = { "heading", "secondSort", "thirdSort" }
-- { key, ascending } ...: the column the list sorts by, then the ones that settle
-- its ties, in order. Empty until the window first opens.
local sorts = {}
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

-- What the materials cost, in red: it's gold the craft takes from you.
local function costText(row)
	return row.cost and Color("loss", Money(row.cost)) or Color("muted", "-")
end

-- Green or red by the amount as it shows: a loss of under half a copper reads 0, in green.
local function netText(row)
	if not row.net then return Color("muted", "-") end
	local net = math.floor(row.net + 0.5)
	return Color(ns.AmountColor(net), Money(net))
end

-- The skill the recipe needs, in orange. For a recipe a trainer teaches the game
-- data doesn't have it: then the skill where it turns yellow, in yellow.
local function skillText(row)
	if row.required then return ns.Skillups.Colored("orange", tostring(row.required)) end
	if row.yellow then return ns.Skillups.Colored("yellow", tostring(row.yellow)) end
	return Color("muted", "-")
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
	{ key = "name", header = "Item", tip = "What the recipe makes, with how many when one craft makes more than one. "
		.. "An enchant goes by its own name.",
		sort = function(row) return row.name:lower() end, ascending = true },
	{ key = "profession", header = "Profession", tip = "The profession the recipe belongs to.", width = 120,
		sort = "profession", left = true, ascending = true, text = function(row) return row.profession end },
	{ key = "skill", header = "Skill", width = 48, sort = "skill", ascending = true, text = skillText,
		shown = function() return not ns.QUALITY_CRAFTING end, -- Retail's recipes don't go by a skill number
		tip = "The profession skill the recipe needs, in orange. The game only says that for recipes learned from "
			.. "a recipe item (a pattern, plans, a schematic...).\n\nFor a recipe a trainer teaches, it's the skill where "
			.. "the recipe turns yellow, in yellow: you can learn it by then, often a little sooner." },
	{ key = "cost", header = "Materials", width = 104, sort = "cost",
		tip = "What the materials for one craft cost to buy: at a vendor when one sells them, otherwise on the "
			.. "auction house. In red, since it's gold the craft takes from you. A dash when one of them has no price.",
		text = costText },
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

-- The column that shows right now with this key, or nil.
local function columnOf(key)
	for _, column in ipairs(columns) do
		if column.key == key then return column end
	end
end

-- The sorts in use, first to last: yours, without the columns that no longer
-- show, or to start with, what sells most (the most profit without TSM).
local function currentSorts()
	for i = #sorts, 1, -1 do
		if not columnOf(sorts[i].key) then table.remove(sorts, i) end
	end
	if #sorts == 0 then
		local key = ns.Prices.HasTSM() and columnOf("soldPerDay") and "soldPerDay" or "net"
		sorts[1] = { key = key, ascending = false }
	end
	return sorts
end

-- Where a column is in the sort (1 for the first), and its entry there, or nil.
local function sortPlace(key)
	for place, order in ipairs(currentSorts()) do
		if order.key == key then return place, order end
	end
end

-- A click sorts by that column alone, or reverses it. A shift-click (`chain`)
-- keeps the sort and adds the column after it, up to MAX_SORTS columns, or
-- reverses just that column when the list already sorts by it.
local function setSort(column, chain)
	local current = currentSorts()
	local place, order = sortPlace(column.key)
	if not chain then
		local ascending = column.ascending == true
		if place == 1 then ascending = not order.ascending end
		wipe(sorts)
		sorts[1] = { key = column.key, ascending = ascending }
	elseif order then
		order.ascending = not order.ascending
	else
		-- With the list full, it takes the last column's place.
		if #current >= MAX_SORTS then table.remove(current) end
		current[#current + 1] = { key = column.key, ascending = column.ascending == true }
	end
	AllRecipesWindow.Render()
end

local function sortRows(rows)
	-- What each sorted column reads from a row: its field, or a function.
	local chain = {}
	for i, order in ipairs(currentSorts()) do
		chain[i] = { read = columnOf(order.key).sort, ascending = order.ascending }
	end
	local function valueOf(read, row)
		if type(read) == "function" then return read(row) end
		return row[read]
	end
	table.sort(rows, function(a, b)
		for _, order in ipairs(chain) do
			local av, bv = valueOf(order.read, a), valueOf(order.read, b)
			-- Rows without the number go last, whichever way it sorts.
			if (av == nil) ~= (bv == nil) then return av ~= nil end
			if av ~= bv then
				if order.ascending then return av < bv end
				return av > bv
			end
		end
		if a.name ~= b.name then return a.name < b.name end
		return a.recipeID < b.recipeID
	end)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

-- "Bronze Bar x2": the item, and how many when one craft makes more than one.
-- An enchant goes by its own name. On Retail the rank it's priced at follows.
local function nameText(row)
	if row.enchant then return row.name end
	local text = ns.Format.RarityColored(row.itemID, row.name)
	if row.rank then
		-- Asked once for each row; false when the game has no icon for it.
		if row.rankIcon == nil then row.rankIcon = ns.Blizzard.ItemQualityMarkup(row.recipeID, row.rank) or false end
		if row.rankIcon then text = text .. " " .. row.rankIcon end
	end
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
	GameTooltip:SetText(row.enchant and row.name or ns.Format.RarityColored(row.itemID, row.name))
	if row.recipeName and row.recipeName ~= row.name then
		GameTooltip:AddLine(format("%s (%s)", row.recipeName, row.profession), 1, 1, 1)
	else
		GameTooltip:AddLine(row.profession, 1, 1, 1)
	end
	if row.rank then
		addPair("Priced at", (row.rankIcon or ("rank " .. row.rank))
			.. (row.highest and ", best materials" or ", cheapest materials"))
	end
	-- The skill it needs when the game says, then where it turns yellow, green and grey.
	if row.required then addPair("Skill needed", ns.Skillups.Colored("orange", tostring(row.required))) end
	if row.yellow and row.grey then
		addPair("Turns yellow, green, grey at", format("%s  %s  %s", ns.Skillups.Colored("yellow", tostring(row.yellow)),
			ns.Skillups.Colored("green", tostring(math.floor((row.yellow + row.grey) / 2))),
			ns.Skillups.Colored("grey", tostring(row.grey))))
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Materials for one craft")
	for _, material in ipairs(row.materials) do
		local price = ns.Prices.Buy(material.itemID)
		addPair(ns.Format.Item(material.itemID, material.qty),
			price and Money(price * material.qty) or Color("warning", "no price"))
	end
	GameTooltip:AddLine(" ")
	addPair("Materials", row.cost and costText(row) or Color("warning", "not all priced"))
	if row.enchant then
		GameTooltip:AddLine("An enchant makes nothing to sell.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
		return
	end
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
	button.icon:SetTexture(row.itemID and C_Item.GetItemIconByID(row.itemID) or ns.SCROLL_ICON)
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
	GameTooltip:AddLine("Click to sort; click again to reverse.", 0.6, 0.6, 0.6)
	GameTooltip:AddLine(format("Shift-click: sort by this next, up to %d columns", MAX_SORTS), 0.6, 0.6, 0.6)
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
		if self.column then setSort(self.column, IsShiftKeyDown()) end
	end)
	header:SetScript("OnEnter", showHeaderTip)
	header:SetScript("OnLeave", GameTooltip_Hide)
	return header
end

local function drawHeaders()
	local places = columnPlaces(scrollBox:GetWidth())
	for _, header in ipairs(headers) do header:Hide() end
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
		-- A sorted column's name is in the color of its place in the sort, with an arrow.
		local place, order = sortPlace(column.key)
		header.text:SetText(order and Color(SORT_COLORS[place], column.header) or column.header)
		header.arrow:SetShown(order ~= nil)
		if order then
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

-- The recipes with a price, and the enchants, that the profession, the search and
-- the filters leave; how many recipes' items have no price at all; and whether
-- anything has a price. The search looks in the item's name, the recipe's, and the
-- names of its materials.
local function inView(rows)
	local search = searchBox:GetText():lower()
	local list, unpriced, anyPrice = {}, 0, false
	local profitable = ns.db.recipesProfitable
	-- The lowest net profit, in copper.
	local netMin = ns.db.recipesMinNet or nil
	-- The sale rate's bounds, in percent, only with TSM there to say the rate.
	local rated = ns.Prices.HasSaleRate()
	local rateMin, rateMax = rated and ns.db.recipesRateMin or nil, rated and ns.db.recipesRateMax or nil
	-- Whether the row passes Only profitable, the lowest net profit and the sale
	-- rate's bounds, by the numbers as the list shows them. A recipe with no net
	-- profit or no sale rate to go by is left out by the filter that asks about it.
	local function passes(row)
		if profitable and not (row.net and row.net >= 0.5) then return false end
		if netMin and not (row.net and math.floor(row.net + 0.5) >= netMin) then return false end
		if rateMin or rateMax then
			if not row.saleRate then return false end
			local percent = math.floor(row.saleRate * 100 + 0.5)
			if (rateMin and percent < rateMin) or (rateMax and percent > rateMax) then return false end
		end
		return true
	end
	for _, row in ipairs(rows) do
		if row.each or row.cost then anyPrice = true end
		if not row.each and not row.enchant then
			unpriced = unpriced + 1
		elseif not passes(row) then
			-- filtered away
		elseif (not professionFilter or row.professionID == professionFilter)
			and (search == "" or row.name:lower():find(search, 1, true)
				or (row.recipeName and row.recipeName:lower():find(search, 1, true))
				or ns.AllRecipes.UsesMaterial(row, search)) then
			list[#list + 1] = row
		end
	end
	return list, unpriced, anyPrice
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
	if expansionDropdown then
		expansionDropdown:GenerateMenu()
		rankDropdown:GenerateMenu()
	end
	drawFilters()
	local rows = ns.AllRecipes.Rows()
	if not rows then return end
	local list, unpriced, anyPrice = inView(rows)
	local priced = #rows - unpriced
	sortRows(list)
	for index, row in ipairs(list) do row.stripe = index % 2 == 0 end
	footer:SetText(footerText(#list, priced, unpriced))
	if #list == 0 then
		showInstead(anyPrice and NO_MATCH or format(NO_PRICES, ns.Prices.SourceLabel()))
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
		empty:SetText(format(PRICING, pricing.total > 0 and math.floor(pricing.done / pricing.total * 100) or 0))
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

-- Retail: another expansion or rank was picked. The recipes are let go, and the
-- game is asked about the new ones, which are then priced.
local function reload()
	showInstead(format(PRICING, 0))
	ns.AllRecipes.Release()
	ns.AllRecipes.Price(onPriced)
	AllRecipesWindow.Render()
end

local function expansionMenu(_, root)
	for _, expansion in ipairs(ns.AllRecipes.Expansions()) do
		root:CreateRadio(expansion.name, function() return ns.AllRecipes.Expansion() == expansion.id end, function()
			if ns.AllRecipes.Expansion() == expansion.id then return end
			ns.db.recipesExpansion = expansion.id
			reload()
		end)
	end
end

local function rankMenu(_, root)
	for _, choice in ipairs(RANK_CHOICES) do
		local key = choice[1]
		root:CreateRadio(choice[2], function() return ns.AllRecipes.Highest() == (key == "highest") end, function()
			if ns.AllRecipes.Highest() == (key == "highest") then return end
			ns.db.recipesRank = key
			reload()
		end)
	end
end

-- Retail: the expansion and rank dropdowns, left of the profession's.
local function createRetailDropdowns()
	expansionDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	expansionDropdown:SetWidth(EXPANSION_WIDTH)
	expansionDropdown:SetPoint("RIGHT", professionDropdown, "LEFT", -8, 0)
	expansionDropdown:SetupMenu(expansionMenu)
	rankDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	rankDropdown:SetWidth(RANK_WIDTH)
	rankDropdown:SetPoint("RIGHT", expansionDropdown, "LEFT", -8, 0)
	rankDropdown:SetupMenu(rankMenu)
end

local function showNote(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("How this is worked out")
	GameTooltip:AddLine(HOW, 1, 1, 1, true)
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The filters
---------------------------------------------------------------------------

local function showFilterTip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.tipTitle)
	GameTooltip:AddLine(self.tipText, 1, 1, 1, true)
	GameTooltip:Show()
end

-- How many filters are on, for the Filters button: Only profitable, the lowest
-- net profit, and the sale rate's two bounds as one (they only count with TSM).
local function filtersOn()
	local count = 0
	if ns.db.recipesProfitable then count = count + 1 end
	if ns.db.recipesMinNet then count = count + 1 end
	if ns.Prices.HasSaleRate() and (ns.db.recipesRateMin or ns.db.recipesRateMax) then count = count + 1 end
	return count
end

-- The Filters button says how many filters are on, and the filters' box has the
-- sale rate's line only with TSM there to say the rate.
drawFilters = function()
	local count = filtersOn()
	filtersButton:SetText(count > 0 and format("Filters (%d)", count) or "Filters")
	local rated = ns.Prices.HasSaleRate()
	for _, part in ipairs(rateParts) do part:SetShown(rated) end
	filtersBox:SetHeight(rated and FILTERS_HEIGHT or FILTERS_HEIGHT - FILTER_LINE)
end

-- A text in the filters' box.
local function filterText(text)
	local label = filtersBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetText(text)
	return label
end

-- A box for one of a filter's numbers: whole, up to `letters` digits, empty for
-- none. `changed` keeps what's typed.
local function createFilterBox(width, letters, title, tip, changed)
	local box = CreateFrame("EditBox", nil, filtersBox, "InputBoxTemplate")
	box:SetSize(width, 22)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(letters)
	box:SetJustifyH("CENTER")
	box:SetFontObject("GameFontHighlight")
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnTextChanged", function(_, userInput)
		if not userInput then return end
		changed()
		drawFilters()
		refresh()
	end)
	-- Tab goes to the next box that shows, and from the last one back to the first.
	box:SetScript("OnTabPressed", function(self)
		local index = tIndexOf(filterBoxes, self) or 0
		for step = 1, #filterBoxes do
			local nextBox = filterBoxes[(index + step - 1) % #filterBoxes + 1]
			if nextBox:IsShown() then return nextBox:SetFocus() end
		end
	end)
	box.tipTitle, box.tipText = title, tip
	box:SetScript("OnEnter", showFilterTip)
	box:SetScript("OnLeave", GameTooltip_Hide)
	filterBoxes[#filterBoxes + 1] = box
	return box
end

-- The lowest net profit as typed in its gold, silver and copper boxes, in copper,
-- or false with all three empty.
local function typedNet()
	local gold, silver, copper = netBoxes[1]:GetText(), netBoxes[2]:GetText(), netBoxes[3]:GetText()
	if gold == "" and silver == "" and copper == "" then return false end
	return (tonumber(gold) or 0) * 10000 + (tonumber(silver) or 0) * 100 + (tonumber(copper) or 0)
end

-- Puts the saved filters in the box's controls.
local function showFilters()
	profitableCheck:SetChecked(ns.db.recipesProfitable == true)
	local net = ns.db.recipesMinNet
	netBoxes[1]:SetText(net and net >= 10000 and tostring(math.floor(net / 10000)) or "")
	netBoxes[2]:SetText(net and net >= 100 and tostring(math.floor(net / 100) % 100) or "")
	netBoxes[3]:SetText(net and tostring(net % 100) or "")
	rateMinBox:SetText(ns.db.recipesRateMin and tostring(ns.db.recipesRateMin) or "")
	rateMaxBox:SetText(ns.db.recipesRateMax and tostring(ns.db.recipesRateMax) or "")
end

-- The box's first two lines: Only profitable, and the lowest net profit in gold,
-- silver and copper.
local function createProfitFilters()
	profitableCheck = CreateFrame("CheckButton", nil, filtersBox, "UICheckButtonTemplate")
	profitableCheck:SetSize(CHECK_SIZE, CHECK_SIZE)
	profitableCheck:SetPoint("TOPLEFT", FILTERS_PAD - 4, -FILTERS_PAD + 2)
	local label = filterText("Only profitable")
	label:SetPoint("LEFT", profitableCheck, "RIGHT", 2, 0)
	-- The label is clickable too, like Blizzard's.
	profitableCheck:SetHitRectInsets(0, -(label:GetStringWidth() + 2), 0, 0)
	profitableCheck:SetScript("OnClick", function(self)
		ns.db.recipesProfitable = self:GetChecked() == true
		AllRecipesWindow.Render()
	end)
	profitableCheck.tipTitle = "Only profitable"
	profitableCheck.tipText = "Lists only the recipes whose Net Profit is above zero. A recipe with a material "
		.. "that has no price has no Net Profit, and is left out too."
	profitableCheck:SetScript("OnEnter", showFilterTip)
	profitableCheck:SetScript("OnLeave", GameTooltip_Hide)

	local netLabel = filterText("Min Net Profit")
	netLabel:SetPoint("TOPLEFT", FILTERS_PAD, -FILTERS_PAD - FILTER_LINE - 5)
	local tip = "Lists only the recipes whose Net Profit is at least this much gold, silver and copper. All three "
		.. "empty for any. A recipe with a material that has no price has no Net Profit, and is left out while "
		.. "this has a number."
	local function changed() ns.db.recipesMinNet = typedNet() end
	local after
	for index, coin in ipairs({ "Gold", "Silver", "Copper" }) do
		local box = createFilterBox(index == 1 and GOLD_BOX_WIDTH or COIN_BOX_WIDTH, index == 1 and 6 or 2,
			"Lowest Net Profit", tip, changed)
		if after then
			box:SetPoint("LEFT", after, "RIGHT", 10, 0)
		else
			box:SetPoint("LEFT", filtersBox, "TOPLEFT", FILTER_BOX_X, -FILTERS_PAD - FILTER_LINE - 11)
		end
		after = filterText(format("|TInterface\\MoneyFrame\\UI-%sIcon:14:14:0:0|t", coin))
		after:SetPoint("LEFT", box, "RIGHT", 3, 0)
		netBoxes[index] = box
	end
end

-- The box's third line: the lowest and highest TSM sale rate, in percent.
local function createRateFilters()
	local rateLabel = filterText("TSM Sale Rate")
	rateLabel:SetPoint("TOPLEFT", FILTERS_PAD, -FILTERS_PAD - 2 * FILTER_LINE - 5)
	rateMinBox = createFilterBox(RATE_BOX_WIDTH, 3, "Lowest TSM Sale Rate",
		"Lists only the recipes whose item's TSM Sale Rate is at least this, in percent. Empty for any. An item "
			.. "with no sale rate is left out while either box has a number.",
		function() ns.db.recipesRateMin = tonumber(rateMinBox:GetText()) or false end)
	rateMinBox:SetPoint("LEFT", filtersBox, "TOPLEFT", FILTER_BOX_X, -FILTERS_PAD - 2 * FILTER_LINE - 11)
	local toText = filterText("to")
	toText:SetPoint("LEFT", rateMinBox, "RIGHT", 6, 0)
	rateMaxBox = createFilterBox(RATE_BOX_WIDTH, 3, "Highest TSM Sale Rate",
		"Lists only the recipes whose item's TSM Sale Rate is at most this, in percent. Empty for any. An item "
			.. "with no sale rate is left out while either box has a number.",
		function() ns.db.recipesRateMax = tonumber(rateMaxBox:GetText()) or false end)
	rateMaxBox:SetPoint("LEFT", toText, "RIGHT", 12, 0)
	local percentText = filterText("%")
	percentText:SetPoint("LEFT", rateMaxBox, "RIGHT", 4, 0)
	rateParts = { rateLabel, rateMinBox, toText, rateMaxBox, percentText }
end

-- The Filters button right of the search box, and the box it opens under it:
-- Only profitable, the lowest net profit, and the lowest and highest TSM sale
-- rate, with a button that clears them all. The filters are remembered.
local function createFilters()
	filtersButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	filtersButton:SetSize(FILTERS_BUTTON_WIDTH, 22)
	filtersButton:SetPoint("LEFT", searchBox, "RIGHT", 12, 0)
	filtersButton:SetScript("OnClick", function() filtersBox:SetShown(not filtersBox:IsShown()) end)

	filtersBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	filtersBox:SetSize(FILTERS_WIDTH, FILTERS_HEIGHT)
	filtersBox:SetPoint("TOPLEFT", filtersButton, "BOTTOMLEFT", 0, -2)
	filtersBox:SetFrameStrata("DIALOG")
	filtersBox:SetBackdrop(FILTERS_BACKDROP)
	filtersBox:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
	filtersBox:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	filtersBox:EnableMouse(true) -- a click in it doesn't fall through to the list under it
	filtersBox:Hide()

	createProfitFilters()
	createRateFilters()

	local clear = CreateFrame("Button", nil, filtersBox, "UIPanelButtonTemplate")
	clear:SetSize(80, 22)
	clear:SetPoint("BOTTOMRIGHT", -FILTERS_PAD, 10)
	clear:SetText("Clear")
	clear:SetScript("OnClick", function()
		ns.db.recipesProfitable, ns.db.recipesMinNet = false, false
		ns.db.recipesRateMin, ns.db.recipesRateMax = false, false
		showFilters()
		AllRecipesWindow.Render()
	end)

	showFilters()
	drawFilters()
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
	-- The template's own fonts are smaller than the rest of the window's text.
	searchBox:SetFontObject("GameFontHighlight")
	if searchBox.Instructions then
		searchBox.Instructions:SetFontObject("GameFontDisable")
		searchBox.Instructions:SetText("Item or material")
	end
	searchBox:HookScript("OnTextChanged", refresh)

	professionDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	professionDropdown:SetWidth(170)
	professionDropdown:SetPoint("TOPRIGHT", -SIDE, -FILTERS_TOP)
	professionDropdown:SetupMenu(professionMenu)
	if ns.QUALITY_CRAFTING then createRetailDropdowns() end

	createFilters()
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
		if ns.AllRecipes.ItemArrived(itemID) then refresh() end
	end)
	-- Only the packed recipes stay when it closes. Hidden with the whole interface
	-- (Alt+Z, a cinematic), it's still open and keeps them.
	frame:SetScript("OnHide", function()
		if frame:IsShown() then return end
		filtersBox:Hide()
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
