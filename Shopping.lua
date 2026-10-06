-- Craft Profit: the missing materials button. Sends what you're short of for a
-- craft to an Auctionator shopping list, or tracks the recipe in Blizzard's
-- objective tracker. Which one is an option.
local ADDON_NAME, ns = ...

local Shopping = {}
ns.Shopping = Shopping

local format = string.format

-- Bind types that can be bought on the auction house.
local TRADEABLE = {
	[Enum.ItemBind.None] = true,
	[Enum.ItemBind.OnEquip] = true,
	[Enum.ItemBind.OnUse] = true,
}

local function say(text)
	print(ns.Color("heading", "Craft Profit:") .. " " .. text)
end

local function auctionatorAPI()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.CreateShoppingList and api.ConvertToSearchString then return api end
end

-- Auctionator's API can change or throw, so every call into it is guarded.
local function call(fn, ...)
	if not fn then return end
	local ok, result = pcall(fn, ADDON_NAME, ...)
	if ok then return result end
end

-- Where the button sends missing materials: "auctionator", "blizzard", or nil
-- when it's turned off or Auctionator was picked but isn't loaded.
function Shopping.Target()
	local choice = ns.db.missingTarget
	if choice == "off" then return end
	if choice == "blizzard" then return "blizzard" end
	if auctionatorAPI() then return "auctionator" end
	if choice == "auto" then return "blizzard" end
end

---------------------------------------------------------------------------
-- Blizzard's recipe tracker
---------------------------------------------------------------------------

function Shopping.IsTracked(model)
	local recipe = model.recipe
	return recipe and C_TradeSkillUI.IsRecipeTracked(recipe.recipeID, recipe.isRecraft) or false
end

-- Tracks the recipe, or stops tracking it if it already is.
local function toggleTracked(model)
	local recipe = model.recipe
	local name = C_TradeSkillUI.GetRecipeInfo(recipe.recipeID)
	name = name and name.name or model.title
	local track = not Shopping.IsTracked(model)
	C_TradeSkillUI.SetRecipeTracked(recipe.recipeID, track, recipe.isRecraft)
	if not track then
		say(format("Stopped tracking %s.", name))
	elseif Shopping.IsTracked(model) then
		say(format("Tracking %s. Its materials are in your objective tracker.", name))
	else
		say(ns.Color("warning", format("Couldn't track %s. Try untracking another recipe.", name)))
	end
	ns.Panel.Refresh()
end

---------------------------------------------------------------------------
-- Auctionator shopping list
---------------------------------------------------------------------------

-- One list line per material and quality, so adding the same one again adds up
-- the amount.
local function termKey(term)
	return format("%s|%s|%s", term.searchString:lower(), tostring(term.tier), tostring(term.isExact))
end

-- Adds { { name, tier, qty } ... } to the shopping list, keeping what's on it.
-- Returns whether it worked.
local function addToList(api, items)
	-- The API only makes whole lists, so read the old one and rebuild it.
	local lines, byKey = {}, {}
	for _, searchString in ipairs(call(api.GetShoppingListItems, ns.SHOPPING_LIST) or {}) do
		local line = { text = searchString }
		local term = call(api.ConvertFromSearchString, searchString)
		if type(term) == "table" and type(term.searchString) == "string" then
			line.term = term
			byKey[termKey(term)] = line
		end
		lines[#lines + 1] = line
	end

	for _, item in ipairs(items) do
		local term = { searchString = item.name, isExact = true, tier = item.tier, quantity = item.qty }
		local line = byKey[termKey(term)]
		if line then
			line.term.quantity = (line.term.quantity or 0) + item.qty
			line.text = nil -- rebuilt below with the new amount
		else
			line = { term = term }
			byKey[termKey(term)] = line
			lines[#lines + 1] = line
		end
	end

	local searchStrings = {}
	for _, line in ipairs(lines) do
		local text = line.text or call(api.ConvertToSearchString, line.term)
		if not text then return false end
		searchStrings[#searchStrings + 1] = text
	end
	local ok = pcall(api.CreateShoppingList, ADDON_NAME, ns.SHOPPING_LIST, searchStrings)
	return ok
end

-- "5x [Item], 2x [Item]" for the chat messages.
local function itemList(items)
	local parts = {}
	for _, item in ipairs(items) do parts[#parts + 1] = format("%dx %s", item.qty, item.link) end
	return table.concat(parts, ", ")
end

-- Sorts the missing materials into auction house, vendor and can't-buy, then
-- adds the auction house ones to the list. Item info has to be loaded first.
local function sendToAuctionator(api, missing)
	local container = ContinuableContainer:Create()
	for _, material in ipairs(missing) do
		container:AddContinuable(Item:CreateFromItemID(material.itemID))
	end
	container:ContinueOnLoad(function()
		local auction, vendor, bound = {}, {}, {}
		for _, material in ipairs(missing) do
			local name, link, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(material.itemID)
			local tier = C_TradeSkillUI.GetItemReagentQualityByItemInfo(material.itemID)
			local item = {
				name = name, link = link or name, qty = material.qty,
				tier = tier and tier > 0 and tier or nil,
			}
			if not name then
				-- Never loaded; nothing to search for.
			elseif ns.Prices.Vendor(material.itemID) then
				vendor[#vendor + 1] = item
			elseif bindType and not TRADEABLE[bindType] then
				bound[#bound + 1] = item
			else
				auction[#auction + 1] = item
			end
		end

		if #auction > 0 then
			if addToList(api, auction) then
				say(format("Added to Auctionator's \"%s\" shopping list: %s.", ns.SHOPPING_LIST, itemList(auction)))
			else
				say(ns.Color("warning", "Auctionator couldn't update the shopping list."))
			end
		end
		if #vendor > 0 then say("Buy from a vendor: " .. itemList(vendor) .. ".") end
		if #bound > 0 then say("Not on the auction house (soulbound): " .. itemList(bound) .. ".") end
	end)
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------

-- What the panel's button does for this model.
function Shopping.Send(model)
	local target = Shopping.Target()
	if target == "blizzard" then
		toggleTracked(model)
	elseif target == "auctionator" and #model.missing > 0 then
		sendToAuctionator(auctionatorAPI(), model.missing)
	end
end
