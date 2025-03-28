
local pn = ...
local SongDir = GAMESTATE:GetCurrentSong():GetSongDir()

----------------------------------------------------------------------------

local frames = {
	Down = {
		{ Frame=0,	Delay=TSH.SleepDuration},
		{ Frame=1,	Delay=TSH.SleepDuration},
		{ Frame=2,	Delay=TSH.SleepDuration},
		{ Frame=3,	Delay=TSH.SleepDuration}
	},
	Left = {
		{ Frame=4,	Delay=TSH.SleepDuration},
		{ Frame=5,	Delay=TSH.SleepDuration},
		{ Frame=6,	Delay=TSH.SleepDuration},
		{ Frame=7,	Delay=TSH.SleepDuration}
	},
	Right = {
		{ Frame=8,	Delay=TSH.SleepDuration},
		{ Frame=9,	Delay=TSH.SleepDuration},
		{ Frame=10,	Delay=TSH.SleepDuration},
		{ Frame=11,	Delay=TSH.SleepDuration}
	},
	Up = {
		{ Frame=12,	Delay=TSH.SleepDuration},
		{ Frame=13,	Delay=TSH.SleepDuration},
		{ Frame=14,	Delay=TSH.SleepDuration},
		{ Frame=15,	Delay=TSH.SleepDuration}
	}
}

local WillCollide = function()
	local r = false
	local NextTile

	if TSH[pn].dir == "Up" then
		NextTile = (TSH[pn].pos.d-1) * TSH.TileData.Width.Tiles + TSH[pn].pos.r + 1

	elseif TSH[pn].dir == "Down" then
		NextTile = (TSH[pn].pos.d+1) * TSH.TileData.Width.Tiles + TSH[pn].pos.r + 1

	elseif TSH[pn].dir == "Left" then
		NextTile = TSH[pn].pos.d * TSH.TileData.Width.Tiles + TSH[pn].pos.r

	elseif TSH[pn].dir == "Right" then
		NextTile = TSH[pn].pos.d * TSH.TileData.Width.Tiles + TSH[pn].pos.r + 2
	end

	if NextTile then
		if TSH.TileData.CollisionTiles[ NextTile ] == 1 then
			r = true
		elseif TSH.TileData.EventTiles[ NextTile ] ~= 0 then
			r = EventHandler( NextTile, pn )
		end
	end

	return r
end

local WillBeOffMap = function()
	local r = true

	if TSH[pn].dir == "Up" then
		r = TSH[pn].pos.d > 0
	elseif TSH[pn].dir == "Down" then
		r = TSH[pn].pos.d < TSH.TileData.Height.Tiles-1
	elseif TSH[pn].dir == "Left" then
		r = TSH[pn].pos.r > 0
	elseif TSH[pn].dir == "Right" then
		r = TSH[pn].pos.r < TSH.TileData.Width.Tiles-1
	end

	return not r
end

local UpdatePosition = function()

	-- set the sprite's current tile to not collidable
	-- we are probably about to update the position
	TSH.TileData.CollisionTiles[TSH[pn].pos.d * TSH.TileData.Width.Tiles + TSH[pn].pos.r + 1] = 0

	-- The general idea here is to increment/decrement the value as needed first,
	-- then calculate their distance (still, before tweening actually occurs)
	-- and then undo the increment/decrement if it would put the player off screen

	if TSH[pn].dir == "Up" then
		TSH[pn].pos.d = TSH[pn].pos.d - 1
		if Distance("d") > TSH.Screen.Height.Tiles then
			TSH[pn].pos.d = TSH[pn].pos.d + 1
		end

	elseif TSH[pn].dir == "Down" then
		TSH[pn].pos.d = TSH[pn].pos.d + 1
		if Distance("d") > TSH.Screen.Height.Tiles then
			TSH[pn].pos.d = TSH[pn].pos.d - 1
		end

	elseif TSH[pn].dir == "Left" then
		TSH[pn].pos.r = TSH[pn].pos.r - 1
		if Distance("r") > TSH.Screen.Width.Tiles then
			TSH[pn].pos.r = TSH[pn].pos.r + 1
		end

	elseif TSH[pn].dir == "Right" then
		TSH[pn].pos.r = TSH[pn].pos.r + 1
		if Distance("r") > TSH.Screen.Width.Tiles then
			TSH[pn].pos.r = TSH[pn].pos.r - 1
		end
	end

	-- update this sprite's z value based on its down value
	TSH[pn].pos.z = TSH.TileData.Height.Tiles - TSH[pn].pos.d

	-- set the current tile to collidable
	TSH.TileData.CollisionTiles[TSH[pn].pos.d * TSH.TileData.Width.Tiles + TSH[pn].pos.r + 1] = 1
end

----------------------------------------------------------------------------

return Def.Sprite{

	OnCommand=function(self)
		self:Load( SongDir .. "Sprites/" .. TSH[pn].file .. " 4x4.png" )
	end,
	LoadCommand=function(self)
		self:animate(0)

		-- align to left and v-middle
		self:halign(0)
		self:valign(0.5)

		-- initialize the position
		self:x( TSH[pn].pos.r * TSH.TileData.TileSize )
		self:y( TSH[pn].pos.d * TSH.TileData.TileSize )
		self:z( -(TSH.TileData.Height.Tiles - TSH[pn].pos.d) )
		-- initialize the sprite state
		self:SetStateProperties( frames[TSH[pn].dir] )

		-- mark the MapData where the player is standing as collidable
		TSH.TileData.CollisionTiles[TSH[pn].pos.d * TSH.TileData.Width.Tiles + TSH[pn].pos.r + 1] = 1
	end,
	UpdateSpriteFramesCommand=function(self)
		self:SetStateProperties( frames[TSH[pn].dir] )
	end,
	AnimationOnCommand=cmd(animate,1),
	AnimationOffCommand=cmd(animate, 0; setstate, 0),
	TweenCommand=function(self)

		-- this does a good job of mitigating tween overflows resulting from button mashing
		self:stoptweening()

		-- sanity check
		if TSH[pn].dir and TSH[pn].input[ TSH[pn].dir ] then

			self:linear(TSH.SleepDuration)
			self:x(TSH[pn].pos.r * TSH.TileData.TileSize)
			self:y(TSH[pn].pos.d * TSH.TileData.TileSize)
			self:z( -TSH[pn].pos.z )
		end
	end,

	AttemptToTweenCommand=function(self, params)

		self:playcommand("AnimationOn")

		-- Does the player sprite's current direction match the direction
		-- we were just passed from the input handler?
		if TSH[pn].dir ~= params.dir then

			-- if not, update it
			TSH[pn].dir = params.dir
			-- and update the sprite's frames appropriately
			self:playcommand("UpdateSpriteFrames")
		end

		-- collision check the impending tile
		if not TSH.Collisions or not WillCollide() then

			-- don't allow us to go off the map
			if not WillBeOffMap() then

				-- we *probably* want to update the player's map position
				-- UpdatePosition() does just that, if we should
				UpdatePosition()

				-- tween the player sprite
				self:playcommand("Tween")
			end
		end
	end
}