-- Input.lua
--
-- Input state machine for ScreenSelectMusicCasual's horizontal redesign.
--
-- Focus states (t.WheelWithFocus points to one of these):
--   SongWheel      : the main horizontal music wheel (default)
--   SortMenu       : the sort menu overlay (opened by Select on wheel,
--                    OR by pressing Start on the in-wheel "Sorts" folder)
--   GroupJumper    : sub-view of SortMenu -> "Change Group"
--   LetterJumper   : sub-view of SortMenu -> "By Title" or "By Artist"
--   MeterJumper    : sub-view of SortMenu -> "By Meter"
--   OptionsWheel   : per-player modal (Chart + Speed + Exit rows)
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
local LetterWheel  = args.LetterWheel    -- sick_wheel inside LetterJumper
local MeterWheel   = args.MeterWheel     -- sick_wheel inside MeterJumper
local OptionsWheel = args.OptionsWheel
local OptionRows   = args.OptionRows
local setup        = args.setup

-- Overlay actor refs are wired later (in default.lua's InitCommand) so we
-- can't capture them here at LoadActor time.  Look them up lazily via
-- args.* whenever we need identity comparisons or state routing.
local function get_SortMenu()     return args.SortMenu     end
local function get_GroupJumper()  return args.GroupJumper  end
local function get_LetterJumper() return args.LetterJumper end
local function get_MeterJumper()  return args.MeterJumper  end

-- Must stay in sync with SortMenu/default.lua's option_keys table.
local sort_options = { "ChangeGroup", "Title", "Artist", "Meter", "Popular", "Recent" }

local Players = GAMESTATE:GetHumanPlayers()
local ActiveOptionRow

local t = {}

local GetRowIndexByName = function(name)
	for i, row in ipairs(OptionRows) do
		if row and row.Name == name then return i end
	end
	return nil
end

local SpeedRowIndex = GetRowIndexByName("Speed")
local ChartRowIndex = GetRowIndexByName("Chart")

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
		MESSAGEMAN:Broadcast("OnePlayerIsAtLastRow", { Player = player })
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

-- After a sort is applied, jump the SongWheel to the first item that
-- matches a predicate.  Skips the Sorts folder marker so we never land
-- on it accidentally.
local JumpToFirstMatch = function(predicate)
	local info = SongWheel.info_set
	if not info then return end
	for i, item in ipairs(info) do
		if not setup.IsSortsFolder(item) and predicate(item) then
			SongWheel:scroll_to_pos(i)
			return
		end
	end
end

local function LetterMatcher(field, letter)
	return function(song)
		local s = ((field == "Artist") and song:GetDisplayArtist() or song:GetDisplayMainTitle()) or ""
		s = s:gsub("^%s+", "")
		local first = s:sub(1,1):upper()
		if letter == "#" then
			return first < "A" or first > "Z"
		end
		return first == letter
	end
end

local function MeterMatcher(meter)
	local max_m = ThemePrefs.Get("CasualMaxMeter")
	return function(song)
		local ok, list = pcall(song.GetStepsByStepsType, song, setup.steps_type)
		if not ok or type(list) ~= "table" then return false end
		for chart in ivalues(list) do
			local m = chart:GetMeter()
			if m == meter and m <= max_m then return true end
		end
		return false
	end
end

-----------------------------------------------------------------
t.Init = function()
	t.Enabled           = false
	t.WheelWithFocus    = SongWheel
	t.SortMenuCursor    = 1
	t.CurrentSortMode   = setup.InitialSortMode or "Group"
	t.CurrentGroup      = setup.InitialGroup
	t.LetterJumperMode  = "Title"  -- which field the letter refers to
	ActiveOptionRow     = { [PLAYER_1] = 1, [PLAYER_2] = 1 }

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
local BroadcastGameplayDemoSpeed = function(player, source)
	if not player or not SpeedRowIndex then return end
	local row_def = OptionRows[SpeedRowIndex]
	if not row_def or not row_def.ResolveCModForChoice then return end
	local wheel = OptionsWheel[player] and OptionsWheel[player][SpeedRowIndex]
	if not wheel then
		local cmod = GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred"):CMod()
		MESSAGEMAN:Broadcast("GameplayDemoSpeedChanged", {
			Player = player,
			CMod = tonumber(cmod) or 300,
			Source = source or "InputFallback"
		})
		return
	end

	local choice = wheel:get_info_at_focus_pos()
	local cmod = choice and row_def:ResolveCModForChoice(player, choice)
	if not cmod then
		cmod = GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred"):CMod()
	end
	if cmod then
		MESSAGEMAN:Broadcast("GameplayDemoSpeedChanged", {
			Player = player,
			CMod = tonumber(cmod) or 300,
			Source = source or "Input"
		})
	end
end

local RefreshAutoSpeedForPlayer = function(player)
	if not player or not SpeedRowIndex then return end
	local row_def = OptionRows[SpeedRowIndex]
	if not row_def or not row_def.ResolveCModForChoice then return end
	local wheel = OptionsWheel[player] and OptionsWheel[player][SpeedRowIndex]
	if not wheel then return end

	local choice = wheel:get_info_at_focus_pos()
	if choice and choice.index == 1 then
		local cmod = row_def:ResolveCModForChoice(player, choice)
		GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred"):CMod(cmod)
		MESSAGEMAN:Broadcast("GameplayDemoSpeedChanged", {
			Player = player,
			CMod = cmod,
			Source = "AutoSpeedRefresh"
		})
	end
end

local BroadcastGameplayDemoDifficulty = function(player, source, explicit_meter)
	if not player then return end
	local meter = tonumber(explicit_meter)

	if not meter and ChartRowIndex and ActiveOptionRow and ActiveOptionRow[player] == ChartRowIndex then
		local wheel = OptionsWheel[player] and OptionsWheel[player][ChartRowIndex]
		if wheel then
			local choice = wheel:get_info_at_focus_pos()
			meter = choice and tonumber(choice.meter)
		end
	end

	if not meter then
		local steps = GAMESTATE:GetCurrentSteps(player)
		meter = steps and tonumber(steps:GetMeter()) or nil
	end

	if meter then
		MESSAGEMAN:Broadcast("GameplayDemoDifficultyChanged", {
			Player = player,
			Meter = meter,
			Source = source or "Input"
		})
	end
end

local EnterModalForAllPlayers = function()
	MESSAGEMAN:Broadcast("SwitchFocusToSingleSong")
	t.WheelWithFocus = OptionsWheel
	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		BroadcastGameplayDemoDifficulty(player, "OpenModal")
		BroadcastGameplayDemoSpeed(player, "OpenModal")
	end
end

-- Open the SortMenu.  Used by Select-on-wheel AND Start-on-Sorts-folder.
local OpenSortMenu = function()
	MESSAGEMAN:Broadcast("OpenSortMenu")
	MESSAGEMAN:Broadcast("SortMenuCursorChanged", { cursor = t.SortMenuCursor })
	t.WheelWithFocus = get_SortMenu()
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
			OpenSortMenu()
			return false
		elseif t.WheelWithFocus == get_LetterJumper() then
			MESSAGEMAN:Broadcast("CloseLetterJumper")
			OpenSortMenu()
			return false
		elseif t.WheelWithFocus == get_MeterJumper() then
			MESSAGEMAN:Broadcast("CloseMeterJumper")
			OpenSortMenu()
			return false
		elseif t.WheelWithFocus == OptionsWheel then
			t.CancelSongChoice()
		else
			SCREENMAN:GetTopScreen():SetNextScreenName( Branch.SSMCancel() ):StartTransitioningScreen("SM_GoToNextScreen")
		end
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

		elseif event.GameButton == "MenuDown" then
			-- Difficulty controls only make sense when we're focused on
			-- an actual song (not the Sorts folder marker).
			local focused = SongWheel:get_info_at_focus_pos()
			if not setup.IsSortsFolder(focused) then
				if CyclePlayerDifficulty(event.PlayerNumber, -1) then
					MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})
				end
			end

		elseif event.GameButton == "MenuUp" then
			local focused = SongWheel:get_info_at_focus_pos()
			if not setup.IsSortsFolder(focused) then
				if CyclePlayerDifficulty(event.PlayerNumber, 1) then
					MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})
				end
			end

		elseif event.GameButton == "Start" then
			local focused = SongWheel:get_info_at_focus_pos()
			if setup.IsSortsFolder(focused) then
				-- Start on the Sorts folder opens the SortMenu overlay
				-- (same behavior as Select; both entry points coexist).
				MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeGroup", Player=event.PlayerNumber})
				OpenSortMenu()
			else
				t.Enabled = false
				MESSAGEMAN:Broadcast("PlaySFX", {Action="Start"})
				EnterModalForAllPlayers()
			end

		elseif event.GameButton == "Select" then
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeGroup", Player=event.PlayerNumber})
			OpenSortMenu()
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
			MESSAGEMAN:Broadcast("CloseSortMenu")

			if chosen == "ChangeGroup" then
				MESSAGEMAN:Broadcast("OpenGroupJumper")
				t.WheelWithFocus = get_GroupJumper()

			elseif chosen == "Title" or chosen == "Artist" then
				t.LetterJumperMode = chosen
				MESSAGEMAN:Broadcast("OpenLetterJumper", { mode = chosen })
				t.WheelWithFocus = get_LetterJumper()

			elseif chosen == "Meter" then
				MESSAGEMAN:Broadcast("OpenMeterJumper")
				t.WheelWithFocus = get_MeterJumper()

			else
				-- Popular / Recent: apply directly.
				ApplySort(chosen, t.CurrentGroup)
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
			OpenSortMenu()
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeGroup", Player=event.PlayerNumber})
		end

	--------------------------------------------------------------
	-- LetterJumper (# + A-Z coverflow after picking Title or Artist)
	--------------------------------------------------------------
	elseif t.WheelWithFocus == get_LetterJumper() then
		if event.GameButton == "MenuRight" then
			LetterWheel:scroll_by_amount(1)
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})

		elseif event.GameButton == "MenuLeft" then
			LetterWheel:scroll_by_amount(-1)
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})

		elseif event.GameButton == "Start" then
			local letter = LetterWheel:get_info_at_focus_pos()
			if letter then
				ApplySort(t.LetterJumperMode, t.CurrentGroup)
				JumpToFirstMatch( LetterMatcher(t.LetterJumperMode, letter) )
			end
			MESSAGEMAN:Broadcast("CloseLetterJumper")
			MESSAGEMAN:Broadcast("PlaySFX", {Action="Start", Player=event.PlayerNumber})
			t.WheelWithFocus = SongWheel

		elseif event.GameButton == "Select" then
			MESSAGEMAN:Broadcast("CloseLetterJumper")
			OpenSortMenu()
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeGroup", Player=event.PlayerNumber})
		end

	--------------------------------------------------------------
	-- MeterJumper (meter-number coverflow after picking By Meter)
	--------------------------------------------------------------
	elseif t.WheelWithFocus == get_MeterJumper() then
		if event.GameButton == "MenuRight" then
			MeterWheel:scroll_by_amount(1)
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})

		elseif event.GameButton == "MenuLeft" then
			MeterWheel:scroll_by_amount(-1)
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})

		elseif event.GameButton == "Start" then
			local meter = MeterWheel:get_info_at_focus_pos()
			if meter then
				ApplySort("Meter", t.CurrentGroup)
				JumpToFirstMatch( MeterMatcher(meter) )
			end
			MESSAGEMAN:Broadcast("CloseMeterJumper")
			MESSAGEMAN:Broadcast("PlaySFX", {Action="Start", Player=event.PlayerNumber})
			t.WheelWithFocus = SongWheel

		elseif event.GameButton == "Select" then
			MESSAGEMAN:Broadcast("CloseMeterJumper")
			OpenSortMenu()
			MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeGroup", Player=event.PlayerNumber})
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
				if row_def.Name == "Chart" then
					BroadcastGameplayDemoDifficulty(event.PlayerNumber, "ChartScroll")
				end
				if row_def.Name == "Speed" then
					BroadcastGameplayDemoSpeed(event.PlayerNumber, "SpeedScroll")
				end
			end

		elseif event.GameButton == "MenuLeft" then
			if has_row then
				OptionsWheel[event.PlayerNumber][index]:scroll_by_amount(-1)
				MESSAGEMAN:Broadcast("PlaySFX", {Action="ChangeSong", Player=event.PlayerNumber})
				if row_def.Name == "Chart" then
					BroadcastGameplayDemoDifficulty(event.PlayerNumber, "ChartScroll")
				end
				if row_def.Name == "Speed" then
					BroadcastGameplayDemoSpeed(event.PlayerNumber, "SpeedScroll")
				end
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
				if ChartRowIndex and index == ChartRowIndex then
					BroadcastGameplayDemoDifficulty(event.PlayerNumber, "ChartSaved")
					RefreshAutoSpeedForPlayer(event.PlayerNumber)
				end
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
				local new_row = OptionRows[index]
				if new_row and new_row.Name == "Chart" then
					BroadcastGameplayDemoDifficulty(event.PlayerNumber, "ChartRowFocus")
				end
				if new_row and new_row.Name == "Speed" then
					BroadcastGameplayDemoSpeed(event.PlayerNumber, "SpeedRowFocus")
				end
			end

		elseif event.GameButton == "Select" then
			t.CancelSongChoice()
		end
	end

	return false
end

return t
