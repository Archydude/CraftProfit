-- Craft Profit: every profession's recipes on WoW Forever, priced as if you
-- bought the materials and sold what a craft makes, whether or not a character of
-- yours knows the recipe. For the All recipes window (AllRecipesWindow.lua). The
-- recipes come from Data\ForeverRecipes.lua; they're unpacked and priced a few at
-- a time while the window is open, and let go when it closes.
local _, ns = ...
if ns.QUALITY_CRAFTING then return end

local AllRecipes = {}
ns.AllRecipes = AllRecipes

-- Pricing works this long each frame, then waits for the next one.
local FRAME_BUDGET_MS = 4

-- Every recipe while the window is open: {
--   recipeID, itemID, link = the item as price addons are asked about it,
--   made = how many one craft makes (the average, for recipes that make a range),
--   professionID, profession = its name, materials = { { itemID, qty } ... },
--   recipeName, name = the item's (the recipe's until the game has loaded it),
--   -- once priced:
--   each = what one item sells for (nil without a price), gross = what a craft's
--   items sell for after the auction house cut, cost = the materials (nil when one
--   has no price), unpriced = how many of them have none, net = gross - cost,
--   saleRate and soldPerDay = TSM's (nil without),
-- }
local rows
local byItem -- itemID -> the rows that make it (a few items have two recipes)
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

-- One line of the data ("recipe:item:made:material.count,...") as a row, or nil.
local function unpackRecipe(text, professionID, profession)
	local recipeID, itemID, made, packed = text:match("^(%d+):(%d+):([%d.]+):(.+)$")
	if not recipeID then return end
	local materials = {}
	for material, qty in packed:gmatch("(%d+)%.(%d+)") do
		materials[#materials + 1] = { itemID = tonumber(material), qty = tonumber(qty) }
	end
	recipeID, itemID = tonumber(recipeID), tonumber(itemID)
	local recipeName = C_Spell.GetSpellName(recipeID)
	return { recipeID = recipeID, itemID = itemID, link = "item:" .. itemID, made = tonumber(made),
		professionID = professionID, profession = profession, materials = materials,
		recipeName = recipeName, name = recipeName or "?" }
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
				local same = items[row.itemID]
				if not same then
					same = {}
					items[row.itemID] = same
				end
				same[#same + 1] = row
			end
			pauseIfDue()
		end
	end
	rows, byItem = list, items
end

-- Fills in what a recipe costs and makes at today's prices. `buy` is what buying
-- a material costs (see Prices.Buy), `keep` the share of a sale the auction house
-- leaves you.
local function priceRow(row, buy, keep)
	-- The item's own name, once the game has loaded it. Some prices need the item
	-- loaded too, so it's priced again then (see AllRecipes.ItemArrived).
	local name = ns.Format.ItemName(row.itemID)
	if name then row.name = name else C_Item.RequestLoadItemDataByID(row.itemID) end
	row.each = ns.Prices.Sale(row.link, row.itemID)
	row.gross, row.cost, row.net, row.saleRate, row.soldPerDay = nil, nil, nil, nil, nil
	-- Without a price the window leaves it out, so there's nothing more to ask.
	if not row.each then return end
	local cost, unpriced = 0, 0
	for _, material in ipairs(row.materials) do
		local price = buy(material.itemID)
		if price then cost = cost + price * material.qty else unpriced = unpriced + 1 end
	end
	row.unpriced = unpriced
	row.cost = unpriced == 0 and cost or nil
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
-- True when it's an item of these recipes: its name, color or price may show
-- differently now.
function AllRecipes.ItemArrived(itemID)
	local same = byItem and byItem[itemID]
	if not same then return false end
	local name = ns.Format.ItemName(itemID)
	for _, row in ipairs(same) do
		if name then row.name = name end
		if not row.each and run and run.buy then priceRow(row, run.buy, run.keep) end
	end
	return true
end

-- Stops pricing and lets the recipes go: the window closed.
function AllRecipes.Release()
	run, rows, byItem = nil, nil, nil
end
