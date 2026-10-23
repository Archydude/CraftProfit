-- Craft Profit: reminders to scan the auction house when prices come from
-- Auctionator and its last scan is old. A chat line when you open the auction
-- house, and a notice over the Best crafts list when you open it with very old
-- prices (BestCraftsList.lua draws it). The panel's and the list's footers show
-- the scan's age too.
local _, ns = ...

local Reminder = {}
ns.Reminder = Reminder

local format = string.format

-- Days after which the last scan is old: the chat reminder and red footers.
Reminder.OLD_DAYS = 1
-- Days after which opening the Best crafts list shows a notice.
local NOTICE_DAYS = 3

local noticed = false -- the notice shows once a session

-- Whether Auctionator's last scan is at least `days` old (or never happened).
function Reminder.IsOld(days)
	local age = ns.Prices.ScanAge()
	if age == nil then return false end
	return age == false or age >= days
end

-- ", last scan 2 days ago" in red for a footer, or "" when the scan is recent.
function Reminder.FooterText()
	if not Reminder.IsOld(Reminder.OLD_DAYS) then return "" end
	return ns.Color("warning", ", last scan " .. ns.Prices.ScanAgeText(ns.Prices.ScanAge()))
end

local function ageWords()
	local age = ns.Prices.ScanAge()
	if age == false then return "Auctionator hasn't scanned the auction house yet" end
	return format("Auctionator's prices are from %s", ns.Prices.ScanAgeText(age))
end

-- When the Best crafts list opens: the notice's text if prices are very old,
-- once a session, or nil.
function Reminder.BestCraftsNotice()
	if noticed or not ns.db.scanReminder or not Reminder.IsOld(NOTICE_DAYS) then return end
	noticed = true
	return ageWords() .. ".\n\nThe profits in Best crafts may be far off. Run a full scan with Auctionator the "
		.. "next time you're at the auction house."
end

-- At the auction house: a chat line if prices are old.
local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent", function()
	if not (ns.db and ns.db.scanReminder) or not Reminder.IsOld(Reminder.OLD_DAYS) then return end
	ns.Shopping.Say(ageWords() .. ": run a full scan so your profits are right.")
end)
