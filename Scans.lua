-- Craft Profit: what each character's Best crafts scan found, for the list's
-- All characters view. The game only says how a craft turns out for the character
-- whose profession window is open, so each finished scan is saved, and the other
-- characters' recipes are priced from that. Prices stay live; only the ranks and
-- proc chances are as old as the scan.
--
-- A recipe can have dozens of mixes of qualities, and a saved file only loads up
-- to a limit of unique values, so each recipe is saved as one string.
local _, ns = ...

local Scans = {}
ns.Scans = Scans

local format = string.format

-- Scans saved in another format are ignored until that character scans again.
local FORMAT = 1

-- CraftProfitDB.characters["Name-Realm"].scans[professionID] = {
--   format, time = when it was scanned, name = the profession ("Midnight Blacksmithing"),
--   recipes = { packed recipe ... } (see packRecipe),
-- }
-- A saved scan's entries once unpacked, until it's replaced: saved scan -> { entry ... }.
local unpacked = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Packing
---------------------------------------------------------------------------

-- `text` cut at each `separator` (a pattern), empty parts included.
local function split(text, separator)
	local parts = {}
	for part in (text .. separator:gsub("%%", "")):gmatch("(.-)" .. separator) do parts[#parts + 1] = part end
	return parts
end

-- Which option of a slot the itemID is.
local function optionIndex(slot, itemID)
	for index, option in ipairs(slot.options) do
		if option.itemID == itemID then return index end
	end
	return 1
end

-- One recipe (see BestCrafts' scanRecipe) as five lines:
--   recipeID, name, icon, maxRank, qtyMin, qtyMax, multicraft, resourcefulness
--   for each rank that makes something: rank, itemID, link
--   for each slot in qualities: "slotIndex,qty,itemID,itemID..."
--   for each other slot: "slotIndex,qty,basic,itemID,itemID..."
--   for each mix: "quality,concentration,option.option...", an option for each slot in qualities
-- Fields are split by tabs.
local function packRecipe(entry)
	local chances = entry.chances or {}
	local schematic = entry.schematic
	local head = table.concat({ entry.recipeID, entry.name or "", tostring(entry.icon or ""), entry.maxRank,
		schematic.quantityMin or 1, schematic.quantityMax or 1,
		format("%.4f", chances.multicraft or 0), format("%.4f", chances.resourcefulness or 0) }, "\t")

	local outputs = {}
	for rank = 1, entry.maxRank do
		local output = entry.outputs[rank]
		if output then
			outputs[#outputs + 1] = table.concat({ rank, output.itemID, output.link }, "\t")
		end
	end

	local slots = {}
	for i, slot in ipairs(entry.slots) do
		local parts = { slot.slotIndex, slot.qty }
		for _, option in ipairs(slot.options) do parts[#parts + 1] = option.itemID end
		slots[i] = table.concat(parts, ",")
	end

	local others = {}
	for i, other in ipairs(entry.others) do
		local parts = { other.slotIndex, other.qty, other.basic and 1 or 0 }
		for _, itemID in ipairs(other.itemIDs) do parts[#parts + 1] = itemID end
		others[i] = table.concat(parts, ",")
	end

	local options = {}
	for i, option in ipairs(entry.options) do
		local mix = {}
		for j, slot in ipairs(entry.slots) do mix[j] = optionIndex(slot, option.picks[slot.slotIndex]) end
		options[i] = format("%s,%s,%s", tostring(option.quality or ""), tostring(option.concentration or ""),
			table.concat(mix, "."))
	end

	return table.concat({ head, table.concat(outputs, "\t"), table.concat(slots, "\t"),
		table.concat(others, "\t"), table.concat(options, "\t") }, "\n")
end

-- "1,2,3" as numbers.
local function numbers(text)
	local list = split(text, ",")
	for i, value in ipairs(list) do list[i] = tonumber(value) end
	return list
end

-- A recipe back as an entry, as BestCrafts' scanRecipe makes them, or nil. Its
-- schematic only has what pricing and shopping read: the slots you fill, with
-- empty ones between them, since slots are found by their number.
local function unpackRecipe(text, professionID, character, scanned)
	local lines = split(text, "\n")
	if #lines ~= 5 then return end
	local head = split(lines[1], "\t")
	local recipeID, maxRank = tonumber(head[1]), tonumber(head[4])
	if not (recipeID and maxRank) then return end
	local entry = {
		recipeID = recipeID, name = head[2], icon = tonumber(head[3]) or head[3], maxRank = maxRank,
		professionID = professionID, character = character, scanned = scanned,
		chances = { multicraft = tonumber(head[7]) or 0, resourcefulness = tonumber(head[8]) or 0 },
		outputs = {}, slots = {}, others = {}, options = {},
	}

	local fields = split(lines[2], "\t")
	for i = 1, #fields - 2, 3 do
		entry.outputs[tonumber(fields[i])] = { itemID = tonumber(fields[i + 1]), link = fields[i + 2] }
	end

	local slotSchematics, slotCount = {}, 0
	local function addSlot(slotIndex, qty, itemIDs)
		local reagents = {}
		for i, itemID in ipairs(itemIDs) do reagents[i] = { itemID = itemID } end
		slotSchematics[slotIndex] = { required = true, quantityRequired = qty, reagents = reagents }
		slotCount = math.max(slotCount, slotIndex)
	end

	for _, packed in ipairs(split(lines[3], "\t")) do
		if packed ~= "" then
			local parts = numbers(packed)
			local options, itemIDs = {}, {}
			for i = 3, #parts do
				options[#options + 1] = { itemID = parts[i] }
				itemIDs[#itemIDs + 1] = parts[i]
			end
			entry.slots[#entry.slots + 1] = { slotIndex = parts[1], qty = parts[2], options = options }
			addSlot(parts[1], parts[2], itemIDs)
		end
	end

	for _, packed in ipairs(split(lines[4], "\t")) do
		if packed ~= "" then
			local parts = numbers(packed)
			local itemIDs = {}
			for i = 4, #parts do itemIDs[#itemIDs + 1] = parts[i] end
			entry.others[#entry.others + 1] = { slotIndex = parts[1], qty = parts[2], itemIDs = itemIDs, basic = parts[3] == 1 }
			addSlot(parts[1], parts[2], itemIDs)
		end
	end

	for slotIndex = 1, slotCount do
		slotSchematics[slotIndex] = slotSchematics[slotIndex] or { required = false, reagents = {} }
	end
	entry.schematic = { quantityMin = tonumber(head[5]) or 1, quantityMax = tonumber(head[6]) or 1,
		reagentSlotSchematics = slotSchematics }

	for _, packed in ipairs(split(lines[5], "\t")) do
		local quality, concentration, mix = packed:match("^([%d.]*),([%d.]*),(.*)$")
		if quality then
			local picks = {}
			local chosen = mix ~= "" and split(mix, "%.") or {}
			for i, slot in ipairs(entry.slots) do
				local option = slot.options[tonumber(chosen[i])]
				picks[slot.slotIndex] = option and option.itemID
			end
			entry.options[#entry.options + 1] = { picks = picks, quality = tonumber(quality),
				concentration = tonumber(concentration) }
		end
	end
	if #entry.options == 0 then return end
	return entry
end

---------------------------------------------------------------------------
-- Saving and reading
---------------------------------------------------------------------------

-- Saves a finished scan (see BestCrafts.Scan) as this character's.
function Scans.Save(run)
	local me = ns.Ranks.Me()
	if not me or #run.recipes == 0 then return end
	local recipes = {}
	for i, entry in ipairs(run.recipes) do recipes[i] = packRecipe(entry) end
	me.scans = me.scans or {}
	me.scans[run.professionID] = { format = FORMAT, time = time(), name = run.name, recipes = recipes }
end

local function entriesOf(saved, professionID, character)
	local entries = unpacked[saved]
	if not entries then
		entries = {}
		for _, text in ipairs(saved.recipes) do
			entries[#entries + 1] = unpackRecipe(text, professionID, character, saved.time)
		end
		unpacked[saved] = entries
	end
	return entries
end

-- Every saved recipe of every character, except this character's `shownProfession`,
-- which the list has fresh from the game.
function Scans.Entries(shownProfession)
	local list = {}
	local _, myKey = ns.Ranks.Me()
	for key, character in pairs(CraftProfitDB.characters) do
		for professionID, saved in pairs(character.scans or {}) do
			if saved.format == FORMAT and not (key == myKey and professionID == shownProfession) then
				for _, entry in ipairs(entriesOf(saved, professionID, key)) do list[#list + 1] = entry end
			end
		end
	end
	return list
end
