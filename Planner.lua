-- Craft Profit: which material qualities a patron order should use, for the
-- Patron order list: the cheapest ones that still meet the order's minimum
-- quality. "Cheapest" counts what you own at what it would sell for, so a rank
-- you have only loses to a cheaper one when buying that really comes out ahead.
-- Also, for the recipe on the crafting page, the ones the crafting strategy picks
-- (see ns.STRATEGIES).
local _, ns = ...

local format = string.format

local Planner = {}
ns.Planner = Planner

-- Most quality mixes tried for one order (5 slots of 3 qualities). Past that,
-- only the top qualities are tried.
local MAX_MIXES = 243
-- Cost given to a material with no price, so mixes with it are tried last.
local UNPRICED = 1e12
-- Milliseconds the crafting page's plan may spend asking the game in one frame. A
-- recipe with more mixes than that is worked out over the next frames.
local PLAN_BUDGET_MS = 5

-- orderID -> plan, until the order list changes.
local plans = {}
-- The crafting page's plan, and what it was made for (see Planner.ForCraft).
local craftPlan, craftPlanKey
-- What the game predicted for each mix of qualities. What you own doesn't change
-- that, so it outlasts the plans: until your skill changes (see skillKey) or the
-- form's other slots do. context -> mix (see mixKey) -> { quality, concentration,
-- currencyID }, or false when the game couldn't say.
local predictions = {}

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
	craftPlan, craftPlanKey = nil, nil
end

-- Your skill in the recipe's profession, gear and buffs included, as text: the
-- game's answers change with it.
local function skillKey(recipeID)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	return info and format("%d+%d", info.skillLevel or 0, info.skillModifier or 0) or "?"
end

-- The predictions kept for a context (see predictions).
local function predictionsFor(context)
	local list = predictions[context]
	if not list then
		list = {}
		predictions[context] = list
	end
	return list
end

