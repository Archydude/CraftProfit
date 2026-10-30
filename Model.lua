-- Craft Profit: the math. Builds a plain table describing what the panel should
-- show for a craft or an order. No drawing here; Panel.lua draws these tables.
--
-- Model fields shared by both kinds:
--   kind          "craft" | "order"
--   key           recipeID or orderID (procs are matched against it)
--   recipeID
--   title
--   materials     see Model.Materials
--   missing       what's missing for one craft, see Model.Missing
--   missingFor    function(crafts) -> what's missing for that many crafts
--   shoppable     there are materials you supply that the shopping list can buy
--   cost         what the listed materials cost (simulated ones included)
--   total         forecast profit; with nothing to sell, a loss of what the materials cost
--   realCost      what the materials in the form cost (procs use this)
--   realProfit    forecast profit with the form's materials, or nil while simulating
--   canSimulate   materials can be clicked for what-if qualities
--   simulating    some materials are what-if qualities
--   best          more profitable materials than the form's, or nil
--   notes         { estimated = bool, missing = count, [1..n] = extra notes }
--   procs         what multicraft and resourcefulness add on average (Procs.Expected);
--                 on orders resourcefulness only. Nil on recrafts
--   expected      profit with that counted
-- Orders also have:
--   provided      the basic materials the customer sent, { { itemID, qty, price } }
local _, ns = ...

local Model = {}
ns.Model = Model

-- The profit to show and rank by: with Count multicraft and resourcefulness on,
-- the expected profit.
function Model.Shown(model)
	return ns.db.countProcs and model.expected or model.total
end

-- The cheapest quality of a material, for slots the form leaves empty.
local function cheapestQuality(slot)
	local bestID, bestPrice
	for _, reagent in ipairs(slot.reagents) do
		if reagent.itemID then
			local price = ns.Prices.Material(reagent.itemID)
			if not bestID or (price and (not bestPrice or price < bestPrice)) then
				bestID, bestPrice = reagent.itemID, price
			end
		end
	end
	return bestID
end

-- What the form puts in a slot. Empty required slots (you don't own the
-- material yet) get the quality `fill` (slotIndex -> itemID) has for them, or the
-- cheapest one, marked as missing. (Model.Materials also lets `fill` swap out
-- what a slot holds.)
local function formPicks(slotIndex, slot, transaction, fill)
	local picks = ns.Blizzard.Allocated(transaction, slotIndex)
	if #picks == 0 and slot.required and slot.reagentType == Enum.CraftingReagentType.Basic then
		local itemID = fill and fill[slotIndex] or cheapestQuality(slot)
		if itemID then picks[1] = { itemID = itemID, qty = slot.quantityRequired, missing = true } end
	end
	return picks
end

