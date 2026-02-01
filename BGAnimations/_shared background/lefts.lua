-- All we were left with

local path_to_tex = THEME:GetPathB("","_shared background/leftsbg.png")


local swing_time = 0

local Update = function(self, delta)
	swing_time = swing_time + delta

	local swing = math.sin(swing_time * 0.6) * 18
	self:GetChild("SpotlightLeft"):rotationz(-12 + swing)
	self:GetChild("SpotlightRight"):rotationz(12 - swing)
end

local af = Def.ActorFrame{
	InitCommand=function(self) 
		if ThemePrefs.Get("VisualStyle") == "Lefts" then
			self:SetUpdateFunction( Update )
			self:visible(true) 
		else
			self:visible(false)
		end
	end,
	VisualStyleSelectedMessageCommand=function(self)
		if ThemePrefs.Get("VisualStyle") == "Lefts" then
			self:visible(true)
		else
			self:visible(false)
		end
	end
}

af[#af+1] = Def.Sprite{
	Name="leftsbg",
	Texture="leftsbg.png",
	InitCommand=function(self)
		self:zoom(0.5):Center()
	end,
}
af[#af+1] = Def.Quad{
	Name="StageDim",
	InitCommand=function(self)
		self
			:FullScreen()
			:blend(Blend.Multiply)
			:diffuse(0.55, 0.55, 0.55, 1)
	end
}

local function SpotlightSlice(name, width, alpha)
	return Def.Quad{
		Name=name,
		InitCommand=function(self)
			self
				:valign(0)
				:zoomto(width, SCREEN_HEIGHT * 1.2)
				:blend(Blend.Add)
				:diffuse(1, 0.95, 0.8, alpha)
				:diffusebottomedge(1, 0.95, 0.8, 0)
				:diffusetopedge(1,0.95,0.8,alpha * 0.8)
				:x(math.random(-2,2))
		end
	}
end

af[#af+1] = Def.ActorFrame{
	Name="SpotlightLeft",
	InitCommand=function(self)
		self
			:x(SCREEN_LEFT)
			:y(-SCREEN_HEIGHT * 0.2)
			:halign(0)
			:valign(0)
			:rotationz(-12)
	end,

	SpotlightSlice("Wide",   300, 0.18),
	SpotlightSlice("Mid",    220, 0.24),
	SpotlightSlice("Narrow", 140, 0.30),
}

af[#af+1] = Def.ActorFrame{
	Name="SpotlightRight",
	InitCommand=function(self)
		self
			:x(SCREEN_RIGHT)
			:y(-SCREEN_HEIGHT * 0.2)
			:halign(1)
			:valign(0)
			:rotationz(12)
	end,

	SpotlightSlice("Wide",   300, 0.18),
	SpotlightSlice("Mid",    220, 0.24),
	SpotlightSlice("Narrow", 140, 0.30),
}

af[#af+1] = Def.Sprite{
	Name="LeftCurtain",
	Texture="curtain.jpg",
	InitCommand=function(self)
		self
			:halign(0)
			:valign(0)
			:xy(SCREEN_LEFT, SCREEN_TOP)
			:zoomto(SCREEN_WIDTH/2, SCREEN_HEIGHT)
	end,
	OnCommand=function(self)
		self:smooth(2.5)
			:x(SCREEN_LEFT - SCREEN_WIDTH/2)
	end
}

af[#af+1] = Def.Sprite{
	Name="RightCurtain",
	Texture="curtain.jpg",
	InitCommand=function(self)
		self
			:halign(1)
			:valign(0)
			:xy(SCREEN_RIGHT, SCREEN_TOP)
			:zoomto(SCREEN_WIDTH/2, SCREEN_HEIGHT)
	end,
	OnCommand=function(self)
		self:smooth(2.5)
			:x(SCREEN_RIGHT + SCREEN_WIDTH/2)
	end
}
return af