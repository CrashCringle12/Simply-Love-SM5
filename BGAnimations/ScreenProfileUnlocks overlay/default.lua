local PreferredStyle = ThemePrefs.Get("PreferredStyle")
local mpn = GAMESTATE:GetMasterPlayerNumber()
local profile_data, guest_data = LoadActor("../ScreenSelectProfile underlay/PlayerProfileData.lua")

local scrollers = {}
scrollers[PLAYER_1] = setmetatable({disable_wrapping=true}, sick_wheel_mt)
scrollers[PLAYER_2] = setmetatable({disable_wrapping=true}, sick_wheel_mt)

local t = Def.ActorFrame {
    InitCommand = function(self) self:queuecommand("Stall") end,
    StallCommand = function(self)
        self:sleep(0.5):queuecommand("InitInput")
        if PREFSMAN:GetPreference("MenuTimer") then
            self:queuecommand("CheckMenuTimer")
        end
    end,
    InitInputCommand = function(self)
        SCREENMAN:GetTopScreen():AddInputCallback(LoadActor("./Input.lua", {af=self, ProfileData=profile_data, GuestData=guest_data}))
    end,

    CheckMenuTimerCommand = function(self)
        if SCREENMAN:GetTopScreen():GetChild("Timer"):GetSeconds() <= 0 then
            self:queuecommand("Off")
        else
            self:sleep(0.5):queuecommand("CheckMenuTimer")
        end
    end,

    OffCommand = function(self)
        self:sleep(0.75):queuecommand("Finish")
    end,
    FinishCommand = function(self)
        if SL.Global.UnlockMenuActive then
            SL.Global.UnlockMenuActive = false
        end
        SCREENMAN:GetTopScreen():Cancel()
    end,

    OnCommand = function(self) self:queuecommand('Update') end,

    -- sounds
    LoadActor(THEME:GetPathS("Common", "start")) .. {
        IsAction = true,
        StartButtonMessageCommand = function(self) self:play() end
    },
    LoadActor(THEME:GetPathS("ScreenSelectMusic", "select down")) .. {
        IsAction = true,
        BackButtonMessageCommand = function(self) self:play() end
    },
    LoadActor(THEME:GetPathS("ScreenSelectMaster", "change")) .. {
        IsAction = true,
        DirectionButtonMessageCommand = function(self) self:play() end
    },
}

-- get avatars
local avatars = {}
for profile in ivalues(profile_data) do
    if profile.dir and profile.displayname then
        avatars[profile.index] = GetAvatarPath(profile.dir, profile.displayname)
    end
end

-- dim background
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
        self:valign(0):horizalign(left):zoom(0.8):diffusealpha(1):xy(300, 9*SCREEN_HEIGHT/10)
    end,
}

-- Load unlock frames
if not (PreferredStyle=="single" or PreferredStyle=="double") or #GAMESTATE:GetHumanPlayers() > 1 then
    t[#t+1] = LoadActor("Unlocks.lua", {Player=PLAYER_1, ProfileData=profile_data, Avatars=avatars, GuestData=guest_data})
    t[#t+1] = LoadActor("Unlocks.lua", {Player=PLAYER_2, ProfileData=profile_data, Avatars=avatars, GuestData=guest_data})
else
    t[#t+1] = LoadActor("Unlocks.lua", {Player=GAMESTATE:GetMasterPlayerNumber(), ProfileData=profile_data, Avatars=avatars, GuestData=guest_data})
end

return t
