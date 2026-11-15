-- Quickdraw: open and close the live palette in each layout (arc, fan
-- horizontal and vertical, grid), screen and cursor placement, a few frames
-- of updates (steering, alpha, slam), the timeout close, and a close with
-- nothing open. Snapshots the live frame.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIQuickdraw
local p = mod.Profile()
p.enabled = true
p.palettes[1].slots = {
    { kind = "spell", id = 133 },
    { kind = "spell", id = 116 },
    { kind = "item", id = 6948 },
    { kind = "macro", name = "Hello", body = "/wave" },
}
GetCursorPosition = function() return 900, 500 end
local frame = rawget(_G, "CUIQuickdrawFrame")
local function Frames(n)
    for _ = 1, n do
        HARNESS_ADVANCE(0.05)
        local up = frame.__scripts.OnUpdate
        if up then up(frame, 0.05) end
    end
end
local function Cycle(label)
    mod.Open(1)
    SNAP(label .. " open", frame)
    Frames(6)
    SNAP(label .. " after frames", frame)
    mod.Close()
    SNAP(label .. " closed", frame)
end

Cycle("arc cursor")
p.centerMode, p.posX, p.posY = "SCREEN", 120, -40
Cycle("arc screen")
p.centerMode = nil
p.layout, p.fanOrientation = "FAN", "HORIZONTAL"
Cycle("fan horizontal")
p.fanOrientation = "VERTICAL"
Cycle("fan vertical")
p.layout = "GRID"
Cycle("grid")
p.layout = "ARC"
-- Left open past the timeout: the palette closes itself.
mod.Open(1)
for _ = 1, 40 do
    HARNESS_ADVANCE(1)
    local up = frame.__scripts.OnUpdate
    if up then up(frame, 1) end
end
SNAP("timed out", frame)
mod.Close()
mod.Close()
SNAP("closed twice", frame)
