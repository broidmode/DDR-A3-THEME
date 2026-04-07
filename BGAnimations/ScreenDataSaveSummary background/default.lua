local t = Def.ActorFrame{};

if IsGoldenLeague() then
	t[#t+1] = loadfile(THEME:GetPathB("ScreenGameplay","out/_doors"))()..{
		OnCommand=function(s) s:playcommand("AnimStand") end,
	};
else
	t[#t+1] = loadfile(THEME:GetPathB("","_normaldoors"))()..{
		OnCommand=function(s) s:finishtweening():playcommand("AnimStand") end,
	};
end

return t;