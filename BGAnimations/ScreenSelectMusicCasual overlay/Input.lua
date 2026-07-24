-- Input.lua
--
-- Input state machine for ScreenSelectMusicCasual's horizontal redesign.
--
-- Focus states (t.WheelWithFocus points to one of these):
--   SongWheel    : the main horizontal music wheel (default)
--   SortMenu     : the sort menu overlay (opened by Select)
--   GroupJumper  : sub-view of SortMenu -> "Change Group"
--   OptionsWheel : per-player modal (Chart + Speed + Exit rows)
--
-- Sort state (t.CurrentSortMode, t.CurrentGroup) is owned here and
-- broadcast to interested widgets via:
--   ApplySortMode      { mode, group }  -- MusicWheel rebuilds its list
--   SortModeChanged    { mode }         -- Header updates its label
--
-- SortMenu cursor state (t.SortMenuCursor) is broadcast as:
--   SortMenuCursorChanged { cursor }    -- SortMenu highlights the card
---------------------------------------------------------------------------
local args = ...
local SongWheel    = args.SongWheel
local GroupWheel   = args.GroupWheel     -- sick_wheel inside GroupJumper
local OptionsWheel = args.OptionsWheel
local OptionRows   = args.OptionRows
local setup        = args.setup

-- SortMenu and GroupJumper overlay actors are wired later (in the outer
-- default.lua's InitCommand) so we can't capture them here at LoadActor
-- time -- they'd still be nil.  Look them up lazily via args.* whenever
-- we need to compare identity or push messages.
local function get_SortMenu()    return args.SortMenu    end
local function get_GroupJumper() return args.GroupJumper end

-- Must stay in sync with SortMenu/default.lua's option_keys table.
local sort_options = { "ChangeGroup", "Title", "Artist", "MostPlayed", "RecentlyPlayed" }

local Players = GAMESTATE:GetHumanPlayers()
local ActiveOptionRow

local t = {}

-----------------------------------------------------------------
t.AllowLateJoin = function()
	if GAMESTATE:GetCurrentStyle():GetName() ~= "single" then return false end
	if PREFSMAN:GetPreference("EventMode") then return true end
	if GAMESTATE:GetCoinMode() ~= "CoinMode_Pay" then return true end
	if GAMESTATE:GetCoinMode() == "CoinMode_Pay"
	   and PREFSMAN:GetPreference("Premium") == "Premium_2PlayersFor1Credit" then return true end
	return false
end

t.AllPlayersAreAtLastRow = function()
	for player in ivalues(Players) do
		if ActiveOptionRow[player] ~= #OptionRows then return false end
	end
	return true
end

-----------------------------------------------------------------
local GetAllowedSteps = function()
	local song = GAMESTATE:GetCurrentSong()
	if not song then return {} end
	local max_meter  = ThemePrefs.Get("CasualMaxMeter")
	local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
	local out = {}
	for chart in ivalues(SongUtil.GetPlayableSteps(song)) do
		if chart:GetStepsType() == steps_type and chart:GetMeter() <= max_meter then
			out[#out+1] = chart
		end
	end
	return out
end

local CyclePlayerDifficulty = function(player, direction)
	local allowed = GetAllowedSteps()
	if #allowed <= 1 then return false end
	local cur = GAMESTATE:GetCurrentSteps(player)
	local idx = 1
	for i, s in ipairs(allowed) do if s == cur then idx = i; break end end
	idx = ((idx - 1 + direction) % #allowed) + 1
	GAMESTATE:SetCurrentSteps(player, allowed[idx])
	return true
end

-----------------------------------------------------------------
-- Apply a new sort mode: rebuild the SongWheel's list and update the
-- header label.  Called from both the SortMenu (any non-Group choice)
-- and the GroupJumper ("Change Group" commit).
local ApplySort = function(mode, group)
	t.CurrentSortMode = mode
	if group then t.CurrentGroup = group end
	MESSAGEMAN:Broadcast("ApplySortMode", { mode = mode, group = t.CurrentGroup })
	MESSAGEMAN:Broadcast("SortModeChanged", { mode = mode })
end

-----------------------------------------------------------------
t.Init = function()
	t.Enabled         = false
	t.WheelWithFocus  = SongWheel
	t.SortMenuCursor  = 1
	t.CurrentSortMode = setup.InitialSortMode or "Group"
	t.CurrentGroup    = setup.InitialGroup
	ActiveOptionRow   = { [PLAYER_1] = 1, [PLAYER_2] = 1 }

	t.CancelSongChoice = function()
		t.Enabled = false
		for pn in ivalues(Players) do
			ActiveOptionRow[pn] = 1
			OptionsWheel[pn]:scroll_to_pos(1)
		end
		MESSAGEMAN:Broadcast("SingleSongCanceled")
		MESSAGEMAN:Broadcast("CancelBothPlayersAreReady")
		t.WheelWithFocus = SongWheel
		MESSAGEMAN:Broadcast("SwitchFocusToSongs")
	end
end

-----------------------------------------------------------------
local EnterModalForAllPlayers = function()
	MESSAGEMAN:Broadcast("SwitchFocusToSingleSong")
	t.WheelWithFocus = OptionsWheel
end

-----------------------------------------------------------------
-- main input handler
t.Handler = function(event)
	if t.Enabled == false or not event or not event.PlayerNumber or not event.button then
		return false
	end

	-- Late-join
	if not GAMESTATE:IsSideJoined(event.PlayerNumber) then
		if not t.AllowLateJoin() then return false end
		if t.WheelWithFocus == OptionsWheel and event.GameButton == "Start" then
			GAMESTATE:JoinPlayer( event.PlayerNumber )
			Players = GAMESTATE:GetHumanPlayers()
			MESSAGEMAN:Broadcast("PlaySFX", {Action="Start"})
		end
		return false
	end

	if event.type == "InputEventType_Release" then return false end

	if event.GameButton == "Back" then
		if t.WheelWithFocus == get_SortMenu() then
			MESSAGEMAN:Broadcast("CloseSortMenu")
			t.WheelWithFocus = SongWheel
			return false
		elseif t.WheelWithFocus == get_GroupJumper() then
			MESSAGEMAN:Broadcast("CloseGroupJumper")
			MESSAGEMAN:Broadcast("OpenSortMenu")
			t.WheelWithFocus = get_SortMenu()
			return false
		end
		SCREENMAN:GetTopScreen():SetNextScreenName( Branch.SSMCancel() ):StartTransitioningScreen("SM_GoToNextScreen")
		return false
	end

	--------------------------------------------------------------
	-- SongWheel
	--------------------------------------------------------------
	if t.WheelWithFocus == SongWheel then
		if event.GameButton == "MenuRight" then
			SongWheel:scroll_by_amount(1)
			MESSAGEMAN:Broadcast("ScrolledRight")
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})

		elseif event.GameButton == "MenuLeft" then
			SongWheel:scroll_by_amount(-1)
			MESSAGEMAN:Broadcast("ScrolledLeft")
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})

		elseif event.GameButton == "MenuUp" then
			if CyclePlayerDifficulty(event.PlayerNumber, -1) then
				MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})
			end

		elseif event.GameButton == "MenuDown" then
			if CyclePlayerDifficulty(event.PlayerNumber, 1) then
				MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})
			end

		elseif event.GameButton == "Start" then
			t.Enabled = false
			MESSAGEMAN:Broadcast("PlaySFX", {Action="Start"})
			EnterModalForAllPlayers()

		elseif event.GameButton == "Select" then
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeGroup", Player=event.PlayerNumber})
			-- Cursor stays where it was last (or starts at 1 on first open)
			MESSAGEMAN:Broadcast("OpenSortMenu")
			-- Publish initial cursor state so SortMenu highlights the right card
			MESSAGEMAN:Broadcast("SortMenuCursorChanged", { cursor = t.SortMenuCursor })
			t.WheelWithFocus = get_SortMenu()
		end

	--------------------------------------------------------------
	-- SortMenu (horizontal 5-card picker)
	--------------------------------------------------------------
	elseif t.WheelWithFocus == get_SortMenu() then
		if event.GameButton == "MenuRight" then
			t.SortMenuCursor = (t.SortMenuCursor % #sort_options) + 1
			MESSAGEMAN:Broadcast("SortMenuCursorChanged", { cursor = t.SortMenuCursor })
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})

		elseif event.GameButton == "MenuLeft" then
			t.SortMenuCursor = ((t.SortMenuCursor - 2) % #sort_options) + 1
			MESSAGEMAN:Broadcast("SortMenuCursorChanged", { cursor = t.SortMenuCursor })
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})

		elseif event.GameButton == "Start" then
			local chosen = sort_options[t.SortMenuCursor]
			MESSAGEMAN:Broadcast("SortMenuChose", { cursor = t.SortMenuCursor })
			MESSAGEMAN:Broadcast("PlaySFX", {Action="Start", Player=event.PlayerNumber})
			if chosen == "ChangeGroup" then
				MESSAGEMAN:Broadcast("CloseSortMenu")
				MESSAGEMAN:Broadcast("OpenGroupJumper")
				t.WheelWithFocus = get_GroupJumper()
			else
				ApplySort(chosen, t.CurrentGroup)
				MESSAGEMAN:Broadcast("CloseSortMenu")
				t.WheelWithFocus = SongWheel
			end

		elseif event.GameButton == "Select" then
			MESSAGEMAN:Broadcast("CloseSortMenu")
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeGroup", Player=event.PlayerNumber})
			t.WheelWithFocus = SongWheel
		end

	--------------------------------------------------------------
	-- GroupJumper (horizontal coverflow of groups)
	--------------------------------------------------------------
	elseif t.WheelWithFocus == get_GroupJumper() then
		if event.GameButton == "MenuRight" then
			GroupWheel:scroll_by_amount(1)
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeGroup", Player=event.PlayerNumber})

		elseif event.GameButton == "MenuLeft" then
			GroupWheel:scroll_by_amount(-1)
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeGroup", Player=event.PlayerNumber})

		elseif event.GameButton == "Start" then
			local group_name = GroupWheel:get_info_at_focus_pos()
			if group_name then
				ApplySort("Group", group_name)
			end
			MESSAGEMAN:Broadcast("CloseGroupJumper")
			MESSAGEMAN:Broadcast("PlaySFX", {Action="Start", Player=event.PlayerNumber})
			t.WheelWithFocus = SongWheel

		elseif event.GameButton == "Select" then
			MESSAGEMAN:Broadcast("CloseGroupJumper")
			MESSAGEMAN:Broadcast("OpenSortMenu")
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeGroup", Player=event.PlayerNumber})
			t.WheelWithFocus = get_SortMenu()
		end

	--------------------------------------------------------------
	-- OptionsWheel (per-player modal)
	--------------------------------------------------------------
	else
		local index    = ActiveOptionRow[event.PlayerNumber]
		local row_def  = OptionRows[index]
		local has_row  = row_def and row_def.Choices ~= nil

		if event.GameButton == "MenuRight" then
			if has_row then
				OptionsWheel[event.PlayerNumber][index]:scroll_by_amount(1)
				MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})
			end

		elseif event.GameButton == "MenuLeft" then
			if has_row then
				OptionsWheel[event.PlayerNumber][index]:scroll_by_amount(-1)
				MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})
			end

		elseif event.GameButton == "Start" or event.GameButton == "MenuDown" then
			if event.GameButton == "Start" and t.AllPlayersAreAtLastRow() then
				MESSAGEMAN:Broadcast("PlaySFX", {Action="Start", Player=event.PlayerNumber})
				MESSAGEMAN:Broadcast("WheelSongCommitted")
				local topscreen = SCREENMAN:GetTopScreen()
				if topscreen then topscreen:StartTransitioningScreen("SM_GoToNextScreen") end
				return false
			end

			if index < #OptionRows and has_row then
				local choice  = OptionsWheel[event.PlayerNumber][index]:get_info_at_focus_pos()
				local choices = row_def:Choices()
				local values  = row_def.Values()
				row_def:OnSave(event.PlayerNumber, choice, choices, values)
				OptionsWheel[event.PlayerNumber]:scroll_by_amount(1)
			elseif index < #OptionRows then
				OptionsWheel[event.PlayerNumber]:scroll_by_amount(1)
			end

			index = math.min(index + 1, #OptionRows)
			ActiveOptionRow[event.PlayerNumber] = index

			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})

			if t.AllPlayersAreAtLastRow() then
				MESSAGEMAN:Broadcast("BothPlayersAreReady")
			end

		elseif event.GameButton == "MenuUp" then
			if index > 1 then
				index = index - 1
				ActiveOptionRow[event.PlayerNumber] = index
				OptionsWheel[event.PlayerNumber]:scroll_by_amount(-1)
				MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})
				MESSAGEMAN:Broadcast("CancelBothPlayersAreReady")
			end

		elseif event.GameButton == "Select" then
			t.CancelSongChoice()
		end
	end

	return false
end

return t
