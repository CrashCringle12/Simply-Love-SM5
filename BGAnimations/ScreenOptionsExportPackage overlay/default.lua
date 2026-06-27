-- ScreenOptionsExportPackage overlay (Simply Love)
--
-- Layout:
--   * Tab strip across the top (one tab per category)
--   * Bordered "wheel box" on the left listing items in the focused category
--     (with drill-in for Song groups)
--   * Right-side panel showing current selection + package metadata
--   * "Edit Info" and "Export Package" action buttons above/below the right panel,
--     reachable as the last entries in the tab strip
--   * Modal edit-info overlay (built in Lua so it works with cab keys only)
--   * Centered progress modal while a zip job is running
--
-- Cab input model (MenuLeft / MenuRight / Start / Select / Back; Select == Back):
--   focus = "tabs": Left/Right cycles tab index. Start enters list / opens edit /
--                   starts export. Back exits screen.
--   focus = "list": Left/Right scrolls wheel. Start toggles/drills. Back un-drills
--                   or returns focus to tabs.
--   focus = "edit": Modal panel. Left/Right cycles row. Start opens TextEntry.
--                   Back closes the overlay.

local af = Def.ActorFrame{}

-- ---------------------------------------------------------------------------
-- UI text (inlined; ScreenOptionsExportPackage strings did not resolve from
-- Languages/en.ini reliably during development)
-- ---------------------------------------------------------------------------

local UI = {
	HeaderText            = "",
	PackageContents       = "Package Contents",
	PackageInfo           = "Package Info",
	NothingSelected       = "(nothing selected)",
	Exporting             = "Exporting package...",
	ItemCountFmt          = "%d item(s)",
	AndNMoreFmt           = "...and %d more",
	GroupBackRow          = "..&MENULEFT; Back to groups",
	GroupSelectAllRow     = "[+] Select whole group",
	GroupDeselectAllRow   = "[-] Deselect whole group",
	EditButton            = "Edit Package Details",
	ExportButton          = "Export Package",
	PageFmt               = "Page %d / %d",
	HintTabs              = "&MENULEFT;/&MENURIGHT; Cycle   &START; Confirm   &SELECT; Exit",
	HintList              = "&MENULEFT;/&MENURIGHT; Scroll   &START; Toggle / Open   &SELECT; Back",
	HintContents          = "&MENULEFT;/&MENURIGHT; Page   &SELECT; Back",
	HintEdit              = "&MENULEFT;/&MENURIGHT; Choose Field   &START; Edit   &SELECT; Done",
}

local CATEGORY_LABELS = {
	Themes        = "Themes",
	NoteSkins     = "Note Skins",
	Songs         = "Songs",
	Courses       = "Courses",
	Characters    = "Characters",
	Announcers    = "Announcers",
	BGAnimations  = "BG Animations",
}

local Categories = ExportPackages.GetAvailableCategories()
local NUM_CATEGORY_TABS = #Categories
local EDIT_TAB_INDEX     = NUM_CATEGORY_TABS + 1
local CONTENTS_TAB_INDEX = NUM_CATEGORY_TABS + 2
local EXPORT_TAB_INDEX   = NUM_CATEGORY_TABS + 3
local NUM_TABS           = EXPORT_TAB_INDEX

-- Virtual row codes used for non-item rows in the wheel.
local ROW_BACK_TO_GROUPS  = "__back_to_groups__"
local ROW_SELECT_ALL      = "__select_whole_group__"
local ROW_DESELECT_ALL    = "__deselect_whole_group__"

-- Edit overlay fields (key shown to user, metadata key, max input length)
local EDIT_FIELDS = {
	{ label = "Name",        key = "Name",        max = 64  },
	{ label = "Author",      key = "Author",      max = 64  },
	{ label = "Version",     key = "Version",     max = 32  },
	{ label = "Homepage",    key = "Homepage",    max = 128 },
	{ label = "Description", key = "Description", max = 240 },
}

-- ---------------------------------------------------------------------------
-- State (entirely in Lua; engine only stores selection, metadata, progress)
-- ---------------------------------------------------------------------------
local state = {
	focus         = "tabs",       -- "tabs" | "list" | "edit" | "contents"
	tab_index     = 1,            -- 1..NUM_TABS
	drilled_group = nil,          -- when on Songs and drilled into a group
	wheel_pos     = {},           -- per-context remembered scroll position
	edit_index    = 1,            -- 1..#EDIT_FIELDS while focus="edit"
	contents_page = 1,            -- 1..total_pages while focus="contents"
}

