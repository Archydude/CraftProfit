-- Craft Profit: the Best crafts list. A "Best crafts" button at the top of the
-- panel opens a list over the crafting page's recipe details: every recipe of the
-- profession shown, most profitable first. Draws the rows BestCrafts.lua works out.
local _, ns = ...

local BestCraftsList = {}
ns.BestCraftsList = BestCraftsList

local Color, Money, Item = ns.Color, ns.Format.Money, ns.Format.Item
local format = string.format

local ROW_HEIGHT = 24
local ICON_SIZE = 20
local CART_SIZE = 18
local PAD = 12             -- list edge to its content
local CELL_GAP = 10        -- between columns
local HEADER_HEIGHT = 20
local TOP_HEIGHT = 34      -- title, search and filter
local FOOTER_HEIGHT = 24
local TAG_GAP = 4          -- item name to its rank and other icons
local TOGGLE_HEIGHT = 20   -- the Best crafts button on the panel
local TOGGLE_RIGHT = 28    -- panel's right edge to the button (room for its gear)
local TOGGLE_TOP = 5       -- panel's top edge to the button
local TOGGLE_GAP = 6       -- the button to the panel's title
local OPEN_TRIES, OPEN_RETRY = 20, 0.1 -- from an order: waiting for the recipes to show
local FILTER_WIDTH = 90
local STRATEGY_WIDTH = 130 -- the crafting strategy dropdown at the bottom
local STRATEGY_LABEL = "Strategy:"
local REFRESH_DELAY = 0.2  -- redraws are batched this long
local LIST_LEVEL = 700     -- at least this frame level (Auctionator's crafting info sits at 520)
local STALE_DAYS = 3       -- Auctionator counts this old or older show in grey
local STALE_SCAN_DAYS = 7  -- other characters' saved scans this old or older show in the warning color
-- Columns right of the item name, right to left: key, width, header, sort key,
-- needsTSM: true shows it only with TSM, false only without, and allCharacters:
-- the same for the All characters view, and goldWidth: its width when amounts
-- show in whole gold. The demand column is TSM's Sells/day, or without TSM, You sold.
local COLUMNS = {
	{ key = "ignore", width = CART_SIZE },
	{ key = "cart", width = CART_SIZE },
	{ key = "sold", width = 64, header = "You sold", sort = "sold", needsTSM = false },
	{ key = "perDay", width = 64, header = "Sells/day", sort = "perDay", needsTSM = true },
	{ key = "listed", width = 46, header = "Listed", sort = "listed" },
	{ key = "gold", width = 64, header = "Gold/day", sort = "gold" },
	{ key = "profit", width = 112, goldWidth = 70, header = "Profit", sort = "profit" },
	{ key = "crafter", width = 64, header = "Crafter", sort = "crafter", allCharacters = true },
}
local HEADER_TIPS = {
	name = "Click to sort by name.",
	crafter = "Which of your characters makes it. A character shows up here after opening Best crafts once.",
	profit = "What one craft makes after the 5% auction house cut, at the highest rank you can make, with the "
		.. "cheapest materials that reach it. What you own counts at what it would sell for when picking them. A "
		.. "rank is never priced above a better one.\n\nWith Count multicraft and resourcefulness on (Filter menu), "
		.. "it's Expected: what a craft makes on average with procs.",
	gold = "Roughly what this recipe could make in a day: the profit on each item times how many sell per day. For "
		.. "comparing recipes, not a promise: with TSM it counts sales across your whole region, and you'd only get a "
		.. "share of them. Without TSM, it counts your own recent sales. Recipes that lose gold or haven't sold show -.",
	listed ="How many were up for sale the last time Auctionator saw them. Needs Auctionator.",
	perDay = "How many sell per day across your region, on average, from TSM.",
	sold = format("How many your characters sold on the auction house in the last %d days, from the auction "
		.. "house's mail. Counts sales from when you first opened your mailbox with this version.", ns.Sales.DAYS),
}
-- What the Profit column shows: with procs counted, the expected profit.
local function shownProfit(row)
	if ns.db.countProcs then return row.expected end
	return row.profit
end

-- How many of the item sell per day: across your region with TSM, or your own
-- average without it. Nil when neither says.
local function demandOf(row)
	if row.soldPerDay then return row.soldPerDay end
	if row.itemName and not ns.Prices.HasTSM() then
		return row.sold / math.max(ns.Sales.DaysCounted(), 1)
	end
end

-- What the recipe could make in a day, for the Gold/day column. Nil (which sorts
-- last) when there's no profit or no sales number to go on.
local function goldPerDay(row)
	local profit, demand = shownProfit(row), demandOf(row)
	if not (profit and demand) then return end
	local schematic = row.entry.schematic
	local perItem = profit / (((schematic.quantityMin or 1) + (schematic.quantityMax or 1)) / 2)
	if perItem <= 0 or demand <= 0 then return end
	return perItem * demand
end

-- The row's character, by key ("Name-Realm"): a saved one, or this one.
local function crafterKey(row)
	local _, myKey = ns.Ranks.Me()
	return row.entry.character or myKey or ""
end

-- How each sort key reads a row's value; nil values always go last.
local SORT_VALUES = {
	profit = shownProfit,
	gold = goldPerDay,
	crafter = crafterKey,
	listed = function(row) return row.listed end,
	sold = function(row) return row.itemName and row.sold or nil end,
	perDay = function(row) return row.soldPerDay end,
}
local CART_ICON = { atlases = { "Perks-ShoppingCart", "Banker" }, file = "Interface\\Icons\\INV_Misc_Bag_10" }
-- The ignore button's picture: an eye to hide the recipe, or undo on an ignored one.
local IGNORE_ICON = { atlases = { "transmog-icon-hidden" }, file = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" }
local UNIGNORE_ICON = { atlases = { "common-icon-undo" }, file = "Interface\\Buttons\\UI-RefreshButton" }
local FIRST_CRAFT_ATLAS = "professions_icon_firsttimecraft"
local COOLDOWN_ICON = "|TInterface\\Icons\\INV_Misc_PocketWatch_01:14|t"
-- The sorted column's arrow: the auction house's, or the older one.
local SORT_ARROW_ATLAS = "auctionhouse-ui-sortarrow"
local SORT_ARROW_FILE = "Interface\\Buttons\\UI-SortArrow"
local SORT_ARROW_SIZE = 10

local list, toggle, scrollBox, status, title, strategyDropdown, charactersButton
local headers = {}
local refreshQueued = false

local function signedMoney(amount)
	return Color(ns.AmountColor(amount), (amount > 0 and "+" or "") .. Money(amount))
end

-- "+1,250g" in whole gold, to fit the Gold/day column; under 1g, the usual amount.
local function dailyText(amount)
	local gold = math.floor(math.abs(amount) / 10000 + 0.5)
	if gold < 1 then return signedMoney(amount) end
	return Color(ns.AmountColor(amount), (amount > 0 and "+" or "-") .. BreakUpLargeNumbers(gold) .. GOLD_AMOUNT_SYMBOL)
end

local function firstCraftMarkup()
	if C_Texture.GetAtlasInfo(FIRST_CRAFT_ATLAS) then return CreateAtlasMarkup(FIRST_CRAFT_ATLAS, 16, 16) end
	return Color("good", "new")
end

-- "0.4" below 10 a day, "25" or "1,250" from there.
local function perDayText(perDay)
	if perDay < 10 then return format("%.1f", perDay) end
	return BreakUpLargeNumbers(math.floor(perDay + 0.5))
end

-- "3 h", "25 min".
local function timeText(seconds)
	if seconds >= 3600 then return format("%d h", math.ceil(seconds / 3600)) end
	return format("%d min", math.ceil(seconds / 60))
end

---------------------------------------------------------------------------
-- Which rows, in which order
---------------------------------------------------------------------------

-- The search finds item names, and in All characters, characters too.
local function matches(row, search)
	if search == "" or row.sortName:find(search, 1, true) then return true end
	return ns.db.bestAllCharacters and crafterKey(row):lower():find(search, 1, true) ~= nil
end

-- Whether a column shows, with these addons and in this view.
local function columnShown(column)
	if column.needsTSM ~= nil and column.needsTSM ~= ns.Prices.HasTSM() then return false end
	return column.allCharacters == nil or column.allCharacters == ns.db.bestAllCharacters
end

-- The column the list sorts by. A sort by the demand column that's hidden
-- (You sold with TSM, Sells/day without) goes by the one that shows. A saved sort
-- by a column that's gone, or hidden in this view, goes by profit.
local function sortKey()
	local key = ns.db.bestSort
	if key == "sold" or key == "perDay" then return ns.Prices.HasTSM() and "perDay" or "sold" end
	if key ~= "name" and not SORT_VALUES[key] then return "profit" end
	for _, column in ipairs(COLUMNS) do
		if column.sort == key and not columnShown(column) then return "profit" end
	end
	return key
end

-- Sorted by the chosen column; rows without a value for it go last either way.
-- Ties go by profit, then name.
local function sortRows(rows)
	local key, ascending = sortKey(), ns.db.bestSortAscending
	local valueOf = SORT_VALUES[key]
	local function nameOf(row) return row.sortName end
	table.sort(rows, function(a, b)
		if key == "name" then
			local an, bn = nameOf(a), nameOf(b)
			if an ~= bn then
				if ascending then return an < bn end
				return an > bn
			end
		else
			local av, bv = valueOf(a), valueOf(b)
			if (av == nil) ~= (bv == nil) then return av ~= nil end
			if av ~= bv and av ~= nil then
				if ascending then return av < bv end
				return av > bv
			end
		end
		local ap, bp = shownProfit(a), shownProfit(b)
		if (ap == nil) ~= (bp == nil) then return ap ~= nil end
		if ap ~= bp and ap then return ap > bp end
		return nameOf(a) < nameOf(b)
	end)
end

local allRows = {} -- every row before filtering, for the filter menu's counts

local function visibleRows()
	local search = list.Search:GetText():lower()
	local shown = {}
	allRows = ns.BestCrafts.Rows()
	for _, row in ipairs(allRows) do
		if matches(row, search) and not ns.db.bestHidden[row.group]
			and not (ns.db.bestIgnored[row.entry.recipeID] and not ns.db.bestShowIgnored)
			and not (ns.db.bestProfitableOnly and not ((shownProfit(row) or 0) > 0)) then
			shown[#shown + 1] = row
		end
	end
	sortRows(shown)
	return shown
end

---------------------------------------------------------------------------
-- The row tooltip
---------------------------------------------------------------------------

local function addLine(tip, text) tip:AddLine(text, 1, 1, 1, true) end
local function addPair(tip, left, right) tip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1) end

local function rankIcon(row, rank)
	return ns.Blizzard.ItemQualityMarkup(row.entry.recipeID, rank) or ("rank " .. rank)
end

local function listedText(count, age)
	if not count then return Color("muted", "-") end
	local text = BreakUpLargeNumbers(count)
	if age and age > 0 then
		local seen = Color("muted", ", " .. ns.Prices.AgeText(age))
		return (age >= STALE_DAYS and Color("muted", text) or text) .. seen
	end
	return text
end

-- "Skill data from 3 days ago", for the tooltip of a recipe from a saved scan.
local function scanAgeText(entry)
	local days = math.floor((time() - entry.scanned) / 86400)
	return Color(days >= STALE_SCAN_DAYS and "warning" or "muted", "Skill data from " .. ns.Prices.AgeText(days))
end

local function rowTooltip(tip, row)
	local entry = row.entry
	tip:SetText(entry.name or "?")
	if ns.db.bestAllCharacters then
		addPair(tip, "Crafter", ns.Ranks.CharacterName(crafterKey(row)))
		if entry.scanned then addLine(tip, scanAgeText(entry)) end
	end
	local schematic = entry.schematic
	local qtyMin, qtyMax = schematic.quantityMin or 1, schematic.quantityMax or 1
	if row.output then
		addLine(tip, format("Makes %s %s", qtyMin == qtyMax and (qtyMin .. "x") or (qtyMin .. "-" .. qtyMax .. "x"), row.output.link))
	end

	if row.profit then
		local sellText = ns.db.ahCut and format("Sells for (after %d%% AH cut)", ns.AH_CUT * 100) or "Sells for"
		addPair(tip, sellText, Money(row.sale))
		if row.cappedBy then
			tip:AddLine(ns.Model.CappedNote(entry.recipeID, row.cappedBy, row.listedPrice), 0.53, 0.53, 0.53, true)
		end
	elseif row.quality and entry.maxRank > 1 then
		addPair(tip, "Sells for", Color("warning", "no price at " .. rankIcon(row, row.quality)))
	else
		addPair(tip, "Sells for", Color("warning", "no auction price"))
	end

	tip:AddLine(" ")
	tip:AddLine("Materials", 1, 0.82, 0)
	for _, material in ipairs(ns.BestCrafts.Materials(row)) do
		addPair(tip, Item(material.itemID, material.qty),
			material.price and Money(material.price * material.qty) or Color("warning", "no price"))
	end
	addPair(tip, "Materials cost", Money(-row.cost))
	if row.profit then
		addPair(tip, row.profit >= 0 and "Profit" or "Loss", signedMoney(row.profit))
	end
	local procs = row.procs
	if row.expected and procs.total > 0 then
		addPair(tip, "Expected with procs", signedMoney(row.expected))
		if procs.chances.multicraft > 0 then
			tip:AddDoubleLine(format("  Multicraft %.0f%% x %.2f extra per item", procs.chances.multicraft * 100,
				procs.extraPerItem), signedMoney(procs.multicraft), 0.53, 0.53, 0.53, 0.53, 0.53, 0.53)
		end
		if procs.chances.resourcefulness > 0 then
			tip:AddDoubleLine(format("  Resourcefulness %.0f%% x %.0f%% saved", procs.chances.resourcefulness * 100,
				procs.savedShare * 100), signedMoney(procs.resourcefulness), 0.53, 0.53, 0.53, 0.53, 0.53, 0.53)
		end
	end
	if row.unpriced > 0 then
		tip:AddLine(format("%d material(s) have no price, so profit is too high", row.unpriced), 1, 0.4, 0.4, true)
	end

	if row.concentration then
		local c = row.concentration
		tip:AddLine(" ")
		addLine(tip, format("With concentration: %s %s for %d concentration (%s per point)", rankIcon(row, c.quality),
			signedMoney(c.extra), c.points, Money(c.extra / c.points)))
	end

	-- Each rank's price and how many are listed, so a rank nobody buys shows.
	if entry.maxRank > 1 then
		tip:AddLine(" ")
		tip:AddLine("Ranks", 1, 0.82, 0)
		for _, rank in ipairs(ns.BestCrafts.Ranks(row)) do
			local price = rank.sale and Money(rank.sale) or Color("muted", "no price")
			local listed = rank.listed and format("%s listed", BreakUpLargeNumbers(rank.listed)) or ""
			addPair(tip, rankIcon(row, rank.rank) .. "  " .. price, listed)
		end
	end

	tip:AddLine(" ")
	addPair(tip, "Listed", listedText(row.listed, row.listedAge))
	local counted = math.max(ns.Sales.DaysCounted(), 1)
	addPair(tip, format("You sold (last %d day%s)", counted, counted == 1 and "" or "s"),
		row.itemName and tostring(row.sold) or Color("muted", "-"))
	if ns.Prices.HasTSM() then
		addPair(tip, "Sells per day in your region (TSM)", row.soldPerDay and perDayText(row.soldPerDay) or Color("muted", "-"))
	end
	local daily = goldPerDay(row)
	if daily then addPair(tip, "Gold per day", signedMoney(daily)) end
	if row.firstCraft then addLine(tip, firstCraftMarkup() .. " First craft: gives profession knowledge") end
	if row.cooldown then addLine(tip, COOLDOWN_ICON .. " On cooldown: ready in " .. timeText(row.cooldown)) end

	tip:AddLine(" ")
	tip:AddLine(Color("simulated", ns.BestCrafts.IsMine(entry) and "Click: show the recipe"
		or "Log in to this character to craft it"))
	tip:AddLine(Color("simulated", ns.db.bestIgnored[entry.recipeID] and "Right-click: stop ignoring it"
		or "Right-click: ignore it (hide it from the list)"))
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

-- Where each column sits in a row `width` wide: key -> { x, width }. The item
-- name takes what the others leave.
local function columnLayout(width)
	local layout, right = {}, width - 4
	for _, column in ipairs(COLUMNS) do
		if columnShown(column) then
			local columnWidth = ns.db.precision == "gold" and column.goldWidth or column.width
			layout[column.key] = { x = right - columnWidth, width = columnWidth }
			right = right - columnWidth - CELL_GAP
		end
	end
	layout.name = { x = 4 + ICON_SIZE + 6, width = right - (4 + ICON_SIZE + 6) }
	return layout
end

-- Shows `icon` (CART_ICON...) on a button: the first atlas the game has, or else the file.
local function setIcon(button, icon)
	for _, atlas in ipairs(icon.atlases) do
		if C_Texture.GetAtlasInfo(atlas) then
			button:SetNormalAtlas(atlas)
			return
		end
	end
	button:SetNormalTexture(icon.file)
end

local function cartTooltip(self)
	local row = self.row
	local model = ns.BestCrafts.ShoppingModel(row)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if #model.missing > 0 then
		GameTooltip:SetText("Missing for 1 craft")
		for _, material in ipairs(model.missing) do GameTooltip:AddLine(Item(material.itemID, material.qty), 1, 1, 1) end
	else
		GameTooltip:SetText("Nothing missing for 1 craft")
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(Color("simulated", ns.Shopping.ListTarget() == "tsm" and "Click: copy a TSM search for 1 craft"
		or format("Click: add what's missing for 1 craft to the \"%s\" list", model.listName)))
	GameTooltip:AddLine(Color("simulated", "Shift-click: pick how many crafts"))
	GameTooltip:Show()
end

local function cellText(button, key, justify)
	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetJustifyH(justify or "RIGHT")
	text:SetWordWrap(false)
	button.cells[key] = text
	return text
end

-- Ignoring a recipe hides it from the list, for when its price makes no sense.
-- Kept for every character, by recipe.
local function setIgnored(row, ignored)
	ns.db.bestIgnored[row.entry.recipeID] = ignored or nil
	GameTooltip:Hide()
	BestCraftsList.Render()
end

local function createRow(button)
	button.cells = {}
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(ICON_SIZE, ICON_SIZE)
	button.icon:SetPoint("LEFT", 4, 0)
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cellText(button, "name", "LEFT")
	-- The rank and other icons, right after the name, so a long name that's cut
	-- short never hides them.
	button.tags = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.tags:SetWordWrap(false)
	for _, column in ipairs(COLUMNS) do
		if column.header then cellText(button, column.key) end
	end

	local cart = CreateFrame("Button", nil, button)
	cart:SetSize(CART_SIZE, CART_SIZE)
	setIcon(cart, CART_ICON)
	cart:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	cart:RegisterForClicks("LeftButtonUp")
	cart:SetScript("OnClick", function(self)
		ns.Shopping.Click(ns.BestCrafts.ShoppingModel(self.row), self, IsShiftKeyDown(), IsControlKeyDown())
	end)
	cart:SetScript("OnEnter", cartTooltip)
	cart:SetScript("OnLeave", GameTooltip_Hide)
	button.cart = cart

	local ignore = CreateFrame("Button", nil, button)
	ignore:SetSize(CART_SIZE, CART_SIZE)
	ignore:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	ignore:RegisterForClicks("LeftButtonUp")
	ignore:SetScript("OnClick", function(self)
		setIgnored(self.row, not ns.db.bestIgnored[self.row.entry.recipeID])
	end)
	ignore:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if ns.db.bestIgnored[self.row.entry.recipeID] then
			GameTooltip:SetText("Stop ignoring")
			GameTooltip:AddLine("Puts this recipe back on the list.", 1, 1, 1, true)
		else
			GameTooltip:SetText("Ignore")
			GameTooltip:AddLine("Hides this recipe from the list, for when its price makes no sense. "
				.. "Show ignored recipes in the Filter menu brings it back.", 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	ignore:SetScript("OnLeave", GameTooltip_Hide)
	button.ignore = ignore

	button:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			setIgnored(self.row, not ns.db.bestIgnored[self.row.entry.recipeID])
			return
		end
		if not ns.BestCrafts.IsMine(self.row.entry) then
			ns.Shopping.Say(format("Log in to %s to craft this.", ns.Ranks.CharacterName(crafterKey(self.row))))
			return
		end
		BestCraftsList.Hide()
		ns.Blizzard.ShowRecipe(self.row.entry.recipeID)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		rowTooltip(GameTooltip, self.row)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
end

local function drawRow(button, row)
	if not button.cells then createRow(button) end
	button.row = row
	button.cart.row = row
	button.ignore.row = row
	local layout = columnLayout(scrollBox:GetWidth())
	for key, text in pairs(button.cells) do
		local place = layout[key]
		text:SetShown(place ~= nil)
		if place then
			text:ClearAllPoints()
			text:SetPoint("LEFT", button, "LEFT", place.x, 0)
			text:SetWidth(place.width)
		end
	end
	button.cart:ClearAllPoints()
	button.cart:SetPoint("LEFT", button, "LEFT", layout.cart.x, 0)
	button.ignore:ClearAllPoints()
	button.ignore:SetPoint("LEFT", button, "LEFT", layout.ignore.x, 0)
	setIcon(button.ignore, ns.db.bestIgnored[row.entry.recipeID] and UNIGNORE_ICON or IGNORE_ICON)

	local entry = row.entry
	button.icon:SetTexture(row.output and C_Item.GetItemIconByID(row.output.itemID) or entry.icon)
	local name = row.itemName or entry.name or "?"
	local tags = {}
	if row.quality and entry.maxRank > 1 then tags[#tags + 1] = rankIcon(row, row.quality) end
	if row.firstCraft then tags[#tags + 1] = firstCraftMarkup() end
	if row.cooldown then tags[#tags + 1] = COOLDOWN_ICON end
	local ignored = ns.db.bestIgnored[entry.recipeID]
	if ignored then tags[#tags + 1] = Color("muted", "ignored") end
	local tagText = table.concat(tags, " ")
	button.tags:SetText(tagText)
	local nameCell = button.cells.name
	-- In its rarity's color; grey when ignored or without a price.
	nameCell:SetText((row.profit and not ignored) and ns.Format.RarityColored(row.output and row.output.itemID, name)
		or Color("muted", name))
	-- The name takes what the icons leave, and is cut short with "..." past that.
	local tagWidth = tagText ~= "" and (button.tags:GetUnboundedStringWidth() + TAG_GAP) or 0
	nameCell:SetWidth(math.max(1, math.min(nameCell:GetUnboundedStringWidth() + 2, layout.name.width - tagWidth)))
	button.tags:ClearAllPoints()
	button.tags:SetPoint("LEFT", nameCell, "RIGHT", TAG_GAP, 0)

	local profit = shownProfit(row)
	if profit then
		button.cells.profit:SetText(signedMoney(profit))
	else
		button.cells.profit:SetText(Color("muted", "No price"))
	end
	local daily = goldPerDay(row)
	button.cells.gold:SetText(daily and dailyText(daily) or Color("muted", "-"))
	button.cells.crafter:SetText(ns.Ranks.CharacterName(crafterKey(row)))
	local listed = row.listed and BreakUpLargeNumbers(row.listed) or "-"
	button.cells.listed:SetText((row.listed and (row.listedAge or 0) < STALE_DAYS) and listed or Color("muted", listed))
	button.cells.perDay:SetText(row.soldPerDay and perDayText(row.soldPerDay) or Color("muted", "-"))
	button.cells.sold:SetText(not row.itemName and Color("muted", "-")
		or row.sold > 0 and tostring(row.sold) or Color("muted", "0"))
	button.cart:SetShown(ns.db.shoppingButton and ns.Shopping.ListTarget() ~= nil)
end

---------------------------------------------------------------------------
-- Headers, footer and drawing
---------------------------------------------------------------------------

-- One column header at `place` ({ x, width }), gold with an arrow while it sorts:
-- down for most first, up for least first, beside the label.
local function drawHeader(key, header, place)
	header:ClearAllPoints()
	header:SetPoint("BOTTOMLEFT", scrollBox, "TOPLEFT", place.x, 2)
	header:SetSize(place.width, HEADER_HEIGHT)
	local sorted = sortKey() == key
	local label = key == "profit" and ns.db.countProcs and "Expected" or header.label
	header.text:SetText(sorted and Color("heading", label) or label)
	local arrow = header.arrow
	arrow:SetShown(sorted)
	if not sorted then return end
	if ns.db.bestSortAscending then arrow:SetTexCoord(0, 1, 1, 0) else arrow:SetTexCoord(0, 1, 0, 1) end
	arrow:ClearAllPoints()
	local textWidth = header.text:GetStringWidth()
	if key == "name" then
		arrow:SetPoint("LEFT", header, "LEFT", textWidth + 3, 0)
	else
		arrow:SetPoint("RIGHT", header, "RIGHT", -textWidth - 3, 0)
	end
end

local function updateHeaders()
	local layout = columnLayout(scrollBox:GetWidth())
	for key, header in pairs(headers) do
		local place = layout[key]
		header:SetShown(place ~= nil)
		if place then drawHeader(key, header, place) end
	end
end

local function statusText(count, total)
	local done, scanTotal = ns.BestCrafts.Progress()
	if done then return format("Pricing %d of %d recipes...", done, scanTotal) end
	local scan = ns.BestCrafts.Current()
	if not scan then return "" end
	local text = count == total and format("%d recipes", total) or format("%d of %d recipes", count, total)
	return Color("muted", text .. " · Prices: " .. ns.Prices.SourceLabel()) .. ns.Reminder.FooterText()
end

function BestCraftsList.Render()
	refreshQueued = false
	if not (list and list:IsShown()) then return end
	local scan = ns.BestCrafts.Current()
	local shown = ns.db.bestAllCharacters and "All characters" or (scan and scan.name)
	title:SetText("Best crafts" .. (shown and ("  " .. Color("muted", shown)) or ""))
	if ns.db.bestAllCharacters then charactersButton:LockHighlight() else charactersButton:UnlockHighlight() end
	local rows = visibleRows()
	scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
	status:SetText(statusText(#rows, #allRows))
	-- The strategy can change in the options too.
	strategyDropdown:GenerateMenu()
	updateHeaders()
end

-- Redraws once shortly, however many times it's called.
function BestCraftsList.Refresh()
	if refreshQueued or not (list and list:IsShown()) then return end
	refreshQueued = true
	C_Timer.After(REFRESH_DELAY, BestCraftsList.Render)
end

local function setSort(key)
	if sortKey() == key then
		ns.db.bestSortAscending = not ns.db.bestSortAscending
	else
		ns.db.bestSort, ns.db.bestSortAscending = key, key == "name" or key == "crafter"
	end
	BestCraftsList.Render()
end

local function createHeader(key, label)
	local header = CreateFrame("Button", nil, list)
	header.text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight") -- white; the sorted one turns gold
	header.text:SetAllPoints()
	header.text:SetJustifyH(key == "name" and "LEFT" or "RIGHT")
	header.label = label
	header.arrow = header:CreateTexture(nil, "OVERLAY")
	header.arrow:SetSize(SORT_ARROW_SIZE, SORT_ARROW_SIZE)
	if C_Texture.GetAtlasInfo(SORT_ARROW_ATLAS) then
		header.arrow:SetAtlas(SORT_ARROW_ATLAS)
	else
		header.arrow:SetTexture(SORT_ARROW_FILE)
	end
	header:SetScript("OnClick", function() setSort(key) end)
	header:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(label)
		GameTooltip:AddLine(HEADER_TIPS[key], 1, 1, 1, true)
		if key ~= "name" then GameTooltip:AddLine(Color("simulated", "Click to sort; click again to reverse.")) end
		GameTooltip:Show()
	end)
	header:SetScript("OnLeave", GameTooltip_Hide)
	headers[key] = header
end

---------------------------------------------------------------------------
-- The filter menu
---------------------------------------------------------------------------

local function filtersAreDefault()
	return not ns.db.bestProfitableOnly and not ns.db.bestShowIgnored and next(ns.db.bestHidden) == nil
end

-- Back to the default filters. Ignored recipes stay ignored.
local function resetFilters()
	ns.db.bestProfitableOnly, ns.db.bestShowIgnored = false, false
	wipe(ns.db.bestHidden)
	BestCraftsList.Render()
end

-- How many of the profession's recipes are ignored.
local function ignoredCount()
	local count = 0
	for _, row in ipairs(allRows) do
		if ns.db.bestIgnored[row.entry.recipeID] then count = count + 1 end
	end
	return count
end

local function setAllGroups(hidden)
	for _, group in ipairs(ns.BestCrafts.GROUPS) do ns.db.bestHidden[group.key] = hidden or nil end
	BestCraftsList.Render()
	return MenuResponse.Refresh
end

-- Profitable only, then a checkbox for each kind of item the list has, with how many.
local function filterMenu(_, root)
	root:CreateCheckbox("Profitable only", function() return ns.db.bestProfitableOnly end, function()
		ns.db.bestProfitableOnly = not ns.db.bestProfitableOnly
		BestCraftsList.Render()
	end)
	local procs = root:CreateCheckbox("Count multicraft and resourcefulness", function() return ns.db.countProcs end,
		function() ns.Options.Set("countProcs", not ns.db.countProcs) end)
	procs:SetTooltip(function(tip)
		GameTooltip_SetTitle(tip, "Count multicraft and resourcefulness")
		GameTooltip_AddNormalLine(tip, "Profit becomes Expected: what a craft makes on average with procs, and the "
			.. "list ranks by it. Your chances come from the game; how big a proc is, from your own crafts.")
	end)
	root:CreateDivider()
	root:CreateTitle("Show")
	local counts = {}
	for _, row in ipairs(allRows) do counts[row.group] = (counts[row.group] or 0) + 1 end
	for _, group in ipairs(ns.BestCrafts.GROUPS) do
		local key = group.key
		-- Kinds the profession doesn't make aren't listed, unless they're hidden.
		if counts[key] or ns.db.bestHidden[key] then
			root:CreateCheckbox(format("%s %s", group.label, Color("muted", "(" .. (counts[key] or 0) .. ")")),
				function() return not ns.db.bestHidden[key] end,
				function()
					ns.db.bestHidden[key] = not ns.db.bestHidden[key] or nil
					BestCraftsList.Render()
				end)
		end
	end
	root:CreateDivider()
	root:CreateButton("Show all", function() return setAllGroups(false) end)
	root:CreateButton("Hide all", function() return setAllGroups(true) end)

	-- Recipes you ignored with a right-click.
	local ignored = ignoredCount()
	root:CreateDivider()
	local show = root:CreateCheckbox(format("Show ignored recipes %s", Color("muted", "(" .. ignored .. ")")),
		function() return ns.db.bestShowIgnored end,
		function()
			ns.db.bestShowIgnored = not ns.db.bestShowIgnored
			BestCraftsList.Render()
		end)
	show:SetTooltip(function(tip)
		GameTooltip_SetTitle(tip, "Show ignored recipes")
		GameTooltip_AddNormalLine(tip, "Right-click a recipe in the list to ignore it, for when its price makes no sense. "
			.. "Ignored recipes show here in grey, marked ignored; right-click one again to stop ignoring it.")
	end)
	if ignored > 0 then
		root:CreateButton("Stop ignoring all", function()
			for _, row in ipairs(allRows) do ns.db.bestIgnored[row.entry.recipeID] = nil end
			BestCraftsList.Render()
			return MenuResponse.Refresh
		end)
	end
end

---------------------------------------------------------------------------
-- The crafting strategy dropdown
---------------------------------------------------------------------------

local function createStrategyDropdown()
	strategyDropdown = CreateFrame("DropdownButton", nil, list, "WowStyle1DropdownTemplate")
	strategyDropdown:SetWidth(STRATEGY_WIDTH)
	strategyDropdown:SetPoint("BOTTOMRIGHT", -PAD, PAD - 4)
	if strategyDropdown.SetSelectionTranslator then strategyDropdown:SetSelectionTranslator(ns.StrategyText) end
	strategyDropdown:SetupMenu(ns.StrategyMenu)
	local label = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("RIGHT", strategyDropdown, "LEFT", -6, 0)
	label:SetText(STRATEGY_LABEL)
	return STRATEGY_WIDTH + 6 + label:GetUnboundedStringWidth()
end

---------------------------------------------------------------------------
-- The All characters button
---------------------------------------------------------------------------

-- Between the status line and the strategy dropdown; lit while it's on.
local function createCharactersButton(strategyWidth)
	charactersButton = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
	charactersButton:SetText("All characters")
	charactersButton:SetSize(charactersButton:GetFontString():GetUnboundedStringWidth() + 24, 22)
	charactersButton:SetPoint("BOTTOMRIGHT", -(PAD + strategyWidth + 12), PAD - 3)
	charactersButton:SetScript("OnClick", function()
		ns.db.bestAllCharacters = not ns.db.bestAllCharacters
		BestCraftsList.Render()
	end)
	charactersButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("All characters")
		GameTooltip:AddLine("Every profession of every character you've opened Best crafts on, in one list, at "
			.. "today's prices. Ranks and proc chances are from when that character last opened it.", 1, 1, 1, true)
		GameTooltip:AddLine(Color("simulated", ns.db.bestAllCharacters and "Click: back to this profession"
			or "Click: show them all"))
		GameTooltip:Show()
	end)
	charactersButton:SetScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------------
-- The notice over the list (old prices), drawn like Blizzard's Crafting Details box
---------------------------------------------------------------------------

local NOTICE_WIDTH, NOTICE_HEIGHT = 263, 200 -- the Crafting Details box's width, and room for the text
local NOTICE_SHADE_ALPHA = 0.7 -- how dark the list gets behind the notice
local NOTICE_SHADE_INSET = 4   -- inside the list's border
local NOTICE_ART = { -- its background, top to bottom
	top = "Professions-QualityPane-bg-top",
	middle = "Professions-QualityPane-bg-middle",
	bottom = "Professions-QualityPane-bg-bottom",
	divider = "Professions-QualityPane-Divider",
}
local notice

local function noticeTexture(atlas)
	local texture = notice:CreateTexture(nil, "BACKGROUND")
	if C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas)
	else
		texture:SetColorTexture(0.05, 0.05, 0.05, 0.95)
	end
	return texture
end

local function createNotice()
	-- The list darkens behind the notice, and takes no clicks until it's closed.
	local shade = CreateFrame("Frame", nil, list)
	shade:SetPoint("TOPLEFT", NOTICE_SHADE_INSET, -NOTICE_SHADE_INSET)
	shade:SetPoint("BOTTOMRIGHT", -NOTICE_SHADE_INSET, NOTICE_SHADE_INSET)
	shade:SetFrameLevel(scrollBox:GetFrameLevel() + 20)
	shade:EnableMouse(true)
	shade:Hide()
	local dark = shade:CreateTexture(nil, "BACKGROUND")
	dark:SetAllPoints()
	dark:SetColorTexture(0, 0, 0, NOTICE_SHADE_ALPHA)

	notice = CreateFrame("Frame", nil, shade)
	notice:SetSize(NOTICE_WIDTH, NOTICE_HEIGHT)
	notice:SetPoint("CENTER", scrollBox, "CENTER")
	notice:SetFrameLevel(shade:GetFrameLevel() + 5)
	notice.shade = shade

	local top = noticeTexture(NOTICE_ART.top)
	top:SetSize(NOTICE_WIDTH, 100)
	top:SetPoint("TOP")
	local bottom = noticeTexture(NOTICE_ART.bottom)
	bottom:SetSize(NOTICE_WIDTH, 100)
	bottom:SetPoint("BOTTOM", 0, -1)
	local middle = noticeTexture(NOTICE_ART.middle)
	middle:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
	middle:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")

	local title = notice:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -25)
	title:SetText("Old prices")
	local divider = notice:CreateTexture(nil, "ARTWORK")
	divider:SetAtlas(NOTICE_ART.divider, true)
	divider:SetPoint("TOP", title, "BOTTOM", 0, -4)

	notice.text = notice:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	notice.text:SetPoint("TOP", divider, "BOTTOM", 0, -10)
	notice.text:SetWidth(NOTICE_WIDTH - 40)
	notice.text:SetJustifyH("CENTER")

	local okay = CreateFrame("Button", nil, notice, "UIPanelButtonTemplate")
	okay:SetText(OKAY)
	okay:SetSize(100, 22)
	okay:SetPoint("BOTTOM", 0, 22)
	okay:SetScript("OnClick", function() shade:Hide() end)
end

local function showNotice(text)
	notice.text:SetText(text)
	notice.shade:Show()
end

-- Testing (/craftprofit testnotice): shows the old prices notice on the open
-- list, whatever the scan's age. False when the list isn't open.
function BestCraftsList.TestNotice()
	if not (list and list:IsVisible()) then return false end
	showNotice("Auctionator's prices are from 4 days ago.\n\nThe profits in Best crafts may be far off. Run a full "
		.. "scan with Auctionator the next time you're at the auction house.")
	return true
end

local function createList()
	list = CreateFrame("Frame", "CraftProfitBestCrafts", ProfessionsFrame.CraftingPage, "BackdropTemplate")
	list:SetAllPoints(ns.Blizzard.RecipeDetails())
	-- Over everything on the recipe details, other addons' frames there included.
	list:SetFrameLevel(math.max(ns.Blizzard.RecipeDetails():GetFrameLevel() + 40, LIST_LEVEL))
	list:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	list:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
	list:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	list:EnableMouse(true)
	list:Hide()

	title = list:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetJustifyH("LEFT")

	local search = CreateFrame("EditBox", nil, list, "SearchBoxTemplate")
	search:SetSize(160, 20)
	search:SetPoint("TOPRIGHT", -PAD - 2, -PAD + 2)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", BestCraftsList.Refresh)
	list.Search = search

	local filter = CreateFrame("DropdownButton", nil, list, "WowStyle1FilterDropdownTemplate")
	filter:SetSize(FILTER_WIDTH, 22)
	filter:SetPoint("RIGHT", search, "LEFT", -10, 0)
	filter:SetText(FILTER)
	filter:SetupMenu(filterMenu)
	filter:SetIsDefaultCallback(filtersAreDefault)
	filter:SetDefaultCallback(resetFilters)
	title:SetPoint("RIGHT", filter, "LEFT", -8, 0)

	scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", PAD, -(PAD + TOP_HEIGHT + HEADER_HEIGHT))
	scrollBox:SetPoint("BOTTOMRIGHT", -(PAD + 14), PAD + FOOTER_HEIGHT)
	local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", drawRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	scrollBox:HookScript("OnSizeChanged", BestCraftsList.Refresh)

	createNotice()
	createHeader("name", "Item")
	for _, column in ipairs(COLUMNS) do
		if column.header then createHeader(column.sort, column.header) end
	end

	local strategyWidth = createStrategyDropdown()
	createCharactersButton(strategyWidth)
	status = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	status:SetPoint("BOTTOMLEFT", PAD, PAD)
	status:SetPoint("BOTTOMRIGHT", charactersButton, "BOTTOMLEFT", -8, 3)
	status:SetJustifyH("LEFT")
	status:SetWordWrap(false)

	-- Item names arrive from the server after first use; what you own changes what a craft costs you.
	list:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	list:RegisterEvent("BAG_UPDATE_DELAYED")
	list:SetScript("OnEvent", function(_, event)
		if event == "BAG_UPDATE_DELAYED" then ns.BestCrafts.Reprice() end
		BestCraftsList.Refresh()
	end)
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

-- Whether the list can open now: this character's profession, on the crafting
-- page's full view.
local function canShow()
	return ns.Blizzard.IsOwnProfession() and ns.Blizzard.ShowsRecipeList()
end

-- Shows the panel's button on the crafting page and on your crafting orders, lit
-- while the list is open.
function BestCraftsList.UpdateToggle()
	if not toggle then return end
	local page = ns.Blizzard.ActivePage()
	toggle:SetShown((page == "craft" and canShow()) or (page == "order" and ns.Blizzard.IsOwnProfession()))
	if list:IsShown() then toggle:LockHighlight() else toggle:UnlockHighlight() end
end

-- The room the panel's first row leaves for the button.
function BestCraftsList.HeaderSpace()
	return toggle and toggle:IsShown() and (toggle:GetWidth() + TOGGLE_GAP) or 0
end

function BestCraftsList.Show()
	if not (list and canShow()) then return false end
	list:Show()
	BestCraftsList.UpdateToggle()
	ns.BestCrafts.Scan()
	BestCraftsList.Render()
	local text = ns.Reminder.BestCraftsNotice()
	if text then showNotice(text) end
	return true
end

function BestCraftsList.IsShown()
	return list ~= nil and list:IsVisible()
end

function BestCraftsList.Hide()
	if not list then return end
	list:Hide()
	GameTooltip:Hide()
	BestCraftsList.UpdateToggle()
end

function BestCraftsList.Toggle()
	if list and list:IsShown() then
		BestCraftsList.Hide()
		return
	end
	if BestCraftsList.Show() or not ns.Blizzard.IsOwnProfession() then return end
	-- From a crafting order: back to the recipes, and the list once they show.
	ns.Blizzard.ShowRecipesTab()
	local tries = 0
	local function try()
		tries = tries + 1
		if BestCraftsList.Show() or tries >= OPEN_TRIES then return end
		C_Timer.After(OPEN_RETRY, try)
	end
	C_Timer.After(0, try)
end

-- The crafting page switched view, showed or hid: the list only fits the full view.
local function onLayout()
	if list:IsShown() and not canShow() then list:Hide() end
	-- The panel shows the button, and leaves room for it.
	ns.Panel.Refresh()
end

-- The button at the top of the panel, left of its gear.
local function createToggle()
	local panel = ns.Panel.Frame()
	toggle = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	toggle:SetText("Best crafts")
	toggle:SetSize(toggle:GetFontString():GetUnboundedStringWidth() + 24, TOGGLE_HEIGHT)
	toggle:SetPoint("TOPRIGHT", -TOGGLE_RIGHT, -TOGGLE_TOP)
	toggle:SetFrameLevel(panel:GetFrameLevel() + 5)
	toggle:Hide()
	toggle:SetScript("OnClick", BestCraftsList.Toggle)
	toggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Best crafts")
		GameTooltip:AddLine("Every recipe you know in this profession, most profitable first.", 1, 1, 1, true)
		GameTooltip:AddLine(Color("simulated", list:IsShown() and "Click: back to the recipe" or "Click: open the list"))
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", GameTooltip_Hide)
end

-- Creates the button and the list. Safe to call more than once; needs the panel.
function BestCraftsList.Init()
	if list or not (ns.Blizzard.IsLoaded() and ns.Panel.Frame()) then return end
	createList()
	createToggle()
	ns.BestCrafts.Watch(BestCraftsList.Refresh, function() return list:IsShown() end)
	ns.Blizzard.WatchCraftingPage(BestCraftsList.Hide, onLayout)
	ns.Panel.Refresh()
end
