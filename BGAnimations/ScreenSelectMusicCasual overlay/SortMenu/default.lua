-- SortMenu/default.lua
--
-- Overlay opened when the player presses Select on the SongWheel.
-- Shows five sort options as a horizontal row of cards:
--
--     [ Change Group ]  [ Title ]  [ Artist ]  [ Most Played ]  [ Recently Played ]
--                            ^^^^  <-- highlighted cursor
--
-- Behavior (input handled by Input.lua):
--   * MenuLeft / MenuRight cycles the cursor across the 5 cards.
--   * Start on "Change Group" opens the GroupJumper sub-view.
--   * Start on any other option applies that sort mode (broadcasts
--     ApplySortMode; MusicWheel rebuilds its list) and closes the menu.
--   * Select or Back closes the menu without changing anything.
--
-- Cursor position is driven by SortMenuCursorChanged broadcasts from
-- Input.lua so the visual highlight stays in sync with the state
-- machine.  Options list also lives in Input.lua so both sides agree.
---------------------------------------------------------------------------
local args = ...
local setup = args.setup

-- Must stay in sync with `sort_options` in Input.lua.  Duplicated only
-- for the localization key lookups; the mode names come from Input.
local option_keys = { "ChangeGroup", "Title", "Artist", "MostPlayed", "RecentlyPlayed" }
local NUM = #option_keys

-- Layout
local CARD_W    = 132
local CARD_H    = 60
local CARD_GAP  = 12
local ROW_Y     = _screen.cy + 10
local TITLE_Y   = _screen.cy - 80
local HINT_Y    = _screen.cy + 90

local get = function(key)
	local s = THEME:GetString("ScreenSelectMusicCasual", "SortMode_" .. key)
	if not s or s:sub(1,1) == "?" then return key end
	return s
end

-- Small helper: total row width used for centering cards
local ROW_TOTAL_W = NUM * CARD_W + (NUM - 1) * CARD_GAP
local FIRST_CARD_X = _screen.cx - ROW_TOTAL_W/2 + CARD_W/2

-- Build a single sort option card.
local build_card = function(index, key)
	local x = FIRST_CARD_X + (index - 1) * (CARD_W + CARD_GAP)

	local card = Def.ActorFrame{
		Name = "SortCard_" .. index,
		InitCommand = function(self) self:xy(x, ROW_Y) end,

		-- Highlight border (only visible for the currently focused card)
		Def.Quad{
			Name = "Border",
			InitCommand = function(self)
				self:zoomto(CARD_W + 6, CARD_H + 6)
					:diffuse( GetCurrentColor() ):diffusealpha(0)
			end,
		},
		-- Card body
		Def.Quad{
			Name = "Body",
			InitCommand = function(self)
				self:zoomto(CARD_W, CARD_H):diffuse( color("#233038") ):diffusealpha(0.95)
			end,
		},
		-- Icon strip: use a small quad recolored by option to give each
		-- card a visual anchor.
		Def.Quad{
			Name = "IconStrip",
			InitCommand = function(self)
				local role_colors = {
					ChangeGroup    = color("#ffe14a"),
					Title          = color("#7cd3ff"),
					Artist         = color("#c199ff"),
					MostPlayed     = color("#ff9d5b"),
					RecentlyPlayed = color("#5bffa0"),
				}
				self:zoomto(4, CARD_H):x(-CARD_W/2 + 2)
					:diffuse( role_colors[key] or Color.White )
			end,
		},
		LoadFont("Common Normal")..{
			Name = "Label",
			InitCommand = function(self)
				self:zoom(0.85):diffuse(Color.White):shadowlength(0.75)
					:maxwidth(CARD_W - 20):settext( get(key) )
			end,
		},

		-- Focus/blur animations driven by SortMenuCursorChanged broadcast
		SortMenuCursorChangedMessageCommand = function(self, params)
			if not params then return end
			if params.cursor == index then
				self:finishtweening():linear(0.1):zoom(1.06)
				self:GetChild("Border"):stoptweening():linear(0.1):diffusealpha(1)
				self:GetChild("Body"):stoptweening():linear(0.1):diffusealpha(1)
			else
				self:finishtweening():linear(0.1):zoom(1.0)
				self:GetChild("Border"):stoptweening():linear(0.1):diffusealpha(0)
				self:GetChild("Body"):stoptweening():linear(0.1):diffusealpha(0.75)
			end
		end,
		-- Small "chosen" pulse when the user commits with Start
		SortMenuChoseMessageCommand = function(self, params)
			if params and params.cursor == index then
				self:finishtweening():decelerate(0.15):zoom(1.15):accelerate(0.15):zoom(1.0)
			end
		end,
	}
	return card
end

---------------------------------------------------------------------------
local af = Def.ActorFrame{
	Name = "SortMenu",
	InitCommand = function(self) self:visible(false):diffusealpha(0) end,

	OpenSortMenuMessageCommand = function(self)
		self:stoptweening():visible(true):diffusealpha(0):linear(0.15):diffusealpha(1)
		-- Input.lua broadcasts SortMenuCursorChanged right after
		-- OpenSortMenu, which the card children listen for; no need to
		-- forward it here (playcommand does not propagate to children).
	end,
	CloseSortMenuMessageCommand = function(self)
		self:stoptweening():linear(0.15):diffusealpha(0):queuecommand("HideMe")
	end,
	HideMeCommand = function(self) self:visible(false) end,

	-- Scrim over the base screen
	Def.Quad{
		Name = "Scrim",
		InitCommand = function(self)
			self:xy(_screen.cx, _screen.cy):zoomto(_screen.w, _screen.h)
				:diffuse(0, 0, 0, 0.72)
		end,
	},

	-- Title
	LoadFont("Wendy/_wendy small")..{
		Name = "Title",
		InitCommand = function(self)
			self:xy(_screen.cx, TITLE_Y)
				:zoom(0.5):diffuse(Color.White):shadowlength(1)
				:settext( THEME:GetString("ScreenSelectMusic", "SortBy"):upper() )
		end,
	},

	-- Bottom hint
	LoadFont("Common Normal")..{
		Name = "Hint",
		InitCommand = function(self)
			self:xy(_screen.cx, HINT_Y)
				:zoom(0.75):diffuse(color("#cfd6dc")):shadowlength(0.5)
				:settext(
					THEME:GetString("ScreenSelectMusicCasual", "SortMenuHint")
				)
		end,
	},
}

for i, key in ipairs(option_keys) do
	af[#af+1] = build_card(i, key)
end

return af
