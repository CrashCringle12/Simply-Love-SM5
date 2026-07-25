-- LetterJumper/default.lua
--
-- Sub-view of the SortMenu opened when the player picks "By Title" or
-- "By Artist".  Presents a horizontal coverflow of first-letter cards
-- (# + A-Z) so the player can jump straight to the letter they want.
--
-- Follows the same architecture as GroupJumper: the sick_wheel is owned
-- externally (default.lua) and passed in via args.letter_wheel so
-- Input.lua can drive it directly.
--
-- Behavior (handled by Input.lua):
--   * MenuLeft / MenuRight scrolls through letters.
--   * Start applies the appropriate sort (Title or Artist -- whichever
--     the SortMenu was pointing at when this was opened) and jumps the
--     SongWheel to the first matching song.
--   * Select or Back returns to the SortMenu without changing anything.
---------------------------------------------------------------------------
local args         = ...
local setup        = args.setup
local letter_wheel = args.letter_wheel

local LETTERS = { "#", "A","B","C","D","E","F","G","H","I","J","K","L","M",
                  "N","O","P","Q","R","S","T","U","V","W","X","Y","Z" }

local NUM_VISIBLE = 7
local CARD_W = 92
local CARD_H = 92
local CARD_GAP = 8

local scale_for_offset = { [0]=1.00, [1]=0.82, [2]=0.62, [3]=0.42 }
local alpha_for_offset = { [0]=1.00, [1]=0.80, [2]=0.55, [3]=0.28 }
local xgap_for_offset  = { [0]=0,    [1]=1.05, [2]=1.85, [3]=2.55 }

-- Cycle color per letter for a bit of variety along the row.  Uses the
-- SL palette so it changes with the player's color choice.
local color_for_letter = function(letter)
	local n = (letter == "#") and 1 or ((string.byte(letter) - string.byte("A")) % 8 + 1)
	return GetHexColor(n, false)
end

---------------------------------------------------------------------------
-- Item metatable for one letter card.
local letter_item_mt = {
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
				-- Accent stripe along the left edge (color per letter).
				Def.Quad{
					Name = "Stripe",
					InitCommand = function(subself)
						self.stripe = subself
						subself:zoomto(4, CARD_H):x(-CARD_W/2 + 2):diffuse(Color.White)
					end,
				},
				-- Big letter glyph
				LoadFont("Wendy/_wendy small")..{
					Name = "Letter",
					InitCommand = function(subself)
						self.letter_bmt = subself
						subself:zoom(1.4):diffuse(Color.White):shadowlength(1)
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
			local xgap  = (xgap_for_offset[off] or xgap_for_offset[3]) * (CARD_W + CARD_GAP)

			self.container:finishtweening():linear(0.15)
				:x(direction * xgap):zoom(scale):diffusealpha(alpha)

			if self.border then
				self.border:stoptweening():linear(0.15):diffusealpha(has_focus and 1 or 0)
			end
		end,

		set = function(self, letter)
			if not letter or not self.letter_bmt then return end
			self.letter = letter
			self.letter_bmt:settext(letter)
			local c = color_for_letter(letter)
			if self.stripe then self.stripe:diffuse(c) end
			if self.border then self.border:diffuse(c) end
		end,
	}
}

---------------------------------------------------------------------------
return Def.ActorFrame{
	Name = "LetterJumper",
	InitCommand = function(self)
		self:visible(false):diffusealpha(0)
		-- Symmetric prev/center/next requires focus_pos = ceil(N/2).
		letter_wheel.focus_pos = math.ceil(NUM_VISIBLE / 2)
	end,

	OpenLetterJumperMessageCommand = function(self, params)
		-- Center on the current song's first letter when possible so the
		-- jumper opens in a spot near where the user already is.
		local start_idx = 1
		local cur = GAMESTATE:GetCurrentSong()
		if cur then
			local mode = (params and params.mode) or "Title"
			local s = (mode == "Artist" and cur:GetDisplayArtist() or cur:GetDisplayMainTitle()) or ""
			s = s:gsub("^%s+", "")
			local first = s:sub(1,1):upper()
			local target = (first >= "A" and first <= "Z") and first or "#"
			for i, l in ipairs(LETTERS) do
				if l == target then start_idx = i; break end
			end
		end
		letter_wheel:set_info_set(LETTERS, start_idx)
		self:stoptweening():visible(true):diffusealpha(0):linear(0.15):diffusealpha(1)
	end,

	CloseLetterJumperMessageCommand = function(self)
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

	-- Title.  Text changes based on whether we're jumping by Title or Artist.
	LoadFont("Wendy/_wendy small")..{
		Name = "Title",
		InitCommand = function(self)
			self:xy(_screen.cx, _screen.cy - 100)
				:zoom(0.5):diffuse(Color.White):shadowlength(1)
				:settext( THEME:GetString("ScreenSelectMusicCasual", "LetterJumperTitleTitle") )
		end,
		OpenLetterJumperMessageCommand = function(self, params)
			local key = (params and params.mode == "Artist")
				and "LetterJumperTitleArtist"
				or  "LetterJumperTitleTitle"
			self:settext( THEME:GetString("ScreenSelectMusicCasual", key) )
		end,
	},

	-- Bottom hint
	LoadFont("Common Normal")..{
		InitCommand = function(self)
			self:xy(_screen.cx, _screen.cy + 110)
				:zoom(0.75):diffuse(color("#cfd6dc")):shadowlength(0.5)
				:settext( THEME:GetString("ScreenSelectMusicCasual", "LetterJumperHint") )
		end,
	},

	letter_wheel:create_actors("LetterWheel", NUM_VISIBLE, letter_item_mt, _screen.cx, _screen.cy + 10),
}
