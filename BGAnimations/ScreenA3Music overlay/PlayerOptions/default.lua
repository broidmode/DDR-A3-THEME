-- PlayerOptions overlay for ScreenA3Music
-- Styled to match the legacy ScreenPlayerOptions visuals
-- Works like TwoPartDiff: fades in as overlay, handles own input

local X_SPACING = 5
local Y_SPACING = 40
local NUM_VISIBLE_ROWS = 12

-- Get assets from the ScreenPlayerOptions overlay folder
-- Must use absolute path (leading /) or engine treats it as relative to current actor
local ThemeDir = THEME:GetCurrentThemeDirectory()
local assetsPath = "/" .. ThemeDir .. "BGAnimations/ScreenPlayerOptions overlay/"

-- Track which players have confirmed (closed) options
local optionsClosed = {
	[PLAYER_1] = false,
	[PLAYER_2] = false
}

-- Current row selection per player
local currentRow = {
	[PLAYER_1] = 1,
	[PLAYER_2] = 1
}

-- The option row frames per player
local optionFrames = {
	[PLAYER_1] = nil,
	[PLAYER_2] = nil
}

-- ============================================================================
-- OPTION DEFINITIONS
-- Each option has: name, choices (array of {label, mod}), getValue, setValue
-- ============================================================================

local SPEED_MODS = {}
for i = 1, 32 do
	local mult = i * 0.25
	-- Format: show .25/.5/.75 decimals but not .00
	local label
	if mult == math.floor(mult) then
		label = string.format("%dx", mult)
	elseif mult * 2 == math.floor(mult * 2) then
		label = string.format("%.1fx", mult)
	else
		label = string.format("%.2fx", mult)
	end
	SPEED_MODS[i] = { label = label, mod = string.format("*%g", mult) }
end

local ACCEL_CHOICES = {
	{ label = "OFF", mod = "" },
	{ label = "BOOST", mod = "Boost" },
	{ label = "BRAKE", mod = "Brake" },
	{ label = "WAVE", mod = "Wave" },
	{ label = "EXPAND", mod = "Expand" },
	{ label = "BOOMERANG", mod = "Boomerang" },
}

local APPEARANCE_CHOICES = {
	{ label = "VISIBLE", mod = "" },
	{ label = "HIDDEN", mod = "Hidden" },
	{ label = "SUDDEN", mod = "Sudden" },
	{ label = "STEALTH", mod = "Stealth" },
	{ label = "HIDDEN+", mod = "HiddenOffset" },
	{ label = "SUDDEN+", mod = "SuddenOffset" },
}

local TURN_CHOICES = {
	{ label = "OFF", mod = "" },
	{ label = "MIRROR", mod = "Mirror" },
	{ label = "BACKWARDS", mod = "Backwards" },
	{ label = "LEFT", mod = "Left" },
	{ label = "RIGHT", mod = "Right" },
	{ label = "SHUFFLE", mod = "Shuffle" },
	{ label = "SOFT SHUFFLE", mod = "SoftShuffle" },
	{ label = "SUPER SHUFFLE", mod = "SuperShuffle" },
}

local SCROLL_CHOICES = {
	{ label = "OFF", mod = "" },
	{ label = "REVERSE", mod = "Reverse" },
	{ label = "SPLIT", mod = "Split" },
	{ label = "ALTERNATE", mod = "Alternate" },
	{ label = "CROSS", mod = "Cross" },
	{ label = "CENTERED", mod = "Centered" },
}

local HIDE_CHOICES = {
	{ label = "OFF", mod = "" },
	{ label = "DARK", mod = "Dark" },
}

local REMOVE_CHOICES = {
	{ label = "OFF", mod = "" },
	{ label = "NO HOLDS", mod = "NoHolds" },
	{ label = "NO ROLLS", mod = "NoRolls" },
	{ label = "NO MINES", mod = "NoMines" },
	{ label = "NO HANDS", mod = "NoHands" },
	{ label = "NO QUADS", mod = "NoQuads" },
	{ label = "NO STRETCH", mod = "NoStretch" },
}

