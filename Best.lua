-- Craft Profit: the most profitable materials for a crafting order. The panel's
-- "Use the most profitable materials" row puts them in once; the "Use Most
-- Profitable Reagents" checkbox on the order form, next to Blizzard's "Use Best
-- Quality Reagents", puts them in every order you open.
local _, ns = ...

local Best = {}
ns.Best = Best

local format = string.format

local LABEL = "Use Most Profitable Reagents"
local LABEL_GAP = 2   -- checkbox to its label
local BLIZZARD_GAP = 24 -- Blizzard's checkbox label to ours

local checkbox

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
	forgetOrder()
	ns.Panel.Refresh()
	showTooltip(self)
end

-- Blizzard's checkbox was clicked, and it has filled the form its way.
local function onBlizzardBestQuality(checked)
	if checked and ns.db.bestMaterials then
		ns.db.bestMaterials = false
		checkbox:SetChecked(false)
	end
	forgetOrder()
end

-- Adds the checkbox next to Blizzard's. Safe to call more than once.
function Best.Init()
	if checkbox then return end
	local blizzardBox = ns.Blizzard.OrderBestQualityBox()
	if not blizzardBox then return end
	-- On Blizzard's checkbox, so it shows only where that one does: recipes whose
	-- materials come in qualities.
	checkbox = CreateFrame("CheckButton", nil, blizzardBox, "UICheckButtonTemplate")
	checkbox:SetSize(blizzardBox:GetSize())
	checkbox:SetPoint("LEFT", blizzardBox.text or blizzardBox, "RIGHT", BLIZZARD_GAP, 0)
	local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", checkbox, "RIGHT", LABEL_GAP, 0)
	label:SetText(LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(LABEL))
	-- The label is clickable too, like Blizzard's.
	checkbox:SetHitRectInsets(0, -(label:GetStringWidth() + LABEL_GAP), 0, 0)
	checkbox:SetChecked(ns.db.bestMaterials)
	checkbox:SetScript("OnClick", onClick)
	checkbox:SetScript("OnEnter", showTooltip)
	checkbox:SetScript("OnLeave", GameTooltip_Hide)
	checkbox:SetScript("OnShow", function(self) self:SetChecked(ns.db.bestMaterials) end)

	ns.Blizzard.WatchOrderForm(onBlizzardBestQuality, forgetOrder, checkbox)
end
