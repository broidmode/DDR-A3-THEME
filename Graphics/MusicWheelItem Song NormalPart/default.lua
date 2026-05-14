local grade = Def.ActorFrame{}
local cursor = Def.ActorFrame{};
local diff = Def.ActorFrame{};
local top

local function GetExpandedSectionIndex()
	local mWheel
	if SCREENMAN:GetTopScreen():GetChild("MusicWheel")  ~= nil then
		mWheel = SCREENMAN:GetTopScreen():GetChild("MusicWheel")
		local curSections = mWheel:GetCurrentSections()
		for i=1, #curSections do
			if curSections[i] == GAMESTATE:GetExpandedSectionName() then
				return i-1
			end
		end
	end
end

local function IndexStage(param)
	if GAMESTATE:IsExtraStage() or GAMESTATE:IsExtraStage2() then
		return param.Index ~= nil
	else
		return GetExpandedSectionIndex()
	end
end

local function IndexStage2(param)
	if GAMESTATE:IsExtraStage() or GAMESTATE:IsExtraStage2() then
		return param.Index
	else
		return param.Index-GetExpandedSectionIndex()-1
	end
end

local function SetXYPosition(self, param)
	if GetExpandedSectionIndex() then
		local index = param.Index-GetExpandedSectionIndex()-1
		
		if index%3 == 0 then
			self:x(-304):y(107)
		elseif index%3 == 1 then
			self:x(0):y(0)
		else
			self:x(304):y(-107)
		end
	end
end

for i=1,2 do
	cursor[#cursor+1] = Def.Sprite{
		Texture=THEME:GetPathG("","_shared/"..Model().."cursor"),
		InitCommand=function(s) s:x(i==1 and -114 or 114):zoom(0.85):rotationy(i==2 and 180 or 0) end,
		SetMessageCommand=function(s,p)
			if p.Index then
				s:visible(p.HasFocus)
				if p.HasFocus then
					s:bounce():effectmagnitude(i==1 and 12 or -12,0,0):effectperiod(1)
				else
					s:stopeffect()
				end
			end
		end
	};
end

-- Helper to map flareGauge string to asset path
local function GetFlareBadgeTexture(flareGauge)
	if not flareGauge then return nil end
	local level = flareGauge:match("^Flare(%d+)$")
	local filename
	if level then
		filename = "scre_flare_level_"..level
	elseif flareGauge == "FlareEX" then
		filename = "scre_flare_level_ex"
	else
		return nil
	end
	return THEME:GetCurrentThemeDirectory() .. "Graphics/MusicWheelItem Song NormalPart/flare/"..filename..".png"
end

local flareBadge = Def.ActorFrame{}

for i,pn in pairs(GAMESTATE:GetEnabledPlayers()) do
	grade[#grade+1] = loadfile(THEME:GetPathG("MusicWheelItem","Song NormalPart/grade.lua"))(pn)..{
		InitCommand=function(s) s:xy(-5,3.4):zoomy(1.13) end,
	};
	diff[#diff+1] = loadfile(THEME:GetPathG("MusicWheelItem","Song NormalPart/diff.lua"))(pn)..{
		InitCommand=function(s) s:xy(pn == PLAYER_1 and -74 or 74,-36) end,
	};
	flareBadge[#flareBadge+1] = Def.Sprite{
		InitCommand=function(s)
			s:xy(pn == PLAYER_1 and -74 or 74, 38):zoom(0.4):visible(false)
		end,
		SetCommand=function(self, param)
			self.cur_song = param.Song
			self:queuecommand("DiffChange")
		end,
		DiffChangeCommand=function(self)
			if not self.cur_song then
				self:visible(false)
				return
			end
			local st = GAMESTATE:GetCurrentStyle():GetStepsType()
			local steps = GAMESTATE:GetCurrentSteps(pn)
			if not steps then
				self:visible(false)
				return
			end
			local diff = steps:GetDifficulty()
			if not self.cur_song:HasStepsTypeAndDifficulty(st, diff) then
				self:visible(false)
				return
			end
			local chartSteps = self.cur_song:GetOneSteps(st, diff)
			if not chartSteps then
				self:visible(false)
				return
			end
			local chartResult = nil
			if GetChartResultBySong then
				chartResult = GetChartResultBySong(pn, self.cur_song, chartSteps)
			end
			if chartResult and chartResult.flareGauge then
				local tex = GetFlareBadgeTexture(chartResult.flareGauge)
				if tex and FILEMAN:DoesFileExist(tex) then
					self:Load(tex)
					self:visible(true)
					return
				end
			end
			self:visible(false)
		end,
		CurrentStepsP1ChangedMessageCommand=function(self) if pn == PLAYER_1 then self:queuecommand("DiffChange") end end,
		CurrentStepsP2ChangedMessageCommand=function(self) if pn == PLAYER_2 then self:queuecommand("DiffChange") end end,
	};
end;


