---------------------------------------------------------------------
-- Initialize generalized Event Handling function(s)
---------------------------------------------------------------------
LoadActor("EventHandler.lua")

---------------------------------------------------------------------
-- Primary ActorFrame and children
---------------------------------------------------------------------
local t = Def.ActorFrame{
	OnCommand=function(self)
		self:xy(0,0)
		
		-- queue the next command so that we can actually GetTopScreen()
		self:queuecommand("Capture"):sleep(9999)
	end,
	CaptureCommand=function(self)
		-- attach our InputHandler to the TopScreen and pass it this ActorFrame
		-- so we can manipulate stuff more easily from there
		SCREENMAN:GetTopScreen():AddInputCallback( LoadActor("InputHandler.lua", self) )
	end,
}

t[#t+1] = LoadActor("Visuals.lua")
-- t[#t+1] = LoadActor("Audio.lua")

---------------------------------------------------------------------
return t