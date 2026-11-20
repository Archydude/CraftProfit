-- Craftonomics: the Ledger window. What your crafting made: three totals, where
-- the gold you put into materials went, three things that stand out, and one row
-- for each item, which opens on its crafts. A second tab has what you bought. From
-- the records in Ledger.lua: they're unpacked when it opens and let go when it closes.
local _, ns = ...

local LedgerWindow = {}
ns.LedgerWindow = LedgerWindow

local Color, Money = ns.Color, ns.Format.Money
local format = string.format

local WIDTH, HEIGHT = 1240, 660
local SIDE = 12             -- window edge to its content
local FILTERS_TOP = 30      -- window top to the filters
local TILES_TOP = 62        -- window top to the totals
local TILE_WIDTH, TILE_HEIGHT = 200, 64
local TILE_GAP = 6
local CARDS_TOP = TILES_TOP + TILE_HEIGHT + TILE_GAP -- window top to the three things that stand out
local CARD_HEIGHT = 46
local INSET_TOP = CARDS_TOP + CARD_HEIGHT + 8        -- window top to the list's box on Crafting,
local INSET_TOP_BOUGHT = TILES_TOP + TILE_HEIGHT + 8 -- and on Purchases, which has no such things
local INSET_PAD = 8         -- that box's edge to what's in it
local SCROLLBAR_ROOM = 20
local HEADER_HEIGHT = 22
local ROW_HEIGHT = 24
local ICON_SIZE = 20
local TOGGLE_SIZE = 14      -- the plus or minus in front of an item that opens
local CELL_GAP = 8
local TAB_PADDING = 16      -- room beside a tab's label, so it's never cut short
local TAB_KEYS = { "items", "bought" }
local TAB_LABELS = { "Crafting", "Purchases" }
local TILE_LABELS = {
	items = { "Profit so far", "Waiting to sell", "If it all sells" },
	bought = { "Spent", "Against your price", "Resale profit" },
}
local FLOW_BAR_HEIGHT = 12  -- the bar of where the materials' gold went
local UNDER_FORECAST = 0.10 -- from this far under its forecast, an item's row says so
local SLOW_DAYS = 3         -- an item with nothing sold after this many days isn't selling
local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- The parts of that bar, left to right: what flowOf calls it, its name, its color
-- and what its tooltip says.
local FLOW_PARTS = {
	{ key = "sold", name = "Sold", color = { 0.30, 0.72, 0.36 },
		tip = "In items that sold, and in orders, which are paid when they're done." },
	{ key = "waiting", name = "Waiting to sell", color = { 0.93, 0.62, 0.15 },
		tip = "In items you crafted that haven't sold or been used yet." },
	{ key = "used", name = "Used in your crafts", color = { 0.55, 0.55, 0.55 },
		tip = "In items you crafted and then used as materials in your other crafts." },
	{ key = "gone", name = "Gone", color = { 0.42, 0.30, 0.30 },
		tip = "In items you used yourself, destroyed, mailed, traded or wrote off: gone without a sale, so no profit "
			.. "or loss is counted for them." },
}
-- The three things that stand out: each one's name, its color, and what it says
-- with nothing to show.
local CARDS = {
	{ title = "Best earner", color = "good", none = "Nothing has made a profit yet" },
	{ title = "Not selling", color = "missing", none = "Nothing is waiting with none sold" },
	{ title = "Furthest under its forecast", color = "loss", none = "Nothing sold under its forecast" },
}
local SORT_ARROW_ATLAS = "auctionhouse-ui-sortarrow"
local SORT_ARROW_FILE = "Interface\\Buttons\\UI-SortArrow"
local SORT_ARROW_SIZE = 10
local INFO_ICON = "Interface\\Common\\help-i"
local EXPORT_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local REFRESH_DELAY = 0.2   -- redraws are batched this long
local DAY = 86400
local RANGES = { { 7, "Last 7 days" }, { 30, "Last 30 days" }, { 90, "Last 90 days" } }
local KIND_SHORT = { craft = "Regular", patron = "Patron", personal = "Personal", guild = "Guild", public = "Public" }
-- Whether crafts come in types. WoW Forever has no crafting orders, so every
-- craft there is a regular one: no type filter, section, column or label.
local SHOWS_TYPES = ns.QUALITY_CRAFTING
-- Whether crafts proc. WoW Forever has no multicraft or resourcefulness, so no
-- procs columns or lines there; the forecast stays, since prices still move.
local SHOWS_PROCS = ns.QUALITY_CRAFTING
local NO_CRAFTS = "Nothing here yet. Crafts are recorded from now on, with what the panel forecast for them."
local NO_BOUGHT = "Nothing here yet. What you buy on the auction house, and materials from vendors, are recorded from now on."
local NO_MATCH = "Nothing matches the filters."
local NO_COST = "Crafted while the Craftonomics panel wasn't showing this recipe, so what its materials cost isn't known. It's left out of profit."
local MATCH_NOTE = "A sale counts toward your oldest unsold craft of that item and rank, so one craft's result is an estimate. Totals are what really sold."

local frame, scrollBox, headerBar, footer, empty, searchBox, exportFrame, flow
local tiles, headers, cards = {}, {}, {}
local rangeDropdown, characterDropdown, professionDropdown, kindDropdown
local tab = "items"
local characterFilter, professionFilter, kindFilter -- nil for all
local sorts = { items = { key = "earned", ascending = false }, bought = { key = "spent", ascending = false } }
local expanded = {} -- the items whose crafts show under them: their key -> true
local crafts, other, bought -- unpacked while the window is open
local stale = false -- new records came in: unpack again at the next redraw
local refreshQueued = false

local function signedMoney(amount)
	return Color(ns.AmountColor(amount), (amount > 0 and "+" or "") .. Money(amount))
end

local function plainMoney(amount, color)
	if not amount or amount == 0 then return Color("muted", "-") end
	return color and Color(color, Money(amount)) or Money(amount)
end

-- What procs added, or a dash for crafts from before it was saved.
local function procsText(amount)
	if not amount then return Color("muted", "-") end
	if math.abs(amount) < 1 then return Color("muted", "0") end
	return signedMoney(amount)
end

local function offText(off)
	if not off then return Color("muted", "-") end
	return Color(ns.AmountColor(off), format("%+.0f%%", off * 100))
end

local function marginText(margin)
	if not margin then return Color("muted", "-") end
	return Color(ns.AmountColor(margin), format("%.0f%%", margin * 100))
end

local function count(amount)
	if not amount or amount == 0 then return Color("muted", "0") end
	return BreakUpLargeNumbers(amount)
end

---------------------------------------------------------------------------
-- What's in view
---------------------------------------------------------------------------

local function nameOf(entry)
	if entry.name then return entry.name end
	if entry.itemID then return ns.Ledger.ItemName(entry.itemID) end
	return entry.recipeID > 0 and C_Spell.GetSpellName(entry.recipeID) or "Craft"
end

local function rankMarkup(entry)
	if not entry.rank or entry.rank == 0 then return "" end
	local icon
	if entry.recipeID and entry.recipeID > 0 and entry.recipeID ~= ns.Ledger.DISENCHANT then
		icon = ns.Blizzard.ItemQualityMarkup(entry.recipeID, entry.rank)
	elseif entry.itemID then
		icon = ns.Blizzard.ReagentQualityMarkup(entry.itemID)
	end
	return " " .. (icon or ("rank " .. entry.rank))
end

-- When today started, by your clock.
local function midnight()
	local today = date("*t")
	today.hour, today.min, today.sec = 0, 0, 0
	return time(today)
