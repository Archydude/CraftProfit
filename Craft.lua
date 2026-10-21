-- Craft Profit: the hammer on each Patron tab row. Each click does the next
-- step of that order: start it, craft it with the materials the list picked,
-- then complete it. The game needs a click for each, and only one order can be
-- started at a time. Chat confirms each step.
local _, ns = ...

local Craft = {}
ns.Craft = Craft

local format = string.format

-- Per orderID, for the orders the hammer worked on this session:
local names = {}     -- the order's name, for chat
local crafting = {}  -- craft cast under way: its recipe's spellID
local crafted = {}   -- crafted, waiting to be completed
-- Completed orders. The order list only refreshes when Blizzard asks for it
-- again, so these are left out until then.
local completed = {}
-- The list's numbers for the craft under way, for the session total: the panel
-- isn't showing that order, so its craft result can't be matched to it.
local pendingModel

local function profession()
	local info = C_TradeSkillUI.GetChildProfessionInfo()
	return info and info.profession
end

local function say(orderID, text, color)
	local name = names[orderID] or "the order"
	ns.Shopping.Say(ns.Color(color or "good", format(text, name)))
end

-- The patron order you've started, or nil.
function Craft.ClaimedPatronOrder()
	local order = C_CraftingOrders.GetClaimedOrder()
	if order and order.orderType == Enum.CraftingOrderType.Npc and not completed[order.orderID] then return order end
end

function Craft.IsCompleted(orderID)
	return completed[orderID] == true
end

-- Where the row's order is, and what a click on its hammer does now:
--   "claim"     not started; you're ready for it and no other order is started
--   "craft"     started
--   "crafting"  the craft is under way (no click)
--   "complete"  crafted
--   nil         another order is started, or you aren't ready for this one
-- `ready`: you have everything for it and reach its minimum quality.
function Craft.Step(row, ready)
	local orderID = row.order.orderID
	local claimed = C_CraftingOrders.GetClaimedOrder()
	if claimed and claimed.orderID == orderID then
		-- Our own record first: the game's order can lag a moment behind the craft.
		if crafted[orderID] or claimed.isFulfillable then return "complete" end
		if crafting[orderID] then return "crafting" end
		return "craft"
	end
	if not claimed and ready then return "claim" end
end

-- One required slot's material: the list's pick, the only one there is, or the
-- first quality you own enough of.
local function slotItem(slot, slotIndex, overrides)
	local pick = overrides and overrides[slotIndex]
	if pick then return pick end
	for _, reagent in ipairs(slot.reagents) do
		if reagent.itemID and ns.Model.Owned(reagent.itemID) >= slot.quantityRequired then return reagent.itemID end
	end
	return slot.reagents[1] and slot.reagents[1].itemID
end

-- The materials you supply, in the shape the craft takes. Plain materials (one
-- kind, no quality) are taken by the game itself.
local function reagentsFor(row)
	local list = {}
	for slotIndex, slot in ipairs(row.job.schematic.reagentSlotSchematics) do
		if slot.required and slot.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent
			and not row.job.provided[slotIndex] then
			local itemID = slotItem(slot, slotIndex, row.job.overrides)
			if itemID then
				list[#list + 1] = { reagent = { itemID = itemID }, dataSlotIndex = slot.dataSlotIndex, quantity = slot.quantityRequired }
			end
		end
	end
	return list
end

-- Does `step` for the row's order.
function Craft.Do(row, step)
	local orderID = row.order.orderID
	names[orderID] = row.name
	if step == "claim" then
		C_CraftingOrders.ClaimOrder(orderID, profession())
	elseif step == "craft" then
		crafting[orderID] = row.order.spellID
		pendingModel = row.model
		local concentrate = row.plan and row.plan.concentration and true or false
		C_TradeSkillUI.CraftRecipe(row.order.spellID, 1, reagentsFor(row), nil, orderID, concentrate)
		ns.Patron.Redraw()
	elseif step == "complete" then
		C_CraftingOrders.FulfillOrder(orderID, "", profession())
	end
end

-- The order model of a craft the hammer started, once, for the craft's result
-- (see Results.lua). nil when the craft came from somewhere else.
function Craft.TakeCraftModel()
	local model = pendingModel
	pendingModel = nil
	return model
end

-- What the hammer's tooltip says for a step.
function Craft.StepText(step, row)
	if step == "claim" then return "Click: start this order" end
	if step == "craft" then
		local concentration = row.plan and row.plan.concentration
		return concentration and format("Click: craft it, using %d concentration", concentration) or "Click: craft it"
	end
	if step == "crafting" then return "Crafting it now..." end
	if step == "complete" then return "Click: complete it and collect the rewards" end
end

-- A craft cast stopped without crafting its order: it can be tried again.
local function craftFailed(spellID)
	for orderID, craftSpell in pairs(crafting) do
		if craftSpell == spellID then
			crafting[orderID], pendingModel = nil, nil
			say(orderID, "Crafting %s stopped. Click its hammer to try again.", "warning")
			ns.Patron.Redraw()
		end
	end
end

local handlers = {}

function handlers.CRAFTINGORDERS_CLAIM_ORDER_RESPONSE(result, orderID)
	if not names[orderID] then return end
	if result == Enum.CraftingOrderResult.Ok then
		say(orderID, "Started %s. Click its hammer again to craft it.")
	else
		say(orderID, "Couldn't start %s (the game said no: " .. tostring(result) .. ").", "warning")
	end
end

-- Sent only when the craft fails.
function handlers.CRAFTINGORDERS_CRAFT_ORDER_RESPONSE(result, orderID)
	if not names[orderID] or result == Enum.CraftingOrderResult.Ok then return end
	crafting[orderID], pendingModel = nil, nil
	say(orderID, "Couldn't craft %s (the game said no: " .. tostring(result) .. ").", "warning")
end

function handlers.CRAFTINGORDERS_CLAIMED_ORDER_UPDATED(orderID)
	if crafting[orderID] then
		crafting[orderID] = nil
		crafted[orderID] = true
		say(orderID, "Crafted %s. Click its hammer again to complete it.")
	end
end

function handlers.CRAFTINGORDERS_FULFILL_ORDER_RESPONSE(result, orderID)
	if not names[orderID] then return end
	if result == Enum.CraftingOrderResult.Ok then
		completed[orderID], crafted[orderID] = true, nil
		say(orderID, "Completed %s.")
		-- Gone from the Patron tab right away, instead of a blank row until it refreshes.
		ns.Blizzard.RemoveListedOrder(orderID)
	else
		say(orderID, "Couldn't complete %s (the game said no: " .. tostring(result) .. ").", "warning")
	end
end

handlers.CRAFTINGORDERS_CLAIMED_ORDER_ADDED = function() end
handlers.CRAFTINGORDERS_CLAIMED_ORDER_REMOVED = function() end

function handlers.UNIT_SPELLCAST_INTERRUPTED(unit, _, spellID)
	if unit == "player" and next(crafting) then craftFailed(spellID) end
end
handlers.UNIT_SPELLCAST_FAILED = handlers.UNIT_SPELLCAST_INTERRUPTED

local frame

-- Starts following orders' progress. Safe to call more than once.
function Craft.Init()
	if frame then return end
	frame = CreateFrame("Frame")
	for event in pairs(handlers) do
		if event:find("^UNIT_") then frame:RegisterUnitEvent(event, "player") else frame:RegisterEvent(event) end
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		handlers[event](...)
		-- The hammer's next step may have changed: redraw the list.
		if not event:find("^UNIT_") then ns.Patron.Redraw() end
	end)
end
