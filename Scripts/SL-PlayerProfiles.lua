-- It's possible for players to edit their Simply Love UserPrefs.ini file
-- in various ways that might break the theme.  Also, sometimes theme-specific mods
-- are deprecated or change their internal name, leaving old values behind in player profiles
-- that might break the theme as well. Use this table to validate settings read in
-- from and written out to player profiles.
--
-- For now, this table is local to this file, but might be moved into the SL table (or something)
-- in the future to facilitate type checking in ./Scripts/SL-PlayerOptions.lua and elsewhere.

local permitted_profile_settings = {

	----------------------------------
	-- "Main Modifiers"
	-- OptionRows that appear in SL's first page of PlayerOptions

	SpeedModType     = "string",
	SpeedMod         = "number",
	Mini             = "string",
	NoteSkin         = "string",
	JudgmentGraphic  = "string",
	ComboFont        = "string",
	HoldJudgment     = "string",
	BackgroundFilter = "string",
	BackgroundColor  = "string",
	NoteFieldOffsetX = "number",
	NoteFieldOffsetY = "number",
	VisualDelay      = "string",

	----------------------------------
	-- "Advanced Modifiers"
	-- OptionRows that appear in SL's second page of PlayerOptions

	HideTargets          = "boolean",
	HideSongBG           = "boolean",
	HideCombo            = "boolean",
	HideLifebar          = "boolean",
	HideScore            = "boolean",
	HideDanger           = "boolean",
	HideComboExplosions  = "boolean",

	LifeMeterType        = "string",
	DataVisualizations   = "string",
	TargetScore          = "number",
	ActionOnMissedTarget = "string",

	MeasureCounter       = "string",
	MeasureCounterLeft   = "boolean",
	MeasureCounterUp     = "boolean",
	HideLookahead        = "boolean",

	MeasureLines         = "string",

	ColumnFlashOnMiss    = "boolean",
	SubtractiveScoring   = "boolean",
	Pacemaker            = "boolean",
	NPSGraphAtTop        = "boolean",
	JudgmentTilt         = "boolean",
	TiltMultiplier       = "number",
	ColumnCues           = "boolean",
	DisplayScorebox      = "boolean",

	ErrorBar             = "string",
	ErrorBarUp           = "boolean",
	ErrorBarMultiTick    = "boolean",
	ErrorBarTrim         = "string",

	ShowFaPlusWindow     = "boolean",
	ShowExScore          = "boolean",
	ShowFaPlusPane       = "boolean",

	HideEarlyDecentWayOffJudgments = "boolean",
	HideEarlyDecentWayOffFlash     = "boolean",

	----------------------------------
	-- Profile Settings without OptionRows
	-- these settings are saved per-profile, but are transparently managed by the theme
	-- they have no player-facing OptionRows

	PlayerOptionsString = "string",
}

-- -----------------------------------------------------------------------

local theme_name = THEME:GetThemeDisplayName()
local filename =  theme_name .. " UserPrefs.ini"
-- Function called when a [GUEST] joins during SSM, either by late joining or via the fast
-- profile switcher. It does two things:
-- 1) properly reset profile state (e.g. modifiers), and
-- 2) persist any state that should survive a profile switch (e.g., session history
--    in SL[pn].Stages with songs played for displaying on ScreenEvaluationSummary).
-- LoadProfileCustom takes care of this for persistent profiles.
LoadGuest = function(player)
	GAMESTATE:ResetPlayerOptions(player)
	local pn = ToEnumShortString(player)
	local stages = SL[pn].Stages
	SL[pn]:initialize()
	SL[pn].Stages = stages
end


RetrieveProfileAchievements = function(player)
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

	local profile_slot = {
		[PLAYER_1] = "ProfileSlot_Player1",
		[PLAYER_2] = "ProfileSlot_Player2"
	}
	
	local dir = PROFILEMAN:GetProfileDir(profile_slot[player])
	local pn = ToEnumShortString(player)
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

