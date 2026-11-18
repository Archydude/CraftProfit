-- Craft Profit: every profession's recipes on WoW Forever, priced as if you
-- bought the materials and sold what a craft makes, whether or not a character of
-- yours knows the recipe. An enchant makes nothing to sell: it has only what its
-- materials cost. For the All recipes window (AllRecipesWindow.lua). The
-- recipes come from Data\ForeverRecipes.lua; they're unpacked and priced a few at
-- a time while the window is open, and let go when it closes.
local _, ns = ...
if ns.QUALITY_CRAFTING then return end

local AllRecipes = {}
ns.AllRecipes = AllRecipes

-- Pricing works this long each frame, then waits for the next one.
local FRAME_BUDGET_MS = 4

-- Every recipe while the window is open: {
--   recipeID, itemID, link = the item as price addons are asked about it (an
--   enchant, which makes no item, has neither, and enchant = true),
--   made = how many one craft makes (the average, for recipes that make a range),
--   professionID, profession = its name, materials = { { itemID, qty } ... },
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

-- A profession's name, in the game's language when the data has it.
function AllRecipes.ProfessionName(professionID)
	local names = ns.RECIPE_PROFESSION_NAMES[GetLocale()]
	return names and names[professionID] or ns.RECIPE_PROFESSIONS[professionID]
end

-- The professions with recipes here: { { id, name } ... }, by name.
function AllRecipes.Professions()
	local list = {}
	for professionID in pairs(ns.ALL_RECIPES) do
		list[#list + 1] = { id = professionID, name = AllRecipes.ProfessionName(professionID) }
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
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

-- Unpacks every recipe. They only count once all are there: a pricing dropped
-- halfway leaves nothing behind.
local function unpackAll()
	local list, items = {}, {}
	for professionID, packed in pairs(ns.ALL_RECIPES) do
		local profession = AllRecipes.ProfessionName(professionID)
		for _, text in ipairs(packed) do
			local row = unpackRecipe(text, professionID, profession)
			if row then
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
			pauseIfDue()
		end
	end
	rows, byItem, materialNames = list, items, {}
end

-- Fills in what a recipe's materials cost at today's prices: cost and unpriced.
-- `buy` is what buying a material costs (see Prices.Buy).
local function priceMaterials(row, buy)
	local cost, unpriced = 0, 0
	for _, material in ipairs(row.materials) do
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
	if not rows then unpackAll() end
	this.total = #rows
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
		this.done = index
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