local FREEZE_CHOICES = {
	{ label = "OFF", mod = "" },
	{ label = "NO JUMPS", mod = "NoJumps" },
}

local GAUGE_CHOICES = {
	{ label = "NORMAL", mod = "", gaugeType = "Normal" },
	{ label = "LIFE4", mod = "4 Lives,battery", gaugeType = "Life4" },
	{ label = "RISKY", mod = "1 Lives,battery", gaugeType = "Risky" },
	{ label = "FLARE I", mod = "failoff", gaugeType = "Flare1" },
	{ label = "FLARE II", mod = "failoff", gaugeType = "Flare2" },
	{ label = "FLARE III", mod = "failoff", gaugeType = "Flare3" },
	{ label = "FLARE IV", mod = "failoff", gaugeType = "Flare4" },
	{ label = "FLARE V", mod = "failoff", gaugeType = "Flare5" },
	{ label = "FLARE VI", mod = "failoff", gaugeType = "Flare6" },
	{ label = "FLARE VII", mod = "failoff", gaugeType = "Flare7" },
	{ label = "FLARE VIII", mod = "failoff", gaugeType = "Flare8" },
	{ label = "FLARE IX", mod = "failoff", gaugeType = "Flare9" },
	{ label = "FLARE EX", mod = "failoff", gaugeType = "FlareEX" },
	{ label = "FLOATING", mod = "failoff", gaugeType = "FloatingFlare" },
}

-- Build noteskin choices dynamically
local function GetNoteSkinChoices()
	local skins = NOTESKIN:GetNoteSkinNames()
	local choices = {}
	for i, skin in ipairs(skins) do
		choices[i] = { label = skin:upper(), mod = skin }
	end
	return choices
end

-- Helper to check if a mod is active (handles both boolean and numeric returns)
local function IsModActive(val)
	if val == nil then return false end
	if type(val) == "boolean" then return val end
	if type(val) == "number" then return val > 0 end
	return false
end

