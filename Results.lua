-- Craft Profit: what happens after each craft. Works out what the craft really
-- made (quality you got, multicraft extras, materials resourcefulness returned),
-- adds it to the session total, and celebrates procs.
local _, ns = ...

local Results = {}
ns.Results = Results

local Layout = ns.Layout
local format = string.format

-- The last craft that procced, while it's still the one on screen:
--   { kind, key, multicraft, multicraftValue, saved = { { itemID, qty, value } },
--     savedValue, bonus, actual }
local lastProc

-- The proc to show for this model: same recipe/order, and not while simulating
-- (then Profit/Loss is the what-if forecast).
function Results.ProcFor(model)
	if lastProc and lastProc.kind == model.kind and lastProc.key == model.key and not model.simulating then
		return lastProc
	end
end

function Results.ResetSession()
	ns.db.session = { total = 0, crafts = 0 }
	ns.Panel.Refresh()
end

-- Clicking the session row asks first, so a stray click can't wipe it.
StaticPopupDialogs.CRAFTPROFIT_RESET_SESSION = {
	text = "Reset this session's total?",
	button1 = "Reset",
	button2 = CANCEL,
	OnAccept = function() Results.ResetSession() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function Results.ConfirmResetSession()
	StaticPopup_Show("CRAFTPROFIT_RESET_SESSION")
end

---------------------------------------------------------------------------
-- Celebration: "+1,234g" floating up from Profit/Loss, a gold border flash, a coin
---------------------------------------------------------------------------

-- The panel's floaters, and the Patron orders list's (that list is one of the
-- game's menus, rebuilt after each step, so its floaters sit on UIParent).
local floaters, listFloaters = {}, {}

local function createFloater(parent, pool)
	local floater = CreateFrame("Frame", nil, parent)
	floater:SetSize(Layout.WIDTH - 2 * Layout.PAD_SIDE, 44)
	floater:SetFrameLevel(parent:GetFrameLevel() + 10)
	floater.amount = floater:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	floater.amount:SetPoint("BOTTOMRIGHT")
	floater.label = floater:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	floater.label:SetPoint("BOTTOMRIGHT", floater.amount, "TOPRIGHT", 0, 2)

	-- Pops in big, settles, floats up and fades.
	local anim = floater:CreateAnimationGroup()
	local pop = anim:CreateAnimation("Scale")
	pop:SetScaleFrom(1.7, 1.7)
	pop:SetScaleTo(1, 1)
	pop:SetOrigin("BOTTOMRIGHT", 0, 0)
	pop:SetDuration(0.3)
	pop:SetSmoothing("OUT")
	local fadeIn = anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.15)
	local rise = anim:CreateAnimation("Translation")
	rise:SetOffset(0, 55)
	rise:SetStartDelay(0.4)
	rise:SetDuration(2)
	rise:SetSmoothing("OUT")
	local fadeOut = anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetStartDelay(1.6)
	fadeOut:SetDuration(0.8)
	anim:SetScript("OnFinished", function() floater:Hide() end)
	floater.anim = anim

	pool[#pool + 1] = floater
	return floater
end

-- A floater that isn't playing, so quick procs in a row each get their own.
local function getFloater(parent, pool)
	for _, floater in ipairs(pool) do
		if not floater.anim:IsPlaying() then return floater end
	end
	return createFloater(parent, pool)
end

-- The panel border flashes gold, then fades back to grey.
local BORDER_FLASH_SECONDS = 1.5
local function flashBorder(panel)
	panel.flasher = panel.flasher or CreateFrame("Frame", nil, panel)
	local elapsedTotal = 0
	panel.flasher:SetScript("OnUpdate", function(self, elapsed)
		elapsedTotal = elapsedTotal + elapsed
		local p = math.min(elapsedTotal / BORDER_FLASH_SECONDS, 1)
		-- Gold (1, 0.82, 0) to grey (0.6, 0.6, 0.6).
		panel:SetBackdropBorderColor(1 - 0.4 * p, 0.82 - 0.22 * p, 0.6 * p, 1)
		if p >= 1 then self:SetScript("OnUpdate", nil) end
	end)
end

-- The Patron orders list has no border of its own to color, so a gold one is laid
-- over it and fades out.
local listGlow
local function flashList(list)
	if not listGlow then
		listGlow = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		listGlow:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
		listGlow:SetBackdropBorderColor(1, 0.82, 0, 1)
		listGlow:EnableMouse(false)
		local fade = listGlow:CreateAnimationGroup()
		local alpha = fade:CreateAnimation("Alpha")
		alpha:SetFromAlpha(1)
		alpha:SetToAlpha(0)
		alpha:SetDuration(BORDER_FLASH_SECONDS)
		alpha:SetSmoothing("IN")
		fade:SetScript("OnFinished", function() listGlow:Hide() end)
		listGlow.fade = fade
	end
	listGlow:SetFrameStrata(list:GetFrameStrata())
	listGlow:SetFrameLevel(list:GetFrameLevel() + 40)
	listGlow:ClearAllPoints()
	listGlow:SetAllPoints(list)
	listGlow:Show()
	listGlow.fade:Stop()
	listGlow.fade:Play()
end

local function setFloaterText(floater, proc)
	local parts = {}
	if proc.multicraft > 0 then parts[#parts + 1] = format("Multicraft x%d", proc.multicraft) end
	if #proc.saved > 0 then parts[#parts + 1] = "Resourcefulness" end
	floater.label:SetText(ns.Color("heading", table.concat(parts, " + ") .. "!"))
	floater.amount:SetText(proc.bonus > 0 and ns.Color("profit", "+" .. ns.Format.Money(proc.bonus)) or "")
end

local function playFloater(floater)
	floater:Show()
	floater.anim:Stop()
	floater.anim:Play()
end

local function playCoin()
	if ns.db.procSound and SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND then
		PlaySound(SOUNDKIT.LOOT_WINDOW_COIN_SOUND)
	end
end

-- On the panel: the gold floats up from Profit/Loss.
local function celebrate(proc)
	playCoin()
	if not ns.db.procFx then return end

	local panel = ns.Panel.Frame()
	flashBorder(panel)

	local floater = getFloater(panel, floaters)
	setFloaterText(floater, proc)
	floater:ClearAllPoints()
	local anchor = ns.Panel.ProfitAnchor()
	if anchor then
		floater:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)
	else
		floater:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -Layout.PAD_SIDE, 4)
	end
	playFloater(floater)
end

-- On the Patron orders list, for an order crafted with its hammer: the gold
-- floats up from the list's top edge.
local function celebrateOnList(proc, list)
	playCoin()
	if not ns.db.procFx then return end

	flashList(list)
	local floater = getFloater(UIParent, listFloaters)
	floater:SetFrameStrata(list:GetFrameStrata())
	floater:SetFrameLevel(list:GetFrameLevel() + 50)
	setFloaterText(floater, proc)
	floater:ClearAllPoints()
	floater:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", -Layout.PAD_SIDE, 4)
	playFloater(floater)
end

---------------------------------------------------------------------------
-- Craft results
---------------------------------------------------------------------------

-- What one craft really made, from the game's craft result and the model that
-- was on screen when it happened.
local function evaluate(data, model)
	local proc = { kind = model.kind, key = model.key, multicraft = 0, saved = {}, savedValue = 0 }

	-- Net value of one crafted item, at the quality you actually got.
	local unit
	if model.kind == "craft" and not data.isEnchant and data.hyperlink and data.hyperlink ~= "" then
		local price = ns.Prices.Sale(data.hyperlink, data.itemID)
		if price then unit = ns.db.ahCut and price * (1 - ns.AH_CUT) or price end
	end

	-- On orders the customer gets the item, so only crafting-page multicraft counts.
	if model.kind == "craft" and (data.multicraft or 0) > 0 then
		proc.multicraft = data.multicraft
		proc.multicraftValue = unit and unit * data.multicraft
	end

	for _, returned in ipairs(data.resourcesReturned or {}) do
		local itemID = returned.reagent and returned.reagent.itemID
		if itemID and (returned.quantity or 0) > 0 then
			local price = ns.Prices.Material(itemID)
			local value = price and price * returned.quantity
			proc.saved[#proc.saved + 1] = { itemID = itemID, qty = returned.quantity, value = value }
			proc.savedValue = proc.savedValue + (value or 0)
		end
	end

	proc.bonus = (proc.multicraftValue or 0) + proc.savedValue
	if unit and (data.quantity or 0) > 0 then
		-- quantity includes the multicraft extras.
		proc.actual = data.quantity * unit - model.realCost + proc.savedValue
	elseif model.realProfit then
		proc.actual = model.realProfit + proc.bonus
	end
	return proc
end

local function onCraftResult(data)
	if not data then return end
	local panel = ns.Panel.Frame()
	local shown = panel and panel:IsShown()
	-- A craft from the Patron orders list's hammer: the panel isn't showing that
	-- order, so the list's numbers for it are used, and procs show on the list.
	local listModel = ns.Craft.TakeCraftModel()
	local model = listModel or (shown and ns.Panel.current)
	if not model then return end

	local result = evaluate(data, model)

	-- Crafts without a price (enchants, recrafts...) aren't counted.
	if result.actual then
		local session = ns.db.session
		session.total = session.total + result.actual
		session.crafts = session.crafts + 1
	end

	if result.multicraft == 0 and #result.saved == 0 then
		-- A craft without procs: Profit/Loss goes back to the normal forecast.
		lastProc = nil
		ns.Panel.Refresh()
		return
	end

	lastProc = result
	local list = listModel and ns.Patron.ListFrame()
	if list then
		celebrateOnList(result, list)
		return
	end
	if not shown then
		-- Nothing on screen to animate; the coin sound still says it procced.
		playCoin()
		return
	end
	ns.Panel.Render() -- now, so the animation starts from the updated Profit line
	celebrate(result)
end

-- Testing (/craftprofit testproc): a made-up resourcefulness proc, on the Patron
-- orders list when it's open, otherwise on the panel. Nothing is counted.
-- Returns where it showed: "list", "panel" or nil.
function Results.TestProc()
	local proc = { multicraft = 0, saved = { { qty = 1 } }, bonus = 12345678 }
	local list = ns.Patron.ListFrame()
	if list then
		celebrateOnList(proc, list)
		return "list"
	end
	local panel = ns.Panel.Frame()
	if panel and panel:IsShown() then
		celebrate(proc)
		return "panel"
	end
end

function Results.Init()
	local events = CreateFrame("Frame")
	events:RegisterEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT")
	events:SetScript("OnEvent", function(_, _, data) onCraftResult(data) end)
end
