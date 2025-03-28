---------------------------------------------------------------------
-- Initialize Global Variable(s)
---------------------------------------------------------------------
LoadActor("./TSH-Variables.lua")

---------------------------------------------------------------------
-- Initialize common functions that are needed all over this engine
---------------------------------------------------------------------
LoadActor("./TSH-Functions.lua")


return Def.ActorFrame{
	InitCommand=function(self)
		self:sleep(999)
	end
}