local video = ("./Hd%d.mp4"):format(276 + math.random(4))

return Def.ActorFrame{
	InitCommand=function(self) self:diffusealpha(0) end,
	OnCommand=function(self) self:fov(90):accelerate(0.8):diffusealpha(1) end,
	LoadActor(video)..{
		InitCommand=function(self)
			self:zoom(_screen.h / 1080):Center()
		end,
	},
	Def.Quad{
		InitCommand=function(self)
			self:FullScreen():Center():diffuse(0, 0, 0, 0.4):playcommand("UpdateVisible")
		end,
		ScreenChangedMessageCommand=function(self) self:playcommand("UpdateVisible") end,
		UpdateVisibleCommand=function(self)
			local screen = SCREENMAN:GetTopScreen()
			self:visible(not screen or screen:GetName() ~= "ScreenTitleMenu")
		end,
	},
}
