-- THE BEST WAY TO SPREAD SCHOOL SPIRIT!

-- -----------------------------------
-- variables you might want to configure to your liking

local num_particles = 20
-- particle size in pixels
local min_size = 30
local max_size = 150
-- particle velocity in pixels per second
local min_vx = 30
local max_vx = 90
local min_vy = -1
local max_vy = 1
local min_trans = 5
local max_trans = 9
-- Images loaded in background, keep it PG
local path_to_texture = THEME:GetPathB("","_shared background/arrowcloud.png")
local path_to_tex = THEME:GetPathB("","_shared background/rightsbg.png")

-----------------
-- Taro wrote the original version of this code, quietly-turning h*cked it up from there

-- how far offscreen should it be before it wraps
local wrap_buffer = 50

-- we will need these later
local particles = {}

local Update = function(self, delta)

	for i=1,#particles do
		local a = particles[i]

		if a then
			local b = a.actor
			if b then
				-- each sprite will have an aux of 0 by default
				if b:getaux() < 1 then
					-- increment this sprite's aux by delta (presumably some small value)
					b:aux( b:getaux() + delta )
					-- and use the result to increase this sprite's alpha until it is 1
					-- b:diffusealpha( b:getaux())
				end

				b:addx( a.xspd*delta )
				b:addy( a.yspd*delta )

				if b:GetX() > (_screen.w + wrap_buffer) then
					b:x( (-wrap_buffer*2) )
					b:y(math.random( 0, _screen.h /2 ))
				end
				if b:GetY() < 0 - wrap_buffer then
					b:x( (-wrap_buffer*2) )
					b:y(math.random( 0, _screen.h /2 ))
				end
			end
		end
	end
end

local af = Def.ActorFrame{
	InitCommand=function(self) 
		if ThemePrefs.Get("VisualStyle") == "Rights" then
			self:SetUpdateFunction( Update )
			self:visible(true) 
		else
			self:visible(false)
		end
	end,
	VisualStyleSelectedMessageCommand=function(self)
		if ThemePrefs.Get("VisualStyle") == "Rights" then
			self:visible(true)
		else
			self:visible(false)
		end
	end
}

-- background Quad with a black-to-blue gradient
af[#af+1] = Def.Sprite{
	Name="rightsbg",
	Texture="rightsbg.png",
	InitCommand=function(self)
		self:zoom(0.5):Center()
	end,

}
for i=1,num_particles do
	af[#af+1] = Def.Sprite{
		Texture=path_to_texture,
		InitCommand=function(self)

			-- initialize this particle's x-speed, y-speed, and size now
			-- store this in the particles tables for retrieval within Update()
			local _t = {
				actor = self,
				xspd = math.random( min_vx, max_vx ),
				yspd = math.random( min_vy, max_vy ),
				size = math.random( min_size,max_size)+(i/#particles),
			}

			table.insert( particles, _t )

			self:diffusealpha((math.random(min_trans, max_trans) /10))
			self:x( math.random( -40, math.floor(_screen.w)+40 ) )
			self:y( math.random( 0, _screen.h /2 ) )
			self:zoomto( _t.size, _t.size )

		end
	}
end


return af