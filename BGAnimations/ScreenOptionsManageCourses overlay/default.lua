-- ScreenOptionsManageCourses overlay (Simply Love)
--
-- Layout:
--   * Header with current StepsType+Difficulty cycle hint
--   * Sick_wheel of courses on the left
--   * Right-side preview panel (title / entries / step counts)
--   * Action tab strip at the bottom with "New Course" reachable as the
--     final tab
--   * Hint bar at very bottom
--
-- Cab input model (MenuLeft / MenuRight / Start / Select; Select == Back):
--   focus = "list":  Left/Right scroll wheel. Start opens selected.
--                    Select cycles StepsType (legacy "set next combination").
--                    Back exits screen.
--   focus = "tabs":  Left/Right cycles action tab. Start triggers tab.
--                    Back returns focus to list.

local af = Def.ActorFrame{}

-- ---------------------------------------------------------------------------
-- Static UI strings
-- ---------------------------------------------------------------------------
local UI = {
	HeaderText          = "Manage Courses",
	NoCourses           = "(no courses)",
	NewCourseTab        = "New Course",
	BackTab             = "Back",
	EntriesFmt          = "%d entries",
	HintList            = "&MENULEFT;/&MENURIGHT; Browse   &START; Open   &SELECT; Cycle Type/Diff",
	HintListAtNew       = "&MENULEFT;/&MENURIGHT; Browse   &START; Create New   &SELECT; Back",
	HintTabs            = "&MENULEFT;/&MENURIGHT; Choose   &START; Confirm   &SELECT; Back",
	MaxReachedFmt       = "Maximum of %d courses reached. Delete one first.",
}

local TAB_OPEN = "open"
local TAB_NEW  = "new"
local TAB_BACK = "back"

local NUM_VISIBLE = 13
local ROW_HEIGHT  = 22
local WHEEL_W     = WideScale(330, 420)
local WHEEL_H     = NUM_VISIBLE * ROW_HEIGHT

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local state = {
	focus      = "list",
	tab_index  = 1,
	tabs       = { TAB_OPEN, TAB_NEW, TAB_BACK },
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function GetCourses()
	return ManageCourses.GetCourses() or {}
end

local function CurrentCourse()
	local courses = GetCourses()
	local idx     = ManageCourses.GetSelectedIndex()
	if idx >= 1 and idx <= #courses then return courses[idx] end
	return nil
end

local function CanCreate()
	return ManageCourses.CanCreateMore()
end

-- ---------------------------------------------------------------------------
-- Sick wheel
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
							:maxwidth((WHEEL_W * 0.65) / 0.8)
					end,
				},
				Def.BitmapText{
					Font = "Common Normal",
					InitCommand = function(s)
						self.count = s
						s:halign(1):zoom(0.7)
							:x(WHEEL_W / 2 - 12)
							:diffuse(color("#bbbbbb"))
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
				self.title:diffuse(color("#cccccc")):zoom(0.8)
			end
		end,

		set = function(self, info)
			self.info = info
			if not info then
				self.title:settext("")
				self.count:settext("")
				return
			end
			self.title:settext(info.name or "")
			if info.numEntries then
				self.count:settext(UI.EntriesFmt:format(info.numEntries))
			else
				self.count:settext("")
			end
		end,
	},
}

-- ---------------------------------------------------------------------------
-- Wheel refresh
-- ---------------------------------------------------------------------------
local current_rows = {}

