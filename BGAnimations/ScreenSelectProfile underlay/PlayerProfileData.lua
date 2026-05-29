
-- ----------------------------------------------------
-- local tables containing NoteSkins and JudgmentGraphics available to SL
-- We'll compare values from profiles against these "master" tables as it
-- seems to be disconcertingly possible for user data to contain errata, typos, etc.

local noteskins = NOTESKIN:GetNoteSkinNames()
local judgment_graphics = {}

-- get a table like { "ITG", "FA+" }
local judgment_dirs = FILEMAN:GetDirListing(THEME:GetCurrentThemeDirectory().."Graphics/_judgments/", true, false)
for dir in ivalues(judgment_dirs) do
	judgment_graphics[dir] = GetJudgmentGraphics(dir)
end
-- ----------------------------------------------------
-- some local functions that will help process profile data into presentable strings

local RecentMods = function(mods)
	if type(mods) ~= "table" then return "" end

	local text = ""

	-- SpeedModType should be a string and SpeedMod should be a number
	if type(mods.SpeedModType)=="string" and type(mods.SpeedMod)=="number" then
		-- for ScreenSelectProfile, allow either "x" or "X" to be in the player's profile for SpeedModType
		if (mods.SpeedModType):upper()=="X" and mods.SpeedMod > 0 then
			-- take whatever number is in the player's profile, string format it to 2 decimal places
			-- convert back to a number to remove potential trailing 0s (we want "1.5x" not "1.50x")
			-- and finally convert that back to a string
			text = ("%gx"):format(tonumber(("%.2f"):format(mods.SpeedMod)))

		elseif (mods.SpeedModType=="M" or mods.SpeedModType=="C") and mods.SpeedMod > 0 then
			text = ("%s%.0f"):format(mods.SpeedModType, mods.SpeedMod)
		end
	end

	-- -----------------------------------------------------------------------
	-- the NoteSkin and JudgmentGraphic previews are not text, and are loaded, handled, and positioned separately

	-- ASIDE: My informal testing of reading ~80 unique JudgmentGraphic files from disk and
	-- loading them into memory caused StepMania to hang for a few seconds, so
	-- JudgmentGraphicPreviews.lua and NoteSkinPreviews.lua only load assets that are
	-- needed by current player profiles (not every possible asset).

	-- FIXME: If a profile's values for NoteSkin and/or JudgmentGraphic don't match with anything
	-- available to StepMania (players commonly modify their profiles by hand and introduce typos),
	-- we currently don't show anything.  Maybe a generic graphic of a question mark (or similar)
	-- would be nice but that can wait for a future release.
	-- -----------------------------------------------------------------------

	-- Mini should definitely be a string
	if type(mods.Mini)=="string" and mods.Mini ~= "" then text = ("%s %s, "):format(mods.Mini, THEME:GetString("OptionTitles", "Mini")) end

	-- DataVisualizations should be a string and a specific string at that
	if mods.DataVisualizations=="Target Score Graph" or mods.DataVisualizations=="Step Statistics" then
		text = text .. THEME:GetString("SLPlayerOptions", mods.DataVisualizations)..", "
	end

	-- loop for mods that save as booleans
	local flags, hideflags = "", ""
	for k,v in pairs(mods) do
		-- explicitly check for true (not Lua truthiness)
		if v == true then
			-- gsub() returns two values:
			-- the string resulting from the substitution, and the number of times the substitution occurred (0, 1, 2, 3, ...)
			-- custom modifier strings in SL should have "Hide" occur as a substring 0 or 1 times
			local mod, hide = k:gsub("Hide", "")

			if THEME:HasString("SLPlayerOptions", mod) then
				if hide == 0 then
					flags = flags..THEME:GetString("SLPlayerOptions", mod)..", "
				elseif hide == 1 then
					hideflags = hideflags..THEME:GetString("ThemePrefs", "Hide").." "..THEME:GetString("SLPlayerOptions", mod)..", "
				end
			end
		end
	end
	text = text .. hideflags .. flags

	-- remove trailing comma and whitespace
	text = text:sub(1,-3)

	return text, mods.NoteSkin, mods.JudgmentGraphic, mods.SpeedMod, mods.SpeedModType, mods.lifeMeterType
end

-- ----------------------------------------------------
-- profiles have a GetTotalSessions() method, but the value doesn't (seem to?) increment in EventMode
-- making it much less useful for the players who will most likely be using this screen
-- for now, just retrieve total songs played

local TotalSongs = function(numSongs)
	if numSongs == 1 then
		return Screen.String("SingularSongPlayed"):format(numSongs)
	else
		return Screen.String("SeveralSongsPlayed"):format(numSongs)
	end
	return ""
end

local ValidSong = function(lastSong)
	if lastSong == nil or lastSong == "" then
		return "N/A"

	else
		return lastSong:GetDisplayMainTitle()

	end
	return ""
end
-- ----------------------------------------------------
-- retrieves profile data from disk without applying it to the SL table

