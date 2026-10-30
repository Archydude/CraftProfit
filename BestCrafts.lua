-- Craft Profit: the math behind the Best crafts list. No drawing here;
-- BestCraftsList.lua draws what this works out.
--
-- The game only says which rank a craft comes out at while the profession window
-- is open, so each time the list opens, every recipe of the profession shown is
-- scanned, a little each frame: which rank each mix of material qualities
-- reaches, and what concentration would add. Prices aren't part of the scan, so
-- the list can be priced again at any time (BestCrafts.Rows) without asking the
-- game again.
local _, ns = ...

local BestCrafts = {}
ns.BestCrafts = BestCrafts

-- Milliseconds the scan may spend each frame, so it never slows the game down.
local FRAME_BUDGET_MS = 4
-- Most quality mixes tried for one recipe. Past that, only the top qualities.
local MAX_MIXES = 81
-- Waits after a change that needs a new scan (skill, gear, specializations), so
-- a burst of changes scans once.
local RESCAN_DELAY = 1

-- The last scan: {
--   professionID, name = the profession shown ("Midnight Blacksmithing"),
--   total = recipes to scan, done = recipes scanned so far, finished = bool,
--   recipes = { entry ... } (see scanRecipe),
-- }
local scan
local active -- the scan in progress (the same as scan, unless the last one is still shown)
local onChange = nop -- called when the scan has something new to show
local isWanted = function() return false end -- whether the list wants a scan now

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------

local deadline = 0 -- when this frame's share of the scan runs out
local forgetMarket -- see Pricing

local function pauseIfDue()
	if debugprofilestop() > deadline then coroutine.yield() end
end

-- How a craft with these reagents turns out, or nil.
local function operation(recipeID, reagents)
	local ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, reagents, nil, false)
	pauseIfDue()
	return ok and info and info.craftingQuality and info or nil
end

local function reagentEntry(itemID, slot)
	return { reagent = { itemID = itemID }, dataSlotIndex = slot.dataSlotIndex, quantity = slot.quantityRequired }
end

-- A slot the planner picks qualities for (see Planner.QualitySlots).
local function isQualitySlot(slot)
	return ns.Blizzard.IsQualitySlot(slot) and slot.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent
end

-- The item a craft makes at a quality: { link, itemID }, or nil.
local function outputAt(recipeID, reagents, qualityID)
	local ok, output = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID, reagents, nil, qualityID)
	if ok and output and output.hyperlink then return { link = output.hyperlink, itemID = output.itemID } end
end

-- The scroll an enchant makes at a rank: { link, itemID }, or nil.
local function scrollAt(recipeID, name, rank)
	local link, itemID = ns.Blizzard.ScrollAt(recipeID, name, rank)
	if link then return { link = link, itemID = itemID } end
end

