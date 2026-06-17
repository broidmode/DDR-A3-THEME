-- Real Speed support.
--
-- Two speed "types" are persisted per player (see XX ChartResults.lua):
--   * "multiplier" : the classic X-mod. The stored `xmod` is the multiplier.
--   * "real"       : the player picks a target read BPM (`realBPM`) and the
--                    engine X-mod is derived per song so the chart's DOMINANT
--                    BPM (the BPM the song spends the most real time at) reads
--                    at approximately that target. The multiplier is rounded to
--                    0.01 to land as close to the target as possible.
--
-- The derived multiplier is song/steps specific, so it must be recomputed every
-- time the selected song or chart changes (the ScreenA3Music overlay installs a
-- listener that calls RealSpeed_ApplyAll for that purpose).

-- Sane bounds for the derived multiplier so pathological BPM ratios can't make
-- the playfield unreadable.
local MIN_MULT, MAX_MULT = 0.1, 20.0

-- Round a multiplier to 0.01 and clamp it. Returns nil for invalid inputs.
function RealSpeed_ComputeMult(targetBPM, dominantBPM)
	if type(targetBPM) ~= "number" or targetBPM <= 0 then return nil end
	if type(dominantBPM) ~= "number" or dominantBPM <= 0 then return nil end
	local mult = targetBPM / dominantBPM
	mult = math.floor(mult * 100 + 0.5) / 100  -- nearest 0.01
	if mult < MIN_MULT then mult = MIN_MULT end
	if mult > MAX_MULT then mult = MAX_MULT end
	return mult
end

-- The multiplier that real-speed mode would currently apply for this player,
-- plus the dominant BPM it anchored to. Returns (mult, dominantBPM); either may
-- be nil if it can't be determined (e.g. no song/steps yet).
function RealSpeed_DerivedMult(pn)
	local prefs = GetPlayerSpeedPrefs(pn)
	local dom = GetDominantBPMForPlayer(pn)
	local mult = dom and RealSpeed_ComputeMult(prefs.realBPM, dom) or nil
	return mult, dom
end

-- Apply the player's stored speed preference to their preferred PlayerOptions.
-- In real mode the X-mod is derived from the current song; in multiplier mode
-- the stored manual multiplier (if any) is re-asserted. Our stored preference
-- is authoritative and overrides whatever the engine restored from the profile.
function RealSpeed_Apply(pn)
	if not pn then return end
	if not GAMESTATE:IsPlayerEnabled(pn) then return end
	local ps = GAMESTATE:GetPlayerState(pn)
	if not ps then return end
	local po = ps:GetPlayerOptions("ModsLevel_Preferred")
	if not po then return end

	local prefs = GetPlayerSpeedPrefs(pn)
	if prefs.speedType == "real" then
		local mult = RealSpeed_DerivedMult(pn)
		-- Only override when we could actually derive a multiplier. If timing
		-- isn't available yet (e.g. mid screen load), leave the current value;
		-- a later CurrentSongChanged will re-anchor once timing exists.
		if mult then po:XMod(mult) end
	else
		-- Multiplier mode: keep the engine in sync with the stored manual value.
		-- If we have never captured one, leave the engine's restored X-mod alone.
		if prefs.xmod then
			po:XMod(prefs.xmod)
		end
	end
end

-- Apply for every enabled player.
function RealSpeed_ApplyAll()
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		RealSpeed_Apply(pn)
	end
end
