-- Craftonomics: what one craft makes, on each recipe's row of the profession
-- window's own recipe list. The number is the Best crafts list's (see
-- BestCrafts.RowOf): at the rank and with the materials the crafting strategy
-- picks, so only recipes you know have one.
local _, ns = ...

local RecipeProfit = {}
ns.RecipeProfit = RecipeProfit

local Color, Money = ns.Color, ns.Format.Money

local GAP = 6             -- between a recipe's name and its profit
local RIGHT_PAD = 4       -- the profit to the row's right edge
local LABEL_PAD = 10      -- what the game keeps free next to a recipe's name
local MIN_NAME_WIDTH = 60 -- a row whose name would get narrower than this shows no profit
local REFRESH_DELAY = 0.3 -- redraws are batched this long
local SCAN_DELAY = 0.3    -- a profession that just showed is scanned after this long
local GOLD = 10000        -- copper

local scrollBox       -- the game's recipe list
local texts = {}      -- recipe row (the game's frame) -> our text on it
local narrowed = {}   -- rows whose name we made room next to
local refreshQueued, scanQueued = false, false
local stale = false   -- the window was closed since the prices were asked for

local function enabled()
	return ns.db.listProfit
end

-- Whether the profits can show now: your own profession's recipe list.
local function wanted()
	return enabled() and scrollBox ~= nil and scrollBox:IsVisible() and ns.Blizzard.IsOwnProfession()
end

-- The profit as a row shows it: in whole gold from 1 gold up where prices are
-- big, green or red. Grey with a "?" when a material has no price, since the
-- profit is too high then. Nil without a price for what the recipe makes.
local function profitText(row)
	local profit = ns.db.countProcs and row.expected or row.profit
	if not profit then return end
	if ns.QUALITY_CRAFTING and math.abs(profit) >= GOLD then profit = math.floor(profit / GOLD + 0.5) * GOLD end
	local text = (profit > 0 and "+" or "") .. Money(profit)
	if row.unpriced > 0 then return Color("muted", text .. "?") end
	return Color(ns.AmountColor(profit), text)
end

-- Sets how wide a row's name is, as the game does when it fills the row in, with
-- `taken` more kept free on the right. False when that leaves the name too little.
local function fitName(frame, taken)
	local label, width = frame.Label, frame:GetWidth()
	local locked = frame.LockedIcon:IsShown() and frame.LockedIcon:GetWidth() or 0
	local count = frame.Count:IsShown() and frame.Count:GetStringWidth() or 0
	local room = width - (locked + count + LABEL_PAD + frame.SkillUps:GetWidth() + taken)
	if taken > 0 and room < MIN_NAME_WIDTH then return false end
	label:SetWidth(width)
	label:SetWidth(math.min(room, label:GetStringWidth()))
	return true
end

-- A row's recipe, as the game shows it there: the highest rank you know of a
-- recipe that has ranks. Nil for a row that isn't a recipe's.
local function recipeOf(frame)
	local node = frame.GetElementData and frame:GetElementData()
	local data = node and node.GetData and node:GetData()
	local info = data and data.recipeInfo
	if not info then return end
	local highest = Professions and Professions.GetHighestLearnedRecipe and Professions.GetHighestLearnedRecipe(info)
	return highest or info
end

local function scanSoon()
	if scanQueued then return end
	scanQueued = true
	C_Timer.After(SCAN_DELAY, function()
		scanQueued = false
		if wanted() then ns.BestCrafts.Ensure() end
	end)
end

local function textOn(frame)
	local text = texts[frame]
	if not text then
		-- The font of the row's name, where the game has it.
		text = frame:CreateFontString(nil, "OVERLAY",
			GameFontHighlight_NoShadow and "GameFontHighlight_NoShadow" or "GameFontHighlight")
		text:SetDrawLayer("OVERLAY", 1) -- with the row's name, under its highlight
		text:SetJustifyH("RIGHT")
		text:SetWordWrap(false)
		texts[frame] = text
	end
	return text
end

-- Takes a row's profit off, and gives its name the room back.
local function clearRow(frame)
	local text = texts[frame]
	if text then text:Hide() end
	if narrowed[frame] then
		narrowed[frame] = nil
		fitName(frame, 0)
	end
end

-- Draws one row of the recipe list: its profit at the right, the name cut short
-- before it.
local function drawRow(frame)
	-- Only recipe rows have these; categories and dividers don't.
	if not (type(frame) == "table" and frame.Label and frame.Count and frame.LockedIcon and frame.SkillUps) then return end
	local info = recipeOf(frame)
	if not (info and wanted()) then return clearRow(frame) end
	local row = ns.BestCrafts.RowOf(info.recipeID)
	if not row then
		scanSoon()
		return clearRow(frame)
	end
	local shown = profitText(row)
	if not shown then return clearRow(frame) end
	local text = textOn(frame)
	text:SetText(shown)
	if not fitName(frame, text:GetStringWidth() + GAP) then return clearRow(frame) end
	narrowed[frame] = true
	local locked = frame.LockedIcon:IsShown() and frame.LockedIcon:GetWidth() or 0
	text:ClearAllPoints()
	text:SetPoint("RIGHT", frame, "RIGHT", -(RIGHT_PAD + locked), 0)
	text:Show()
end

function RecipeProfit.Render()
	refreshQueued = false
	if not (scrollBox and scrollBox:IsVisible()) then return end
	-- A window opened again asks the price addons again.
	if stale and wanted() then
		stale = false
		ns.BestCrafts.Reprice(true)
	end
	scrollBox:ForEachFrame(drawRow)
end

-- Redraws once shortly, however many times it's called.
function RecipeProfit.Refresh()
	if refreshQueued or not (scrollBox and scrollBox:IsVisible()) then return end
	refreshQueued = true
	C_Timer.After(REFRESH_DELAY, RecipeProfit.Render)
end

-- The game filled a row in. The row is the first frame among what it passes.
local function onRowFilled(...)
	for i = 1, select("#", ...) do
		local arg = select(i, ...)
		if type(arg) == "table" and arg.GetElementData and arg.GetObjectType then return drawRow(arg) end
	end
end

-- Follows the game's recipe list. Safe to call more than once.
function RecipeProfit.Init()
	if scrollBox or not ns.Blizzard.IsLoaded() then return end
	local event = ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnInitializedFrame
	local list = ns.Blizzard.RecipeList()
	if not (event and list and list.ScrollBox and list.ScrollBox.RegisterCallback) then return end
	scrollBox = list.ScrollBox
	scrollBox:RegisterCallback(event, onRowFilled, RecipeProfit)
	scrollBox:HookScript("OnShow", RecipeProfit.Refresh)
	ns.BestCrafts.Watch(RecipeProfit.Refresh, wanted)
	ns.Blizzard.WatchWindowClosed(function() stale = true end)

	-- What you own changes which materials a craft uses.
	local events = CreateFrame("Frame")
	events:RegisterEvent("BAG_UPDATE_DELAYED")
	events:SetScript("OnEvent", RecipeProfit.Refresh)
	RecipeProfit.Refresh()
end