return Def.ActorFrame{
	OnCommand = function(self)
		top = SCREENMAN:GetTopScreen()
	end;
	SetMessageCommand=function(self,params)
		local index = params.Index
		
		if index ~= nil then
			SetXYPosition(self, params)
			self:zoom(params.HasFocus and 2 or 1.7);
			self:name(tostring(params.Index))
		end
	end;
	Def.Sprite{
		Texture=Model().."card",
		InitCommand=function(s) s:zoom(0.94) end,
	};
	Def.Sprite{
		InitCommand=function(s) s:zoom(0.94) end,
		SetCommand=function(s,p)
			local song = p.Song;
			if song then
				local songtit = song:GetDisplayMainTitle();
				if GoldenLeagueSong[songtit] ~= nil then
					local GoldenLeagueSong = GoldenLeagueSong[songtit];
					s:Load(THEME:GetPathG("","MusicWheelItem Song NormalPart/"..GoldenLeagueSong));
				else
					s:Load(THEME:GetPathG("","_blank"));
				end
			end
		end,
	};
	Def.ActorFrame{
		Name="Highlights",
		InitCommand=function(s) s:x(-4) end,
		SetMessageCommand=function(self, params)
			if params.Index ~= nil then
				self:visible( params.HasFocus );
			end
		end;
		Def.Sprite{
			Texture=Model().."high",
			InitCommand=function(s) s:zoom(0.94):x(5)
				s:diffuseramp():effectcolor1(color("1,1,1,0.2")):effectcolor2(color("1,1,1,1")):effectperiod(0.5)
			end,
		};
		Def.ActorFrame{
			Name="cardcursor",
			InitCommand=function(s) s:diffuseramp():effectcolor1(color("1,1,1,0")):effectcolor2(color("1,1,1,1")):effectperiod(0.5) end,
			Def.Sprite{
				Texture=Model().."line",
				InitCommand=function(s) s:zoom(0.94):x(5)
					s:thump(1):effectmagnitude(1.1,1,0):effectperiod(0.5) 
				end,
			};
		};
	};
	Def.Sprite{
		Texture=Model().."New",
		InitCommand=function(s) s:visible(false):xy(90,-67):halign(1,1):zoom(0.5) end,
		SetMessageCommand=function(s,p)
			local song = p.Song
			if song then
				s:visible(PROFILEMAN:IsSongNew(song))
			end
		end,
	};
	Def.ActorFrame{
		Def.Sprite{
			Name="Banner",
			InitCommand=function(s) s:xy(-2.5,-1.5) end,
			SetMessageCommand=function(s,p)
				local song = p.Song;
				if song then
					s:LoadFromCached("Jacket",GetJacketPath(song))
				end
				s:setsize(103,103)
			end,
		};
		
	};
	Def.ActorFrame{
		InitCommand=function(s) s:x(1):y(67) end,
		Def.BitmapText{
			Name="TranslitTitle";
			Font="_futura pt medium 30px";
			InitCommand=function(s)
				s:y(-10):zoom(0.35):maxwidth(440)
				s:strokecolor(color("0,0,0,0.5"))
			end;
			SetMessageCommand=function(s,p)
				local song = p.Song
				if song and GetTitleDisplayMode() == "Dual" and HasTranslitTitle(song) then
					s:settext(GetTranslitTitle(song))
					s:visible(true)
				else
					s:settext("")
					s:visible(false)
				end
			end;
		};
		Def.BitmapText{
			Name="Title";
			Font="_wheelnames 28px",
			InitCommand=function(s) s:zoom(0.6):maxwidth(260) end,
			SetMessageCommand=function(s,p)
				local song = p.Song
				if song then
					s:settext(GetSongName(song))
					s:diffuse(SongAttributes.GetMenuColor(song))
					s:strokecolor(color("0.15,0.15,0.0,0.9"))
					if GetTitleDisplayMode() == "Dual" and HasTranslitTitle(song) then
						s:y(4)
					else
						s:y(0)
					end
				end
			end;
		};
	};
	Def.ActorFrame{
		Name="Clear Bases",
		Def.Sprite{
			Texture=THEME:GetPathG("MusicWheelItem Song","NormalPart/cleared"),
			InitCommand=function(s) s:xy(54.9,3) end,
		};
		Def.Sprite{
			Texture=THEME:GetPathG("MusicWheelItem Song","NormalPart/cleared"),
			InitCommand=function(s) s:xy(-60,3):zoomx(-1) end,
		};
		grade;
	};
	diff;
	flareBadge;
	cursor;
	Def.Sprite{
		Texture=THEME:GetPathG("","_shared/"..Model().."long"),
		InitCommand=function(s) s:visible(false):xy(-40,36):zoom(0.3) end,
		SetMessageCommand=function(s,p)
			local song = p.Song
			if song then
				if song:IsLong() or song:IsMarathon() then
					s:visible(true)
				else
					s:visible(false)
				end
			end
		end,
	};
}