-- What one recipe can make: {
--   recipeID, name, icon, schematic,
--   maxRank = its number of ranks (1 for items without ranks),
--   outputs = rank -> { link, itemID },
--   slots = the slots that come in qualities (Planner.QualitySlots),
--   others = the other required slots: { slotIndex, qty, itemIDs, basic } ...,
--     basic for basic materials (the ones resourcefulness saves),
--   options = { { picks = slotIndex -> itemID, quality, concentration } ... },
--     one for each mix of qualities; concentration is what lifts it a rank, or nil,
--   professionID, chances = your multicraft and resourcefulness chances (Procs.Chances),
--   character, scanned = whose saved scan it's from, and when (Scans.lua), nil from the game,
-- }, or nil for recipes that don't make an item. Enchants count as the scroll
-- they make, with their vellum as one more slot (see Blizzard.ScrollSchematic).
local function scanRecipe(recipeID, info, professionID)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if not schematic then return end
	local scroll = ns.Blizzard.MakesScroll(recipeID)
	if scroll then
		schematic = ns.Blizzard.ScrollSchematic(schematic)
	elseif schematic.recipeType ~= Enum.TradeskillRecipeType.Item then
		return
	end
	local qualityIDs = info.supportsQualities and info.qualityIDs or nil
	if qualityIDs and #qualityIDs == 0 then qualityIDs = nil end
	local entry = {
		recipeID = recipeID, name = info.name, icon = info.icon, schematic = schematic,
		maxRank = qualityIDs and #qualityIDs or 1, professionID = professionID,
		outputs = {}, slots = ns.Planner.QualitySlots(schematic, {}), others = {}, options = {},
	}

	-- Required slots that don't come in qualities count too, at their cheapest
	-- (sparks and the like), and the game needs the ones that change the craft.
	local base = {}
	for slotIndex, slot in ipairs(schematic.reagentSlotSchematics) do
		if slot.required and not isQualitySlot(slot) then
			local itemIDs = {}
			for _, reagent in ipairs(slot.reagents) do
				if reagent.itemID then itemIDs[#itemIDs + 1] = reagent.itemID end
			end
			if #itemIDs > 0 then
				entry.others[#entry.others + 1] = { slotIndex = slotIndex, qty = slot.quantityRequired, itemIDs = itemIDs,
					basic = slot.reagentType == Enum.CraftingReagentType.Basic }
				if slot.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent then
					base[#base + 1] = reagentEntry(itemIDs[1], slot)
				end
			end
		end
	end

	local function reagentsFor(picks)
		local list = {}
		for i, reagent in ipairs(base) do list[i] = reagent end
		for _, slot in ipairs(entry.slots) do
			list[#list + 1] = reagentEntry(picks[slot.slotIndex], schematic.reagentSlotSchematics[slot.slotIndex])
		end
		return list
	end

	local mixes = ns.Planner.Mixes(entry.slots, MAX_MIXES)
	local function picksOf(mix)
		local picks = {}
		for i, slot in ipairs(entry.slots) do picks[slot.slotIndex] = slot.options[mix[i]].itemID end
		return picks
	end

	-- What it makes at each rank, priced or not. A recipe with no price at any
	-- rank isn't worth asking the game about every mix.
	local firstReagents = reagentsFor(picksOf(mixes[1]))
	local anyPrice = false
	for rank = 1, entry.maxRank do
		local output
		if scroll then
			output = scrollAt(recipeID, info.name, rank)
		else
			output = outputAt(recipeID, firstReagents, qualityIDs and qualityIDs[rank])
		end
		entry.outputs[rank] = output
		if output and ns.Prices.Sale(output.link, output.itemID) then anyPrice = true end
	end
	pauseIfDue()
	if not next(entry.outputs) then return end

	local answer -- one of the game's answers, for your proc chances
	for _, mix in ipairs(mixes) do
		local picks = picksOf(mix)
		if not qualityIDs then
			entry.options[#entry.options + 1] = { picks = picks, quality = 1 }
		elseif anyPrice and schematic.hasCraftingOperationInfo then
			local result = operation(recipeID, reagentsFor(picks))
			answer = answer or result
			if result then
				local quality = result.craftingQuality
				local lifts = quality < entry.maxRank and (result.concentrationCost or 0) > 0
				entry.options[#entry.options + 1] = { picks = picks, quality = quality,
					concentration = lifts and result.concentrationCost or nil }
			end
		end
	end
	-- Unpriced items with ranks: the cheapest mix, at a rank no one asked about.
	if #entry.options == 0 then entry.options[1] = { picks = picksOf(mixes[1]) } end
	if not answer and schematic.hasCraftingOperationInfo then answer = operation(recipeID, firstReagents) end
	entry.chances = ns.Procs.Chances(answer)
	return entry
end

-- The profession the window shows right now: its ID and name.
local function shownProfession()
	local child = C_TradeSkillUI.GetChildProfessionInfo()
	if child and child.professionID and child.professionID > 0 then return child.professionID, child.professionName end
end

-- Whether a learned recipe belongs on the list of the profession shown.
local function listable(recipeID, info, professionID)
	if not (info and info.learned) or info.isRecraft or info.isSalvageRecipe or info.isDummyRecipe then return false end
	local profession = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	return profession ~= nil and profession.professionID == professionID
end

local function scanAll(run, recipeIDs)
	local wanted = {}
	for _, recipeID in ipairs(recipeIDs) do
		local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if listable(recipeID, info, run.professionID) then wanted[#wanted + 1] = info end
		pauseIfDue()
	end
	run.total = #wanted
	for _, info in ipairs(wanted) do
		local entry = scanRecipe(info.recipeID, info, run.professionID)
		if entry then run.recipes[#run.recipes + 1] = entry end
		run.done = run.done + 1
		pauseIfDue()
	end
	run.finished = true
end

-- Starts a new scan of the profession shown. The last scan's rows stay on the
-- list until this one has something to show.
function BestCrafts.Scan()
	if not ns.Blizzard.IsOwnProfession() then return end
	local professionID, name = shownProfession()
	if not professionID then return end
	local recipeIDs = (C_TradeSkillUI.GetAllRecipeIDs or C_TradeSkillUI.GetFilteredRecipeIDs)()
	if not recipeIDs or #recipeIDs == 0 then return end

	-- Each opening of the list asks the price addons again.
	forgetMarket()
	local run = { professionID = professionID, name = name, total = 0, done = 0, recipes = {}, finished = false }
	local previous = scan
	-- Keep showing the last scan of the same profession while this one runs.
	if not (previous and previous.professionID == professionID and previous.finished) then scan = run end
	local thread = coroutine.create(scanAll)
	active = run
	local function step()
		if active ~= run then return end
		-- Stop if the window closed or switched profession: the game's answers
		-- would be wrong from here on.
		if not ns.Blizzard.IsOwnProfession() or shownProfession() ~= professionID then
			active = nil
			onChange()
			return
		end
		deadline = debugprofilestop() + FRAME_BUDGET_MS
		local ok, err = coroutine.resume(thread, run, recipeIDs)
		if not ok then
			active = nil
			geterrorhandler()(err)
			return
		end
		if coroutine.status(thread) == "dead" then
			active = nil
			scan = run
			ns.Scans.Save(run)
		end
		onChange()
		if active == run then C_Timer.After(0, step) end
	end
	step()
end

-- The scan to show: { name, total, done, finished, recipes }, or nil.
function BestCrafts.Current()
	return scan
end

-- Whether the entry is this character's, not another's saved one.
function BestCrafts.IsMine(entry)
	local _, myKey = ns.Ranks.Me()
	return entry.character == nil or entry.character == myKey
end

-- How far the scan in progress is: done, total. Nil when none is running.
function BestCrafts.Progress()
	if active then return active.done, active.total end
end

-- `changed()` runs whenever the scan has something new to show; `wanted()`
-- says whether the list is open, so changes to your skill scan again.
function BestCrafts.Watch(changed, wanted)
	onChange, isWanted = changed, wanted
end

---------------------------------------------------------------------------
-- Pricing
---------------------------------------------------------------------------

-- What kind of item a recipe makes, for the list's filter, by the item's class
-- (Enum.ItemClass). Anything else is "other".
BestCrafts.GROUPS = {
	{ key = "gear", label = "Gear", classes = { 2, 4, 19 } },      -- weapons, armor, profession tools
	{ key = "decor", label = "Decor", classes = { 20 } },          -- housing
	{ key = "materials", label = "Materials", classes = { 3, 5, 7 } }, -- gems, reagents, trade goods
	{ key = "enhancements", label = "Enchants and kits", classes = { 8 } },
	{ key = "consumables", label = "Consumables", classes = { 0 } },
	{ key = "bags", label = "Bags", classes = { 1 } },
	{ key = "other", label = "Other" },
}
local groupOfClass = {}
for _, group in ipairs(BestCrafts.GROUPS) do
	for _, classID in ipairs(group.classes or {}) do groupOfClass[classID] = group.key end
end

local function groupOf(itemID)
	local classID = itemID and select(6, C_Item.GetItemInfoInstant(itemID))
	return classID and groupOfClass[classID] or "other"
end

local function memo(fn)
	local cache = {}
	return function(itemID, qty)
		local byQty = cache[itemID]
		if not byQty then
			byQty = {}
			cache[itemID] = byQty
		end
		local value = byQty[qty or 0]
		if value == nil then
			value = fn(itemID, qty) or false
			byQty[qty or 0] = value
		end
		return value or nil
	end
end

-- Asking the price addons for hundreds of rows takes a while, so answers are
-- kept: market ones (prices, Listed, Sells/day) until a new scan or an option
-- changes, and ones that follow what you own until your bags change. See
-- BestCrafts.Reprice.
local materialPrice, salePrice, market -- market: link -> { listed, listedAge, soldPerDay }
local effectiveCost, buyCost
-- Rows priced so far: entry -> row (see priceEntry).
local priced = setmetatable({}, { __mode = "k" })

function forgetMarket()
	materialPrice = memo(ns.Prices.Material)
	local sales = {}
	salePrice = function(link, itemID)
		local price = sales[link]
		if price == nil then
			price = ns.Prices.Sale(link, itemID) or false
			sales[link] = price
		end
		return price or nil
	end
	market = {}
end

local function forgetOwned()
	effectiveCost = memo(ns.Model.EffectiveCost)
	buyCost = memo(ns.Model.BuyCost)
	wipe(priced)
end

-- Prices the list again on its next redraw: after your bags change, or with
-- `all`, after an option changes (prices too).
function BestCrafts.Reprice(all)
	if all or not market then forgetMarket() end
	forgetOwned()
end

-- What the auction house says about a crafted item (see market).
local function marketOf(link)
	local found = market[link]
	if not found then
		found = {}
		found.listed, found.listedAge = ns.Prices.Listed(link)
		found.soldPerDay = ns.Prices.SoldPerDay(link)
		market[link] = found
	end
	return found
end

-- The cheapest priced itemID of a slot that doesn't come in qualities, and its price.
local function cheapestOther(other)
	local bestID, bestPrice
	for _, itemID in ipairs(other.itemIDs) do
		local price = materialPrice(itemID)
		if price and (not bestPrice or price < bestPrice) then bestID, bestPrice = itemID, price end
	end
	return bestID, bestPrice
end

-- Whether you own enough of any item a slot that doesn't come in qualities takes.
local function ownsOther(other)
	for _, itemID in ipairs(other.itemIDs) do
		if buyCost(itemID, other.qty) == 0 then return true end
	end
	return false
end

-- What an option's materials cost: at full price, and what they really cost you
-- (what you own counts at what it would sell for, as the planner counts it).
-- Also how many materials have no price, what the basic ones cost (the ones
-- resourcefulness saves; the slots in qualities are all basic), the gold you'd
-- spend on what you don't own, and whether you're short of anything.
local function costOf(entry, option)
	local full, effective, unpriced, basic, buy = 0, 0, 0, 0, 0
	local short = false
	for _, slot in ipairs(entry.slots) do
		local itemID = option.picks[slot.slotIndex]
		local price = materialPrice(itemID)
		short = short or buyCost(itemID, slot.qty) ~= 0
		if price then
			full = full + price * slot.qty
			basic = basic + price * slot.qty
			effective = effective + (effectiveCost(itemID, slot.qty) or price * slot.qty)
			buy = buy + (buyCost(itemID, slot.qty) or price * slot.qty)
		else
			unpriced = unpriced + 1
		end
	end
	for _, other in ipairs(entry.others) do
		local itemID, price = cheapestOther(other)
		short = short or not ownsOther(other)
		if price then
			full = full + price * other.qty
			if other.basic then basic = basic + price * other.qty end
			effective = effective + (effectiveCost(itemID, other.qty) or price * other.qty)
			buy = buy + (buyCost(itemID, other.qty) or price * other.qty)
		else
			unpriced = unpriced + 1
		end
	end
	return full, effective, unpriced, basic, buy, short
end

-- Seconds until the recipe can be crafted again, or nil when it can now.
local function cooldownOf(recipeID)
	local cooldown, _, charges, maxCharges = C_TradeSkillUI.GetRecipeCooldown(recipeID)
	if not (cooldown and cooldown > 0) then return end
	if maxCharges and maxCharges > 0 and charges and charges > 0 then return end
	return cooldown
end

-- One list row: the recipe at the rank the crafting strategy picks, the cheapest
-- way (see Planner.Choose). {
--   entry, quality = the rank it makes (nil when unknown), picks = slotIndex -> itemID,
--   output = { link, itemID } at that rank, itemName,
--   sale = what a craft sells for after the AH cut (capped), cost = materials at full price,
--   profit, or nil with noPrice (no auction price at that rank),
--   cappedBy, listedPrice = the rank that capped the price and the price before,
--   unpriced = materials without a price, short = you don't own them all,
--   concentration = { extra, points, quality } when concentrating makes more,
--   procs = what multicraft and resourcefulness add on average (Procs.Expected),
--   expected = profit with that counted,
--   listed, listedAge = Auctionator's count, sold = your sales, soldPerDay = TSM's,
--   cooldown = seconds, or nil, firstCraft = crafting it the first time gives knowledge,
--   group = what kind of item it is (see BestCrafts.GROUPS),
-- }
local function priceEntry(entry)
	local sales = {}
	for rank, output in pairs(entry.outputs) do sales[rank] = salePrice(output.link, output.itemID) end
	local prices, cappedBy = ns.Planner.RankPrices(sales, entry.maxRank, entry.schematic)

	local options = {}
	for _, option in ipairs(entry.options) do
		if option.quality then
			local full, effective, unpriced, basic, buy, short = costOf(entry, option)
			options[#options + 1] = { cost = effective, full = full, unpriced = unpriced, basic = basic, buy = buy,
				short = short, quality = option.quality, option = option }
		end
	end
	local best = ns.Planner.Choose(options)
	if not best then
		-- Items with ranks but no price at any rank aren't worked out: the cheapest
		-- mix, at a rank no one asked about.
		local option = entry.options[1]
		local full, effective, unpriced, basic, _, short = costOf(entry, option)
		best = { cost = effective, full = full, unpriced = unpriced, basic = basic, short = short, option = option }
	end

	local row = { entry = entry, firstCraft = false }
	-- What the game says is about this character, so only for its own recipes.
	if BestCrafts.IsMine(entry) and C_TradeSkillUI.IsRecipeFirstCraft then
		row.firstCraft = C_TradeSkillUI.IsRecipeFirstCraft(entry.recipeID) or false
	end
	row.quality = best.quality
	row.picks, row.cost, row.unpriced, row.short = best.option.picks, best.full, best.unpriced, best.short
	-- The game also counts what you can make with a slot split across qualities.
	if row.short and BestCrafts.IsMine(entry) then
		local info = C_TradeSkillUI.GetRecipeInfo(entry.recipeID)
		row.short = not (info and (info.numAvailable or 0) > 0)
	end
	local sale = row.quality and prices[row.quality]
	if sale then
		row.sale, row.profit = sale, sale - best.full
		row.cappedBy = cappedBy[row.quality]
		row.listedPrice = row.cappedBy and sales[row.quality]
	else
		row.noPrice = true
	end
	row.procs = ns.Procs.Expected(entry.professionID, entry.chances, sale, best.basic, entry.character)
	row.expected = row.profit and row.profit + row.procs.total

	-- What concentrating adds: one rank above the row's, made the cheapest way,
	-- minus what the row makes without it.
	local liftedPrice = row.profit and prices[row.quality + 1]
	if liftedPrice then
		local lifted
		for _, candidate in ipairs(options) do
			if candidate.quality == row.quality and candidate.option.concentration
				and (not lifted or candidate.cost < lifted.cost) then
				lifted = candidate
			end
		end
		local extra = lifted and liftedPrice - lifted.full - row.profit
		if extra and extra > 0 then
			row.concentration = { extra = extra, points = lifted.option.concentration, quality = row.quality + 1 }
		end
	end

	row.output = row.quality and entry.outputs[row.quality] or entry.outputs[entry.maxRank] or entry.outputs[1]
	row.group = groupOf(row.output and row.output.itemID)
	if row.output then
		local found = marketOf(row.output.link)
		row.listed, row.listedAge, row.soldPerDay = found.listed, found.listedAge, found.soldPerDay
	end
	return row
end

-- What can change between redraws without a new price: the item's name once it
-- arrives, your sales, and the cooldown.
local function refreshRow(row)
	local entry = row.entry
	if row.output and not row.itemName then
		row.itemName = C_Item.GetItemNameByID(row.output.itemID)
		if not row.itemName then C_Item.RequestLoadItemDataByID(row.output.itemID) end
	end
	row.sortName = (row.itemName or entry.name or ""):lower()
	row.sold = ns.Sales.Sold(row.itemName or entry.name)
	row.cooldown = BestCrafts.IsMine(entry) and cooldownOf(entry.recipeID) or nil
end

-- Every scanned recipe as a list row (see priceEntry), with All characters on,
-- your characters' saved ones too. Rows are priced once and kept until
-- BestCrafts.Reprice.
function BestCrafts.Rows()
	local rows = {}
	if not scan then return rows end
	if not effectiveCost then BestCrafts.Reprice() end
	local function add(entry)
		local row = priced[entry]
		if not row then
			row = priceEntry(entry)
			priced[entry] = row
		end
		refreshRow(row)
		rows[#rows + 1] = row
	end
	for _, entry in ipairs(scan.recipes) do add(entry) end
	if ns.db.bestAllCharacters then
		for _, entry in ipairs(ns.Scans.Entries(scan.professionID)) do add(entry) end
	end
	return rows
end

-- The rank-by-rank details for a row's tooltip: { rank, link, sale, listed } for
-- each rank the recipe makes, best first.
function BestCrafts.Ranks(row)
	local list = {}
	for rank = row.entry.maxRank, 1, -1 do
		local output = row.entry.outputs[rank]
		if output then
			list[#list + 1] = { rank = rank, link = output.link,
				sale = ns.Prices.Sale(output.link, output.itemID), listed = ns.Prices.Listed(output.link) }
		end
	end
	return list
end

-- The materials a row is priced with: { itemID, qty, price } ..., price nil
-- when it has none.
function BestCrafts.Materials(row)
	local list = {}
	for _, slot in ipairs(row.entry.slots) do
		local itemID = row.picks[slot.slotIndex]
		list[#list + 1] = { itemID = itemID, qty = slot.qty, price = ns.Prices.Material(itemID) }
	end
	for _, other in ipairs(row.entry.others) do
		local bestID, bestPrice = other.itemIDs[1], nil
		for _, itemID in ipairs(other.itemIDs) do
			local price = ns.Prices.Material(itemID)
			if price and (not bestPrice or price < bestPrice) then bestID, bestPrice = itemID, price end
		end
		list[#list + 1] = { itemID = bestID, qty = other.qty, price = bestPrice }
	end
	return list
end

-- The shopping list of an entry: a saved one's goes on its own character and
-- profession's, whichever window is open.
local function listNameOf(entry)
	if not entry.character then return ns.Shopping.ListName() end
	local name, profession = ns.Ranks.ListOwner(entry.character, entry.professionID)
	return ns.Shopping.ListName(profession, name)
end

-- What the shopping list needs for a row: the panel's model fields for what's
-- missing, buying the qualities the row is priced with, and the list it goes on.
function BestCrafts.ShoppingModel(row)
	local schematic, picks = row.entry.schematic, row.picks
	return {
		missing = ns.Model.Missing(schematic, {}, picks),
		missingFor = function(crafts) return ns.Model.Missing(schematic, {}, picks, crafts) end,
		shoppable = true,
		listName = listNameOf(row.entry),
	}
end

---------------------------------------------------------------------------
-- Scanning again when what you can craft changes
---------------------------------------------------------------------------

local rescanQueued
local function queueRescan()
	if rescanQueued or not scan then return end
	rescanQueued = true
	C_Timer.After(RESCAN_DELAY, function()
		rescanQueued = false
		if isWanted() then BestCrafts.Scan() end
	end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "SKILL_LINES_CHANGED", "TRAIT_CONFIG_UPDATED", "PROFESSION_EQUIPMENT_CHANGED", "NEW_RECIPE_LEARNED" }) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", queueRescan)
