-- MusicWheel/WheelItemMT.lua
--
-- Metatable for a single jacket slot in the horizontal music wheel.
-- Each slot is a sick_wheel item; the wheel keeps NUM_VISIBLE of them
-- alive at all times and calls set()/transform() as songs scroll past.
--
-- Design notes:
--   * The center slot (focus_pos) is scaled up, gets a glow border, and
--     shows the song's jacket/banner at full-quality.  Neighboring slots
--     shrink and dim with distance from center for the SMX-style filmstrip
--     look.
--   * We deliberately do NOT read the theme's song here.  All lookups go
--     through the Song object we were handed in :set() so the same MT can
--     be reused for other wheels (e.g. a preview/recent wheel) later.
--   * Image loading uses SM5.1's LoadFromCached() when available to avoid
--     hitching when scrolling through big packs.
---------------------------------------------------------------------------

local args = ...
local wheel_config = args.wheel_config  -- shared geometry values

local ITEM_W, ITEM_H = wheel_config.item_w, wheel_config.item_h

-- Scale + alpha curve based on distance from center slot.
-- Index 0 == center; 1/2/3 fall off progressively.
local scale_for_offset = { [0]=1.00, [1]=0.68, [2]=0.48, [3]=0.34 }
local alpha_for_offset = { [0]=1.00, [1]=0.85, [2]=0.55, [3]=0.30 }
local xgap_for_offset  = { [0]=0,    [1]=1.05, [2]=1.85, [3]=2.55 }  -- multiplied by ITEM_W

-- cached fallback texture used when a song has no jacket/banner/background
local NoJacketTexture = nil

