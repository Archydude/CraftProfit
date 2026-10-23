-- Craft Profit: minimap button (LibDBIcon, so minimap button collectors pick it
-- up) and addon compartment entry. Click to open your profession window on the
-- Best crafts list, right-click for a menu, hover for this session's total.
local _, ns = ...

local Button = {}
ns.Minimap = Button

local format = string.format

local NAME = "CraftProfit" -- the button's name with LibDBIcon
local ICON = "Interface\\Icons\\INV_Hammer_20"
-- Degrees around the minimap where the button starts, away from where the other
-- addons in this folder start theirs (160, 200, 220).
local START_POSITION = 250
-- How long to wait for the profession window to be ready for the Best crafts
-- list after opening it: tries, and seconds between them.
local OPEN_TRIES, OPEN_RETRY = 20, 0.1

local LDBIcon = LibStub("LibDBIcon-1.0")
local registered = false

---------------------------------------------------------------------------
-- Your professions
---------------------------------------------------------------------------

-- Your crafting professions and cooking: { { name, icon, skillLine } ... }.
local function professions()
	local list = {}
	local first, second, _, _, cooking = GetProfessions()
	for _, index in ipairs({ first, second, cooking }) do
		local name, icon, _, _, _, _, skillLine = GetProfessionInfo(index)
		if name and skillLine then list[#list + 1] = { name = name, icon = icon, skillLine = skillLine } end
	end
	return list
end

-- The profession to open: the one whose window you opened last, or else your first.
local function lastProfession()
	local list = professions()
	local last = CraftProfitCharDB and CraftProfitCharDB.lastProfession
	for _, profession in ipairs(list) do
		if profession.skillLine == last then return profession end
	end
	return list[1]
end

-- Opens a profession's window on the Best crafts list. The window takes a moment
-- to be ready, so the list is tried a few times.
local function openBestCrafts(skillLine)
	if not (ns.Blizzard.IsLoaded() and ProfessionsFrame:IsShown()) or ns.Blizzard.ShownBaseProfession() ~= skillLine then
		if not C_TradeSkillUI.OpenTradeSkill(skillLine) then
			ns.Shopping.Say("Couldn't open that profession right now.")
			return
		end
	end
	local tries = 0
	local function try()
		tries = tries + 1
		if not ns.Blizzard.ShowsRecipeList() and ns.Blizzard.IsOwnProfession() then ns.Blizzard.ShowRecipesTab() end
		if ns.BestCraftsList.Show() or tries >= OPEN_TRIES then return end
		C_Timer.After(OPEN_RETRY, try)
	end
	C_Timer.After(0, try)
end

---------------------------------------------------------------------------
-- Clicks, menu and tooltip
---------------------------------------------------------------------------

-- Left-click: the Best crafts list of your last profession, or closes it when it's open.
local function toggleBestCrafts()
	if ns.BestCraftsList.IsShown() then
		ns.BestCraftsList.Hide()
		return
	end
	local profession = lastProfession()
	if not profession then
		ns.Options.Open()
		return
	end
	openBestCrafts(profession.skillLine)
end

local function openMenu()
	MenuUtil.CreateContextMenu(UIParent, function(_, root)
		root:CreateTitle("Craft Profit")
		for _, profession in ipairs(professions()) do
			root:CreateButton(format("|T%s:16|t %s: Best crafts", profession.icon, profession.name),
				function() openBestCrafts(profession.skillLine) end)
		end
		local strategies = root:CreateButton("Crafting strategy")
		for _, strategy in ipairs(ns.STRATEGIES) do
			local key = strategy[1]
			strategies:CreateRadio(strategy[2], function() return ns.db.craftStrategy == key end,
				function() ns.Options.Set("craftStrategy", key) end)
		end
		root:CreateDivider()
		root:CreateButton("Options", ns.Options.Open)
	end)
end

local function onClick(mouseButton)
	if mouseButton == "RightButton" then openMenu() else toggleBestCrafts() end
end

local function fillTooltip(tooltip)
	tooltip:SetText("Craft Profit")
	local session = ns.db.session
	if session.crafts > 0 then
		local luck = ns.Procs.LuckText()
		tooltip:AddDoubleLine(format("This session (%d craft%s)", session.crafts, session.crafts == 1 and "" or "s"),
			ns.Color(ns.AmountColor(session.total), ns.Format.Money(session.total)), 1, 1, 1)
		if luck then tooltip:AddLine(luck) end
	else
		tooltip:AddLine("Nothing crafted this session yet.", 1, 1, 1)
	end
	tooltip:AddLine(" ")
	local profession = lastProfession()
	tooltip:AddLine(profession and format("Click: %s's Best crafts", profession.name) or "Click: options", 0.6, 0.6, 0.6)
	tooltip:AddLine("Right-click: professions, crafting strategy, options", 0.6, 0.6, 0.6)
end

---------------------------------------------------------------------------
-- The button
---------------------------------------------------------------------------

-- Shows or hides the button, following the "Show minimap button" option.
function Button.Update()
	if not registered then return end
	if ns.db.minimap then LDBIcon:Show(NAME) else LDBIcon:Hide(NAME) end
end

function Button.Init()
	if registered then return end
	registered = true
	ns.db.minimapIcon = ns.db.minimapIcon or { minimapPos = START_POSITION }
	ns.db.minimapIcon.hide = not ns.db.minimap
	local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(NAME, {
		type = "launcher",
		label = "Craft Profit",
		icon = ICON,
		OnClick = function(_, mouseButton) onClick(mouseButton) end,
		OnTooltipShow = fillTooltip,
	})
	LDBIcon:Register(NAME, launcher, ns.db.minimapIcon)
end

-- Remembers the profession whose window you opened last, for the next click.
local events = CreateFrame("Frame")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:SetScript("OnEvent", function()
	if not ns.Blizzard.IsOwnProfession() then return end
	local skillLine = ns.Blizzard.ShownBaseProfession()
	if not skillLine then return end
	CraftProfitCharDB = CraftProfitCharDB or {}
	CraftProfitCharDB.lastProfession = skillLine
end)

-- Addon compartment (the addon menu on Retail's minimap), named in the .toc.
function CraftProfit_OnAddonCompartmentClick(_, mouseButton)
	onClick(mouseButton)
end

function CraftProfit_OnAddonCompartmentEnter(_, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	fillTooltip(GameTooltip)
	GameTooltip:Show()
end

function CraftProfit_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
