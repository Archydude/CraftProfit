-- What's New window, shared by all of Archdude's addons. After an addon updates, it shows the
-- changelog of every version the player hasn't seen yet; addons updated at the same time share
-- one window. A new install shows nothing.
--
-- Every addon ships the same copy of this file (the original is tools\WhatsNew.lua; build.ps1
-- copies it in) plus its own WhatsNewData.lua, which tools\whatsnew.ps1 writes from the addon's
-- CHANGELOG.md and which calls Register below. The highest REVISION to load takes over the shared
-- table, like LibStub, so raise it whenever this file changes.

local REVISION = 1

local lib = _G.ArchdudeWhatsNew
if lib and lib.revision >= REVISION then return end
lib = lib or { addons = {}, pending = {} }
lib.revision = REVISION
_G.ArchdudeWhatsNew = lib

local WIDTH, HEIGHT = 560, 460 -- the window shrinks to fit short changelogs, and scrolls past HEIGHT
local MIN_HEIGHT = 180
local INDENT = 16        -- bullet text, and each nesting level, sits this far in
local LINE_GAP = 4
local SECTION_GAP = 10
local ADDON_GAP = 18
local ICON_SIZE = 20
local NAV_ROW_HEIGHT = 20 -- the row of addon names, shown when the window has more than one
local NAV_GAP = 16
local GROUP_ICON = "Interface\\Icons\\INV_Scroll_03" -- the Retail portrait when several addons share the window
local SHOW_DELAY = 5     -- seconds after login, so the window doesn't open while the game is still loading

-- "1.20.1" is newer than "1.9.4": compares each number in turn.
local function isNewer(a, b)
	local pa, pb = {}, {}
	for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
	for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x > y end
	end
	return false
end

-- Called by each addon's WhatsNewData.lua while the addon loads. info holds:
--   title    the addon's name as players see it
--   icon     the addon's icon (its .toc IconTexture), or nil
--   version  the version being loaded
--   seen     the saved variable that keeps the last version the player was shown
--   saved    the addon's other saved variables; any of them existing means it was installed before
--   changes  { { "1.2.0", "line", "\tsub-line", ... }, ... }, newest first
function lib:Register(addon, info)
	self.addons[addon] = info
end

