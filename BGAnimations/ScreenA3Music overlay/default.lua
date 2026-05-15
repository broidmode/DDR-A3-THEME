-- ScreenA3Music overlay/default.lua
-- Custom music select screen (ported from GALAXY)
-- Replaces ScreenSelectMusic with a pure-Lua 3-column grid browser

-- ============================================================================
-- CONSTANTS
-- ============================================================================
local COLS = 3
local POOL_CARDS = 75
local POOL_HEADERS = 30

-- Stagger offsets for DDR A3 pseudo-3D perspective (from MusicWheelItem)
local STAGGER = {
	[0] = { x = -304, y = 107 },   -- left column
	[1] = { x = 0,    y = 0 },     -- center column
	[2] = { x = 304,  y = -107 },  -- right column
}

-- Animation
local ANIM_DUR = 0.15  -- scroll animation duration in seconds

-- ============================================================================
-- STATE
-- ============================================================================
local FlatList = {}      -- mixed array: string = group header, table = {Song, Steps...}
local Cursor = 1         -- current index into FlatList
local OpenGroup = ""     -- currently expanded group (empty = all collapsed)

-- Actor pools (to be populated)
local CardPool = {}
local HeaderPool = {}
local CardAssign = {}    -- CardAssign[poolIdx] = flatIdx
local CardByFlat = {}    -- CardByFlat[flatIdx] = poolIdx

-- Animation state
local VisualOffset = 0
local AnimStart = 0
local AnimA, AnimB, AnimC, AnimD = 0, 0, 0, 0

-- Difficulty picker state
local DiffFrame = {}      -- per-player picker actors
local DiffSong = nil      -- song being selected
local DiffSteps = {}      -- array of available Steps for the song
local DiffPickIdx = {}    -- per-player cursor index into DiffSteps
local DiffPickOpen = false
local Accepted = false    -- prevent double-confirm

-- Side menu state (Stage 7)
local MenuOpen = {}       -- MenuOpen[pn] = true/false
local MenuRow = {}        -- MenuRow[pn] = current row index
local MenuFrame = {}      -- MenuFrame[pn] = ActorFrame reference
local PlayerOptions = {}  -- PlayerOptions[pn] = { {name, choices, selected}, ... }

-- Score panel state (Stage 8)
local ScorePanelFrame = {}  -- ScorePanelFrame[pn] = ActorFrame reference

-- Song preview state (Stage 9)
local PreviewActor = nil
local PreviewGen = 0           -- generation counter to cancel stale previews
local CurrentPreviewPath = nil -- path of currently playing preview
local PREVIEW_DELAY = 0.3      -- seconds before starting preview

-- Cursor persistence (survives screen transitions)
A3MusicCursorState = A3MusicCursorState or {}

local function SaveCursorState()
	A3MusicCursorState.cursor = Cursor
	A3MusicCursorState.openGroup = OpenGroup
	-- Also save the song dir if on a song, for matching after rebuild
	if IsSong(Cursor) then
		local song = FlatList[Cursor][1]
		A3MusicCursorState.songDir = song:GetSongDir()
	else
		A3MusicCursorState.songDir = nil
	end
end

local function RestoreCursorState()
	local saved = A3MusicCursorState
	if saved.openGroup and saved.openGroup ~= "" then
		OpenGroup = saved.openGroup
		BuildFlatList()
	end
	if saved.cursor and saved.cursor >= 1 and saved.cursor <= #FlatList then
		Cursor = saved.cursor
	end
	-- Try to match by song dir if available (in case list order changed)
	if saved.songDir then
		for i, item in ipairs(FlatList) do
			if type(item) == "table" and item[1] and item[1]:GetSongDir() == saved.songDir then
				Cursor = i
				break
			end
		end
	end
end

-- ============================================================================
-- DATA MODEL (Stage 2)
-- ============================================================================

