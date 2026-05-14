local t = Def.ActorFrame{};

local storedStyle = getenv("ForceStyle")
if storedStyle then
  GAMESTATE:SetCurrentStyle(storedStyle)
  setenv("ForceStyle", nil)
end


local TwoPart = Def.ActorFrame{
	StartSelectingStepsMessageCommand=function(s) s:AddChildFromPath(THEME:GetPathB("ScreenSelectMusic","overlay/TwoPartDiff")) end,
	SongUnchosenMessageCommand=function(s) 
		s:sleep(0.2):queuecommand("Remove")
	end,
	RemoveCommand=function(s) s:RemoveChild("TwoPartDiff") end,
};

for _,pn in pairs(GAMESTATE:GetEnabledPlayers()) do
	t[#t+1] = loadfile(THEME:GetPathB("ScreenSelectMusic","overlay/Difficulty"))(pn)..{
		InitCommand=function(s) s:xy(pn==PLAYER_1 and SCREEN_LEFT+94 or SCREEN_RIGHT-94,_screen.cy-97):zoom(0.667) end,
	};
	t[#t+1] = Def.ActorFrame{
		loadfile(THEME:GetPathB("ScreenSelectMusic","overlay/RadarHandler/default.lua"))(pn)..{
			InitCommand=function(s) s:xy(pn==PLAYER_1 and SCREEN_LEFT+86 or SCREEN_RIGHT-86,_screen.cy+24):zoom(0.667) end,
		};
		loadfile(THEME:GetPathB("ScreenSelectMusic","overlay/TargetScore/default.lua"))(pn);
		};
	t[#t+1] = loadfile(THEME:GetPathB("ScreenSelectMusic","overlay/ShockArrows/default.lua"))(pn)..{
		InitCommand=function(s) s:xy(pn==PLAYER_1 and SCREEN_LEFT+86 or SCREEN_RIGHT-86,_screen.cy+36):zoom(0.667) end,
	};
end

t[#t+1] = loadfile(THEME:GetPathB("ScreenSelectMusic","overlay/Info"))()..{
	OnCommand=function(s) s:zoom(0.667):y(57):diffusealpha(0):sleep(0.4):linear(0.05):diffusealpha(0.75):linear(0.1):diffusealpha(0.25):linear(0.1):diffusealpha(1) end,
};
t[#t+1] = loadfile(THEME:GetPathB("ScreenSelectMusic","overlay/StageDisplay"))()..{
	OnCommand=function(s) s:zoom(0.667):diffusealpha(0):sleep(0.4):linear(0.05):diffusealpha(0.75):linear(0.1):diffusealpha(0.25):linear(0.1):diffusealpha(1) end,
};

-- DEBUG: Radar values display (remove after testing)
local debugRadar = Def.BitmapText{
	Font="_avenirnext lt pro bold/20px",
	InitCommand=function(s)
		s:xy(SCREEN_CENTER_X, SCREEN_BOTTOM-120):zoom(0.7):halign(0.5)
		s:strokecolor(color("#000000"))
	end,
	CurrentSongChangedMessageCommand=function(s) s:queuecommand("Update") end,
	CurrentStepsP1ChangedMessageCommand=function(s) s:queuecommand("Update") end,
	CurrentStepsP2ChangedMessageCommand=function(s) s:queuecommand("Update") end,
	UpdateCommand=function(s)
		local song = GAMESTATE:GetCurrentSong()
		if not song then s:settext("") return end

		local pn = GAMESTATE:GetMasterPlayerNumber()
		local steps = GAMESTATE:GetCurrentSteps(pn)
		if not steps then s:settext("No steps") return end

		local rv = steps:GetRadarValues(pn)
		local notes = rv:GetValue('RadarCategory_Notes')
		local taps = rv:GetValue('RadarCategory_TapsAndHolds')
		local jumps = rv:GetValue('RadarCategory_Jumps')
		local hands = rv:GetValue('RadarCategory_Hands')
		local holds = rv:GetValue('RadarCategory_Holds')
		local rolls = rv:GetValue('RadarCategory_Rolls')
		local mines = rv:GetValue('RadarCategory_Mines')

		local calc = taps - jumps - (hands * 2)

		s:settext(string.format(
			"Notes=%d  TapsAndHolds=%d  Jumps=%d  Hands=%d\nHolds=%d  Rolls=%d  Mines=%d\nCalc (taps-jumps-2*hands)=%d",
			notes, taps, jumps, hands, holds, rolls, mines, calc
		))
	end,
}

return Def.ActorFrame{
	OffCommand=function(s) s:finishtweening() end,
	TwoPart;
	t;
	debugRadar;
}