-- Craft Profit: the Patron tab of the crafting orders page. Blizzard's own order
-- list gets Craft Profit's columns in the room of three of its own (Patron Name,
-- Commission, Reagents): Profit, Rewards, Materials and Actions. Actions has a
-- button to shop for what's missing and one to start, craft and complete the
-- order. Above the list, buttons add what's missing for the profitable
-- orders or all of them; under it, the concentration they use, the session
-- total and a menu of the list's choices.
local _, ns = ...

local Patron = {}
ns.Patron = Patron

local format = string.format
local COLUMNS = ns.Blizzard.ORDER_COLUMNS

local ICON_SIZE = 20        -- recipe icons in tooltips
local ACTION_SIZE = 18      -- the buttons in the Actions column
local ACTION_GAP = 6        -- between them
local REWARD_SIZE = 16      -- reward icons in the Rewards column
local REWARD_GAP = 6        -- between one reward and the next
local MAX_REWARDS = 4       -- reward icons a row has room for
local FOOTER_HEIGHT = 28    -- room under the rows for the footer
local GEAR_SIZE = 16
-- Our columns, in the room Blizzard's Patron Name, Commission, Reagents and
-- time left columns take together. Time left is Blizzard's own cell and header,
-- moved. Whatever room is left goes evenly between them.
local LAYOUT = {
	{ key = "materials", width = 90 },
	{ key = "rewards", width = 115 },
	{ key = "profit", width = 115 },
	{ key = "time", width = 45 },
	{ key = "actions", width = 70 },
}
-- That room, until the list can say, and how far Blizzard's header text sits
-- in from its edge, until it can be measured on screen.
local DEFAULT_AREA_WIDTH = 500
local DEFAULT_HEADER_INSET = 8
-- The picture on each action button: the first atlas the game has, or else the
-- file. Item icons are cropped to hide their border. The craft button's picture
-- shows the order's next step (see Craft.Step).
local ACTION_ICONS = {
	claim = { file = "Interface\\Icons\\INV_Scroll_03" },                -- a scroll: take the order
	craft = { atlases = { "Cursor_Repair_32", "worldquest-icon-blacksmithing" },
		file = "Interface\\Icons\\Trade_BlackSmithing" },                 -- the hammer
	crafting = { file = "Interface\\Icons\\INV_Misc_PocketWatch_01" },   -- a watch: wait for the cast
	complete = { file = "Interface\\Icons\\INV_Misc_Coin_01" },          -- coins: hand it in for the rewards
	shop = { atlases = { "Perks-ShoppingCart", "Banker" }, file = "Interface\\Icons\\INV_Misc_Bag_10" }, -- shopping
}
local ICON_CROP = { 0.08, 0.92, 0.08, 0.92 }

local function setActionIcon(button, name)
	local icon = ACTION_ICONS[name]
	for _, atlas in ipairs(icon.atlases or {}) do
		if C_Texture.GetAtlasInfo(atlas) then
			button:SetNormalAtlas(atlas)
			return
		end
	end
	button:SetNormalTexture(icon.file)
	button:GetNormalTexture():SetTexCoord(unpack(ICON_CROP))
end