-- Wrap an index into [1, #FlatList]
local function Wrap(idx)
	local n = #FlatList
	if n == 0 then return 1 end
	return ((idx - 1) % n) + 1
end

local function IsGroup(idx)
	return type(FlatList[idx]) == "string"
end

local function IsSong(idx)
	return type(FlatList[idx]) == "table"
end

-- ===== JAPANESE TITLE SORTING =====
-- A song "has a Japanese title" when its display title STARTS with a
-- CJK / Hiragana / Katakana / fullwidth character.
-- UTF-8 ranges: U+3000+ → 3-byte sequences starting with 0xE3..0xE9

local function HasJapaneseTitle(song)
	local title = song:GetDisplayMainTitle()
	local start = title:match("^%s*()") or 1
	local b = title:byte(start)
	if not b then return false end
	return b >= 0xE3
end

local function StartsWithDigit(s)
	local b = s:byte(1)
	return b and b >= 48 and b <= 57  -- '0'..'9'
end

-- Returns a sort-key string that groups songs by category bucket first,
-- then alphabetically within each bucket.
-- Bucket prefixes: "0" = first priority, "1" = middle, "2" = last priority.
local function SortKey(song)
	local translit = song:GetTranslitMainTitle():lower()
	local jpMode = GetA3Pref("JapaneseSorting") or "romaji"

	-- Migrate legacy values
	if jpMode == "first" then jpMode = "nl" end
	if jpMode == "last"  then jpMode = "nj" end

	if jpMode == "romaji" then
		return translit
	end

	-- Determine category: J (Japanese), L (Latin), N (Numbers)
	local isJP  = HasJapaneseTitle(song)
	local isNum = StartsWithDigit(translit)
	local cat
	if isNum then cat = "n"
	elseif isJP then cat = "j"
	else cat = "l"
	end

	-- Two-letter code: first letter = highest priority, second = lowest
	local first = jpMode:sub(1, 1)
	local last  = jpMode:sub(2, 2)

	local prefix
	if cat == first then prefix = "0"
	elseif cat == last then prefix = "2"
	else prefix = "1"
	end

	return prefix .. translit
end

local function SortSongs(songs)
	local keyed = {}
	for i, song in ipairs(songs) do
		keyed[i] = { song = song, key = SortKey(song) }
	end
	table.sort(keyed, function(a, b) return a.key < b.key end)
	local out = {}
	for i, v in ipairs(keyed) do out[i] = v.song end
	return out
end

-- Build FlatList from song groups
-- FlatList entries: string = group header, table = {Song, Steps1, Steps2, ...}
local function BuildFlatList()
	local list = {}
	local groups = SONGMAN:GetSongGroupNames()

	for _, grp in ipairs(groups) do
		list[#list+1] = grp

		if grp == OpenGroup then
			local songs = SortSongs(SONGMAN:GetSongsInGroup(grp))
			for _, song in ipairs(songs) do
				local stType = GAMESTATE:GetCurrentStyle():GetStepsType()
				local allSteps = song:GetStepsByStepsType(stType)
				if #allSteps > 0 then
					local entry = { song }
					for _, st in ipairs(allSteps) do
						entry[#entry+1] = st
					end
					list[#list+1] = entry
				end
			end
		end
	end

	FlatList = list
	Cursor = math.min(Cursor, math.max(1, #FlatList))
	Trace("[ScreenA3Music] BuildFlatList: " .. #FlatList .. " items, " .. #groups .. " groups")
end

-- Toggle a group open/closed
local function ToggleGroup(groupName)
	if OpenGroup == groupName then
		OpenGroup = ""
	else
		OpenGroup = groupName
	end
	BuildFlatList()
	MESSAGEMAN:Broadcast("CursorChanged")
end

-- ============================================================================
-- ACTOR POOL FACTORIES (Stage 3)
-- ============================================================================

-- Root frame for all pool actors (populated in OnCommand)
local PoolRoot = nil

-- Get the model prefix (gold/blue) based on game state
local function GetModel()
	if GAMESTATE:IsExtraStage() or GAMESTATE:IsExtraStage2() then
		return "blue_"
	end
	return "gold_"
end

-- Theme directory for texture loading
local ThemeDir = THEME:GetCurrentThemeDirectory()

-- Timing - accumulated from frame deltas
local AccumulatedTime = 0

-- Factory: Create a song card actor
local function MakeSongCard(idx)
	local model = GetModel()
	local cardPath = ThemeDir .. "Graphics/MusicWheelItem Song NormalPart/"

	local card = Def.ActorFrame{
		Name = "Card"..idx,
		InitCommand = function(self)
			self:visible(false)
			self.poolIdx = idx
			self.flatIdx = nil
		end,

		-- Main card background
		Def.Sprite{
			Name = "CardBG",
			InitCommand = function(s)
				s:Load(cardPath .. model .. "card.png")
				s:zoom(0.94)
			end,
		},

		-- Jacket/banner
		Def.Sprite{
			Name = "Jacket",
			InitCommand = function(s) s:xy(-2.5, -1.5) end,
		},

		-- Highlight frame (shown when focused)
		Def.Sprite{
			Name = "Highlight",
			InitCommand = function(s)
				s:Load(cardPath .. model .. "high.png")
				s:zoom(0.94):visible(false)
				s:diffuseramp():effectcolor1(color("1,1,1,0.2")):effectcolor2(color("1,1,1,1")):effectperiod(0.5)
			end,
		},

		-- Highlight line
		Def.Sprite{
			Name = "HighlightLine",
			InitCommand = function(s)
				s:Load(cardPath .. model .. "line.png")
				s:zoom(0.94):visible(false)
				s:diffuseramp():effectcolor1(color("1,1,1,0")):effectcolor2(color("1,1,1,1")):effectperiod(0.5)
				s:thump(1):effectmagnitude(1.1,1,0):effectperiod(0.5)
			end,
		},

		-- Clear lamp base (left)
		Def.Sprite{
			Name = "ClearBaseL",
			InitCommand = function(s)
				s:Load(cardPath .. "cleared.png")
				s:xy(-60, 3):zoomx(-1)
			end,
		},

		-- Clear lamp base (right)
		Def.Sprite{
			Name = "ClearBaseR",
			InitCommand = function(s)
				s:Load(cardPath .. "cleared.png")
				s:xy(54.9, 3)
			end,
		},

		-- Title text
		Def.BitmapText{
			Name = "Title",
			Font = "_wheelnames 28px",
			InitCommand = function(s)
				s:xy(1, 67):zoom(0.6):maxwidth(260)
				s:strokecolor(color("0.15,0.15,0.0,0.9"))
			end,
		},

		-- Transliterated title (small, above main title)
		Def.BitmapText{
			Name = "TranslitTitle",
			Font = "_futura pt medium 30px",
			InitCommand = function(s)
				s:xy(1, 57):zoom(0.35):maxwidth(440)
				s:strokecolor(color("0,0,0,0.5"))
				s:visible(false)
			end,
		},

		-- Difficulty hex background
		Def.Sprite{
			Name = "DiffHex",
			InitCommand = function(s)
				s:Load(ThemeDir .. "Graphics/_shared/" .. model .. "hex.png")
				s:xy(-74, -36):zoom(0.37)
			end,
		},

		-- Difficulty line overlay (colored by difficulty)
		Def.Sprite{
			Name = "DiffLine",
			InitCommand = function(s)
				s:Load(cardPath .. "line.png")
				s:xy(-74, -36):zoom(0.37)
			end,
		},

		-- Difficulty number
		Def.BitmapText{
			Name = "DiffNum",
			Font = "_impact 32px",
			InitCommand = function(s)
				s:xy(-75, -36):zoom(0.8)
				s:diffuse(color("#FFFFFF")):strokecolor(color("#000000"))
			end,
		},

		-- Clear lamp sprite
		Def.Sprite{
			Name = "ClearLamp",
			InitCommand = function(s) s:xy(-5, 3.4):zoomy(1.13):visible(false) end,
		},

		-- Flare badge
		Def.Sprite{
			Name = "FlareBadge",
			InitCommand = function(s) s:xy(-74, 38):zoom(0.4):visible(false) end,
		},
	}
	return card
end

-- Factory: Create a group header actor
local function MakeGroupHeader(idx)
	local header = Def.ActorFrame{
		Name = "Header"..idx,
		InitCommand = function(self)
			self:visible(false)
			self.poolIdx = idx
			self.flatIdx = nil
		end,

		-- Background bar
		Def.Quad{
			Name = "HeaderBG",
			InitCommand = function(s)
				s:setsize(280, 40):diffuse(color("0.1,0.1,0.1,0.9"))
			end,
		},

		-- Accent line
		Def.Quad{
			Name = "HeaderAccent",
			InitCommand = function(s)
				s:setsize(280, 3):y(-18.5)
				if GAMESTATE:IsExtraStage() or GAMESTATE:IsExtraStage2() then
					s:diffuse(color("0.3,0.5,0.9,1"))
				else
					s:diffuse(color("0.9,0.7,0.2,1"))
				end
			end,
		},

		-- Group name text
		Def.BitmapText{
			Name = "GroupName",
			Font = "_wheelnames 28px",
			InitCommand = function(s)
				s:zoom(0.5):maxwidth(500)
				s:diffuse(color("1,1,1,1"))
				s:strokecolor(color("0,0,0,0.8"))
			end,
		},

		-- Expand/collapse indicator
		Def.BitmapText{
			Name = "ExpandIcon",
			Font = "Common Normal",
			Text = ">",
			InitCommand = function(s)
				s:x(125):zoom(0.8):diffuse(color("0.8,0.8,0.8,1"))
			end,
		},
	}
	return header
end

-- Update a song card with data from FlatList entry
local function UpdateSongCard(actor, entry, isFocused)
	if not entry or type(entry) ~= "table" then
		actor:visible(false)
		return
	end

	local song = entry[1]
	if not song then
		actor:visible(false)
		return
	end

	actor:visible(true)

	-- Jacket
	local jacket = actor:GetChild("Jacket")
	if jacket then
		jacket:LoadFromCached("Jacket", GetJacketPath(song))
		jacket:setsize(103, 103)
	end

	-- Title
	local title = actor:GetChild("Title")
	if title then
		local displayTitle = GetSongName and GetSongName(song) or song:GetDisplayMainTitle()
		title:settext(displayTitle)
		if SongAttributes and SongAttributes.GetMenuColor then
			title:diffuse(SongAttributes.GetMenuColor(song))
		end
	end

	-- Translit title
	local translit = actor:GetChild("TranslitTitle")
	if translit then
		if GetTitleDisplayMode and GetTitleDisplayMode() == "Dual" and HasTranslitTitle and HasTranslitTitle(song) then
			translit:settext(GetTranslitTitle(song))
			translit:visible(true)
			if title then title:y(71) end
		else
			translit:visible(false)
			if title then title:y(67) end
		end
	end

	-- Highlight
	local highlight = actor:GetChild("Highlight")
	local highlightLine = actor:GetChild("HighlightLine")
	if highlight then highlight:visible(isFocused) end
	if highlightLine then highlightLine:visible(isFocused) end

	-- Get current steps for difficulty display
	local pn = GAMESTATE:GetMasterPlayerNumber()
	local st = GAMESTATE:GetCurrentStyle() and GAMESTATE:GetCurrentStyle():GetStepsType()
	local steps = #entry > 1 and entry[2] or nil  -- First steps in entry

	-- Difficulty display
	local diffHex = actor:GetChild("DiffHex")
	local diffLine = actor:GetChild("DiffLine")
	local diffNum = actor:GetChild("DiffNum")
	if steps and diffNum then
		diffNum:settext(steps:GetMeter())
		diffNum:visible(true)
		if diffLine then
			diffLine:diffuse(CustomDifficultyToColor(steps:GetDifficulty()))
		end
	elseif diffNum then
		diffNum:visible(false)
	end

	-- Clear lamp and flare badge (simplified - will enhance later)
	local clearLamp = actor:GetChild("ClearLamp")
	local flareBadge = actor:GetChild("FlareBadge")
	if clearLamp then clearLamp:visible(false) end
	if flareBadge then flareBadge:visible(false) end
end

-- Update a group header with data
local function UpdateGroupHeader(actor, groupName, isExpanded, isFocused)
	if not groupName or type(groupName) ~= "string" then
		actor:visible(false)
		return
	end

	actor:visible(true)

	local nameText = actor:GetChild("GroupName")
	if nameText then
		nameText:settext(groupName)
	end

	local expandIcon = actor:GetChild("ExpandIcon")
	if expandIcon then
		expandIcon:settext(isExpanded and "v" or ">")
	end

	local bg = actor:GetChild("HeaderBG")
	if bg then
		if isFocused then
			bg:diffuse(color("0.2,0.2,0.2,0.95"))
		else
			bg:diffuse(color("0.1,0.1,0.1,0.9"))
		end
	end
end

-- ============================================================================
-- DIFFICULTY PICKER (Stage 6)
-- ============================================================================

local DIFF_ROW_H = 60
local DIFF_W = 400
local MAX_DIFFS = 6

-- Difficulty colors matching DDR A3
local DiffColors = {
	Difficulty_Beginner = color("#66ccff"),
	Difficulty_Easy     = color("#ffcc33"),
	Difficulty_Medium   = color("#ff6666"),
	Difficulty_Hard     = color("#66ff66"),
	Difficulty_Challenge= color("#cc66ff"),
	Difficulty_Edit     = color("#aaaaaa"),
}

local function GetDiffColor(steps)
	local d = steps:GetDifficulty()
	return DiffColors[d] or color("#aaaaaa")
end

local function RefreshDiffPicker()
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if DiffFrame[pn] then DiffFrame[pn]:playcommand("RefreshDiff") end
	end
end

local function OpenDiffPicker(song, stepsArray)
	DiffSong = song
	DiffSteps = stepsArray
	-- Initialize each player's cursor to their preferred difficulty
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		DiffPickIdx[pn] = 1
		local pref = GAMESTATE:GetPreferredDifficulty(pn)
		if pref then
			for i, st in ipairs(DiffSteps) do
				if st:GetDifficulty() == pref then
					DiffPickIdx[pn] = i
					break
				end
			end
		end
	end
	DiffPickOpen = true
	for _, p in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if DiffFrame[p] then DiffFrame[p]:visible(true) end
	end
	RefreshDiffPicker()
	SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
end

local function CloseDiffPicker()
	DiffPickOpen = false
	for _, p in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if DiffFrame[p] then DiffFrame[p]:visible(false) end
	end
end

local function ConfirmDifficulty()
	if Accepted then return end
	SaveCursorState()
	StopPreview()
	GAMESTATE:SetCurrentSong(DiffSong)
	GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		local idx = DiffPickIdx[pn] or 1
		local steps = DiffSteps[idx]
		if not steps then return end
		GAMESTATE:SetCurrentSteps(pn, steps)
		GAMESTATE:SetPreferredDifficulty(pn, steps:GetDifficulty())
	end
	Accepted = true
	CloseDiffPicker()
	SOUND:PlayOnce(THEME:GetPathS("Common", "start"))
	SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
end

-- Called when Start is pressed on a song
local function ConfirmSong()
	if Accepted or not IsSong(Cursor) then return end
	local entry = FlatList[Cursor]
	local song = entry[1]
	-- Gather available Steps
	local stepsArray = {}
	for i = 2, #entry do
		stepsArray[#stepsArray + 1] = entry[i]
	end
	if #stepsArray == 0 then return end
	if #stepsArray == 1 then
		-- Single difficulty - skip picker
		SaveCursorState()
		StopPreview()
		GAMESTATE:SetCurrentSong(song)
		GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
		for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
			GAMESTATE:SetCurrentSteps(pn, stepsArray[1])
		end
		Accepted = true
		SOUND:PlayOnce(THEME:GetPathS("Common", "start"))
		SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
	else
		-- Multiple difficulties - open picker
		OpenDiffPicker(song, stepsArray)
	end
end

-- Factory: Create difficulty picker for a player
local function MakeDiffPicker(pn)
	local isVersus = GAMESTATE:GetNumPlayersEnabled() > 1
	local boxX
	if isVersus then
		boxX = (pn == PLAYER_1) and (SCREEN_CENTER_X - DIFF_W/2 - 20)
		                           or (SCREEN_CENTER_X + DIFF_W/2 + 20)
	else
		boxX = SCREEN_CENTER_X
	end

	local pColors = {
		[PLAYER_1] = { border = color("#334488"), highlight = color("#334488aa") },
		[PLAYER_2] = { border = color("#883344"), highlight = color("#883344aa") },
	}
	local pc = pColors[pn] or pColors[PLAYER_1]

	local m = Def.ActorFrame{
		Name = "DiffPicker_"..ToEnumShortString(pn),
		InitCommand = function(self)
			DiffFrame[pn] = self
			self:visible(false)
		end,
		RefreshDiffCommand = function(self)
			local n = #DiffSteps
			local totalH = n * DIFF_ROW_H + 80
			local topY = SCREEN_CENTER_Y - totalH/2

			-- Size background
			local bg = self:GetChild("DiffBG")
			local border = self:GetChild("DiffBorder")
			if bg then bg:y(SCREEN_CENTER_Y):zoomto(DIFF_W, totalH) end
			if border then border:y(SCREEN_CENTER_Y):zoomto(DIFF_W + 4, totalH + 4) end

			-- Title
			local title = self:GetChild("DiffTitle")
			if title and DiffSong then
				title:y(topY + 25):settext(DiffSong:GetDisplayMainTitle())
			end

			local selIdx = DiffPickIdx[pn] or 1

			-- Rows
			for i = 1, MAX_DIFFS do
				local rowBG = self:GetChild("DiffRowBG"..i)
				local label = self:GetChild("DiffLabel"..i)
				local meter = self:GetChild("DiffMeter"..i)
				if i <= n then
					local st = DiffSteps[i]
					local dc = GetDiffColor(st)
					local rowY = topY + 60 + (i - 1) * DIFF_ROW_H + DIFF_ROW_H/2
					local sel = (i == selIdx)
					if rowBG then
						rowBG:visible(true):y(rowY)
						rowBG:diffuse(sel and pc.highlight or color("#00000000"))
					end
					if label then
						label:visible(true):y(rowY)
						label:settext(ToEnumShortString(st:GetDifficulty()))
						label:diffuse(sel and dc or color("#888888"))
					end
					if meter then
						meter:visible(true):y(rowY)
						meter:settext(tostring(st:GetMeter()))
						meter:diffuse(sel and dc or color("#666666"))
					end
				else
					if rowBG then rowBG:visible(false) end
					if label then label:visible(false) end
					if meter then meter:visible(false) end
				end
			end
		end,

		-- Border
		Def.Quad{
			Name = "DiffBorder",
			InitCommand = function(self)
				self:x(boxX):zoomto(DIFF_W + 4, 200)
					:diffuse(pc.border)
			end,
		},
		-- Background
		Def.Quad{
			Name = "DiffBG",
			InitCommand = function(self)
				self:x(boxX):zoomto(DIFF_W, 200)
					:diffuse(color("#0a0a18")):diffusealpha(0.95)
			end,
		},
		-- Title
		Def.BitmapText{
			Font = "_wheelnames 28px",
			Name = "DiffTitle",
			InitCommand = function(self)
				self:x(boxX):zoom(0.7)
					:diffuse(Color.White)
					:maxwidth(DIFF_W - 20)
					:strokecolor(color("0,0,0,0.8"))
			end,
		},
	}

	-- Difficulty rows
	for i = 1, MAX_DIFFS do
		m[#m+1] = Def.Quad{
			Name = "DiffRowBG"..i,
			InitCommand = function(self)
				self:x(boxX):zoomto(DIFF_W - 10, DIFF_ROW_H - 6):visible(false)
			end,
		}
		m[#m+1] = Def.BitmapText{
			Font = "_wheelnames 28px",
			Name = "DiffLabel"..i,
			InitCommand = function(self)
				self:x(boxX - DIFF_W/2 + 60):zoom(0.5)
					:visible(false):halign(0)
					:strokecolor(color("0,0,0,0.8"))
			end,
		}
		m[#m+1] = Def.BitmapText{
			Font = "_impact 32px",
			Name = "DiffMeter"..i,
			InitCommand = function(self)
				self:x(boxX + DIFF_W/2 - 40):zoom(0.8)
					:visible(false):halign(1)
					:strokecolor(color("0,0,0,0.8"))
			end,
		}
	end

	return m
end

-- ============================================================================
-- SIDE MENU (Stage 7)
-- ============================================================================

local MENU_W = 380
local MENU_ROW_H = 36
local MENU_PAD = 12

-- Option definitions
local SpeedModes = {
	{ label = "XMod",  value = "XMod" },
	{ label = "CMod",  value = "CMod" },
	{ label = "MMod",  value = "MMod" },
}

local XModValues = {}
do
	for v = 25, 800, 25 do
		XModValues[#XModValues+1] = { label = string.format("x%.2f", v/100), value = v/100 }
	end
end

local BPMValues = {}
do
	for v = 100, 1000, 50 do
		BPMValues[#BPMValues+1] = { label = tostring(v), value = v }
	end
end

local TurnChoices = {
	{ label = "Off",     mod = "" },
	{ label = "Mirror",  mod = "Mirror" },
	{ label = "Left",    mod = "Left" },
	{ label = "Right",   mod = "Right" },
	{ label = "Shuffle", mod = "Shuffle" },
}

local ScrollChoices = {
	{ label = "Normal",  mod = "" },
	{ label = "Reverse", mod = "Reverse" },
}

local MenuGaugeChoices = {
	{ label = "Normal",     value = "Normal" },
	{ label = "LIFE4",      value = "LIFE4" },
	{ label = "Risky",      value = "Risky" },
	{ label = "Flare I",    value = "Flare1" },
	{ label = "Flare II",   value = "Flare2" },
	{ label = "Flare III",  value = "Flare3" },
	{ label = "Flare IV",   value = "Flare4" },
	{ label = "Flare V",    value = "Flare5" },
	{ label = "Flare VI",   value = "Flare6" },
	{ label = "Flare VII",  value = "Flare7" },
	{ label = "Flare VIII", value = "Flare8" },
	{ label = "Flare IX",   value = "Flare9" },
	{ label = "Flare EX",   value = "FlareEX" },
	{ label = "Floating",   value = "FloatingFlare" },
}

local MENU_ROW_NAMES = { "Mode", "Speed", "Turn", "Scroll", "Gauge" }
local NUM_MENU_ROWS = #MENU_ROW_NAMES

-- Helper: find index by field value
local function FindChoiceIdx(choices, field, val, fallback)
	for i, c in ipairs(choices) do
		if c[field] == val then return i end
	end
	return fallback or 1
end

-- Helper: find closest numeric value
local function FindClosestIdx(choices, val)
	local bestIdx, bestDist = 1, 999999
	for i, c in ipairs(choices) do
		local d = math.abs(c.value - val)
		if d < bestDist then bestIdx, bestDist = i, d end
	end
	return bestIdx
end

-- Build options for a player from current state
local function BuildOptionsForPlayer(pn)
	local po = GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred")

	-- Detect current speed mode
	local modeIdx = 1
	local speedChoices = XModValues
	local speedIdx = 1

	local cmod = po:CMod()
	local mmod = po:MMod()
	local xmod = po:ScrollSpeed()

	if cmod and cmod > 0 then
		modeIdx = 2
		speedChoices = BPMValues
		speedIdx = FindClosestIdx(speedChoices, cmod)
	elseif mmod and mmod > 0 then
		modeIdx = 3
		speedChoices = BPMValues
		speedIdx = FindClosestIdx(speedChoices, mmod)
	else
		modeIdx = 1
		speedChoices = XModValues
		speedIdx = FindClosestIdx(speedChoices, xmod or 1)
	end

	-- Turn
	local turnIdx = 1
	if po:Mirror() then turnIdx = 2
	elseif po:Left() then turnIdx = 3
	elseif po:Right() then turnIdx = 4
	elseif po:Shuffle() then turnIdx = 5
	end

	-- Scroll
	local scrollIdx = po:Reverse() == 1 and 2 or 1

	-- Gauge
	local gaugeIdx = 1
	local gaugeType = GetPlayerGaugePref and GetPlayerGaugePref(pn) or "Normal"
	gaugeIdx = FindChoiceIdx(MenuGaugeChoices, "value", gaugeType, 1)

	return {
		{ name = "Mode",   choices = SpeedModes,       selected = modeIdx },
		{ name = "Speed",  choices = speedChoices,     selected = speedIdx },
		{ name = "Turn",   choices = TurnChoices,      selected = turnIdx },
		{ name = "Scroll", choices = ScrollChoices,    selected = scrollIdx },
		{ name = "Gauge",  choices = MenuGaugeChoices, selected = gaugeIdx },
	}
end

-- Sync speed choices when mode changes
local function SyncSpeedChoices(pn)
	local rows = PlayerOptions[pn]
	if not rows then return end
	local mode = SpeedModes[rows[1].selected].value
	local oldVal = rows[2].choices[rows[2].selected]
	if mode == "XMod" then
		rows[2].choices = XModValues
		rows[2].selected = FindClosestIdx(XModValues, oldVal and oldVal.value or 1)
	else
		rows[2].choices = BPMValues
		rows[2].selected = FindClosestIdx(BPMValues, oldVal and oldVal.value or 300)
	end
end

-- Apply options to player
local function ApplyMenuOptions(pn)
	local rows = PlayerOptions[pn]
	if not rows then return end

	local mode = SpeedModes[rows[1].selected].value
	local speedVal = rows[2].choices[rows[2].selected].value
	local turn = TurnChoices[rows[3].selected].mod
	local scroll = ScrollChoices[rows[4].selected].mod
	local gauge = MenuGaugeChoices[rows[5].selected].value

	-- Build mod string
	local mods = {}

	-- Speed
	if mode == "XMod" then
		mods[#mods+1] = string.format("%.2fx", speedVal)
	elseif mode == "CMod" then
		mods[#mods+1] = "C" .. speedVal
	elseif mode == "MMod" then
		mods[#mods+1] = "M" .. speedVal
	end

	-- Turn
	if turn ~= "" then mods[#mods+1] = turn end

	-- Scroll
	if scroll ~= "" then mods[#mods+1] = scroll end

	-- Apply mods
	if #mods > 0 then
		GAMESTATE:ApplyPreferredModifiers(pn, table.concat(mods, ","))
	end

	-- Gauge (use existing system)
	if SetPlayerGaugePref then
		SetPlayerGaugePref(pn, gauge)
	end
end

local function RefreshMenu(pn)
	if MenuFrame[pn] then MenuFrame[pn]:playcommand("Refresh") end
end

local function OpenMenu(pn)
	PlayerOptions[pn] = BuildOptionsForPlayer(pn)
	MenuRow[pn] = 1
	MenuOpen[pn] = true
	if MenuFrame[pn] then MenuFrame[pn]:visible(true) end
	RefreshMenu(pn)
end

local function CloseMenu(pn, apply)
	if apply then ApplyMenuOptions(pn) end
	MenuOpen[pn] = false
	if MenuFrame[pn] then MenuFrame[pn]:visible(false) end
end

local function AnyMenuOpen()
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if MenuOpen[pn] then return true end
	end
	return false
end

-- Factory: Create side menu for a player
local function MakeMenu(pn)
	local totalH = MENU_PAD + 30 + NUM_MENU_ROWS * MENU_ROW_H + MENU_PAD
	local topY = SCREEN_CENTER_Y - totalH/2
	local centerY = topY + totalH/2
	local menuX = (pn == PLAYER_1) and (MENU_W/2 + 20) or (SCREEN_WIDTH - MENU_W/2 - 20)

	local borderColor = (pn == PLAYER_1) and color("#334488") or color("#883344")

	local m = Def.ActorFrame{
		Name = "SideMenu_"..ToEnumShortString(pn),
		InitCommand = function(self)
			MenuFrame[pn] = self
			self:visible(false)
		end,
		RefreshCommand = function(self)
			local rows = PlayerOptions[pn]
			if not rows then return end
			for i = 1, NUM_MENU_ROWS do
				local row = rows[i]
				local rowBG = self:GetChild("RowBG"..i)
				local label = self:GetChild("Label"..i)
				local value = self:GetChild("Value"..i)
				if rowBG then
					rowBG:diffuse(i == MenuRow[pn] and color("#333366") or color("#00000000"))
				end
				if label then
					label:settext(row and row.name or MENU_ROW_NAMES[i])
					label:diffuse(i == MenuRow[pn] and Color.White or color("#888888"))
				end
				if value then
					local ch = row and row.choices[row.selected]
					value:settext(ch and ch.label or "")
					value:diffuse(i == MenuRow[pn] and Color.White or color("#aaaaaa"))
				end
			end
		end,

		-- Border
		Def.Quad{
			InitCommand = function(self)
				self:xy(menuX, centerY)
					:zoomto(MENU_W + 4, totalH + 4)
					:diffuse(borderColor)
			end,
		},
		-- Background
		Def.Quad{
			InitCommand = function(self)
				self:xy(menuX, centerY)
					:zoomto(MENU_W, totalH)
					:diffuse(color("#0a0a18"))
					:diffusealpha(0.95)
			end,
		},
		-- Title
		Def.BitmapText{
			Font = "_wheelnames 28px",
			Text = "OPTIONS",
			InitCommand = function(self)
				self:xy(menuX, topY + MENU_PAD + 12)
					:zoom(0.6)
					:diffuse(Color.White)
					:strokecolor(color("0,0,0,0.8"))
			end,
		},
		-- Divider
		Def.Quad{
			InitCommand = function(self)
				self:xy(menuX, topY + MENU_PAD + 26)
					:zoomto(MENU_W - 20, 1)
					:diffuse(color("#444466"))
			end,
		},
	}

	-- Option rows
	for i = 1, NUM_MENU_ROWS do
		local rowY = topY + MENU_PAD + 30 + (i - 1) * MENU_ROW_H + MENU_ROW_H/2

		m[#m+1] = Def.Quad{
			Name = "RowBG"..i,
			InitCommand = function(self)
				self:xy(menuX, rowY)
					:zoomto(MENU_W - 8, MENU_ROW_H - 4)
					:diffuse(color("#00000000"))
			end,
		}
		m[#m+1] = Def.BitmapText{
			Font = "_wheelnames 28px",
			Name = "Label"..i,
			InitCommand = function(self)
				self:xy(menuX - MENU_W/2 + 20, rowY)
					:zoom(0.45):halign(0)
					:diffuse(color("#888888"))
					:strokecolor(color("0,0,0,0.8"))
			end,
		}
		m[#m+1] = Def.BitmapText{
			Font = "_wheelnames 28px",
			Name = "Value"..i,
			InitCommand = function(self)
				self:xy(menuX + MENU_W/2 - 20, rowY)
					:zoom(0.45):halign(1)
					:diffuse(color("#aaaaaa"))
					:strokecolor(color("0,0,0,0.8"))
			end,
		}
	end

	return m
end

-- ============================================================================
-- SCORE PANEL (Stage 8)
-- ============================================================================

local PANEL_W = 320
local PANEL_H = 200
local PANEL_ROW_H = 32
local PANEL_Y = SCREEN_CENTER_Y + 100

local PANEL_DIFFS = {
	"Difficulty_Beginner",
	"Difficulty_Easy",
	"Difficulty_Medium",
	"Difficulty_Hard",
	"Difficulty_Challenge",
}

local PANEL_DIFF_LABELS = { "BEG", "BSC", "DIF", "EXP", "CHA" }

local PANEL_DIFF_COLORS = {
	Difficulty_Beginner = color("#66ccff"),
	Difficulty_Easy     = color("#ffcc33"),
	Difficulty_Medium   = color("#ff6666"),
	Difficulty_Hard     = color("#66ff66"),
	Difficulty_Challenge= color("#cc66ff"),
}

local LampColors = {
	MFC   = color("#00ccff"),
	PFC   = color("#ffcc00"),
	GFC   = color("#00ff66"),
	FC    = color("#ffffff"),
	LIFE4 = color("#ff66cc"),
	Clear = color("#888888"),
}

-- Get score data for a player's steps
local function GetScoreData(pn, song, steps)
	if not song or not steps then return nil end

	local profile = PROFILEMAN:GetProfile(pn)
	if not profile then return nil end

	local scorelist = profile:GetHighScoreList(song, steps)
	if not scorelist then return nil end

	local scores = scorelist:GetHighScores()
	if not scores or not scores[1] then return nil end

	local hs = scores[1]
	return {
		score = hs:GetScore(),
		grade = string.gsub(ToEnumShortString(hs:GetGrade()), "Grade_", ""),
	}
end

-- Refresh score panel for a song
local function RefreshScorePanel(pn, song)
	local panel = ScorePanelFrame[pn]
	if not panel then return end

	local st = GAMESTATE:GetCurrentStyle()
	local stepsType = st and st:GetStepsType() or nil

	for i = 1, 5 do
		local diffEnum = PANEL_DIFFS[i]
		local diffText = panel:GetChild("SPDiff"..i)
		local meterText = panel:GetChild("SPMeter"..i)
		local gradeText = panel:GetChild("SPGrade"..i)
		local scoreText = panel:GetChild("SPScore"..i)
		local lampText = panel:GetChild("SPLamp"..i)
		local rowBG = panel:GetChild("SPRowBG"..i)

		local dc = PANEL_DIFF_COLORS[diffEnum] or color("#888888")
		local hasDiff = song and stepsType and song:HasStepsTypeAndDifficulty(stepsType, diffEnum)

		if hasDiff then
			local steps = song:GetOneSteps(stepsType, diffEnum)
			local data = GetScoreData(pn, song, steps)
			local chartKey = GetChartKey and GetChartKey(song, steps)
			local cr = chartKey and GetChartResult and GetChartResult(pn, chartKey)

			if diffText then
				diffText:settext(PANEL_DIFF_LABELS[i])
				diffText:diffuse(dc)
			end
			if meterText then
				meterText:settext(tostring(steps:GetMeter()))
				meterText:diffuse(dc)
			end

			if data then
				if gradeText then
					gradeText:settext(data.grade)
					gradeText:diffuse(Color.White)
				end
				if scoreText then
					scoreText:settext(tostring(data.score))
					scoreText:diffuse(Color.White)
				end
			else
				if gradeText then gradeText:settext("---"); gradeText:diffuse(color("#555555")) end
				if scoreText then scoreText:settext("---"); scoreText:diffuse(color("#555555")) end
			end

			-- Lamp from ChartResults
			if cr and cr.lamp and lampText then
				lampText:settext(cr.lamp)
				lampText:diffuse(LampColors[cr.lamp] or color("#888888"))
			elseif lampText then
				lampText:settext("")
			end

			if rowBG then rowBG:diffusealpha(0) end
		else
			-- Difficulty doesn't exist
			if diffText then diffText:settext(PANEL_DIFF_LABELS[i]); diffText:diffuse(color("#333333")) end
			if meterText then meterText:settext("--"); meterText:diffuse(color("#333333")) end
			if gradeText then gradeText:settext(""); gradeText:diffusealpha(0) end
			if scoreText then scoreText:settext(""); scoreText:diffusealpha(0) end
			if lampText then lampText:settext(""); lampText:diffusealpha(0) end
			if rowBG then rowBG:diffusealpha(0) end
		end
	end
end

-- Factory: Create score panel for a player
local function MakeScorePanel(pn)
	local isVersus = GAMESTATE:GetNumPlayersEnabled() > 1
	local panelX
	if isVersus then
		panelX = (pn == PLAYER_1) and (PANEL_W/2 + 30) or (SCREEN_WIDTH - PANEL_W/2 - 30)
	else
		panelX = SCREEN_WIDTH - PANEL_W/2 - 30
	end

	local pnShort = ToEnumShortString(pn)

	local panel = Def.ActorFrame{
		Name = "ScorePanel_"..pnShort,
		InitCommand = function(self)
			self:xy(panelX, PANEL_Y)
			self:visible(GAMESTATE:IsPlayerEnabled(pn))
			ScorePanelFrame[pn] = self
		end,

		-- Background
		Def.Quad{
			InitCommand = function(self)
				self:zoomto(PANEL_W, PANEL_H)
				self:diffuse(color("#0a0a18")):diffusealpha(0.85)
			end,
		},
		-- Border
		Def.Quad{
			InitCommand = function(self)
				self:zoomto(PANEL_W + 2, PANEL_H + 2)
				local bc = (pn == PLAYER_1) and color("#334488") or color("#883344")
				self:diffuse(bc):diffusealpha(0.5)
			end,
		},
		-- Header
		Def.BitmapText{
			Font = "_wheelnames 28px",
			Text = "HIGH SCORES",
			InitCommand = function(self)
				self:y(-PANEL_H/2 + 15):zoom(0.45)
				self:diffuse(Color.White)
				self:strokecolor(color("0,0,0,0.8"))
			end,
		},
	}

	-- Score rows
	local startY = -PANEL_H/2 + 40
	for i = 1, 5 do
		local rowY = startY + (i - 1) * PANEL_ROW_H

		-- Row highlight
		panel[#panel+1] = Def.Quad{
			Name = "SPRowBG"..i,
			InitCommand = function(self)
				self:y(rowY):zoomto(PANEL_W - 8, PANEL_ROW_H - 4)
				self:diffusealpha(0)
			end,
		}
		-- Difficulty label
		panel[#panel+1] = Def.BitmapText{
			Font = "_wheelnames 28px",
			Name = "SPDiff"..i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 30, rowY):zoom(0.35):halign(0)
				self:strokecolor(color("0,0,0,0.8"))
			end,
		}
		-- Meter
		panel[#panel+1] = Def.BitmapText{
			Font = "_impact 32px",
			Name = "SPMeter"..i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 70, rowY):zoom(0.5):halign(0)
				self:strokecolor(color("0,0,0,0.8"))
			end,
		}
		-- Grade
		panel[#panel+1] = Def.BitmapText{
			Font = "_wheelnames 28px",
			Name = "SPGrade"..i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 110, rowY):zoom(0.35):halign(0)
				self:strokecolor(color("0,0,0,0.8"))
			end,
		}
		-- Score
		panel[#panel+1] = Def.BitmapText{
			Font = "_wheelnames 28px",
			Name = "SPScore"..i,
			InitCommand = function(self)
				self:xy(PANEL_W/2 - 50, rowY):zoom(0.35):halign(1)
				self:strokecolor(color("0,0,0,0.8"))
			end,
		}
		-- Lamp
		panel[#panel+1] = Def.BitmapText{
			Font = "_wheelnames 28px",
			Name = "SPLamp"..i,
			InitCommand = function(self)
				self:xy(PANEL_W/2 - 15, rowY):zoom(0.3):halign(1)
				self:strokecolor(color("0,0,0,0.8"))
			end,
		}
	end

	return panel
end

-- ============================================================================
-- SONG PREVIEW (Stage 9)
-- ============================================================================

local function StopPreview()
	PreviewGen = PreviewGen + 1
	if CurrentPreviewPath then
		CurrentPreviewPath = nil
		SOUND:StopMusic()
	end
end

local function StartPreview()
	PreviewGen = PreviewGen + 1
	if PreviewActor then
		PreviewActor:stoptweening()
		PreviewActor:sleep(PREVIEW_DELAY)
		PreviewActor:queuecommand("DoPreview")
		PreviewActor._gen = PreviewGen
	end
end

-- Factory: Create preview actor (invisible, just handles timing)
local function MakePreviewActor()
	return Def.Actor{
		Name = "PreviewActor",
		InitCommand = function(self)
			PreviewActor = self
			self._gen = 0
		end,
		DoPreviewCommand = function(self)
			-- Check generation to cancel stale previews
			if self._gen ~= PreviewGen then return end

			-- Get current song from cursor
			local song = nil
			if IsSong(Cursor) then
				local item = FlatList[Cursor]
				song = item[1]
			end

			if song then
				local path = song:GetPreviewMusicPath()
				if path and path ~= "" then
					-- Skip if already playing this file
					if path == CurrentPreviewPath then return end
					CurrentPreviewPath = path
					SOUND:PlayMusicPart(
						path,
						song:GetSampleStart(),
						song:GetSampleLength(),
						0,    -- fadeIn
						0,    -- fadeOut
						true, -- loop
						false,-- applyRate
						false -- alignBeat
					)
				end
			else
				-- On a group header - stop music
				StopPreview()
			end
		end,
		OffCommand = function(self)
			StopPreview()
		end,
	}
end

-- ============================================================================
-- LAYOUT & SCROLL (Stage 4)
-- ============================================================================

-- Layout constants
local ROW_HEIGHT = 120        -- Vertical spacing between rows
local CARD_SCALE_FOCUS = 1.0  -- Scale for focused card
local CARD_SCALE_NORMAL = 0.85 -- Scale for non-focused cards
local VISIBLE_ROWS = 5        -- Number of visible rows (2 above, 1 center, 2 below)
local CENTER_Y = 0            -- Y position of center row (relative to PoolRoot)

-- Scroll state
local ScrollOffset = 0        -- Current visual scroll offset (fractional rows)
local TargetRow = 0           -- Target row (derived from Cursor)
local ScrollVelocity = 0      -- For cubic Hermite continuity

-- Cubic Hermite interpolation for smooth scrolling
local function CubicHermite(t, p0, p1, m0, m1)
	local t2 = t * t
	local t3 = t2 * t
	return (2*t3 - 3*t2 + 1) * p0 + (t3 - 2*t2 + t) * m0 + (-2*t3 + 3*t2) * p1 + (t3 - t2) * m1
end

-- Get the row index for a flat list index
local function GetRow(flatIdx)
	return math.floor((flatIdx - 1) / COLS)
end

-- Get the column for a flat list index (0, 1, or 2)
local function GetCol(flatIdx)
	return (flatIdx - 1) % COLS
end

-- Compute which items should be visible based on current scroll position
local function ComputeVisibleItems()
	local visible = {}
	local centerRow = GetRow(Cursor)
	local startRow = centerRow - math.floor(VISIBLE_ROWS / 2) - 1
	local endRow = centerRow + math.ceil(VISIBLE_ROWS / 2) + 1

	for row = startRow, endRow do
		for col = 0, COLS - 1 do
			local flatIdx = row * COLS + col + 1
			if flatIdx >= 1 and flatIdx <= #FlatList then
				visible[#visible + 1] = {
					flatIdx = flatIdx,
					row = row,
					col = col,
				}
			end
		end
	end

	return visible
end

-- Hide all pool actors
local function HideAllPools()
	for i = 1, POOL_CARDS do
		if CardPool[i] then CardPool[i]:visible(false) end
	end
	for i = 1, POOL_HEADERS do
		if HeaderPool[i] then HeaderPool[i]:visible(false) end
	end
	-- Reset assignments
	CardAssign = {}
	CardByFlat = {}
end

-- Main refresh function - updates all visible actors
local function Refresh()
	if not PoolRoot then return end
	if #FlatList == 0 then return end

	HideAllPools()

	local visible = ComputeVisibleItems()
	local cursorRow = GetRow(Cursor)
	local cursorCol = GetCol(Cursor)

	local cardIdx = 1
	local headerIdx = 1

	for _, v in ipairs(visible) do
		local flatIdx = v.flatIdx
		local row = v.row
		local col = v.col
		local item = FlatList[flatIdx]

		-- Calculate position
		local rowOffset = row - cursorRow - ScrollOffset
		local x = STAGGER[col].x
		local y = CENTER_Y + rowOffset * ROW_HEIGHT + STAGGER[col].y

		-- Determine if this item is focused
		local isFocused = (flatIdx == Cursor)

		-- Scale based on focus
		local scale = isFocused and CARD_SCALE_FOCUS or CARD_SCALE_NORMAL

		-- Fade items near edges
		local alpha = 1.0
		local edgeDist = math.abs(rowOffset)
		if edgeDist > 1.5 then
			alpha = math.max(0, 1 - (edgeDist - 1.5) / 1.0)
		end

		if IsGroup(flatIdx) then
			-- Use a header from the pool
			if headerIdx <= POOL_HEADERS then
				local header = HeaderPool[headerIdx]
				if header then
					header:xy(x, y)
					header:zoom(scale)
					header:diffusealpha(alpha)
					UpdateGroupHeader(header, item, item == OpenGroup, isFocused)
					headerIdx = headerIdx + 1
				end
			end
		else
			-- Use a card from the pool
			if cardIdx <= POOL_CARDS then
				local card = CardPool[cardIdx]
				if card then
					card:xy(x, y)
					card:zoom(scale)
					card:diffusealpha(alpha)
					UpdateSongCard(card, item, isFocused)
					CardAssign[cardIdx] = flatIdx
					CardByFlat[flatIdx] = cardIdx
					cardIdx = cardIdx + 1
				end
			end
		end
	end
end

-- Scroll animation state
local AnimElapsed = 0
local AnimStartOffset = 0
local AnimTargetOffset = 0
local AnimStartVel = 0
local IsAnimating = false

-- Start a scroll animation
local function StartScrollAnimation(targetOffset)
	AnimElapsed = 0
	AnimStartOffset = ScrollOffset
	AnimTargetOffset = targetOffset
	AnimStartVel = ScrollVelocity
	IsAnimating = true
end

-- Update scroll animation (called each frame via SetUpdateFunction)
local function UpdateScroll(self)
	-- Accumulate time from frame delta
	local dt = self:GetEffectDelta()
	AccumulatedTime = AccumulatedTime + dt

	if not IsAnimating then return end

	AnimElapsed = AnimElapsed + dt
	local t = math.min(1, AnimElapsed / ANIM_DUR)

	if t >= 1 then
		-- Animation complete
		ScrollOffset = AnimTargetOffset
		ScrollVelocity = 0
		IsAnimating = false
	else
		-- Cubic Hermite interpolation
		local targetVel = 0
		ScrollOffset = CubicHermite(t, AnimStartOffset, AnimTargetOffset, AnimStartVel * ANIM_DUR, targetVel * ANIM_DUR)
		-- Estimate velocity for continuity
		ScrollVelocity = (AnimTargetOffset - AnimStartOffset) * (1 - t) / ANIM_DUR
	end

	Refresh()
end

-- ============================================================================
-- NAVIGATION (Stage 4/5)
-- ============================================================================

local function MoveCursor(delta)
	local oldRow = GetRow(Cursor)
	Cursor = Wrap(Cursor + delta)
	local newRow = GetRow(Cursor)

	-- If row changed, animate the scroll
	if newRow ~= oldRow then
		-- Set offset so view appears to stay in place, then animate to 0
		ScrollOffset = ScrollOffset + (oldRow - newRow)
		StartScrollAnimation(0)
	end

	Refresh()
	MESSAGEMAN:Broadcast("CursorChanged")
end

-- ============================================================================
-- INPUT HANDLER
-- ============================================================================

local function InputHandler(event)
	if event.type == "InputEventType_Release" then return false end
	if Accepted then return true end

	local button = event.GameButton
	if not button then return false end

	local pn = event.PlayerNumber
	if not pn then return false end

	-- When diff picker is open, route input to picker (blocks all else)
	if DiffPickOpen then
		if button == "MenuUp" or button == "MenuLeft" then
			DiffPickIdx[pn] = (DiffPickIdx[pn] or 1) - 1
			if DiffPickIdx[pn] < 1 then DiffPickIdx[pn] = #DiffSteps end
			SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
			RefreshDiffPicker()
			return true
		elseif button == "MenuDown" or button == "MenuRight" then
			DiffPickIdx[pn] = (DiffPickIdx[pn] or 1) + 1
			if DiffPickIdx[pn] > #DiffSteps then DiffPickIdx[pn] = 1 end
			SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
			RefreshDiffPicker()
			return true
		elseif button == "Start" then
			ConfirmDifficulty()
			return true
		elseif button == "Back" then
			CloseDiffPicker()
			SOUND:PlayOnce(THEME:GetPathS("_Screen", "cancel"))
			return true
		end
		return true
	end

	-- Select opens/closes options menu for this player
	if button == "Select" then
		if MenuOpen[pn] then
			CloseMenu(pn, true)  -- apply options on close
			SOUND:PlayOnce(THEME:GetPathS("Common", "start"))
		else
			OpenMenu(pn)
			SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
		end
		return true
	end

	-- When this player's menu is open, route their input to menu
	if MenuOpen[pn] then
		local rows = PlayerOptions[pn]
		if button == "MenuUp" then
			MenuRow[pn] = MenuRow[pn] - 1
			if MenuRow[pn] < 1 then MenuRow[pn] = NUM_MENU_ROWS end
			SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
			RefreshMenu(pn)
			return true
		elseif button == "MenuDown" then
			MenuRow[pn] = MenuRow[pn] + 1
			if MenuRow[pn] > NUM_MENU_ROWS then MenuRow[pn] = 1 end
			SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
			RefreshMenu(pn)
			return true
		elseif button == "MenuLeft" then
			local row = rows[MenuRow[pn]]
			row.selected = row.selected - 1
			if row.selected < 1 then row.selected = #row.choices end
			-- Sync speed choices when mode changes
			if MenuRow[pn] == 1 then SyncSpeedChoices(pn) end
			SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
			RefreshMenu(pn)
			return true
		elseif button == "MenuRight" then
			local row = rows[MenuRow[pn]]
			row.selected = row.selected + 1
			if row.selected > #row.choices then row.selected = 1 end
			-- Sync speed choices when mode changes
			if MenuRow[pn] == 1 then SyncSpeedChoices(pn) end
			SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
			RefreshMenu(pn)
			return true
		elseif button == "Start" then
			CloseMenu(pn, true)
			SOUND:PlayOnce(THEME:GetPathS("Common", "start"))
			return true
		elseif button == "Back" then
			CloseMenu(pn, false)  -- discard changes
			SOUND:PlayOnce(THEME:GetPathS("_Screen", "cancel"))
			return true
		end
		return true
	end

	-- Normal navigation (no menu open for this player)
	if button == "MenuRight" then
		MoveCursor(1)
		return true
	elseif button == "MenuLeft" then
		MoveCursor(-1)
		return true
	elseif button == "MenuDown" then
		MoveCursor(COLS)
		return true
	elseif button == "MenuUp" then
		MoveCursor(-COLS)
		return true
	elseif button == "Start" then
		if IsGroup(Cursor) then
			ToggleGroup(FlatList[Cursor])
		else
			ConfirmSong()
		end
		return true
	elseif button == "Back" then
		SCREENMAN:GetTopScreen():Cancel()
		return true
	end

	return false
end

-- ============================================================================
-- MAIN ACTOR
-- ============================================================================

local t = Def.ActorFrame{
	Name = "ScreenA3MusicOverlay",

	OnCommand = function(self)
		Trace("[ScreenA3Music] Screen loaded successfully!")

		-- Store reference to pool root
		PoolRoot = self:GetChild("PoolRoot")

		-- Populate pool arrays from created actors
		if PoolRoot then
			for i = 1, POOL_CARDS do
				CardPool[i] = PoolRoot:GetChild("Card"..i)
			end
			for i = 1, POOL_HEADERS do
				HeaderPool[i] = PoolRoot:GetChild("Header"..i)
			end
			Trace("[ScreenA3Music] Pools initialized: "..#CardPool.." cards, "..#HeaderPool.." headers")
		end

		-- Build initial data
		BuildFlatList()

		-- Restore cursor position from previous visit
		RestoreCursorState()

		-- Set up input handler
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)

		-- Initial refresh
		Refresh()

		-- Set up animation update loop
		self:SetUpdateFunction(UpdateScroll)

		-- Trigger initial display update
		MESSAGEMAN:Broadcast("CursorChanged")
	end,

	OffCommand = function(self)
		self:finishtweening()
		StopPreview()
	end,

	CursorChangedMessageCommand = function(self)
		Refresh()
		-- Refresh score panels when cursor lands on a song
		local item = FlatList[Cursor]
		local song = nil
		if IsSong(Cursor) then
			song = item[1]
		end
		for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
			RefreshScorePanel(pn, song)
		end
		-- Start song preview
		StartPreview()
	end,
}

-- Pool root container (centered on screen)
local poolRoot = Def.ActorFrame{
	Name = "PoolRoot",
	InitCommand = function(s) s:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y) end,
}

-- Create song card pool
for i = 1, POOL_CARDS do
	poolRoot[#poolRoot + 1] = MakeSongCard(i)
end

-- Create group header pool
for i = 1, POOL_HEADERS do
	poolRoot[#poolRoot + 1] = MakeGroupHeader(i)
end

t[#t + 1] = poolRoot

-- Difficulty pickers (one per player, created even if not needed)
t[#t + 1] = MakeDiffPicker(PLAYER_1)
t[#t + 1] = MakeDiffPicker(PLAYER_2)

-- Side menus (one per player)
t[#t + 1] = MakeMenu(PLAYER_1)
t[#t + 1] = MakeMenu(PLAYER_2)

-- Score panels (one per player)
t[#t + 1] = MakeScorePanel(PLAYER_1)
t[#t + 1] = MakeScorePanel(PLAYER_2)

-- Song preview actor
t[#t + 1] = MakePreviewActor()

-- Debug info display
t[#t+1] = Def.BitmapText{
	Name = "DebugText",
	Font = "Common Normal",
	Text = "",
	InitCommand = function(self)
		self:xy(SCREEN_CENTER_X, SCREEN_TOP + 80):diffuse(1,1,1,1):shadowlength(2):zoom(0.8)
	end,
	OnCommand = function(self)
		self:queuecommand("Update")
	end,
	UpdateCommand = function(self)
		local item = FlatList[Cursor]
		local info = "ScreenA3Music - Stage 9 (Polish)\n"
		info = info .. "Items: " .. #FlatList .. "  Cursor: " .. Cursor
		info = info .. "  Row: " .. GetRow(Cursor) .. "  Col: " .. GetCol(Cursor) .. "\n"
		info = info .. "Open: " .. (OpenGroup ~= "" and OpenGroup or "(none)")
		if DiffPickOpen then
			info = info .. "  [DIFF PICKER]"
		end
		if AnyMenuOpen() then
			info = info .. "  [MENU]"
		end
		info = info .. "\n"

		if IsGroup(Cursor) then
			info = info .. ">> GROUP: " .. item
		elseif IsSong(Cursor) then
			local song = item[1]
			info = info .. ">> " .. song:GetDisplayMainTitle()
		end

		info = info .. "\nSelect=options  Start=select  Back=exit"
		self:settext(info)
	end,
	CursorChangedMessageCommand = function(self)
		self:queuecommand("Update")
	end,
}


return t
