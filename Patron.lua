-- Craft Profit: a Shopping list button on the Patron orders tab. Its menu lists
-- every patron order with its profit or loss; click one to add what you're
-- missing for it to the Auctionator shopping list, or add them all at once.
local _, ns = ...

local Patron = {}
ns.Patron = Patron

local format = string.format

local ICON_SIZE = 16        -- recipe icons in the menu
local MENU_MAX_HEIGHT = 500 -- taller menus scroll
local MENU_ROW_HEIGHT = 20
local RIGHT_GAP = 24        -- between an order's name and its profit
local GEAR_SIZE = 16        -- options button on the title row, as on the panel

local button

-- "1 patron order", "5 patron orders".
local function ordersText(count)
	return format("%d patron order%s", count, count == 1 and "" or "s")
end

-- "+12g 50s" in green, "-3g" in red.
local function signedMoney(amount)
	return ns.Color(ns.AmountColor(amount), (amount > 0 and "+" or "") .. ns.Format.Money(amount))
end

local function iconText(icon)
	return icon and format("|T%s:%d|t ", icon, ICON_SIZE) or ""
end

-- The listed orders you can craft, most profitable first: { order, job, model,
-- plan, noConcentration, name, icon }. Also the orders whose recipe you don't
-- know: { name, icon }, and your concentration: { have, used } or nil.
local function listOrders()
	local rows, unknown = {}, {}
	for _, order in ipairs(ns.Blizzard.PatronOrders() or {}) do
		local job, name, icon = ns.Blizzard.OrderJob(order)
		if job then
			-- What you supply at its cheapest quality, or for an order with a minimum
			-- quality, the cheapest qualities that reach it.
			local plan = ns.Planner.ForOrder(order, job.schematic, job.provided)
			job.overrides = plan and plan.overrides
			local model = ns.Model.Order({ order = order, schematic = job.schematic, provided = job.provided, overrides = job.overrides })
			rows[#rows + 1] = { order = order, job = job, model = model, plan = plan, name = job.name or "?", icon = job.icon }
		else
			unknown[#unknown + 1] = { name = name or "?", icon = icon }
		end
	end
	-- Most profitable first; orders you can't craft go last, since their profit is moot.
	table.sort(rows, function(a, b)
		local aOut, bOut = a.plan and a.plan.unreachable or false, b.plan and b.plan.unreachable or false
		if aOut ~= bOut then return bOut end
		return a.model.total > b.model.total
	end)
	local concentration = ns.Planner.SpendConcentration(rows, ns.db.concentrationFor)
	return rows, unknown, concentration
end

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

local function addAll()
	local rows, unknown = listOrders()
	local reachable, unreachable, short = reachableRows(rows)
	ns.Shopping.AddMissing(missingForAll(reachable), ordersText(#reachable))
	remember(reachable)
	if short > 0 then ns.Shopping.Say(ns.Color("muted", shortText(short))) end
	if unreachable > 0 then ns.Shopping.Say(ns.Color("muted", unreachableText(unreachable))) end
	if #unknown > 0 then ns.Shopping.Say(ns.Color("muted", skippedText(#unknown))) end
end

local function addProfitable()
	local rows = profitableRows(listOrders())
	ns.Shopping.AddMissing(missingForAll(rows), "the " .. ordersText(#rows) .. " that make a profit")
	remember(rows)
end

-- With only TSM, materials go to a TSM search to copy instead of a shopping list,
-- and there's no list to take things back off or clear.
local function usingTSM()
	return ns.Shopping.ListTarget() == "tsm"
end

-- Green check for an order you have everything for.
local READY_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:" .. ICON_SIZE .. "|t"

-- Whether you own everything an order needs, in the qualities picked for the most
-- profit: nothing's missing, and the minimum quality is reachable. (The picks
-- already prefer a cheaper rank to buy over one you own when that pays, so
-- nothing missing means nothing worth buying either.)
local function isReady(row)
	if ns.Shopping.Total(row.model.missing) > 0 then return false end
	return not (row.noConcentration or row.plan and row.plan.unreachable)
end

-- " [rank icon]" after an order's name when it needs more than rank 1, like
-- Blizzard's order list. (While testing, the pretend minimum.)
local function minQualityText(row)
	local minQuality = row.plan and row.plan.minQuality or row.order.minQuality or 0
	if minQuality <= 1 then return "" end
	local icon = ns.Blizzard.ItemQualityMarkup(row.order.spellID, minQuality)
	return icon and " " .. icon or ""
end

-- An order's minimum quality as its icon, or "rank N".
local function qualityText(row, quality)
	return ns.Blizzard.ItemQualityMarkup(row.order.spellID, quality) or format("rank %d", quality)
end

-- Shown after an order's name when reaching its minimum quality takes concentration.
local function concentrationNote(row)
	local plan = row.plan
	if not (plan and plan.concentration) or plan.unreachable then return "" end
	if row.noConcentration then return ns.Color("loss", " (not enough concentration)") end
	return ns.Color("muted", format(" (%d concentration)", plan.concentration))
end

-- Adds one order's missing materials. The menu stays open for the next one,
-- except for a TSM search, whose popup needs the focus.
local function addOrder(row)
	ns.Shopping.AddMissing(row.model.missing, row.name)
	if usingTSM() then return end
	remember({ row })
	return MenuResponse and MenuResponse.Open
end

-- Shift-click: takes off what this order added, or what it's missing now if it
-- added nothing this session. The menu stays open.
local function removeOrder(row)
	local list = added[row.order.orderID] or row.model.missing
	added[row.order.orderID] = nil
	ns.Shopping.RemoveMissing(list, row.name)
	return MenuResponse and MenuResponse.Open
end

-- Puts `text` at the right end of a menu row, after a gap.
local function rightText(item, text)
	item:AddInitializer(function(frame)
		local label = frame.fontString
		local right = frame:AttachFontString()
		right:SetFontObject(label and label:GetFontObject() or "GameFontHighlight")
		right:SetPoint("RIGHT")
		right:SetJustifyH("RIGHT")
		right:SetText(text)
		local width = (label and label:GetUnboundedStringWidth() or 0) + RIGHT_GAP + right:GetUnboundedStringWidth()
		return width, MENU_ROW_HEIGHT
	end)
end

local function showTooltip(self)
	local rows, unknown = listOrders()
	local reachable, unreachable, short = reachableRows(rows)
	local total = ns.Shopping.Total(missingForAll(reachable))
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Shopping list")
	GameTooltip:AddLine(usingTSM()
		and ("Every patron order with its profit or loss. Click one to copy a TSM search for what you're missing "
			.. "for it, or copy one for the ones that make a profit, or all of them.")
		or ("Every patron order with its profit or loss. Click one to add what you're missing for it to "
			.. format("Auctionator's \"%s\" shopping list, or add the ones that make a profit, or all of them.", ns.Shopping.ListName())),
		1, 1, 1, true)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(format("%s: %s", ordersText(#reachable),
		total > 0 and ns.Color("missing", format("%d missing", total)) or "nothing missing"))
	if short > 0 then GameTooltip:AddLine(shortText(short), 0.53, 0.53, 0.53, true) end
	if unreachable > 0 then GameTooltip:AddLine(unreachableText(unreachable), 0.53, 0.53, 0.53, true) end
	if #unknown > 0 then GameTooltip:AddLine(skippedText(#unknown), 0.53, 0.53, 0.53, true) end
	if ns.Shopping.CanClear() then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(ns.Color("simulated", format("Ctrl-click: clear the \"%s\" shopping list", ns.Shopping.ListName())))
	end
	GameTooltip:Show()
end

-- An order's row tooltip: where its profit comes from, and what's missing.
local function orderTooltip(tooltip, row)
	local model = row.model
	local function line(label, amount, signed)
		tooltip:AddDoubleLine(label, signed and signedMoney(amount) or ns.Format.Money(amount), 1, 1, 1, 1, 1, 1)
	end
	GameTooltip_SetTitle(tooltip, iconText(row.icon) .. row.name)
	line("Commission (after cut)", model.receive)
	line("Materials you supply", -model.cost, true)
	local rewards = model.total - model.receive + model.cost
	if rewards > 0 then line("Sellable rewards", rewards) end
	line(model.total >= 0 and "Profit" or "Loss", model.total, true)

	-- Every reward, as on the panel: sellable items with their value, the rest
	-- (currencies like Moxie, bound items) just listed.
	if #model.rewards > 0 then
		tooltip:AddLine(" ")
		tooltip:AddLine("Rewards", 1, 0.82, 0)
		for _, reward in ipairs(model.rewards) do
			local text = reward.currency and ns.Format.Currency(reward.currency, reward.qty)
				or ns.Format.Item(reward.itemID, reward.qty)
			if reward.knowledge then text = text .. ns.Color("good", format(" (%d knowledge)", reward.knowledge * reward.qty)) end
			local value = reward.value and ns.Format.Money(reward.value) or ns.Color("muted", "not sellable")
			tooltip:AddDoubleLine(text, value, 1, 1, 1, 1, 1, 1)
		end
	end
	if model.notes.missing then
		tooltip:AddLine("Some materials have no price, so the profit is too high.", 1, 0.4, 0.4, true)
	end

	-- The order's minimum quality, and the material qualities picked to reach it.
	local plan = row.plan
	if plan and plan.minQuality then
		tooltip:AddLine(" ")
		tooltip:AddLine("Minimum quality " .. qualityText(row, plan.minQuality), 1, 0.82, 0)
		if plan.unreachable then
			tooltip:AddLine("You can't reach it, even with the best materials.", 1, 0.4, 0.4, true)
		elseif row.noConcentration then
			tooltip:AddLine(format("Needs %d concentration, but there isn't enough left once the orders worth more get theirs.",
				plan.concentration), 1, 0.4, 0.4, true)
			tooltip:AddLine("Using:", 1, 1, 1)
		elseif plan.concentration then
			tooltip:AddLine(format("Reached with %d concentration, using:", plan.concentration), 1, 1, 1, true)
		else
			tooltip:AddLine("Reached with the cheapest qualities that do it:", 1, 1, 1, true)
		end
		if not plan.unreachable then
			for _, pick in ipairs(plan.picks) do
				tooltip:AddLine(ns.Format.Item(pick.itemID, pick.qty), 1, 1, 1)
			end
		end
	end
	-- What's missing only matters for an order you can craft.
	if plan and plan.unreachable then
		if added[row.order.orderID] and not usingTSM() then
			tooltip:AddLine(" ")
			tooltip:AddLine(ns.Color("simulated", "Shift-click: remove it from the shopping list"))
		end
		return
	end
	tooltip:AddLine(" ")
	local missing = ns.Shopping.Total(model.missing)
	if missing > 0 then
		tooltip:AddLine(ns.Color("missing", format("%d missing", missing)))
		for _, material in ipairs(model.missing) do
			tooltip:AddLine(ns.Format.Item(material.itemID, material.qty), 1, 1, 1)
		end
		tooltip:AddLine(ns.Color("simulated", usingTSM() and "Click: copy a TSM search for what's missing"
			or "Click: add what's missing to the shopping list"))
	else
		if isReady(row) then
			tooltip:AddLine(READY_ICON .. " You have everything, in the qualities that make the most profit.", 0.53, 1, 0.53, true)
		else
			tooltip:AddLine("Nothing missing", 0.53, 0.53, 0.53)
		end
	end
	if not usingTSM() then
		tooltip:AddLine(ns.Color("simulated", "Shift-click: remove it from the shopping list"))
	end
end

-- A gear in the list's top-right corner that opens the options, like the panel's.
-- One button, laid over whichever list is open, and hidden once that list closes.
local gear, gearMenu

local function showGear(menu)
	if not menu then return end
	if not gear then
		gear = CreateFrame("Button", nil, UIParent)
		gear:SetSize(GEAR_SIZE, GEAR_SIZE)
		gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
		gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		gear:SetScript("OnClick", function()
			local manager = Menu and Menu.GetManager and Menu.GetManager()
			if manager then manager:CloseMenus() end
			ns.Options.Open()
		end)
		gear:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Craft Profit options")
			GameTooltip:Show()
		end)
		gear:SetScript("OnLeave", GameTooltip_Hide)
		-- Menus are reused by other addons, so the gear goes away as soon as ours closes.
		gear:SetScript("OnUpdate", function(self)
			if not (gearMenu and gearMenu:IsVisible()) then self:Hide() end
		end)
	end
	gearMenu = menu
	gear:SetFrameStrata(menu:GetFrameStrata())
	gear:SetFrameLevel(menu:GetFrameLevel() + 50)
	gear:ClearAllPoints()
	gear:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -8, -8)
	gear:Show()
end

-- A menu action that leaves the menu open afterwards (unless it shows a TSM
-- search, whose popup needs the focus).
local function keepOpen(action)
	return function()
		action()
		if usingTSM() then return end
		return MenuResponse and MenuResponse.Open
	end
end

local function openMenu(owner)
	GameTooltip:Hide()
	local menu = MenuUtil.CreateContextMenu(owner, function(_, root)
		-- Worked out here, so a refresh (after switching the concentration choice) redoes it.
		local rows, unknown, concentration = listOrders()
		local reachable, unreachable, short = reachableRows(rows)
		local total = ns.Shopping.Total(missingForAll(reachable))
		local tsm = usingTSM()
		local verb = tsm and "Copy" or "Add"
		-- Long lists scroll instead of running off the screen.
		if root.SetScrollMode then root:SetScrollMode(MENU_MAX_HEIGHT) end
		root:CreateTitle("Patron orders")
		if concentration then
			root:CreateTitle(ns.Color("muted", format("Concentration: these orders use %d of your %d",
				concentration.used, concentration.have)))
		end
		for _, row in ipairs(rows) do
			local unreachableRow = row.plan and row.plan.unreachable
			local missing = ns.Shopping.Total(row.model.missing)
			local note = ""
			if unreachableRow then
				-- Nothing to buy for an order you can't craft.
			elseif missing > 0 then
				note = ns.Color("missing", format(" (%d missing)", missing))
			elseif isReady(row) then
				note = " " .. READY_ICON
			end
			local item = root:CreateButton(iconText(row.icon) .. row.name .. minQualityText(row) .. note .. concentrationNote(row), function()
				if IsShiftKeyDown() and not tsm then return removeOrder(row) end
				if unreachableRow then return MenuResponse and MenuResponse.Open end
				return addOrder(row)
			end)
			-- Short of concentration: the profit in grey, since you can't take it right now.
			local right = unreachableRow and ns.Color("loss", "can't craft")
				or row.noConcentration and ns.Color("muted", (row.model.total > 0 and "+" or "") .. ns.Format.Money(row.model.total))
				or signedMoney(row.model.total)
			rightText(item, right)
			item:SetTooltip(function(tooltip) orderTooltip(tooltip, row) end)
		end
		for _, row in ipairs(unknown) do
			local item = root:CreateButton(iconText(row.icon) .. row.name .. ns.Color("muted", "  recipe not known"))
			item:SetEnabled(false)
		end

		root:CreateDivider()
		local function missingNote(count)
			return ns.Color("muted", count > 0 and format("(%d missing)", count) or "(nothing missing)")
		end
		local profitable = profitableRows(rows)
		local profitableTotal = ns.Shopping.Total(missingForAll(profitable))
		local best = root:CreateButton(format("%s profitable: %s %s", verb, ordersText(#profitable), missingNote(profitableTotal)),
			keepOpen(addProfitable))
		best:SetEnabled(profitableTotal > 0)
		best:SetTooltip(function(tooltip)
			GameTooltip_SetTitle(tooltip, verb .. " profitable orders")
			tooltip:AddLine((tsm and "A TSM search for what you're missing for every order" or "Adds what you're missing for every order")
				.. " that makes a profit and whose minimum quality "
				.. "you can reach, at the cheapest qualities that reach it. Orders left without enough concentration "
				.. "are skipped.", 1, 1, 1, true)
		end)
		local all = root:CreateButton(format("%s all %s %s", verb, ordersText(#reachable), missingNote(total)), keepOpen(addAll))
		all:SetEnabled(total > 0)
		if unreachable > 0 or short > 0 then
			all:SetTooltip(function(tooltip)
				GameTooltip_SetTitle(tooltip, verb .. " all orders")
				if short > 0 then tooltip:AddLine(shortText(short), 1, 1, 1, true) end
				if unreachable > 0 then tooltip:AddLine(unreachableText(unreachable), 1, 1, 1, true) end
			end)
		end
		if not tsm then root:CreateButton("Clear shopping list", keepOpen(ns.Shopping.Clear)) end

		ns.Shopping.AddShopWithChoice(root)

		-- Which orders get your concentration first; the list redraws with the new shares.
		root:CreateDivider()
		root:CreateTitle("Spend concentration on")
		local function isChosen(key) return ns.db.concentrationFor == key end
		local function choose(key)
			ns.db.concentrationFor = key
			return MenuResponse and MenuResponse.Refresh
		end
		for _, choice in ipairs(ns.CONCENTRATION_CHOICES) do
			root:CreateRadio(choice[2], isChosen, choose, choice[1])
		end
	end)
	showGear(menu)
end

-- Shown on the Patron tab while it lists orders, when materials go to Auctionator's
-- shopping list or a TSM search.
function Patron.Refresh()
	if not button then return end
	ns.Planner.Reset()
	local orders = ns.Blizzard.PatronOrders()
	button:SetShown(orders ~= nil and #orders > 0 and ns.Shopping.ListTarget() ~= nil)
end

function Patron.Init()
	if button or not ns.Blizzard.IsLoaded() then return end
	local list = ns.Blizzard.OrderList()
	button = CreateFrame("Button", nil, list:GetParent(), "UIPanelButtonTemplate")
	button:SetText("Shopping list")
	button:SetSize(button:GetFontString():GetStringWidth() + 32, 22)
	-- On the row of order type tabs, at the list's right end.
	button:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", -2, 2)
	button:SetScript("OnClick", function(self)
		if IsControlKeyDown() and ns.Shopping.CanClear() then
			ns.Shopping.Clear()
		else
			openMenu(self)
		end
	end)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:Hide()
	ns.Blizzard.WatchOrderList(Patron.Refresh)
end
