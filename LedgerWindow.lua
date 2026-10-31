-- Craft Profit: the Ledger window. Overview, every craft, how each item did, from the
-- records in Ledger.lua. They're unpacked when it opens and let go when it closes.
local _, ns = ...

local LedgerWindow = {}
ns.LedgerWindow = LedgerWindow

local Color, Money = ns.Color, ns.Format.Money
local format = string.format

local WIDTH, HEIGHT = 1240, 660
local SIDE = 12             -- window edge to its content
local FILTERS_TOP = 30      -- window top to the filters
local TILES_TOP = 62        -- window top to the totals
local TILE_HEIGHT = 54
local TILE_GAP = 6
local INSET_TOP = 124       -- window top to the table's box
local INSET_PAD = 8         -- that box's edge to what's in it
local SCROLLBAR_ROOM = 20
local CHART_HEIGHT = 104
local HEADER_HEIGHT = 22
local ROW_HEIGHT = 24
local ICON_SIZE = 20
local CELL_GAP = 8
local TAB_PADDING = 16      -- room beside a tab's label, so it's never cut short
local TAB_KEYS = { "overview", "crafts", "items", "bought" }
local TAB_LABELS = { "Overview", "Crafts", "Performance", "Purchased" }
local TILE_LABELS = { "Profit so far", "Sold for", "Spent on materials", "Forecast off by", "Not sold yet" }
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
local MAX_BARS = 90         -- the chart's bars; longer ranges share a bar between days
local BAR_WIDTH = 18        -- at most, so a few days don't make wide blocks
local CHART_LABEL_ROOM = 20 -- under the bars, for the dates
local CHART_TOP_ROOM = 8    -- over the tallest bar
local MISSES_SHOWN = 5      -- items on the Overview's "furthest below forecast"
local DAY = 86400
local RANGES = { { 7, "Last 7 days" }, { 30, "Last 30 days" }, { 90, "Last 90 days" } }
local KIND_SHORT = { craft = "Regular", patron = "Patron", personal = "Personal", guild = "Guild", public = "Public" }
local NO_CRAFTS = "Nothing here yet. Crafts are recorded from now on, with what the panel forecast for them."
local NO_BOUGHT = "Nothing here yet. What you buy on the auction house, and materials from vendors, are recorded from now on."
local MATCH_NOTE = "A sale counts toward your oldest unsold craft of that item and rank, so one craft's result is an estimate. Totals are what really sold."

local frame, scrollBox, headerBar, footer, empty, chart, searchBox, exportFrame
local tiles, headers, bars = {}, {}, {}
local rangeDropdown, characterDropdown, professionDropdown, kindDropdown
local tab = "overview"
local characterFilter, professionFilter, kindFilter -- nil for all
local sorts = { crafts = { key = "time", ascending = false }, items = { key = "earned", ascending = false },
	bought = { key = "spent", ascending = false } }
local crafts, other, bought -- unpacked while the window is open
local refreshQueued = false

local function signedMoney(amount)
	return Color(ns.AmountColor(amount), (amount > 0 and "+" or "") .. Money(amount))
end

local function plainMoney(amount, color)
	if not amount or amount == 0 then return Color("muted", "-") end
	return color and Color(color, Money(amount)) or Money(amount)
end

local function signedOrDash(amount)
	return amount and signedMoney(amount) or Color("muted", "-")
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
	if entry.recipeID and entry.recipeID > 0 then
		icon = ns.Blizzard.ItemQualityMarkup(entry.recipeID, entry.rank)
	elseif entry.itemID then
		icon = ns.Blizzard.ReagentQualityMarkup(entry.itemID)
	end
	return " " .. (icon or ("rank " .. entry.rank))
end

