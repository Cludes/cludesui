-- Forever: CludesUI.KnownHiddenLevel (the PvP feature), which unit frames,
-- nameplates and the tooltip ask before showing "??". A target is a player
-- 20 levels above you, its level hidden (-1); the cases: a level the feature
-- remembers, one only guessed, a stale one (below your level + 10), an
-- unknown player, a level that is not hidden, the option off, the feature
-- off. Then the nameplate level text for the remembered player.
local CUI = rawget(_G, "CludesUI")
local fn = CUI.KnownHiddenLevel
OUT:write("== lookup " .. tostring(fn ~= nil) .. "\n")
if not fn then
    return
end
local env = getfenv(fn)
local target = { name = "Gankmaster", level = -1 }
local function Stub(e)
    e.UnitExists = function(u) return u == "target" or u == "player" end
    e.UnitIsPlayer = function() return true end
    e.UnitName = function(u) if u == "target" then return target.name, nil end return "Me", nil end
    e.UnitLevel = function(u) if u == "target" then return target.level end return 20 end
    e.UnitEffectiveLevel = e.UnitLevel
end
Stub(env)
Stub(_G)
CludesUIDB.pvp = {
    enabled = true,
    players = {
        Gankmaster = { level = 58 },
        Guessed = { level = 30, guess = true },
        Stale = { level = 27 },
    },
}
local function Case(label, name, level)
    target.name, target.level = name, level
    OUT:write("== " .. label .. ": " .. tostring(fn("target")) .. "\n")
end
Case("remembered", "Gankmaster", -1)
Case("guessed", "Guessed", -1)
Case("stale", "Stale", -1)
Case("unknown", "Nobody", -1)
Case("not hidden", "Gankmaster", 25)
CludesUIDB.pvp.knownLevels = false
Case("option off", "Gankmaster", -1)
CludesUIDB.pvp.knownLevels = nil
CludesUIDB.pvp.enabled = false
Case("feature off", "Gankmaster", -1)
CludesUIDB.pvp.enabled = true

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
