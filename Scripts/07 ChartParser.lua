-- ChartParser.lua
-- Parses SM/SSC files to calculate accurate DDR A3 maxsteps
-- DDR counts double-freeze arrows (hold jumps) as 1 OK, not 2

ChartParser = {}

-- Cache parsed results to avoid re-parsing the same chart
local ParseCache = {}

-- Get cache key for a chart
local function GetCacheKey(steps)
    local song = GAMESTATE:GetCurrentSong()
    if not song then return nil end
    local songDir = song:GetSongDir()
    local stepsType = ToEnumShortString(steps:GetStepsType())
    local difficulty = ToEnumShortString(steps:GetDifficulty())
    local meter = steps:GetMeter()
    return songDir .. "|" .. stepsType .. "|" .. difficulty .. "|" .. meter
end

-- Read file contents using RageFileUtil
local function ReadFile(filepath)
    local f = RageFileUtil.CreateRageFile()
    if not f:Open(filepath, 1) then -- 1 = read mode
        f:destroy()
        return nil
    end
    local contents = f:Read()
    f:destroy()
    return contents
end

-- Parse note data string and count judgment opportunities
local function ParseNoteData(notedata)
    local counts = {
        tap_rows = 0,
        tap_arrows = 0,
        jump_rows = 0,
        hand_rows = 0,
        hold_heads = 0,
        hold_tails = 0,
        hold_jump_rows = 0,
        shock_rows = 0,
        mine_arrows = 0,
    }

    -- Split into lines
    for line in notedata:gmatch("[^\r\n]+") do
        -- Skip measure separators and comments
        line = line:gsub("//.*", ""):match("^%s*(.-)%s*$") -- trim and remove comments
        if line ~= "" and line ~= "," and line ~= ";" and #line >= 4 then
            -- Count note types in this row
            local taps = 0
            local holds = 0
            local tails = 0
            local mines = 0

            for i = 1, #line do
                local c = line:sub(i, i)
                if c == "1" then
                    taps = taps + 1
                elseif c == "2" then
                    taps = taps + 1
                    holds = holds + 1
                elseif c == "4" then
                    taps = taps + 1  -- roll head
                elseif c == "3" then
                    tails = tails + 1
                elseif c == "M" then
                    mines = mines + 1
                end
            end

            -- Track counts
            counts.tap_arrows = counts.tap_arrows + taps
            counts.hold_heads = counts.hold_heads + holds
            counts.hold_tails = counts.hold_tails + tails
            counts.mine_arrows = counts.mine_arrows + mines

            -- Track rows (judgment opportunities)
            if taps > 0 then
                counts.tap_rows = counts.tap_rows + 1
                if taps == 2 then
                    counts.jump_rows = counts.jump_rows + 1
                elseif taps >= 3 then
                    counts.hand_rows = counts.hand_rows + 1
                end
            end

            -- Detect hold jumps (2+ holds starting on same row)
            if holds >= 2 then
                counts.hold_jump_rows = counts.hold_jump_rows + 1
            end

            -- Detect shock arrows (all 4 columns are mines)
            if #line >= 4 and line:sub(1, 4) == "MMMM" then
                counts.shock_rows = counts.shock_rows + 1
            end
        end
    end

    return counts
end

-- Extract chart data from SM file content
local function ExtractChartFromSM(content, targetStepsType, targetDifficulty)
    -- SM format: #NOTES: stepstype : description : difficulty : meter : groove : notedata ;
    local pattern = "#NOTES:%s*([^:]+):%s*([^:]*):%s*([^:]+):%s*(%d+):%s*([^:]*):%s*([^;]+)"

    for stepsType, desc, difficulty, meter, groove, notedata in content:gmatch(pattern) do
        stepsType = stepsType:match("^%s*(.-)%s*$"):lower()
        difficulty = difficulty:match("^%s*(.-)%s*$")

        -- Normalize difficulty names (Expert -> Hard in SM files)
        local normalizedTarget = targetDifficulty:lower()
        local normalizedDiff = difficulty:lower()

        if stepsType == targetStepsType:lower() and normalizedDiff == normalizedTarget then
            return notedata
        end
    end

    return nil