-- function assigned to "CustomLoadFunction" under [Profile] in metrics.ini
LoadProfileCustom = function(profile, dir)
	local path =  dir .. filename
	local player, pn, filecontents

	-- we've been passed a profile object as the variable "profile"
	-- see if it matches against anything returned by PROFILEMAN:GetProfile(player)
	for p in ivalues( GAMESTATE:GetHumanPlayers() ) do
		if profile == PROFILEMAN:GetProfile(p) then
			player = p
			pn = ToEnumShortString(p)
			break
		end
	end

	if pn then
		-- Remember and persist stats about songs played across profile switches
		local stages = SL[pn].Stages

		SL[pn]:initialize()
		ParseGrooveStatsIni(player)
		ReadItlFile(player)
		SL[pn].AchievementData = RetrieveProfileAchievements(player)
		-- SM("Achievement Data Loaded")
		SL[pn].Stages = stages

		-- Fetch latest ITL achievements in the background on profile login
		RefreshITLAchievementsForPlayer(player)
	end

	if pn and FILEMAN:DoesFileExist(path) then
		filecontents = IniFile.ReadFile(path)[theme_name]

		-- for each key/value pair read in from the player's profile
		for k,v in pairs(filecontents) do
			-- ensure that the key has a corresponding key in permitted_profile_settings
			if permitted_profile_settings[k]
			--  ensure that the datatype of the value matches the datatype specified in permitted_profile_settings
			and type(v)==permitted_profile_settings[k] then
				-- if the datatype is string and this key corresponds with an OptionRow in ScreenPlayerOptions
				-- ensure that the string read in from the player's profile
				-- is a valid value (or choice) for the corresponding OptionRow
				if type(v) == "string" and CustomOptionRow(k) and FindInTable(v, CustomOptionRow(k).Values or CustomOptionRow(k).Choices)
				or type(v) ~= "string" then
					SL[pn].ActiveModifiers[k] = v
				end

				-- special-case PlayerOptionsString for now
				-- it is saved to and read from profile as a string, but doesn't have a corresponding
				-- OptionRow in ScreenPlayerOptions, so it will fail validation above
				-- we want engine-defined mods (e.g. dizzy) to be applied as well, not just SL-defined mods
				if k=="PlayerOptionsString" and type(v)=="string" then
					-- v here is the comma-delimited set of modifiers the engine's PlayerOptions interface understands

					-- use the engine's SetPlayerOptions() method to set a whole bunch of mods in the engine all at once
					GAMESTATE:GetPlayerState(player):SetPlayerOptions("ModsLevel_Preferred", v)
					-- Special case timing windows as they're not controllable in SL.
					GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred"):ResetDisabledTimingWindows()

					-- However! It's quite likely that a FailType mod could be in that^ string, meaning a player could
					-- have their own setting for FailType saved to their profile.  I think it makes more sense to let
					-- machine operators specify a default FailType at a global/machine level, so use this opportunity to
					-- use the PlayerOptions interface to set FailSetting() using the default FailType setting from
					-- the operator menu's Advanced Options
					GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred"):FailSetting( GetDefaultFailType() )
					
					-- Finally extract out the PlayerOptionsString by the fetching it from the engine
					-- Update the SL table so that this PlayerOptionsString value is easily accessible throughout the theme
					SL[pn].PlayerOptionsString = GAMESTATE:GetPlayerState(player):GetPlayerOptionsString("ModsLevel_Preferred")
				end
			end
		end
	end

	return true
end

