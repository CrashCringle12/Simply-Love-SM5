local t = {}

local function ProfileSortRecent(player)
	if player == nil then return end
    MESSAGEMAN:Broadcast('Sort', { order = "Recent"..ToEnumShortString(player) })
	MESSAGEMAN:Broadcast('ResetHeaderText')
	SCREENMAN:GetTopScreen():GetChild("Overlay"):queuecommand("DirectInputToEngine")
end
local function ProfileSortTopGrades(player)
    if player == nil then return end
    MESSAGEMAN:Broadcast('Sort', { order = "Top"..ToEnumShortString(player).."Grades" })
    MESSAGEMAN:Broadcast('ResetHeaderText')
    SCREENMAN:GetTopScreen():GetChild("Overlay"):queuecommand("DirectInputToEngine")
end

local function ProfileSortPopularity(player)
    if player == nil then return end
    MESSAGEMAN:Broadcast('Sort', { order = "Popularity"..ToEnumShortString(player) })
    MESSAGEMAN:Broadcast('ResetHeaderText')
    SCREENMAN:GetTopScreen():GetChild("Overlay"):queuecommand("DirectInputToEngine")
end

local atLeastOneProfile = function()
    return PROFILEMAN:IsPersistentProfile(PLAYER_1) or PROFILEMAN:IsPersistentProfile(PLAYER_2)
end

t["ScreenSelectMusic"] = Def.ActorFrame {
    ModuleCommand=function(self)
        -- Get all actors on screen
        local screen = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("SortMenu")
        table.insert(screen.wheel_options, 1, {
            name="FolderProfile Sorts",
            open=false,
            module=true,
            children={
                { {"Show", "My Recently Played", ProfileSortRecent}, atLeastOneProfile },
                { {"Show", "My High Scores",    ProfileSortTopGrades}, atLeastOneProfile },
                { {"Show", "My Most Played", ProfileSortPopularity}, atLeastOneProfile },
                -- One might ask the question...what else could go here besides built in sorts?
                -- On cabby I have the achievement system pretty much setup as a module...And you view achievements in the sort menu.
                -- I could and probably should move the Screenshot Gallery to a Module.
                -- But the idea here is that I can add other functions here that are custom and now selectable
                -- So I could also have "Show Achievements" and "Show Screenshot Gallery" in this folder too
                -- Maybe I have a check to see if that module exists before adding the option or it's something added as part of this one.
            }   
        })

    end

}

return t;
