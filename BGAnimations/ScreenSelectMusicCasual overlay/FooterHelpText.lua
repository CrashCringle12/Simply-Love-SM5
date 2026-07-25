-- FooterHelpText.lua
--
-- Single-line footer help text.  Different message in each focus state:
--   * SongWheel  -- "Song L/R    Diff U/D    Sort/Group SELECT    Play START"
--   * Modal      -- "Change L/R    START to continue    SELECT to cancel"
--
-- Positioned just ABOVE the player panes.  Pane top for PANE_H=118 and
-- INSET_Y=8 is _screen.h - 8 - 118 = _screen.h - 126.  Rendering at
-- y = _screen.h - 140 places the text roughly 14px above that top edge.
---------------------------------------------------------------------------
local get = function(key)
	local s = THEME:GetString("ScreenSelectMusicCasual", key)
	if not s or s:sub(1,1) == "?" then return "" end
	return s
end

return LoadFont("Common Normal")..{
	Name = "FooterHelpText",
	InitCommand = function(self)
		self:xy(_screen.cx, _screen.h - 170)
			:zoom(0.7):diffuse(color("#cfd6dc")):shadowlength(0.5)
			:settext( get("FooterTextSongs") )
	end,

	SwitchFocusToSongsMessageCommand = function(self)
		self:diffusealpha(0):settext( get("FooterTextSongs") )
			:linear(0.15):diffusealpha(1)
	end,
	SwitchFocusToSingleSongMessageCommand = function(self)
		local s = get("FooterTextSingleSong")
		if PREFSMAN:GetPreference("ThreeKeyNavigation") then
			s = get("FooterTextSingleSong3Key")
		end
		self:diffusealpha(0):settext(s):linear(0.15):diffusealpha(1)
	end,
	SingleSongCanceledMessageCommand = function(self)
		self:diffusealpha(0):settext( get("FooterTextSongs") )
			:linear(0.15):diffusealpha(1)
	end,
}
