-- PlayerPane/DifficultyLabel.lua
--
-- The prominent "7  HARD" line right under the profile header.  Meter
-- number on the left, difficulty name on the right, both tinted with the
-- SL DifficultyColor for the currently-selected chart.
--
-- Uses the same meter-based naming Casual Mode's OptionRows use so the
-- label here always matches the shared difficulty row above the pane.
---------------------------------------------------------------------------
local params = ...
local player = params.player
local pane_w = params.pane_w
local pane_h = params.pane_h

local NameForMeter = function(m)
	if m == 1 then return "NOVICE"
	elseif m == 2 then return "NOVICE+"
	elseif m == 3 then return "EASY"
	elseif m == 4 then return "EASY+"
	elseif m == 5 then return "MEDIUM"
	elseif m == 6 then return "MEDIUM+"
	elseif m == 7 then return "HARD"
	elseif m == 8 then return "HARD+"
	elseif m == 9 then return "EXPERT"
	elseif m and m >= 10 then return "🔥INSANE"
	end
	return ""
end

return Def.ActorFrame{
	Name = "DifficultyLabel",
	InitCommand = function(self)
		self:y(-pane_h/2 + 40)
	end,

	OnCommand = function(self) self:playcommand("Refresh") end,
	CurrentSongChangedMessageCommand    = function(self) self:playcommand("Refresh") end,
	CurrentStepsP1ChangedMessageCommand = function(self) if player == PLAYER_1 then self:playcommand("Refresh") end end,
	CurrentStepsP2ChangedMessageCommand = function(self) if player == PLAYER_2 then self:playcommand("Refresh") end end,

	-- Meter number (large)
	LoadFont("Wendy/_wendy small")..{
		Name = "Meter",
		InitCommand = function(self)
			self:zoom(0.85):shadowlength(1)
				:halign(0):x(-pane_w/2 + 14)
		end,
	},
	-- Difficulty name (big uppercase to the right of the meter)
	LoadFont("Wendy/_wendy small")..{
		Name = "Name",
		InitCommand = function(self)
			self:zoom(0.55):shadowlength(0.75)
				:halign(0):x(-pane_w/2 + 60)
				:maxwidth( pane_w - 80 )
		end,
	},

	RefreshCommand = function(self)
		local steps = GAMESTATE:GetCurrentSteps(player)
		local meter = self:GetChild("Meter")
		local name  = self:GetChild("Name")
		if not steps then meter:settext(""); name:settext(""); return end
		local m   = steps:GetMeter()
		local clr = DifficultyColor( steps:GetDifficulty() )
		meter:settext( tostring(m) ):diffuse(clr)
		name:settext( NameForMeter(m) ):diffuse(clr)
	end,
}
