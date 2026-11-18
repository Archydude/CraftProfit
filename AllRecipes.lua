-- Craft Profit: every profession's recipes, priced as if you bought the
-- materials and sold what a craft makes, whether or not a character of yours
-- knows the recipe. For the All recipes window (AllRecipesWindow.lua). The recipes
-- are unpacked and priced a few at a time while the window is open, and let go
-- when it closes.
--
-- WoW Forever: all of them at once, from Data\ForeverRecipes.lua, which has what
-- each takes and makes. An enchant makes nothing to sell there: it has only what
-- its materials cost.
--
-- Retail: one expansion at a time, from Data\RetailRecipes.lua, which only says
-- which recipes there are: the game says what each takes and makes. A recipe with
-- ranks is priced at its highest rank with the best materials, or at its lowest
-- with the cheapest (ns.db.recipesRank): nobody's skill is there to say which rank
-- a craft would come out at.
local _, ns = ...

local AllRecipes = {}
ns.AllRecipes = AllRecipes

-- Pricing works this long each frame, then waits for the next one.
local FRAME_BUDGET_MS = 4

-- Every recipe while the window is open: {
--   recipeID, itemID, link = the item as price addons are asked about it (an
--   enchant, which makes no item, has neither, and enchant = true),
--   made = how many one craft makes (the average, for recipes that make a range),
--   professionID, profession = its name, materials = { { itemID, qty } ... }
--   (on Retail a material that comes in several also has options = their item IDs,
--   lowest quality first, and qualities = true when they're one material's
--   qualities; itemID is then the one the craft is priced with),
--   rank = the rank it's priced at, and highest = whether that's its highest (Retail,
--   rank nil for a recipe without ranks),
--   recipeName, name = the item's (the recipe's until the game has loaded it),
--   required = the skill the recipe needs (nil for one a trainer teaches: the game
--   data doesn't have it), yellow and grey = the skills where it turns yellow and
--   grey (nil when the data has neither), skill = what the Skill column shows and
--   sorts by: required, or else yellow,
--   -- once priced:
--   each = what one item sells for (nil without a price), gross = what a craft's
--   items sell for after the auction house cut, cost = the materials (nil when one
--   has no price), unpriced = how many of them have none, net = gross - cost,
--   saleRate and soldPerDay = TSM's (nil without). An enchant has only cost and
--   unpriced,
-- }
local rows
local byItem -- itemID -> the rows that make it (a few items have two recipes)
-- Every material's name in lower case, for the search: itemID -> name, or false
-- until the game has loaded the item.
local materialNames
-- The pricing in progress or finished: { done, total, finished, buy and keep = what
-- it prices with (see priceRow) }.
local run
local deadline = 0 -- when this frame's share of the pricing runs out

local function pauseIfDue()
	if debugprofilestop() > deadline then coroutine.yield() end
end

-- A profession's name, in the game's language when the game or the data has it.
function AllRecipes.ProfessionName(professionID)
	if ns.QUALITY_CRAFTING then
		local name = C_TradeSkillUI.GetTradeSkillDisplayName and C_TradeSkillUI.GetTradeSkillDisplayName(professionID)
		return name and name ~= "" and name or ns.RECIPE_PROFESSIONS[professionID]
	end
	local names = ns.RECIPE_PROFESSION_NAMES[GetLocale()]
	return names and names[professionID] or ns.RECIPE_PROFESSIONS[professionID]
end

