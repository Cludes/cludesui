-- Forever: Known Levels Instead of ?? (General > Display; Forever Essentials'
-- CludesUI.KnownHiddenLevel), which unit frames, nameplates and the tooltip ask
-- before showing "??". You are level 20. Recording: a target whose level reads
-- is noted when targeted, moused over or its nameplate shows, PvP on or off;
-- a hidden level is not noted. Lookup, for a target whose level reads -1: a
-- level the PvP feature remembers, one it only guessed, a stale one (below
-- your level + 10), the newer of PvP's and the noted one, an unknown player,
-- a level that is not hidden, the option off, the PvP feature off. Then the
-- nameplate level text.
local CUI = rawget(_G, "CludesUI")
local fn = CUI.KnownHiddenLevel
OUT:write("== lookup " .. tostring(fn ~= nil) .. "\n")
if not fn then
    return
end
local target = { name = "Gankmaster", level = -1 }
local function Stub(e)
    e.UnitExists = function(u) return u ~= nil end
    e.UnitIsPlayer = function() return true end
    e.UnitName = function(u) if u == "player" then return "Me", nil end return target.name, nil end
    e.UnitLevel = function(u) if u == "player" then return 20 end return target.level end
    -- The shown level: hidden (-1) with the real one, unless a case sets it apart.
    e.UnitEffectiveLevel = function(u)
        if u == "player" then return 20 end
        if target.effective ~= nil then return target.effective end
        return target.level
    end
end
Stub(getfenv(fn))
Stub(_G)
CludesUIDB.pvp = {
    enabled = false,
    players = {
        Gankmaster = { level = 58 },
        Guessed = { level = 30, guess = true },
        Stale = { level = 27 },
        Older = { level = 40 },
    },
    levels = { Older = { 44, time() } },
}
local function Levels()
    local keys = {}
    for k, v in pairs(CludesUIDB.pvp.levels or {}) do keys[#keys + 1] = k .. "=" .. tostring(v[1]) end
    table.sort(keys)
    return table.concat(keys, ",")
end

-- Recording (PvP off).
target.name, target.level = "Seeny", 41
HARNESS_FIRE_EVENT("PLAYER_TARGET_CHANGED")
target.name, target.level = "Hovered", 35
HARNESS_FIRE_EVENT("UPDATE_MOUSEOVER_UNIT")
target.name, target.level = "Plated", 33
HARNESS_FIRE_EVENT("NAME_PLATE_UNIT_ADDED", "nameplate1")
target.name, target.level = "Hidden", -1
HARNESS_FIRE_EVENT("PLAYER_TARGET_CHANGED")
OUT:write("== noted: " .. Levels() .. "\n")
CludesUIDB.pvp.knownLevels = false
target.name, target.level = "Ignored", 50
HARNESS_FIRE_EVENT("PLAYER_TARGET_CHANGED")
OUT:write("== noted with the option off: " .. Levels() .. "\n")
CludesUIDB.pvp.knownLevels = nil

local function Case(label, name, level)
    target.name, target.level = name, level
    OUT:write("== " .. label .. ": " .. tostring(fn("target")) .. "\n")
end
Case("pvp remembered, pvp off", "Gankmaster", -1)
Case("noted earlier", "Seeny", -1)
Case("newer of the two", "Older", -1)
Case("guessed", "Guessed", -1)
Case("stale", "Stale", -1)
Case("noted from a nameplate", "Plated", -1)
Case("unknown", "Nobody", -1)
Case("not hidden", "Gankmaster", 25)
CludesUIDB.pvp.knownLevels = false
Case("option off", "Gankmaster", -1)
CludesUIDB.pvp.knownLevels = nil
CludesUIDB.pvp.enabled = true
Case("pvp on", "Gankmaster", -1)

-- WoW Forever as measured in game: the shown (effective) level hides (-1)
-- while UnitLevel still answers. The real level wins, remembered or not;
-- a shown level that is not hidden is left alone.
target.effective = -1
Case("shown hidden, real 53, never seen", "Nobody", 53)
Case("shown hidden, real 53, remembered 58", "Gankmaster", 53)
target.effective = 44
Case("shown 44, real 53 (not hidden)", "Nobody", 53)
target.effective = -1
CludesUIDB.pvp.knownLevels = false
Case("shown hidden, real 53, option off", "Nobody", 53)
CludesUIDB.pvp.knownLevels = nil
target.effective = nil

local np = CUI._ModuleNS and CUI._ModuleNS.CludesUINameplates
if np and np.GetUnitLevelText then
    Stub(getfenv(np.GetUnitLevelText))
    target.name, target.level = "Gankmaster", -1
    OUT:write("== nameplate remembered: " .. tostring(np.GetUnitLevelText("target")) .. "\n")
    target.name = "Nobody"
    OUT:write("== nameplate unknown: " .. tostring(np.GetUnitLevelText("target")) .. "\n")
else
    OUT:write("== no nameplate text fn\n")
end
