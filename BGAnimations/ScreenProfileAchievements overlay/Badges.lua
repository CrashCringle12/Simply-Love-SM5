
local binfo = ...
local apple = ""
local pages = binfo.pages
local currPage = 0;
local rows = binfo.rows
local maxRows = math.max(rows, 4)
local cols = binfo.cols 
local accolades = binfo.achievements
local activePack = "Default"
local rowOffset = 0

local fallbackIcon = THEME:GetCurrentThemeDirectory() .. "BGAnimations/ScreenProfileAchievements overlay/medal 4x3.png"
local itlTrophyIcon = THEME:GetCurrentThemeDirectory() .. "Other/Achievements/ITL/Trophy.png"

local GetPackTable = function(packName)
	if type(SL) == "table" and type(SL.Accolades) == "table" and type(SL.Accolades.Achievements) == "table" then
		local pack = SL.Accolades.Achievements[packName]
		if type(pack) == "table" then return pack end
	end
	return nil
end

local GetAchievementAt = function(packName, index)
	local pack = GetPackTable(packName)
	if not pack then return nil end
	if type(index) ~= "number" or index < 1 then return nil end
	return pack[index]
end

local ResolveIconPath = function(packName, achievement)
	if packName == "ITL" and FILEMAN:DoesFileExist(itlTrophyIcon) then
		return itlTrophyIcon
	end

	if type(achievement) == "table" and type(achievement.Icon) == "string" and achievement.Icon ~= "" then
		local custom = THEME:GetCurrentThemeDirectory() .. "Other/Achievements/" .. packName .. "/" .. achievement.Icon
		if FILEMAN:DoesFileExist(custom) then
			return custom
		end
	end

	if FILEMAN:DoesFileExist(fallbackIcon) then
		return fallbackIcon
	end

	return nil
end

local GetProfilePack = function(params)
	if not params or type(params.achievements) ~= "table" then return nil end
	local pack = params.achievements[params.activePack]
	if type(pack) == "table" then return pack end
	return nil
end

local GetTotalForPack = function(params)
	local pack = GetPackTable(params.activePack)
	local machineTotal = pack and #pack or 0
	local profilePack = GetProfilePack(params)
	local profileTotal = profilePack and #profilePack or 0
	if machineTotal > profileTotal then return machineTotal end
	return profileTotal
end

local ResolveUnlockedDiffuse = function(params, index)
	local packName = params and params.activePack
	if type(packName) ~= "string" then return nil end

	local definition = GetAchievementAt(packName, index)
	if type(definition) ~= "table" then return nil end

	local c = definition.UnlockedDiffuse
	if type(c) ~= "table" then return nil end

	local r = tonumber(c[1] or c.r)
	local g = tonumber(c[2] or c.g)
	local b = tonumber(c[3] or c.b)
	local a = tonumber(c[4] or c.a) or 1
	if not r or not g or not b then return nil end

	return r, g, b, a
end

local GetRowsForPack = function(params)
	local total = GetTotalForPack(params)
	if total > 100 then
		return 4
	end
	return rows
end

local GetGridMetrics = function(activeRows)
	if activeRows >= 4 then
		return {
			badgeSize = 40,
			yStep = 46,
			baseY = -25,
		}
	end

	return {
		badgeSize = 50,
		yStep = 68,
		baseY = -25,
	}
end
local achievements = Def.ActorFrame {
	Name="Badges",
	-- Def.Quad {
	-- 	InitCommand=function(self)
	-- 		self:zoomto(binfo.w+24,3):rotationz(0):align(0,0):xy(-124,-18):diffusealpha(0)
	-- 		if ThemePrefs.Get("RainbowMode") then self:diffuse(0,0,0,0) end
	-- 	end,
	-- 	OnCommand=function(self) self:sleep(0.45):linear(0.1):diffusealpha(0) end,
	-- 	PageMessageCommand=function(self, params)
	-- 		if params.Player ~= binfo.player then return; end;
	-- 		if params.Page ~= 0 then
	-- 			currPage = params.Page
	-- 			self:linear(0.1):diffusealpha(0.8)
	-- 		else
	-- 			self:linear(0.1):diffusealpha(0)
	-- 		end
	-- 	end,
	-- },
	-- LoadFont("Wendy/_wendy white")..{
	-- 	Name='Achievements',
	-- 	InitCommand=function(self)
	-- 		self:settext("Achievements")
	-- 		self:y(binfo.y+148):zoom(0.20):shadowlength(ThemePrefs.Get("RainbowMode") and 0.5 or 0):cropright(1):diffusealpha(0)
	-- 	end,
	-- 	OnCommand=function(self) self:sleep(0.2):smooth(0.2):cropright(0) end,
	-- 	PageMessageCommand=function(self, params)
	-- 		if params.Player ~= binfo.player then return; end
	-- 		if params.Page ~= 0 then
	-- 			self:linear(0.1):diffusealpha(1)
	-- 		else
	-- 			self:linear(0.1):diffusealpha(0)
	-- 		end
	-- 	end,
	-- }
}

