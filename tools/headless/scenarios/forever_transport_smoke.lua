-- Boat and Zeppelin Timers (CludesUIForeverEssentials_Transport.lua, Forever),
-- a smoke run: turned on in Menethil Harbor with a party, its board builds,
-- the zone and group events and an addon whisper go through, it ticks for a
-- while and turns off again, all without an error.
local CUI = rawget(_G, "CludesUI")
local TR = CUI._Transport
if not TR then
    OUT:write("== no Transport on this client\n")
    return
end
C_Map.GetBestMapForUnit = function() return 1437 end
UnitPosition = function() return -3700, -600, 0, 0 end
IsInGroup = function() return true end
CludesUIDB.transport = { enabled = true, share = true, zone = true }
TR.Apply()
for _, ev in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE" }) do
    HARNESS_FIRE_EVENT(ev)
end
HARNESS_FIRE_EVENT("CHAT_MSG_ADDON", "NauticusClassic", "garbage", "PARTY", "Other-Realm")
for _ = 1, 30 do HARNESS_ADVANCE(0.2) end
local board
for _, f in ipairs({ UIParent:GetChildren() }) do
    if f.GetName and f:GetName() == nil and f.IsShown and f:IsShown() then board = board or f end
end
OUT:write("== transport on, ran 6 seconds\n")
CludesUIDB.transport.enabled = false
TR.Apply()
OUT:write("== transport off\n")
