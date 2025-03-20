local t = {}
local discordPresence = {
    startTime = 0,
    endTime = 0,
    totalTime = os.time(),
    lastSeenSong = "",
    smalltext = "",
    state = "",
    details = "",
    largetext = "",
    sync_interval = 400
}
local quotes = {
    "Let's Groove Tonight...",
    "Put your Mask Up",
    "My arrows are getting cold 🥶",
    "My arrows are getting cold 😢",
    "🤧 I think I've caught something, and you're the cure 💓",
    "You were always my favorite 🙈",
    "When will I see you again?",
    "When will I see you again?",
    "I'm a little teapot",
    "I miss you 😔",
    "Awaiting Dance Gamers....",
    "Awaiting Dance Gamers....",
    "Awaiting Dance Gamers....", 
    "Awaiting Dance Gamers....",
    "Step on me...? 🥺👉👈", 
    "Step on me...? 🥺👉👈",
    "Let's Groove Tonight...", 
    "Step on me...please?", 
    "Step on me...please?",
    "Step on me when??", 
    "What'll be today? 💪", 
    "Stamina?", 
    "Footspeed",
    "Time for some FA practice ay?", 
    "Accuracy?",
    "Prices going up to $1 for 1 song! See this is why you shouldn't have left 😜",
    "I'm not a bot, I swear", 
    "owo?", 
    "uwu?", 
    "When will I see you again 😿?",
    "When will I see you again 👉👈", 
    "🥺👉👈",
    "Feeling a little lonely today...", 
    "Waiting....", "You're beautiful 😍",
    "'Tis but a scratch", 
    "I'm not dead yet", 
    "Let's get this party started",
    "The Letter of the Day is 'S'",
    "Bass Kick? Box? Megolovania? Honestly, I don't even understand what's on my screen 😵",
    "Hey You! Yeah, you! Come to Pollock pls 🥺",
    "Hey You! Yeah, you! Come to Pollock pls", 
    "Come to Pollock 🥺👉👈",
    "😏 https://youtu.be/izGwDsrQ1eQ", 
    "Did you turn the fans off? 😠",
    "I'm not a bot, I swear", 
    "I'm not a bot, I swear",
    "\"Cinnamon Sugar Pancake\"? Eh, I prefer Chocolate chip",
    "My bars are ready", 
    "Letsa Go!", 
    "Ok ok, I'm done", 
    "💤💤💤💤",
    "💤💤💤", 
    "💤💤💤", 
    "💤💤💤", 
    "💤💤💤",
    "💤💤💤", 
    "😪💤", 
    "😪💤", 
    "😪💤", 
    "😴", 
    "😪💤",
    "💤", 
    "🥱", 
    "🥱 I'm boreedddddddd", 
    "🍉",
    "🍎", 
    "🍌", 
    "🍇",
    "🍓", 
    "🍑", 
    "🍒", 
    "🍍", 
    "🍐", 
    "🍊",
    "Looking good! Keep up the good work!",
    "Hey Hey, Look at Me. You Are Amazing.", 
    "Loving this weather 🥰",
    "Omg, I love this song! 🥰🥰", 
    "Where have you been 😿",
    "You're not here 💔", 
    "The Letter of the Day is 'O'",
    "You know...Pollock has chairs too...", 
    "It's been a while :(",
    "🎵 La La La La La La La 🎵", 
    "2 Songs 1 Quarter 😏",
    "Are you as swift as a coursing river?",
    "Have you the strength of a raging fire?", 
    "Fine...I see how it is",
    "It's party time!", 
    "Oh- Hey! Been a while...",
    "Socks or Shoes? My question is why not both?", 
    "The numbers Mason",
    "Dark side of the moon is quite the mystery", 
    "I miss you guys",
    "When wilst thou return?", 
    "Come on...you know you want to...",
    "When's the last time you played....? 🥺",
    "Jingle Bells, Jingle Bells, Jingle All The Way",
    "DANCE DANCE REVOLUTION.....Ha jk", 
    "It's been so long :("
}
local quotesIndex = math.random(1, #quotes)

function getQuote()
    if math.random(1, 100) > 90 then quotesIndex = math.random(1, #quotes) end
    return quotes[quotesIndex]
end

local function ToExtraShortString(style, diff, level)
    local shortStyle = style:sub(1,1):upper()
    if style ~= "single" and style ~= "double" then
        -- Capitalize the first letter of the style
        shortStyle = style:gsub("^%l", string.upper)
        return shortStyle .. "-" .. level
    end
    if diff == "Difficulty_Beginner" then
        return shortStyle .. "B" .. level
    elseif diff == "Difficulty_Easy" then
        return shortStyle .. "E" .. level
    elseif diff == "Difficulty_Medium" then
        return shortStyle .. "N" .. level
    elseif diff == "Difficulty_Hard" then
        return shortStyle .. "H" .. level
    elseif diff == "Difficulty_Challenge" then
        return shortStyle .. "X" .. level
    elseif diff == "Difficulty_Edit" then
        return "Edit-" .. shortStyle .. level
    else
        return level
    end
end

function GetChartFootprint(step_data)
    local author = step_data:GetAuthorCredit()
    local name = step_data:GetChartName()
    local description = step_data:GetDescription()
    if author == "" or not author then
        if name == "" or not name then
            if description == "" or not description then
                return "Unknown Origin"
            else
                return description
            end
        else
            return name
        end
    else
        return author
    end
end
function FullComboType(pss)
	if pss:FullComboOfScore('TapNoteScore_W1') then -- MFC
		return 'TapNoteScore_W1'
	elseif pss:FullComboOfScore('TapNoteScore_W2') then -- PFC
		return 'TapNoteScore_W2'
	elseif pss:FullComboOfScore('TapNoteScore_W3') then -- GFC
		return 'TapNoteScore_W3'
	elseif pss:FullComboOfScore('TapNoteScore_W5') then -- FC
		return 'TapNoteScore_W4'
	else
		return nil
	end
end

-- Copied from everyone.dance
-- Gets all the data of the current song/selection and outputs it to a file for everyone.dance to read
function updateDiscordGameplayStatus(pn, inEvaluation)

    --[[

        song_info: { // Current song info, either in menu select or ingame
            name: "Flowers",
            artist: "HANA RAMAN",
            pack: "Assorted",
            charter: "Konami",
            difficulty: 10,
            difficulty_name: "Expert"
            steps: 567
        },
        ingame: false, // If this player is currently in the gameplay or scores screen in stepmania
        steps_info: { // All info about a player's current steps in a song
            TapNoteScore_W1: 0,
            TapNoteScore_W2: 0,
            TapNoteScore_W3: 0,
            TapNoteScore_W4: 0,
            TapNoteScore_W5: 0,
            TapNoteScore_Miss: 0,
            TapNoteScore_HitMine: 0,
            TapNoteScore_AvoidMine: 0,
            HoldNoteScore_MissedHold: 0,
            HoldNoteScore_Held: 0,
            HoldNoteScore_LetGo: 0
        },
        fc = 'TapNoteScore_W1', -- Full combo if there was one
        progress = 0.7, // Current song progress betwen 0 and 1
        score: 99.20,
    ]]

    local profile = GetPlayerOrMachineProfile(pn)
    local largeImageTooltip = string.format("%s: %s",
                                            profile:GetDisplayName() == "" and
                                                "Guest" or
                                                profile:GetDisplayName(),
                                            profile:GetLastUsedHighScoreName())
    local style = GAMESTATE:GetCurrentStyle():GetName()
    if style == "versus" then style = "single" end
    style =
        THEME:GetString("ScreenSelectMusic", style:gsub("^%l", string.upper))

    local data = ""
    local player_data = {
        song_info = {},
        steps_info = {},
        progress = 0,
        score = 0,
        failed = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn):GetFailed()
    }

    local song = GAMESTATE:GetCurrentSong() -- Works for both music select and gameplay
    local step_data = GAMESTATE:GetCurrentSteps(pn)
    local bpm
    local bpms = song:GetDisplayBpms()
    if bpms[1] == bpms[2] then
        bpm = bpms[1]
    elseif bpms[1] <= 0 then
        bpm = bpms[2]
    elseif bpms[2] <= 0 then
        bpm = bpms[1]
    else
        bpm = bpms[1] .. " - " .. bpms[2]
    end

    if not song then return end
    if not step_data then return end

    local song_info = {
        name = song:GetTranslitFullTitle(),
        artist = song:GetTranslitArtist(),
        pack = song:GetGroupName(),
        charter = GetChartFootprint(step_data),
        difficulty = step_data:GetMeter(),
        difficulty_name = step_data:GetDifficulty(),
        steps = step_data:GetRadarValues(pn):GetValue(5),
        steps_type = step_data:GetStepsType(),
        style = THEME:GetString("ScreenSelectMusic", GAMESTATE:GetCurrentStyle()
                                    :GetName():gsub("^%l", string.upper)),
        mode = SL.Global.GameMode,
        song_dir = song:GetSongDir(),
        bpm = bpm
    }

    local time = song:MusicLengthSeconds()
    local minutes, seconds = math.floor(time / 60), math.floor(time % 60)

    -- Should return number of seconds passed in the song. Can be used to track song progress
    local song_progress = GAMESTATE:GetPlayerState(pn):GetSongPosition()
                              :GetMusicSeconds() / time

    player_data.progress = math.min(1, song_progress)

    -- Potentially use this to get player profile name: PROFILEMAN:GetProfile(pn):GetDisplayName()

    local cur_stats = STATSMAN:GetCurStageStats()
    local player_stats = cur_stats:GetPlayerStageStats(pn);

    player_data.fc = FullComboType(player_stats); -- Returns nil if no FC

    local dance_points = player_stats:GetPercentDancePoints()
    -- player_data.score = player_stats:GetScore()
    player_data.score = tonumber(dance_points) * 100

    local failed = player_stats:GetFailed()
    local detail = string.format("%s %s %s ...", player_data.failed == true and
                                     "💀Failed - " or "Playing",
                                 song_info.mode,
                                 ToExtraShortString(song_info.style,
                                                    step_data:GetDifficulty(),
                                                    song_info.difficulty));
    -- truncated to 128 characters(discord hard limit)
    detail = #detail < 128 and detail or (string.sub(detail, 1, 124) .. "...")
    local state = string.format("%s", song_info.name)
    local largeImageTooltip = string.format(
                                  "Pack: [%s] | BPM: %s | Chart: %s | ",
                                  song_info.pack, song_info.bpm,
                                  song_info.charter)
    local smallImageTooltip
    local image
    if inEvaluation then
        smallImageTooltip = string.format("Score: %5.2f%% %s ** %s",
                                          player_data.score,
                                          THEME:GetString("SLPlayerOptions",
                                                          "Grade" ..
                                                              ToEnumShortString(
                                                                  player_stats:GetGrade())),
                                          player_data.fc and "✔Full Combo!" or
                                              "❌Broken Combo")
        image = "heart"
    else
        smallImageTooltip = string.format("Score: %5.2f%% %s",
                                          player_data.score, player_data.fc and
                                              "✔Full Combo!" or
                                              "❌Broken Combo")
        image = "arrow"
    end

    GAMESTATE:UpdateDiscordFullPresence(largeImageTooltip, smallImageTooltip,
                                        "default", image, detail, state,
                                        discordPresence.startTime,
                                        discordPresence.startTime +
                                            math.floor(time))

end

-- update discord rpc for ingame menus
function updateDiscordStatusForMenus()
    local profile = GetPlayerOrMachineProfile(GAMESTATE:GetMasterPlayerNumber())
    local detail = string.format("%s: %s", profile:GetDisplayName(),
                                 profile:GetLastUsedHighScoreName())
    GAMESTATE:UpdateDiscordMenu(detail)
end

function updateDiscordStatusForSelection()
    local profile = GetPlayerOrMachineProfile(GAMESTATE:GetMasterPlayerNumber())
    local name = string.format("%s: %s", profile:GetDisplayName(),
                               profile:GetLastUsedHighScoreName())
    if GAMESTATE:IsEventMode() then
        discordPresence.smalltext = "Event Mode"
    elseif GAMESTATE:GetCoinMode() == "CoinMode_Pay" then
        discordPresence.smalltext = GAMESTATE:GetCoins() ..
                                        " credits remaining..."
    else
        discordPresence.smalltext = "Free Play"
    end
    local style = THEME:GetString("ScreenSelectMusic",
                                  GAMESTATE:GetCurrentStyle():GetName()
                                      :gsub("^%l", string.upper))
    style = style == "Versus" and style or (style .. "s")
    if GAMESTATE:IsCourseMode() then
        discordPresence.state =
            "Playing " .. SL.Global.GameMode .. " " .. style .. " Marathon"
    else
        discordPresence.state = "Playing " .. SL.Global.GameMode .. " " .. style
    end
    GAMESTATE:UpdateDiscordPresenceDetails(
        name .. " || Stage: " .. (GAMESTATE:GetCurrentStageIndex() + 1),
        discordPresence.smalltext, "default", "selectmusic",
        "Selecting Music...", discordPresence.state, discordPresence.startTime)
end

-- Copied from everyone.dance
-- Returns true if the player is playing a song / in end screen, false otherwise (aka in the music wheel or otherwise)
local function IsPlayerInGameplayScreen()
    local top_screen = SCREENMAN:GetTopScreen()
    if top_screen and top_screen.GetName then
        local screen_name = SCREENMAN:GetTopScreen():GetName()
        return screen_name == "ScreenGameplay"
    else
        return ""
    end
end

t["ScreenGameplay"] = Def.ActorFrame {
    ModuleCommand = function(self)
        discordPresence.startTime = os.time()
        updateDiscordGameplayStatus(GAMESTATE:GetMasterPlayerNumber(), false)
        -- Copied from everyone.dance
        self:sleep(discordPresence.sync_interval / 1000):queuecommand(
            "SyncInterval")
    end,
    SyncIntervalCommand = function(self)
        if (IsPlayerInGameplayScreen()) then
            updateDiscordGameplayStatus(GAMESTATE:GetMasterPlayerNumber())
            self:sleep(discordPresence.sync_interval / 1000):queuecommand(
                "SyncInterval")
        end
    end
}
t["ScreenSelectMusic"] = Def.ActorFrame {
    ModuleCommand = function(self) updateDiscordStatusForSelection() end
}
t["ScreenEvaluation"] = Def.ActorFrame {
    ModuleCommand = function(self)
        discordPresence.totalTime = os.time()
        updateDiscordGameplayStatus(GAMESTATE:GetMasterPlayerNumber(), true)
    end
}
t["ScreenGameOver"] = Def.ActorFrame {
    ModuleCommand = function(self)
        discordPresence.totalTime = os.time()
    end
}

t["ScreenTitleMenu"] = Def.ActorFrame {
    ModuleCommand = function(self)
        if GAMESTATE:GetCoinMode() == "CoinMode_Pay" then      
            GAMESTATE:UpdateDiscordPresence("I have " .. GAMESTATE:GetCoins() .." credits 🙃", "Basking in Pollock Commons",
        getQuote(), discordPresence.totalTime)
        else
            GAMESTATE:UpdateDiscordPresence("We Chilling", "On the Title Screen", "Arrow Steppin", discordPresence.totalTime)
        end
    end
}
t["ScreenLogo"] = Def.ActorFrame {
    ModuleCommand = function(self)
        if GAMESTATE:GetCoinMode() == "CoinMode_Pay" then      
            GAMESTATE:UpdateDiscordPresence("I have " .. GAMESTATE:GetCoins() .." credits 🙃", "Basking in Pollock Commons",
        getQuote(), discordPresence.totalTime)
        else
            GAMESTATE:UpdateDiscordPresence("We Chilling", "On the Title Screen", "Arrow Steppin", discordPresence.totalTime)
        end
    end
}
t["ScreenRankingSingle"] = Def.ActorFrame {
    ModuleCommand = function(self)
        if GAMESTATE:GetCoinMode() == "CoinMode_Pay" then      
            GAMESTATE:UpdateDiscordPresence("I have " .. GAMESTATE:GetCoins() .." credits 🙃", "Basking in Pollock Commons",
        getQuote(), discordPresence.totalTime)
        else
            GAMESTATE:UpdateDiscordPresence("We Chilling", "On the Title Screen", "Arrow Steppin", discordPresence.totalTime)
        end
    end
}
t["ScreenRankingDouble"] = Def.ActorFrame {
    ModuleCommand = function(self)
        if GAMESTATE:GetCoinMode() == "CoinMode_Pay" then      
            GAMESTATE:UpdateDiscordPresence("I have " .. GAMESTATE:GetCoins() .." credits 🙃", "Basking in Pollock Commons",
        getQuote(), discordPresence.totalTime)
        else
            GAMESTATE:UpdateDiscordPresence("We Chilling", "On the Title Screen", "Arrow Steppin", discordPresence.totalTime)
        end
    end
}
t["ScreenEdit"] = Def.ActorFrame {
    ModuleCommand = function(self)
        local groupName = GAMESTATE:GetCurrentSong():GetGroupName()
        local style = GAMESTATE:GetCurrentStyle():GetName()
        local bpm
        local bpms = GAMESTATE:GetCurrentSong():GetDisplayBpms()
        if bpms[1] == bpms[2] then
            bpm = bpms[1]
        elseif bpms[1] <= 0 then
            bpm = bpms[2]
        elseif bpms[2] <= 0 then
            bpm = bpms[1]
        else
            bpm = bpms[1] .. " - " .. bpms[2]
        end
        local currBeat = GAMESTATE:GetSongBeat()
        local lastBeat = round(GAMESTATE:GetCurrentSong():GetLastBeat())
        GAMESTATE:UpdateDiscordPresenceDetails(
            "Working in the " .. groupName .. " pack.", "Current beat: " ..
                currBeat .. "/" .. lastBeat .. " (" .. bpm .. "bpm)", "default",
            "editing", "Currently in Edit Mode..",
            "Editing a " .. style .. "s chart", discordPresence.totalTime)
    end
}
t["ScreenEditMenu"] = Def.ActorFrame {
    ModuleCommand = function(self)
        GAMESTATE:UpdateDiscordPresence("This is where the magic happens...",
                                        "Currently in Edit Mode..",
                                        "Browsing the Edit Menu",
                                        discordPresence.totalTime)
    end
}
t["ScreenPlayerOptions"] = Def.ActorFrame {
    ModuleCommand = function(self)
        GAMESTATE:UpdateDiscordPresenceDetails("Song: " ..
                                                   GAMESTATE:GetCurrentSong()
                                                       :GetDisplayMainTitle() ..
                                                   " | Stage: " ..
                                                   GAMESTATE:GetCurrentStageIndex() +
                                                   1,
                                               GAMESTATE:GetNumSidesJoined() ..
                                                   " Player || " ..
                                                   discordPresence.smalltext,
                                               "default", "selectmusic",
                                               "Entering Players Options...",
                                               discordPresence.state,
                                               discordPresence.totalTime)
    end
}

return t
