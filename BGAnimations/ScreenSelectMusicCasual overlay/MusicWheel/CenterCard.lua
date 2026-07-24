-- MusicWheel/CenterCard.lua
--
-- The animated glow border that surrounds whatever jacket is currently in
-- the center slot of the horizontal wheel.  Sits behind the jackets in
-- draw order but on top of the wheel background so it "hugs" the focus.
--
-- Visual language:
--   * Two nested Quads produce a hollow border ring (outer bright, inner
--     transparent = the frame).  Colored using DifficultyColor for the
--     currently selected steps if available, otherwise SL's current color.
--   * A slow diffuseshift + rainbow tint on the outer border gives it the
--     SMX "energized frame" feel while staying inside the SL palette.
---------------------------------------------------------------------------
local args = ...
local wheel_config = args.wheel_config

local ITEM_W, ITEM_H = wheel_config.item_w, wheel_config.item_h
local BORDER = 8

local af = Def.ActorFrame{
	Name = "CenterCard",
	InitCommand = function(self)
		self:xy(0, 0)   -- parented to the wheel container, which is centered
	end,

	-- Outer glow ring (bright colored quad, larger than jacket)
	Def.Quad{
		Name = "GlowOuter",
		InitCommand = function(self)
			self:zoomto(ITEM_W + BORDER*2, ITEM_H + BORDER*2)
				:diffuse( GetCurrentColor() )
				:diffusealpha(0.85)
		end,
		OnCommand = function(self)
			self:diffuseshift():effectperiod(2.4)
				:effectcolor1( GetCurrentColor() )
				:effectcolor2( GetCurrentColor(true) )
		end,
		CurrentSongChangedMessageCommand = function(self)
			-- Retint on song change; we intentionally do NOT pull from
			-- current steps yet because the wheel drives current-song only.
			self:effectcolor1( GetCurrentColor() )
				:effectcolor2( GetCurrentColor(true) )
		end,
	},

	-- Inner cutout (black quad slightly larger than jacket to leave a
	-- 1-2px hairline breathing room between the jacket and the glow).
	Def.Quad{
		Name = "GlowCutout",
		InitCommand = function(self)
			self:zoomto(ITEM_W + 2, ITEM_H + 2)
				:diffuse(0, 0, 0, 1)
		end,
	},
}

return af
