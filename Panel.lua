-- Craft Profit: the panel next to the profession window. Draws the tables built
-- by Model.lua; the math lives there.
local _, ns = ...

local Panel = {}
ns.Panel = Panel

local Layout = ns.Layout
local Color, Money, Item = ns.Color, ns.Format.Money, ns.Format.Item
local format = string.format

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
	button:SetScript("OnClick", function(self, mouseButton) self.onClick(mouseButton) end)
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

-- Adds a row: text on the left, an amount on the right. `onClick(mouseButton)`
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

local function signedMoney(amount)
	return Color(ns.AmountColor(amount), (amount > 0 and "+" or "") .. Money(amount))
end

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------

local function materialTooltip(material)
	return function(tip)
		tip:SetItemByID(material.itemID)
		tip:AddLine(" ")
		tip:AddLine(Color("simulated", "Click: try the next quality"))
		tip:AddLine(Color("simulated", "Right-click: back to what's in the form"))
	end
end

local function missingTooltip(model, target)
	return function(tip)
		tip:SetText("Missing materials")
		for _, material in ipairs(model.missing) do tip:AddLine(Item(material.itemID, material.qty), 1, 1, 1) end
		tip:AddLine(" ")
		if target == "auctionator" then
			tip:AddLine(Color("simulated", format("Click: add these to Auctionator's \"%s\" shopping list", ns.SHOPPING_LIST)))
			tip:AddLine("Click again to add them again, for another craft. Vendor and soulbound materials are listed in chat instead.", 1, 1, 1, true)
			tip:AddLine("Buys the cheapest quality, or the one you picked by clicking a material.", 1, 1, 1, true)
		elseif ns.Shopping.IsTracked(model) then
			tip:AddLine(Color("simulated", "Click: stop tracking this recipe"))
		else
			tip:AddLine(Color("simulated", "Click: track this recipe"))
			tip:AddLine("Blizzard's objective tracker lists all its materials with how many you have.", 1, 1, 1, true)
		end
	end
end

-- The button that sends missing materials to a shopping list or the tracker.
local function drawMissingButton(model)
	local count = #model.missing
	if count == 0 or ns.db.missingTarget == "off" then return end
	local target = ns.Shopping.Target()
	local plural = count == 1 and "" or "s"
	local text
	addGap()
	if target == "auctionator" then
		text = format("Add %d missing material%s to Auctionator", count, plural)
	elseif target == "blizzard" and ns.Shopping.IsTracked(model) then
		text = format("%d material%s missing - recipe tracked", count, plural)
	elseif target == "blizzard" then
		text = format("Track recipe (%d material%s missing)", count, plural)
	else
		addRow(Color("muted", format("%d material%s missing (Auctionator is not loaded)", count, plural)))
		return
	end
	addRow(Color("missing", text), nil, nil, function() ns.Shopping.Send(model) end, missingTooltip(model, target))
end

local function drawMaterials(model)
	if #model.materials == 0 then return end
	addSpacer()
	addRow("Your materials", nil, fonts.heading)
	for _, material in ipairs(model.materials) do
		local tag = (material.simulated and ("  " .. Color("simulated", "simulated")))
			or (material.estimated and ("  " .. Color("missing", "missing")))
			or ""
		local onClick, tooltip
		if model.canSimulate and ns.Simulation.CanChange(material) then
			onClick = function(mouseButton) ns.Simulation.Cycle(material, mouseButton) end
			tooltip = materialTooltip(material)
		end
		local amount = material.price and Money(material.price * material.qty) or Color("warning", "no price")
		addRow(Item(material.itemID, material.qty) .. tag, amount, nil, onClick, tooltip)
	end
	addRow("Materials cost", Money(-model.cost))
	drawMissingButton(model)
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
			Color(ns.AmountColor(session.total), Money(session.total)))
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
	addRow(Color("muted", "Prices: " .. ns.Prices.SourceLabel()))
end

local function drawCraft(model)
	addRow(model.title, nil, fonts.title)
	local output = model.output
	if output then
		addRow(format("Makes %sx %s", output.qtyText, output.link))
		if output.sale then
			addRow("Sells for", Money(output.sale))
			if output.ahCut then
				addRow(Color("muted", format("AH cut (%d%%)", ns.AH_CUT * 100)), Color("muted", Money(-output.ahCut)))
			end
		else
			addRow("Sells for", Color("warning", "no price"))
		end
	end
	drawMaterials(model)
	drawFooter(model)
end

local function drawOrder(model)
	addRow(model.title, nil, fonts.title)
	addRow("Commission", Money(model.commission))
	addRow(Color("muted", "Consortium cut"), Color("muted", Money(-model.consortiumCut)))
	addRow("You receive", Money(model.receive))

	drawMaterials(model)
	if #model.materials == 0 then
		addSpacer()
		addRow(Color("good", "Customer provides all materials"))
	end

	local quality = model.simulatedQuality
	if quality then
		-- Set apart from the costs, in the same blue as the "simulated" tags.
		addGap()
		addRow(Color("simulated", "Simulated quality:") .. " " .. quality.markup)
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

-- Redraws right away. Prefer Panel.Refresh, which batches redraws.
function Panel.Render()
	refreshQueued = false
	if not frame then return end
	rowCount, contentHeight, profitRow = 0, 0, nil

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
	if model then
		frame:SetHeight(Layout.PAD_TOP + contentHeight + Layout.PAD_BOTTOM)
		frame:Show()
	else
		frame:Hide()
	end
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
	-- The missing materials button follows what you own and what's tracked.
	frame:RegisterEvent("BAG_UPDATE_DELAYED")
	frame:RegisterEvent("TRACKED_RECIPE_UPDATE")
	frame:SetScript("OnEvent", function(self)
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
