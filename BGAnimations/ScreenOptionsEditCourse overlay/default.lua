-- ScreenOptionsEditCourse overlay (Simply Love)
--
-- Keyboard-first course editor. Single-screen with internal modes.
--
-- Modes:
--   "properties"   - course-level metadata
--   "entries"      - per-entry list (with hot keys for common ops)
--   "song_picker"  - pick a Fixed song (group → song)
--   "mod_chooser"  - curated mods picker
--   "attacks"      - timed attacks list
--   "songselect"   - SONGSELECT filter editor
--   "confirm_back" - unsaved-changes prompt
--
-- Global keys (any mode):
--   Tab          : switch Properties <-> Entries
--   Esc / Back   : back one level (or confirm leave if dirty)
--   F2 / Ctrl+S  : Save
--   F5           : Test Play
--
-- Properties mode:   Up/Down move row, Enter/Space edit, Left/Right toggle.
-- Entries mode:      Up/Down move row, Enter song picker, A add, D delete,
--                    Alt+Up/Alt+Down reorder, M mods, T attacks, F filter,
--                    S secret toggle, N nodifficult toggle, X duplicate.
-- Song picker:       Left pane groups, Right pane songs, letters jump.
-- Mod chooser:       Up/Down rows, Left/Right tabs, Space toggle, Enter apply.
-- Attacks editor:    Up/Down rows, Enter edit, A add, D delete.
-- SongSelect editor: Up/Down rows, Enter edit value.

local af = Def.ActorFrame{}

-- =========================================================================
-- Constants / colors
-- =========================================================================
local panel_bg     = DarkUI() and color("#666666") or color("#333333")
local hilite_color = color("#0a8cf2")
local dim_color    = color("#bbbbbb")
local accent_dim   = color("#cccccc")

local LAYOUT = {
	title_y    = 28,
	subtitle_y = 50,
	body_top   = 70,
	body_bot   = _screen.h - 60,
	hint_y     = _screen.h - 16,
	left_x     = WideScale(160, 220),
	right_x    = WideScale(490, 660),
	pane_w     = WideScale(300, 360),
}
LAYOUT.body_h  = LAYOUT.body_bot - LAYOUT.body_top
LAYOUT.body_cy = (LAYOUT.body_top + LAYOUT.body_bot) / 2

local ROW_H = 20

-- =========================================================================
-- State
-- =========================================================================
local state = {
	mode             = "properties",
	-- Properties pane
	prop_index       = 1,
	-- Entries pane
	entry_index      = 1,
	-- Song picker
	picker_focus     = "groups",  -- "groups" | "songs"
	picker_group     = nil,
	picker_group_idx = 1,
	picker_song_idx  = 1,
	-- Mod chooser
	mod_target_entry = 0,
	mod_cat_idx      = 1,
	mod_item_idx     = 1,
	mod_selected     = {},        -- set keyed by mod string
	-- Attacks editor
	atk_target_entry = 0,
	atk_index        = 1,
	-- SongSelect editor
	ss_target_entry  = 0,
	ss_index         = 1,
}

-- =========================================================================
-- Property descriptors
-- =========================================================================
local function CycleSelectorKind(forward)
	-- Used in entries mode to cycle the selector kind for the focused entry.
	local kinds = EditCourse.GetSelectorKinds()
	local current = "Fixed"
	if state.entry_index >= 1 then
		local e = EditCourse.GetEntry(state.entry_index)
		current = e.SelectorKind or "Fixed"
	end
	local found = 1
	for i, k in ipairs(kinds) do if k == current then found = i; break end end
	found = found + (forward and 1 or -1)
	if found < 1 then found = #kinds end
	if found > #kinds then found = 1 end
	EditCourse.SetEntrySelectorKind(state.entry_index, kinds[found])
end

local PROPS  -- forward-declared so onChange callbacks can refer to it later

local function PromptText(question, current, maxLen, onOK)
	local settings = {
		Question = question,
		InitialAnswer = current or "",
		MaxInputLength = maxLen or 256,
		OnOK = function(answer) onOK(answer) end,
		OnCancel = function() end,
	}
	SCREENMAN:AddNewScreenToTop("ScreenTextEntry")
	SCREENMAN:GetTopScreen():Load(settings)
end

local function PromptInt(question, current, onOK)
	PromptText(question, tostring(current or 0), 12, function(answer)
		local n = tonumber(answer)
		if n then onOK(math.floor(n)) end
	end)
end

local function PromptFloat(question, current, onOK)
	PromptText(question, tostring(current or 0), 16, function(answer)
		local f = tonumber(answer)
		if f then onOK(f) end
	end)
end

