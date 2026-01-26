local transitioning_out = false

local Update = function(self, dt)
	if not transitioning_out then
		SL.Global.MenuTimer.ScreenSelectMusic = SCREENMAN:GetTopScreen():GetChild("Timer"):GetSeconds()
		local topscreen = SCREENMAN:GetTopScreen():GetName()
		if topscreen == "ScreenSelectMusic" then
			SL.Global.WheelLocked = SCREENMAN:GetTopScreen():GetMusicWheel():IsLocked()
		end
	end
end

local UpdateLockStatus = function(self, dt)
	if not transitioning_out then
		local topscreen = SCREENMAN:GetTopScreen():GetName()
		if topscreen == "ScreenSelectMusic" then
			SL.Global.WheelLocked = SCREENMAN:GetTopScreen():GetMusicWheel():IsLocked()
		end
	end
end

return Def.ActorFrame{
	InitCommand=function(self)
		-- if the MenuTimer is being used, save the current number of seconds remaining
		-- before transitioning to the next screen.  In this manner, we can reinstate this
		-- value if the player opts to return to ScreenSelectMusic from ScreenPlayerOptions.
		if PREFSMAN:GetPreference("MenuTimer") then
			self:SetUpdateFunction(Update)
		else
			self:SetUpdateFunction(UpdateLockStatus)
		end
	end,
	ViewGalleryCommand=function(self)
		transitioning_out = true
	end,
	ShowPressStartForOptionsCommand=function(self)
		transitioning_out = true
	end
}