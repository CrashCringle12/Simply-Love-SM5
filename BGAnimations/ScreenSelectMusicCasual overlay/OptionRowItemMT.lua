-- OptionRowItemMT.lua
--
-- One choice card inside a row's item wheel.  Each row (Chart, Speed)
-- gets its own 3-item sick_wheel; this MT renders one slot as a
-- colored card with prev / current / next symmetric positioning.
--
-- Center card = focused choice, drawn at full scale + brighter border.
-- Prev / next = 85% scale + dimmer.
--
-- Coloring reacts to the choice's role:
--   role = "chart"  -- card takes the DifficultyColor of that chart
--   role = "speed"  -- neutral steel-blue tint
--   (any other)     -- neutral gray
--
-- Visibility is controlled by ancestor ActorFrames (Modal wrapper +
-- per-player wrapper) so this MT never fades itself.  It only handles
-- the horizontal slide-in animation across the 3 slots.
--
-- 3-visible symmetric layout requires sick_wheel's focus_pos = 2, not the
-- default floor(3/2) = 1.  default.lua overrides `focus_pos = 2` on each
-- item wheel before set_info_set is first called.
---------------------------------------------------------------------------
local CARD_W    = WideScale(78, 96)
local CARD_H    = 46
local CARD_GAP  = 8
local CENTER    = 2   -- matches default.lua's focus_pos override

local role_color = {
	speed   = color("#2c3d4a"),
	default = color("#233038"),
}

local optionrow_item_mt = {
	__index = {
		create_actors = function(self, name)
			self.name = name

			return Def.ActorFrame{
				Name = name,
				InitCommand = function(subself)
					self.container = subself
				end,

				-- Card border (behind the fill; slightly larger).  Alpha
				-- reflects focus state per transform().
				Def.Quad{
					Name = "Border",
					InitCommand = function(subself)
						self.border = subself
						subself:zoomto(CARD_W + 4, CARD_H + 4)
							:diffuse(Color.White):diffusealpha(0)
					end,
				},
				-- Card fill (recolored per-choice by set()).
				Def.Quad{
					Name = "Fill",
					InitCommand = function(subself)
						self.fill = subself
						subself:zoomto(CARD_W, CARD_H):diffuse(role_color.default)
					end,
				},
				-- Primary label (meter number for chart, full text otherwise)
				LoadFont("Wendy/_wendy small")..{
					Name = "Primary",
					InitCommand = function(subself)
						self.primary = subself
						subself:zoom(0.5):diffuse(Color.White):shadowlength(0.75)
							:y(-8):maxwidth(CARD_W - 2)
					end,
				},
				-- Secondary label (name under meter for chart cards)
				LoadFont("Common Normal")..{
					Name = "Secondary",
					InitCommand = function(subself)
						self.secondary = subself
						subself:zoom(0.75):diffuse(Color.White):shadowlength(0.5)
							:y(14):maxwidth(CARD_W - 8)
					end,
				},
			}
		end,

		-- sick_wheel drives this on every scroll.  We ignore has_focus
		-- (which reflects sick_wheel's internal focus_pos, potentially
		-- mismatched with our visual layout) and use item_index directly.
		transform = function(self, item_index, num_items, has_focus)
			if not self.container then return end
			local off = item_index - CENTER   -- -1, 0, +1 for 3-item wheel

			self.container:finishtweening():linear(0.12)

			if off == 0 then
				self.container:x(0):zoom(1.0)
				self.container:diffusealpha(1)
				if self.border then self.border:diffusealpha(0.9) end
			elseif off == -1 then
				self.container:x( -(CARD_W + CARD_GAP) ):zoom(0.85)
				self.container:diffusealpha(0.55)
				if self.border then self.border:diffusealpha(0) end
			elseif off == 1 then
				self.container:x( CARD_W + CARD_GAP ):zoom(0.85)
				self.container:diffusealpha(0.55)
				if self.border then self.border:diffusealpha(0) end
			else
				self.container:diffusealpha(0)
				if self.border then self.border:diffusealpha(0) end
			end
		end,

		-- set() receives a choice info table from OptionRows.lua Choices().
		set = function(self, info)
			if not info or not self.primary or not self.secondary then
				if self.primary then self.primary:settext("") end
				if self.secondary then self.secondary:settext("") end
				return
			end

			local role = info.role or "default"
			local base = info.color or role_color[role] or role_color.default

			if self.fill   then self.fill:diffuse(base):diffusealpha(0.9) end
			if self.border then self.border:diffuse(base) end

			if role == "chart" then
				self.primary:settext( tostring(info.meter or "") )
					:diffuse(Color.Black):zoom(0.7):y(-6)
				self.secondary:settext( (info.name or ""):upper() )
					:diffuse(Color.Black):zoom(0.75):y(16)
			else
				self.primary:settext( info.text or "" )
					:diffuse(Color.White):zoom(0.65):y(0)
				self.secondary:settext("")
			end
		end,
	}
}

return optionrow_item_mt
