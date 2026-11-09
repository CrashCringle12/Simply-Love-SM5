return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self) self:FullScreen():Center():diffuse(Color.White) end,
	},
	Def.Sprite{
		Texture="./TimeChamber.png",
		InitCommand=function(self)
			self:zoom(0.5):Center():texcoordvelocity(0.01, 0):SetTextureFiltering(false)
		end,
	},
}
