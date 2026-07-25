-- OptionRowMT.lua
--
-- One container per row (Chart, Speed, Exit) in the per-player modal.
-- Renders only the row-header text ("SELECT YOUR DIFFICULTY", etc.);
-- the actual choice cards are drawn by a sibling OptionRowItemMT wheel
-- composed by default.lua.
--
-- Visibility is controlled by ancestor ActorFrames in default.lua (the
-- shared "Modal" AF for open/close, and per-player AFs for late-join),
-- so this container just needs to render its header cleanly and
-- brighten / dim on GainFocus / LoseFocus.
--
-- Vertical layout (relative to OptionsWheel[pn] container origin):
--   row 1 header  y = -132   Chart
--   row 2 header  y = -32    Speed
--   row 3 header  y =  76    Exit  (blank; StartButton handles visuals)
---------------------------------------------------------------------------
local ROW_HEADER_Y = { [1] = -152, [2] = -32, [3] = 76 }
local GlobalOffsetSeconds = PREFSMAN:GetPreference("GlobalOffsetSeconds")

local optionrow_mt = {
	__index = {
		create_actors = function(self, name)
			self.name = name
			-- Legacy naming convention: sick_wheel names items "item1",
			-- "item2", ... .  Parse the trailing number to look up this
			-- row's fixed y offset within the panel.
			local item_index = tonumber( (name:gsub("item", "")) ) or 1
			self.index = item_index

			return Def.ActorFrame{
				Name = name,
				InitCommand = function(subself)
					self.container = subself
					subself:y( ROW_HEADER_Y[item_index] or 0 )
				end,

				GainFocusCommand = function(subself)
					local h = subself:GetChild("Header")
					if h then h:stoptweening():linear(0.1):diffusealpha(1.0):diffuse(GetCurrentColor()) end
				end,
				LoseFocusCommand = function(subself)
					local h = subself:GetChild("Header")
					if h then h:stoptweening():linear(0.1):diffuse(Color.White):diffusealpha(0.45) end
				end,

				-- Row header label
				LoadFont("Common Normal")..{
					Name = "Header",
					InitCommand = function(subself)
						self.header = subself
						subself:zoom(0.85):diffuse(Color.White):diffusealpha(0.45)
							:shadowlength(0.75)
					end,
				},
                Def.Sprite {
                    Texture = "arrow.png",
                    InitCommand = function(subself)
                        self.arrow = subself
                        subself:zoom(0.5):diffuse(Color.White):diffusealpha(0.45)
                            :shadowlength(0.75)
                            :x(-85)
                        	subself:bounce():effectclock("beatnooffset")
                            subself:effectmagnitude(-3,0,0)
                            subself:effectperiod(1):effectoffset( -10 * GlobalOffsetSeconds)
                    end,
                }
			}
		end,

		-- sick_wheel forwards focus changes here.  Rows don't move; we
		-- only forward has_focus so the header can brighten or dim.
		transform = function(self, item_index, num_items, has_focus)
			if not self.container then return end
			self.container:finishtweening()
			if has_focus then
				self.container:playcommand("GainFocus")
                if self.index < 3 then
                    self.arrow:stoptweening():visible(true)
                end
			else
				self.container:playcommand("LoseFocus")
                self.arrow:stoptweening():visible(false)
			end
		end,

		-- set() receives the OptionRow definition table (Chart / Speed /
		-- Exit).  Copy its HelpText into the header, and hide the header
		-- entirely if the row is helptext-less (Exit).
		set = function(self, optionrow)
			if not optionrow or not self.header then return end
			local ht = optionrow.HelpText or ""
			self.header:settext(ht):visible(ht ~= "")
		end,
	}
}

return optionrow_mt
