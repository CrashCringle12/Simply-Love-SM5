-- PlayerPane/LateJoinPrompt.lua
--
-- Overlay shown on top of the pane when the player has not yet joined but
-- late-join is allowed.  Hides itself if the player is joined already, or
-- if late-join is disabled by the coin/premium settings.
---------------------------------------------------------------------------
local params = ...
local player = params.player
local pane_w = params.pane_w
local pane_h = params.pane_h

-- Same rules Input.lua uses.  Kept locally to avoid a circular dep.
local AllowLateJoin = function()
	if GAMESTATE:GetCurrentStyle():GetName() ~= "single" then return false end
	if PREFSMAN:GetPreference("EventMode") then return true end
	if GAMESTATE:GetCoinMode() ~= "CoinMode_Pay" then return true end
	if GAMESTATE:GetCoinMode() == "CoinMode_Pay"
	   and PREFSMAN:GetPreference("Premium") == "Premium_2PlayersFor1Credit" then return true end
	return false
end

local ShouldShow = function()
	if GAMESTATE:IsHumanPlayer(player) then return false end
	return AllowLateJoin()
end

return Def.ActorFrame{
	Name = "LateJoinPrompt",
	InitCommand = function(self)
		-- covers the entire pane; drawn last so it visually replaces the
		-- underlying widgets when active
		self:xy(0, 0)
		self:visible( ShouldShow() )
	end,

	OnCommand = function(self) self:playcommand("Refresh") end,
	PlayerJoinedMessageCommand   = function(self, p)
		if p.Player == player then
			self:linear(0.15):diffusealpha(0):queuecommand("Hide")
		end
	end,
	HideCommand = function(self) self:visible(false):diffusealpha(1) end,
	RefreshCommand = function(self) self:visible( ShouldShow() ) end,

	Def.Quad{
		InitCommand = function(self)
			self:zoomto(pane_w, pane_h):diffuse(0, 0, 0, 0.75)
		end,
	},

	LoadFont("Common Normal")..{
		Text = THEME:GetString("ScreenSelectMusicCasual", "PressStartToLateJoin"),
		InitCommand = function(self)
			self:zoom(0.95):shadowlength(0.75):diffuse(Color.White)
				:diffuseshift():effectcolor1(1,1,1,1):effectcolor2(1,1,1,0.5):effectperiod(1.4)
				:maxwidth(pane_w - 16)
		end,
	},
}