-- The materials you supply:
--   { itemID, qty, price, estimated, simulated, slotIndex, slot, formItemID }
-- `provided` marks slots someone else fills (the customer, on an order).
-- `overrides` (slotIndex -> itemID) swaps in what-if qualities; `fill` (the same)
-- picks the quality of empty slots (see formPicks).
-- formItemID is what the form has in that slot, so a click can tell when it's
-- back to the real thing.
function Model.Materials(schematic, transaction, provided, overrides, fill)
	local list, byItem = {}, {}
	local function add(itemID, qty, slotIndex, slot, flag, formItemID)
		local entry = byItem[itemID]
		if not entry then
			entry = {
				itemID = itemID, qty = 0, price = ns.Prices.Material(itemID),
				estimated = flag == "missing", simulated = flag == "simulated",
				slotIndex = slotIndex, slot = slot, formItemID = formItemID,
			}
			byItem[itemID] = entry
			list[#list + 1] = entry
		end
		entry.qty = entry.qty + qty
	end

	for slotIndex, slot in ipairs(schematic.reagentSlotSchematics) do
		if not provided[slotIndex] then
			local picks = formPicks(slotIndex, slot, transaction, fill)
			-- A slot split over several qualities has no single "form" quality.
			local formItemID = #picks == 1 and picks[1].itemID or nil
			local override = overrides and overrides[slotIndex]
			-- `fill` can also swap out what the form holds (see shortFill).
			local swap = not override and fill and fill[slotIndex]
			if override then
				add(override, slot.quantityRequired, slotIndex, slot, "simulated", formItemID)
			elseif swap and not (#picks == 1 and picks[1].itemID == swap) then
				add(swap, slot.quantityRequired, slotIndex, slot, "missing", formItemID)
			else
				for _, pick in ipairs(picks) do
					add(pick.itemID, pick.qty, slotIndex, slot, pick.missing and "missing" or nil, formItemID)
				end
			end
		end
	end
	return list
end

-- How many of an item you have where crafting takes it from: bags, bank,
-- warband bank.
local function owned(itemID)
	return C_Item.GetItemCount(itemID, true, false, true, true) or 0
end

-- What using `qty` of a material really costs you, or nil without a price. What
-- you'd buy costs its price; what you already own costs what you'd get selling it
-- instead (after the auction house cut, when that option is on).
function Model.EffectiveCost(itemID, qty)
	local price = ns.Prices.Material(itemID)
	if not price then return end
	local own = math.min(owned(itemID), qty)
	local keep = ns.db.ahCut and (1 - ns.AH_CUT) or 1
	return own * price * keep + (qty - own) * price
end

-- The gold you'd spend on `qty` of a material, past what you own, or nil when
-- you'd have to buy some and it has no price.
function Model.BuyCost(itemID, qty)
	local missing = math.max(qty - owned(itemID), 0)
	if missing == 0 then return 0 end
	local price = ns.Prices.Material(itemID)
	return price and missing * price
end

-- For an order you have open: in each slot you fill from your bags, the rank that's
-- cheaper to buy than to use yours, and still meets the order's minimum quality.
-- slotIndex -> { itemID, saves, buyCost, ownValue }. Slots you've picked a quality
-- for, or that are missing, are left alone. With the Patron orders list's `plan`
-- for the order, only the rank it picks is suggested, so this never goes against
-- it (Optimize concentration can pick a dearer rank on purpose).
local function cheaperRanks(ctx, materials, picks, plan)
	local planned = plan and not plan.unreachable and plan.overrides or {}
	local order, schematic, transaction, recipeInfo = ctx.order, ctx.schematic, ctx.transaction, ctx.recipeInfo
	local minQuality = order.minQuality or 0
	local needsQuality = minQuality > 1
	if needsQuality and not (recipeInfo and recipeInfo.supportsQualities) then return {} end

	local inSlot = {}
	for _, material in ipairs(materials) do
		if material.slot and ns.Blizzard.IsQualitySlot(material.slot) then
			local list = inSlot[material.slotIndex] or {}
			list[#list + 1] = material
			inSlot[material.slotIndex] = list
		end
	end

	local found = {}
	for slotIndex, list in pairs(inSlot) do
		local skip, ownValue, usedIDs = false, 0, {}
		for _, material in ipairs(list) do
			if material.simulated or material.estimated then skip = true end
			local value = Model.EffectiveCost(material.itemID, material.qty)
			if not value then skip = true else ownValue = ownValue + value end
			usedIDs[material.itemID] = true
		end
		if not skip then
			local slot = list[1].slot
			for _, reagent in ipairs(slot.reagents) do
				local itemID = reagent.itemID
				local allowed = not planned[slotIndex] or planned[slotIndex] == itemID
				local buyCost = itemID and allowed and not usedIDs[itemID] and Model.EffectiveCost(itemID, slot.quantityRequired)
				local saves = buyCost and ownValue - buyCost
				if saves and saves > 0 and (not found[slotIndex] or saves > found[slotIndex].saves) then
					local meets = true
					if needsQuality then
						local overrides = {}
						for k, v in pairs(picks or {}) do overrides[k] = v end
						overrides[slotIndex] = itemID
						-- Without your skill boosters: the cheaper rank has to do it on its own.
						local quality = ns.Blizzard.PredictQuality(recipeInfo.recipeID, schematic, transaction, overrides, ctx.provided)
						meets = quality ~= nil and quality >= minQuality
					end
					if meets then
						found[slotIndex] = { itemID = itemID, saves = saves, buyCost = buyCost, ownValue = ownValue }
					end
				end
			end
		end
	end
	return found
end
Model.Owned = owned

-- What you're short of for several recipes at once: { { itemID, qty } ... }.
-- `jobs` is a list of { schematic, provided, overrides, crafts }. What you own
-- counts once across all of them, so two orders needing the same material don't
-- both count the same stack. Every quality you own counts toward a slot, as in
-- the form, and the cheapest quality is the one to buy. A what-if pick
-- (`overrides`) counts and buys only that quality.
function Model.MissingForAll(jobs)
	-- One need per set of qualities that can fill a slot.
	local needs, byKey = {}, {}
	for _, job in ipairs(jobs) do
		for slotIndex, slot in ipairs(job.schematic.reagentSlotSchematics) do
			if slot.required and not job.provided[slotIndex] then
				local buyID = job.overrides and job.overrides[slotIndex]
				local counts = {}
				if buyID then
					counts[1] = buyID
				else
					for _, reagent in ipairs(slot.reagents) do
						if reagent.itemID then counts[#counts + 1] = reagent.itemID end
					end
					buyID = cheapestQuality(slot)
				end
				if buyID then
					local key = table.concat(counts, ",")
					local need = byKey[key]
					if not need then
						need = { counts = counts, itemID = buyID, qty = 0 }
						byKey[key] = need
						needs[#needs + 1] = need
					end
					need.qty = need.qty + slot.quantityRequired * (job.crafts or 1)
				end
			end
		end
	end

	local list, byItem = {}, {}
	for _, need in ipairs(needs) do
		local short = need.qty
		for _, itemID in ipairs(need.counts) do short = short - owned(itemID) end
		if short > 0 then
			local entry = byItem[need.itemID]
			if not entry then
				entry = { itemID = need.itemID, qty = 0 }
				byItem[need.itemID] = entry
				list[#list + 1] = entry
			end
			entry.qty = entry.qty + short
		end
	end
	return list
end

-- What you're short of for `crafts` crafts (default 1) of one recipe.
function Model.Missing(schematic, provided, overrides, crafts)
	return Model.MissingForAll({ { schematic = schematic, provided = provided, overrides = overrides, crafts = crafts } })
end

-- Shopping fields of a model: what's missing for one craft, a function for any
-- number of crafts, and whether there's anything you supply that can be bought.
local function addShopping(model, schematic, provided, overrides)
	model.missing = Model.Missing(schematic, provided, overrides)
	model.missingFor = function(crafts) return Model.Missing(schematic, provided, overrides, crafts) end
	model.shoppable = false
	for slotIndex, slot in ipairs(schematic.reagentSlotSchematics) do
		if slot.required and not provided[slotIndex] and cheapestQuality(slot) then
			model.shoppable = true
			break
		end
	end
end

-- Total cost of a material list. With `notes`, also records missing materials
-- and ones without a price.
local function costOf(materials, notes)
	local cost = 0
	for _, material in ipairs(materials) do
		if material.price then
			cost = cost + material.price * material.qty
		elseif notes then
			notes.missing = (notes.missing or 0) + 1
		end
		if notes and material.estimated then notes.estimated = true end
	end
	return cost
end

-- What the basic materials in a list (see Model.Materials) cost: the ones
-- resourcefulness can save.
function Model.BasicCost(materials)
	local cost = 0
	for _, material in ipairs(materials) do
		if material.price and material.slot and material.slot.reagentType == Enum.CraftingReagentType.Basic then
			cost = cost + material.price * material.qty
		end
	end
	return cost
end

-- The basic materials the customer sent for an order: { { itemID, qty, price } }.
-- Resourcefulness saves these too, and what it saves comes back to you.
local function providedBasics(order, schematic)
	local list = {}
	for _, sent in ipairs(order.reagents or {}) do
		local slot = schematic.reagentSlotSchematics[sent.slotIndex]
		local info = sent.reagentInfo
		local itemID = info and (info.reagent and info.reagent.itemID or info.itemID)
		if itemID and slot and slot.reagentType == Enum.CraftingReagentType.Basic then
			list[#list + 1] = { itemID = itemID, qty = info.quantity or slot.quantityRequired, price = ns.Prices.Material(itemID) }
		end
	end
	return list
end

-- The slots where the form holds another quality than the Patron orders list's
-- `plan` picks because you're short of the picked one (Blizzard tops it up with
-- what you have): slotIndex -> the picked itemID, or nil. They're priced and
-- bought at the picked quality, since that's what you'd craft once you've bought
-- it. Slots with a what-if pick are left alone.
local function shortFill(transaction, schematic, plan, picks)
	local fill
	for slotIndex, itemID in pairs(plan.overrides) do
		local inForm = ns.Blizzard.Allocated(transaction, slotIndex)
		local holds = #inForm == 1 and inForm[1].itemID == itemID
		if not picks[slotIndex] and #inForm > 0 and not holds
			and owned(itemID) < schematic.reagentSlotSchematics[slotIndex].quantityRequired then
			fill = fill or {}
			fill[slotIndex] = itemID
		end
	end
	return fill
end

-- Whether the form has something other than `overrides` (slotIndex -> itemID,
-- the full amount each) in those slots.
local function differsFromForm(schematic, transaction, overrides)
	for slotIndex, itemID in pairs(overrides) do
		local inForm = ns.Blizzard.Allocated(transaction, slotIndex)
		local qty = schematic.reagentSlotSchematics[slotIndex].quantityRequired
		if not (#inForm == 1 and inForm[1].itemID == itemID and inForm[1].qty == qty) then return true end
	end
	return false
end

-- For the recipe on the crafting page: the crafting strategy's materials (see
-- Planner.ForCraft), when the form has something else. Same shape as
-- bestMaterials below, plus fromQuality/toQuality when they make another rank
-- than the form; concentration is left as you set it.
local function bestCraftMaterials(ctx, model)
	local schematic, transaction = ctx.schematic, ctx.transaction
	local plan = ns.Planner.ForCraft(ctx)
	if not (plan and differsFromForm(schematic, transaction, plan.overrides)) then return end

	local planned = Model.Craft({ recipeInfo = ctx.recipeInfo, schematic = schematic, transaction = transaction,
		isRecraft = ctx.isRecraft, overrides = plan.overrides })
	-- With no sale price, both are a loss of what the materials cost: the gain is what they save.
	local gain = planned.total - model.realProfit
	-- Worth it even when it costs more, if it makes a better rank than the form.
	local formQuality = plan.quality and ns.Blizzard.PredictQuality(ctx.recipeInfo.recipeID, schematic, transaction, {})
	local otherRank = formQuality and plan.quality ~= formQuality
	local betterRank = otherRank and plan.quality > formQuality
	-- Or, with "Optimize concentration" on, when it takes less than the form does.
	local savesConcentration = ns.db.leastConcentration and plan.concentration
		and (ns.Blizzard.FormConcentrationCost(ctx.recipeInfo.recipeID, schematic, transaction) or 0) > plan.concentration
	-- Or, with "Use what I own", whatever it's worth: spending less is the point.
	local usesOwned = ns.db.craftStrategy == "owned"
	if gain <= 0 and not betterRank and not savesConcentration and not usesOwned then return end
	return { picks = plan.overrides, list = plan.picks, concentrate = false, concentration = plan.concentration,
		savesConcentration = savesConcentration and true or false, usesOwned = usesOwned, gain = gain,
		fromQuality = otherRank and formQuality or nil, toQuality = otherRank and plan.quality or nil }
end

-- What the item at `quality` sells for, capped at what any better rank sells for
-- (see Prices.CapRanks). Also the rank that set the cap, when it did, and the
-- price before the cap.
local function cappedSale(ctx, link, itemID, quality)
	local price = ns.Prices.Sale(link, itemID)
	local qualityIDs = ctx.recipeInfo.qualityIDs
	if not (price and quality and qualityIDs) then return price end
	local sales = { [quality] = price }
	for rank = quality + 1, #qualityIDs do
		local higherLink, higherID = ns.Blizzard.OutputAtQuality(ctx.recipeInfo, ctx.transaction, rank)
		sales[rank] = higherLink and ns.Prices.Sale(higherLink, higherID)
	end
	local capped, cappedBy = ns.Prices.CapRanks(sales, #qualityIDs)
	return capped[quality], cappedBy[quality], price
end

-- The note for a sale price a better rank capped.
function Model.CappedNote(recipeID, rank, listed)
	local icon = ns.Blizzard.ItemQualityMarkup(recipeID, rank) or ("rank " .. rank)
	return string.format("Priced as %s sells: this rank is listed at %s, but the better rank sells for less.",
		icon, ns.Format.Money(listed))
end

-- The crafting strategy's quality (see Planner.ForCraft) for each of the form's
-- empty slots that `picks` (what-if qualities) doesn't set: slotIndex -> itemID,
-- or nil when there are none. So a craft you're still missing materials for is
-- priced, and shopped for, as the strategy would craft it.
local function strategyFill(transaction, plan, picks)
	if not plan then return end
	local fill
	for slotIndex, itemID in pairs(plan.overrides) do
		if not picks[slotIndex] and #ns.Blizzard.Allocated(transaction, slotIndex) == 0 then
			fill = fill or {}
			fill[slotIndex] = itemID
		end
	end
	return fill
end

-- `a` with `b` laid over it, as a new table.
local function merged(a, b)
	local result = {}
	for k, v in pairs(a or {}) do result[k] = v end
	for k, v in pairs(b or {}) do result[k] = v end
	return result
end

-- Model.Materials for a craft: with `scroll`, also the vellum it goes on, which
-- isn't one of the recipe's slots.
local function craftMaterials(scroll, ...)
	local list = Model.Materials(...)
	if scroll then list[#list + 1] = { itemID = ns.VELLUM_ITEM, qty = 1, price = ns.Prices.Material(ns.VELLUM_ITEM) } end
	return list
end

-- What concentration does for the craft the game described in `info`, or nil when
-- it does nothing: { points, on, short = you have too little, icon = the
-- currency's, quality = the rank it would lift this to, gain = what that rank adds
-- per craft }. No `quality` or `gain` while it's on, since the craft already counts it.
local function concentrationOf(ctx, info, quality, model, sold)
	local points = info and info.concentrationCost or 0
	if points <= 0 then return end
	local on = ns.Blizzard.IsConcentrating(ctx.transaction)
	local qualityIDs = ctx.recipeInfo.qualityIDs
	if not on and not (quality and qualityIDs and quality < #qualityIDs) then return end
	local currency = info.concentrationCurrencyID and C_CurrencyInfo.GetCurrencyInfo(info.concentrationCurrencyID)
	local found = { points = points, on = on, short = currency ~= nil and currency.quantity < points,
		icon = currency and currency.iconFileID }
	if on then return found end

	found.quality = quality + 1
	local output = model.output
	local link, itemID = ns.Blizzard.OutputAtQuality(ctx.recipeInfo, ctx.transaction, found.quality)
	local price = link and output and output.sale and cappedSale(ctx, link, itemID, found.quality)
	if price then
		local keep = ns.db.ahCut and (1 - ns.AH_CUT) or 1
		local gain = (price * ((sold.quantityMin or 1) + (sold.quantityMax or 1)) / 2 - output.sale) * keep
		if gain > 0 then found.gain = gain end
	end
	return found
end

-- The recipe selected on the crafting page. With ctx.overrides (slotIndex ->
-- itemID), prices those qualities instead of the form's, for comparing. Nil and
-- true while the crafting strategy's plan is still being worked out (see
-- Planner.ForCraft).
function Model.Craft(ctx)
	local recipeInfo, schematic, transaction = ctx.recipeInfo, ctx.schematic, ctx.transaction
	local planning = ctx.overrides ~= nil
	local simulating = not planning and ns.Simulation.UseFor("craft:" .. recipeInfo.recipeID)
	local picks = planning and ctx.overrides or ns.Simulation.picks
	local notes = {}
	local model = {
		kind = "craft",
		key = recipeInfo.recipeID,
		recipeID = recipeInfo.recipeID,
		title = schematic.name or "Craft",
		canSimulate = true,
		simulating = simulating,
		notes = notes,
	}

	-- What the crafting strategy would craft; its qualities fill the empty slots.
	local plan
	if not (planning or ctx.isRecraft) then
		local pending
		plan, pending = ns.Planner.ForCraft(ctx)
		if pending then return nil, true end
	end
	local fill = strategyFill(transaction, plan, picks)
	-- And the slots the form tops up with another quality because you're short of
	-- the strategy's: what you can craft right now (realCost) still uses those.
	local short = plan and plan.overrides and shortFill(transaction, schematic, plan, picks or {}) or nil
	local filled = short and merged(fill, short) or fill

	-- An enchant on a vellum makes a scroll: what you sell, and what you shop for.
	local scroll = not ctx.isRecraft and ns.Blizzard.MakesScroll(recipeInfo.recipeID, transaction)
	local sold = scroll and ns.Blizzard.ScrollSchematic(schematic) or schematic

	local link, itemID, quality
	if scroll or (not ctx.isRecraft and schematic.recipeType == Enum.TradeskillRecipeType.Item) then
		local predicted
		link, itemID, predicted, quality = ns.Blizzard.ExpectedOutput(ctx, merged(picks, filled))
		if not predicted then
			notes[#notes + 1] = "The game couldn't predict the quality for these materials, so the sale price uses the form's quality."
		end
	end

	if link then
		local qtyMin, qtyMax = sold.quantityMin or 1, sold.quantityMax or 1
		local price, cappedBy, listed = cappedSale(ctx, link, itemID, quality)
		if cappedBy then notes[#notes + 1] = Model.CappedNote(recipeInfo.recipeID, cappedBy, listed) end
		local output = {
			link = link,
			qtyText = qtyMin == qtyMax and tostring(qtyMin) or (qtyMin .. "-" .. qtyMax),
		}
		model.output = output
		if price then
			output.sale = price * (qtyMin + qtyMax) / 2
			model.total = output.sale
			if ns.db.ahCut then
				output.ahCut = output.sale * ns.AH_CUT
				model.total = output.sale - output.ahCut
			end
			if qtyMin ~= qtyMax then notes[#notes + 1] = "Average amount used for the sale price." end
		else
			notes[#notes + 1] = "No auction price for this item, so the loss is what the materials cost."
		end
	elseif ctx.isRecraft then
		notes[#notes + 1] = "Recraft: the loss is what the materials cost."
	else
		notes[#notes + 1] = "Nothing to sell from this recipe: the loss is what the materials cost."
	end

	model.materials = craftMaterials(scroll, schematic, transaction, {}, picks, filled)
	model.cost = costOf(model.materials, notes)
	notes.filled = filled ~= nil
	-- The shopping list buys the strategy's qualities when the form can't make its
	-- rank (or has empty slots); otherwise any quality you own counts. What-if
	-- picks always win: they're the ranks you chose.
	local shopPicks = picks
	if plan and not simulating and (filled or plan.quality and
		(ns.Blizzard.PredictQuality(recipeInfo.recipeID, schematic, transaction, {}) or 0) < plan.quality) then
		shopPicks = plan.overrides
	end
	addShopping(model, sold, {}, shopPicks)
	model.total = (model.total or 0) - model.cost

	-- What multicraft and resourcefulness add on average (see Procs.Expected).
	if not (planning or ctx.isRecraft) then
		local info = ns.Blizzard.CraftInfo(ctx, merged(picks, filled))
		local chances = ns.Procs.Chances(info)
		model.concentration = concentrationOf(ctx, info, quality, model, sold)
		local output = model.output
		local sale = output and output.sale and output.sale - (output.ahCut or 0)
		model.procs = ns.Procs.Expected(ns.Procs.ProfessionOf(recipeInfo.recipeID), chances, sale,
			Model.BasicCost(model.materials))
		model.expected = model.total + model.procs.total
	end

	-- Real crafts use what's in the form, never the what-if picks, nor the
	-- strategy's qualities you're short of.
	model.realCost = (simulating or short) and costOf(craftMaterials(scroll, schematic, transaction, {}, nil, fill)) or model.cost
	model.realProfit = not simulating and (model.total + model.cost - model.realCost) or nil
	if not (planning or simulating or ctx.isRecraft) then model.best = bestCraftMaterials(ctx, model) end
	return model
end

-- For an order open in the form: the materials that make it the most gold while
-- still reaching its minimum quality (the same picks as the Patron orders list),
-- when the form has something else. { picks = slotIndex -> itemID, list = { {
-- itemID, qty } ... }, concentrate, concentration = what it takes or nil, gain =
-- gold more than the form makes }, or nil.
local function bestMaterials(ctx, model)
	local order, schematic, transaction = ctx.order, ctx.schematic, ctx.transaction
	local plan = ns.Planner.ForOrder(order, schematic, ctx.provided)
	if not (plan and plan.overrides and next(plan.overrides)) or plan.unreachable then return end
	-- Patron orders kept off concentration ("Don't use concentration"): these
	-- materials only reach the minimum with it, so nothing is offered.
	if plan.concentration and ns.db.concentrationFor == "none" and order.orderType == Enum.CraftingOrderType.Npc then
		return
	end

	local concentrate = plan.concentration ~= nil and not ns.Blizzard.IsConcentrating(transaction)
	if not (concentrate or differsFromForm(schematic, transaction, plan.overrides)) then return end

	local planned = Model.Order({ order = order, schematic = schematic, provided = ctx.provided, overrides = plan.overrides })
	local gain = planned.total - model.realProfit
	-- Also worth it when it makes less, if the form misses the minimum quality.
	-- The form is judged without your skill boosters, like the plan.
	local minQuality = order.minQuality or 0
	local belowMinimum = minQuality > 1 and ctx.recipeInfo
		and (ns.Blizzard.PredictQuality(ctx.recipeInfo.recipeID, schematic, transaction, {}, ctx.provided) or 0) < minQuality
	-- Or, with "Optimize concentration" on, when it takes less than the form does.
	local savesConcentration = ns.db.leastConcentration and plan.concentration and ctx.recipeInfo
		and ns.Blizzard.IsConcentrating(transaction)
		and (ns.Blizzard.FormConcentrationCost(ctx.recipeInfo.recipeID, schematic, transaction, ctx.provided) or 0)
			> plan.concentration
	if gain <= 0 and not belowMinimum and not savesConcentration then return end
	return { picks = plan.overrides, list = plan.picks, concentrate = concentrate, concentration = plan.concentration,
		savesConcentration = savesConcentration and true or false, gain = gain }
end

-- The open crafting order, or one listed on the Patron tab.
function Model.Order(ctx)
	local order, schematic, transaction = ctx.order, ctx.schematic, ctx.transaction
	-- What-if needs the order screen's form; not on recrafts, where the customer's item decides.
	local canSimulate = (ctx.live and transaction and not order.isRecraft and schematic.hasCraftingOperationInfo) and true or false
	local simulating = canSimulate and ns.Simulation.UseFor("order:" .. tostring(order.orderID)) or false
	-- Without the form, ctx.overrides can set qualities (the Patron list's picks
	-- for an order's minimum quality).
	local picks = canSimulate and ns.Simulation.picks or ctx.overrides
	local notes = {}
	local model = {
		kind = "order",
		key = order.orderID,
		recipeID = order.spellID,
		title = "Crafting Order",
		commission = order.tipAmount,
		consortiumCut = order.consortiumCut,
		receive = order.tipAmount - order.consortiumCut,
		canSimulate = canSimulate,
		simulating = simulating,
		notes = notes,
	}

	local recipeInfo = ctx.recipeInfo
	-- The Patron orders list's picks for this order (see Planner.ForOrder). Like the
	-- crafting strategy's on the crafting page, they fill the slots the form leaves
	-- empty (materials you don't have enough of), so those are priced and bought at
	-- the quality the list picked, not the cheapest.
	local plan = canSimulate and not simulating and recipeInfo and ns.Planner.ForOrder(order, schematic, ctx.provided)
	local usable = plan and plan.overrides and not plan.unreachable
	local fill = usable and strategyFill(transaction, plan, picks or {}) or nil
	-- And the slots the form tops up with another quality because you're short of
	-- the picked one: what you can craft right now (realCost) still uses those.
	local short = usable and shortFill(transaction, schematic, plan, picks or {}) or nil
	local filled = short and merged(fill, short) or fill
	model.materials = Model.Materials(schematic, transaction, ctx.provided, picks, filled)
	model.cost = costOf(model.materials, notes)
	notes.filled = filled ~= nil
	-- When the form doesn't reach the order's minimum quality (without your skill
	-- boosters), the shopping list buys the ranks that do: the list's picks.
	-- Otherwise any rank you own counts, and the cheapest one is bought, except in
	-- the slots the picks fill. What-if picks always win: they're the ranks you chose.
	local shopPicks = filled and merged(picks, filled) or picks
	if plan and plan.minQuality and plan.overrides and next(plan.overrides) and not plan.unreachable
		and (ns.Blizzard.PredictQuality(recipeInfo.recipeID, schematic, transaction, {}, ctx.provided) or 0) < plan.minQuality then
		shopPicks = plan.overrides
	end
	addShopping(model, schematic, ctx.provided, shopPicks)
	model.cheaper = canSimulate and cheaperRanks(ctx, model.materials, picks, plan) or {}

	-- While simulating: the quality the picked materials give, and whether it meets
	-- the order. Only for items that come in qualities; others are always "quality 1".
	if simulating and recipeInfo and recipeInfo.supportsQualities then
		local quality, concentration = ns.Blizzard.PredictQuality(recipeInfo.recipeID, schematic, transaction, picks)
		local markup = quality and ns.Blizzard.ItemQualityMarkup(order.spellID, quality)
		if markup then
			model.simulatedQuality = {
				markup = markup,
				-- The concentration that quality spends, or nil without it.
				concentration = concentration,
				-- Icon of the order's minimum quality, when the pick falls short of it.
				belowMinimum = (order.minQuality or 0) > 1 and quality < order.minQuality
					and ns.Blizzard.ItemQualityMarkup(order.spellID, order.minQuality) or nil,
			}
		elseif not quality then
			notes[#notes + 1] = "The game couldn't predict the quality for these materials."
		end
	end

	-- What an NPC (patron) order gives on top of the commission. Sellable items
	-- count toward profit; currencies (Moxie...) have no gold value.
	model.rewards = {}
	model.knowledge = 0
	local rewardsValue = 0
	for _, reward in ipairs(order.npcOrderRewards or {}) do
		local qty = reward.count or 1
		local itemID = reward.itemLink and C_Item.GetItemInfoInstant(reward.itemLink)
		if itemID then
			local price = ns.Prices.Sale(reward.itemLink, itemID)
			local value = price and price * qty
			local knowledge = ns.KNOWLEDGE_ITEMS[itemID]
			rewardsValue = rewardsValue + (value or 0)
			model.knowledge = model.knowledge + (knowledge or 0) * qty
			model.rewards[#model.rewards + 1] = { itemID = itemID, qty = qty, value = value, knowledge = knowledge }
		elseif reward.currencyType then
			local currency = C_CurrencyInfo.GetCurrencyInfo(reward.currencyType)
			if currency then model.rewards[#model.rewards + 1] = { currency = currency, qty = qty } end
		end
	end

	model.total = model.receive - model.cost + rewardsValue

	-- What resourcefulness gives back on average (see Procs.Expected): of what you
	-- supply, and of what the customer sent, which comes back to you too. The
	-- customer gets the item, so multicraft adds nothing.
	model.provided = providedBasics(order, schematic)
	if not order.isRecraft then
		local chances = ctx.transaction and recipeInfo and ns.Procs.Chances(ns.Blizzard.CraftInfo(ctx, merged(picks, filled)))
			or ns.Procs.RecipeChances(order.spellID)
		chances.multicraft = 0
		model.procs = ns.Procs.Expected(ns.Procs.ProfessionOf(order.spellID), chances, nil,
			Model.BasicCost(model.materials) + costOf(model.provided))
		model.expected = model.total + model.procs.total
	end

	-- Real crafts use what's in the form, never the what-if picks, nor the picked
	-- qualities you're short of.
	model.realCost = (simulating and costOf(Model.Materials(schematic, transaction, ctx.provided)))
		or (short and costOf(Model.Materials(schematic, transaction, ctx.provided, nil, fill)))
		or model.cost
	model.realProfit = model.receive - model.realCost + rewardsValue
	model.best = canSimulate and bestMaterials(ctx, model) or nil
	return model
end
