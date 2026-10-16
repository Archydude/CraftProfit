-- Craft Profit: the most profitable materials for a crafting order. The panel's
-- "Use the most profitable materials" row puts them in once; the "Use Most
-- Profitable Reagents" checkbox on the order form, above Blizzard's "Use Best
-- Quality Reagents", puts them in every order you open. Above it, "Optimize
-- Concentration" picks the ones that need the least concentration instead.
local _, ns = ...

local Best = {}
ns.Best = Best

local format = string.format

local LABEL = "Use Most Profitable Reagents"
local CONCENTRATION_LABEL = "Optimize Concentration"
local LABEL_GAP = 2 -- checkbox to its label
local ROW_GAP = 0   -- between the stacked checkboxes

local checkbox, concentrationBox

-- How faded Optimize Concentration is while it doesn't change the form.
local DIMMED_ALPHA = 0.45

-- Optimize Concentration only changes the form through Use Most Profitable
-- Reagents, so it's dimmed (box, check and label) while that's off. It stays
-- clickable: it still sets the Patron orders list's picks.
local function updateDim()
	if not concentrationBox then return end
	concentrationBox:SetAlpha(ns.db.bestMaterials and 1 or DIMMED_ALPHA)
end

-- What the checkbox already put in for the open order, so each set goes in once
-- and a slot you change afterwards stays as you set it. Cleared for each order.
local applied = {}
-- Whether the checkbox turned concentration on for the open order.
local concentrated = false

local function forgetOrder()
	wipe(applied)
	concentrated = false
end

local function keyOf(model)
	local parts = { tostring(model.key), tostring(model.best.concentrate) }
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

-- After each panel redraw: with the checkbox on, puts the order's best
-- materials in, once.
function Best.Check(model)
	if not (ns.db.bestMaterials and model and model.kind == "order" and model.best) then return end
	local key = keyOf(model)
	if applied[key] then return end
	applied[key] = true
	if model.best.concentrate then concentrated = true end
	Best.Use(model.best, true)
end

local function showTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(LABEL)
	GameTooltip:AddLine("Puts the most profitable materials in every crafting order you open: the cheapest qualities "
		.. "that still reach the order's minimum quality, with what you own counted at what it would sell for. "
		.. "Turns on concentration when the minimum quality needs it.", 1, 1, 1, true)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Turning it on turns off Use Best Quality Reagents, and the other way round.", 0.53, 0.53, 0.53, true)
	GameTooltip:Show()
end

local function onClick(self)
	local on = self:GetChecked() and true or false
	ns.db.bestMaterials = on
	PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	if on then
		-- Both fill the same slots, so only one can be on.
		ns.Blizzard.StopBestQuality()
	else
		-- Back to what Blizzard puts in by itself, like unticking its checkbox.
		ns.Blizzard.ResetMaterials(concentrated)
	end
	updateDim()
	forgetOrder()
	ns.Panel.Refresh()
	showTooltip(self)
end

-- Blizzard's checkbox was clicked, and it has filled the form its way.
local function onBlizzardBestQuality(checked)
	if checked and ns.db.bestMaterials then
		ns.db.bestMaterials = false
		checkbox:SetChecked(false)
		updateDim()
	end
	forgetOrder()
end

local function showConcentrationTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(CONCENTRATION_LABEL)
	GameTooltip:AddLine(ns.LEAST_CONCENTRATION_TIP, 1, 1, 1, true)
	if not ns.db.bestMaterials then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Use Most Profitable Reagents is off, so this doesn't change the form right now.", 1, 0.82, 0, true)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Picks the materials for Use Most Profitable Reagents and the Patron orders list. "
		.. "The same as Optimize concentration at the bottom of that list.", 0.53, 0.53, 0.53, true)
	GameTooltip:Show()
end

local function onConcentrationClick(self)
	local on = self:GetChecked() and true or false
	PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	-- New picks go in by themselves while Use Most Profitable Reagents is on.
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
	-- The label is clickable too, like Blizzard's.
	box:SetHitRectInsets(0, -(label:GetStringWidth() + LABEL_GAP), 0, 0)
	box:SetChecked(ns.db[setting])
	box:SetScript("OnClick", onClickHandler)
	box:SetScript("OnEnter", tooltip)
	box:SetScript("OnLeave", GameTooltip_Hide)
	-- The setting can change elsewhere (options, the Patron orders list).
	box:SetScript("OnShow", function(self)
		self:SetChecked(ns.db[setting])
		updateDim()
	end)
	return box
end

-- Adds the checkboxes above Blizzard's, stacked upward. Safe to call more than once.
function Best.Init()
	if checkbox then return end
	local blizzardBox = ns.Blizzard.OrderBestQualityBox()
	if not blizzardBox then return end
	-- On Blizzard's checkbox, so they show only where that one does: recipes whose
	-- materials come in qualities.
	checkbox = addCheckbox(blizzardBox, blizzardBox, LABEL, "bestMaterials", onClick, showTooltip)
	concentrationBox = addCheckbox(blizzardBox, checkbox, CONCENTRATION_LABEL, "leastConcentration",
		onConcentrationClick, showConcentrationTooltip)
	updateDim()

	ns.Blizzard.WatchOrderForm(onBlizzardBestQuality, forgetOrder, checkbox)
end
