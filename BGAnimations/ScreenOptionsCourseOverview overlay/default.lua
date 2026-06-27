-- ScreenOptionsCourseOverview overlay (Simply Love)
--
-- Layout:
--   * Big course title at the top
--   * Scrollable entries list on the left (Song + Difficulty/Meter)
--   * Action tab strip across the bottom (Play / Edit / Shuffle / Rename /
--     Delete / Save / Back)
--   * Hint bar
--
-- Cab input model:
--   focus = "list": Left/Right scroll entries. Up/Down moves to action tabs.
--   focus = "tabs": Left/Right cycles tab. Start triggers tab. Up/Down back
--                   to list. Select/Back returns to ManageCourses.

local af = Def.ActorFrame{}

local UI = {
	NoCourseText      = "(no course)",
	NoEntries         = "(no entries yet)",
	EntriesHeader     = "Entries",
	EntryFmt          = "%2d. %s",
	EntryMeterFmt     = "  [%d-%d]",
	EntryDiffFmt      = "  %s",
	EntrySecret       = "  (secret)",
	HintList          = "&MENULEFT;/&MENURIGHT; Scroll Entries   &MENUUP;/&MENUDOWN; Actions   &SELECT; Back",
	HintTabs          = "&MENULEFT;/&MENURIGHT; Choose   &START; Confirm   &MENUUP;/&MENUDOWN; Entries   &SELECT; Back",
	NamePrompt        = "Enter a name for the course.",
	NameError         = "Name is invalid.",
	NamePromptTooLong = "Name too long.",
	DeleteConfirm     = "This course will be lost permanently.\n\nContinue with delete?",
	NoOpEmpty         = "Course has no entries.",
	SavedMsg          = "Course saved.",
	DeletedMsg        = "Course deleted.",
}

local NUM_VISIBLE = 13
local ROW_HEIGHT  = 22
local WHEEL_W     = WideScale(420, 540)
local WHEEL_H     = NUM_VISIBLE * ROW_HEIGHT

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local function MakeTabs()
	return {
		{ id = "play",    label = "Play"   },
		{ id = "edit",    label = "Edit"   },
		{ id = "shuffle", label = "Shuffle" },
		{ id = "rename",  label = "Rename" },
		{ id = "delete",  label = "Delete" },
		{ id = "save",    label = "Save"   },
		{ id = "back",    label = "Back"   },
	}
end

local state = {
	focus     = "list",
	tab_index = 1,
	tabs      = MakeTabs(),
	wheel_pos = 1,
}

local function GetEntries() return CourseOverview.GetEntries() or {} end

-- ---------------------------------------------------------------------------
-- Sick wheel for entries
-- ---------------------------------------------------------------------------
local wheel = setmetatable({}, sick_wheel_mt)

local wheel_item_mt = {
	__index = {
		create_actors = function(self, name)
			self.name = name
			return Def.ActorFrame{
				Name = name,
				InitCommand = function(s) self.frame = s end,
				Def.Quad{
					InitCommand = function(s)
						self.bg = s
						s:zoomto(WHEEL_W - 8, ROW_HEIGHT - 2)
							:diffuse(color("#ffffff")):diffusealpha(0)
					end,
				},
				Def.BitmapText{
					Font = "Common Normal",
					InitCommand = function(s)
						self.title = s
						s:halign(0):zoom(0.8)
							:x(-WHEEL_W / 2 + 12)
							:maxwidth((WHEEL_W * 0.66) / 0.8)
					end,
				},
				Def.BitmapText{
					Font = "Common Normal",
					InitCommand = function(s)
						self.meta = s
						s:halign(1):zoom(0.7)
							:x(WHEEL_W / 2 - 12)
							:diffuse(color("#cccccc"))
					end,
				},
			}
		end,

		transform = function(self, item_index, num_items, has_focus)
			self.frame:finishtweening():linear(0.05)
			local offset = item_index - math.floor(num_items / 2) - 1
			self.frame:y(offset * ROW_HEIGHT)
			if has_focus and state.focus == "list" then
				self.bg:diffusealpha(0.25)
				self.title:diffuse(Color.White):zoom(0.85)
			else
				self.bg:diffusealpha(0)
				self.title:diffuse(color("#dddddd")):zoom(0.8)
			end
		end,

		set = function(self, info)
			self.info = info
			if not info then
				self.title:settext("")
				self.meta:settext("")
				return
			end
			local title = info.SongTitle or ""
			if info.IsSecret then title = "?????" end
			self.title:settext(UI.EntryFmt:format(info.Index or 0, title))
			local meta = ""
			if info.Difficulty and info.Difficulty ~= "" then
				meta = UI.EntryDiffFmt:format(info.Difficulty)
			elseif (info.LowMeter or 0) > 0 or (info.HighMeter or 0) > 0 then
				meta = UI.EntryMeterFmt:format(info.LowMeter or 0, info.HighMeter or 0)
			end
			self.meta:settext(meta)
		end,
	},
}

