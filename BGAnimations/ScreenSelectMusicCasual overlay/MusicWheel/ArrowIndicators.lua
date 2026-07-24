-- MusicWheel/ArrowIndicators.lua
--
-- Yellow left/right arrow prompts flanking the center jacket.  They pulse
-- gently at rest and flash+shrink when the wheel is scrolled in that
-- direction (:playcommand("Press")).
--
-- The existing arrow art at ../img/arrow.png + arrow_glow.png is reused
-- so we stay visually consistent with other SL wheels and don't need to
-- ship new graphics for this pass.  If we later want the pointier SMX
-- style, we swap the .png files without touching this file.
---------------------------------------------------------------------------
local args = ...
local wheel_config = args.wheel_config

local ITEM_W = wheel_config.item_w
local ARROW_ZOOM = 0.42
local ARROW_INSET = ITEM_W * 1.55  -- distance from wheel center to arrow

local build_arrow = function(name, direction)
	return Def.ActorFrame{
		Name = name,
		InitCommand = function(self)
			self:x(direction * ARROW_INSET)
			-- Draw the arrow pointing outward.  Our source arrow art
			-- points right, so P1-side (direction = -1) gets flipped.
			if direction < 0 then self:rotationz(180) end
		end,

		-- The glow beneath the arrow.  Pulsing color-shift = "alive".
		LoadActor("../img/arrow_glow.png")..{
			Name = "Glow",
			InitCommand = function(self)
				self:zoom(ARROW_ZOOM * 1.2)
					:diffuse( color("#ffe14a") )   -- SMX-style yellow
					:diffuseshift():effectcolor1(1,1,1,0):effectcolor2(1,0.88,0.29,0.9)
					:effectperiod(1.6)
			end,
			PressCommand = function(self)
				self:finishtweening():zoom(ARROW_ZOOM * 1.55):diffusealpha(1)
					:decelerate(0.18):zoom(ARROW_ZOOM * 1.2)
			end,
		},

		-- The arrow itself.
		LoadActor("../img/arrow.png")..{
			Name = "Arrow",
			InitCommand = function(self)
				self:zoom(ARROW_ZOOM):diffuse( color("#ffe14a") )
			end,
			PressCommand = function(self)
				self:finishtweening():zoom(ARROW_ZOOM * 0.82)
					:decelerate(0.18):zoom(ARROW_ZOOM)
			end,
		},
	}
end

return Def.ActorFrame{
	Name = "ArrowIndicators",
	InitCommand = function(self) self:xy(0, 0) end,

	build_arrow("LeftArrow",  -1),
	build_arrow("RightArrow",  1),
}
