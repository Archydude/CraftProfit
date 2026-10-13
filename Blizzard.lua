-- Craft Profit: everything that reads Blizzard's profession window internals
-- (frame fields, the crafting form's "transaction", mixin methods). Blizzard can
-- change these in any patch, so they live here and nowhere else.
--
-- The addon reads them and follows them with hooks. The one exception is
-- Blizzard.UseMaterials, which fills the order form the way Blizzard's own
-- quality picker does, and only when the player clicks for it.
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

-- Whether the profession window shows this character's own profession, not a
-- linked or guild member's one or an NPC's.
function Blizzard.IsOwnProfession()
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then return false end
	if Professions and Professions.InLocalCraftingMode then return Professions.InLocalCraftingMode() end
	return not (C_TradeSkillUI.IsNPCCrafting() or C_TradeSkillUI.IsTradeSkillGuild()
		or C_TradeSkillUI.IsTradeSkillGuildMember() or C_TradeSkillUI.IsTradeSkillLinked())
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

-- Puts materials in the open order's form, the way Blizzard's quality picker
-- does: `picks` is slotIndex -> itemID, the full amount each. With `concentrate`,
-- also turns on concentration. A slot you don't own enough for is left as it is;
-- returns those as { { itemID, qty short } ... }.
function Blizzard.UseMaterials(picks, concentrate)
	local view = ProfessionsFrame.OrdersPage.OrderView
	local form = view.OrderDetails and view.OrderDetails.SchematicForm
	local transaction, schematic = form and form.transaction, form and form.recipeSchematic
	if not (transaction and schematic) then return {} end
	local charOnly = transaction.ShouldUseCharacterInventoryOnly and transaction:ShouldUseCharacterInventoryOnly()
	local short, changed = {}, false
	for slotIndex, itemID in pairs(picks) do
		local slot = schematic.reagentSlotSchematics[slotIndex]
		local reagent
		for _, candidate in ipairs(slot and slot.reagents or {}) do
			if candidate.itemID == itemID then reagent = candidate end
		end
		if reagent then
			local qty = slot.quantityRequired
			local have = ProfessionsUtil and ProfessionsUtil.GetReagentQuantityInPossession
				and ProfessionsUtil.GetReagentQuantityInPossession(reagent, charOnly) or ns.Model.Owned(itemID)
			if have >= qty then
				transaction:OverwriteAllocation(slotIndex, reagent, qty)
				changed = true
			else
				short[#short + 1] = { itemID = itemID, qty = qty - have }
			end
		end
	end
	if changed then
		-- Keeps the form from putting its own choice back on its next refresh.
		transaction:SetManuallyAllocated(true)
		form:UpdateAllSlots()
	end
	if concentrate and transaction.SetApplyConcentration then transaction:SetApplyConcentration(true) end
	return short
end

-- The order form's "Use Best Quality Reagents" checkbox.
function Blizzard.OrderBestQualityBox()
	local details = ProfessionsFrame.OrdersPage.OrderView.OrderDetails
	return details and details.SchematicForm and details.SchematicForm.AllocateBestQualityCheckbox
end

-- Moves "Use Best Quality Reagents" up by `height`, to make room under it. It's
-- anchored to the form's bottom left, and the order form never moves it again.
function Blizzard.RaiseOrderBestQualityBox(height)
	local box = Blizzard.OrderBestQualityBox()
	local point, relativeTo, relativePoint, x, y = box:GetPoint(1)
	if not point then return end
	box:ClearAllPoints()
	box:SetPoint(point, relativeTo, relativePoint, x, y + height)
end

-- Turns Blizzard's "Use Best Quality Reagents" off: its setting and its checkbox.
function Blizzard.StopBestQuality()
	if Professions.ShouldAllocateBestQualityReagents() then
		Professions.SetShouldAllocateBestQualityReagents(false)
	end
	local box = Blizzard.OrderBestQualityBox()
	if box then box:SetChecked(false) end
end

-- Calls onBestQuality(checked) after the player clicks "Use Best Quality
-- Reagents" on the order form (Blizzard has re-filled the form by then), and
-- onOrder() when the order screen shows an order.
function Blizzard.WatchOrderForm(onBestQuality, onOrder, owner)
	local view = ProfessionsFrame.OrdersPage.OrderView
	view.OrderDetails.SchematicForm:RegisterCallback(ProfessionsRecipeSchematicFormMixin.Event.UseBestQualityModified,
		function(_, checked) onBestQuality(checked) end, owner)
	hooksecurefunc(view, "SetOrder", onOrder)
end

-- Fills the open order's form the way Blizzard does by itself (lowest or best
-- quality, following its checkbox), as unticking that checkbox does. With
-- `stopConcentration`, also turns concentration off.
function Blizzard.ResetMaterials(stopConcentration)
	local view = ProfessionsFrame.OrdersPage.OrderView
	local form = view.OrderDetails and view.OrderDetails.SchematicForm
	local transaction = form and form.transaction
	if not (transaction and view:IsVisible() and view.order) then return end
	Professions.AllocateAllBasicReagents(transaction, Professions.ShouldAllocateBestQualityReagents())
	-- Puts back what the customer provides, as Blizzard does after re-filling.
	if view.SchematicPostInit then view:SchematicPostInit() end
	form:UpdateAllSlots()
	if stopConcentration and transaction.SetApplyConcentration then transaction:SetApplyConcentration(false) end
end

-- Whether the order form is applying concentration.
function Blizzard.IsConcentrating(transaction)
	return transaction and transaction.IsApplyingConcentration and transaction:IsApplyingConcentration() or false
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
-- Also returns whether the answer includes concentration.
local function operationInfo(recipeID, reagents, transaction)
	local guid = transaction:GetAllocationItemGUID()
	local concentrating = transaction.IsApplyingConcentration and transaction:IsApplyingConcentration() or false
	local ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, reagents, guid, concentrating)
	if not (ok and info) and concentrating then
		-- Changed materials can raise the concentration cost past what you have.
		concentrating = false
		ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, reagents, guid, false)
	end
	if not (ok and info) then return nil end
	return info, concentrating
end

-- The quality tier the game predicts for these materials, or nil. Also the
-- concentration that prediction spends, or nil when it uses none.
function Blizzard.PredictQuality(recipeID, schematic, transaction, overrides)
	local info, concentrating = operationInfo(recipeID, reagentsForPrediction(schematic, transaction, overrides), transaction)
	if not info then return nil end
	return info.craftingQuality, concentrating and (info.concentrationCost or 0) or nil
end

-- The concentration crafting with what's in the form would take, or nil.
function Blizzard.FormConcentrationCost(recipeID, schematic, transaction)
	local info = operationInfo(recipeID, reagentsForPrediction(schematic, transaction, {}), transaction)
	return info and info.concentrationCost
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

-- What crafting a listed order takes: { schematic, provided, name, icon }, or
-- nil when you don't know its recipe (then also its name and icon, for the list).
-- `provided` marks the slots the customer fills.
function Blizzard.OrderJob(order)
	local recipeInfo = C_TradeSkillUI.GetRecipeInfo(order.spellID)
	if not (recipeInfo and recipeInfo.learned) then
		return nil, recipeInfo and recipeInfo.name, recipeInfo and recipeInfo.icon
	end
	local schematic = C_TradeSkillUI.GetRecipeSchematic(order.spellID, order.isRecraft)
	if not schematic then return end
	local provided = {}
	for _, reagent in ipairs(order.reagents or {}) do provided[reagent.slotIndex] = true end
	return { schematic = schematic, provided = provided, name = recipeInfo.name, icon = recipeInfo.icon }
end
