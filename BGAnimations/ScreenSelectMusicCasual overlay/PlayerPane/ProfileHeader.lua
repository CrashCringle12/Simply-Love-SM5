-- PlayerPane/ProfileHeader.lua
--
-- The top row of the per-player pane: "P1  ·  PlayerName".  Player color
-- tag on the left, resolved profile name (falling back to "GUEST" for
-- unpersistent profiles) on the right.
---------------------------------------------------------------------------
local params = ...
local player = params.player
local pn     = ToEnumShortString(player)
local pane_w = params.pane_w
local pane_h = params.pane_h

local GetProfileName = function()
	if not GAMESTATE:IsHumanPlayer(player) then return "" end
	if PROFILEMAN:IsPersistentProfile(player) then
		local profile = PROFILEMAN:GetProfile(player)
		if profile then
			local n = profile:GetDisplayName()
			if n and n ~= "" then return n end
		end
	end
	return "GUEST"
end

return Def.ActorFrame{
	Name = "ProfileHeader",
	InitCommand = function(self)
		self:y(-pane_h/2 + 14)
	end,

	-- "P1" or "P2" -- small tag, colored
	LoadFont("Wendy/_wendy small")..{
		InitCommand = function(self)
			self:zoom(0.32)
				:diffuse( PlayerColor(player) )
				:halign(0):x(-pane_w/2 + 12)
				:settext(pn)
		end,
	},

	-- profile display name
	LoadFont("Common Normal")..{
		Name = "Name",
		InitCommand = function(self)
			self:zoom(0.9):diffuse(Color.White):shadowlength(0.5)
				:halign(0):x(-pane_w/2 + 42)
				:maxwidth(pane_w - 60)
		end,
		OnCommand = function(self) self:playcommand("Refresh") end,
		PlayerJoinedMessageCommand    = function(self, p) if p.Player == player then self:playcommand("Refresh") end end,
		PlayerProfileSetMessageCommand = function(self, p) if p.Player == player then self:playcommand("Refresh") end end,
		RefreshCommand = function(self) self:settext( GetProfileName() ) end,
	},
	LoadActor("./ProfileAvatar", {player, pane_w/2 - 20})
}
