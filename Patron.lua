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
-- name, icon }. Also the orders whose recipe you don't know: { name, icon }.
local function listOrders()
	local rows, unknown = {}, {}
	for _, order in ipairs(ns.Blizzard.PatronOrders() or {}) do
		local job, name, icon = ns.Blizzard.OrderJob(order)
		if job then
			-- Priced like the panel does for an order you haven't opened: what you
			-- supply at its cheapest quality.
			local model = ns.Model.Order({ order = order, schematic = job.schematic, provided = job.provided })
			rows[#rows + 1] = { order = order, job = job, model = model, name = job.name or "?", icon = job.icon }
		else
			unknown[#unknown + 1] = { name = name or "?", icon = icon }
		end
	end
	table.sort(rows, function(a, b) return a.model.total > b.model.total end)
	return rows, unknown
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

local function addAll()
	local rows, unknown = listOrders()
	ns.Shopping.AddMissing(missingForAll(rows), ordersText(#rows))
	if #unknown > 0 then ns.Shopping.Say(ns.Color("muted", skippedText(#unknown))) end
end

-- Adds one order's missing materials. The menu stays open for the next one.
local function addOrder(row)
	ns.Shopping.AddMissing(row.model.missing, row.name)
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
	local total = ns.Shopping.Total(missingForAll(rows))
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Shopping list")
	GameTooltip:AddLine("Every patron order with its profit or loss. Click one to add what you're missing for it to "
		.. format("Auctionator's \"%s\" shopping list, or add them all.", ns.SHOPPING_LIST), 1, 1, 1, true)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(format("%s: %s", ordersText(#rows),
		total > 0 and ns.Color("missing", format("%d missing", total)) or "nothing missing"))
	if #unknown > 0 then GameTooltip:AddLine(skippedText(#unknown), 0.53, 0.53, 0.53, true) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(ns.Color("simulated", format("Ctrl-click: clear the \"%s\" shopping list", ns.SHOPPING_LIST)))
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
			local value = reward.value and ns.Format.Money(reward.value) or ns.Color("muted", "not sellable")
			tooltip:AddDoubleLine(text, value, 1, 1, 1, 1, 1, 1)
		end
	end
	if model.notes.missing then
		tooltip:AddLine("Some materials have no price, so the profit is too high.", 1, 0.4, 0.4, true)
	end
	tooltip:AddLine(" ")
	local missing = ns.Shopping.Total(model.missing)
	if missing > 0 then
		tooltip:AddLine(ns.Color("missing", format("%d missing", missing)))
		for _, material in ipairs(model.missing) do
			tooltip:AddLine(ns.Format.Item(material.itemID, material.qty), 1, 1, 1)
		end
		tooltip:AddLine(ns.Color("simulated", "Click: add what's missing to the shopping list"))
	else
		tooltip:AddLine("Nothing missing", 0.53, 0.53, 0.53)
	end
end

local function openMenu(owner)
	GameTooltip:Hide()
	local rows, unknown = listOrders()
	local total = ns.Shopping.Total(missingForAll(rows))
	MenuUtil.CreateContextMenu(owner, function(_, root)
		-- Long lists scroll instead of running off the screen.
		if root.SetScrollMode then root:SetScrollMode(MENU_MAX_HEIGHT) end
		root:CreateTitle("Patron orders")
		for _, row in ipairs(rows) do
			local missing = ns.Shopping.Total(row.model.missing)
			local note = missing > 0 and ns.Color("missing", format(" (%d missing)", missing)) or ""
			local item = root:CreateButton(iconText(row.icon) .. row.name .. note, function() return addOrder(row) end)
			rightText(item, signedMoney(row.model.total))
			item:SetTooltip(function(tooltip) orderTooltip(tooltip, row) end)
		end
		for _, row in ipairs(unknown) do
			local item = root:CreateButton(iconText(row.icon) .. row.name .. ns.Color("muted", "  recipe not known"))
			item:SetEnabled(false)
		end

		root:CreateDivider()
		local note = total > 0 and format("(%d missing)", total) or "(nothing missing)"
		local all = root:CreateButton(format("Add all %s %s", ordersText(#rows), ns.Color("muted", note)), addAll)
		all:SetEnabled(total > 0)
		root:CreateButton("Clear shopping list", ns.Shopping.Clear)
	end)
end

-- Shown on the Patron tab while it lists orders, when the shopping list uses
-- Auctionator.
function Patron.Refresh()
	if not button then return end
	local orders = ns.Blizzard.PatronOrders()
	button:SetShown(orders ~= nil and #orders > 0 and ns.Shopping.CanClear())
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
		if IsControlKeyDown() then
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
