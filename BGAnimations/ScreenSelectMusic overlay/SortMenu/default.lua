local sort_wheel = setmetatable({}, sick_wheel_mt)

local input = LoadActor("InputHandler.lua", sort_wheel)
local wheel_item_mt = LoadActor("WheelItemMT.lua")

local sortmenu = { w=210, h=160 }
-- - - - - - - - - - - - - - - - - - - - - - - - - - - -

local t = Def.ActorFrame {
	Name="SortMenu",
	InitCommand=function(self)
		-- Always ensure that the SortMenu is hidden and that player input
		-- is directed back to the engine on screen initialization.
		self:queuecommand("HideSortMenu")
	end,
	ShowSortMenuCommand=function(self)
		SOUND:StopMusic()
		SCREENMAN:GetTopScreen():AddInputCallback(input)

		for player in ivalues(GAMESTATE:GetHumanPlayers()) do
			SCREENMAN:set_input_redirected(player, true)
		end
		self:visible(true)
	end,
	HideSortMenuCommand=function(self)
		SCREENMAN:GetTopScreen():RemoveInputCallback(input)
		for player in ivalues(GAMESTATE:GetHumanPlayers()) do
			SCREENMAN:set_input_redirected(player, false)
		end
		self:visible(false)
	end,
	-- Always ensure that player input is directed back to the engine when leaving SelectMusic.
	OffCommand=function(self) self:playcommand("HideSortMenu") end,

	OnCommand=function(self)
		self:visible(false)

		local wheel_options = {
			{"SortBy", "Group"},
			{"SortBy", "Title"},
			{"SortBy", "Artist"},
			{"SortBy", "Genre"},
			{"SortBy", "BPM"},
			{"SortBy", "Length"},

			{"SortBy", "BeginnerMeter"},
			{"SortBy", "EasyMeter"},
			{"SortBy", "MediumMeter"},
			{"SortBy", "HardMeter"},
			{"SortBy", "ChallengeMeter"},

			{"SortBy", "Popularity"},
			{"SortBy", "Recent"}
		}

		local style = GAMESTATE:GetCurrentStyle():GetName():gsub("8", "")

		-- Override sick_wheel's default focus_pos, which is math.floor(num_items / 2)
		--
		-- keep in mind that num_items is the number of Actors in the wheel (here, 7)
		-- NOT the total number of things you can eventually scroll through (#wheel_options = 14)
		--
		-- so, math.floor(7/2) gives focus to the third item in the wheel, which looks weird
		-- in this particular usage.  Thus, set the focus to the wheel's current 4th Actor.
		sort_wheel.focus_pos = 4

		-- get the currenly active SortOrder and truncate the "SortOrder_" from the beginning
		local current_sort_order = ToEnumShortString(GAMESTATE:GetSortOrder())
		local current_sort_order_index = 1

		-- find the sick_wheel index of the item we want to display first when the player activates this SortMenu
		for i=1, #wheel_options do
			if wheel_options[i][1] == "SortBy" and wheel_options[i][2] == current_sort_order then
				current_sort_order_index = i
				break
			end
		end

		-- the second argument passed to set_info_set is the index of the item in wheel_options
		-- that we want to have focus when the wheel is displayed
		sort_wheel:set_info_set(wheel_options, current_sort_order_index)
	end,

	-- slightly darken the entire screen
	Def.Quad {
		InitCommand=function(self) self:FullScreen():diffuse(Color.Black):diffusealpha(0.8) end
	},

	-- OptionsList Header Quad
	Def.Quad {
		InitCommand=function(self) self:Center():zoomto(sortmenu.w+2,22):xy(_screen.cx, _screen.cy-92) end
	},
	-- "Options" text
	Def.BitmapText{
		Font="_wendy small",
		Text=ScreenString("Options"),
		InitCommand=function(self)
			self:xy(_screen.cx, _screen.cy-92):zoom(0.4)
				:diffuse( Color.Black )
		end
	},

	-- white border
	Def.Quad {
		InitCommand=function(self) self:Center():zoomto(sortmenu.w+2,sortmenu.h+2) end
	},
	-- BG of the sortmenu box
	Def.Quad {
		InitCommand=function(self) self:Center():zoomto(sortmenu.w,sortmenu.h):diffuse(Color.Black) end
	},
	-- top mask
	Def.Quad {
		InitCommand=function(self) self:Center():zoomto(sortmenu.w,_screen.h/2):y(40):MaskSource() end
	},
	-- bottom mask
	Def.Quad {
		InitCommand=function(self) self:zoomto(sortmenu.w,_screen.h/2):xy(_screen.cx,_screen.cy+200):MaskSource() end
	},

	-- "Press SELECT To Cancel" text
	Def.BitmapText{
		Font="_wendy small",
		Text=ScreenString("Cancel"),
		InitCommand=function(self)
			if PREFSMAN:GetPreference("ThreeKeyNavigation") then
				self:visible(false)
			else
				self:xy(_screen.cx, _screen.cy+100):zoom(0.3):diffusealpha(0.6)
			end
		end
	},

	-- this returns an ActorFrame ( see: ./Scripts/Consensual-sick_wheel.lua )
	sort_wheel:create_actors( "Sort Menu", 7, wheel_item_mt, _screen.cx, _screen.cy )
}

t[#t+1] = LoadActor( THEME:GetPathS("ScreenSelectMaster", "change") )..{ Name="change_sound", SupportPan = false }
t[#t+1] = LoadActor( THEME:GetPathS("common", "start") )..{ Name="start_sound", SupportPan = false }

return t
