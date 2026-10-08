-- Craft Profit: a Shopping list button on the Patron orders tab. Adds what
-- you're missing for every patron order in the list to the Auctionator
-- shopping list in one go.
local _, ns = ...

local Patron = {}
ns.Patron = Patron

local format = string.format

local button

-- "1 patron order", "5 patron orders".
local function ordersText(count)
	return format("%d patron order%s", count, count == 1 and "" or "s")
end

-- What's missing for every listed order you can craft, how many orders that is,
-- and how many were skipped because you don't know their recipe.
local function missingForAll()
	local jobs, skipped = {}, 0
	for _, order in ipairs(ns.Blizzard.PatronOrders() or {}) do
		local job = ns.Blizzard.OrderJob(order)
		if job then
			jobs[#jobs + 1] = job
		else
			skipped = skipped + 1
		end
	end
	return ns.Model.MissingForAll(jobs), #jobs, skipped
end

local function skippedText(skipped)
	return format("Skipped %d order%s whose recipe you don't know.", skipped, skipped == 1 and "" or "s")
end

local function addAll()
	local missing, orders, skipped = missingForAll()
	ns.Shopping.AddMissing(missing, ordersText(orders))
	if skipped > 0 then ns.Shopping.Say(ns.Color("muted", skippedText(skipped))) end
end

local function showTooltip(self)
	local missing, orders, skipped = missingForAll()
	local total = ns.Shopping.Total(missing)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Shopping list")
	GameTooltip:AddLine(format("Add what you're missing for every order in this list to Auctionator's \"%s\" shopping list.",
		ns.SHOPPING_LIST), 1, 1, 1, true)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(format("%s: %s", ordersText(orders),
		total > 0 and ns.Color("missing", format("%d missing", total)) or "nothing missing"))
	if skipped > 0 then GameTooltip:AddLine(skippedText(skipped), 0.53, 0.53, 0.53, true) end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(ns.Color("simulated", format("Ctrl-click: clear the \"%s\" shopping list", ns.SHOPPING_LIST)))
	GameTooltip:Show()
end

local function openMenu(owner)
	GameTooltip:Hide()
	local missing, orders = missingForAll()
	local total = ns.Shopping.Total(missing)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(format("Add to \"%s\" list", ns.SHOPPING_LIST))
		local note = total > 0 and format("(%d missing)", total) or "(nothing missing)"
		local add = root:CreateButton(format("For all %s %s", ordersText(orders), ns.Color("muted", note)), addAll)
		add:SetEnabled(total > 0)
		root:CreateDivider()
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
