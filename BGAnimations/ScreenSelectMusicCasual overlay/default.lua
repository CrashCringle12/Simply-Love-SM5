-- default.lua for ScreenSelectMusicCasual (horizontal redesign).
--
-- Top-level composer.  Setup.lua does the data prep; this file wires the
-- visual actors + the wheels shared between subsystems.
--
-- Structure:
--   Base HUD (always visible)
--     Header, MusicWheel, Player panes, Footer, SoundEffects
--
--   Overlays (hidden until opened)
--     SortMenu     (opened by Select on the wheel)
--     GroupJumper  (sub-view of SortMenu, opened via "Change Group")
--
--   Modal (hidden until Start on the wheel)
--     PlayerOptionsShared + per-player OptionsWheels + StartButton,
--     all wrapped in a single fade-controlled ActorFrame.
--
-- Wheels owned here (all sick_wheel_mt instances) and passed via args:
--   SongWheel   -> MusicWheel + Input
--   GroupWheel  -> GroupJumper + Input
--   OptionsWheel[pn] and OptionsWheel[pn][i] come from Setup.lua
---------------------------------------------------------------------------
local setup = LoadActor("./Setup.lua")

if setup == nil then
	return LoadActor(THEME:GetPathB("ScreenSelectMusicCasual", "overlay/NoValidSongs.lua"))
end

---------------------------------------------------------------------------
local SongWheel    = setmetatable({}, sick_wheel_mt)
local GroupWheel   = setmetatable({}, sick_wheel_mt)
local OptionsWheel = setup.OptionsWheel
local OptionRows   = setup.OptionRows

local song_list, focus_index = setup.GetSongList(setup.InitialSortMode, setup.InitialGroup)

local row = setup.row
local col = setup.col

---------------------------------------------------------------------------
-- Modal panel geometry
local PANEL_W        = WideScale(300, 400)
local PANEL_H        = 340
local PANEL_MARGIN_X = 16
local PANEL_CY       = _screen.cy + 10

local panel_geom = {
	w     = PANEL_W,
	h     = PANEL_H,
	cy    = PANEL_CY,
	p1_cx = PANEL_MARGIN_X + PANEL_W/2,
	p2_cx = _screen.w - PANEL_MARGIN_X - PANEL_W/2,
}

local ITEM_ROW_Y = {
	[1] = PANEL_CY - 92,
	[2] = PANEL_CY + 8,
}

---------------------------------------------------------------------------
-- Input handler.  Receives references to all wheels + overlay actors so
-- its state machine can drive them directly.
local params_for_input = {
	SongWheel    = SongWheel,
	GroupWheel   = GroupWheel,
	SortMenu     = nil,   -- filled from InitCommand
	GroupJumper  = nil,   -- filled from InitCommand
	OptionsWheel = OptionsWheel,
	OptionRows   = OptionRows,
	setup        = setup,
}
local Input = LoadActor("./Input.lua", params_for_input)

local optionrow_mt      = LoadActor("./OptionRowMT.lua")
local optionrow_item_mt = LoadActor("./OptionRowItemMT.lua")

---------------------------------------------------------------------------
local TransitionTime = 0.35

