-- Craft Profit: the Prices tab of its auction house window (see
-- ShoppingList.lua): where your prices come from, when the auction house was
-- last scanned, and the button that scans it (the scan itself is in PriceScan.lua).
local _, ns = ...

local PricesTab = {}
ns.PricesTab = PricesTab

local format = string.format
local Color = ns.Color

local PAD = 16          -- window edge to the text
local TOP = 40          -- under the title bar
local GAP = 14          -- between the tab's parts
local BUTTON_WIDTH, BUTTON_HEIGHT = 170, 26
local CHECK_SIZE = 26
local LABEL_GAP = 2     -- checkbox to its label

local HELP_TEXT = "A scan reads the lowest price of everything on the auction house, and how many are up.\n\n"
	.. "Craft Profit prices your materials and crafts with it when neither TSM nor Auctionator does, or when "
	.. "you pick it as the Price addon in the options.\n\n"
	.. "A scan can take a few minutes on a busy auction house, and you can keep buying and selling while it "
	.. "runs. What vendors sell is learned as you visit them."

local panel, sourceText, lastText, scanButton, progressText, autoCheck

-- "just now", "12 minutes ago", "3 hours ago", "2 days ago".
local function ago(seconds)
	if seconds < 60 then return "just now" end
	if seconds < 3600 then
		local minutes = math.floor(seconds / 60)
		return minutes == 1 and "a minute ago" or format("%d minutes ago", minutes)
	end
	if seconds < 86400 then
		local hours = math.floor(seconds / 3600)
		return hours == 1 and "an hour ago" or format("%d hours ago", hours)
	end
	local days = math.floor(seconds / 86400)
	return days == 1 and "yesterday" or format("%d days ago", days)
end

local function refresh()
	if not (panel and panel:IsVisible()) then return end
	local scanner = ns.Prices.Scanner()
	local source = "Your prices come from: " .. ns.Prices.SourceLabel() .. "."
	if scanner ~= "own" then
		source = source .. Color("muted", "\nCraft Profit's scan only prices what that has no price for.")
	end
	sourceText:SetText(source)

	local seconds = ns.PriceScan.Seconds()
	lastText:SetText(seconds and format("Last scan: %s, %s items.", ago(seconds), BreakUpLargeNumbers(ns.PriceScan.Count()))
		or "The auction house hasn't been scanned yet.")

	local state, message = ns.PriceScan.State()
	local open = ns.AuctionSearch.IsOpen()
	scanButton:SetText(state and "Stop" or "Scan now")
	scanButton:SetEnabled(state ~= nil or open)
	if state then
		progressText:SetText(format("Scanning... %s items so far.", BreakUpLargeNumbers(state.items)))
	elseif not open then
		progressText:SetText(Color("muted", "Open the auction house to scan."))
	else
		progressText:SetText(message or "")
	end
	autoCheck:SetChecked(ns.db.autoScan)
end

-- Makes the tab's frame inside the window. Called once, the first time the tab
-- is opened.
function PricesTab.Create(parent, width)
	panel = CreateFrame("Frame", nil, parent)
	panel:SetAllPoints()
	panel:Hide()

	local function text(below, gap)
		local fontString = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		if below then
			fontString:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -gap)
		else
			fontString:SetPoint("TOPLEFT", PAD, -TOP)
		end
		fontString:SetWidth(width - 2 * PAD)
		fontString:SetJustifyH("LEFT")
		return fontString
	end

	sourceText = text()
	lastText = text(sourceText, GAP)

	scanButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	scanButton:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
	scanButton:SetPoint("TOPLEFT", lastText, "BOTTOMLEFT", 0, -GAP)
	scanButton:SetScript("OnClick", function()
		if ns.PriceScan.State() then
			ns.PriceScan.Stop()
		else
			local started, problem = ns.PriceScan.Start()
			if not started then progressText:SetText(Color("warning", problem)) end
		end
	end)
	progressText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	progressText:SetPoint("TOPLEFT", scanButton, "BOTTOMLEFT", 0, -8)
	progressText:SetWidth(width - 2 * PAD)
	progressText:SetJustifyH("LEFT")
	progressText:SetJustifyV("TOP")
	progressText:SetHeight(34) -- two lines, so what's under it doesn't move

	autoCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	autoCheck:SetSize(CHECK_SIZE, CHECK_SIZE)
	autoCheck:SetPoint("TOPLEFT", progressText, "BOTTOMLEFT", -4, -GAP)
	local label = autoCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", autoCheck, "RIGHT", LABEL_GAP, 0)
	label:SetText("Scan when I open the auction house")
	-- The label is clickable too, like Blizzard's.
	autoCheck:SetHitRectInsets(0, -(label:GetStringWidth() + LABEL_GAP), 0, 0)
	autoCheck:SetScript("OnClick", function(self) ns.Options.Set("autoScan", self:GetChecked()) end)
	autoCheck:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Scan when I open the auction house", 1, 1, 1)
		GameTooltip:AddLine("Only while your prices come from Craft Profit's scan, and at most once an hour.",
			nil, nil, nil, true)
		GameTooltip:Show()
	end)
	autoCheck:SetScript("OnLeave", GameTooltip_Hide)

	local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	help:SetPoint("TOPLEFT", autoCheck, "BOTTOMLEFT", 4, -GAP)
	help:SetWidth(width - 2 * PAD)
	help:SetJustifyH("LEFT")
	help:SetText(Color("muted", HELP_TEXT))

	panel:SetScript("OnShow", refresh)
	ns.PriceScan.Watch(refresh)
	return panel
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent", function()
	-- A moment later, once the auction house is known to be open or closed.
	C_Timer.After(0, refresh)
end)
