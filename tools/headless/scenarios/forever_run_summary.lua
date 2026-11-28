-- Instance Tracker run summary (CludesUIForeverEssentials_InstanceTracker.lua,
-- Forever): a 20 minute Deadmines visit with two boss kills, 5,000 XP of a
-- 10,000 XP level, 3 gold looted and two items prints one summary line with
-- the bosses, the share of a level, the XP an hour and the gold; the stored
-- run keeps the bosses and gold.
local CUI = rawget(_G, "CludesUI")
local IT = CUI._InstanceTracker
if not IT then
    OUT:write("== no Instance Tracker on this client\n")
    return
end
local inside, xp, money = false, 1000, 50000
IsInInstance = function() return inside, inside and "party" or "none" end
GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 end
UnitXP = function() return xp end
UnitXPMax = function() return 10000 end
GetMoney = function() return money end
UnitGUID = function() return "Player-1-ME" end
UnitIsDeadOrGhost = function() return false end
-- The fake client's formatters answer 0; these stand in for the game's.
BreakUpLargeNumbers = function(n)
    local s = tostring(math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
GetCoinTextureString = function(c) return ("%dg %ds %dc"):format(c / 10000, (c % 10000) / 100, c % 100) end
-- (Items stay 0 here: the loot line prefix is read from the game's string at load.)
local said = {}
local oldPrint = CUI.Print
CUI.Print = function(t) said[#said + 1] = (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]*|t", "")) end

CludesUIDB.instanceTracker = { enabled = true, summary = true }
IT.Apply()
inside = true
HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD", false, false)
HARNESS_ADVANCE(0.5)
xp = 3500
HARNESS_FIRE_EVENT("PLAYER_XP_UPDATE", "player")
HARNESS_FIRE_EVENT("ENCOUNTER_END", 2741, "Rhahk'Zor", 1, 5, 1)
HARNESS_FIRE_EVENT("ENCOUNTER_END", 2742, "Sneed", 1, 5, 0)
HARNESS_FIRE_EVENT("ENCOUNTER_END", 2742, "Sneed", 1, 5, 1)
xp = 6000
HARNESS_FIRE_EVENT("PLAYER_XP_UPDATE", "player")
HARNESS_FIRE_EVENT("CHAT_MSG_LOOT", (LOOT_SELF or "You receive loot: ") .. "[Thin Cloth]")
HARNESS_FIRE_EVENT("CHAT_MSG_LOOT", (LOOT_SELF or "You receive loot: ") .. "[Linen Cloth]")
money = 80000
-- Twenty minutes later, out.
local realTime = time
time = function() return realTime() + 1200 end
wipe(said)
inside = false
HARNESS_FIRE_EVENT("PLAYER_ENTERING_WORLD", false, false)
HARNESS_ADVANCE(0.5)
time = realTime
for _, line in ipairs(said) do OUT:write("== said: " .. line .. "\n") end
local runs = IT.Runs and IT.Runs() or {}
local last = runs[1]
OUT:write(("== stored: bosses %s, money %s, xp %s\n"):format(tostring(last and last.bosses), tostring(last and last.money), tostring(last and last.xp)))
CUI.Print = oldPrint