-- Where each of our columns starts, from the left of the room they share
-- (`width` wide): key -> x.
local function columnStarts(width)
	local used = 0
	for _, column in ipairs(LAYOUT) do used = used + column.width end
	local gap = math.max(0, (width - used) / (#LAYOUT - 1))
	local starts, x = {}, 0
	for _, column in ipairs(LAYOUT) do
		starts[column.key] = x
		x = x + column.width + gap
	end
	return starts
end

-- "1 patron order", "5 patron orders".
local function ordersText(count)
	return format("%d patron order%s", count, count == 1 and "" or "s")
end

-- "+12g 50s" in green, "-3g" in red.
local function signedMoney(amount)
	return ns.Color(ns.AmountColor(amount), (amount > 0 and "+" or "") .. ns.Format.Money(amount))
end

local function iconText(icon, size)
	return icon and format("|T%s:%d|t ", icon, size or ICON_SIZE) or ""
end

-- Green check for an order you have everything for.
local READY_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"

---------------------------------------------------------------------------
-- The orders and what they're worth
---------------------------------------------------------------------------

-- The listed orders you can craft, most profitable first: { order, job, model,
-- plan, noConcentration, name, icon }. Also the orders whose recipe you don't
-- know: { order, name, icon }, and your concentration: { have, used } or nil.
local function listOrders()
	local rows, unknown = {}, {}
	-- The order you've started counts until it's complete, even once the game
	-- drops it from the Patron tab.
	local orders, listed = {}, {}
	for _, order in ipairs(ns.Blizzard.PatronOrders() or {}) do
		if not ns.Craft.IsCompleted(order.orderID) then
			orders[#orders + 1] = order
			listed[order.orderID] = true
		end
	end
	local claimed = ns.Craft.ClaimedPatronOrder()
	if claimed and not listed[claimed.orderID] then table.insert(orders, 1, claimed) end

	for _, order in ipairs(orders) do
		local job, name, icon = ns.Blizzard.OrderJob(order)
		if job then
			-- What you supply at its cheapest quality, or for an order with a minimum
			-- quality, the cheapest qualities that reach it.
			local plan = ns.Planner.ForOrder(order, job.schematic, job.provided)
			job.overrides = plan and plan.overrides
			local model = ns.Model.Order({ order = order, schematic = job.schematic, provided = job.provided, overrides = job.overrides })
			rows[#rows + 1] = { order = order, job = job, model = model, plan = plan, name = job.name or "?", icon = job.icon }
		else
			unknown[#unknown + 1] = { order = order, name = name or "?", icon = icon }
		end
	end
	-- Most profitable first, so concentration goes to them; orders you can't craft
	-- go last, since their profit is moot.
	table.sort(rows, function(a, b)
		local aOut, bOut = a.plan and a.plan.unreachable or false, b.plan and b.plan.unreachable or false
		if aOut ~= bOut then return bOut end
		return a.model.total > b.model.total
	end)
	local concentration = ns.Planner.SpendConcentration(rows, ns.db.concentrationFor)
	return rows, unknown, concentration
end

-- What the list shows, worked out by Patron.Redraw: rows and unknown as from
-- listOrders, each also by orderID, and the concentration they use.
local state = { rows = {}, unknown = {}, byID = {}, unknownByID = {} }

-- What each order added to the shopping list this session (orderID -> { { itemID,
-- qty } ... }), so Shift-click can take the same amounts back off.
local added = {}

local function remember(rows)
	-- A TSM search adds nothing to the list, so there's nothing to take back off.
	if ns.Shopping.ListTarget() ~= "auctionator" then return end
	for _, row in ipairs(rows) do
		local list = added[row.order.orderID] or {}
		for _, material in ipairs(row.model.missing) do
			list[#list + 1] = { itemID = material.itemID, qty = material.qty }
		end
		added[row.order.orderID] = list
	end
end

-- What's missing for all of these orders together.
local function missingForAll(rows)
	local jobs = {}
	for i, row in ipairs(rows) do jobs[i] = row.job end
	return ns.Model.MissingForAll(jobs)
end

local function skippedText(skipped)
	return format("Skipped %d order%s whose recipe you don't know.", skipped, skipped == 1 and "" or "s")
end

local function unreachableText(skipped)
	return format("Skipped %d order%s whose minimum quality you can't reach, even with the best materials and concentration.",
		skipped, skipped == 1 and "" or "s")
end

local function shortText(skipped)
	if ns.db.concentrationFor == "none" then
		return format("Skipped %d order%s that need%s concentration (Don't use concentration is picked).",
			skipped, skipped == 1 and "" or "s", skipped == 1 and "s" or "")
	end
	return format("Skipped %d order%s: not enough concentration left for %s.",
		skipped, skipped == 1 and "" or "s", skipped == 1 and "it" or "them")
end

-- The orders you can craft at their minimum quality now, how many you can't
-- reach at all, and how many are short of concentration.
local function reachableRows(rows)
	local list, unreachable, short = {}, 0, 0
	for _, row in ipairs(rows) do
		if row.plan and row.plan.unreachable then
			unreachable = unreachable + 1
		elseif row.noConcentration then
			short = short + 1
		else
			list[#list + 1] = row
		end
	end
	return list, unreachable, short
end

-- The orders worth taking: they make gold, and you can reach their minimum quality.
local function profitableRows(rows)
	local list = {}
	for _, row in ipairs(reachableRows(rows)) do
		if row.model.total > 0 then list[#list + 1] = row end
	end
	return list
end

-- With only TSM, materials go to a TSM search to copy instead of a shopping list:
-- on the Patron tab, one running search (see tsmSearchRows).
local function usingTSM()
	return ns.Shopping.ListTarget() == "tsm"
end

-- Whether you own everything an order needs, in the qualities picked for the most
-- profit: nothing's missing, and the minimum quality is reachable. (The picks
-- already prefer a cheaper rank to buy over one you own when that pays, so
-- nothing missing means nothing worth buying either.)
local function isReady(row)
	if ns.Shopping.Total(row.model.missing) > 0 then return false end
	return not (row.noConcentration or row.plan and row.plan.unreachable)
end

-- An order's minimum quality as its icon, or "rank N".
local function qualityText(row, quality)
	return ns.Blizzard.ItemQualityMarkup(row.order.spellID, quality) or format("rank %d", quality)
end

-- With TSM there's no list to add to, so the Patron tab keeps one running TSM
-- search instead: the orders in it (ns.db.tsmOrders, orderID -> true, emptied at
-- each login). It's worked out from what they're missing now each time it's
-- shown, so what you've bought since drops out.

-- The listed orders in the TSM search.
local function tsmSearchRows()
	local list = {}
	for _, row in ipairs(state.rows) do
		if ns.db.tsmOrders[row.order.orderID] then list[#list + 1] = row end
	end
	return list
end

local function inTSMSearch(row)
	return ns.db.tsmOrders[row.order.orderID] == true
end

-- Shows the TSM search to copy, for every order in it.
local function showTSMSearch()
	local rows = tsmSearchRows()
	if #rows == 0 then
		ns.Shopping.Say("The TSM search is empty.")
		return
	end
	ns.Shopping.AddMissing(missingForAll(rows), ordersText(#rows))
end

local function addToTSMSearch(rows)
	for _, row in ipairs(rows) do ns.db.tsmOrders[row.order.orderID] = true end
	showTSMSearch()
end

local function clearTSMSearch()
	wipe(ns.db.tsmOrders)
	ns.Shopping.Say("Cleared the TSM search.")
end

local function addAll()
	local reachable, unreachable, short = reachableRows(state.rows)
	if usingTSM() then
		addToTSMSearch(reachable)
	else
		ns.Shopping.AddMissing(missingForAll(reachable), ordersText(#reachable))
		remember(reachable)
	end
	if short > 0 then ns.Shopping.Say(ns.Color("muted", shortText(short))) end
	if unreachable > 0 then ns.Shopping.Say(ns.Color("muted", unreachableText(unreachable))) end
	if #state.unknown > 0 then ns.Shopping.Say(ns.Color("muted", skippedText(#state.unknown))) end
end

local function addProfitable()
	local rows = profitableRows(state.rows)
	if usingTSM() then return addToTSMSearch(rows) end
	ns.Shopping.AddMissing(missingForAll(rows), "the " .. ordersText(#rows) .. " that make a profit")
	remember(rows)
end

local function addOrder(row)
	if usingTSM() then return addToTSMSearch({ row }) end
	ns.Shopping.AddMissing(row.model.missing, row.name)
	remember({ row })
end

-- Shift-click: takes off what this order added, or what it's missing now if it
-- added nothing this session. With TSM, takes it out of the search.
local function removeOrder(row)
	if usingTSM() then
		ns.db.tsmOrders[row.order.orderID] = nil
		return showTSMSearch()
	end
	local list = added[row.order.orderID] or row.model.missing
	added[row.order.orderID] = nil
	ns.Shopping.RemoveMissing(list, row.name)
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

-- Whether an order needs concentration while "Spend concentration on" is set
-- to "Don't use concentration": it gets no buttons and isn't shopped for.
local function keptOffConcentration(row)
	return ns.db.concentrationFor == "none" and row.noConcentration == true
end

local KEPT_OFF_TEXT = "Needs %d concentration to reach its minimum quality, and Spend concentration on is set "
	.. "to Don't use concentration."

-- The concentration an order takes, as "[icon]120", or "".
local function concentrationText(row)
	local plan = row.plan
	if not (plan and plan.concentration) or plan.unreachable then return "" end
	local info = plan.currencyID and C_CurrencyInfo.GetCurrencyInfo(plan.currencyID)
	local text = iconText(info and info.iconFileID, 14) .. plan.concentration
	return ns.Color(row.noConcentration and "loss" or "muted", text)
end

-- The Profit cell's tooltip: where the profit comes from.
local function profitTooltip(row)
	local model, plan = row.model, row.plan
	local tooltip = GameTooltip
	local function line(label, amount, signed)
		tooltip:AddDoubleLine(label, signed and signedMoney(amount) or ns.Format.Money(amount), 1, 1, 1, 1, 1, 1)
	end
	GameTooltip_SetTitle(tooltip, iconText(row.icon) .. row.name)
	if row.order.customerName and row.order.customerName ~= "" then
		tooltip:AddLine(row.order.customerName, 0.53, 0.53, 0.53)
	end
	tooltip:AddLine(" ")
	line("Commission (after cut)", model.receive)
	line("Materials you supply", -model.cost, true)
	local rewards = model.total - model.receive + model.cost
	if rewards > 0 then line("Sellable rewards", rewards) end
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine(model.total >= 0 and "Profit" or "Loss", signedMoney(model.total), 1, 0.82, 0, 1, 1, 1)
	if model.notes.missing then
		tooltip:AddLine("Some materials have no price, so the profit is too high.", 1, 0.4, 0.4, true)
	end

	-- The order's minimum quality, and the material qualities picked to reach it.
	if plan and plan.minQuality then
		tooltip:AddLine(" ")
		tooltip:AddLine("Minimum quality " .. qualityText(row, plan.minQuality), 1, 0.82, 0)
		if plan.unreachable then
			tooltip:AddLine("You can't reach it, even with the best materials.", 1, 0.4, 0.4, true)
		elseif keptOffConcentration(row) then
			tooltip:AddLine(format(KEPT_OFF_TEXT, plan.concentration), 1, 0.4, 0.4, true)
			tooltip:AddLine("Using:", 1, 1, 1)
		elseif row.noConcentration then
			tooltip:AddLine(format("Needs %d concentration, but there isn't enough left once the orders worth more get theirs.",
				plan.concentration), 1, 0.4, 0.4, true)
			tooltip:AddLine("Using:", 1, 1, 1)
		elseif plan.concentration then
			tooltip:AddLine(format(ns.db.leastConcentration and "Reached with %d concentration, the least it can take, using:"
				or "Reached with %d concentration, using:", plan.concentration), 1, 1, 1, true)
		else
			tooltip:AddLine("Reached with the cheapest qualities that do it:", 1, 1, 1, true)
		end
		if not plan.unreachable then
			for _, pick in ipairs(plan.picks) do
				tooltip:AddLine(ns.Format.Item(pick.itemID, pick.qty), 1, 1, 1)
			end
		end
	end
end

-- The Materials column's tooltip: what's missing, or why the order can't be crafted.
local function materialsTooltip(row, step)
	local tooltip = GameTooltip
	GameTooltip_SetTitle(tooltip, iconText(row.icon) .. row.name)
	if keptOffConcentration(row) and step ~= "crafting" and step ~= "complete" then
		tooltip:AddLine(format(KEPT_OFF_TEXT, row.plan.concentration), 1, 0.4, 0.4, true)
		local missing = ns.Shopping.Total(row.model.missing)
		if missing > 0 then
			tooltip:AddLine(" ")
			tooltip:AddLine(ns.Color("missing", format("%d missing", missing)))
			for _, material in ipairs(row.model.missing) do
				tooltip:AddLine(ns.Format.Item(material.itemID, material.qty), 1, 1, 1)
			end
		end
		return
	end
	if step == "craft" or step == "crafting" or step == "complete" then
		tooltip:AddLine("You've started this order.", 1, 1, 1)
		tooltip:AddLine(ns.Color("simulated", ns.Craft.StepText(step, row)))
		return
	end
	if row.plan and row.plan.unreachable then
		tooltip:AddLine("You can't reach its minimum quality, even with the best materials.", 1, 0.4, 0.4, true)
		return
	end
	local missing = ns.Shopping.Total(row.model.missing)
	if missing > 0 then
		tooltip:AddLine(ns.Color("missing", format("%d missing", missing)))
		for _, material in ipairs(row.model.missing) do
			tooltip:AddLine(ns.Format.Item(material.itemID, material.qty), 1, 1, 1)
		end
	elseif row.noConcentration then
		tooltip:AddLine("You have the materials, but not enough concentration is left for it once the orders "
			.. "worth more get theirs.", 1, 0.4, 0.4, true)
	else
		tooltip:AddLine(READY_ICON .. " You have everything, in the qualities that make the most profit.", 0.53, 1, 0.53, true)
	end
end

-- The shopping button's tooltip: what a click adds, and what Shift-click takes off.
local function shopTooltip(row)
	local tooltip = GameTooltip
	local tsm = usingTSM()
	GameTooltip_SetTitle(tooltip, tsm and "TSM search" or "Shopping list")
	if tsm and inTSMSearch(row) then tooltip:AddLine("In the TSM search.", 0.53, 1, 0.53) end
	local missing = ns.Shopping.Total(row.model.missing)
	if missing > 0 then
		tooltip:AddLine(ns.Color("missing", format("%d missing", missing)))
		for _, material in ipairs(row.model.missing) do
			tooltip:AddLine(ns.Format.Item(material.itemID, material.qty), 1, 1, 1)
		end
		tooltip:AddLine(" ")
		tooltip:AddLine(ns.Color("simulated", tsm and "Click: add it to the TSM search, and copy the search"
			or format("Click: add what's missing to the \"%s\" list", ns.Shopping.ListName())))
	end
	if tsm and inTSMSearch(row) then
		tooltip:AddLine(ns.Color("simulated", "Shift-click: take it out of the TSM search"))
	elseif added[row.order.orderID] and not tsm then
		tooltip:AddLine(ns.Color("simulated", "Shift-click: remove it from the shopping list"))
	end
end

-- An order's rewards besides the commission: { icon, qty, itemLink or
-- currencyType, knowledge }.
local function rewardsOf(order)
	local list = {}
	for _, reward in ipairs(order.npcOrderRewards or {}) do
		local qty = reward.count or 1
		local itemID, icon
		if reward.itemLink then itemID, _, _, _, icon = C_Item.GetItemInfoInstant(reward.itemLink) end
		if itemID then
			list[#list + 1] = { icon = icon, qty = qty, itemLink = reward.itemLink, itemID = itemID,
				knowledge = ns.KNOWLEDGE_ITEMS[itemID] }
		elseif reward.currencyType then
			local info = C_CurrencyInfo.GetCurrencyInfo(reward.currencyType)
			if info then list[#list + 1] = { icon = info.iconFileID, qty = qty, currencyType = reward.currencyType } end
		end
	end
	return list
end

local function rewardTooltip(button)
	local reward = button.reward
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if reward.itemLink then
		GameTooltip:SetHyperlink(reward.itemLink)
		if reward.knowledge then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(format("%d profession knowledge", reward.knowledge * reward.qty), 0.53, 1, 0.53)
		end
		local price = ns.Prices.Sale(reward.itemLink, reward.itemID)
		if price then
			GameTooltip:AddLine(" ")
			GameTooltip:AddDoubleLine(reward.qty > 1 and format("Worth (%d)", reward.qty) or "Worth",
				ns.Format.Money(price * reward.qty), 1, 0.82, 0, 1, 1, 1)
		end
	else
		GameTooltip:SetCurrencyByID(reward.currencyType, reward.qty)
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Our columns on Blizzard's rows
---------------------------------------------------------------------------

-- Our columns, per row frame of Blizzard's list. Kept here, not on the rows.
local cells = {}
local active = false

local function showRowTooltip(owner, row, fill)
	ns.Blizzard.SetRowHighlight(row, true)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	fill()
	GameTooltip:Show()
end

local function hideRowTooltip(owner, row)
	ns.Blizzard.SetRowHighlight(row, false)
	if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

-- A frame with its own tooltip that passes clicks on to the row (which opens
-- the order).
local function overlay(parent)
	local frame = CreateFrame("Button", nil, parent)
	frame:SetFrameLevel(parent:GetFrameLevel() + 3)
	frame:SetPropagateMouseClicks(true)
	return frame
end

-- The room our columns share on a row, from the start of Patron Name to the end
-- of time left.
local function areaWidth()
	return ns.Blizzard.ColumnSpan(COLUMNS.customer, COLUMNS.expiration) or DEFAULT_AREA_WIDTH
end

local function widthOf(key)
	for _, column in ipairs(LAYOUT) do
		if column.key == key then return column.width end
	end
end

-- Puts `frame` at `x` in `parent`, `width` wide, the full height.
local function place(frame, parent, x, width)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
	frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 0)
	frame:SetWidth(width)
end

-- Puts a row's own columns in place for the room they share.
local function layoutColumns(area, frames)
	local starts = columnStarts(area:GetWidth() > 0 and area:GetWidth() or areaWidth())
	for _, column in ipairs(LAYOUT) do
		local frame = frames[column.key]
		if frame then place(frame, area, starts[column.key], column.width) end
	end
end

-- Blizzard's frames we moved into our columns (its time left cell and header),
-- with where it had put them, to put them back when Craft Profit's columns are
-- turned off. The list lays them out again by itself on another tab.
local moved = setmetatable({}, { __mode = "k" })

local function moveInto(frame, parent, x, width)
	local _, relativeTo = frame:GetPoint(1)
	if relativeTo ~= parent then
		local points = {}
		for i = 1, frame:GetNumPoints() do points[i] = { frame:GetPoint(i) } end
		moved[frame] = { parent = parent, points = points, width = frame:GetWidth() }
	end
	place(frame, parent, x, width)
end

local function putBack(frame)
	local saved = frame and moved[frame]
	if not saved then return end
	moved[frame] = nil
	-- Laid out again by the list since: it's where Blizzard wants it already.
	if select(2, frame:GetPoint(1)) ~= saved.parent then return end
	frame:ClearAllPoints()
	for _, point in ipairs(saved.points) do frame:SetPoint(unpack(point)) end
	frame:SetWidth(saved.width)
end

local function actionButton(parent, row, onClick, fill)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(ACTION_SIZE, ACTION_SIZE)
	button:SetFrameLevel(parent:GetFrameLevel() + 2)
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self) showRowTooltip(self, row, function() fill(self) end) end)
	button:SetScript("OnLeave", function(self) hideRowTooltip(self, row) end)
	return button
end

local function createCells(row)
	local own = {}
	-- The room Blizzard's three replaced columns take, laid over them.
	own.area = CreateFrame("Frame", nil, row)
	own.area:SetFrameLevel(row:GetFrameLevel() + 2)

	own.profit = overlay(own.area)
	own.profit.text = own.profit:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	own.profit.text:SetPoint("LEFT")
	own.profit.text:SetPoint("RIGHT")
	own.profit.text:SetJustifyH("LEFT")
	own.profit.text:SetWordWrap(false)
	own.profit:SetScript("OnEnter", function(self)
		if self.data then showRowTooltip(self, row, function() profitTooltip(self.data) end) end
	end)
	own.profit:SetScript("OnLeave", function(self) hideRowTooltip(self, row) end)

	-- Only the icons take the mouse; the rest of the column is the row's.
	own.rewards = CreateFrame("Frame", nil, own.area)
	own.rewards:SetFrameLevel(own.area:GetFrameLevel() + 1)
	own.rewards.buttons = {}
	for i = 1, MAX_REWARDS do
		local button = overlay(own.rewards)
		button:SetSize(REWARD_SIZE, REWARD_SIZE)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetAllPoints()
		button.icon:SetTexCoord(unpack(ICON_CROP))
		button.count = own.rewards:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		button.count:SetPoint("LEFT", button, "RIGHT", 2, 0)
		button:SetScript("OnEnter", function(self)
			ns.Blizzard.SetRowHighlight(row, true)
			rewardTooltip(self)
		end)
		button:SetScript("OnLeave", function(self) hideRowTooltip(self, row) end)
		own.rewards.buttons[i] = button
	end

	own.materials = overlay(own.area)
	own.materials.text = own.materials:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	own.materials.text:SetPoint("LEFT")
	own.materials.text:SetPoint("RIGHT")
	own.materials.text:SetJustifyH("LEFT")
	own.materials.text:SetWordWrap(false)
	own.materials:SetScript("OnEnter", function(self)
		if self.data then showRowTooltip(self, row, function() materialsTooltip(self.data, self.step) end) end
	end)
	own.materials:SetScript("OnLeave", function(self) hideRowTooltip(self, row) end)

	-- Each button has its own place, so they line up from row to row.
	own.actions = CreateFrame("Frame", nil, own.area)
	own.actions:SetFrameLevel(own.area:GetFrameLevel() + 1)
	own.shop = actionButton(own.actions, row, function(self)
		if IsShiftKeyDown() and (not usingTSM() or inTSMSearch(self.data)) then
			removeOrder(self.data)
		elseif ns.Shopping.Total(self.data.model.missing) > 0 then
			addOrder(self.data)
		end
		Patron.Redraw()
	end, function(self) shopTooltip(self.data) end)
	own.shop:SetPoint("LEFT")
	setActionIcon(own.shop, "shop")
	-- Each click does the order's next step (see Craft.Step).
	own.step = actionButton(own.actions, row, function(self) ns.Craft.Do(self.data, self.step) end, function(self)
		GameTooltip:SetText("Craft this order")
		GameTooltip:AddLine(ns.Color("simulated", ns.Craft.StepText(self.step, self.data)))
		GameTooltip:AddLine("Each click does the next step: start, craft, complete.", 0.53, 0.53, 0.53, true)
	end)
	own.step:SetPoint("LEFT", own.shop, "RIGHT", ACTION_GAP, 0)

	own.area:SetScript("OnSizeChanged", function(area) layoutColumns(area, own) end)
	layoutColumns(own.area, own)
	cells[row] = own
	return own
end

-- Blizzard's cells under ours: hidden while ours show. The list shows them again
-- each time it fills in the row.
local REPLACED = { COLUMNS.customer, COLUMNS.commission, COLUMNS.reagents }

local function showRewards(own, order)
	local rewards = rewardsOf(order)
	local previous
	for i, button in ipairs(own.rewards.buttons) do
		local reward = rewards[i]
		button:SetShown(reward ~= nil)
		button.count:SetShown(reward ~= nil)
		if reward then
			button.reward = reward
			button.icon:SetTexture(reward.icon)
			-- Knowledge in green, like the panel; one of anything else needs no count.
			local count = (reward.qty > 1 or reward.knowledge) and tostring(reward.qty) or ""
			button.count:SetText(reward.knowledge and ns.Color("good", count) or count)
			button:ClearAllPoints()
			if previous then
				-- After the count, or right after the icon when it has none.
				local after = previous.count:GetText() ~= "" and previous.count or previous
				button:SetPoint("LEFT", after, "RIGHT", REWARD_GAP, 0)
			else
				button:SetPoint("LEFT", own.rewards, "LEFT", 0, 0)
			end
			previous = button
		end
	end
end

-- The step an order's craft button does now (see Craft.Step), or nil for no
-- button. Kept off concentration, a started order that needs it isn't crafted
-- from here.
local function shownStep(row)
	local step = ns.Craft.Step(row, isReady(row))
	if step == "craft" and keptOffConcentration(row) then return nil end
	return step
end

-- Whether an order gets the shopping button: only while something's missing (an
-- order you have everything for has nothing to buy, even if it put things on the
-- list before), and not while it has a craft button or is kept off concentration.
local function hasCart(row, step)
	return ns.Shopping.ListTarget() ~= nil and step == nil and not keptOffConcentration(row)
		and ns.Shopping.Total(row.model.missing) > 0
end

-- What a known order's Materials column says.
local function materialsText(row, step)
	if step == "complete" then return ns.Color("good", "Crafted") end
	if step == "crafting" then return ns.Color("good", "Crafting...") end
	if keptOffConcentration(row) then return ns.Color("muted", "No concentration") end
	if step == "craft" then return ns.Color("good", "Started") end
	if row.plan and row.plan.unreachable then return ns.Color("loss", "Can't craft") end
	local missing = ns.Shopping.Total(row.model.missing)
	if missing > 0 then return ns.Color("missing", format("%d missing", missing)) end
	if row.noConcentration then return ns.Color("muted", "No concentration") end
	return READY_ICON .. ns.Color("good", " Ready")
end

-- Fills in our columns on one of Blizzard's rows, or takes them away.
local function drawRow(row)
	local order = active and ns.Blizzard.RowOrder(row)
	local own = cells[row]
	local first = order and ns.Blizzard.RowCell(row, COLUMNS.customer)
	local time = order and ns.Blizzard.RowCell(row, COLUMNS.expiration)
	if not (first and time) then
		if not own then return end
		own.area:Hide()
		-- Turned off with the list on screen: Blizzard's cells back.
		for _, column in ipairs(REPLACED) do
			local cell = ns.Blizzard.RowCell(row, column)
			if cell then cell:Show() end
		end
		putBack(ns.Blizzard.RowCell(row, COLUMNS.expiration))
		return
	end
	own = own or createCells(row)
	for _, column in ipairs(REPLACED) do
		local cell = ns.Blizzard.RowCell(row, column)
		if cell then cell:Hide() end
	end
	own.area:ClearAllPoints()
	own.area:SetPoint("TOPLEFT", first, "TOPLEFT")
	own.area:SetPoint("BOTTOMLEFT", first, "BOTTOMLEFT")
	own.area:SetWidth(areaWidth())
	own.area:Show()
	-- Blizzard's own time left, moved in before Actions.
	moveInto(time, own.area, columnStarts(own.area:GetWidth()).time, widthOf("time"))
	showRewards(own, order)

	local data = state.byID[order.orderID]
	own.profit.data, own.materials.data = data, data
	if not data then
		own.profit.text:SetText(ns.Color("muted", state.unknownByID[order.orderID] and "Recipe not known" or ""))
		own.materials.text:SetText("")
		own.shop:Hide()
		own.step:Hide()
		return
	end

	-- Short of concentration or out of reach: the profit in grey, since you can't take it now.
	local total = data.model.total
	local grey = data.noConcentration or data.plan and data.plan.unreachable
	local profit = grey and ns.Color("muted", (total > 0 and "+" or "") .. ns.Format.Money(total)) or signedMoney(total)
	local concentration = concentrationText(data)
	own.profit.text:SetText(concentration ~= "" and (profit .. "   " .. concentration) or profit)

	local step = shownStep(data)
	own.materials.step = step
	own.materials.text:SetText(materialsText(data, step))

	local tsm = usingTSM()
	own.shop:SetShown(hasCart(data, step))
	own.shop.data = data
	-- Lit while the order is in the TSM search.
	if tsm and inTSMSearch(data) then own.shop:LockHighlight() else own.shop:UnlockHighlight() end
	own.step:SetShown(step ~= nil)
	if step then
		own.step.data, own.step.step = data, step
		setActionIcon(own.step, step)
		-- While the craft is under way there's nothing to click; the tooltip still shows.
		own.step:SetEnabled(step ~= "crafting")
	end
end

---------------------------------------------------------------------------
-- Headers, buttons and footer
---------------------------------------------------------------------------

-- Our headers, in place of Blizzard's three, in its header style. Profit and
-- Actions sort the list; the others don't.
local HEADERS = {
	profit = { text = "Profit", sorts = "profit", tip = "Commission after the cut, plus the rewards that sell, minus the "
		.. "materials you supply, at the qualities that reach the order's minimum quality. The concentration it "
		.. "takes is shown after it." },
	rewards = { text = "Rewards", tip = "What the patron gives besides the commission. Green counts give "
		.. "profession knowledge. Point at one for its value." },
	materials = { text = "Materials", tip = "Whether you have everything for the order, or how much you're missing. "
		.. "Point at it for the list." },
	actions = { text = "Actions", sorts = "actions", tip = "The cart adds what's missing to the shopping list (Shift-click "
		.. "takes it back off). When you have everything, the next button starts, crafts and completes the order, one "
		.. "click per step." },
}
local headerBar, headers

-- Sorting by profit or by what you can do with each order (ns.db.patronSort:
-- "desc" or "asc" profit, "craftable" or "shoppable" first). The game's list is
-- sorted once each time it fills in (`sortedRows` is the list sorted last), not
-- each time the orders change, so the rows don't jump around while you craft
-- and shop.
local sortedRows

-- Where an order goes when sorting by Actions, lowest first: the order you've
-- started and those you have everything for, the ones with a cart, then the
-- rest (no concentration, can't craft). "Shoppable first" swaps the first two.
local function actionRank(row)
	local step = shownStep(row)
	local craftable = step == "craft" or step == "crafting" or step == "complete" or isReady(row)
	local shoppable = hasCart(row, step)
	local started = step ~= nil and step ~= "claim"
	if ns.db.patronSort == "shoppable" then
		if shoppable then return 1 end
		if craftable then return started and 2 or 3 end
		return 4
	end
	if craftable then return started and 1 or 2 end
	if shoppable then return 3 end
	return 4
end

local function sortBefore(a, b)
	local aRow, bRow = state.byID[a.orderID], state.byID[b.orderID]
	-- Orders whose recipe you don't know go last: they have no profit or actions.
	if (aRow ~= nil) ~= (bRow ~= nil) then return aRow ~= nil end
	if aRow then
		local mode = ns.db.patronSort
		if mode == "craftable" or mode == "shoppable" then
			local aRank, bRank = actionRank(aRow), actionRank(bRow)
			if aRank ~= bRank then return aRank < bRank end
		end
		if aRow.model.total ~= bRow.model.total then
			if mode == "asc" then return aRow.model.total < bRow.model.total end
			return aRow.model.total > bRow.model.total
		end
	end
	return a.orderID < b.orderID
end

local function sortList()
	if not ns.db.patronSort then return end
	local rows = ns.Blizzard.OrderListRows()
	if rows and rows ~= sortedRows then
		sortedRows = rows
		ns.Blizzard.SortOrderList(sortBefore)
	end
end

local function setSort(mode)
	ns.db.patronSort = mode
	sortedRows = nil
	Patron.Redraw()
end

-- Clicking a header: Profit is most profit first, then least first, and back;
-- Actions is craftable first, then shoppable first, and back.
local function toggleSort(kind)
	local mode = ns.db.patronSort
	if kind == "profit" then
		setSort(mode == "desc" and "asc" or "desc")
	else
		setSort(mode == "craftable" and "shoppable" or "craftable")
	end
end

-- What a sorting header's tooltip says it does, and what it does now.
local SORT_HINTS = {
	profit = { "Click: sort by profit, most first; again for least first",
		desc = "Sorted: most profit first", asc = "Sorted: least profit first" },
	actions = { "Click: craftable orders first; again for the ones to shop for first",
		craftable = "Sorted: craftable first", shoppable = "Sorted: to shop for first" },
}

local SORT_ICON_SIZE = 14

-- Shows the action button picture `name` (see ACTION_ICONS) on a texture.
local function setIconTexture(texture, name)
	local icon = ACTION_ICONS[name]
	for _, atlas in ipairs(icon.atlases or {}) do
		if C_Texture.GetAtlasInfo(atlas) then
			texture:SetAtlas(atlas)
			texture:SetTexCoord(0, 1, 0, 1)
			return
		end
	end
	texture:SetTexture(icon.file)
	texture:SetTexCoord(unpack(ICON_CROP))
end

-- What our sorting headers show while they sort the list. Profit: Blizzard's
-- arrow, down for most profit first, up for least. Actions: the button it sorts
-- by, the hammer for craftable first or the cart for shoppable first.
local function updateSortArrows()
	if not headers then return end
	local mode = ns.db.patronSort
	local arrow = headers.profit and headers.profit.Arrow
	if arrow then
		arrow:SetShown(mode == "desc" or mode == "asc")
		if mode == "asc" then arrow:SetTexCoord(0, 1, 1, 0) else arrow:SetTexCoord(0, 1, 0, 1) end
	end
	local actions = headers.actions
	if actions then
		if actions.Arrow then actions.Arrow:Hide() end
		if not actions.sortIcon then
			actions.sortIcon = actions:CreateTexture(nil, "OVERLAY")
			actions.sortIcon:SetSize(SORT_ICON_SIZE, SORT_ICON_SIZE)
			actions.sortIcon:SetPoint("LEFT", actions:GetFontString(), "RIGHT", 3, 0)
		end
		local sorting = mode == "craftable" or mode == "shoppable"
		actions.sortIcon:SetShown(sorting)
		if sorting then setIconTexture(actions.sortIcon, mode == "craftable" and "craft" or "shop") end
	end
end

local function createHeaders(parent)
	headerBar = CreateFrame("Frame", nil, parent)
	headers = {}
	for _, column in ipairs(LAYOUT) do
		local info = HEADERS[column.key]
		-- Time left keeps Blizzard's own header, which sorts.
		if info then
			local header = CreateFrame("Button", nil, headerBar, "ProfessionsCrafterTableHeaderStringTemplate")
			header:SetText(info.text)
			if header.Arrow then header.Arrow:Hide() end
			header:SetScript("OnClick", info.sorts and function() toggleSort(info.sorts) end or nil)
			header:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(info.text)
				GameTooltip:AddLine(info.tip, 1, 1, 1, true)
				local hints = info.sorts and SORT_HINTS[info.sorts]
				if hints then
					GameTooltip:AddLine(" ")
					if hints[ns.db.patronSort or ""] then GameTooltip:AddLine(hints[ns.db.patronSort], 0.53, 1, 0.53) end
					GameTooltip:AddLine(ns.Color("simulated", hints[1]))
				end
				GameTooltip:Show()
			end)
			header:SetScript("OnLeave", GameTooltip_Hide)
			headers[column.key] = header
		end
	end
end

-- Measured on screen, once there's something to measure: how far Blizzard's
-- header text sits in from its edge, and where the rows' room for our columns
-- starts from the first replaced header.
local measured = { inset = DEFAULT_HEADER_INSET, left = DEFAULT_HEADER_INSET }

local function measure(first)
	local text = first:IsShown() and first.GetFontString and first:GetFontString()
	if text and text:GetLeft() and first:GetLeft() then measured.inset = text:GetLeft() - first:GetLeft() end
	for _, own in pairs(cells) do
		if own.area:IsVisible() and own.area:GetLeft() and first:GetLeft() then
			measured.left = own.area:GetLeft() - first:GetLeft()
			return
		end
	end
end

-- Lays our headers, and Blizzard's time left header, from the first replaced
-- header to the end of the header row, each one's text above its column.
local function layoutHeaders(first, timeHeader)
	headerBar:ClearAllPoints()
	headerBar:SetPoint("TOPLEFT", first, "TOPLEFT")
	headerBar:SetPoint("BOTTOMRIGHT", first:GetParent(), "BOTTOMRIGHT")
	local barWidth = headerBar:GetWidth()
	local starts = columnStarts(areaWidth())
	-- Side by side like Blizzard's, overlapping a little, the first at Blizzard's first.
	local lefts = {}
	for i, column in ipairs(LAYOUT) do
		lefts[i] = i == 1 and 0 or math.max(0, measured.left + starts[column.key] - measured.inset)
	end
	for i, column in ipairs(LAYOUT) do
		local right = lefts[i + 1] and lefts[i + 1] + 2 or barWidth
		local width = math.max(1, right - lefts[i])
		local header = headers[column.key]
		if header then
			place(header, headerBar, lefts[i], width)
		elseif column.key == "time" then
			moveInto(timeHeader, headerBar, lefts[i], width)
		end
	end
end

local function drawHeaders()
	local first = ns.Blizzard.ColumnHeader(COLUMNS.customer)
	local timeHeader = ns.Blizzard.ColumnHeader(COLUMNS.expiration)
	local shown = active and first ~= nil and timeHeader ~= nil
	if shown then measure(first) end
	for _, column in ipairs(REPLACED) do
		local header = ns.Blizzard.ColumnHeader(column)
		-- Turned off with the list on screen: Blizzard's headers back. (Another tab
		-- lays out its headers itself.)
		if header then header:SetShown(not shown) end
	end
	if not shown then
		putBack(timeHeader)
		if headerBar then
			headerBar:Hide()
			ns.Blizzard.ShowSortArrows(true)
		end
		return
	end
	if not headerBar then createHeaders(first:GetParent()) end
	headerBar:SetFrameLevel(first:GetFrameLevel() + 1)
	headerBar:Show()
	layoutHeaders(first, timeHeader)
	-- Above the bar, so it still takes the clicks that sort by it.
	timeHeader:SetFrameLevel(headerBar:GetFrameLevel() + 2)
	-- Sorted by our headers: only their markers show.
	ns.Blizzard.ShowSortArrows(not ns.db.patronSort)
	updateSortArrows()
end

local addProfitableButton, addAllButton, footer

local function verb()
	return usingTSM() and "Copy" or "Add"
end

local function profitableTooltip(self)
	local rows = profitableRows(state.rows)
	local total = ns.Shopping.Total(missingForAll(rows))
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(verb() .. " profitable orders")
	GameTooltip:AddLine((usingTSM() and "Adds to the TSM search every order" or
		"Adds what you're missing for every order") .. " that makes a profit and whose minimum quality you can reach, at the cheapest qualities that "
		.. "reach it. Orders left without enough concentration are skipped.", 1, 1, 1, true)
	if not usingTSM() then
		GameTooltip:AddLine(format("Goes to Auctionator's \"%s\" shopping list.", ns.Shopping.ListName()), 0.53, 0.53, 0.53, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(format("%s: %s", ordersText(#rows),
		total > 0 and ns.Color("missing", format("%d missing", total)) or "nothing missing"))
	GameTooltip:Show()
end

local function allTooltip(self)
	local reachable, unreachable, short = reachableRows(state.rows)
	local total = ns.Shopping.Total(missingForAll(reachable))
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(verb() .. " all orders")
	GameTooltip:AddLine((usingTSM() and "Adds to the TSM search every order" or
		"Adds what you're missing for every order") .. " whose minimum quality you can reach.", 1, 1, 1, true)
	if not usingTSM() then
		GameTooltip:AddLine(format("Goes to Auctionator's \"%s\" shopping list.", ns.Shopping.ListName()), 0.53, 0.53, 0.53, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(format("%s: %s", ordersText(#reachable),
		total > 0 and ns.Color("missing", format("%d missing", total)) or "nothing missing"))
	if short > 0 then GameTooltip:AddLine(shortText(short), 0.53, 0.53, 0.53, true) end
	if unreachable > 0 then GameTooltip:AddLine(unreachableText(unreachable), 0.53, 0.53, 0.53, true) end
	if #state.unknown > 0 then GameTooltip:AddLine(skippedText(#state.unknown), 0.53, 0.53, 0.53, true) end
	GameTooltip:Show()
end

local function makeButton(parent, onClick, onEnter)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetScript("OnClick", function()
		onClick()
		Patron.Redraw()
	end)
	button:SetScript("OnEnter", onEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetMotionScriptsWhileDisabled(true)
	button:Hide()
	return button
end

local function sizeButton(button, text)
	button:SetText(text)
	button:SetSize(button:GetFontString():GetUnboundedStringWidth() + 32, 22)
end

local function drawButtons()
	local shown = active and ns.Shopping.ListTarget() ~= nil and #state.rows > 0
	addProfitableButton:SetShown(shown)
	addAllButton:SetShown(shown)
	if not shown then return end
	sizeButton(addProfitableButton, verb() .. " profitable")
	sizeButton(addAllButton, verb() .. " all")
	addProfitableButton:SetEnabled(ns.Shopping.Total(missingForAll(profitableRows(state.rows))) > 0)
	addAllButton:SetEnabled(ns.Shopping.Total(missingForAll((reachableRows(state.rows)))) > 0)
end

-- The gear's menu: the list's choices, shopping and the options.
local function openGearMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Patron orders")
		root:CreateTitle("Spend concentration on")
		local function isChosen(key) return ns.db.concentrationFor == key end
		local function choose(key)
			ns.db.concentrationFor = key
			Patron.Redraw()
			return MenuResponse and MenuResponse.Refresh
		end
		for _, choice in ipairs(ns.CONCENTRATION_CHOICES) do
			root:CreateRadio(choice[2], isChosen, choose, choice[1])
		end
		local least = root:CreateCheckbox(ns.LEAST_CONCENTRATION, function() return ns.db.leastConcentration end, function()
			Patron.SetLeastConcentration(not ns.db.leastConcentration)
			return MenuResponse and MenuResponse.Refresh
		end)
		least:SetTooltip(function(tooltip)
			GameTooltip_SetTitle(tooltip, ns.LEAST_CONCENTRATION)
			tooltip:AddLine(ns.LEAST_CONCENTRATION_TIP, 1, 1, 1, true)
			if ns.db.concentrationFor == "none" then
				tooltip:AddLine("Patron orders don't use concentration now (Don't use concentration, above). "
					.. "It still picks the materials on the crafting page.", 1, 0.82, 0, true)
			end
		end)

		ns.Shopping.AddShopWithChoice(root)
		if ns.Shopping.CanClear() then
			root:CreateDivider()
			root:CreateButton("Clear shopping list", ns.Shopping.Clear)
		elseif usingTSM() and #tsmSearchRows() > 0 then
			root:CreateDivider()
			root:CreateButton("Clear TSM search", function()
				clearTSMSearch()
				Patron.Redraw()
			end)
		end
		root:CreateDivider()
		root:CreateButton("Craft Profit options", ns.Options.Open)
	end)
end

local function createFooter()
	local list = ns.Blizzard.OrderList()
	footer = CreateFrame("Frame", nil, list)
	footer:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 10, 3)
	footer:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -32, 3)
	footer:SetHeight(FOOTER_HEIGHT - 4)
	footer:Hide()

	local line = footer:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.15)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", footer, "TOPLEFT", -6, 1)
	line:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 28, 1)

	local gear = CreateFrame("Button", nil, footer)
	gear:SetSize(GEAR_SIZE, GEAR_SIZE)
	gear:SetPoint("LEFT")
	gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	gear:SetScript("OnClick", openGearMenu)
	gear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Craft Profit")
		GameTooltip:AddLine("Which orders get your concentration first, Optimize concentration, shopping and the options.",
			1, 1, 1, true)
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", GameTooltip_Hide)

	footer.concentration = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	footer.concentration:SetPoint("LEFT", gear, "RIGHT", 8, 0)

	-- What your crafts made this session, as on the panel, which doesn't show on
	-- this page. Click to reset.
	local session = CreateFrame("Button", nil, footer)
	session:SetPoint("RIGHT")
	session:SetHeight(FOOTER_HEIGHT - 4)
	session.text = session:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	session.text:SetPoint("RIGHT")
	session:SetScript("OnClick", ns.Results.ConfirmResetSession)
	session:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("This session")
		GameTooltip:AddLine("What all your crafts made since you logged in on this character, including orders "
			.. "crafted from this list.", 1, 1, 1, true)
		GameTooltip:AddLine(ns.Color("simulated", "Click: reset to zero"))
		GameTooltip:Show()
	end)
	session:SetScript("OnLeave", GameTooltip_Hide)
	footer.session = session

	-- With TSM: the running search, to copy again after its box is closed.
	local search = CreateFrame("Button", nil, footer)
	search:SetHeight(FOOTER_HEIGHT - 4)
	search.text = search:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	search.text:SetPoint("RIGHT")
	search:SetScript("OnClick", showTSMSearch)
	search:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("TSM search")
		local rows = tsmSearchRows()
		GameTooltip:AddLine(format("What you're missing for %s, in one search to paste into TSM's Shopping tab.",
			ordersText(#rows)), 1, 1, 1, true)
		for _, row in ipairs(rows) do GameTooltip:AddLine(iconText(row.icon, 14) .. row.name, 1, 1, 1) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(ns.Color("simulated", "Click: copy the search"))
		GameTooltip:AddLine(ns.Color("simulated", "Clear it with the gear"))
		GameTooltip:Show()
	end)
	search:SetScript("OnLeave", GameTooltip_Hide)
	footer.search = search
end

local function drawFooter()
	ns.Blizzard.SetOrderListFooter(active and FOOTER_HEIGHT or 0)
	footer:SetShown(active)
	if not active then return end

	local concentration = state.concentration
	footer.concentration:SetText(concentration and ns.Color("muted", format("Concentration: these orders use %d of your %d",
		concentration.used, concentration.have)) or "")

	local session = ns.db.session
	local showSession = ns.db.showSession and session.crafts > 0
	footer.session:SetShown(showSession)
	if showSession then
		footer.session.text:SetText(format("%s %s %s", ns.Color("heading", "This session"), signedMoney(session.total),
			ns.Color("muted", format("(%d craft%s)", session.crafts, session.crafts == 1 and "" or "s"))))
		footer.session:SetWidth(footer.session.text:GetUnboundedStringWidth())
	end

	local searchRows = usingTSM() and #tsmSearchRows() or 0
	local search = footer.search
	search:SetShown(searchRows > 0)
	if searchRows > 0 then
		search.text:SetText(format("%s %s", ns.Color("simulated", "TSM search:"), ordersText(searchRows)))
		search:SetWidth(search.text:GetUnboundedStringWidth())
		search:ClearAllPoints()
		if showSession then
			search:SetPoint("RIGHT", footer.session, "LEFT", -24, 0)
		else
			search:SetPoint("RIGHT")
		end
	end
end

---------------------------------------------------------------------------
-- Redrawing
---------------------------------------------------------------------------

-- Works out every order again and redraws the list's rows, headers, buttons and
-- footer. Called when the list or what you own changes, and after each step.
function Patron.Redraw()
	if not footer then return end
	active = ns.db.patronList and ns.Blizzard.IsOwnProfession() and ns.Blizzard.IsPatronTable()
	state = { rows = {}, unknown = {}, byID = {}, unknownByID = {} }
	if active then
		-- What you own has changed (materials used up, rewards in).
		ns.Planner.Reset()
		state.rows, state.unknown, state.concentration = listOrders()
		for _, row in ipairs(state.rows) do state.byID[row.order.orderID] = row end
		for _, row in ipairs(state.unknown) do state.unknownByID[row.order.orderID] = true end
		sortList()
	end
	ns.Blizzard.ForEachOrderRow(drawRow)
	-- After the rows: the headers line up with what they measure.
	drawHeaders()
	drawButtons()
	drawFooter()
end

-- Redraws on the next frame, once for a burst of changes (bags filling up).
local queued = false
function Patron.QueueRedraw()
	if queued or not active then return end
	queued = true
	C_Timer.After(0, function()
		queued = false
		Patron.Redraw()
	end)
end

-- Turns "Optimize concentration" on or off. Every order's picks change,
-- including the open order's "Use the most profitable materials".
function Patron.SetLeastConcentration(on)
	ns.db.leastConcentration = on
	ns.Planner.Reset()
	ns.Panel.Refresh()
	Patron.Redraw()
end

-- Where a proc of a patron order crafted from the list shows: the list, to flash,
-- and the frame the gold floats up from (that order's Profit text, or the list).
-- nil when the list isn't showing Craft Profit's columns.
function Patron.ProcTarget(orderID)
	if not (active and footer and footer:IsVisible()) then return end
	local list, anchor = ns.Blizzard.OrderList(), nil
	for row, own in pairs(cells) do
		local order = row:IsVisible() and ns.Blizzard.RowOrder(row)
		if order and order.orderID == orderID then anchor = own.profit.text end
	end
	return list, anchor
end

function Patron.Init()
	if footer or not ns.Blizzard.IsLoaded() then return end
	local list = ns.Blizzard.OrderList()
	addAllButton = makeButton(list:GetParent(), addAll, allTooltip)
	-- On the row of order type tabs, at the list's right end.
	addAllButton:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", -2, 2)
	addProfitableButton = makeButton(list:GetParent(), addProfitable, profitableTooltip)
	addProfitableButton:SetPoint("RIGHT", addAllButton, "LEFT", -4, 0)
	createFooter()

	ns.Blizzard.WatchOrderList(Patron.Redraw)
	-- Sorting by one of Blizzard's headers ends sorting by profit.
	ns.Blizzard.WatchSortOrder(function()
		ns.db.patronSort = false
		sortedRows = nil
		drawHeaders()
	end)
	ns.Blizzard.WatchOrderRows(drawRow, function()
		-- Columns laid out again: the headers are Blizzard's again.
		drawHeaders()
		Patron.QueueRedraw()
	end)

	local events = CreateFrame("Frame")
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	events:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
	events:SetScript("OnEvent", Patron.QueueRedraw)
end
