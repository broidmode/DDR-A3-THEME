local t = Def.ActorFrame {};

t[#t+1] = loadfile(THEME:GetPathB("","_normaldoors"))()..{
	StartTransitioningCommand=function(s) s:playcommand("AnimClose") end,
};

return t;