local function CurrentCategory()
	if state.tab_index >= 1 and state.tab_index <= NUM_CATEGORY_TABS then
		return Categories[state.tab_index]
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Wheel rows
-- ---------------------------------------------------------------------------
local function BuildRows()
	local cat = CurrentCategory()
	local rows = {}
	if not cat then return rows end
	if cat == "Songs" and not state.drilled_group then
		for _, gpath in ipairs(ExportPackages.GetSongGroups()) do
			local name = gpath:match("([^/]+)/?$") or gpath
			local full    = ExportPackages.IsSongGroupFullySelected(gpath)
			local any     = false
			if not full then
				for _, spath in ipairs(ExportPackages.GetSongsInGroup(gpath)) do
					if ExportPackages.IsSelected(spath) then any = true break end
				end
			end
			local partial = (not full) and any
			rows[#rows + 1] = {
				kind = "group",
				label = name,
				path = gpath,
				selection = full and "full" or (partial and "partial" or "none"),
			}
		end
	elseif cat == "Songs" and state.drilled_group then
		rows[#rows + 1] = {
			kind = "virtual", label = UI.GroupBackRow,
			path = ROW_BACK_TO_GROUPS,
		}
		rows[#rows + 1] = {
			kind = "virtual", label = UI.GroupSelectAllRow,
			path = ROW_SELECT_ALL,
		}
		rows[#rows + 1] = {
			kind = "virtual", label = UI.GroupDeselectAllRow,
			path = ROW_DESELECT_ALL,
		}
		for _, spath in ipairs(ExportPackages.GetSongsInGroup(state.drilled_group)) do
			local name = spath:match("([^/]+)/?$") or spath
			rows[#rows + 1] = {
				kind = "item",
				label = name,
				path = spath,
				selection = ExportPackages.IsSelected(spath) and "full" or "none",
			}
		end
	else
		for _, path in ipairs(ExportPackages.GetItemsInCategory(cat)) do
			local name = path:match("([^/]+)/?$") or path
			rows[#rows + 1] = {
				kind = "item",
				label = name,
				path = path,
				selection = ExportPackages.IsSelected(path) and "full" or "none",
			}
		end
	end
	return rows
end

-- ---------------------------------------------------------------------------
-- Sick wheel item metatable
-- ---------------------------------------------------------------------------

local NUM_VISIBLE = 11
local ROW_HEIGHT  = 24
local WHEEL_W     = WideScale(300, 380)
local WHEEL_H     = NUM_VISIBLE * ROW_HEIGHT

local wheel = setmetatable({}, sick_wheel_mt)

local wheel_item_mt = {
	__index = {
		create_actors = function(self, name)
			self.name = name
			return Def.ActorFrame{
				Name = name,
				InitCommand = function(subself) self.container = subself end,

				Def.Quad{
					InitCommand = function(subself)
						self.bg = subself
						subself:zoomto(WHEEL_W - 8, ROW_HEIGHT - 2)
							:diffuse(color("#ffffff")):diffusealpha(0)
					end,
				},
				Def.BitmapText{
					Font = "Common Normal",
					InitCommand = function(subself)
						self.glyph = subself
						subself:halign(0):zoom(0.8)
							:x(-WHEEL_W / 2 + 10)
					end,
				},
				Def.BitmapText{
					Font = "Common Normal",
					InitCommand = function(subself)
						self.label = subself
						subself:halign(0):zoom(0.75)
							:x(-WHEEL_W / 2 + 40)
							:maxwidth((WHEEL_W - 60) / 0.75)
					end,
				},
				Def.BitmapText{
					Font = "Common Normal",
					InitCommand = function(subself)
						self.chev = subself
						subself:halign(1):zoom(0.8)
							:x(WHEEL_W / 2 - 10)
							:settext("")
					end,
				},
			}
		end,

		transform = function(self, item_index, num_items, has_focus)
			self.container:finishtweening()
			self.container:linear(0.05)
			local offset = item_index - math.floor(num_items / 2) - 1
			self.container:y(offset * ROW_HEIGHT)
			-- Focus highlight only meaningful while focus="list"; we always show
			-- the cursor band on the center row though so the user can see where
			-- they'll act when they enter the list.
			if has_focus then
				local alpha = (state.focus == "list") and 0.25 or 0.10
				self.bg:diffusealpha(alpha)
				self.label:diffuse(Color.White):zoom(0.8)
				self.glyph:diffuse(Color.White)
			else
				self.bg:diffusealpha(0)
				self.label:diffuse(color("#cccccc")):zoom(0.75)
				self.glyph:diffuse(color("#cccccc"))
			end
		end,

		set = function(self, info)
			self.info = info
			if not info then
				self.label:settext("")
				self.glyph:settext("")
				self.chev:settext("")
				return
			end
			self.label:settext(info.label or "")
			if info.kind == "virtual" then
				self.glyph:settext("")
				self.chev:settext("")
			elseif info.kind == "group" then
				if info.selection == "full" then
					self.glyph:settext("[x]")
				elseif info.selection == "partial" then
					self.glyph:settext("[~]")
				else
					self.glyph:settext("[ ]")
				end
				self.chev:settext(">")
			else
				if info.selection == "full" then
					self.glyph:settext("[x]")
				else
					self.glyph:settext("[ ]")
				end
				self.chev:settext("")
			end
		end,
	},
}

