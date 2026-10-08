-- Craft Profit: the math. Builds a plain table describing what the panel should
-- show for a craft or an order. No drawing here; Panel.lua draws these tables.
--
-- Model fields shared by both kinds:
--   kind          "craft" | "order"
--   key           recipeID or orderID (procs are matched against it)
--   title
--   recipe        { recipeID, isRecraft }, for Blizzard's recipe tracker
--   materials     see Model.Materials
--   missing       what's missing for one craft, see Model.Missing
--   missingFor    function(crafts) -> what's missing for that many crafts
--   shoppable     there are materials you supply that the shopping list can buy
--   cost         what the listed materials cost (simulated ones included)
--   total         forecast profit, or nil when there's no sale price
--   realCost      what the materials in the form cost (procs use this)
--   realProfit    forecast profit with the form's materials, or nil
--   canSimulate   materials can be clicked for what-if qualities
--   simulating    some materials are what-if qualities
--   notes         { estimated = bool, missing = count, [1..n] = extra notes }
local _, ns = ...

local Model = {}
ns.Model = Model

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
-- material yet) get the cheapest quality, marked as missing.
local function formPicks(slotIndex, slot, transaction)
	local picks = ns.Blizzard.Allocated(transaction, slotIndex)
	if #picks == 0 and slot.required and slot.reagentType == Enum.CraftingReagentType.Basic then
		local itemID = cheapestQuality(slot)
		if itemID then picks[1] = { itemID = itemID, qty = slot.quantityRequired, missing = true } end
	end
	return picks
end

-- The materials you supply:
--   { itemID, qty, price, estimated, simulated, slotIndex, slot, formItemID }
-- `provided` marks slots someone else fills (the customer, on an order).
-- `overrides` (slotIndex -> itemID) swaps in what-if qualities.
-- formItemID is what the form has in that slot, so a click can tell when it's
-- back to the real thing.
function Model.Materials(schematic, transaction, provided, overrides)
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
			local picks = formPicks(slotIndex, slot, transaction)
			-- A slot split over several qualities has no single "form" quality.
			local formItemID = #picks == 1 and picks[1].itemID or nil
			local override = overrides and overrides[slotIndex]
			if override then
				add(override, slot.quantityRequired, slotIndex, slot, "simulated", formItemID)
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

-- The recipe selected on the crafting page.
function Model.Craft(ctx)
	local recipeInfo, schematic, transaction = ctx.recipeInfo, ctx.schematic, ctx.transaction
	local simulating = ns.Simulation.UseFor("craft:" .. recipeInfo.recipeID)
	local picks = ns.Simulation.picks
	local notes = {}
	local model = {
		kind = "craft",
		key = recipeInfo.recipeID,
		recipe = { recipeID = recipeInfo.recipeID, isRecraft = ctx.isRecraft },
		title = schematic.name or "Craft",
		canSimulate = true,
		simulating = simulating,
		notes = notes,
	}

	local link, itemID
	if not ctx.isRecraft and schematic.recipeType == Enum.TradeskillRecipeType.Item then
		local predicted
		link, itemID, predicted = ns.Blizzard.ExpectedOutput(ctx, picks)
		if not predicted then
			notes[#notes + 1] = "The game couldn't predict the quality for these materials, so the sale price uses the form's quality."
		end
	end

	if link then
		local qtyMin, qtyMax = schematic.quantityMin or 1, schematic.quantityMax or 1
		local price = ns.Prices.Sale(link, itemID)
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
			notes[#notes + 1] = "No auction price for this item, so no profit shown."
		end
	elseif ctx.isRecraft then
		notes[#notes + 1] = "Recraft: showing material cost only."
	else
		notes[#notes + 1] = "Nothing to sell from this recipe: material cost only."
	end

	model.materials = Model.Materials(schematic, transaction, {}, picks)
	model.cost = costOf(model.materials, notes)
	addShopping(model, schematic, {}, picks)
	if model.total then model.total = model.total - model.cost end

	-- Real crafts use what's in the form, never the what-if picks.
	model.realCost = simulating and costOf(Model.Materials(schematic, transaction, {})) or model.cost
	model.realProfit = not simulating and model.total or nil
	return model
end

-- The open crafting order.
function Model.Order(ctx)
	local order, schematic, transaction = ctx.order, ctx.schematic, ctx.transaction
	-- What-if needs the order screen's form; not on recrafts, where the customer's item decides.
	local canSimulate = (ctx.live and transaction and not order.isRecraft and schematic.hasCraftingOperationInfo) and true or false
	local simulating = canSimulate and ns.Simulation.UseFor("order:" .. tostring(order.orderID)) or false
	local picks = canSimulate and ns.Simulation.picks or nil
	local notes = {}
	local model = {
		kind = "order",
		key = order.orderID,
		recipe = { recipeID = order.spellID, isRecraft = order.isRecraft or false },
		title = "Crafting Order",
		commission = order.tipAmount,
		consortiumCut = order.consortiumCut,
		receive = order.tipAmount - order.consortiumCut,
		canSimulate = canSimulate,
		simulating = simulating,
		notes = notes,
	}

	model.materials = Model.Materials(schematic, transaction, ctx.provided, picks)
	model.cost = costOf(model.materials, notes)
	addShopping(model, schematic, ctx.provided, picks)

	-- While simulating: the quality the picked materials give, and whether it meets
	-- the order. Only for items that come in qualities; others are always "quality 1".
	local recipeInfo = ctx.recipeInfo
	if simulating and recipeInfo and recipeInfo.supportsQualities then
		local quality = ns.Blizzard.PredictQuality(recipeInfo.recipeID, schematic, transaction, picks)
		local markup = quality and ns.Blizzard.ItemQualityMarkup(order.spellID, quality)
		if markup then
			model.simulatedQuality = {
				markup = markup,
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
	local rewardsValue = 0
	for _, reward in ipairs(order.npcOrderRewards or {}) do
		local qty = reward.count or 1
		local itemID = reward.itemLink and C_Item.GetItemInfoInstant(reward.itemLink)
		if itemID then
			local price = ns.Prices.Sale(reward.itemLink, itemID)
			local value = price and price * qty
			rewardsValue = rewardsValue + (value or 0)
			model.rewards[#model.rewards + 1] = { itemID = itemID, qty = qty, value = value }
		elseif reward.currencyType then
			local currency = C_CurrencyInfo.GetCurrencyInfo(reward.currencyType)
			if currency then model.rewards[#model.rewards + 1] = { currency = currency, qty = qty } end
		end
	end

	model.total = model.receive - model.cost + rewardsValue
	-- Real crafts use what's in the form, never the what-if picks.
	model.realCost = simulating and costOf(Model.Materials(schematic, transaction, ctx.provided)) or model.cost
	model.realProfit = model.receive - model.realCost + rewardsValue
	return model
end
