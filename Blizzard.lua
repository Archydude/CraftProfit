-- Craft Profit: everything that reads Blizzard's profession window internals
-- (frame fields, the crafting form's "transaction", mixin methods). Blizzard can
-- change these in any patch, so they live here and nowhere else.
--
-- The addon reads them and follows them with hooks. The one exception is
-- Blizzard.UseMaterials, which fills the form the way Blizzard's own quality
-- picker does, and only when the player clicks or ticks a box for it.
local _, ns = ...

local Blizzard = {}
ns.Blizzard = Blizzard

local format = string.format

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

-- The order screen's form.
local function orderForm()
	local details = ProfessionsFrame.OrdersPage.OrderView.OrderDetails
	return details and details.SchematicForm
end

-- The form showing: the order screen's or the crafting page's, or nil.
local function activeForm()
	local page = Blizzard.ActivePage()
	if page == "order" then return orderForm() end
	if page == "craft" then return ProfessionsFrame.CraftingPage.SchematicForm end
end

-- Puts materials in the form showing, the way Blizzard's quality picker does:
-- `picks` is slotIndex -> itemID, the full amount each. With `concentrate`, also
-- turns on concentration. A slot you don't own enough for is left as it is;
-- returns those as { { itemID, qty short } ... }.
function Blizzard.UseMaterials(picks, concentrate)
	local form = activeForm()
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

-- The "Use Best Quality Reagents" checkboxes: the order form's and the crafting
-- page's.
function Blizzard.BestQualityBoxes()
	local boxes = {}
	for _, form in pairs({ orderForm(), ProfessionsFrame.CraftingPage.SchematicForm }) do
		if form.AllocateBestQualityCheckbox then boxes[#boxes + 1] = form.AllocateBestQualityCheckbox end
	end
	return boxes
end

-- Turns Blizzard's "Use Best Quality Reagents" off: its setting and its checkboxes.
function Blizzard.StopBestQuality()
	if Professions.ShouldAllocateBestQualityReagents() then
		Professions.SetShouldAllocateBestQualityReagents(false)
	end
	for _, box in ipairs(Blizzard.BestQualityBoxes()) do box:SetChecked(false) end
end

-- Calls onBestQuality(checked) after the player clicks "Use Best Quality
-- Reagents" on either form (Blizzard has re-filled the form by then), and
-- onNewForm() when the order screen shows an order or the crafting page a recipe.
function Blizzard.WatchForms(onBestQuality, onNewForm, owner)
	for _, form in pairs({ orderForm(), ProfessionsFrame.CraftingPage.SchematicForm }) do
		form:RegisterCallback(ProfessionsRecipeSchematicFormMixin.Event.UseBestQualityModified,
			function(_, checked) onBestQuality(checked) end, owner)
	end
	hooksecurefunc(ProfessionsFrame.OrdersPage.OrderView, "SetOrder", onNewForm)
	hooksecurefunc(ProfessionsFrame.CraftingPage.SchematicForm, "Init", onNewForm)
end

-- Fills the form showing the way Blizzard does by itself (lowest or best
-- quality, following its checkbox), as unticking that checkbox does. With
-- `stopConcentration`, also turns concentration off.
function Blizzard.ResetMaterials(stopConcentration)
	local page, form = Blizzard.ActivePage(), activeForm()
	local transaction = form and form.transaction
	if not transaction then return end
	if page == "craft" and transaction.SetManuallyAllocated then transaction:SetManuallyAllocated(false) end
	Professions.AllocateAllBasicReagents(transaction, Professions.ShouldAllocateBestQualityReagents())
	-- Puts back what the customer provides, as Blizzard does after re-filling.
	local view = ProfessionsFrame.OrdersPage.OrderView
	if page == "order" and view.SchematicPostInit then view:SchematicPostInit() end
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

local function skillOf(info)
	return (info.baseSkill or 0) + (info.bonusSkill or 0)
end

-- The game's answers this frame. One redraw asks some questions more than once
-- (the form's own quality, say), and each takes a while. GetTime() stays the same
-- all frame, so a new frame starts over.
local answers, answersAt = {}, nil

-- `fn(recipeID, reagents, guid, extra)`, guarded, asked once per frame for the
-- same arguments. False when the game rejected the question.
local function ask(fn, recipeID, reagents, guid, extra)
	local now = GetTime()
	if answersAt ~= now then
		wipe(answers)
		answersAt = now
	end
	local parts = { tostring(fn), recipeID, tostring(guid), tostring(extra) }
	for _, entry in ipairs(reagents) do
		local reagent = entry.reagent or {}
		parts[#parts + 1] = format("%s=%sx%s", tostring(entry.dataSlotIndex),
			tostring(reagent.itemID or reagent.currencyID), tostring(entry.quantity))
	end
	local key = table.concat(parts, ":")
	local answer = answers[key]
	if answer == nil then
		local ok, result = pcall(fn, recipeID, reagents, guid, extra)
		answer = ok and result or false
		answers[key] = answer
	end
	return answer
end

-- Leaves out the optional and finishing reagents you put in that raise your skill
-- (found by asking the game without each one). Advice on what to buy or use has
-- to reach the minimum quality without them: they're used up by the craft, and
-- you may not have one next time. Reagents that do something else (an embellishment
-- that makes the craft harder, say) stay, and so does whatever the customer provides
-- (`provided`, slotIndex -> true).
local function withoutBoosters(recipeID, schematic, transaction, reagents, provided)
	local slotOf = {}
	for slotIndex, slot in ipairs(schematic.reagentSlotSchematics) do
		if slot.dataSlotIndex then slotOf[slot.dataSlotIndex] = slotIndex end
	end
	local guid = transaction:GetAllocationItemGUID()
	local function skillWith(list)
		local info = ask(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, list, guid, false)
		return info and skillOf(info) or nil
	end

	local full, kept = nil, {}
	for i, reagent in ipairs(reagents) do
		local slotIndex = slotOf[reagent.dataSlotIndex]
		local slot = slotIndex and schematic.reagentSlotSchematics[slotIndex]
		local boosts = false
		if slot and slot.reagentType ~= Enum.CraftingReagentType.Basic and not (provided and provided[slotIndex]) then
			full = full or skillWith(reagents)
			local without = {}
			for j, other in ipairs(reagents) do
				if j ~= i then without[#without + 1] = other end
			end
			local skill = full and skillWith(without)
			boosts = skill ~= nil and skill < full
		end
		if not boosts then kept[#kept + 1] = reagent end
	end
	return kept
end

-- Asks the game how a craft with these materials turns out. The game may reject a
-- made-up material list (that's what what-if builds), so these calls are guarded.
-- Also returns whether the answer includes concentration.
local function operationInfo(recipeID, reagents, transaction)
	local guid = transaction:GetAllocationItemGUID()
	local concentrating = transaction.IsApplyingConcentration and transaction:IsApplyingConcentration() or false
	local info = ask(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, reagents, guid, concentrating)
	if not info and concentrating then
		-- Changed materials can raise the concentration cost past what you have.
		concentrating = false
		info = ask(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, reagents, guid, false)
	end
	if not info then return nil end
	return info, concentrating
end

-- The reagents to predict with. `advice`: for advice on what to buy or use, so
-- leave out your skill boosters; it's the slots the customer provides
-- (slotIndex -> true, {} for none), which always stay.
local function predictionReagents(recipeID, schematic, transaction, overrides, advice)
	local reagents = reagentsForPrediction(schematic, transaction, overrides)
	if advice then reagents = withoutBoosters(recipeID, schematic, transaction, reagents, advice) end
	return reagents
end

-- The quality tier the game predicts for these materials, or nil. Also the
-- concentration that prediction spends, or nil when it uses none. `advice`: see
-- predictionReagents.
function Blizzard.PredictQuality(recipeID, schematic, transaction, overrides, advice)
	local reagents = predictionReagents(recipeID, schematic, transaction, overrides, advice)
	local info, concentrating = operationInfo(recipeID, reagents, transaction)
	if not info then return nil end
	return info.craftingQuality, concentrating and (info.concentrationCost or 0) or nil
end

-- The concentration crafting with what's in the form would take, or nil.
-- `advice`: see predictionReagents.
function Blizzard.FormConcentrationCost(recipeID, schematic, transaction, advice)
	local info = operationInfo(recipeID, predictionReagents(recipeID, schematic, transaction, {}, advice), transaction)
	return info and info.concentrationCost
end

-- The item a craft makes at its predicted quality: link, itemID, whether the
-- game could predict the quality for the picked qualities (if not, the form's own
-- materials are used), and that quality tier (nil for items without ranks).
function Blizzard.ExpectedOutput(ctx, overrides)
	local recipeInfo, schematic, transaction = ctx.recipeInfo, ctx.schematic, ctx.transaction
	local recipeID = recipeInfo.recipeID
	local reagents = reagentsForPrediction(schematic, transaction, overrides)
	local predicted = true

	local quality, qualityID
	if recipeInfo.qualityIDs and schematic.hasCraftingOperationInfo then
		local info = operationInfo(recipeID, reagents, transaction)
		if not info and next(overrides) then
			predicted = false
			reagents = transaction:CreateCraftingReagentInfoTbl()
			info = operationInfo(recipeID, reagents, transaction)
		end
		quality = info and info.craftingQuality
		qualityID = quality and recipeInfo.qualityIDs[quality]
	end

	local output = ask(C_TradeSkillUI.GetRecipeOutputItemData, recipeID, reagents,
		transaction:GetAllocationItemGUID(), qualityID)
	if not output then return nil, nil, predicted end
	return output.hyperlink, output.itemID, predicted, qualityID and quality
end

-- The item a craft makes at a quality tier, with what's in the form: link and
-- itemID, or nil.
function Blizzard.OutputAtQuality(recipeInfo, transaction, quality)
	local qualityID = recipeInfo.qualityIDs and recipeInfo.qualityIDs[quality]
	if not qualityID then return end
	local output = ask(C_TradeSkillUI.GetRecipeOutputItemData, recipeInfo.recipeID,
		transaction:CreateCraftingReagentInfoTbl(), transaction:GetAllocationItemGUID(), qualityID)
	if output then return output.hyperlink, output.itemID end
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
-- The crafting page, for the Best crafts list
---------------------------------------------------------------------------

-- The recipe details on the crafting page: the list covers them while it's open.
function Blizzard.RecipeDetails()
	return ProfessionsFrame.CraftingPage.SchematicForm
end

-- Whether the crafting page shows its recipe list (it's hidden in the small view).
function Blizzard.ShowsRecipeList()
	local page = ProfessionsFrame.CraftingPage
	return page:IsVisible() and page.RecipeList:IsShown()
end

-- Shows a recipe on the crafting page, as a recipe link does.
function Blizzard.ShowRecipe(recipeID)
	C_TradeSkillUI.OpenRecipe(recipeID)
end

-- Calls onSelect() when the crafting page shows another recipe, and onLayout()
-- when it switches between the full and the small view, shows or hides.
function Blizzard.WatchCraftingPage(onSelect, onLayout)
	local page = ProfessionsFrame.CraftingPage
	hooksecurefunc(page, "SelectRecipe", onSelect)
	hooksecurefunc(page, "SetMaximized", onLayout)
	hooksecurefunc(page, "SetMinimized", onLayout)
	page:HookScript("OnShow", onLayout)
	page:HookScript("OnHide", onLayout)
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

-- The flat order list's columns (one row per order), by position.
Blizzard.ORDER_COLUMNS = { name = 1, customer = 2, commission = 3, reagents = 4, expiration = 5 }

local function orderTable()
	return ProfessionsFrame.OrdersPage.tableBuilder
end

-- Whether the order list shows patron orders one per row, in the columns above
-- (not grouped by recipe).
function Blizzard.IsPatronTable()
	local page = ProfessionsFrame.OrdersPage
	if not (page.BrowseFrame:IsVisible() and page.orderType == Enum.CraftingOrderType.Npc) then return false end
	local builder = orderTable()
	local columns = builder and builder:GetColumns()
	return columns ~= nil and #columns == 5
end

-- Calls onRow(row) each time the order list fills in a row, and onTable() after
-- it lays out its columns again (another tab, or grouped rows).
function Blizzard.WatchOrderRows(onRow, onTable)
	local builder = orderTable()
	hooksecurefunc(builder, "AddRow", function(_, row) onRow(row) end)
	hooksecurefunc(builder, "Arrange", onTable)
end

-- The order list's rows, as a list the game sorts by itself (one per search), or nil.
function Blizzard.OrderListRows()
	return ProfessionsFrame.OrdersPage.BrowseFrame.OrderList.ScrollBox:GetDataProvider()
end

-- Puts the order list's rows in the order `before(a, b)` says (a and b are orders),
-- until the game fills it in again.
function Blizzard.SortOrderList(before)
	local rows = Blizzard.OrderListRows()
	if not (rows and rows.Sort) then return end
	rows:Sort(function(a, b)
		local aOrder, bOrder = a.option, b.option
		if not (aOrder and bOrder) then return false end
		return before(aOrder, bOrder)
	end)
end

-- Takes an order off the order list, until the game fills it in again (by then
-- the game has dropped it too).
function Blizzard.RemoveListedOrder(orderID)
	local rows = Blizzard.OrderListRows()
	if not (rows and rows.RemoveAllByPredicate) then return end
	rows:RemoveAllByPredicate(function(data)
		return data.option ~= nil and data.option.orderID == orderID
	end)
end

-- Calls onSort() after the player sorts the list by one of Blizzard's headers.
function Blizzard.WatchSortOrder(onSort)
	hooksecurefunc(ProfessionsFrame.OrdersPage, "SetSortOrder", onSort)
end

-- Shows the sort arrow on Blizzard's headers that sort the list now, or hides
-- them all.
function Blizzard.ShowSortArrows(shown)
	local builder = orderTable()
	if not builder then return end
	for header in builder:EnumerateHeaders() do
		if shown and header.UpdateArrow then
			header:UpdateArrow()
		elseif header.Arrow then
			header.Arrow:Hide()
		end
	end
end

-- Calls fn(row) for every row of the order list on screen.
function Blizzard.ForEachOrderRow(fn)
	ProfessionsFrame.OrdersPage.BrowseFrame.OrderList.ScrollBox:ForEachFrame(fn)
end

-- A row's order, or nil for a grouped row.
function Blizzard.RowOrder(row)
	local data = row.rowData
	local order = data and data.option
	if order and order.orderID and order.spellID then return order end
end

-- A row's cell in a column (see ORDER_COLUMNS), or nil.
function Blizzard.RowCell(row, column)
	return row.cells and row.cells[column]
end

-- How wide the cells of columns `first` to `last` are together, with the gaps
-- between them, as the list lays them out.
function Blizzard.ColumnSpan(first, last)
	local columns = orderTable():GetColumns()
	local width = 0
	for i = first, last do
		local column = columns[i]
		if not column then return end
		width = width + column:GetCellWidth()
		if i > first then
			local left = column:GetCellPadding()
			local _, previousRight = columns[i - 1]:GetCellPadding()
			width = width + column:GetPadding() + left + previousRight
		end
	end
	return width
end

-- Shows or hides a row's mouse-over highlight.
function Blizzard.SetRowHighlight(row, shown)
	if row.HighlightTexture then row.HighlightTexture:SetShown(shown) end
end

-- A column's header button (see ORDER_COLUMNS), or nil.
function Blizzard.ColumnHeader(column)
	local builder = orderTable()
	local entry = builder and builder:GetColumns()[column]
	return entry and entry:GetHeaderFrame()
end

-- Leaves `height` pixels free at the bottom of the order list, under its rows
-- (0 gives them back).
local listBottom
function Blizzard.SetOrderListFooter(height)
	local background = Blizzard.OrderList().Background
	if not background then return end
	if not listBottom then
		for i = 1, background:GetNumPoints() do
			local point, relativeTo, relativePoint, x, y = background:GetPoint(i)
			if point == "BOTTOMRIGHT" then listBottom = { relativeTo, relativePoint, x, y } end
		end
		if not listBottom then return end
	end
	local relativeTo, relativePoint, x, y = unpack(listBottom)
	background:SetPoint("BOTTOMRIGHT", relativeTo, relativePoint, x, y + height)
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
