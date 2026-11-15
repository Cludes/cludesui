-- Info Bar > Time Played block: the /played reply, this level vs total, the
-- tooltip with saved characters on two realms, the minute heartbeat (over and
-- under a day), a change during combat and the pass when it ends, a level-up,
-- and a vertical bar. Counts layout passes, which should not grow when the
-- shown text does not change.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIDataBars

local played = { 3 * 86400 + 5 * 3600 + 120, 3600 + 30 * 60 }
CUI.RequestTimePlayed = function() return played[1], played[2] end
local combat = false
InCombatLockdown = function() return combat end
-- Below max level, so "this level" is shown unless the setting asks for the total.
IsPlayerAtEffectiveMaxLevel = function() return false end
IsLevelAtEffectiveMaxLevel = function() return false end
GetMaxLevelForPlayerExpansion = function() return 100 end
UnitXP = function() return 1000 end -- the XP bar shows below max level too
UnitXPMax = function() return 5000 end

CludesUIDB = CludesUIDB or {}
CludesUIDB.timePlayedChars = {
    ["Player-2-00000002"] = { name = "Altone", realm = "Zeta", class = "MAGE", level = 80, total = 9 * 86400 },
    ["Player-2-00000003"] = { name = "Alttwo", realm = "Alpha", class = "ROGUE", level = 12, total = 7200 },
    ["Player-2-00000004"] = { name = "Altthree", realm = "Zeta", class = "PRIEST", level = 80, total = 40 * 86400 },
}

LAYOUTS = 0
local snap = mod.SnapToPixelGrid
mod.SnapToPixelGrid = function(...)
    LAYOUTS = LAYOUTS + 1
    return snap(...)
end

local bar = mod.BarsInOrder()[1] or mod.CreateBar("empty")
local b = mod.AddBlock(bar.id, "timeplayed")
b.settings = b.settings or {}
local function Bar() return rawget(_G, "CludesUIDataBarsBar" .. bar.id) end
local function Show(label)
    mod.ApplyBar(bar.id)
    SNAP(label, Bar())
end
local function Hoverable()
    local found
    local stack = { Bar() }
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and f["\0scripts"].OnEnter and f["\0shown"] then found = f end
            for _, c in ipairs(f["\0children"]) do stack[#stack + 1] = c end
        end
    end
    return found
end

Show("played level")
b.settings.alwaysTotal = true
Show("played total")
b.settings.alwaysTotal = false
Show("played level again")

local h = Hoverable()
h["\0scripts"].OnEnter(h)
SNAP("played hovered", Bar())
SNAP("played tooltip", rawget(_G, "CludesUIDataBarsTip"))
h["\0scripts"].OnLeave(h)
SNAP("played left", Bar())

-- The heartbeat: minutes roll over (under a day, the text changes)...
local before = LAYOUTS
for _ = 1, 125 do
    HARNESS_ADVANCE(1)
end
SNAP("played +2 min", Bar())
OUT:write("== layouts over 2 min at the level time: ", LAYOUTS - before, "\n")
-- ...and over a day (total shown, hours only, so most minutes change nothing).
b.settings.alwaysTotal = true
mod.ApplyBar(bar.id)
before = LAYOUTS
for _ = 1, 600 do
    HARNESS_ADVANCE(1)
end
SNAP("played total +10 min", Bar())
OUT:write("== layouts over 10 min at the total: ", LAYOUTS - before, "\n")
b.settings.alwaysTotal = false
mod.ApplyBar(bar.id)

-- Combat: the minute changes the text only; the layout follows on regen.
combat = true
for _ = 1, 60 do
    HARNESS_ADVANCE(1)
end
SNAP("played in combat", Bar())
combat = false
HARNESS_FIRE_EVENT("PLAYER_REGEN_ENABLED")
SNAP("played after combat", Bar())

HARNESS_FIRE_EVENT("PLAYER_LEVEL_UP", 91)
SNAP("played level up", Bar())
local me = CludesUIDB.timePlayedChars["Player-1-00000001"]
OUT:write("== saved: ", tostring(me and me.level), " ", tostring(me and math.floor(me.total)), "\n")

bar.orientation = "V"
Show("played vertical")
bar.orientation = "H"
mod.ApplyBar(bar.id)