-- The versions to show for an addon that just loaded, newest first, or nil for none.
function lib:Unseen(info)
	local seen = _G[info.seen]
	if seen == nil then
		-- The first version with this window. It's an update when the addon has saved data from
		-- before; show this version's notes back to the last feature release, like the release notes.
		local installed = false
		for _, name in ipairs(info.saved) do
			if _G[name] ~= nil then installed = true end
		end
		local first = info.changes[1]
		if not installed or not first or first[1] ~= info.version then
			_G[info.seen] = info.version
			return nil
		end
	end

	local list = {}
	for _, entry in ipairs(info.changes) do
		local version = entry[1]
		if seen then
			if not isNewer(version, seen) then break end
		end
		list[#list + 1] = entry
		if not seen and version:match("^%d+%.%d+%.0$") then break end
	end
	if #list == 0 then return nil end
	return list
end

function lib:OnEvent(event, arg)
	if event == "ADDON_LOADED" then
		local info = self.addons[arg]
		if not info then return end
		local list = self:Unseen(info)
		if list then
			self.pending[#self.pending + 1] = { info = info, list = list }
			if IsLoggedIn() then self:Schedule() end
		end
	else -- PLAYER_LOGIN, or PLAYER_REGEN_ENABLED after waiting out a fight
		self:Schedule()
	end
end

function lib:Schedule()
	if self.scheduled or #self.pending == 0 then return end
	self.scheduled = true
	C_Timer.After(SHOW_DELAY, function()
		lib.scheduled = false
		if InCombatLockdown() then
			lib.events:RegisterEvent("PLAYER_REGEN_ENABLED")
			return
		end
		lib.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
		lib:Show()
	end)
end

lib.events = lib.events or CreateFrame("Frame")
lib.events:RegisterEvent("ADDON_LOADED")
lib.events:RegisterEvent("PLAYER_LOGIN")
lib.events:SetScript("OnEvent", function(_, event, arg) lib:OnEvent(event, arg) end)

-- Window --------------------------------------------------------------------------------------
-- Retail gets the game's current look: a portrait frame with the addon's icon and the thin scroll
-- bar. The Classic flavors keep the plain frame their own windows use.

local MODERN = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar

local function makeMovable(f)
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	tinsert(UISpecialFrames, "ArchdudeWhatsNewFrame") -- Esc closes it
end

local function makeCloseButton(f, ...)
	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(100, 22)
	close:SetPoint(...)
	close:SetText("Close")
	close:SetScript("OnClick", function() f:Hide() end)
end

-- Each window style sets textWidth (the changes' width), linkX, linkY and linkWidth (where the row
-- of addon names goes), SetHeader(title, icon, single) and PlaceContent(linksHeight, textHeight),
-- which also fits the window's height to the text, up to HEIGHT.
local function fitHeight(f, chrome, textHeight)
	f:SetHeight(math.max(MIN_HEIGHT, math.min(HEIGHT, chrome + textHeight)))
end

local function hasTemplate(name)
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

local function createModern()
	-- The flat dark panel of the game's newer windows; without it, the textured frame minus its
	-- stone inset.
	local template = hasTemplate("PortraitFrameFlatTemplate") and "PortraitFrameFlatTemplate" or "ButtonFrameTemplate"
	local f = CreateFrame("Frame", "ArchdudeWhatsNewFrame", UIParent, template)
	makeMovable(f)
	makeCloseButton(f, "BOTTOMRIGHT", -8, 6)
	if f.Inset then f.Inset:Hide() end

	-- The changes sit on a slightly darker panel, with a thin line along its top.
	f.body = CreateFrame("Frame", nil, f)
	local shade = f.body:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.3)
	local line = f.body:CreateTexture(nil, "BORDER")
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	line:SetHeight(1)
	line:SetColorTexture(1, 1, 1, 0.12)

	-- Under the title, beside the portrait: the row of addon names, or this line for one addon.
	f.linkX, f.linkY, f.linkWidth = 64, -32, WIDTH - 64 - 12
	f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.subtitle:SetPoint("TOPLEFT", f.linkX, f.linkY - 4)
	f.subtitle:SetText("Here's what changed since the version you had.")

	f.scroll = CreateFrame("ScrollFrame", nil, f.body)
	f.scroll:SetPoint("TOPLEFT", 12, -12)
	f.scroll:SetPoint("BOTTOMRIGHT", -26, 12)
	local bar = CreateFrame("EventFrame", nil, f.body, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", f.scroll, "TOPRIGHT", 8, 0)
	bar:SetPoint("BOTTOMLEFT", f.scroll, "BOTTOMRIGHT", 8, 0)
	ScrollUtil.InitScrollFrameWithScrollBar(f.scroll, bar)
	bar:SetHideIfUnscrollable(true)
	f.scroll:EnableMouseWheel(true)
	f.textWidth = WIDTH - 4 - 4 - 12 - 26

	function f:SetHeader(title, icon, single)
		self:SetTitle(title)
		if self.SetPortraitToAsset then self:SetPortraitToAsset(icon or GROUP_ICON) end
		self.subtitle:SetShown(single)
	end
	function f:PlaceContent(linksHeight, textHeight)
		local top = math.max(60, -self.linkY + linksHeight + 6)
		self.body:ClearAllPoints()
		self.body:SetPoint("TOPLEFT", 4, -top)
		self.body:SetPoint("BOTTOMRIGHT", -4, 34)
		fitHeight(self, top + 12 + 12 + 34, textHeight)
	end
	return f
end

local function createClassic()
	local PADDING, SCROLLBAR_WIDTH, TOP = 14, 22, -32
	local f = CreateFrame("Frame", "ArchdudeWhatsNewFrame", UIParent, "BasicFrameTemplateWithInset")
	makeMovable(f)
	makeCloseButton(f, "BOTTOM", 0, 12)

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.title:SetPoint("TOP", 0, -5)

	f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	f.scroll:SetPoint("BOTTOMRIGHT", -(PADDING + SCROLLBAR_WIDTH), 44)
	f.textWidth = WIDTH - 2 * PADDING - SCROLLBAR_WIDTH
	f.linkX, f.linkY, f.linkWidth = PADDING, TOP, WIDTH - 2 * PADDING

	function f:SetHeader(title)
		self.title:SetText(title)
	end
	function f:PlaceContent(linksHeight, textHeight)
		local top = -TOP + (linksHeight > 0 and linksHeight + 8 or 0)
		self.scroll:SetPoint("TOPLEFT", PADDING, -top)
		fitHeight(self, top + 44 + 8, textHeight)
	end
	return f
end

function lib:CreateWindow()
	local f = MODERN and createModern() or createClassic()
	f.child = CreateFrame("Frame", nil, f.scroll)
	f.child:SetSize(f.textWidth, 1)
	f.scroll:SetScrollChild(f.child)
	f.strings, f.icons, f.links = {}, {}, {}
	return f
end

-- The row of addon names over the changes: clicking one scrolls to that addon. Wraps onto more
-- rows when the names don't fit on one. Returns its height.
local function layoutLinks(f, pending, tops)
	local x, rows = 0, 1
	for i, entry in ipairs(pending) do
		local link = f.links[i]
		if not link then
			link = CreateFrame("Button", nil, f)
			link:SetNormalFontObject("GameFontNormal")
			link:SetHighlightFontObject("GameFontHighlight")
			f.links[i] = link
		end
		link:SetText(entry.info.title)
		local w = link:GetFontString():GetStringWidth()
		if x > 0 and x + w > f.linkWidth then x, rows = 0, rows + 1 end
		link:SetSize(w, NAV_ROW_HEIGHT)
		link:ClearAllPoints()
		link:SetPoint("TOPLEFT", f.linkX + x, f.linkY - (rows - 1) * NAV_ROW_HEIGHT)
		link:SetScript("OnClick", function()
			f.scroll:SetVerticalScroll(math.min(tops[i], f.scroll:GetVerticalScrollRange()))
		end)
		link:Show()
		x = x + w + NAV_GAP
	end
	return rows * NAV_ROW_HEIGHT
end

-- Lays out every pending addon's changes in the window and opens it.
function lib:Show()
	local f = self.window or self:CreateWindow()
	self.window = f
	local pending = self.pending
	local width = f.textWidth

	local used = 0
	local function text(font, x, y, w, value)
		used = used + 1
		local fs = f.strings[used]
		if not fs then
			fs = f.child:CreateFontString(nil, "OVERLAY")
			fs:SetJustifyH("LEFT")
			fs:SetJustifyV("TOP")
			f.strings[used] = fs
		end
		fs:SetFontObject(font)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", x, y)
		fs:SetWidth(w)
		fs:SetText(value)
		fs:Show()
		return fs:GetStringHeight()
	end

	table.sort(pending, function(a, b) return a.info.title < b.info.title end)
	local single = #pending == 1
	local y, tops = 0, {}
	for i, entry in ipairs(pending) do
		local info, list = entry.info, entry.list
		if i > 1 then y = y - ADDON_GAP end
		tops[i] = -y

		-- Heading: the addon's icon, its name, and the version when there's only one. A window for
		-- one addon has its name in the title already, so it goes straight to the versions.
		local headed = not single
		if headed then
			local x = 0
			local icon = f.icons[i]
			if not icon then
				icon = f.child:CreateTexture(nil, "ARTWORK")
				icon:SetSize(ICON_SIZE, ICON_SIZE)
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trims the icon's dark border
				f.icons[i] = icon
			end
			icon:SetShown(info.icon ~= nil)
			if info.icon then
				icon:SetTexture(info.icon)
				icon:ClearAllPoints()
				icon:SetPoint("TOPLEFT", 0, y)
				x = ICON_SIZE + 6
			end
			local heading = #list == 1 and (info.title .. " " .. list[1][1]) or info.title
			local height = text("GameFontNormalLarge", x, y - 2, width - x, heading) + 2
			y = y - math.max(height, info.icon and ICON_SIZE or 0) - SECTION_GAP
		end

		for v, changes in ipairs(list) do
			if #list > 1 or not headed then
				if v > 1 then y = y - SECTION_GAP end
				y = y - text("GameFontNormal", 0, y, width, changes[1]) - LINE_GAP
			end
			for c = 2, #changes do
				local depth = changes[c]:match("^\t*"):len()
				local indent = depth * INDENT
				text("GameFontHighlight", indent, y, INDENT, depth > 0 and "-" or "•")
				y = y - text("GameFontHighlight", indent + INDENT, y, width - indent - INDENT, changes[c]:sub(depth + 1)) - LINE_GAP
			end
		end
		_G[info.seen] = info.version
	end
	for i = used + 1, #f.strings do f.strings[i]:Hide() end
	for i = (single and 0 or #pending) + 1, #f.icons do f.icons[i]:Hide() end

	-- One addon: its name in the title. Several: a count in the title and a row of their names.
	local links = 0
	if single then
		f:SetHeader(pending[1].info.title .. ": What's New", pending[1].info.icon, true)
	else
		f:SetHeader("What's New in " .. #pending .. " addons", nil, false)
		links = layoutLinks(f, pending, tops)
	end
	for i = (single and 0 or #pending) + 1, #f.links do f.links[i]:Hide() end
	f:PlaceContent(links, -y)

	wipe(pending)
	f.child:SetHeight(math.max(1, -y))
	f.scroll:SetVerticalScroll(0)
	f:Show()
end
