-- Info Bar > Audio block: each channel, mute (the channel, then master), no
-- icon, hover and tooltip, the mouse wheel (and Shift), a drag on the bar,
-- the wheel at the limits, and a vertical bar. Counts volume writes, which
-- should not grow when nothing changes.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIDataBars

local cvars = {
    Sound_MasterVolume = "0.5", Sound_SFXVolume = "0.8", Sound_MusicVolume = "0.3",
    Sound_AmbienceVolume = "0.6", Sound_DialogVolume = "1",
    Sound_EnableAllSound = "1", Sound_EnableSFX = "1", Sound_EnableMusic = "1",
    Sound_EnableAmbience = "1", Sound_EnableDialog = "1",
}
WRITES = 0
GetCVar = function(k) return cvars[k] end
GetCVarBool = function(k) return cvars[k] == "1" end
SetCVar = function(k, v)
    WRITES = WRITES + 1
    cvars[k] = tostring(v)
    HARNESS_FIRE_EVENT("CVAR_UPDATE", k, tostring(v)) -- the client fires it as the write happens
end
local shift = false
IsShiftKeyDown = function() return shift end
GetCursorPosition = function() return 150, 0 end

local bar = mod.BarsInOrder()[1] or mod.CreateBar("empty")
local b = mod.AddBlock(bar.id, "audio")
local function Bar() return rawget(_G, "CludesUIDataBarsBar" .. bar.id) end
local function Show(label)
    mod.ApplyBar(bar.id)
    SNAP(label, Bar())
end
local function Find(test)
    local found
    local stack = { Bar() }
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "__children") then
            if f.__shown and test(f) then found = f end
            for _, c in ipairs(f.__children) do stack[#stack + 1] = c end
        end
    end
    return found
end
local function Main() return Find(function(f) return f.__kind == "Button" and f.__scripts.OnMouseWheel end) end
local function Hit() return Find(function(f) return f.__kind == "Button" and f.__scripts.OnMouseDown end) end

Show("audio master")
for _, ch in ipairs({ "sfx", "music", "ambience", "dialog", "master" }) do
    b.settings.channel = ch
    Show("audio " .. ch)
end
b.settings.showIcon = false
Show("audio no icon")
b.settings.showIcon = true
Show("audio icon back")

local main = Main()
main.__scripts.OnEnter(main)
SNAP("audio hovered", Bar())
SNAP("audio tooltip", rawget(_G, "CludesUIDataBarsTip"))
main.__scripts.OnLeave(main)
SNAP("audio left", Bar())

-- Wheel: up 1%, Shift up 10%, down past 0.
main.__scripts.OnMouseWheel(main, 1)
SNAP("audio wheel up", Bar())
shift = true
main.__scripts.OnMouseWheel(main, 1)
shift = false
SNAP("audio shift wheel up", Bar())
cvars.Sound_MasterVolume = "0"
mod.ApplyBar(bar.id)
local before = WRITES
main.__scripts.OnMouseWheel(main, -1)
OUT:write("== wheel down at 0%: volume ", cvars.Sound_MasterVolume, "\n")
SNAP("audio wheel at zero", Bar())

-- Drag: press on the bar, hold for a few frames without moving, release.
local hit = Hit()
hit.__scripts.OnMouseDown(hit, "LeftButton")
for _ = 1, 5 do
    local up = hit.__scripts.OnUpdate
    if up then up(hit, 0.02) end
end
hit.__scripts.OnMouseUp(hit, "LeftButton")
OUT:write("== drag: volume ", cvars.Sound_MasterVolume, "\n")
SNAP("audio after drag", Bar())

-- Mute the channel (click), then master off with another channel selected.
main.__scripts.OnClick(main, "LeftButton")
SNAP("audio muted", Bar())
main.__scripts.OnClick(main, "LeftButton")
b.settings.channel = "music"
cvars.Sound_EnableAllSound = "0"
Show("audio master off")
main = Main()
main.__scripts.OnEnter(main)
SNAP("audio master off tooltip", rawget(_G, "CludesUIDataBarsTip"))
main.__scripts.OnLeave(main)
cvars.Sound_EnableAllSound = "1"

bar.orientation = "V"
Show("audio vertical")
bar.orientation = "H"
mod.ApplyBar(bar.id)
OUT:write("== volume writes in total: ", WRITES, "\n")
