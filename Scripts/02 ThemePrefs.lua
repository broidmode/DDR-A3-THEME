-- sm-ssc Default Theme Preferences Handler

local Prefs = {
	-- Music select sorting — controls song order within groups
	-- Romaji: alphabetical by transliteration (most rhythm games)
	-- DDR A3: Japanese → Latin → Numbers (arcade DDR A3)
	-- DDR WORLD: Latin → Numbers → Japanese (arcade DDR WORLD)
	JapaneseSorting = {
		Default = "romaji",
		Choices = { "Romaji", "DDR A3", "DDR WORLD" },
		Values  = { "romaji", "jn",     "ln" },
	},
	-- Music select jacket loading quality
	JacketQuality = {
		Default = "incremental",
		Choices = { "Low", "Incremental", "Unlimited" },
		Values  = { "low", "incremental", "full" },
	},
	-- Intro flow mode: Full shows all intro screens, Fast skips to profile then music
	IntroMode = {
		Default = "full",
		Choices = { "Full", "Fast" },
		Values  = { "full", "fast" },
	},
}

ThemePrefs.InitAll(Prefs)

-- Convenience wrappers for new prefs
function GetA3Pref(key)
	return ThemePrefs.Get(key)
end

function SetA3Pref(key, value)
	ThemePrefs.Set(key, value)
end


function InitUserPrefs()
	local Prefs = {
		UserPrefGameplayShowStepsDisplay = true,
		UserPrefGameplayShowStepsDisplay = true,
		UserPrefGameplayShowScore = false,
		UserPrefScoringMode = 'DDR Extreme',
		UserPrefShowLotsaOptions = true,
		UserPrefAutoSetStyle = false,
		UserPrefLongFail = false,
		UserPrefNotePosition = true,
		UserPrefComboOnRolls = false,
		UserPrefProtimingP1 = false,
		UserPrefProtimingP2 = false,
		UserPrefGameplayShowCalories=true,
		FlashyCombos = false,
		UserPrefComboUnderField = true,
		UserPrefFancyUIBG = true,
		UserPrefTimingDisplay = true
	}
	for k, v in pairs(Prefs) do
		-- kind of xxx
		local GetPref = type(v) == "boolean" and GetUserPrefB or GetUserPref
		if GetPref(k) == nil then
			SetUserPref(k, v)
		end
	end
	-- screen filter
	setenv("ScreenFilterP1",0)
	setenv("ScreenFilterP2",0)
end