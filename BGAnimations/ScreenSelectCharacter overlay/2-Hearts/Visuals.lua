local SongDir = GAMESTATE:GetCurrentSong():GetSongDir()
local map_texture

local af = Def.ActorFrame{
	Name="Visuals",

	Def.ActorFrameTexture{
		Name="AFT",
		OnCommand=function(self)
			self:SetDrawByZPosition(true)
			self:SetTextureName("Map")

			LoadMap(TSH.ActiveMap)

			-- get the width and height of our to-be-created texture, in pixels
			local texture = {
				w = TSH.TileData.Width.Pixels,
				h = TSH.TileData.Height.Pixels
			}

			-- since SM requires texture dimensions to be powers of 2, we need to calculate
			-- how wide and long our texture is actually going to be
			-- this WILL result in texture dimensions being "larger" than seemingly necessary
			-- but it's what SM requires
			for dimension, size in pairs(texture) do
				local p = 1
				while math.pow(2, p) < size do
					p = p + 1
				end

				texture[dimension] = math.pow(2, p)
			end

			self:SetWidth( texture.w )
			self:SetHeight( texture.h )

			-- assuming you don't need an alphabuffer, as your 'under' covers the entire screen.  --Matt
			self:Create()
			self:Draw()
			
			map_texture = self:GetTexture()

			self:GetParent():queuecommand("Load")
		end,

		-- load a "sub" layer, if available, to be used for water, lava, etc.
		Def.Sprite{
			Name="Sub",
			OnCommand=cmd(halign,0; valign,0; z, -500),
			LoadCommand=function(self)
				if FILEMAN:DoesFileExist(SongDir .. "Scenes/" .. TSH.ActiveMap .. "/sub.png") then
					self:Load( SongDir .. "Scenes/" .. TSH.ActiveMap .. "/sub.png" )
				end
			end
		},

		-- load a fog layer, if available, to be place over "sub" but under "under"
		Def.Sprite{
			Name="Sub-Fog",
			OnCommand=cmd(halign,0; valign,0; z, -500),
			LoadCommand=function(self)
				if FILEMAN:DoesFileExist(SongDir .. "Scenes/" .. TSH.ActiveMap .. "/sub-fog.png") then
					self:Load( SongDir .. "Scenes/" .. TSH.ActiveMap .. "/sub-fog.png" )
	 				self:zoomto(TSH.TileData.Width.Pixels, TSH.TileData.Height.Pixels)
					self:customtexturerect(0,0,1,1)
					self:texcoordvelocity(0.025,0.025)
					self:diffusealpha(0.05)
				end
			end
		},


		-- load the map layer that player sprites walk "on top of"
		Def.Sprite{
			Name="Under",
			OnCommand=cmd(halign,0; valign,0; z,-500),
			LoadCommand=function(self)
				self:Load( SongDir .. "Scenes/" .. TSH.ActiveMap .. "/under.png" )
			end
		},

		-- load the PLAYER_1 sprite
		LoadActor("./Character.lua", "P1")..{
			Name="P1_Sprite",
		},


		-- load the PLAYER_2 sprite
		LoadActor("./Character.lua", "P2")..{
			Name="P2_Sprite",
		},

		-- load the map layer that player sprites walk "underneath"
		-- initialize its z value to be arbitrarily high
		Def.Sprite{
			Name="Over",
			OnCommand=cmd(halign,0; valign,0, z, 1000),
			LoadCommand=function(self)
				self:Load( SongDir .. "Scenes/" .. TSH.ActiveMap .. "/over.png" )
			end
		},
	},
}


-- this is the sprite that the AFT gets rendered to
af[#af+1] = Def.Sprite{
	Name="Sprite",
	OnCommand=function(self)
		self:halign(0):valign(0)
			:diffuse(0,0,0,1)
			:zoom(480/TSH.Screen.Height.Pixels)
			:queuecommand("SetTexture")
	end,
	SetTextureCommand=function(self)
		self:SetTexture(map_texture)
	end,
	FadeInCommand=cmd(sleep,0.25; linear, 0.5; diffuse,1,1,1,1),
	FadeOutCommand=cmd(linear,0.5; diffuse,0,0,0,1),

	LoadCommand=function(self)

		-- for the sake of initializing the map, place it so both characters are visible onscreen
		local MapCenter = FindCenterOfMap()
		self:x(-(MapCenter.right * TSH.TileData.TileSize - TSH.Screen.Width.Pixels/2))
		self:y(-(MapCenter.down * TSH.TileData.TileSize - TSH.Screen.Height.Pixels/2))

		self:GetParent():queuecommand("FadeIn")
	end,
	AttemptToTweenCommand=function(self)

		self:stoptweening()

		-- if players are moving in opposing directions, don't tween the map at all
		if TSH.P1.input.Active == "Down" 	and TSH.P2.input.Active == "Up"
		or TSH.P1.input.Active == "Up" 		and TSH.P2.input.Active == "Down"
		or TSH.P1.input.Active == "Left" 	and TSH.P2.input.Active == "Right"
		or TSH.P1.input.Active == "Right" 	and TSH.P2.input.Active == "Left" then
			return
		else

			self:linear(TSH.SleepDuration)
			local MapCenter = FindCenterOfMap()

			-- update the map's xy position
			self:x(-(MapCenter.right * TSH.TileData.TileSize - TSH.Screen.Width.Pixels/2))
			self:y(-(MapCenter.down * TSH.TileData.TileSize - TSH.Screen.Height.Pixels/2))
		end
	end
}

return af