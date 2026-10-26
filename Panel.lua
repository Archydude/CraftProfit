-- Craft Profit: the panel next to the profession window. Draws the tables built
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
	body = makeFont("CraftProfitBodyFont", GameFontHighlightSmall, 4),
	heading = makeFont("CraftProfitHeadingFont", GameFontNormalSmall, 4), -- gold section headings
	title = makeFont("CraftProfitTitleFont", GameFontNormal, 3),
	total = makeFont("CraftProfitTotalFont", GameFontNormalLarge, 2),     -- Profit / Loss
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

-- Adds a row: text on the left, an amount on the right. `onClick(mouseButton, button)`
-- and `tooltip(GameTooltip)` make the row clickable. Returns the row.
local function addRow(left, right, font, onClick, tooltip)
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

-- A little extra space that sets the next row apart.
local function addGap()
	contentHeight = contentHeight + Layout.GAP
end

local dividers = {}
local dividerCount = 0

-- A thin line across the panel, like the one above a sum.
local function addDivider()
	dividerCount = dividerCount + 1
	local line = dividers[dividerCount]
	if not line then
		line = frame:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(1, 1, 1, 0.25)
		dividers[dividerCount] = line
	end
	contentHeight = contentHeight + Layout.DIVIDER_GAP
	local y = -Layout.PAD_TOP - contentHeight
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", Layout.PAD_SIDE, y)
	line:SetPoint("TOPRIGHT", -Layout.PAD_SIDE, y)
	-- At least one screen pixel, whatever the panel size.
	PixelUtil.SetHeight(line, 1, 1)
	line:Show()
	contentHeight = contentHeight + line:GetHeight() + Layout.DIVIDER_GAP
end

local function signedMoney(amount)
	return Color(ns.AmountColor(amount), (amount > 0 and "+" or "") .. Money(amount))
end

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------

-- How many of a material you're short of for one craft (0 when you have enough).
local function missingOf(model, material)
	for _, entry in ipairs(model.missing or {}) do
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
		ns.Shopping.Say(format("Nothing missing: you have enough %s for 1 craft.", name))
		return
	end
	ns.Shopping.AddMissing({ { itemID = material.itemID, qty = qty } }, "1 craft")
end

-- `canCycle`: the material comes in qualities you can click through.
local function materialTooltip(model, material, canCycle)
	return function(tip)
		tip:SetItemByID(material.itemID)
		local age = material.price and ns.Prices.MaterialAge(material.itemID)
		if age ~= nil then
			local stale = age == false or age >= STALE_DAYS
			tip:AddLine(" ")
			tip:AddLine(Color(stale and "warning" or "muted", "Auctionator price seen " .. ns.Prices.AgeText(age)))
		end
		local missing = missingOf(model, material)
		if material.estimated then
			tip:AddLine(" ")
			tip:AddLine(Color("missing", format("You're short of %d for 1 craft.", missing > 0 and missing or material.qty)))
		end
		tip:AddLine(" ")
		if canCycle then
			tip:AddLine(Color("simulated", "Click: try the next quality"))
			tip:AddLine(Color("simulated", "Right-click: back to what's in the form"))
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
		if #model.missing > 0 then
			tip:SetText("Missing for 1 craft")
			for _, material in ipairs(model.missing) do tip:AddLine(Item(material.itemID, material.qty), 1, 1, 1) end
		else
			tip:SetText("Nothing missing for 1 craft")
		end
		tip:AddLine(" ")
		tip:AddLine(Color("simulated", target == "tsm" and "Click: copy a TSM search for 1 craft"
			or "Click: add what's missing for 1 craft to the shopping list"))
		tip:AddLine(Color("simulated", "Shift-click: pick how many crafts"))
		if ns.Shopping.CanClear() then
			tip:AddLine(Color("simulated", format("Ctrl-click: clear the \"%s\" shopping list", ns.Shopping.ListName())))
		end
	end
end

-- The button for the shopping list or the TSM search. It shows even when one
-- craft is covered, since its menu buys for several. Hidden with nothing to send
-- the materials to.
local function drawShoppingButton(model)
	if not model.shoppable then return end
	local target = ns.Shopping.ListTarget()
	if not target then return end
	local missing = ns.Shopping.Total(model.missing)
	addGap()
	local text
	if target == "auctionator" then
		text = missing > 0 and format("Shopping list (%d missing)", missing) or "Shopping list"
	else
		text = missing > 0 and format("Copy TSM search (%d missing)", missing) or "Copy TSM search"
	end
	local onClick = function(_, button)
		ns.Shopping.Click(model, button, IsShiftKeyDown(), IsControlKeyDown())
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

-- The tag on a material you're short of: a little cart (the word "missing" if the
-- game has no cart picture).
local function missingTag()
	if C_Texture.GetAtlasInfo("Perks-ShoppingCart") then return CreateAtlasMarkup("Perks-ShoppingCart", 16, 16) end
	return Color("missing", "missing")
end

