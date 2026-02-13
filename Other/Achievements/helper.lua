function TrialCheck(pn,trial)
	local profile = PROFILEMAN:GetProfile(pn)
	local trialMap = SL.Global.TrialMap[trial]
	if trialMap then
		for song, i in ivalues(trialMap) do
			if song then
				if not profile:HasPassedAnyStepsInSong(song) then
					return false;
				end
			end
		end
		return true
	else
		return false
	end
end

function HasPassed(pn,song)
	local profile = PROFILEMAN:GetProfile(pn)
	if song then
		if profile:HasPassedAnyStepsInSong(song) then
			return true;
		else
			return false
		end
	else
		return false
	end
end

-- Returns True if rate mod is at least 1
function RateCheck()
    local rateMod
    if GAMESTATE:GetSongOptionsString() == '' then
        rateMod = '1.00'
    else
        rateMod = string.format("%.2f",string.sub(GAMESTATE:GetSongOptionsString(), 1,string.len(GAMESTATE:GetSongOptionsString()) - 6))
    end
    return tonumber(rateMod) >= 1
end

-- Returns rate mod
function RateCheck2()
    local rateMod
    if GAMESTATE:GetSongOptionsString() == '' then
        rateMod = '1.00'
    else
        rateMod = string.format("%.2f",string.sub(GAMESTATE:GetSongOptionsString(), 1, string.len( GAMESTATE:GetSongOptionsString()) - 6))
    end
    return tonumber(rateMod)
end

function PassCheck(pn)
    if RateCheck() then
        return not STATSMAN:GetCurStageStats():GetPlayerStageStats(pn):GetFailed()
    else
        return false
    end
end
function BPMCheck(pn, bpm, greaterThan)
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
	local song = GAMESTATE:GetCurrentSong()
	local bpms = song:GetDisplayBpms()
	local averageBpm = (bpms[1] + bpms[2]) / 2
	if greaterThan then
		return averageBpm >= bpm
	else
		return averageBpm <= bpm
	end
end

function BPMCheckRange(pn, bpm1, bpm2)
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
	local song = GAMESTATE:GetCurrentSong()
	local bpms = song:GetDisplayBpms()
	local bpm = (bpms[1] + bpms[2]) / 2
	-- I don't know why this is the case, but this is REALLY sensitive to how you write your conditionals.
	-- I had to write it like this to get it to work, rather than as a one liner.
	if ((bpm >= bpm1)) then
		if (bpm <= bpm2) then
			return true
		end
	end
	return false
end

function ScoreCheck(pn, score, greaterThan)
    local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
    local PercentDP = stats:GetPercentDancePoints()
    local percent = FormatPercentScore(PercentDP)
    -- Format the Percentage string, removing the % symbol
    percent = percent:gsub("%%", "")
    if not stats:GetFailed() then
        return greaterThan and tonumber(percent) >= score or tonumber(percent) <= score
    else
        return false
    end
end

function TimingWindowCheck(pn, window, amount, greaterThan)
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
	local number = stats:GetTapNoteScores( "TapNoteScore_"..window )
	if greaterThan then
		return number >= amount
	else
		return number <= amount
	end
end

function _GetTapNoteScores(pn, window)
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
	return stats:GetTapNoteScores( "TapNoteScore_"..window )
end
function ComboCheck(pn, amount, greaterThan)
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
	local number = stats:GetCurrentCombo()
	return greaterThan and number >= amount or number <= amount
end

function RadarCheck(pn, RCType, amount, greaterThan)
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
	local performance = stats:GetRadarActual():GetValue( "RadarCategory_"..RCType )
	return greaterThan and performance >= amount or performance <= amount
end

-- -----------------------------------------------------------------------
-- Convenience function to return the SongOrCourse and StepsOrTrail for a
-- for a player.
local GetSongAndSteps = function(player)
    local SongOrCourse = (GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentCourse()) or GAMESTATE:GetCurrentSong()
    local StepsOrTrail = (GAMESTATE:IsCourseMode() and GAMESTATE:GetCurrentTrail(player)) or GAMESTATE:GetCurrentSteps(player)
    return SongOrCourse, StepsOrTrail
end

-- -----------------------------------------------------------------------
local GetScoreFromProfile = function(profile, SongOrCourse, StepsOrTrail)
    -- if we don't have everything we need, return nil
    if not (profile and SongOrCourse and StepsOrTrail) then return nil end

    return profile:GetHighScoreList(SongOrCourse, StepsOrTrail):GetHighScores()[1]
end

