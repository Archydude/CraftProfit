-- Craft Profit: Craft Profit's materials for a crafting order (the most
-- profitable ones) or a recipe (the crafting strategy's). The panel's row puts
-- them in once; the "Use Craft Profit Reagents" checkbox, above Blizzard's "Use
-- Best Quality Reagents" on the order form and on the crafting page, puts them in
-- every order or recipe you open. Above it, "Optimize Concentration" picks the
-- ones that need the least concentration instead. When a recipe's reagents reach
-- down to them, both move into a row beside Blizzard's.
local _, ns = ...

local Best = {}
ns.Best = Best

local format = string.format

local LABEL = "Use Craft Profit Reagents"
local CONCENTRATION_LABEL = "Optimize Concentration"
local LABEL_GAP = 2 -- checkbox to its label
local ROW_GAP = 0   -- between the stacked checkboxes
local ROW_SPACE = 16 -- between the checkboxes when they sit in a row

-- One of each on every form that has Blizzard's checkbox.
local boxes, concentrationBoxes = {}, {}

-- How faded Optimize Concentration is while it doesn't change the form.
local DIMMED_ALPHA = 0.45

-- Optimize Concentration only changes the form through Use Most Profitable
-- Reagents, so it's dimmed (box, check and label) while that's off. It stays
-- clickable: it still sets the Patron tab's picks.
local function updateDim()
	for _, box in ipairs(concentrationBoxes) do
		box:SetAlpha(ns.db.bestMaterials and 1 or DIMMED_ALPHA)
	end
end

-- What the checkbox already put in for the open order or recipe, so each set goes
-- in once and a slot you change afterwards stays as you set it. Cleared for each
-- order or recipe.
local applied = {}
-- Whether the checkbox turned concentration on for the open order.
local concentrated = false

local function forget()
	wipe(applied)
	concentrated = false
end

local function keyOf(model)
	local parts = { model.kind, tostring(model.key), tostring(model.best.concentrate) }
	for _, pick in ipairs(model.best.list) do parts[#parts + 1] = pick.itemID end
	return table.concat(parts, ":")
end

-- Puts `best` (a model's best materials) in the form. `quiet`: nothing in chat
-- about materials you're short of.
function Best.Use(best, quiet)
	local short = ns.Blizzard.UseMaterials(best.picks, best.concentrate)
	-- The form has them now, so what-if picks would only hide that.
	ns.Simulation.Reset()
	if quiet then return end
	for _, material in ipairs(short) do
		ns.Shopping.Say(format("Not enough %s to put in; buy it first.", ns.Format.Item(material.itemID, material.qty)))
	end
end

-- After each panel redraw: with the checkbox on, puts the order's or recipe's
-- best materials in, once.
function Best.Check(model)
	if not (ns.db.bestMaterials and model and model.best) then return end
	local key = keyOf(model)
	if applied[key] then return end
	applied[key] = true
	if model.best.concentrate then concentrated = true end
	Best.Use(model.best, true)
end

local function onCraftPage()
	return ns.Blizzard.ActivePage() == "craft"
end

local function showTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(LABEL)
	if onCraftPage() then
		local strategy = ns.Strategy()
		GameTooltip:AddLine("Puts the materials your crafting strategy picks in every recipe you pick, with what you own "
			.. "counted at what it would sell for.", 1, 1, 1, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(format("Crafting strategy: %s", strategy[2]), 1, 0.82, 0)
		GameTooltip:AddLine(strategy[4], 1, 1, 1, true)
		GameTooltip:AddLine("Change it in the options or at the bottom of the Best crafts list.", 0.53, 0.53, 0.53, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Concentration stays as you set it. With it on, the ranks it reaches count.", 1, 1, 1, true)
	else
		GameTooltip:AddLine("Puts the most profitable materials in every crafting order you open: the cheapest qualities "
			.. "that still reach the order's minimum quality, with what you own counted at what it would sell for. "
			.. "Turns on concentration when the minimum quality needs it.", 1, 1, 1, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Turning it on turns off Use Best Quality Reagents, and the other way round. "
		.. "The same setting on the crafting page and the order form.", 0.53, 0.53, 0.53, true)
	GameTooltip:Show()
end

local function onClick(self)
	local on = self:GetChecked() and true or false
	ns.db.bestMaterials = on
	PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	for _, box in ipairs(boxes) do box:SetChecked(on) end
	if on then
		-- Both fill the same slots, so only one can be on.
		ns.Blizzard.StopBestQuality()
	else
		-- Back to what Blizzard puts in by itself, like unticking its checkbox.
		ns.Blizzard.ResetMaterials(concentrated)
	end
	updateDim()
	forget()
	ns.Panel.Refresh()
	showTooltip(self)
end

-- Blizzard's checkbox was clicked, and it has filled the form its way.
local function onBlizzardBestQuality(checked)
	if checked and ns.db.bestMaterials then
		ns.db.bestMaterials = false
		for _, box in ipairs(boxes) do box:SetChecked(false) end
		updateDim()
	end
	forget()
end

local function showConcentrationTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(CONCENTRATION_LABEL)
	if onCraftPage() then
		GameTooltip:AddLine("With concentration on, uses the material qualities that reach your crafting strategy's "
			.. "rank with the least concentration, and the cheapest of those. The materials cost more, but your concentration "
			.. "lasts for more crafts.\n\nOff: the cheapest materials for that rank, whatever concentration they take.",
			1, 1, 1, true)
	else
		GameTooltip:AddLine(ns.LEAST_CONCENTRATION_TIP, 1, 1, 1, true)
	end
	if not ns.db.bestMaterials then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(LABEL .. " is off, so this doesn't change the form right now.", 1, 0.82, 0, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Picks the materials for " .. LABEL .. " and the Patron tab. "
		.. "The same as Optimize concentration at the bottom of that list.", 0.53, 0.53, 0.53, true)
	GameTooltip:Show()
end

local function onConcentrationClick(self)
	local on = self:GetChecked() and true or false
	PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	for _, box in ipairs(concentrationBoxes) do box:SetChecked(on) end
	-- New picks go in by themselves while Use Craft Profit Reagents is on.
	ns.Patron.SetLeastConcentration(on)
	showConcentrationTooltip(self)
end

-- A checkbox like Blizzard's, above `below`, with a clickable label.
local function addCheckbox(parent, below, text, setting, onClickHandler, tooltip)
	local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	box:SetSize(below:GetSize())
	box:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, ROW_GAP)
	local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", box, "RIGHT", LABEL_GAP, 0)
	label:SetText(LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(text))
	box.label = label
	-- The label is clickable too, like Blizzard's.
	box:SetHitRectInsets(0, -(label:GetStringWidth() + LABEL_GAP), 0, 0)
	box:SetChecked(ns.db[setting])
	box:SetScript("OnClick", onClickHandler)
	box:SetScript("OnEnter", tooltip)
	box:SetScript("OnLeave", GameTooltip_Hide)
	-- The setting can change elsewhere (options, the Patron tab).
	box:SetScript("OnShow", function(self)
		self:SetChecked(ns.db[setting])
		updateDim()
	end)
	return box
end

-- Stacks a form's checkboxes above Blizzard's, or when that would run into the
-- reagents, puts them in a row beside it.
local function placeBoxes(form)
	local blizzardBox = form.AllocateBestQualityCheckbox
	local top = blizzardBox:GetTop()
	if not top then return end -- not on screen yet
	for i, box in ipairs(boxes) do
		if box:GetParent() == blizzardBox then
			local concentration = concentrationBoxes[i]
			local height = blizzardBox:GetHeight() + ROW_GAP
			local fits = top + 2 * height <= ns.Blizzard.ReagentsBottom(form)
			box:ClearAllPoints()
			concentration:ClearAllPoints()
			if fits then
				box:SetPoint("BOTTOMLEFT", blizzardBox, "TOPLEFT", 0, ROW_GAP)
				concentration:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, ROW_GAP)
			else
				box:SetPoint("LEFT", blizzardBox.text, "RIGHT", ROW_SPACE, 0)
				concentration:SetPoint("LEFT", box.label, "RIGHT", ROW_SPACE, 0)
			end
		end
	end
end

-- Adds the checkboxes above Blizzard's on each form, stacked upward. Safe to call
-- more than once.
function Best.Init()
	if #boxes > 0 then return end
	-- On Blizzard's checkbox, so they show only where that one does: recipes whose
	-- materials come in qualities.
	for _, blizzardBox in ipairs(ns.Blizzard.BestQualityBoxes()) do
		local box = addCheckbox(blizzardBox, blizzardBox, LABEL, "bestMaterials", onClick, showTooltip)
		boxes[#boxes + 1] = box
		concentrationBoxes[#concentrationBoxes + 1] = addCheckbox(blizzardBox, box, CONCENTRATION_LABEL,
			"leastConcentration", onConcentrationClick, showConcentrationTooltip)
	end
	if #boxes == 0 then return end
	updateDim()

	ns.Blizzard.WatchForms(onBlizzardBestQuality, forget, boxes[1])
	ns.Blizzard.WatchLayout(placeBoxes)
end
