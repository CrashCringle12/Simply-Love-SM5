local candidatesScroller = ...

local input = function(event)
	if not (event and event.PlayerNumber and event.button) then
		return false
	end

	local overlay = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("SongSearch")

	if event.type ~= "InputEventType_Release" then
		local info = candidatesScroller:get_info_at_focus_pos()
		local index = type(info)=="table" and info.index or 0
		local num_items = type(info)=="table" and info.totalItems or candidatesScroller.num_items
		if event.GameButton == "MenuRight" or event.GameButton == "MenuDown" then
			candidatesScroller:scroll_by_amount(1)
		elseif event.GameButton == "MenuLeft" or event.GameButton == "MenuUp" then
			candidatesScroller:scroll_by_amount(-1)
		elseif event.GameButton == "Start" then
			local focus = candidatesScroller:get_actor_item_at_focus_pos()
			local songOrExit = focus.song_name.songOrExit
			if type(songOrExit) ~= "string" then
				GAMESTATE:SetPreferredSong(songOrExit)
				local screen = SCREENMAN:GetTopScreen()

				-- some SortOrders reduce the number of songs currently displayed in the MusicWheel.
				-- GAMESTATE:SetPreferredSong() will correctly set the preferred song, but the MusicWheel
				-- may not currently have that song to display after screen reload.
				-- if we're in one of those SortOrders, change the SortOrder to Series as a workaround
				local current_sort_order = GAMESTATE:GetSortOrder()
				if (current_sort_order == "SortOrder_Preferred")
				or (string.find(current_sort_order, "SortOrder_Popularity") ~= nil)
				or (string.find(current_sort_order, "SortOrder_Recent") ~= nil) then
					screen:GetMusicWheel():ChangeSort("SortOrder_Series")
				end
				
				if THEME:GetMetric("Common", "AutoSetStyle") == true then
					GAMESTATE:SetCurrentSong(songOrExit)
					local preferredDifficulty = GAMESTATE:GetPreferredDifficulty(event.PlayerNumber)
					local steps = songOrExit:GetOneSteps(GAMESTATE:GetCurrentStyle():GetStepsType(), preferredDifficulty)
					if steps and SongUtil.IsStepsPlayable(songOrExit, steps) then
						GAMESTATE:SetCurrentSteps(event.PlayerNumber, steps)
					else
						-- if the preferred difficulty isn't available, pick the first available Steps
						local playable_steps = SongUtil.GetPlayableSteps(songOrExit)
						if playable_steps and #playable_steps > 0 then
							GAMESTATE:SetCurrentSteps(event.PlayerNumber, playable_steps[1])
						end
					end
				end

				screen:SetNextScreenName("ScreenReloadSSM")
				screen:StartTransitioningScreen("SM_GoToNextScreen")
			end
			overlay:queuecommand("DirectInputToEngine")
		elseif event.GameButton == "Back" or event.GameButton == "Select" then
			overlay:queuecommand("DirectInputToEngine")
		end
	end
	return false
end

return input