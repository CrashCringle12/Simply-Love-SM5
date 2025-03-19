local args = ...
local player = args.Player
local profile_data = args.ProfileData
local guest_data = args.GuestData
local avatars = args.Avatars
local DateFormat = "%04d/%02d/%02d %02d:%02d"

local counter = 0;

-- -----------------------------------------------------------------------
-- TODO: start over from scratch so that these numbers make sense in SL
--       as-is, they are half-leftover from editing _fallback's code

local frame = {w = 225, h = 368, border = 6}

local row_height = 35

local info = {
    y = frame.h * -0.5,
    w = frame.w * 0.475,
    x = frame.w * 0.475,
    padding = 4
}

local CountUnlockedAchievements = function(achievements)
    local count = 0
    for i, achievement in ipairs(achievements) do
        if achievement.Unlocked then count = count + 1 end
    end
    return count
end

local accolades = SL.Accolades.Achievements
local binfo = {
    -- 35 * -5
    y = row_height * -5,
    w = frame.w * 1,
    h = frame.h * 0.1,
    x = frame.w * -0.56,
    padding = 1.8,
    pages = 3,
    rows = 3,
    cols = 8,
    player = player,
    achievements = accolades
}
local arb = 10
local avatar_dim = 85

-- account for the possibility that there are no local profiles and
-- we want "[ Guest ]" to start in the middle, with focus
if PROFILEMAN:GetNumLocalProfiles() <= 0 then scroller.y = row_height * -4 end
-- -----------------------------------------------------------------------

local initial_data = guest_data
local pos = nil
-- If we're fast profile switching, we want to open the profile scrollers
-- focused on current player profiles. Let's remember the index of the profile
-- so that we can scroll to it.
for profile in ivalues(profile_data) do
    if profile.guid == PROFILEMAN:GetProfile(player):GetGUID() then
        SM(PROFILEMAN:GetProfile(player):GetDisplayName())
        pos = profile.index
        break
    end
end

-- If we haven't found a matching profile looking in profile_data, this has to
-- be [GUEST]
pos = pos or 0

initial_data = pos == 0 and guest_data or profile_data[pos]

local count = 0

local badges = LoadActor("Badges.lua", binfo)

local FrameBackground2 = function(pad, c, player, w, h)
    w = w or frame.w
    -- scroller.w = w - info.w

    return Def.ActorFrame {
        OnCommand = function(self)
            self:runcommandsonleaves(function(leaf)
                leaf:smooth(0.3):cropbottom(0)
            end)
            self:x(pad):y(60)
        end,
        OffCommand = function(self)
            if not GAMESTATE:IsSideJoined(player) then
                self:runcommandsonleaves(function(leaf)
                    leaf:accelerate(0.25):cropbottom(1)
                end)
            end
        end,

        -- -- top mask to hide scroller text
        -- Def.Quad{
        -- 	InitCommand=function(self) self:horizalign(left):vertalign(bottom):setsize(540,50):xy(-self:GetWidth()/2, -107):MaskSource() end
        -- },
        -- bottom mask to hide scroller text
        Def.Quad {
            InitCommand = function(self)
                self:horizalign(left):vertalign(top):setsize(540, 120):xy(
                    -self:GetWidth() / 2, 100):MaskSource()
            end
        },

        -- border
        Def.Quad {
            InitCommand = function(self)
                self:cropbottom(1):zoomto(w + frame.border, h + frame.border)
                if ThemePrefs.Get("RainbowMode") then
                    self:diffuse(Color.Black)
                end
            end
        },
        -- colored bg
        Def.Quad {
            InitCommand = function(self)
                self:cropbottom(1):zoomto(w, h):diffuse(c):diffusetopedge(
                    LightenColor(c))
            end
        }
    }
end

local FrameBackground3 = function(pad, c, player, w, h)
    w = w or frame.w
    -- scroller.w = w - info.w

    return Def.ActorFrame {
        OnCommand = function(self)
            self:runcommandsonleaves(function(leaf)
                leaf:smooth(0.3):cropbottom(0)
            end)
            self:x(pad):y(-108)
        end,
        OffCommand = function(self)
            if not GAMESTATE:IsSideJoined(player) then
                self:runcommandsonleaves(function(leaf)
                    leaf:accelerate(0.25):cropbottom(1)
                end)
            end
        end,

        -- -- top mask to hide scroller text
        -- Def.Quad{
        -- 	InitCommand=function(self) self:horizalign(left):vertalign(bottom):setsize(540,50):xy(-self:GetWidth()/2, -107):MaskSource() end
        -- },
        -- bottom mask to hide scroller text
        Def.Quad {
            InitCommand = function(self)
                self:horizalign(left):vertalign(top):setsize(540, 120):xy(
                    -self:GetWidth() / 2, 100):MaskSource()
            end
        },

        -- border
        Def.Quad {
            InitCommand = function(self)
                self:cropbottom(1):zoomto(w + frame.border, h + frame.border)
                if ThemePrefs.Get("RainbowMode") then
                    self:diffuse(Color.Black)
                end
            end
        },
        -- colored bg
        Def.Quad {
            InitCommand = function(self)
                self:cropbottom(1):zoomto(w, h):diffuse(c):diffusetopedge(
                    LightenColor(c))
            end
        }
    }
