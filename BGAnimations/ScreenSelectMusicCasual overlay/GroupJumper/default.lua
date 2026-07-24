-- GroupJumper/default.lua
--
-- Sub-view of the SortMenu opened when the player picks "Change Group".
-- Renders a horizontal sick_wheel coverflow of every allowed group so
-- players can jump straight to another pack.
--
-- The sick_wheel itself is owned by default.lua (like SongWheel) and
-- passed in via args.group_wheel so Input.lua can drive it directly.
-- This file only wires the visual actors (backdrop + wheel actors +
-- title + hint) and the open/close animations.
--
-- Behavior (input handled by Input.lua):
--   * MenuLeft / MenuRight scrolls through groups.
--   * Start jumps the SongWheel to the first song of the chosen group
--     (broadcasts ApplySortMode with mode="Group") and closes this view.
--   * Select or Back returns to the SortMenu without changing anything.
---------------------------------------------------------------------------
local args        = ...
local setup       = args.setup
local group_wheel = args.group_wheel

local NUM_VISIBLE = 5
local CARD_W = WideScale(150, 180)
local CARD_H = 84
local CARD_GAP = 14

-- scale + alpha curve by distance from center slot (0 = focus)
local scale_for_offset = { [0]=1.00, [1]=0.78, [2]=0.55 }
local alpha_for_offset = { [0]=1.00, [1]=0.75, [2]=0.35 }
local xgap_for_offset  = { [0]=0,    [1]=1.05, [2]=1.90 }

---------------------------------------------------------------------------
-- Item metatable for one group card.
local group_item_mt = {
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
							:diffuse( GetCurrentColor() ):diffusealpha(0)
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
				-- Pack banner sprite (loaded per group in set() when present)
				Def.Sprite{
					Name = "Banner",
					InitCommand = function(subself)
						self.banner = subself
						subself:setsize(CARD_W - 20, 32):y(-14):visible(false)
					end,
				},
				LoadFont("Common Normal")..{
					Name = "GroupName",
					InitCommand = function(subself)
						self.name_bmt = subself
						subself:zoom(0.85):diffuse(Color.White):shadowlength(0.75)
							:y(12):maxwidth(CARD_W - 16)
					end,
				},
				LoadFont("Common Normal")..{
					Name = "Count",
					InitCommand = function(subself)
						self.count_bmt = subself
						subself:zoom(0.65):diffuse(color("#8b95a0")):shadowlength(0.5)
							:y(30):maxwidth(CARD_W - 16)
					end,
				},
			}
		end,

		transform = function(self, item_index, num_items, has_focus)
			if not self.container then return end
			-- Matches default.lua's focus_pos override for symmetric layout.
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

		set = function(self, group_name)
			if not group_name or not self.name_bmt then return end
			self.group = group_name
			self.name_bmt:settext(group_name)

			local n = setup.GroupIndex[group_name] and #setup.GroupIndex[group_name] or 0
			self.count_bmt:settext( n .. " " .. THEME:GetString("ScreenSelectMusicCasual", "SongsSuffix") )

			-- Pack banner when available
			if self.banner and SONGMAN.GetSongGroupBannerPath then
				local ok, path = pcall(SONGMAN.GetSongGroupBannerPath, SONGMAN, group_name)
				if ok and type(path) == "string" and path ~= "" then
					self.banner:visible(true):Load(path):scaletoclipped(CARD_W - 20, 32)
				else
					self.banner:visible(false)
				end
			end
		end,
	}
}

---------------------------------------------------------------------------
local af = Def.ActorFrame{
	Name = "GroupJumper",
	InitCommand = function(self)
		self:visible(false):diffusealpha(0)
		-- Override focus_pos for symmetric prev/center/next.  Must
		-- happen before the first set_info_set (in OpenGroupJumper).
		group_wheel.focus_pos = math.ceil(NUM_VISIBLE / 2)
	end,

	OpenGroupJumperMessageCommand = function(self)
		-- Point the wheel at the current song's group (or first available).
		local cur_song = GAMESTATE:GetCurrentSong()
		local cur_group = cur_song and cur_song:GetGroupName() or setup.Groups[1]
		local start_idx = 1
		for i, g in ipairs(setup.Groups) do
			if g == cur_group then start_idx = i; break end
		end
		group_wheel:set_info_set(setup.Groups, start_idx)

		self:stoptweening():visible(true):diffusealpha(0):linear(0.15):diffusealpha(1)
	end,

	CloseGroupJumperMessageCommand = function(self)
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
				:settext( THEME:GetString("ScreenSelectMusicCasual", "ChangeGroupTitle") )
		end,
	},

	-- Bottom hint
	LoadFont("Common Normal")..{
		InitCommand = function(self)
			self:xy(_screen.cx, _screen.cy + 110)
				:zoom(0.75):diffuse(color("#cfd6dc")):shadowlength(0.5)
				:settext( THEME:GetString("ScreenSelectMusicCasual", "GroupJumperHint") )
		end,
	},

	group_wheel:create_actors("GroupWheel", NUM_VISIBLE, group_item_mt, _screen.cx, _screen.cy + 10),
}

return af
