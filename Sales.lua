-- Craft Profit: what your characters sold on the auction house, for the Best
-- crafts list's "You sold" column. Read from the "Auction successful" mail each
-- time the mailbox shows it, so a sale counts whether or not you take the gold.
local _, ns = ...

local Sales = {}
ns.Sales = Sales

-- Sales older than this many days are dropped and not shown.
Sales.DAYS = 14
-- A sale mail lives this many days, so its daysLeft says when it came.
local MAIL_DAYS = 30
-- Seconds two readings of the same mail may differ by.
local SAME_MAIL = 300
local DAY = 86400

-- CraftProfitDB.sales = {
--   since = when Craft Profit started counting (time()),
--   list = { { name, qty, money, t } ... }, every sale in the last DAYS days,
-- }
local saved

function Sales.Init()
	CraftProfitDB.sales = CraftProfitDB.sales or { since = time(), list = {} }
	saved = CraftProfitDB.sales
end

local function prune()
	local cutoff = time() - Sales.DAYS * DAY
	local kept = {}
	for _, sale in ipairs(saved.list) do
		if sale.t >= cutoff then kept[#kept + 1] = sale end
	end
	saved.list = kept
end

-- The "Auction successful" mails in the inbox: { { name, qty, money, t } ... }.
local function inboxSales()
	local list = {}
	local now = time()
	for index = 1, GetInboxNumItems() do
		local invoiceType, itemName, _, bid, _, _, _, _, _, _, count = GetInboxInvoiceInfo(index)
		if invoiceType == "seller" and itemName then
			local daysLeft = select(7, GetInboxHeaderInfo(index))
			if daysLeft then
				list[#list + 1] = { name = itemName, qty = count or 1, money = bid or 0, t = now + (daysLeft - MAIL_DAYS) * DAY }
			end
		end
	end
	return list
end

-- Adds the inbox's sales that aren't saved yet. A mail that's still there from
-- last time matches the saved sale with the same item, amount and gold that came
-- at the same time; each saved sale matches one mail, so identical sales stay apart.
local function record()
	if not saved then return end
	prune()
	local cutoff = time() - Sales.DAYS * DAY
	local matched = {}
	for _, sale in ipairs(inboxSales()) do
		if sale.t >= cutoff then
			local found = false
			for i, old in ipairs(saved.list) do
				if not matched[i] and old.name == sale.name and old.qty == sale.qty and old.money == sale.money
					and math.abs(old.t - sale.t) <= SAME_MAIL then
					matched[i], found = true, true
					break
				end
			end
			if not found then
				saved.list[#saved.list + 1] = sale
				matched[#saved.list] = true
			end
		end
	end
end

-- How many of the item called `name` your characters sold in the last DAYS days.
function Sales.Sold(name)
	if not (saved and name) then return 0 end
	local cutoff = time() - Sales.DAYS * DAY
	local qty = 0
	for _, sale in ipairs(saved.list) do
		if sale.name == name and sale.t >= cutoff then qty = qty + sale.qty end
	end
	return qty
end

-- How many days of sales there are so far: DAYS, or fewer when Craft Profit
-- started counting more recently.
function Sales.DaysCounted()
	if not saved then return 0 end
	return math.min(Sales.DAYS, math.floor((time() - saved.since) / DAY))
end

-- The inbox changes in bursts while you take mail: read it right away, so a
-- mail taken at once still counts, then once more when the burst is over.
local queued = false
local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_INBOX_UPDATE")
events:SetScript("OnEvent", function()
	if queued then return end
	queued = true
	record()
	C_Timer.After(0.5, function()
		queued = false
		record()
	end)
end)
