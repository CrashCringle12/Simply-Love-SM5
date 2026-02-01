-- Currently the Density Graph in SSM doesn't work for Courses.
-- Disable the functionality.
if GAMESTATE:IsCourseMode() then return end

local player = ...
local pn = ToEnumShortString(player)


-- Height and width of the density graph.
local height = 64
local width = IsUsingWideScreen() and 300 or 268

-- In 2-players mode, whether the DensityGraph or PatternInfo is shown
-- Can be toggled by the code "ToggleChartInfo" in metrics.ini
local showPatternInfo = false

local af = Def.ActorFrame{
	InitCommand=function(self)
		if hiddenUI() then
			self:visible(false)
		else
			self:visible(GAMESTATE:IsHumanPlayer(player))
		end
		self:xy(IsUsingWideScreen() and  _screen.cx-192 or  _screen.cx-176, _screen.cy+20):zoom(0.92)

		if player == PLAYER_2 then
			self:addy(height+12)
		else
			self:addy(-2)
		end

		if IsUsingWideScreen() then
			self:addx(0)
		end
	end,
	PlayerJoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:visible(hiddenUI())
		end
	end,
	PlayerUnjoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:visible(false)
		end
	end,
	PlayerProfileSetMessageCommand=function(self, params)
		if params.Player == player then
			self:queuecommand("Redraw")
		end
	end,
	CodeMessageCommand=function(self, params)
		-- Toggle between the density graph and the pattern info
		if params.Name == "TogglePatternInfo" and params.PlayerNumber == player then
			-- Only need to toggle in versus since in single player modes, both
			-- panes are already displayed.
			if GAMESTATE:GetNumSidesJoined() == 2 then
				showPatternInfo = not showPatternInfo
				self:queuecommand("TogglePatternInfo")
			end
		end
	end,
}

-- Background quad for the density graph
af[#af+1] = Def.Quad{
	InitCommand=function(self)
		self:diffuse(color("#1e282f")):zoomto(width, height)
		if ThemePrefs.Get("RainbowMode") then
			self:diffusealpha(0.9)
		end
		if ThemePrefs.Get("VisualStyle") == "Technique" then
			self:diffusealpha(0.5)
		end
	end
}

af[#af+1] = Def.ActorFrame{
	Name="ChartParser",
	-- Hide when scrolling through the wheel. This also handles the case of
	-- going from song -> folder. It will get unhidden after a chart is parsed
	-- below.
	CurrentSongChangedMessageCommand=function(self)
		self:queuecommand("Hide")
	end,
	["CurrentSteps"..pn.."ChangedMessageCommand"]=function(self)
		self:queuecommand("Hide")
		self:stoptweening()
		self:sleep(0.4)
		self:queuecommand("ParseChart")
	end,
	ParseChartCommand=function(self)
		local steps = GAMESTATE:GetCurrentSteps(player)
		if steps then
			MESSAGEMAN:Broadcast(pn.."ChartParsing")
			ParseChartInfo(steps, pn)
			self:queuecommand("Show")
		end
	end,
	ShowCommand=function(self)
		if GAMESTATE:GetCurrentSong() and
				GAMESTATE:GetCurrentSteps(player) then
			MESSAGEMAN:Broadcast(pn.."ChartParsed")
			self:queuecommand("Redraw")
		else
			self:queuecommand("Hide")
		end
	end
}