-- ---------------------------------------------------------------------------
-- Wheel refresh
-- ---------------------------------------------------------------------------
local current_rows = {}

local function ContextKey()
	return (CurrentCategory() or "") .. (state.drilled_group or "")
end

local function RefreshWheel()
	current_rows = BuildRows()
	if #current_rows == 0 then
		current_rows = {{ kind = "virtual", label = "(empty)", path = "" }}
	end
	local key = ContextKey()
	local pos = state.wheel_pos[key] or 1
	if pos > #current_rows then pos = #current_rows end
	state.wheel_pos[key] = pos
	wheel:set_info_set(current_rows, pos)
end

local function RememberPos()
	state.wheel_pos[ContextKey()] = wheel.info_pos + wheel.focus_pos
end

-- ---------------------------------------------------------------------------
-- Header
-- ---------------------------------------------------------------------------
af[#af + 1] = Def.BitmapText{
	Font = "Common Normal",
	Text = UI.HeaderText,
	InitCommand = function(self)
		self:xy(_screen.cx, 24):zoom(1.0):diffuse(Color.White)
	end,
}

-- ---------------------------------------------------------------------------
-- Layout constants (positions of the various boxes)
-- ---------------------------------------------------------------------------
local LAYOUT = {
	tabs_y         = 56,
	tab_w          = WideScale(78, 96),
	tab_h          = 22,
	tab_spacing    = WideScale(82, 100),

	wheel_cx       = WideScale(170, 220),
	wheel_cy       = _screen.cy - 12,

	right_cx       = WideScale(490, 683),
	right_cy       = _screen.cy - 12,
	right_w        = WideScale(287, 292),

	edit_btn_h     = 28,    -- "Edit Package Details" button height
	export_btn_h   = 28,    -- "Export Package" button height
	right_panel_h  = 280,   -- main info panel between the two buttons
	right_gap      = 8,     -- vertical gap between buttons and panel

	panel_padding  = 10,
	info_section_h = 110,   -- height reserved at bottom of right panel for info
	contents_lines = 12,    -- max lines shown in package contents
	hint_y         = _screen.h - 44,
}
local panel_bg = DarkUI() and color("#666666") or color("#333333")
local tab_bg_inactive = color("#222a33")
local tab_bg_active   = color("#0a8cf2")

-- ---------------------------------------------------------------------------
-- Top tab strip (category tabs 1..N)
-- ---------------------------------------------------------------------------
local tab_actors = {}        -- per-tab table: {bg=, label=}

local tab_frame = Def.ActorFrame{
	Name = "TabStrip",
	InitCommand = function(self) self:xy(_screen.cx, LAYOUT.tabs_y) end,
}
for i, cat in ipairs(Categories) do
	local x = (i - (NUM_CATEGORY_TABS + 1) / 2) * LAYOUT.tab_spacing
	local rec = {}
	tab_actors[i] = rec
	tab_frame[#tab_frame + 1] = Def.ActorFrame{
		InitCommand = function(self) self:x(x) end,
		Def.Quad{
			InitCommand = function(self)
				rec.bg = self
				self:zoomto(LAYOUT.tab_w, LAYOUT.tab_h):diffuse(tab_bg_inactive)
			end,
		},
		Def.BitmapText{
			Font = "Common Normal",
			InitCommand = function(self)
				rec.label = self
				self:zoom(0.7):diffuse(color("#cccccc"))
					:settext(CATEGORY_LABELS[cat] or cat)
					:maxwidth((LAYOUT.tab_w - 8) / 0.7)
			end,
		},
	}
