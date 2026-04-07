local x = Def.ActorFrame{};

x[#x+1] = Def.Actor {
	OnCommand=function(self) self:sleep(2) end;
};

if IsGoldenLeague() then
	x[#x+1] = loadfile(THEME:GetPathB("ScreenGameplay","out/_doors"))() .. {
		InitCommand=function(s) s:draworder(99) end,
		OffCommand=function(s) s:queuecommand("AnimClose") end,
	};
else
	x[#x+1] = loadfile(THEME:GetPathB("","_normaldoors"))()..{
		OffCommand=function(s) s:finishtweening():playcommand("AnimClose")
			s:sleep(1.6):queuecommand("AnimStand") 
		end,
	};
end

return x;