local RetrieveProfileData = function(profile, dir)
	local theme_name = THEME:GetThemeDisplayName()
	local path = dir .. theme_name .. " UserPrefs.ini"
	if FILEMAN:DoesFileExist(path) then
		return IniFile.ReadFile(path)[theme_name]
	end
	return false
end

local RetrieveGrooveStatsData = function(dir)
	local path = dir .. "GrooveStats.ini"
	if not FILEMAN:DoesFileExist(path) then
		return {ApiKey = "", Username = "", IsPadPlayer = 0}
	end

	local contents = IniFile.ReadFile(path)
	if type(contents) ~= "table" or type(contents.GrooveStats) ~= "table" then
		return {ApiKey = "", Username = "", IsPadPlayer = 0}
	end

	local data = contents.GrooveStats
	local apiKey = type(data.ApiKey) == "string" and data.ApiKey or ""
	if #apiKey ~= 64 then
		apiKey = ""
	end

	return {
		ApiKey = apiKey,
		Username = type(data.Username) == "string" and data.Username or "",
		IsPadPlayer = (data.IsPadPlayer == 1 or data.IsPadPlayer == "1") and 1 or 0,
	}
end

local RetrieveProfileAchievements = function(profile, dir)
	local BuildITLAchievementsFromEventData = function(data)
		if type(data) ~= "table" or type(data.data) ~= "table" then return {} end

		local joinRequirements = function(requirements)
			if type(requirements) ~= "table" then return "" end
			local parts = {}
			for _, requirement in pairs(requirements) do
				if type(requirement) == "table" and type(requirement.requirement) == "string" and requirement.requirement ~= "" then
					parts[#parts+1] = requirement.requirement
				end
			end
			return table.concat(parts, "; ")
		end

		local output = {}
		for _, category in pairs(data.data) do
			if type(category) == "table" and type(category.info) == "table" then
				local categoryTitle = (type(category.title) == "string" and category.title ~= "") and category.title or "ITL Achievement"
				local tiers = {}
				for tierIndex, tierData in pairs(category.info) do
					if type(tierData) == "table" then
						tiers[#tiers+1] = {index = tonumber(tierIndex) or 0, data = tierData}
					end
				end

				table.sort(tiers, function(a, b)
					return a.index < b.index
				end)

				for _, tier in ipairs(tiers) do
					local tierData = tier.data
					local requirementText = joinRequirements(tierData.requirements)
					local unlockedTitle = type(tierData.titleUnlocked) == "string" and tierData.titleUnlocked or ""
					local isUnlocked = tierData.satisfied == true
					local hasVisibleTitle = unlockedTitle ~= ""

					local id = tonumber(tierData.id)
					if not id then
						id = (tonumber(category.id) or 0) * 100 + tier.index
					end

					local name = hasVisibleTitle and unlockedTitle or categoryTitle

					local desc = requirementText ~= "" and ("Requirements: " .. requirementText) or "Requirements unavailable"

					output[#output+1] = {
						ID = id,
						Name = name,
						Desc = desc,
						Unlocked = isUnlocked,
						TitleUnlocked = unlockedTitle,
						PercentEarned = tonumber(tierData.percentEarned) or 0,
						Requirements = requirementText,
						Category = categoryTitle,
						Hidden = (not hasVisibleTitle and not isUnlocked),
					}
				end
			end
		end

		table.sort(output, function(a, b)
			return (a.ID or 0) < (b.ID or 0)
		end)

		return output
	end

	local ReadJSONFile = function(path)
		if not FILEMAN:DoesFileExist(path) then return nil end

		local f = RageFileUtil:CreateRageFile()
		local data = nil
		if f:Open(path, 1) then
			data = JsonDecode(f:Read())
			f:Close()
		end
		f:destroy()
		return data
	end

	-- local theme_name = THEME:GetThemeDisplayName()
	local path = dir .. "Achievements.json"
	local achievements = {}
	local existing = ReadJSONFile(path)
	if existing ~= nil then
		achievements = existing
	end

	local itlPath = dir .. "ITL-achievements.json"
	local itlData = ReadJSONFile(itlPath)
	if itlData == nil then
		local samplePath = THEME:GetCurrentThemeDirectory() .. "Other/Achievements/ITL/sample.json"
		itlData = ReadJSONFile(samplePath)
	end
	if itlData ~= nil then
		local parsedITL = BuildITLAchievementsFromEventData(itlData)
		local previousById = {}
		if type(achievements.ITL) == "table" then
			for _, previous in ipairs(achievements.ITL) do
				if type(previous) == "table" and previous.ID ~= nil then
					previousById[previous.ID] = previous
				end
			end
		end

		achievements.ITL = {}
		for i, entry in ipairs(parsedITL) do
			local previous = previousById[entry.ID]
			achievements.ITL[i] = {
				ID = entry.ID,
				Name = entry.Name,
				Desc = entry.Desc,
				Unlocked = entry.Unlocked,
				TitleUnlocked = entry.TitleUnlocked,
				Date = previous and previous.Date or nil,
				PercentEarned = entry.PercentEarned,
				Requirements = entry.Requirements,
				Category = entry.Category,
				Hidden = entry.Hidden,
			}
		end
	end

	return achievements
end

SweatLevelRibbon = function(profile)
	-- Params.totalsongs returns the text "## Songs Played also so we need to split it
	-- Now we need to conver the amount of songs played to an integer and check if it meets the criteria
	local numSongs = profile:GetNumTotalSongsPlayed()
	if numSongs > 10000 then
		return "Dance Dance Maniac",(11)
	elseif numSongs > 7500 then
		return "I ❤️ Dance Games",(10)
	elseif numSongs > 5000 then
		return "Broken",(9)
	elseif numSongs > 4000 then
		return "Not Casual",(8)
	elseif numSongs > 3000 then
		return "Groove Master",(7)
	elseif numSongs > 2000 then
		return "DDR God",(6)
	elseif numSongs > 1000 then
		return "Maniac",(5)
	elseif numSongs > 750 then
		return "True Gamer",(4)
	elseif numSongs > 500 then
		return "Insane",(3)
	elseif numSongs > 250 then
		return "Competitive", (2)
	elseif numSongs > 100 then
		return "Casual", (1)
	elseif numSongs > 50 then
		return "Casual", (0)
	else
		return "Casual",-1
	end
end

-- ----------------------------------------------------
-- Retrieve and process data (mods, most recently played song, high score name, etc.)
-- for each available local profile and put it in the profile_data table.
-- Since both players are using the same list of local profiles, this only needs to be performed once (not once for each player).
-- I'm doing it here, in PlayerProfileData.lua, to keep default.lua from growing too large/unwieldy.  Once done, pass the
-- table of data back default.lua where it can be sent via playcommand parameter to the appropriate PlayerFrames as needed.

local profile_data = {}
--Handle Guest Profile
GetMachineProfileData = function()
	-- Get Machine Profile
	local profile = PROFILEMAN:GetMachineProfile()
	-- GetLocalProfileIDFromIndex() also expects indices to start at 0
	local sweatLevel, ribbon = SweatLevelRibbon(profile)
	local data = {
		index = 0,
		dir = nil,
		lifeMeterType = nil,
		sweatLevel = sweatLevel,
		timePlayed = roundToDecimal((profile:GetTotalGameplaySeconds()/60)/60, 2),
		displayname = THEME:GetString("ScreenSelectProfile", "GuestProfile"),
		highscorename = profile:GetLastUsedHighScoreName(),
		recentsong = ValidSong(profile:GetLastPlayedSong()),
		totalsongs = TotalSongs(profile:GetNumTotalSongsPlayed()),
		ribbon = ribbon,
		mods = nil,
		popularSong = ValidSong(profile:GetMostPopularSong()),
		noteskin = "cel",
		judgment = "Love",
		guid = profile:GetGUID(),
		achievementIndex = 1,
		packIndex = 1,
		achievements = nil,
		activePack = "Default",
		inUse = false,
	}
	return data
end


for i=1, PROFILEMAN:GetNumLocalProfiles() do

	-- GetLocalProfileFromIndex() expects indices to start at 0
	local profile = PROFILEMAN:GetLocalProfileFromIndex(i-1)
	-- GetLocalProfileIDFromIndex() also expects indices to start at 0
	local id = PROFILEMAN:GetLocalProfileIDFromIndex(i-1)
	local dir = PROFILEMAN:LocalProfileIDToDir(id)
	local userprefs = RetrieveProfileData(profile, dir)
	local groovestats = RetrieveGrooveStatsData(dir)
	local mods, noteskin, judgment, speedMod, speedModType, lifeMeterType = RecentMods(userprefs)
	local sweatLevel, ribbon = SweatLevelRibbon(profile)
	local data = {
		index = i,
		dir = dir,
		speedmod = speedMod,
		speedModType = speedModType,
		lifeMeterType = lifeMeterType,
		sweatLevel = sweatLevel,
		timePlayed = roundToDecimal((profile:GetTotalGameplaySeconds()/60)/60, 2),
		displayname = profile:GetDisplayName(),
		highscorename = profile:GetLastUsedHighScoreName(),
		recentsong = ValidSong(profile:GetLastPlayedSong()),
		totalsongs = TotalSongs(profile:GetNumTotalSongsPlayed()),
		ribbon = ribbon,
		mods = mods,
		popularSong = ValidSong(profile:GetMostPopularSong()),
		noteskin = noteskin,
		judgment = judgment,
		guid = profile:GetGUID(),
		apikey = groovestats and groovestats.ApiKey or "",
		achievementIndex = 1,
		achievements = RetrieveProfileAchievements(profile, dir),
		activePack = "Default",
		inUse = isProfileLocked({index = i, dir = dir, displayname = profile:GetDisplayName()}),
	}

	table.insert(profile_data, data)
end

return profile_data, GetMachineProfileData()
