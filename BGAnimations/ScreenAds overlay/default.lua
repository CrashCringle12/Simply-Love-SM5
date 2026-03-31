InputHandler = function(event)	
	if event.type == 'InputEventType_FirstPress' and event.button == 'Start' and count == -1 then 		
		SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
	end	
end

local WideScale = function(AR4_3, AR16_9)
	-- return scale( SCREEN_WIDTH, 640, 854, AR4_3, AR16_9 )
	local w = 480 * PREFSMAN:GetPreference("DisplayAspectRatio")
	return scale( w, 640, 854, AR4_3, AR16_9 )
 end
 
local adChoice = math.random(1, 27)
d = Enum.Reverse(Difficulty)
count = 10
nice = {}

local function game_init()
	TimeAtInit = GetTimeSinceStart()
	nice.vid:queuecommand('Update')
	nice.box:queuecommand('Update')
	nice.count:queuecommand('Count')
	nice.preview:queuecommand('Update')
	counter = 2
end

local function game_update(self, delta)
	if counter == 2 then
		SOUND:StopMusic()
		if GetTimeSinceStart() - TimeAtInit > 31 then
		end
	end
end

actor = Def.ActorFrame{
	OnCommand=function(self)
		game_init()
		self:SetUpdateFunction(game_update)
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
	end,

	Def.Quad{
		Name="#YOLO",
		InitCommand=function(self)
			self:sleep(420)
		end
	},
	Def.Sprite{
    	Texture=THEME:GetPathB("ScreenAds", "overlay/Ads/"..SL.AprilFools.Ads[adChoice]),
    	InitCommand=function(self)
			local src_w = self:GetTexture():GetSourceWidth()
			self:Center():zoom(_screen.w/WideScale(src_w*0.75,src_w))
			self:loop(false):diffusealpha(1)
			nice.vid = self
    	end,
		UpdateCommand=function(self)
			self:diffusealpha(1)
		end
	}
}	
actor[#actor+1] = Def.Sound{
	--replace the .mp4 with .ogg and it should work
	File=THEME:GetPathB("ScreenAds", "overlay/Ads/"..SL.AprilFools.Ads[adChoice]:gsub(".mp4", ".ogg")),
	OnCommand=function(self) self:play() end
}

actor[#actor+1] = Def.Quad{
	InitCommand=function(self)
		self:horizalign('HorizAlign_Right'):zoomto(168,72):x(_screen.w):y(350):diffuse(Color.Black):diffusealpha(0)
		nice.box = self
	end,
	UpdateCommand=function(self)
		self:diffusealpha(0.7)
	end}	
	
actor[#actor+1] = Def.Sprite{
    	Texture="preview.jpg",
    	InitCommand=function(self)
        	self:horizalign('HorizAlign_Right'):zoom(0.4):x(_screen.w):y(350):diffusealpha(0)
			nice.preview = self
    	end,
		UpdateCommand=function(self)
			self:diffusealpha(1)
		end,
		OffCommand=function(self)
			self:diffusealpha(0)
		end
	}

actor[#actor+1] = Def.BitmapText{
    File="./_leroyletteringlightbeta01 20px.ini",	
    InitCommand=function(self)
		TimeAtInit = GetTimeSinceStart()	
   		self:horizalign('HorizAlign_Right'):x(_screen.w):y(350):settext(count..'                        '):diffusealpha(0)
   		nice.count = self
	end,
	CountCommand=function(self)	
		if count == 0 then
			nice.preview:queuecommand('Off')
			self:settext('Skip Ad &START;     ')
		else			
			self:diffusealpha(1):settext(count..'                        '):sleep(1.2):queuecommand("Count")
		end		
		count = count - 1
   	end
}

return actor