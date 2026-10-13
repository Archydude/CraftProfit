-- Craft Profit: the shopping list button. Adds what you're short of, for one or
-- more crafts, to an Auctionator shopping list, or gives you a TSM search for it.
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

local function tsmLoaded()
	return TSM_API and TSM_API.GetCustomPriceValue and true or false
end

-- Whether both Auctionator and TSM are loaded, so there's a choice between them.
function Shopping.HasBoth()
	return auctionatorAPI() ~= nil and tsmLoaded()
end

-- Where lists of missing materials go: "auctionator" (its shopping list), "tsm"
-- (a search to copy into TSM's Shopping tab), or nil when that's turned off or
-- neither is loaded. With both, the "Shop with" choice decides.
function Shopping.ListTarget()
	if not ns.db.shoppingButton then return end
	local auctionator, tsm = auctionatorAPI() ~= nil, tsmLoaded()
	if auctionator and tsm then return ns.db.listAddon == "tsm" and "tsm" or "auctionator" end
	if auctionator then return "auctionator" end
	if tsm then return "tsm" end
end

-- "Shop with" radios at the bottom of a menu, when both addons are loaded. The
-- menu redraws for the new choice.
function Shopping.AddShopWithChoice(root)
	if not Shopping.HasBoth() then return end
	root:CreateDivider()
	root:CreateTitle("Shop with")
	local function isChosen(key) return Shopping.ListTarget() == key end
	local function choose(key)
		ns.db.listAddon = key
		ns.Panel.Refresh()
		return MenuResponse and MenuResponse.Refresh
	end
	for _, choice in ipairs(ns.LIST_ADDON_CHOICES) do
		root:CreateRadio(choice[2], isChosen, choose, choice[1])
	end
end

---------------------------------------------------------------------------
-- Auctionator shopping list
---------------------------------------------------------------------------

-- The profession whose window is open ("Blacksmithing"), or nil.
local function openProfession()
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then return end
	local info = C_TradeSkillUI.GetBaseProfessionInfo()
	local name = info and info.professionName
	if name and name ~= "" then return name end
end

-- The list materials go to: "Craft Profit", or one per character and/or per
-- profession, as the options say ("Craft Profit - Snir - Blacksmithing").
-- `profession` defaults to the open one; with none, the profession is left out.
function Shopping.ListName(profession)
	local parts = { ns.SHOPPING_LIST }
	if ns.db.listPerCharacter then parts[#parts + 1] = UnitName("player") end
	if ns.db.listPerProfession then parts[#parts + 1] = profession or openProfession() end
	return table.concat(parts, " - ")
end

-- The lists Clear empties: the current one, or with one list per profession and
-- no profession window open, the lists of all this character's professions.
local function listsToClear()
	local names = {}
	if ns.db.listPerProfession and not openProfession() then
		for _, index in pairs({ GetProfessions() }) do
			local name = GetProfessionInfo(index)
			if name then names[#names + 1] = Shopping.ListName(name) end
		end
	end
	if #names == 0 then names[1] = Shopping.ListName() end
	return names
end

-- One list line per material and quality, so adding the same one again adds up
-- the amount.
local function termKey(term)
	return format("%s|%s|%s", term.searchString:lower(), tostring(term.tier), tostring(term.isExact))
end

-- Adds { { name, tier, qty } ... } to the shopping list, keeping what's on it.
-- Returns whether it worked.
local function addToList(api, items, listName)
	-- The API only makes whole lists, so read the old one and rebuild it.
	local lines, byKey = {}, {}
	for _, searchString in ipairs(call(api.GetShoppingListItems, listName) or {}) do
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
	local ok = pcall(api.CreateShoppingList, ADDON_NAME, listName, searchStrings)
	return ok
end

-- Takes { { name, tier, qty, link } ... } off the shopping list, lowering amounts
-- and dropping lines that reach zero. Returns what came off ({ { link, qty } }),
-- or nil when Auctionator couldn't update the list.
local function removeFromList(api, items, listName)
	local lines, byKey = {}, {}
	for _, searchString in ipairs(call(api.GetShoppingListItems, listName) or {}) do
		local line = { text = searchString }
		local term = call(api.ConvertFromSearchString, searchString)
		if type(term) == "table" and type(term.searchString) == "string" then
			line.term = term
			byKey[termKey(term)] = line
		end
		lines[#lines + 1] = line
	end

	local removed = {}
	for _, item in ipairs(items) do
		local line = byKey[termKey({ searchString = item.name, isExact = true, tier = item.tier })]
		if line and not line.gone then
			local have = line.term.quantity
			if not have or have <= item.qty then
				line.gone = true
				removed[#removed + 1] = { link = item.link, qty = have or item.qty }
			else
				line.term.quantity = have - item.qty
				line.text = nil -- rebuilt below with the new amount
				removed[#removed + 1] = { link = item.link, qty = item.qty }
			end
		end
	end
	if #removed == 0 then return removed end

	local searchStrings = {}
	for _, line in ipairs(lines) do
		if not line.gone then
			local text = line.text or call(api.ConvertToSearchString, line.term)
			if not text then return end
			searchStrings[#searchStrings + 1] = text
		end
	end
	if not pcall(api.CreateShoppingList, ADDON_NAME, listName, searchStrings) then return end
	return removed
end

-- "5x [Item], 2x [Item]" for the chat messages.
local function itemList(items)
	local parts = {}
	for _, item in ipairs(items) do parts[#parts + 1] = format("%dx %s", item.qty, item.link) end
	return table.concat(parts, ", ")
end

-- Sorts the missing materials into auction house, vendor and can't-buy once their
-- item info has loaded, then calls andThen(auction, vendor, bound), each a list of
-- { itemID, name, link, tier, qty }.
local function sortMissing(missing, andThen)
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
				itemID = material.itemID, name = name, link = link or name, qty = material.qty,
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
		andThen(auction, vendor, bound)
	end)
end

-- The materials no auction house search covers, listed in chat.
local function sayUnbuyable(vendor, bound)
	if #vendor > 0 then say("Buy from a vendor: " .. itemList(vendor) .. ".") end
	if #bound > 0 then say("Not on the auction house (soulbound): " .. itemList(bound) .. ".") end
end

-- Adds the auction house materials to the list.
-- `forText` says what they're for in chat: "5 crafts", "3 patron orders".
local function sendToAuctionator(api, missing, forText)
	-- Picked now: the window may close before the items load.
	local listName = Shopping.ListName()
	sortMissing(missing, function(auction, vendor, bound)
		if #auction > 0 then
			if addToList(api, auction, listName) then
				say(format("Added to Auctionator's \"%s\" shopping list, for %s: %s.",
					listName, forText, itemList(auction)))
			else
				say(ns.Color("warning", "Auctionator couldn't update the shopping list."))
			end
		end
		sayUnbuyable(vendor, bound)
	end)
end

-- The popup with a TSM search to copy. It can't be edited, so a stray key
-- doesn't break it.
StaticPopupDialogs.CRAFTPROFIT_TSM_SEARCH = {
	text = "TSM search for %s\n\nPress Ctrl+C to copy it, then paste it into the search box on TSM's Shopping tab.",
	button1 = CLOSE,
	hasEditBox = true,
	editBoxWidth = 320,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnShow = function(self, data)
		local editBox = self.GetEditBox and self:GetEditBox() or self.editBox
		editBox:SetMaxLetters(0)
		editBox:SetText(data or self.data or "")
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	EditBoxOnTextChanged = function(editBox, data)
		local search = data or editBox:GetParent().data
		if search and editBox:GetText() ~= search then
			editBox:SetText(search)
			editBox:HighlightText()
		end
	end,
	EditBoxOnEnterPressed = function(editBox) editBox:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
}

-- Shows a TSM Shopping search for the auction house materials. Each rank of a
-- material is its own item, so "i:<itemID>" buys exactly that rank, and "/x<qty>"
-- stops at the amount needed; ";" puts several in one search.
local function copyTSMSearch(missing, forText)
	sortMissing(missing, function(auction, vendor, bound)
		if #auction > 0 then
			local parts = {}
			for _, item in ipairs(auction) do parts[#parts + 1] = format("i:%d/x%d", item.itemID, item.qty) end
			say(format("TSM search for %s: %s.", forText, itemList(auction)))
			StaticPopup_Show("CRAFTPROFIT_TSM_SEARCH", forText, nil, table.concat(parts, ";"))
		end
		sayUnbuyable(vendor, bound)
	end)
end

-- Empties the shopping list (see listsToClear). Auctionator's API can't delete a
-- list, so an empty one is left behind; the next add fills it again.
function Shopping.Clear()
	local api = auctionatorAPI()
	if not api then
		say(ns.Color("warning", "Auctionator is not loaded."))
		return
	end
	local names, cleared, failed = listsToClear(), {}, false
	for _, name in ipairs(names) do
		local items = call(api.GetShoppingListItems, name)
		if items and #items > 0 then
			if pcall(api.CreateShoppingList, ADDON_NAME, name, {}) then
				cleared[#cleared + 1] = format("\"%s\"", name)
			else
				failed = true
			end
		end
	end
	if failed then say(ns.Color("warning", "Auctionator couldn't clear the shopping list.")) end
	if #cleared > 0 then
		say(format("Cleared Auctionator's %s shopping list%s.", table.concat(cleared, ", "), #cleared > 1 and "s" or ""))
	elseif not failed then
		say(#names > 1 and "Your Craft Profit shopping lists are already empty."
			or format("Auctionator's \"%s\" shopping list is already empty.", names[1]))
	end
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------

-- Craft counts the menu always offers.
local PRESET_CRAFTS = { 1, 5, 10 }
local MAX_CRAFTS = 999

-- The last count typed into "Other amount...", offered in the menu until you
-- log out or /reload.
local customCrafts

-- "1 craft", "5 crafts".
function Shopping.CraftsText(crafts)
	return format("%d craft%s", crafts, crafts == 1 and "" or "s")
end

-- How many items a missing list adds up to.
function Shopping.Total(missing)
	local total = 0
	for _, material in ipairs(missing) do total = total + material.qty end
	return total
end

-- Whether Ctrl-click on the button clears the shopping list: when the button
-- uses Auctionator at all.
function Shopping.CanClear()
	return Shopping.ListTarget() == "auctionator"
end

Shopping.Say = say

-- Adds missing materials ({ { itemID, qty } ... }) to the shopping list.
-- `forText` says what they're for in chat: "5 crafts", "3 patron orders".
function Shopping.AddMissing(missing, forText)
	if #missing == 0 then
		say(format("Nothing missing for %s.", forText))
		return
	end
	local target = Shopping.ListTarget()
	if target == "tsm" then
		copyTSMSearch(missing, forText)
	elseif target == "auctionator" then
		sendToAuctionator(auctionatorAPI(), missing, forText)
	else
		say(ns.Color("warning", "Install Auctionator or TSM to shop for materials."))
	end
end

-- Takes materials ({ { itemID, qty } ... }) back off the shopping list.
-- `forText` says what they were for in chat.
function Shopping.RemoveMissing(missing, forText)
	local api = auctionatorAPI()
	if not api then
		say(ns.Color("warning", "Auctionator is not loaded."))
		return
	end
	local container = ContinuableContainer:Create()
	for _, material in ipairs(missing) do
		container:AddContinuable(Item:CreateFromItemID(material.itemID))
	end
	local listName = Shopping.ListName()
	container:ContinueOnLoad(function()
		local items = {}
		for _, material in ipairs(missing) do
			local name, link = C_Item.GetItemInfo(material.itemID)
			if name then
				local tier = C_TradeSkillUI.GetItemReagentQualityByItemInfo(material.itemID)
				items[#items + 1] = { name = name, link = link or name, qty = material.qty, tier = tier and tier > 0 and tier or nil }
			end
		end
		local removed = removeFromList(api, items, listName)
		if not removed then
			say(ns.Color("warning", "Auctionator couldn't update the shopping list."))
		elseif #removed == 0 then
			say(format("Nothing on the shopping list for %s.", forText))
		else
			say(format("Removed from Auctionator's \"%s\" shopping list, for %s: %s.",
				listName, forText, itemList(removed)))
		end
	end)
end

local function addForCrafts(model, crafts)
	Shopping.AddMissing(model.missingFor(crafts), Shopping.CraftsText(crafts))
end

-- The typed count from "Other amount...", remembered for the menu.
local function acceptCustom(text, model)
	local crafts = tonumber(text)
	if not crafts or crafts < 1 then return end
	crafts = math.min(math.floor(crafts), MAX_CRAFTS)
	customCrafts = crafts
	addForCrafts(model, crafts)
end

-- The popup's edit box (its name changed between game versions).
local function popupEditBox(popup)
	return popup.GetEditBox and popup:GetEditBox() or popup.editBox
end

-- "Other amount...": asks for a number of crafts.
StaticPopupDialogs.CRAFTPROFIT_CRAFTS = {
	text = "Buy materials for how many crafts?",
	button1 = OKAY,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = #tostring(MAX_CRAFTS),
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnShow = function(self)
		local editBox = popupEditBox(self)
		editBox:SetNumeric(true)
		editBox:SetText(tostring(customCrafts or ""))
		editBox:HighlightText()
	end,
	OnAccept = function(self, model)
		acceptCustom(popupEditBox(self):GetText(), model)
	end,
	EditBoxOnEnterPressed = function(editBox, model)
		acceptCustom(editBox:GetText(), model)
		editBox:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
}

-- The menu a click on the button opens.
local function openMenu(owner, model)
	GameTooltip:Hide()
	MenuUtil.CreateContextMenu(owner, function(_, root)
		local tsm = Shopping.ListTarget() == "tsm"
		root:CreateTitle(tsm and "Copy a TSM search" or format("Add to \"%s\" list", Shopping.ListName()))

		local counts = { unpack(PRESET_CRAFTS) }
		if customCrafts and not tContains(counts, customCrafts) then
			counts[#counts + 1] = customCrafts
			table.sort(counts)
		end
		for _, crafts in ipairs(counts) do
			local total = Shopping.Total(model.missingFor(crafts))
			local note = total > 0 and format("(%d missing)", total) or "(nothing missing)"
			local button = root:CreateButton(format("For %s %s", Shopping.CraftsText(crafts), ns.Color("muted", note)),
				function() addForCrafts(model, crafts) end)
			button:SetEnabled(total > 0)
		end
		root:CreateButton("Other amount...", function() StaticPopup_Show("CRAFTPROFIT_CRAFTS", nil, nil, model) end)

		if not tsm then
			root:CreateDivider()
			root:CreateButton("Clear shopping list", Shopping.Clear)
		end
		Shopping.AddShopWithChoice(root)
	end)
end

-- What a click on the panel's button does: adds what's missing for one craft.
-- Shift-click opens the menu of craft counts, Ctrl-click clears the shopping
-- list. `owner` is the button, for the menu to open from.
function Shopping.Click(model, owner, shift, ctrl)
	if ctrl and Shopping.CanClear() then
		Shopping.Clear()
	elseif not Shopping.ListTarget() then
		return
	elseif shift then
		openMenu(owner, model)
	else
		addForCrafts(model, 1)
	end
end
