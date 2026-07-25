-- PlayerPane/SongStepStats.lua
--
-- Per-player chart statistics row.  Shows counts most useful to a casual
-- player at a glance:  Notes / Jumps / Holds / Mines / Crossovers.
--
-- Data sources:
--   * Notes / Jumps / Holds / Mines come from SM5's RadarValues API
--     (Steps:GetRadarValues(player)) so routine-style asymmetric charts
--     count correctly per side.
--   * Crossovers come from the newer TechCounts API
--     (Steps:GetTechCounts(player)), which isn't present on every fork.
--     We pcall around the call so a missing API degrades to "0" cleanly.
---------------------------------------------------------------------------
local params = ...
local player = params.player
local pane_w = params.pane_w
local pane_h = params.pane_h

-- Column definitions.  Each entry says how to fetch its value from a
-- Steps object:
--   source = "radar" -> uses steps:GetRadarValues(player):GetValue("RadarCategory_"..key)
--   source = "tech"  -> uses steps:GetTechCounts(player):GetValue("TechCountsCategory_"..key)
local STATS = {
	{ key = "Notes",      label = "NOTES",  source = "radar" },
	{ key = "Jumps",      label = "JUMPS",  source = "radar" },
	{ key = "Holds",      label = "HOLDS",  source = "radar" },
	{ key = "Mines",      label = "MINES",  source = "radar" },
	{ key = "Crossovers", label = "CROSSOVERS", source = "tech"  },
}
local COL_W = (pane_w - 24) / #STATS

local build_cell = function(i, def)
	local x = -pane_w/2 + 12 + (i - 0.5) * COL_W

	return Def.ActorFrame{
		Name = "Stat_" .. def.key,
		InitCommand = function(self) self:x(x) end,

		LoadFont("Wendy/_wendy small")..{
			Name = "Value",
			InitCommand = function(self)
				self:zoom(0.36):diffuse(Color.White):shadowlength(0.5)
					:settext("0"):maxwidth(COL_W - 4)
			end,
		},
		LoadFont("Common Normal")..{
			Name = "Label",
			InitCommand = function(self)
				self:zoom(0.5):y(15):diffuse(color("#8b95a0")):shadowlength(0.5)
					:settext( def.label ):maxwidth(COL_W + 4)
			end,
		},

		SetValueCommand = function(self, p)
			self:GetChild("Value"):settext( tostring(p.value or 0) )
		end,
	}
end

-- Fetch a value from a Steps object for the given stat definition.
-- Returns 0 on any error (missing API, nil steps, etc.).
local FetchValue = function(steps, def, player)
	if not steps then return 0 end
	if def.source == "tech" then
		if not steps.GetTechCounts then return 0 end
		local ok, tc = pcall(steps.GetTechCounts, steps, player)
		if not ok or not tc then return 0 end
		local ok2, v = pcall(tc.GetValue, tc, "TechCountsCategory_" .. def.key)
		if not ok2 or type(v) ~= "number" then return 0 end
		return v
	end
	-- default: radar
	local ok, rv = pcall(steps.GetRadarValues, steps, player)
	if not ok or not rv then return 0 end
	local ok2, v = pcall(rv.GetValue, rv, "RadarCategory_" .. def.key)
	if not ok2 or type(v) ~= "number" then return 0 end
	return v
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
		for _, def in ipairs(STATS) do
			local v = FetchValue(steps, def, player)
			if v < 0 then v = 0 end
			self:GetChild("Stat_" .. def.key):playcommand("SetValue", { value = math.floor(v) })
		end
	end,
}

for i, def in ipairs(STATS) do af[#af+1] = build_cell(i, def) end
return af
