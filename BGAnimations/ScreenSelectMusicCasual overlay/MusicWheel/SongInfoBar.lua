-- MusicWheel/SongInfoBar.lua
--
-- The song identification block rendered directly beneath the wheel:
--   TITLE                       (Wendy small, bold uppercase)
--   Artist  ·  M:SS  ·  BPM     (Common Normal, muted)
--
-- Positioned relative to the parent MusicWheel frame; the +24 offset from
-- the bottom of the jacket row (ITEM_H/2 +24) puts the title just inside
-- the info backdrop with room to breathe above it.
---------------------------------------------------------------------------
local args = ...
local wheel_config = args.wheel_config
local ITEM_H = wheel_config.item_h

local FormatDuration = function(seconds)
	if not seconds or seconds <= 0 then return "" end
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds - m*60)
	return ("%d:%02d"):format(m, s)
end

local FormatBPM = function(song)
	if not song then return "" end
	if StringifyDisplayBPMs then
		local ok, res = pcall(StringifyDisplayBPMs)
		if ok and res and res ~= "" then return res end
	end
	local dbpm = song:GetDisplayBpms()
	if dbpm and dbpm[1] and dbpm[2] then
		if math.floor(dbpm[1]) == math.floor(dbpm[2]) then
			return tostring(math.floor(dbpm[1]))
		else
			return ("%d - %d"):format(math.floor(dbpm[1]), math.floor(dbpm[2]))
		end
	end
	return ""
end

return Def.ActorFrame{
	Name = "SongInfoBar",
	InitCommand = function(self)
		self:y(ITEM_H/2 + 28)
	end,

	-- ---------- Title ----------
	LoadFont("Wendy/_wendy small")..{
		Name = "Title",
		InitCommand = function(self)
			self:zoom(0.5):diffuse(Color.White):shadowlength(1)
				:maxwidth( _screen.w * 1.6 )
		end,
		OnCommand = function(self) self:playcommand("Set") end,
		CurrentSongChangedMessageCommand = function(self) self:playcommand("Set") end,
		SetCommand = function(self)
			local s = GAMESTATE:GetCurrentSong()
			self:settext( s and s:GetDisplayMainTitle():upper() or "" )
		end,
	},

	-- ---------- Artist / duration / BPM ----------
	LoadFont("Common Normal")..{
		Name = "Meta",
		InitCommand = function(self)
			self:y(22):zoom(0.8):diffuse(color("#cfd6dc")):shadowlength(0.5)
				:maxwidth( _screen.w * 1.25 )
		end,
		OnCommand = function(self) self:playcommand("Set") end,
		CurrentSongChangedMessageCommand = function(self) self:playcommand("Set") end,
		SetCommand = function(self)
			local s = GAMESTATE:GetCurrentSong()
			if not s then self:settext(""); return end
			local artist = s:GetDisplayArtist() or ""
			local dur    = FormatDuration(s:MusicLengthSeconds())
			local bpm    = FormatBPM(s)
			local parts = {}
			if artist ~= "" then parts[#parts+1] = artist end
			if dur    ~= "" then parts[#parts+1] = dur    end
			if bpm    ~= "" then parts[#parts+1] = bpm .. " BPM" end
			-- U+2022 bullet, raw UTF-8 for Lua 5.1 compatibility.
			self:settext( table.concat(parts, "   \226\128\162   ") )
		end,
	},
}