end
af[#af + 1] = tab_frame

-- ---------------------------------------------------------------------------
-- Wheel container box + the wheel itself
-- ---------------------------------------------------------------------------
local wheel_box_border = nil
af[#af + 1] = Def.ActorFrame{
	Name = "WheelBox",
	InitCommand = function(self) self:xy(LAYOUT.wheel_cx, LAYOUT.wheel_cy) end,

	-- Outer border (highlights when focus="list")
	Def.Quad{
		InitCommand = function(self)
			wheel_box_border = self
			self:zoomto(WHEEL_W + 8, WHEEL_H + 14):diffuse(tab_bg_inactive)
		end,
	},
	-- Inner panel
	Def.Quad{
		InitCommand = function(self)
			self:zoomto(WHEEL_W + 2, WHEEL_H + 8):diffuse(panel_bg)
		end,
	},
}
af[#af + 1] = wheel:create_actors(
	"Wheel", NUM_VISIBLE, wheel_item_mt,
	LAYOUT.wheel_cx, LAYOUT.wheel_cy)

-- ---------------------------------------------------------------------------
-- Right side: Edit button, info panel, Export button (stacked)
-- ---------------------------------------------------------------------------
local function ButtonActor(rec_target, label_text, y, h)
	return Def.ActorFrame{
		InitCommand = function(self) self:y(y) end,
		Def.Quad{
			InitCommand = function(self)
				rec_target.bg = self
				self:zoomto(LAYOUT.right_w, h):diffuse(tab_bg_inactive)
			end,
		},
		Def.BitmapText{
			Font = "Common Normal",
			InitCommand = function(self)
				rec_target.label = self
				self:zoom(0.8):diffuse(color("#cccccc")):settext(label_text)
					:maxwidth((LAYOUT.right_w - 16) / 0.8)
			end,
		},
	}
end

-- Compute Y offsets so the right column matches the wheel box visually.
local right_top_y = -(WHEEL_H + 14) / 2
local edit_btn_y  = right_top_y + LAYOUT.edit_btn_h / 2
local panel_y     = edit_btn_y + LAYOUT.edit_btn_h / 2 + LAYOUT.right_gap + LAYOUT.right_panel_h / 2
local export_btn_y = panel_y + LAYOUT.right_panel_h / 2 + LAYOUT.right_gap + LAYOUT.export_btn_h / 2

tab_actors[EDIT_TAB_INDEX]     = {}
tab_actors[CONTENTS_TAB_INDEX] = {}
tab_actors[EXPORT_TAB_INDEX]   = {}

-- Contents panel state captured during InitCommand (used by RefreshContents)
local NUM_CONTENTS_ROWS    = 10
local CONTENTS_ROW_H       = 11
local contents_rows        = {}      -- { {label_bmt=...}, ... }
local contents_page_bmt    = nil
local contents_arrow_left  = nil
local contents_arrow_right = nil

local function BuildContentsEntries()
	local items = ExportPackages.GetSelected()
	local entries = {}
	local seen_groups = {}
	for _, path in ipairs(items) do
		local trimmed = path:gsub("/$", "")
		local parent = trimmed:match("^(.+)/[^/]+$")
		if parent and ExportPackages.IsSongGroupFullySelected(parent) then
			if not seen_groups[parent] then
				seen_groups[parent] = true
				local gname = parent:match("([^/]+)$") or parent
				entries[#entries + 1] = gname .. "/*"
			end
		else
			local pretty = path:match("([^/]+/[^/]+/?[^/]*)$") or path
			entries[#entries + 1] = pretty
		end
	end
	return entries
end

local function ContentsTotalPages()
	local n = #BuildContentsEntries()
	if n == 0 then return 1 end
	return math.ceil(n / NUM_CONTENTS_ROWS)
end

local function RefreshContents()
	local entries = BuildContentsEntries()
	local total = ContentsTotalPages()
	if state.contents_page > total then state.contents_page = total end
	if state.contents_page < 1 then state.contents_page = 1 end
	local start_idx = (state.contents_page - 1) * NUM_CONTENTS_ROWS + 1
	for i = 1, NUM_CONTENTS_ROWS do
		local rec = contents_rows[i]
		if rec and rec.label_bmt then
			local entry = entries[start_idx + i - 1]
			rec.label_bmt:settext(entry and ("- " .. entry) or "")
		end
	end
	if contents_page_bmt then
		if #entries == 0 then
			contents_page_bmt:settext(UI.NothingSelected)
		else
			contents_page_bmt:settext(string.format(UI.PageFmt, state.contents_page, total))
		end
	end
	local can_prev = (state.contents_page > 1)
	local can_next = (state.contents_page < total)
	if contents_arrow_left  then contents_arrow_left:diffusealpha(can_prev and 1 or 0.15) end
	if contents_arrow_right then contents_arrow_right:diffusealpha(can_next and 1 or 0.15) end
end

-- Build the inner contents panel as a table so we can splice in N row BMTs.
local contents_panel = Def.ActorFrame{
	InitCommand = function(self) self:y(panel_y) end,

	-- Border (acts as tab highlight bg for CONTENTS_TAB_INDEX)
	Def.Quad{
		InitCommand = function(self)
			tab_actors[CONTENTS_TAB_INDEX].bg = self
			self:zoomto(LAYOUT.right_w + 6, LAYOUT.right_panel_h + 8):diffuse(tab_bg_inactive)
		end,
	},
	-- Inner background
	Def.Quad{
		InitCommand = function(self)
			self:zoomto(LAYOUT.right_w, LAYOUT.right_panel_h):diffuse(panel_bg)
		end,
	},

	-- Title (left)
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			self:xy(-LAYOUT.right_w / 2 + LAYOUT.panel_padding,
				   -LAYOUT.right_panel_h / 2 + LAYOUT.panel_padding)
				:halign(0):valign(0):zoom(0.9):diffuse(Color.White)
				:settext(UI.PackageContents)
		end,
	},

	-- Count (right)
	Def.BitmapText{
		Name = "Count",
		Font = "Common Normal",
		InitCommand = function(self)
			self:xy(LAYOUT.right_w / 2 - LAYOUT.panel_padding,
				   -LAYOUT.right_panel_h / 2 + LAYOUT.panel_padding)
				:halign(1):valign(0):zoom(0.8):diffuse(color("#bbbbbb"))
		end,
		OnCommand = function(self) self:queuecommand("Refresh") end,
		RefreshCommand = function(self)
			self:settext(string.format(UI.ItemCountFmt, ExportPackages.GetSelectedCount()))
		end,
		ExportPackageSelectionChangedMessageCommand = function(self) self:queuecommand("Refresh") end,
	},

	-- Page indicator + arrows
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			contents_arrow_left = self
			self:xy(-LAYOUT.right_w / 2 + LAYOUT.panel_padding + 6,
				   -LAYOUT.right_panel_h / 2 + LAYOUT.panel_padding * 2.6)
				:halign(0):valign(0):zoom(0.7):diffuse(Color.White):settext("&MENULEFT;")
				:diffusealpha(0.15)
		end,
	},
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			contents_arrow_right = self
			self:xy(LAYOUT.right_w / 2 - LAYOUT.panel_padding - 6,
				   -LAYOUT.right_panel_h / 2 + LAYOUT.panel_padding * 2.6)
				:halign(1):valign(0):zoom(0.7):diffuse(Color.White):settext("&MENURIGHT;")
				:diffusealpha(0.15)
		end,
	},
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			contents_page_bmt = self
			self:xy(0, -LAYOUT.right_panel_h / 2 + LAYOUT.panel_padding * 2.6)
				:halign(0.5):valign(0):zoom(0.7):diffuse(color("#dddddd"))
				:settext(string.format(UI.PageFmt, 1, 1))
		end,
		OnCommand = function(self) RefreshContents() end,
		ExportPackageSelectionChangedMessageCommand = function(self) RefreshContents() end,
	},

	-- Divider
		Def.Quad{
			InitCommand = function(self)
				self:zoomto(LAYOUT.right_w - LAYOUT.panel_padding * 2, 1)
					:y(LAYOUT.right_panel_h / 2 - LAYOUT.info_section_h - LAYOUT.panel_padding)
					:diffuse(color("#000000")):diffusealpha(0.5)
			end,
		},

		-- Info header
		Def.BitmapText{
			Font = "Common Normal",
			InitCommand = function(self)
				self:xy(-LAYOUT.right_w / 2 + LAYOUT.panel_padding,
					   LAYOUT.right_panel_h / 2 - LAYOUT.info_section_h)
					:halign(0):valign(0):zoom(0.85):diffuse(Color.White)
					:settext(UI.PackageInfo)
			end,
		},

		-- Info body
		Def.BitmapText{
			Name = "Info",
			Font = "Common Normal",
			InitCommand = function(self)
				self:xy(-LAYOUT.right_w / 2 + LAYOUT.panel_padding,
					   LAYOUT.right_panel_h / 2 - LAYOUT.info_section_h + LAYOUT.panel_padding * 2.5)
					:halign(0):valign(0):zoom(0.7):diffuse(color("#dddddd"))
					:_wrapwidthpixels(math.floor((LAYOUT.right_w - LAYOUT.panel_padding * 2) / 0.7))
			end,
			OnCommand = function(self) self:queuecommand("Refresh") end,
			RefreshCommand = function(self)
				local m = ExportPackages.GetMetadata()
				local function row(k, v)
					if v == nil or v == "" then v = "(unset)" end
					return k .. ": " .. v
				end
				self:settext(table.concat({
					row("Name", m.Name),
					row("Author", m.Author),
					row("Version", m.Version),
				}, "\n"))
			end,
			ExportPackageMetadataChangedMessageCommand = function(self) self:queuecommand("Refresh") end,
		},
}

