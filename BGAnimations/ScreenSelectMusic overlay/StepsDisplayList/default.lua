local VisualList

if GAMESTATE:IsCourseMode() then
	VisualList = LoadActor("./CourseContentsList.lua")
	
elseif THEME:GetMetric("Common", "AutoSetStyle") == true then
	-- returning a NullActor meets the needs of returning an Actor but doesn't display anything
	VisualList = LoadActor("./Grid.lua")	
	
elseif enhancedUI() then
	-- This display only supports dance mode at this point in Singles mode
	VisualList = LoadActor("./Grid.lua")	
else
	VisualList = LoadActor("./Grid-Classic.lua")
end

return VisualList