local wheel_item_mt = {
	__index = {
		create_actors = function(self, name)
			self.name = name

			local af = Def.ActorFrame{
				Name = name,
				InitCommand = function(subself)
					self.container = subself
					subself:diffusealpha(0)
				end,

				-- Solid dark card behind the jacket so partially-transparent
				-- jackets read cleanly against whatever bg is behind.  Drawn
				-- BEFORE the sprite so it lands underneath naturally.
				Def.Quad{
					Name = "CardShadow",
					InitCommand = function(subself)
						self.card_shadow = subself
						subself:zoomto(ITEM_W + 6, ITEM_H + 6)
						       :diffuse(0, 0, 0, 0.55)
					end,
				},

				-- Jacket sprite -- the star of the show.
				Def.Sprite{
					Name = "Jacket",
					InitCommand = function(subself)
						self.jacket = subself
						subself:setsize(ITEM_W, ITEM_H)
					end,
				},
				Def.ActorFrame {
					InitCommand = function(subself)
						self.titleText = subself
					end,
					Def.Quad{
						InitCommand = function(subself)
							subself:zoomto(ITEM_W, 20):y(55):diffuse(Color.Black ):diffusealpha(0.65)
						end,
					},
					LoadFont("Wendy/_wendy small")..{
						InitCommand = function(subself)
							self.titleActor = subself
							subself:zoom(0.25):diffuse( color("#c6fbff") ):shadowlength(1)
								:y(55)
						end,
					},
				},

				-- "SORTS" folder card (hidden for song slots; shown only
				-- when set() receives the sorts_folder marker).  Yellow
				-- accent + list-icon glyph + label makes it visually
				-- distinct from song jackets at a glance.
				Def.ActorFrame{
					Name = "SortsCard",
					InitCommand = function(subself)
						self.sorts_card = subself
						subself:visible(false)
					end,

					-- Yellow-tinted outer accent
					Def.Quad{
						InitCommand = function(subself)
							subself:zoomto(ITEM_W, ITEM_H):diffuse( color("#ffe14a") ):diffusealpha(0.98)
						end,
					},
					-- Inner dark quad so the yellow forms a border
					Def.Quad{
						InitCommand = function(subself)
							subself:zoomto(ITEM_W - 10, ITEM_H - 10):diffuse( color("#233038") )
						end,
					},
					-- Big icon glyph (list-like symbol)
					LoadFont("Wendy/_wendy small")..{
						InitCommand = function(subself)
							subself:zoom(1.4):diffuse( color("#ffe14a") ):shadowlength(1)
								:y(-16):settext("=")
						end,
					},
					-- Label
					LoadFont("Common Normal")..{
						InitCommand = function(subself)
							subself:zoom(1.1):diffuse(Color.White):shadowlength(0.75)
								:y(20):maxwidth(ITEM_W - 14)
								:settext( THEME:GetString("ScreenSelectMusicCasual", "SortsFolderLabel") )
						end,
					},
				},
			}
			return af
		end,

		-- Called by sick_wheel every time this slot's position changes.
		-- item_index is 1-based within the visible window.  We use
		-- math.ceil(num_items/2) to place the focus item at the geometric
		-- center of the visible window; MusicWheel/default.lua overrides
		-- SongWheel.focus_pos to match, so has_focus stays truthful.
		transform = function(self, item_index, num_items, has_focus)
			local focus_pos = math.ceil(num_items / 2)
			local off       = math.abs(item_index - focus_pos)
			local direction = (item_index < focus_pos) and -1 or 1

			local scale = scale_for_offset[off] or scale_for_offset[3]
			local alpha = alpha_for_offset[off] or 0
			local xgap  = (xgap_for_offset[off] or xgap_for_offset[3]) * ITEM_W

			self.container:finishtweening():linear(0.18)
				:x(direction * xgap)
				:y(0)
				:zoom(scale)
				:diffusealpha(alpha)
			-- We shoulde hide the textActor when the jacket is in focus
			if self.titleText then
				self.titleText:visible(not has_focus)
			end
			-- Slots outside our defined offsets get clamped alpha to 0 so
			-- they don't bleed onto screen at extreme wheel positions.
			if off > 3 then self.container:diffusealpha(0) end
		end,

		-- Called by sick_wheel when this slot needs to display a new item.
		-- The item is either a Song object OR the special Sorts folder
		-- marker table (info.is_sorts_folder == true) that Setup.lua
		-- appends as the last entry of every wheel list.
		set = function(self, info)
			if not info then
				self.container:visible(false)
				return
			end
			self.container:visible(true)

			-- Sorts folder marker: hide song visuals, show sorts card.
			if type(info) == "table" and info.is_sorts_folder then
				self.song = nil
				if self.jacket      then self.jacket:visible(false) end
				if self.card_shadow then self.card_shadow:visible(false) end
				if self.sorts_card  then self.sorts_card:visible(true)  end
				if self.titleText then self.titleText:visible(false) end
				return
			end

			-- Otherwise info is a Song object.
			self.song = info
			if self.jacket      then self.jacket:visible(true) end
			if self.card_shadow then self.card_shadow:visible(true) end
			if self.sorts_card  then self.sorts_card:visible(false) end
			if self.titleText then self.titleText:visible(true) end

			local song = info

			-- Pick the best image we have available, in the same priority
			-- order the old SongMT.lua used: Jacket > Background > Banner.
			local img_type, img_path = nil, nil
			if song:HasJacket() then
				img_type = "Jacket"     ; img_path = song:GetJacketPath()
			elseif song:HasBackground() then
				img_type = "Background" ; img_path = song:GetBackgroundPath()
			elseif song:HasBanner() then
				img_type = "Banner"     ; img_path = song:GetBannerPath()
			end

			if self.titleText then
				self.titleActor:settext( song:GetDisplayMainTitle() )
			end

			if img_path then
				if Sprite.LoadFromCached ~= nil then
					self.jacket:LoadFromCached(img_type, img_path)
				else
					self.jacket:LoadBanner(img_path)
				end
			else
				if NoJacketTexture then
					self.jacket:SetTexture(NoJacketTexture)
				else
					self.jacket:Load( THEME:GetPathB("ScreenSelectMusicCasual", "overlay/img/no-jacket.png") )
					NoJacketTexture = self.jacket:GetTexture()
				end
			end

			self.jacket:scaletoclipped(ITEM_W, ITEM_H)
		end,
	}
}

return wheel_item_mt
