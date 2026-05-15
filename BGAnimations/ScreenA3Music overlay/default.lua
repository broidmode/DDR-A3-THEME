-- ScreenA3Music overlay/default.lua
-- Custom music select screen (ported from GALAXY)
-- Replaces ScreenSelectMusic with a pure-Lua 3-column grid browser

-- ============================================================================
-- CONSTANTS
-- ============================================================================
local COLS = 3
local POOL_CARDS = 75
local POOL_HEADERS = 30

-- Animation
local ANIM_DUR = 0.15  -- scroll animation duration in seconds

-- Graphics paths
local ThemeDir = THEME:GetCurrentThemeDirectory()
local sharedPath = ThemeDir .. "Graphics/_shared/"
local footerPath = ThemeDir .. "Graphics/ScreenWithMenuElements footer/"

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

-- Forward declaration for layout cache rebuild (defined in LAYOUT section)
local RebuildLayoutCache

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

-- Button state tracking (for simultaneous press detection)
local ButtonHeld = {}  -- ButtonHeld["MenuUp"] = true/false

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
		if RebuildLayoutCache then RebuildLayoutCache() end
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
	-- Keep cursor on the group header after rebuild
	for i, item in ipairs(FlatList) do
		if type(item) == "string" and item == groupName then
			Cursor = i
			break
		end
	end
	RebuildLayoutCache()
	MESSAGEMAN:Broadcast("CursorChanged")
end

-- Jump cursor to the header of the current folder
local function JumpToFolderHeader()
	if IsGroup(Cursor) then return end  -- already on a header
	-- Walk backward to find the nearest group header
	local idx = Cursor
	local n = #FlatList
	for _ = 1, n do
		idx = Wrap(idx - 1)
		if IsGroup(idx) then
			local oldCursor = Cursor
			Cursor = idx
			local offset = CalcScrollOffset(oldCursor, Cursor)
			if offset ~= 0 then
				StartScrollAnim(offset, 0)
			end
			Refresh()
			MESSAGEMAN:Broadcast("CursorChanged")
			SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
			return
		end
	end
end

-- ============================================================================
-- ACTOR POOL FACTORIES (Stage 3)
-- ============================================================================

-- Root frame for all pool actors (populated in OnCommand)
local PoolRoot = nil

-- Get the model prefix (gold/blue) - uses theme's Model() function if available
local function GetModel()
	if Model then
		return Model()
	end
	if GAMESTATE:IsExtraStage() or GAMESTATE:IsExtraStage2() then
		return "blue_"
	end
	return "gold_"
end

-- Helper: Get lamp texture path based on lamp type
local function GetLampTexture(lampType)
	local lampPath = THEME:GetCurrentThemeDirectory() .. "Graphics/MusicWheelItem Song NormalPart/lamp/"
	local mapping = {
		MFC = "ClearedMark MFC.png",
		PFC = "ClearedMark PFC.png",
		GFC = "ClearedMark GreatFC.png",
		FC = "ClearedMark GoodFC.png",
		Clear = "ClearedMark LifeBar.png",
		LIFE4 = "ClearedMark Risky.png",
		Failed = "ClearedMark Failed.png",
	}
	local file = mapping[lampType]
	if file then return lampPath .. file end
	return nil
end

-- Helper: Get flare badge texture path
local function GetFlareBadgeTexture(flareGauge)
	if not flareGauge then return nil end
	local flarePath = THEME:GetCurrentThemeDirectory() .. "Graphics/MusicWheelItem Song NormalPart/flare/"
	local level = flareGauge:match("^Flare(%d+)$")
	local filename
	if level then
		filename = "scre_flare_level_" .. level .. ".png"
	elseif flareGauge == "FlareEX" then
		filename = "scre_flare_level_ex.png"
	else
		return nil
	end
	local fullPath = flarePath .. filename
	if FILEMAN:DoesFileExist(fullPath) then
		return fullPath
	end
	return nil
end

-- Helper: Determine lamp type from high score
local function GetLampFromHighScore(score)
	if not score or score:GetScore() <= 0 then return nil end

	local misses = score:GetTapNoteScore("TapNoteScore_Miss")
	             + score:GetTapNoteScore("TapNoteScore_CheckpointMiss")
	             + score:GetTapNoteScore("TapNoteScore_HitMine")
	             + score:GetTapNoteScore("TapNoteScore_W5")
	local goods = score:GetTapNoteScore("TapNoteScore_W4")
	local greats = score:GetTapNoteScore("TapNoteScore_W3")
	local perfects = score:GetTapNoteScore("TapNoteScore_W2")
	local hasUsedBattery = string.find(score:GetModifiers() or "", "Lives")

	if misses == 0 and (score:GetTapNoteScore("TapNoteScore_W1") + perfects) > 0 then
		if greats == 0 and perfects == 0 then
			return "MFC"
		elseif greats == 0 then
			return "PFC"
		elseif goods == 0 then
			return "GFC"
		else
			return "FC"
		end
	elseif score:GetGrade() ~= "Grade_Failed" then
		return hasUsedBattery and "LIFE4" or "Clear"
	else
		return "Failed"
	end
end

-- Timing - accumulated from frame deltas
local AccumulatedTime = 0

