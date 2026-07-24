-- Setup.lua for the horizontal CasualMode music select redesign.
--
-- Responsibilities:
--   * Build a fully-pruned list of songs allowed in Casual Mode (respecting
--     CasualMaxMeter, LongVerSongSeconds, IsSongLocked, steps_type, and
--     the operator-configured group whitelist in Other/CasualMode-Groups.txt).
--   * Build a parallel list of allowed group names AND a lookup table mapping
--     each group name to the ordered song indices it contains, so the group
--     jumper can seek the wheel to a group boundary quickly.
--   * Expose a small state object for the current wheel view (sort mode +
--     optional current-group scope) and a GetSongList() helper the wheel uses
--     to (re)populate itself when the sort mode changes.
--   * Preserve the OptionsWheel / OptionRows contract used by the existing
--     per-player modal, since Step 5 will replace that visually but not
--     structurally.
--   * Determine the starting song (respects Other/CasualMode-DefaultSong.txt)
--     and the starting group scope for the wheel.
---------------------------------------------------------------------------

-- because no one wants "Invalid PlayMode 7"
GAMESTATE:SetCurrentPlayMode('PlayMode_Regular')

---------------------------------------------------------------------------
-- OptionsWheel / OptionRows plumbing.
-- The modal is unchanged in Step 1; we keep the old sick_wheel scaffolding
-- for it so default.lua's Start-flow keeps working while the new UI lands.

local OptionsWheel = {}
local OptionRows = LoadActor("./OptionRows.lua")

for player in ivalues( PlayerNumber ) do
	OptionsWheel[player] = setmetatable({disable_wrapping = true}, sick_wheel_mt)
	for i=1,#OptionRows do
		OptionsWheel[player][i] = setmetatable({}, sick_wheel_mt)
	end
end

-- kept for compatibility with the old modal geometry
local margin = { w = WideScale(54,72), h = 30 }
local numCols, numRows = 3, 5
local col = { how_many = numCols, w = (_screen.w/numCols) - margin.w }
local row = { how_many = numRows, h = ((_screen.h - (margin.h*(numRows-2))) / (numRows-2)) }

local InitOptionRowsForSingleSong = function()
	for pn in ivalues( PlayerNumber ) do
		OptionsWheel[pn]:set_info_set(OptionRows, 1)
		for i,rowdef in ipairs(OptionRows) do
			if rowdef.OnLoad then
				rowdef.OnLoad(OptionsWheel[pn][i], pn, rowdef:Choices(), rowdef.Values())
			end
		end
	end
end

---------------------------------------------------------------------------
-- steps_type filter (e.g. StepsType_Dance_Single) applied everywhere
local steps_type = GAMESTATE:GetCurrentStyle():GetStepsType()

