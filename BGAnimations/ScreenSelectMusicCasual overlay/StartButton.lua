-- StartButton.lua
--
-- Big pulsing green pill rendered at the bottom-center of the modal
-- overlay.  Hidden by default; shown once both joined players have
-- advanced through every option row to the terminal Exit row.
--
-- Message contract (broadcast from Input.lua):
--   SwitchFocusToSingleSong          : modal opened -- reset button state
--   SwitchFocusToSongs / SingleSong* : modal closed -- hide button
--   BothPlayersAreReady              : light it up, players can commit
---------------------------------------------------------------------------
local args = ...
local panel_geom = args and args.panel_geom or nil

-- Positioned at bottom center between the two panels.  Falls back to
-- _screen coordinates if panel geometry isn't threaded through.
local BUTTON_CX = panel_geom and _screen.cx or _screen.cx
local BUTTON_CY = panel_geom and (panel_geom.cy + panel_geom.h/2 + 28)
                              or (_screen.h - 60)

local W, H = 160, 44
local onePlayerIsAtLastRow = false
return Def.ActorFrame{
	Name = "StartButton",
	InitCommand = function(self)
		self:xy(BUTTON_CX, BUTTON_CY):diffusealpha(0)
	end,

	SwitchFocusToSingleSongMessageCommand = function(self)
		-- Modal opened; button is present but dim until players are ready.
		self:sleep(0.25):linear(0.15):diffusealpha(0.55)
	end,
	SwitchFocusToSongsMessageCommand = function(self)
		self:stopeffect():linear(0.15):diffusealpha(0)
	end,
	SingleSongCanceledMessageCommand = function(self)
		self:stopeffect():linear(0.15):diffusealpha(0)
	end,
	BothPlayersAreReadyMessageCommand = function(self)
		self:linear(0.15):diffusealpha(1)
		-- Extra bounce on the pill quad + text to signal "you can commit now"
		local quad = self:GetChild("Pill")
		local text = self:GetChild("Text")
		if quad then quad:finishtweening():decelerate(0.15):zoomto(W*1.06, H*1.06):accelerate(0.15):zoomto(W, H) end
		if text then text:finishtweening():decelerate(0.15):zoom(1.05):accelerate(0.15):zoom(1.0) end
	end,
	CancelBothPlayersAreReadyMessageCommand = function(self)
        if not onePlayerIsAtLastRow then
           return
        end
        onePlayerIsAtLastRow = false
		self:linear(0.15):diffusealpha(0.55)
        local text = self:GetChild("Text")
        if text then text:finishtweening():decelerate(0.1):accelerate(0.15):zoom(0.5) end
	end,

	-- Soft outer glow (pulses when active)
	LoadActor("./img/start_glow.png")..{
		Name = "Glow",
		InitCommand = function(self)
			self:zoomto(W*1.2, H*1.47)
		end,
		OnCommand = function(self)
			self:diffuseshift():effectcolor1(color("#55CC5500")):effectcolor2(color("#55CC55FF")):effectperiod(1.6)
		end,
        OnePlayerIsAtLastRowMessageCommand = function(self, params)
            if onePlayerIsAtLastRow then
                return
            end
            self:diffuseshift():effectcolor1(color("#55CC55FF")):effectcolor2(PlayerColor(params.player)):effectperiod(1.1)
            onePlayerIsAtLastRow = true
        end,
        CancelBothPlayersAreReadyMessageCommand = function(self)
            self:diffuseshift():effectcolor1(color("#55CC5500")):effectcolor2(color("#55CC55FF")):effectperiod(1.6)
        end,
	},

	-- Pill body
	Def.Quad{
		Name = "Pill",
		InitCommand = function(self)
			self:zoomto(W, H):diffuseshift()
				:effectcolor1(color("#33aa33")):effectcolor2(color("#55cc55")):effectperiod(1.6)
		end,
	},

	-- Label.  Reads "PRESS" until both players are ready; "START!" then.
	LoadFont("Wendy/_wendy small")..{
		Name = "Text",
		InitCommand = function(self)
			self:diffuse(Color.Black):zoom(0.5):shadowlength(0):settext(
				THEME:GetString("ScreenSelectMusicCasual", "Press")
			)
		end,
		BothPlayersAreReadyMessageCommand = function(self)
			self:settext( THEME:GetString("ScreenSelectMusicCasual", "Start") )
		end,
		CancelBothPlayersAreReadyMessageCommand = function(self)
			self:settext( THEME:GetString("ScreenSelectMusicCasual", "Press") )
		end,
		SwitchFocusToSongsMessageCommand = function(self)
			self:settext( THEME:GetString("ScreenSelectMusicCasual", "Press") )
		end,
	},
}
