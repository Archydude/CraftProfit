-- Craft Profit: what one skill point costs with a recipe, on WoW Forever. The
-- materials, minus what the item is worth back, divided by the skill points a
-- craft gives on average at your skill: an orange recipe always gives one, a
-- yellow or green one less often the closer it is to grey, and a grey one never.
-- Where each recipe turns yellow and grey comes from Data\Forever.lua.
local _, ns = ...

local Skillups = {}
ns.Skillups = Skillups

local format = string.format

-- How each color reads, for the panel and tooltips.
local COLORS = {
	orange = "ffff8040",
	yellow = "ffffff00",
	green = "ff40c040",
	grey = "ff808080",
}

-- The game's own color for a recipe, from its difficulty, or nil.
local function gameColor(recipeID)
	local difficulty = Enum.TradeskillRelativeDifficulty
	local info = difficulty and C_TradeSkillUI.GetRecipeInfo(recipeID)
	local relative = info and info.relativeDifficulty
	if relative == nil then return end
	if relative == difficulty.Optimal then return "orange" end
	if relative == difficulty.Medium then return "yellow" end
	if relative == difficulty.Easy then return "green" end
	if relative == difficulty.Trivial then return "grey" end
end

-- This character's skill in the profession the recipe belongs to, racial bonus
-- included (it moves the colors too), or nil.
local function skillFor(recipeID)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	if not (info and (info.skillLevel or 0) > 0) then info = C_TradeSkillUI.GetBaseProfessionInfo() end
	if info and (info.skillLevel or 0) > 0 then return info.skillLevel + (info.skillModifier or 0) end
end

-- The chance a craft of a recipe in the open profession window gives a skill-up,
-- its color ("orange", "yellow", "green", "grey") and the skill points a skill-up
-- gives. Nil off WoW Forever, or for recipes the data or the game can't place.
function Skillups.Chance(recipeID)
	local data = ns.SKILLUPS and ns.SKILLUPS[recipeID]
	if not data then return end
	local yellow, grey, points = data[1], data[2], data[3]
	local color = gameColor(recipeID)
	if color == "orange" then return 1, color, points end
	if color == "grey" then return 0, color, points end
	local skill = skillFor(recipeID)
	if not skill then return end
	if not color then
		color = (skill < yellow and "orange") or (skill >= grey and "grey")
			or (skill < (yellow + grey) / 2 and "yellow") or "green"
		if color == "orange" then return 1, color, points end
		if color == "grey" then return 0, color, points end
	end
	if grey <= yellow then return end
	local chance = math.min(math.max((grey - skill) / (grey - yellow), 0), 1)
	-- The game says it still gives skill-ups but the data's grey is behind it.
	if chance <= 0 then return end
	return chance, color, points
end

-- What one skill point costs with a recipe, in copper: `cost` is one craft's
-- materials, `sale` what one craft sells for after the auction house cut (nil
-- without a price), `itemID` and `made` the item and how many a craft makes on
-- average. Worth back is the sale or what a vendor pays, whichever is more.
-- 0 when crafting makes gold: a skill point is free then. (Dividing a gain by
-- the chance would make a recipe that rarely gives a skill-up look better.)
-- Returns the cost, chance, color and points, or nil when the recipe gives no
-- skill-ups (grey) or can't be placed.
function Skillups.Cost(recipeID, cost, sale, itemID, made)
	local chance, color, points = Skillups.Chance(recipeID)
	if not (chance and chance > 0) then return nil, chance, color end
	local vendor = itemID and select(11, C_Item.GetItemInfo(itemID))
	local back = math.max(sale or 0, (vendor or 0) * (made or 1))
	return math.max(cost - back, 0) / (chance * points), chance, color, points
end

-- A skill point's cost as shown: "Free" in green, the gold it costs in red, or
-- "-" without one.
function Skillups.CostText(cost)
	if not cost then return ns.Color("muted", "-") end
	if cost <= 0 then return ns.Color("good", "Free") end
	return ns.Color(ns.AmountColor(-cost), ns.Format.Money(-cost))
end

-- The chance alone, "63%", in the recipe's color; "-" for grey.
function Skillups.ChancePercent(chance, color)
	if not chance or chance <= 0 then return ns.Color("muted", "-") end
	return format("|c%s%.0f%%|r", COLORS[color] or COLORS.grey, chance * 100)
end

-- "yellow, 65% chance" in its color, for the panel and tooltips.
function Skillups.ChanceText(chance, color)
	local hex = COLORS[color] or COLORS.grey
	if color == "grey" or not chance then return format("|c%sgrey|r, no skill-ups", hex) end
	return format("|c%s%s|r, %.0f%% chance", hex, color, chance * 100)
end