---------------------------------------------------------------------------
-- helper: read a config txt (one entry per line) into an array of strings
local GetFileContents = function(path)
	local contents = ""
	if FILEMAN:DoesFileExist(path) then
		local file = RageFileUtil.CreateRageFile()
		if file:Open(path, 1) then contents = file:Read() end
		file:destroy()
	end
	local lines = {}
	for line in contents:gmatch("[^\r\n]+") do lines[#lines+1] = line end
	return lines
end

---------------------------------------------------------------------------
-- Is this a song we are allowed to show in Casual Mode?
-- Returns true only if at least one stepchart of the required steps_type
-- exists at meter <= CasualMaxMeter, and the song is otherwise playable.
local SongIsAllowed = function(song)
	if not song:HasStepsType(steps_type) then return false end
	if song:GetLastSecond() >= PREFSMAN:GetPreference("LongVerSongSeconds") then return false end
	if UNLOCKMAN:IsSongLocked(song) ~= 0 then return false end

	local maxMeter = ThemePrefs.Get("CasualMaxMeter")
	for steps in ivalues(song:GetStepsByStepsType(steps_type)) do
		if steps:GetMeter() <= maxMeter then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- Read Other/CasualMode-Groups.txt.  If empty / missing / all bad,
-- fall back to every group known to SM.
local ReadRawGroups = function()
	local path = THEME:GetCurrentThemeDirectory() .. "Other/CasualMode-Groups.txt"
	local preliminary_groups = GetFileContents(path)

	if preliminary_groups == nil or #preliminary_groups == 0 then
		return SONGMAN:GetSongGroupNames()
	end

	local groups = {}
	for prelim_group in ivalues(preliminary_groups) do
		if SONGMAN:DoesSongGroupExist( prelim_group ) then
			groups[#groups+1] = prelim_group
		end
	end
	if #groups > 0 then return groups end
	return SONGMAN:GetSongGroupNames()
end

---------------------------------------------------------------------------
-- Build the full allowed catalog: a flat song list + group name list + a
-- lookup mapping group name -> array of song indices in the flat list.
-- The flat list is ordered by group order first, then by SONGMAN's natural
-- in-group order.  Every group that has at least one allowed song is kept.
local BuildCatalog = function()
	local raw_groups = ReadRawGroups()

	local all_songs = {}
	local groups = {}
	local group_index = {}   -- group_name -> array of indices in all_songs

	for group in ivalues(raw_groups) do
		local indices = {}
		for song in ivalues(SONGMAN:GetSongsInGroup(group)) do
			if SongIsAllowed(song) then
				all_songs[#all_songs+1] = song
				indices[#indices+1] = #all_songs
			end
		end
		if #indices > 0 then
			groups[#groups+1] = group
			group_index[group] = indices
		end
	end

	-- If the whitelist yielded nothing usable, retry against every group.
	if #groups == 0 then
		for group in ivalues(SONGMAN:GetSongGroupNames()) do
			local indices = {}
			for song in ivalues(SONGMAN:GetSongsInGroup(group)) do
				if SongIsAllowed(song) then
					all_songs[#all_songs+1] = song
					indices[#indices+1] = #all_songs
				end
			end
			if #indices > 0 then
				groups[#groups+1] = group
				group_index[group] = indices
			end
		end
	end

	return all_songs, groups, group_index
end

local all_songs, groups, group_index = BuildCatalog()

-- If we STILL have nothing, default.lua will interpret nil as "no valid songs".
if #groups == 0 or #all_songs == 0 then return nil end

---------------------------------------------------------------------------
-- Determine the starting song.  Priorities:
--   1. GAMESTATE:GetCurrentSong() -- set on stage 2+, "Play Again" flow.
--   2. Other/CasualMode-DefaultSong.txt (one or more "Group/Song" entries;
--      picked at random if multiple valid ones are listed).
--   3. First allowed song of the first allowed group.
local GetDefaultSong = function()
	local path = THEME:GetCurrentThemeDirectory() .. "Other/CasualMode-DefaultSong.txt"
	local prelim = GetFileContents(path)
	if prelim and #prelim > 0 then
		local candidates = {}
		for entry in ivalues(prelim) do
			local group = entry:gsub("/.*", "")
			if SONGMAN:FindSong(entry) and group_index[group] then
				candidates[#candidates+1] = entry
			end
		end
		if #candidates >= 1 then
			local pick = candidates[math.random(1, #candidates)]
			local song = SONGMAN:FindSong(pick)
			if song and SongIsAllowed(song) then return song end
		end
	end
	-- fallback: first allowed song of the first allowed group
	return all_songs[ group_index[groups[1]][1] ]
end

local current_song = GAMESTATE:GetCurrentSong()
if current_song == nil or not SongIsAllowed(current_song) then
	current_song = GetDefaultSong()
	GAMESTATE:SetCurrentSong(current_song)
end

local initial_group = current_song:GetGroupName()
if not group_index[initial_group] then
	initial_group = groups[1]
end

---------------------------------------------------------------------------
-- Sort mode definitions.
-- Each entry has:
--   Name         : key (used by the wheel and SortMenu)
--   Scope        : "group" (wheel shows one group's songs) or "all" (flat)
--   SortFn(list) : mutates `list` in place with the desired ordering
--
-- SortMenu will surface all of these to the player.  When Scope=="group",
-- the wheel state also tracks which group is currently on-screen.

local Compare_Title = function(a, b)
	return a:GetDisplayMainTitle():lower() < b:GetDisplayMainTitle():lower()
end

local Compare_Artist = function(a, b)
	local aa = (a:GetDisplayArtist() or ""):lower()
	local bb = (b:GetDisplayArtist() or ""):lower()
	if aa == bb then return Compare_Title(a, b) end
	return aa < bb
end

-- Machine profile is the most reliable source for play counts on a cabinet.
-- If the machine profile doesn't have play data we quietly fall back to the
-- first joined player's profile.
local GetPlayCountSource = function()
	local machine = PROFILEMAN:GetMachineProfile()
	if machine then return machine end
	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		local p = PROFILEMAN:GetProfile(player)
		if p then return p end
	end
	return nil
end

local Compare_MostPlayed = function(a, b)
	local profile = GetPlayCountSource()
	local ap = profile and profile:GetSongNumTimesPlayed(a) or 0
	local bp = profile and profile:GetSongNumTimesPlayed(b) or 0
	if ap == bp then return Compare_Title(a, b) end
	return ap > bp
end

-- StepMania doesn't expose per-song "last played" as a first-class field on
-- Profile; the closest usable signal is high-score dates.  Best-effort: use
-- the newest high-score date for any chart of the song's steps_type; ties
-- fall back to title order.  Songs never played end up at the bottom.
local GetSongLastPlayedTimestamp = function(profile, song)
	if not profile or not song then return "" end
	local best = ""
	for steps in ivalues(song:GetStepsByStepsType(steps_type)) do
		local hsl = profile:GetHighScoreList(song, steps)
		if hsl then
			for hs in ivalues(hsl:GetHighScores()) do
				local d = hs:GetDate()
				if d and d > best then best = d end
			end
		end
	end
	return best
end

local Compare_RecentlyPlayed = function(a, b)
	local profile = GetPlayCountSource()
	local at = GetSongLastPlayedTimestamp(profile, a)
	local bt = GetSongLastPlayedTimestamp(profile, b)
	if at == bt then return Compare_Title(a, b) end
	return at > bt
end

local SortModes = {
	{ Name="Group",          Scope="group" },
	{ Name="Title",          Scope="all", SortFn=function(list) table.sort(list, Compare_Title) end },
	{ Name="Artist",         Scope="all", SortFn=function(list) table.sort(list, Compare_Artist) end },
	{ Name="MostPlayed",     Scope="all", SortFn=function(list) table.sort(list, Compare_MostPlayed) end },
	{ Name="RecentlyPlayed", Scope="all", SortFn=function(list) table.sort(list, Compare_RecentlyPlayed) end },
}

local SortModesByName = {}
for m in ivalues(SortModes) do SortModesByName[m.Name] = m end

---------------------------------------------------------------------------
-- GetSongList(sort_mode_name, group_name)
--
-- Returns:
--   list         : array of Song objects the wheel should render, in order
--   focus_index  : 1-based index of the currently-selected song within `list`
--                  (or 1 if the current song isn't present)
local GetSongList = function(sort_mode_name, group_name)
	local mode = SortModesByName[sort_mode_name] or SortModesByName["Group"]
	local list = {}

	if mode.Scope == "group" then
		local g = (group_name and group_index[group_name]) and group_name or initial_group
		for i in ivalues(group_index[g]) do
			list[#list+1] = all_songs[i]
		end
	else
		for i,song in ipairs(all_songs) do list[i] = song end
		if mode.SortFn then mode.SortFn(list) end
	end

	local cur = GAMESTATE:GetCurrentSong()
	local focus_index = 1
	if cur then
		for i,song in ipairs(list) do
			if song == cur then focus_index = i; break end
		end
	end
	return list, focus_index
end

---------------------------------------------------------------------------
return {
	steps_type                   = steps_type,

	-- catalog
	AllSongs                     = all_songs,
	Groups                       = groups,
	GroupIndex                   = group_index,

	-- initial state
	InitialGroup                 = initial_group,
	InitialSortMode              = "Group",

	-- sort machinery
	SortModes                    = SortModes,
	SortModesByName              = SortModesByName,
	GetSongList                  = GetSongList,

	-- modal plumbing preserved for now
	OptionsWheel                 = OptionsWheel,
	OptionRows                   = OptionRows,
	row                          = row,
	col                          = col,
	InitOptionRowsForSingleSong  = InitOptionRowsForSingleSong,
}
