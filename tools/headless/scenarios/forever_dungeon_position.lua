-- Dungeon Map position learning (CludesUIForeverEssentials_DungeonMap.lua,
-- Forever). A made-up but north-up line-up of the Deadmines picture with the
-- world: zoning in reads the entrance, killing Rhahk'Zor reads his pin (a
-- few yards off, as you stand beside him), and from then the map shows you
-- where you stand, a line to the next boss, an arrow and the yards. Where
-- the game hides your position (every Forever dungeon), the footer stays blank.
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

-- World position hidden (as in Forever dungeons) but the game's own dungeon
-- map gives your place on it: picture across = 0.1 + 0.8 * map x, down =
-- 0.05 + 0.8 * map y; that map is 480 by 320 yards. The same learning runs
-- on those readings.
local mx, my = 0, 0
C_Map.GetBestMapForUnit = function() return 291 end
C_Map.GetPlayerMapPosition = function()
    return { GetXY = function() return mx, my end }
end
C_Map.GetMapWorldSize = function() return 480, 320 end
local function OnMap(u, v) return (u - 0.1) / 0.8, (v - 0.05) / 0.8 end
CludesUIDB.dungeonMap.readings = nil
mx, my = OnMap(e[2], e[3])
HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD", false, false)
for _ = 1, 20 do HARNESS_ADVANCE(0.1) end
local _, _, boss2 = DM.State() -- the next boss still alive this run
mx, my = OnMap(boss2.x, boss2.y)
mx = mx + 0.005
DM.KilledEncounter(boss2.boss.encounters[1])
local _, _, stop2 = DM.State()
mx, my = OnMap(stop2.x, stop2.y)
mx, my = mx - 0.2, my + 0.1 -- 96 yards west and 32 south of it: 101 yards
DM.DrawYou()
local dot, line, arrow2, yards2 = DM.You()
OUT:write(("== map position: you shown %s, line %s, arrow %s, %s; saved under %s\n"):format(tostring(dot:IsShown()), tostring(line:IsShown()),
    tostring(arrow2:IsShown()), tostring(yards2:GetText()), tostring(next(CludesUIDB.dungeonMap.readings or {}))))
local fit1 = DM.Fit(1, "#291")
OUT:write(("== floor 1 lined up on the game's map: %s (across %.2f x + %.2f, down %.2f y + %.2f); the next boss is on floor %d, not learned yet\n"):format(
    tostring(fit1 ~= nil), fit1 and fit1.su or 0, fit1 and fit1.au or 0, fit1 and fit1.sv or 0, fit1 and fit1.av or 0, stop2.floor))