end

-- When the range starts: whole days, today being the last.
local function rangeStart()
	return midnight() - (ns.db.ledgerRange - 1) * DAY
end

-- What's being searched for.
local function searchText()
	return searchBox:GetText():lower()
end

-- The crafts the filters leave, oldest first.
local function inView()
	local since = rangeStart()
	local search = searchText()
	local list = {}
	for _, craft in ipairs(crafts or {}) do
		if craft.t >= since and (not characterFilter or craft.character == characterFilter)
			and (not professionFilter or craft.profession == professionFilter)
			and (not kindFilter or craft.kind == kindFilter)
			and (search == "" or nameOf(craft):lower():find(search, 1, true)) then
			list[#list + 1] = craft
		end
	end
	return list
end

-- The purchases the time, character and search filters leave. They have no profession.
local function boughtInView()
	local since = rangeStart()
	local search = searchText()
	local list = {}
	for _, entry in ipairs(bought or {}) do
		if entry.t >= since and (not characterFilter or entry.character == characterFilter)
			and (search == "" or entry.name:lower():find(search, 1, true)) then
			list[#list + 1] = entry
		end
	end
	return list
end

local function addHeading(rows, text)
	rows[#rows + 1] = { heading = text }
end

local function addAll(rows, list)
	for _, row in ipairs(list) do rows[#rows + 1] = row end
end


-- The months from before the days kept in full, newest first. Only their totals
-- are left, so there's nothing to filter them by.
local function monthRows()
	local rows = {}
	for _, totals in ipairs(ns.Ledger.Months()) do
		local year, month = totals.month:match("^(%d+)-(%d+)$")
		local label = year and date("%B %Y", time({ year = tonumber(year), month = tonumber(month), day = 1, hour = 12 }))
		rows[#rows + 1] = { label = label or totals.month, month = true, items = totals.items, earned = totals.profit }
	end
	return rows
end

---------------------------------------------------------------------------
-- What the crafts in view add up to
---------------------------------------------------------------------------

local function craftStatus(craft)
	if craft.kind ~= "craft" then return Color("good", "Paid") end
	if not craft.itemID then return Color("muted", "Nothing to sell") end
	if craft.left == 0 and craft.sold + craft.used == 0 then return Color("muted", "Gone") end
	if craft.left == 0 then
		if craft.sold > 0 and craft.vendored == craft.sold then return Color("good", "Sold to a vendor") end
		if craft.sold > 0 then return Color("good", craft.used > 0 and "Sold and used" or "Sold") end
		if craft.disenchanted == craft.used then return Color("good", "Disenchanted") end
		return Color("good", "Used")
	end
	if craft.sold + craft.used > 0 then return format("%d of %d sold", craft.sold + craft.used, craft.qty) end
	return Color("missing", "Not sold yet")
end


-- Where the gold put into materials went, for the crafts in view: sold (in items
-- that sold, and in orders, which are paid when done), waiting (in items not sold
-- or used yet), used (in items that went into your own crafts) and gone (in items
-- that left you without a sale). And ifAll: the profit still to come if what's
-- waiting sells for what it was worth when crafted.
local function flowOf(list)
	local parts = { sold = 0, waiting = 0, used = 0, gone = 0, ifAll = 0 }
	for _, craft in ipairs(list) do
		if not craft.noCost and craft.qty > 0 then
			if craft.kind == "craft" and craft.itemID then
				local share = craft.cost / craft.qty
				parts.sold = parts.sold + share * craft.sold
				parts.used = parts.used + share * craft.used
				parts.gone = parts.gone + share * craft.gone
				parts.waiting = parts.waiting + share * craft.left
				if craft.unit > 0 then parts.ifAll = parts.ifAll + (craft.unit - share) * craft.left end
			else
				parts.sold = parts.sold + craft.cost
			end
		end
	end
	return parts
end

-- How many whole days an item's oldest craft with some left has waited.
local function daysWaiting(item)
	local oldest
	for _, craft in ipairs(item.made) do
		if craft.left > 0 and (not oldest or craft.t < oldest) then oldest = craft.t end
	end
	return oldest and math.floor((time() - oldest) / DAY) or 0
end

-- What became of the ones that are gone without a sale: "40 used, 22 given away".
local function goneWords(of)
	local words = {}
	if of.consumed > 0 then words[#words + 1] = BreakUpLargeNumbers(of.consumed) .. " used" end
	if of.given > 0 then words[#words + 1] = BreakUpLargeNumbers(of.given) .. " given away" end
	if of.written > 0 then words[#words + 1] = BreakUpLargeNumbers(of.written) .. " written off" end
	return table.concat(words, ", ")
end

-- How an item is going, in a few words, and where that sorts (what needs a look
-- comes first).
local function itemStatus(item)
	if item.kind ~= "craft" then return Color("good", "Paid"), 0 end
	if not item.itemID then return Color("muted", "Nothing to sell"), 0 end
	local sold, left = BreakUpLargeNumbers(item.sold), BreakUpLargeNumbers(item.unsold)
	if item.unsold == 0 and item.sold + item.used == 0 then return Color("muted", "Gone: " .. goneWords(item)), 1 end
	if item.sold == 0 and item.used > 0 then
		-- What went into your crafts, and what you disenchanted.
		local inCrafts, words = item.used - item.disenchanted, {}
		if inCrafts > 0 then words[#words + 1] = format("Material: %s used in your crafts", BreakUpLargeNumbers(inCrafts)) end
		if item.disenchanted > 0 then words[#words + 1] = BreakUpLargeNumbers(item.disenchanted) .. " disenchanted" end
		if item.unsold > 0 then words[#words + 1] = left .. " left" end
		return Color("muted", table.concat(words, ", ")), 1
	end
	local off = ns.Ledger.Off(item)
	local under = off and off <= -UNDER_FORECAST and format("%.0f%% under its forecast", -off * 100)
	if item.unsold == 0 then
		if item.vendored == item.sold then return Color("good", "Sold to a vendor"), 2 end
		if under then return Color("loss", "Sold out, " .. under), 5 end
		return Color("good", "Sold out"), 2
	end
	if item.sold == 0 then
		local worth = item.pending > 0 and (", worth " .. Money(item.pending)) or ""
		local days = daysWaiting(item)
		if days >= SLOW_DAYS then return Color("missing", format("Not selling for %d days%s", days, worth)), 6 end
		return Color("missing", "Waiting to sell" .. worth), 4
	end
	if under then return Color("loss", under), 5 end
	local gone = format("%s of %s sold", sold, BreakUpLargeNumbers(item.items))
	if item.sold + item.used >= item.unsold then return Color("good", "Selling well: " .. gone), 3 end
	return "Selling: " .. gone, 3
end

-- One row per item, rank and type of craft in view (see Ledger.Items), each with
-- its key, how it's going (status) and where that sorts (statusOrder). Crafts that
-- made nothing to sell get a row for their recipe.
local function itemsOf(list)
	local items = ns.Ledger.Items(list)
	local recipes = {}
	for _, craft in ipairs(list) do
		if not craft.itemID then
			local key = format("r%d:%s", craft.recipeID, craft.kind)
			local group = recipes[key]
			if not group then
				group = { key = key, recipeID = craft.recipeID, rank = 0, kind = craft.kind, made = {} }
				recipes[key] = group
				items[#items + 1] = group
			end
			group.made[#group.made + 1] = craft
		end
	end
	for _, group in pairs(recipes) do
		for key, value in pairs(ns.Ledger.Summarize(group.made)) do group[key] = value end
	end
	for _, item in ipairs(items) do
		item.key = item.key or format("%d:%d:%s", item.itemID, item.rank, item.kind)
		item.status, item.statusOrder = itemStatus(item)
	end
	return items
end

-- The rows of the list: every item, and under an open one its crafts, newest
-- first (the ones of the same minute as one).
local function withCrafts(items)
	local rows = {}
	for _, item in ipairs(items) do
		rows[#rows + 1] = item
		if expanded[item.key] then
			local made = ns.Ledger.Merge(item.made)
			table.sort(made, function(a, b) return a.t > b.t end)
			for _, craft in ipairs(made) do
				craft.detail = true
				rows[#rows + 1] = craft
			end
		end
	end
	return rows
end

-- The three things that stand out among the items: the one that made the most,
-- the one with the most gold waiting and none sold, and the one furthest under
-- its forecast. Each can be nil.
local function standouts(items)
	local best, stuck, miss
	for _, item in ipairs(items) do
		if item.earned > 0 and (not best or item.earned > best.earned) then best = item end
		if item.kind == "craft" and item.itemID and item.sold == 0 and item.used == 0 and item.unsold > 0
			and (not stuck or item.pending > stuck.pending) then
			stuck = item
		end
		local off = ns.Ledger.Off(item)
		if off and off < 0 and (not miss or item.actual - item.forecast < miss.actual - miss.forecast) then miss = item end
	end
	return best, stuck, miss
end

-- An item's name as a row shows it: in its rarity's color, with its rank, and on
-- Retail the type of craft when it isn't a regular one.
local function itemName(row)
	local name = row.itemID and ns.Format.RarityColored(row.itemID, nameOf(row)) or nameOf(row)
	if SHOWS_TYPES and row.kind and row.kind ~= "craft" then
		return name .. rankMarkup(row) .. " " .. Color("muted", KIND_SHORT[row.kind] or row.kind)
	end
	-- What a disenchant gave you says so.
	if row.recipeID == ns.Ledger.DISENCHANT then return name .. rankMarkup(row) .. "  " .. Color("muted", "from disenchanting") end
	return name .. rankMarkup(row)
end

---------------------------------------------------------------------------
-- Columns: the first is the name; the others are key, header, width, text and,
-- for sorting, sort (what it sorts by; rows' field or function). left: its text
-- starts at the left. On Crafting a row is an item, one of an open item's crafts
-- (detail), or a month's totals (month).
---------------------------------------------------------------------------

-- Paying under your price source is the good direction.
local function vsMarketText(row)
	if not row.vsMarket then return Color("muted", "-") end
	return Color(row.vsMarket <= 0 and "profit" or "loss", format("%+.0f%%", row.vsMarket * 100))
end

-- How many are gone without a sale: used in your crafts, used yourself, destroyed,
-- given away or written off. With these, Made is Sold plus Gone plus Left.
local function goneCount(row)
	return (row.used or 0) + (row.gone or 0)
end

-- A dash while nothing of it has sold or been used for a profit of its own (what
-- was disenchanted, or used at its cost, has its profit in what it went into),
-- and for a craft whose materials cost isn't known.
local function profitText(row)
	if row.month then return signedMoney(row.earned) end
	if row.noCost or (row.unknown and row.unknown == row.crafts) then return Color("muted", "-") end
	if row.earned == 0 and (row.sold or 0) + (row.used or 0) - (row.usedAtCost or 0) == 0 then return Color("muted", "-") end
	return signedMoney(row.earned)
end

local COLUMNS = {
	items = {
		{ key = "name", header = "Item", sort = function(row) return nameOf(row):lower() end },
		{ key = "items", header = "Made", width = 60, sort = "items",
			text = function(row) return count(row.detail and row.qty or row.items) end },
		{ key = "sold", header = "Sold", width = 60, sort = "sold",
			text = function(row) return row.month and Color("muted", "-") or count(row.sold) end },
		{ key = "gone", header = "Gone", width = 60, sort = goneCount,
			text = function(row) return row.month and Color("muted", "-") or count(goneCount(row)) end },
		{ key = "unsold", header = "Left", width = 60, sort = "unsold",
			text = function(row)
				if row.month then return Color("muted", "-") end
				return count(row.detail and row.left or row.unsold)
			end },
		{ key = "earned", header = "Profit", width = 120, sort = "earned", text = profitText },
		{ key = "status", header = "How it's going", width = 340, left = true, sort = "statusOrder",
			text = function(row)
				if row.month then return "" end
				return row.detail and craftStatus(row) or row.status
			end },
	},
	bought = {
		{ key = "name", header = "Item", sort = function(row) return nameOf(row):lower() end },
		{ key = "qty", header = "Purchased", width = 70, sort = "qty", text = function(row) return count(row.qty) end },
		{ key = "spent", header = "Spent", width = 110, sort = "spent", text = function(row) return Color("loss", Money(row.spent)) end },
		{ key = "unitPaid", header = "Paid each", width = 96, sort = "unitPaid", text = function(row) return Money(row.unitPaid) end },
		{ key = "unitMarket", header = "Price each", width = 96, sort = "unitMarket",
			text = function(row) return plainMoney(row.unitMarket) end },
		{ key = "vsMarket", header = "Vs price", width = 66, sort = "vsMarket", text = vsMarketText },
		{ key = "resold", header = "Resold", width = 50, sort = "resold", text = function(row) return count(row.resold) end },
		{ key = "resaleProfit", header = "Resale profit", width = 104, sort = "resaleProfit", text = function(row)
			return row.resaleProfit and signedMoney(row.resaleProfit) or Color("muted", "-") end },
	},
}

-- Where each column sits in a row `width` wide; the name takes what the others
-- leave. On Crafting it starts after the plus that opens an item.
local function columnPlaces(columns, width)
	local places, right = {}, width - 4
	for i = #columns, 2, -1 do
		local column = columns[i]
		places[i] = { x = right - column.width, width = column.width }
		right = right - column.width - CELL_GAP
	end
	local nameX = 4 + (tab == "items" and TOGGLE_SIZE + 4 or 0) + ICON_SIZE + 6
	places[1] = { x = nameX, width = right - nameX }
	return places
end

local function sortRows(rows)
	local sort = sorts[tab]
	local valueOf
	for _, column in ipairs(COLUMNS[tab]) do
		if column.key == sort.key then valueOf = column.sort end
	end
	local function read(row)
		if type(valueOf) == "function" then return valueOf(row) end
		return row[valueOf]
	end
	table.sort(rows, function(a, b)
		local av, bv = read(a), read(b)
		if (av == nil) ~= (bv == nil) then return av ~= nil end
		if av == bv or av == nil then return (a.earned or 0) > (b.earned or 0) end
		if sort.ascending then return av < bv end
		return av > bv
	end)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function addPair(left, right)
	GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
end

-- What became of the ones that didn't sell at auction.
local function addGone(of)
	if (of.vendored or 0) > 0 then addPair("Of those sold, to a vendor", of.vendored) end
	if (of.consumed or 0) > 0 then addPair("Used yourself or destroyed", of.consumed) end
	if (of.given or 0) > 0 then addPair("Mailed, traded or put in the guild bank", of.given) end
	if (of.written or 0) > 0 then addPair("Written off", of.written) end
end

-- The game's own tooltip of an item (with what price addons add to it), or just
-- the name of a craft that made no item. Then a heading for what the Ledger adds:
-- only what the row doesn't already show.
local function startTooltip(entry)
	if entry.itemID then
		GameTooltip:SetItemByID(entry.itemID)
	else
		GameTooltip:SetText(nameOf(entry))
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("In your Ledger", 1, 0.82, 0)
end

-- One of an open item's crafts. When, who, how many and the profit are in its row.
local function craftTooltip(craft)
	startTooltip(craft)
	local disenchant = craft.recipeID == ns.Ledger.DISENCHANT
	if disenchant then
		addPair("Made by", "Disenchanting")
	elseif SHOWS_TYPES then
		addPair("Type", ns.Ledger.KINDS[craft.kind] or craft.kind)
	end
	addPair(disenchant and "Cost of what you disenchanted" or "Materials cost",
		craft.noCost and Color("muted", "Not known") or Money(craft.cost))
	if craft.noCost then
		-- No forecast either.
	elseif not SHOWS_PROCS then
		if craft.expected ~= 0 then addPair("Forecast", signedMoney(craft.expected)) end
	elseif craft.hasProcs then
		if craft.expected ~= 0 then addPair("Forecast without procs", signedMoney(craft.expected)) end
		if craft.forecast ~= craft.expected then addPair("Forecast with average procs", signedMoney(craft.forecast)) end
		addPair("Procs added", procsText(craft.procGain))
	elseif craft.forecast ~= 0 then
		addPair("Forecast with average procs", signedMoney(craft.forecast))
	end
	if craft.kind == "craft" and craft.itemID then
		if craft.unit > 0 then addPair("Worth each when crafted", Money(craft.unit)) end
		if craft.sold > 0 then
			addPair("Sold for", Money(craft.money))
			addPair("Sold each", Money(craft.money / craft.sold))
		end
		if craft.used > 0 then addPair("Used in your crafts", craft.used) end
		if craft.usedAtCost > 0 then addPair("Of those, counted at their cost", craft.usedAtCost) end
		if craft.disenchanted > 0 then addPair("Of those, disenchanted", craft.disenchanted) end
		addGone(craft)
	elseif craft.kind ~= "craft" then
		if not craft.noCost then addPair("Paid", Money(craft.money)) end
	end
	GameTooltip:AddLine(" ")
	if craft.noCost then
		GameTooltip:AddLine(NO_COST, 1, 0.82, 0, true)
		GameTooltip:AddLine(" ")
	end
	GameTooltip:AddLine(MATCH_NOTE, 0.53, 0.53, 0.53, true)
end

-- An item. How many were made, sold, gone and left, and the profit, are in its row.
local function itemTooltip(item)
	startTooltip(item)
	if SHOWS_TYPES then addPair("Type", ns.Ledger.KINDS[item.kind] or item.kind) end
	addPair("Materials cost", Money(item.cost))
	if item.unitCost then addPair("Cost each", Money(item.unitCost)) end
	if item.unitPrice then
		addPair(item.kind == "craft" and "Expected sale price each" or "Expected pay each", Money(item.unitPrice))
	end
	if item.unitSold then addPair("Sold each", Money(item.unitSold)) end
	if item.unitProfit then addPair("Profit each", signedMoney(item.unitProfit)) end
	if item.margin then addPair("Margin on what sold", marginText(item.margin)) end
	if item.days then addPair("Days to sell", format("%.1f", item.days)) end
	if item.used > 0 then addPair("Used in your crafts", item.used) end
	if (item.disenchanted or 0) > 0 then addPair("Of those, disenchanted", item.disenchanted) end
	addGone(item)
	if item.pending > 0 then addPair("Worth when crafted, what's left", Money(item.pending)) end
	if item.forecast ~= 0 then
		addPair("Forecast for what's done", signedMoney(item.forecast))
		if item.unitProcs and SHOWS_PROCS then addPair("Procs added", procsText(item.procs)) end
		addPair("Off by", offText(ns.Ledger.Off(item)))
	end
end

-- Something you bought. What you paid and resold it for is in its row.
local function boughtTooltip(row)
	startTooltip(row)
	addPair("Bought from", row.source == "vendor" and "Vendors" or "The auction house")
end

local function showRowTooltip(button)
	local row = button.row
	if not row or row.heading or row.month then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if tab == "bought" then
		boughtTooltip(row)
	elseif row.detail then
		craftTooltip(row)
	else
		itemTooltip(row)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(expanded[row.key] and "Click: hide its crafts" or "Click: show its crafts", 0.6, 0.6, 0.6)
		if row.itemID and row.kind == "craft" then
			GameTooltip:AddLine("Right-click: write off what's left", 0.6, 0.6, 0.6)
		end
	end
	GameTooltip:Show()
end

-- How many of an item, of its rank and type, are on record as left in all,
-- whatever time the filters show.
local function leftInAll(item)
	local left = 0
	for _, craft in ipairs(crafts or {}) do
		if craft.itemID == item.itemID and craft.rank == item.rank and craft.kind == item.kind then left = left + craft.left end
	end
	return left
end

-- An item's right-click menu: write off what's left of it (you don't have it any
-- more, and it didn't sell), or take its write-offs back.
local function showItemMenu(button, item)
	local left = leftInAll(item)
	MenuUtil.CreateContextMenu(button, function(_, root)
		root:CreateTitle(nameOf(item))
		local writeOff = root:CreateButton(left > 0 and format("Write off the %s left", BreakUpLargeNumbers(left))
			or "Nothing left to write off", function()
			ns.Ledger.WriteOff({ { itemID = item.itemID, qty = left, rank = item.rank } })
		end)
		writeOff:SetEnabled(left > 0)
		if item.written > 0 then
			root:CreateButton("Take its write-offs back", function() ns.Ledger.TakeBack(item.itemID) end)
		end
	end)
end

-- A click on an item opens it on its crafts, or closes it again. A right-click
-- has its menu.
local function onRowClick(button, mouseButton)
	local row = button.row
	if tab ~= "items" or not (row and row.key) then return end
	if mouseButton == "RightButton" then
		GameTooltip:Hide()
		if row.itemID and row.kind == "craft" then showItemMenu(button, row) end
		return
	end
	expanded[row.key] = not expanded[row.key] or nil
	GameTooltip:Hide()
	LedgerWindow.Render()
end

local function createRow(button)
	button.cells = {}
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	button.toggle = button:CreateTexture(nil, "ARTWORK")
	button.toggle:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
	button.toggle:SetPoint("LEFT", 4, 0)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(ICON_SIZE, ICON_SIZE)
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.stripe = button:CreateTexture(nil, "BACKGROUND")
	button.stripe:SetAllPoints()
	button.stripe:SetColorTexture(1, 1, 1, 0.035)
	-- Behind an open item's crafts, so they read as part of it.
	button.shade = button:CreateTexture(nil, "BACKGROUND")
	button.shade:SetAllPoints()
	button.shade:SetColorTexture(0, 0, 0, 0.32)
	button.rule = button:CreateTexture(nil, "ARTWORK")
	button.rule:SetHeight(1)
	button.rule:SetPoint("BOTTOMLEFT", 4, 1)
	button.rule:SetPoint("BOTTOMRIGHT", -4, 1)
	button.rule:SetColorTexture(1, 0.82, 0, 0.3)
	button:SetScript("OnEnter", showRowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", onRowClick)
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
	local columns = COLUMNS[tab]
	local places = columnPlaces(columns, scrollBox:GetWidth())
	for i, cell in ipairs(button.cells) do cell:SetShown(i <= #columns) end
	for i, column in ipairs(columns) do
		local cell = cellOf(button, i)
		cell:Show()
		cell:ClearAllPoints()
		cell:SetPoint("LEFT", button, "LEFT", places[i].x, 0)
		cell:SetWidth(places[i].width)
		cell:SetJustifyH((i == 1 or column.left) and "LEFT" or "RIGHT")
		if row.heading then
			cell:SetText("")
		elseif i > 1 then
			cell:SetText(column.text(row))
		end
	end

	local opens = tab == "items" and row.key ~= nil
	button.stripe:SetShown(row.stripe == true)
	button.shade:SetShown(row.detail == true)
	button.rule:SetShown(row.heading ~= nil)
	button.toggle:SetShown(opens)
	if opens then button.toggle:SetTexture(expanded[row.key] and MINUS or PLUS) end
	local first = button.cells[1]
	local hasIcon = row.itemID ~= nil and not row.detail
	button.icon:SetShown(hasIcon)
	if row.heading then
		first:ClearAllPoints()
		first:SetPoint("LEFT", button, "LEFT", 4, 0)
		first:SetWidth(places[1].x + places[1].width - 4)
		first:SetText(Color("heading", row.heading))
	elseif row.label then
		first:SetText(row.label)
	elseif row.detail then
		-- One of an open item's crafts: when, who, and how many crafts it stands for.
		local what = row.recipeID == ns.Ledger.DISENCHANT and "disenchant" or "craft"
		local many = row.count > 1 and format("   %d %ss", row.count, what) or (what == "disenchant" and "   disenchant" or "")
		first:SetText(Color("muted", date("%b %d %H:%M", row.t)) .. "   " .. ns.Ranks.CharacterName(row.character or "?")
			.. Color("muted", many))
	else
		first:SetText(itemName(row))
	end
	if hasIcon then
		button.icon:ClearAllPoints()
		button.icon:SetPoint("LEFT", button, "LEFT", places[1].x - ICON_SIZE - 6, 0)
		button.icon:SetTexture(C_Item.GetItemIconByID(row.itemID))
	end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

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
		local current = sorts[tab]
		if not (current and self.sortKey) then return end
		if current.key == self.sortKey then
			current.ascending = not current.ascending
		else
			current.key, current.ascending = self.sortKey, false
		end
		LedgerWindow.Render()
	end)
	return header
end

local function drawHeaders()
	local columns = COLUMNS[tab]
	local places = columnPlaces(columns, scrollBox:GetWidth())
	for _, header in ipairs(headers) do header:Hide() end
	local sort = sorts[tab]
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
		header.sortKey = column.sort and column.key or nil
		header.text:SetJustifyH(left and "LEFT" or "RIGHT")
		local sorted = sort.key == column.key
		header.text:SetText(sorted and Color("heading", column.header) or column.header)
		header.arrow:SetShown(sorted)
		if sorted then
			if sort.ascending then header.arrow:SetTexCoord(0, 1, 1, 0) else header.arrow:SetTexCoord(0, 1, 0, 1) end
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

-- One of the three totals: its number, a line under it, and what its tooltip says.
local function setTile(index, value, sub, note)
	local tile = tiles[index]
	tile.label = TILE_LABELS[tab][index]
	tile.name:SetText(tile.label)
	tile.value:SetText(value)
	tile.sub:SetText(Color("muted", sub))
	tile.note = note
end

-- Crafting's totals: the profit so far, what's waiting to sell, and the profit
-- if that sells too.
local function drawTiles(total, parts)
	local off = ns.Ledger.Off(total)
	setTile(1, signedMoney(total.earned),
		format("%s sold for %s", BreakUpLargeNumbers(total.sold), Money(total.money)),
		"Orders when they're done, regular crafts as they sell, each minus its materials."
			.. (total.unknown > 0 and format("\n\n%s crafts are left out: they were crafted while the Craftonomics panel wasn't showing their recipe, so what their materials cost isn't known.",
				BreakUpLargeNumbers(total.unknown)) or "")
			.. (off and (SHOWS_PROCS
				and format("\n\nAgainst the forecast: leaving procs out, what's done made %s, forecast %s. Procs added %s.",
					signedMoney(total.actual), signedMoney(total.forecast), procsText(total.procs))
				or format("\n\nAgainst the forecast: what's done made %s, forecast %s.", signedMoney(total.actual),
					signedMoney(total.forecast))) or ""))
	setTile(2, Money(total.pending),
		format("%s items, at their price when crafted", BreakUpLargeNumbers(total.unsold)),
		"What you crafted and haven't sold or used yet, at what it was worth when you crafted it.")
	setTile(3, signedMoney(total.earned + parts.ifAll), "profit so far, plus what's waiting",
		"The profit so far, plus what the items still waiting would make if they sell for what they were worth when "
			.. "you crafted them, minus their materials. Items with no price then aren't counted.")
end

-- Purchases' totals: what you spent, how that compares with your price source at
-- the time, and what you made reselling.
local function drawBoughtTiles(rows)
	local spent, qty, paid, worth, resale, resold = 0, 0, 0, 0, 0, 0
	for _, row in ipairs(rows) do
		spent, qty = spent + row.spent, qty + row.qty
		paid, worth = paid + row.marketPaid, worth + row.marketWorth
		resale, resold = resale + (row.resaleProfit or 0), resold + row.resold
	end
	setTile(1, spent > 0 and Color("loss", Money(spent)) or Color("muted", "-"),
		format("%s items bought", BreakUpLargeNumbers(qty)),
		"What you paid on the auction house and to vendors in this time. It isn't added to what your crafts' "
			.. "materials cost, or what you buy and then use would count twice.")
	local against = worth > 0 and (paid - worth) / worth
	setTile(2, against and Color(against <= 0 and "profit" or "loss", format("%+.0f%%", against * 100)) or Color("muted", "-"),
		"what you paid, against your price then",
		"What you paid for the items that had a price at the time, against that price. Under it is the good direction.")
	setTile(3, resold > 0 and signedMoney(resale) or Color("muted", "-"),
		format("%s resold", BreakUpLargeNumbers(resold)),
		"A sale no craft of yours explains counts toward what you bought of that item: this is what those sold for, "
			.. "minus what you paid for them.")
end

-- The bar of where the gold put into materials went, with what each part is
-- under it.
local function drawFlow(parts)
	local all = parts.sold + parts.waiting + parts.used + parts.gone
	flow.title:SetText(all > 0 and format("Where the %s you put into materials went", Money(all))
		or "Where the gold you put into materials went")
	flow.none:SetShown(all == 0)
	local x, legend = 0, {}
	for index, part in ipairs(FLOW_PARTS) do
		local amount = parts[part.key]
		local segment = flow.segments[index]
		local size = all > 0 and amount / all * flow.barWidth or 0
		segment:SetShown(size >= 1)
		if size >= 1 then
			segment:ClearAllPoints()
			segment:SetPoint("LEFT", flow.bar, "LEFT", x, 0)
			segment:SetSize(size, FLOW_BAR_HEIGHT)
			x = x + size
		end
		segment.amount, segment.share = amount, all > 0 and amount / all or 0
		local color = part.color
		legend[index] = format("|T%s:10:10:0:0:8:8:0:8:0:8:%d:%d:%d|t %s %s", WHITE, math.floor(color[1] * 255),
			math.floor(color[2] * 255), math.floor(color[3] * 255), part.name,
			amount > 0 and Money(amount) or Color("muted", "-"))
	end
	flow.legend:SetText(all > 0 and table.concat(legend, "    ") or "")
end

-- The three things that stand out, each an item with a few words on it. A click
-- on one shows only that item, opened on its crafts.
local function drawCards(items)
	local best, stuck, miss = standouts(items)
	local picks = { best or false, stuck or false, miss or false }
	local words = {}
	if best then
		words[1] = signedMoney(best.earned) .. Color("muted", format(", %s of %s sold", BreakUpLargeNumbers(best.sold),
			BreakUpLargeNumbers(best.items)))
	end
	if stuck then
		local days = daysWaiting(stuck)
		words[2] = Color("muted", days >= 1 and format("%s made, none sold in %d days", BreakUpLargeNumbers(stuck.items), days)
			or format("%s made, none sold yet", BreakUpLargeNumbers(stuck.items)))
	end
	if miss then
		words[3] = Color("loss", format("%.0f%% under", -ns.Ledger.Off(miss) * 100)) .. Color("muted", " its forecast")
	end
	for index, card in ipairs(cards) do
		local item = picks[index] or nil
		card.item = item
		if item then
			local icon = item.itemID and C_Item.GetItemIconByID(item.itemID)
			card.text:SetText((icon and format("|T%s:16|t ", icon) or "") .. itemName(item) .. "    " .. words[index])
		else
			card.text:SetText(Color("muted", CARDS[index].none))
		end
	end
end

local function showNote(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("How this is worked out")
	GameTooltip:AddLine(MATCH_NOTE, 1, 1, 1, true)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Forecasts and prices use your price options, as they were when each craft or purchase was recorded, so they don't change later."
		.. (SHOWS_PROCS and " Forecasts leave procs out, because they're luck: what procs really added shows on its own. Crafts from before that was saved show a forecast with average procs." or ""),
		1, 1, 1, true)
	if other and other.qty > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(format("%s sold with no craft or purchase on record, for %s: from before the Ledger.",
			BreakUpLargeNumbers(other.qty), Money(other.money)), 1, 1, 1, true)
	end
	GameTooltip:Show()
end

function LedgerWindow.Render()
	refreshQueued = false
	if not (frame and frame:IsShown()) then return end
	if stale then
		stale = false
		crafts, other, bought = ns.Ledger.Load()
	end
	local crafting = tab == "items"
	PanelTemplates_SetTab(frame, tIndexOf(TAB_KEYS, tab))
	-- The selected tab's label uses a smaller font: a width measured then would cut
	-- it short once another tab is picked, so all of them measure again each time.
	for _, button in ipairs(frame.Tabs) do PanelTemplates_TabResize(button, TAB_PADDING) end
	-- Purchases has no bar and no things that stand out: its list starts higher.
	flow:SetShown(crafting)
	for _, card in ipairs(cards) do card:SetShown(crafting) end
	frame.Inset:SetPoint("TOPLEFT", SIDE - 4, -(crafting and INSET_TOP or INSET_TOP_BOUGHT))

	local rows
	if crafting then
		local list = inView()
		local total = ns.Ledger.Summarize(list)
		local parts = flowOf(list)
		local items = itemsOf(list)
		drawTiles(total, parts)
		drawFlow(parts)
		drawCards(items)
		sortRows(items)
		rows = withCrafts(items)
		-- The months before the days kept in full have nothing to filter them by.
		if not (characterFilter or professionFilter or kindFilter) and searchText() == "" then
			local months = monthRows()
			if #months > 0 then
				addHeading(rows, "More than 90 days ago, by month")
				addAll(rows, months)
			end
		end
		footer:SetText(Color("muted", format("%s crafts, %s items · Prices: %s", BreakUpLargeNumbers(total.crafts),
			BreakUpLargeNumbers(total.items), ns.Prices.SourceLabel())))
	else
		local purchases = boughtInView()
		rows = ns.Ledger.BoughtItems(purchases)
		drawBoughtTiles(rows)
		sortRows(rows)
		footer:SetText(Color("muted", format("%s purchases · Prices: %s", BreakUpLargeNumbers(#purchases),
			ns.Prices.SourceLabel())))
	end
	-- Nothing recorded yet, or nothing the filters leave.
	local any = #(crafting and (crafts or {}) or bought or {}) > 0
	empty:SetText(any and NO_MATCH or (crafting and NO_CRAFTS or NO_BOUGHT))
	empty:SetShown(#rows == 0)
	local striped = 0
	for _, row in ipairs(rows) do
		-- An open item's crafts have their own shade, and don't count for the stripes.
		if row.heading or row.detail then
			row.stripe = false
		else
			striped = striped + 1
			row.stripe = striped % 2 == 0
		end
	end
	scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
	drawHeaders()
	rangeDropdown:GenerateMenu()
	characterDropdown:GenerateMenu()
	professionDropdown:GenerateMenu()
	kindDropdown:GenerateMenu()
end

-- A redraw swaps the rows' frames, so it waits for a click or a menu in progress.
local function renderWhenIdle()
	if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") or Menu.GetManager():GetOpenMenu() then
		C_Timer.After(REFRESH_DELAY, renderWhenIdle)
		return
	end
	LedgerWindow.Render()
end

local function refresh()
	if refreshQueued or not (frame and frame:IsShown()) then return end
	refreshQueued = true
	C_Timer.After(REFRESH_DELAY, renderWhenIdle)
end

-- New records while it's open: unpack again, once for all that come together.
local function reload()
	if not (frame and frame:IsShown()) then return end
	stale = true
	refresh()
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------

local function csvField(text)
	text = tostring(text)
	if text:find('[,"]') then return '"' .. text:gsub('"', '""') .. '"' end
	return text
end

-- What the tab shows, for a spreadsheet: the purchases on Purchased, the crafts
-- on the others.
local function exportText()
	local function gold(amount) return format("%.2f", amount / 10000) end
	if tab == "bought" then
		local lines = { "Date,Character,Item,Rank,From,Purchased,Spent (gold),Price each then (gold)" }
		for _, entry in ipairs(boughtInView()) do
			lines[#lines + 1] = table.concat({ date("%Y-%m-%d %H:%M", entry.t), csvField(entry.character or "?"),
				csvField(entry.name), entry.rank, entry.source == "vendor" and "Vendor" or "Auction house", entry.qty,
				gold(entry.spent), entry.market > 0 and gold(entry.market) or "" }, ",")
		end
		return table.concat(lines, "\n")
	end
	local lines = { "Date,Character,Profession,Item,Rank,Type,Made,Sold,Used,Unsold,Materials cost (gold),Forecast (gold),Procs (gold),Sold for (gold),Profit so far (gold)" }
	for _, craft in ipairs(inView()) do
		-- No cost on record: no forecast or profit either.
		local known = not craft.noCost
		lines[#lines + 1] = table.concat({ date("%Y-%m-%d %H:%M", craft.t), csvField(craft.character or "?"),
			csvField(craft.profession or "?"), csvField(nameOf(craft)), craft.rank, KIND_SHORT[craft.kind] or craft.kind,
			craft.qty, craft.sold, craft.used, craft.left, known and gold(craft.cost) or "", known and gold(craft.expected) or "",
			known and craft.hasProcs and gold(craft.procGain) or "", gold(craft.money), known and gold(craft.earned) or "" }, ",")
	end
	return table.concat(lines, "\n")
end

-- Asks first: there's no getting the records back.
StaticPopupDialogs.CRAFTONOMICS_CLEAR_LEDGER = {
	text = "Clear the whole Ledger, for all your characters?\n\nEvery craft, sale and purchase in it is gone for good.",
	button1 = "Clear",
	button2 = CANCEL,
	OnAccept = function() ns.Ledger.Clear() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- Asks first, saying how many it found (see checkOwned).
StaticPopupDialogs.CRAFTONOMICS_CHECK_LEDGER = {
	text = "%s",
	button1 = "Write off",
	button2 = CANCEL,
	OnAccept = function(_, list) ns.Ledger.WriteOff(list) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- The Check what I have button: finds what's on record as left of this
-- character's crafts but isn't with it any more, and offers to write it off.
local function checkOwned()
	local list, total = ns.Ledger.Missing()
	if total == 0 then
		ns.Shopping.Say("Ledger: everything on record as left of this character's crafts is still with it.")
		return
	end
	local name = ns.Ranks.CharacterName(select(2, ns.Ranks.Me()) or "?")
	StaticPopup_Show("CRAFTONOMICS_CHECK_LEDGER", format("%s items of %s kinds are on record as left, but %s doesn't "
		.. "have them: not in bags or bank, and not put on the auction house these last days.\n\nWrite them off? They "
		.. "leave Waiting to sell, and no profit or loss is counted for them. An item's right-click menu takes its "
		.. "write-offs back.", BreakUpLargeNumbers(total), BreakUpLargeNumbers(#list), name), nil, list)
end

local function showCheckTip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Check what I have")
	GameTooltip:AddLine("Compares what's on record as left of this character's crafts with what it really has, in "
		.. "bags and bank and on the auction house, and offers to write off the rest: what you used, sold to a "
		.. "vendor, mailed or traded before the Ledger kept track of that.", 1, 1, 1, true)
	GameTooltip:AddLine("Only this character's crafts are checked: log in on each crafter for theirs.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function showExport()
	if not exportFrame then
		exportFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		exportFrame:SetPoint("TOPLEFT", 40, -60)
		exportFrame:SetPoint("BOTTOMRIGHT", -40, 60)
		exportFrame:SetFrameLevel(frame:GetFrameLevel() + 30)
		exportFrame:SetBackdrop(EXPORT_BACKDROP)
		exportFrame:SetBackdropColor(0.05, 0.05, 0.05, 1)
		exportFrame:EnableMouse(true)
		local label = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("TOPLEFT", SIDE, -SIDE)
		label:SetText("Copy with Ctrl+C, then paste into a spreadsheet")
		local close = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
		local scroll = CreateFrame("ScrollFrame", nil, exportFrame, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", SIDE, -(SIDE + 24))
		scroll:SetPoint("BOTTOMRIGHT", -(SIDE + 24), SIDE)
		local box = CreateFrame("EditBox", nil, scroll)
		box:SetMultiLine(true)
		box:SetFontObject("GameFontHighlight")
		box:SetAutoFocus(false)
		box:SetSize(400, 100)
		box:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
		scroll:SetScrollChild(box)
		exportFrame.box = box
	end
	exportFrame:Show()
	exportFrame.box:SetWidth(exportFrame:GetWidth() - 2 * SIDE - 24)
	exportFrame.box:SetText(exportText())
	exportFrame.box:SetFocus()
	exportFrame.box:HighlightText()
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- The values of `field` among the crafts, sorted; for characters, among the
-- purchases too, since a character can buy without crafting.
local function distinct(field)
	local seen, list = {}, {}
	local function add(records)
		for _, record in ipairs(records or {}) do
			local value = record[field]
			if value and value ~= "?" and not seen[value] then
				seen[value] = true
				list[#list + 1] = value
			end
		end
	end
	add(crafts)
	if field == "character" then add(bought) end
	table.sort(list)
	return list
end

local function rangeMenu(_, root)
	for _, range in ipairs(RANGES) do
		root:CreateRadio(range[2], function() return ns.db.ledgerRange == range[1] end, function()
			ns.db.ledgerRange = range[1]
			LedgerWindow.Render()
		end)
	end
end

local function characterMenu(_, root)
	root:CreateRadio("All characters", function() return characterFilter == nil end, function()
		characterFilter = nil
		LedgerWindow.Render()
	end)
	for _, key in ipairs(distinct("character")) do
		root:CreateRadio(ns.Ranks.CharacterName(key), function() return characterFilter == key end, function()
			characterFilter = key
			LedgerWindow.Render()
		end)
	end
end

local function professionMenu(_, root)
	root:CreateRadio("All professions", function() return professionFilter == nil end, function()
		professionFilter = nil
		LedgerWindow.Render()
	end)
	for _, name in ipairs(distinct("profession")) do
		root:CreateRadio(name, function() return professionFilter == name end, function()
			professionFilter = name
			LedgerWindow.Render()
		end)
	end
end

local function kindMenu(_, root)
	root:CreateRadio("All types", function() return kindFilter == nil end, function()
		kindFilter = nil
		LedgerWindow.Render()
	end)
	local present = distinct("kind")
	for _, kind in ipairs(ns.Ledger.KIND_ORDER) do
		if tContains(present, kind) then
			root:CreateRadio(ns.Ledger.KINDS[kind], function() return kindFilter == kind end, function()
				kindFilter = kind
				LedgerWindow.Render()
			end)
		end
	end
end

local function createDropdown(menu, width)
	local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(width)
	dropdown:SetupMenu(menu)
	return dropdown
end

local function createTabs()
	for index, label in ipairs(TAB_LABELS) do
		local button = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
		button:SetID(index)
		button:SetText(label)
		button:SetNormalFontObject("GameFontNormal")
		button:SetHighlightFontObject("GameFontHighlight")
		button:SetDisabledFontObject("GameFontHighlight")
		button:SetScript("OnClick", function()
			tab = TAB_KEYS[index]
			LedgerWindow.Render()
		end)
		PanelTemplates_TabResize(button, TAB_PADDING)
	end
	frame.Tabs[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
	PanelTemplates_SetNumTabs(frame, #TAB_LABELS)
end

-- A dark box with a gold line along its top, as the totals and the things that
-- stand out have.
local function addBox(region)
	local back = region:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.45)
	local edge = region:CreateTexture(nil, "ARTWORK")
	edge:SetHeight(2)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("TOPRIGHT")
	edge:SetColorTexture(1, 0.82, 0, 0.5)
end

local function createTiles()
	for index = 1, 3 do
		local tile = CreateFrame("Frame", nil, frame)
		tile:SetSize(TILE_WIDTH, TILE_HEIGHT)
		tile:SetPoint("TOPLEFT", SIDE + (index - 1) * (TILE_WIDTH + TILE_GAP), -TILES_TOP)
		addBox(tile)
		tile.name = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		tile.name:SetPoint("TOPLEFT", 10, -7)
		tile.value = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		tile.value:SetPoint("TOPLEFT", 10, -23)
		tile.value:SetPoint("RIGHT", -6, 0)
		tile.value:SetJustifyH("LEFT")
		tile.value:SetWordWrap(false)
		tile.value:SetTextColor(1, 1, 1)
		tile.sub = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		tile.sub:SetPoint("BOTTOMLEFT", 10, 6)
		tile.sub:SetPoint("RIGHT", -6, 0)
		tile.sub:SetJustifyH("LEFT")
		tile.sub:SetWordWrap(false)
		tile:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(self.label)
			GameTooltip:AddLine(self.note, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		tile:SetScript("OnLeave", GameTooltip_Hide)
		tiles[index] = tile
	end
end

-- Right of the totals: the bar of where the gold put into materials went.
local function createFlow()
	local left = SIDE + 3 * (TILE_WIDTH + TILE_GAP)
	flow = CreateFrame("Frame", nil, frame)
	flow:SetPoint("TOPLEFT", left, -TILES_TOP)
	flow:SetSize(WIDTH - SIDE - left, TILE_HEIGHT)
	addBox(flow)
	flow.title = flow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	flow.title:SetPoint("TOPLEFT", 10, -7)
	flow.barWidth = WIDTH - SIDE - left - 20
	flow.bar = CreateFrame("Frame", nil, flow)
	flow.bar:SetPoint("TOPLEFT", 10, -27)
	flow.bar:SetSize(flow.barWidth, FLOW_BAR_HEIGHT)
	local ground = flow.bar:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(1, 1, 1, 0.06)
	flow.none = flow:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	flow.none:SetPoint("BOTTOMLEFT", 10, 6)
	flow.none:SetText("Nothing crafted in this time.")
	flow.legend = flow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	flow.legend:SetPoint("BOTTOMLEFT", 10, 6)
	flow.segments = {}
	for index, part in ipairs(FLOW_PARTS) do
		local segment = CreateFrame("Frame", nil, flow.bar)
		segment:EnableMouse(true)
		local fill = segment:CreateTexture(nil, "ARTWORK")
		fill:SetAllPoints()
		fill:SetColorTexture(part.color[1], part.color[2], part.color[3], 0.95)
		segment:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(part.name)
			GameTooltip:AddLine(format("%s of the gold you put into materials, %.0f%% of it.", Money(self.amount),
				self.share * 100), 1, 1, 1, true)
			GameTooltip:AddLine(part.tip, 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end)
		segment:SetScript("OnLeave", GameTooltip_Hide)
		flow.segments[index] = segment
	end
end

-- Under the totals: the three things that stand out.
local function createCards()
	local width = (WIDTH - 2 * SIDE - 2 * TILE_GAP) / 3
	for index, about in ipairs(CARDS) do
		local card = CreateFrame("Button", nil, frame)
		card:SetSize(width, CARD_HEIGHT)
		card:SetPoint("TOPLEFT", SIDE + (index - 1) * (width + TILE_GAP), -CARDS_TOP)
		addBox(card)
		local highlight = card:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.06)
		local title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		title:SetPoint("TOPLEFT", 10, -7)
		title:SetText(Color(about.color, about.title))
		card.text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		card.text:SetPoint("BOTTOMLEFT", 10, 7)
		card.text:SetPoint("RIGHT", -6, 0)
		card.text:SetJustifyH("LEFT")
		card.text:SetWordWrap(false)
		card:SetScript("OnClick", function(self)
			local item = self.item
			if not item then return end
			expanded[item.key] = true
			searchBox:SetText(nameOf(item))
		end)
		card:SetScript("OnEnter", function(self)
			if not self.item then return end
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			itemTooltip(self.item)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Click: show only this item, with its crafts", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		card:SetScript("OnLeave", GameTooltip_Hide)
		cards[index] = card
	end
end

local function create()
	frame = CreateFrame("Frame", "CraftonomicsLedger", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(frame)
	frame:SetTitle("Ledger")
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
	tinsert(UISpecialFrames, "CraftonomicsLedger")
	frame.Inset:ClearAllPoints()
	frame.Inset:SetPoint("TOPLEFT", SIDE - 4, -INSET_TOP)
	frame.Inset:SetPoint("BOTTOMRIGHT", -(SIDE - 4), 32)

	searchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	searchBox:SetSize(200, 20)
	searchBox:SetPoint("TOPLEFT", SIDE + 6, -(FILTERS_TOP + 2))
	searchBox:SetAutoFocus(false)
	searchBox:HookScript("OnTextChanged", refresh)

	rangeDropdown = createDropdown(rangeMenu, 130)
	rangeDropdown:SetPoint("TOPRIGHT", -SIDE, -FILTERS_TOP)
	characterDropdown = createDropdown(characterMenu, 150)
	characterDropdown:SetPoint("RIGHT", rangeDropdown, "LEFT", -8, 0)
	professionDropdown = createDropdown(professionMenu, 150)
	professionDropdown:SetPoint("RIGHT", characterDropdown, "LEFT", -8, 0)
	kindDropdown = createDropdown(kindMenu, 130)
	kindDropdown:SetPoint("RIGHT", professionDropdown, "LEFT", -8, 0)
	kindDropdown:SetShown(SHOWS_TYPES)

	createTabs()
	createTiles()
	createFlow()
	createCards()

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

	headerBar = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	headerBar:SetPoint("BOTTOMLEFT", scrollBox, "TOPLEFT", 0, 0)
	headerBar:SetPoint("BOTTOMRIGHT", scrollBox, "TOPRIGHT", 0, 0)
	headerBar:SetHeight(HEADER_HEIGHT)
	headerBar:SetColorTexture(0, 0, 0, 0.5)

	empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	empty:SetPoint("CENTER", scrollBox, "CENTER")
	empty:SetWidth(WIDTH - 200)
	empty:SetText(NO_CRAFTS)

	local export = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	export:SetText("Export")
	export:SetSize(export:GetFontString():GetUnboundedStringWidth() + 24, 22)
	export:SetPoint("BOTTOMRIGHT", -SIDE + 4, 6)
	export:SetScript("OnClick", showExport)

	local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	clear:SetText("Clear")
	clear:SetSize(clear:GetFontString():GetUnboundedStringWidth() + 24, 22)
	clear:SetPoint("RIGHT", export, "LEFT", -6, 0)
	clear:SetScript("OnClick", function() StaticPopup_Show("CRAFTONOMICS_CLEAR_LEDGER") end)

	local check = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	check:SetText("Check what I have")
	check:SetSize(check:GetFontString():GetUnboundedStringWidth() + 24, 22)
	check:SetPoint("RIGHT", clear, "LEFT", -6, 0)
	check:SetScript("OnClick", checkOwned)
	check:SetScript("OnEnter", showCheckTip)
	check:SetScript("OnLeave", GameTooltip_Hide)

	footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	footer:SetPoint("BOTTOMLEFT", SIDE + 4, 10)

	local info = CreateFrame("Button", nil, frame)
	info:SetSize(20, 20)
	info:SetPoint("LEFT", footer, "RIGHT", 6, 0)
	info:SetNormalTexture(INFO_ICON)
	info:SetScript("OnEnter", showNote)
	info:SetScript("OnLeave", GameTooltip_Hide)

	-- Item names arrive from the server after first use.
	frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	frame:SetScript("OnEvent", refresh)
	-- Only the packed records stay when it closes.
	frame:SetScript("OnHide", function()
		crafts, other, bought = nil, nil, nil
		scrollBox:SetDataProvider(CreateDataProvider({}))
		GameTooltip:Hide()
	end)
	ns.Ledger.Watch(reload)
end

function LedgerWindow.Show()
	if not frame then create() end
	crafts, other, bought = ns.Ledger.Load()
	-- It opens on the character you're on, when it has anything on record;
	-- All characters is one pick away.
	local _, mine = ns.Ranks.Me()
	characterFilter = mine and tContains(distinct("character"), mine) and mine or nil
	frame:Show()
	LedgerWindow.Render()
end

-- Testing (/craftonomics testledger): made-up records in the window, or back to
-- yours. Nothing is saved.
function LedgerWindow.ToggleDemo()
	local on = ns.Ledger.ToggleDemo()
	LedgerWindow.Show()
	return on
end

function LedgerWindow.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		LedgerWindow.Show()
	end
end