LoadAllAchievements = function()
	local accolades = {}
	-- Get all Achievement Packs from the Achievements folder
	local achievementPacks = FILEMAN:GetDirListing(THEME:GetCurrentThemeDirectory().."Other/Achievements/")
	for pack in ivalues(achievementPacks) do
		if pack then
			local packName = pack:match("([^/]+)$")
			local packPath = THEME:GetCurrentThemeDirectory().."Other/Achievements/"..packName.."/"
			local packFiles = FILEMAN:GetDirListing(packPath)
			-- Load the achievement file for each pack
			local achievement = packPath.."Achievements.lua"
			if FILEMAN:DoesFileExist(achievement) then
				local achiev = dofile(achievement)
				-- We don't want spaces in the pack name
				packName = packName:gsub("%s+", "_")
				accolades[packName] = achiev
			-- elseif FILEMAN:DoesFileExist(packPath.."Achievements.json") then
			-- 	local achiev = JsonDecode(FILEMAN:ReadFile(packPath.."Achievements.json"))
			-- 	-- We don't want spaces in the pack name
			-- 	packName = packName:gsub("%s+", "_")
			-- 	accolades[packName] = achiev
			-- 	accolades[packName].isJson = true
			-- else
			-- 	--SM("No achievements found for "..packName)
			end
		end
	end
	return accolades
end

