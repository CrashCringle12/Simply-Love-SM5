-- MusicWheel/default.lua
--
-- Composes the horizontal music wheel + all "song info block" widgets
-- rendered directly beneath it.
--
-- Vertical stack (relative offsets from WHEEL_Y):
--   -ITEM_H/2                top of jacket row
--   0                        center of jacket row  (SongWheel container)
--   +ITEM_H/2                bottom of jacket row
--   +ITEM_H/2 +24            TITLE
--   +ITEM_H/2 +46            Artist / duration / BPM
--   +ITEM_H/2 +72            Shared difficulty row (blocks)
--   +ITEM_H/2 +94             ... diff-name labels
--   +ITEM_H/2 +110            ... P1 / P2 activation markers
--   +ITEM_H/2 +128           PACK BANNER (small sprite)
--   +ITEM_H/2 +148           Pack name  |  N / M counter
--
-- Message contract:
--   ApplySortMode { mode, group }
--     Broadcast by Input.lua when the SortMenu / GroupJumper commits a
--     new sort mode.  We call setup.GetSongList(mode, group) to build a
--     fresh song list and pipe it into SongWheel:set_info_set, then
--     force a BroadcastFocus refresh so every downstream widget updates.
---------------------------------------------------------------------------
local args = ...
local SongWheel   = args.SongWheel
local setup       = args.setup
local song_list   = args.song_list
local focus_index = args.focus_index or 1

---------------------------------------------------------------------------
local ITEM_W = WideScale(115, 130)
local ITEM_H = ITEM_W
local NUM_VISIBLE = 7

local wheel_config = {
	item_w      = ITEM_W,
	item_h      = ITEM_H,
	num_visible = NUM_VISIBLE,
}

local WheelItemMT = LoadActor("./WheelItemMT.lua", { wheel_config = wheel_config })

local WHEEL_Y = 40 + ITEM_H/2