local GetScoreForPlayer = function(player)
    local highScore
    if PROFILEMAN:IsPersistentProfile(player) then
        local SongOrCourse, StepsOrTrail = GetSongAndSteps(player)
        highScore = GetScoreFromProfile(PROFILEMAN:GetProfile(player), SongOrCourse, StepsOrTrail)
    end
    return highScore
end

function HasPassed(pn)
    if PassCheck(pn) then
        return true
    else
        local highScore = GetScoreForPlayer(pn)
        if highScore then return highScore:GetGrade() ~= 'Grade_Failed' end
    end
    return false
end

function updateSingleProgress(pn, pack, i, amount)
	if SL[pn].AchievementData[pack][i].Data then
		if SL[pn].AchievementData[pack][i].Data.Progress then
			SL[pn].AchievementData[pack][i].Data.Progress = SL[pn].AchievementData[pack][i].Data.Progress + amount
		else
			SL[pn].AchievementData[pack][i].Data.Progress = amount
		end
	else
		SL[pn].AchievementData[pack][i].Data = {Progress = amount, Target = SL.Accolades.Achievements[pack][i].Data.Target}
	end
	if SL[pn].AchievementData[pack][i].Data.Progress >= SL[pn].AchievementData[pack][i].Data.Target then
		return true
	end
	return false
end

function updateMultiProgress(pn, pack, i, incrementTable)
	-- Increment table can look like { Holds = 1, Mines = 2, Jumps = 3 }
	-- This will increment the Holds progress by 1, Mines by 2, and Jumps by 3
	-- We will loop through the table and add the values to the achievement data
	if SL[pn].AchievementData[pack][i].Data then
		for k,v in pairs(incrementTable) do
			if SL[pn].AchievementData[pack][i].Data[k] then
				SL[pn].AchievementData[pack][i].Data[k].Progress = SL[pn].AchievementData[pack][i].Data[k].Progress + v
			else
				SL[pn].AchievementData[pack][i].Data[k] = {Progress = v, Target = SL.Accolades.Achievements[pack][i].Data[k].Target}
			end
		end
	else
		SL[pn].AchievementData[pack][i].Data = {}
		for k,v in pairs(incrementTable) do
			SL[pn].AchievementData[pack][i].Data[k] = {Progress = v, Target = SL.Accolades.Achievements[pack][i].Data[k].Target}
		end
	end
end

function updatePassData(pn, pack, i)
    local songName = GAMESTATE:GetCurrentSong():GetDisplayMainTitle()
    local difficulty = GAMESTATE:GetCurrentSteps(pn):GetDifficulty()
    if SL[pn].AchievementData[pack][i].Data then
        if SL[pn].AchievementData[pack][i].Data.Pass then
            if SL[pn].AchievementData[pack][i].Data.Pass[songName] then
                if SL[pn].AchievementData[pack][i].Data.Pass[songName][difficulty] then
                    if not SL[pn].AchievementData[pack][i].Data.Pass[songName][difficulty].played then
                        SL[pn].AchievementData[pack][i].Data.Pass[songName][difficulty].played = true
                    end
                    if not SL[pn].AchievementData[pack][i].Data.Pass[songName][difficulty].passed then
                        SL[pn].AchievementData[pack][i].Data.Pass[songName][difficulty] = HasPassed(pn)
                    end
                else
                    SL[pn].AchievementData[pack][i].Data.Pass[songName][difficulty] = {played = true, passed = HasPassed(pn)}
                end
            else
                SL[pn].AchievementData[pack][i].Data.Pass[songName] = {
                    [difficulty] = {played = true, passed = HasPassed(pn)}
                }
            end
        else
            SL[pn].AchievementData[pack][i].Data.Pass = {
                [songName] = {
                    [difficulty] = {played = true, passed = HasPassed(pn)}
                }
            }
        end
    else
        SL[pn].AchievementData[pack][i].Data = {
            Pass = {
                [songName] = {
                    [difficulty] = {played = true, passed = HasPassed(pn)}
                }
            }
        }
    end
end

function checkSingleProgress(pn, pack, i)
	if SL[pn].AchievementData[pack][i].Data then
		if SL[pn].AchievementData[pack][i].Data.Progress then
			return SL[pn].AchievementData[pack][i].Data.Progress >= SL[pn].AchievementData[pack][i].Data.Target
		end
	end
	return false
end

function checkMultiProgress(pn, pack, i)
	if SL[pn].AchievementData[pack][i].Data then
		for k,v in pairs(SL[pn].AchievementData[pack][i].Data) do
			if v.Progress < v.Target then
				return false
			end
		end
		return true
	end
	return false
