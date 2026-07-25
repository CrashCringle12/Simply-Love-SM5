local params = ...
if type(params) ~= "table" then params = {} end

local is_modal = params.modal == true
local demo_player = params.player or PLAYER_1

local game = GAMESTATE:GetCurrentGame():GetName()
local ScreenName, TopScreen, MPN = nil, nil, GAMESTATE:GetMasterPlayerNumber()

local arrow = {
	w = 12,
	h = 20,
	rotation = {
		center = 0,
		up = 45,
		upright = 90,
		right = 135,
		downright= 180,
		down = 225,
		downleft = 270,
		left = 315,
		upleft = 0,
	},
	x = {
		pump = { downleft=-48, upleft=-24, center=0, upright=24, downright=48 },
		techno = { downleft=-84, left=-60, upleft=-36, down=-12, up=12, upright=36, right=60, downright=84 },
		dance = { left=-36, down=-12, up=12, right=36 }
	},
	columns = {
		pump = { "downleft", "upleft", "center", "upright", "downright" },
		techno = { "downleft", "left", "upleft", "down", "up", "upright", "right", "downright" },
		dance = { "left", "down", "up", "right" }
	}
}

local timePerArrow = 0.2
local receptorY = -55
local base_pattern = {
	dance = {
		"left", "down", "left", "right", "down", "up",
		"left", "right", "left", "down", "up", "right",
		"left", "right", "down", "up", "down", "right",
		"left", "right", "up", "down", "up", "right"
	},
	pump = {
		"upright", "center", "downright", "downleft", "center", "upleft",
		"upright", "downleft", "downright", "center", "upright", "downleft",
		"upleft", "center", "upright", "center", "downright", "upleft",
		"downright", "upright", "center", "upleft", "center", "downleft"
	},
	techno = {
		"upleft", "upright", "down", "downright", "downleft", "up",
		"down", "right", "left", "downright", "downleft", "up"
	},
}

-- Per-meter pattern spacing configuration for the modal preview.
-- `DIFFICULTY_GAP_TICKS` = how many blank "ticks" to insert when a gap happens.
-- `DIFFICULTY_GAP_EVERY_ARROWS` = after how many arrows to insert that gap.
--
-- Example:
--   [1] gap_ticks=5, gap_every=1
--   left, (5 blanks), down, (5 blanks), left, ...
--
--   [5] gap_ticks=3, gap_every=3
--   arrow, arrow, arrow, (3 blanks), arrow, arrow, arrow, (3 blanks), ...
local DIFFICULTY_GAP_TICKS = {
	[1]  = 7,
	[2]  = 6,
	[3]  = 4,
    
	[4]  = 3,

	[5]  = 2,

	[6]  = 1,

	[7]  = 2,
	[8]  = 2,
    [9]  = 2,
    [10] = 0,
}
local DIFFICULTY_GAP_EVERY_ARROWS = {
	[1]  = 1,
	[2]  = 1,
	[3]  = 1,

	[4]  = 1,

	[5]  = 3,

	[6]  = 2,

	[7]  = 4,
	[8]  = 5,
    [9]  = 8,
	[10] = 0,
}
local DEFAULT_GAP_TICKS_FOR_9PLUS = 0
local DEFAULT_GAP_EVERY_ARROWS_FOR_9PLUS = 0

-- Fallback for unsupported games (kb7, beat, popn, etc.)
if not base_pattern[game] then
	game = "dance"
end

local currentCMod = 300
local currentMeter = 9
local currentGapTicks = DEFAULT_GAP_TICKS_FOR_9PLUS
local currentGapEveryArrows = DEFAULT_GAP_EVERY_ARROWS_FOR_9PLUS

