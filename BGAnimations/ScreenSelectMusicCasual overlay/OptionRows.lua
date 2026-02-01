-- helper functions
local GetDifficulty = function(steps)
	if steps:GetMeter() == 1 then
		return "1 Novice"
	elseif steps:GetMeter() == 2 then
		return "2 Novice+"
	elseif steps:GetMeter() == 3 then
		return "3 Easy"
	elseif steps:GetMeter() == 4 then
		return "4 Easy+"
	elseif steps:GetMeter() == 5 then
		return "5 Medium"
	elseif steps:GetMeter() == 6 then
		return "6 Medium+"
	elseif steps:GetMeter() == 7 then
		return "7 Hard"
	elseif steps:GetMeter() == 8 then
		return "8 Hard+"
	elseif steps:GetMeter() == 9 then
		return "9 Expert"
	elseif steps:GetMeter() >= 10 then
		return steps:GetMeter().." Insane"
	end
end

-- ------------------------------------------------------
local OptionRows = {
	{
		Name = "Charts",
		HelpText = THEME:GetString("ScreenSelectMusicCasual", "SelectDifficulty"),
		Choices = function(self) return map(GetDifficulty, self.Values()) end,
		Values = function()
			local steps = {}
			-- prune out charts whose meter exceeds the specified max
			for chart in ivalues(SongUtil.GetPlayableSteps( GAMESTATE:GetCurrentSong() )) do
				if chart:GetMeter() <= ThemePrefs.Get("CasualMaxMeter") then
					steps[#steps+1] = chart
				end
			end
			return steps
		end,
		OnLoad=function(actor, pn, choices, values)
			local index = 1
			local current_meter = GAMESTATE:IsHumanPlayer(pn) and GAMESTATE:GetCurrentSteps(pn) and GAMESTATE:GetCurrentSteps(pn):GetMeter() or 1

			-- if the player has a chart set (from a previous round, picking a song but then canceling, etc.),
			-- set this OptionRow's starting choice to the chart whose meter is closest without exceeding
			-- previous chart's meter.  I attempting to match by numerical Meter makes more sense for Casual mode than
			-- attempting to match by difficulty. It mitagates scenarios in which the previous song had a Medium 4
			-- but the current song has a Medium 10.
			for i,chart in ipairs(values) do
				if chart:GetMeter() <= current_meter then
					if current_meter-chart:GetMeter() < current_meter-values[index]:GetMeter() then
						index = i
					end
				end
			end
			actor:set_info_set(choices, index)
		end,
		OnSave=function(self, pn, choice)
			local index = 1
			for i,v in ipairs(self:Choices()) do
				if choice[1]==v[1] and choice[2]==v[2] then index=i; break end
			end
			GAMESTATE:SetCurrentSteps(pn, self:Values()[index])
		end
	},
	-- ------------------------------------------------------
	{
		Name = "Speed",
		HelpText = THEME:GetString("ScreenSelectMusicCasual", "SelectSpeedMod"),
		Choices = function()
			return {
				THEME:GetString("ScreenSelectMusicCasual", "Normal"),
				THEME:GetString("ScreenSelectMusicCasual", "MoreSpace"),
				THEME:GetString("ScreenSelectMusicCasual", "LessSpace"),
			}
		end,
		Values = function() return {210, 300, 125} end,
		OnLoad=function(actor, pn, choices, values)
			local index = 1
			local cmod = GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred"):CMod()
			if cmod then index = FindInTable(cmod,values) or 1 end
			actor:set_info_set(choices, index)
		end,
		OnSave=function(self, pn, choice, choices, values)
			local index = FindInTable(choice, choices)
			local player_options = GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred")
			player_options:CMod(values[index])
		end,
	},
}
-- ------------------------------------------------------

-- add Exit row last
OptionRows[#OptionRows + 1] = {
	Name = "Exit",
	HelpText = "",
}

return OptionRows
