-- Craftonomics: the All recipes window's heatmap. The items the window's recipes
-- make, or the materials they take, as tiles. A tile's size is the gold of the
-- item sold in a day (TSM's sold per day times its market value), and its color
-- is TSM's trend (its market value against its historical price): red for below,
-- green for above. Tiles sit in groups: a profession's items, or a kind of
-- material. A click on a group shows only that group, a right-click goes back.
local _, ns = ...

local Heatmap = {}
ns.Heatmap = Heatmap

local Color, Money = ns.Color, ns.Format.Money
local format = string.format

local BAR_HEIGHT = 26       -- the line above the map: where you are, and what the colors mean
local HEADER_HEIGHT = 18    -- a group's name above its tiles
local HEADER_MIN_WIDTH = 60 -- a group narrower than this has no name above it
local GAP = 1               -- between tiles
local MIN_TILE_AREA = 256   -- an item whose tile would be smaller than 16 by 16 joins its group's "more" tile
local MAX_TILES = 60        -- how many tiles a group gets among the other groups,
local MAX_TILES_ALONE = 500 -- and shown alone
local NAME_MAX_LINES = 3    -- how many lines a tile's name can take
-- A tile's texts come in three sizes: the game's font for it, how high a line of
-- it is, and how wide a tile has to be to show a name in it. The small one is 10
-- high, under the addons' usual 12: the author's choice for these tiles (2026-11-20).
local FONT_BIG = { object = "GameFontHighlightLarge", line = 18, nameWidth = 40 }
local FONT_NORMAL = { object = "GameFontHighlight", line = 13, nameWidth = 40 }
local FONT_SMALL = { object = "GameFontHighlightSmall", line = 11, nameWidth = 34 }
local FULL_TREND = 50      -- the trend, in percent, from where the color is at its strongest
local KEY_STEPS = { -50, -25, 0, 25, 50 } -- the trends the colors' key shows
local KEY_WIDTH, KEY_HEIGHT = 18, 12
local BACK_WIDTH = 64
local CLICK_HINT = "Click a group to see only its items."
-- The colors a trend runs through: red at -50% or less, grey-blue at 0%, green at +50% or more.
local FALLING, FLAT, RISING = { 0.80, 0.20, 0.20 }, { 0.20, 0.22, 0.27 }, { 0.20, 0.72, 0.28 }

local frame, map, backButton, where
local changed          -- called when a click changes what the map shows
local mapWidth, mapHeight
local tiles, headers = {}, {} -- the tiles' and the groups' names' buttons, reused
local kind             -- "crafted" or "materials": what the map last showed
local zoom             -- the name of the group shown alone, or nil for all of them
-- Shown alone, a group's "more" tile opens on the items it stands for: how many of
-- the group's biggest are left out, for each time one was opened.
local skips = {}
local hovered          -- the tile or group name whose tooltip shows

---------------------------------------------------------------------------
-- Where the tiles go. This part only works with numbers: nothing of the game's.
---------------------------------------------------------------------------

-- How far from square the worst tile of a row is, for a row of tiles whose areas
-- add up to `sum`, the smallest `least` and the biggest `most`, along a side `side` long.
local function worst(sum, least, most, side)
	local sumSq, sideSq = sum * sum, side * side
	return math.max(sideSq * most / sumSq, sumSq / (sideSq * least))
end

-- Gives every entry of `list` (heaviest first) a left, top, width and height
-- inside the box, its area by its weight, as close to square as they come.
local function squarify(list, left, top, width, height)
	local total = 0
	for _, entry in ipairs(list) do total = total + entry.weight end
	if total <= 0 or width < 1 or height < 1 then return end
	local scale = width * height / total
	local first, count = 1, #list
	while first <= count do
		local side = math.min(width, height)
		if side <= 0 then return end
		-- The row takes entries for as long as that makes its tiles more square.
		local area = list[first].weight * scale
		local sum, least, most, last = area, area, area, first
		local ratio = worst(sum, least, most, side)
		while last < count do
			area = list[last + 1].weight * scale
			local nextRatio = worst(sum + area, math.min(least, area), math.max(most, area), side)
			if nextRatio > ratio then break end
			sum, least, most = sum + area, math.min(least, area), math.max(most, area)
			ratio, last = nextRatio, last + 1
		end
		-- It goes along the box's short side, and the rest of the box is what's left.
		local thick, along = sum / side, 0
		local upright = width >= height
		for index = first, last do
			local entry = list[index]
			local length = entry.weight * scale / thick
			if upright then
				entry.left, entry.top, entry.width, entry.height = left, top + along, thick, length
			else
				entry.left, entry.top, entry.width, entry.height = left + along, top, length, thick
			end
			along = along + length
		end
		if upright then
			left, width = left + thick, width - thick
		else
			top, height = top + thick, height - thick
		end
		first = last + 1
	end
end

-- How many of `items` (heaviest first, from the one after `skip`) get a tile of
-- their own in a box of `area`: the ones big enough, up to `most`. The rest share
-- one tile, so never just one of them.
local function ownTiles(items, skip, area, most)
	local total = 0
	for index = skip + 1, #items do total = total + items[index].weight end
	local count = 0
	for index = skip + 1, #items do
		if count >= most or items[index].weight / total * area < MIN_TILE_AREA then break end
		count = count + 1
	end
	if count == #items - skip - 1 then count = count + 1 end
	return count
end

---------------------------------------------------------------------------
-- What the map shows
---------------------------------------------------------------------------

local function heavier(a, b)
	if a.weight ~= b.weight then return a.weight > b.weight end
	return a.name < b.name
end

-- One item for the map, or nil when TSM lacks its trend or its sales: { itemID,
-- name, group = its group's name, weight = the gold of it sold in a day, trend (in
-- percent, not rounded), market, historical, soldPerDay, saleRate (nil when TSM has none) }.
local function entryOf(itemID, name, group, market, historical, soldPerDay, saleRate)
	if not (market and historical and soldPerDay and soldPerDay > 0) then return end
	return { itemID = itemID, name = name, group = group, weight = soldPerDay * market,
		trend = (market - historical) * 100 / historical,
		market = market, historical = historical, soldPerDay = soldPerDay, saleRate = saleRate }
