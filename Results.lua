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
	ns.Patron.Redraw()
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

-- The panel's floaters, and the Patron tab's (those sit on UIParent, over the
-- profession window, so the list's rows can't clip them).
local floaters, listFloaters = {}, {}

local POP_SCALE, POP_SECONDS = 1.7, 0.3
local RISE_HEIGHT, RISE_DELAY, RISE_SECONDS = 55, 0.4, 2

-- Fast at first, slowing to a stop.
local function easeOut(progress)
	progress = math.min(math.max(progress, 0), 1)
	return 1 - (1 - progress) ^ 2
end

-- Puts the floater where it is `elapsed` seconds into its animation: scaled
-- about its bottom right corner, which sits at its anchor, raised as it rises.
-- Offsets are in the floater's own scale, hence the division.
local function moveFloater(floater)
	local anchor, elapsed = floater.anchor, floater.elapsed or 0
	local scale = POP_SCALE + (1 - POP_SCALE) * easeOut(elapsed / POP_SECONDS)
	local rise = RISE_HEIGHT * easeOut((elapsed - RISE_DELAY) / RISE_SECONDS)
	floater:SetScale(scale)
	floater:ClearAllPoints()
	floater:SetPoint("BOTTOMRIGHT", anchor[1], anchor[2], anchor[3] / scale, (anchor[4] + rise) / scale)
end

local function createFloater(parent, pool)
	local floater = CreateFrame("Frame", nil, parent)
	floater:SetSize(Layout.WIDTH - 2 * Layout.PAD_SIDE, 44)
	floater:SetFrameLevel(parent:GetFrameLevel() + 10)
	floater.amount = floater:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	floater.amount:SetPoint("BOTTOMRIGHT")
	floater.label = floater:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	floater.label:SetPoint("BOTTOMRIGHT", floater.amount, "TOPRIGHT", 0, 2)

	-- Pops in big, settles, floats up and fades. The pop and the rise move the frame
	-- itself each frame: the coin icons in the text stay behind with Scale and
	-- Translation animations.
	local anim = floater:CreateAnimationGroup()
	local fadeIn = anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.15)
	local fadeOut = anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetStartDelay(1.6)
	fadeOut:SetDuration(0.8)
	anim:SetScript("OnPlay", function() floater.elapsed = 0 end)
	anim:SetScript("OnUpdate", function(_, elapsed)
		floater.elapsed = floater.elapsed + elapsed
		moveFloater(floater)
	end)
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

-- The Patron tab's gold and border flash sit in a layer above the profession
-- window: in its own layer, the window comes to the front each time it's
-- clicked and covers them.
local LIST_FX_STRATA = "DIALOG"

-- The Patron tab's order list has no border of its own to color, so a gold one is laid
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
	listGlow:SetFrameStrata(LIST_FX_STRATA)
	listGlow:SetFrameLevel(40)
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

-- Starts the animation with the floater's bottom right corner at `relativeTo`'s
-- `relativePoint`, offset by x, y.
local function playFloater(floater, relativeTo, relativePoint, x, y)
	floater.anchor = { relativeTo, relativePoint, x, y }
	floater.elapsed = 0
	moveFloater(floater)
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
	local anchor = ns.Panel.ProfitAnchor()
	if anchor then
		playFloater(floater, anchor, "TOPRIGHT", 0, 4)
	else
		playFloater(floater, panel, "TOPRIGHT", -Layout.PAD_SIDE, 4)
	end
end

-- On the Patron tab, for an order crafted with its hammer: the gold floats up
-- from `anchor` (the order's Profit), or else from the list's top edge.
local function celebrateOnList(proc, list, anchor)
	playCoin()
	if not ns.db.procFx then return end

	flashList(list)
	local floater = getFloater(UIParent, listFloaters)
	floater:SetFrameStrata(LIST_FX_STRATA)
	floater:SetFrameLevel(50)
	setFloaterText(floater, proc)
	if anchor then
		playFloater(floater, anchor, "TOPRIGHT", 0, 4)
	else
		playFloater(floater, list, "TOPRIGHT", -Layout.PAD_SIDE, 4)
	end
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
		-- Nothing to sell (no price, an enchant, a recraft) is a loss of what the
		-- materials cost, less what resourcefulness gave back.
		proc.actual = model.realProfit + proc.bonus
	elseif model.kind == "craft" then
		-- The same while what-if qualities are on screen: the real craft used the
		-- form's materials.
		proc.actual = proc.bonus - model.realCost
	end
	return proc
end

-- Teaches Procs how big this craft's procs were, and adds it to the luck meter:
-- the gold procs were expected to add (the panel's numbers, or for an order from
-- the Patron tab, resourcefulness alone) against what they did.
local function learnProcs(data, model, result)
	local professionID = ns.Procs.ProfessionOf(model.recipeID)
	local used = {}
	for _, material in ipairs(model.materials or {}) do used[material.itemID] = material.qty end
	ns.Procs.Record(professionID, data, used)

	local expected = model.procs
	if not expected and model.recipeID then
		expected = ns.Procs.Expected(professionID, ns.Procs.RecipeChances(model.recipeID), nil,
			ns.Model.BasicCost(model.materials or {}))
	end
	ns.Procs.AddToSession(expected and expected.total, result.bonus)
end

local function onCraftResult(data)
	if not data then return end
	local panel = ns.Panel.Frame()
	local shown = panel and panel:IsShown()
	-- A craft from the Patron tab's hammer: the panel isn't showing that
	-- order, so the list's numbers for it are used, and procs show on the list.
	local listModel = ns.Craft.TakeCraftModel()
	local model = listModel or (shown and ns.Panel.current)
	if not model then return end

	local result = evaluate(data, model)

	-- Every craft counts, those with nothing to sell as a loss of what their materials cost.
	if result.actual then
		local session = ns.db.session
		session.total = session.total + result.actual
		session.crafts = session.crafts + 1
		learnProcs(data, model, result)
	end

	-- The Patron tab's session total has a new amount.
	ns.Patron.Redraw()
	if result.multicraft == 0 and #result.saved == 0 then
		-- A craft without procs: Profit/Loss goes back to the normal forecast.
		lastProc = nil
		ns.Panel.Refresh()
		return
	end

	lastProc = result
	if listModel then
		local list, anchor = ns.Patron.ProcTarget(listModel.key)
		if list then
			celebrateOnList(result, list, anchor)
			return
		end
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
	local list = ns.Patron.ProcTarget()
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