local function drawMaterials(model)
	if #model.materials == 0 then return end
	addGap()
	-- What they cost in all, on the heading.
	addRow("Your materials", Color(ns.AmountColor(-model.cost), Money(-model.cost)), fonts.heading)
	local shownCheaper = {}
	for _, material in ipairs(model.materials) do
		local tag = (material.simulated and ("  " .. Color("simulated", "simulated")))
			or (material.estimated and ("  " .. missingTag()))
			or ""
		-- Click cycles qualities; Shift-click shops for just this material.
		local onClick, tooltip
		local canCycle = model.canSimulate and ns.Simulation.CanChange(material)
		local canShop = ns.Shopping.ListTarget() and missingOf(model, material) > 0
		if canCycle or canShop then
			onClick = function(mouseButton)
				if IsShiftKeyDown() then
					if ns.Shopping.ListTarget() then shopMaterial(model, material) end
				elseif canCycle then
					ns.Simulation.Cycle(material, mouseButton)
				end
			end
			tooltip = materialTooltip(model, material, canCycle)
		end
		local amount = material.price and Money(material.price * material.qty) or Color("warning", "no price")
		addRow(Item(material.itemID, material.qty) .. tag, amount, nil, onClick, tooltip)

		-- A cheaper rank to buy instead of using yours, once per slot.
		local cheaper = model.cheaper and model.cheaper[material.slotIndex]
		if cheaper and not shownCheaper[material.slotIndex] then
			shownCheaper[material.slotIndex] = true
			local rank = ns.Blizzard.ReagentQualityMarkup(cheaper.itemID) or "Another rank"
			addRow(Color("simulated", format("   %s saves %s: click to use it", rank, Money(cheaper.saves))), nil, nil,
				function() ns.Simulation.Pick(material.slotIndex, cheaper.itemID) end, cheaperTooltip(material, cheaper))
		end
	end
	drawShoppingButton(model)
end

-- What multicraft / resourcefulness added on the last craft, and what that craft
-- made in all.
local function drawProcs(model)
	local proc = ns.Results.ProcFor(model)
	if not proc then return end
	addGap()
	addRow("Procs", nil, fonts.heading)
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
		tip:SetText(model.expected >= 0 and "Expected profit" or "Expected loss")
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
		tip:AddDoubleLine("Without procs", signedMoney(model.total), 1, 1, 1, 1, 1, 1)
		if chances.multicraft > 0 then
			tip:AddDoubleLine(format("Multicraft %.0f%% x %.2f extra per item", chances.multicraft * 100, procs.extraPerItem),
				signedMoney(procs.multicraft), 1, 1, 1, 1, 1, 1)
			tip:AddLine("  " .. ns.Procs.SourceText(procs.multicraftProcs), 0.53, 0.53, 0.53)
		end
		if chances.resourcefulness > 0 then
			tip:AddDoubleLine(format("Resourcefulness %.0f%% x %.0f%% saved", chances.resourcefulness * 100,
				procs.savedShare * 100), signedMoney(procs.resourcefulness), 1, 1, 1, 1, 1, 1)
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
local function drawHeadline(model)
	addGap()
	local total = model.total
	local procs = model.procs
	if procs and procs.total > 0 then
		local expected = model.expected
		profitRow = addRow(expected >= 0 and "Expected profit" or "Expected loss",
			Color(ns.AmountColor(expected), Money(expected)), fonts.total, nop, expectedTooltip(model))
		addRow(Color("muted", "Without procs"), Color("muted", Money(total)), nil, nop, expectedTooltip(model))
	elseif total then
		profitRow = addRow(total >= 0 and "Profit" or "Loss", Color(ns.AmountColor(total), Money(total)), fonts.total)
	end
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

	addDivider()
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
end

-- " (after 10% cut)", in grey, for an amount shown after a cut. Empty when
-- there's no cut.
local function cutNote(cut, gross, name)
	if not (cut and cut > 0 and gross > 0) then return "" end
	return " " .. Color("muted", format("(after %d%% %s)", math.floor(cut / gross * 100 + 0.5), name))
end

