-- Load the video background from ScreenWithMenuElements
return LoadActor(THEME:GetPathB("ScreenWithMenuElements","background/"..Model().."background"))..{
	InitCommand=function(s)
		s:FullScreen()
	end,
};
