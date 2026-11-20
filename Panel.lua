-- Craftonomics: the panel next to the profession window. Draws the tables built
-- by Model.lua; the math lives there.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local Layout = ns.Layout
local Color, Money, Item = ns.Color, ns.Format.Money, ns.Format.Item
local format = string.format

-- Auctionator prices this many days old or older show in red.
local STALE_DAYS = 3

-- The model on screen (Results.lua matches crafts against it), or nil.
Panel.current = nil

local frame
local refreshQueued = false

-- The Crafts box: how many crafts the crafting page's numbers are for, and the
-- recipe it was typed on (another recipe starts at 1 again).
local crafts, craftsKey = 1, nil
-- What this drawing is for: that many crafts (1 on an order), and what's missing
-- for them.
local count, shownMissing = 1, nil

---------------------------------------------------------------------------
-- Fonts, built from the game's own so they follow its font choice
---------------------------------------------------------------------------

local function makeFont(name, base, extra)
	local font = CreateFont(name)
	font:CopyFontObject(base)
	local path, size, flags = base:GetFont()
	font:SetFont(path, size + extra, flags or "")
	return font
end

local fonts = {
	body = makeFont("CraftonomicsBodyFont", GameFontHighlightSmall, 4),
	heading = makeFont("CraftonomicsHeadingFont", GameFontNormalSmall, 4), -- gold section headings
	title = makeFont("CraftonomicsTitleFont", GameFontNormal, 4),
	total = makeFont("CraftonomicsTotalFont", GameFontNormalLarge, 4),     -- Profit / Loss
}

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local rows = {}
local rowCount = 0
local contentHeight = 0
local profitRow -- the Profit/Loss row, for the proc animation to start from
local procRow   -- "This craft made", after a proc: the animation starts from it instead

-- An invisible button over a row, for rows you can click.
local function createRowButton()
	local button = CreateFrame("Button", nil, frame)
	button:SetFrameLevel(frame:GetFrameLevel() + 2)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	button:SetScript("OnClick", function(self, mouseButton) self.onClick(mouseButton, self) end)
	button:SetScript("OnEnter", function(self)
		if not self.tooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		self.tooltip(GameTooltip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	-- Keep the panel draggable from clickable rows too.
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function() frame:GetScript("OnDragStart")(frame) end)
	button:SetScript("OnDragStop", function() frame:GetScript("OnDragStop")(frame) end)
	return button
end

-- A row's cart button, left of its amount: shops for what the row is short of.
local CART_SIZE = 16
local CART_GAP = 6
local function createCartButton()
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(CART_SIZE, CART_SIZE)
	button:SetFrameLevel(frame:GetFrameLevel() + 4)
	if C_Texture.GetAtlasInfo("Perks-ShoppingCart") then
		button:SetNormalAtlas("Perks-ShoppingCart")
	else
		button:SetNormalTexture("Interface\\Icons\\INV_Misc_Bag_10")
	end
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnClick", function(self) self.onClick() end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		self.tooltip(GameTooltip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

-- Adds a row: text on the left, an amount on the right. `onClick(mouseButton, button)`
-- and `tooltip(GameTooltip)` make the row clickable. `cart` ({ onClick, tooltip })
-- adds a cart button left of the amount. Returns the row.
local function addRow(left, right, font, onClick, tooltip, cart)
	rowCount = rowCount + 1
	local row = rows[rowCount]
	if not row then
		row = {
			left = frame:CreateFontString(nil, "OVERLAY"),
			right = frame:CreateFontString(nil, "OVERLAY"),
		}
		row.left:SetJustifyH("LEFT")
		row.right:SetJustifyH("RIGHT")
		rows[rowCount] = row
	end

	local y = -Layout.PAD_TOP - contentHeight
	row.left:ClearAllPoints()
	row.left:SetPoint("TOPLEFT", Layout.PAD_SIDE, y)
	row.right:ClearAllPoints()
	row.right:SetPoint("TOPRIGHT", -Layout.PAD_SIDE, y)
	row.left:SetFontObject(font or fonts.body)
	row.right:SetFontObject(font or fonts.body)
	row.right:SetText(right or "")
	row.left:SetText(left or "")

	-- Rows with an amount stay on one line (long names get cut); notes wrap.
	-- The first row leaves room for the options button and the Best crafts button.
	local hasAmount = right ~= nil and right ~= ""
	local reserved = hasAmount and (row.right:GetStringWidth() + 8)
		or (rowCount == 1 and (Layout.GEAR_SPACE + ns.BestCraftsList.HeaderSpace()) or 0)
	if cart then reserved = reserved + CART_SIZE + CART_GAP end
	row.left:SetWidth(Layout.WIDTH - 2 * Layout.PAD_SIDE - reserved)
	row.left:SetWordWrap(not hasAmount)

	-- Tall enough for wrapped notes and the bigger Profit/Loss font.
	local textHeight = math.max(row.left:GetStringHeight(), row.right:GetStringHeight())
	local height = math.max(Layout.LINE_HEIGHT, math.ceil(textHeight) + 3)
	contentHeight = contentHeight + height
	row.left:Show()
	row.right:Show()

	if onClick then
		row.button = row.button or createRowButton()
		row.button:ClearAllPoints()
		row.button:SetPoint("TOPLEFT", frame, "TOPLEFT", Layout.PAD_SIDE / 2, y + 2)
		row.button:SetPoint("RIGHT", frame, "RIGHT", -Layout.PAD_SIDE / 2, 0)
		row.button:SetHeight(height)
		row.button.onClick, row.button.tooltip = onClick, tooltip
		row.button:Show()
	elseif row.button then
		row.button:Hide()
	end

	if cart then
		row.cart = row.cart or createCartButton()
		row.cart:ClearAllPoints()
		row.cart:SetPoint("RIGHT", frame, "TOPRIGHT", -Layout.PAD_SIDE - row.right:GetStringWidth() - CART_GAP,
			y - height / 2 + 1)
		row.cart.onClick, row.cart.tooltip = cart.onClick, cart.tooltip
		row.cart:Show()
	elseif row.cart then
		row.cart:Hide()
	end
	return row
end

-- One Blizzard-style button across a row (the shopping list's), left-aligned.
-- `onClick(mouseButton, button)` and `tooltip(GameTooltip)` as for addRow.
local BUTTON_HEIGHT = 22
local rowButton, rowButtonUsed
local function addButton(text, onClick, tooltip)
	if not rowButton then
		rowButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		rowButton:SetFrameLevel(frame:GetFrameLevel() + 2)
		rowButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		rowButton:SetScript("OnClick", function(self, mouseButton) self.onClick(mouseButton, self) end)
		rowButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			self.tooltip(GameTooltip)
			GameTooltip:Show()
		end)
		rowButton:SetScript("OnLeave", GameTooltip_Hide)
	end
	rowButton:SetText(text)
	rowButton:SetSize(rowButton:GetFontString():GetUnboundedStringWidth() + 32, BUTTON_HEIGHT)
	rowButton:ClearAllPoints()
	rowButton:SetPoint("TOPLEFT", frame, "TOPLEFT", Layout.PAD_SIDE - 2, -Layout.PAD_TOP - contentHeight)
	rowButton.onClick, rowButton.tooltip = onClick, tooltip
	rowButton:Show()
	rowButtonUsed = true
	contentHeight = contentHeight + BUTTON_HEIGHT + 2
end

-- The Craft button, at the right of the shopping list button's row: starts the
-- crafts, as the game's own Create button does.
local craftButton, craftButtonUsed

-- Its text and whether it can be clicked follow the game's Create button and
-- amount box: "Craft", or "Craft 5" for more than one.
local function updateCraftButton()
	if not (craftButton and craftButton:IsShown()) then return end
	local amount = ns.Blizzard.CreateCount()
	craftButton:SetText(amount > 1 and format("Craft %d", amount) or "Craft")
	craftButton:SetWidth(craftButton:GetFontString():GetUnboundedStringWidth() + 32)
	craftButton:SetEnabled(ns.Blizzard.CanCreate())
end

local function showCraftTip(self)
	local can, reason = ns.Blizzard.CanCreate()
	local amount = ns.Blizzard.CreateCount()
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Craft")
	if can then
		GameTooltip:AddLine(amount > 1 and format("Crafts this %d times, with the materials picked in the crafting window.", amount)
			or "Crafts this once, with the materials picked in the crafting window.", 1, 1, 1, true)
		GameTooltip:AddLine("The same as the Create button there. The Crafts box sets how many, up to what you can "
			.. "make now.", 0.53, 0.53, 0.53, true)
	else
		GameTooltip:AddLine(reason or "You can't craft this right now.", 1, 0.3, 0.3, true)
	end
	GameTooltip:Show()
end

-- Puts the Craft button on the row that starts at `top`.
local function addCraftButton(top)
	if not craftButton then
		craftButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		craftButton:SetFrameLevel(frame:GetFrameLevel() + 2)
		craftButton:SetHeight(BUTTON_HEIGHT)
		craftButton:SetMotionScriptsWhileDisabled(true)
		craftButton:SetScript("OnClick", function()
			GameTooltip:Hide()
			ns.Blizzard.Create()
		end)
		craftButton:SetScript("OnEnter", showCraftTip)
		craftButton:SetScript("OnLeave", GameTooltip_Hide)
	end
	craftButton:ClearAllPoints()
	craftButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Layout.PAD_SIDE + 2, -Layout.PAD_TOP - top)
	craftButton:Show()
	craftButtonUsed = true
	updateCraftButton()