---------------------------------------------------------------------------
-- Whenever the focused song changes we explicitly SetCurrentSteps for
-- every joined player.  Engine's SetCurrentSong does NOT touch player
-- steps; without this every per-player widget (step stats, high score,
-- P1/P2 activation markers) would render empty.
local UpdatePlayerSteps = function(song)
	if not song then return end
	local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()
	local max_meter  = ThemePrefs.Get("CasualMaxMeter")

	local allowed = {}
	for chart in ivalues(SongUtil.GetPlayableSteps(song)) do
		if chart:GetStepsType() == steps_type and chart:GetMeter() <= max_meter then
			allowed[#allowed+1] = chart
		end
	end
	if #allowed == 0 then return end

	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		local current       = GAMESTATE:GetCurrentSteps(player)
		local current_meter = current and current:GetMeter() or 1
		local current_diff  = current and current:GetDifficulty() or nil

		local match = nil
		if current_diff then
			for chart in ivalues(allowed) do
				if chart:GetDifficulty() == current_diff then match = chart; break end
			end
		end
		if not match then
			local best_delta = math.huge
			for chart in ivalues(allowed) do
				local d = math.abs(chart:GetMeter() - current_meter)
				if d < best_delta then best_delta = d; match = chart end
			end
		end
		if not match then match = allowed[1] end

		if match ~= current then
			GAMESTATE:SetCurrentSteps(player, match)
		end
	end
end

---------------------------------------------------------------------------
local last_broadcast_pos = -1

local BroadcastFocus = function(self)
	local info = SongWheel.info_set
	if not info or #info == 0 then return end
	local N   = #info
	local pos = ((SongWheel.info_pos - 1 + SongWheel.focus_pos) % N) + 1

	if pos == last_broadcast_pos then return end
	last_broadcast_pos = pos

	local song = info[pos]
	if song and GAMESTATE:GetCurrentSong() ~= song then
		GAMESTATE:SetCurrentSong(song)
		MESSAGEMAN:Broadcast("CurrentSongChanged", {song = song})
	end
	UpdatePlayerSteps(song)

	MESSAGEMAN:Broadcast("WheelPosChanged", { pos = pos, total = N, song = song })

	if self and self.preview_actor then
		self.preview_actor:stoptweening():sleep(0.25):queuecommand("PlayPreview")
	end
end

---------------------------------------------------------------------------
-- Info backdrop geometry
local INFO_BACK_W = _screen.w - 40
local INFO_BACK_H = 140
local INFO_BACK_Y = ITEM_H/2 + 83

local af = Def.ActorFrame{
	Name = "MusicWheel",
	InitCommand = function(self)
		self:xy(_screen.cx, WHEEL_Y)
		SongWheel.focus_pos = math.ceil(NUM_VISIBLE / 2)
		SongWheel:set_info_set(song_list, focus_index)
		self.preview_actor = self:GetChild("PreviewMusicHelper")
		BroadcastFocus(self)
		self:queuecommand("PollFocus")
	end,

	OnCommand = function(self)
		self:diffusealpha(0):linear(0.25):diffusealpha(1)
		-- Publish the initial sort mode so Header.lua's right-side label
		-- populates without needing an explicit user interaction.
		MESSAGEMAN:Broadcast("SortModeChanged", { mode = setup.InitialSortMode })
	end,

	PollFocusCommand = function(self)
		BroadcastFocus(self)
		self:sleep(0.05):queuecommand("PollFocus")
	end,

	ScrolledLeftMessageCommand = function(self)
		local arrows = self:GetChild("ArrowIndicators")
		if arrows then arrows:GetChild("LeftArrow"):playcommand("Press") end
	end,
	ScrolledRightMessageCommand = function(self)
		local arrows = self:GetChild("ArrowIndicators")
		if arrows then arrows:GetChild("RightArrow"):playcommand("Press") end
	end,

	---------------------------------------------------------------------
	-- Sort mode changed.  Rebuild SongWheel from setup.GetSongList and
	-- push the new focus into every downstream widget.  Called when the
	-- SortMenu picks a non-Group sort, or when GroupJumper commits a
	-- new group.
	ApplySortModeMessageCommand = function(self, params)
		if not params then return end
		local list, focus = setup.GetSongList(params.mode, params.group)
		SongWheel:set_info_set(list, focus)
		last_broadcast_pos = -1   -- force refresh
		BroadcastFocus(self)
	end,

	Def.Actor{
		Name = "PreviewMusicHelper",
		PlayPreviewCommand = function(self)
			if play_sample_music then play_sample_music() end
		end,
		WheelSongCommittedMessageCommand = function(self)
			if stop_music then stop_music() end
		end,
	},

	-- Info backdrop
	Def.Quad{
		Name = "InfoBackdrop",
		InitCommand = function(self)
			self:xy(0, INFO_BACK_Y)
				:zoomto(INFO_BACK_W, INFO_BACK_H)
				:diffuse(color("#0a0f13")):diffusealpha(0.72)
		end,
	},
	Def.Quad{
		Name = "InfoBackdropAccent",
		InitCommand = function(self)
			self:xy(0, INFO_BACK_Y + INFO_BACK_H/2 - 1)
				:zoomto(INFO_BACK_W - 8, 2)
				:diffuse( GetCurrentColor() ):diffusealpha(0.85)
		end,
	},

	LoadActor("./CenterCard.lua",          { wheel_config = wheel_config }),
	SongWheel:create_actors("SongWheel", NUM_VISIBLE, WheelItemMT, 0, 0),
	LoadActor("./ArrowIndicators.lua",     { wheel_config = wheel_config }),

	LoadActor("./SongInfoBar.lua",         { wheel_config = wheel_config }),
	LoadActor("./SharedDifficultyRow.lua", { wheel_config = wheel_config }),
	LoadActor("./PackInfo.lua",            { wheel_config = wheel_config }),
}

return af
