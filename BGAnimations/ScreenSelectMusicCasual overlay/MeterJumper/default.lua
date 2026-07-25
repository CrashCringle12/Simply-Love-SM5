-- MeterJumper/default.lua
--
-- Sub-view of the SortMenu opened when the player picks "By Meter".
-- Presents a horizontal coverflow of meter levels (1..CasualMaxMeter),
-- each labeled with the Casual difficulty name (Novice / Novice+ / Easy /
-- Easy+ / ... / Insane) so the player can see both the number and its
-- name.  Color-coded by the SL DifficultyColor that meter maps to.
--
-- Follows the same architecture as GroupJumper / LetterJumper: the
-- sick_wheel is owned externally (default.lua) and passed in via
-- args.meter_wheel so Input.lua can drive it directly.
--
-- Behavior (handled by Input.lua):
--   * MenuLeft / MenuRight scrolls through meters.
--   * Start applies the Meter sort and jumps the SongWheel to the first
--     song that has a chart at the chosen meter.
--   * Select or Back returns to the SortMenu without changing anything.
---------------------------------------------------------------------------
local args        = ...
local setup       = args.setup
local meter_wheel = args.meter_wheel

local NUM_VISIBLE = 5
local CARD_W = 130
local CARD_H = 92
local CARD_GAP = 10

local scale_for_offset = { [0]=1.00, [1]=0.78, [2]=0.55 }
local alpha_for_offset = { [0]=1.00, [1]=0.75, [2]=0.35 }
local xgap_for_offset  = { [0]=0,    [1]=1.05, [2]=1.90 }

-- Meter -> Casual difficulty name (mirrors OptionRows.lua / SharedDifficultyRow).
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

-- Meter -> approximate Difficulty enum for coloring.  Casual mode's
-- meter->difficulty mapping is fuzzy across songs; this is a visual
-- approximation only.
local MeterToDifficultyColor = function(m)
	local diff = "Difficulty_Challenge"
	if m <= 2 then diff = "Difficulty_Beginner"
	elseif m <= 4 then diff = "Difficulty_Easy"
	elseif m <= 6 then diff = "Difficulty_Medium"
	elseif m <= 8 then diff = "Difficulty_Hard"
	end
	return DifficultyColor(diff)
end

---------------------------------------------------------------------------
-- Item metatable for one meter card.
local meter_item_mt = {
	__index = {
		create_actors = function(self, name)
			self.name = name

			return Def.ActorFrame{
				Name = name,
				InitCommand = function(subself)
					self.container = subself
					subself:diffusealpha(0)
				end,

				Def.Quad{
					Name = "Border",
					InitCommand = function(subself)
						self.border = subself
						subself:zoomto(CARD_W + 6, CARD_H + 6)
							:diffuse(Color.White):diffusealpha(0)
					end,
				},
				Def.Quad{
					Name = "Body",
					InitCommand = function(subself)
						self.body = subself
						subself:zoomto(CARD_W, CARD_H)
							:diffuse(color("#233038")):diffusealpha(0.95)
					end,
				},
				Def.Quad{
					Name = "Stripe",
					InitCommand = function(subself)
						self.stripe = subself
						subself:zoomto(4, CARD_H):x(-CARD_W/2 + 2):diffuse(Color.White)
					end,
				},
				-- Big meter number
				LoadFont("Wendy/_wendy small")..{
					Name = "Meter",
					InitCommand = function(subself)
						self.meter_bmt = subself
						subself:zoom(1.2):diffuse(Color.White):shadowlength(1):y(-14)
					end,
				},
				-- Difficulty name under the meter
				LoadFont("Common Normal")..{
					Name = "DiffName",
					InitCommand = function(subself)
						self.name_bmt = subself
						subself:zoom(0.85):diffuse(Color.White):shadowlength(0.75)
							:y(22):maxwidth(CARD_W - 12)
					end,
				},
			}
		end,

		transform = function(self, item_index, num_items, has_focus)
			if not self.container then return end
			local focus_pos = math.ceil(num_items / 2)
			local off       = math.abs(item_index - focus_pos)
			local direction = (item_index < focus_pos) and -1 or 1

			local scale = scale_for_offset[off] or 0
			local alpha = alpha_for_offset[off] or 0
			local xgap  = (xgap_for_offset[off] or xgap_for_offset[2]) * (CARD_W + CARD_GAP)

			self.container:finishtweening():linear(0.15)
				:x(direction * xgap):zoom(scale):diffusealpha(alpha)

			if self.border then
				self.border:stoptweening():linear(0.15):diffusealpha(has_focus and 1 or 0)
			end
		end,

		set = function(self, meter)
			if not meter or not self.meter_bmt then return end
			self.meter = meter
			self.meter_bmt:settext(tostring(meter))
			self.name_bmt:settext(NameForMeter(meter))
			local c = MeterToDifficultyColor(meter)
			if self.stripe then self.stripe:diffuse(c) end
			if self.border then self.border:diffuse(c) end
			-- Also tint the meter/name text in that color for punch.
			self.name_bmt:diffuse(c)
		end,
	}
}