end

-- A little extra space that sets the next row apart.
-- The crafting strategy dropdown, on a row of its own with a label.
local STRATEGY_WIDTH = 140
local CONCENTRATION_WIDTH = 165 -- the concentration strategy's: its names are longer
local IDLE_ALPHA = 0.45 -- how faded a dropdown is while it changes nothing for what's open
local DROPDOWN_HEIGHT = 24

-- The panel's dropdowns, by name, made the first time they're needed, and the
-- ones this drawing shows (the rest are hidden after it).
local dropdowns, dropdownsUsed = {}, {}

-- A row with `label` on the left and a dropdown at its right end. `make(dropdown)`
-- sets up a new one: its menu, what it shows and its tooltip.
local function addDropdownRow(name, label, make)
	local dropdown = dropdowns[name]
	if not dropdown then
		dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
		dropdown:SetWidth(STRATEGY_WIDTH)
		dropdown:SetFrameLevel(frame:GetFrameLevel() + 2)
		make(dropdown)
		dropdown:HookScript("OnLeave", GameTooltip_Hide)
		dropdowns[name] = dropdown
	end
	local top = -Layout.PAD_TOP - contentHeight
	local row = addRow(label)
	row.left:ClearAllPoints()
	row.left:SetPoint("LEFT", frame, "TOPLEFT", Layout.PAD_SIDE, top - DROPDOWN_HEIGHT / 2)
	contentHeight = contentHeight - math.max(Layout.LINE_HEIGHT, math.ceil(row.left:GetStringHeight()) + 3)
		+ DROPDOWN_HEIGHT + 2
	dropdown:ClearAllPoints()
	dropdown:SetPoint("RIGHT", frame, "TOPRIGHT", -Layout.PAD_SIDE + 2, top - DROPDOWN_HEIGHT / 2)
	dropdown:GenerateMenu()
	dropdown:Show()
	dropdownsUsed[name] = true
end

-- The crafting strategy dropdown, on a row of its own with a label.
local function addStrategyDropdown()
	addDropdownRow("strategy", "Crafting strategy", function(dropdown)
		if dropdown.SetSelectionTranslator then dropdown:SetSelectionTranslator(ns.StrategyText) end
		dropdown:SetupMenu(ns.StrategyMenu)
		dropdown:HookScript("OnEnter", function(self)
			local strategy = ns.Strategy()
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText("Crafting strategy")
			GameTooltip:AddLine(strategy[2] .. ": " .. strategy[4], 1, 1, 1, true)
			GameTooltip:AddLine((ns.QUALITY_CRAFTING and "It picks the materials for Use Craftonomics materials, prices "
				.. "what you're missing and decides what the shopping list buys." or "It prices what you're missing and "
				.. "decides what the shopping list buys.") .. " Also under the Best crafts list and in the options.",
				0.53, 0.53, 0.53, true)
			GameTooltip:Show()
		end)
	end)
end

-- A dropdown row for one of the settings with choices ({ key, label, tooltip }
-- each): its tooltip lists them under `intro` (optional), then `note` in grey.
-- `width`: when the choices' names need more than the usual.
local function addChoiceRow(name, label, key, title, choices, note, intro, width)
	addDropdownRow(name, label, function(dropdown)
		if width then dropdown:SetWidth(width) end
		if dropdown.SetSelectionTranslator then dropdown:SetSelectionTranslator(ns.ChoiceText(choices)) end
		dropdown:SetupMenu(ns.ChoiceMenu(key, title, choices))
		dropdown:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(title)
			-- Why it changes nothing right now, when it doesn't (see addConcentrationDropdown).
			if self.idleNote then GameTooltip:AddLine(self.idleNote, 1, 0.82, 0, true) end
			if intro then GameTooltip:AddLine(intro, 1, 1, 1, true) end
			for _, choice in ipairs(choices) do
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(ns.ChoiceName(choice), 1, 0.82, 0)
				GameTooltip:AddLine(choice[3], 1, 1, 1, true)
			end
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(note, 0.53, 0.53, 0.53, true)
			GameTooltip:Show()
		end)
	end)
end

-- The concentration strategy dropdown, like the crafting strategy's. With
-- `idleNote` (why it changes nothing for what's open), it's faded and its tooltip
-- says so; it still sets the strategy.
local function addConcentrationDropdown(idleNote)
	local title = ns.CONCENTRATION_STRATEGY_TITLE
	addChoiceRow("concentration", idleNote and Color("muted", title) or title, "concentrationStrategy", title,
		ns.CONCENTRATION_STRATEGIES, "Also under the Patron tab's list and in the options.", ns.CONCENTRATION_STRATEGY_TIP,
		CONCENTRATION_WIDTH)
	local dropdown = dropdowns.concentration
	dropdown.idleNote = idleNote
	dropdown:SetAlpha(idleNote and IDLE_ALPHA or 1)
end

-- On a crafting order: Order materials, and with a minimum quality, Reach the
-- minimum with and the concentration strategy. The same choices as under the
-- Patron tab's list.
local function addOrderChoices(model)
	local note = "For every crafting order. Also under the Patron tab's list and in the options."
	addChoiceRow("orderMaterials", "Materials", "patronMaterials", ns.PATRON_MATERIALS_TITLE, ns.PATRON_MATERIALS_CHOICES, note)
	if (model.minQuality or 0) > 1 then
		addChoiceRow("orderReach", "Reach with", "patronReach", ns.PATRON_REACH_TITLE, ns.PATRON_REACH_CHOICES, note)
		addConcentrationDropdown()
	end
end

-- The Crafts box, on a row of its own with a label: the crafting page's profit,
-- materials and shopping list button are for the number typed in it.
local CRAFTS_BOX_WIDTH, CRAFTS_BOX_HEIGHT = 44, 20
local CRAFTS_ROW = 24
local craftsBox, craftsBoxUsed

local function setCrafts(value)
	value = math.max(1, math.min(math.floor(value or 1), ns.Shopping.MAX_CRAFTS))
	if value == crafts then return end
	crafts = value
	-- The amount box next to Create follows it.
	ns.Blizzard.SetCraftAmount(crafts, craftsKey)
	Panel.Refresh()
end

local function createCraftsBox()
	local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	box:SetSize(CRAFTS_BOX_WIDTH, CRAFTS_BOX_HEIGHT)
	box:SetFrameLevel(frame:GetFrameLevel() + 3)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(#tostring(ns.Shopping.MAX_CRAFTS))
	box:SetJustifyH("CENTER")
	box:SetFontObject(fonts.body)
	-- The panel follows the number while it's typed; an empty box counts as 1.
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then setCrafts(tonumber(self:GetText())) end
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		self:SetText(tostring(crafts))
	end)
	box:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Crafts")
		GameTooltip:AddLine("The profit, the materials and the shopping list button are for this many crafts. The amount "
			.. "box next to Create gets the same number, up to what you can make now.", 1, 1, 1, true)
		GameTooltip:AddLine("Every craft is counted at today's prices. Buying or selling a lot at once can move them, "
			.. "so many crafts can make less than this.", 0.53, 0.53, 0.53, true)
		GameTooltip:Show()
	end)
	box:SetScript("OnLeave", GameTooltip_Hide)
	return box
end

local function addCraftsRow()
	craftsBox = craftsBox or createCraftsBox()
	local top = -Layout.PAD_TOP - contentHeight
	local row = addRow("Crafts")
	row.left:ClearAllPoints()
	row.left:SetPoint("LEFT", frame, "TOPLEFT", Layout.PAD_SIDE, top - CRAFTS_ROW / 2)
	contentHeight = contentHeight - math.max(Layout.LINE_HEIGHT, math.ceil(row.left:GetStringHeight()) + 3) + CRAFTS_ROW
	craftsBox:ClearAllPoints()
	craftsBox:SetPoint("RIGHT", frame, "TOPRIGHT", -Layout.PAD_SIDE, top - CRAFTS_ROW / 2)
	-- Not while it's being typed in: the text is the player's until they're done.
	if not craftsBox:HasFocus() then craftsBox:SetText(tostring(crafts)) end
	craftsBox:Show()
	craftsBoxUsed = true
end

-- The panel's checkboxes, by the setting they turn on and off, made the first
-- time they're needed, and the ones this drawing shows (the rest are hidden after it).
local CHECK_ROW, CHECK_SIZE = 24, 22
local checks, checksUsed = {}, {}

-- A row with a checkbox for the setting `key` and `label` after it.
-- `tooltip(GameTooltip)` fills its tooltip.
local function addCheckRow(key, label, tooltip)
	local check = checks[key]
	if not check then
		check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
		check:SetSize(CHECK_SIZE, CHECK_SIZE)
		check:SetFrameLevel(frame:GetFrameLevel() + 3)
		check:SetScript("OnClick", function(self) ns.Options.Set(key, self:GetChecked() == true) end)
		check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			tooltip(GameTooltip)
			GameTooltip:Show()
		end)
		check:SetScript("OnLeave", GameTooltip_Hide)
		checks[key] = check
	end
	local top = -Layout.PAD_TOP - contentHeight
	local row = addRow(label)
	row.left:ClearAllPoints()
	row.left:SetPoint("LEFT", frame, "TOPLEFT", Layout.PAD_SIDE + CHECK_SIZE, top - CHECK_ROW / 2)
	row.left:SetWidth(Layout.WIDTH - 2 * Layout.PAD_SIDE - CHECK_SIZE)
	contentHeight = contentHeight - math.max(Layout.LINE_HEIGHT, math.ceil(row.left:GetStringHeight()) + 3) + CHECK_ROW
	check:ClearAllPoints()
	check:SetPoint("LEFT", frame, "TOPLEFT", Layout.PAD_SIDE - 4, top - CHECK_ROW / 2)
	check:SetChecked(ns.db[key] == true)
	-- The label is clickable too, like Blizzard's.
	check:SetHitRectInsets(0, -(row.left:GetStringWidth() + 2), 0, 0)
	check:Show()
	checksUsed[key] = true
