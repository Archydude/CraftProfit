-- Craftonomics: Craftonomics' materials for a crafting order (the most
-- profitable ones) or a recipe (the crafting strategy's). The panel's row puts
-- them in once; the "Use Craftonomics Reagents" checkbox, above Blizzard's "Use
-- Best Quality Reagents" on the order form and on the crafting page, puts them in
-- every order or recipe you open. When a recipe's reagents reach down to it, it
-- moves beside Blizzard's.
local _, ns = ...

local Best = {}
ns.Best = Best

local format = string.format

local LABEL = "Use Craftonomics Reagents"
local LABEL_GAP = 2 -- checkbox to its label
local ROW_GAP = 0   -- between the stacked checkboxes
local ROW_SPACE = 16 -- between the checkboxes when they sit in a row

-- One on every form that has Blizzard's checkbox.
local boxes = {}

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
		GameTooltip:AddLine("Concentration stays as you set it. With it on, the ranks it reaches count, and the "
			.. "concentration strategy picks the materials for them.", 1, 1, 1, true)
	else
		GameTooltip:AddLine("Puts the most profitable materials in every crafting order you open: the cheapest qualities "
			.. "that still reach the order's minimum quality, with what you own counted at what it would sell for. "
			.. "Turns on concentration when the minimum quality needs it; the concentration strategy then picks the materials.",
			1, 1, 1, true)
	end
	local concentration = ns.ConcentrationStrategy()
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(format("%s: %s", ns.CONCENTRATION_STRATEGY_TITLE, ns.ChoiceName(concentration)), 1, 0.82, 0)
	GameTooltip:AddLine(concentration[3], 1, 1, 1, true)
	GameTooltip:AddLine("Change it on the panel, in the options or in the gear at the bottom of the Patron tab.",
		0.53, 0.53, 0.53, true)
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
	forget()
	ns.Panel.Refresh()
	showTooltip(self)
end

-- Blizzard's checkbox was clicked, and it has filled the form its way.
local function onBlizzardBestQuality(checked)
	if checked and ns.db.bestMaterials then
		ns.db.bestMaterials = false
		for _, box in ipairs(boxes) do box:SetChecked(false) end
	end
	forget()
end

-- A checkbox like Blizzard's, above it, with a clickable label.
local function addCheckbox(blizzardBox)
	local box = CreateFrame("CheckButton", nil, blizzardBox, "UICheckButtonTemplate")
	box:SetSize(blizzardBox:GetSize())
	box:SetPoint("BOTTOMLEFT", blizzardBox, "TOPLEFT", 0, ROW_GAP)
	local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", box, "RIGHT", LABEL_GAP, 0)
	label:SetText(LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(LABEL))
	box.label = label
	-- The label is clickable too, like Blizzard's.
	box:SetHitRectInsets(0, -(label:GetStringWidth() + LABEL_GAP), 0, 0)
	box:SetChecked(ns.db.bestMaterials)
	box:SetScript("OnClick", onClick)
	box:SetScript("OnEnter", showTooltip)
	box:SetScript("OnLeave", GameTooltip_Hide)
	-- The other form's checkbox may have changed the setting.
	box:SetScript("OnShow", function(self) self:SetChecked(ns.db.bestMaterials) end)
	return box
end

-- Puts a form's checkbox above Blizzard's, or when that would run into the
-- reagents, beside it.
local function placeBoxes(form)
	local blizzardBox = form.AllocateBestQualityCheckbox
	local top = blizzardBox:GetTop()
	if not top then return end -- not on screen yet
	for _, box in ipairs(boxes) do
		if box:GetParent() == blizzardBox then
			local fits = top + blizzardBox:GetHeight() + ROW_GAP <= ns.Blizzard.ReagentsBottom(form)
			box:ClearAllPoints()
			if fits then
				box:SetPoint("BOTTOMLEFT", blizzardBox, "TOPLEFT", 0, ROW_GAP)
			else
				box:SetPoint("LEFT", blizzardBox.text, "RIGHT", ROW_SPACE, 0)
			end
		end
	end
end

-- Adds the checkbox above Blizzard's on each form. Safe to call more than once.
function Best.Init()
	if #boxes > 0 then return end
	-- On Blizzard's checkbox, so it shows only where that one does: recipes whose
	-- materials come in qualities.
	for _, blizzardBox in ipairs(ns.Blizzard.BestQualityBoxes()) do
		boxes[#boxes + 1] = addCheckbox(blizzardBox)
	end
	if #boxes == 0 then return end

	ns.Blizzard.WatchForms(onBlizzardBestQuality, forget, boxes[1])
	ns.Blizzard.WatchLayout(placeBoxes)
end
