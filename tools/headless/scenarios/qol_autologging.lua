-- QoL > Auto Combat Logging: every zone kind (raid difficulties, LFR, a low
-- current raid ID, M+ and mythic dungeons, a legacy one, scenarios, arenas,
-- rated and Blitz battlegrounds, the open world), the delayed stop and its
-- cancel, the immediate stop, notify, a manual log left alone, the feature
-- switched off mid-instance, and zone events. Records every logging call.
local CUI = rawget(_G, "CludesUI")
local logging = false
CALLS = {}
LoggingCombat = function(v)
    if v ~= nil then
        CALLS[#CALLS + 1] = "log " .. tostring(v)
        logging = v
    end
    return logging
end
local cvars = { advancedCombatLogging = "0" }
GetCVar = function(k) return cvars[k] end
CUI.SetCVar = function(k, v) CALLS[#CALLS + 1] = "cvar " .. k .. "=" .. tostring(v); cvars[k] = tostring(v) end
local printed = {}
CUI.Print = function(m) CALLS[#CALLS + 1] = "print " .. m end
local zone = { "World", "none", 0, "", 5, 0, false, 0 }
GetInstanceInfo = function() return unpack(zone) end
local rbg, blitz = false, false
C_PvP.IsRatedBattleground = function() return rbg end
C_PvP.IsRatedSoloRBG = function() return blitz end
CludesUIDB = CludesUIDB or {}
CludesUIDB.autoLogging = { enabled = true }
local c = CludesUIDB.autoLogging
-- One second at a time: a long jump runs out of the harness's timer budget.
local function Wait(n) for _ = 1, n do HARNESS_ADVANCE(1) end end
local function At(label, kind, diff, mapID, cap)
    zone = { label, kind, diff or 0, "", cap or 5, 0, false, mapID or 0 }
    CALLS = {}
    _CUI_AutoLogging_Check()
    OUT:write("== ", label, ": ", table.concat(CALLS, ", "), " (logging ", tostring(logging), ")\n")
end
At("open world", "none")
At("mythic raid", "raid", 16, 2800)
At("world again (delayed stop)", "none")
Wait(31)
OUT:write("== after 31s: logging ", tostring(logging), " ", table.concat(CALLS, ", "), "\n")
At("flex mythic raid", "raid", 233, 2800)
At("heroic raid", "raid", 15, 2800)
c.delaystop = false
At("world (immediate stop)", "none")
c.delaystop = nil
At("normal raid", "raid", 14, 2800)
At("lfr", "raid", 17, 2800)
At("timewalking raid", "raid", 33, 2800)
At("old raid", "raid", 14, 1000)
At("sporefall", "raid", 15, 1592)
At("keystone", "party", 23, 2700)
At("mythic dungeon", "party", 8, 2700)
At("heroic dungeon", "party", 2, 2700)
At("motherlode keystone", "party", 23, 1594)
At("old keystone", "party", 23, 500)
At("scenario solo", "scenario", 0, 2000, 1)
c.logScenario = true
At("scenario group", "scenario", 0, 2000, 3)
c.notify = true
At("arena", "arena", 0, 2000)
At("world, notify", "none")
Wait(5)
At("back in arena within the delay", "arena", 0, 2000)
Wait(31)
OUT:write("== the cancelled stop: logging ", tostring(logging), "\n")
c.notify = nil
At("unrated bg", "pvp", 0, 2000)
rbg = true
c.logRBG = true
At("rated bg", "pvp", 0, 2000)
blitz = true
At("blitz (off)", "pvp", 0, 2000)
rbg, blitz = false, false
-- A log the player started by hand is never stopped.
logging = false
At("world", "none")
logging = true
At("world, manual log", "none")
Wait(31)
OUT:write("== manual log kept: ", tostring(logging), "\n")
-- Switched off inside an instance.
logging = false
At("mythic raid", "raid", 16, 2800)
c.enabled = false
At("feature off in the raid", "raid", 16, 2800)
Wait(31)
OUT:write("== after off: logging ", tostring(logging), "\n")
c.enabled = true
_CUI_AutoLogging_Check()
zone = { "Raid", "raid", 16, "", 20, 0, false, 2800 }
CALLS = {}
HARNESS_FIRE_EVENT("ZONE_CHANGED_NEW_AREA")
Wait(3)
OUT:write("== zone event: ", table.concat(CALLS, ", "), "\n")