---------------------------------------------------------------------------
-- Compute the list of allowed meters (1..CasualMaxMeter).
local BuildMeters = function()
	local max_m = ThemePrefs.Get("CasualMaxMeter")
	local out = {}
	for m = 1, max_m do out[#out+1] = m end
	return out
end

---------------------------------------------------------------------------
return Def.ActorFrame{
	Name = "MeterJumper",
	InitCommand = function(self)
		self:visible(false):diffusealpha(0)
		meter_wheel.focus_pos = math.ceil(NUM_VISIBLE / 2)
	end,

	OpenMeterJumperMessageCommand = function(self)
		local meters = BuildMeters()

		-- Center on the current player's currently-selected meter if
		-- possible.  Falls back to the middle of the range.
		local start_idx = math.ceil(#meters / 2)
		local cur_steps = GAMESTATE:GetCurrentSteps(PLAYER_1) or GAMESTATE:GetCurrentSteps(PLAYER_2)
		if cur_steps then
			local cm = cur_steps:GetMeter()
			for i, m in ipairs(meters) do
				if m == cm then start_idx = i; break end
			end
		end
		meter_wheel:set_info_set(meters, start_idx)
		self:stoptweening():visible(true):diffusealpha(0):linear(0.15):diffusealpha(1)
	end,

	CloseMeterJumperMessageCommand = function(self)
		self:stoptweening():linear(0.15):diffusealpha(0):queuecommand("HideMe")
	end,
	HideMeCommand = function(self) self:visible(false) end,

	-- Scrim
	Def.Quad{
		Name = "Scrim",
		InitCommand = function(self)
			self:xy(_screen.cx, _screen.cy):zoomto(_screen.w, _screen.h)
				:diffuse(0, 0, 0, 0.72)
		end,
	},

	-- Title
	LoadFont("Wendy/_wendy small")..{
		InitCommand = function(self)
			self:xy(_screen.cx, _screen.cy - 100)
				:zoom(0.5):diffuse(Color.White):shadowlength(1)
				:settext( THEME:GetString("ScreenSelectMusicCasual", "MeterJumperTitle") )
		end,
	},

	-- Bottom hint
	LoadFont("Common Normal")..{
		InitCommand = function(self)
			self:xy(_screen.cx, _screen.cy + 110)
				:zoom(0.75):diffuse(color("#cfd6dc")):shadowlength(0.5)
				:settext( THEME:GetString("ScreenSelectMusicCasual", "MeterJumperHint") )
		end,
	},

	meter_wheel:create_actors("MeterWheel", NUM_VISIBLE, meter_item_mt, _screen.cx, _screen.cy + 10),
}