end

-- The panel's last line: whether it opens by itself with the profession window
-- (the "Open with the profession window" option).
local function addAutoRow()
	addCheckRow("panelAuto", Color("muted", "Open with the profession window"), function(tip)
		tip:SetText("Open with the profession window")
		tip:AddLine("The panel opens by itself when you pick a recipe.", 1, 1, 1, true)
		tip:AddLine("Off: it stays closed until you click the Craftonomics button at the top of the "
			.. "profession window. That button opens and closes the panel either way.", 0.53, 0.53, 0.53, true)
	end)
end

-- Whether materials a vendor sells are bought on the auction house (the "Buy
-- vendor items on the auction house" option), under the crafting strategy.
local function addVendorRow()
	addCheckRow("vendorOnAH", "Buy vendor items on the auction house", function(tip)
		tip:SetText("Buy vendor items on the auction house")
		tip:AddLine("Materials a vendor sells (thread, flux, vials...) are priced at their auction house price and go "
			.. "on the shopping list.", 1, 1, 1, true)
		tip:AddLine("Off: they're priced at the vendor, and the shopping list says in chat to buy them there. Also in "
			.. "the options.", 0.53, 0.53, 0.53, true)
	end)
end

-- "1 craft" or "10 crafts": what this drawing's numbers are for.
local function craftsText()
	return ns.Shopping.CraftsText(count)
end

local function addGap()
	contentHeight = contentHeight + Layout.GAP
end

---------------------------------------------------------------------------
-- Decoration: tinted bands behind rows, fading lines, the header
---------------------------------------------------------------------------

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD = { 1, 0.82, 0 }
local PROFIT_TINT, LOSS_TINT = { 0.2, 0.9, 0.3 }, { 1, 0.3, 0.3 }
local EDGE = 4          -- the frame's border: decoration stays inside it
local BOX_INSET = 6     -- panel edge to a box around rows
local HERO_PAD = 6      -- inside the box around the profit, above and below
local ICON = 36         -- the crafted item's icon in the header
local HEADER_HEIGHT = ICON + 8

-- Colors a texture from one color at its left (or bottom) to another at its
-- right (or top). Guarded: how the game takes a gradient differs between versions.
local function gradient(texture, orientation, from, fromAlpha, to, toAlpha)
	texture:SetTexture(WHITE)
	local ok = pcall(function()
		texture:SetGradient(orientation, CreateColor(from[1], from[2], from[3], fromAlpha),
			CreateColor(to[1], to[2], to[3], toAlpha))
	end)
	if not ok then texture:SetVertexColor(from[1], from[2], from[3], math.max(fromAlpha, toAlpha)) end
end

local bands, bandCount = {}, 0

-- A strip behind the rows, from "top" down the content for "height", "inset" from
-- the panel's sides (or "width" wide from its left). The caller colors it.
local function addBand(top, height, inset, width)
	bandCount = bandCount + 1
	local band = bands[bandCount]
	if not band then
		band = frame:CreateTexture(nil, "BORDER")
		bands[bandCount] = band
	end
	band:ClearAllPoints()
	band:SetPoint("TOPLEFT", inset, -Layout.PAD_TOP - top)
	if width then band:SetWidth(width) else band:SetPoint("RIGHT", -inset, 0) end
	band:SetHeight(height)
	band:Show()
	return band
end

local dividers = {}
local dividerCount = 0

-- A gold line that fades out to the right, under a heading or over the footer.
local function addRule(inset)
	dividerCount = dividerCount + 1
	local line = dividers[dividerCount]
	if not line then
		line = frame:CreateTexture(nil, "ARTWORK")
		dividers[dividerCount] = line
	end
	gradient(line, "HORIZONTAL", GOLD, 0.7, GOLD, 0)
	local y = -Layout.PAD_TOP - contentHeight
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", inset, y)
	line:SetPoint("TOPRIGHT", -inset, y)
	-- At least one screen pixel, whatever the panel size.
	PixelUtil.SetHeight(line, 1, 1)
	line:Show()
end

-- A section's heading in gold, with what it adds up to and a line under it.
local function addHeading(left, right)
	local row = addRow(left, right, fonts.heading)
	addRule(Layout.PAD_SIDE)
	contentHeight = contentHeight + Layout.DIVIDER_GAP
	return row
end

-- A faint stripe behind the row that was just added at "top": every other line
-- of a list, so amounts are easy to follow across.
local function stripe(top)
	local band = addBand(top - 2, contentHeight - top, BOX_INSET)
	gradient(band, "HORIZONTAL", { 1, 1, 1 }, 0.05, { 1, 1, 1 }, 0.05)
end

-- A red tint behind the row that was just added at "top": a material you're
-- short of. It fades out to the right, under the amount.
local function shortTint(top)
	local band = addBand(top - 2, contentHeight - top, BOX_INSET)
	gradient(band, "HORIZONTAL", LOSS_TINT, 0.28, LOSS_TINT, 0.04)
end

local header

local function createHeader()
	header = {}
	header.band = frame:CreateTexture(nil, "BORDER")
	header.band:SetPoint("TOPLEFT", EDGE, -EDGE)
	header.band:SetPoint("TOPRIGHT", -EDGE, -EDGE)
	header.band:SetHeight(Layout.PAD_TOP + HEADER_HEIGHT - EDGE)
	gradient(header.band, "VERTICAL", GOLD, 0.02, GOLD, 0.2)
	header.line = frame:CreateTexture(nil, "ARTWORK")
	header.line:SetPoint("TOPLEFT", header.band, "BOTTOMLEFT")
	header.line:SetPoint("TOPRIGHT", header.band, "BOTTOMRIGHT")
	PixelUtil.SetHeight(header.line, 1, 1)
	gradient(header.line, "HORIZONTAL", GOLD, 0.8, GOLD, 0.1)

	local icon = CreateFrame("Button", nil, frame)
	icon:SetSize(ICON, ICON)
	icon:SetPoint("TOPLEFT", Layout.PAD_SIDE, -Layout.PAD_TOP)
	icon:SetFrameLevel(frame:GetFrameLevel() + 2)
	-- A rim in the item's rarity color, then the icon without its own border.
	icon.rim = icon:CreateTexture(nil, "BACKGROUND")
	icon.rim:SetPoint("TOPLEFT", -1, 1)
	icon.rim:SetPoint("BOTTOMRIGHT", 1, -1)
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints()
	icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	icon:SetScript("OnEnter", function(self)
		if not self.link then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetHyperlink(self.link)
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", GameTooltip_Hide)
	icon:SetScript("OnClick", function(self)
		if self.link and IsModifiedClick() then HandleModifiedItemClick(self.link) end
	end)
	-- The panel can be dragged by it too.
	icon:RegisterForDrag("LeftButton")
	icon:SetScript("OnDragStart", function() frame:GetScript("OnDragStart")(frame) end)
	icon:SetScript("OnDragStop", function() frame:GetScript("OnDragStop")(frame) end)
	header.icon = icon

	header.title = frame:CreateFontString(nil, "OVERLAY")
	header.title:SetFontObject(fonts.title)
	header.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
	header.title:SetJustifyH("LEFT")
	header.title:SetWordWrap(false)
	header.sub = frame:CreateFontString(nil, "OVERLAY")
	header.sub:SetFontObject(fonts.body)
	header.sub:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -4)
	header.sub:SetPoint("RIGHT", frame, "RIGHT", -Layout.PAD_SIDE, 0)
	header.sub:SetJustifyH("LEFT")
	header.sub:SetWordWrap(false)
end

-- The top of the panel: the crafted item's icon, the recipe's name and what it
-- makes (on an order: what's ordered). "link" is the item, when there is one.
local function drawHeader(model, sub, link)
	if not header then createHeader() end
	local icon = header.icon
	local itemID = link and C_Item.GetItemInfoInstant(link)
	icon.link = link
	-- Without an item: the recipe's own picture, or on WoW Forever (an enchant) a scroll.
	icon.texture:SetTexture((itemID and C_Item.GetItemIconByID(itemID))
		or (ns.QUALITY_CRAFTING and ns.RecipeIcon(model.icon)) or ns.SCROLL_ICON)
	local quality = link and C_Item.GetItemQualityByID(link)
	local color = quality and ITEM_QUALITY_COLORS[quality]
	if color then
		icon.rim:SetColorTexture(color.r, color.g, color.b, 1)
	else
		icon.rim:SetColorTexture(0.5, 0.5, 0.5, 1)
	end
	-- Room for the options button and the Ledger button at its right.
	header.title:SetWidth(Layout.WIDTH - 2 * Layout.PAD_SIDE - ICON - 10 - Layout.GEAR_SPACE
		- ns.BestCraftsList.HeaderSpace())
	header.title:SetText(model.title)
	header.sub:SetText(sub or "")
	contentHeight = contentHeight + HEADER_HEIGHT
end

local function signedMoney(amount)
	return Color(ns.AmountColor(amount), (amount > 0 and "+" or "") .. Money(amount))
end

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------

-- How many of a material you're short of for the crafts shown (0 when you have enough).
local function missingOf(model, material)
	for _, entry in ipairs(shownMissing or model.missing or {}) do
		if entry.itemID == material.itemID then return entry.qty end
	end
	return 0
end

-- Shift-click on a material: just that material's missing amount, to the shopping
-- list or a TSM search.
local function shopMaterial(model, material)
	local qty = missingOf(model, material)
	if qty == 0 then
		local name = C_Item.GetItemNameByID(material.itemID) or "that material"
		ns.Shopping.Say(format("Nothing missing: you have enough %s for %s.", name, craftsText()))
		return
	end
	ns.Shopping.AddMissing({ { itemID = material.itemID, qty = qty } }, craftsText(), nil, model.listSource)
end

-- The hammer after a material you craft yourself, in the text: the same picture
-- as the Patron tab's craft button.
local CRAFTED_ICON
local function craftedIcon()
	if not CRAFTED_ICON then
		for _, atlas in ipairs({ "Cursor_Repair_32", "worldquest-icon-blacksmithing" }) do
			if not CRAFTED_ICON and C_Texture.GetAtlasInfo(atlas) then
				CRAFTED_ICON = format("|A:%s:%d:%d|a", atlas, Layout.ICON_SIZE - 2, Layout.ICON_SIZE - 2)
			end
		end
		CRAFTED_ICON = CRAFTED_ICON or format("|TInterface\\Icons\\Trade_BlackSmithing:%d|t", Layout.ICON_SIZE - 2)
	end
	return CRAFTED_ICON
end

-- Whether a material is one you craft yourself (Craft myself, Cheapest way), so
-- it's priced at what crafting it costs.
local function isCrafted(material)
	return ns.Chains.Crafted(material.itemID) ~= nil
end

-- The recipes you came from by clicking a material you craft yourself, the first
-- one first: { recipeID, professionID = its profession, name } ... The Back row
-- at the top of the panel returns to the last of them. Forgotten when the
-- profession window closes.
local trail = {}
-- The recipe a click is on its way to, and until when: another profession takes
-- a moment to open, and until then the panel still draws the recipe you left.
-- headingCrafts is what its Crafts box starts on when it shows.
local headingTo, headingUntil, headingCrafts = nil, 0, 1
local HEADING_SECONDS = 3
local BACK_ICON = "|TInterface\\Buttons\\UI-SpellbookIcon-PrevPage-Up:18|t"
local CANT_OPEN = "Couldn't open the profession that makes %s right now."

-- How many crafts of its recipe make what you're short of a material for the
-- crafts the panel shows: one when you have enough.
local function craftsToCover(material, recipe)
	local short = material.qty * count - ns.Model.Owned(material.itemID)
	if short <= 0 then return 1 end
	return math.min(math.ceil(short / recipe.madeAtLeast), ns.Shopping.MAX_CRAFTS)
end

-- Shows the recipe that makes a material you craft yourself, in its profession's
-- window, with its Crafts box on what you're short of. Remembers the recipe you
-- clicked it on, and how many crafts that was on, for the Back row.
local function openCrafted(model, material)
	local recipe = ns.Chains.RecipeFor(material.itemID)
	if not (recipe and recipe.recipeID) then return end
	GameTooltip:Hide()
	local from = model.kind == "craft" and model.recipeID and model.recipeID ~= recipe.recipeID
		and { recipeID = model.recipeID, professionID = ns.Blizzard.ShownBaseProfession(), name = model.title,
			crafts = count }
	local cover = craftsToCover(material, recipe)
	if not ns.Blizzard.OpenRecipe(recipe.recipeID, recipe.professionID) then
		ns.Shopping.Say(format(CANT_OPEN, recipe.name or "it"))
		return
	end
	if from then trail[#trail + 1] = from end
	headingTo, headingUntil, headingCrafts = recipe.recipeID, GetTime() + HEADING_SECONDS, cover
end

-- The Back row's click: shows the recipe you last came from again.
local function goBack()
	local to = table.remove(trail)
	if not to then return end
	GameTooltip:Hide()
	if ns.Blizzard.OpenRecipe(to.recipeID, to.professionID) then
		headingTo, headingUntil, headingCrafts = to.recipeID, GetTime() + HEADING_SECONDS, to.crafts or 1
	else
		trail[#trail + 1] = to
		ns.Shopping.Say(format(CANT_OPEN, to.name or "it"))
	end
	Panel.Refresh()
end

-- The Back row, under the panel's top: "Back to" the recipe whose material you
-- clicked, while there is one. Drawn before the rest of a craft.
local function drawBack(model)
	if headingTo == model.recipeID or GetTime() > headingUntil then headingTo = nil end
	-- You're on a recipe you came from again (picked by hand, or its materials
	-- lead back to it): the way back ends before it.
	if not headingTo then
		for index, entry in ipairs(trail) do
			if entry.recipeID == model.recipeID then
				for last = #trail, index, -1 do trail[last] = nil end
				break
			end
		end
	end
	local to = trail[#trail]
	if not to then return end
	local name = to.name or "the recipe"
	addGap()
	addRow(BACK_ICON .. " Back to " .. Color("heading", name), nil, nil, goBack, function(tip)
		tip:SetText("Back to " .. name)
		tip:AddLine("The recipe you clicked this material on.", 1, 1, 1, true)
	end)
end

-- `canCycle`: the material comes in qualities you can click through.
local function materialTooltip(model, material, canCycle)
	return function(tip)
		tip:SetItemByID(material.itemID)
		if isCrafted(material) then
			tip:AddLine(" ")
			tip:AddLine(craftedIcon() .. " You craft this yourself: priced at what crafting it costs.", 1, 1, 1, true)
		end
		local age = material.price and ns.Prices.MaterialAge(material.itemID)
		if age ~= nil then
			local stale = age == false or age >= STALE_DAYS
			tip:AddLine(" ")
			tip:AddLine(Color(stale and "warning" or "muted", "Auctionator price seen " .. ns.Prices.AgeText(age)))
		end
		local missing = missingOf(model, material)
		if material.estimated then
			tip:AddLine(" ")
			tip:AddLine(Color("missing", format("You're short of %d for %s.",
				missing > 0 and missing or material.qty * count, craftsText())))
		end
		tip:AddLine(" ")
		if canCycle then
			tip:AddLine(Color("simulated", "Click: try the next quality"))
			tip:AddLine(Color("simulated", "Right-click: back to what's in the form"))
		elseif isCrafted(material) then
			tip:AddLine(Color("simulated", "Click: open its recipe"))
		end
		if missing > 0 and ns.Shopping.ListTarget() then
			tip:AddLine(Color("simulated", format(ns.Shopping.ListTarget() == "tsm"
				and "Shift-click: copy a TSM search for the %d missing"
				or "Shift-click: add the %d missing to the shopping list", missing)))
		end
	end
end

local function shoppingTooltip(model, target)
	return function(tip)
		local missing = shownMissing or model.missing
		if #missing > 0 then
			tip:SetText("Missing for " .. craftsText())
			for _, material in ipairs(missing) do ns.Shopping.AddMissingLine(tip, material.itemID, material.qty) end
		else
			tip:SetText("Nothing missing for " .. craftsText())
		end
		tip:AddLine(" ")
		tip:AddLine(Color("simulated", target == "tsm" and ("Click: copy a TSM search for " .. craftsText())
			or format("Click: add what's missing for %s to the shopping list", craftsText())))
		tip:AddLine(Color("simulated", "Right-click: pick how many crafts"))
		if ns.Shopping.CanClear() then
			tip:AddLine(Color("simulated", format("Ctrl-click: clear the \"%s\" shopping list", ns.Shopping.ListName())))
		end
	end
end

-- The button for the shopping list or the TSM search, for the crafts shown. It
-- shows even when they're covered, since its menu buys for more. Hidden when
-- shopping is turned off in the options.
local function drawShoppingButton(model)
	if not model.shoppable then return end
	local target = ns.Shopping.ListTarget()
	if not target then return end
	local missing = ns.Shopping.Total(shownMissing or model.missing)
	local forCrafts = count
	addGap()
	local text
	if target == "tsm" then
		text = missing > 0 and format("Copy TSM search (%d missing)", missing) or "Copy TSM search"
	else
		text = missing > 0 and format("Shopping list (%d missing)", missing) or "Shopping list"
	end
	local onClick = function(mouseButton, button)
		-- Right-click opens the menu; Ctrl-click (left) clears the list.
		local menu = mouseButton == "RightButton"
		ns.Shopping.Click(model, button, menu, not menu and IsControlKeyDown(), forCrafts)
	end
	addButton(text, onClick, shoppingTooltip(model, target))
end

-- The tooltip of a "saves" line: why the cheaper rank comes out ahead.
local function cheaperTooltip(material, cheaper)
	return function(tip)
		tip:SetText("Cheaper to buy")
		local qty = material.slot.quantityRequired
		tip:AddDoubleLine(Item(cheaper.itemID, qty) .. " instead", Money(cheaper.buyCost), 1, 1, 1, 1, 1, 1)
		local sellText = ns.db.ahCut and format("Yours sell for (after %d%% AH cut)", ns.AH_CUT * 100) or "Yours sell for"
		tip:AddDoubleLine(sellText, Money(cheaper.ownValue), 1, 1, 1, 1, 1, 1)
		tip:AddDoubleLine("You come out ahead", signedMoney(cheaper.saves), 1, 1, 1, 1, 1, 1)
		tip:AddLine("The order still gets its minimum quality.", 0.53, 0.53, 0.53, true)
		tip:AddLine(" ")
		tip:AddLine(Color("simulated", "Click: use it, so the shopping list buys it"))
	end
end

-- The cart button on a material you're short of: adds what's missing of it for
-- the crafts shown to the shopping list (or a TSM search).
local function materialCart(model, material)
	local missing = missingOf(model, material)
	local target = ns.Shopping.ListTarget()
	if missing == 0 or not target then return end
	return {
		onClick = function() shopMaterial(model, material) end,
		tooltip = function(tip)
			tip:SetText(format("Missing %d for %s", missing, craftsText()))
			ns.Shopping.AddMissingLine(tip, material.itemID, missing)
			tip:AddLine(" ")
			tip:AddLine(Color("simulated", target == "tsm" and "Click: copy a TSM search for them"
				or "Click: add them to the shopping list"))
		end,
	}
end

-- The buttons under the materials: the shopping list's, and on the crafting page
-- the Craft button, which shares its row or has its own.
local function drawActions(model)
	local before = contentHeight
	drawShoppingButton(model)
	if model.kind == "craft" and ns.Blizzard.ShowsCreate() then
		if contentHeight == before then
			addGap()
			contentHeight = contentHeight + BUTTON_HEIGHT + 2
		end
		addCraftButton(contentHeight - BUTTON_HEIGHT - 2)
	end
end

local function drawMaterials(model)
	if #model.materials == 0 then return drawActions(model) end
	addGap()
	-- What they cost in all, on the heading.
	addHeading("Your materials", Color(ns.AmountColor(-model.cost), Money(-model.cost * count)))
	local shownCheaper = {}
	for index, material in ipairs(model.materials) do
		local cart = materialCart(model, material)
		-- Short of it, with shopping turned off in the options: the word instead.
		local tag = (material.simulated and ("  " .. Color("simulated", "simulated")))
			or (not cart and missingOf(model, material) > 0 and ("  " .. Color("missing", "missing")))
			or ""
		-- Craft myself: priced at what crafting it costs.
		local crafted = isCrafted(material)
		if crafted then tag = tag .. "  " .. craftedIcon() end
		-- Click cycles qualities, or opens the recipe of a material you craft
		-- yourself; Shift-click shops for just this material.
		local onClick, tooltip
		local canCycle = model.canSimulate and ns.Simulation.CanChange(material)
		local canShop = ns.Shopping.ListTarget() and missingOf(model, material) > 0
		if canCycle or canShop or crafted then
			onClick = function(mouseButton)
				if IsShiftKeyDown() then
					if canShop then shopMaterial(model, material) end
				elseif canCycle then
					ns.Simulation.Cycle(material, mouseButton)
				elseif crafted and mouseButton == "LeftButton" then
					openCrafted(model, material)
				end
			end
			tooltip = materialTooltip(model, material, canCycle)
		end
		local amount = material.price and Money(material.price * material.qty * count) or Color("warning", "no price")
		local top = contentHeight
		-- In front, how many you have of how many the crafts shown take ("2/5"), as
		-- the crafting window has it: green when that's enough, and red, on a row
		-- tinted red, when you're short.
		local need, have = material.qty * count, ns.Model.Owned(material.itemID)
		local short = have < need
		local name = Item(material.itemID, need):gsub("^%d+x",
			Color(short and "loss" or "profit", format("%d/%d", have, need)), 1)
		addRow(name .. tag, amount, nil, onClick, tooltip, cart)
		if short then
			shortTint(top)
		elseif index % 2 == 0 then
			stripe(top)
		end

		-- A cheaper rank to buy instead of using yours, once per slot.
		local cheaper = model.cheaper and model.cheaper[material.slotIndex]
		if cheaper and not shownCheaper[material.slotIndex] then
			shownCheaper[material.slotIndex] = true
			local rank = ns.Blizzard.ReagentQualityMarkup(cheaper.itemID) or "Another rank"
			addRow(Color("simulated", format("   %s saves %s: click to use it", rank, Money(cheaper.saves))), nil, nil,
				function() ns.Simulation.Pick(material.slotIndex, cheaper.itemID) end, cheaperTooltip(material, cheaper))
		end
	end
	drawActions(model)
end

-- What multicraft / resourcefulness added on the last craft, and what that craft
-- made in all.
local function drawProcs(model)
	local proc = ns.Results.ProcFor(model)
	if not proc then return end
	addGap()
	addHeading("Procs")
	if proc.multicraft > 0 then
		addRow(format("Multicraft: +%d extra", proc.multicraft),
			proc.multicraftValue and signedMoney(proc.multicraftValue) or Color("muted", "no price"))
	end
	for _, saved in ipairs(proc.saved) do
		addRow("Resourcefulness: " .. Item(saved.itemID, saved.qty),
			saved.value and signedMoney(saved.value) or Color("muted", "no price"))
	end
	if proc.actual then procRow = addRow("This craft made", signedMoney(proc.actual)) end
end

local function resetTooltip(tip)
	tip:SetText("Back to what's in the form")
	tip:AddLine("The panel shows what this craft would make with the qualities you picked. Your real craft still uses what's in the form.", 1, 1, 1, true)
end


-- The breakdown of the expected profit.
local function expectedTooltip(model)
	return function(tip)
		local procs, chances = model.procs, model.procs.chances
		tip:SetText((model.expected >= 0 and "Expected profit" or "Expected loss")
			.. (count > 1 and (" for " .. craftsText()) or ""))
		if model.kind == "order" then
			tip:AddLine("What this order makes on average, counting resourcefulness on the materials you supply and "
				.. "the ones the customer sent (what it saves comes back to you). Multicraft doesn't count, since the "
				.. "customer gets the item. Without procs, under it, is what it makes when resourcefulness doesn't "
				.. "proc.", 1, 1, 1, true)
		else
			tip:AddLine("What this craft makes on average, counting multicraft and resourcefulness. "
				.. "Without procs, under it, is what it makes when neither procs.", 1, 1, 1, true)
		end
		tip:AddLine(" ")
		tip:AddDoubleLine("Without procs", signedMoney(model.total * count), 1, 1, 1, 1, 1, 1)
		if chances.multicraft > 0 then
			tip:AddDoubleLine(format("Multicraft %.0f%% x %.2f extra per item", chances.multicraft * 100, procs.extraPerItem),
				signedMoney(procs.multicraft * count), 1, 1, 1, 1, 1, 1)
			tip:AddLine("  " .. ns.Procs.SourceText(procs.multicraftProcs), 0.53, 0.53, 0.53)
		end
		if chances.resourcefulness > 0 then
			tip:AddDoubleLine(format("Resourcefulness %.0f%% x %.0f%% saved", chances.resourcefulness * 100,
				procs.savedShare * 100), signedMoney(procs.resourcefulness * count), 1, 1, 1, 1, 1, 1)
			tip:AddLine("  " .. ns.Procs.SourceText(procs.resourcefulnessProcs), 0.53, 0.53, 0.53)
		end
	end
end

-- How old the oldest Auctionator price on the panel is: ", seen today",
-- ", oldest 4 days ago" (in red once it's stale), or "" when prices come from TSM.
-- Also true when it's old enough to show in red.
local function priceAgeText(model)
	-- An old auction house scan says more than any one price: it comes first, in red.
	local scan = ns.Reminder.FooterText()
	if scan ~= "" then return "|r" .. scan, true end
	local oldest
	local function consider(age)
		if age == false then
			oldest = false
		elseif age and oldest ~= false and (not oldest or age > oldest) then
			oldest = age
		end
	end
	for _, material in ipairs(model.materials or {}) do
		if material.price then consider(ns.Prices.MaterialAge(material.itemID)) end
	end
	if model.output and model.output.sale then consider(ns.Prices.SaleAge(model.output.link)) end
	if oldest == nil then return "" end
	if oldest == 0 then return ", seen today" end
	local text = ", oldest " .. ns.Prices.AgeText(oldest)
	if oldest == false or oldest >= STALE_DAYS then return "|r" .. Color("warning", text), true end
	return text
end

-- The answer, under the title: the expected profit in the big font, with what a
-- craft makes without procs under it in grey. Without procs to expect: Profit/Loss.
-- On the crafting page the Crafts box is over it, and the amounts are for that
-- many crafts ("x10" after the label).
local function drawHeadline(model)
	local total = model.total
	local procs = model.procs
	local expecting = procs and procs.total > 0
	local amount = expecting and model.expected or total
	if not amount then return end
	addGap()
	-- In a box of its own, green for a profit and red for a loss.
	local top = contentHeight
	contentHeight = contentHeight + HERO_PAD
	if model.kind == "craft" then addCraftsRow() end
	local times = count > 1 and (" " .. Color("muted", "x" .. count)) or ""
	if expecting then
		profitRow = addRow((amount >= 0 and "Expected profit" or "Expected loss") .. times,
			Color(ns.AmountColor(amount), Money(amount * count)), fonts.total, nop, expectedTooltip(model))
		addRow(Color("muted", "Without procs"), Color("muted", Money(total * count)), nil, nop, expectedTooltip(model))
	else
		-- WoW Forever: "Net", next to the Gross profit line under it.
		local net = not ns.QUALITY_CRAFTING
		local label = amount >= 0 and (net and "Net profit" or "Profit") or (net and "Net loss" or "Loss")
		profitRow = addRow(label .. times,
			Color(ns.AmountColor(amount), Money(amount * count)), fonts.total)
	end
	contentHeight = contentHeight + HERO_PAD - 2
	local tint = amount >= 0 and PROFIT_TINT or LOSS_TINT
	gradient(addBand(top, contentHeight - top, BOX_INSET), "HORIZONTAL", tint, 0.3, tint, 0.05)
	gradient(addBand(top, contentHeight - top, BOX_INSET, 3), "HORIZONTAL", tint, 1, tint, 1)
end

local INFO_ICON = "|TInterface\\Common\\help-i:20:20|t"

-- The footer's tooltip: this session and its luck (when `session`), then the
-- notes about how the panel got its numbers.
local function footerTooltip(session, notes)
	return function(tip)
		tip:SetText(session and "This session" or "Notes")
		if session then
			tip:AddLine("What your crafts made since you logged in on this character.", 1, 1, 1, true)
			ns.Procs.AddLuckLines(tip)
		end
		if #notes > 0 then
			tip:AddLine(" ")
			for _, text in ipairs(notes) do tip:AddLine(text, 0.53, 0.53, 0.53, true) end
		end
		if session then
			tip:AddLine(" ")
			tip:AddLine(Color("simulated", "Click: reset to zero"))
		end
	end
end

-- The bottom: problems you should see stay in sight (materials without a price,
-- old prices, what-if qualities); then one line with this session's total and
-- luck, whose tooltip holds the other notes.
local function drawFooter(model)
	local notes, quiet = model.notes, {}
	if notes.estimated then
		quiet[#quiet + 1] = notes.filled and (model.kind == "order"
				and "Missing materials: priced at the qualities the Patron tab picks."
				or "Missing materials: priced at the qualities your crafting strategy picks.")
			or "Missing materials: cheapest quality assumed."
	end
	for _, text in ipairs(notes) do quiet[#quiet + 1] = text end
	local ageText, stale = priceAgeText(model)
	local pricesText = "Prices: " .. ns.Prices.SourceLabel() .. ageText
	local session = ns.db.session
	local showSession = ns.db.showSession and session.crafts > 0

	-- The bottom of the panel is a darker strip, under a line.
	addGap()
	local top = contentHeight
	addRule(EDGE)
	contentHeight = contentHeight + Layout.DIVIDER_GAP + 2
	if notes.missing then
		addRow(Color("warning", format("%d material(s) have no price, so profit is too high", notes.missing)))
	end
	if model.simulating then
		addRow(Color("simulated", "Simulating other qualities. Click here to go back to what's in the form."),
			nil, nil, ns.Simulation.Reset, resetTooltip)
	end
	-- The prices line stays in sight when they're old, and is the last line without
	-- a session total; the other notes are in its tooltip.
	if stale or not showSession then
		local hasNotes = #quiet > 0
		addRow(Color("muted", pricesText), hasNotes and INFO_ICON or nil, nil, hasNotes and nop or nil,
			hasNotes and footerTooltip(false, quiet) or nil)
	end
	if showSession then
		local sessionNotes = { unpack(quiet) }
		if not stale then sessionNotes[#sessionNotes + 1] = pricesText end
		local dot = " " .. Color("muted", "·") .. " "
		local luck = ns.Procs.LuckText()
		addRow(format("%s %s%s%d craft%s%s", Color("heading", "Session"), signedMoney(session.total), dot,
			session.crafts, session.crafts == 1 and "" or "s", luck and (dot .. luck) or ""),
			INFO_ICON, nil, ns.Results.ConfirmResetSession, footerTooltip(true, sessionNotes))
	end
	addAutoRow()
	local band = addBand(top, contentHeight + Layout.PAD_BOTTOM - EDGE - top, EDGE)
	gradient(band, "HORIZONTAL", { 0, 0, 0 }, 0.35, { 0, 0, 0 }, 0.35)
end

-- " (after 10% cut)", in grey, for an amount shown after a cut. Empty when
-- there's no cut.
local function cutNote(cut, gross, name)
	if not (cut and cut > 0 and gross > 0) then return "" end
	return " " .. Color("muted", format("(after %d%% %s)", math.floor(cut / gross * 100 + 0.5), name))
end

-- What the row's materials are, for its tooltip.
local function bestExplanation(kind, best)
	-- What the concentration strategy picked them for, when they spend any.
	local goal = best.concentration and ns.OptimizesFor()
	if kind == "order" then
		if goal == "gold" then
			return format("The materials that reach the order's minimum quality and earn the most gold for each "
				.. "concentration point (it takes %d).", best.concentration)
		elseif goal then
			return format("The materials that reach the order's minimum quality with the least concentration (%d), "
				.. "and the cheapest of those.", best.concentration)
		end
		return "The cheapest materials that still reach the order's minimum quality."
	end
	local strategy = ns.Strategy()
	local text = format("Crafting strategy: %s. %s", strategy[2], strategy[4])
	if goal == "gold" and strategy[1] ~= "cheapest" then
		text = text .. format(" Concentration strategy: the materials that make that rank and earn the most gold "
			.. "for each concentration point (it takes %d).", best.concentration)
	elseif goal and strategy[1] ~= "cheapest" then
		text = text .. format(" Concentration strategy: the materials that reach that rank with the least "
			.. "concentration (%d), the cheapest of those.", best.concentration)
	end
	return text
end

-- A rank's quality icon, or "rank 3".
local function rankIcon(recipeID, rank)
	return ns.Blizzard.ItemQualityMarkup(recipeID, rank) or ("rank " .. rank)
end

local function bestTooltip(kind, best, recipeID)
	return function(tip)
		tip:SetText(kind == "order" and "Use the most profitable materials" or "Use Craftonomics materials")
		tip:AddLine("Puts these in the form:", 1, 1, 1)
		for _, pick in ipairs(best.list) do tip:AddLine(Item(pick.itemID, pick.qty), 1, 1, 1) end
		if best.concentrate then tip:AddLine("and turns on concentration, which it needs.", 1, 1, 1, true) end
		tip:AddLine(bestExplanation(kind, best) .. " What you own counts at what it would sell for.", 0.53, 0.53, 0.53, true)
		if best.toQuality then
			tip:AddLine(format("Makes %s instead of %s.", rankIcon(recipeID, best.toQuality),
				rankIcon(recipeID, best.fromQuality)), 1, 1, 1, true)
		end
		-- For the crafts shown, like the row.
		local gain = best.gain * count
		if best.gain > 0 then
			tip:AddDoubleLine("You come out ahead", signedMoney(gain), 1, 1, 1, 1, 1, 1)
		elseif best.toQuality and best.toQuality > best.fromQuality then
			tip:AddDoubleLine("Costs more, makes a better rank", signedMoney(gain), 1, 1, 1, 1, 1, 1)
		elseif best.savesConcentration then
			tip:AddDoubleLine("Costs more, saves concentration", signedMoney(gain), 1, 1, 1, 1, 1, 1)
		elseif best.usesOwned then
			tip:AddDoubleLine("Costs more, uses what you own", signedMoney(gain), 1, 1, 1, 1, 1, 1)
		end
	end
end

-- A row that puts Craftonomics' materials in the form, when it has others: on an
-- order the most profitable ones, on the crafting page the crafting strategy's.
-- With "Use Craftonomics Reagents" on, it only shows when something couldn't go
-- in (you're short of it) or you changed a slot since.
local function drawBest(model)
	local best = model.best
	if not best then return end
	addGap()
	local text = Color("simulated", model.kind == "order" and "Use the most profitable materials" or "Use Craftonomics materials")
	if best.toQuality then text = text .. " " .. rankIcon(model.key, best.toQuality) end
	if best.gain > 0 then text = text .. " " .. signedMoney(best.gain * count) end
	addRow(text, nil, nil, function() ns.Best.Use(best) end, bestTooltip(model.kind, best, model.key))
end

-- What concentration spends on the crafts shown, or the rank it would reach.
local function drawConcentration(model)
	local concentration = model.concentration
	if not concentration then return end
	local needed = concentration.points * count
	local points = concentration.icon and format("%d |T%s:%d|t", needed, concentration.icon, Layout.ICON_SIZE)
		or format("%d concentration", needed)
	local short = concentration.short or (concentration.have ~= nil and concentration.have < needed)
	if short then points = Color("warning", points .. " (not enough)") end
	if concentration.on then
		addRow("Uses " .. points)
	else
		addRow(format("%s makes %s", points, rankIcon(model.key, concentration.quality)),
			concentration.gain and signedMoney(concentration.gain * count) or nil)
	end
end

-- How well the item sells, from TSM: the share of its auctions that sell. On an
-- alt with saved TSM prices, which don't carry that, how many sell a day in your region.
local function drawDemand(output)
	if not output.link then return end
	if ns.Prices.HasSaleRate() then
		local rate = ns.Prices.SaleRate(output.link)
		addRow("Sale rate " .. Color("muted", "(TSM)"), rate and ns.Format.SaleRate(rate) or Color("muted", "-"))
	elseif ns.Prices.HasTSM() then
		local perDay = ns.Prices.SoldPerDay(output.link)
		local text = perDay and (perDay < 10 and format("%.1f", perDay) or BreakUpLargeNumbers(math.floor(perDay + 0.5)))
		addRow("Sells per day " .. Color("muted", "(TSM)"), text or Color("muted", "-"))
	end
	-- How far its market value is from its historical price, as TSM's tooltip shows it.
	if ns.Prices.HasTrend() then
		local trend = ns.Prices.Trend(output.link)
		addRow("Trend " .. Color("muted", "(TSM)"), trend and ns.Format.Trend(trend) or Color("muted", "-"))
	end
end

-- From this share of the profit, the auction house deposit is called high.
local HIGH_DEPOSIT = 0.25
-- With TSM's sale rate for the item, a high deposit only matters under this: an
-- item that mostly sells gives its deposit back.
local LOW_SALE_RATE = 0.60

-- A warning when the auction house deposit for what the crafts shown make is high
-- against their profit, and the item often doesn't sell: you only get a deposit
-- back when the auction sells. For the duration the Sell tab is on, or the longest
-- when none was picked. Without a sale rate to go by (no TSM, or it has none for
-- the item), a high deposit is enough.
local function drawDeposit(model)
	local output = model.output
	local profit = (model.procs and model.procs.total > 0 and model.expected or model.total or 0) * count
	if not (output and output.itemID and output.sale) or profit <= 0 then return end
	local durations = ns.AUCTION_DURATIONS
	local duration = durations[ns.db.sellDuration] and ns.db.sellDuration or #durations
	local qty = math.max(math.floor(output.made * count + 0.5), 1)
	local deposit = ns.Prices.Deposit(output.itemID, duration, qty)
	if not deposit or deposit < HIGH_DEPOSIT * profit then return end
	local rate = ns.Prices.HasSaleRate() and ns.Prices.SaleRate(output.link) or nil
	if rate and rate >= LOW_SALE_RATE then return end
	local share = math.floor(deposit / profit * 100 + 0.5)
	addRow(Color("missing", "High AH deposit ") .. Color("muted", format("(%s)", durations[duration])),
		Color("missing", Money(deposit)), nil, nop, function(tip)
			tip:SetText("High AH deposit")
			tip:AddLine(format("Putting what %s make on the auction house for %s takes a deposit of %s. That's %d%% of "
				.. "the profit.", craftsText(), durations[duration], Money(deposit), share), 1, 1, 1, true)
			tip:AddLine("You get it back when the auction sells, and lose it when it runs out unsold.", 1, 1, 1, true)
			if rate then
				tip:AddLine("TSM's sale rate for it: " .. ns.Format.SaleRate(rate), 1, 1, 1)
				tip:AddLine(format("Shown from %d%% of the profit, when the sale rate is under %d%%.", HIGH_DEPOSIT * 100,
					LOW_SALE_RATE * 100), 0.53, 0.53, 0.53, true)
			else
				tip:AddLine(format("Shown from %d%% of the profit.", HIGH_DEPOSIT * 100), 0.53, 0.53, 0.53)
			end
		end)
end

-- WoW Forever: what a skill point costs with this recipe, with its color and chance.
-- Not for a grey recipe: it gives no skill-ups, so there's nothing to say.
local function drawSkillup(model)
	-- An enchant makes nothing to sell: its skill point costs the materials.
	local output = model.output
	if not (ns.SKILLUPS and model.recipeID and model.kind == "craft") then return end
	local sale = output and output.sale and (output.sale - (output.ahCut or 0))
	local cost, chance, color = ns.Skillups.Cost(model.recipeID, model.cost or 0, sale,
		output and output.itemID, output and output.made)
	if not color or color == "grey" or not (chance and chance > 0) then return end
	addRow("Per skill-up  " .. Color("muted", "(") .. ns.Skillups.ChanceText(chance, color) .. Color("muted", ")"),
		ns.Skillups.CostText(cost))
end

local function drawCraft(model)
	local output = model.output
	drawHeader(model, output and format("Makes %sx %s", output.qtyText, output.link), output and output.link)
	drawBack(model)
	drawHeadline(model)
	if output then
		addGap()
		-- WoW Forever calls it Gross profit, over the Net profit at the top.
		local sells = ns.QUALITY_CRAFTING and "Sells for" or "Gross profit"
		if output.sale then
			-- One line, after the AH cut.
			if output.ahCut then
				addRow(sells .. cutNote(output.ahCut, output.sale, "AH cut"), Money((output.sale - output.ahCut) * count))
			else
				addRow(sells, Money(output.sale * count))
			end
		else
			addRow(sells, Color("warning", "no price"))
		end
		drawDemand(output)
		drawDeposit(model)
		drawSkillup(model)
		drawConcentration(model)
	end
	drawMaterials(model)
	-- Right above the blue row, which follows it. (Orders have their own rule.)
	addGap()
	addStrategyDropdown()
	-- Only where materials come in qualities. Faded when it has nothing to choose
	-- between: a craft only spends concentration with Concentrate on, and then
	-- only when more than one mix of materials makes the rank.
	if ns.QUALITY_CRAFTING then
		addConcentrationDropdown(not model.concentrating
			and "Concentrate is off in the crafting window, so this changes nothing for this recipe right now."
			or model.ways == 0 and "This recipe has no materials or ranks to choose between, so this changes nothing for it."
			or model.ways == 1 and "Only one combination of materials makes this rank, so this changes nothing for this "
				.. "recipe. The rank comes from your crafting strategy."
			or nil)
	end
	addVendorRow()
	drawBest(model)
	drawProcs(model)
	drawFooter(model)
end

-- An order's income: the commission after the cut and the rewards that sell, with
-- their sum on the heading. A reward that could sell but has no price gets a line
-- that says so. Rewards that don't sell share one grey line of icons, named in
-- its tooltip.
local function drawIncome(model)
	local income, sellable, unpriced, other = model.receive, {}, {}, {}
	for _, reward in ipairs(model.rewards) do
		if reward.value then
			income = income + reward.value
			sellable[#sellable + 1] = reward
		elseif reward.unpriced then
			unpriced[#unpriced + 1] = reward
		else
			other[#other + 1] = reward
		end
	end
	addGap()
	addHeading("Income", Color(ns.AmountColor(income), Money(income)))
	-- One line, after the consortium's cut.
	addRow("Commission" .. cutNote(model.consortiumCut, model.commission, "cut"), Money(model.receive))
	for _, reward in ipairs(sellable) do addRow(Item(reward.itemID, reward.qty), Money(reward.value)) end
	for _, reward in ipairs(unpriced) do
		addRow(Item(reward.itemID, reward.qty), Color("warning", "no price"), nil, nop, function(tip)
			tip:SetText("No price")
			tip:AddLine("This reward can be sold, but your price source has no price for it, so the profit doesn't count it.",
				1, 1, 1, true)
		end)
	end
	if #other > 0 then
		local icons = {}
		for _, reward in ipairs(other) do
			local icon = reward.currency and reward.currency.iconFileID or C_Item.GetItemIconByID(reward.itemID)
			icons[#icons + 1] = format("%dx |T%s:%d|t", reward.qty, icon or 134400, Layout.ICON_SIZE)
		end
		addRow(Color("muted", "Rewards") .. "  " .. table.concat(icons, "  "), Color("muted", "not sellable"), nil, nop,
			function(tip)
				tip:SetText("Rewards that don't sell")
				for _, reward in ipairs(other) do
					tip:AddLine(reward.currency and ns.Format.Currency(reward.currency, reward.qty)
						or Item(reward.itemID, reward.qty), 1, 1, 1)
				end
			end)
	end
end

local function drawOrder(model)
	drawHeader(model, model.recipeName)
	drawHeadline(model)
	drawIncome(model)

	drawMaterials(model)
	-- Right above the blue row, which follows them: the order's own choices.
	if #model.materials > 0 and not model.isRecraft then
		addGap()
		addOrderChoices(model)
		addVendorRow()
	end
	drawBest(model)
	if #model.materials == 0 then
		addGap()
		addRow(Color("good", "Customer provides all materials"))
	end

	local quality = model.simulatedQuality
	if quality then
		-- Set apart from the costs, in the same blue as the "simulated" tags.
		addGap()
		-- Say when the form's concentration is what reaches it.
		local concentration = quality.concentration
			and Color("simulated", format(" (%d concentration)",quality.concentration)) or ""
		addRow(Color("simulated", "Simulated quality:") .. " " .. quality.markup .. concentration)
		if quality.belowMinimum then
			addRow(Color("loss", "Below the order's minimum quality (") .. quality.belowMinimum .. Color("loss", ")"))
		end
	end

	drawProcs(model)
	drawFooter(model)
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function buildModel()
	local db = ns.db
	local page = ns.Blizzard.ActivePage()
	if page == "order" and db.orders then
		local ctx = ns.Blizzard.OrderContext()
		return ctx and ns.Model.Order(ctx)
	elseif page == "craft" and db.crafting then
		local ctx = ns.Blizzard.CraftContext()
		if ctx then return ns.Model.Craft(ctx) end
	end
end

-- Every item the model shows, by itemID: its name arriving from the server
-- redraws the panel.
local function itemsOf(model)
	local items = {}
	local function add(list)
		for _, entry in pairs(list or {}) do
			if entry.itemID then items[entry.itemID] = true end
		end
	end
	add(model.materials)
	add(model.missing)
	add(model.rewards)
	add(model.cheaper)
	add(model.best and model.best.list)
	if model.output and model.output.link then
		local itemID = C_Item.GetItemInfoInstant(model.output.link)
		if itemID then items[itemID] = true end
	end
	return items
end
local shownItems = {}

-- A redraw can change the row under the mouse (tracked, simulated...), so its
-- tooltip is drawn again, or hidden if the row isn't clickable any more.
local function refreshTooltip()
	for _, row in ipairs(rows) do
		local button = row.button
		if button and GameTooltip:IsOwned(button) then
			if button:IsVisible() and button.tooltip then
				button:GetScript("OnEnter")(button)
			else
				GameTooltip:Hide()
			end
			return
		end
	end
end

-- Whether the panel is open while the profession window is. Each time that
-- window opens it starts as the "Open with the profession window" option says;
-- the Craftonomics button on the window then opens or closes it.
local open = true

-- Redraws right away. Prefer Panel.Refresh, which batches redraws.
function Panel.Render()
	refreshQueued = false
	if not frame then return end
	local model, waiting = buildModel()
	-- A recipe with many material mixes takes a few frames to work out: the panel
	-- shows what it had until then.
	if waiting then
		Panel.Refresh()
		return
	end
	rowCount, dividerCount, bandCount, contentHeight, profitRow, procRow = 0, 0, 0, 0, nil, nil
	rowButtonUsed, craftsBoxUsed, craftButtonUsed = false, false, false
	wipe(dropdownsUsed)
	wipe(checksUsed)
	-- The Crafts box is for the recipe it was typed on: another one starts at 1.
	-- One you came to from a material, or went back to, starts on what you're
	-- short of there, or on what it was on.
	local crafting = model ~= nil and model.kind == "craft"
	if crafting and model.key ~= craftsKey then
		local start = (headingTo == model.key and GetTime() <= headingUntil) and headingCrafts or 1
		-- The amount box next to Create follows the new number, not the old one.
		if crafts > 1 or start > 1 then ns.Blizzard.SetCraftAmount(start, model.key) end
		crafts, craftsKey = start, model.key
		if craftsBox then craftsBox:ClearFocus() end
	end
	count = crafting and crafts or 1
	shownMissing = model and (count > 1 and model.missingFor(count) or model.missing)
	-- Before the rows, which leave room for it.
	ns.BestCraftsList.UpdateTab()

	Panel.current = model
	shownItems = model and itemsOf(model) or {}
	if model then
		if model.kind == "order" then drawOrder(model) else drawCraft(model) end
	end

	for i = rowCount + 1, #rows do
		rows[i].left:Hide()
		rows[i].right:Hide()
		if rows[i].button then rows[i].button:Hide() end
		if rows[i].cart then rows[i].cart:Hide() end
	end
	for i = dividerCount + 1, #dividers do dividers[i]:Hide() end
	for i = bandCount + 1, #bands do bands[i]:Hide() end
	if rowButton and not rowButtonUsed then rowButton:Hide() end
	if craftButton and not craftButtonUsed then craftButton:Hide() end
	if craftsBox and not craftsBoxUsed then craftsBox:Hide() end
	for key, check in pairs(checks) do
		if not checksUsed[key] then check:Hide() end
	end
	for name, dropdown in pairs(dropdowns) do
		if not dropdownsUsed[name] then dropdown:Hide() end
	end
	-- Closed (see Panel.Toggle), it's drawn all the same, so what follows the panel
	-- (the shopping list, the Best crafts tab) has what it needs.
	if model and open then
		frame:SetHeight(Layout.PAD_TOP + contentHeight + Layout.PAD_BOTTOM)
		frame:Show()
	else
		frame:Hide()
	end
	refreshTooltip()
	ns.Best.Check(model)
end

-- Opens the panel, or closes it: the Craftonomics button on the profession window.
-- It stays that way until the profession window is opened again.
function Panel.Toggle()
	open = not open
	Panel.Render()
end

-- Redraws once at the end of this frame, however many times it's called.
-- A craft of `recipeID` finished. When that's the recipe the Crafts box is for
-- and it's on more than one, there's one fewer to go: the box counts down to 1,
-- and the panel and the amount box next to Create follow it.
function Panel.Crafted(recipeID)
	if not recipeID or recipeID ~= craftsKey or crafts <= 1 then return end
	crafts = crafts - 1
	ns.Blizzard.SetCraftAmount(crafts, craftsKey)
	Panel.Refresh()
end

function Panel.Refresh()
	if refreshQueued or not frame then return end
	refreshQueued = true
	C_Timer.After(0, Panel.Render)
end

function Panel.Frame()
	return frame
end

-- Where the proc animation starts: "This craft made", or the Profit/Loss amount, or nil.
function Panel.ProfitAnchor()
	local row = procRow or profitRow
	return row and row.right
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------

-- Puts the panel at its saved spot (relative to the profession window) and size.
function Panel.Place()
	if not frame then return end
	-- By default clear of Forever's side tabs, as far from them as from the window elsewhere.
	local pos = ns.db.pos or { x = Layout.DEFAULT_POS.x + ns.Blizzard.SideTabsWidth(), y = Layout.DEFAULT_POS.y }
	frame:SetScale(ns.db.scale)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", pos.x, pos.y)
end

-- The Craftonomics button on the profession window's title bar, left of where
-- the window's own buttons and other addons' sit: it opens and closes the panel.
local TOGGLE_WIDTH, TOGGLE_HEIGHT = 92, 20
local TOGGLE_X, TOGGLE_Y = -104, -1 -- from the window's top right corner

local function createToggle()
	local toggle = CreateFrame("Button", nil, ProfessionsFrame, "UIPanelButtonTemplate")
	toggle:SetSize(TOGGLE_WIDTH, TOGGLE_HEIGHT)
	toggle:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPRIGHT", TOGGLE_X, TOGGLE_Y)
	-- Over the title bar's art, like the window's close button.
	local close = ProfessionsFrame.CloseButton
	if close then toggle:SetFrameLevel(close:GetFrameLevel()) end
	toggle:SetText("Craftonomics")
	toggle:SetScript("OnClick", Panel.Toggle)
	toggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Craftonomics")
		GameTooltip:AddLine("Click: open or close the Craftonomics panel.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", GameTooltip_Hide)
	-- Each time the window opens, the panel starts open or closed as the option says.
	open = ns.db.panelAuto == true
	ProfessionsFrame:HookScript("OnShow", function() open = ns.db.panelAuto == true end)
	-- The Back row's way back ends when the window closes (not when it only
	-- switches to another profession).
	ns.Blizzard.WatchWindowClosed(function()
		wipe(trail)
		headingTo = nil
	end)
end

local function createFrame()
	frame = CreateFrame("Frame", "CraftonomicsPanel", ProfessionsFrame, "BackdropTemplate")
	frame:SetWidth(Layout.WIDTH)
	-- On top of the profession window, should it be dragged over it: a frame level
	-- alone isn't enough (Blizzard raises the window's own layers when it's clicked),
	-- so a higher strata. Also above other addons' buttons on its edge (AllTheThings).
	frame:SetFrameStrata("HIGH")
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.03, 0.03, 0.04, 0.95)
	frame:SetBackdropBorderColor(unpack(Layout.BORDER))
	frame:Hide()

	-- Drag to move (unless locked); the spot is remembered relative to the profession window.
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not ns.db.locked then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- Offsets are in the panel's own (scaled) coordinates.
		local scale = self:GetEffectiveScale()
		local parentScale = ProfessionsFrame:GetEffectiveScale()
		ns.db.pos = {
			x = (self:GetLeft() * scale - ProfessionsFrame:GetRight() * parentScale) / scale,
			y = (self:GetTop() * scale - ProfessionsFrame:GetTop() * parentScale) / scale,
		}
		Panel.Place()
	end)

	local gear = CreateFrame("Button", nil, frame)
	gear:SetSize(16, 16)
	gear:SetPoint("TOPRIGHT", -8, -8)
	gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	gear:SetScript("OnClick", ns.Options.Open)
	gear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Craftonomics options")
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", GameTooltip_Hide)

	createToggle()

	-- Item names arrive from the server after first use; redraw when they do.
	frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	-- The missing materials button follows what you own.
	frame:RegisterEvent("BAG_UPDATE_DELAYED")
	frame:SetScript("OnEvent", function(self, event, itemID)
		-- Other items' names (the Best crafts list loads hundreds) change nothing here.
		if event == "GET_ITEM_INFO_RECEIVED" and not shownItems[itemID] then return end
		-- What you own changes which materials are the most profitable.
		if event == "BAG_UPDATE_DELAYED" then ns.Planner.Reset() end
		if self:IsShown() then Panel.Refresh() end
	end)

	Panel.Place()
end

-- Creates the panel and starts following the profession window. Safe to call
-- more than once.
function Panel.Init()
	if frame or not ns.Blizzard.IsLoaded() then return end
	createFrame()
	ns.Blizzard.Watch(Panel.Refresh, frame)
	ns.Blizzard.WatchCraftAmount()
	ns.Blizzard.WatchCreate(updateCraftButton)
	ns.Results.Init()
end