-- Factory: Create a song card actor
local function MakeSongCard(idx)
	local cardPath = ThemeDir .. "Graphics/MusicWheelItem Song NormalPart/"

	local card = Def.ActorFrame{
		Name = "Card"..idx,
		InitCommand = function(self)
			self:visible(false)
			self.poolIdx = idx
			self.flatIdx = nil
			self.model = GetModel()
		end,

		-- Main card background
		Def.Sprite{
			Name = "CardBG",
			InitCommand = function(s)
				local m = GetModel()
				s:Load(cardPath .. m .. "card.png")
				s:zoom(0.94)
			end,
		},

		-- Golden League overlay (for special songs)
		Def.Sprite{
			Name = "LeagueOverlay",
			InitCommand = function(s)
				s:zoom(0.94):visible(false)
			end,
		},

		-- Jacket/banner
		Def.Sprite{
			Name = "Jacket",
			InitCommand = function(s) s:xy(-2.5, -1.5) end,
		},

		-- Highlight frame (shown when focused)
		Def.ActorFrame{
			Name = "Highlights",
			InitCommand = function(s) s:x(-4):visible(false) end,

			Def.Sprite{
				Name = "HighSprite",
				InitCommand = function(s)
					local m = GetModel()
					s:Load(cardPath .. m .. "high.png")
					s:zoom(0.94):x(5)
					s:diffuseramp():effectcolor1(color("1,1,1,0.2")):effectcolor2(color("1,1,1,1")):effectperiod(0.5)
				end,
			},

			Def.ActorFrame{
				InitCommand = function(s)
					s:diffuseramp():effectcolor1(color("1,1,1,0")):effectcolor2(color("1,1,1,1")):effectperiod(0.5)
				end,
				Def.Sprite{
					Name = "LineSprite",
					InitCommand = function(s)
						local m = GetModel()
						s:Load(cardPath .. m .. "line.png")
						s:zoom(0.94):x(5)
						s:thump(1):effectmagnitude(1.1,1,0):effectperiod(0.5)
					end,
				},
			},
		},

		-- "NEW" badge
		Def.Sprite{
			Name = "NewBadge",
			InitCommand = function(s)
				local m = GetModel()
				s:Load(cardPath .. m .. "new.png")
				s:xy(90, -67):halign(1):zoom(0.5):visible(false)
			end,
		},

		-- Clear lamp bases
		Def.ActorFrame{
			Name = "ClearBases",
			Def.Sprite{
				Name = "ClearBaseR",
				InitCommand = function(s)
					s:Load(cardPath .. "cleared.png")
					s:xy(54.9, 3)
				end,
			},
			Def.Sprite{
				Name = "ClearBaseL",
				InitCommand = function(s)
					s:Load(cardPath .. "cleared.png")
					s:xy(-60, 3):zoomx(-1)
				end,
			},
		},

		-- Clear lamp sprite (per-player, but we show P1 for simplicity in grid)
		Def.Sprite{
			Name = "ClearLamp",
			InitCommand = function(s) s:xy(-5, 3.4):zoomy(1.13):visible(false) end,
		},

		-- Title area
		Def.ActorFrame{
			Name = "TitleArea",
			InitCommand = function(s) s:xy(1, 67) end,

			-- Transliterated title (small, above main title)
			Def.BitmapText{
				Name = "TranslitTitle",
				Font = "_futura pt medium 30px",
				InitCommand = function(s)
					s:y(-10):zoom(0.35):maxwidth(440)
					s:strokecolor(color("0,0,0,0.5"))
					s:visible(false)
				end,
			},

			-- Main title
			Def.BitmapText{
				Name = "Title",
				Font = "_wheelnames 28px",
				InitCommand = function(s)
					s:zoom(0.6):maxwidth(260)
					s:strokecolor(color("0.15,0.15,0.0,0.9"))
				end,
			},
		},

		-- Difficulty hex background
		Def.ActorFrame{
			Name = "DiffArea",
			InitCommand = function(s) s:xy(-54, -16) end,  -- adjusted: lower and right

			Def.Sprite{
				Name = "DiffHex",
				InitCommand = function(s)
					local m = GetModel()
					s:Load(sharedPath .. m .. "hex.png")
					s:zoom(0.37)
				end,
			},

			-- Difficulty line overlay (colored by difficulty)
			Def.Sprite{
				Name = "DiffLine",
				InitCommand = function(s)
					s:Load(cardPath .. "line.png")
					s:zoom(0.37)
				end,
			},

			-- Difficulty number
			Def.BitmapText{
				Name = "DiffNum",
				Font = "_impact 32px",
				InitCommand = function(s)
					s:x(-1):zoom(0.8)
					s:diffuse(color("#FFFFFF")):strokecolor(color("#000000"))
				end,
			},
		},

		-- Flare badge
		Def.Sprite{
			Name = "FlareBadge",
			InitCommand = function(s) s:xy(-74, 38):zoom(0.4):visible(false) end,
		},

		-- Long/Marathon indicator
		Def.Sprite{
			Name = "LongIndicator",
			InitCommand = function(s)
				local m = GetModel()
				s:Load(sharedPath .. m .. "long.png")
				s:xy(-40, 36):zoom(0.3):visible(false)
			end,
		},

		-- Cursor arrows (only visible when focused)
		Def.Sprite{
			Name = "CursorL",
			InitCommand = function(s)
				local m = GetModel()
				s:Load(sharedPath .. m .. "cursor.png")
				s:x(-114):zoom(0.85):visible(false)
			end,
		},
		Def.Sprite{
			Name = "CursorR",
			InitCommand = function(s)
				local m = GetModel()
				s:Load(sharedPath .. m .. "cursor.png")
				s:x(114):zoom(0.85):rotationy(180):visible(false)
			end,
		},
	}
	return card
end

