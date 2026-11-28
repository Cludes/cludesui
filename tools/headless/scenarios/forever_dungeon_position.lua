-- Dungeon Map position learning (CludesUIForeverEssentials_DungeonMap.lua,
-- Forever). A made-up but north-up line-up of the Deadmines picture with the
-- world: zoning in reads the entrance, killing Rhahk'Zor reads his pin (a
-- few yards off, as you stand beside him), and from then the map shows you
-- where you stand, a line to the next boss, an arrow and the yards. Where
-- the game hides your position, the footer says so.
local CUI = rawget(_G, "CludesUI")
local DM = CUI._DungeonMap
if not (DM and DM.Map) then
    OUT:write("== no Dungeon Map on this client\n")
    return
end
-- The world: picture across = 0.55 - y / 600, down = 0.45 - x / 400 (3:2).
local function World(u, v) return (0.45 - v) * 400, (0.55 - u) * 600 end
local px, py, facing = 0, 0, 0
local hidden = false
UnitPosition = function()
    if hidden then return nil end
    return px, py, 0, 36
end
GetPlayerFacing = function() return facing end
IsInInstance = function() return true, "party" end
GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
CludesUIDB.dungeonMap = { enabled = true, autoShow = true }

HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD", false, false)
local map = DM.Map()
local e = map.entrance
px, py = World(e[2], e[3])
for _ = 1, 20 do HARNESS_ADVANCE(0.1) end
local function Status(label)
    DM.DrawYou()
    local dot, line, arrow, yards = DM.You()
    local fit = DM.Fit(e[1])
    OUT:write(("== %s: fit %s, you shown %s, line %s, arrow %s, %s\n"):format(label, tostring(fit ~= nil), tostring(dot and dot:IsShown()),
        tostring(line and line:IsShown()), tostring(arrow and arrow:IsShown()), tostring(yards and yards:GetText())))
end
Status("one reading (the entrance)")

-- Kill Rhahk'Zor, standing 6 yards off his pin.
local _, route = DM.State()
local first = route[1]
px, py = World(first.x, first.y)
px, py = px + 4, py - 4
DM.KilledEncounter(first.boss.encounters[1])
Status("after Rhahk'Zor")

-- Walk somewhere on the floor: the dot follows and the yards are right.
local _, _, nextStop = DM.State()
local tx, ty = World(nextStop.x, nextStop.y)
px, py = tx + 120, ty - 50
Status("130 yards from " .. nextStop.boss.name)
-- Facing the boss: the arrow points straight up the screen (art points down, so pi).
facing = math.atan2(ty - py, tx - px)
DM.DrawYou()
local _, _, arrow = DM.You()
OUT:write(("== facing the boss, arrow turned %.2f (pi = %.2f)\n"):format(arrow:GetRotation() or -1, math.pi))

-- A fresh run of the same dungeon lines up at once from the saved readings.
local saved = CludesUIDB.dungeonMap.readings
OUT:write("== readings saved for " .. tostring(next(saved or {})) .. "\n")

hidden = true
DM.Enter()
local _, _, _, yards = DM.You()
OUT:write("== position hidden: footer says " .. tostring(yards:GetText()) .. "\n")
