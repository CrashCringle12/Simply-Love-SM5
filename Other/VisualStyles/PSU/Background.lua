local num_particles = 60
local min_size = 8
local max_size = 20
local min_vx = -8
local max_vx = 8
local min_vy = 30
local max_vy = 90
local path_to_texture = "./paw1.png"

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
					b:diffusealpha( b:getaux() )
				end

				b:addx( a.xspd*delta )
				b:addy( a.yspd*delta )

				if b:GetY() > (_screen.h + wrap_buffer) then
					b:y( (-wrap_buffer*2) )
				end
				if b:GetX() < 0 then
					b:x( math.random( -40, math.floor(_screen.w)+40 )  )
				end
			end
		end
	end
end

local af = Def.ActorFrame{
	InitCommand=function(self) self:SetUpdateFunction(Update) end,
}

af[#af+1] = Def.Sprite{
	Name="oldmain",
	Texture="./oldmain.png",
	InitCommand=function(self)
		self:zoom(0.29):Center()
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

			self:diffusealpha(0)
			self:x( math.random( -40, math.floor(_screen.w)+40 ) )
			self:y( math.random( -40, math.floor(_screen.h)+40 ) )
			self:zoomto( _t.size, _t.size )

		end
	}
end

return af