local t = Def.ActorFrame{
	InitCommand = function(self)
		params_for_input.SortMenu    = self:GetChild("SortMenu")
		params_for_input.GroupJumper = self:GetChild("GroupJumper")
		self:queuecommand("Capture")
	end,

	OnCommand = function(self)
		if PREFSMAN:GetPreference("MenuTimer") then self:queuecommand("Listen") end
	end,

	ListenCommand = function(self)
		local topscreen = SCREENMAN:GetTopScreen()
		local timer = topscreen:GetChild("Timer")
		local seconds = timer and timer:GetSeconds() or 999

		if not Input.AllPlayersAreAtLastRow() and seconds <= 0 then
			if Input.WheelWithFocus ~= OptionsWheel then
				setup.InitOptionRowsForSingleSong()
			end
			for player in ivalues(GAMESTATE:GetHumanPlayers()) do
				for i = 1, #OptionRows - 1 do
					local choice  = OptionsWheel[player][i]:get_info_at_focus_pos()
					local choices = OptionRows[i]:Choices()
					local values  = OptionRows[i].Values()
					OptionRows[i]:OnSave(player, choice, choices, values)
				end
			end
			topscreen:StartTransitioningScreen("SM_GoToNextScreen")
		else
			self:sleep(0.5):queuecommand("Listen")
		end
	end,

	CaptureCommand = function(self)
		SCREENMAN:GetTopScreen():AddInputCallback( Input.Handler )
		Input:Init()
		self:queuecommand("EnableInput")
	end,

	CodeMessageCommand = function(self, params)
		if params.Name == "Exit" then
			if PREFSMAN:GetPreference("EventMode") then
				SCREENMAN:GetTopScreen():SetNextScreenName( Branch.SSMCancel() ):StartTransitioningScreen("SM_GoToNextScreen")
			else
				if SL.Global.Stages.PlayedThisGame == 0 then
					SL.Global.GameMode = "ITG"
					SetGameModePreferences()
					THEME:ReloadMetrics()
					SCREENMAN:GetTopScreen():SetNextScreenName("ScreenReloadSSM"):StartTransitioningScreen("SM_GoToNextScreen")
				end
			end
		end
		if params.Name == "CancelSingleSong" then
			if Input.WheelWithFocus ~= OptionsWheel then return end
			Input.CancelSongChoice()
		end
	end,

	SwitchFocusToSongsMessageCommand      = function(self) self:sleep(TransitionTime):queuecommand("EnableInput") end,
	SwitchFocusToGroupsMessageCommand     = function(self) self:sleep(TransitionTime):queuecommand("EnableInput") end,
	SwitchFocusToSingleSongMessageCommand = function(self)
		setup.InitOptionRowsForSingleSong()
		self:sleep(TransitionTime):queuecommand("EnableInput")
	end,
	EnableInputCommand = function(self) Input.Enabled = true end,

	-------------------------------------------------------------
	-- Base HUD
	-------------------------------------------------------------
	LoadActor("./Header.lua"),

	LoadActor("./MusicWheel/default.lua", {
		SongWheel   = SongWheel,
		setup       = setup,
		song_list   = song_list,
		focus_index = focus_index,
	}),

	LoadActor("./PlayerPane/default.lua", { player = PLAYER_1 }),
	LoadActor("./PlayerPane/default.lua", { player = PLAYER_2 }),

	LoadActor("./FooterHelpText.lua"),

	-- Overlays (SortMenu + GroupJumper).  Loaded here so their child
	-- position is above the wheel/panes in draw order.  Both are
	-- hidden until an OpenSortMenu / OpenGroupJumper broadcast fires.
	LoadActor("./SortMenu/default.lua",    { setup = setup }),
	LoadActor("./GroupJumper/default.lua", { setup = setup, group_wheel = GroupWheel }),

	LoadActor("./SoundEffects.lua"),
}

-- Now that params_for_input has the wheel refs, thread GroupWheel too.
-- (SortMenu/GroupJumper actors are set in InitCommand via GetChild.)
params_for_input.GroupWheel = GroupWheel

---------------------------------------------------------------------------
-- Modal wrapper (single AF whose diffusealpha follows SwitchFocus*)
local modal_af = Def.ActorFrame{
	Name = "Modal",
	InitCommand = function(self) self:diffusealpha(0) end,

	SwitchFocusToSingleSongMessageCommand = function(self)
		self:stoptweening():sleep(0.15):linear(0.2):diffusealpha(1)
	end,
	SwitchFocusToSongsMessageCommand  = function(self) self:stoptweening():linear(0.15):diffusealpha(0) end,
	SwitchFocusToGroupsMessageCommand = function(self) self:stoptweening():linear(0.15):diffusealpha(0) end,
	SingleSongCanceledMessageCommand  = function(self) self:stoptweening():linear(0.15):diffusealpha(0) end,

	LoadActor("./PlayerOptionsShared.lua", { row, col, Input, panel_geom }),
}

for pn in ivalues(PlayerNumber) do
	local pn_short = ToEnumShortString(pn)
	local panel_cx = (pn == PLAYER_1) and panel_geom.p1_cx or panel_geom.p2_cx

	local player_af = Def.ActorFrame{
		Name = "ModalPlayer_" .. pn_short,
		InitCommand = function(self)
			self:visible( GAMESTATE:IsHumanPlayer(pn) )
		end,
		PlayerJoinedMessageCommand = function(self, params)
			if params.Player == pn then self:visible(true) end
		end,
		PlayerUnjoinedMessageCommand = function(self, params)
			if params.Player == pn then self:visible(false) end
		end,

		OptionsWheel[pn]:create_actors(
			"OptionsWheel" .. pn_short,
			#OptionRows,
			optionrow_mt,
			panel_cx,
			PANEL_CY
		),
	}

	for i = 1, #OptionRows do
		local item_y = ITEM_ROW_Y[i]
		if item_y then
			local item_wheel_af = OptionsWheel[pn][i]:create_actors(
				pn_short .. "OptionWheel" .. i,
				3,
				optionrow_item_mt,
				panel_cx,
				item_y
			)
			OptionsWheel[pn][i].focus_pos = 2
			player_af[#player_af+1] = item_wheel_af
		end
	end

	modal_af[#modal_af+1] = player_af
end

modal_af[#modal_af+1] = LoadActor("./StartButton.lua", { panel_geom = panel_geom })

t[#t+1] = modal_af

return t
