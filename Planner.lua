-- Craft Profit: which material qualities a patron order should use, for the
-- Patron order list: the cheapest ones that still meet the order's minimum
-- quality. "Cheapest" counts what you own at what it would sell for, so a rank
-- you have only loses to a cheaper one when buying that really comes out ahead.
local _, ns = ...

local Planner = {}
ns.Planner = Planner

-- Most quality mixes tried for one order (5 slots of 3 qualities). Past that,
-- only the top qualities are tried.
local MAX_MIXES = 243
-- Cost given to a material with no price, so mixes with it are tried last.
local UNPRICED = 1e12

-- orderID -> plan, until the order list changes.
local plans = {}

-- For testing (/craftprofit testquality <rank>): treat every patron order as
-- needing at least this rank. Not saved; a /reload turns it off.
Planner.testMinQuality = nil

-- For testing (/craftprofit testconcentration <amount>): pretend you have this much
-- concentration. Not saved; a /reload turns it off.
Planner.testConcentration = nil

function Planner.SetTestMinQuality(rank)
	Planner.testMinQuality = rank
	wipe(plans)
end

function Planner.Reset()
	wipe(plans)
end

-- The slots you fill that come in several qualities:
-- { slotIndex, qty, options = { { itemID, cost, quality } ... } cheapest first },
-- where cost is what using that quality in this slot really costs you.
local function qualitySlots(schematic, provided)
	local list = {}
	for slotIndex, slot in ipairs(schematic.reagentSlotSchematics) do
		if slot.required and not provided[slotIndex] and ns.Blizzard.IsQualitySlot(slot)
			and slot.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent then
			local options = {}
			for _, reagent in ipairs(slot.reagents) do
				if reagent.itemID then
					options[#options + 1] = {
						itemID = reagent.itemID,
						cost = ns.Model.EffectiveCost(reagent.itemID, slot.quantityRequired) or UNPRICED,
						quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(reagent.itemID) or 0,
					}
				end
			end
			table.sort(options, function(a, b) return a.cost < b.cost end)
			if #options > 0 then
				list[#list + 1] = { slotIndex = slotIndex, dataSlotIndex = slot.dataSlotIndex, qty = slot.quantityRequired, options = options }
			end
		end
	end
	return list
end

-- Every mix of qualities (mix[i] = option picked for slots[i]), cheapest first,
-- or only the top qualities when there are too many mixes to try.
local function mixesOf(slots)
	local count = 1
	for _, entry in ipairs(slots) do count = count * #entry.options end
	if count > MAX_MIXES then
		local top = { cost = 0 }
		for i, entry in ipairs(slots) do
			local best = 1
			for o, option in ipairs(entry.options) do
				if option.quality > entry.options[best].quality then best = o end
			end
			top[i] = best
		end
		return { top }
	end

	local mixes = { { cost = 0 } }
	for i, entry in ipairs(slots) do
		local grown = {}
		for _, mix in ipairs(mixes) do
			for o, option in ipairs(entry.options) do
				local nextMix = { cost = mix.cost + option.cost }
				for j = 1, i - 1 do nextMix[j] = mix[j] end
				nextMix[i] = o
				grown[#grown + 1] = nextMix
			end
		end
		mixes = grown
	end
	table.sort(mixes, function(a, b) return a.cost < b.cost end)
	return mixes
end

-- The quality the game predicts for a mix, with what the customer provides, and
-- the concentration that would lift it one rank.
local function predict(order, schematic, slots, mix)
	local reagents = {}
	for _, provided in ipairs(order.reagents or {}) do
		local slot = schematic.reagentSlotSchematics[provided.slotIndex]
		if slot and slot.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent and provided.reagentInfo then
			reagents[#reagents + 1] = provided.reagentInfo
		end
	end
	for i, entry in ipairs(slots) do
		local option = entry.options[mix[i]]
		reagents[#reagents + 1] = { reagent = { itemID = option.itemID }, dataSlotIndex = entry.dataSlotIndex, quantity = entry.qty }
	end
	local ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, order.spellID, reagents, nil, false)
	if ok and info and info.craftingQuality then
		return info.craftingQuality, info.concentrationCost or 0, info.concentrationCurrencyID
	end
end

-- A plan's picks: overrides (slotIndex -> itemID) for pricing and shopping, and
-- the list { itemID, qty } for tooltips.
local function picksOf(slots, mix)
	local overrides, picks = {}, {}
	for i, entry in ipairs(slots) do
		local itemID = entry.options[mix[i]].itemID
		overrides[entry.slotIndex] = itemID
		picks[#picks + 1] = { itemID = itemID, qty = entry.qty }
	end
	return overrides, picks
end

-- Shares out your concentration among the listed orders that need it to reach
-- their minimum quality, in the order the option sets: "profit" (most gold per
-- concentration point first, orders that lose gold last) or "knowledge" (most
-- knowledge per point first, then by profit). Orders left without enough get
-- row.noConcentration. Returns { have, used }, or nil when no order needs any.
function Planner.SpendConcentration(rows, mode)
	local needing, currencyID = {}, nil
	for _, row in ipairs(rows) do
		row.noConcentration = nil
		local plan = row.plan
		if plan and plan.concentration and not plan.unreachable then
			needing[#needing + 1] = row
			currencyID = currencyID or plan.currencyID
		end
	end
	if #needing == 0 then return end
	local info = currencyID and C_CurrencyInfo.GetCurrencyInfo(currencyID)
	local have = Planner.testConcentration or info and info.quantity
	if not have then return end

	local function perPoint(row, amount) return amount / row.plan.concentration end
	table.sort(needing, function(a, b)
		if mode == "knowledge" then
			local aKnow, bKnow = perPoint(a, a.model.knowledge or 0), perPoint(b, b.model.knowledge or 0)
			if aKnow ~= bKnow then return aKnow > bKnow end
		end
		local aGain, bGain = a.model.total > 0, b.model.total > 0
		if aGain ~= bGain then return aGain end
		return perPoint(a, a.model.total) > perPoint(b, b.model.total)
	end)

	local left = have
	for _, row in ipairs(needing) do
		if row.plan.concentration <= left then
			left = left - row.plan.concentration
		else
			row.noConcentration = true
		end
	end
	return { have = have, used = have - left }
end

-- Which qualities a patron order should use, or nil when there's nothing to pick
-- (or the game can't predict the quality):
--   { overrides, picks }                             no minimum: the cheapest of each
--   { minQuality, overrides, picks }                 cheapest mix that reaches the minimum
--   { minQuality, overrides, picks, concentration }  only reached with concentration
--   { minQuality, overrides, picks, unreachable }    not even the top qualities reach it
function Planner.ForOrder(order, schematic, provided)
	if order.isRecraft then return end
	local cached = plans[order.orderID]
	if cached ~= nil then return cached or nil end

	local slots = qualitySlots(schematic, provided)
	local minQuality = order.minQuality or 0
	if Planner.testMinQuality then minQuality = math.max(minQuality, Planner.testMinQuality) end
	if minQuality <= 1 or not schematic.hasCraftingOperationInfo then
		-- Any quality will do, so each slot takes its cheapest.
		local plan = false
		if #slots > 0 then
			local mix = {}
			for i = 1, #slots do mix[i] = 1 end
			plan = {}
			plan.overrides, plan.picks = picksOf(slots, mix)
		end
		plans[order.orderID] = plan
		return plan or nil
	end

	local mixes = mixesOf(slots)
	local plan, withConcentration, predicted, best
	for _, mix in ipairs(mixes) do
		local quality, cost, currencyID = predict(order, schematic, slots, mix)
		if quality then
			predicted = true
			if quality >= minQuality then
				plan = { mix = mix }
				break
			end
			if not withConcentration and quality + 1 >= minQuality and cost > 0 then
				withConcentration = { mix = mix, concentration = cost, currencyID = currencyID }
			end
			if not best or quality > best.quality then best = { mix = mix, quality = quality } end
		end
	end

	if not predicted then
		plans[order.orderID] = false
		return
	end
	plan = plan or withConcentration or { mix = best.mix, unreachable = true }
	plan.minQuality = minQuality
	plan.overrides, plan.picks = picksOf(slots, plan.mix)
	plan.mix = nil
	plans[order.orderID] = plan
	return plan
end
