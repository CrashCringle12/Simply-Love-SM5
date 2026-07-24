-- PlayerOptionsShared.lua
--
-- Modal chrome that sits behind the per-player OptionsWheel + item wheels.
-- Renders:
--   * A full-screen dim overlay to visually mute the wheel + player panes
--     while the modal is active.
--   * One panel card per side (P1 left, P2 right) with a player-color
--     accent border so each side reads clearly.
--   * A player header ("P1  ·  PlayerName") + the current song title at
--     the top of each panel.
--   * Late-join prompts for unjoined sides when allowed.
--
-- The whole frame follows the SwitchFocus* message convention already
-- used by the wheel and the player panes so opacity changes stay in sync.
--
-- Interface:
--   LoadActor("./PlayerOptionsShared.lua", { row, col, Input, panel_geom })
--   where panel_geom = { p1_cx, p2_cx, cy, w, h } is computed by
--   default.lua to keep every actor's geometry consistent.
---------------------------------------------------------------------------
local args        = ...
local Input       = args[3]
local panel_geom  = args[4]

local W = panel_geom.w
local H = panel_geom.h
local CY = panel_geom.cy

local PANEL_CX = { [PLAYER_1] = panel_geom.p1_cx, [PLAYER_2] = panel_geom.p2_cx }

local af = Def.ActorFrame{
	InitCommand = function(self) self:diffusealpha(0) end,

	-- Follow the modal open / close message contract.
	SwitchFocusToSongsMessageCommand      = function(self) self:linear(0.15):diffusealpha(0) end,
	SwitchFocusToGroupsMessageCommand     = function(self) self:linear(0.15):diffusealpha(0) end,
	SwitchFocusToSingleSongMessageCommand = function(self) self:sleep(0.15):linear(0.2):diffusealpha(1) end,
	SingleSongCanceledMessageCommand      = function(self) self:linear(0.15):diffusealpha(0) end,

	---------------------------------------------------------------------
	-- Full-screen dim behind the panels
	Def.Quad{
		Name = "ScrimBG",
		InitCommand = function(self)
			self:zoomto(_screen.w, _screen.h):xy(_screen.cx, _screen.cy)
				:diffuse(0, 0, 0, 0.62)
		end,
	},
}

---------------------------------------------------------------------------
-- Build one panel per player.
for player in ivalues(PlayerNumber) do
	local cx = PANEL_CX[player]
	local pn = ToEnumShortString(player)
	local player_color = PlayerColor(player)

	-- Panel body: dark rounded card with a player-color accent bar along
	-- the top edge.  Player-color border is a thin outer quad.
	af[#af+1] = Def.ActorFrame{
		Name = "Panel_" .. pn,
		InitCommand = function(self) self:xy(cx, CY) end,

		-- Colored border ring
		Def.Quad{
			InitCommand = function(self)
				self:zoomto(W + 4, H + 4):diffuse(player_color):diffusealpha(0.9)
			end,
		},
		-- Panel body
		Def.Quad{
			InitCommand = function(self)
				self:zoomto(W, H):diffuse(color("#0a0f13")):diffusealpha(0.96)
			end,
		},
		-- Top accent bar (player color)
		Def.Quad{
			InitCommand = function(self)
				self:zoomto(W, 4):y(-H/2 + 2):diffuse(player_color)
			end,
		},

		-- "P1" tag on the top-left of the panel
		LoadFont("Wendy/_wendy small")..{
			InitCommand = function(self)
				self:zoom(0.4):diffuse(player_color):shadowlength(0.75)
					:halign(0):xy(-W/2 + 12, -H/2 + 22)
					:settext(pn)
			end,
		},
		-- Profile display name to the right of the tag
		LoadFont("Common Normal")..{
			Name = "Name",
			InitCommand = function(self)
				self:zoom(0.9):diffuse(Color.White):shadowlength(0.5)
					:halign(0):xy(-W/2 + 40, -H/2 + 22)
					:maxwidth(W - 60)
			end,
			OnCommand = function(self) self:playcommand("Refresh") end,
			PlayerProfileSetMessageCommand = function(self, p)
				if p.Player == player then self:playcommand("Refresh") end
			end,
			RefreshCommand = function(self)
				local name = "GUEST"
				if GAMESTATE:IsHumanPlayer(player) and PROFILEMAN:IsPersistentProfile(player) then
					local prof = PROFILEMAN:GetProfile(player)
					local n = prof and prof:GetDisplayName() or ""
					if n and n ~= "" then name = n end
				end
				self:settext( name )
			end,
		},

		-- Song title (centered, just under the header row).  Serves as
		-- a reminder of which song this modal is for.
		LoadFont("Common Normal")..{
			Name = "SongTitle",
			InitCommand = function(self)
				self:zoom(0.8):diffuse(color("#cfd6dc")):shadowlength(0.5)
					:xy(0, -H/2 + 46):maxwidth(W - 24)
			end,
			OnCommand = function(self) self:playcommand("Refresh") end,
			CurrentSongChangedMessageCommand = function(self) self:playcommand("Refresh") end,
			RefreshCommand = function(self)
				local s = GAMESTATE:GetCurrentSong()
				self:settext( s and s:GetDisplayMainTitle() or "" )
			end,
		},

		-- "SELECT to cancel" hint at the very bottom of the panel
		LoadFont("Common Normal")..{
			InitCommand = function(self)
				self:zoom(0.6):diffuse(color("#8b95a0")):shadowlength(0.5)
					:xy(0, H/2 - 12)
			end,
			OnCommand = function(self)
				local s = PREFSMAN:GetPreference("ThreeKeyNavigation")
					and THEME:GetString("ScreenSelectMusicCasual", "FooterTextSingleSong3Key")
					or  THEME:GetString("ScreenSelectMusicCasual", "FooterTextSingleSong")
				self:settext( s or "" )
			end,
		},
	}

	---------------------------------------------------------------------
	-- Late-join prompt (only if this side isn't joined and late-join is
	-- allowed).  Overlays the panel content with a blinking hint.
	if not GAMESTATE:IsSideJoined(player) and Input.AllowLateJoin() then
		af[#af+1] = LoadFont("Common Normal")..{
			Name = "LateJoin_" .. pn,
			Text = THEME:GetString("ScreenSelectMusicCasual", "PressStartToLateJoin"),
			InitCommand = function(self)
				self:xy(cx, CY):zoom(1.1):diffuse(Color.White):shadowlength(1)
					:diffuseshift():effectcolor1(1,1,1,1):effectcolor2(1,1,1,0.35):effectperiod(1.3)
			end,
			PlayerJoinedMessageCommand = function(self, params)
				if params.Player == player then
					self:stopeffect():smooth(0.15):zoom(1.5):diffusealpha(0)
				end
			end,
		}
	end
end

return af
