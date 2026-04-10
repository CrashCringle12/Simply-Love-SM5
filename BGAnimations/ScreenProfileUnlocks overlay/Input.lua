local args = ...
local af = args.af
local localprofile_data = args.ProfileData
local guest_data = args.GuestData

local finished = false
local profiles = {}
local profile_data = {guest_data, guest_data}

for player in ivalues(GAMESTATE:GetHumanPlayers()) do
    local profile = PROFILEMAN:GetProfile(player)
    if profile then
        profiles[player] = profile
        for i, v in ipairs(localprofile_data) do
            if v.guid == profile:GetGUID() then
                profile_data[player] = v
                break
            end
        end
    end
end

local Handle = {}

Handle.Start = function(event)
    if not GAMESTATE:IsHumanPlayer(event.PlayerNumber) then return end
    MESSAGEMAN:Broadcast("StartButton")
end
Handle.Center = Handle.Start

Handle.MenuLeft = function(event)
    if not GAMESTATE:IsHumanPlayer(event.PlayerNumber) then return end
    if not SL.Global.UnlockMenuActive then return end

    local pn = ToEnumShortString(event.PlayerNumber)
    local nav = SL.Global.UnlockNav and SL.Global.UnlockNav[pn]
    if not nav then return end

    nav.chainIndex = nav.chainIndex - 1
    if nav.chainIndex < 1 then nav.chainIndex = #nav.chains end
    nav.nodeIndex = 1
    nav.scrollOffset = 0

    MESSAGEMAN:Broadcast("DirectionButton")
    local unlockFrame = af:GetChild('UnlockFrame')
    if unlockFrame then
        unlockFrame:playcommand("Set", {
            chainIndex = nav.chainIndex,
            nodeIndex = nav.nodeIndex,
            displayname = profile_data[event.PlayerNumber] and profile_data[event.PlayerNumber].displayname or "",
            index = profile_data[event.PlayerNumber] and profile_data[event.PlayerNumber].index or 0,
        })
    end
end

Handle.MenuRight = function(event)
    if not GAMESTATE:IsHumanPlayer(event.PlayerNumber) then return end
    if not SL.Global.UnlockMenuActive then return end

    local pn = ToEnumShortString(event.PlayerNumber)
    local nav = SL.Global.UnlockNav and SL.Global.UnlockNav[pn]
    if not nav then return end

    nav.chainIndex = nav.chainIndex + 1
    if nav.chainIndex > #nav.chains then nav.chainIndex = 1 end
    nav.nodeIndex = 1
    nav.scrollOffset = 0

    MESSAGEMAN:Broadcast("DirectionButton")
    local unlockFrame = af:GetChild('UnlockFrame')
    if unlockFrame then
        unlockFrame:playcommand("Set", {
            chainIndex = nav.chainIndex,
            nodeIndex = nav.nodeIndex,
            displayname = profile_data[event.PlayerNumber] and profile_data[event.PlayerNumber].displayname or "",
            index = profile_data[event.PlayerNumber] and profile_data[event.PlayerNumber].index or 0,
        })
    end
end

Handle.MenuUp = function(event)
    if not GAMESTATE:IsHumanPlayer(event.PlayerNumber) then return end
    if not SL.Global.UnlockMenuActive then return end

    local pn = ToEnumShortString(event.PlayerNumber)
    local nav = SL.Global.UnlockNav and SL.Global.UnlockNav[pn]
    if not nav then return end

    local chain = nav.chains[nav.chainIndex]
    if not chain or #chain.nodes == 0 then return end

    nav.nodeIndex = nav.nodeIndex - 1
    if nav.nodeIndex < 1 then nav.nodeIndex = #chain.nodes end

    MESSAGEMAN:Broadcast("DirectionButton")
    local unlockFrame = af:GetChild('UnlockFrame')
    if unlockFrame then
        unlockFrame:playcommand("Set", {
            chainIndex = nav.chainIndex,
            nodeIndex = nav.nodeIndex,
            displayname = profile_data[event.PlayerNumber] and profile_data[event.PlayerNumber].displayname or "",
            index = profile_data[event.PlayerNumber] and profile_data[event.PlayerNumber].index or 0,
        })
    end
end

Handle.MenuDown = function(event)
    if not GAMESTATE:IsHumanPlayer(event.PlayerNumber) then return end
    if not SL.Global.UnlockMenuActive then return end

    local pn = ToEnumShortString(event.PlayerNumber)
    local nav = SL.Global.UnlockNav and SL.Global.UnlockNav[pn]
    if not nav then return end

    local chain = nav.chains[nav.chainIndex]
    if not chain or #chain.nodes == 0 then return end

    nav.nodeIndex = nav.nodeIndex + 1
    if nav.nodeIndex > #chain.nodes then nav.nodeIndex = 1 end

    MESSAGEMAN:Broadcast("DirectionButton")
    local unlockFrame = af:GetChild('UnlockFrame')
    if unlockFrame then
        unlockFrame:playcommand("Set", {
            chainIndex = nav.chainIndex,
            nodeIndex = nav.nodeIndex,
            displayname = profile_data[event.PlayerNumber] and profile_data[event.PlayerNumber].displayname or "",
            index = profile_data[event.PlayerNumber] and profile_data[event.PlayerNumber].index or 0,
        })
    end
end

Handle.Up = Handle.MenuUp
Handle.Down = Handle.MenuDown
Handle.Left = Handle.MenuLeft
Handle.Right = Handle.MenuRight
Handle.DownLeft = Handle.MenuLeft
Handle.DownRight = Handle.MenuRight

Handle.Back = function(event)
    if SL.Global.UnlockMenuActive then
        MESSAGEMAN:Broadcast("BackButton", {PlayerNumber = event.PlayerNumber})
        SCREENMAN:GetTopScreen():playcommand("Hide")
        SCREENMAN:GetTopScreen():playcommand("Off")
        SL.Global.UnlockMenuActive = false
    end
end
Handle.Select = Handle.Back

local InputHandler = function(event)
    if finished then return false end
    if not event or not event.button then return false end
    if not profile_data[event.PlayerNumber] then
        if not (PROFILEMAN:IsPersistentProfile(PLAYER_1) or PROFILEMAN:IsPersistentProfile(PLAYER_2)) then
            Handle.Back(event)
        end
        return false
    end
    if event.type ~= "InputEventType_Release" then
        if Handle[event.button] then Handle[event.button](event) end
    end
end

return InputHandler
