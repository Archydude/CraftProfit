-- Craft Profit: multicraft and resourcefulness. Your chances come with each answer
-- the game gives about a craft. How big a proc is (how many extra items, how much
-- of a material comes back) the game doesn't say, so it's learned from your own
-- crafts, starting from base values. From those: what procs add to a craft on
-- average, and how lucky this session has been.
local _, ns = ...

local Procs = {}
ns.Procs = Procs

local format = string.format

-- Proc sizes used until enough of your own procs are counted. Estimates: your
-- own crafts replace them.
local BASE_EXTRA = 1.25 -- multicraft: extra items for each item a craft makes
local BASE_SAVED = 0.30 -- resourcefulness: the share of a material that comes back
-- Your own procs of a kind needed before they replace the base value.
local MIN_PROCS = 10

-- The names the game shows for the two stats: localized, with the English ones
-- as a last resort. (/craftprofit testprocs shows what the game sends.)
local STATS = {
	multicraft = { ITEM_MOD_MULTICRAFT_SHORT, ITEM_MOD_MULTICRAFT, "Multicraft" },
	resourcefulness = { ITEM_MOD_RESOURCEFULNESS_SHORT, ITEM_MOD_RESOURCEFULNESS, "Resourcefulness" },
}

-- CraftProfitDB.procSizes["Name-Realm"][professionID] = {
--   multicraft = { n, sum },      -- one per proc: extra items / items the craft made
--   resourcefulness = { n, sum }, -- one per material that came back: returned / used
-- }
local mine -- this character's table

function Procs.Init()
	CraftProfitDB.procSizes = CraftProfitDB.procSizes or {}
end

-- This character's counts for a profession, made when first needed.
local function sizesFor(professionID)
	if not mine then
		local name, realm = UnitFullName("player")
		realm = realm or GetNormalizedRealmName()
		if not (name and realm) then return end
		local key = name .. "-" .. realm
		CraftProfitDB.procSizes[key] = CraftProfitDB.procSizes[key] or {}
		mine = CraftProfitDB.procSizes[key]
	end
	local sizes = mine[professionID]
	if not sizes then
		sizes = { multicraft = { n = 0, sum = 0 }, resourcefulness = { n = 0, sum = 0 } }
		mine[professionID] = sizes
	end
	return sizes
end

-- The profession (Midnight Tailoring, say) a recipe belongs to, or nil.
function Procs.ProfessionOf(recipeID)
	local info = recipeID and C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	return info and info.professionID and info.professionID > 0 and info.professionID or nil
end

---------------------------------------------------------------------------
-- Chances and sizes
---------------------------------------------------------------------------

local function isStat(stat, kind)
	for _, name in pairs(STATS[kind]) do
		if stat.bonusStatName == name then return true end
	end
	return false
end

-- Your multicraft and resourcefulness chances (0 to 1) in the game's answer
-- about a craft ("operation info"). 0 when the craft can't proc it.
function Procs.Chances(info)
	local chances = { multicraft = 0, resourcefulness = 0 }
	for _, stat in ipairs(info and info.bonusStats or {}) do
		for kind in pairs(STATS) do
			if isStat(stat, kind) then chances[kind] = (stat.ratingPct or 0) / 100 end
		end
	end
	return chances
end

-- Your chances for a recipe without any particular materials (optional reagents
-- that add to them aren't counted). For crafts the crafting page didn't price.
function Procs.RecipeChances(recipeID)
	local ok, info = pcall(C_TradeSkillUI.GetCraftingOperationInfo, recipeID, {}, nil, false)
	return Procs.Chances(ok and info or nil)
end

-- Testing (/craftprofit testprocs): prints what the game says about the recipe on
-- the crafting page's stats, and the proc sizes in use. False with no recipe open.
function Procs.Explain()
	local ctx = ns.Blizzard.ActivePage() == "craft" and ns.Blizzard.CraftContext()
	if not ctx then return false end
	local function say(...) print("|cffffd100Craft Profit:|r " .. format(...)) end
	local info = ns.Blizzard.CraftInfo(ctx)
	for _, stat in ipairs(info and info.bonusStats or {}) do
		say("stat %q: value %s, %s%%, bonus %s%%", tostring(stat.bonusStatName), tostring(stat.bonusStatValue),
			tostring(stat.ratingPct), tostring(stat.bonusRatingPct))
	end
	local chances = Procs.Chances(info)
	local professionID = Procs.ProfessionOf(ctx.recipeInfo.recipeID)
	local extra, extraProcs = Procs.ExtraPerItem(professionID)
	local saved, savedProcs = Procs.SavedShare(professionID)
	say("Multicraft %.1f%%, %.2f extra per item (%s)", chances.multicraft * 100, extra, Procs.SourceText(extraProcs))
	say("Resourcefulness %.1f%%, saves %.0f%% (%s)", chances.resourcefulness * 100, saved * 100, Procs.SourceText(savedProcs))
	return true
end

-- How big a proc is on average, and how many of your own procs that's from (0:
-- the base value). `character` is another character's key ("Name-Realm"), for
-- its proc sizes; nil for this character. The same goes for the functions below.
local function average(professionID, kind, base, character)
	local sizes
	if character then
		sizes = (CraftProfitDB.procSizes[character] or {})[professionID]
	else
		sizes = professionID and sizesFor(professionID)
	end
	local count = sizes and sizes[kind]
	if count and count.n >= MIN_PROCS then return count.sum / count.n, count.n end
	return base, 0
