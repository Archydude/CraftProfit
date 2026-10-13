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
	-- The first row leaves room for the options button.
	local hasAmount = right ~= nil and right ~= ""
	local reserved = hasAmount and (row.right:GetStringWidth() + 8) or (rowCount == 1 and Layout.GEAR_SPACE or 0)
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

local function addSpacer()
	addRow(" ")
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
		tip:AddLine(" ")
		if canCycle then
			tip:AddLine(Color("simulated", "Click: try the next quality"))
			tip:AddLine(Color("simulated", "Right-click: back to what's in the form"))
		end
		local missing = missingOf(model, material)
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
	addRow(Color(missing > 0 and "missing" or "muted", text), nil, nil, onClick, shoppingTooltip(model, target))
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

local function drawMaterials(model)
	if #model.materials == 0 then return end
	addSpacer()
	addRow("Your materials", nil, fonts.heading)
	local shownCheaper = {}
	for _, material in ipairs(model.materials) do
		local tag = (material.simulated and ("  " .. Color("simulated", "simulated")))
			or (material.estimated and ("  " .. Color("missing", "missing")))
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
	addDivider()
	addRow("Materials cost", Money(-model.cost))
	drawShoppingButton(model)
end

-- What multicraft / resourcefulness added on the last craft, listed above the
-- total they changed. Returns the total to show.
local function drawProcs(model)
	local proc = ns.Results.ProcFor(model)
	if not proc then return model.total end
	addSpacer()
	addRow("Procs", nil, fonts.heading)
	if proc.multicraft > 0 then
		addRow(format("Multicraft: +%d extra", proc.multicraft),
			proc.multicraftValue and signedMoney(proc.multicraftValue) or Color("muted", "no price"))
	end
	for _, saved in ipairs(proc.saved) do
		addRow("Resourcefulness: " .. Item(saved.itemID, saved.qty),
			saved.value and signedMoney(saved.value) or Color("muted", "no price"))
	end
	return proc.actual or model.total
end

local function resetTooltip(tip)
	tip:SetText("Back to what's in the form")
	tip:AddLine("The panel shows what this craft would make with the qualities you picked. Your real craft still uses what's in the form.", 1, 1, 1, true)
end

local function sessionTooltip(tip)
	tip:SetText("This session")
	tip:AddLine(Color("simulated", "Click: reset to zero"))
end

-- How old the oldest Auctionator price on the panel is: ", seen today",
-- ", oldest 4 days ago" (in red once it's stale), or "" when prices come from TSM.
local function priceAgeText(model)
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
	if oldest == false or oldest >= STALE_DAYS then return "|r" .. Color("warning", text) end
	return text
end

local function drawFooter(model)
	local total = drawProcs(model)

	addSpacer()
	if total then
		profitRow = addRow(total >= 0 and "Profit" or "Loss", Color(ns.AmountColor(total), Money(total)), fonts.total)
	end

	local session = ns.db.session
	if ns.db.showSession and session.crafts > 0 then
		-- Gold label like Profit/Loss, but in the small font so it doesn't compete with it.
		addGap()
		addRow(format("%s (%d craft%s)", Color("heading", "This session"), session.crafts, session.crafts == 1 and "" or "s"),
			Color(ns.AmountColor(session.total), Money(session.total)), nil, ns.Results.ConfirmResetSession, sessionTooltip)
	end

	local notes = model.notes
	if notes.estimated then addRow(Color("muted", "Missing materials: cheapest quality assumed.")) end
	if notes.missing then
		addRow(Color("warning", format("%d material(s) have no price, so profit is too high", notes.missing)))
	end
	for _, text in ipairs(notes) do addRow(Color("muted", text)) end
	if model.simulating then
		addRow(Color("simulated", "Simulating other qualities. Click here to go back to what's in the form."),
			nil, nil, ns.Simulation.Reset, resetTooltip)
	end
	addRow(Color("muted", "Prices: " .. ns.Prices.SourceLabel() .. priceAgeText(model)))
end

-- " (after 10% cut)", in grey, for an amount shown after a cut. Empty when
-- there's no cut.
local function cutNote(cut, gross, name)
	if not (cut and cut > 0 and gross > 0) then return "" end
	return " " .. Color("muted", format("(after %d%% %s)", math.floor(cut / gross * 100 + 0.5), name))
end

local function drawCraft(model)
	addRow(model.title, nil, fonts.title)
	local output = model.output
	if output then
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
	drawFooter(model)
end

local function bestTooltip(best)
	return function(tip)
		tip:SetText("Use the most profitable materials")
		tip:AddLine("Puts these in the order form:", 1, 1, 1)
		for _, pick in ipairs(best.list) do tip:AddLine(Item(pick.itemID, pick.qty), 1, 1, 1) end
		if best.concentrate then tip:AddLine("and turns on concentration, which it needs.", 1, 1, 1, true) end
		if ns.db.leastConcentration and best.concentration then
			tip:AddLine(format("The materials that reach the order's minimum quality with the least concentration (%d), "
				.. "and the cheapest of those. What you own counts at what it would sell for.", best.concentration),
				0.53, 0.53, 0.53, true)
		else
			tip:AddLine("The cheapest materials that still reach the order's minimum quality. What you own counts at what it would sell for.",
				0.53, 0.53, 0.53, true)
		end
		if best.gain > 0 then
			tip:AddDoubleLine("You come out ahead", signedMoney(best.gain), 1, 1, 1, 1, 1, 1)
		elseif best.savesConcentration then
			tip:AddDoubleLine("Costs more, saves concentration", signedMoney(best.gain), 1, 1, 1, 1, 1, 1)
		end
	end
end

-- A row that puts the most profitable materials in the form, when it has others.
-- With "Use Most Profitable Reagents" on, it only shows when something couldn't
-- go in (you're short of it) or you changed a slot since.
local function drawBest(model)
	local best = model.best
	if not best then return end
	addGap()
	local text = Color("simulated", "Use the most profitable materials")
	if best.gain > 0 then text = text .. " " .. signedMoney(best.gain) end
	addRow(text, nil, nil, function() ns.Best.Use(best) end, bestTooltip(best))
end

local function drawOrder(model)
	addRow(model.title, nil, fonts.title)
	-- One line, after the consortium's cut.
	addRow("Commission" .. cutNote(model.consortiumCut, model.commission, "cut"), Money(model.receive))

	drawMaterials(model)
	drawBest(model)
	if #model.materials == 0 then
		addSpacer()
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

	if #model.rewards > 0 then
		addSpacer()
		addRow("Rewards", nil, fonts.heading)
		for _, reward in ipairs(model.rewards) do
			if reward.currency then
				addRow(ns.Format.Currency(reward.currency, reward.qty), Color("muted", "not sellable"))
			else
				addRow(Item(reward.itemID, reward.qty), reward.value and Money(reward.value) or Color("muted", "not sellable"))
			end
		end
	end

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
		return ctx and ns.Model.Craft(ctx)
	end
end

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
	rowCount, dividerCount, contentHeight, profitRow = 0, 0, 0, nil

	local model = buildModel()
	Panel.current = model
	if model then
		if model.kind == "order" then drawOrder(model) else drawCraft(model) end
	end

	for i = rowCount + 1, #rows do
		rows[i].left:Hide()
		rows[i].right:Hide()
		if rows[i].button then rows[i].button:Hide() end
	end
	for i = dividerCount + 1, #dividers do dividers[i]:Hide() end
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

-- The Profit/Loss amount on screen, or nil.
function Panel.ProfitAnchor()
	return profitRow and profitRow.right
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
	frame:SetScript("OnEvent", function(self, event)
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