local af2 = af[#af]

-- The Density Graph itself. It already has a "RedrawCommand".
af2[#af2+1] = NPS_Histogram(player, width, height)..{
	Name="DensityGraph",
	OnCommand=function(self)
		self:addx(-width/2):addy(height/2)
	end,
	HideCommand=function(self)
		self:visible(false)
	end,
	RedrawCommand=function(self)
		self:visible(not showPatternInfo)
	end,
	TogglePatternInfoCommand=function(self)
		self:visible(not showPatternInfo)
	end
}
-- Don't let the density graph parse the chart.
-- We do this in parent actorframe because we want to "stall" before we parse.
af2[#af2]["CurrentSteps"..pn.."ChangedMessageCommand"] = nil

-- The Peak NPS text
local peakNPSText = THEME:GetString("ScreenGameplay", "PeakNPS")
af2[#af2+1] = LoadFont("Common Normal")..{
	Name="NPS",
	Text=peakNPSText..": ",
	InitCommand=function(self)
		self:horizalign(left):zoom(0.8)
		if player == PLAYER_1 then
			self:addx(60):addy(-41)
		else
			self:addx(-136):addy(-41)
		end
		-- We want black text in Rainbow mode except during HolidayCheer(), white otherwise.
		self:diffuse((ThemePrefs.Get("RainbowMode") and not HolidayCheer()) and {0, 0, 0, 1} or {1, 1, 1, 1})
	end,
	HideCommand=function(self)
		self:settext(peakNPSText..": ")
		self:visible(false)
	end,
	RedrawCommand=function(self)
		if SL[pn].Streams.PeakNPS ~= 0 then
			self:settext((peakNPSText..": %.1f"):format(SL[pn].Streams.PeakNPS * SL.Global.ActiveModifiers.MusicRate))
			self:visible(not showPatternInfo)
		end
	end,
	TogglePatternInfoCommand=function(self)
		self:visible(not showPatternInfo)
	end
}

-- Breakdown
af2[#af2+1] = Def.ActorFrame{
	Name="Breakdown",
	InitCommand=function(self)
		local actorHeight = 17
		self:addy(height/2 - actorHeight/2)
	end,
	HideCommand=function(self)
		self:visible(false)
	end,
	RedrawCommand=function(self)
		self:visible(not showPatternInfo)
	end,
	TogglePatternInfoCommand=function(self)
		self:visible(not showPatternInfo)
	end,
	Def.Quad{
		InitCommand=function(self)
			local bgHeight = 17
			self:diffuse(color("#000000")):zoomto(width, bgHeight):diffusealpha(0.5)
		end
	},

	LoadFont("Common Normal")..{
		Text="",
		Name="BreakdownText",
		InitCommand=function(self)

			local textZoom = 0.8
			self:maxwidth(width/textZoom):zoom(textZoom)
		end,
		HideCommand=function(self)
			self:settext("")
		end,
		RedrawCommand=function(self)
			local textZoom = 0.8
			self:settext(GenerateBreakdownText(pn, 0))
			local minimization_level = 1
			while self:GetWidth() > (width/textZoom) and minimization_level < 4 do
				self:settext(GenerateBreakdownText(pn, minimization_level))
				minimization_level = minimization_level + 1
			end
		end,
	}
}

af2[#af2+1] = Def.ActorFrame{
	Name="PatternInfo",
	InitCommand=function(self)
		if GAMESTATE:GetNumSidesJoined() == 2 then
			self:y(0)
		else
			self:y(74 * (player == PLAYER_1 and 1 or -1.25))
		end
		self:visible(GAMESTATE:GetNumSidesJoined() == 1)
	end,
	PlayerJoinedMessageCommand=function(self, params)
		self:visible(GAMESTATE:GetNumSidesJoined() == 1)
		if GAMESTATE:GetNumSidesJoined() == 2 then
			self:y(0)
		else
			self:y(74 * (player == PLAYER_1 and 1 or -1.25))
		end
	end,
	PlayerUnjoinedMessageCommand=function(self, params)
		self:visible(GAMESTATE:GetNumSidesJoined() == 1)
		if GAMESTATE:GetNumSidesJoined() == 2 then
			self:y(0)
		else
			self:y(74 * (player == PLAYER_1 and 1 or -1))
		end
	end,
	TogglePatternInfoCommand=function(self)
		self:visible(showPatternInfo)
	end,

	-- Background for the additional chart info.
	-- Only shown in 1 Player mode
	Def.Quad{
		InitCommand=function(self)
			self:diffuse(color("#1e282f")):zoomto(width, height)
			if ThemePrefs.Get("VisualStyle") == "Technique" then
				self:diffusealpha(0.5)
			end
		end,
	}
}

local af3 = af2[#af2]

local layout = {
	{"Crossovers", "Footswitches"},
	{"Sideswitches", "Jacks"},
	{"Brackets", "Total Stream"},
}

local colSpacing = 150
local rowSpacing = 20
local noneText = THEME:GetString("SLPlayerOptions", "None")
local totalStreamText = THEME:GetString("SLPlayerOptions", "TotalStream")

for i, row in ipairs(layout) do
	for j, col in pairs(row) do
		af3[#af3+1] = LoadFont("Common normal")..{
			Text=(col ~= totalStreamText and "0" or noneText).." (0.0%)",
			Name=col .. "Value",
			InitCommand=function(self)
				local textHeight = 17
				local textZoom = 0.8
				self:zoom(textZoom):horizalign(right)
				if col == "Total Stream" then
					self:maxwidth(100)
				end
				self:xy(-width/2 + 40, -height/2 + 13)
				self:addx((j-1)*colSpacing)
				self:addy((i-1)*rowSpacing)
			end,
			HideCommand=function(self)
				if col ~= "Total Stream" then
					self:settext("0")
				else
					self:settext(noneText.." (0.0%)")
				end
			end,
			RedrawCommand=function(self)
				if col ~= "Total Stream" then
					self:settext(SL[pn].Streams[col])
				else
					local streamMeasures, breakMeasures = GetTotalStreamAndBreakMeasures(pn)
					local totalMeasures = streamMeasures + breakMeasures
					if streamMeasures == 0 then
						self:settext(noneText.." (0.0%)")
					else
						self:settext(string.format("%d/%d (%0.1f%%)", streamMeasures, totalMeasures, streamMeasures/totalMeasures*100))
					end
				end
			end
		}

		af3[#af3+1] = LoadFont("Common Normal")..{
			Text=THEME:GetString("TechCategory", col),
			Name=col,
			InitCommand=function(self)
				local textHeight = 17
				local textZoom = 0.8
				self:maxwidth(width/textZoom):zoom(textZoom):horizalign(left)
				self:xy(-width/2 + 50, -height/2 + 13)
				self:addx((j-1)*colSpacing)
				self:addy((i-1)*rowSpacing)
			end,
		}

	end
end

local num_segments = 7
local amv_reference

local ComputeVertices = function()
	local verts = {}
	local angle = (math.pi*2) / num_segments
	for i=1, num_segments+1 do
	  --                                   x,                  y,   z,   Color.White
	  table.insert(verts, {{math.sin(i*angle),  math.cos(i*angle),  1},  {1,1,1,1}})
	end
	return verts
  end
  
-- Helper function to compute vertices from raw tech counts with a cap.
local function ComputeVerticesFromRawValues(rawValues)
    local verts = {}
    local num_segments = #rawValues
    local angleIncrement = (math.pi * 2) / num_segments
    local baseline = 5         -- Minimum radius for each vertex (adjust as needed)
    local scalingFactor = 2    -- Multiplier for the raw tech count
    local maxRadius = 80      -- Maximum radius cap; change this single variable to control the cap.
    for i = 1, num_segments do
        local angle = (i - 1) * angleIncrement  -- Start at angle 0 for first category
        local computedRadius = baseline + rawValues[i] * scalingFactor
        local radius = math.min(computedRadius, maxRadius)
        local x = math.sin(angle) * radius
        local y = math.cos(angle) * radius
        table.insert(verts, { { x, y, 0 }, { 1, 1, 1, 1 } })
    end
    -- Repeat the first vertex to close the polygon.
    table.insert(verts, verts[1])
    return verts
end

-- local lineColor = color("#cccccc")
-- af3[#af3+1] = Def.ActorFrame{
-- 	InitCommand=function(self)
-- 		if #GAMESTATE:GetHumanPlayers() == 2 then
-- 			self:xy(width/2 +40, height/2 - (pn == "P1" and 30 or -45)):rotationz(77):zoom(0.55)

-- 		else
-- 			self:xy(width/2 +40, height/2 - 35):rotationz(77):zoom(0.55)

-- 		end
-- 	end,
-- 	RedrawCommand=function(self)
-- 		self:visible(true)
-- 	end,
-- 	HideCommand=function(self)
-- 		self:visible(false)
-- 	end,
-- 	Def.ActorMultiVertex{
-- 		InitCommand=function(self)
-- 			-- these coordinates aren't neat and tidy, but they do create three triangles
-- 			-- that fit together to approximate hurtpiggypig's original png asset
-- 			local verts = {}
-- 			-- Set verts to an empty table then lets use it to draw a circle with for loops
-- 			for i=1,360 do
-- 				verts[i] = {{math.cos(i)*10,math.sin(i)*10,0},{1,1,1,0.25}}
-- 			end
-- 			self:SetDrawState({Mode=6}):SetVertices(verts)
-- 			self:diffuse(Color.Black):diffusealpha(0.01)
-- 			self:zoom(7.75)
-- 		end
-- 	},
-- 	Def.ActorMultiVertex{
-- 		InitCommand=function(self)
-- 			-- these coordinates aren't neat and tidy, but they do create three triangles
-- 			-- that fit together to approximate hurtpiggypig's original png asset
-- 			local verts = {}
-- 			-- Set verts to an empty table then lets use it to draw a circle with for loops
-- 			for i=1,360 do
-- 				verts[i] = {{math.cos(i)*10,math.sin(i)*10,0},{1,1,1,0.25}}
-- 			end
-- 			self:SetDrawState({Mode=6}):SetVertices(verts)
-- 			self:diffuse(color("f5f5f5")):diffusealpha(0.05)
-- 			self:zoom(7)
-- 		end
-- 	},
-- 	Def.ActorMultiVertex{
-- 		Name="LifeLine_AMV",
-- 		InitCommand=function(self)
-- 		amv_reference = self
-- 			self:SetDrawState({Mode="DrawMode_Fan"})
-- 				:SetLineWidth( 1 ):zoom(65):diffuse(color("f6e8c9")):diffusealpha(0.25)
-- 				:queuecommand("SetVertices")
			
-- 		end,
-- 		SetVerticesCommand=function(self)
-- 			local verts = ComputeVertices()
-- 			self:SetNumVertices(#verts):SetVertices(verts)
-- 		end
-- 	},
-- 	Def.ActorMultiVertex{
-- 		Name="LifeLine_AMV",
-- 		InitCommand=function(self)
-- 		amv_reference = self
-- 			self:SetDrawState({Mode="DrawMode_LineStrip"})
-- 				:SetLineWidth( 1 ):zoom(65):diffuse(lineColor)
-- 				:queuecommand("SetVertices")
			
-- 		end,
-- 		SetVerticesCommand=function(self)
-- 			local verts = ComputeVertices()
-- 			self:SetNumVertices(#verts):SetVertices(verts)
-- 		end
-- 	},
-- 	Def.ActorMultiVertex{
-- 		Name="LifeLine_AMV",
-- 		InitCommand=function(self)
-- 		amv_reference = self
-- 			self:SetDrawState({Mode="DrawMode_LineStrip"})
-- 				:SetLineWidth( 1 ):zoom(50):diffuse(lineColor)
-- 				:queuecommand("SetVertices")
			
-- 		end,
-- 		SetVerticesCommand=function(self)
-- 			local verts = ComputeVertices()
-- 			self:SetNumVertices(#verts):SetVertices(verts)
-- 		end
-- 	},
-- 	Def.ActorMultiVertex{
-- 		Name="LifeLine_AMV",
-- 		InitCommand=function(self)
-- 		amv_reference = self
-- 			self:SetDrawState({Mode="DrawMode_LineStrip"})
-- 				:SetLineWidth( 1 ):zoom(35):diffuse(lineColor)
-- 				:queuecommand("SetVertices")
-- 		end,
-- 	  SetVerticesCommand=function(self)
-- 		local verts = ComputeVertices()
-- 		self:SetNumVertices(#verts):SetVertices(verts)
-- 	  end
-- 	},
-- 	Def.ActorMultiVertex{
-- 		Name="LifeLine_AMV",
-- 		InitCommand=function(self)
-- 		amv_reference = self
-- 			self:SetDrawState({Mode="DrawMode_LineStrip"})
-- 				:SetLineWidth( 1 ):zoom(20):diffuse(lineColor)
-- 				:queuecommand("SetVertices")
-- 		end,
-- 	  SetVerticesCommand=function(self)
-- 		local verts = ComputeVertices()
-- 		self:SetNumVertices(#verts):SetVertices(verts)
-- 	  end
-- 	},
-- 	Def.ActorMultiVertex{
-- 		Name = "GrooveRadar_AMV",
-- 		InitCommand = function(self)
-- 			self:zoom(0.85)
-- 				:SetDrawState({ Mode = 2})
-- 				:SetLineWidth(1):diffuse(color("#ff6384")):diffusealpha(0.5)
-- 				:queuecommand("Redraw")
-- 		end,
-- 		RedrawCommand = function(self)
-- 			-- Gather raw tech counts.
-- 			local rawValues = { 0, 0, 0, 0, 0, 0, 0 }
-- 			if GAMESTATE:GetCurrentSong() and GAMESTATE:GetCurrentSteps(player) then
-- 				local techCounts = GAMESTATE:GetCurrentSteps(player):CalculateTechCounts(player)
-- 				local crossovers    = techCounts:GetValue("TechCountsCategory_Crossovers")    or 0
-- 				local footswitches  = techCounts:GetValue("TechCountsCategory_Footswitches")    or 0
-- 				local sideswitches  = techCounts:GetValue("TechCountsCategory_Sideswitches")    or 0
-- 				local jacks         = techCounts:GetValue("TechCountsCategory_Jacks")           or 0
-- 				local brackets      = techCounts:GetValue("TechCountsCategory_Brackets")        or 0
-- 				local doublesteps   = techCounts:GetValue("TechCountsCategory_Doublesteps")     or 0
-- 				local streamMeasures, breakMeasures = GetTotalStreamAndBreakMeasures(pn)
-- 				local stream = streamMeasures or 0
				
-- 				rawValues = {
-- 					crossovers,
-- 					sideswitches,
-- 					footswitches,
-- 					jacks,
-- 					doublesteps,
-- 					brackets,
-- 					stream
-- 				}
-- 			end
-- 			local verts = ComputeVerticesFromRawValues(rawValues)
-- 			self:SetNumVertices(#verts):SetVertices(verts)
-- 		end
-- 	},
-- }



-- af3[#af3+1] = Def.ActorFrame{
-- 	InitCommand=function(self)
-- 		if #GAMESTATE:GetHumanPlayers() == 2 then
-- 			self:xy(width/2 -100, height/2 - (pn == "P1" and 30 or -45)):rotationz(77):zoom(0.55)

-- 		else
-- 			self:xy(width/2 -100, height/2 - 35):rotationz(77):zoom(0.55)

-- 		end
-- 	end,
-- 	RedrawCommand=function(self)
-- 		self:visible(true)
-- 	end,
-- 	HideCommand=function(self)
-- 		self:visible(false)
-- 	end,
-- 	Def.ActorMultiVertex{
-- 		InitCommand=function(self)
-- 			-- these coordinates aren't neat and tidy, but they do create three triangles
-- 			-- that fit together to approximate hurtpiggypig's original png asset
-- 			local verts = {}
-- 			-- Set verts to an empty table then lets use it to draw a circle with for loops
-- 			for i=1,360 do
-- 				verts[i] = {{math.cos(i)*10,math.sin(i)*10,0},{1,1,1,0.25}}
-- 			end
-- 			self:SetDrawState({Mode=6}):SetVertices(verts)
-- 			self:diffuse(Color.Black):diffusealpha(0.01)
-- 			self:zoom(7.75)
-- 		end
-- 	},
-- 	Def.ActorMultiVertex{
-- 		InitCommand=function(self)
-- 			-- these coordinates aren't neat and tidy, but they do create three triangles
-- 			-- that fit together to approximate hurtpiggypig's original png asset
-- 			local verts = {}
-- 			-- Set verts to an empty table then lets use it to draw a circle with for loops
-- 			for i=1,360 do
-- 				verts[i] = {{math.cos(i)*10,math.sin(i)*10,0},{1,1,1,0.25}}
-- 			end
-- 			self:SetDrawState({Mode=6}):SetVertices(verts)
-- 			self:diffuse(color("f5f5f5")):diffusealpha(0.05)
-- 			self:zoom(7)
-- 		end
-- 	},
-- 	Def.ActorMultiVertex{
-- 		Name="LifeLine_AMV",
-- 		InitCommand=function(self)
-- 		amv_reference = self
-- 			self:SetDrawState({Mode="DrawMode_Fan"})
-- 				:SetLineWidth( 1 ):zoom(65):diffuse(color("f6e8c9")):diffusealpha(0.25)
-- 				:queuecommand("SetVertices")
			
-- 		end,
-- 		SetVerticesCommand=function(self)
-- 			local verts = ComputeVertices()
-- 			self:SetNumVertices(#verts):SetVertices(verts)
-- 		end
-- 	},
-- 	Def.GrooveRadar{
-- 		Name="GrooveRadar",
-- 		InitCommand=function(self)
-- 			self:visible(true):zoom(3)
-- 			self:queuecommand("Redraw")
-- 		end,

-- 		RedrawCommand=function(self)
-- 			if GAMESTATE:GetCurrentSong() and
-- 				GAMESTATE:GetCurrentSteps(player) then
-- 					local radarValues = GAMESTATE:GetCurrentSteps(player):GetRadarValues(player)
-- 					self:SetFromRadarValues(player, radarValues)
-- 				end
-- 		end
-- 	}
-- }


-- XO Skill:  XS count + 20.6 · (BPM – 100)

-- JA Skill:  JS count + 0.9 · (BPM – 100)

-- FS Skill:  FS count + (BPM – 100) · [≈0.48 for high BPM; ≈1.0 when BPM ≈105]

-- DS Skill:  (hidden DS count) + 0.5 · (BPM – 100)

-- BR Skill:  BR count + (11 – Peak NPS) · ≈7.2

-- Stamina Skill: (stream count) · (BPM ÷ ~27)
return af
