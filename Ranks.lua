-- Craft Profit: on a crafted item's tooltip, the best rank each of your
-- characters can craft it at with the top quality of every material, using
-- concentration when that reaches a higher rank. Also the best rank with the
-- optional reagents that make it hardest (the ones that raise its item level).
--
-- The game only gives addons your crafting skill while the profession window is
-- open, so each recipe's best rank is worked out and saved then, and tooltips
-- show what was saved.
local _, ns = ...

local Ranks = {}
ns.Ranks = Ranks

local format = string.format

-- Milliseconds the scan may spend each frame, so it never slows the game down.
-- One question to the game can take about a millisecond, so this is a few of them.
local FRAME_BUDGET_MS = 2
-- Seconds to wait after the recipe list changes before scanning it, so a burst
-- of changes (opening the window, crafting) scans once.
local SCAN_DELAY = 1

-- CraftProfitDB.characters["Name-Realm"] = {
--   name, realm, class = for showing the character on tooltips,
--   professions = { [professionID] = {
--     parent = base profession (Blacksmithing), for dropping unlearned ones,
--     recipes = { [recipeID] = { best rank, max rank, concentration cost,
--                                with optional reagents: best rank, concentration cost } },
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

local deadline = 0 -- when this frame's share of the scan runs out

-- The scan runs as a coroutine; this pauses it until the next frame once this
-- frame's share is used up.
local function pauseIfDue()
	if debugprofilestop() > deadline then coroutine.yield() end
end

-- How a craft with these reagents turns out, or nil.
local function operation(recipeID, reagents)
	local ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, reagents, nil, false)
	pauseIfDue()
	return ok and info and info.craftingQuality and info or nil
end

local function difficultyOf(info)
	return (info.baseDifficulty or 0) + (info.bonusDifficulty or 0)
end

-- The best rank and its concentration cost. Concentration lifts a craft to the
-- next rank, for the cost the game quotes.
local function bestOf(info, max)
	local best = info.craftingQuality
	if best < max and (info.concentrationCost or 0) > 0 then return best + 1, info.concentrationCost end
	return best, 0
end

-- A slot's reagents, each at its top rank: a reagent's ranks come one after
-- another, lowest first, and a higher rank makes the craft easier.
local function topRanks(slot)
	local list, lastQuality = {}, nil
	for _, reagent in ipairs(slot.reagents) do
		if reagent.itemID then
			local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(reagent.itemID) or 0
			if quality > 0 and lastQuality and quality > lastQuality then
				list[#list] = reagent.itemID -- the next rank of the same reagent
			else
				list[#list + 1] = reagent.itemID
			end
			lastQuality = quality > 0 and quality or nil
		end
	end
	return list
end

-- Adds to `reagents` the optional reagent in each slot that makes the craft
-- hardest (the one that raises its item level the most), at its top rank.
-- Returns how it turns out then, or nil when none makes it harder.
local function withHardestOptional(recipeID, schematic, reagents, info)
	local harder
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		if slot.reagentType == Enum.CraftingReagentType.Modifying and not slot.hiddenInCraftingForm then
			local hardest, hardestInfo
			for _, itemID in ipairs(topRanks(slot)) do
				local entry = { reagent = { itemID = itemID }, dataSlotIndex = slot.dataSlotIndex, quantity = slot.quantityRequired }
				reagents[#reagents + 1] = entry
				local trial = operation(recipeID, reagents)
				reagents[#reagents] = nil
				if trial and difficultyOf(trial) > difficultyOf(hardestInfo or info) then hardest, hardestInfo = entry, trial end
			end
			if hardest then
				reagents[#reagents + 1] = hardest
				info, harder = hardestInfo, hardestInfo
			end
		end
	end
	return harder
end

-- { best, max, cost, best and cost with optional reagents } for a learned recipe,
-- and the item it makes, or nil. The last two are nil when no optional reagent
-- makes it harder.
local function rankOf(recipeID, recipeInfo)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if not (schematic and schematic.hasCraftingOperationInfo) then return end
	local max = recipeInfo.maxQuality or (recipeInfo.qualityIDs and #recipeInfo.qualityIDs)
	if not max or max < 2 then return end
	local reagents = topQualityReagents(schematic)
	local info = operation(recipeID, reagents)
	if not info then return end

	local best, cost = bestOf(info, max)
	local rank = { best, max, cost }
	local harder = withHardestOptional(recipeID, schematic, reagents, info)
	if harder then rank[4], rank[5] = bestOf(harder, max) end
	return rank, schematic.outputItemID
end

-- Testing (/craftprofit testrank): prints how the open crafting order turns out
-- next to how Craft Rank works it out for the same recipe. False when no order is open.
function Ranks.Explain()
	local ctx = ns.Blizzard.OrderContext()
	if not (ctx and ctx.live and ctx.transaction) then return false end
	local order, transaction = ctx.order, ctx.transaction
	local recipeID = order.spellID
	local function say(...) print("|cffffd100Craft Profit:|r " .. format(...)) end
	local function line(label, info)
		if not info then return say("%s: no answer", label) end
		say("%s: rank %s, difficulty %d + %d, skill %d + %d, concentration %d", label, tostring(info.craftingQuality),
			info.baseDifficulty or 0, info.bonusDifficulty or 0, info.baseSkill or 0, info.bonusSkill or 0, info.concentrationCost or 0)
	end
	local function list(label, reagents)
		for _, entry in ipairs(reagents) do
			local itemID = entry.reagent and entry.reagent.itemID or entry.itemID
			say("  %s: slot %s, %s x%s (rank %s)", label, tostring(entry.dataSlotIndex), itemID and (C_Item.GetItemNameByID(itemID) or itemID) or "?",
				tostring(entry.quantity), itemID and tostring(C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)) or "-")
		end
	end
	local outsideScan = deadline
	deadline = math.huge -- not in a scan: never pause

	local guid = transaction:GetAllocationItemGUID()
	local formReagents = transaction:CreateCraftingReagentInfoTbl()
	say("Recipe %d, recraft %s, customer's item %s, concentrating %s", recipeID, tostring(order.isRecraft),
		guid and "yes" or "no", tostring(ns.Blizzard.IsConcentrating(transaction)))
	list("order", formReagents)
	local ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, formReagents, guid, false)
	line("Order form", ok and info or nil)
	line("Order materials, without the customer's item", operation(recipeID, formReagents))

	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	local reagents = schematic and topQualityReagents(schematic) or {}
	local top = operation(recipeID, reagents)
	line("Craft Rank, top materials", top)
	local harder = top and withHardestOptional(recipeID, schematic, reagents, top)
	line("Craft Rank, hardest optional reagents", harder)
	list("craft rank", reagents)
	for professionID, profession in pairs(saved or {}) do
		local rank = profession.recipes[recipeID]
		if rank then say("Saved (profession %d): best %s of %s, concentration %s", professionID, tostring(rank[1]), tostring(rank[2]), tostring(rank[3])) end
	end
	deadline = outsideScan
	return true
end

-- The profession the window shows right now (Midnight Blacksmithing) and its base (Blacksmithing).
local function shownProfession()
	local child = C_TradeSkillUI.GetChildProfessionInfo()
	local base = C_TradeSkillUI.GetBaseProfessionInfo()
	if not (child and child.professionID and child.professionID > 0) then return end
	return child.professionID, base and base.professionID
end

-- Works out the rank of every recipe in the list and saves them. Runs as a
-- coroutine, a little each frame.
local function scanAll(professionID, recipeIDs, parentID)
	local result = { parent = parentID, recipes = {}, items = {} }
	for _, recipeID in ipairs(recipeIDs) do
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
		pauseIfDue()
	end
	saved[professionID] = result
end

local scanRun -- the scan in progress; a scan of another profession replaces it
local rescan  -- the recipe list changed during the scan: scan again once it's done
local queueScan

local function scan()
	if not ns.Blizzard.IsOwnProfession() then return end
	local professionID, parentID = shownProfession()
	if not professionID then return end
	-- Already scanning this profession: finish first, then go again.
	if scanRun and scanRun.professionID == professionID then
		rescan = true
		return
	end
	local recipeIDs = (C_TradeSkillUI.GetAllRecipeIDs or C_TradeSkillUI.GetFilteredRecipeIDs)()
	if not recipeIDs or #recipeIDs == 0 then return end

	local run = { professionID = professionID, thread = coroutine.create(scanAll) }
	scanRun, rescan = run, false
	local function step()
		if scanRun ~= run then return end
		-- Stop without saving if the window closed or switched profession: the
		-- game's answers would be wrong from here on.
		if not ns.Blizzard.IsOwnProfession() or shownProfession() ~= professionID then
			scanRun, rescan = nil, false
			return
		end
		-- The Best crafts list's scan goes first: both in one frame would slow the game down.
		if ns.BestCrafts.Progress() then
			C_Timer.After(0, step)
			return
		end
		deadline = debugprofilestop() + FRAME_BUDGET_MS
		local ok, err = coroutine.resume(run.thread, professionID, recipeIDs, parentID)
		if not ok then
			scanRun = nil
			geterrorhandler()(err)
			return
		end
		if coroutine.status(run.thread) ~= "dead" then
			C_Timer.After(0, step)
			return
		end
		scanRun = nil
		if rescan then
			rescan = false
			queueScan()
		end
	end
	step()
end

local scanQueued
function queueScan()
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

-- "Max rank <icon> (38 concentration)" and its color. `best` and `cost` replace
-- the rank's own, for the rank with optional reagents.
local function rankText(rank, recipeID, best, cost)
	local max = rank[2]
	best, cost = best or rank[1], cost or rank[3]
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

-- The rank with optional reagents, when it's worse than without them.
local function harderText(rank, recipeID)
	if not rank[4] or (rank[4] == rank[1] and rank[5] == rank[3]) then return end
	return rankText(rank, recipeID, rank[4], rank[5])
end

local HARDER_LABEL = "with optional reagents"

local function onItem(tooltip, data)
	if not (saved and ns.db and ns.db.rankTooltip) then return end
	local itemID = data and data.id
	if type(itemID) ~= "number" or (issecretvalue and issecretvalue(itemID)) then return end

	if ns.db.rankCharacters ~= "all" then
		local rank, recipeID = lookup(saved, itemID)
		if not rank then return end
		local text, r, g, b = rankText(rank, recipeID)
		tooltip:AddDoubleLine("Craft Rank", text, 1, 0.82, 0, r, g, b)
		text, r, g, b = harderText(rank, recipeID)
		if text then tooltip:AddDoubleLine("  " .. HARDER_LABEL, text, 0.53, 0.53, 0.53, r, g, b) end
		return
	end

	local list = knownBy(itemID)
	if #list == 0 then return end
	tooltip:AddLine("Craft Rank", 1, 0.82, 0)
	for _, entry in ipairs(list) do
		local text, r, g, b = rankText(entry.rank, entry.recipeID)
		tooltip:AddDoubleLine("  " .. characterName(entry.character), text, 1, 1, 1, r, g, b)
		text, r, g, b = harderText(entry.rank, entry.recipeID)
		if text then tooltip:AddDoubleLine("    " .. HARDER_LABEL, text, 0.53, 0.53, 0.53, r, g, b) end
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