-- Option row definitions
local function GetOptionRows(pn)
	local ps = GAMESTATE:GetPlayerState(pn)
	local po = ps:GetPlayerOptions("ModsLevel_Preferred")

	local rows = {
		{
			name = "SPEED",
			choices = SPEED_MODS,
			selected = 4, -- Default to 1.0x
			getValue = function()
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				local speedmod = curPo:XMod()
				if speedmod then
					local idx = math.floor(speedmod / 0.25 + 0.5)
					return math.max(1, math.min(idx, #SPEED_MODS))
				end
				return 4
			end,
			setValue = function(choice)
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				local mult = choice * 0.25
				curPo:XMod(mult)
			end,
		},
		{
			name = "ACCEL",
			choices = ACCEL_CHOICES,
			selected = 1,
			getValue = function()
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				if IsModActive(curPo:Boost()) then return 2
				elseif IsModActive(curPo:Brake()) then return 3
				elseif IsModActive(curPo:Wave()) then return 4
				elseif IsModActive(curPo:Expand()) then return 5
				elseif IsModActive(curPo:Boomerang()) then return 6
				end
				return 1
			end,
			setValue = function(choice)
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				-- Clear all accel mods first, then apply selected
				curPo:FromString("no boost,no brake,no wave,no expand,no boomerang")
				local mods = {"", "boost", "brake", "wave", "expand", "boomerang"}
				if mods[choice] and mods[choice] ~= "" then
					curPo:FromString(mods[choice])
				end
			end,
		},
		{
			name = "APPEARANCE",
			choices = APPEARANCE_CHOICES,
			selected = 1,
			getValue = function()
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				if IsModActive(curPo:HiddenOffset()) then return 5
				elseif IsModActive(curPo:SuddenOffset()) then return 6
				elseif IsModActive(curPo:Hidden()) then return 2
				elseif IsModActive(curPo:Sudden()) then return 3
				elseif IsModActive(curPo:Stealth()) then return 4
				end
				return 1
			end,
			setValue = function(choice)
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				-- Clear appearance mods first
				curPo:FromString("no hidden,no sudden,no stealth")
				curPo:HiddenOffset(nil)
				curPo:SuddenOffset(nil)
				local mods = {"", "hidden", "sudden", "stealth", "", ""}
				if choice == 5 then
					curPo:HiddenOffset(1)
				elseif choice == 6 then
					curPo:SuddenOffset(1)
				elseif mods[choice] and mods[choice] ~= "" then
					curPo:FromString(mods[choice])
				end
			end,
		},
		{
			name = "TURN",
			choices = TURN_CHOICES,
			selected = 1,
			getValue = function()
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				if IsModActive(curPo:Mirror()) then return 2
				elseif IsModActive(curPo:Backwards()) then return 3
				elseif IsModActive(curPo:Left()) then return 4
				elseif IsModActive(curPo:Right()) then return 5
				elseif IsModActive(curPo:Shuffle()) then return 6
				elseif IsModActive(curPo:SoftShuffle()) then return 7
				elseif IsModActive(curPo:SuperShuffle()) then return 8
				end
				return 1
			end,
			setValue = function(choice)
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				-- Clear all turn mods first
				curPo:FromString("no turn")
				local mods = {"", "mirror", "backwards", "left", "right", "shuffle", "softshuffle", "supershuffle"}
				if mods[choice] and mods[choice] ~= "" then
					curPo:FromString(mods[choice])
				end
			end,
		},
		{
			name = "SCROLL",
			choices = SCROLL_CHOICES,
			selected = 1,
			getValue = function()
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				local reverse = curPo:Reverse() or 0
				if type(reverse) == "number" and reverse >= 0.5 then return 2
				elseif IsModActive(curPo:Split()) then return 3
				elseif IsModActive(curPo:Alternate()) then return 4
				elseif IsModActive(curPo:Cross()) then return 5
				elseif IsModActive(curPo:Centered()) then return 6
				end
				return 1
			end,
			setValue = function(choice)
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				-- Clear all scroll mods first
				curPo:FromString("no reverse,no split,no alternate,no cross,no centered")
				local mods = {"", "reverse", "split", "alternate", "cross", "centered"}
				if mods[choice] and mods[choice] ~= "" then
					curPo:FromString(mods[choice])
				end
			end,
		},
		{
			name = "HIDE",
			choices = HIDE_CHOICES,
			selected = 1,
			getValue = function()
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				if IsModActive(curPo:Dark()) then return 2 end
				return 1
			end,
			setValue = function(choice)
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				curPo:FromString(choice == 2 and "dark" or "no dark")
			end,
		},
		{
			name = "NOTESKIN",
			choices = GetNoteSkinChoices(),
			selected = 1,
			getValue = function()
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				local current = curPo:NoteSkin()
				if not current or current == "" then return 1 end
				local skins = NOTESKIN:GetNoteSkinNames()
				for i, skin in ipairs(skins) do
					if skin:lower() == current:lower() then return i end
				end
				return 1
			end,
			setValue = function(choice)
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				local skins = NOTESKIN:GetNoteSkinNames()
				if skins[choice] then
					curPo:NoteSkin(skins[choice])
				end
			end,
		},
		{
			name = "REMOVE",
			choices = REMOVE_CHOICES,
			selected = 1,
			getValue = function()
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				if IsModActive(curPo:NoHolds()) then return 2
				elseif IsModActive(curPo:NoRolls()) then return 3
				elseif IsModActive(curPo:NoMines()) then return 4
				elseif IsModActive(curPo:NoHands()) then return 5
				elseif IsModActive(curPo:NoQuads()) then return 6
				elseif IsModActive(curPo:NoStretch()) then return 7
				end
				return 1
			end,
			setValue = function(choice)
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				-- Clear all remove mods first
				curPo:FromString("no noholds,no norolls,no nomines,no nohands,no noquads,no nostretch")
				local mods = {"", "noholds", "norolls", "nomines", "nohands", "noquads", "nostretch"}
				if mods[choice] and mods[choice] ~= "" then
					curPo:FromString(mods[choice])
				end
			end,
		},
		{
			name = "FREEZE",
			choices = FREEZE_CHOICES,
			selected = 1,
			getValue = function()
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				if IsModActive(curPo:NoJumps()) then return 2 end
				return 1
			end,
			setValue = function(choice)
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				curPo:FromString(choice == 2 and "nojumps" or "no nojumps")
			end,
		},
	}

	-- Add Gauge option only if not extra stage
	if not (GAMESTATE:IsExtraStage() or GAMESTATE:IsExtraStage2()) then
		-- Map gaugeType to choice index
		local gaugeTypeToIdx = {}
		for i, c in ipairs(GAUGE_CHOICES) do
			gaugeTypeToIdx[c.gaugeType] = i
		end

		rows[#rows+1] = {
			name = "GAUGE",
			choices = GAUGE_CHOICES,
			selected = 1,
			getValue = function()
				-- Check saved FlareGauge preference first
				local saved = GetPlayerGaugePref and GetPlayerGaugePref(pn) or nil
				if saved and gaugeTypeToIdx[saved] then
					return gaugeTypeToIdx[saved]
				end
				-- Fall back to checking mod string
				local mods = ps:GetPlayerOptionsString("ModsLevel_Preferred")
				if string.find(mods, "4 Lives") or string.find(mods, "Life4") then return 2
				elseif string.find(mods, "1 Lives") or string.find(mods, "Risky") then return 3
				end
				return 1
			end,
			setValue = function(choice)
				local curPo = ps:GetPlayerOptions("ModsLevel_Preferred")
				local gaugeChoice = GAUGE_CHOICES[choice]
				if not gaugeChoice then return end

				-- Store gauge type for FlareGauge system
				local gaugeType = gaugeChoice.gaugeType
				if SetPlayerGaugePref then
					SetPlayerGaugePref(pn, gaugeType)
				end
				local short = ToEnumShortString(pn)
				setenv("FlareGaugeType" .. short, gaugeType)

				-- Clear battery/lives mods first, then apply new gauge
				curPo:FromString("bar,failimmediate")
				if gaugeChoice.mod and gaugeChoice.mod ~= "" then
					curPo:FromString(gaugeChoice.mod)
				end
			end,
		}
	end

	-- Initialize selections from current values
	for _, row in ipairs(rows) do
		row.selected = row.getValue()
	end

	return rows
end

-- ============================================================================
-- BUILD THE OPTION FRAME FOR A PLAYER
-- ============================================================================

-- Helper to calculate BPM display for speed row
local function GetBPMDisplayText(pn, speedMult)
	local song = GAMESTATE:GetCurrentSong()
	if not song then return "?" end

	local steps = GAMESTATE:GetCurrentSteps(pn)
	if not steps then return "?" end

	if song:IsDisplayBpmRandom() or song:IsDisplayBpmSecret() then
		return "?"
	end

	local td = steps:GetTimingData()
	if not td then return "?" end

	local bpms = td:GetActualBPM()
	if not bpms or not bpms[1] or not bpms[2] then return "?" end

	local bpmMin = bpms[1]
	local bpmMax = bpms[2]
	local BPM1Mod = math.floor(bpmMin * speedMult + 0.5)

	if bpmMin == bpmMax then
		return tostring(BPM1Mod)
	else
		local dominant = GetDominantBPM and GetDominantBPM(song) or bpmMin
		local bpmMed = dominant or bpmMin
		local BPM2Mod = math.floor(bpmMed * speedMult + 0.5)
		local BPM3Mod = math.floor(bpmMax * speedMult + 0.5)
		return BPM1Mod.." - "..BPM2Mod.." - "..BPM3Mod
	end
end

local function MakeRow(pn, rowIndex, optionRows)
	local row = optionRows[rowIndex]
	local hasFocus = rowIndex == currentRow[pn]
	local isSpeedRow = row.name == "SPEED"

	return Def.ActorFrame{
		Name = "Row"..rowIndex,
		InitCommand = function(s) s:y((rowIndex - 1) * Y_SPACING) end,
		OnCommand = function(s)
			s:playcommand(hasFocus and "GainFocus" or "LoseFocus")
		end,

		-- BPM Display (only for Speed row, shows above)
		isSpeedRow and Def.ActorFrame{
			Name = "BPMDisplay",
			InitCommand = function(s) s:y(-39):diffusealpha(hasFocus and 1 or 0) end,
			GainFocusCommand = function(s) s:finishtweening():linear(0.1):diffusealpha(1) end,
			LoseFocusCommand = function(s) s:finishtweening():linear(0.1):diffusealpha(0) end,

			Def.Sprite{
				Texture = assetsPath.."large_base.png",
				InitCommand = function(s) s:diffuse(color("0,0,0,1")) end,
			},
			Def.Sprite{
				Texture = assetsPath.."large_line.png",
			},
			Def.Sprite{
				Texture = assetsPath.."type_line.png",
				InitCommand = function(s) s:x(64):setsize(142,30):diffuse(color(GetCurrentModel() == "Gold" and "#dac42e" or "#00ffde")) end,
			},
			Def.Quad{
				InitCommand = function(s) s:setsize(4,15):x(-132):diffuse(color(GetCurrentModel() == "Gold" and "#8b000e" or "#00d8ff")) end,
			},
			LoadFont("_avenirnext lt pro bold Bold 20px")..{
				Text = "CURRENT BPM",
				InitCommand = function(s) s:x(-69):zoom(0.78):maxwidth(150) end,
			},
			LoadFont("_avenirnext lt pro bold Bold 20px")..{
				Name = "BPMValue",
				InitCommand = function(s)
					s:x(65):zoom(0.9)
					local speedMult = row.selected * 0.25
					s:settext(GetBPMDisplayText(pn, speedMult))
				end,
				RefreshCommand = function(s)
					local speedMult = row.selected * 0.25
					s:settext(GetBPMDisplayText(pn, speedMult))
				end,
			},
		} or Def.Actor{},

		-- Row base (each child defines its own GainFocus/LoseFocus per original pattern)
		Def.Sprite{
			Name = "Base",
			Texture = assetsPath.."large_base.png",
			InitCommand = function(s)
				-- Set initial color based on focus state
				if hasFocus then
					s:diffuse(color(GetCurrentModel() == "Gold" and "#84ffff" or "#ffee00"))
				else
					s:diffuse(color("0,0,0,1"))
				end
			end,
			GainFocusCommand = function(s) s:diffuse(color(GetCurrentModel() == "Gold" and "#84ffff" or "#ffee00")) end,
			LoseFocusCommand = function(s) s:diffuse(color("0,0,0,1")) end,
		},
		Def.Sprite{
			Texture = assetsPath.."large_line.png",
		},
		-- Left color bar
		Def.Quad{
			Name = "LeftBar",
			InitCommand = function(s)
				s:setsize(4,15):x(-132)
				if hasFocus then
					s:diffuse(color("0,0,0,1"))
				else
					s:diffuse(color(GetCurrentModel() == "Gold" and "#8b000e" or "#00d8ff"))
				end
			end,
			GainFocusCommand = function(s) s:diffuse(color("0,0,0,1")) end,
			LoseFocusCommand = function(s) s:diffuse(color(GetCurrentModel() == "Gold" and "#8b000e" or "#00d8ff")) end,
		},
		-- Value box
		Def.Sprite{
			Texture = assetsPath.."type_base.png",
			InitCommand = function(s) s:diffuse(color("0,0,0,1")):x(64):setsize(142,30) end,
		},
		Def.Sprite{
			Texture = assetsPath.."type_line.png",
			InitCommand = function(s) s:x(64):setsize(142,30):diffuse(color(GetCurrentModel() == "Gold" and "#dac42e" or "#00ffde")) end,
		},

		-- Option name
		LoadFont("_avenirnext lt pro bold Bold 20px")..{
			Name = "Name",
			Text = row.name,
			InitCommand = function(s)
				s:x(-122):halign(0):zoom(0.75):maxwidth(150):uppercase(true)
				if hasFocus then
					s:diffuse(color("0,0,0,1"))
				else
					s:diffuse(color("1,1,1,1"))
				end
			end,
			GainFocusCommand = function(s) s:diffuse(color("0,0,0,1")) end,
			LoseFocusCommand = function(s) s:diffuse(color("1,1,1,1")) end,
		},

		-- Current value (set text immediately in InitCommand, then update via Set)
		LoadFont("_avenirnext lt pro bold Bold 20px")..{
			Name = "Value",
			InitCommand = function(s)
				s:x(64):zoom(0.8):maxwidth(150):uppercase(true)
				-- Set initial value immediately
				local choice = row.choices[row.selected]
				if choice then
					s:settext(choice.label)
					if row.selected == 1 or (row.name == "SPEED" and row.selected == 4) then
						s:diffuse(color("#06ff06")):diffusetopedge(color("#74ff74"))
					elseif choice.label == "LIFE4" or choice.label == "RISKY" then
						s:diffuse(color("#ff0606")):diffusetopedge(color("#ff7474"))
					elseif string.find(choice.label, "FLARE") or choice.label == "FLOATING" then
						s:diffuse(color("#ff9900")):diffusetopedge(color("#ffcc66"))
					else
						s:diffuse(color("1,1,1,1"))
					end
				end
			end,
			SetCommand = function(s)
				local choice = row.choices[row.selected]
				if choice then
					s:settext(choice.label)
					if row.selected == 1 or (row.name == "SPEED" and row.selected == 4) then
						s:diffuse(color("#06ff06")):diffusetopedge(color("#74ff74"))
					elseif choice.label == "LIFE4" or choice.label == "RISKY" then
						s:diffuse(color("#ff0606")):diffusetopedge(color("#ff7474"))
					elseif string.find(choice.label, "FLARE") or choice.label == "FLOATING" then
						s:diffuse(color("#ff9900")):diffusetopedge(color("#ffcc66"))
					else
						s:diffuse(color("1,1,1,1"))
					end
				end
			end,
			RefreshCommand = function(s) s:playcommand("Set") end,
		},

		-- Cursors
		LoadActor(THEME:GetPathG("", "_shared/"..Model().."cursor"))..{
			Name = "CursorL",
			InitCommand = function(s) s:zoom(0.75):x(-20):visible(hasFocus):bounce():effectmagnitude(3,0,0):effectperiod(1) end,
			GainFocusCommand = function(s) s:visible(true) end,
			LoseFocusCommand = function(s) s:visible(false) end,
		},
		LoadActor(THEME:GetPathG("", "_shared/"..Model().."cursor"))..{
			Name = "CursorR",
			InitCommand = function(s) s:zoom(0.75):x(146):zoomx(-0.75):visible(hasFocus):bounce():effectmagnitude(-3,0,0):effectperiod(1) end,
			GainFocusCommand = function(s) s:visible(true) end,
			LoseFocusCommand = function(s) s:visible(false) end,
		},
	}
end

local function BuildOptionsFrame(pn)
	local optionRows = GetOptionRows(pn)
	local numRows = #optionRows

	-- Build scroller with all rows
	-- Initial Y matches original ScreenPlayerOptions scroller position
	local scrollerDef = Def.ActorFrame{
		Name = "Scroller",
		InitCommand = function(s) s:y(SCREEN_CENTER_Y - 26) end,
	}
	for i = 1, numRows do
		scrollerDef[#scrollerDef+1] = MakeRow(pn, i, optionRows)
	end

	local f = Def.ActorFrame{
		Name = "OptionsFrame_"..ToEnumShortString(pn),
		InitCommand = function(s)
			optionFrames[pn] = s
			s.optionRows = optionRows
		end,

		-- Header
		Def.Sprite{
			Texture = assetsPath..Model().."header.png",
			InitCommand = function(s) s:y(SCREEN_CENTER_Y - 150) end,
		},
		Def.Sprite{
			Texture = assetsPath..Language().."text.png",
			InitCommand = function(s) s:y(SCREEN_CENTER_Y - 150) end,
		},

		-- Scroller container with rows
		scrollerDef,

		-- Explanation box
		Def.Sprite{
			Texture = assetsPath.."exp.png",
			InitCommand = function(s) s:y(SCREEN_CENTER_Y + 215) end,
		},
		LoadFont("_avenirnext lt pro bold Bold 20px")..{
			Name = "Explanation",
			InitCommand = function(s) s:y(SCREEN_CENTER_Y + 215):wrapwidthpixels(290):zoom(1) end,
			BeginCommand = function(s) s:queuecommand("Refresh") end,
			RefreshCommand = function(s)
				local row = optionRows[currentRow[pn]]
				if row then
					-- Simple explanations
					local explanations = {
						SPEED = "Adjust scroll speed multiplier.",
						ACCEL = "Change arrow acceleration patterns.",
						APPEARANCE = "Control arrow visibility timing.",
						TURN = "Rotate or shuffle arrow directions.",
						SCROLL = "Change scroll direction.",
						HIDE = "Hide gameplay elements.",
						NOTESKIN = "Change the appearance of arrows.",
						REMOVE = "Remove certain note types.",
						FREEZE = "Remove jump patterns.",
						GAUGE = "Change life gauge behavior.\nLIFE4/RISKY = battery life.",
					}
					s:settext(explanations[row.name] or "")
				end
			end,
		},
	}

	return f, optionRows
end

-- ============================================================================
-- REFRESH DISPLAY
-- ============================================================================

local function RefreshRow(pn, rowIndex)
	local frame = optionFrames[pn]
	if not frame then return end

	local scroller = frame:GetChild("Scroller")
	if not scroller then return end

	local rowFrame = scroller:GetChild("Row"..rowIndex)
	if rowFrame then
		rowFrame:GetChild("Value"):playcommand("Refresh")
		-- Also refresh BPM display if this is the speed row
		local bpmDisplay = rowFrame:GetChild("BPMDisplay")
		if bpmDisplay then
			local bpmValue = bpmDisplay:GetChild("BPMValue")
			if bpmValue then
				bpmValue:playcommand("Refresh")
			end
		end
	end
end

local function RefreshFocus(pn)
	local frame = optionFrames[pn]
	if not frame then return end

	local scroller = frame:GetChild("Scroller")
	if not scroller then return end

	local optionRows = frame.optionRows
	for i = 1, #optionRows do
		local rowFrame = scroller:GetChild("Row"..i)
		if rowFrame then
			rowFrame:playcommand(i == currentRow[pn] and "GainFocus" or "LoseFocus")
		end
	end

	-- Scroll to keep current row visible (matches original SCREEN_CENTER_Y - 26)
	local baseY = SCREEN_CENTER_Y - 26
	local targetY = baseY - (currentRow[pn] - 1) * Y_SPACING + (NUM_VISIBLE_ROWS/2 - 1) * Y_SPACING
	targetY = math.min(baseY, targetY)
	scroller:stoptweening():decelerate(0.1):y(targetY)

	-- Update explanation
	frame:GetChild("Explanation"):playcommand("Refresh")
end

-- ============================================================================
-- INPUT HANDLER
-- ============================================================================

local function OptionsInputHandler(event)
	local pn = event.PlayerNumber
	local button = event.button
	if event.type == "InputEventType_Release" then return end
	if not GAMESTATE:IsPlayerEnabled(pn) then return end
	if optionsClosed[pn] then return end

	local frame = optionFrames[pn]
	if not frame then return end
	local optionRows = frame.optionRows
	if not optionRows then return end

	local row = optionRows[currentRow[pn]]

	if button == "MenuUp" or button == "Up" then
		if currentRow[pn] > 1 then
			SOUND:PlayOnce(THEME:GetPathS("ScreenOptions", "next"))
			currentRow[pn] = currentRow[pn] - 1
			RefreshFocus(pn)
		end
		return true

	elseif button == "MenuDown" or button == "Down" then
		if currentRow[pn] < #optionRows then
			SOUND:PlayOnce(THEME:GetPathS("ScreenOptions", "next"))
			currentRow[pn] = currentRow[pn] + 1
			RefreshFocus(pn)
		end
		return true

	elseif button == "MenuLeft" or button == "Left" then
		if row and row.selected > 1 then
			SOUND:PlayOnce(THEME:GetPathS("ScreenOptions", "change"))
			row.selected = row.selected - 1
			row.setValue(row.selected)
			RefreshRow(pn, currentRow[pn])
		end
		return true

	elseif button == "MenuRight" or button == "Right" then
		if row and row.selected < #row.choices then
			SOUND:PlayOnce(THEME:GetPathS("ScreenOptions", "change"))
			row.selected = row.selected + 1
			row.setValue(row.selected)
			RefreshRow(pn, currentRow[pn])
		end
		return true

	elseif button == "Start" or button == "Select" or button == "Back" then
		-- Close options for this player
		SOUND:PlayOnce(THEME:GetPathS("ScreenSelectMusic", "swoosh"))
		optionsClosed[pn] = true
		MESSAGEMAN:Broadcast("OptionsConfirmed"..pn)

		-- Check if all players have closed
		local allClosed = true
		for _, p in ipairs(GAMESTATE:GetEnabledPlayers()) do
			if not optionsClosed[p] then
				allClosed = false
				break
			end
		end

		if allClosed then
			MESSAGEMAN:Broadcast("OptionsClosed")
		end
		return true
	end

	return false
end

-- ============================================================================
-- MAIN ACTOR
-- ============================================================================

local t = Def.ActorFrame{
	InitCommand = function(s)
		s:sleep(0.3):queuecommand("AddInput")
	end,
	AddInputCommand = function(s)
		SCREENMAN:GetTopScreen():AddInputCallback(OptionsInputHandler)
	end,
	OptionsClosedMessageCommand = function(s)
		SCREENMAN:GetTopScreen():RemoveInputCallback(OptionsInputHandler)
		s:sleep(0.3):queuecommand("Remove")
	end,
	RemoveCommand = function(s)
		-- The parent container will remove us
	end,

	-- Darkening background (like legacy ScreenPlayerOptions)
	Def.Quad{
		InitCommand = function(s)
			s:diffuse(color("0,0,0,0.5")):FullScreen()
		end,
		OnCommand = function(s)
			s:diffusealpha(0):sleep(0.1):linear(0.2):diffusealpha(0.5)
		end,
		OffCommand = function(s)
			s:linear(0.2):diffusealpha(0)
		end,
	},

	-- Swoosh sound on open (like legacy ScreenPlayerOptions)
	LoadActor(THEME:GetPathS("ScreenSelectMusic", "swoosh"))..{
		OnCommand = function(s) s:queuecommand("Play") end,
		PlayCommand = function(s) s:play() end,
	},
}

-- Build frames for each joined player (wrapped with external zoom like original)
for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	optionsClosed[pn] = false
	currentRow[pn] = 1

	local frame, rows = BuildOptionsFrame(pn)
	-- Wrap in container that applies zoom externally (matching original default.lua pattern)
	local wrapX = pn == PLAYER_1 and (SCREEN_CENTER_X - 143) or (SCREEN_CENTER_X + 143)
	local wrapper = Def.ActorFrame{
		InitCommand = function(s)
			s:xy(wrapX, SCREEN_CENTER_Y - 160.5):zoom(0.667)
		end,
		OnCommand = function(s)
			s:diffusealpha(0):sleep(0.1):linear(0.2):diffusealpha(1)
		end,
		OffCommand = function(s)
			s:linear(0.2):diffusealpha(0)
		end,
	}
	wrapper[#wrapper+1] = frame
	t[#t+1] = wrapper
end

return t
