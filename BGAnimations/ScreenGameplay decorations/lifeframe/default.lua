local pn = ...
local Risky = GAMESTATE:GetPlayerState(pn):GetPlayerOptions('ModsLevel_Current'):LifeSetting() == 'LifeType_Battery'

-- Check if using Flare gauge (set by OptionRowGauge)
local short = ToEnumShortString(pn)
local gaugeType = getenv("FlareGaugeType" .. short) or "Normal"
local isFlareGauge = (gaugeType ~= "Normal" and gaugeType ~= "LIFE4" and gaugeType ~= "Risky")

-- Flare gauge colors by level (1=I through 10=EX)
local FlareColors = {
	color("#0066FF"),   -- I    Blue
	color("#00CCFF"),   -- II   Cyan
	color("#00FFCC"),   -- III  Teal
	color("#00FF66"),   -- IV   Green
	color("#66FF00"),   -- V    Lime
	color("#CCFF00"),   -- VI   Yellow-Green
	color("#FFCC00"),   -- VII  Gold
	color("#FF6600"),   -- VIII Orange
	color("#FF0066"),   -- IX   Pink
	color("#CC00FF"),   -- EX   Magenta
}
local FlareDangerColor = color("#666666")  -- Gray when low
local FlareFailColor = color("#FF0000")    -- Red on fail

-- Bar dimensions (matching existing life bar position)
local BAR_WIDTH = 296
local BAR_HEIGHT = 20

local t = Def.ActorFrame{
	InitCommand=function(s)
		s:xy(pn==PLAYER_1 and _screen.cx-231 or _screen.cx+229,SCREEN_TOP+23):draworder(99)
	end,
	Name="LifeFrame",
}

if isFlareGauge then
	-- ========== FLARE GAUGE DISPLAY ==========
	-- Base (background)
	t[#t+1] = Def.Quad{
		InitCommand=function(s)
			s:x(pn==PLAYER_1 and -7 or 9)
			s:zoomto(BAR_WIDTH, BAR_HEIGHT)
			s:diffuse(color("#111122"))
		end,
	}

	-- Fill bar (left-aligned, scales with life)
	t[#t+1] = Def.Quad{
		Name = "FlareFill",
		InitCommand=function(s)
			s:x(pn==PLAYER_1 and -7 or 9)
			s:halign(pn==PLAYER_1 and 0 or 1)
			s:x(pn==PLAYER_1 and (-7 - BAR_WIDTH/2) or (9 + BAR_WIDTH/2))
			s:zoomto(BAR_WIDTH, BAR_HEIGHT)
			s:diffuse(FlareColors[10])  -- Start at max color
		end,
		FlareGaugeChangedMessageCommand = function(self, params)
			if params.Player ~= pn then return end

			local life = params.Life or 0
			local fillW = math.max(0, math.min(1, life)) * BAR_WIDTH

			-- Determine color based on flare level
			local flareIdx = params.FloatingCurrent or params.FlareIndex or 10
			local c
			if params.Failed then
				c = FlareFailColor
			elseif life < 0.2 then
				c = FlareDangerColor
			else
				c = FlareColors[flareIdx] or FlareColors[10]
			end

			self:stoptweening():linear(0.05)
				:zoomto(fillW, BAR_HEIGHT)
				:diffuse(c)
		end,
	}

	-- Flare level label (shows "FLARE IX" or "FLOAT VII" etc)
	t[#t+1] = Def.BitmapText{
		Font = "_futura pt medium 30px",
		Name = "FlareLabel",
		InitCommand = function(s)
			s:x(pn==PLAYER_1 and -7 or 9)
			s:zoom(0.5)
			s:diffuse(Color.White)
			s:shadowlength(1)
		end,
		FlareGaugeChangedMessageCommand = function(self, params)
			if params.Player ~= pn then return end
			local displayName = GetFlareGaugeDisplayName(pn)
			self:settext(displayName)
		end,
	}

	-- Life percentage text (overlaid)
	t[#t+1] = Def.BitmapText{
		Font = "_futura pt medium 30px",
		Name = "FlarePct",
		InitCommand = function(s)
			s:x(pn==PLAYER_1 and (BAR_WIDTH/2 - 30) or (-BAR_WIDTH/2 + 30))
			s:zoom(0.4)
			s:diffuse(Color.White)
			s:shadowlength(1)
		end,
		FlareGaugeChangedMessageCommand = function(self, params)
			if params.Player ~= pn then return end
			if params.Failed then
				self:settext("FAILED")
			else
				local pct = math.floor((params.Life or 0) * 100 + 0.5)
				self:settext(pct .. "%")
			end
		end,
	}

	-- Frame graphic (same as normal but with a different tint for Flare)
	t[#t+1] = Def.Sprite{
		Name="LifeFrame"..pn,
		InitCommand=function(s)
			s:x(pn==PLAYER_1 and -3.97 or 6)
			s:zoom(0.667)
			s:rotationy(pn==PLAYER_2 and 180 or 0)
			s:y(-0.5)
		end,
		BeginCommand=function(self)
			-- Use gold frame for Flare gauges
			self:Load(THEME:GetPathB("ScreenGameplay","decorations/lifeframe/"..Model().."normal"))
		end
	}

else
	-- ========== NORMAL / BATTERY GAUGE DISPLAY (existing code) ==========
	t[#t+1] = Def.Sprite{
		Texture=THEME:GetPathB("","ScreenGameplay decorations/lifeframe/stream/base"),
		InitCommand=function(s) s:x(pn==PLAYER_1 and -7 or 9):zoomto(296,20):diffusealpha(Risky and 0 or 1) end,
	}
	t[#t+1] = Def.Sprite{
		Texture=THEME:GetPathB("","ScreenGameplay decorations/lifeframe/stream/normal"),
		InitCommand=function(s) s:x(pn==PLAYER_1 and -8 or 10) end,
		OnCommand=function(s) s:scaletoclipped(296,20)
			:MaskDest():ztestmode("ZTestMode_WriteOnFail"):customtexturerect(0,0,1,1)
			:texcoordvelocity(pn=="PlayerNumber_P2" and 0.6 or -0.6,0)
		end,
		HealthStateChangedMessageCommand=function(self, param)
			if param.PlayerNumber == pn then
				if param.HealthState == "HealthState_Danger" then
					self:Load(THEME:GetPathB("","ScreenGameplay decorations/lifeframe/stream/danger"))
				elseif param.HealthState == "HealthState_Hot" then
					self:Load(THEME:GetPathB("","ScreenGameplay decorations/lifeframe/stream/full"))
				else
					self:Load(THEME:GetPathB("","ScreenGameplay decorations/lifeframe/stream/normal"))
				end
			end
		end,
	}
	t[#t+1] = Def.Sprite{
		Name="LifeFrame"..pn,
		InitCommand=function(s) s:x(pn==PLAYER_1 and -3.97 or 6):zoom(0.667):rotationy(pn==PLAYER_2 and 180 or 0):y(-0.5) end,
		BeginCommand=function(self)
			if Risky then
				self:Load(THEME:GetPathB("ScreenGameplay","decorations/lifeframe/"..Model().."life"))
			else
				self:Load(THEME:GetPathB("ScreenGameplay","decorations/lifeframe/"..Model().."normal"))
			end
		end
	}
end

return t
