-- Craft Profit: on a crafted item's tooltip, the best rank each of your
-- characters can craft it at with the top quality of every material, using
-- concentration when that reaches a higher rank.
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

-- CraftProfitDB.characters["Name-Realm"] = {
--   name, realm, class = for showing the character on tooltips,
--   professions = { [professionID] = {
--     parent = base profession (Blacksmithing), for dropping unlearned ones,
--     recipes = { [recipeID] = { best rank, max rank, concentration cost } },
--     items = { [itemID] = recipeID },  -- every item the recipe makes, any quality
--   } },
-- }
local characters
local myKey, saved -- this character's key and professions, from login on

function Ranks.Init()
	CraftProfitDB.characters = CraftProfitDB.characters or {}
	characters = CraftProfitDB.characters
end

-- This character's entry, made on login. Ranks saved per character by 1.7 and
-- 1.8 move into it.
local function login()
	local name, realm = UnitFullName("player")
	realm = realm or GetNormalizedRealmName()
	if not (name and realm) then return end
	myKey = name .. "-" .. realm
	local me = characters[myKey] or { professions = {} }
	me.name, me.realm, me.class = name, realm, UnitClassBase("player")
	characters[myKey] = me
	if CraftProfitCharDB and CraftProfitCharDB.professions then
		for professionID, profession in pairs(CraftProfitCharDB.professions) do
			me.professions[professionID] = me.professions[professionID] or profession
		end
		CraftProfitCharDB.professions = nil
	end
	saved = me.professions
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
	if not characters then return end
	if event == "PLAYER_LOGIN" then
		login()
		if saved then dropUnlearned() end
	elseif saved then
		queueScan()
	end
end)

---------------------------------------------------------------------------
-- The tooltip line
---------------------------------------------------------------------------

-- A character's best saved rank for an item, and the recipe it's for.
local function lookup(professions, itemID)
	local bestRank, bestRecipe
	for _, profession in pairs(professions) do
		local recipeID = profession.items[itemID]
		local rank = recipeID and profession.recipes[recipeID]
		if rank and (not bestRank or rank[1] > bestRank[1]) then bestRank, bestRecipe = rank, recipeID end
	end
	return bestRank, bestRecipe
end

-- "Max rank <icon> (38 concentration)" and its color.
local function rankText(rank, recipeID)
	local best, max, cost = rank[1], rank[2], rank[3]
	local text = best >= max and "Max rank" or format("Rank %d of %d", best, max)
	local ok, icon = pcall(ns.Blizzard.ItemQualityMarkup, recipeID, best)
	if ok and icon then text = text .. " " .. icon end
	if ns.db.rankConcentration and cost > 0 then text = text .. format(" (%d concentration)", cost) end
	local r, g, b = CreateColorFromHexString(best >= max and ns.Colors.good or ns.Colors.missing):GetRGB()
	return text, r, g, b
end

-- A character's name in its class color, with the realm when it's not this one
-- (or always, with withRealm).
local function characterName(character, withRealm)
	local name = character.name or "?"
	if character.realm and (withRealm or (myKey and character.realm ~= characters[myKey].realm)) then
		name = name .. "-" .. character.realm
	end
	local color = character.class and C_ClassColor.GetClassColor(character.class)
	return color and color:WrapTextInColorCode(name) or name
end

-- Every character that can craft the item, best rank first, then this character.
local function knownBy(itemID)
	local list = {}
	for key, character in pairs(characters) do
		local rank, recipeID = lookup(character.professions or {}, itemID)
		if rank then list[#list + 1] = { key = key, character = character, rank = rank, recipeID = recipeID } end
	end
	table.sort(list, function(a, b)
		if a.rank[1] ~= b.rank[1] then return a.rank[1] > b.rank[1] end
		if (a.key == myKey) ~= (b.key == myKey) then return a.key == myKey end
		return a.key < b.key
	end)
	return list
end

local function onItem(tooltip, data)
	if not (saved and ns.db and ns.db.rankTooltip) then return end
	local itemID = data and data.id
	if type(itemID) ~= "number" or (issecretvalue and issecretvalue(itemID)) then return end

	if ns.db.rankCharacters ~= "all" then
		local rank, recipeID = lookup(saved, itemID)
		if not rank then return end
		local text, r, g, b = rankText(rank, recipeID)
		tooltip:AddDoubleLine("Craft Rank", text, 1, 0.82, 0, r, g, b)
		return
	end

	local list = knownBy(itemID)
	if #list == 0 then return end
	tooltip:AddLine("Craft Rank", 1, 0.82, 0)
	for _, entry in ipairs(list) do
		local text, r, g, b = rankText(entry.rank, entry.recipeID)
		tooltip:AddDoubleLine("  " .. characterName(entry.character), text, 1, 1, 1, r, g, b)
	end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)

---------------------------------------------------------------------------
-- Forgetting characters you deleted, renamed or moved
---------------------------------------------------------------------------

function Ranks.Forget(key)
	if not (characters and characters[key]) then return end
	local name = characterName(characters[key], true)
	characters[key] = nil
	ns.Shopping.Say(format("Forgot %s's Craft Ranks.", name))
end

StaticPopupDialogs.CRAFTPROFIT_FORGET_CHARACTER = {
	text = "Forget %s's Craft Ranks?",
	button1 = "Forget",
	button2 = CANCEL,
	OnAccept = function(_, key) Ranks.Forget(key) end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- A menu of your other saved characters; picking one asks, then forgets it.
-- This character isn't listed, since it would be saved again right away.
function Ranks.OpenForgetMenu()
	MenuUtil.CreateContextMenu(UIParent, function(_, root)
		root:CreateTitle("Forget a character")
		local others = {}
		for key, character in pairs(characters or {}) do
			if key ~= myKey then others[#others + 1] = { key = key, character = character } end
		end
		table.sort(others, function(a, b) return a.key < b.key end)
		if #others == 0 then
			root:CreateButton(ns.Color("muted", "No other characters saved"), nop):SetEnabled(false)
		end
		for _, entry in ipairs(others) do
			local name = characterName(entry.character, true)
			root:CreateButton(name, function()
				StaticPopup_Show("CRAFTPROFIT_FORGET_CHARACTER", name, nil, entry.key)
			end)
		end
	end)
end
