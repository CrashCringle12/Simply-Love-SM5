-- OptionRows.lua
--
-- The per-player options presented after Start is pressed on the wheel:
--   1. Chart   (difficulty selection)
--   2. Speed   (CMod value)
--   3. Exit    (final row -- press Start to commit to Gameplay)
--
-- STEP 5 REDESIGN: Choices() now returns a table of "choice info" tables
-- (not plain strings) so OptionRowItemMT can render color-coded cards.
-- Every choice info entry carries:
--   text  : the label to display on the card
--   index : 1-based position in the source Values() array; used by OnSave
--           to look up the corresponding raw value cleanly
-- Plus optional per-role fields:
--   color, meter, name, role
--
-- The old string-based OnSave path had a latent bug (choice[1]==v[1] on
-- strings is nil==nil, which is always true, so it saved the first item
-- regardless of pick).  The new index-based path fixes that.
---------------------------------------------------------------------------

-- Meter number -> Casual-mode difficulty name.  Kept in sync with
-- MusicWheel/SharedDifficultyRow.lua and PlayerPane/DifficultyLabel.lua.
local NameForMeter = function(m)
	if m == 1 then return "Novice"
	elseif m == 2 then return "Novice+"
	elseif m == 3 then return "Easy"
	elseif m == 4 then return "Easy+"
	elseif m == 5 then return "Medium"
	elseif m == 6 then return "Medium+"
	elseif m == 7 then return "Hard"
	elseif m == 8 then return "Hard+"
	elseif m == 9 then return "Expert"
	elseif m and m >= 10 then return "🔥Insane"
	end
	return ""
end

-- ------------------------------------------------------
local OptionRows = {
	{
		Name     = "Chart",
		HelpText = THEME:GetString("ScreenSelectMusicCasual", "SelectDifficulty"),

		Values = function()
			local steps  = {}
			local max_m  = ThemePrefs.Get("CasualMaxMeter")
			for chart in ivalues(SongUtil.GetPlayableSteps( GAMESTATE:GetCurrentSong() )) do
				if chart:GetMeter() <= max_m then steps[#steps+1] = chart end
			end
			return steps
		end,

		Choices = function(self)
			local out = {}
			for i, chart in ipairs(self.Values()) do
				local meter = chart:GetMeter()
				out[#out+1] = {
					role   = "chart",
					index  = i,
					meter  = meter,
					name   = NameForMeter(meter),
					text   = tostring(meter) .. "  " .. NameForMeter(meter),
					color  = DifficultyColor( chart:GetDifficulty() ),
				}
			end
			return out
		end,

		OnLoad = function(actor, pn, choices, values)
			-- Preserve the player's last-picked meter across song changes.
			local start = 1
			local current_meter = GAMESTATE:IsHumanPlayer(pn) and GAMESTATE:GetCurrentSteps(pn)
			                       and GAMESTATE:GetCurrentSteps(pn):GetMeter() or 1
			-- Closest match without exceeding current meter (falls through to
			-- absolute closest if nothing is <= current).
			local best_delta = math.huge
			for i, chart in ipairs(values) do
				local d = math.abs(chart:GetMeter() - current_meter)
				if d < best_delta then best_delta = d; start = i end
			end
			actor:set_info_set(choices, start)
		end,

		OnSave = function(self, pn, choice)
			if not choice or not choice.index then return end
			local values = self:Values()
			if values[choice.index] then
				GAMESTATE:SetCurrentSteps(pn, values[choice.index])
			end
		end,
	},

	-- ------------------------------------------------------
	{
		Name     = "Speed",
		HelpText = THEME:GetString("ScreenSelectMusicCasual", "SelectSpeedMod"),

		Values = function() return {"auto", "more", "less"} end,

		AutoCModForMeter = function(_, meter)
			meter = tonumber(meter) or 1
			if meter <= 3 then return 200 end
			if meter == 4 then return 250 end
			if meter == 5 then return 300 end
			if meter <= 7 then return 350 end
			if meter == 8 then return 400 end
			return 450
		end,

		ResolveCModForChoice = function(self, pn, choice)
			if not choice or not choice.index then return 300 end

			local meter = 5
			local cur_steps = GAMESTATE:GetCurrentSteps(pn)
			if cur_steps then meter = cur_steps:GetMeter() end
			local auto = self:AutoCModForMeter(meter)

			if choice.index == 1 then return auto end
			if choice.index == 2 then return auto + 150 end
			if choice.index == 3 then return math.max(50, auto - 150) end
			return auto
		end,

		Choices = function()
			return {
                { role="speed", index=1, text = THEME:GetString("ScreenSelectMusicCasual", "Auto")    },
				{ role="speed", index=2, text = THEME:GetString("ScreenSelectMusicCasual", "MoreSpace") },
				{ role="speed", index=3, text = THEME:GetString("ScreenSelectMusicCasual", "LessSpace") },
			}
		end,

		OnLoad = function(actor, pn, choices, values)
			local start = 1
			local cmod = GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred"):CMod()
			local meter = 5
			local cur_steps = GAMESTATE:GetCurrentSteps(pn)
			if cur_steps then meter = cur_steps:GetMeter() end
			local auto = 300
			if meter <= 3 then auto = 200
			elseif meter == 4 then auto = 250
			elseif meter == 5 then auto = 300
			elseif meter <= 7 then auto = 350
			elseif meter == 8 then auto = 400
			else auto = 450 end
			if cmod then
				if cmod == auto + 150 then
					start = 2
				elseif cmod == math.max(50, auto - 150) then
					start = 3
				end
			end
			actor:set_info_set(choices, start)
		end,

		OnSave = function(self, pn, choice)
			local cmod = self:ResolveCModForChoice(pn, choice)
			GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred"):CMod(cmod)
			MESSAGEMAN:Broadcast("GameplayDemoSpeedChanged", {
				Player = pn,
				CMod = cmod,
				Source = "SpeedRowSave"
			})
		end,
	},
}
-- ------------------------------------------------------

-- Terminal Exit row.  Reaching this row means the player is READY; a Start
-- press with all joined players on this row commits to Gameplay.  This row
-- intentionally has no Choices/Values -- StartButton.lua handles the
-- confirmation visual.
OptionRows[#OptionRows + 1] = { Name = "Exit", HelpText = "" }

return OptionRows