local Clamp = function(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local GetGapTicksForMeter = function(meter)
	meter = math.max(1, tonumber(meter) or 9)
	if meter >= 10 then return DEFAULT_GAP_TICKS_FOR_9PLUS end
	return DIFFICULTY_GAP_TICKS[meter] or 0
end

local GetGapEveryArrowsForMeter = function(meter)
	meter = math.max(1, tonumber(meter) or 9)
	if meter >= 10 then return DEFAULT_GAP_EVERY_ARROWS_FOR_9PLUS end
	return DIFFICULTY_GAP_EVERY_ARROWS[meter] or 1
end

local ReadPlayerMeter = function(player)
	local steps = GAMESTATE:GetCurrentSteps(player)
	return (steps and steps:GetMeter()) or 9
end

local SetCurrentMeter = function(self, meter)
	meter = math.max(1, tonumber(meter) or 9)
	local gap = GetGapTicksForMeter(meter)
	local cadence = GetGapEveryArrowsForMeter(meter)
	if meter ~= currentMeter or gap ~= currentGapTicks or cadence ~= currentGapEveryArrows then
		currentMeter = meter
		currentGapTicks = gap
		currentGapEveryArrows = cadence
		self:playcommand("RestartPattern")
	end
end

local GetGapInsertionsBeforeArrow = function(previous_arrow_count)
	if not is_modal then return 0 end
	local gap_ticks = tonumber(currentGapTicks) or 0
	local cadence = tonumber(currentGapEveryArrows) or 0
	if gap_ticks <= 0 or cadence <= 0 then return 0 end
	return math.floor(previous_arrow_count / cadence)
end

local GetArrowTimelineTick = function(arrow_index)
	local previous_arrow_count = math.max(0, (tonumber(arrow_index) or 1) - 1)
	return arrow_index + GetGapInsertionsBeforeArrow(previous_arrow_count) * currentGapTicks
end

local GetPatternTotalTicks = function()
	local arrow_count = #base_pattern[game]
	local gap_ticks = tonumber(currentGapTicks) or 0
	local cadence = tonumber(currentGapEveryArrows) or 0
	if not is_modal or gap_ticks <= 0 or cadence <= 0 then return arrow_count end
	return arrow_count + math.floor(arrow_count / cadence) * gap_ticks
end

local ReadPlayerCMod = function(player)
	local po = GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred")
	if not po then return 300 end
	local c = po:CMod()
	return tonumber(c) or 300
end

local GetStepSpacing = function()
	if not is_modal then return arrow.h + 5 end
	-- CMod-aware spacing for the modal demo: larger CMod -> more vertical spacing.
	local c = Clamp(tonumber(currentCMod) or 300, 100, 1000)
	return Clamp(math.floor(c / 12), 18, 40)
end

local notefield = Def.ActorFrame{
	InitCommand = function(self)
		if is_modal then
			self:zoom(params.zoom or 0.7):xy(params.x or _screen.cx, params.y or _screen.cy):MaskDest()
		else
			if game == "dance" then
				self:zoom(1):xy(90, 15)
			elseif game == "techno" then
				self:zoom(0.6):xy(90, -10)
			elseif game == "pump" then
				self:zoom(0.9):xy(90, 10)
			end
		end
	end,
	OnCommand = function(self)
		currentCMod = ReadPlayerCMod(demo_player)
		if is_modal then
			currentMeter = ReadPlayerMeter(demo_player)
			currentGapTicks = GetGapTicksForMeter(currentMeter)
			currentGapEveryArrows = GetGapEveryArrowsForMeter(currentMeter)
		end
		if not is_modal then
			TopScreen = SCREENMAN:GetTopScreen()
			ScreenName = TopScreen and TopScreen:GetName() or ""
		end
	end,
	OffCommand = function(self)
		if not is_modal then self:sleep(0.4):diffusealpha(0) end
	end,
	GameplayDemoSpeedChangedMessageCommand = function(self, p)
		if not is_modal or not p then return end
		if p.Player and p.Player ~= demo_player then return end
		local c = tonumber(p.CMod)
		if c and c ~= currentCMod then
			currentCMod = c
			self:playcommand("RestartPattern")
		end
	end,
	GameplayDemoDifficultyChangedMessageCommand = function(self, p)
		if not is_modal or not p then return end
		if p.Player and p.Player ~= demo_player then return end
		SetCurrentMeter(self, p.Meter)
	end,
	CurrentStepsP1ChangedMessageCommand = function(self)
		if is_modal and demo_player == PLAYER_1 then
			SetCurrentMeter(self, ReadPlayerMeter(demo_player))
		end
	end,
	CurrentStepsP2ChangedMessageCommand = function(self)
		if is_modal and demo_player == PLAYER_2 then
			SetCurrentMeter(self, ReadPlayerMeter(demo_player))
		end
	end,
	CurrentSongChangedMessageCommand = function(self)
		if is_modal then
			SetCurrentMeter(self, ReadPlayerMeter(demo_player))
		end
	end,
}

local function ColumnZoom(column)
	if (game ~= "pump") then return 0.18 end
	return (column == "center") and 0.165 or 0.2
end

for _, column in ipairs(arrow.columns[game]) do
	local file = (column == "center") and "center-body.png" or "arrow-body.png"
	notefield[#notefield+1] = LoadActor(file)..{
		InitCommand = function(self)
			self:rotationz(arrow.rotation[column])
				:x(arrow.x[game][column])
				:y(receptorY)
				:zoom(ColumnZoom(column))
		end
	}
end

local function YieldStepPattern(i, dir)
	local step = Def.ActorFrame{
		InitCommand = function(self)
			self:queuecommand("Update")
			self:MaskDest()
		end,
		OnCommand = function(self)
			self:queuecommand("FirstLoopRegular")
		end,
		RestartPatternCommand = function(self)
			self:stoptweening()
			self:queuecommand("FirstLoopRegular")
		end,
		UpdateCommand = function(self)
			self:visible(true)
			if not is_modal and ScreenName == "ScreenSelectPlayMode" and TopScreen and TopScreen:GetSelectionIndex(MPN) == 0 and i % 3 ~= 0 then
				self:visible(false)
			end
		end,
		FirstLoopRegularCommand = function(self)
			self:stoptweening()
			local base_spacing = GetStepSpacing()
			local tick = GetArrowTimelineTick(i)
			self:y(receptorY + (tick * base_spacing))
				:rotationz(arrow.rotation[dir])
				:x(arrow.x[game][dir])
				:linear(timePerArrow * tick)
				:y(receptorY)
				:queuecommand("LoopRegular")
		end,
		LoopRegularCommand = function(self)
			local base_spacing = GetStepSpacing()
			local total_ticks = GetPatternTotalTicks()
			self:y(receptorY + (total_ticks * base_spacing))
				:linear(timePerArrow * total_ticks)
				:y(receptorY)
				:queuecommand("LoopRegular")
		end,
		FirstLoopMarathonCommand = function(self)
			self:stoptweening()
			local base_spacing = GetStepSpacing()
			local tick = GetArrowTimelineTick(i)
			self:y(receptorY + (tick * base_spacing))
				:rotationz(arrow.rotation[dir])
				:x(arrow.x[game][dir])
				:ease(timePerArrow * tick, 75):addrotationz(720)
				:y(receptorY)
				:queuecommand("LoopMarathon")
		end,
		LoopMarathonCommand = function(self)
			local base_spacing = GetStepSpacing()
			local total_ticks = GetPatternTotalTicks()
			self:y(receptorY + (total_ticks * base_spacing))
				:ease(timePerArrow * total_ticks, 75):addrotationz(720)
				:y(receptorY)
				:queuecommand("LoopMarathon")
		end,
	}

	local files
	if dir == "center" then
		files = { "center-body.png", "center-border.png", "center-feet.png" }
	else
		files = { "arrow-border.png", "arrow-body.png", "arrow-stripes.png" }
	end

	for _, file in ipairs(files) do
		step[#step+1] = LoadActor(file)..{
			InitCommand = function(self)
				self:diffuse(1, 1, 1, 1):zoom(ColumnZoom(dir))
			end,
			OnCommand = function(self)
				if file == "center-feet.png" or file == "arrow-stripes.png" then
					self:blend(Blend.Multiply)
				end
				if file == "center-body.png" or file == "center-feet.png" or file == "arrow-body.png" then
					self:diffuse(GetHexColor(i, true))
				end
			end,
		}
	end

	return step
end

for index, direction in ipairs(base_pattern[game]) do
	notefield[#notefield+1] = YieldStepPattern(index, direction)
end

return notefield