-- The crafts the filters leave, oldest first.
local function inView()
	local since = time() - ns.db.ledgerRange * DAY
	local search = searchBox:GetText():lower()
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
	local since = time() - ns.db.ledgerRange * DAY
	local search = searchBox:GetText():lower()
	local list = {}
	for _, entry in ipairs(bought or {}) do
		if entry.t >= since and (not characterFilter or entry.character == characterFilter)
			and (search == "" or entry.name:lower():find(search, 1, true)) then
			list[#list + 1] = entry
		end
	end
	return list
end

-- Totals for each value of craft[field], biggest profit first; names are worked out by `label`.
local function groupRows(list, field, label)
	local groups, order = {}, {}
	for _, craft in ipairs(list) do
		local value = craft[field] or "?"
		if not groups[value] then
			groups[value] = {}
			order[#order + 1] = value
		end
		local group = groups[value]
		group[#group + 1] = craft
	end
	local rows = {}
	for _, value in ipairs(order) do
		local row = ns.Ledger.Summarize(groups[value])
		row.label = label and label(value) or value
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b) return a.earned > b.earned end)
	return rows
end

local function addHeading(rows, text)
	rows[#rows + 1] = { heading = text }
end

local function addAll(rows, list)
	for _, row in ipairs(list) do rows[#rows + 1] = row end
end

local function overviewRows(list)
	local rows = {}
	addHeading(rows, "By type")
	addAll(rows, groupRows(list, "kind", function(kind) return ns.Ledger.KINDS[kind] or kind end))
	addHeading(rows, "By profession")
	addAll(rows, groupRows(list, "profession"))
	addHeading(rows, "By character")
	addAll(rows, groupRows(list, "character", ns.Ranks.CharacterName))

	local missed = {}
	for _, item in ipairs(ns.Ledger.Items(list)) do
		local off = ns.Ledger.Off(item)
		if off and off < 0 then
			item.off = off
			item.label = format("%s%s %s", nameOf(item), rankMarkup(item), Color("muted", KIND_SHORT[item.kind] or item.kind))
			missed[#missed + 1] = item
		end
	end
	if #missed > 0 then
		table.sort(missed, function(a, b) return a.actual - a.forecast < b.actual - b.forecast end)
		addHeading(rows, "Furthest below forecast")
		for i = 1, math.min(MISSES_SHOWN, #missed) do rows[#rows + 1] = missed[i] end
	end

	return rows
end

---------------------------------------------------------------------------
-- Columns: the first is the name; the others are key, header, width, text and,
-- for sorting, sort (what it sorts by; rows' field or function)
---------------------------------------------------------------------------

local function craftStatus(craft)
	if craft.kind ~= "craft" then return Color("good", "Paid") end
	if not craft.itemID then return Color("muted", "Nothing to sell") end
	if craft.left == 0 then
		if craft.sold > 0 then return Color("good", craft.used > 0 and "Sold and used" or "Sold") end
		return Color("good", "Used")
	end
	if craft.sold + craft.used > 0 then return format("%d of %d sold", craft.sold + craft.used, craft.qty) end
	return Color("missing", "Not sold yet")
end

-- For sorting by status: what still needs selling comes first.
local function statusOrder(craft)
	if craft.kind ~= "craft" then return 1 end
	if not craft.itemID then return 0 end
	if craft.left == 0 then return 2 end
	return craft.sold + craft.used > 0 and 3 or 4
end

-- Paying under your price source is the good direction.
local function vsMarketText(row)
	if not row.vsMarket then return Color("muted", "-") end
	return Color(row.vsMarket <= 0 and "profit" or "loss", format("%+.0f%%", row.vsMarket * 100))
end

local COLUMNS = {
	overview = {
		{ key = "name", header = "" },
		{ key = "crafts", header = "Crafts", width = 60, text = function(row) return count(row.crafts) end },
		{ key = "items", header = "Items", width = 60, text = function(row) return count(row.items) end },
		{ key = "unsold", header = "Unsold", width = 60, text = function(row) return count(row.unsold) end },
		{ key = "pending", header = "Unsold value", width = 110, text = function(row) return plainMoney(row.pending) end },
		{ key = "expected", header = "Forecast", width = 110, text = function(row)
			return (row.expected or 0) ~= 0 and signedMoney(row.expected) or Color("muted", "-") end },
		{ key = "off", header = "Off by", width = 60, text = function(row) return offText(ns.Ledger.Off(row)) end },
		{ key = "earned", header = "Profit so far", width = 120, text = function(row) return signedMoney(row.earned) end },
	},
	crafts = {
		{ key = "name", header = "Item", sort = function(row) return nameOf(row):lower() end },
		{ key = "time", header = "When", width = 96, sort = "t", text = function(row) return date("%b %d %H:%M", row.t) end },
		{ key = "crafter", header = "Crafter", width = 84, sort = "character",
			text = function(row) return ns.Ranks.CharacterName(row.character or "?") end },
		{ key = "kind", header = "Type", width = 60, sort = "kind", text = function(row) return KIND_SHORT[row.kind] or row.kind end },
		{ key = "qty", header = "Made", width = 44, sort = "qty", text = function(row) return count(row.qty) end },
		{ key = "status", header = "Status", width = 96, sort = statusOrder, text = craftStatus },
		{ key = "forecast", header = "Forecast", width = 104, sort = "forecast", text = function(row)
			return row.forecast ~= 0 and signedMoney(row.forecast) or Color("muted", "-") end },
		{ key = "earned", header = "Profit so far", width = 110, sort = "earned", text = function(row) return signedMoney(row.earned) end },
	},
	items = {
		{ key = "name", header = "Item", sort = function(row) return nameOf(row):lower() end },
		{ key = "kind", header = "Type", width = 60, sort = "kind", text = function(row) return KIND_SHORT[row.kind] or row.kind end },
		{ key = "items", header = "Made", width = 46, sort = "items", text = function(row) return count(row.items) end },
		{ key = "sold", header = "Sold", width = 46, sort = "sold", text = function(row) return count(row.sold) end },
		{ key = "unitForecast", header = "Forecast each", width = 90, sort = "unitForecast",
			text = function(row) return signedOrDash(row.unitForecast) end },
		{ key = "unitCost", header = "Cost each", width = 76, sort = "unitCost",
			text = function(row) return plainMoney(row.unitCost, "loss") end },
		{ key = "unitSold", header = "Sold each", width = 76, sort = "unitSold",
			text = function(row) return plainMoney(row.unitSold) end },
		{ key = "unitProfit", header = "Profit each", width = 76, sort = "unitProfit",
			text = function(row) return signedOrDash(row.unitProfit) end },
		{ key = "off", header = "Off by", width = 54, sort = function(row) return ns.Ledger.Off(row) end,
			text = function(row) return offText(ns.Ledger.Off(row)) end },
		{ key = "margin", header = "Margin", width = 54, sort = "margin", text = function(row) return marginText(row.margin) end },
		{ key = "days", header = "Days to sell", width = 76, sort = "days", text = function(row)
			return row.days and format("%.1f", row.days) or Color("muted", "-") end },
		{ key = "earned", header = "Profit so far", width = 96, sort = "earned", text = function(row) return signedMoney(row.earned) end },
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

-- Where each column sits in a row `width` wide; the name takes what the others leave.
local function columnPlaces(columns, width)
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

local function sortRows(rows)
	local sort = sorts[tab]
	if not sort then return end
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
		if av == bv or av == nil then return (a.t or 0) > (b.t or 0) end
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

local function craftTooltip(craft)
	GameTooltip:SetText(nameOf(craft) .. rankMarkup(craft))
	addPair("Crafted", date("%b %d %Y, %H:%M", craft.t))
	addPair("Crafter", ns.Ranks.CharacterName(craft.character or "?"))
	addPair("Type", ns.Ledger.KINDS[craft.kind] or craft.kind)
	if craft.count > 1 then addPair("Crafts", craft.count) end
	addPair("Made", craft.qty)
	addPair("Materials cost", Money(craft.cost))
	if craft.forecast ~= 0 then addPair("Forecast on the panel", signedMoney(craft.forecast)) end
	if craft.kind == "craft" and craft.itemID then
		if craft.unit > 0 then addPair("Worth each when crafted", Money(craft.unit)) end
		if craft.sold > 0 then
			addPair("Sold", format("%d for %s", craft.sold, Money(craft.money)))
			addPair("Sold each", Money(craft.money / craft.sold))
		end
		if craft.used > 0 then addPair("Used in your crafts", craft.used) end
		if craft.left > 0 then addPair("Not sold yet", craft.left) end
	elseif craft.kind ~= "craft" then
		addPair("Paid", Money(craft.money))
	end
	addPair("Profit so far", signedMoney(craft.earned))
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(MATCH_NOTE, 0.53, 0.53, 0.53, true)
end

local function itemTooltip(item)
	GameTooltip:SetText(nameOf(item) .. rankMarkup(item))
	addPair("Type", ns.Ledger.KINDS[item.kind] or item.kind)
	addPair("Made", item.items)
	addPair("Sold", item.sold)
	addPair("Not sold yet", item.unsold)
	addPair("Materials cost", Money(item.cost))
	if item.pending > 0 then addPair("Unsold value when crafted", Money(item.pending)) end
	if item.unitPrice then
		addPair(item.kind == "craft" and "Expected sale price each" or "Expected pay each", Money(item.unitPrice))
	end
	addPair("Profit so far", signedMoney(item.earned))
	if item.margin then addPair("Margin on what sold", marginText(item.margin)) end
	if item.forecast ~= 0 then
		addPair("Forecast for what's done", signedMoney(item.forecast))
		addPair("Off by", offText(ns.Ledger.Off(item)))
	end
end

local function boughtTooltip(row)
	GameTooltip:SetText(nameOf(row) .. rankMarkup(row))
	addPair("Purchased", row.qty)
	addPair("From", row.source == "vendor" and "Vendors" or "The auction house")
	addPair("Spent", Money(row.spent))
	addPair("Paid each", Money(row.unitPaid))
	if row.unitMarket then addPair("Your price source then", Money(row.unitMarket)) end
	if row.resold > 0 then
		addPair("Resold", format("%d for %s", row.resold, Money(row.resoldMoney)))
		addPair("Resale profit", signedMoney(row.resaleProfit))
	end
end

local function showRowTooltip(button)
	local row = button.row
	if tab == "overview" or row.heading then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if tab == "crafts" then
		craftTooltip(row)
	elseif tab == "items" then
		itemTooltip(row)
	else
		boughtTooltip(row)
	end
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
	button.rule = button:CreateTexture(nil, "ARTWORK")
	button.rule:SetHeight(1)
	button.rule:SetPoint("BOTTOMLEFT", 4, 1)
	button.rule:SetPoint("BOTTOMRIGHT", -4, 1)
	button.rule:SetColorTexture(1, 0.82, 0, 0.3)
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
	local columns = COLUMNS[tab]
	local places = columnPlaces(columns, scrollBox:GetWidth())
	for i, cell in ipairs(button.cells) do cell:SetShown(i <= #columns) end
	for i, column in ipairs(columns) do
		local cell = cellOf(button, i)
		cell:Show()
		cell:ClearAllPoints()
		cell:SetPoint("LEFT", button, "LEFT", places[i].x, 0)
		cell:SetWidth(places[i].width)
		cell:SetJustifyH(i == 1 and "LEFT" or "RIGHT")
		if row.heading then
			cell:SetText("")
		elseif i > 1 then
			cell:SetText(column.text(row))
		end
	end

	button.stripe:SetShown(row.stripe == true)
	button.rule:SetShown(row.heading ~= nil)
	local first = button.cells[1]
	local hasItem = row.itemID ~= nil
	button.icon:SetShown(hasItem)
	if row.heading then
		first:ClearAllPoints()
		first:SetPoint("LEFT", button, "LEFT", 4, 0)
		first:SetWidth(places[1].x + places[1].width - 4)
		first:SetText(Color("heading", row.heading))
	elseif row.label then
		first:SetText(row.label)
	else
		first:SetText(ns.Format.RarityColored(row.itemID, nameOf(row)) .. rankMarkup(row))
	end
	if hasItem then button.icon:SetTexture(C_Item.GetItemIconByID(row.itemID)) end
end

---------------------------------------------------------------------------
-- The chart: profit by the day it was crafted
---------------------------------------------------------------------------

local function barOf(index)
	local bar = bars[index]
	if not bar then
		bar = CreateFrame("Frame", nil, chart)
		bar:EnableMouse(true)
		bar.fill = bar:CreateTexture(nil, "ARTWORK")
		bar:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.label)
			GameTooltip:AddLine(signedMoney(self.amount), 1, 1, 1)
			GameTooltip:Show()
		end)
		bar:SetScript("OnLeave", GameTooltip_Hide)
		bars[index] = bar
	end
	return bar
end

local function drawChart(list)
	for _, bar in ipairs(bars) do bar:Hide() end
	local now = time()
	local days = ns.db.ledgerRange
	local perBar = math.max(math.ceil(days / MAX_BARS), 1)
	local total = math.ceil(days / perBar)
	local amounts = {}
	for _, craft in ipairs(list) do
		local back = math.floor((now - craft.t) / (DAY * perBar))
		local index = total - math.min(back, total - 1)
		amounts[index] = (amounts[index] or 0) + craft.earned
	end
	-- The zero line sits as low as the losses allow, so the bars get all the height.
	local highest, lowest = 0, 0
	for _, amount in pairs(amounts) do
		highest, lowest = math.max(highest, amount), math.min(lowest, amount)
	end
	local spread = math.max(highest - lowest, 1)

	local width, height = chart:GetWidth(), chart:GetHeight() - CHART_LABEL_ROOM - CHART_TOP_ROOM
	local slot = width / total
	local zero = -lowest / spread * height
	chart.zero:ClearAllPoints()
	chart.zero:SetPoint("LEFT", chart, "BOTTOMLEFT", 0, CHART_LABEL_ROOM + zero)
	chart.zero:SetPoint("RIGHT", chart, "BOTTOMRIGHT", 0, CHART_LABEL_ROOM + zero)
	chart.top:SetText(highest > 0 and format("Best %s: %s", perBar == 1 and "day" or "stretch", signedMoney(highest)) or "")
	for index = 1, total do
		local amount = amounts[index]
		if amount then
			local bar = barOf(index)
			local size = math.max(math.abs(amount) / spread * height, 1)
			bar:ClearAllPoints()
			bar:SetSize(math.max(slot - 2, 1), height)
			bar:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", (index - 1) * slot + 1, CHART_LABEL_ROOM)
			bar.fill:ClearAllPoints()
			bar.fill:SetSize(math.min(math.max(slot - 2, 1), BAR_WIDTH), size)
			bar.fill:SetPoint(amount >= 0 and "BOTTOM" or "TOP", bar, "BOTTOM", 0, zero)
			if amount >= 0 then bar.fill:SetColorTexture(0.3, 0.72, 0.36, 0.95) else bar.fill:SetColorTexture(0.82, 0.3, 0.28, 0.95) end
			local last = now - (total - index) * perBar * DAY
			bar.label = perBar == 1 and date("%b %d", last)
				or format("%s - %s", date("%b %d", last - (perBar - 1) * DAY), date("%b %d", last))
			bar.amount = amount
			bar:Show()
		end
	end
	chart.first:SetText(date("%b %d", now - (days - 1) * DAY))
	chart.last:SetText(Color("muted", "Today"))
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
		header:ClearAllPoints()
		header:SetPoint("BOTTOMLEFT", scrollBox, "TOPLEFT", places[i].x, 0)
		header:SetSize(places[i].width, HEADER_HEIGHT)
		header.sortKey = sort and column.sort and column.key or nil
		header.text:SetJustifyH(i == 1 and "LEFT" or "RIGHT")
		local sorted = sort and sort.key == column.key
		header.text:SetText(sorted and Color("heading", column.header) or column.header)
		header.arrow:SetShown(sorted == true)
		if sorted then
			if sort.ascending then header.arrow:SetTexCoord(0, 1, 1, 0) else header.arrow:SetTexCoord(0, 1, 0, 1) end
			header.arrow:ClearAllPoints()
			local textWidth = header.text:GetStringWidth()
			if i == 1 then
				header.arrow:SetPoint("LEFT", header, "LEFT", textWidth + 3, 0)
			else
				header.arrow:SetPoint("RIGHT", header, "RIGHT", -textWidth - 3, 0)
			end
		end
		header:Show()
	end
end

local function drawTiles(total, spent)
	local off = ns.Ledger.Off(total)
	local values = {
		signedMoney(total.earned),
		Money(total.money),
		Color("loss", Money(total.cost)),
		offText(off),
		Money(total.pending),
	}
	local notes = {
		"Orders when they're done, regular crafts as they sell, each minus its materials.",
		format("%s items: what sold on the auction house, after its cut, and what orders paid.", BreakUpLargeNumbers(total.sold)),
		"What the materials in these crafts were worth when you crafted them, whether you bought or gathered them."
			.. (spent and format("\n\nPurchased in this time: %s. That isn't added on top, or what you buy and then use would count twice.",
				Money(spent)) or ""),
		off and format("What's done made %s, against %s forecast on the panel.", signedMoney(total.actual), signedMoney(total.forecast))
			or "Nothing to compare yet: this fills in as things sell.",
		format("%s items, at what they were worth when crafted.", BreakUpLargeNumbers(total.unsold)),
	}
	for index, tile in ipairs(tiles) do
		tile.value:SetText(values[index])
		tile.note = notes[index]
	end
end

local function showNote(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("How this is worked out")
	GameTooltip:AddLine(MATCH_NOTE, 1, 1, 1, true)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Forecasts and prices use your price options, as they were when each craft or purchase was recorded, so they don't change later.", 1, 1, 1, true)
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
	local list = inView()
	local total = ns.Ledger.Summarize(list)
	local purchases = boughtInView()
	-- Purchases have no profession or type, so with one picked there's no sum.
	local spent = not (professionFilter or kindFilter) and 0 or nil
	if spent then
		for _, entry in ipairs(purchases) do spent = spent + entry.spent end
	end
	drawTiles(total, spent)
	footer:SetText(Color("muted", format("%s crafts, %s items · Prices: %s", BreakUpLargeNumbers(total.crafts),
		BreakUpLargeNumbers(total.items), ns.Prices.SourceLabel())))
	empty:SetText(tab == "bought" and NO_BOUGHT or NO_CRAFTS)
	empty:SetShown(#(tab == "bought" and (bought or {}) or crafts or {}) == 0)

	local overview = tab == "overview"
	chart:SetShown(overview)
	searchBox:SetShown(not overview)
	scrollBox:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", INSET_PAD,
		-(INSET_PAD + HEADER_HEIGHT + (overview and CHART_HEIGHT or 0)))
	PanelTemplates_SetTab(frame, tIndexOf(TAB_KEYS, tab))
	-- The selected tab's label uses a smaller font: a width measured then would cut
	-- it short once another tab is picked, so all of them measure again each time.
	for _, button in ipairs(frame.Tabs) do PanelTemplates_TabResize(button, TAB_PADDING) end
	local rows
	if overview then
		drawChart(list)
		rows = overviewRows(list)
	elseif tab == "crafts" then
		rows = ns.Ledger.Merge(list)
		sortRows(rows)
	elseif tab == "items" then
		rows = ns.Ledger.Items(list)
		sortRows(rows)
	else
		rows = ns.Ledger.BoughtItems(purchases)
		sortRows(rows)
	end
	for index, row in ipairs(rows) do row.stripe = index % 2 == 0 and not row.heading end
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

-- New records while it's open: unpack again.
local function reload()
	if not (frame and frame:IsShown()) then return end
	crafts, other, bought = ns.Ledger.Load()
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

local function exportText()
	local lines = { "Date,Character,Profession,Item,Rank,Type,Made,Sold,Unsold,Materials cost (gold),Forecast (gold),Sold for (gold),Profit so far (gold)" }
	local function gold(amount) return format("%.2f", amount / 10000) end
	for _, craft in ipairs(inView()) do
		lines[#lines + 1] = table.concat({ date("%Y-%m-%d %H:%M", craft.t), csvField(craft.character or "?"),
			csvField(craft.profession or "?"), csvField(nameOf(craft)), craft.rank, KIND_SHORT[craft.kind] or craft.kind,
			craft.qty, craft.sold, craft.left, gold(craft.cost), gold(craft.forecast), gold(craft.money), gold(craft.earned) }, ",")
	end
	return table.concat(lines, "\n")
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

local function distinct(field)
	local seen, list = {}, {}
	for _, craft in ipairs(crafts or {}) do
		local value = craft[field]
		if value and value ~= "?" and not seen[value] then
			seen[value] = true
			list[#list + 1] = value
		end
	end
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

local function createTiles()
	local count = #TILE_LABELS
	local width = (WIDTH - 2 * SIDE - (count - 1) * TILE_GAP) / count
	for index, label in ipairs(TILE_LABELS) do
		local tile = CreateFrame("Frame", nil, frame)
		tile:SetSize(width, TILE_HEIGHT)
		tile:SetPoint("TOPLEFT", SIDE + (index - 1) * (width + TILE_GAP), -TILES_TOP)
		local back = tile:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(0, 0, 0, 0.45)
		local edge = tile:CreateTexture(nil, "ARTWORK")
		edge:SetHeight(2)
		edge:SetPoint("TOPLEFT")
		edge:SetPoint("TOPRIGHT")
		edge:SetColorTexture(1, 0.82, 0, 0.5)
		local name = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		name:SetPoint("TOPLEFT", 10, -9)
		name:SetText(label)
		tile.value = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		tile.value:SetPoint("BOTTOMLEFT", 10, 8)
		tile.value:SetPoint("BOTTOMRIGHT", -6, 8)
		tile.value:SetJustifyH("LEFT")
		tile.value:SetWordWrap(false)
		tile.value:SetTextColor(1, 1, 1)
		tile:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(label)
			GameTooltip:AddLine(self.note, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		tile:SetScript("OnLeave", GameTooltip_Hide)
		tiles[index] = tile
	end
end

local function createChart()
	chart = CreateFrame("Frame", nil, frame)
	chart:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", INSET_PAD, -INSET_PAD)
	chart:SetPoint("TOPRIGHT", frame.Inset, "TOPRIGHT", -INSET_PAD, -INSET_PAD)
	chart:SetHeight(CHART_HEIGHT - 8)
	local back = chart:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.3)
	chart.zero = chart:CreateTexture(nil, "BORDER")
	chart.zero:SetColorTexture(1, 1, 1, 0.15)
	chart.zero:SetHeight(1)
	chart.top = chart:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	chart.top:SetPoint("TOPLEFT", 6, -4)
	chart.first = chart:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	chart.first:SetPoint("BOTTOMLEFT", 6, 3)
	chart.last = chart:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	chart.last:SetPoint("BOTTOMRIGHT", -6, 3)
	local label = chart:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	label:SetPoint("BOTTOM", 0, 3)
	label:SetText("Profit so far, by the day it was crafted")
end

local function create()
	frame = CreateFrame("Frame", "CraftProfitLedger", UIParent, "ButtonFrameTemplate")
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
	tinsert(UISpecialFrames, "CraftProfitLedger")
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

	createTabs()
	createTiles()
	createChart()

	scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
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
	frame:Show()
	LedgerWindow.Render()
end

-- Testing (/craftprofit testledger): made-up records in the window, or back to
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