-- (Property descriptors are defined as functions returning the row table so
-- they read live values each refresh.)
local function BuildProps()
	local props = {
		{ label = "Title", value = EditCourse.GetTitle(),
		  edit = function()
			PromptText("Course title", EditCourse.GetTitle(), 64,
				function(a) EditCourse.SetTitle(a) end)
		  end },
		{ label = "Subtitle", value = EditCourse.GetSubtitle(),
		  edit = function()
			PromptText("Course subtitle", EditCourse.GetSubtitle(), 64,
				function(a) EditCourse.SetSubtitle(a) end)
		  end },
		{ label = "Scripter", value = EditCourse.GetScripter(),
		  edit = function()
			PromptText("Scripter / author", EditCourse.GetScripter(), 64,
				function(a) EditCourse.SetScripter(a) end)
		  end },
		{ label = "Description", value = EditCourse.GetDescription(),
		  edit = function()
			PromptText("Description", EditCourse.GetDescription(), 240,
				function(a) EditCourse.SetDescription(a) end)
		  end },
		{ label = "Repeat", value = tostring(EditCourse.GetRepeat()),
		  toggle = function() EditCourse.SetRepeat(not EditCourse.GetRepeat()) end },
		{ label = "Shuffle", value = tostring(EditCourse.GetShuffle()),
		  toggle = function() EditCourse.SetShuffle(not EditCourse.GetShuffle()) end },
		{ label = "Lives (-1 = bar life)", value = tostring(EditCourse.GetLives()),
		  edit = function()
			PromptInt("Lives (-1 for bar life)", EditCourse.GetLives(),
				function(n) EditCourse.SetLives(n) end)
		  end },
		{ label = "Goal seconds (0 = none)",
		  value = string.format("%.1f", EditCourse.GetGoalSeconds() or 0),
		  edit = function()
			PromptFloat("Goal time in seconds", EditCourse.GetGoalSeconds(),
				function(f) EditCourse.SetGoalSeconds(f) end)
		  end },
	}
	-- Custom meters per course difficulty.
	local cds = EditCourse.GetCourseDifficulties()
	for cdIndex, cdLabel in ipairs(cds) do
		local i = cdIndex - 1  -- 0-based Difficulty enum value
		props[#props + 1] = {
			label = "Custom meter: " .. cdLabel,
			value = tostring(EditCourse.GetCustomMeter(i)),
			edit = function()
				PromptInt("Meter for " .. cdLabel .. " (-1 = unset)",
					EditCourse.GetCustomMeter(i),
					function(n) EditCourse.SetCustomMeter(i, n) end)
			end,
		}
	end
	props[#props + 1] = {
		label = "Allowed styles",
		value = table.concat(EditCourse.GetStyles() or {}, ", "),
		edit = function()
			-- Cycle through available styles, adding/removing.
			local cur = {}
			for _, s in ipairs(EditCourse.GetStyles()) do cur[s] = true end
			local all = EditCourse.GetAvailableStyles()
			local choices = "Available: " .. table.concat(all, ", ")
				.. "\nEnter style to toggle (blank = clear all):"
			PromptText(choices, "", 64, function(answer)
				if answer == "" then
					for s in pairs(cur) do EditCourse.RemoveStyle(s) end
				else
					if cur[answer] then
						EditCourse.RemoveStyle(answer)
					else
						EditCourse.AddStyle(answer)
					end
				end
			end)
		end,
	}
	return props
end

-- =========================================================================
-- Header
-- =========================================================================
local title_bmt
local subtitle_bmt
local mode_bmt

af[#af + 1] = Def.BitmapText{
	Font = "Common Header",
	InitCommand = function(self)
		title_bmt = self
		self:xy(_screen.cx, LAYOUT.title_y):zoom(0.85):diffuse(Color.White)
			:maxwidth((_screen.w - 80) / 0.85)
	end,
}
af[#af + 1] = Def.BitmapText{
	Font = "Common Normal",
	InitCommand = function(self)
		subtitle_bmt = self
		self:xy(_screen.cx, LAYOUT.subtitle_y):zoom(0.6):diffuse(dim_color)
	end,
}
af[#af + 1] = Def.BitmapText{
	Font = "Common Normal",
	InitCommand = function(self)
		mode_bmt = self
		self:xy(_screen.cx, LAYOUT.subtitle_y + 16):zoom(0.6):diffuse(hilite_color)
	end,
}

local function RefreshHeader()
	local t = EditCourse.GetTitle()
	if t == "" or t == nil then t = "(Untitled)" end
	if EditCourse.IsDirty() then t = t .. " *" end
	title_bmt:settext(t)

	local n = EditCourse.GetEntryCount()
	subtitle_bmt:settext(string.format("%d entries", n))
	local labels = {
		properties   = "Properties pane",
		entries      = "Entries pane",
		song_picker  = "Song picker",
		mod_chooser  = "Mod chooser",
		attacks      = "Attacks editor",
		songselect   = "SongSelect filter",
		confirm_back = "Confirm",
	}
	mode_bmt:settext(labels[state.mode] or state.mode)
end