-- Splice N row BMTs into contents_panel between the page indicator (header area)
-- and the divider.  Each row has maxwidth so that long entries scale-to-fit
-- on a single line rather than wrapping onto the next row.
local rows_top_y = -LAYOUT.right_panel_h / 2 + LAYOUT.panel_padding * 4
for i = 1, NUM_CONTENTS_ROWS do
	local rec = {}
	contents_rows[i] = rec
	local row_y = rows_top_y + (i - 1) * CONTENTS_ROW_H
	contents_panel[#contents_panel + 1] = Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			rec.label_bmt = self
			self:xy(-LAYOUT.right_w / 2 + LAYOUT.panel_padding, row_y)
				:halign(0):valign(0):zoom(0.7):diffuse(color("#dddddd"))
				:maxwidth((LAYOUT.right_w - LAYOUT.panel_padding * 2) / 0.7)
		end,
	}
end

local right_frame = Def.ActorFrame{
	Name = "RightColumn",
	InitCommand = function(self) self:xy(LAYOUT.right_cx, LAYOUT.wheel_cy) end,

	ButtonActor(tab_actors[EDIT_TAB_INDEX], UI.EditButton, edit_btn_y, LAYOUT.edit_btn_h),
	contents_panel,
	ButtonActor(tab_actors[EXPORT_TAB_INDEX], UI.ExportButton, export_btn_y, LAYOUT.export_btn_h),
}
af[#af + 1] = right_frame

-- ---------------------------------------------------------------------------
-- Hint bar
-- ---------------------------------------------------------------------------
local hint_bmt = nil
af[#af + 1] = Def.BitmapText{
	Font = "Common Normal",
	InitCommand = function(self)
		hint_bmt = self
		self:xy(_screen.cx, LAYOUT.hint_y):zoom(0.6):diffuse(color("#bbbbbb"))
			:settext(UI.HintTabs)
	end,
}

-- ---------------------------------------------------------------------------
-- Tab highlight refresh
-- ---------------------------------------------------------------------------
local function RefreshTabs()
	for i, rec in pairs(tab_actors) do
		if not rec then
			-- skip
		else
			local active = (i == state.tab_index)
			local inside = active and (
				(state.focus == "list"     and i <= NUM_CATEGORY_TABS) or
				(state.focus == "contents" and i == CONTENTS_TAB_INDEX)
			)
			local bg_color, text_color, zoom
			if active and not inside then
				bg_color, text_color, zoom = tab_bg_active, Color.White, (i <= NUM_CATEGORY_TABS) and 0.78 or 0.85
			elseif active and inside then
				bg_color, text_color, zoom = color("#085ca0"), Color.White, (i <= NUM_CATEGORY_TABS) and 0.78 or 0.85
			else
				bg_color, text_color, zoom = tab_bg_inactive, color("#cccccc"), (i <= NUM_CATEGORY_TABS) and 0.7 or 0.8
			end
			if rec.bg then rec.bg:diffuse(bg_color) end
			if rec.label then rec.label:diffuse(text_color):zoom(zoom) end
		end
	end
	-- Wheel box border lights up when actively inside the list.
	if wheel_box_border then
		if state.focus == "list" then
			wheel_box_border:diffuse(tab_bg_active)
		else
			wheel_box_border:diffuse(tab_bg_inactive)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Edit overlay (modal Lua menu; rows = EDIT_FIELDS)
-- ---------------------------------------------------------------------------
local edit_overlay = nil
local live_edit_overlay = nil
local edit_row_actors = {}      -- { {bg=, label=, value=}, ... }

local function FieldValueText(idx)
	local f = EDIT_FIELDS[idx]
	local m = ExportPackages.GetMetadata()
	local v = m[f.key]
	if v == nil or v == "" then v = "(empty)" end
	return v
end

local function RefreshEditOverlay()
	for i, rec in ipairs(edit_row_actors) do
		local active = (i == state.edit_index)
		if rec.bg then
			rec.bg:diffuse(active and tab_bg_active or tab_bg_inactive)
		end
		if rec.label then rec.label:diffuse(active and Color.White or color("#cccccc")) end
		if rec.value then
			rec.value:diffuse(active and Color.White or color("#bbbbbb"))
				:settext(FieldValueText(i))
		end
	end
end

local EDIT_PANEL_W = WideScale(420, 520)
local EDIT_ROW_H   = 28
local EDIT_PANEL_H = EDIT_ROW_H * (#EDIT_FIELDS + 2) + 30

local edit_frame_children = {
	Def.Quad{
		InitCommand = function(self) self:FullScreen():diffuse(color("#000000")):diffusealpha(0.6) end,
	},
	Def.Quad{
		InitCommand = function(self) self:xy(_screen.cx, _screen.cy):zoomto(EDIT_PANEL_W, EDIT_PANEL_H):diffuse(panel_bg) end,
	},
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			self:xy(_screen.cx, _screen.cy - EDIT_PANEL_H / 2 + 20):zoom(1.0):diffuse(Color.White)
				:settext(UI.EditButton)
		end,
	},
}

for i, field in ipairs(EDIT_FIELDS) do
	local rec = {}
	edit_row_actors[i] = rec
	local row_y = _screen.cy - EDIT_PANEL_H / 2 + 50 + (i - 1) * EDIT_ROW_H + EDIT_ROW_H / 2
	edit_frame_children[#edit_frame_children + 1] = Def.ActorFrame{
		InitCommand = function(self) self:xy(_screen.cx, row_y) end,
		Def.Quad{
			InitCommand = function(self)
				rec.bg = self
				self:zoomto(EDIT_PANEL_W - 20, EDIT_ROW_H - 4):diffuse(tab_bg_inactive)
			end,
		},
		Def.BitmapText{
			Font = "Common Normal",
			InitCommand = function(self)
				rec.label = self
				self:halign(0):x(-EDIT_PANEL_W / 2 + 20):zoom(0.8)
					:diffuse(color("#cccccc")):settext(field.label .. ":")
			end,
		},
		Def.BitmapText{
			Font = "Common Normal",
			InitCommand = function(self)
				rec.value = self
				self:halign(1):x(EDIT_PANEL_W / 2 - 20):zoom(0.75)
					:diffuse(color("#bbbbbb"))
					:maxwidth((EDIT_PANEL_W * 0.6) / 0.75)
			end,
		},
	}
end

edit_overlay = Def.ActorFrame{
	Name = "EditOverlay",
	InitCommand = function(self)
		live_edit_overlay = self
		self:visible(false)
	end,
	ExportPackageMetadataChangedMessageCommand = function(self)
		if state.focus == "edit" then RefreshEditOverlay() end
	end,
}
for _, child in ipairs(edit_frame_children) do
	edit_overlay[#edit_overlay + 1] = child
end
af[#af + 1] = edit_overlay

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function SetHint()
	if not hint_bmt then return end
	if state.focus == "edit" then
		hint_bmt:settext(UI.HintEdit)
	elseif state.focus == "list" then
		hint_bmt:settext(UI.HintList)
	elseif state.focus == "contents" then
		hint_bmt:settext(UI.HintContents)
	else
		hint_bmt:settext(UI.HintTabs)
	end
end

local function EnterTab(idx)
	state.tab_index = idx
	if idx <= NUM_CATEGORY_TABS then
		-- Switching to a category tab: drop any drill-in from previous Songs view.
		state.drilled_group = nil
		RefreshWheel()
	end
	RefreshTabs()
end

local function CycleTab(dir)
	local idx = ((state.tab_index - 1 + dir) % NUM_TABS) + 1
	EnterTab(idx)
end

local function OpenEditOverlay()
	state.focus = "edit"
	state.edit_index = 1
	if live_edit_overlay then live_edit_overlay:visible(true) end
	RefreshEditOverlay()
	RefreshTabs()
	SetHint()
end

local function CloseEditOverlay()
	if live_edit_overlay then live_edit_overlay:visible(false) end
	state.focus = "tabs"
	RefreshTabs()
	SetHint()
end

local function PromptEditField()
	local field = EDIT_FIELDS[state.edit_index]
	if not field then return end
	local current = ExportPackages.GetMetadata()[field.key] or ""
	local settings = {
		Question      = "Enter " .. field.label,
		InitialAnswer = current,
		MaxInputLength = field.max,
		OnOK = function(answer)
			ExportPackages.SetMetadata(field.key, answer or "")
			-- Engine broadcasts ExportPackageMetadataChanged; overlay re-renders.
		end,
	}
	SCREENMAN:AddNewScreenToTop("ScreenTextEntry")
	SCREENMAN:GetTopScreen():Load(settings)
end

local function ToggleAtFocus()
	local info = wheel:get_info_at_focus_pos()
	if not info then return end
	if info.kind == "item" then
		ExportPackages.ToggleSelected(info.path)
		RefreshWheel()
	elseif info.kind == "group" then
		RememberPos()
		state.drilled_group = info.path
		RefreshWheel()
	elseif info.kind == "virtual" then
		if info.path == ROW_BACK_TO_GROUPS then
			state.drilled_group = nil
			RefreshWheel()
		elseif info.path == ROW_SELECT_ALL and state.drilled_group then
			ExportPackages.SelectSongGroup(state.drilled_group)
			RefreshWheel()
		elseif info.path == ROW_DESELECT_ALL and state.drilled_group then
			ExportPackages.DeselectSongGroup(state.drilled_group)
			RefreshWheel()
		end
	end
end

local function StartExport()
	-- The engine now runs the zip on a worker thread; this returns
	-- immediately.  Success / failure is reported via the
	-- ExportPackageFinishedMessage handler below, which calls
	-- ExportPackages.GetLastExportPath / GetLastExportError.
	local ok, err = ExportPackages.StartExport()
	if not ok then
		SCREENMAN:SystemMessage(err or "Failed to start export.")
	end
end

local function ActivateTab()
	if state.tab_index == EDIT_TAB_INDEX then
		OpenEditOverlay()
	elseif state.tab_index == EXPORT_TAB_INDEX then
		StartExport()
	elseif state.tab_index == CONTENTS_TAB_INDEX then
		state.focus = "contents"
		state.contents_page = 1
		RefreshContents()
		RefreshTabs()
		SetHint()
	else
		-- Enter the list for this category.
		state.focus = "list"
		RefreshTabs()
		SetHint()
	end
end

-- ---------------------------------------------------------------------------
-- Input
-- ---------------------------------------------------------------------------
local function HandleInput(event)
	if not event.button or event.type ~= "InputEventType_FirstPress" then
		return false
	end
	if ExportPackages.IsExporting() then
		return false
	end

	local top = SCREENMAN:GetTopScreen()
	local gb = event.GameButton

	if state.focus == "edit" then
		if gb == "MenuLeft" then
			state.edit_index = ((state.edit_index - 2) % #EDIT_FIELDS) + 1
			RefreshEditOverlay()
		elseif gb == "MenuRight" then
			state.edit_index = (state.edit_index % #EDIT_FIELDS) + 1
			RefreshEditOverlay()
		elseif gb == "Start" then
			PromptEditField()
		elseif gb == "Back" or gb == "Select" then
			CloseEditOverlay()
		end
		return false
	end

	if state.focus == "list" then
		if gb == "MenuLeft" then
			wheel:scroll_by_amount(-1)
			RememberPos()
		elseif gb == "MenuRight" then
			wheel:scroll_by_amount(1)
			RememberPos()
		elseif gb == "Start" then
			ToggleAtFocus()
		elseif gb == "Back" or gb == "Select" then
			if state.drilled_group then
				state.drilled_group = nil
				RefreshWheel()
			else
				state.focus = "tabs"
				RefreshTabs()
				SetHint()
			end
		end
		return false
	end

	if state.focus == "contents" then
		if gb == "MenuLeft" then
			if state.contents_page > 1 then
				state.contents_page = state.contents_page - 1
				RefreshContents()
			end
		elseif gb == "MenuRight" then
			local total = ContentsTotalPages()
			if state.contents_page < total then
				state.contents_page = state.contents_page + 1
				RefreshContents()
			end
		elseif gb == "Back" or gb == "Select" or gb == "Start" then
			state.focus = "tabs"
			RefreshContents()
			RefreshTabs()
			SetHint()
		end
		return false
	end

	-- focus == "tabs"
	if gb == "MenuLeft" then
		CycleTab(-1)
	elseif gb == "MenuRight" then
		CycleTab(1)
	elseif gb == "Start" then
		ActivateTab()
	elseif gb == "Back" or gb == "Select" then
		top:Cancel()
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Progress modal
-- ---------------------------------------------------------------------------
local bar_w = 480
local bar_h = 24

af[#af + 1] = Def.ActorFrame{
	Name = "ProgressOverlay",
	InitCommand = function(self) self:visible(false) end,
	OnCommand = function(self) self:queuecommand("Refresh") end,
	RefreshCommand = function(self)
		self:visible(ExportPackages.IsExporting())
	end,
	ExportPackageStartedMessageCommand  = function(self) self:visible(true):queuecommand("Refresh") end,
	ExportPackageFinishedMessageCommand = function(self)
		self:visible(false)
		local err = ExportPackages.GetLastExportError()
		if err and err ~= "" then
			SCREENMAN:SystemMessage(err)
		else
			local path = ExportPackages.GetLastExportPath() or ""
			if path ~= "" then
				SCREENMAN:SystemMessage("Exported to: " .. path)
			end
		end
	end,
	ExportPackageProgressMessageCommand = function(self) self:queuecommand("Refresh") end,

	Def.Quad{
		InitCommand = function(self) self:FullScreen():diffuse(color("#000000")):diffusealpha(0.7) end,
	},
	Def.Quad{
		InitCommand = function(self) self:xy(_screen.cx, _screen.cy):zoomto(bar_w + 80, bar_h + 130):diffuse(panel_bg) end,
	},
	Def.BitmapText{
		Font = "Common Normal",
		InitCommand = function(self)
			self:xy(_screen.cx, _screen.cy - bar_h / 2 - 42):zoom(1.0):diffuse(Color.White):settext(UI.Exporting)
		end,
	},
	Def.BitmapText{
		Name = "File",
		Font = "Common Normal",
		InitCommand = function(self)
			self:xy(_screen.cx, _screen.cy - bar_h / 2 - 14):zoom(0.65):diffuse(color("#bbbbbb"))
				:maxwidth(bar_w / 0.65)
		end,
		ExportPackageStartedMessageCommand = function(self) self:settext("") end,
		ExportPackageProgressMessageCommand = function(self)
			self:settext(ExportPackages.GetProgressFile() or "")
		end,
	},
	Def.Quad{
		InitCommand = function(self) self:xy(_screen.cx, _screen.cy):zoomto(bar_w, bar_h):diffuse(color("#444444")) end,
	},
	Def.Quad{
		Name = "Fill",
		InitCommand = function(self)
			self:horizalign(left):xy(_screen.cx - bar_w / 2, _screen.cy):zoomto(0, bar_h):diffuse(color("#33cc66"))
		end,
		ExportPackageStartedMessageCommand = function(self) self:zoomto(0, bar_h) end,
		ExportPackageProgressMessageCommand = function(self)
			local f = ExportPackages.GetProgressFraction()
			self:zoomto(bar_w * f, bar_h)
		end,
	},
	Def.BitmapText{
		Name = "Counter",
		Font = "Common Normal",
		InitCommand = function(self) self:xy(_screen.cx, _screen.cy + bar_h / 2 + 14):zoom(0.8):diffuse(Color.White) end,
		ExportPackageStartedMessageCommand = function(self) self:settext("0 / 0") end,
		ExportPackageProgressMessageCommand = function(self)
			self:settext(tostring(ExportPackages.GetProgressCurrent()) .. " / " ..
				tostring(ExportPackages.GetProgressTotal()))
		end,
	},
}

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------
af.OnCommand = function(self)
	RefreshTabs()
	RefreshWheel()
	RefreshContents()
	SetHint()
	SCREENMAN:GetTopScreen():AddInputCallback(HandleInput)
end

return af
