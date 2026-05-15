-- sm-ssc Default Theme Preferences Handler

local Prefs = {
	-- Music select sorting — two-letter codes set first/last priority
	-- L = Latin, J = Japanese, N = Numbers. Unlisted fills middle.
	JapaneseSorting = {
		Default = "nl",
		Choices = { "J,N,L", "L,N,J", "J,L,N", "N,L,J", "L,J,N", "N,J,L", "Romaji" },
		Values  = { "jl",   "lj",    "jn",    "nj",    "ln",    "nl",    "romaji" },
	},
	-- Music select jacket loading quality
	JacketQuality = {
		Default = "incremental",
		Choices = { "Low", "Incremental", "Unlimited" },
		Values  = { "low", "incremental", "full" },
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