end

-- Multicraft: extra items for each item a craft makes.
function Procs.ExtraPerItem(professionID, character)
	return average(professionID, "multicraft", BASE_EXTRA, character)
end

-- Resourcefulness: the share of a material that comes back.
function Procs.SavedShare(professionID, character)
	return average(professionID, "resourcefulness", BASE_SAVED, character)
end

-- What procs add to one craft on average: {
--   multicraft, resourcefulness = gold each adds, total,
--   chances, extraPerItem, savedShare, multicraftProcs, resourcefulnessProcs (your
--   procs the sizes come from; 0 for base values),
-- }. `sale` is what one craft's items sell for after the AH cut (nil without a
-- price), `basicCost` what its basic materials cost (the ones resourcefulness saves).
function Procs.Expected(professionID, chances, sale, basicCost, character)
	local expected = { chances = chances }
	expected.extraPerItem, expected.multicraftProcs = Procs.ExtraPerItem(professionID, character)
	expected.savedShare, expected.resourcefulnessProcs = Procs.SavedShare(professionID, character)
	expected.multicraft = sale and chances.multicraft * expected.extraPerItem * sale or 0
	expected.resourcefulness = chances.resourcefulness * expected.savedShare * (basicCost or 0)
	expected.total = expected.multicraft + expected.resourcefulness
	return expected
end

-- "Based on 47 of your procs" or "Base value until you've had 10 procs".
function Procs.SourceText(procs)
	if procs > 0 then return format("from %d of your procs", procs) end
	return format("base value until you've had %d procs", MIN_PROCS)
end

---------------------------------------------------------------------------
-- Learning from your crafts
---------------------------------------------------------------------------

local function add(count, value)
	count.n = count.n + 1
	count.sum = count.sum + value
end

-- Learns from a craft's result (the game's craft result `data`). `used` is
-- itemID -> how many of it the craft took.
function Procs.Record(professionID, data, used)
	local sizes = professionID and sizesFor(professionID)
	if not sizes then return end
	local extra = data.multicraft or 0
	-- The quantity includes the multicraft extras.
	local made = (data.quantity or 0) - extra
	if extra > 0 and made > 0 then add(sizes.multicraft, extra / made) end
	for _, returned in ipairs(data.resourcesReturned or {}) do
		local itemID = returned.reagent and returned.reagent.itemID
		local qty = itemID and used[itemID]
		if qty and qty > 0 and (returned.quantity or 0) > 0 then
			add(sizes.resourcefulness, math.min(returned.quantity / qty, 1))
		end
	end
end

---------------------------------------------------------------------------
-- Luck: what procs made this session, against what they should have
---------------------------------------------------------------------------

-- Adds one craft: the gold its procs were expected to add, and what they did.
function Procs.AddToSession(expected, actual)
	local session = ns.db.session
	session.expectedBonus = (session.expectedBonus or 0) + (expected or 0)
	session.actualBonus = (session.actualBonus or 0) + (actual or 0)
end

-- This session's luck: how far procs made more (or less) than expected, as a
-- share (0.14 is 14% more), then what they made and what was expected. Nil until
-- a craft this session could proc.
function Procs.Luck()
	local session = ns.db.session
	local expected = session.expectedBonus or 0
	if expected <= 0 then return end
	local actual = session.actualBonus or 0
	return actual / expected - 1, actual, expected
end

-- "Luck +14%" in green, or "Luck -8%" in red, or nil.
function Procs.LuckText()
	local luck = Procs.Luck()
	if not luck then return end
	local percent = math.floor(luck * 100 + 0.5)
	return ns.Color(ns.AmountColor(percent), format("Luck %s%d%%", percent > 0 and "+" or "", percent))
end

-- The luck meter's lines for a tooltip.
function Procs.AddLuckLines(tip)
	local luck, actual, expected = Procs.Luck()
	if not luck then return end
	tip:AddLine(" ")
	tip:AddDoubleLine("Procs made", ns.Format.Money(actual), 1, 1, 1, 1, 1, 1)
	tip:AddDoubleLine("Procs make on average", ns.Format.Money(expected), 1, 1, 1, 1, 1, 1)
	tip:AddLine("What multicraft and resourcefulness made on these crafts, against what your chances and proc "
		.. "sizes say they make on average.", 0.53, 0.53, 0.53, true)
end