-- The professions with recipes here: { { id, name } ... }, by name.
function AllRecipes.Professions()
	local list = {}
	for professionID in pairs(ns.RECIPE_PROFESSIONS) do
		list[#list + 1] = { id = professionID, name = AllRecipes.ProfessionName(professionID) }
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

-- Retail: the expansions with recipes: { { id, name } ... }, newest first. The
-- name is the game's own for the expansion, in its language.
function AllRecipes.Expansions()
	local list = {}
	for id, name in pairs(ns.RECIPE_EXPANSIONS or {}) do
		list[#list + 1] = { id = id, name = _G["EXPANSION_NAME" .. id] or name }
	end
	table.sort(list, function(a, b) return a.id > b.id end)
	return list
end

-- Retail: the expansion whose recipes the window lists: the one you picked, or
-- the newest.
function AllRecipes.Expansion()
	local picked = ns.db.recipesExpansion
	if picked and ns.RETAIL_RECIPES[picked] then return picked end
	local newest
	for id in pairs(ns.RETAIL_RECIPES) do
		if not newest or id > newest then newest = id end
	end
	return newest
end

-- Retail: whether recipes with ranks are priced at their highest rank with the
-- best materials (otherwise at their lowest, with the cheapest).
function AllRecipes.Highest()
	return ns.db.recipesRank ~= "lowest"
end

-- One line of the data ("recipe:item:made:skill needed:material.count,...") as a row, or nil.
local function unpackRecipe(text, professionID, profession)
	local recipeID, itemID, made, required, packed = text:match("^(%d+):(%d+):([%d.]+):(%d+):(.+)$")
	if not recipeID then return end
	local materials = {}
	for material, qty in packed:gmatch("(%d+)%.(%d+)") do
		materials[#materials + 1] = { itemID = tonumber(material), qty = tonumber(qty) }
	end
	recipeID, itemID, required = tonumber(recipeID), tonumber(itemID), tonumber(required)
	if required == 0 then required = nil end
	-- Item 0: an enchant, which makes no item.
	local enchant = itemID == 0
	if enchant then itemID = nil end
	-- Where it turns yellow and grey, from the skill-up data (Data\Forever.lua).
	local colors = ns.SKILLUPS and ns.SKILLUPS[recipeID]
	local yellow, grey = colors and colors[1], colors and colors[2]
	if yellow == 0 then yellow = nil end
	if grey == 0 then grey = nil end
	local recipeName = C_Spell.GetSpellName(recipeID)
	return { recipeID = recipeID, itemID = itemID, link = itemID and "item:" .. itemID, enchant = enchant,
		made = tonumber(made),
		professionID = professionID, profession = profession, materials = materials,
		required = required, yellow = yellow, grey = grey, skill = required or yellow,
		recipeName = recipeName, name = recipeName or "?" }
end

-- Retail: the item a recipe makes at a rank (nil for a recipe without ranks):
-- link and itemID, or nil. An enchant makes its scroll.
local function retailOutput(recipeID, name, scroll, qualityIDs, rank)
	if scroll then
		local link, itemID = ns.Blizzard.ScrollAt(recipeID, name, rank)
		-- The scrolls can have fewer ranks than the game says the recipe has.
		if not itemID then link, itemID = ns.Blizzard.ScrollAt(recipeID, name) end
		return link, itemID
	end
	local ok, output = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID, {}, nil, rank and qualityIDs[rank])
	if ok and output and output.hyperlink and (output.itemID or 0) > 0 then return output.hyperlink, output.itemID end
end

-- Retail: one recipe as a row, from what the game says about it, or nil when it
-- makes nothing to sell. `highest`: see AllRecipes.Highest.
local function retailRow(recipeID, professionID, profession, highest)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if not schematic then return end
	local scroll = ns.Blizzard.MakesScroll(recipeID)
	if scroll then
		schematic = ns.Blizzard.ScrollSchematic(schematic)
	elseif schematic.recipeType ~= Enum.TradeskillRecipeType.Item then
		return
	end

	local qualityIDs = C_TradeSkillUI.GetQualitiesForRecipe(recipeID)
	local ranks = qualityIDs and #qualityIDs or 0
	local rank = ranks > 1 and (highest and ranks or 1) or nil
	local link, itemID = retailOutput(recipeID, schematic.name, scroll, qualityIDs, rank)
	if not itemID then return end

	-- What it needs: every required slot, with all the items that can fill it.
	local materials = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		if slot.required then
			local options = {}
			for _, reagent in ipairs(slot.reagents or {}) do
				if reagent.itemID then options[#options + 1] = reagent.itemID end
			end
			if #options > 0 then
				materials[#materials + 1] = { itemID = options[1], qty = slot.quantityRequired or 1,
					options = #options > 1 and options or nil,
					qualities = #options > 1 and ns.Blizzard.IsQualitySlot(slot) or nil }
			end
		end
	end

	local name = schematic.name
	return { recipeID = recipeID, itemID = itemID, link = link, enchant = false,
		made = ((schematic.quantityMin or 1) + (schematic.quantityMax or 1)) / 2,
		professionID = professionID, profession = profession, materials = materials,
		rank = rank, highest = highest, recipeName = name, name = name or "?" }
end

-- Retail: which of a material's items a craft is priced with: the best quality at
-- the highest rank, and otherwise the cheapest (the first while none has a price).
local function pickMaterial(material, buy, highest)
	local options = material.options
	if highest and material.qualities then return options[#options] end
	local cheapest, lowest
	for _, itemID in ipairs(options) do
		local price = buy(itemID)
		if price and (not lowest or price < lowest) then cheapest, lowest = itemID, price end
	end
	return cheapest or options[1]
end

-- A material's name in lower case, or nil until the game has loaded it (it's
-- asked to, and AllRecipes.ItemArrived hears when it has).
local function materialName(itemID)
	local name = materialNames[itemID]
	if name then return name end
	name = C_Item.GetItemNameByID(itemID)
	if name then
		name = name:lower()
		materialNames[itemID] = name
		return name
	end
	if materialNames[itemID] == nil then
		materialNames[itemID] = false
		C_Item.RequestLoadItemDataByID(itemID)
	end
end

-- Whether one of the recipe's materials has `search` (lower case) in its name.
function AllRecipes.UsesMaterial(row, search)
	if not materialNames then return false end
	for _, material in ipairs(row.materials) do
		local name = materialName(material.itemID)
		if name and name:find(search, 1, true) then return true end
	end
	return false
end

-- Unpacks every recipe: all of WoW Forever's, or on Retail the shown expansion's,
-- asking the game about each (`this` is the pricing: it's told how far that is).
-- They only count once all are there: a pricing dropped halfway leaves nothing
-- behind.
local function unpackAll(this)
	local list, items = {}, {}
	local function add(row)
		if not row then return end
		list[#list + 1] = row
		if row.itemID then
			local same = items[row.itemID]
			if not same then
				same = {}
				items[row.itemID] = same
			end
			same[#same + 1] = row
		end
	end
	if ns.QUALITY_CRAFTING then
		local packed = ns.RETAIL_RECIPES[AllRecipes.Expansion()] or {}
		local highest = AllRecipes.Highest()
		-- Asking the game is the first half of the work, pricing the second.
		local count = 0
		for _, recipes in pairs(packed) do
			count = count + select(2, recipes:gsub("%d+", "")) -- how many recipes the text has
		end
		this.total = 2 * count
		for professionID, recipes in pairs(packed) do
			local profession = AllRecipes.ProfessionName(professionID)
			for recipeID in recipes:gmatch("%d+") do
				add(retailRow(tonumber(recipeID), professionID, profession, highest))
				this.done = this.done + 1
				pauseIfDue()
			end
		end
		this.scanned = count
	else
		for professionID, packed in pairs(ns.ALL_RECIPES) do
			local profession = AllRecipes.ProfessionName(professionID)
			for _, text in ipairs(packed) do
				add(unpackRecipe(text, professionID, profession))
				pauseIfDue()
			end
		end
	end
	rows, byItem, materialNames = list, items, {}
end

-- Fills in what a recipe's materials cost at today's prices: cost and unpriced.
-- `buy` is what buying a material costs (see Prices.Buy).
local function priceMaterials(row, buy)
	local cost, unpriced = 0, 0
	for _, material in ipairs(row.materials) do
		if material.options then material.itemID = pickMaterial(material, buy, row.highest) end
		materialName(material.itemID) -- asked for now, so the search has it by the time you type
		local price = buy(material.itemID)
		if price then cost = cost + price * material.qty else unpriced = unpriced + 1 end
	end
	row.unpriced = unpriced
	row.cost = unpriced == 0 and cost or nil
end

-- Fills in what a recipe costs and makes at today's prices. `keep` is the share
-- of a sale the auction house leaves you.
local function priceRow(row, buy, keep)
	row.each, row.gross, row.cost, row.net, row.saleRate, row.soldPerDay = nil, nil, nil, nil, nil, nil
	-- An enchant makes nothing to sell: only its materials have a price.
	if row.enchant then return priceMaterials(row, buy) end
	-- The item's own name, once the game has loaded it. Some prices need the item
	-- loaded too, so it's priced again then (see AllRecipes.ItemArrived).
	local name = ns.Format.ItemName(row.itemID)
	if name then row.name = name else C_Item.RequestLoadItemDataByID(row.itemID) end
	row.each = ns.Prices.Sale(row.link, row.itemID)
	-- Without a price the window leaves it out, so there's nothing more to ask.
	if not row.each then return end
	priceMaterials(row, buy)
	row.gross = row.each * row.made * keep
	row.net = row.cost and row.gross - row.cost
	row.saleRate = ns.Prices.SaleRate(row.link)
	row.soldPerDay = ns.Prices.SoldPerDay(row.link)
end

local function priceAll(this)
	if not rows then unpackAll(this) end
	-- On Retail, asking the game about each recipe came first and counts too.
	local scanned = this.scanned or 0
	this.total = scanned + #rows
	-- Most materials are in many recipes: each is asked about once. False is "no price".
	local known = {}
	local function buy(itemID)
		local price = known[itemID]
		if price == nil then
			price = ns.Prices.Buy(itemID) or false
			known[itemID] = price
		end
		return price or nil
	end
	local keep = ns.db.ahCut and (1 - ns.AH_CUT) or 1
	-- Kept for the recipes priced again when their item loads.
	this.buy, this.keep = buy, keep
	for index, row in ipairs(rows) do
		priceRow(row, buy, keep)
		this.done = scanned + index
		pauseIfDue()
	end
end

-- Prices every recipe again, a few each frame. `onChange` is called after each
-- frame's share with the pricing ({ done, total, finished }); the rows are whole
-- once it's finished. A pricing still going is dropped.
function AllRecipes.Price(onChange)
	local this = { done = 0, total = 0, finished = false }
	run = this
	local thread = coroutine.create(priceAll)
	local function step()
		if run ~= this then return end
		deadline = debugprofilestop() + FRAME_BUDGET_MS
		local ok, err = coroutine.resume(thread, this)
		if not ok then
			run = nil
			geterrorhandler()(err)
			return
		end
		if coroutine.status(thread) == "dead" then this.finished = true end
		onChange(this)
		if not this.finished then C_Timer.After(0, step) end
	end
	step()
end

-- The recipes once they're all priced, or nil until then.
function AllRecipes.Rows()
	return run and run.finished and rows or nil
end

-- The game has loaded an item: its recipes go by its name from here on, and one
-- that had no price is priced again, since some prices need the item loaded.
-- A material's name is there for the search from here on. True when it's an item
-- or a material of these recipes: its name, color or price may show differently
-- now, or the search may find it.
function AllRecipes.ItemArrived(itemID)
	local isMaterial = false
	if materialNames and materialNames[itemID] == false then
		isMaterial = materialName(itemID) ~= nil
	end
	local same = byItem and byItem[itemID]
	if not same then return isMaterial end
	local name = ns.Format.ItemName(itemID)
	for _, row in ipairs(same) do
		if name then row.name = name end
		if not row.each and run and run.buy then priceRow(row, run.buy, run.keep) end
	end
	return true
end

-- Stops pricing and lets the recipes go: the window closed.
function AllRecipes.Release()
	run, rows, byItem, materialNames = nil, nil, nil, nil
end
