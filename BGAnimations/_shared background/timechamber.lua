-- THE BEST WAY TO SPREAD SCHOOL SPIRIT!

-- -----------------------------------
-- Images loaded in background, keep it PG
local path_to_tex = THEME:GetPathB("","_shared background/TimeChamber.png")

-----------------
-- Taro wrote the original version of this code, quietly-turning h*cked it up from there

-- how far offscreen should it be before it wraps
local wrap_buffer = 50

local af = Def.ActorFrame{
	InitCommand=function(self) 
		if ThemePrefs.Get("VisualStyle") == "DBZ" then
			self:visible(true) 
		else
			self:visible(false)
		end
	end,
	VisualStyleSelectedMessageCommand=function(self)
		if ThemePrefs.Get("VisualStyle") == "DBZ" then
			self:visible(true)
		else
			self:visible(false)
		end
	end
}

af[#af+1] = Def.Quad{
	InitCommand=function(self) self:FullScreen():diffuse(Color.White) end
}
-- background Quad with a black-to-blue gradient
af[#af+1] = Def.Sprite{
	Name="timeChamber",
	Texture=path_to_tex,
	InitCommand=function(self)
		self:zoom(0.5):Center()
    	 self:texcoordvelocity(0.01,0):SetTextureFiltering(false)
	end,

}



return af