-- Craft Profit: on a crafted item's tooltip, the best rank this character can
-- craft it at with the top quality of every material, using concentration when
-- that reaches a higher rank.
--
-- The game only gives addons your crafting skill while the profession window is
-- open, so each recipe's best rank is worked out and saved then, and tooltips
-- show what was saved.
local _, ns = ...

local Ranks = {}
ns.Ranks = Ranks

local format = string.format

-- Recipes worked out per frame, so opening the window doesn't stutter.
local BATCH = 25
-- Seconds to wait after the recipe list changes before scanning it, so a burst
-- of changes (opening the window, crafting) scans once.
local SCAN_DELAY = 1

-- CraftProfitCharDB.professions[professionID] = {
--   parent = base profession (Blacksmithing), for dropping unlearned ones,
--   recipes = { [recipeID] = { best rank, max rank, concentration cost } },
--   items = { [itemID] = recipeID },  -- every item the recipe makes, any quality
-- }
local saved

function Ranks.Init()
	CraftProfitCharDB = CraftProfitCharDB or {}
	CraftProfitCharDB.professions = CraftProfitCharDB.professions or {}
	saved = CraftProfitCharDB.professions
end

---------------------------------------------------------------------------
-- Working out the ranks
---------------------------------------------------------------------------

-- The recipe's required materials that come in qualities, each at its top quality.
local function topQualityReagents(schematic)
	local list = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		if slot.required and slot.reagentType == Enum.CraftingReagentType.Basic
			and slot.dataSlotType == Enum.TradeskillSlotDataType.ModifiedReagent then
			local top, topQuality
			for _, reagent in ipairs(slot.reagents) do
				local quality = reagent.itemID and C_TradeSkillUI.GetItemReagentQualityByItemInfo(reagent.itemID) or 0
				if not top or quality > topQuality then top, topQuality = reagent, quality end
			end
			if top and top.itemID then
				list[#list + 1] = { reagent = { itemID = top.itemID }, dataSlotIndex = slot.dataSlotIndex, quantity = slot.quantityRequired }
			end
		end
	end
	return list
end

-- { best, max, cost } for a learned recipe, and the item it makes, or nil.
local function rankOf(recipeID, recipeInfo)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if not (schematic and schematic.hasCraftingOperationInfo) then return end
	local max = recipeInfo.maxQuality or (recipeInfo.qualityIDs and #recipeInfo.qualityIDs)
	if not max or max < 2 then return end
	local ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, topQualityReagents(schematic), nil, false)
	if not (ok and info and info.craftingQuality) then return end

	local best, cost = info.craftingQuality, 0
	-- Concentration lifts a craft to the next rank, for the cost the game quotes.
	if best < max and (info.concentrationCost or 0) > 0 then
		best, cost = best + 1, info.concentrationCost
	end
	return { best, max, cost }, schematic.outputItemID
end

-- The profession the window shows right now (Midnight Blacksmithing) and its base (Blacksmithing).
local function shownProfession()
	local child = C_TradeSkillUI.GetChildProfessionInfo()
	local base = C_TradeSkillUI.GetBaseProfessionInfo()
	if not (child and child.professionID and child.professionID > 0) then return end
	return child.professionID, base and base.professionID
end

local scanRun -- the scan in progress; a newer one replaces it

local function scan()
	if not ns.Blizzard.IsOwnProfession() then return end
	local professionID, parentID = shownProfession()
	if not professionID then return end
	local recipeIDs = (C_TradeSkillUI.GetAllRecipeIDs or C_TradeSkillUI.GetFilteredRecipeIDs)()
	if not recipeIDs or #recipeIDs == 0 then return end

	local result = { parent = parentID, recipes = {}, items = {} }
	local run = {}
	scanRun = run
	local i = 0
	local function step()
		-- Stop without saving if a newer scan started, the window closed or it
		-- switched profession: the game's answers would be wrong from here on.
		if scanRun ~= run then return end
		if not ns.Blizzard.IsOwnProfession() or shownProfession() ~= professionID then
			scanRun = nil
			return
		end
		for _ = 1, BATCH do
			i = i + 1
			local recipeID = recipeIDs[i]
			if not recipeID then
				saved[professionID] = result
				scanRun = nil
				return
			end
			local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
			if info and info.learned and info.supportsQualities
				and not (info.isRecraft or info.isSalvageRecipe or info.isDummyRecipe) then
				local rank, outputID = rankOf(recipeID, info)
				if rank then
					result.recipes[recipeID] = rank
					for _, itemID in ipairs(info.qualityItemIDs or {}) do result.items[itemID] = recipeID end
					if outputID then result.items[outputID] = recipeID end
				end
			end
		end
		C_Timer.After(0, step)
	end
	step()
end

local scanQueued
local function queueScan()
	if scanQueued or not ns.Blizzard.IsOwnProfession() then return end
	scanQueued = true
	C_Timer.After(SCAN_DELAY, function()
		scanQueued = false
		scan()
	end)
end

-- Forget professions this character has unlearned.
local function dropUnlearned()
	local known = {}
	for _, index in pairs({ GetProfessions() }) do
		local skillLine = select(7, GetProfessionInfo(index))
		if skillLine then known[skillLine] = true end
	end
	if not next(known) then return end
	for professionID, profession in pairs(saved) do
		if profession.parent and not known[profession.parent] then saved[professionID] = nil end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
events:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
events:SetScript("OnEvent", function(_, event)
	if not saved then return end
	if event == "PLAYER_LOGIN" then
		dropUnlearned()
	else
		queueScan()
	end
end)

---------------------------------------------------------------------------
-- The tooltip line
---------------------------------------------------------------------------

-- The best saved rank for an item, and the recipe it's for.
local function lookup(itemID)
	local bestRank, bestRecipe
	for _, profession in pairs(saved) do
		local recipeID = profession.items[itemID]
		local rank = recipeID and profession.recipes[recipeID]
		if rank and (not bestRank or rank[1] > bestRank[1]) then bestRank, bestRecipe = rank, recipeID end
	end
	return bestRank, bestRecipe
end

local function onItem(tooltip, data)
	if not (saved and ns.db and ns.db.rankTooltip) then return end
	local itemID = data and data.id
	if type(itemID) ~= "number" or (issecretvalue and issecretvalue(itemID)) then return end
	local rank, recipeID = lookup(itemID)
	if not rank then return end

	local best, max, cost = rank[1], rank[2], rank[3]
	local text = best >= max and "Max rank" or format("Rank %d of %d", best, max)
	local ok, icon = pcall(ns.Blizzard.ItemQualityMarkup, recipeID, best)
	if ok and icon then text = text .. " " .. icon end
	if ns.db.rankConcentration and cost > 0 then text = text .. format(" (%d concentration)", cost) end

	local color = best >= max and ns.Colors.good or ns.Colors.missing
	local r, g, b = CreateColorFromHexString(color):GetRGB()
	tooltip:AddDoubleLine("Craft Rank", text, 1, 0.82, 0, r, g, b)
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
