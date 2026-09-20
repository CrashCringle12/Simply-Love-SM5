-- the MusicWheelItem for CourseMode contains the basic colored Quads
-- use that as a common base, and add in a Sprite for "Has Edit"
local af = LoadActor("../MusicWheelItem Course NormalPart.lua")

local stepstype = GAMESTATE:GetCurrentStyle():GetStepsType()


-- sortByDates exposes Song:GetFirstSeen().  Treat songs/packs first seen
-- within the last 30 days as new.
local NEW_SONG_DAYS = 30
local pack_new_cache = {}

local function days_from_civil(year, month, day)
	if month <= 2 then year = year - 1 end
	local era = math.floor(year / 400)
	local yoe = year - era * 400
	local mp = month + (month > 2 and -3 or 9)
	local doy = math.floor((153 * mp + 2) / 5) + day - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe
end

local function song_is_new(song)
	if not song or not song.GetFirstSeen then return false end

	local y, m, d = tostring(song:GetFirstSeen() or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not y or not m or not d then return false end

	local today = days_from_civil(Year(), MonthOfYear() + 1, DayOfMonth())
	local first_seen = days_from_civil(y, m, d)

	return math.max(0, today - first_seen) < NEW_SONG_DAYS
end

local function pack_is_new(group)
	if not group or group == "" then return false end
	if pack_new_cache[group] ~= nil then return pack_new_cache[group] end

	for song in ivalues(SONGMAN:GetSongsInGroup(group) or {}) do
		if song_is_new(song) then
			pack_new_cache[group] = true
			return true
		end
	end

	pack_new_cache[group] = false
	return false
end

local function song_or_pack_is_new(song)
	return song and (song_is_new(song) or pack_is_new(song:GetGroupName())) or false
end

-- using a png in a Sprite ties the visual to a specific rasterized font (currently Miso),
-- but Sprites are cheaper than BitmapTexts, so we should use them where dynamic text is not needed
af[#af+1] = Def.Sprite{
	Texture=THEME:GetPathG("", "Has Edit (doubleres).png"),
	InitCommand=function(self)
		self:horizalign(left):visible(false):zoom(0.375)
		self:x( _screen.w/(WideScale(2.15, 2.14)) - self:GetWidth()*self:GetZoom() - 8 )

		if DarkUI() then self:diffuse(0,0,0,1) end
	end,
	SetCommand=function(self, params)
		local song = params.Song
		self:visible(song and not song_or_pack_is_new(song) and song:HasEdits(stepstype) or false)
	end
}

af[#af+1] = Def.BitmapText{
	Font="Common Bold",
	Text="New!",
	InitCommand=function(self)
		self:horizalign(right):visible(false):zoom(0.34)
		self:x( _screen.w/(WideScale(2.15, 2.14)) - 8 )
		self:strokecolor(Color.Black)
		self:diffuseshift():effectperiod(0.8)
		self:effectcolor1(Color.White):effectcolor2(color("#F4D35E"))
	end,
	SetCommand=function(self, params)
		self:visible(params.Song and song_or_pack_is_new(params.Song) or false)
	end
}

for player in ivalues(PlayerNumber) do
	af[#af+1] = LoadActor("Favorites.lua", player)
	af[#af+1] = LoadActor("Unlocks.lua", player)

	-- Add ITL EX scores to the song wheel as well.
	-- It will be centered to the item if only one player is enabled, and stacked otherwise.
	af[#af+1] = Def.BitmapText{
		Font="Wendy/_wendy monospace numbers",
		Text="",
		InitCommand=function(self)
			self:visible(false)
			self:zoom(0.2)
			self:x( _screen.w/(WideScale(2.15, 2.14)) - self:GetWidth()*self:GetZoom() - 40 )
			self:diffuse(SL.JudgmentColors["ITG"][1])
		end,
		PlayerJoinedMessageCommand=function(self)
			self:visible(GAMESTATE:IsPlayerEnabled(player))
		end,
		PlayerUnjoinedMessageCommand=function(self)
			self:visible(GAMESTATE:IsPlayerEnabled(player))
		end,
		SetCommand=function(self, params)
			-- Only display EX score if a profile is found for an enabled player.
			if not GAMESTATE:IsPlayerEnabled(player) or not PROFILEMAN:IsPersistentProfile(player) then
				self:visible(false)
				return
			end

			if GAMESTATE:GetNumSidesJoined() == 2 then
				if player == PLAYER_1 then
					self:y(-11)
				else
					self:y(4)
				end
			else
				self:y(-4)
			end
			local pn = ToEnumShortString(player)
			if params.Song ~= nil then
				local song = params.Song
				local song_dir = song:GetSongDir()
				if song_dir ~= nil and #song_dir ~= 0 then
					if SL[pn].ITLData["pathMap"][song_dir] ~= nil then
						local hash = SL[pn].ITLData["pathMap"][song_dir]
						if SL[pn].ITLData["hashMap"][hash] ~= nil then
							local ex = SL[pn].ITLData["hashMap"][hash]["ex"] / 100
							self:settext(("%.2f"):format(ex))
							self:visible(true)
							return
						end
					end
				end
			end
			self:visible(false)
		end,
	}
end
--af[#af+1] = LoadActor("Trial.lua")
af[#af+1] = Def.Sprite{
	-- This will likely rarely be used, but it's here because there was a situation for it.
	-- In Fall 2022, the PSU cab underwent a lot of maintenance, including an overhaul to the pads.
	-- While the pads were being powdercoated, the PSU cab had pump pads in place of its ITG pads.
	-- I put most of the pump official charts on the machine, but I also used a dance -> pump chart converter
	-- to convert all of the songs on the machine to pump. 
	-- You can imagine what sort of... "mixed" results that had. But... it wasn't that bad? There were a lot of charts
	-- that generated pretty well. Interesting tech that actually worked. I added this tag to the charts so
	-- players know the difference between charts made for pump and charts converted from dance.
	
	-- You can add the Autogen tag to show in the music wheel by putting 'autogen' as your simfile's origin.
	-- I've been using Origin as a place to hold certain information about the chart for the theme.
	Texture=THEME:GetPathG("", "Autogen (doubleres).png"),
	InitCommand=function(self)
	  self:horizalign(left):visible(false):zoom(0.375)
	  self:x( _screen.w/(WideScale(2.15, 2.14)) - self:GetWidth()*self:GetZoom() - 36 )
  
	  if DarkUI() then self:diffuse(0,0,0,1) end
	end,
	SetCommand=function(self, params)
	  self:visible(params.Song and (params.Song:GetOrigin():find('autogen')) or false)
	end
  }

return af