-- for loop to create 4 rows and 4 columns of badges
for p=1,pages do
	local badges = Def.ActorFrame {
		InitCommand=function(self)
			self:x(-28):y(-20):diffusealpha(0):zoom(1)
		end,
		PageMessageCommand=function(self, params)
			if params.Player ~= binfo.player then return; end;
			if params.Page == p  then
				self:linear(0.2):diffusealpha(1):zoom(1):visible(true)	
			else
				self:linear(0.4):diffusealpha(0):linear(0.01):zoom(1)
			end
		end,
	}
	local pI = ((p-1)*cols)
	local pY = ((p-1)*rows)
	-- 
	for j=1,maxRows do
		for i=1,cols do
				badges[#badges+1] = Def.ActorFrame {
					InitCommand=function(self)
						--self:xy(0,0)
						self:visible(true)
					end,
					Def.Sprite {
						Texture=fallbackIcon,
						InitCommand=function(self)
							local metrics = GetGridMetrics(rows)
							local index = (j-1)*cols + i+pI+rowOffset+rowOffset
							local achievement = GetAchievementAt(activePack, index)
							local iconPath = ResolveIconPath(activePack, achievement)
							self:visible(true):diffusealpha(1)
							if iconPath then
								self:Load(iconPath)
							else
								self:visible(false)
							end
							self:zoomto(metrics.badgeSize,metrics.badgeSize):align(0,0):xy(-400+(90*i),metrics.baseY+(metrics.yStep*((j-1)%maxRows))):diffusealpha(0)
							self:diffuse(0.1,0,0.1,1)
							--self:setstate(math.random(1,11))
							if math.random(0,100) % 30 == 0 then
								self:SetAllStateDelays(0.3)
							else
								self:animate(false)
							end
						end,
						OnCommand=function(self) 
							self:sleep(0.45):linear(0.1):diffusealpha(0.5) 
						end,
						GlowCommand=function(self)
							self:glowshift():effectcolor1(1,1,1,0.7):effectcolor2(1,1,1,0.1):effectperiod(1)
						end,
						UnGlowCommand=function(self)
							self:stopeffect()
						end,
						PageMessageCommand=function(self, params)
							-- no-op; icon selection occurs in MigratoMessageCommand
						end,
						MigratoMessageCommand=function(self, params)
							local activeRows = GetRowsForPack(params)
							local pageCapacity = activeRows * cols
							local metrics = GetGridMetrics(activeRows)

							if j > activeRows then
								self:visible(false)
								self:queuecommand("UnGlow")
								return
							end
							-- TODO FIX THISSSS
							if params.achievements then
								-- If we exceed the number of rows * cols then increment the row offset
								if params.achievementIndex > (pageCapacity+rowOffset) then
									rowOffset = rowOffset + cols
								elseif params.achievementIndex <= (pageCapacity+rowOffset-pageCapacity) then
									rowOffset = rowOffset - cols
								end
							end
							if params.Page then
								rowOffset = params.Page
							end
							if true then
								local index = (j-1)*cols + i+pI+rowOffset
								local machineAchievement = GetAchievementAt(params.activePack, index)
								local profileAchievement = params.achievements and params.achievements[params.activePack] and params.achievements[params.activePack][index] or nil
								local achievement = machineAchievement or profileAchievement
								local iconPath = ResolveIconPath(params.activePack, achievement)
								if iconPath then
									self:Load(iconPath)
									self:visible(true)
								else
									self:visible(false)
								end
								self:zoomto(metrics.badgeSize,metrics.badgeSize):align(0,0):xy(-400+(90*i),metrics.baseY+(metrics.yStep*((j-1)%maxRows))):diffusealpha(0)
								self:diffuse(0.1,0,0.1,1)
								--self:setstate(math.random(1,11))
								if math.random(0,100) % 30 == 0 then
									self:SetAllStateDelays(0.3)
								else
									self:animate(false)
								end
								if (j*i >= 20) then
									activePack = params.activePack
								end
							end
							if params.achievements then
								local index = (j-1)*cols + i+pI+rowOffset
								local total = GetTotalForPack(params)
								if index <= total then
									self:visible(true)
									if params.achievements[params.activePack     ] then
										if params.achievements[params.activePack     ][index] then
											if params.achievements[params.activePack     ][index].Unlocked then
												local r, g, b, a = ResolveUnlockedDiffuse(params, index)
												if r then
													self:diffuse(r, g, b, a)
												else
													self:diffuse(1,1,1,1)
												end
											else
												self:diffuse(0.1,0,0.1,0.5)
											end
										else
											self:diffuse(0.1,0,0.1,0.5)
										end
									else
										self:diffuse(0.1,0,0.1,0.5)
									end
								else
									self:visible(false)
								end
							end
							if ( (j-1)*cols + i+pI+rowOffset) == params.achievementIndex then
								self:queuecommand("Glow")
							else
								self:queuecommand("UnGlow")
							end
						end,
						
					},
		
				}
		end
	end
	achievements[#achievements+1] = badges
end

return achievements