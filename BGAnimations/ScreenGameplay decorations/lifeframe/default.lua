local pn = ...
local Risky = GAMESTATE:GetPlayerState(pn):GetPlayerOptions('ModsLevel_Current'):LifeSetting() == 'LifeType_Battery'

-- Check if using Flare gauge - use selection (env var or persisted pref) since
-- FlareGaugeState isn't initialized yet when actors are created
local gaugeType = (GetFlareGaugeSelection and GetFlareGaugeSelection(pn)) or "Normal"
local isFlareGauge = (gaugeType ~= "Normal" and gaugeType ~= "LIFE4" and gaugeType ~= "Risky")

local t = Def.ActorFrame{
	InitCommand=function(s)
		s:xy(pn==PLAYER_1 and _screen.cx-231 or _screen.cx+229,SCREEN_TOP+23):draworder(99)
	end,
	Name="LifeFrame",
}

if isFlareGauge then
	-- ========== FLARE GAUGE DISPLAY ==========
	-- Determine initial flare level for texture selection
	local initialFlareLevel = 1
	if gaugeType == "FloatingFlare" then
		initialFlareLevel = 10  -- Floating starts at EX, drops down
	else
		local levelMatch = gaugeType:match("Flare(%d+)")
		if levelMatch then
			initialFlareLevel = tonumber(levelMatch)
		elseif gaugeType == "FlareEX" then
			initialFlareLevel = 10
		end
	end

	-- Helper to get flare fill texture path
	local function GetFlareTexturePath(level)
		if level == 10 then
			return THEME:GetPathB("","ScreenGameplay decorations/lifeframe/flare/gauge0000_gauge_flareex")
		else
			return THEME:GetPathB("","ScreenGameplay decorations/lifeframe/flare/gauge0000_gauge_flare"..level)
		end
	end
	local FlareDangerPath = THEME:GetPathB("","ScreenGameplay decorations/lifeframe/flare/gauge0000_gauge_flare_danger")

	-- Track current texture to avoid reloading (which resets scroll)
	local currentTexturePath = GetFlareTexturePath(initialFlareLevel)

	-- Base (background)
	t[#t+1] = Def.Sprite{
		Texture=THEME:GetPathB("","ScreenGameplay decorations/lifeframe/stream/base"),
		InitCommand=function(s) s:x(pn==PLAYER_1 and -7 or 9):zoomto(296,20) end,
	}

	-- Fill bar - matches normal gauge setup exactly (textures have (stretch) hint)
	t[#t+1] = Def.Sprite{
		Name = "FlareFill",
		Texture=currentTexturePath,
		InitCommand=function(s) s:x(pn==PLAYER_1 and -8 or 10) end,
		OnCommand=function(s)
			s:scaletoclipped(296,20)
			s:customtexturerect(0,0,1,1)
			s:texcoordvelocity(pn==PLAYER_2 and 1.8 or -1.8, 0)  -- Scroll speed: higher = faster
		end,
		FlareGaugeChangedMessageCommand = function(self, params)
			if params.Player ~= pn then return end

			local life = math.max(0, math.min(1, params.Life or 0))
			local flareIdx = params.FloatingCurrent or params.FlareIndex or initialFlareLevel
			local empty = 1 - life

			-- Determine what texture we SHOULD have
			local wantTexture
			if life < 0.2 and not params.Failed then
				wantTexture = FlareDangerPath
			else
				wantTexture = GetFlareTexturePath(flareIdx)
			end

			-- Only reload if texture actually changed (preserves scroll position)
			if wantTexture ~= currentTexturePath then
				currentTexturePath = wantTexture
				self:Load(wantTexture)
				self:scaletoclipped(296,20)
				self:customtexturerect(0,0,1,1)
				self:texcoordvelocity(pn==PLAYER_2 and 1.8 or -1.8, 0)
			end

			-- Crop based on life (P1 drains right-to-left, P2 drains left-to-right)
			if pn == PLAYER_1 then
				self:cropright(empty)
			else
				self:cropleft(empty)
			end
		end,
	}

	-- Frame graphic
	t[#t+1] = Def.Sprite{
		Name="LifeFrame"..pn,
		InitCommand=function(s)
			s:x(pn==PLAYER_1 and -3.97 or 6)
			s:zoom(0.667)
			s:rotationy(pn==PLAYER_2 and 180 or 0)
			s:y(-0.5)
		end,
		BeginCommand=function(self)
			self:Load(THEME:GetPathB("ScreenGameplay","decorations/lifeframe/"..Model().."normal"))
		end
	}

else
	-- ========== NORMAL / BATTERY GAUGE DISPLAY ==========
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