-- Factory: Create a group header actor
local function MakeGroupHeader(idx)
	local wheelItemPath = ThemeDir .. "Graphics/MusicWheelItem/"

	local header = Def.ActorFrame{
		Name = "Header"..idx,
		InitCommand = function(self)
			self:visible(false)
			self.poolIdx = idx
			self.flatIdx = nil
			self.isExpanded = false
		end,

		-- Background sprite (normal state)
		Def.Sprite{
			Name = "HeaderBG",
			InitCommand = function(s)
				local m = GetModel()
				s:Load(wheelItemPath .. m .. "normal.png")
				s:y(2):zoom(0.91)
			end,
		},

		-- Flash overlay (focused state)
		Def.Sprite{
			Name = "HeaderFlash",
			InitCommand = function(s)
				local m = GetModel()
				s:Load(wheelItemPath .. m .. "flash.png")
				s:y(2):zoomx(0.915):zoomy(0.76):visible(false)
				s:diffuseramp():effectcolor1(color("1,1,1,0.2")):effectcolor2(color("1,1,1,1")):effectperiod(0.5)
			end,
		},

		-- Group name text
		Def.BitmapText{
			Name = "GroupName",
			Font = "MusicWheelItem GroupNames",
			InitCommand = function(s)
				s:maxwidth(320)
				s:diffuse(Color.White)
			end,
		},

		-- Cursor arrows
		Def.Sprite{
			Name = "CursorL",
			InitCommand = function(s)
				local m = GetModel()
				s:Load(sharedPath .. m .. "cursor.png")
				s:x(-287):zoom(0.85):visible(false)
				s:bounce():effectmagnitude(12,0,0):effectperiod(0.8)
			end,
		},
		Def.Sprite{
			Name = "CursorR",
			InitCommand = function(s)
				local m = GetModel()
				s:Load(sharedPath .. m .. "cursor.png")
				s:x(287):zoom(0.85):rotationy(180):visible(false)
				s:bounce():effectmagnitude(-12,0,0):effectperiod(0.8)
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

	-- Golden League overlay
	local leagueOverlay = actor:GetChild("LeagueOverlay")
	if leagueOverlay then
		local songtit = song:GetDisplayMainTitle()
		if GoldenLeagueSong and GoldenLeagueSong[songtit] then
			local leaguePath = ThemeDir .. "Graphics/MusicWheelItem Song NormalPart/" .. GoldenLeagueSong[songtit] .. ".png"
			if FILEMAN:DoesFileExist(leaguePath) then
				leagueOverlay:Load(leaguePath)
				leagueOverlay:visible(true)
			else
				leagueOverlay:visible(false)
			end
		else
			leagueOverlay:visible(false)
		end
	end

	-- Title area
	local titleArea = actor:GetChild("TitleArea")
	local title = titleArea and titleArea:GetChild("Title")
	local translit = titleArea and titleArea:GetChild("TranslitTitle")

	if title then
		local displayTitle = GetSongName and GetSongName(song) or song:GetDisplayMainTitle()
		title:settext(displayTitle)
		if SongAttributes and SongAttributes.GetMenuColor then
			title:diffuse(SongAttributes.GetMenuColor(song))
		end
	end

	if translit then
		if GetTitleDisplayMode and GetTitleDisplayMode() == "Dual" and HasTranslitTitle and HasTranslitTitle(song) then
			translit:settext(GetTranslitTitle(song))
			translit:visible(true)
			if title then title:y(4) end
		else
			translit:visible(false)
			if title then title:y(0) end
		end
	end

	-- Highlights (focused state)
	local highlights = actor:GetChild("Highlights")
	if highlights then highlights:visible(isFocused) end

	-- Cursors (focused state)
	local cursorL = actor:GetChild("CursorL")
	local cursorR = actor:GetChild("CursorR")
	if cursorL then
		cursorL:visible(isFocused)
		if isFocused then
			cursorL:stoptweening():bounce():effectmagnitude(12,0,0):effectperiod(1)
		end
	end
	if cursorR then
		cursorR:visible(isFocused)
		if isFocused then
			cursorR:stoptweening():bounce():effectmagnitude(-12,0,0):effectperiod(1)
		end
	end

	-- "NEW" badge
	local newBadge = actor:GetChild("NewBadge")
	if newBadge then
		newBadge:visible(PROFILEMAN:IsSongNew(song))
	end

	-- Long/Marathon indicator
	local longInd = actor:GetChild("LongIndicator")
	if longInd then
		longInd:visible(song:IsLong() or song:IsMarathon())
	end

	-- Get current steps for difficulty display
	local pn = GAMESTATE:GetMasterPlayerNumber()
	local st = GAMESTATE:GetCurrentStyle() and GAMESTATE:GetCurrentStyle():GetStepsType()
	local steps = #entry > 1 and entry[2] or nil  -- First steps in entry

	-- Difficulty display
	local diffArea = actor:GetChild("DiffArea")
	local diffLine = diffArea and diffArea:GetChild("DiffLine")
	local diffNum = diffArea and diffArea:GetChild("DiffNum")
	if steps then
		if diffNum then
			diffNum:settext(steps:GetMeter())
			diffNum:visible(true)
		end
		if diffLine then
			diffLine:diffuse(CustomDifficultyToColor(steps:GetDifficulty()))
			diffLine:visible(true)
		end
		if diffArea then diffArea:visible(true) end
	else
		if diffArea then diffArea:visible(false) end
	end

	-- Clear lamp and flare badge
	local clearLamp = actor:GetChild("ClearLamp")
	local flareBadge = actor:GetChild("FlareBadge")

	-- Reset visibility
	if clearLamp then clearLamp:visible(false) end
	if flareBadge then flareBadge:visible(false) end

	-- Only show for valid steps
	if steps then
		local lampType = nil
		local flareGauge = nil

		-- Try ChartResults first (includes Flare data)
		if GetChartResultBySong then
			local chartResult = GetChartResultBySong(pn, song, steps)
			if chartResult then
				lampType = chartResult.lamp
				flareGauge = chartResult.flareGauge
			end
		end

		-- Fall back to high scores if no ChartResult
		if not lampType then
			local profile
			if PROFILEMAN:IsPersistentProfile(pn) then
				profile = PROFILEMAN:GetProfile(pn)
			else
				profile = PROFILEMAN:GetMachineProfile()
			end
			if profile then
				local scorelist = profile:GetHighScoreList(song, steps)
				if scorelist then
					local scores = scorelist:GetHighScores()
					if scores and scores[1] then
						lampType = GetLampFromHighScore(scores[1])
					end
				end
			end
		end

		-- Load lamp texture
		if clearLamp and lampType then
			local lampTex = GetLampTexture(lampType)
			if lampTex and FILEMAN:DoesFileExist(lampTex) then
				clearLamp:Load(lampTex)
				clearLamp:visible(true)
				-- Add shimmer effect for FC lamps
				if lampType == "MFC" or lampType == "PFC" or lampType == "GFC" or lampType == "FC" then
					clearLamp:diffuseshift():effectcolor1(color("1,1,1,1")):effectcolor2(color("1,1,1,0.75")):effectperiod(0.1)
				else
					clearLamp:diffuseshift():effectcolor1(color("1,1,1,1")):effectcolor2(color("1,1,1,1")):effectperiod(1.1)
				end
			end
		end

		-- Load flare badge
		if flareBadge and flareGauge then
			local flareTex = GetFlareBadgeTexture(flareGauge)
			if flareTex then
				flareBadge:Load(flareTex)
				flareBadge:visible(true)
			end
		end
	end
end

-- Update a group header with data
local function UpdateGroupHeader(actor, groupName, isExpanded, isFocused)
	if not groupName or type(groupName) ~= "string" then
		actor:visible(false)
		return
	end

	actor:visible(true)
	actor.isExpanded = isExpanded

	local wheelItemPath = ThemeDir .. "Graphics/MusicWheelItem/"
	local m = GetModel()

	-- Background sprite - switch based on expanded state
	local bg = actor:GetChild("HeaderBG")
	if bg then
		local bgTex = isExpanded and (m .. "selected.png") or (m .. "normal.png")
		bg:Load(wheelItemPath .. bgTex)
	end

	-- Flash overlay - visible when focused
	local flash = actor:GetChild("HeaderFlash")
	if flash then
		flash:visible(isFocused)
	end

	-- Group name text
	local nameText = actor:GetChild("GroupName")
	if nameText then
		-- Format group name (strip leading numbers for Group sort, etc.)
		local displayName = groupName
		if SongAttributes and SongAttributes.GetGroupName then
			displayName = SongAttributes.GetGroupName(groupName)
		end
		if GAMESTATE:GetSortOrder() == "SortOrder_Group" then
			displayName = string.gsub(displayName, "^%d%d? ?%- ?", "")
		elseif GAMESTATE:GetSortOrder() == "SortOrder_TopGrades" then
			displayName = string.gsub(displayName, "AAAA", "AAA+")
		end
		nameText:settext(displayName)
		-- Text color: black on selected (expanded), white otherwise
		if isExpanded then
			nameText:diffuse(Color.Black)
		else
			nameText:diffuse(Color.White)
		end
	end

	-- Cursor arrows - visible when focused
	local cursorL = actor:GetChild("CursorL")
	local cursorR = actor:GetChild("CursorR")
	if cursorL then cursorL:visible(isFocused) end
	if cursorR then cursorR:visible(isFocused) end
end

-- ============================================================================
-- DIFFICULTY PICKER (Stage 6)
-- ============================================================================

local DIFF_ROW_H = 50
local DIFF_W = 340
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

local TwoPartConfirmed = {
	[PLAYER_1] = false,
	[PLAYER_2] = false,
}
local TwoPartActive = false

local function ConfirmSong()
	if Accepted or not IsSong(Cursor) then return end
	local entry = FlatList[Cursor]
	local song = entry[1]

	local stepsArray = {}
	for i = 2, #entry do
		stepsArray[#stepsArray + 1] = entry[i]
	end
	if #stepsArray == 0 then return end

	if #stepsArray == 1 then
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
		TwoPartActive = true
		TwoPartConfirmed[PLAYER_1] = false
		TwoPartConfirmed[PLAYER_2] = false
		MESSAGEMAN:Broadcast("StartSelectingSteps")
	end
end

local function OnTwoPartConfirm(pn)
	if not TwoPartActive then return end
	TwoPartConfirmed[pn] = true

	local allConfirmed = true
	for _, p in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if not TwoPartConfirmed[p] then
			allConfirmed = false
			break
		end
	end

	if allConfirmed and not Accepted then
		SaveCursorState()
		StopPreview()
		GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
		Accepted = true
		TwoPartActive = false
	end
end

local function OnSongUnchosen()
	TwoPartActive = false
	TwoPartConfirmed[PLAYER_1] = false
	TwoPartConfirmed[PLAYER_2] = false
end

-- Factory: Create difficulty picker for a player (fallback, TwoPartDiff is primary)
local function MakeDiffPicker(pn)
	local isVersus = GAMESTATE:GetNumPlayersEnabled() > 1
	local boxX
	if isVersus then
		boxX = (pn == PLAYER_1) and (SCREEN_CENTER_X - DIFF_W/2 - 40)
		                           or (SCREEN_CENTER_X + DIFF_W/2 + 40)
	else
		boxX = SCREEN_CENTER_X
	end

	local m = Def.ActorFrame{
		Name = "DiffPicker_"..ToEnumShortString(pn),
		InitCommand = function(self)
			DiffFrame[pn] = self
			self:visible(false)
		end,
		RefreshDiffCommand = function(self)
			local n = #DiffSteps
			local totalH = n * DIFF_ROW_H + 70
			local topY = SCREEN_CENTER_Y - totalH/2

			local panelTop = self:GetChild("PanelTop")
			local panelMid = self:GetChild("PanelMid")
			local panelBot = self:GetChild("PanelBot")
			if panelTop then panelTop:y(topY) end
			if panelMid then panelMid:y(topY + 20):zoomto(DIFF_W * 0.78, totalH - 20) end
			if panelBot then panelBot:y(topY + totalH) end

			local title = self:GetChild("DiffTitle")
			if title and DiffSong then
				title:y(topY + 28):settext(DiffSong:GetDisplayMainTitle())
			end

			local selIdx = DiffPickIdx[pn] or 1

			for i = 1, MAX_DIFFS do
				local rowBG = self:GetChild("DiffRowBG"..i)
				local label = self:GetChild("DiffLabel"..i)
				local meter = self:GetChild("DiffMeter"..i)
				local arrow = self:GetChild("DiffArrow"..i)
				if i <= n then
					local st = DiffSteps[i]
					local dc = GetDiffColor(st)
					local rowY = topY + 52 + (i - 1) * DIFF_ROW_H + DIFF_ROW_H/2
					local sel = (i == selIdx)
					if rowBG then
						rowBG:visible(true):y(rowY)
						rowBG:diffuse(sel and color("#FFD700") or color("#00000000"))
						rowBG:diffusealpha(sel and 0.3 or 0)
					end
					if arrow then
						arrow:visible(sel):y(rowY)
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
					if arrow then arrow:visible(false) end
					if label then label:visible(false) end
					if meter then meter:visible(false) end
				end
			end
		end,

		-- Panel graphics
		Def.Sprite{
			Name = "PanelTop",
			InitCommand = function(self)
				self:Load(sharedPath .. Model() .. "infotop.png")
				self:x(boxX):valign(0):zoom(0.7)
			end,
		},
		Def.Sprite{
			Name = "PanelMid",
			InitCommand = function(self)
				self:Load(sharedPath .. "infomiddle.png")
				self:x(boxX):valign(0)
			end,
		},
		Def.Sprite{
			Name = "PanelBot",
			InitCommand = function(self)
				self:Load(sharedPath .. Model() .. "infobottom.png")
				self:x(boxX):valign(1):zoom(0.7)
			end,
		},
		-- Title
		Def.BitmapText{
			Font = "_avenirnext lt pro bold Bold 20px",
			Name = "DiffTitle",
			InitCommand = function(self)
				self:x(boxX):zoom(0.6)
				self:diffuse(Color.White)
				self:maxwidth(DIFF_W - 40)
				self:strokecolor(color("0,0,0,0.8"))
			end,
		},
	}

	for i = 1, MAX_DIFFS do
		m[#m+1] = Def.Quad{
			Name = "DiffRowBG"..i,
			InitCommand = function(self)
				self:x(boxX):zoomto(DIFF_W * 0.7, DIFF_ROW_H - 6):visible(false)
			end,
		}
		m[#m+1] = Def.Sprite{
			Name = "DiffArrow"..i,
			InitCommand = function(self)
				self:Load(sharedPath .. Model() .. "cursor.png")
				self:x(boxX - DIFF_W/2 + 30):zoom(0.25):visible(false)
			end,
		}
		m[#m+1] = Def.BitmapText{
			Font = "_avenirnext lt pro bold Bold 20px",
			Name = "DiffLabel"..i,
			InitCommand = function(self)
				self:x(boxX - DIFF_W/2 + 55):zoom(0.5)
				self:visible(false):halign(0)
				self:strokecolor(color("0,0,0,0.8"))
			end,
		}
		m[#m+1] = Def.BitmapText{
			Font = "_impact 32px",
			Name = "DiffMeter"..i,
			InitCommand = function(self)
				self:x(boxX + DIFF_W/2 - 35):zoom(0.7)
				self:visible(false):halign(1)
				self:strokecolor(color("0,0,0,0.8"))
			end,
		}
	end

	return m
end

-- ============================================================================
-- SIDE MENU (Stage 7)
-- ============================================================================

local MENU_W = 320
local MENU_ROW_H = 32
local MENU_PAD = 8

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
	local totalH = MENU_PAD + 36 + NUM_MENU_ROWS * MENU_ROW_H + MENU_PAD
	local topY = SCREEN_CENTER_Y - totalH/2
	local centerY = topY + totalH/2
	-- Position further from center (was 20, now 60)
	local menuX = (pn == PLAYER_1) and (MENU_W/2 + 60) or (SCREEN_WIDTH - MENU_W/2 - 60)

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
				local arrow = self:GetChild("Arrow"..i)
				if rowBG then
					local isSel = (i == MenuRow[pn])
					rowBG:diffuse(isSel and color("#FFD700") or color("#00000000"))
					rowBG:diffusealpha(isSel and 0.3 or 0)
				end
				if label then
					label:settext(row and row.name or MENU_ROW_NAMES[i])
					label:diffuse(i == MenuRow[pn] and color("#FFD700") or color("#CCCCCC"))
				end
				if value then
					local ch = row and row.choices[row.selected]
					value:settext(ch and ch.label or "")
					value:diffuse(i == MenuRow[pn] and Color.White or color("#AAAAAA"))
				end
				if arrow then
					arrow:visible(i == MenuRow[pn])
				end
			end
		end,

		-- Panel top
		Def.Sprite{
			InitCommand = function(self)
				self:Load(sharedPath .. Model() .. "infotop.png")
				self:xy(menuX, topY):valign(0):zoom(0.75)
			end,
		},
		-- Panel middle (stretched)
		Def.Sprite{
			InitCommand = function(self)
				self:Load(sharedPath .. "infomiddle.png")
				self:xy(menuX, topY + 20):valign(0)
				self:zoomto(MENU_W * 0.78, totalH - 20)
			end,
		},
		-- Panel bottom
		Def.Sprite{
			InitCommand = function(self)
				self:Load(sharedPath .. Model() .. "infobottom.png")
				self:xy(menuX, topY + totalH):valign(1):zoom(0.75)
			end,
		},
		-- Player indicator
		Def.Sprite{
			InitCommand = function(self)
				self:Load(sharedPath .. Model() .. "player.png")
				self:xy(menuX, topY + 18):zoom(0.6)
			end,
		},
		-- Title
		Def.BitmapText{
			Font = "_avenirnext lt pro bold Bold 20px",
			Text = "OPTIONS",
			InitCommand = function(self)
				self:xy(menuX, topY + MENU_PAD + 28)
				self:zoom(0.7):diffuse(Color.White)
				self:strokecolor(color("0,0,0,0.8"))
			end,
		},
	}

	-- Option rows
	for i = 1, NUM_MENU_ROWS do
		local rowY = topY + MENU_PAD + 44 + (i - 1) * MENU_ROW_H + MENU_ROW_H/2

		-- Selection highlight
		m[#m+1] = Def.Quad{
			Name = "RowBG"..i,
			InitCommand = function(self)
				self:xy(menuX, rowY)
				self:zoomto(MENU_W * 0.72, MENU_ROW_H - 2)
				self:diffuse(color("#00000000"))
			end,
		}
		-- Selection arrow (cursor indicator)
		m[#m+1] = Def.Sprite{
			Name = "Arrow"..i,
			InitCommand = function(self)
				self:Load(sharedPath .. Model() .. "cursor.png")
				self:xy(menuX - MENU_W/2 + 30, rowY)
				self:zoom(0.3):visible(false)
			end,
		}
		-- Row label
		m[#m+1] = Def.BitmapText{
			Font = "_avenirnext lt pro bold Bold 20px",
			Name = "Label"..i,
			InitCommand = function(self)
				self:xy(menuX - MENU_W/2 + 50, rowY)
				self:zoom(0.5):halign(0)
				self:diffuse(color("#CCCCCC"))
				self:strokecolor(color("0,0,0,0.6"))
			end,
		}
		-- Row value
		m[#m+1] = Def.BitmapText{
			Font = "_avenirnext lt pro bold Bold 20px",
			Name = "Value"..i,
			InitCommand = function(self)
				self:xy(menuX + MENU_W/2 - 30, rowY)
				self:zoom(0.5):halign(1)
				self:diffuse(color("#AAAAAA"))
				self:strokecolor(color("0,0,0,0.6"))
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
-- LAYOUT & SCROLL (Stage 4) - Ported from GALAXY
-- ============================================================================

-- Layout constants (in pool coordinates, before 0.4 zoom)
local CARD_H = 285            -- Song card height (for center-to-center calc)
local HEADER_H = 66           -- Header height
local ROW_GAP = 18            -- Gap between rows
local CARD_SCALE_FOCUS = 2.0  -- Focused song card zoom
local CARD_SCALE_NORMAL = 1.7 -- Normal song card zoom
local HEADER_SCALE_FOCUS = 2.2  -- Focused header zoom
local HEADER_SCALE_NORMAL = 1.8 -- Normal header zoom
local CENTER_Y = 0            -- Y position of cursor item (relative to PoolRoot)
local COL_WIDTH = 340         -- X spacing between columns
local X_STAGGER_PER_Y = 0.27  -- X shift per Y unit (diagonal stagger)

-- How far above/below center we render (in pool coordinates)
-- This determines how many rows are visible
local RENDER_MARGIN = 1400    -- ~7 song rows each direction (7 * ~200 = 1400)

-- Scroll state
local VisualOffset = 0        -- Current pixel offset during animation
local ScrollVelocity = 0      -- For animation continuity

-- Center-to-center distance between two vertically adjacent items
-- Based on item types (group=header, song=card)
local function CenterAdvance(typeA, typeB)
	local hA = (typeA == "group") and HEADER_H or CARD_H
	local hB = (typeB == "group") and HEADER_H or CARD_H
	return hA / 2 + ROW_GAP + hB / 2
end

-- Get the column (1, 2, 3) for a song by counting back to nearest group header
-- This works with wrapped indices for proper looping
local function GetSongColLocal(idx)
	local count = 0
	local i = idx
	local n = #FlatList
	while i >= 1 and IsSong(Wrap(i)) do
		count = count + 1
		i = i - 1
		if count > n then break end  -- safety: avoid infinite loop
	end
	return ((count - 1) % COLS) + 1
end

-- Compute visible items by walking forward/backward from cursor
-- Returns array of { flatIdx, y, type, col } entries
-- y is relative to cursor (cursor is at y=0)
local function ComputeVisibleItems(renderMargin)
	renderMargin = renderMargin or RENDER_MARGIN
	local n = #FlatList
	if n == 0 then return {} end

	local result = {}

	-- Find the start of cursor's row (for songs, walk back to col 1)
	local rowStart = Cursor
	if IsSong(Cursor) then
		while true do
			local prevWi = Wrap(rowStart - 1)
			if not IsSong(prevWi) then break end
			if GetSongColLocal(prevWi) >= GetSongColLocal(Wrap(rowStart)) then break end
			if rowStart - 1 == Cursor - n then break end
			rowStart = rowStart - 1
		end
	end

	-- Walk FORWARD from row start
	local y = 0
	local visited = 0
	local idx = rowStart
	while y < renderMargin and visited < n do
		local wi = Wrap(idx)
		if IsGroup(wi) then
			result[#result+1] = { flatIdx = wi, y = y, type = "group", col = 0 }
			local nextType = IsSong(Wrap(idx + 1)) and "song" or "group"
			y = y + CenterAdvance("group", nextType)
		else
			local col = GetSongColLocal(wi)
			result[#result+1] = { flatIdx = wi, y = y, type = "song", col = col }
			local nextWi = Wrap(idx + 1)
			if col == COLS or not IsSong(nextWi) then
				local nextType = IsSong(nextWi) and "song" or "group"
				y = y + CenterAdvance("song", nextType)
			end
		end
		visited = visited + 1
		idx = idx + 1
	end

	-- Walk BACKWARD from row start
	local lastBelowType = IsGroup(Wrap(rowStart)) and "group" or "song"
	y = 0
	visited = 0
	idx = rowStart - 1
	local pendingRow = {}

	local function FlushPending()
		if #pendingRow == 0 then return end
		y = y - CenterAdvance("song", lastBelowType)
		for _, p in ipairs(pendingRow) do
			result[#result+1] = { flatIdx = p.fi, y = y, type = "song", col = p.col }
		end
		pendingRow = {}
		lastBelowType = "song"
	end

	while (-y) < renderMargin and visited < n do
		local wi = Wrap(idx)
		if IsGroup(wi) then
			FlushPending()
			y = y - CenterAdvance("group", lastBelowType)
			result[#result+1] = { flatIdx = wi, y = y, type = "group", col = 0 }
			lastBelowType = "group"
		else
			local col = GetSongColLocal(wi)
			pendingRow[#pendingRow+1] = { fi = wi, col = col }
			if col == 1 then
				FlushPending()
			end
		end
		visited = visited + 1
		idx = idx - 1
	end
	FlushPending()

	return result
end

-- Stub for compatibility (no longer needed with dynamic layout)
RebuildLayoutCache = function() end

-- Cubic Hermite interpolation for smooth scrolling
local function CubicHermite(t, p0, p1, m0, m1)
	local t2 = t * t
	local t3 = t2 * t
	return (2*t3 - 3*t2 + 1) * p0 + (t3 - 2*t2 + t) * m0 + (-2*t3 + 3*t2) * p1 + (t3 - t2) * m1
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

	-- ComputeVisibleItems returns { flatIdx, y, type, col } where y is relative to cursor
	local items = ComputeVisibleItems(RENDER_MARGIN + math.abs(VisualOffset))

	local cardIdx = 1
	local headerIdx = 1

	for _, item in ipairs(items) do
		local flatIdx = item.flatIdx
		local y = item.y + VisualOffset  -- Apply scroll animation offset
		local col = item.col
		local itemType = item.type
		local entry = FlatList[flatIdx]

		-- Screen Y = center + relative Y
		local screenY = CENTER_Y + y

		-- Horizontal stagger based on Y distance
		local xStagger = y * X_STAGGER_PER_Y

		-- Determine if this item is focused
		local isFocused = (flatIdx == Cursor)

		-- Fade items near edges
		local alpha = 1.0
		local yDist = math.abs(y)
		local fadeStart = RENDER_MARGIN - 300
		if yDist > fadeStart then
			alpha = math.max(0, 1 - (yDist - fadeStart) / 300)
		end

		-- Z-depth for proper layering (focused items on top)
		local zDepth = 1 - yDist / RENDER_MARGIN

		if itemType == "group" then
			-- Header: centered with stagger
			local x = 0 + xStagger
			local headerScale = isFocused and HEADER_SCALE_FOCUS or HEADER_SCALE_NORMAL
			if headerIdx <= POOL_HEADERS then
				local header = HeaderPool[headerIdx]
				if header then
					header:xy(x, screenY)
					header:z(zDepth)
					header:zoom(headerScale)
					header:diffusealpha(alpha)
					UpdateGroupHeader(header, entry, entry == OpenGroup, isFocused)
					headerIdx = headerIdx + 1
				end
			end
		else
			-- Song card: 3 columns (col is 1, 2, or 3)
			-- Convert to offset: col 1 = -1, col 2 = 0, col 3 = +1
			local x = (col - 2) * COL_WIDTH + xStagger
			local cardScale = isFocused and CARD_SCALE_FOCUS or CARD_SCALE_NORMAL
			if cardIdx <= POOL_CARDS then
				local card = CardPool[cardIdx]
				if card then
					card:xy(x, screenY)
					card:z(zDepth)
					card:zoom(cardScale)
					card:diffusealpha(alpha)
					UpdateSongCard(card, entry, isFocused)
					CardAssign[cardIdx] = flatIdx
					CardByFlat[flatIdx] = cardIdx
					cardIdx = cardIdx + 1
				end
			end
		end
	end
end

-- ===== SCROLL ANIMATION (ported from GALAXY) =====
-- Cubic Hermite: f(s) from startOffset to 0, f'(1)=0.
-- f(s) = As³ + Bs² + Cs + D,  s ∈ [0, 1]

local AnimActive = false
local AnimTime = 0
local AnimA, AnimB, AnimC, AnimD = 0, 0, 0, 0

local function EvalCubic(s)
	return AnimA*s*s*s + AnimB*s*s + AnimC*s + AnimD
end

local function GetCurrentAnimVelNorm()
	if not AnimActive then return 0 end
	local s = math.min(AnimTime / ANIM_DUR, 1)
	return 3*AnimA*s*s + 2*AnimB*s + AnimC
end

local function StartScrollAnim(startOffset, velNorm)
	local P = startOffset
	local V = velNorm
	AnimA = V + 2*P
	AnimB = -2*V - 3*P
	AnimC = V
	AnimD = P
	AnimTime = 0
	AnimActive = true
	VisualOffset = P
end

local function ResetAnim()
	VisualOffset = 0
	AnimActive = false
end

-- Update scroll animation (called each frame)
local function UpdateScroll(self)
	local dt = self:GetEffectDelta()
	AccumulatedTime = AccumulatedTime + dt

	if not AnimActive then return end

	AnimTime = AnimTime + dt
	local s = AnimTime / ANIM_DUR

	if s >= 1 then
		VisualOffset = 0
		AnimActive = false
	else
		VisualOffset = EvalCubic(s)
	end

	Refresh()
end

-- ============================================================================
-- NAVIGATION (Stage 4/5) - Ported from GALAXY
-- ============================================================================

-- Calculate the scroll offset needed when moving from one cursor to another
local function CalcScrollOffset(oldCursor, newCursor)
	if oldCursor == newCursor then return 0 end

	local n = #FlatList
	local fwdDist, bwdDist = 0, 0

	-- Walk forward from old to new
	local idx = oldCursor
	local y = 0
	local lastType = IsGroup(oldCursor) and "group" or "song"
	while idx ~= newCursor do
		local nextIdx = Wrap(idx + 1)
		local nextType = IsGroup(nextIdx) and "group" or "song"
		-- Only advance Y when we finish a row
		if lastType == "group" or (IsSong(idx) and (GetSongColLocal(idx) == COLS or not IsSong(nextIdx))) then
			y = y + CenterAdvance(lastType, nextType)
		end
		if IsSong(nextIdx) then lastType = "song" else lastType = "group" end
		idx = nextIdx
		fwdDist = y
		if idx == oldCursor then break end  -- wrapped around
	end

	-- Walk backward from old to new
	idx = oldCursor
	y = 0
	lastType = IsGroup(oldCursor) and "group" or "song"
	while idx ~= newCursor do
		local prevIdx = Wrap(idx - 1)
		local prevType = IsGroup(prevIdx) and "group" or "song"
		if lastType == "group" or (IsSong(idx) and GetSongColLocal(idx) == 1) then
			y = y + CenterAdvance(prevType, lastType)
		end
		if IsSong(prevIdx) then lastType = "song" else lastType = "group" end
		idx = prevIdx
		bwdDist = y
		if idx == oldCursor then break end
	end

	-- Return the shorter distance (positive for forward/down, negative for backward/up)
	if fwdDist <= bwdDist then
		return fwdDist   -- moved forward/down, content scrolls up
	else
		return -bwdDist  -- moved backward/up, content scrolls down
	end
end

-- Move cursor by a number of items (for left/right within a row)
local function MoveCursorByItems(delta)
	local oldCursor = Cursor
	Cursor = Wrap(Cursor + delta)

	-- Calculate and animate scroll offset
	local offset = CalcScrollOffset(oldCursor, Cursor)
	if offset ~= 0 then
		local vel = GetCurrentAnimVelNorm()
		StartScrollAnim(offset, vel)
	end

	Refresh()
	MESSAGEMAN:Broadcast("CursorChanged")
end

-- Move cursor to a different row (for up/down navigation)
local function MoveCursorByRows(rowDelta)
	local oldCursor = Cursor
	local currentCol = IsSong(Cursor) and GetSongColLocal(Cursor) or 0
	local isHeader = IsGroup(Cursor)
	local n = #FlatList

	-- Find the next row in the given direction
	local searchDir = rowDelta > 0 and 1 or -1
	local idx = Cursor
	local foundNewRow = false

	-- Skip to the next row
	local visited = 0
	while visited < n do
		idx = Wrap(idx + searchDir)
		visited = visited + 1

		-- Check if we've reached a new row
		if IsGroup(idx) then
			-- Headers are always their own row
			foundNewRow = true
			break
		else
			local col = GetSongColLocal(idx)
			if searchDir > 0 then
				-- Moving down: new row starts at col 1
				if col == 1 then foundNewRow = true; break end
			else
				-- Moving up: new row ends at col COLS (or last song before header)
				local nextIdx = Wrap(idx + 1)
				if col == COLS or IsGroup(nextIdx) then foundNewRow = true; break end
			end
		end
	end

	if not foundNewRow then return end

	-- Now find the best item in this row (prefer same column)
	local rowStart = idx
	local bestIdx = idx

	if IsSong(idx) and currentCol > 0 then
		-- Find the item with matching or closest column
		local bestColDiff = math.abs(GetSongColLocal(idx) - currentCol)

		-- Check other items in same row
		local checkIdx = idx
		while true do
			local nextIdx = Wrap(checkIdx + searchDir)
			if IsGroup(nextIdx) then break end
			local nextCol = GetSongColLocal(nextIdx)

			-- Check if still in same row
			if searchDir > 0 then
				if nextCol <= GetSongColLocal(checkIdx) then break end
			else
				if nextCol >= GetSongColLocal(checkIdx) then break end
			end

			local colDiff = math.abs(nextCol - currentCol)
			if colDiff < bestColDiff then
				bestColDiff = colDiff
				bestIdx = nextIdx
			end
			checkIdx = nextIdx
		end
	end

	Cursor = bestIdx

	-- Calculate and animate scroll offset
	local offset = CalcScrollOffset(oldCursor, Cursor)
	if offset ~= 0 then
		local vel = GetCurrentAnimVelNorm()
		StartScrollAnim(offset, vel)
	end

	Refresh()
	MESSAGEMAN:Broadcast("CursorChanged")
end

-- ============================================================================
-- INPUT HANDLER
-- ============================================================================

local function InputHandler(event)
	local button = event.GameButton
	if not button then return false end

	-- Track button held state
	if event.type == "InputEventType_Release" then
		ButtonHeld[button] = false
		return false
	end
	ButtonHeld[button] = true

	if Accepted then return true end

	local pn = event.PlayerNumber
	if not pn then return false end

	-- Check for simultaneous Up+Down press (jump to folder header)
	if (button == "MenuUp" or button == "MenuDown") and
	   ButtonHeld["MenuUp"] and ButtonHeld["MenuDown"] then
		JumpToFolderHeader()
		return true
	end

	-- When TwoPartDiff is active, let it handle input (except Back to cancel)
	if TwoPartActive then
		if button == "Back" then
			-- Cancel TwoPartDiff selection
			MESSAGEMAN:Broadcast("SongUnchosen")
			SOUND:PlayOnce(THEME:GetPathS("Common", "cancel"))
			return true
		end
		-- Let TwoPartDiff's own input handler process other buttons
		return false
	end

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
		MoveCursorByItems(1)
		SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
		return true
	elseif button == "MenuLeft" then
		MoveCursorByItems(-1)
		SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
		return true
	elseif button == "MenuDown" then
		MoveCursorByRows(1)
		SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
		return true
	elseif button == "MenuUp" then
		MoveCursorByRows(-1)
		SOUND:PlayOnce(THEME:GetPathS("MusicWheel", "change"))
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
		RebuildLayoutCache()

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

	-- TwoPartDiff confirmation messages
	OKPlayerNumber_P1MessageCommand = function(self)
		OnTwoPartConfirm(PLAYER_1)
		-- Check if we should transition
		if Accepted then
			self:sleep(1.5):queuecommand("DoTransition")
		end
	end,
	OKPlayerNumber_P2MessageCommand = function(self)
		OnTwoPartConfirm(PLAYER_2)
		-- Check if we should transition
		if Accepted then
			self:sleep(1.5):queuecommand("DoTransition")
		end
	end,
	DoTransitionCommand = function(self)
		if Accepted then
			SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
		end
	end,
	SongUnchosenMessageCommand = function(self)
		OnSongUnchosen()
	end,

	CursorChangedMessageCommand = function(self)
		Refresh()

		-- Set GAMESTATE current song/steps so original overlay components receive messages
		local item = FlatList[Cursor]
		if IsSong(Cursor) then
			local song = item[1]
			GAMESTATE:SetCurrentSong(song)
			-- Set steps for each player (prefer their last difficulty, or first available)
			local st = GAMESTATE:GetCurrentStyle():GetStepsType()
			for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
				local pref = GAMESTATE:GetPreferredDifficulty(pn)
				local steps = nil
				if pref then
					steps = song:GetOneSteps(st, pref)
				end
				if not steps then
					local allSteps = song:GetStepsByStepsType(st)
					if #allSteps > 0 then steps = allSteps[1] end
				end
				if steps then
					GAMESTATE:SetCurrentSteps(pn, steps)
				end
			end
		else
			GAMESTATE:SetCurrentSong(nil)
		end

		-- Start song preview
		StartPreview()
	end,
}

-- ============================================================================
-- OVERLAY COMPONENTS (from ScreenSelectMusic)
-- ============================================================================

-- Pool root container (centered on screen)
-- Matches original MusicWheel positioning and zoom from ScreenSelectMusic metrics
local poolRoot = Def.ActorFrame{
	Name = "PoolRoot",
	InitCommand = function(s)
		s:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y + 25)
		s:zoom(0.4)  -- Original MusicWheelOnCommand has zoom,0.4
		s:SetDrawByZPosition(true)
		s:fov(60)
	end,
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

-- ============================================================================
-- SONG INFO PANEL (top center - jacket, title, artist, BPM)
-- ============================================================================
t[#t + 1] = loadfile(THEME:GetPathB("ScreenSelectMusic", "overlay/Info"))() .. {
	OnCommand = function(s)
		s:zoom(0.667):y(57)
		s:diffusealpha(0):sleep(0.4):linear(0.05):diffusealpha(0.75)
		s:linear(0.1):diffusealpha(0.25):linear(0.1):diffusealpha(1)
	end,
}

-- ============================================================================
-- STAGE DISPLAY (top left - 1st, 2nd, Final, etc.)
-- ============================================================================
t[#t + 1] = loadfile(THEME:GetPathB("ScreenSelectMusic", "overlay/StageDisplay"))() .. {
	OnCommand = function(s)
		s:zoom(0.667)
		s:diffusealpha(0):sleep(0.4):linear(0.05):diffusealpha(0.75)
		s:linear(0.1):diffusealpha(0.25):linear(0.1):diffusealpha(1)
	end,
}

-- ============================================================================
-- PER-PLAYER COMPONENTS (Difficulty panel, Radar, Target Score, Shock Arrows)
-- ============================================================================
for _, pn in pairs(GAMESTATE:GetEnabledPlayers()) do
	-- Difficulty Panel (left side for P1, right side for P2)
	-- Adjusted: lower and slightly inward
	t[#t + 1] = loadfile(THEME:GetPathB("ScreenSelectMusic", "overlay/Difficulty"))(pn) .. {
		InitCommand = function(s)
			s:xy(pn == PLAYER_1 and SCREEN_LEFT + 100 or SCREEN_RIGHT - 100, _screen.cy - 90)
			s:zoom(0.667)
		end,
	}

	-- Groove Radar (adjusted: lower and slightly inward)
	t[#t + 1] = loadfile(THEME:GetPathB("ScreenSelectMusic", "overlay/RadarHandler/default.lua"))(pn) .. {
		InitCommand = function(s)
			s:xy(pn == PLAYER_1 and SCREEN_LEFT + 92 or SCREEN_RIGHT - 92, _screen.cy + 30)
			s:zoom(0.667)
		end,
	}

	-- Target Score Panel (uses its own positioning from default.lua)
	t[#t + 1] = loadfile(THEME:GetPathB("ScreenSelectMusic", "overlay/TargetScore/default.lua"))(pn)

	-- Shock Arrows Indicator (aligned with radar)
	t[#t + 1] = loadfile(THEME:GetPathB("ScreenSelectMusic", "overlay/ShockArrows/default.lua"))(pn) .. {
		InitCommand = function(s)
			s:xy(pn == PLAYER_1 and SCREEN_LEFT + 92 or SCREEN_RIGHT - 92, _screen.cy + 42)
			s:zoom(0.667)
		end,
	}
end

-- ============================================================================
-- TWO-PART DIFFICULTY PICKER (shown when confirming song)
-- ============================================================================
local TwoPartDiffContainer = Def.ActorFrame{
	Name = "TwoPartDiffContainer",
	StartSelectingStepsMessageCommand = function(s)
		s:RemoveAllChildren()
		s:AddChildFromPath(THEME:GetPathB("ScreenSelectMusic", "overlay/TwoPartDiff"))
	end,
	SongUnchosenMessageCommand = function(s)
		s:sleep(0.2):queuecommand("Remove")
	end,
	RemoveCommand = function(s)
		s:RemoveAllChildren()
	end,
}
t[#t + 1] = TwoPartDiffContainer

-- ============================================================================
-- FOOTER (bottom - "SELECT MUSIC" text)
-- ============================================================================
t[#t + 1] = Def.ActorFrame{
	Name = "Footer",
	InitCommand = function(s)
		s:xy(SCREEN_CENTER_X, SCREEN_BOTTOM - 22)
	end,
	OnCommand = function(s)
		s:diffusealpha(0):sleep(0.4):linear(0.05):diffusealpha(0.75)
		s:linear(0.1):diffusealpha(0.25):linear(0.1):diffusealpha(1)
	end,

	-- Footer base
	Def.Sprite{
		InitCommand = function(s)
			s:Load(footerPath .. Model() .. "base.png")
			s:zoom(0.667):y(11)
		end,
	},

	-- Footer text (SELECT MUSIC)
	Def.Sprite{
		InitCommand = function(s)
			s:Load(footerPath .. Model() .. Language() .. "selmus.png")
			s:zoom(0.667):xy(0.5, 12)
		end,
	},
}

-- ============================================================================
-- OUR CUSTOM COMPONENTS (kept for functionality)
-- ============================================================================

-- Difficulty pickers (our simple version, hidden by default - TwoPartDiff is primary)
t[#t + 1] = MakeDiffPicker(PLAYER_1)
t[#t + 1] = MakeDiffPicker(PLAYER_2)

-- Side menus (one per player)
t[#t + 1] = MakeMenu(PLAYER_1)
t[#t + 1] = MakeMenu(PLAYER_2)

-- Song preview actor
t[#t + 1] = MakePreviewActor()


return t
