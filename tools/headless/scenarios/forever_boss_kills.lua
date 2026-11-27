-- Boss Kill History (CludesUIForeverEssentials_BossKills.lua, Forever): an
-- encounter's pull and kill record a kill with its length and group; a faster
-- kill is a new best; a wipe records nothing; the summary and latest kills
-- read back for the Journal and the Dungeon Map.
local CUI = rawget(_G, "CludesUI")
local BK = CUI._BossKills
if not BK then
    OUT:write("== no Boss Kill History on this client\n")
    return
end
UnitName = function(u)
    if u == "player" then return "Me" end
    if u == "party1" then return "Tanky" end
    if u == "party2" then return "Healz" end
end
GetRealmName = function() return "Lightbane" end
local printed = {}
local oldPrint = CUI.Print
CUI.Print = function(t) printed[#printed + 1] = t end
local boss = { name = "Rhahk'Zor", encounters = { 2741 } }
local function Fight(seconds, success)
    HARNESS_FIRE_EVENT("ENCOUNTER_START", 2741, "Rhahk'Zor", 1, 5)
    HARNESS_ADVANCE(seconds)
    HARNESS_FIRE_EVENT("ENCOUNTER_END", 2741, "Rhahk'Zor", 1, 5, success)
end
local function Report(label)
    OUT:write(("== %s: %s\n"):format(label, tostring(BK.Summary(boss))))
    for _, line in ipairs(BK.Recent(boss, 3)) do OUT:write("   " .. line .. "\n") end
end
Report("before any kill")
Fight(95, 1)
Report("first kill, 95s")
Fight(60, 0)
Report("a wipe")
Fight(72, 1)
Report("second kill, 72s")
OUT:write("== chat: " .. table.concat(printed, " / "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "\n")
BK.Cfg().enabled = false
BK.Apply()
Report("history off")
BK.Cfg().enabled = true
BK.Apply()
BK.Forget()
Report("forgotten")
CUI.Print = oldPrint
