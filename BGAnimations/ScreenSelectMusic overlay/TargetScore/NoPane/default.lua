local pn = ...

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
    -- Hint text replacing the cycling image hints
    Def.ActorFrame{
        InitCommand=function(s) s:xy(pn==PLAYER_1 and -20 or 20,-22) end,
        Def.BitmapText{
            Font="_wheelnames 28px",
            Text="UP + LEFT",
            InitCommand=function(s)
                s:y(-8):zoom(0.7):diffuse(color("#FFFFFF")):diffusealpha(0.9)
                s:strokecolor(color("#000000"))
            end,
        },
        Def.BitmapText{
            Font="_wheelnames 28px",
            Text="CYCLE PANELS",
            InitCommand=function(s)
                s:y(12):zoom(0.5):diffuse(color("#AAAAFF")):diffusealpha(0.8)
                s:strokecolor(color("#000000"))
            end,
        },
    };
    -- Arrow indicators (simplified - just show up+left)
    Def.ActorFrame{
        InitCommand=function(s) s:xy(pn==PLAYER_1 and -70 or 70,-95) end,
        Def.ActorFrame{
            Name="UpLeftHint",
            InitCommand=function(s)
                s:queuecommand("Pulse")
            end,
            PulseCommand=function(s)
                s:diffusealpha(1):linear(1):diffusealpha(0.4):linear(1):diffusealpha(1):queuecommand("Pulse")
            end,
            Def.Sprite{
                Texture=Model().."glow",
                InitCommand=function(s) s:x(-18) end,
            };
            Def.Sprite{
                Texture=Model().."glow",
                InitCommand=function(s) s:y(-18) end,
            };
        };
    };
};