-- =========================================================================
-- Generic vertical list renderer (used by all modes)
-- =========================================================================
local function MakeListPane(x, w, max_rows, build_actor)
	-- build_actor(self) is called once to allocate child actors.
	-- Returns { frame, refresh(rows, focus_index) }
	local rows_text = {}
	local hi_quad
	local bg_quad
	local frame_actor
	local h = max_rows * ROW_H

	local frame = Def.ActorFrame{
		InitCommand = function(self)
			frame_actor = self
			self:xy(x, LAYOUT.body_cy)
		end,
		Def.Quad{
			InitCommand = function(self)
				bg_quad = self
				self:zoomto(w, h + 12)
					:diffuse(panel_bg):diffusealpha(0.7)
			end,
		},
		Def.Quad{
			InitCommand = function(self)
				hi_quad = self
				self:zoomto(w - 4, ROW_H - 1)
					:diffuse(hilite_color):diffusealpha(0)
			end,
		},
	}
	for i = 1, max_rows do
		local idx = i
		frame[#frame + 1] = Def.BitmapText{
			Font = "Common Normal",
			InitCommand = function(self)
				rows_text[idx] = self
				self:halign(0):zoom(0.7)
					:xy(-w / 2 + 10, (idx - (max_rows + 1) / 2) * ROW_H)
					:maxwidth((w - 20) / 0.7)
			end,
		}
	end

	local pane = { frame = frame, h = h }
	function pane:set_visible(v)
		if frame_actor then frame_actor:visible(v and true or false) end
	end
	function pane:refresh(rows, focus_index, focus_active)
		-- Center the focus row by computing scroll offset.
		local n = #rows
		local mid = math.floor(max_rows / 2) + 1
		local offset = focus_index - mid
		if offset < 0 then offset = 0 end
		if offset > n - max_rows then offset = math.max(0, n - max_rows) end
		for i = 1, max_rows do
			local r = rows[i + offset]
			if r then
				rows_text[i]:settext(r.text or "")
				local active = (i + offset == focus_index)
				rows_text[i]:diffuse(active and Color.White or accent_dim)
				rows_text[i]:zoom(active and 0.78 or 0.7)
				if r.color then rows_text[i]:diffuse(r.color) end
			else
				rows_text[i]:settext("")
			end
		end
		local hi_row = focus_index - offset
		if focus_active and rows[focus_index] then
			hi_quad:diffusealpha(0.25)
			hi_quad:y((hi_row - (max_rows + 1) / 2) * ROW_H)
		else
			hi_quad:diffusealpha(0)
		end
	end
	return pane
end