end

-- Extract chart data from SSC file content
local function ExtractChartFromSSC(content, targetStepsType, targetDifficulty)
    -- SSC format uses #NOTEDATA sections
    local inTargetChart = false
    local notedata = nil

    -- Find NOTEDATA sections
    for section in content:gmatch("#NOTEDATA.-#NOTES[2]?:%s*([^;]+)") do
        -- Extract metadata from this section
        local stepsType = section:match("#STEPSTYPE:([^;]+);")
        local difficulty = section:match("#DIFFICULTY:([^;]+);")
        local notes = section:match("#NOTES[2]?:%s*([^;]+)")

        if stepsType and difficulty and notes then
            stepsType = stepsType:match("^%s*(.-)%s*$"):lower()
            difficulty = difficulty:match("^%s*(.-)%s*$"):lower()

            if stepsType == targetStepsType:lower() and difficulty == targetDifficulty:lower() then
                return notes
            end
        end
    end

    return nil
end

-- Main function: parse chart and calculate DDR A3 maxsteps
function ChartParser.GetMaxSteps(pn)
    local steps = GAMESTATE:GetCurrentSteps(pn)
    if not steps then return nil end

    -- Check cache first
    local cacheKey = GetCacheKey(steps)
    if cacheKey and ParseCache[cacheKey] then
        return ParseCache[cacheKey]
    end

    -- Get the simfile path
    local filepath = steps:GetFilename()
    if not filepath or filepath == "" then
        return nil
    end

    -- Read the file
    local content = ReadFile(filepath)
    if not content then
        return nil
    end

    -- Determine file type and extract chart
    local filetype = filepath:match("%.([^%.]+)$"):lower()
    local stepsType = ToEnumShortString(steps:GetStepsType()):gsub("_", "-"):lower()
    local difficulty = ToEnumShortString(steps:GetDifficulty())

    local notedata = nil
    if filetype == "ssc" then
        notedata = ExtractChartFromSSC(content, stepsType, difficulty)
    elseif filetype == "sm" then
        notedata = ExtractChartFromSM(content, stepsType, difficulty)
    end

    if not notedata then
        return nil
    end

    -- Parse the note data
    local counts = ParseNoteData(notedata)

    -- Calculate DDR A3 maxsteps
    -- Formula: tap_rows + (hold_tails - hold_jump_rows) + shock_rows
    local result = {
        tap_rows = counts.tap_rows,
        hold_tails = counts.hold_tails,
        hold_jump_rows = counts.hold_jump_rows,
        shock_rows = counts.shock_rows,
        adjusted_hold_oks = counts.hold_tails - counts.hold_jump_rows,
        maxsteps = counts.tap_rows + (counts.hold_tails - counts.hold_jump_rows) + counts.shock_rows,
        -- Also include raw counts for debugging
        raw = counts
    }

    -- Cache the result
    if cacheKey then
        ParseCache[cacheKey] = result
    end

    return result
end

-- Clear cache (call when song changes)
function ChartParser.ClearCache()
    ParseCache = {}
end

-- Debug function: print chart analysis
function ChartParser.DebugPrint(pn)
    local result = ChartParser.GetMaxSteps(pn)
    if not result then
        Trace("ChartParser: Could not parse chart")
        return
    end

    Trace("=== ChartParser Debug ===")
    Trace("tap_rows: " .. result.tap_rows)
    Trace("hold_tails: " .. result.hold_tails)
    Trace("hold_jump_rows: " .. result.hold_jump_rows)
    Trace("adjusted_hold_oks: " .. result.adjusted_hold_oks)
    Trace("shock_rows: " .. result.shock_rows)
    Trace("MAXSTEPS: " .. result.maxsteps)
    Trace("=========================")
end
