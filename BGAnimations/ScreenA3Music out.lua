-- Match ScreenSelectMusic out - no door animation, just sleep for transition
return Def.ActorFrame{
	StartTransitioningCommand=function(s) s:sleep(2) end,
};
