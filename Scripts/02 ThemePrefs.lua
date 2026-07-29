-- sm-ssc Default Theme Preferences Handler

local Prefs = {
	-- Music select sorting — controls song order within groups
	-- Romaji: alphabetical by transliteration (most rhythm games)
	-- DDR A3: Japanese → Latin → Numbers (arcade DDR A3)
	-- DDR WORLD: Latin → Numbers → Japanese (arcade DDR WORLD)
	-- Shuffle: deterministic random order using the persisted ShuffleSeed
	JapaneseSorting = {
		Default = "romaji",
		Choices = { "Romaji", "DDR A3", "DDR WORLD", "Shuffle" },
		Values  = { "romaji", "jn",     "ln",        "shuffle" },
	},
	-- Machine-wide seed used by ScreenA3Music's deterministic shuffle.
	-- Zero means a seed has not been generated yet.
	ShuffleSeed = {
		Default = 0,
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

local SHUFFLE_SEED_MAX = 2147483646

-- Generate a new persisted-shuffle seed without reseeding the engine's global
-- random-number generator. Random values are consumed only on an actual
-- sorting-mode change or recovery of a missing seed, never on normal rebuilds.
function GenerateA3ShuffleSeed()
	local previous = tonumber(ThemePrefs.Get("ShuffleSeed")) or 0
	previous = math.floor(previous)
	if previous < 1 or previous > SHUFFLE_SEED_MAX then
		previous = 0
	end

	-- Build a positive delta from two small draws. Adding it to the previous
	-- seed guarantees that every saved sorting-mode change gets a new seed,
	-- even if the engine starts from the same random state on another launch.
	local high = math.random(0, 32767)
	local low = math.random(0, 32767)
	local delta = ((high * 32768 + low) % (SHUFFLE_SEED_MAX - 1)) + 1
	local seed = ((previous - 1 + delta) % SHUFFLE_SEED_MAX) + 1

	ThemePrefs.Set("ShuffleSeed", seed)
	return seed
end

function GetA3ShuffleSeed()
	local seed = tonumber(ThemePrefs.Get("ShuffleSeed"))
	if not seed or seed < 1 or seed > SHUFFLE_SEED_MAX then
		seed = GenerateA3ShuffleSeed()
		ThemePrefs.Save()
	end
	return math.floor(seed)
end

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