local function RefreshWheel()
	local courses = GetCourses()
	current_rows = {}
	if #courses == 0 then
		current_rows = {{ name = UI.NoCourses, numEntries = nil, empty = true }}
	else
		for _, c in ipairs(courses) do
			current_rows[#current_rows + 1] = c
		end
	end
	local pos = ManageCourses.GetSelectedIndex()
	if pos < 1 then pos = 1 end
	if pos > #current_rows then pos = #current_rows end
	wheel:set_info_set(current_rows, pos)
end

-- ---------------------------------------------------------------------------
-- Header
-- ---------------------------------------------------------------------------
af[#af + 1] = Def.BitmapText{
	Font = "Common Header",
	Text = UI.HeaderText,
	InitCommand = function(self)
		self:xy(_screen.cx, 28):zoom(0.9):diffuse(Color.White)
	end,
}

local LAYOUT = {
	wheel_cx   = WideScale(180, 240),
	wheel_cy   = _screen.cy - 18,
	right_cx   = WideScale(490, 660),
	right_cy   = _screen.cy - 18,
	right_w    = WideScale(280, 320),
	tabs_y     = _screen.h - 56,
	tab_w      = WideScale(120, 140),
	tab_h      = 28,
	tab_gap    = 12,
	hint_y     = _screen.h - 18,
}

local tab_bg_inactive = color("#222a33")
local tab_bg_active   = color("#0a8cf2")
local panel_bg        = DarkUI() and color("#666666") or color("#333333")

-- ---------------------------------------------------------------------------
-- Wheel actor
-- ---------------------------------------------------------------------------
af[#af + 1] = Def.ActorFrame{
	InitCommand = function(self)
		self:xy(LAYOUT.wheel_cx, LAYOUT.wheel_cy)
	end,
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
	wheel:create_actors("CourseWheel", NUM_VISIBLE, wheel_item_mt, 0, 0),
}

-- ---------------------------------------------------------------------------
-- Right side preview
-- ---------------------------------------------------------------------------
local preview_title
local preview_subtitle
local preview_entries
local preview_steps
local preview_diff
local preview_path

af[#af + 1] = Def.ActorFrame{
	InitCommand = function(self)
		self:xy(LAYOUT.right_cx, LAYOUT.right_cy)
	end,
	Def.Quad{
		InitCommand = function(self)
			self:zoomto(LAYOUT.right_w, WHEEL_H + 12)
				:diffuse(panel_bg):diffusealpha(0.7)
		end,
	},
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			preview_title = self
			self:halign(0):valign(0)
				:xy(-LAYOUT.right_w / 2 + 14, -WHEEL_H / 2)
				:zoom(0.9):diffuse(Color.White)
				:maxwidth((LAYOUT.right_w - 28) / 0.9)
		end,
	},
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			preview_subtitle = self
			self:halign(0):valign(0)
				:xy(-LAYOUT.right_w / 2 + 14, -WHEEL_H / 2 + 22)
				:zoom(0.65):diffuse(color("#bbbbbb"))
				:maxwidth((LAYOUT.right_w - 28) / 0.65)
		end,
	},
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			preview_entries = self
			self:halign(0):valign(0)
				:xy(-LAYOUT.right_w / 2 + 14, -WHEEL_H / 2 + 58)
				:zoom(0.75):diffuse(color("#cccccc"))
		end,
	},
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			preview_steps = self
			self:halign(0):valign(0)
				:xy(-LAYOUT.right_w / 2 + 14, -WHEEL_H / 2 + 82)
				:zoom(0.75):diffuse(color("#cccccc"))
		end,
	},
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			preview_diff = self
			self:halign(0):valign(0)
				:xy(-LAYOUT.right_w / 2 + 14, -WHEEL_H / 2 + 104)
				:zoom(0.75):diffuse(color("#cccccc"))
		end,
	},
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			preview_path = self
			self:halign(0):valign(1)
				:xy(-LAYOUT.right_w / 2 + 14, WHEEL_H / 2 - 4)
				:zoom(0.55):diffuse(color("#888888"))
				:maxwidth((LAYOUT.right_w - 28) / 0.55)
		end,
	},
}

local function RefreshPreview()
	local c = CurrentCourse()
	if not c then
		preview_title:settext("")
		preview_subtitle:settext("")
		preview_entries:settext("")
		preview_steps:settext("")
		preview_diff:settext("")
		preview_path:settext("")
		return
	end
	preview_title:settext(c.name or "")
	preview_subtitle:settext(c.isMachineCourse and "(machine)" or "")
	preview_entries:settext(UI.EntriesFmt:format(c.numEntries or 0))
	preview_steps:settext("Type: " .. (ManageCourses.GetCurrentStepsType() or "-"))
	preview_diff:settext("Difficulty: " .. (ManageCourses.GetCurrentCourseDifficulty() or "-"))
	preview_path:settext(c.path or "")
