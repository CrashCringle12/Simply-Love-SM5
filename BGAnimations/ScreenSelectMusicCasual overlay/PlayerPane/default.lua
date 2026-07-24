-- PlayerPane/default.lua
--
-- Composes a bottom-corner information pane for a single player.  In the
-- current design the shared difficulty row lives in the info backdrop
-- above (see MusicWheel/SharedDifficultyRow.lua), so this pane focuses
-- entirely on THIS player's currently activated chart.
--
-- Layout (top -> bottom, PANE_H = 118):
--   Profile header    -- "P1  ·  PlayerName"
--   Difficulty label  -- big colored "7 HARD"
--   Song step stats   -- notes / jumps / holds / mines for this chart
--   High-score panel  -- grade + %score, or "NO HIGH SCORE"
--   Late-join prompt  -- overlaid when this side hasn't joined yet
--
-- Height is intentionally kept modest so the footer help text has room
-- to sit above without overlapping.
---------------------------------------------------------------------------
local args = ...
local player = args.player
local pn     = ToEnumShortString(player)

local PANE_W  = WideScale(280, 320)
local PANE_H  = 118
local INSET_X = 10
local INSET_Y = 8

local side     = (player == PLAYER_1) and -1 or 1
local anchor_x = (player == PLAYER_1)
	and (INSET_X + PANE_W/2)
	or  (_screen.w - INSET_X - PANE_W/2)
local anchor_y = _screen.h - INSET_Y - PANE_H/2

local params = {
	player = player,
	pane_w = PANE_W,
	pane_h = PANE_H,
	side   = side,
}

local af = Def.ActorFrame{
	Name = "PlayerPane_" .. pn,
	InitCommand = function(self)
		self:xy(anchor_x, anchor_y)
		self:visible( GAMESTATE:IsHumanPlayer(player) )
	end,

	PlayerJoinedMessageCommand = function(self, p)
		if p.Player == player then self:visible(true) end
	end,
	PlayerUnjoinedMessageCommand = function(self, p)
		if p.Player == player then self:visible(false) end
	end,

	SwitchFocusToSingleSongMessageCommand = function(self)
		self:linear(0.15):diffusealpha(0)
	end,
	SwitchFocusToSongsMessageCommand = function(self)
		self:linear(0.15):diffusealpha(1)
	end,
	SwitchFocusToGroupsMessageCommand = function(self)
		self:linear(0.15):diffusealpha(1)
	end,
	SingleSongCanceledMessageCommand = function(self)
		self:linear(0.15):diffusealpha(1)
	end,

	Def.Quad{
		Name = "PaneBG",
		InitCommand = function(self)
			self:zoomto(PANE_W, PANE_H):diffuse(color("#0a0f13ee"))
		end,
	},
	Def.Quad{
		Name = "AccentTop",
		InitCommand = function(self)
			self:zoomto(PANE_W, 3):y(-PANE_H/2 + 1.5)
				:diffuse( PlayerColor(player) )
		end,
	},

	LoadActor("./ProfileHeader.lua",   params),
	LoadActor("./DifficultyLabel.lua", params),
	LoadActor("./SongStepStats.lua",   params),
	LoadActor("./HighScorePanel.lua",  params),
	LoadActor("./LateJoinPrompt.lua",  params),
}

-- Future SSM hooks: density graph + pattern info slots for the eventual
-- regular-SSM reuse of this module.  CasualMode never passes these.
if args.density_graph then af[#af+1] = args.density_graph(params) end
if args.pattern_info  then af[#af+1] = args.pattern_info(params)  end

return af
