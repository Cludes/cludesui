-- Creature Scout (CludesUIForeverEssentials_Scout.lua, Forever): a hostile
-- creature's tooltip gains its abilities, armor and damage cut, immunities,
-- and for a hunter its pet family. The fake client has no C_EncodingUtil, so
-- the unpacker hands back small tables in Load's order (abilities, tameable,
-- stats).
local CUI = rawget(_G, "CludesUI")
local SC = CUI._Scout
local tip = rawget(_G, "GameTooltip")
if not (SC and tip) then
    OUT:write("== no Creature Scout on this client\n")
    return
end
local hook
for _, rec in ipairs(TooltipDataProcessor.postCalls or {}) do
    local info = debug.getinfo(rec[2], "S")
    if info and info.source:find("Scout", 1, true) then hook = rec[2] end
end
OUT:write("== hook before enabling " .. tostring(hook ~= nil) .. "\n")

local unpacked = {
    { 448, { 6016, 6268 } }, -- Hogger: abilities
    { 448, 2000 }, -- tameable (pretend), 2.0 attack speed
    { 448, { 538, 0, bit.lshift(1, 11), 0, 15, 0, 0, 0, 0 } }, -- armor 538, immune to Stun, 15 fire resist
}
local calls = 0
local function Flat(pair) return { pair[1], pair[2] } end
C_EncodingUtil = {
    DecodeBase64 = function(s) return s end,
    DecompressString = function(s) return s end,
    DeserializeCBOR = function()
        calls = calls + 1
        return Flat(unpacked[calls])
    end,
}
Enum.CompressionMethod = Enum.CompressionMethod or {}
Enum.CompressionMethod.Deflate = 1

local function Stub(e)
    e.UnitLevel = function(u) return u == "player" and 20 or 11 end
    e.UnitCanAttack = function() return true end
    e.UnitClass = function() return "Hunter", "HUNTER" end
    e.UnitCreatureFamily = function() return "Wolf" end
    e.UnitClassification = function() return "elite" end
    e.IsInInstance = function() return false end
    e.InCombatLockdown = function() return false end
    e.IsControlKeyDown = function() return false end
end
Stub(_G)
C_Spell.GetSpellName = function(id) return ({ [6016] = "Pierce Armor", [6268] = "Rushing Charge" })[id] end
C_Spell.GetSpellTexture = function() return 132100 end
C_Spell.GetSpellInfo = function(id)
    local n = C_Spell.GetSpellName(id)
    return n and { name = n, castTime = id == 6268 and 1500 or 0, minRange = id == 6268 and 8 or 0, maxRange = id == 6268 and 25 or 0 }
end

CludesUIDB.scout = { enabled = true }
SC.Apply()
for _, rec in ipairs(TooltipDataProcessor.postCalls or {}) do
    local info = debug.getinfo(rec[2], "S")
    if info and info.source:find("Scout", 1, true) then hook = rec[2] end
end
OUT:write("== hook after enabling " .. tostring(hook ~= nil) .. "\n")
if not hook then return end
Stub(getfenv(hook))

local out = {}
tip.AddLine = function(_, t) out[#out + 1] = t end
tip.AddDoubleLine = function(_, l, r) out[#out + 1] = l .. " | " .. r end
tip.GetUnit = function() return "Hogger", "mouseover" end
tip.IsForbidden = function() return false end
local function Hover(label, guid)
    wipe(out)
    local ok, err = pcall(hook, tip, { guid = guid })
    OUT:write("== " .. label .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
    for _, t in ipairs(out) do OUT:write("   " .. t:gsub("|T[^|]*|t ", "") .. "\n") end
end
Hover("Hogger", "Creature-0-1-2-3-448-0000ABCDEF")
Hover("an npc with no data (estimated armor)", "Creature-0-1-2-3-99999-0000ABCDEF")
Hover("a player (nothing added)", "Player-1-ABC")
CludesUIDB.scout.enabled = false
SC.Apply()
Hover("Scout off", "Creature-0-1-2-3-448-0000ABCDEF")