ValidateAchievements = function(player)
 	local pn = ToEnumShortString(player)

	-- Only validate achievements if the player has a loaded profile
	if not PROFILEMAN:IsPersistentProfile(player) then return end

	-- Loop through all available achievement packs
	for pack,achievements in pairs(SL.Accolades.Achievements) do
		-- If the pack has achievements proceed
		if achievements then
			-- If the player has no achievement data for this pack, create it
			if not SL[pn].AchievementData[pack] then
				SL[pn].AchievementData[pack] = {}
				for i, achievement in ipairs(achievements) do
					SL[pn].AchievementData[pack][i] = {}
					SL[pn].AchievementData[pack][i].Date = nil
					SL[pn].AchievementData[pack][i].ID = achievement.ID
					SL[pn].AchievementData[pack][i].Name = achievement.Name
					--SL[pn].AchievementData[pack][i].Data = achievement.Data
					if achievement.Condition then
						SL[pn].AchievementData[pack][i].Unlocked = achievement.Condition(pn)
					else
						SL[pn].AchievementData[pack][i].Unlocked = false
					end
				end
			else
				for i, achievement in ipairs(achievements) do
					-- If the player has no achievement data for this achievement, create it
					if not SL[pn].AchievementData[pack][i] then
						SL[pn].AchievementData[pack][i] = {}
						SL[pn].AchievementData[pack][i].Date = nil
						SL[pn].AchievementData[pack][i].ID = achievement.ID
						SL[pn].AchievementData[pack][i].Name = achievement.Name
					--	SL[pn].AchievementData[pack][i].Data = achievement.Data
						if achievement.Condition then
							SL[pn].AchievementData[pack][i].Unlocked = achievement.Condition(pn)
						else
							SL[pn].AchievementData[pack][i].Unlocked = false
						end
					else
						if not SL[pn].AchievementData[pack][i].Unlocked then
							SL[pn].AchievementData[pack][i].Unlocked = achievement.Condition and achievement.Condition(pn) or false
						end
					end
					if (SL[pn].AchievementData[pack][i].Unlocked and not SL[pn].AchievementData[pack][i].Date) then
						local DateFormat = "%02d/%02d/%04d  %02d:%02d"
						SL[pn].AchievementData[pack][i].Date = DateFormat:format(MonthOfYear()+1, DayOfMonth(), Year() , Hour(), Minute())
						SL.Accolades.Notifications[pn].achievements[#SL.Accolades.Notifications[pn].achievements+1] = {Player = player, Pack = pack, Achievement = i, Name = achievement.Name, Desc = achievement.Desc}
					end
				end
			end
		end
	end
	if #SL.Accolades.Notifications[pn].achievements > 0 then
		MESSAGEMAN:Broadcast("AchievementUnlocked")
		MESSAGEMAN:Broadcast("AchievementUnlocked"..pn)
	end
end

-- ValidateAchievementsForPack = function(player, _pack)
-- 	local pn = ToEnumShortString(player)
--    -- Loop through all available achievement packs
--    for pack,achievements in pairs(SL.Accolades.Achievements) do
-- 		if pack == _pack then
-- 			-- If the pack has achievements proceed
-- 			if achievements then
-- 				-- If the player has no achievement data for this pack, create it
-- 				if not SL[pn].AchievementData[pack] then
-- 					SL[pn].AchievementData[pack] = {}
-- 					for i, achievement in ipairs(achievements) do
-- 						SL[pn].AchievementData[pack][i] = {}
-- 						if achievement.Condition then
-- 							SL[pn].AchievementData[pack][i].Unlocked = achievement.Condition(pn)
-- 						else
-- 							SL[pn].AchievementData[pack][i].Unlocked = false
-- 						end
-- 						SL[pn].AchievementData[pack][i].Date = nil
-- 						SL[pn].AchievementData[pack][i].ID = achievement.ID
-- 						SL[pn].AchievementData[pack][i].Data = achievement.Data
-- 					end
-- 				else
-- 					for i, achievement in ipairs(achievements) do
-- 						-- If the player has no achievement data for this achievement, create it
-- 						if not SL[pn].AchievementData[pack][i] then
-- 							SL[pn].AchievementData[pack][i] = {}
-- 							if achievement.Condition then
-- 								SL[pn].AchievementData[pack][i].Unlocked = achievement.Condition(pn)
-- 							else
-- 								SL[pn].AchievementData[pack][i].Unlocked = false
-- 							end
-- 							SL[pn].AchievementData[pack][i].Date = nil
-- 							SL[pn].AchievementData[pack][i].ID = achievement.ID
-- 							SL[pn].AchievementData[pack][i].Data = achievement.Data
-- 						else
-- 							SL[pn].AchievementData[pack][i].Unlocked = achievement.Condition and achievement.Condition(pn) or false
-- 						end
-- 					end
-- 				end
-- 			end
-- 		end
--    end
-- end

UpdateAchievements = function(player)

	local pn = ToEnumShortString(player)
	if (SL.Global.Stages.PlayedThisGame <= 0) then
		return
	end

	if not SL[pn].AchievementData then
		--SM("No achievement data found for "..pn.."...")
	else
		ValidateAchievements(player)
		--SM("Updating achievements for "..pn.."...")
		local profile_slot = {
			[PLAYER_1] = "ProfileSlot_Player1",
			[PLAYER_2] = "ProfileSlot_Player2"
		}
		
		local dir = PROFILEMAN:GetProfileDir(profile_slot[player])

		-- We require an explicit profile to be loaded.
		if not dir or #dir == 0 then return end

		path = dir .. "Achievements.json"
		local f = RageFileUtil:CreateRageFile()
		--SM(SL[pn].AchievementData)
		if f:Open(path, 2) then
			f:Write(JsonEncode(SL[pn].AchievementData, true))
			f:Close()
		end
		f:destroy()
	end

end

-- function assigned to "CustomSaveFunction" under [Profile] in metrics.ini
SaveProfileCustom = function(profile, dir)

	local path =  dir .. filename

	for player in ivalues( GAMESTATE:GetHumanPlayers() ) do
		if profile == PROFILEMAN:GetProfile(player) then
			local pn = ToEnumShortString(player)
			local output = {}
			for k,v in pairs(SL[pn].ActiveModifiers) do
				if permitted_profile_settings[k] and type(v)==permitted_profile_settings[k] then
					output[k] = v
				end
			end

			-- these values are saved outside the SL[pn].ActiveModifiers tables
			-- and thus won't be handled in the loop above
			output.PlayerOptionsString = SL[pn].PlayerOptionsString

			IniFile.WriteFile( path, {[theme_name]=output} )

			WriteGrooveStatsIni(player)
			-- Write to the ITL file if we need to.
			-- This is relevant for memory cards.
			WriteItlFile(player)
			break
		end
	end

	return true
end

-- -----------------------------------------------------------------------
-- returns a path to a profile avatar, or nil if none is found

GetAvatarPath = function(profileDirectory, displayName)

	if type(profileDirectory) ~= "string" then return end

	local path = nil

	-- sequence matters here
	-- prefer png first, then jpg, then jpeg, etc.
	-- (note that SM5 does not support animated gifs at this time, so SL doesn't either)
	-- TODO: investigate effects (memory footprint, fps) of allowing movie files as avatars in SL
	local extensions = { "png", "jpg", "jpeg", "bmp", "gif", "mp4" }

	-- prefer an avatar named:
	--    "avatar" in the player's profile directory (preferred by Simply Love)
	--    then "profile picture" in the player's profile directory (used by Digital Dance)
	--    then (whatever the profile's DisplayName is) in /Appearance/Avatars/ (used in OutFox?)
	local paths = {
		("%savatar"):format(profileDirectory),
		("%sprofile picture"):format(profileDirectory),
		("/Appearance/Avatars/%s"):format(displayName)
	}

	for _, path in ipairs(paths) do
		for _, extension in ipairs(extensions) do
			local avatar_path = ("%s.%s"):format(path, extension)

			if FILEMAN:DoesFileExist(avatar_path)
			and (ActorUtil.GetFileType(avatar_path)   == "FileType_Bitmap"
			    or ActorUtil.GetFileType(avatar_path) == "FileType_Movie")
			then
				-- return the first valid avatar path that is found
				return avatar_path
			end
		end
	end

	-- or, return nil if no avatars were found in any of the permitted paths
	return nil
end

-- -----------------------------------------------------------------------
-- returns a path to a player's profile avatar, or nil if none is found

GetPlayerAvatarPath = function(player)
	if not player then return end

	local profile_slot = {
		[PLAYER_1] = "ProfileSlot_Player1",
		[PLAYER_2] = "ProfileSlot_Player2"
	}

	if not profile_slot[player] then return end

	local dir  = PROFILEMAN:GetProfileDir(profile_slot[player])
	local name = PROFILEMAN:GetProfile(player):GetDisplayName()

	return GetAvatarPath(dir, name)
end
GetScreenshotsPath = function(profileDirectory, displayName)

	if type(profileDirectory) ~= "string" then return end

	local path = nil

	-- sequence matters here
	-- prefer png first, then jpg, then jpeg, etc.
	-- (note that SM5 does not support animated gifs at this time, so SL doesn't either)
	-- TODO: investigate effects (memory footprint, fps) of allowing movie files as avatars in SL
	local extensions = { "png", "jpg", "jpeg", "bmp", "gif", "mp4" }

	-- prefer an avatar named:
	--    "avatar" in the player's profile directory (preferred by Simply Love)
	--    then "profile picture" in the player's profile directory (used by Digital Dance)
	--    then (whatever the profile's DisplayName is) in /Appearance/Avatars/ (used in OutFox?)
	local dascreens = {}
	path = ("%s/Screenshots/Simply_love/"):format(profileDirectory)
	local pathos = " "
	local year = FILEMAN:GetDirListing(path.."/", true, true)
	if year then
		for  _, monthInYear in ipairs(year) do 
			local months = FILEMAN:GetDirListing(monthInYear.."/", true, true)
			if months then
				for _, month in ipairs(months) do
					local screenies = FILEMAN:GetDirListing(month.."/", false, true)
					if screenies then
						for _, screenshot in ipairs(screenies) do
							table.insert(dascreens, screenshot)
						 end
					end							
				end
			end
		end
	end
	return dascreens

	-- or, return nil if no avatars were found in any of the permitted paths
	--return pathos
end

GetPlayerScreenshotsPath = function(player)
	if not player then	return end
	local profile_slot = {
		[PLAYER_1] = "ProfileSlot_Player1",
		[PLAYER_2] = "ProfileSlot_Player2"
	}

	if not profile_slot[player] then return end

	local dir  = PROFILEMAN:GetProfileDir(profile_slot[player])
	local name = PROFILEMAN:GetProfile(player):GetDisplayName()
	return GetScreenshotsPath(dir, name)
end