end

-- -----------------------------------------------------------------------

return Def.ActorFrame {
    Name = "AchievementFrame",
    InitCommand = function(self)
        if counter >= binfo.pages then
            counter = 0;
        else
            counter = counter + 1;
        end
        MESSAGEMAN:Broadcast("Page",
                             {Player = player, Page = counter})
    end,
    SetCommand = function(self, params)
        -- local test = params
        -- test.achievements = {}
        -- SM(params)
        MESSAGEMAN:Broadcast("Migrato", {
            Player = player,
            achievementIndex = params.achievementIndex,
            achievements = params.achievements,
            activePack = params.activePack,
            Page = params.Page
        })
    end,

    Def.ActorFrame {
        InitCommand = function(self)
            self:xy(_screen.cx, _screen.cy + 10):zoom(0):diffusealpha(0)
            self:visible(true):smooth(0.3):diffusealpha(1):zoom(1)
        end,
        HideCommand = function(self) 
            self:smooth(0.3):diffusealpha(0):zoom(0)
        end,
        FrameBackground3(0, color("#575867"), player, frame.w * 3.2,
                         frame.h * 0.3),
        FrameBackground2(0, color("#f5f5f5"), player, frame.w * 3.2,
                         frame.h * 0.59),
        LoadFont("Common Normal") .. {
            Text = "Accolades",
            InitCommand = function(self)
                self:valign(0):horizalign(left):zoom(1):diffusealpha(0.9):xy(
                    -330, -190):diffuse(color("#FFFFFF"))
            end,
            SetCommand = function(self, params)
                if params == nil then
                    self:settext("Accolades")
                else
                    self:settext("Accolades")
                end
            end
        },
        LoadFont("Common Header") .. {
            Text = "Cabby's Achievements",
            InitCommand = function(self)
                self:valign(0):horizalign(left):zoom(0.4):diffusealpha(0.9):xy(
                    -332, -148):diffuse(color("#FFFFFF"))
            end,
            SetCommand = function(self, params)
                if params == nil then
                    self:settext("Achievements")
                else
                    self:settext(params.displayname .. "'s Achievements")
                end
            end
        },
        LoadFont("Wendy/_wendy small") .. {
            Text = "Got Milk?",
            InitCommand = function(self)
                self:valign(0):horizalign(left):zoom(0.3):diffusealpha(0.9):xy(
                    -330, -120):diffuse(color("#c7cbd9"))
            end,
            SetCommand = function(self, params)
                if params == nil then
                    -- SM(params)
                    self:settext(params.displayname)
                else
                    if accolades[params.activePack][params.achievementIndex] then
                        self:settext(
                            accolades[params.activePack][params.achievementIndex]
                                .Name)
                    else
                        self:settext("N/A")
                    end
                end
            end
        },
        LoadFont("Common Normal") .. {
            Text = "Pass I'll Make a Man Out of You on Expert difficulty or higher",
            InitCommand = function(self)
                self:valign(0):horizalign(left):zoom(1):diffusealpha(0.9):xy(
                    -330, -100):diffuse(color("#c7cbd9"))
            end,
            SetCommand = function(self, params)
                if params == nil then
                    --	SM(params)
                    self:settext(params.displayname)
                else
                    if accolades[params.activePack][params.achievementIndex] then
                        self:settext(
                            accolades[params.activePack][params.achievementIndex]
                                .Desc)
                    else
                        self:settext("N/A")
                    end
                end
            end
        },
        LoadFont("Wendy/_wendy small") .. {
            Text = "04/24/2023",
            InitCommand = function(self)
                self:valign(0):horizalign(right):zoom(0.25):diffusealpha(0.9)
                    :xy(350, -115):diffuse(color("#FFFFFF"))
            end,
            SetCommand = function(self, params)
                if params == nil or not params.achievements or
                    not params.achievements[params.activePack] or
                    not params.achievements[params.activePack][params.achievementIndex] then
                    -- SM(params)
                    self:settext(params.displayname)
                else
                    if params.achievements[params.activePack][params.achievementIndex]
                        .Date then
                        self:settext(
                            params.achievements[params.activePack][params.achievementIndex]
                                .Date)
                    else
                        self:settext("Not Unlocked")
                    end
                end
            end
        },
        LoadFont("Common Normal") .. {
            Text = "Difficulty: ⭐⭐⭐⭐",
            InitCommand = function(self)
                self:valign(0):horizalign(right):zoom(1):diffusealpha(0.9):xy(
                    350, -150):diffuse(color("#FFFFFF"))
            end,
            SetCommand = function(self, params)
                if params == nil then
                    -- SM(params)
                    self:settext(params.displayname)
                else
                    if accolades[params.activePack][params.achievementIndex] then
                        local str = "Difficulty: "
                        for i = 1, accolades[params.activePack][params.achievementIndex]
                            .Difficulty do
                            str = str .. "⭐"
                        end
                        self:settext(str)
                    else
                        self:settext("N/A")
                    end
                end
            end
        },
        -- add a BitmapText to this ActorFrame
        LoadFont("Common Normal") .. {
            Name = "DateTime",
            InitCommand = function(self)
                timestamp_bmt = self

                self:xy(_screen.cx - 63, -180):horizalign(right)
                self:zoom(1)
            end,
            OnCommand = function(self)
                -- y offset for ScreenEvaluationStage or ScreenEvaluationNonstop
                -- or anything else that inherits from ScreenEvaluation

                -- use a slightly diffrent y offset for ScreenEvaluationSummary
                local screen = SCREENMAN:GetTopScreen()

                local textColor = Color.White

                self:diffuse(textColor)
                self:playcommand("Refresh")
            end,
            RefreshCommand = function(self)
                self:settext(DateFormat:format(Year(), MonthOfYear() + 1,
                                               DayOfMonth(), Hour(), Minute()))
            end
        },
        badges,
        Def.Sprite {
            Texture = "../ScreenSelectProfile underlay/_ranks/arrow",
            InitCommand = function(self)
                self:xy(300, 155):zoom(0.9):diffuse(color("#c7cbd9")):rotationz(
                    -90)
            end
        },
        Def.Sprite {
            Texture = "../ScreenSelectProfile underlay/_ranks/arrow",
            InitCommand = function(self)
                self:xy(325, 155):zoom(0.9):diffuse(color("#c7cbd9")):rotationz(
                    90)
            end

        },
        LoadFont("Common Normal") .. {
            Text = "Number",
            InitCommand = function(self)
                self:valign(0):horizalign(left):zoom(0.9):diffusealpha(0.9):xy(
                    -332, 148):diffuse(color("#575867"))
            end,
            SetCommand = function(self, params)
                if params == nil then
                    self:settext("0 of 0 unlocked")
                elseif not params.achievements or
                    not params.achievements[params.activePack] then
                    self:settext("0 of " .. #accolades[params.activePack] ..
                                     " unlocked")
                else
                    -- self:settext(math.random(0,binfo.rows * binfo.cols) .. " of " .. binfo.rows * binfo.cols .. " unlocked.")
                    self:settext(CountUnlockedAchievements(
                                     params.achievements[params.activePack]) ..
                                     " of " .. #accolades[params.activePack] ..
                                     " unlocked.")
                end
            end
        },
        -- --------------------------------------------------------------------------------
        -- Avatar ActorFrame
        Def.ActorFrame {
            InitCommand = function(self) self:xy(-40, -210):zoom(0.5) end,

            ---------------------------------------
            -- fallback avatar
            Def.ActorFrame {
                InitCommand = function(self) self:visible(true) end,
                SetCommand = function(self, params)
                    if params and params.index and avatars[params.index] then
                        self:visible(false)
                    else
                        self:visible(true)
                    end
                end,

                Def.Quad {
                    InitCommand = function(self)
                        self:align(0, 0):zoomto(avatar_dim, avatar_dim):diffuse(
                            color("#283239aa"))
                    end
                },
                LoadActor(THEME:GetPathG("", "_VisualStyles/" ..
                                             ThemePrefs.Get("VisualStyle") ..
                                             "/SelectColor")) .. {
                    InitCommand = function(self)
                        self:align(0, 0):zoom(0.09):diffusealpha(0.9):xy(13, 8)
                    end
                },
                LoadFont("Common Normal") .. {
                    Text = THEME:GetString("ProfileAvatar", "NoAvatar"),
                    InitCommand = function(self)
                        self:valign(0):zoom(0.815):diffusealpha(0.9):xy(
                            self:GetWidth() * 0.5 + 13, 67)
                    end,
                    SetCommand = function(self, params)
                        if params == nil then
                            self:settext(
                                THEME:GetString("ScreenSelectProfile",
                                                "GuestProfile"))
                        else
                            self:settext(
                                THEME:GetString("ProfileAvatar", "NoAvatar"))
                        end
                    end
                }
            },
            ---------------------------------------

            Def.Sprite {
                Name = "PlayerAvatar",
                InitCommand = function(self)
                    self:align(0, 0):scaletoclipped(avatar_dim, avatar_dim)
                end,
                SetCommand = function(self, params)
                    if params and params.index and avatars[params.index] then
                        self:Load(avatars[params.index]):visible(true)
                    elseif params.index == 0 then
                        self:Load(THEME:GetPathB("ScreenSelectProfile",
                                                 "underlay/" .. "Cabby.png"))
                            :visible(true)
                    else
                        self:visible(false)
                    end
                end
            },
            
        }
    }
}
