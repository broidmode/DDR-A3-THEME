-- 00 Timing.lua — DDR A3 timing window configuration
-- Applies engine-level timing via PREFSMAN:SetPreference() on theme load.
-- Per-player W5 disable applied at gameplay start.

-- All PREFSMAN keys managed by the timing system.
local TimingPrefKeys = {
	"TimingWindowSecondsW1",
	"TimingWindowSecondsW2",
	"TimingWindowSecondsW3",
	"TimingWindowSecondsW4",
	"TimingWindowSecondsW5",
	"TimingWindowSecondsHold",
	"TimingWindowSecondsMine",
	"TimingWindowSecondsRoll",
	"TimingWindowAdd",
	"RegenComboAfterMiss",
	"MaxRegenComboAfterMiss",
	"MinTNSToHideNotes",
}

-- DDR A3 timing values
-- W5 is set to 150ms for auto-miss timing, but the judgment itself is disabled per-player
local DDRA3Timing = {
	TimingWindowSecondsW1   = 0.01667,  -- ±16.67ms Marvelous
	TimingWindowSecondsW2   = 0.03333,  -- ±33.33ms Perfect
	TimingWindowSecondsW3   = 0.08333,  -- ±83.33ms Great
	TimingWindowSecondsW4   = 0.12000,  -- ±120.00ms Good
	TimingWindowSecondsW5   = 0.15000,  -- ±150.00ms (disabled, for auto-miss timing only)
	TimingWindowSecondsHold = 0.25000,  -- Hold checkpoint window
	TimingWindowSecondsMine = 0.01667,  -- ±16.67ms shock arrows (symmetric fallback)
	TimingWindowSecondsRoll = 0.50000,  -- Roll checkpoint window
	TimingWindowAdd         = 0,        -- No additional timing leniency
	RegenComboAfterMiss     = 0,        -- No combo regen (DDR behavior)
	MaxRegenComboAfterMiss  = 0,        -- No combo regen (DDR behavior)
	MinTNSToHideNotes       = "W4",     -- Good notes disappear when hit
}

-- Apply DDR A3 timing preferences to the engine.
-- Call this on theme load (ScreenTitleMenu/ScreenLogo).
function ApplyDDRA3Timing()
	for key, val in pairs(DDRA3Timing) do
		PREFSMAN:SetPreference(key, val)
	end
end

-- Reset all timing-related PREFSMAN keys to SM5 stock values.
-- Call this on theme unload if switching to another theme.
function ResetTimingToDefaults()
	for _, key in ipairs(TimingPrefKeys) do
		PREFSMAN:SetPreferenceToDefault(key)
	end
end

-- Apply per-player timing options at gameplay start.
-- Disables W5 (Way Off) judgment so hits outside W4 are ignored, not judged.
function ApplyPerPlayerTiming()
	for _, pn in ipairs(GAMESTATE:GetHumanPlayers()) do
		local po = GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred")
		po:DisableTimingWindow("TimingWindow_W5")
	end
end

-- Combo threshold functions for metrics.ini.
-- DDR behavior: W4 (Good) maintains and continues combo.
-- Use in metrics.ini as: MinScoreToContinueCombo=ComboContinue()
function ComboContinue()
	return "TapNoteScore_W4"
end

function ComboMaintain()
	return "TapNoteScore_W4"
end

-- Custom Theme option row that resets timing when switching to non-DDR-A3 themes.
-- Use in metrics.ini as: Line="lua,ThemeOptionRow()"
function ThemeOptionRow()
	return {
		Name = "Theme",
		Choices = THEME:GetSelectableThemeNames(),
		LayoutType = "ShowAllInRow",
		SelectType = "SelectOne",
		OneChoiceForAllPlayers = true,
		ExportOnChange = false,
		LoadSelections = function(self, list, pn)
			local theme = THEME:GetCurThemeName()
			if not theme then return end
			for i, name in ipairs(self.Choices) do
				if name == theme then
					list[i] = true
					return
				end
			end
			list[1] = true
		end,
		SaveSelections = function(self, list, pn)
			for i = 1, #self.Choices do
				if list[i] then
					local newTheme = self.Choices[i]
					if newTheme ~= THEME:GetCurThemeName() then
						ResetTimingToDefaults()
						PREFSMAN:SavePreferences()
						THEME:SetTheme(newTheme)
					end
					return
				end
			end
		end,
	}
end