local current_rows = {}

local function RefreshWheel()
	local entries = GetEntries()
	current_rows = {}
	if #entries == 0 then
		current_rows = {{ SongTitle = UI.NoEntries, Index = 0, empty = true }}
	else
		for i, e in ipairs(entries) do
			e.Index = i
			current_rows[#current_rows + 1] = e
		end
	end
	if state.wheel_pos > #current_rows then state.wheel_pos = #current_rows end
	if state.wheel_pos < 1 then state.wheel_pos = 1 end
	wheel:set_info_set(current_rows, state.wheel_pos)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------
local LAYOUT = {
	title_y     = 36,
	subtitle_y  = 56,
	wheel_cx    = _screen.cx,
	wheel_cy    = _screen.cy - 4,
	tabs_y      = _screen.h - 56,
	tab_w       = WideScale(82, 100),
	tab_h       = 26,
	tab_gap     = 8,
	hint_y      = _screen.h - 18,
}

local panel_bg        = DarkUI() and color("#666666") or color("#333333")
local tab_bg_inactive = color("#222a33")
local tab_bg_active   = color("#0a8cf2")

-- ---------------------------------------------------------------------------
-- Header
-- ---------------------------------------------------------------------------
local title_bmt
local subtitle_bmt

af[#af + 1] = Def.BitmapText{
	Font = "Common Header",
	InitCommand = function(self)
		title_bmt = self
		self:xy(_screen.cx, LAYOUT.title_y):zoom(0.9):diffuse(Color.White)
			:maxwidth((_screen.w - 80) / 0.9)
	end,
}

af[#af + 1] = Def.BitmapText{
	Font = "Common Normal",
	InitCommand = function(self)
		subtitle_bmt = self
		self:xy(_screen.cx, LAYOUT.subtitle_y):zoom(0.65)
			:diffuse(color("#bbbbbb"))
			:maxwidth((_screen.w - 80) / 0.65)
	end,
}

local function RefreshHeader()
	if not CourseOverview.HasCourse() then
		title_bmt:settext(UI.NoCourseText)
		subtitle_bmt:settext("")
		return
	end
	title_bmt:settext(CourseOverview.GetTitle() or "")
	local secs = CourseOverview.GetTotalSeconds() or 0
	local stype = CourseOverview.GetStepsType() or "-"
	local diff = CourseOverview.GetCourseDifficulty() or "-"
	local sub = string.format(
		"%s   %s   %d entries   %d:%02d",
		stype, diff,
		CourseOverview.GetNumEntries() or 0,
		math.floor(secs / 60), math.floor(secs % 60))
	if CourseOverview.IsMachineCourse() then
		sub = sub .. "   (machine)"
	end
	subtitle_bmt:settext(sub)
end

-- ---------------------------------------------------------------------------
-- Entries wheel
-- ---------------------------------------------------------------------------
af[#af + 1] = Def.ActorFrame{
	InitCommand = function(self) self:xy(LAYOUT.wheel_cx, LAYOUT.wheel_cy) end,
	Def.Quad{
		InitCommand = function(self)
			self:zoomto(WHEEL_W, WHEEL_H + 12)
				:diffuse(panel_bg):diffusealpha(0.7)
		end,
	},
	Def.Quad{
		InitCommand = function(self)
			self:zoomto(WHEEL_W - 4, ROW_HEIGHT - 1)
				:diffuse(color("#0a8cf2")):diffusealpha(0.18)
		end,
	},
	wheel:create_actors("EntryWheel", NUM_VISIBLE, wheel_item_mt, 0, 0),
}

-- ---------------------------------------------------------------------------
-- Tab strip
-- ---------------------------------------------------------------------------
local tab_records = {}

local function TabsAF()
	local total_w = #state.tabs * LAYOUT.tab_w + (#state.tabs - 1) * LAYOUT.tab_gap
	local left = _screen.cx - total_w / 2 + LAYOUT.tab_w / 2
	local frame = Def.ActorFrame{
		InitCommand = function(self) self:y(LAYOUT.tabs_y) end,
	}
	for i, t in ipairs(state.tabs) do
		local rec = {}
		frame[#frame + 1] = Def.ActorFrame{
			InitCommand = function(self)
				self:x(left + (i - 1) * (LAYOUT.tab_w + LAYOUT.tab_gap))
			end,
			Def.Quad{
				InitCommand = function(self)
					rec.bg = self
					self:zoomto(LAYOUT.tab_w, LAYOUT.tab_h):diffuse(tab_bg_inactive)
				end,
			},
			Def.BitmapText{
				Font = "Common Normal",
				Text = t.label,
				InitCommand = function(self)
					rec.label = self
					self:zoom(0.75):diffuse(color("#cccccc"))
				end,
			},
		}
		tab_records[i] = rec
	end
	return frame
end

af[#af + 1] = TabsAF()

local function RefreshTabs()
	for i, rec in ipairs(tab_records) do
		local active = (state.focus == "tabs") and (i == state.tab_index)
		if active then
			rec.bg:diffuse(tab_bg_active)
			rec.label:diffuse(Color.White)
		else
			rec.bg:diffuse(tab_bg_inactive)
			rec.label:diffuse(color("#cccccc"))
		end
	end
end

-- ---------------------------------------------------------------------------
-- Hint
-- ---------------------------------------------------------------------------
local hint_bmt
af[#af + 1] = Def.BitmapText{
	Font = "Common Normal",
	InitCommand = function(self)
		hint_bmt = self
		self:xy(_screen.cx, LAYOUT.hint_y):zoom(0.6):diffuse(color("#bbbbbb"))
	end,
}

local function RefreshHint()
	hint_bmt:settext(state.focus == "tabs" and UI.HintTabs or UI.HintList)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
local function PromptForName()
	local settings = {
		Question = UI.NamePrompt,
		MaxInputLength = CourseOverview.GetMaxNameLength(),
		Validate = function(answer, errOut)
			local err = CourseOverview.ValidateName(answer)
			if err then return false, err end
			return true, ""
		end,
		OnOK = function(answer)
			local ok, errMsg = CourseOverview.Rename(answer)
			if not ok then
				SCREENMAN:SystemMessage(errMsg or UI.NameError)
			end
		end,
		OnCancel = function() end,
	}
	SCREENMAN:AddNewScreenToTop("ScreenTextEntry")
	SCREENMAN:GetTopScreen():Load(settings)
end

local function PromptDelete()
	local settings = {
		Text = UI.DeleteConfirm,
		Question = UI.DeleteConfirm,
		Answer = false,
		ButtonType = "PromptType_YesNo",
		OnYes = function()
			local ok, errMsg = CourseOverview.Delete()
			if ok then
				SCREENMAN:SystemMessage(UI.DeletedMsg)
				SCREENMAN:SetNewScreen(CourseOverview.GetPrevScreen())
			else
				SCREENMAN:SystemMessage(errMsg or "Delete failed.")
			end
		end,
		OnNo = function() end,
	}
	SCREENMAN:AddNewScreenToTop("ScreenPrompt")
	SCREENMAN:GetTopScreen():Load(settings)
end

local function DoSave()
	local ok, errMsg = CourseOverview.Save()
	if ok then
		SCREENMAN:SystemMessage(UI.SavedMsg)
		return
	end
	if errMsg == "NeedsName" then
		PromptForName()
		return
	end
	SCREENMAN:SystemMessage(errMsg or "Save failed.")
end

local function TriggerTab()
	local t = state.tabs[state.tab_index].id
	if t == "play" then
		if (CourseOverview.GetNumEntries() or 0) == 0 then
			SCREENMAN:SystemMessage(UI.NoOpEmpty)
			return
		end
		CourseOverview.Play()
	elseif t == "edit" then
		CourseOverview.Edit()
	elseif t == "shuffle" then
		CourseOverview.Shuffle()
	elseif t == "rename" then
		PromptForName()
	elseif t == "delete" then
		PromptDelete()
	elseif t == "save" then
		DoSave()
	elseif t == "back" then
		SCREENMAN:GetTopScreen():Cancel()
	end
end

-- ---------------------------------------------------------------------------
-- Broadcast handlers
-- ---------------------------------------------------------------------------
af.CourseOverviewCourseChangedMessageCommand = function()
	state.wheel_pos = 1
	RefreshHeader(); RefreshWheel()
end
af.CourseOverviewEntriesChangedMessageCommand = function()
	RefreshHeader(); RefreshWheel()
end
af.CourseOverviewSavedMessageCommand = function()
	RefreshHeader()
end
af.CourseOverviewDeletedMessageCommand = function() end

-- ---------------------------------------------------------------------------
-- Initial render
-- ---------------------------------------------------------------------------
af[#af + 1] = Def.Actor{
	OnCommand = function()
		RefreshHeader(); RefreshWheel(); RefreshTabs(); RefreshHint()
	end,
}

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------
local function ScrollWheelBy(dir)
	if #current_rows == 0 or current_rows[1].empty then return end
	local pos = wheel.info_pos + wheel.focus_pos + dir
	if pos < 1 then pos = #current_rows end
	if pos > #current_rows then pos = 1 end
	state.wheel_pos = pos
	wheel:scroll_to_pos(pos)
end

local function InputHandler(event)
	if event.type == "InputEventType_Release" then return end
	local btn = event.GameButton

	if state.focus == "list" then
		if btn == "MenuLeft" then ScrollWheelBy(-1)
		elseif btn == "MenuRight" then ScrollWheelBy(1)
		elseif btn == "MenuUp" or btn == "MenuDown" then
			state.focus = "tabs"
			RefreshTabs(); RefreshHint(); RefreshWheel()
		elseif btn == "Start" then
			-- Default to "Play" on Start from the entry list.
			for i, t in ipairs(state.tabs) do
				if t.id == "play" then state.tab_index = i; break end
			end
			TriggerTab()
		elseif btn == "Select" or btn == "Back" then
			SCREENMAN:GetTopScreen():Cancel()
		end
	elseif state.focus == "tabs" then
		if btn == "MenuLeft" then
			state.tab_index = state.tab_index - 1
			if state.tab_index < 1 then state.tab_index = #state.tabs end
			RefreshTabs()
		elseif btn == "MenuRight" then
			state.tab_index = state.tab_index + 1
			if state.tab_index > #state.tabs then state.tab_index = 1 end
			RefreshTabs()
		elseif btn == "MenuUp" or btn == "MenuDown" then
			state.focus = "list"
			RefreshTabs(); RefreshHint(); RefreshWheel()
		elseif btn == "Start" then TriggerTab()
		elseif btn == "Select" or btn == "Back" then
			SCREENMAN:GetTopScreen():Cancel()
		end
	end
end

af.OnCommand = function(self)
	SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
end

return af
