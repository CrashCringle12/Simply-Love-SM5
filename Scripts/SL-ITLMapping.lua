-- -----------------------------------------------------------------------
-- ITL Mapping: Fetches the ITL leaderboard and builds a username->entrant
-- mapping so we can look up entrant IDs for achievement/unlock API calls.
-- -----------------------------------------------------------------------

local itl_api_base = "https://itl2026.groovestats.com/api/"
local mapping_path = "Other/ITL-mapping/mapping.json"

-- -----------------------------------------------------------------------
-- File I/O helpers
-- -----------------------------------------------------------------------

LoadITLMapping = function()
	local path = THEME:GetCurrentThemeDirectory() .. mapping_path
	if not FILEMAN:DoesFileExist(path) then return {} end

	local f = RageFileUtil:CreateRageFile()
	local data = nil
	if f:Open(path, 1) then
		data = JsonDecode(f:Read())
		f:Close()
	end
	f:destroy()
	return type(data) == "table" and data or {}
end

SaveITLMapping = function(mapping)
	if type(mapping) ~= "table" then return end

	local path = THEME:GetCurrentThemeDirectory() .. mapping_path
	local f = RageFileUtil:CreateRageFile()
	if f:Open(path, 2) then
		f:Write(JsonEncode(mapping))
		f:Close()
	end
	f:destroy()
end

-- -----------------------------------------------------------------------
-- Parse the raw leaderboard API response into a condensed mapping keyed
-- by lowercase username:
-- { ["username"] = { id, membersId, totalPoints, rankingPoints, currentRank } }
-- -----------------------------------------------------------------------

ParseLeaderboardResponse = function(responseData)
	if type(responseData) ~= "table" then return {} end
	if not responseData.success then return {} end
	if type(responseData.data) ~= "table" then return {} end

	local leaderboard = responseData.data.leaderboard
	if type(leaderboard) ~= "table" then return {} end

	local mapping = {}
	for rank, entry in ipairs(leaderboard) do
		if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
			local key = entry.name:lower()
			mapping[key] = {
				id = entry.id,
				membersId = entry.membersId,
				totalPoints = entry.totalPoints,
				rankingPoints = entry.rankingPoints,
				currentRank = rank,
			}
		end
	end
	return mapping
end

-- -----------------------------------------------------------------------
-- Look up an entrant ID from the in-memory mapping by GS username.
-- Returns the numeric id or nil if not found.
-- -----------------------------------------------------------------------

GetITLEntrantId = function(username)
	if type(username) ~= "string" or username == "" then return nil end
	local mapping = SL.Accolades.ITLMapping.Data
	if type(mapping) ~= "table" then return nil end

	local entry = mapping[username:lower()]
	if type(entry) == "table" then
		return entry.id
	end
	return nil
end

-- -----------------------------------------------------------------------
-- Fetch the leaderboard from the ITL API, parse it, save to disk, and
-- update the in-memory mapping. Calls callback(success) when done.
-- -----------------------------------------------------------------------

FetchITLLeaderboard = function(callback)
	NETWORK:HttpRequest{
		url = itl_api_base .. "entrant/leaderboard",
		method = "GET",
		connectTimeout = 15,
		transferTimeout = 30,
		onResponse = function(response)
			if response.error then
				Warn("ITL leaderboard fetch error: " .. tostring(response.error))
				if callback then callback(false) end
				return
			end
			if response.statusCode ~= 200 then
				Warn("ITL leaderboard fetch failed with status: " .. tostring(response.statusCode))
				if callback then callback(false) end
				return
			end

			local body = JsonDecode(response.body)
			if not body then
				Warn("ITL leaderboard: failed to decode JSON")
				if callback then callback(false) end
				return
			end
            -- SM("Fetched ITL leaderboard, processing...", 3, true)
			local mapping = ParseLeaderboardResponse(body)
			SL.Accolades.ITLMapping.Data = mapping
			SL.Accolades.ITLMapping.LastUpdated = GetTimeSinceStart()
			SaveITLMapping(mapping)

			if callback then callback(true) end
		end,
	}
end

-- -----------------------------------------------------------------------
-- Fetch achievements for a player from the ITL API using their entrant ID.
-- Saves the response as ITL-achievements.json in the player's profile dir.
-- Calls callback(success) when done.
-- -----------------------------------------------------------------------

FetchITLAchievements = function(player, entrantId, callback)
	if not entrantId then
		if callback then callback(false) end
		return
	end

	NETWORK:HttpRequest{
		url = itl_api_base .. "achievement/list/" .. tostring(entrantId),
		method = "GET",
		connectTimeout = 15,
		transferTimeout = 30,
		onResponse = function(response)
            -- SM(response)
			if response.error then
				Warn("ITL achievements fetch error: " .. tostring(response.error))
				if callback then callback(false) end
				return
			end
			if response.statusCode ~= 200 then
				Warn("ITL achievements fetch failed with status: " .. tostring(response.statusCode))
				if callback then callback(false) end
				return
			end

			local body = JsonDecode(response.body)
			if not body then
				Warn("ITL achievements: failed to decode JSON")
				if callback then callback(false) end
				return
			end
            -- SM("Fetched ITL achievements for entrant ID " .. tostring(entrantId), 3, true)
			-- Write the response to the player's profile as ITL-achievements.json
			local profile_slot = {
				[PLAYER_1] = "ProfileSlot_Player1",
				[PLAYER_2] = "ProfileSlot_Player2",
			}
			local slot = profile_slot[player]
			if not slot then
				if callback then callback(false) end
				return
			end

			local dir = PROFILEMAN:GetProfileDir(slot)
			if not dir or #dir == 0 then
				if callback then callback(false) end
				return
			end

			local path = dir .. "ITL-achievements.json"
			local f = RageFileUtil:CreateRageFile()
			if f:Open(path, 2) then
				f:Write(JsonEncode(body))
				f:Close()
			end
			f:destroy()

			if callback then callback(true) end
		end,
	}
end

-- -----------------------------------------------------------------------
-- High-level: refresh achievements for a single player.
-- Looks up entrant ID from mapping. If not found, fetches a fresh
-- leaderboard and retries once.
-- -----------------------------------------------------------------------

RefreshITLAchievementsForPlayer = function(player)
	local pn = ToEnumShortString(player)
	local username = SL[pn].GrooveStatsUsername

	if type(username) ~= "string" or username == "" then return end

	local entrantId = GetITLEntrantId(username)
	if entrantId then
		-- Found in mapping, fetch achievements directly
		FetchITLAchievements(player, entrantId)
	else
		-- Not found — refresh the leaderboard and retry once
		FetchITLLeaderboard(function(success)
			if not success then return end
			local retryId = GetITLEntrantId(username)
			if retryId then
				FetchITLAchievements(player, retryId)
			end
		end)
	end
end
