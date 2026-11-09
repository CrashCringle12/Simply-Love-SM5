local num_particles = 20
local min_size = 30
local max_size = 150
local min_vx = 30
local max_vx = 90
local min_vy = -1
local max_vy = 1
local min_trans = 5
local max_trans = 9
local path_to_texture = "./arrowcloud.png"

-- Adapted from Taro and quietly-turning's particle background.

local wrap_buffer = 50

local particles = {}

local Update = function(self, delta)

	for i=1,#particles do
		local a = particles[i]

		if a then
			local b = a.actor
			if b then
				if b:getaux() < 1 then
					b:aux( b:getaux() + delta )
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
	InitCommand=function(self) self:SetUpdateFunction(Update) end,
}

af[#af+1] = Def.Sprite{
	Name="rightsbg",
	Texture="./rightsbg.png",
	InitCommand=function(self)
		self:zoom(0.5):Center()
	end,

}
for i=1,num_particles do
	af[#af+1] = Def.Sprite{
		Texture=path_to_texture,
		InitCommand=function(self)

			local _t = {
				actor = self,
				xspd = math.random( min_vx, max_vx ),
				yspd = math.random( min_vy, max_vy ),
				size = math.random( min_size,max_size)+(i/num_particles),
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
