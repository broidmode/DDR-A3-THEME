local pn = ...

-- Hint definitions: {main text, sub text, glow positions}
-- Glow positions: "UL"=up+left, "DL"=down+left, "DR"=down+right, "UD"=up+down
local Hints = {
    {"UP + LEFT", "CYCLE PANELS", "UL"},
    {"DOWN + LEFT", "SINGLES MODE", "DL"},
    {"DOWN + RIGHT", "DOUBLES MODE", "DR"},
    {"UP UP / DOWN DOWN", "CYCLE DIFFICULTY", "UD"},
}

local HINT_DURATION = 3.0  -- seconds per hint
local FADE_TIME = 0.25

return Def.ActorFrame{
    InitCommand=function(s) s:zoom(0.8) end,
    Def.Sprite{
        Texture=Model().."pane",
        InitCommand=function(s)
            s:xy(pn==PLAYER_1 and -20 or 20,-20):zoom(1)
        end,
    };
    Def.Sprite{
        Texture="pad.png",
        InitCommand=function(s)
            s:xy(pn==PLAYER_1 and -70 or 70,-58):valign(1):diffusealpha(0.75):zoom(0.95)
        end,
    };
    -- Cycling hint text
    Def.ActorFrame{
        InitCommand=function(s)
            s:xy(pn==PLAYER_1 and -20 or 20,-22)
            s.hintIdx = 1
            s:queuecommand("ShowHint")
        end,
        ShowHintCommand=function(s)
            local hint = Hints[s.hintIdx]
            local mainText = s:GetChild("MainText")
            local subText = s:GetChild("SubText")
            if mainText then mainText:settext(hint[1]) end
            if subText then subText:settext(hint[2]) end
            -- Broadcast to update glow
            s:GetParent():playcommand("UpdateGlow", {pattern = hint[3]})
            -- Fade in
            s:diffusealpha(0):linear(FADE_TIME):diffusealpha(1)
            s:sleep(HINT_DURATION - FADE_TIME * 2)
            s:linear(FADE_TIME):diffusealpha(0)
            s:queuecommand("NextHint")
        end,
        NextHintCommand=function(s)
            s.hintIdx = (s.hintIdx % #Hints) + 1
            s:queuecommand("ShowHint")
        end,
        Def.BitmapText{
            Font="_wheelnames 28px",
            Name="MainText",
            Text="",
            InitCommand=function(s)
                s:y(-8):zoom(0.6):diffuse(color("#FFFFFF")):diffusealpha(0.9)
                s:strokecolor(color("#000000")):maxwidth(200)
            end,
        },
        Def.BitmapText{
            Font="_wheelnames 28px",
            Name="SubText",
            Text="",
            InitCommand=function(s)
                s:y(12):zoom(0.5):diffuse(color("#AAAAFF")):diffusealpha(0.8)
                s:strokecolor(color("#000000")):maxwidth(200)
            end,
        },
    };
    -- Arrow glow indicators
    Def.ActorFrame{
        InitCommand=function(s) s:xy(pn==PLAYER_1 and -70 or 70,-95) end,
        UpdateGlowCommand=function(s, params)
            local pattern = params.pattern
            local up = s:GetChild("GlowUp")
            local down = s:GetChild("GlowDown")
            local left = s:GetChild("GlowLeft")
            local right = s:GetChild("GlowRight")
            -- Hide all first
            if up then up:stoptweening():linear(0.1):diffusealpha(0) end
            if down then down:stoptweening():linear(0.1):diffusealpha(0) end
            if left then left:stoptweening():linear(0.1):diffusealpha(0) end
            if right then right:stoptweening():linear(0.1):diffusealpha(0) end
            -- Show relevant ones
            s:sleep(0.15):queuecommand("ShowGlow")
            s.glowPattern = pattern
        end,
        ShowGlowCommand=function(s)
            local pattern = s.glowPattern or "UL"
            local up = s:GetChild("GlowUp")
            local down = s:GetChild("GlowDown")
            local left = s:GetChild("GlowLeft")
            local right = s:GetChild("GlowRight")
            if pattern == "UL" then
                if up then up:linear(0.1):diffusealpha(1) end
                if left then left:linear(0.1):diffusealpha(1) end
            elseif pattern == "DL" then
                if down then down:linear(0.1):diffusealpha(1) end
                if left then left:linear(0.1):diffusealpha(1) end
            elseif pattern == "DR" then
                if down then down:linear(0.1):diffusealpha(1) end
                if right then right:linear(0.1):diffusealpha(1) end
            elseif pattern == "UD" then
                if up then up:linear(0.1):diffusealpha(1) end
                if down then down:linear(0.1):diffusealpha(1) end
            end
        end,
        Def.Sprite{
            Texture=Model().."glow",
            Name="GlowUp",
            InitCommand=function(s) s:y(-18):diffusealpha(0) end,
        };
        Def.Sprite{
            Texture=Model().."glow",
            Name="GlowDown",
            InitCommand=function(s) s:y(18):diffusealpha(0) end,
        };
        Def.Sprite{
            Texture=Model().."glow",
            Name="GlowLeft",
            InitCommand=function(s) s:x(-18):diffusealpha(0) end,
        };
        Def.Sprite{
            Texture=Model().."glow",
            Name="GlowRight",
            InitCommand=function(s) s:x(18):diffusealpha(0) end,
        };
    };
};
