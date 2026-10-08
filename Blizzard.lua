-- Craft Profit: everything that reads Blizzard's profession window internals
-- (frame fields, the crafting form's "transaction", mixin methods). Blizzard can
-- change these in any patch, so they live here and nowhere else.
--
-- The addon only ever reads them and follows them with hooks, so it can't
-- interfere with Blizzard's own crafting code.
local _, ns = ...

local Blizzard = {}
ns.Blizzard = Blizzard

-- The order the order screen last showed (from its SetOrder).
local currentOrder

function Blizzard.IsLoaded()
	return ProfessionsFrame and ProfessionsFrame.OrdersPage and ProfessionsFrame.CraftingPage and true or false
end

-- Calls onChange() whenever what the panel shows may have changed.
function Blizzard.Watch(onChange, owner)
	local orderView = ProfessionsFrame.OrdersPage.OrderView
	hooksecurefunc(orderView, "SetOrder", function(_, order)
		currentOrder = order
		onChange()
	end)
	orderView:HookScript("OnShow", onChange)
	orderView:HookScript("OnHide", onChange)

	local craftPage = ProfessionsFrame.CraftingPage
	hooksecurefunc(craftPage.SchematicForm, "Init", onChange)
	-- Fires when the expected quality changes (materials, concentration).
	hooksecurefunc(craftPage.SchematicForm, "UpdateDetailsStats", onChange)
	craftPage:HookScript("OnShow", onChange)
	craftPage:HookScript("OnHide", onChange)

	EventRegistry:RegisterCallback("Professions.AllocationUpdated", onChange, owner)
	EventRegistry:RegisterCallback("Professions.TransactionUpdated", onChange, owner)
end

-- Which page is showing: "order", "craft" or nil.
function Blizzard.ActivePage()
	if ProfessionsFrame.OrdersPage.OrderView:IsVisible() and currentOrder then
		return "order"
	end
	local craftPage = ProfessionsFrame.CraftingPage
	if craftPage:IsVisible() and craftPage.SchematicForm:IsVisible() then
		return "craft"
	end
end

-- The recipe on the crafting page: { recipeInfo, schematic, transaction, isRecraft }.
function Blizzard.CraftContext()
	local form = ProfessionsFrame.CraftingPage.SchematicForm
	local recipeInfo, schematic, transaction = form:GetRecipeInfo(), form.recipeSchematic, form.transaction
	if not (recipeInfo and schematic and transaction) then return end
	return {
		recipeInfo = recipeInfo,
		schematic = schematic,
		transaction = transaction,
		isRecraft = transaction.IsRecraft and transaction:IsRecraft() or false,
	}
end

-- The open crafting order: { order, schematic, transaction, recipeInfo, provided, live }.
-- `provided` marks the slots the customer filled; `live` is true when the order
-- screen's form belongs to this order.
function Blizzard.OrderContext()
	local order = currentOrder
	if not order then return end
	local view = ProfessionsFrame.OrdersPage.OrderView
	local form = view.OrderDetails and view.OrderDetails.SchematicForm
	local live = form ~= nil and view.order == order

	-- Use the order screen's own recipe data so slot numbers match its form.
	local schematic = (live and form.recipeSchematic)
		or C_TradeSkillUI.GetRecipeSchematic(order.spellID, order.isRecraft)
	if not schematic then return end

	-- The order's own list is always right. Blizzard's table adds recraft
	-- modifications, but it's left empty once the order has been crafted, so it
	-- can't be used on its own.
	local provided = {}
	for _, reagent in ipairs(order.reagents) do provided[reagent.slotIndex] = true end
	if live and view.reagentSlotProvidedByCustomer then
		for slotIndex in pairs(view.reagentSlotProvidedByCustomer) do provided[slotIndex] = true end
	end

	return {
		order = order,
		schematic = schematic,
		transaction = form and form.transaction,
		recipeInfo = form and form:GetRecipeInfo(),
		provided = provided,
		live = live,
	}
end

-- What the form has in a slot: { { itemID, qty } ... }.
function Blizzard.Allocated(transaction, slotIndex)
	local list = {}
	local allocations = transaction and transaction.GetAllocations and transaction:GetAllocations(slotIndex)
	if allocations and allocations.Enumerate then
		for _, allocation in allocations:Enumerate() do
			local reagent, qty = allocation:GetReagent(), allocation:GetQuantity()
			if reagent and reagent.itemID and qty and qty > 0 then
				list[#list + 1] = { itemID = reagent.itemID, qty = qty }
			end
		end
	end
	return list
end

-- A material that comes in several qualities (Blizzard's own rule for showing
-- its quality picker).
function Blizzard.IsQualitySlot(slot)
	return slot.reagentType == Enum.CraftingReagentType.Basic and #slot.reagents > 1
end

-- The reagent list the game uses to predict quality: what's in the form, with
-- picked qualities (slotIndex -> itemID) swapped in. Same shape Blizzard's form builds.
local function reagentsForPrediction(schematic, transaction, overrides)
	if not next(overrides) then return transaction:CreateCraftingReagentInfoTbl() end
	local list = {}
	for slotIndex, slot in ipairs(schematic.reagentSlotSchematics) do
		if slot.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent then
			local override = overrides[slotIndex]
			if override then
				list[#list + 1] = { reagent = { itemID = override }, dataSlotIndex = slot.dataSlotIndex, quantity = slot.quantityRequired }
			else
				local allocations = transaction:GetAllocations(slotIndex)
				if allocations then
					for _, allocation in allocations:Enumerate() do
						local qty = allocation:GetQuantity()
						if qty > 0 then
							list[#list + 1] = { reagent = allocation:GetReagent(), dataSlotIndex = slot.dataSlotIndex, quantity = qty }
						end
					end
				end
			end
		end
	end
	return list
end

-- Asks the game how a craft with these materials turns out. The game may reject a
-- made-up material list (that's what what-if builds), so these calls are guarded.
local function operationInfo(recipeID, reagents, transaction)
	local guid = transaction:GetAllocationItemGUID()
	local concentrating = transaction.IsApplyingConcentration and transaction:IsApplyingConcentration() or false
	local ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, reagents, guid, concentrating)
	if not (ok and info) and concentrating then
		-- Changed materials can raise the concentration cost past what you have.
		ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, reagents, guid, false)
	end
	return ok and info or nil
end

-- The quality tier the game predicts for these materials, or nil.
function Blizzard.PredictQuality(recipeID, schematic, transaction, overrides)
	local info = operationInfo(recipeID, reagentsForPrediction(schematic, transaction, overrides), transaction)
	return info and info.craftingQuality
end

-- The item a craft makes at its predicted quality: link, itemID, and whether the
-- game could predict the quality for the picked qualities (if not, the form's own
-- materials are used).
function Blizzard.ExpectedOutput(ctx, overrides)
	local recipeInfo, schematic, transaction = ctx.recipeInfo, ctx.schematic, ctx.transaction
	local recipeID = recipeInfo.recipeID
	local reagents = reagentsForPrediction(schematic, transaction, overrides)
	local predicted = true

	local qualityID
	if recipeInfo.qualityIDs and schematic.hasCraftingOperationInfo then
		local info = operationInfo(recipeID, reagents, transaction)
		if not info and next(overrides) then
			predicted = false
			reagents = transaction:CreateCraftingReagentInfoTbl()
			info = operationInfo(recipeID, reagents, transaction)
		end
		qualityID = info and recipeInfo.qualityIDs[info.craftingQuality]
	end

	local ok, output = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID, reagents,
		transaction:GetAllocationItemGUID(), qualityID)
	if not (ok and output) then return nil, nil, predicted end
	return output.hyperlink, output.itemID, predicted
end

-- Inline icon for a quality, from the game's quality info.
local function qualityIcon(info)
	if info.iconChat and Professions and Professions.GetChatIconMarkupForQuality then
		return Professions.GetChatIconMarkupForQuality(info, true)
	end
	if info.iconSmall then
		return CreateAtlasMarkup(info.iconSmall, ns.Layout.ICON_SIZE, ns.Layout.ICON_SIZE)
	end
end

-- Quality icon of a crafted item's tier, or nil if it has none.
function Blizzard.ItemQualityMarkup(recipeID, quality)
	local info = C_TradeSkillUI.GetRecipeItemQualityInfo(recipeID, quality)
	return info and qualityIcon(info)
end

-- Quality icon of a material, or nil if it has none.
function Blizzard.ReagentQualityMarkup(itemID)
	local info = C_TradeSkillUI.GetItemReagentQualityInfo(itemID)
	return info and qualityIcon(info)
end

---------------------------------------------------------------------------
-- The order list (Public / Guild / Patron / Personal tabs)
---------------------------------------------------------------------------

-- Calls onChange() when the order list, or which tab it shows, may have changed.
function Blizzard.WatchOrderList(onChange)
	local page = ProfessionsFrame.OrdersPage
	hooksecurefunc(page, "SetCraftingOrderType", onChange)
	hooksecurefunc(page, "ShowGeneric", onChange)
	page.BrowseFrame:HookScript("OnShow", onChange)
	page.BrowseFrame:HookScript("OnHide", onChange)
end

-- The order list, for placing things next to it.
function Blizzard.OrderList()
	return ProfessionsFrame.OrdersPage.BrowseFrame.OrderList
end

-- The orders listed on the Patron tab, or nil when it isn't showing. Grouped
-- rows (one per recipe, before you pick one) aren't orders and are left out.
function Blizzard.PatronOrders()
	local page = ProfessionsFrame.OrdersPage
	if not (page.BrowseFrame:IsVisible() and page.orderType == Enum.CraftingOrderType.Npc) then return end
	local orders = {}
	local provider = page.BrowseFrame.OrderList.ScrollBox:GetDataProvider()
	if provider then
		for _, data in provider:Enumerate() do
			local order = data.option
			if order and order.orderID and order.spellID then orders[#orders + 1] = order end
		end
	end
	return orders
end

-- What crafting a listed order takes: { schematic, provided }, or nil when you
-- don't know its recipe. `provided` marks the slots the customer fills.
function Blizzard.OrderJob(order)
	local recipeInfo = C_TradeSkillUI.GetRecipeInfo(order.spellID)
	if not (recipeInfo and recipeInfo.learned) then return end
	local schematic = C_TradeSkillUI.GetRecipeSchematic(order.spellID, order.isRecraft)
	if not schematic then return end
	local provided = {}
	for _, reagent in ipairs(order.reagents or {}) do provided[reagent.slotIndex] = true end
	return { schematic = schematic, provided = provided }
end
