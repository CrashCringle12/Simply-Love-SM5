local t = {}

t["ScreenGameOver"] = Def.ActorFrame {
    ModuleCommand=function(self)
        SL.Accolades.Achievements = LoadAllAchievements()

        -- Refresh the ITL leaderboard mapping once per game-over,
        -- then fetch fresh achievements for each logged-in player.
        FetchITLLeaderboard(function(success)
            if not success then return end
            for _, player in pairs(GAMESTATE:GetEnabledPlayers()) do
                local pn = ToEnumShortString(player)
                local username = SL[pn].GrooveStatsUsername
                if type(username) == "string" and username ~= "" then
                    local entrantId = GetITLEntrantId(username)
                    if entrantId then
                        FetchITLAchievements(player, entrantId)
                    end
                end
            end
        end)

        --Unlock profiles from here, placed here temporarily until I've verified this works.
        -- loop through every profile directory and set any session.lock files to empty if they contain a guid that matches a profile on this machine. This is to prevent profiles from being locked indefinitely if the game crashes while a profile is in use.
        for i=1, PROFILEMAN:GetNumLocalProfiles() do
            -- GetLocalProfileFromIndex() expects indices to start at 0
            local profile = PROFILEMAN:GetLocalProfileFromIndex(i-1)
            -- GetLocalProfileIDFromIndex() also expects indices to start at 0
            local id = PROFILEMAN:GetLocalProfileIDFromIndex(i-1)
            local dir = PROFILEMAN:LocalProfileIDToDir(id)
            if profile and id and dir then
                if isProfileLockedByMachine({index = i, dir = dir}) then
                    unlockProfile({index = i, dir = dir})
                end
            end
        end
    end
}

t["ScreenEvaluationStage"] = Def.ActorFrame {
    ModuleCommand=function(self)
        for _, pn in pairs(GAMESTATE:GetEnabledPlayers()) do
            -- Only update achievements if the player has a loaded profile
            if PROFILEMAN:IsPersistentProfile(pn) then
                UpdateAchievements(pn)
            end
        end
    end,
}


return t;