-- What the row's materials are, for its tooltip.
local function bestExplanation(kind, best)
	local least = ns.db.leastConcentration and best.concentration
	if kind == "order" then
		if least then
			return format("The materials that reach the order's minimum quality with the least concentration (%d), "
				.. "and the cheapest of those.", best.concentration)
		end
		return "The cheapest materials that still reach the order's minimum quality."
	end
	if best.noPrice then
		return "No sale price for this item, so: the cheapest materials that keep the rank it comes out at now."
	end
	local strategy = ns.Strategy()
	local text = format("Crafting strategy: %s. %s", strategy[2], strategy[4])
	if least and strategy[1] ~= "cheapest" then
		text = text .. format(" With Optimize Concentration: the materials that reach that rank with the least "
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
		tip:SetText(kind == "order" and "Use the most profitable materials" or "Use Craft Profit materials")
		tip:AddLine("Puts these in the form:", 1, 1, 1)
		for _, pick in ipairs(best.list) do tip:AddLine(Item(pick.itemID, pick.qty), 1, 1, 1) end
		if best.concentrate then tip:AddLine("and turns on concentration, which it needs.", 1, 1, 1, true) end
		tip:AddLine(bestExplanation(kind, best) .. " What you own counts at what it would sell for.", 0.53, 0.53, 0.53, true)
		if best.toQuality then
			tip:AddLine(format("Makes %s instead of %s.", rankIcon(recipeID, best.toQuality),
				rankIcon(recipeID, best.fromQuality)), 1, 1, 1, true)
		end
		if best.gain > 0 then
			tip:AddDoubleLine("You come out ahead", signedMoney(best.gain), 1, 1, 1, 1, 1, 1)
		elseif best.toQuality and best.toQuality > best.fromQuality then
			tip:AddDoubleLine("Costs more, makes a better rank", signedMoney(best.gain), 1, 1, 1, 1, 1, 1)
		elseif best.savesConcentration then
			tip:AddDoubleLine("Costs more, saves concentration", signedMoney(best.gain), 1, 1, 1, 1, 1, 1)
		end
	end
end

-- A row that puts Craft Profit's materials in the form, when it has others: on an
-- order the most profitable ones, on the crafting page the crafting strategy's.
-- With "Use Craft Profit Reagents" on, it only shows when something couldn't go
-- in (you're short of it) or you changed a slot since.
local function drawBest(model)
	local best = model.best
	if not best then return end
	addGap()
	local text = Color("simulated", model.kind == "order" and "Use the most profitable materials" or "Use Craft Profit materials")
	if best.toQuality then text = text .. " " .. rankIcon(model.key, best.toQuality) end
	if best.gain > 0 then text = text .. " " .. signedMoney(best.gain) end
	addRow(text, nil, nil, function() ns.Best.Use(best) end, bestTooltip(model.kind, best, model.key))
end

local function drawCraft(model)
	addRow(model.title, nil, fonts.title)
	drawHeadline(model)
	local output = model.output
	if output then
		addGap()
		addRow(format("Makes %sx %s", output.qtyText, output.link))
		if output.sale then
			-- One line, after the AH cut.
			if output.ahCut then
				addRow("Sells for" .. cutNote(output.ahCut, output.sale, "AH cut"), Money(output.sale - output.ahCut))
			else
				addRow("Sells for", Money(output.sale))
			end
		else
			addRow("Sells for", Color("warning", "no price"))
		end
	end
	drawMaterials(model)
	drawBest(model)
	drawProcs(model)
	drawFooter(model)
end

-- An order's income: the commission after the cut and the rewards that sell, with
-- their sum on the heading. Rewards that don't sell share one grey line of icons,
-- named in its tooltip.
local function drawIncome(model)
	local income, sellable, other = model.receive, {}, {}
	for _, reward in ipairs(model.rewards) do
		if reward.value then
			income = income + reward.value
			sellable[#sellable + 1] = reward
		else
			other[#other + 1] = reward
		end
	end
	addGap()
	addRow("Income", Color(ns.AmountColor(income), Money(income)), fonts.heading)
	-- One line, after the consortium's cut.
	addRow("Commission" .. cutNote(model.consortiumCut, model.commission, "cut"), Money(model.receive))
	for _, reward in ipairs(sellable) do addRow(Item(reward.itemID, reward.qty), Money(reward.value)) end
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
	addRow(model.title, nil, fonts.title)
	drawHeadline(model)
	drawIncome(model)

	drawMaterials(model)
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
	rowCount, dividerCount, contentHeight, profitRow, procRow = 0, 0, 0, nil, nil
	rowButtonUsed = false
	-- Before the rows, which leave room for it.
	ns.BestCraftsList.UpdateToggle()

	Panel.current = model
	shownItems = model and itemsOf(model) or {}
	if model then
		if model.kind == "order" then drawOrder(model) else drawCraft(model) end
	end

	for i = rowCount + 1, #rows do
		rows[i].left:Hide()
		rows[i].right:Hide()
		if rows[i].button then rows[i].button:Hide() end
	end
	for i = dividerCount + 1, #dividers do dividers[i]:Hide() end
	if rowButton and not rowButtonUsed then rowButton:Hide() end
	if model then
		frame:SetHeight(Layout.PAD_TOP + contentHeight + Layout.PAD_BOTTOM)
		frame:Show()
	else
		frame:Hide()
	end
	refreshTooltip()
	ns.Best.Check(model)
end

-- Redraws once at the end of this frame, however many times it's called.
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
	local pos = ns.db.pos or Layout.DEFAULT_POS
	frame:SetScale(ns.db.scale)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", pos.x, pos.y)
end

local function createFrame()
	frame = CreateFrame("Frame", "CraftProfitPanel", ProfessionsFrame, "BackdropTemplate")
	frame:SetWidth(Layout.WIDTH)
	-- Sit above other addons' buttons on the profession window's edge (e.g. AllTheThings).
	frame:SetFrameLevel(ProfessionsFrame:GetFrameLevel() + 50)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
	frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
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
		GameTooltip:SetText("Craft Profit options")
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", GameTooltip_Hide)

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
	ns.Results.Init()
end
