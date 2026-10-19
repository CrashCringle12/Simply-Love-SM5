-- retrieve the current VisualStyle from the ThemePrefs system
local style = ThemePrefs.Get("VisualStyle")

-- Use the shared mapping so playback and package exports include the same music.
local file = GetVisualStyleMusic(style)

-- If this style has no music mapping,
-- fall back on the song for Hearts as default music
-- (this sometimes happens when people are experimenting
-- with making their own custom VisualStyles)
if not file then file = GetVisualStyleMusic("Hearts") end

-- annnnnd some EasterEggs
if PREFSMAN:GetPreference("EasterEggs") and style ~= "Thonk" then
	--  41 days remain until the end of the year.
	if MonthOfYear()==10 and DayOfMonth()==20 then file = "20" end
	-- the best way to spread holiday cheer is singing loud for all to hear
	if MonthOfYear()==11 then file = "HolidayCheer" end
end

return THEME:GetPathS("", "_common menu music/" .. file)
