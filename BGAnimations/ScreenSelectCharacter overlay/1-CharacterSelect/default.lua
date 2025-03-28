---------------------------------------------------------------------
-- Character Select Wheel(s)
---------------------------------------------------------------------

-- the theme may not have Consensual's sick_wheel.lua in ./Scripts
-- so load a bundled copy now
LoadActor("../Scripts/Consensual-sick_wheel.lua")

local CharacterWheels = {}

for player in ivalues( GAMESTATE:GetHumanPlayers() ) do
	-- Add one CharacterWheel per human player
	CharacterWheels[ToEnumShortString(player)] = setmetatable({}, sick_wheel_mt)
end

local PossibleCharacters = {
	"Albonshasta",
	"Ellipsis",
	"Girl",
	"Guy",
	"Kitsune",
	"Larry",
	"Mage",
	"Mark",
	"Silence"
}


local duration_between_frames = 0.15

-- we only want the "Down" frames for CharacterSelect
local frames = {
	Down = {
		{ Frame=0,	Delay=duration_between_frames},
		{ Frame=1,	Delay=duration_between_frames},
		{ Frame=2,	Delay=duration_between_frames},
		{ Frame=3,	Delay=duration_between_frames}
	}
}


-- the metatable for an character in the wheel
local wheel_item_mt = {
	__index = {
		create_actors = function(self, name)
			self.name=name

			local af = Def.ActorFrame{
				Name=self.name,
				InitCommand=function(subself)
					self.container = subself
				end
			}

			af[#af+1] = Def.Sprite{
				InitCommand=function(subself)
					self.sprite = subself
					subself:diffusealpha(0)
					subself:zoom(0.25)
					subself:animate(true)
				end,
				OnCommand=function(subself)
					subself:sleep(0.2)
					subself:sleep(0.04 * self.index)
					subself:linear(0.2)
					subself:diffusealpha(1)
				end,
				OffCommand=function(subself)
					subself:sleep(0.04 * self.index)
					subself:linear(0.2)
					subself:diffusealpha(0)
				end
			}
			
			af[#af+1] = Def.BitmapText{
				Font="Common normal",
				InitCommand=function(subself)
					self.bmt = subself
					subself:zoom(0.125)
					subself:diffuse(Color.Black)
					subself:y(8)
				end,
			}
			
			return af
		end,

		transform = function(self, item_index, num_items, has_focus)
			self.container:finishtweening()
			self.container:linear(0.2)
			self.index=item_index

			local OffsetFromCenter = (item_index - math.floor(num_items/2))-1
			local x_padding = 48
			local x = x_padding * OffsetFromCenter
			local z = -1.25 * math.abs(OffsetFromCenter)
			local zoom = (z + math.floor(num_items/2) + 1) * 1.75

			
			if item_index <= 1 or item_index >= num_items then
				self.container:diffusealpha(0)
			else
				if has_focus then
					self.container:diffusealpha(1)
				else	
					self.container:diffusealpha(0.33)
				end
			end
			

			self.container:x(x)
			self.container:zoom( zoom )
			self.bmt:settext( self.character )

		end,

		set = function(self, character)
			if not character then return end
			
			local dir = GAMESTATE:GetCurrentSong():GetSongDir()
			self.character = character
			self.sprite:Load( dir .. "/Sprites/" .. character .. " 4x4.png")
			self.sprite:SetStateProperties( frames.Down )
		end
	}
}


---------------------------------------------------------------------
-- Update function
---------------------------------------------------------------------

local Update = function(self, delta)
	
	-- beat 16 is the start of the lyrics
	if GAMESTATE:GetSongBeat() >= 16 then
		for player in ivalues(GAMESTATE:GetHumanPlayers()) do
			local pn = ToEnumShortString(player)
			TSH[pn].file = CharacterWheels[pn]:get_info_at_focus_pos()
		end
	end
	
	return false
end


---------------------------------------------------------------------
-- Initialize generalized Event Handling function(s)
---------------------------------------------------------------------

local InputHandler = function(event)
	
	----------------------------------------------------------------------------

	-- if any of these, don't attempt to handle input
	if not event.PlayerNumber or not event.button then
		return false
	end

	-- truncate "PlayerNumber_P1" into "P1" and "PlayerNumber_P2" into "P2"
	local pn = ToEnumShortString(event.PlayerNumber)

	if event.type == "InputEventType_FirstPress" then

		if event.button == "MenuRight" then
			CharacterWheels[pn]:scroll_by_amount(1)
			
		elseif event.button == "MenuLeft" then
			CharacterWheels[pn]:scroll_by_amount(-1)
			
		-- elseif event.GameButton == "Start" then
		-- 	local SelectedCharacter = CharacterWheels[pn]:get_info_at_focus_pos()
		-- 	SM(SelectedCharacter)
		end

	end

	return false
end

---------------------------------------------------------------------
-- Primary ActorFrame and children
---------------------------------------------------------------------
local t = Def.ActorFrame{
	InitCommand=function(self)
		self:xy(0,0)

		for k,wheel in pairs(CharacterWheels) do
			-- set_info_set() takes two arguments:
			--		a table of meaningful data to divvy up to wheel items
			--		the index of which item we want to initially give focus to
			wheel:set_info_set(PossibleCharacters, 1)
		end

		-- queue the next command so that we can actually GetTopScreen()
		self:queuecommand("Capture")
			:sleep( 60/140 * 16 ):accelerate(0.5):diffusealpha(0)
	end,
	CaptureCommand=function(self)
		
		-- custom update function to check beats
		self:SetUpdateFunction( Update )
		
		-- attach our InputHandler to the TopScreen and pass it this ActorFrame
		-- so we can manipulate stuff more easily from there
		SCREENMAN:GetTopScreen():AddInputCallback( InputHandler )
	end,
	
	Def.Quad{
		OnCommand=function(self)
			self:FullScreen():cropbottom(1)
				:linear(0.5):cropbottom(0)
		end
	}
}

-- add a CharacterWheel for each available player
for player in ivalues(GAMESTATE:GetHumanPlayers()) do
	local pn = ToEnumShortString(player)
	local NumToDraw = 7
	local x_pos = player == PLAYER_1 and _screen.cx-(_screen.w*160/640) or _screen.cx+(_screen.w*160/640)
	
	t[#t+1] = CharacterWheels[pn]:create_actors( "CharacterWheel"..pn, NumToDraw, wheel_item_mt, x_pos , _screen.cy)
end

---------------------------------------------------------------------
return t