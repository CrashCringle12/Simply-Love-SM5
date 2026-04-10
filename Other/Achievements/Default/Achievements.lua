LoadActor('../helper.lua')

return {
    {
        Name = "Getting Started",
        Icon = "medal 4x3.png",
        Condition = function(pn)
            -- Checks if the song just played was passed
            return PassCheck(pn)
        end,
        Desc = "Pass your first song",
        Difficulty = 1,
        ID = 1
    }, {
        Name = "Getting Better",
        Icon = "goodjob.png",
        Desc = "Pass 10 songs",
        Data = {Progress = 0, Target = 10},
        ID = 2,
        Difficulty = 1,
        Condition = function(pn)
            if PassCheck(pn) then
                return updateSingleProgress(pn, "Default", 2, 1)
            else
                return checkSingleProgress(pn, "Default", 2)
            end
        end
    }, {
        Name = "Got Milk?",
        Icon = "milk.png",
        Condition = function(pn)
            if GAMESTATE:GetCurrentSong():GetSongDir() == "Milk/Be a Man" then
                return PassCheck(pn)
            else
                return false
            end
            return false
        end,
        Desc = "Pass I'll Make a Man Out of You on Expert difficulty",
        Difficulty = 4,
        ID = 3
    }, {
        Name = "ITG 15 pass club",
        Icon = "medal 4x3.png",
        Condition = function(pn)
            -- Check if the group contains the word DDR, this is to prevent the achievement from being unlocked on DDR songs
            local song = GAMESTATE:GetCurrentSong()
            if song == nil then return false end
            if string.match(GAMESTATE:GetCurrentSong():GetGroupName(), "DDR") ~= nil 
                or string.match(GAMESTATE:GetCurrentSong():GetGroupName(),"zenius") ~= nil 
                or string.match(GAMESTATE:GetCurrentSong():GetGroupName(),"PSU") ~= nil 
                or string.match(GAMESTATE:GetCurrentSong():GetGroupName(),"Dance Dance") ~= nil 
                or string.match(GAMESTATE:GetCurrentSong():GetGroupName(),"DanceDance") ~= nil 
                or string.match(GAMESTATE:GetCurrentSong():GetGroupName(), "2014 Billboard") ~= nil then
                return false
            else
                -- Check if the song meter is 15
                if GAMESTATE:GetCurrentSteps(pn):GetMeter() == 15 then
                    return PassCheck(pn)
                else
                    return false
                end
            end
        end,
        Desc = "Successfully pass your first 15",
        Difficulty = 5,
        ID = 4
    }, {
        Name = "You're Already Dead",
        Icon = "dead.png",
        Condition = function(pn)
            -- 429d726213656886, 82bb1074e4b0b372, 3f921fc09897e2c4, b8f2ab5ccdd3be28
            if SL[pn].Streams.Hash == "82bb1074e4b0b372" or SL[pn].Streams.Hash ==
                "429d726213656886" or SL[pn].Streams.Hash == "3f921fc09897e2c4" or
                SL[pn].Streams.Hash == "b8f2ab5ccdd3be28" or SL[pn].Streams.Hash ==
                "768c577db008a310" then
                return TimingWindowCheck(pn, "HitMine", 100, true)
            end
            return false
        end,
        Desc = "This is a Secret Achievement",
        Difficulty = 1,
        ID = 5
    }, {
        Name = "Maniac",
        Icon = "maniac.png",
        Condition = function(pn)
            -- Check if the profile has played 500 songs
            if PROFILEMAN:GetProfile(pn):GetTotalNumSongsPlayed() >= 500 then
                return PassCheck(pn)
            else
                return false
            end
        end,
        Desc = "Play 500 songs",
        Difficulty = 2,
        ID = 6
    }, {
        Name = "#Goals",
        Icon = "heart.png",
        Condition = function(pn)
            -- Couples packs have the following in their group name: "Couples", "OnlyOneCouples", "OOC"
            -- Additionally they could have these in their steps description: "Couples", "OnlyOneCouples", "OOC"
            -- First lets see if the group name contains any of the above
            if not GAMESTATE:GetCurrentSong() then return false end
            if string.match(GAMESTATE:GetCurrentSong():GetGroupName(), "Couple") ~=
                nil or
                string.match(GAMESTATE:GetCurrentSong():GetGroupName(),
                             "Only One Couples") ~= nil or
                string.match(GAMESTATE:GetCurrentSong():GetGroupName(), "OOC") ~=
                nil then
                return PassCheck(pn)
            elseif string.match(GAMESTATE:GetCurrentSteps(pn):GetDescription(),
                                "couple") ~= nil or
                string.match(GAMESTATE:GetCurrentSteps(pn):GetDescription(),
                             "OnlyOneCouples") ~= nil or
                string.match(GAMESTATE:GetCurrentSteps(pn):GetDescription(),
                             "OOC") ~= nil then
                return PassCheck(pn)
            else
                return false
            end
        end,
        Desc = "Pass your first Couples Song!",
        Difficulty = 2,
        ID = 7
    }, {
        Name = "Make it stop....MAKE IT STOP",
        Icon = "crab.png",
        Condition = function(pn)
            if string.match(GAMESTATE:GetCurrentSong():GetDisplayMainTitle(), "[14] [125] Crab Rave Marathon")
            or (string.match(GAMESTATE:GetCurrentSong():GetDisplayMainTitle(), "[14] [125] Crab Rave Marathon") and string.match(GAMESTATE:GetCurrentSong():GetDisplayMainTitle(), "125")) then
                return HasPassed(pn, song)
            else
                return false
            end
        end,
        Desc = "Pass Crab Rave Marathon",
        Difficulty = 5,
        ID = 8
    }, {
        Name = "Top G",
        Icon = "tate.png",
        Condition = function(pn)
            if GAMESTATE:GetCurrentSong():GetDisplayMainTitle() ==
                "Battle of the Bugatti" then
                return PassCheck(pn)
            else
                return false;
            end
        end,
        Desc = "Defeat Andrew Tate and end his reign of terror",
        Difficulty = 4,
        ID = 9
    }, {
        Name = "Great Player",
        Icon = "tony.png",
        Condition = function(pn)
            return updateSingleProgress(pn, "Default", 10,
                                        _GetTapNoteScores(pn, "W3"))
        end,
        Desc = "Achieve over 10,000 lifetime greats.",
        Difficulty = 3,
        ID = 10,
        Data = {Progress = 0, Target = 10000}
    }, {
        Name = "On My Pillow",
        Icon = "pillow.jpg",
        Condition = function(pn)
            if string.match(GAMESTATE:GetCurrentSong():GetDisplayMainTitle(),
                            "Lay It Down") then
                return PassCheck(pn)
            else
                return false
            end
        end,
        Desc = "Pass the 8 on Lay It Down",
        Difficulty = 2,
        ID = 11
    }, {
        Name = "Mine v1",
        Icon = "Fallback Tap Mine 4x2",
        Condition = function(pn)
            return TimingWindowCheck(pn, "HitMine", 10, true)
        end,
        Desc = "Hit 10 Mines in one song",
        Difficulty = 1,
        ID = 12
    }, {
        Name = "Mine v2",
        Icon = "mine2.png",
        Condition = function(pn)
            return TimingWindowCheck(pn, "HitMine", 50, true)
        end,
        Desc = "Hit 50 Mines in one song",
        Difficulty = 2,
        ID = 13
    }, {
        Name = "Mine v3",
        Icon = "mineSong.jpg",
        Condition = function(pn)
            return TimingWindowCheck(pn, "HitMine", 100, true)
        end,
        Desc = "Hit 100 Mines in one song",
        Difficulty = 3,
        ID = 14
    }, {
        Name = "Long Haul",
        Icon = "energy.png",
        Condition = function(pn)
            -- Check if the song is at least 3 minutes and 30 seconds long
            if GAMESTATE:GetCurrentSong():MusicLengthSeconds() >= 210 then
                return PassCheck(pn)
            else
                return false
            end
        end,
        Desc = "Pass a song that's at least 3 minutes and 30 seconds long.",
        Difficulty = 3,
        ID = 15
    }, {
        Name = "What  Committment  Issue?",
        Icon = "fireClock.png",
        Condition = function(pn)
            if GAMESTATE:GetCurrentSong():MusicLengthSeconds() >= 600 then
                return PassCheck(pn)
            else
                return false
            end
        end,
        Desc = "Play a song that's at least 10 minutes long.",
        Difficulty = 3,
        ID = 16
    }, {
        Name = "Little Engine that could",
        Icon = "littleEngine.png",
        Condition = function(pn)
            if BPMCheck(pn, 50, false) then
                return PassCheck(pn)
            else
                return false
            end
        end,
        Desc = "Pass a song with an average BPM below 50",
        Difficulty = 3,
        ID = 17
    }, {
        Name = "Need for Speed",
        Icon = "meter.png",
        Condition = function(pn)
            return BPMCheckRange(pn, 180, 200) and PassCheck(pn)
        end,
        Desc = "Pass a song with an average BPM in the 180 - 200 range",
        Difficulty = 3,
        ID = 18
    }, {
        Name = "Speed for Need",
        Icon = "Car.png",
        Condition = function(pn)
            return BPMCheckRange(pn, 201, 220) and PassCheck(pn)
        end,
        Desc = "Pass a song with an average BPM in the 201 - 220 range",
        Difficulty = 3,
        ID = 19
    }, {
        Name = "Footspeed Mastery",
        Icon = "footClan.png",
        Condition = function(pn)
            return BPMCheck(pn, 250, true) and PassCheck(pn)
        end,
        Desc = "Pass a song with an average BPM over 250",
        Difficulty = 3,
        ID = 20
    }, {
        Name = "👏👏👏👏",
        Icon = "clap.png",
        Condition = function(pn)
            if not song then return false end
            if string.match(GAMESTATE:GetCurrentSong():GetDisplayMainTitle(),
                            "Go Go Sing") then
                return true
            else
                return false
            end
        end,
        Desc = "Pass Go Go Sing ",
        Difficulty = 3,
        ID = 21
    }, {
        Name = "Masterful Performance",
        Icon = "ianDance 17x1.png",
        Condition = function(pn)
            if string.match(GAMESTATE:GetCurrentSong():GetDisplayMainTitle(),
                            "The Ballad of Ian") then
                return PassCheck(pn)
            else
                return false
            end
            return false
        end,
        Desc = "Complete the Ballad of Ian ",
        Difficulty = 4,
        ID = 22
    }, {
        Name = "Make History",
        Icon = "Books.png",
        Condition = function(pn)
            if string.match(GAMESTATE:GetCurrentSong():GetDisplayMainTitle(),
                            "History Maker") then
                local step_data = GAMESTATE:GetCurrentSteps(pn)
                if step_data then
                    if step_data:GetMeter() == 14 then
                        return PassCheck(pn)
                    end
                end
            else
                return false
            end
            return false
        end,
        Desc = "Pass the 14 on History Maker ",
        Difficulty = 5,
        ID = 23
    }, {
        Name = "Soul Train",
        Icon = "Soul.png",
        Condition = function(pn)
            if string.match(GAMESTATE:GetCurrentSong():GetDisplayMainTitle(), "Soul Meets Body") then
                local step_data = GAMESTATE:GetCurrentSteps(pn)
                if step_data then
                    if step_data:GetMeter() == 10 then
                        return PassCheck(pn)
                    end
                end
            else
                return false
            end
            return false
        end,
        Desc = "Pass Soul Meets Body (Doubles)",
        Difficulty = 3,
        ID = 24
    }, {
        Name = "Built Different",
        Icon = "rhyme (stretch)",
        Desc = "Get your first Quad!",
        Difficulty = 4,
        ID = 25,
        Condition = function(pn)
            -- Unlocks when the player gets their first S grade on a chart.
            if not GAMESTATE:GetCurrentSong() then return false end
            -- Get the player's current grade       
            local playerStats = STATSMAN:GetCurStageStats():GetPlayerStageStats(
                                    pn)
            if not playerStats then return false end
            local grade = playerStats:GetGrade()
            if grade == "Grade_Tier01" then
                return true
            else
                return false
            end
        end
    }, {
        Name = "Gold Star",
        Icon = "star.png",
        UnlockedDiffuse = {0.93, 1.00, 0.94, 1.00},
        Difficulty = 2,
        ID = 26,
        Desc = "Get your first star!",
        Condition = function(pn)
            -- Unlocks when the player gets their first S grade on a chart.
            if not GAMESTATE:GetCurrentSong() then return false end
            -- Get the player's current grade       
            local playerStats = STATSMAN:GetCurStageStats():GetPlayerStageStats(
                                    pn)
            if not playerStats then return false end
            local grade = playerStats:GetGrade()
            if grade == "Grade_Tier01" or grade == "Grade_Tier02" or grade ==
                "Grade_Tier03" or grade == "Grade_Tier04" then
                return true
            else
                return false
            end
        end
    }, {
        Name = "Superb!",
        Icon = "s-plus.png",
        UnlockedDiffuse = {0.93, 1.00, 0.94, 1.00},
        Difficulty = 2,
        ID = 27,
        Desc = "Get your first S!",
        Condition = function(pn)
            -- Unlocks when the player gets their first S grade on a chart.
            if not GAMESTATE:GetCurrentSong() then return false end
            -- Get the player's current grade       
            local playerStats = STATSMAN:GetCurStageStats():GetPlayerStageStats(
                                    pn)
            if not playerStats then return false end
            local grade = playerStats:GetGrade()
            if grade == "Grade_Tier05" or grade == "Grade_Tier06" or grade ==
                "Grade_Tier07" then
                return true
            else
                return false
            end
        end
    }, {
        Name = "A for Effort",
        Icon = "a-plus.png",
        UnlockedDiffuse = {0.93, 1.00, 0.94, 1.00},
        Difficulty = 1,
        Desc = "Get your first A!",
        ID = 28,
        Condition = function(pn)
            -- Unlocks when the player gets their first A grade on a chart.
            if not GAMESTATE:GetCurrentSong() then return false end
            -- Get the player's current grade       
            local playerStats = STATSMAN:GetCurStageStats():GetPlayerStageStats(
                                    pn)
            if not playerStats then return false end
            local grade = playerStats:GetGrade()
            if grade == "Grade_Tier08" or grade == "Grade_Tier09" or grade ==
                "Grade_Tier10" then
                return true
            else
                return false
            end
        end
    }, {
        Name = "Close but no cigar",
        Icon = "affluent.png",
        Desc = "You Tried",
        Difficulty = 1,
        ID = 29,
        Condition = function(pn)
            -- Unlocks when the player gets their first B grade on a chart.
            if not GAMESTATE:GetCurrentSong() then return false end
            -- Get the player's current grade       
            local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
            if not pss then return false end
            if pss ~= nil and pss:GetTapNoteScores('TapNoteScore_Miss') == 0 and
                pss:GetTapNoteScores('TapNoteScore_W5') == 0 and
                pss:GetTapNoteScores('TapNoteScore_W4') == 0 and
                pss:GetTapNoteScores('TapNoteScore_W3') == 0 and
                pss:GetTapNoteScores('TapNoteScore_W2') == 1 then
                return true
            else
                return false
            end
        end
    }, -- Achievement for passing a song titled "e"
    {
        Name = "e",
        Icon = "e 3x2.png",
        Desc = "e",
        Difficulty = 6,
        ID = 30,
        Condition = function(pn)
            if not GAMESTATE:GetCurrentSong() then return false end
            if GAMESTATE:GetCurrentSong():GetDisplayMainTitle() == "e" then
                if string.match(GAMESTATE:GetCurrentSong():GetSongDir(), "E2") then
                    return false
                else
                    return PassCheck(pn)
                end
            else
                return false
            end
        end
    }, -- Achievement for passing a song titled "e"
    {
        Name = "mc^2",
        Icon = "e.png",
        UnlockedDiffuse = {0.93, 1.00, 0.94, 1.00},
        Desc = "Can you make the letter sound?",
        Difficulty = 4,
        ID = 31,
        Condition = function(pn)
            if not GAMESTATE:GetCurrentSong() then return false end
            if GAMESTATE:GetCurrentSong():GetDisplayMainTitle() == "e" then
                -- Check if the SongDir contains E2
                if string.match(GAMESTATE:GetCurrentSong():GetSongDir(), "E2") then
                    return PassCheck(pn)
                end
                return false
            else
                return false
            end
        end
    }

}
