-- MusicWheel/SharedDifficultyRow.lua
--
-- The horizontal row of every difficulty this song offers, rendered as
-- colored blocks with a compact meter-name label under each block, plus
-- small player-color markers underneath showing which chart P1 / P2 has
-- currently activated.
--
-- Since both players are always looking at the same song in Casual Mode,
-- displaying every option here once is more compact and clearer than
-- duplicating a difficulty strip in each player pane.  The activation
-- bars let each side see what the other picked at a glance.
---------------------------------------------------------------------------
local args = ...
local wheel_config = args.wheel_config
local ITEM_H = wheel_config.item_h

-- Layout
local MAX_CELLS   = 10
local BLOCK_W     = 34
local BLOCK_H     = 30
local BLOCK_GAP   = 5
local LABEL_Y     = 26        -- offset from block center to name text
local MARKER_Y    = 38        -- offset from block center to P1/P2 marker

-- meter number -> Casual-mode difficulty name.  Mirrors the labels
-- OptionRows.lua produces so the modal picker and this shared row agree.
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

local GetAllowedSteps = function(song)
	if not song then return {} end
	local max_meter  = ThemePrefs.Get("CasualMaxMeter")
	local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
	local out = {}
	for chart in ivalues(SongUtil.GetPlayableSteps(song)) do
		if chart:GetStepsType() == steps_type and chart:GetMeter() <= max_meter then
			out[#out+1] = chart
		end
	end
	return out
end

local build_cell = function(index)
	return Def.ActorFrame{
		Name = "Cell_" .. index,
		InitCommand = function(self) self:visible(false) end,

		Def.Quad{
			Name = "Block",
			InitCommand = function(self)
				self:zoomto(BLOCK_W, BLOCK_H):diffuse( color("#1e282f") )
			end,
		},
		Def.Quad{
			Name = "Border",
			InitCommand = function(self)
				self:zoomto(BLOCK_W + 2, BLOCK_H + 2)
					:diffuse( color("#0a0f13") ):diffusealpha(0)
			end,
		},
		LoadFont("Wendy/_wendy small")..{
			Name = "Meter",
			InitCommand = function(self)
				self:zoom(0.5):diffuse(Color.White):shadowlength(0.75)
			end,
		},
		LoadFont("Common Normal")..{
			Name = "DiffName",
			InitCommand = function(self)
				self:y(LABEL_Y):zoom(0.65):diffuse(Color.White):shadowlength(0.5)
					:maxwidth(BLOCK_W + BLOCK_GAP*2)
			end,
		},
		Def.Quad{
			Name = "P1Marker",
			InitCommand = function(self)
				self:zoomto(BLOCK_W - 8, 3):y(MARKER_Y)
					:diffuse( PlayerColor(PLAYER_1) )
					:x(-4):visible(false)
			end,
		},
		Def.Quad{
			Name = "P2Marker",
			InitCommand = function(self)
				self:zoomto(BLOCK_W - 8, 3):y(MARKER_Y)
					:diffuse( PlayerColor(PLAYER_2) )
					:x(4):y(40):visible(false)
			end,
		},

		SetCellCommand = function(self, p)
			if not p or not p.steps then self:visible(false); return end
			self:visible(true)

			local diff = p.steps:GetDifficulty()
			local clr  = DifficultyColor(diff)

			self:GetChild("Block"):diffuse(clr):diffusealpha(0.95)
			self:GetChild("Meter"):settext( tostring(p.steps:GetMeter()) )
				:diffuse(Color.Black):zoom(0.55)
			self:GetChild("DiffName"):settext( NameForMeter(p.steps:GetMeter()) )
				:diffuse(clr)

			local border = self:GetChild("Border")
			if p.p1_active or p.p2_active then
				border:diffuse(Color.White):diffusealpha(0.85)
			else
				border:diffusealpha(0)
			end
			self:GetChild("P1Marker"):visible( p.p1_active == true )
			self:GetChild("P2Marker"):visible( p.p2_active == true )
		end,
		HideCellCommand = function(self) self:visible(false) end,
	}
end

---------------------------------------------------------------------------

local af = Def.ActorFrame{
	Name = "SharedDifficultyRow",
	InitCommand = function(self)
		-- +72 offset from wheel origin lands the block row centers just
		-- below the song meta line inside the info backdrop.
		self:y(ITEM_H/2 + 76)
	end,

	OnCommand = function(self) self:playcommand("Refresh") end,
	CurrentSongChangedMessageCommand    = function(self) self:playcommand("Refresh") end,
	CurrentStepsP1ChangedMessageCommand = function(self) self:playcommand("Refresh") end,
	CurrentStepsP2ChangedMessageCommand = function(self) self:playcommand("Refresh") end,

	RefreshCommand = function(self)
		local song  = GAMESTATE:GetCurrentSong()
		local steps = GetAllowedSteps(song)
		local p1_cur = GAMESTATE:GetCurrentSteps(PLAYER_1)
		local p2_cur = GAMESTATE:GetCurrentSteps(PLAYER_2)
		local p1_joined = GAMESTATE:IsHumanPlayer(PLAYER_1)
		local p2_joined = GAMESTATE:IsHumanPlayer(PLAYER_2)

		for i = 1, MAX_CELLS do
			local cell = self:GetChild("Cell_" .. i)
			local s    = steps[i]
			if s then
				cell:playcommand("SetCell", {
					steps     = s,
					p1_active = p1_joined and (s == p1_cur),
					p2_active = p2_joined and (s == p2_cur),
				})
				local n     = #steps
				local total = n * BLOCK_W + (n-1) * BLOCK_GAP
				local x     = (i - 1) * (BLOCK_W + BLOCK_GAP) - total/2 + BLOCK_W/2
				cell:x(x)
			else
				cell:playcommand("HideCell")
			end
		end
	end,
}

for i = 1, MAX_CELLS do af[#af+1] = build_cell(i) end
return af
