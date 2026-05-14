-- XX FlareGauge.lua — DDR A3/WORLD Flare Gauge System
-- Manages Flare gauges entirely in Lua. When Flare is active, the engine's
-- LifeMeterBar is neutralized (LifePercentChange ignored).
--
-- Supports: Normal (engine-managed), Flare I-EX, Floating Flare
-- Broadcasts FlareGaugeChangedMessage for HUD actors.

-- ============================================================================
-- FLARE DRAIN VALUES — EDIT THESE TO ADJUST GAUGE BEHAVIOR
-- ============================================================================
-- Index: 1=Flare I, 2=Flare II, ... 9=Flare IX, 10=Flare EX
-- Values are percentages expressed as decimals (e.g., -0.01 = -1%)
-- Negative = drain, Positive = recovery (none by default)

FLARE_TAP_DRAIN = {
	--           I        II       III      IV       V        VI       VII      VIII     IX       EX
	W1   = {     0,       0,       0,       0,       0,       0,       0,       0,       0,       0      },
	W2   = {     0,       0,       0,       0,       0,       0,       0,       0,       0,      -0.01   },
	W3   = {    -0.001,  -0.001,  -0.001,  -0.0029, -0.0074, -0.0092, -0.0128, -0.0164, -0.02,   -0.02   },
	W4   = {    -0.0063, -0.0063, -0.0075, -0.0145, -0.038,  -0.045,  -0.064,  -0.082,  -0.1,    -0.1    },
	Miss = {    -0.015,  -0.03,   -0.045,  -0.11,   -0.16,   -0.18,   -0.22,   -0.26,   -0.3,    -0.3    },
}

FLARE_HOLD_DRAIN = {
	--              I        II       III      IV       V        VI       VII      VIII     IX       EX
	Held       = {  0,       0,       0,       0,       0,       0,       0,       0,       0,       0      },
	LetGo      = { -0.015,  -0.03,   -0.045,  -0.11,   -0.16,   -0.18,   -0.22,   -0.26,   -0.3,    -0.3    },
	MissedHold = {  0,       0,       0,       0,       0,       0,       0,       0,       0,       0      },
}

-- ============================================================================
-- GAUGE STATE (per player)
-- ============================================================================
FlareGaugeState = {}

-- Map gauge option string to Flare index (1-10)
local FlareIndexMap = {
	Flare1 = 1, Flare2 = 2, Flare3 = 3, Flare4 = 4, Flare5 = 5,
	Flare6 = 6, Flare7 = 7, Flare8 = 8, Flare9 = 9, FlareEX = 10,
	FloatingFlare = 10,  -- starts at EX level
}

-- Roman numeral display names
local FlareRomanNumerals = {"I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "EX"}

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Check if a gauge type uses the Flare system (vs engine-managed Normal/Battery)
function IsFlareGaugeType(gaugeType)
	return gaugeType == "Flare" or gaugeType == "FloatingFlare"
end

-- Get the current gauge selection for a player (env var or persisted pref)
function GetFlareGaugeSelection(pn)
	local short = ToEnumShortString(pn)
	local envVal = getenv("FlareGaugeType" .. short)
	if envVal then return envVal end
	-- Fallback to persisted profile pref
	if GetPlayerGaugePref then
		return GetPlayerGaugePref(pn)
	end
	return "Normal"
end

-- Initialize gauge state for a player at song start
function InitFlareGauge(pn)
	local gaugeStr = GetFlareGaugeSelection(pn)

	local gs = {
		gaugeType       = "Normal",    -- "Normal", "Flare", "FloatingFlare"
		flareIndex      = nil,         -- 1-10 for fixed Flare
		life            = 1.0,         -- 0.0 to 1.0
		failed          = false,
		floatingCurrent = nil,         -- Current level for Floating Flare (1-10, or 0 if dead)
		flareBars       = nil,         -- Parallel bars for Floating Flare [1-10]
	}

	if gaugeStr == "Normal" or gaugeStr == "LIFE4" or gaugeStr == "Risky" then
		-- Engine-managed gauge, we don't track it
		gs.gaugeType = "Normal"
		gs.life = 1.0

	elseif gaugeStr == "FloatingFlare" then
		gs.gaugeType = "FloatingFlare"
		gs.flareIndex = 10
		gs.life = 1.0
		gs.floatingCurrent = 10
		gs.flareBars = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }

	elseif FlareIndexMap[gaugeStr] then
		gs.gaugeType = "Flare"
		gs.flareIndex = FlareIndexMap[gaugeStr]
		gs.life = 1.0
	end

	FlareGaugeState[pn] = gs

	-- Broadcast initial state for HUD
	MESSAGEMAN:Broadcast("FlareGaugeChanged", {
		Player          = pn,
		Life            = gs.life,
		Failed          = gs.failed,
		GaugeType       = gs.gaugeType,
		FlareIndex      = gs.flareIndex,
		FloatingCurrent = gs.floatingCurrent,
	})
end

-- ============================================================================
-- DELTA LOOKUP
-- ============================================================================