end

-- ---------------------------------------------------------------------------
-- Tab strip
-- ---------------------------------------------------------------------------
local tab_records = {}

local function TabLabel(t)
	if t == TAB_OPEN then return "Open" end
	if t == TAB_NEW  then return UI.NewCourseTab end
	if t == TAB_BACK then return UI.BackTab end
	return t
end

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
				Text = TabLabel(t),
				InitCommand = function(self)
					rec.label = self
					self:zoom(0.75):diffuse(color("#cccccc"))
						:maxwidth((LAYOUT.tab_w - 8) / 0.75)
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
-- Hint bar
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
	if state.focus == "tabs" then
		hint_bmt:settext(UI.HintTabs)
	else
		hint_bmt:settext(UI.HintList)
	end
end

-- ---------------------------------------------------------------------------
-- Initial render
-- ---------------------------------------------------------------------------
af[#af + 1] = Def.Actor{
	OnCommand = function()
		RefreshWheel()
		RefreshPreview()
		RefreshTabs()
		RefreshHint()
	end,
}

-- ---------------------------------------------------------------------------
-- Broadcast handlers
-- ---------------------------------------------------------------------------
af.ManageCoursesListChangedMessageCommand = function(self)
	RefreshWheel()
	RefreshPreview()
end
af.ManageCoursesSelectionChangedMessageCommand = function(self)
	wheel:scroll_to_pos(ManageCourses.GetSelectedIndex())
	RefreshPreview()
end
af.ManageCoursesStepsTypeChangedMessageCommand = function(self)
	RefreshPreview()
end

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------
local function ScrollWheel(dir)
	if #current_rows == 0 then return end
	local pos = wheel.info_pos + wheel.focus_pos + dir
	if pos < 1 then pos = #current_rows end
	if pos > #current_rows then pos = 1 end
	if current_rows[1].empty then return end
	ManageCourses.SetSelectedIndex(pos)
end

local function OpenSelected()
	local c = CurrentCourse()
	if not c then return end
	ManageCourses.OpenSelectedCourse()
	SCREENMAN:SetNewScreen(ManageCourses.GetNextScreen())
end

local function CreateNew()
	if not CanCreate() then
		SCREENMAN:SystemMessage(UI.MaxReachedFmt:format(32))
		return
	end
	if ManageCourses.CreateNewCourse() then
		SCREENMAN:SetNewScreen(ManageCourses.GetCreateNewScreen())
	end
end

local function TriggerTab()
	local t = state.tabs[state.tab_index]
	if t == TAB_OPEN then OpenSelected()
	elseif t == TAB_NEW then CreateNew()
	elseif t == TAB_BACK then SCREENMAN:GetTopScreen():Cancel() end
end

local function InputHandler(event)
	if event.type == "InputEventType_Release" then return end
	local btn = event.GameButton

	if state.focus == "list" then
		if btn == "MenuLeft" then
			ScrollWheel(-1)
		elseif btn == "MenuRight" then
			ScrollWheel(1)
		elseif btn == "MenuUp" then
			state.focus = "tabs"
			RefreshTabs(); RefreshHint(); RefreshWheel()
		elseif btn == "MenuDown" then
			state.focus = "tabs"
			RefreshTabs(); RefreshHint(); RefreshWheel()
		elseif btn == "Start" then
			OpenSelected()
		elseif btn == "Select" then
			ManageCourses.CycleStepsType()
		elseif btn == "Back" then
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
		elseif btn == "Start" then
			TriggerTab()
		elseif btn == "Select" or btn == "Back" then
			state.focus = "list"
			RefreshTabs(); RefreshHint(); RefreshWheel()
		end
	end
end

af.OnCommand = function(self)
	SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
end

return af
