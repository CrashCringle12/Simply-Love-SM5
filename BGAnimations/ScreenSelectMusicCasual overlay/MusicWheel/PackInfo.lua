-- MusicWheel/PackInfo.lua
--
-- Bottom of the info backdrop.  Two rows:
--   Row 1 (banner):  a small pack banner sprite, centered horizontally.
--                    Hidden if the current pack has no banner file.
--   Row 2 (pack + counter):  "PackName" on the left, "N / M" on the right.
--
-- The banner uses SONGMAN:GetSongGroupBannerPath which returns "" when the
-- pack folder has no banner.png.  We hide the sprite in that case rather
-- than showing a broken fallback.  Aspect is preserved by scaletoclipped.
---------------------------------------------------------------------------
local args = ...
local wheel_config = args.wheel_config
local ITEM_H = wheel_config.item_h

-- Total horizontal extent we lay content within.
local BAND_W = _screen.w - 200

-- Pack banner dimensions -- small enough to fit inside the info backdrop
-- without competing visually with the song jackets above.
local BANNER_W = 88*2
local BANNER_H = 33*2

local af = Def.ActorFrame{
	Name = "PackInfo",
	InitCommand = function(self)
		-- Frame origin sits above the pack-name line; children position
		-- themselves relative to that origin (banner up, text down).
		self:y(ITEM_H/2 + 80)
	end,

	---------------------------------------------------------------------
	-- Row 1: pack banner
	---------------------------------------------------------------------
	Def.Sprite{
		Name = "PackBanner",
		InitCommand = function(self)
			self:y(0):setsize(BANNER_W, BANNER_H):visible(false)
		end,
		OnCommand = function(self) self:playcommand("Set") end,
		CurrentSongChangedMessageCommand = function(self) self:playcommand("Set") end,
		SetCommand = function(self)
			local s = GAMESTATE:GetCurrentSong()
			if not s then self:visible(false); return end

			local group = s:GetGroupName()
			-- SONGMAN:GetSongGroupBannerPath may not exist on very old
			-- engines; pcall around it defensively so a missing API
			-- doesn't break the screen.
			local path = ""
			if SONGMAN.GetSongGroupBannerPath then
				local ok, res = pcall(SONGMAN.GetSongGroupBannerPath, SONGMAN, group)
				if ok and type(res) == "string" then path = res end
			end

			if path == nil or path == "" then
				self:visible(false)
				return
			end
			self:visible(true):Load(path):scaletoclipped(BANNER_W, BANNER_H):halign(0):x(-BAND_W/2 - 30)
		end,
	},

	---------------------------------------------------------------------
	-- Row 2: pack name on left, N / M counter on right
	---------------------------------------------------------------------
	LoadFont("Common Normal")..{
		Name = "PackName",
		InitCommand = function(self)
			self:y(42):halign(0):x(-BAND_W/2 + 0)
				:zoom(0.85):diffuse(color("#cfd6dc")):shadowlength(0.5)
				:maxwidth(BAND_W * 0.7)
		end,
		OnCommand = function(self) self:playcommand("Set") end,
		CurrentSongChangedMessageCommand = function(self) self:playcommand("Set") end,
		SetCommand = function(self)
			local s = GAMESTATE:GetCurrentSong()
			self:settext( s and s:GetGroupName() or "" )
		end,
	},

	LoadFont("Common Normal")..{
		Name = "IndexIndicator",
		InitCommand = function(self)
			self:y(20):halign(1):x(BAND_W/2 - 20)
				:zoom(0.85):diffuse(color("#cfd6dc")):shadowlength(0.5)
				:settext("0 / 0")
		end,
		WheelPosChangedMessageCommand = function(self, params)
			if not params then return end
			self:settext( ("%d / %d"):format(params.pos or 0, params.total or 0) )
		end,
	},
}

return af
