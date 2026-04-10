-- PreferredStyle is a Simply Love ThemePref that can allow players to always
-- automatically have one of [single, double, versus] chosen for them.
-- If PreferredStyle is either "single" or "double", we don't want to load
-- SelectProfileFrames for both PLAYER_1 and PLAYER_2, but only the MasterPlayerNumber
local PreferredStyle = ThemePrefs.Get("PreferredStyle")

-- retrieve the MasterPlayerNumber now, at initialization, so that if AutoStyle is set
-- to "single" or "double" and that singular player unjoins, we still have a handle on
-- which PlayerNumber they're supposed to be...
local mpn = GAMESTATE:GetMasterPlayerNumber()

-- a table of profile data (highscore name, most recent song, mods, etc.)
-- indexed by "ProfileIndex" (provided by engine)
local profile_data, guest_data = LoadActor("../ScreenSelectProfile underlay/PlayerProfileData.lua")

local scrollers = {}
scrollers[PLAYER_1] = setmetatable({disable_wrapping=true}, sick_wheel_mt)
scrollers[PLAYER_2] = setmetatable({disable_wrapping=true}, sick_wheel_mt)

-- Updated as profiles are selected/de-selected
local readyPlayers = {
	["P1"] = false,
	["P2"] = false,
}

-- ----------------------------------------------------

local HandleStateChange = function(self, Player)
	-- local frame = self:GetChild(ToEnumShortString(Player) .. 'Frame')
	-- local joinframe = frame:GetChild('JoinFrame')

	-- local scrollerframe = frame:GetChild('ScrollerFrame')
	-- local dataframe = scrollerframe:GetChild('DataFrame')
	-- local scroller = scrollerframe:GetChild('Scroller')

	-- local seltext = frame:GetChild('SelectedProfileText')
	-- local usbsprite = frame:GetChild('USBIcon')

	-- if GAMESTATE:IsHumanPlayer(Player) then
	-- 	local selected = readyPlayers[ToEnumShortString(Player)]
	-- 	joinframe:visible(selected)
	-- 	scrollerframe:visible(not selected)
	-- 	seltext:visible(selected)

	-- 	if MEMCARDMAN:GetCardState(Player) == 'MemoryCardState_none' then
	-- 		-- using local profile
	-- 		joinframe:visible(false)
	-- 		scrollerframe:visible(true)
	-- 		seltext:visible(selected)
	-- 		usbsprite:visible(false)
	-- 	else
	-- 		-- using memorycard profile
	-- 		joinframe:visible(false)
	-- 		scrollerframe:visible(false)
	-- 		seltext:visible(true):settext(MEMCARDMAN:GetName(Player))
	-- 		usbsprite:visible(true)

	-- 		SCREENMAN:GetTopScreen():SetProfileIndex(Player, 0)
	-- 	end
	-- else
	-- 	joinframe:visible(true)
	-- 	scrollerframe:visible(false)
	-- 	seltext:visible(false)
	-- 	usbsprite:visible(false)
	-- end
end

-- ----------------------------------------------------

local invalid_count = 0

