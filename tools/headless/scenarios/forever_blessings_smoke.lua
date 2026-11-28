-- Paladin Blessings (CludesUIForeverEssentials_Blessings.lua, Forever), a
-- smoke run as a paladin in a party: on, the bar and window build, the class
-- list and a class blessing read back, roster, aura and addon whisper events
-- go through, it ticks and turns off, all without an error.
local CUI = rawget(_G, "CludesUI")
local BL = CUI._Blessings
if not BL then
    OUT:write("== no Blessings on this client\n")
    return
end
IsInGroup = function() return true end
GetNumSubgroupMembers = function() return 2 end
CludesUIDB.blessings = { enabled = true }
OUT:write("== on: bar built in the fake client " .. tostring(pcall(BL.Apply)) .. "\n")
-- The window's cells sit on the game's secure group headers, which the fake
-- client cannot build (no child buttons): opening it is tried, not required.
local opened = pcall(BL.Open)
OUT:write("== window opened in the fake client " .. tostring(opened) .. "\n")
for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED" }) do
    HARNESS_FIRE_EVENT(ev)
end
HARNESS_FIRE_EVENT("UNIT_AURA", "player")
HARNESS_FIRE_EVENT("CHAT_MSG_ADDON", "PLPWR", "REQ", "PARTY", "Other-Realm")
for _ = 1, 20 do HARNESS_ADVANCE(0.25) end
OUT:write(("== blessings listed %d, spell name of the first %s\n"):format(#(BL.Blessings or {}),
    tostring(BL.Blessings and BL.Blessings[1] and BL.SpellName and BL.SpellName(BL.Blessings[1].key) ~= nil)))
OUT:write("== warrior blessing " .. tostring(BL.ClassBlessing("WARRIOR")) .. "\n")
CludesUIDB.blessings.enabled = false
BL.Apply()
OUT:write("== blessings off\n")
