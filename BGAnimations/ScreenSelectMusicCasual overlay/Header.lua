-- Header.lua
--
-- The top bar of ScreenSelectMusicCasual.  In the horizontal redesign the
-- title is always "CHOOSE YOUR SONG" (the old flow's "Choose Your Group"
-- state no longer exists -- groups are switched via the SortMenu overlay).
--
-- On the right side we show:
--   * The stage number ("Stage 1 of 3") when not in EventMode.
--   * A subtle sort-mode label ("Sort: Group") once Step 6/7 lands and
--     starts broadcasting "SortModeChanged".  Renders empty until then.
---------------------------------------------------------------------------
local HEADER_H = 40

local af = Def.ActorFrame{
	Name = "Header",

	-- Background bar
	Def.Quad{
		InitCommand = function(self)
			self:diffuse(color("#000000dd"))
				:zoomto(_screen.w, HEADER_H)
				:valign(0):xy(_screen.cx, 0)
		end,
	},

	-- Title
	LoadFont("Common Header")..{
		Name = "Title",
		Text = THEME:GetString("ScreenSelectMusicCasual", "HeaderText"),
		InitCommand = function(self)
			self:diffuse(Color.White):zoom(WideScale(0.55, 0.65))
				:horizalign(left):xy(12, HEADER_H/2)
		end,
	},

	-- Sort mode label (right side).  Populated by SortModeChanged; hidden
	-- until we have one.
	LoadFont("Common Normal")..{
		Name = "SortLabel",
		InitCommand = function(self)
			self:diffuse(color("#dddddd")):diffusealpha(0.85):zoom(0.75)
				:horizalign(right):xy(_screen.w - 12, HEADER_H/2)
				:settext("")
		end,
		SortModeChangedMessageCommand = function(self, params)
			if not params or not params.mode then return end
			local key = "SortMode_" .. params.mode
			local label = THEME:GetString("ScreenSelectMusicCasual", key)
			if not label or label == "" or label:sub(1,1) == "?" then label = params.mode end
			self:settext( THEME:GetString("ScreenSelectMusic", "SortBy") .. ": " .. label )
		end,
	},
}

-- Stage number (only outside EventMode).  Positioned above the sort label
-- if we're rendering both.
if not PREFSMAN:GetPreference("EventMode") then
	af[#af+1] = LoadFont("Common Header")..{
		Name = "Stage",
		Text = SSM_Header_StageText(),
		InitCommand = function(self)
			self:diffuse(Color.White):zoom(0.5)
				:horizalign(right):xy(_screen.w - 12, HEADER_H/2 - 8)
		end,
	}
end

return af