local t = Def.ActorFrame {

	InitCommand=function(self) self:queuecommand("Stall") end,
	StallCommand=function(self)
		-- FIXME: Stall for 0.5 seconds so that the Lua InputCallback doesn't get immediately added to the screen.
		-- It's otherwise possible to enter the screen with MenuLeft/MenuRight already held and firing off events,
		-- which causes the sick_wheel of profile names to not display.  I don't have time to debug it right now.
		self:sleep(0.5):queuecommand("InitInput")
        
		-- FIXME: I need to find time to look at how the engine actually handles MenuTimers because
		-- including an Actor command that queues itself every 0.5 seconds to check the MenuTimer on custom
		-- screens like this (and ScreenPlayAgain, etc.) seems like it should be unnecessary.)
		if PREFSMAN:GetPreference("MenuTimer") then
			self:queuecommand("CheckMenuTimer")
		end
	end,
	InitInputCommand=function(self) SCREENMAN:GetTopScreen():AddInputCallback( LoadActor("./Input.lua", {af=self, Scrollers=scrollers, ProfileData=profile_data, GuestData=guest_data}) ) end,


	CheckMenuTimerCommand=function(self)
		-- if the MenuTimer has reached 0, it's time to queue the OffCommand and force a transition to the next screen
		if SCREENMAN:GetTopScreen():GetChild("Timer"):GetSeconds() <= 0 then
			self:queuecommand("Off")
		else
			self:sleep(0.5):queuecommand("CheckMenuTimer")
		end
	end,

	-- the OffCommand will have been queued, when it is appropriate, from ./Input.lua
	-- sleep for 0.5 seconds to give the PlayerFrames time to tween out
	-- and queue a call to Finish() so that the engine can wrap things up
	OffCommand=function(self)
		self:sleep(0.75):queuecommand("Finish")
	end,
	FinishCommand=function(self)
		if SL.Global.AchievementMenuActive then
			SL.Global.AchievementMenuActive = false
            SL.Global.AchievementPackMenuActive = false
		end
        SCREENMAN:GetTopScreen():Cancel()
	end,
	WhatMessageCommand=function(self) self:runcommandsonleaves(function(subself) if subself.distort then subself:distort(0.5) end end):sleep(4):queuecommand("Undistort") end,
	UndistortCommand=function(self) self:runcommandsonleaves(function(subself) if subself.distort then subself:distort(0) end end) end,

	-- various events can occur that require us to reassess what we're drawing
	OnCommand=function(self) self:queuecommand('Update') end,
	StorageDevicesChangedMessageCommand=function(self) self:queuecommand('Update') end,
	PlayerJoinedMessageCommand=function(self, params) self:playcommand('Update', {player=params.Player}) end,
	PlayerUnjoinedMessageCommand=function(self, params) self:playcommand('Update', {player=params.Player}) end,
	-- there are several ways to get here, but if we're here, we'll just
	-- punt to HandleStateChange() to reassess what is being drawn
	UpdateCommand=function(self, params)
		if params and params.player then
			HandleStateChange(self, params.player)
			return
		end

		if PreferredStyle=="none" or PreferredStyle=="versus" or #GAMESTATE:GetHumanPlayers() > 1 then
			HandleStateChange(self, PLAYER_1)
			HandleStateChange(self, PLAYER_2)
		else
			HandleStateChange(self, GAMESTATE:GetMasterPlayerNumber())
		end
	end,

	-- sounds
	LoadActor( THEME:GetPathS("Common", "start") )..{
		IsAction=true,
		StartButtonMessageCommand=function(self) self:play() end
	},
	LoadActor( THEME:GetPathS("ScreenSelectMusic", "select down") )..{
		IsAction=true,
		BackButtonMessageCommand=function(self) self:play() end
	},
	LoadActor( THEME:GetPathS("ScreenSelectMaster", "change") )..{
		IsAction=true,
		DirectionButtonMessageCommand=function(self)
			self:play()
			if invalid_count then invalid_count = 0 end
		end
	},
}

-- get table of player avatar paths
local avatars = {}
for profile in ivalues(profile_data) do
	if profile.dir and profile.displayname then
		avatars[profile.index] = GetAvatarPath(profile.dir, profile.displayname)
	end
end

-- if we're fast profile switching, dim the song wheel in the background
t[#t+1] = Def.Quad {
    InitCommand = function(self)
        self:FullScreen():diffuse(Color.Black):diffusealpha(0)
        self:visible(true):smooth(0.2):diffusealpha(0.8)
    end,
    HideCommand = function(self) self:visible(false) end
}

t[#t+1] = LoadFont("_eurostile normal") .. {
    Text = "Use the Pad to Navigate!",
    InitCommand = function(self)
        self:valign(0):horizalign(left):zoom(0.8):diffusealpha(1):xy(
            300, 9*SCREEN_HEIGHT/10)
    end,
}

-- load PlayerFrames for both
if not (PreferredStyle=="single" or PreferredStyle=="double") or #GAMESTATE:GetHumanPlayers() > 1 then
    t[#t+1] = LoadActor("Achievements.lua", {Player=PLAYER_1, Scroller=scrollers[PLAYER_1], ProfileData=profile_data, Avatars=avatars, GuestData=guest_data})
    t[#t+1] = LoadActor("Achievements.lua", {Player=PLAYER_2, Scroller=scrollers[PLAYER_2], ProfileData=profile_data, Avatars=avatars, GuestData=guest_data})
    -- load only for the MasterPlayerNumber
else
    t[#t+1] = LoadActor("Achievements.lua", {Player=GAMESTATE:GetMasterPlayerNumber(), Scroller=scrollers[GAMESTATE:GetMasterPlayerNumber()], ProfileData=profile_data, Avatars=avatars, GuestData=guest_data})
end


return t
