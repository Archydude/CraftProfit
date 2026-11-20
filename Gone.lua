-- Craftonomics: notices when something you crafted leaves you some other way than
-- an auction or a craft, so the Ledger stops counting it as waiting to sell. Sold
-- to a vendor, used (thrown, drunk, eaten, disenchanted...), destroyed, or given
-- away (mailed, traded, put in the guild bank). It counts what you have of every
-- item you've crafted each time your bags change, and what's gone since the last
-- count goes by what you were doing then. What you put on the auction house or in
-- your own banks hasn't left.
local _, ns = ...

local Gone = {}
ns.Gone = Gone

local SETTLE = 0.5      -- seconds after your bags change before they're counted
local CRAFT_WINDOW = 2  -- seconds around a craft in which what goes is its materials
local AFTER = 3         -- seconds after a trade or a destroy in which what goes is its doing

local counts            -- itemID -> how many you had at the last count; nil until the first one
local queued = false    -- a count is on its way
local reason            -- what the items going would be down to, noted when the bags changed
local loading = true    -- a loading screen is up: what the game says you have can't be trusted
local atMerchant, atMail, atAuction, atGuildBank = false, false, false, false
local craftedAt, tradedAt, destroyedAt = -math.huge, -math.huge, -math.huge

-- A craft just finished: the materials it took are recorded with it (see Ledger.RecordCraft).
function Gone.Crafted()
	craftedAt = GetTime()
end

local function crafting()
	return GetTime() - craftedAt <= CRAFT_WINDOW + SETTLE or C_TradeSkillUI.GetRemainingRecasts() > 0
end

-- What an item leaving right now is down to: "vendor", "destroyed", "given" or
-- "used", or false when it hasn't left (on the auction house) or a craft took it.
local function reasonNow()
	if atAuction or crafting() then return false end
	if atMerchant then return "vendor" end
	local now = GetTime()
	if now - destroyedAt <= AFTER then return "destroyed" end
	if atMail or atGuildBank or now - tradedAt <= AFTER then return "given" end
	return "used"
end

-- Counts what you have of everything you've crafted. What's gone since the last
-- count is recorded, unless this is the first count or nothing says why.
local function count()
	queued = false
	local why = reason
	reason = nil
	if loading then return end
	local first = counts == nil
	counts = counts or {}
	-- The craft's result can arrive just after the bags changed.
	if crafting() then why = false end
	for itemID in pairs(ns.Ledger.CraftedItems()) do
		local now = ns.Model.Owned(itemID)
		local before = counts[itemID]
		if not first and why and before and now < before then
			local qty = before - now
			local pays = why == "vendor" and select(11, C_Item.GetItemInfo(itemID)) or 0
			ns.Ledger.RecordGone(itemID, qty, why, (pays or 0) * qty)
		end
		counts[itemID] = now
	end
end

local function onBagsChanged()
	if loading then return end
	-- The first change of a batch says why: a window can close before the count.
	if reason == nil then reason = reasonNow() end
	if queued then return end
	queued = true
	C_Timer.After(SETTLE, count)
end

local HANDLERS = {
	BAG_UPDATE_DELAYED = onBagsChanged,
	MERCHANT_SHOW = function() atMerchant = true end,
	MERCHANT_CLOSED = function() atMerchant = false end,
	MAIL_SHOW = function() atMail = true end,
	MAIL_CLOSED = function() atMail = false end,
	AUCTION_HOUSE_SHOW = function() atAuction = true end,
	AUCTION_HOUSE_CLOSED = function() atAuction = false end,
	GUILDBANKFRAME_OPENED = function() atGuildBank = true end,
	GUILDBANKFRAME_CLOSED = function() atGuildBank = false end,
	TRADE_CLOSED = function() tradedAt = GetTime() end,
	LOADING_SCREEN_ENABLED = function() loading = true end,
	-- After a loading screen the count starts over: nothing is compared across it.
	LOADING_SCREEN_DISABLED = function()
		loading = false
		counts, reason = nil, nil
		onBagsChanged()
	end,
}

function Gone.Init()
	local events = CreateFrame("Frame")
	for event in pairs(HANDLERS) do
		-- Not every version of the game has every one of these.
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event) HANDLERS[event]() end)
	hooksecurefunc("DeleteCursorItem", function() destroyedAt = GetTime() end)
end
