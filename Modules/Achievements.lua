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