-- A mix as text: the itemID it picks in each slot.
local function mixKey(slots, mix)
	local parts = {}
	for i, entry in ipairs(slots) do parts[i] = entry.options[mix[i]].itemID end
	return table.concat(parts, ",")
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
-- or only the top qualities when there are more than `maxMixes` (default
-- MAX_MIXES) to try.
local function mixesOf(slots, maxMixes)
	local count = 1
	for _, entry in ipairs(slots) do count = count * #entry.options end
	if count > (maxMixes or MAX_MIXES) then
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
Planner.QualitySlots, Planner.Mixes = qualitySlots, mixesOf

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
-- concentration point first, orders that lose gold last), "knowledge" (most
-- knowledge per point first, then by profit) or "none" (no order gets any).
-- Orders left without enough get row.noConcentration. Returns { have, used }, or
-- nil when no order needs any or none is spent.
function Planner.SpendConcentration(rows, mode)
	local needing, currencyID = {}, nil
	for _, row in ipairs(rows) do
		row.noConcentration = nil
		local plan = row.plan
		if plan and plan.concentration and not plan.unreachable then
			needing[#needing + 1] = row
			currencyID = currencyID or plan.currencyID
			if mode == "none" then row.noConcentration = true end
		end
	end
	if #needing == 0 or mode == "none" then return end
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
--   { minQuality, overrides, picks, concentration }  only reached with concentration:
--                                                    the cheapest mix that does it, or with the
--                                                    "Optimize concentration" option, the mix that
--                                                    takes the least (the cheapest of those)
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
	local least = ns.db.leastConcentration
	local known = predictionsFor(format("order:%s:%s", tostring(order.orderID), skillKey(order.spellID)))
	local plan, withConcentration, predicted, best
	for _, mix in ipairs(mixes) do
		local key = mixKey(slots, mix)
		local found = known[key]
		if found == nil then
			local quality, cost, currencyID = predict(order, schematic, slots, mix)
			found = quality and { quality, cost, currencyID } or false
			known[key] = found
		end
		local quality, cost, currencyID
		if found then quality, cost, currencyID = found[1], found[2], found[3] end
		if quality then
			predicted = true
			if quality >= minQuality then
				plan = { mix = mix }
				break
			end
			-- Mixes come cheapest first, so a later one only wins on less concentration.
			if quality + 1 >= minQuality and cost > 0
				and (not withConcentration or least and cost < withConcentration.concentration) then
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

-- What the game's answers for a crafting page plan depend on: the recipe, your
-- skill, its concentration, and what's in the slots the plan doesn't pick
-- (optional and finishing reagents can change the rank).
local function craftContext(recipeID, schematic, transaction, slots, concentrating)
	local parts = { "craft", recipeID, skillKey(recipeID), tostring(concentrating) }
	local picked = {}
	for _, entry in ipairs(slots) do picked[entry.slotIndex] = true end
	for slotIndex in ipairs(schematic.reagentSlotSchematics) do
		if not picked[slotIndex] then
			for _, pick in ipairs(ns.Blizzard.Allocated(transaction, slotIndex)) do
				parts[#parts + 1] = format("%d=%dx%d", slotIndex, pick.itemID, pick.qty)
			end
		end
	end
	return table.concat(parts, ":")
end

-- What a craft at each rank sells for: `sales` (rank -> the item's price) capped
-- at what better ranks sell for (see Prices.CapRanks), times the average amount
-- a craft makes, after the AH cut. Also rank -> the rank that set a cap.
function Planner.RankPrices(sales, maxRank, schematic)
	local capped, cappedBy = ns.Prices.CapRanks(sales, maxRank)
	local qtyMin, qtyMax = schematic.quantityMin or 1, schematic.quantityMax or 1
	local keep = ns.db.ahCut and (1 - ns.AH_CUT) or 1
	local perCraft = {}
	for rank, price in pairs(capped) do perCraft[rank] = price * (qtyMin + qtyMax) / 2 * keep end
	return perCraft, cappedBy
end

-- Picking one of `options` ({ cost, quality } each, cost being what its materials
-- really cost you) to craft. Each returns nil without options.

-- The highest rank they reach, the cheapest way. A lower rank is never the one to
-- make when a better one is in reach: buyers want the best, whatever a lower rank
-- happens to be listed at.
function Planner.HighestRank(options)
	local best
	for _, option in ipairs(options) do
		if option.quality and (not best or option.quality > best.quality
			or (option.quality == best.quality and option.cost < best.cost)) then
			best = option
		end
	end
	return best
end

-- The one whose rank's price (`prices`, rank -> per craft, see Planner.RankPrices)
-- beats its cost (times `costFactor`, default 1) by the most, the cheaper one on
-- a tie; also that profit. Nil when no rank they reach has a price.
function Planner.MostProfitable(options, prices, costFactor)
	local best, bestProfit
	for _, option in ipairs(options) do
		local price = option.quality and prices[option.quality]
		if price then
			local profit = price - option.cost * (costFactor or 1)
			if not best or profit > bestProfit or (profit == bestProfit and option.cost < best.cost) then
				best, bestProfit = option, profit
			end
		end
	end
	return best, bestProfit
end

-- The cheapest, the higher rank on a tie.
function Planner.Cheapest(options)
	local best
	for _, option in ipairs(options) do
		if option.quality and (not best or option.cost < best.cost
			or (option.cost == best.cost and option.quality > best.quality)) then
			best = option
		end
	end
	return best
end

-- The one the crafting strategy picks (ns.db.craftStrategy). `prices` and
-- `costFactor` are only needed for "Most profit" (see Planner.MostProfitable).
function Planner.Choose(options, prices, costFactor)
	local strategy = ns.db.craftStrategy
	if strategy == "profit" then return (Planner.MostProfitable(options, prices, costFactor)) end
	if strategy == "cheapest" then return Planner.Cheapest(options) end
	return Planner.HighestRank(options)
end

-- The plan, or nil. Also true when this frame's share of asking the game
-- (PLAN_BUDGET_MS) ran out before every mix was asked about.
local function planCraft(recipeInfo, schematic, transaction, slots, context)
	local function planOf(mix, quality, concentration)
		local plan = { quality = quality, concentration = concentration }
		plan.overrides, plan.picks = picksOf(slots, mix)
		return plan
	end
	if not (schematic.hasCraftingOperationInfo and recipeInfo.qualityIDs) then
		-- The item has no ranks, so each slot takes its cheapest.
		local mix = {}
		for i = 1, #slots do mix[i] = 1 end
		return planOf(mix)
	end

	-- Each rank the mixes reach: its cheapest mix, or with "Optimize concentration",
	-- the one that takes the least (mixes come cheapest first, so a later one only
	-- wins on less concentration).
	local least = ns.db.leastConcentration
	local known = predictionsFor(context)
	local deadline = debugprofilestop() + PLAN_BUDGET_MS
	local byQuality = {}
	for _, mix in ipairs(mixesOf(slots)) do
		local key = mixKey(slots, mix)
		local predicted = known[key]
		if predicted == nil then
			if debugprofilestop() > deadline then return nil, true end
			local overrides = picksOf(slots, mix)
			local quality, concentration = ns.Blizzard.PredictQuality(recipeInfo.recipeID, schematic, transaction, overrides)
			predicted = quality and { quality, concentration } or false
			known[key] = predicted
		end
		local quality, concentration
		if predicted then quality, concentration = predicted[1], predicted[2] end
		if quality then
			local found = byQuality[quality]
			if not found or (least and concentration and found.concentration and concentration < found.concentration) then
				byQuality[quality] = { mix = mix, cost = mix.cost, quality = quality, concentration = concentration }
			end
		end
	end
	if not next(byQuality) then return end

	-- The rank the crafting strategy picks. "Most profit" needs each rank's price,
	-- and with procs counted, what multicraft and resourcefulness add.
	local options = {}
	for _, found in pairs(byQuality) do options[#options + 1] = found end
	local prices, costFactor = {}, 1
	if ns.db.craftStrategy == "profit" then
		local sales = {}
		for quality = 1, #recipeInfo.qualityIDs do
			local link, itemID = ns.Blizzard.OutputAtQuality(recipeInfo, transaction, quality)
			sales[quality] = link and ns.Prices.Sale(link, itemID)
		end
		prices = Planner.RankPrices(sales, #recipeInfo.qualityIDs, schematic)
		local info = ns.Blizzard.CraftInfo({ recipeInfo = recipeInfo, schematic = schematic, transaction = transaction })
		local multiply
		multiply, costFactor = ns.Procs.Factors(ns.Procs.ProfessionOf(recipeInfo.recipeID), ns.Procs.Chances(info))
		for quality, price in pairs(prices) do prices[quality] = price * multiply end
	end
	local best = Planner.Choose(options, prices, costFactor)
	local noPrice = best == nil
	if noPrice then
		-- "Most profit" with no price at any rank: the cheapest mix that keeps the form's rank.
		local formQuality = ns.Blizzard.PredictQuality(recipeInfo.recipeID, schematic, transaction, {})
		for quality, found in pairs(byQuality) do
			if (not formQuality or quality >= formQuality) and (not best or found.cost < best.cost) then best = found end
		end
	end
	if not best then return end
	local plan = planOf(best.mix, best.quality, best.concentration)
	plan.noPrice = noPrice
	return plan
end

-- Which qualities the recipe on the crafting page should use, with what's in the
-- form's other slots and its concentration as they are: the rank the crafting
-- strategy picks, made the cheapest way (with concentration and "Optimize
-- concentration": the way that takes the least, the cheapest of those). For "Most
-- profit" with no sale price at any rank (noPrice), the cheapest mix that keeps
-- the form's rank. { overrides, picks, quality, concentration, noPrice }, or nil.
-- Also true while a recipe with many mixes is still being worked out: ask again
-- next frame.
function Planner.ForCraft(ctx)
	local recipeInfo, schematic, transaction = ctx.recipeInfo, ctx.schematic, ctx.transaction
	local slots = qualitySlots(schematic, {})
	if #slots == 0 then return end
	local context = craftContext(recipeInfo.recipeID, schematic, transaction, slots, ns.Blizzard.IsConcentrating(transaction))
	local key = format("%s:%s:%s:%s", context, tostring(ns.db.leastConcentration), ns.db.craftStrategy,
		tostring(ns.db.countProcs))
	if key ~= craftPlanKey then
		local plan, pending = planCraft(recipeInfo, schematic, transaction, slots, context)
		if pending then return nil, true end
		craftPlan, craftPlanKey = plan or false, key
	end
	return craftPlan or nil
end

-- Specializations and profession gear change the game's answers.
local events = CreateFrame("Frame")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("PROFESSION_EQUIPMENT_CHANGED")
events:SetScript("OnEvent", function()
	wipe(predictions)
	Planner.Reset()
end)
