-- WoW Forever Auras, Buffs & Consumables page with custom spells (one with
-- classes unticked, an odd count so the last row has a blank) and two spell
-- groups (one empty), then with a custom spell, a group spell and the empty
-- group gone. Run it as a Mage too for the class-only rows.
local CUI = rawget(_G, "CludesUI")
local db = rawget(_G, "_CUABR_AceDB")
local f = db and db.profile and db.profile.forever
if f then
    f.customIDs = { 1126, 467, 21562 }
    f.customClasses = { [467] = { WARRIOR = false, MAGE = false } }
    f.customGroups = { { name = "Armors", ids = { 168, 7302, 6117 } }, { name = "Empty", ids = {} } }
end
-- The page was built before the lists were set: leave, drop the cache, come back.
local function Rebuild()
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIAuraBuffReminders")
    CUI:SelectPage("Auras, Buffs & Consumables")
end
Rebuild()
SNAP("forever page", CUI._scrollFrame)
if f then
    table.remove(f.customIDs, 3)
    table.remove(f.customGroups[1].ids, 1)
    f.customGroups[2] = nil
    Rebuild()
    SNAP("forever page shrunk", CUI._scrollFrame)
end
