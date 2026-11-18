-- Craftonomics was called Craft Profit up to 4.8. This carries a player's saved
-- settings and history over from that name, and deals with an old copy that's
-- still installed.
--
-- The game keeps saved data per addon folder, so the new folder starts with
-- none. Two ways the old data can still be in reach:
--   * the bridge: the Retail download ships a "CraftProfit" folder with nothing
--     in it but the old saved variables' names. It loads first (it's in the
--     .toc's OptionalDeps), so the game loads the old saved file.
--   * the old addon itself, left installed next to this one.
-- Either way the old tables are taken over right here, while this file loads:
-- that's before the game loads Craftonomics' own saved file, which replaces
-- them again once there is one, and before the What's New window looks for a
-- saved version (it would take an empty one for a new install).
--
-- Other addons use the folder name CraftProfit too (on WoW Forever), with saved
-- tables of the same names. Only a folder with this project's ID counts.
local _, ns = ...

local Rename = {}
ns.Rename = Rename

local OLD_FOLDER = "CraftProfit"
local PROJECT_ID = "1723749" -- X-Curse-Project-ID in both .toc files
local NAMES = { -- old saved variable -> new
	CraftProfitDB = "CraftonomicsDB",
	CraftProfitCharDB = "CraftonomicsCharDB",
	CraftProfitWhatsNew = "CraftonomicsWhatsNew",
}

-- "bridge", "addon" (the old Craft Profit, still running) or nil.
local function oldCopy()
	if not C_AddOns.IsAddOnLoaded(OLD_FOLDER) then return nil end
	if C_AddOns.GetAddOnMetadata(OLD_FOLDER, "X-Curse-Project-ID") ~= PROJECT_ID then return nil end
	return C_AddOns.GetAddOnMetadata(OLD_FOLDER, "X-Craftonomics-Bridge") and "bridge" or "addon"
end

local kind = oldCopy()
local taken = {} -- old name -> the value taken over
if kind then
	for old, new in pairs(NAMES) do
		if _G[old] ~= nil then
			_G[new] = _G[old]
			taken[old] = _G[old]
		end
	end
end

StaticPopupDialogs["CRAFTONOMICS_OLD_COPY"] = {
	text = "Craft Profit is now called Craftonomics. Your settings and history came along.\n\n"
		.. "The old Craft Profit was still installed, and is now turned off. Reload to finish.",
	button1 = "Reload",
	button2 = "Later",
	OnAccept = ReloadUI,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_LOGIN")
	local db = CraftonomicsDB
	-- Whether the settings in use are the ones taken over: not when Craftonomics
	-- already had a saved file of its own.
	local carried = taken.CraftProfitDB ~= nil and db == taken.CraftProfitDB

	if kind == "bridge" then
		-- What was taken over is saved under the new names from here on; the old
		-- names are emptied so the bridge has nothing left to hand over. A
		-- character's own data moves the first time that character logs in.
		for old, new in pairs(NAMES) do
			local value = taken[old]
			if value ~= nil and (type(value) ~= "table" or _G[new] == value) then _G[old] = nil end
		end
	elseif kind == "addon" then
		-- Two copies running: turn the old one off for good and ask for a reload.
		C_AddOns.DisableAddOn(OLD_FOLDER)
		if C_AddOns.SaveAddOns then C_AddOns.SaveAddOns() end
		StaticPopup_Show("CRAFTONOMICS_OLD_COPY")
	end

	if not db or db.renameNoted then return end
	db.renameNoted = true
	if carried then
		if kind == "bridge" then
			ns.Shopping.Say("Craft Profit is now called Craftonomics. Your settings and history came along. "
				.. "Type /craftonomics for options.")
		end
	elseif db.renameFresh and not ns.QUALITY_CRAFTING then
		-- WoW Forever has no bridge, so an update from Craft Profit looks like a new install.
		ns.Shopping.Say("Craftonomics is Craft Profit's new name. If you used Craft Profit on WoW Forever, "
			.. "your settings and history start fresh under the new name.")
	end
	db.renameFresh = nil
end)

-- Called from Core.lua before the saved settings get their defaults: notes
-- whether this is the first time Craftonomics runs on this account.
function Rename.BeforeDefaults()
	if CraftonomicsDB == nil then
		CraftonomicsDB = { renameFresh = true }
	end
end
