return Def.ActorFrame {
	Def.Quad{
		InitCommand=function(self) self:FullScreen():diffuse(0,0,0,0) end,
		OnCommand=function(self) self:sleep(0.5):linear(1):diffusealpha(1) end,
		OffCommand=function(self)
			if SL.Global.GameMode == "ITG" then
				local song = GAMESTATE:GetCurrentSong()
				for player in ivalues( GAMESTATE:GetHumanPlayers() ) do
					local pn = ToEnumShortString(player)
					local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
					local number = pss:GetTapNoteScores("TapNoteScore_W1")
					local faPlus = SL[pn].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1].ex_counts.W0_total
					-- Subtract FA+ count from the overall fantastic window count.
					local whites = number - faPlus
					-- This will save the white count to Stats.xml, so we can later recover
					-- it when we deprecate FA+ mode and introduce W0.
					--
					-- The Score field is completely unused in Simply Love, and the ability
					-- to set the field is exposed to lua so we can hijack it for our own\
					-- purposes.
					local bestWhites = whites
					if PROFILEMAN:IsPersistentProfile(pn) then
						local steps = GAMESTATE:GetCurrentSteps(pn)
						local scores = PROFILEMAN:GetProfile(pn):GetHighScoreList(song, steps):GetHighScores()
						for hs in ivalues(scores) do
							-- If the player previously quadded the song, retain the better white count.
							-- Technically this is a workaround because the date would be wrong, but
							-- it's still worth to keep the score around
							if (pss:GetPercentDancePoints() == hs:GetPercentDP() and hs:GetPercentDP() == 1.0) then
								bestWhites = math.min(bestWhites, hs:GetScore())
							end
						end
					end
					pss:SetScore(bestWhites)
				end
			end
		end
	},
	Def.ActorFrame{
		Name="RaveMessages";
		InitCommand=function(self)
			raveChildren = self:GetChildren()
			self:visible(GAMESTATE:GetPlayMode() == 'PlayMode_Rave')

			raveChildren.P1Win:visible(false)
			raveChildren.P2Win:visible(false)
			raveChildren.Draw:visible(false)
		end;
		OffCommand=function(self)
			local p1Win = GAMESTATE:IsWinner(PLAYER_1)
			local p2Win = GAMESTATE:IsWinner(PLAYER_2)

			if GAMESTATE:IsWinner(PLAYER_1) then
				raveChildren.P1Win:visible(true)
			elseif GAMESTATE:IsWinner(PLAYER_2) then
				raveChildren.P2Win:visible(true)
			else
				raveChildren.Draw:visible(true)
			end
		end;

		LoadActor(THEME:GetPathG("_rave result","P1"))..{
			Name="P1Win";
			InitCommand=cmd(Center;cropbottom,1;fadebottom,1;);
			StartTransitioningCommand=cmd(sleep,1.0;linear,0.5;cropbottom,0;fadebottom,0;sleep,1.75;linear,0.25;diffusealpha,0);
		};
		LoadActor(THEME:GetPathG("_rave result","P2"))..{
			Name="P2Win";
			InitCommand=cmd(Center;cropbottom,1;fadebottom,1;);
			StartTransitioningCommand=cmd(sleep,1.0;linear,0.5;cropbottom,0;fadebottom,0;sleep,1.75;linear,0.25;diffusealpha,0);
		};
		LoadActor(THEME:GetPathG("_rave result","draw"))..{
			Name="Draw";
			InitCommand=cmd(Center;cropbottom,1;fadebottom,1;);
			StartTransitioningCommand=cmd(sleep,1.0;linear,0.5;cropbottom,0;fadebottom,0;sleep,1.75;linear,0.25;diffusealpha,0);
		};
	};
}