local pn = ...
local t = Def.ActorFrame{};

local function setDiffBG1(self,param)
	local st = GAMESTATE:GetCurrentStyle():GetStepsType()
	if self.ParamSong then
		local steps = GAMESTATE:GetCurrentSteps(pn)
		if steps then
			local sDiff = steps:GetDifficulty()
			local diff = self.ParamSong:GetOneSteps( st, sDiff)
			local diffname = GAMESTATE:GetCurrentSteps(pn):GetDifficulty()
			if diff then
				self:diffuse(color("1,1,1,1"))
			else
				self:diffuse(color("1,1,1,0"))
			end;
		else
			self:diffuse(color("1,1,1,0"))
		end;
	end;
end;

local function setDiffBG2(self,param)
  local st = GAMESTATE:GetCurrentStyle():GetStepsType()
  if self.ParamSong then
    local steps = GAMESTATE:GetCurrentSteps(pn)
    if steps then
      local sDiff = steps:GetDifficulty()
			 local diff = self.ParamSong:GetOneSteps( st, sDiff)
      local diffname = GAMESTATE:GetCurrentSteps(pn):GetDifficulty()
      if diff then
  			self:diffuse(CustomDifficultyToColor(diffname));
  		else
  			self:diffuse(color("1,1,1,0"))
  		end;
  	else
  		self:diffuse(color("1,1,1,0"))
  	end;
  end;
end;

local function setDiff(self,param)
	local st = GAMESTATE:GetCurrentStyle():GetStepsType()
	if self.ParamSong then
		local steps = GAMESTATE:GetCurrentSteps(pn)
		if steps then
			local sDiff = steps:GetDifficulty()
			local diff = self.ParamSong:GetOneSteps( st, sDiff)
			local diffname = GAMESTATE:GetCurrentSteps(pn):GetDifficulty()
			if diff then
				self:settext( diff:GetMeter() )
				:visible(true)
			else
				self:visible(false):settext("")
			end;
		else
			self:visible(false):settext("")
		end;
	end;
end;



return Def.ActorFrame{
	Def.ActorFrame{
		InitCommand=cmd(zoom,0.37);
		LoadActor(THEME:GetPathG("","_shared/"..Model().."hex"))..{
			InitCommand=cmd(draworder,0);
			SetCommand=function(self,param)
				self.ParamSong = param.Song
				setDiffBG1(self)
			end;
			CurrentStepsP1ChangedMessageCommand=function(self) setDiffBG1(self) end;
			CurrentStepsP2ChangedMessageCommand=function(self) setDiffBG1(self) end;
			CurrentSongChangedMessageCommand=function(self) setDiffBG1(self) end;
		};
		LoadActor("line")..{
			InitCommand=cmd(draworder,1);
			SetCommand=function(self,param)
				self.ParamSong = param.Song
				setDiffBG2(self)
			end;
			CurrentStepsP1ChangedMessageCommand=function(self) setDiffBG2(self) end;
			CurrentStepsP2ChangedMessageCommand=function(self) setDiffBG2(self) end;
			CurrentSongChangedMessageCommand=function(self) setDiffBG2(self) end;
		};
	};
	Def.ActorFrame{
		InitCommand=cmd(x,-1;zoom,0.4;draworder,2);
		Def.BitmapText{
			InitCommand=cmd(diffuse,color("#FFFFFF");strokecolor,color("#000000");zoom,2);
			Font="_impact 32px";
			Name = "Meter";
			SetCommand=function(self,param)
				self.ParamSong = param.Song
				setDiff(self)
			end;
			CurrentStepsP1ChangedMessageCommand=function(self) setDiff(self) end;
			CurrentStepsP2ChangedMessageCommand=function(self) setDiff(self) end;
			CurrentSongChangedMessageCommand=function(self) setDiff(self) end;
		};
	};
};