local props_pane    = MakeListPane(LAYOUT.left_x,  LAYOUT.pane_w, 18, nil)
local entries_pane  = MakeListPane(LAYOUT.right_x, LAYOUT.pane_w, 18, nil)
af[#af + 1] = props_pane.frame
af[#af + 1] = entries_pane.frame

-- Secondary pane (used for song picker right side, mod chooser right side,
-- attacks/songselect single-pane).
local aux_pane = MakeListPane(_screen.cx, LAYOUT.pane_w * 1.4, 18, nil)
af[#af + 1] = aux_pane.frame
local aux_left_pane = MakeListPane(_screen.cx - LAYOUT.pane_w * 0.75,
                                    LAYOUT.pane_w * 0.9, 18, nil)
af[#af + 1] = aux_left_pane.frame
local aux_right_pane = MakeListPane(_screen.cx + LAYOUT.pane_w * 0.75,
                                     LAYOUT.pane_w * 0.9, 18, nil)
af[#af + 1] = aux_right_pane.frame

local function HideAux()
	aux_pane:set_visible(false)
	aux_left_pane:set_visible(false)
	aux_right_pane:set_visible(false)
	aux_pane:refresh({}, 0, false)
	aux_left_pane:refresh({}, 0, false)
	aux_right_pane:refresh({}, 0, false)
end
local function HideMain()
	props_pane:set_visible(false)
	entries_pane:set_visible(false)
	props_pane:refresh({}, 0, false)
	entries_pane:refresh({}, 0, false)
end
local function ShowMain()
	props_pane:set_visible(true)
	entries_pane:set_visible(true)
end

-- =========================================================================
-- Mode renderers
-- =========================================================================
local function EntrySummary(i)
	local e = EditCourse.GetEntry(i)
	local label
	if e.SelectorKind == "Fixed" then
		label = e.SongTitle ~= "" and e.SongTitle or "(unset)"
		if e.SongGroup ~= "" then label = e.SongGroup .. " / " .. label end
	elseif e.SelectorKind == "PureRandom" then
		label = "* RANDOM *"
	elseif e.SelectorKind == "GroupRandom" then
		label = "* RANDOM from " .. (e.SongGroup ~= "" and e.SongGroup or "?") .. " *"
	elseif e.SelectorKind == "Best" then
		label = "BEST " .. e.ChooseIndex
	elseif e.SelectorKind == "Worst" then
		label = "WORST " .. e.ChooseIndex
	elseif e.SelectorKind == "GradeBest" then
		label = "GRADE BEST " .. e.ChooseIndex
	elseif e.SelectorKind == "GradeWorst" then
		label = "GRADE WORST " .. e.ChooseIndex
	elseif e.SelectorKind == "SongSelect" then
		label = "* FILTERED *"
	else
		label = e.SelectorKind or "?"
	end
	local meta = ""
	if e.Difficulty ~= "" then meta = meta .. " [" .. e.Difficulty .. "]"
	elseif (e.LowMeter or 0) > 0 or (e.HighMeter or 0) > 0 then
		meta = meta .. string.format(" [%d-%d]", e.LowMeter or 0, e.HighMeter or 0)
	end
	if e.Secret then meta = meta .. " (secret)" end
	if e.NoDifficult then meta = meta .. " (nodiff)" end
	if (e.Mods or "") ~= "" then meta = meta .. " {mods}" end
	if (e.NumAttacks or 0) > 0 then
		meta = meta .. string.format(" {%d atk}", e.NumAttacks)
	end
	return string.format("%2d. %s%s", i, label, meta)
end

local function RenderProperties()
	HideAux()
	ShowMain()
	local props = BuildProps()
	local prop_rows = {}
	for i, p in ipairs(props) do
		prop_rows[i] = { text = string.format("%-26s %s", p.label, p.value) }
	end
	if #prop_rows == 0 then prop_rows = {{ text = "(no properties)" }} end
	if state.prop_index > #prop_rows then state.prop_index = #prop_rows end
	if state.prop_index < 1 then state.prop_index = 1 end
	props_pane:refresh(prop_rows, state.prop_index, true)

	-- Show entry summaries on the right (read-only preview)
	local n = EditCourse.GetEntryCount()
	local entry_rows = {}
	for i = 1, n do entry_rows[i] = { text = EntrySummary(i) } end
	if #entry_rows == 0 then entry_rows = {{ text = "(no entries)" }} end
	entries_pane:refresh(entry_rows, state.entry_index, false)
end

local function RenderEntries()
	HideAux()
	ShowMain()
	-- Show properties on the left as a non-focused preview
	local props = BuildProps()
	local prop_rows = {}
	for i, p in ipairs(props) do
		prop_rows[i] = { text = string.format("%-26s %s", p.label, p.value) }
	end
	if #prop_rows == 0 then prop_rows = {{ text = "(no properties)" }} end
	props_pane:refresh(prop_rows, state.prop_index, false)

	local n = EditCourse.GetEntryCount()
	local entry_rows = {}
	for i = 1, n do entry_rows[i] = { text = EntrySummary(i) } end
	if #entry_rows == 0 then entry_rows = {{ text = "(no entries)" }} end
	if state.entry_index > #entry_rows then state.entry_index = #entry_rows end
	if state.entry_index < 1 then state.entry_index = 1 end
	entries_pane:refresh(entry_rows, state.entry_index, true)
end

-- Song picker -------------------------------------------------------------
local picker_cache = { groups = nil, songs = {} }

local function RenderSongPicker()
	HideMain()
	aux_left_pane:set_visible(true)
	aux_right_pane:set_visible(true)
	aux_pane:set_visible(false)
	if not picker_cache.groups then
		picker_cache.groups = EditCourse.GetAllGroups()
	end
	local groups = picker_cache.groups
	local group_rows = {}
	for i, g in ipairs(groups) do group_rows[i] = { text = g } end
	if #group_rows == 0 then group_rows = {{ text = "(no groups)" }} end
	aux_left_pane:refresh(group_rows, state.picker_group_idx,
		state.picker_focus == "groups")

	-- Resolve current group
	local g = groups[state.picker_group_idx]
	if g then
		if not picker_cache.songs[g] then
			picker_cache.songs[g] = EditCourse.GetSongsInGroup(g)
		end
		local songs = picker_cache.songs[g] or {}
		local song_rows = {}
		for i, s in ipairs(songs) do song_rows[i] = { text = s.Title or "?" } end
		if #song_rows == 0 then song_rows = {{ text = "(no songs)" }} end
		aux_right_pane:refresh(song_rows, state.picker_song_idx,
			state.picker_focus == "songs")
	else
		aux_right_pane:refresh({{ text = "(select a group)" }}, 0, false)
	end
	aux_pane:refresh({}, 0, false)
end

-- Mod chooser -------------------------------------------------------------
local mod_cats_cache

local function RenderModChooser()
	HideMain()
	aux_left_pane:set_visible(true)
	aux_right_pane:set_visible(true)
	aux_pane:set_visible(true)
	mod_cats_cache = mod_cats_cache or EditCourse.GetModCategories()
	local cats = mod_cats_cache
	if state.mod_cat_idx > #cats then state.mod_cat_idx = 1 end
	local cat_rows = {}
	for i, c in ipairs(cats) do cat_rows[i] = { text = c.Name } end
	aux_left_pane:refresh(cat_rows, state.mod_cat_idx, true)

	local cur = cats[state.mod_cat_idx]
	local mods = cur and cur.Mods or {}
	local mod_rows = {}
	for i, m in ipairs(mods) do
		mod_rows[i] = {
			text = (state.mod_selected[m] and "[x] " or "[ ] ") .. m,
		}
	end
	if state.mod_item_idx > #mod_rows then state.mod_item_idx = 1 end
	aux_right_pane:refresh(mod_rows, state.mod_item_idx, true)

	-- Bottom hint: current combined mod string preview
	local list = {}
	for m in pairs(state.mod_selected) do list[#list + 1] = m end
	table.sort(list)
	aux_pane:refresh({{ text = "Selected: " .. table.concat(list, ", ") }}, 1, false)
end

-- Attacks editor ---------------------------------------------------------
local function RenderAttacksEditor()
	HideMain()
	aux_pane:set_visible(true)
	aux_left_pane:set_visible(false)
	aux_right_pane:set_visible(false)
	local atks = EditCourse.GetEntryAttacks(state.atk_target_entry) or {}
	local rows = {}
	for i, a in ipairs(atks) do
		rows[i] = {
			text = string.format("%2d. t=%.2fs  L=%.2fs  %s",
				i, a.Start or 0, a.Length or 0, a.Mods or ""),
		}
	end
	if #rows == 0 then rows = {{ text = "(no attacks; press A to add)" }} end
	if state.atk_index > #rows then state.atk_index = #rows end
	if state.atk_index < 1 then state.atk_index = 1 end
	aux_pane:refresh(rows, state.atk_index, true)
	aux_left_pane:refresh({}, 0, false)
	aux_right_pane:refresh({}, 0, false)
end

-- SongSelect filter editor ----------------------------------------------
local SS_FIELDS = {
	"Titles", "Groups", "Artists", "Genres",
	"MinBPM", "MaxBPM", "MinDuration", "MaxDuration",
	"MinMeter", "MaxMeter", "Difficulties", "SortKind", "SortIndex",
}

local function RenderSongSelect()
	HideMain()
	aux_pane:set_visible(true)
	aux_left_pane:set_visible(false)
	aux_right_pane:set_visible(false)
	local v = EditCourse.GetEntrySongSelect(state.ss_target_entry)
	local rows = {}
	for i, f in ipairs(SS_FIELDS) do
		local val = v[f]
		if type(val) == "table" then val = table.concat(val, ", ")
		elseif type(val) == "number" then val = tostring(val)
		elseif val == nil then val = "" end
		rows[i] = { text = string.format("%-14s %s", f, val) }
	end
	if state.ss_index > #rows then state.ss_index = #rows end
	if state.ss_index < 1 then state.ss_index = 1 end
	aux_pane:refresh(rows, state.ss_index, true)
	aux_left_pane:refresh({}, 0, false)
	aux_right_pane:refresh({}, 0, false)
end

-- =========================================================================
-- Hint bar
-- =========================================================================
local hint_bmt
af[#af + 1] = Def.BitmapText{
	Font = "Common Normal",
	InitCommand = function(self)
		hint_bmt = self
		self:xy(_screen.cx, LAYOUT.hint_y):zoom(0.55):diffuse(dim_color)
	end,
}

local function RefreshHint()
	local h
	if state.mode == "properties" then
		h = "Tab Switch | Up/Down Move | Enter Edit | F2 Save | F5 Test | Esc Back"
	elseif state.mode == "entries" then
		h = "Tab Switch | Up/Down | Enter Pick Song | A Add | D Del | X Dup | M Mods | T Atk | F Filter | S Secret | N NoDiff | <>/-+ Difficulty | K Kind"
	elseif state.mode == "song_picker" then
		h = "Tab Pane | Up/Down | Enter Pick | Esc Cancel"
	elseif state.mode == "mod_chooser" then
		h = "Up/Down Mods | Left/Right Categories | Space Toggle | Enter Apply | Esc Cancel"
	elseif state.mode == "attacks" then
		h = "Up/Down | Enter Edit | A Add | D Del | Esc Back"
	elseif state.mode == "songselect" then
		h = "Up/Down | Enter Edit | Esc Back"
	elseif state.mode == "confirm_back" then
		h = "Y Discard & exit | N Cancel | S Save & exit"
	else
		h = ""
	end
	hint_bmt:settext(h)
end

-- =========================================================================
-- Mode transitions
-- =========================================================================
local function Render()
	RefreshHeader()
	if state.mode == "properties" then RenderProperties()
	elseif state.mode == "entries" then RenderEntries()
	elseif state.mode == "song_picker" then RenderSongPicker()
	elseif state.mode == "mod_chooser" then RenderModChooser()
	elseif state.mode == "attacks" then RenderAttacksEditor()
	elseif state.mode == "songselect" then RenderSongSelect()
	end
	RefreshHint()
end

local function EnterSongPicker(entry_idx)
	state.entry_index = entry_idx
	state.mode = "song_picker"
	state.picker_focus = "groups"
	Render()
end

local function EnterModChooser(entry_idx)
	state.mod_target_entry = entry_idx
	state.mode = "mod_chooser"
	state.mod_cat_idx = 1
	state.mod_item_idx = 1
	-- Pre-populate selection from current entry mods string
	state.mod_selected = {}
	local e = EditCourse.GetEntry(entry_idx)
	for _, m in ipairs(EditCourse.ParseModList(e.Mods or "")) do
		state.mod_selected[m] = true
	end
	Render()
end

local function EnterAttacks(entry_idx)
	state.atk_target_entry = entry_idx
	state.mode = "attacks"
	state.atk_index = 1
	Render()
end

local function EnterSongSelect(entry_idx)
	state.ss_target_entry = entry_idx
	state.mode = "songselect"
	state.ss_index = 1
	Render()
end

local function ApplyChosenMods()
	local list = {}
	for m in pairs(state.mod_selected) do list[#list + 1] = m end
	table.sort(list)
	EditCourse.SetEntryMods(state.mod_target_entry,
		EditCourse.JoinModList(list))
	state.mode = "entries"
	Render()
end

-- =========================================================================
-- Save / test / back logic
-- =========================================================================
local function PromptCourseName(after)
	PromptText("Enter a name for the course",
		EditCourse.GetTitle(), EditCourse.GetMaxNameLength(),
		function(answer)
			local err = EditCourse.ValidateName(answer)
			if err then
				SCREENMAN:SystemMessage(err)
				return
			end
			local ok, errMsg = EditCourse.Rename(answer)
			if not ok then
				SCREENMAN:SystemMessage(errMsg or "Save failed")
				return
			end
			SCREENMAN:SystemMessage("Course saved.")
			if after then after() end
		end)
end

local function DoSave(after)
	local ok, errMsg = EditCourse.Save()
	if ok then
		SCREENMAN:SystemMessage("Course saved.")
		if after then after() end
		return
	end
	if errMsg == "NeedsName" then
		PromptCourseName(after)
		return
	end
	SCREENMAN:SystemMessage(errMsg or "Save failed")
end

local function DoTestPlay()
	if EditCourse.GetEntryCount() == 0 then
		SCREENMAN:SystemMessage("Add an entry first.")
		return
	end
	EditCourse.TestPlay()
end

local function DoBack()
	if not EditCourse.IsDirty() then
		EditCourse.ReturnToPrev()
		return
	end
	state.mode = "confirm_back"
	Render()
end

-- =========================================================================
-- Editing helpers for entries mode
-- =========================================================================
local function CycleDifficulty(forward)
	local diffs = EditCourse.GetDifficulties()
	-- Include "(unset)" as a virtual first entry.
	table.insert(diffs, 1, "")
	local e = EditCourse.GetEntry(state.entry_index)
	local idx = 1
	for i, d in ipairs(diffs) do
		if d == e.Difficulty then idx = i; break end
	end
	idx = idx + (forward and 1 or -1)
	if idx < 1 then idx = #diffs end
	if idx > #diffs then idx = 1 end
	EditCourse.SetEntryDifficulty(state.entry_index, diffs[idx])
end

local function AdjustMeter(low_delta, high_delta)
	local e = EditCourse.GetEntry(state.entry_index)
	local lo = (e.LowMeter or 0) + low_delta
	local hi = (e.HighMeter or 0) + high_delta
	if lo < 0 then lo = 0 end
	if hi < 0 then hi = 0 end
	EditCourse.SetEntryMeterRange(state.entry_index, lo, hi)
end

local function AddEntry()
	local idx = EditCourse.AddEntry()
	if idx > 0 then state.entry_index = idx end
end

local function DeleteEntry()
	if EditCourse.GetEntryCount() <= 1 then
		SCREENMAN:SystemMessage("Cannot delete last entry.")
		return
	end
	if EditCourse.RemoveEntry(state.entry_index) then
		if state.entry_index > EditCourse.GetEntryCount() then
			state.entry_index = EditCourse.GetEntryCount()
		end
	end
end

local function DuplicateEntry()
	local idx = EditCourse.DuplicateEntry(state.entry_index)
	if idx > 0 then state.entry_index = idx end
end

local function MoveEntry(dir)
	local n = EditCourse.GetEntryCount()
	local to = state.entry_index + dir
	if to < 1 or to > n then return end
	if EditCourse.MoveEntry(state.entry_index, to) then
		state.entry_index = to
	end
end

local function PickedSong(group, title)
	EditCourse.SetEntrySelectorKind(state.entry_index, "Fixed")
	EditCourse.SetEntrySong(state.entry_index, group, title)
	state.mode = "entries"
	Render()
end

-- =========================================================================
-- Broadcast handlers
-- =========================================================================
af.EditCoursePropertyChangedMessageCommand = function() Render() end
af.EditCourseEntriesChangedMessageCommand  = function() Render() end
af.EditCourseEntryChangedMessageCommand    = function() Render() end
af.EditCourseSelectedEntryChangedMessageCommand = function() Render() end
af.EditCourseDirtyChangedMessageCommand    = function() RefreshHeader() end
af.EditCourseSavedMessageCommand           = function() RefreshHeader() end

-- =========================================================================
-- Initial render
-- =========================================================================
af[#af + 1] = Def.Actor{
	OnCommand = function() Render() end,
}

-- =========================================================================
-- Input
-- =========================================================================
local function HandleProperties(event)
	local btn = event.GameButton
	local props = BuildProps()
	if event.DeviceInput.button == "DeviceButton_up" or btn == "MenuUp" then
		state.prop_index = state.prop_index - 1
		if state.prop_index < 1 then state.prop_index = #props end
		Render()
	elseif event.DeviceInput.button == "DeviceButton_down" or btn == "MenuDown" then
		state.prop_index = state.prop_index + 1
		if state.prop_index > #props then state.prop_index = 1 end
		Render()
	elseif btn == "MenuLeft" or btn == "MenuRight" then
		local row = props[state.prop_index]
		if row and row.toggle then row.toggle() end
	elseif btn == "Start" or event.DeviceInput.button == "DeviceButton_space" then
		local row = props[state.prop_index]
		if row then
			if row.toggle then row.toggle()
			elseif row.edit then row.edit() end
		end
	end
end

local function HandleEntries(event)
	local btn = event.GameButton
	local d   = event.DeviceInput.button
	local n   = EditCourse.GetEntryCount()

	if d == "DeviceButton_up" or btn == "MenuUp" then
		if n == 0 then return end
		state.entry_index = state.entry_index - 1
		if state.entry_index < 1 then state.entry_index = n end
		EditCourse.SetSelectedEntryIndex(state.entry_index)
	elseif d == "DeviceButton_down" or btn == "MenuDown" then
		if n == 0 then return end
		state.entry_index = state.entry_index + 1
		if state.entry_index > n then state.entry_index = 1 end
		EditCourse.SetSelectedEntryIndex(state.entry_index)
	elseif d == "DeviceButton_a" then AddEntry()
	elseif d == "DeviceButton_d" then DeleteEntry()
	elseif d == "DeviceButton_x" then DuplicateEntry()
	elseif d == "DeviceButton_m" then
		if n > 0 then EnterModChooser(state.entry_index) end
	elseif d == "DeviceButton_t" then
		if n > 0 then EnterAttacks(state.entry_index) end
	elseif d == "DeviceButton_f" then
		if n > 0 then EnterSongSelect(state.entry_index) end
	elseif d == "DeviceButton_s" then
		if n > 0 then
			local e = EditCourse.GetEntry(state.entry_index)
			EditCourse.SetEntrySecret(state.entry_index, not e.Secret)
		end
	elseif d == "DeviceButton_n" then
		if n > 0 then
			local e = EditCourse.GetEntry(state.entry_index)
			EditCourse.SetEntryNoDifficult(state.entry_index, not e.NoDifficult)
		end
	elseif d == "DeviceButton_k" then CycleSelectorKind(true)
	elseif d == "DeviceButton_,"      then CycleDifficulty(false)
	elseif d == "DeviceButton_."      then CycleDifficulty(true)
	elseif d == "DeviceButton_-"      then AdjustMeter(-1, -1)
	elseif d == "DeviceButton_="      then AdjustMeter(1, 1)
	elseif btn == "Start"             then
		if n > 0 then EnterSongPicker(state.entry_index) end
	end
end

local function HandleSongPicker(event)
	local btn = event.GameButton
	local d   = event.DeviceInput.button
	if not picker_cache.groups then return end
	local groups = picker_cache.groups

	if d == "DeviceButton_tab" then
		state.picker_focus = (state.picker_focus == "groups") and "songs" or "groups"
	elseif state.picker_focus == "groups" then
		if d == "DeviceButton_up" or btn == "MenuUp" then
			state.picker_group_idx = state.picker_group_idx - 1
			if state.picker_group_idx < 1 then state.picker_group_idx = #groups end
			state.picker_song_idx = 1
		elseif d == "DeviceButton_down" or btn == "MenuDown" then
			state.picker_group_idx = state.picker_group_idx + 1
			if state.picker_group_idx > #groups then state.picker_group_idx = 1 end
			state.picker_song_idx = 1
		elseif btn == "Start"
		   or d == "DeviceButton_enter"
		   or d == "DeviceButton_right" then
			state.picker_focus = "songs"
		end
	else
		local g = groups[state.picker_group_idx]
		local songs = picker_cache.songs[g] or {}
		if d == "DeviceButton_up" or btn == "MenuUp" then
			state.picker_song_idx = state.picker_song_idx - 1
			if state.picker_song_idx < 1 then state.picker_song_idx = #songs end
		elseif d == "DeviceButton_down" or btn == "MenuDown" then
			state.picker_song_idx = state.picker_song_idx + 1
			if state.picker_song_idx > #songs then state.picker_song_idx = 1 end
		elseif d == "DeviceButton_left" then
			state.picker_focus = "groups"
		elseif btn == "Start" or d == "DeviceButton_enter" then
			local s = songs[state.picker_song_idx]
			if s then PickedSong(s.Group, s.Title) end
		end
	end
end

local function HandleModChooser(event)
	local btn = event.GameButton
	local d   = event.DeviceInput.button
	local cats = mod_cats_cache or {}
	if d == "DeviceButton_left" or btn == "MenuLeft" then
		state.mod_cat_idx = state.mod_cat_idx - 1
		if state.mod_cat_idx < 1 then state.mod_cat_idx = #cats end
		state.mod_item_idx = 1
	elseif d == "DeviceButton_right" or btn == "MenuRight" then
		state.mod_cat_idx = state.mod_cat_idx + 1
		if state.mod_cat_idx > #cats then state.mod_cat_idx = 1 end
		state.mod_item_idx = 1
	elseif d == "DeviceButton_up" or btn == "MenuUp" then
		local mods = cats[state.mod_cat_idx] and cats[state.mod_cat_idx].Mods or {}
		state.mod_item_idx = state.mod_item_idx - 1
		if state.mod_item_idx < 1 then state.mod_item_idx = #mods end
	elseif d == "DeviceButton_down" or btn == "MenuDown" then
		local mods = cats[state.mod_cat_idx] and cats[state.mod_cat_idx].Mods or {}
		state.mod_item_idx = state.mod_item_idx + 1
		if state.mod_item_idx > #mods then state.mod_item_idx = 1 end
	elseif d == "DeviceButton_space" then
		local mods = cats[state.mod_cat_idx] and cats[state.mod_cat_idx].Mods or {}
		local m = mods[state.mod_item_idx]
		if m then
			if state.mod_selected[m] then state.mod_selected[m] = nil
			else state.mod_selected[m] = true end
		end
	elseif btn == "Start" or d == "DeviceButton_enter" then
		ApplyChosenMods()
	end
end

local function HandleAttacks(event)
	local btn = event.GameButton
	local d   = event.DeviceInput.button
	local atks = EditCourse.GetEntryAttacks(state.atk_target_entry) or {}

	if d == "DeviceButton_up" or btn == "MenuUp" then
		state.atk_index = state.atk_index - 1
		if state.atk_index < 1 then state.atk_index = math.max(1, #atks) end
	elseif d == "DeviceButton_down" or btn == "MenuDown" then
		state.atk_index = state.atk_index + 1
		if state.atk_index > #atks then state.atk_index = 1 end
	elseif d == "DeviceButton_a" then
		atks[#atks + 1] = { Start = 0, Length = 4, Mods = "" }
		EditCourse.SetEntryAttacks(state.atk_target_entry, atks)
		state.atk_index = #atks
	elseif d == "DeviceButton_d" then
		if atks[state.atk_index] then
			table.remove(atks, state.atk_index)
			EditCourse.SetEntryAttacks(state.atk_target_entry, atks)
			if state.atk_index > #atks then state.atk_index = math.max(1, #atks) end
		end
	elseif btn == "Start" or d == "DeviceButton_enter" then
		local a = atks[state.atk_index]
		if not a then return end
		PromptFloat("Attack start (seconds)", a.Start, function(f1)
			a.Start = f1
			PromptFloat("Attack length (seconds)", a.Length, function(f2)
				a.Length = f2
				PromptText("Attack mods", a.Mods, 240, function(s)
					a.Mods = s
					EditCourse.SetEntryAttacks(state.atk_target_entry, atks)
				end)
			end)
		end)
	end
end

local function HandleSongSelect(event)
	local btn = event.GameButton
	local d   = event.DeviceInput.button
	local v = EditCourse.GetEntrySongSelect(state.ss_target_entry)

	if d == "DeviceButton_up" or btn == "MenuUp" then
		state.ss_index = state.ss_index - 1
		if state.ss_index < 1 then state.ss_index = #SS_FIELDS end
	elseif d == "DeviceButton_down" or btn == "MenuDown" then
		state.ss_index = state.ss_index + 1
		if state.ss_index > #SS_FIELDS then state.ss_index = 1 end
	elseif btn == "Start" or d == "DeviceButton_enter" then
		local f = SS_FIELDS[state.ss_index]
		local cur = v[f]
		if type(cur) == "table" then
			PromptText(f .. " (comma-separated)",
				table.concat(cur, ", "), 240, function(answer)
				local list = {}
				for s in (answer .. ","):gmatch("([^,]+),") do
					s = s:match("^%s*(.-)%s*$")
					if s ~= "" then list[#list + 1] = s end
				end
				v[f] = list
				EditCourse.SetEntrySongSelect(state.ss_target_entry, v)
			end)
		elseif type(cur) == "number" or cur == nil then
			PromptFloat(f, cur or 0, function(n)
				v[f] = n
				EditCourse.SetEntrySongSelect(state.ss_target_entry, v)
			end)
		else
			PromptText(f, tostring(cur), 64, function(answer)
				v[f] = answer
				EditCourse.SetEntrySongSelect(state.ss_target_entry, v)
			end)
		end
	end
end

local function HandleConfirmBack(event)
	local d = event.DeviceInput.button
	if d == "DeviceButton_y" then
		EditCourse.MarkClean()
		EditCourse.ReturnToPrev()
	elseif d == "DeviceButton_n" or d == "DeviceButton_escape" then
		state.mode = "entries"; Render()
	elseif d == "DeviceButton_s" then
		DoSave(function() EditCourse.ReturnToPrev() end)
	end
end

local function InputHandler(event)
	if event.type == "InputEventType_Release" then return end
	local d   = event.DeviceInput.button
	local btn = event.GameButton

	-- Global keys (any mode):
	if d == "DeviceButton_F2" then
		DoSave()
		return
	elseif d == "DeviceButton_F5" then
		DoTestPlay()
		return
	elseif d == "DeviceButton_escape" or btn == "Back" or btn == "Select" then
		if state.mode == "properties" or state.mode == "entries" then
			DoBack()
		elseif state.mode == "song_picker"
		   or state.mode == "mod_chooser"
		   or state.mode == "attacks"
		   or state.mode == "songselect" then
			state.mode = "entries"; Render()
		elseif state.mode == "confirm_back" then
			state.mode = "entries"; Render()
		end
		return
	elseif d == "DeviceButton_tab"
	    and (state.mode == "properties" or state.mode == "entries") then
		state.mode = (state.mode == "properties") and "entries" or "properties"
		Render()
		return
	end

	if state.mode == "properties"   then HandleProperties(event)
	elseif state.mode == "entries"     then HandleEntries(event)
	elseif state.mode == "song_picker" then HandleSongPicker(event)
	elseif state.mode == "mod_chooser" then HandleModChooser(event)
	elseif state.mode == "attacks"     then HandleAttacks(event)
	elseif state.mode == "songselect"  then HandleSongSelect(event)
	elseif state.mode == "confirm_back" then HandleConfirmBack(event)
	end
	Render()
end

af.OnCommand = function(self)
	SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
end

return af
