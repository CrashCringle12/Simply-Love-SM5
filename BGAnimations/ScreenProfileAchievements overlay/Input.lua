local args = ...
local af = args.af
local localprofile_data = args.ProfileData
local guest_data = args.GuestData

local spamCheck = {
    lastKey = "",
    amount = 0,
}

local finished = false
local profiles = {}
local profile_data = {guest_data, guest_data}
local indexes = {}

for player in ivalues(GAMESTATE:GetHumanPlayers()) do
    local profile = PROFILEMAN:GetProfile(player)
    if profile then
        profiles[player] = profile
        indexes[player] = 0
        for i, v in ipairs(localprofile_data) do
            if v.guid == profile:GetGUID() then
                profile_data[player] = v
                break
            end
        end
    end
end

local PreferredStyle = ThemePrefs.Get("PreferredStyle")
local mpn = GAMESTATE:GetMasterPlayerNumber()

local Handle = {}

Handle.Start = function(event)
	local topscreen = SCREENMAN:GetTopScreen()
	-- if the input event came from a side that is not currently registered as a human player, we'll either
	-- want to reject the input (we're in Pay mode and there aren't enough credits to join the player),
	-- or we'll use ScreenSelectProfile's inscrutably custom SetProfileIndex() method to join the player.
	if not GAMESTATE:IsHumanPlayer(event.PlayerNumber) then

		-- IsArcade() is defined in _fallback/Scripts/02 Utilities.lua
		-- in CoinMode_Free, EnoughCreditsToJoin() will always return true
		-- thankfully, EnoughCreditsToJoin() factors in Premium settings
		if IsArcade() and not GAMESTATE:EnoughCreditsToJoin() then
			-- play the InvalidChoice sound and don't go any further
			MESSAGEMAN:Broadcast("InvalidChoice", {PlayerNumber=event.PlayerNumber})
			return
		end
	else
		MESSAGEMAN:Broadcast("Cursor", {PlayerNumber=event.PlayerNumber})
		-- otherwise, play the StartButton sound
		MESSAGEMAN:Broadcast("StartButton")
	end
end
Handle.Center = Handle.Start

Handle.MenuLeft = function(event)
	if GAMESTATE:IsHumanPlayer(event.PlayerNumber) then
        local data = profile_data[event.PlayerNumber]
        local index = indexes[event.PlayerNumber]
		if data.achievementIndex - 1 > -1 then
			if SL.Global.AchievementMenuActive then
				local achievements = af:GetChild('AchievementFrame')
				if event.button == "MenuLeft" then
					data.activePack = data.activePack == "Default" and "Trials" or "Default"
				else
					data.achievementIndex = data.achievementIndex - (string.match(event.button, "Up") and 8 or 1)
					if data.achievementIndex < 1 then
						data.achievementIndex = 1
					end
				end
				achievements:playcommand("Set", data)
			elseif SL.Global.AchievementPackMenu then
				local achievementPacks = af:GetChild('AchievementPacksFrame')
				data.activePack = data.activePack - (string.match(event.button, "Up") and 8 or 1)
				if data.activePack < 1 then
					data.activePack = 1
				end
				achievementPacks:playcommand("Set", data)
			end
		end
	end
end

Handle.MenuUp = Handle.MenuLeft

Handle.DownLeft = Handle.MenuLeft

Handle.MenuRight = function(event)
	if GAMESTATE:IsHumanPlayer(event.PlayerNumber) then
		local index = indexes[event.PlayerNumber]
        if SL.Global.AchievementMenuActive then
            local data = profile_data[event.PlayerNumber]
            local achievements = af:GetChild('AchievementFrame')
            if event.button == "MenuRight" then
                data.activePack = data.activePack == "Default" and "Trials" or "Default"
            else
                data.achievementIndex = data.achievementIndex + (string.match(event.button, "Down") and 8 or 1)
                if data.achievementIndex > #SL.Accolades.Achievements[data.activePack] then
                    data.achievementIndex = #SL.Accolades.Achievements[data.activePack]
                end
            end
            achievements:playcommand("Set", data)
        elseif SL.Global.AchievementPackMenu then
            local achievementPacks = af:GetChild('AchievementPacksFrame')
            data.activePack = data.activePack + (string.match(event.button, "Down") and 8 or 1)
            if data.achievementIndex > #SL.Accolades.Achievements[data.activePack] then
                data.achievementIndex = #SL.Accolades.Achievements[data.activePack]
            end
            if data.activePack > 24 then
                data.activePack = 24
            end
            achievementPacks:playcommand("Set", data)
        end
	end
end

Handle.MenuDown = Handle.MenuRight

Handle.DownRight = Handle.MenuRight
Handle.EffectUp = function(event)
	if GAMESTATE:IsHumanPlayer(event.PlayerNumber) then
		local index = type(info)=="table" and info.index or 0
        local data = profile_data[event.PlayerNumber]
        local achievements = af:GetChild('AchievementFrame')
        data.achievementIndex = data.achievementIndex + (event.GameButton == "MenuDown" and 8 or 1)
        if data.achievementIndex > #SL.Accolades.Achievements[data.activePack] then
            data.achievementIndex = #SL.Accolades.Achievements[data.activePack]
        end
        if data.achievementIndex > 24 then
            data.achievementIndex = 24
        end
        achievements:playcommand("Set", data)
	end
end
Handle.Up = Handle.MenuUp
Handle.Down = Handle.MenuDown
Handle.Right = Handle.MenuRight
Handle.Left =Handle.MenuLeft

Handle.Select = Handle.Back
Handle.Back = function(event)
	if SL.Global.AchievementMenuActive then
		local achievements = af:GetChild('AchievementFrame')
        MESSAGEMAN:Broadcast("BackButton", {PlayerNumber=event.PlayerNumber})
        -- On the other hand, dismissing the regular ScreenSelectProfile
        -- (not in fast switch mode) is perfectly fine since we can just go
        -- back to the previous screen
        SCREENMAN:GetTopScreen():playcommand("Hide")
        SCREENMAN:GetTopScreen():playcommand("Off")
		SL.Global.AchievementMenuActive = false
	elseif SL.Global.AchievementPackMenu then
		local achievementPacks = af:GetChild('AchievementPacksFrame')
		achievementPacks:playcommand("Hide", data)
		SL.Global.AchievementPackMenu = false
	end
end


local InputHandler = function(event)
	if finished then return false end
	if not event or not event.button then return false end
	-- if (PreferredStyle=="single" or PreferredStyle=="double") and event.PlayerNumber ~= mpn then return false	end
	if event.type ~= "InputEventType_Release" then
        if spamCheck.lastKey == event.button then
            spamCheck.amount = spamCheck.amount + 1
        else
            spamCheck.lastKey = event.button
            spamCheck.amount = 1
        end
		if Handle[event.button] then Handle[event.button](event) end
		
	end
end

return InputHandler
