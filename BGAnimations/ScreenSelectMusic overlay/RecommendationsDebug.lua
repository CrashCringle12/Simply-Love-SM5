-- Invisible development hook for the recommendation prototype.
-- Generates a recommendations-debug.txt file in each loaded persistent profile
-- when ScreenSelectMusic opens.

return Def.Actor{
    OnCommand=function(self)
        SM("HEY")
        self:sleep(0.25):queuecommand("GenerateRecommendations")
    end,

    PlayerProfileSetMessageCommand=function(self)
        SM("GGG")
        self:sleep(0.25):queuecommand("GenerateRecommendations")
    end,

    GenerateRecommendationsCommand=function(self)
        SM("TEST")
        if not SLRecommendations then return end

        for pn in ivalues(GAMESTATE:GetEnabledPlayers()) do
            if PROFILEMAN:IsPersistentProfile(pn) then
                local results, model, err = SLRecommendations.Generate(pn, { count = 30 })
                if err then
                    Trace("[Recommendations] " .. ToEnumShortString(pn) .. ": " .. tostring(err))
                elseif model then
                    SLRecommendations.WriteDebugFile(pn, results, model)

                    if SLRecommendations.Config.Debug and results[1] then
                        Trace(string.format(
                            "[Recommendations] %s top result: %s (%d) score=%.4f",
                            ToEnumShortString(pn),
                            results[1].song:GetDisplayFullTitle(),
                            results[1].meter,
                            results[1].score
                        ))
                    end
                end
            end
        end
    end,
}
