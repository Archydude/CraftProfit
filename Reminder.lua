-- Craft Profit: reminders to scan the auction house when prices come from
-- Auctionator or Craft Profit's own scan and the last scan is old, or to log in
-- on a character with TSM when prices come from its old save (see SavedPrices.lua). A chat line when you open
-- the auction house, and a notice over the Best crafts list when you open it with
-- very old prices (BestCraftsList.lua draws it). The panel's and the list's
-- footers show the age too.
local _, ns = ...

local Reminder = {}
ns.Reminder = Reminder

local format = string.format

-- Days after which the prices are old: the chat reminder and red footers.
Reminder.OLD_DAYS = 1
-- Days after which opening the Best crafts list shows a notice.
local NOTICE_DAYS = 3

local noticed = false -- the notice shows once a session

-- How old the prices are in days (false: Auctionator never scanned), and the
-- name of the character whose saved TSM prices they are, when they are. Nil when
-- neither Auctionator nor a save prices here.
local function priceAge()
	local age, name = ns.Prices.SavedAge()
	if age then return age, name end
	return ns.Prices.ScanAge()
end

-- Whether the prices are at least `days` old (or Auctionator never scanned).
function Reminder.IsOld(days)
	local age = priceAge()
	if age == nil then return false end
	return age == false or age >= days
end

-- ", last scan 2 days ago" (or ", saved 2 days ago") in red for a footer, or ""
-- when the prices are recent.
function Reminder.FooterText()
	if not Reminder.IsOld(Reminder.OLD_DAYS) then return "" end
	local age, name = priceAge()
	if name then return ns.Color("warning", ", saved " .. ns.Prices.AgeText(age)) end
	-- Craft Profit's scan that never ran: the footer already says there are no prices yet.
	if age == false and ns.Prices.Scanner() == "own" then return "" end
	return ns.Color("warning", ", last scan " .. ns.Prices.ScanAgeText(age))
end

local function ageWords()
	local age, name = priceAge()
	if name then return format("%s's TSM prices are from %s", name, ns.Prices.AgeText(age)) end
	local who = ns.Prices.Scanner() == "own" and "Craft Profit" or "Auctionator"
	if age == false then return who .. " hasn't scanned the auction house yet" end
	return format("%s's prices are from %s", who, ns.Prices.ScanAgeText(age))
end

-- What to do about old prices, after ageWords.
local function fix()
	local _, name = priceAge()
	if name then return format("Log in on %s, or another character with TSM, to update them.", name) end
	if ns.Prices.Scanner() == "own" then
		return "Scan from the Prices tab of Craft Profit's window the next time you're at the auction house."
	end
	return "Run a full scan with Auctionator the next time you're at the auction house."
end

-- When the Best crafts list opens: the notice's text if prices are very old,
-- once a session, or nil.
function Reminder.BestCraftsNotice()
	if noticed or not ns.db.scanReminder or not Reminder.IsOld(NOTICE_DAYS) then return end
	noticed = true
	return ageWords() .. ".\n\nThe profits in Best crafts may be far off. " .. fix()
end

-- At the auction house: a chat line if prices are old.
local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent", function()
	if not (ns.db and ns.db.scanReminder) or not Reminder.IsOld(Reminder.OLD_DAYS) then return end
	local _, name = priceAge()
	local own = not name and ns.Prices.Scanner() == "own"
	-- Craft Profit's own scan is about to start by itself: nothing to remind you of.
	if own and ns.db.autoScan then return end
	ns.Shopping.Say(ageWords() .. (name and format(": log in on %s to update them.", name)
		or own and ": scan from the Prices tab (/craftprofit prices) so your profits are right."
		or ": run a full scan so your profits are right."))
end)