end

-- The items the recipes make, each once, in its profession's group, and how many
-- more TSM lacks the trend or the sales of.
local function craftedEntries(rows)
	local list, seen, left = {}, {}, 0
	for _, row in ipairs(rows) do
		if row.itemID and not seen[row.link] then
			seen[row.link] = true
			local entry = entryOf(row.itemID, row.name, row.profession, row.market, row.historical, row.soldPerDay, row.saleRate)
			if entry then
				entry.row = row
				list[#list + 1] = entry
			else
				left = left + 1
			end
		end
	end
	return list, left
end

-- The materials the recipes take, each once, grouped by what kind of item the
-- game says it is (Metal & Stone, Herb, Cloth...), and how many more TSM lacks the
-- trend or the sales of.
local function materialEntries(rows)
	local list, seen, left = {}, {}, 0
	for _, row in ipairs(rows) do
		for _, material in ipairs(row.materials) do
			local itemID = material.itemID
			if not seen[itemID] then
				seen[itemID] = true
				local info = ns.AllRecipes.Material(itemID)
				local group = select(3, C_Item.GetItemInfoInstant(itemID))
				local entry = info and entryOf(itemID, ns.Format.ItemName(itemID) or "...",
					group and group ~= "" and group or "Other", info.market, info.historical, info.soldPerDay, info.saleRate)
				if entry then list[#list + 1] = entry else left = left + 1 end
			end
		end
	end
	return list, left
end

-- The entries by group, heaviest first, as are each group's items: { name, items,
-- weight = all its items', trend = theirs, the heavier counting for more } ..., and
-- the same groups by name.
local function groupsOf(entries)
	local groups, byName = {}, {}
	for _, entry in ipairs(entries) do
		local group = byName[entry.group]
		if not group then
			group = { name = entry.group, items = {}, weight = 0, lean = 0 }
			byName[entry.group] = group
			groups[#groups + 1] = group
		end
		group.items[#group.items + 1] = entry
		group.weight = group.weight + entry.weight
		group.lean = group.lean + entry.weight * entry.trend
	end
	for _, group in ipairs(groups) do
		group.trend = group.lean / group.weight
		table.sort(group.items, heavier)
	end
	table.sort(groups, heavier)
	return groups, byName
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- A trend's color: red, green and blue.
local function trendColor(trend)
	local to = trend < 0 and FALLING or RISING
	-- Small trends still show: the color moves fastest near zero.
	local part = math.min(math.abs(trend) / FULL_TREND, 1) ^ 0.6
	return FLAT[1] + (to[1] - FLAT[1]) * part, FLAT[2] + (to[2] - FLAT[2]) * part, FLAT[3] + (to[3] - FLAT[3]) * part
end

-- "+14%" or "-20%".
local function percentText(trend)
	local whole = math.floor(trend + 0.5)
	return format("%s%.0f%%", whole > 0 and "+" or "", whole)
end

local function addPair(left, right)
	GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
end

local function addHint(text)
	GameTooltip:AddLine(text, 0.6, 0.6, 0.6)
end

-- The trend and the gold sold a day, of an item, a group or a "more" tile.
local function addNumbers(of)
	addPair("TSM Trend", ns.Format.Trend(math.floor(of.trend + 0.5)))
	if of.market then
		addPair("Market Value", Money(of.market))
		addPair("Historical Price", Money(of.historical))
		addPair("Sold per Day", ns.Format.SoldPerDay(of.soldPerDay))
		if of.saleRate then addPair("TSM Sale Rate", ns.Format.SaleRate(of.saleRate)) end
	end
	addPair("Gold sold per Day", Money(of.weight))
end

local function showTip(button)
	local of = button.of
	if not of then return end
	hovered = button
	GameTooltip:SetOwner(button, "ANCHOR_CURSOR")
	if of.items then
		-- A group's name above its tiles.
		GameTooltip:SetText(of.name)
		GameTooltip:AddLine(format("%s items", BreakUpLargeNumbers(#of.items)), 1, 1, 1)
		addNumbers(of)
		addHint("Click: only this group")
	elseif of.count then
		-- A "more" tile.
		GameTooltip:SetText(format("%s more in %s", BreakUpLargeNumbers(of.count), of.group))
		GameTooltip:AddLine("Too small here for tiles of their own.", 1, 1, 1, true)
		addNumbers(of)
		addHint("Click: see them")
	else
		local row = of.row
		local name = ns.Format.RarityColored(of.itemID, of.name)
		if row and row.rankIcon then name = name .. " " .. row.rankIcon end
		GameTooltip:SetText(name)
		GameTooltip:AddLine(of.group, 1, 1, 1)
		addNumbers(of)
		if row and row.net then
			local net = math.floor(row.net + 0.5)
			addPair("Net Profit of one craft", Color(ns.AmountColor(net), Money(net)))
		end
		if not zoom then addHint("Click: only " .. of.group) end
	end
	if zoom then addHint("Right-click: back") end
	GameTooltip:Show()
end

local function hideTip()
	hovered = nil
	GameTooltip:Hide()
end

local function back()
	if #skips > 0 then
		table.remove(skips)
	elseif zoom then
		zoom = nil
	else
		return
	end
	changed()
end

-- A click on a tile or a group's name: the group alone, or the items a "more"
-- tile stands for once the group is alone. A right-click goes back.
local function onClick(button, mouseButton)
	if mouseButton == "RightButton" then return back() end
	local of = button.of
	if not of then return end
	local group = of.items and of.name or of.group
	if zoom ~= group then
		zoom = group
		wipe(skips)
	elseif of.count then
		skips[#skips + 1] = of.skip
	else
		return
	end
	changed()
end

local function createButton()
	local button = CreateFrame("Button", nil, map)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button.fill = button:CreateTexture(nil, "BACKGROUND")
	button.fill:SetPoint("TOPLEFT")
	button.fill:SetPoint("BOTTOMRIGHT", -GAP, GAP)
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints(button.fill)
	highlight:SetColorTexture(1, 1, 1, 0.18)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", showTip)
	button:SetScript("OnLeave", hideTip)
	return button
end

-- Puts a button where its box is, on whole units so the gaps stay even. False
-- when the box is too small to show.
local function place(button, left, top, width, height)
	local x, y = math.floor(left + 0.5), math.floor(top + 0.5)
	local w, h = math.floor(left + width + 0.5) - x, math.floor(top + height + 0.5) - y
	if w <= GAP or h <= GAP then
		button:Hide()
		return false
	end
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", map, "TOPLEFT", x, -y)
	button:SetSize(w, h)
	button:Show()
	return true
end

-- What fits in a tile with a font: "stacked" (the name above the trend, with how
-- many lines the name gets), "beside" (the name left of the trend, in a tile too
-- low for two lines but wide), "trend" (only that) or nil, and how wide the trend
-- is. The tile's trend text is left in that font.
local function fitting(tile, font, text, width, height)
	local percent = tile.percent
	percent:SetFontObject(font.object)
	percent:SetText(text)
	local percentWidth = percent:GetStringWidth()
	if height < font.line or percentWidth > width - 2 then return end
	local lines = math.min(math.floor((height - font.line) / font.line), NAME_MAX_LINES)
	if lines >= 1 and width >= font.nameWidth then return "stacked", percentWidth, lines end
	if width - percentWidth - 8 >= font.nameWidth then return "beside", percentWidth end
	return "trend", percentWidth
end

-- A tile's texts, as much as fits: the trend, and the name above it on up to
-- three lines, cut short where it's longer. A big tile's texts are bigger. A tile
-- too small for the name, or for anything, at the normal size has small texts
-- when that gets more in.
local function drawTexts(tile, name, trend, width, height)
	local percent, label = tile.percent, tile.name
	local text = percentText(trend)
	local font = (width >= 150 and height >= 70) and FONT_BIG or FONT_NORMAL
	local fits, percentWidth, lines = fitting(tile, font, text, width, height)
	if font == FONT_NORMAL and (fits == nil or fits == "trend") then
		local smallFits, smallWidth, smallLines = fitting(tile, FONT_SMALL, text, width, height)
		if smallFits and smallFits ~= fits then
			font, fits, percentWidth, lines = FONT_SMALL, smallFits, smallWidth, smallLines
		else
			percent:SetFontObject(font.object)
		end
	end
	percent:ClearAllPoints()
	label:ClearAllPoints()
	percent:SetShown(fits ~= nil)
	label:SetShown(fits == "stacked" or fits == "beside")
	if fits == "stacked" then
		label:SetFontObject(font.object)
		label:SetJustifyH("CENTER")
		label:SetWordWrap(true)
		label:SetMaxLines(lines)
		label:SetWidth(width - 4)
		label:SetText(name)
		-- The two together sit in the middle, however many lines the name took.
		local nameHeight = math.min(label:GetStringHeight(), lines * font.line)
		label:SetPoint("TOP", tile.fill, "CENTER", 0, (nameHeight + font.line) / 2)
		percent:SetPoint("TOP", label, "BOTTOM")
	elseif fits == "beside" then
		label:SetFontObject(font.object)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(false)
		label:SetMaxLines(1)
		label:SetWidth(width - percentWidth - 8)
		label:SetText(name)
		label:SetPoint("LEFT", tile.fill, "LEFT", 2, 0)
		percent:SetPoint("RIGHT", tile.fill, "RIGHT", -2, 0)
	elseif fits then
		percent:SetPoint("CENTER", tile.fill, "CENTER")
	end
end

local function tileAt(index)
	local tile = tiles[index]
	if not tile then
		tile = createButton()
		tile:SetClipsChildren(true) -- a word longer than the tile is wide stays inside it
		tile.name = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		tile.percent = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		tiles[index] = tile
	end
	return tile
end

local function headerAt(index)
	local header = headers[index]
	if not header then
		header = createButton()
		header.fill:SetColorTexture(0, 0, 0, 0.55)
		header.text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		header.text:SetPoint("LEFT", 4, 0)
		header.text:SetJustifyH("LEFT")
		header.text:SetWordWrap(false)
		headers[index] = header
	end
	return header
end

-- Draws a group's items from the one after `skip` in the box, the ones too small
-- for a tile of their own as one "more" tile. `used` is how many tiles are taken
-- so far; the new count comes back. `named` is whether the group's name is above.
local function drawItems(group, skip, left, top, width, height, most, used, named)
	local items = group.items
	local own = ownTiles(items, skip, width * height, most)
	local list = {}
	for index = skip + 1, skip + own do list[#list + 1] = items[index] end
	local rest = #items - skip - own
	if rest > 0 then
		-- What they add up to, as one entry: { count, skip = how many of the group's
		-- biggest it leaves out, group = its name, name = what the tile says }.
		local more = { count = rest, skip = skip + own, group = group.name, weight = 0, trend = 0 }
		for index = skip + own + 1, #items do
			more.weight = more.weight + items[index].weight
			more.trend = more.trend + items[index].weight * items[index].trend
		end
		more.trend = more.trend / more.weight
		-- A group too small for any tile is one block with its own name, unless it's above.
		more.name = (own == 0 and not named) and group.name or format("%s more", BreakUpLargeNumbers(rest))
		list[#list + 1] = more
		table.sort(list, heavier)
	end
	squarify(list, left, top, width, height)
	for _, entry in ipairs(list) do
		if entry.width then
			local tile = tileAt(used + 1)
			if place(tile, entry.left, entry.top, entry.width, entry.height) then
				used = used + 1
				tile.of = entry
				tile.fill:SetColorTexture(trendColor(entry.trend))
				drawTexts(tile, entry.name, entry.trend, tile:GetWidth() - GAP, tile:GetHeight() - GAP)
			end
		end
	end
	return used
end

-- Every group in its own box, with its name above its tiles where there's room.
local function drawGroups(groups)
	squarify(groups, 0, 0, mapWidth, mapHeight)
	local used, named = 0, 0
	for _, group in ipairs(groups) do
		if group.width then
			local left, top, width, height = group.left, group.top, group.width, group.height
			local hasName = width >= HEADER_MIN_WIDTH and height >= 2 * HEADER_HEIGHT
			if hasName then
				local header = headerAt(named + 1)
				if place(header, left, top, width, HEADER_HEIGHT) then
					named = named + 1
					header.of = group
					header.text:SetWidth(header:GetWidth() - 8)
					header.text:SetText(group.name .. "  " .. ns.Format.Trend(math.floor(group.trend + 0.5)))
					top, height = top + HEADER_HEIGHT, height - HEADER_HEIGHT
				else
					hasName = false
				end
			end
			used = drawItems(group, 0, left, top, width, height, MAX_TILES, used, hasName)
		end
	end
	return used, named
end

-- The line above the map: Back and the group's name while one is shown alone,
-- and otherwise what a click does.
local function drawBar(group, shown)
	backButton:SetShown(group ~= nil)
	where:ClearAllPoints()
	if not group then
		where:SetPoint("LEFT", frame, "TOPLEFT", 2, -BAR_HEIGHT / 2)
		where:SetText(Color("muted", CLICK_HINT))
		return
	end
	where:SetPoint("LEFT", backButton, "RIGHT", 8, 0)
	local text = format("%s  %s", Color("heading", group.name), ns.Format.Trend(math.floor(group.trend + 0.5)))
	if shown < #group.items then
		text = text .. Color("muted", format("  the %s smallest of %s items", BreakUpLargeNumbers(shown),
			BreakUpLargeNumbers(#group.items)))
	else
		text = text .. Color("muted", format("  %s items", BreakUpLargeNumbers(shown)))
	end
	where:SetText(text)
end

-- Draws the map of the window's recipes (the ones its search and filters leave):
-- the items they make ("crafted") or the materials they take ("materials").
-- Returns how many items it shows, and how many more TSM lacks the trend or the
-- sales of. With none to show the map hides.
function Heatmap.Draw(rows, what)
	if what ~= kind then
		kind, zoom = what, nil
		wipe(skips)
	end
	local entries, left
	if what == "materials" then entries, left = materialEntries(rows) else entries, left = craftedEntries(rows) end
	if #entries == 0 then
		Heatmap.Hide()
		return 0, left
	end
	local groups, byName = groupsOf(entries)
	local group = zoom and byName[zoom]
	if not group then
		zoom = nil
		wipe(skips)
	end
	-- A "more" tile that was opened may have fewer items behind it by now.
	while group and #skips > 0 and skips[#skips] >= #group.items do table.remove(skips) end

	local used, named, shown = 0, 0, #entries
	if group then
		local skip = skips[#skips] or 0
		shown = #group.items - skip
		used = drawItems(group, skip, 0, 0, mapWidth, mapHeight, MAX_TILES_ALONE, 0, true)
	else
		used, named = drawGroups(groups)
	end
	for index = used + 1, #tiles do tiles[index]:Hide() end
	for index = named + 1, #headers do headers[index]:Hide() end
	drawBar(group, shown)
	frame:Show()

	-- The tile under the mouse may stand for something else now.
	if hovered then
		if hovered:IsShown() and hovered:IsMouseOver() then showTip(hovered) else hideTip() end
	end
	return shown, left
end

function Heatmap.Hide()
	if not (frame and frame:IsShown()) then return end
	if hovered then hideTip() end
	frame:Hide()
end

-- Back to every group: the window opened again.
function Heatmap.Reset()
	zoom = nil
	wipe(skips)
end

-- What the colors mean, at the right of the line above the map: a square for
-- each of a few trends, from -50% to +50%.
local function createKey()
	local last = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	last:SetPoint("RIGHT", frame, "TOPRIGHT", -2, -BAR_HEIGHT / 2)
	last:SetText(percentText(KEY_STEPS[#KEY_STEPS]))
	local after = last
	for index = #KEY_STEPS, 1, -1 do
		local square = frame:CreateTexture(nil, "ARTWORK")
		square:SetSize(KEY_WIDTH, KEY_HEIGHT)
		square:SetPoint("RIGHT", after, "LEFT", after == last and -6 or -1, 0)
		square:SetColorTexture(trendColor(KEY_STEPS[index]))
		after = square
	end
	local first = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	first:SetPoint("RIGHT", after, "LEFT", -6, 0)
	first:SetText(percentText(KEY_STEPS[1]))
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("RIGHT", first, "LEFT", -10, 0)
	title:SetText(Color("muted", "TSM Trend"))
end

-- Makes the map, `width` by `height` with its line above, as a child of `parent`
-- for the window to put in place. `onChange` is called when a click changes what
-- it shows: the window then draws it again.
function Heatmap.Create(parent, width, height, onChange)
	changed = onChange
	mapWidth, mapHeight = width, height - BAR_HEIGHT
	frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width, height)
	frame:Hide()

	map = CreateFrame("Frame", nil, frame)
	map:SetSize(mapWidth, mapHeight)
	map:SetPoint("BOTTOMLEFT")
	local ground = map:CreateTexture(nil, "BACKGROUND")
	ground:SetAllPoints()
	ground:SetColorTexture(0.04, 0.04, 0.06, 1)
	-- A right-click between the tiles goes back too.
	map:EnableMouse(true)
	map:SetScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "RightButton" then back() end
	end)

	backButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	backButton:SetSize(BACK_WIDTH, 22)
	backButton:SetPoint("LEFT", frame, "TOPLEFT", 0, -BAR_HEIGHT / 2)
	backButton:SetText("Back")
	backButton:SetScript("OnClick", back)
	where = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	createKey()
	return frame
end
