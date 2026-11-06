-- Craft Profit: the "Craft myself" crafting strategy, on WoW Forever. A material
-- one of this character's recipes makes costs what crafting it costs: its own
-- materials, priced the same way, down to the ones that have to be bought. The
-- shopping list buys those instead of the material. A profession's recipes count
-- once its Best crafts list has been opened (they come from its saved scan, see
-- Scans.lua), so Engineering can use Mining's smelting.
local _, ns = ...

local Chains = {}
ns.Chains = Chains

-- How many steps down the shopping list follows materials of materials. Real
-- chains are two or three deep; this stops a loop of recipes making each other.
local MAX_DEPTH = 6

-- itemID -> the recipe of this character's that makes it: { name, made = how
-- many one craft makes on average, madeAtLeast, materials = { { itemID, qty } ... } }.
-- Built when first needed, and again after a scan is saved.
local byItem

-- Materials whose crafting cost is being worked out right now: a recipe that
-- needs its own item (or one that leads back to it) is bought there instead.
local working = {}

-- Whether the crafting strategy is Craft myself (only on WoW Forever).
function Chains.Active()
	return not ns.QUALITY_CRAFTING and ns.db.craftStrategy == "craft"
end

-- Forgets the recipes: after a scan is saved, they're read again.
function Chains.Reset()
	byItem = nil
end

local function build()
	byItem = {}
	for _, entry in ipairs(ns.Scans.Mine()) do
		local output = entry.outputs[1]
		if output and output.itemID and not byItem[output.itemID] then
			local materials = {}
			for _, other in ipairs(entry.others) do
				-- Forever's slots take one item each.
				if other.itemIDs[1] then materials[#materials + 1] = { itemID = other.itemIDs[1], qty = other.qty } end
			end
			local schematic = entry.schematic
			local made = ((schematic.quantityMin or 1) + (schematic.quantityMax or 1)) / 2
			if #materials > 0 and made > 0 then
				byItem[output.itemID] = { name = entry.name, made = made,
					madeAtLeast = math.max(schematic.quantityMin or 1, 1), materials = materials }
			end
		end
	end
end

-- The recipe of this character's that makes an item (see byItem), or nil.
function Chains.RecipeFor(itemID)
	if not byItem then build() end
	return byItem[itemID]
end

-- What crafting one of an item costs, or nil when you don't know its recipe or
-- one of its materials has no price.
function Chains.CraftCost(itemID)
	local recipe = Chains.RecipeFor(itemID)
	if not recipe or working[itemID] then return end
	working[itemID] = true
	local total = 0
	for _, material in ipairs(recipe.materials) do
		-- Priced the same way, so its own crafted materials count at their cost too.
		local price = ns.Prices.Material(material.itemID)
		if not price then
			working[itemID] = nil
			return
		end
		total = total + price * material.qty
	end
	working[itemID] = nil
	return total / recipe.made
end

-- What to buy for `needs` ({ counts = itemIDs that fill it, itemID = the one to
-- buy, qty } ...), crafting what you can: { { itemID, qty } ... }. What you own
-- counts once, at every step down; a crafted material you're short of becomes
-- enough crafts of it for what's missing.
function Chains.Missing(needs, owned)
	local used, list, byID = {}, {}, {}
	local function buy(itemID, qty)
		local entry = byID[itemID]
		if not entry then
			entry = { itemID = itemID, qty = 0 }
			byID[itemID] = entry
			list[#list + 1] = entry
		end
		entry.qty = entry.qty + qty
	end
	local function need(counts, itemID, qty, depth)
		for _, id in ipairs(counts) do
			local take = math.min(math.max(owned(id) - (used[id] or 0), 0), qty)
			used[id] = (used[id] or 0) + take
			qty = qty - take
		end
		if qty <= 0 then return end
		local recipe = depth < MAX_DEPTH and Chains.RecipeFor(itemID)
		if not recipe then return buy(itemID, qty) end
		local crafts = math.ceil(qty / recipe.madeAtLeast)
		for _, material in ipairs(recipe.materials) do
			need({ material.itemID }, material.itemID, material.qty * crafts, depth + 1)
		end
	end
	for _, entry in ipairs(needs) do need(entry.counts, entry.itemID, entry.qty, 0) end
	return list
end