end

-- { StepType = - steps type here -, Difficulty = -difficulty here-}
-- StepsType = * -> Singles and Doubles
-- Difficulty = * -> All difficulties
-- Otherwise we receive a table of specific songs and difficulties
function checkPassData(pn, pack, i, groupName)
	local profile = PROFILEMAN:GetProfile(pn)
	local requiredSongDifficulties = SL.Accolades.Achievements[pack][i].Data.RequiredPasses
	if requiredSongDifficulties then
		for song,difficulties in pairs(requiredSongDifficulties) do
			if not SL[pn].AchievementData[pack][i].Data.Pass[song] then
				return false
			end
			for difficulty,v in pairs(difficulties) do
				if difficulty == "Any" then
					local passed = false
					for diff,i in pairs(SL[pn].AchievementData[pack][i].Data.Pass[song]) do
						if SL[pn].AchievementData[pack][i].Data.Pass[song][diff].passed then
							passed = true
							break;
						end
					end
					if not passed then
						return false
					end
				else
					if not SL[pn].AchievementData[pack][i].Data.Pass[song][difficulty] then
						return false
					end
					if not SL[pn].AchievementData[pack][i].Data.Pass[song][difficulty].passed then
						return false
					end
				end
			end
		end
		return true
	else
		local requirement = SL.Accolades.Achievements[pack][i].Data.ClearType
		if requirement == "Any" then
			for i, song in ipairs(SONGMAN:GetSongsInGroup(groupName)) do
				if not profile:HasPassedAnyStepsInSong(song) then
					return false
				end
			end
			return true
		elseif requirement == "Single" then
			if not SL[pn].AchievementData[pack][i].Data.Pass[song:GetDisplayMainTitle()] then
				return false
			end
			local passed = false
			for difficulty,v in pairs(SL[pn].AchievementData[pack][i].Data.Pass[song:GetDisplayMainTitle()]) do
				if v.passed then
					passed = true;
					break;
				end
			end
			if not passed then
				return false
			end
			return true;
		elseif requirement == "*" then
			for i, song in ipairs(SONGMAN:GetSongsInGroup(groupName)) do
				if not SL[pn].AchievementData[pack][i].Data.Pass[song:GetDisplayMainTitle()] then
					return false
				end
				local passed = false
				for difficulty,v in pairs(SL[pn].AchievementData[pack][i].Data.Pass[song:GetDisplayMainTitle()]) do
					if not v.passed then
						passed = true;
						break;
					end
				end
				if not passed then
					return false
				end
			end
			return true;
		elseif requirement == "**" then
			for i, song in ipairs(SONGMAN:GetSongsInGroup(groupName)) do
				if not SL[pn].AchievementData[pack][i].Data.Pass[song:GetDisplayMainTitle()] then
					return false
				end
				for difficulty,v in pairs(SL[pn].AchievementData[pack][i].Data.Pass[song:GetDisplayMainTitle()]) do
					if not v.passed then
						return false
					end
				end
			end
			return true;
		elseif requirement == "Easy*" then
			for i, song in ipairs(SONGMAN:GetSongsInGroup(groupName)) do
				if not SL[pn].AchievementData[pack][i].Data.Pass[song:GetDisplayMainTitle()] then
					return false
				end
				if not SL[pn].AchievementData[pack][i].Data.Pass[song:GetDisplayMainTitle()]["Difficulty_Easy"].passed then
					return false
				end
			end
			return true;
		end
	end
	return false
end


function checkPlayedData(pn, pack, i)
	local requiredSongDifficulties = SL.Accolades.Achievements[pack][i].Data.RequiredPlays
	if requiredSongDifficulties then
		for song,difficulties in pairs(requiredSongDifficulties) do
			if not SL[pn].AchievementData[pack][i].Data.Pass[song] then
				return false
			end
			for difficulty,v in pairs(difficulties) do
				if difficulty == "Any" then
					local played = false
					for diff,i in pairs(SL[pn].AchievementData[pack][i].Data.Pass[song]) do
						if SL[pn].AchievementData[pack][i].Data.Pass[song][diff].played then
							played = true
							break;
						end
					end
					if not played then
						return false
					end
				else
					if not SL[pn].AchievementData[pack][i].Data.Pass[song][difficulty] then
						return false
					end
					if not SL[pn].AchievementData[pack][i].Data.Pass[song][difficulty].played then
						return false
					end
				end
			end
		end
		return true
	end
	return false
end

	