-- PlayerPane/HighScorePanel.lua
--
-- Bottom row of the per-player pane: high score for the currently selected
-- chart, resolved via GetPlayerOrMachineProfile.  Shows grade + percent
-- when available, or a muted "NO HIGH SCORE" placeholder otherwise.
---------------------------------------------------------------------------
local params = ...
local player = params.player
local pane_w = params.pane_w
local pane_h = params.pane_h

local GetTopScoreInfo = function(profile, song, steps)
	if not (profile and song and steps) then return nil end
	local hsl = profile:GetHighScoreList(song, steps)
	if not hsl then return nil end
	local scores = hsl:GetHighScores()
	if not scores or #scores == 0 then return nil end
	local best    = scores[1]
	local grade   = best:GetGrade()
	local percent = best:GetPercentDP() * 100
	return ToEnumShortString(grade), percent
end

return Def.ActorFrame{
	Name = "HighScorePanel",
	InitCommand = function(self)
		self:y(pane_h/2 - 14)
	end,

	OnCommand = function(self) self:playcommand("Refresh") end,
	CurrentSongChangedMessageCommand    = function(self) self:playcommand("Refresh") end,
	CurrentStepsP1ChangedMessageCommand = function(self) if player == PLAYER_1 then self:playcommand("Refresh") end end,
	CurrentStepsP2ChangedMessageCommand = function(self) if player == PLAYER_2 then self:playcommand("Refresh") end end,
	PlayerProfileSetMessageCommand      = function(self, p) if p.Player == player then self:playcommand("Refresh") end end,

	-- Grade string (e.g. "AA", "Tier01").  Shown when we have a score.
	LoadFont("Wendy/_wendy small")..{
		Name = "Grade",
		InitCommand = function(self)
			self:zoom(0.4):diffuse(Color.White):shadowlength(0.75)
				:halign(0):x(-pane_w/2 + 14)
		end,
	},
	-- "%score" on the right.
	LoadFont("Common Normal")..{
		Name = "Percent",
		InitCommand = function(self)
			self:zoom(0.9):diffuse(color("#e8e8e8")):shadowlength(0.5)
				:halign(1):x(pane_w/2 - 14)
		end,
	},

	-- Fallback text when there is nothing to show.
	LoadFont("Common Normal")..{
		Name = "NoScore",
		InitCommand = function(self)
			self:zoom(0.75):diffuse(color("#8b95a0")):shadowlength(0.5)
				:visible(false)
		end,
	},

	RefreshCommand = function(self)
		local song    = GAMESTATE:GetCurrentSong()
		local steps   = GAMESTATE:GetCurrentSteps(player)
		local profile = GetPlayerOrMachineProfile(player)

		local grade_str, percent = GetTopScoreInfo(profile, song, steps)
		local gradeBmt   = self:GetChild("Grade")
		local percentBmt = self:GetChild("Percent")
		local noscoreBmt = self:GetChild("NoScore")

		if grade_str then
			gradeBmt:visible(true):settext( (grade_str:gsub("_", " ")):gsub("Grade ", "") )
			percentBmt:visible(true):settext( ("%.2f%%"):format(percent) )
			noscoreBmt:visible(false)
		else
			gradeBmt:visible(false)
			percentBmt:visible(false)
			noscoreBmt:visible(true):settext( THEME:GetString("ScreenSelectMusicCasual", "NoHighScore") )
		end
	end,
}
