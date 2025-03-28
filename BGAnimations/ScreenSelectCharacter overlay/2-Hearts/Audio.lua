local ThemeDir = THEME:GetCurrentThemeDirectory()
local PlayingBGM = false
local BGM = nil

local ResetMusicDefaults = function()
	return {
		start = 0,
		fadeIn = 1,
		fadeOut = 1,
		loop = true,
		applyRate = true,
		alignBeat = true,
	}
end

return Def.Actor{
	Name="BGM",
	OnCommand=function(self)
		self:playcommand("Set", {BGM=TSH.EventData.BGM}):queuecommand("Play")
	end,
	SetCommand=function(self, params)
		BGM = ResetMusicDefaults()
		for key,value in pairs( params.BGM ) do
			BGM[key] = value
		end
	end,
	PlayCommand=function(self)
		if BGM then
			SOUND:PlayMusicPart(ThemeDir .. "Sounds/" .. BGM.file, BGM.start, BGM.length, BGM.fadeIn, BGM.fadeOut, BGM.loop, BGM.applyRate, BGM.alignBeat)
			PlayingBGM = true
		end
	end,
	StopCommand=function(self)
		SOUND:StopMusic()
		PlayingBGM = false
	end,
	ToggleCommand=function(self)
		if PlayingBGM then
			self:playcommand("Stop")
			SM("Audio toggled off.")
		else
			self:playcommand("Play")
			SM("Audio toggled on.")
		end
	end
}