-- PlayerPane/SongStepStats.lua
--
-- Per-player chart statistics row.  Shows the note counts that are most
-- useful to a casual player at a glance:  Notes / Jumps / Holds / Mines.
--
-- Uses SM5's RadarValues interface (Steps:GetRadarValues(player)) so
-- routine-style asymmetric charts count correctly per side.  Zeroes are
-- rendered so the row always has the same visual weight (the actual
-- number changes rather than the field disappearing).
---------------------------------------------------------------------------
local params = ...
local player = params.player
local pane_w = params.pane_w
local pane_h = params.pane_h

-- Which radar values we render, and the localized label under each.
-- Keeping this table-driven makes it easy to add / reorder later.
local STATS = {
	{ key = "Notes", label = "NOTES" },
	{ key = "Jumps", label = "JUMPS" },
	{ key = "Holds", label = "HOLDS" },
	{ key = "Mines", label = "MINES" },
}
local COL_W = (pane_w - 24) / #STATS  -- equal-width columns

local build_cell = function(i, def)
	local x = -pane_w/2 + 12 + (i - 0.5) * COL_W

	return Def.ActorFrame{
		Name = "Stat_" .. def.key,
		InitCommand = function(self) self:x(x) end,

		-- Numeric value (larger, white)
		LoadFont("Wendy/_wendy small")..{
			Name = "Value",
			InitCommand = function(self)
				self:zoom(0.4):diffuse(Color.White):shadowlength(0.5)
					:settext("0")
			end,
		},
		-- Label under the value
		LoadFont("Common Normal")..{
			Name = "Label",
			InitCommand = function(self)
				self:zoom(0.55):y(15):diffuse(color("#8b95a0")):shadowlength(0.5)
					:settext( def.label )
			end,
		},

		SetValueCommand = function(self, p)
			self:GetChild("Value"):settext( tostring(p.value or 0) )
		end,
	}
end

local af = Def.ActorFrame{
	Name = "SongStepStats",
	InitCommand = function(self)
		self:y(-pane_h/2 + 78)   -- below DifficultyLabel, above HighScore
	end,

	OnCommand = function(self) self:playcommand("Refresh") end,
	CurrentSongChangedMessageCommand    = function(self) self:playcommand("Refresh") end,
	CurrentStepsP1ChangedMessageCommand = function(self) if player == PLAYER_1 then self:playcommand("Refresh") end end,
	CurrentStepsP2ChangedMessageCommand = function(self) if player == PLAYER_2 then self:playcommand("Refresh") end end,

	RefreshCommand = function(self)
		local steps = GAMESTATE:GetCurrentSteps(player)
		if not steps then
			for _, def in ipairs(STATS) do
				self:GetChild("Stat_" .. def.key):playcommand("SetValue", { value = 0 })
			end
			return
		end
		local rv = steps:GetRadarValues(player)
		for _, def in ipairs(STATS) do
			local v = rv and rv:GetValue("RadarCategory_" .. def.key) or 0
			-- Guard against negative sentinel values that some engines
			-- return when the chart doesn't measure a category.
			if v < 0 then v = 0 end
			self:GetChild("Stat_" .. def.key):playcommand("SetValue", { value = math.floor(v) })
		end
	end,
}

for i, def in ipairs(STATS) do af[#af+1] = build_cell(i, def) end
return af
