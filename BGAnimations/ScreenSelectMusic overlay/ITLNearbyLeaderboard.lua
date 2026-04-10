local maxRows = 15
local bannerY = 96
local bannerHeight = 164
local bannerZoom = IsUsingWideScreen() and 0.7655 or 0.72
local paneFooterHeight = 32
local paneHeight = 60

local panelTop = bannerY - (bannerHeight * bannerZoom) / 2 + 4
local panelBottom = _screen.h - paneFooterHeight - paneHeight - 4
local panelHeight = panelBottom - panelTop
local panelCenterY = (panelTop + panelBottom) / 2

local bannerCenterX = IsUsingWideScreen() and (_screen.cx - 170) or (_screen.cx - 160)
local bannerEffW = 418 * bannerZoom
local bannerLeftEdge = bannerCenterX - bannerEffW / 2
local panelWidth = math.floor(bannerLeftEdge - 4 - 2)
local panelX = 2 + panelWidth / 2

local headerHeight = 22
local borderWidth = 2
local rowHeight = (panelHeight - headerHeight) / maxRows
local mappingPath = THEME:GetCurrentThemeDirectory() .. "Other/ITL-mapping/mapping.json"

local maxNameLen = 10

local clamp = function(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

local LoadMapping = function()
	if not FILEMAN:DoesFileExist(mappingPath) then return nil end

	local f = RageFileUtil:CreateRageFile()
	local decoded = nil
	if f:Open(mappingPath, 1) then
		decoded = JsonDecode(f:Read())
		f:Close()
	end
	f:destroy()

	if type(decoded) ~= "table" then return nil end
	return decoded
end

local BuildRankedEntries = function(mapping)
	local ranked = {}
	for name, entry in pairs(mapping) do
		if type(name) == "string" and type(entry) == "table" and type(entry.currentRank) == "number" then
			ranked[#ranked + 1] = {
				rank = math.floor(entry.currentRank),
				name = name,
				rankingPoints = tonumber(entry.rankingPoints) or 0,
			}
		end
	end

	table.sort(ranked, function(a, b)
		if a.rank == b.rank then
			return a.name < b.name
		end
		return a.rank < b.rank
	end)

	return ranked
end

local BuildRankLookup = function(entries)
	local byRank = {}
	for _, e in ipairs(entries) do
		byRank[e.rank] = e
	end
	return byRank
end

local GetAnchors = function(mapping)
	local anchors = {}
	for _, player in ipairs(GAMESTATE:GetHumanPlayers()) do
		local pn = ToEnumShortString(player)
		local username = (SL[pn] and SL[pn].GrooveStatsUsername) and SL[pn].GrooveStatsUsername:lower() or nil
		local entry = username and mapping[username] or nil
		if type(entry) == "table" and type(entry.currentRank) == "number" then
			anchors[#anchors + 1] = {
				pn = pn,
				rank = math.floor(entry.currentRank),
				username = username,
			}
		end
	end

	return anchors
end

local GetContiguousWindow = function(totalEntries, centerRank)
	if totalEntries <= maxRows then
		return 1, totalEntries
	end

	local startRank = centerRank - math.floor(maxRows / 2)
	startRank = clamp(startRank, 1, totalEntries - maxRows + 1)
	return startRank, startRank + maxRows - 1
end

local AddRankRange = function(set, list, byRank, fromRank, toRank)
	for r = fromRank, toRank do
		local row = byRank[r]
		if row and not set[r] then
			set[r] = true
			list[#list + 1] = row
		end
	end
end

local BuildTwoAnchorRows = function(totalEntries, byRank, lowRank, highRank)
	local span = highRank - lowRank + 1
	if span <= maxRows then
		local startRank = clamp(lowRank - math.floor((maxRows - span) / 2), 1, math.max(1, totalEntries - maxRows + 1))
		local rows = {}
		for r = startRank, math.min(totalEntries, startRank + maxRows - 1) do
			if byRank[r] then rows[#rows + 1] = byRank[r] end
		end
		return rows
	end

	local set = {}
	local rows = {}

	AddRankRange(set, rows, byRank, lowRank - 3, lowRank + 3)
	AddRankRange(set, rows, byRank, highRank - 3, highRank + 3)

	local distance = 4
	while #rows < maxRows and distance <= totalEntries do
		local lowLeft = lowRank - distance
		local lowRight = lowRank + distance
		local highLeft = highRank - distance
		local highRight = highRank + distance

		for _, r in ipairs({ lowLeft, lowRight, highLeft, highRight }) do
			if #rows >= maxRows then break end
			local row = byRank[r]
			if row and not set[r] then
				set[r] = true
				rows[#rows + 1] = row
			end
		end

		distance = distance + 1
	end

	table.sort(rows, function(a, b) return a.rank < b.rank end)
	if #rows > maxRows then
		local trimmed = {}
		for i = 1, maxRows do
			trimmed[i] = rows[i]
		end
		return trimmed
	end

	return rows
end

local GetRowsToDisplay = function(entries, byRank, anchors)
	if #anchors == 0 then return {} end

	local totalEntries = #entries
	if totalEntries == 0 then return {} end

	if #anchors == 1 then
		local startRank, endRank = GetContiguousWindow(totalEntries, anchors[1].rank)
		local rows = {}
		for r = startRank, endRank do
			if byRank[r] then rows[#rows + 1] = byRank[r] end
		end
		return rows
	end

	local r1 = anchors[1].rank
	local r2 = anchors[2].rank
	if r2 < r1 then r1, r2 = r2, r1 end
	return BuildTwoAnchorRows(totalEntries, byRank, r1, r2)
end

local BuildAnchorSet = function(anchors)
	local set = {}
	for _, a in ipairs(anchors) do
		set[a.rank] = a.pn
	end
	return set
end

local IsCurrentGroupITL = function()
	local song = GAMESTATE:GetCurrentSong()
	if not song then return false end
	local group = string.lower(song:GetGroupName())
	return string.find(group, "itl online") ~= nil 
end

local af = Def.ActorFrame{
	Name = "ITLNearbyLeaderboard",
	InitCommand = function(self)
		self:xy(panelX, panelCenterY)
		self:visible(false)
		self:queuecommand("Refresh")
	end,
	PlayerJoinedMessageCommand = function(self) self:queuecommand("Refresh") end,
	PlayerUnjoinedMessageCommand = function(self) self:queuecommand("Refresh") end,
	PlayerProfileSetMessageCommand = function(self) self:queuecommand("Refresh") end,
	RefreshITLNearbyLeaderboardMessageCommand = function(self) self:queuecommand("Refresh") end,
	CurrentSongChangedMessageCommand = function(self) self:queuecommand("Refresh") end,
	SwitchFocusToGroupsMessageCommand = function(self) self:visible(false) end,
	RefreshCommand = function(self)
		if not IsCurrentGroupITL() then
			self:visible(false)
			return
		end

		local mapping = LoadMapping()
		if not mapping then
			self:visible(false)
			return
		end

		local anchors = GetAnchors(mapping)
		if #anchors == 0 then
			self:visible(false)
			return
		end

		local entries = BuildRankedEntries(mapping)
		local byRank = BuildRankLookup(entries)
		local rows = GetRowsToDisplay(entries, byRank, anchors)
		local anchorSet = BuildAnchorSet(anchors)

		if #rows == 0 then
			self:visible(false)
			return
		end

		self:visible(true)
		-- Build display list, inserting separator markers at rank gaps
		local displayRows = {}
		for i, row in ipairs(rows) do
			if i > 1 and row.rank - rows[i - 1].rank > 1 then
				displayRows[#displayRows + 1] = { separator = true }
			end
			displayRows[#displayRows + 1] = row
		end

		for i = 1, maxRows do
			local rowFrame = self:GetChild("ITLRow" .. i)
			local dRow = displayRows[i]
			if dRow and dRow.separator then
				rowFrame:visible(true)
				rowFrame:GetChild("Rank"):settext("")
				rowFrame:GetChild("Name"):settext("· · · · ·")
				rowFrame:GetChild("Name"):diffuse(color("#666666"))
				rowFrame:GetChild("Points"):settext("")
			elseif dRow then
				rowFrame:visible(true)
				rowFrame:GetChild("Rank"):settext("#" .. tostring(dRow.rank))
				local displayName = #dRow.name > maxNameLen and dRow.name:sub(1, maxNameLen) .. "..." or dRow.name
				rowFrame:GetChild("Name"):settext(displayName)
				rowFrame:GetChild("Points"):settext(tostring(dRow.rankingPoints) .. " RP")

				if anchorSet[dRow.rank] == "P1" then
					rowFrame:GetChild("Name"):diffuse(PlayerColor(PLAYER_1))
					rowFrame:GetChild("Points"):diffuse(PlayerColor(PLAYER_1))
				elseif anchorSet[dRow.rank] == "P2" then
					rowFrame:GetChild("Name"):diffuse(PlayerColor(PLAYER_2))
					rowFrame:GetChild("Points"):diffuse(PlayerColor(PLAYER_2))
				else
					rowFrame:GetChild("Name"):diffuse(Color.White)
					rowFrame:GetChild("Points"):diffuse(Color.White)
				end
			else
				rowFrame:visible(false)
			end
		end
	end,
}

-- White border
af[#af + 1] = Def.Quad{
	InitCommand = function(self)
		self:zoomto(panelWidth + borderWidth, panelHeight + borderWidth):diffuse(Color.White):diffusealpha(0.3)
	end
}

-- Black body
af[#af + 1] = Def.Quad{
	InitCommand = function(self)
		self:zoomto(panelWidth, panelHeight):diffuse(Color.Black):diffusealpha(0.6)
	end
}

-- Header border
af[#af + 1] = Def.Quad{
	InitCommand = function(self)
		self:zoomto(panelWidth + borderWidth, headerHeight + borderWidth)
		self:y(-panelHeight / 2 + headerHeight / 2)
		self:diffuse(Color.White)
	end
}

-- Blue header
af[#af + 1] = Def.Quad{
	InitCommand = function(self)
		self:zoomto(panelWidth, headerHeight)
		self:y(-panelHeight / 2 + headerHeight / 2)
		self:diffuse(Color.Blue)
	end
}

-- Header text
af[#af + 1] = LoadFont("Wendy/_wendy small") .. {
	Text = "ITL 2026",
	InitCommand = function(self)
		self:y(-panelHeight / 2 + headerHeight / 2)
		self:zoom(0.35):maxwidth(panelWidth / 0.35)
		self:diffuse(Color.White)
	end
}

local textZoom = 0.4
local rowContentWidth = panelWidth - 6

for i = 1, maxRows do
	af[#af + 1] = Def.ActorFrame{
		Name = "ITLRow" .. i,
		InitCommand = function(self)
			self:y(-panelHeight / 2 + headerHeight + (i - 0.5) * rowHeight)
		end,

		LoadFont("Common Normal") .. {
			Name = "Rank",
			InitCommand = function(self)
				self:x(-rowContentWidth / 2 + 2):horizalign(left)
				self:zoom(textZoom):maxwidth(40 / textZoom)
				self:diffuse(Color.White)
			end,
		},

		LoadFont("Common Normal") .. {
			Name = "Name",
			InitCommand = function(self)
				self:x(-rowContentWidth / 2 + 22):horizalign(left)
				self:zoom(textZoom):maxwidth((rowContentWidth - 26) / textZoom)
				self:diffuse(Color.White)
			end,
		},

		LoadFont("Common Normal") .. {
			Name = "Points",
			InitCommand = function(self)
				self:x(rowContentWidth / 2 - 2):horizalign(right)
				self:zoom(textZoom):maxwidth(80 / textZoom)
				self:diffuse(Color.White)
			end,
		},
	}
end

return af