local function GetFlareTapDelta(tns, idx)
	if tns == 'TapNoteScore_W1' or tns == 'TapNoteScore_AvoidMine' then
		return FLARE_TAP_DRAIN.W1[idx] or 0
	elseif tns == 'TapNoteScore_W2' then
		return FLARE_TAP_DRAIN.W2[idx] or 0
	elseif tns == 'TapNoteScore_W3' then
		return FLARE_TAP_DRAIN.W3[idx] or 0
	elseif tns == 'TapNoteScore_W4' then
		return FLARE_TAP_DRAIN.W4[idx] or 0
	elseif tns == 'TapNoteScore_Miss' or tns == 'TapNoteScore_HitMine' then
		return FLARE_TAP_DRAIN.Miss[idx] or 0
	end
	return 0
end

local function GetFlareHoldDelta(hns, idx)
	if hns == 'HoldNoteScore_Held' then
		return FLARE_HOLD_DRAIN.Held[idx] or 0
	elseif hns == 'HoldNoteScore_LetGo' then
		return FLARE_HOLD_DRAIN.LetGo[idx] or 0
	elseif hns == 'HoldNoteScore_MissedHold' then
		return FLARE_HOLD_DRAIN.MissedHold[idx] or 0
	end
	return 0
end

local function GetFlareDelta(params, idx)
	if params.HoldNoteScore then
		return GetFlareHoldDelta(params.HoldNoteScore, idx)
	elseif params.TapNoteScore then
		return GetFlareTapDelta(params.TapNoteScore, idx)
	end
	return 0
end

-- ============================================================================
-- FLOATING FLARE ALGORITHM
-- ============================================================================
-- Track 10 parallel bars (Flare I through EX) simultaneously.
-- Each judgment drains every bar at its own rate. The displayed bar is
-- the highest-indexed bar still above 0%.

local function ApplyFloatingFlare(gs, params)
	local bars = gs.flareBars
	for i = 1, 10 do
		if bars[i] > 0 then
			local delta = GetFlareDelta(params, i)
			bars[i] = math.max(0, math.min(1, bars[i] + delta))
		end
	end

	-- Find highest surviving bar
	local best = 0
	for i = 10, 1, -1 do
		if bars[i] > 0 then
			best = i
			break
		end
	end

	gs.floatingCurrent = best
	gs.life = best > 0 and bars[best] or 0
end

-- ============================================================================
-- MAIN UPDATE
-- ============================================================================
-- Call on every JudgmentMessage from gameplay decorations

function UpdateFlareGauge(params, pn)
	local gs = FlareGaugeState[pn]
	if not gs then return end
	if gs.gaugeType == "Normal" then return end  -- Engine handles Normal/Battery
	if gs.failed then return end

	if gs.gaugeType == "Flare" then
		local delta = GetFlareDelta(params, gs.flareIndex)
		gs.life = math.max(0, math.min(1, gs.life + delta))
		if gs.life <= 0 then
			gs.failed = true
		end

	elseif gs.gaugeType == "FloatingFlare" then
		ApplyFloatingFlare(gs, params)
		if gs.life <= 0 then
			gs.failed = true
		end
	end

	-- Broadcast for HUD
	MESSAGEMAN:Broadcast("FlareGaugeChanged", {
		Player          = pn,
		Life            = gs.life,
		Failed          = gs.failed,
		GaugeType       = gs.gaugeType,
		FlareIndex      = gs.flareIndex,
		FloatingCurrent = gs.floatingCurrent,
	})

	-- Trigger fail if gauge depleted and fail behavior is Arcade
	if gs.failed and GetThemeFailBehavior() == "Arcade" then
		local screen = SCREENMAN:GetTopScreen()
		if screen then
			screen:PostScreenMessage('SM_BeginFailed', 0)
		end
	end
end

-- ============================================================================
-- ACCESSORS
-- ============================================================================

function GetFlareGaugeLife(pn)
	local gs = FlareGaugeState[pn]
	return gs and gs.life or 1.0
end

function GetFlareGaugeFailed(pn)
	local gs = FlareGaugeState[pn]
	return gs and gs.failed or false
end

function GetFlareGaugeType(pn)
	local gs = FlareGaugeState[pn]
	return gs and gs.gaugeType or "Normal"
end

function GetFlareGaugeIndex(pn)
	local gs = FlareGaugeState[pn]
	return gs and gs.flareIndex or nil
end

function GetFloatingFlareCurrent(pn)
	local gs = FlareGaugeState[pn]
	return gs and gs.floatingCurrent or nil
end

-- Display name for current gauge state
function GetFlareGaugeDisplayName(pn)
	local gs = FlareGaugeState[pn]
	if not gs then return "Normal" end

	if gs.gaugeType == "Normal" then
		return "Normal"
	end

	if gs.gaugeType == "FloatingFlare" then
		local cur = gs.floatingCurrent or 0
		if cur < 1 then return "FLOAT ---" end
		return "FLOAT " .. (FlareRomanNumerals[cur] or "?")
	end

	if gs.gaugeType == "Flare" and gs.flareIndex then
		return "FLARE " .. (FlareRomanNumerals[gs.flareIndex] or "?")
	end

	return "Normal"
end

-- Get life percentage as integer (0-100)
function GetFlareGaugePercent(pn)
	local gs = FlareGaugeState[pn]
	if not gs then return 100 end
	return math.floor(gs.life * 100 + 0.5)
end
