-- Info Bar > XP / Reputation block: XP (percent, values, plain, off), rested,
-- small XP gains (bar moves, label the same) and a gain that changes the
-- label, the right-click switch to reputation, a normal faction, a friendship,
-- a renown faction, no faction tracked, max level with XP forced, tooltips,
-- and a vertical bar. Counts drawing passes.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIDataBars

local xp = { 1000, 5000, 600 }
UnitXP = function() return xp[1] end
UnitXPMax = function() return xp[2] end
GetXPExhaustion = function() return xp[3] end
local atMax = false
IsPlayerAtEffectiveMaxLevel = function() return atMax end
IsLevelAtEffectiveMaxLevel = function() return atMax end
GetMaxLevelForPlayerExpansion = function() return atMax and 1 or 100 end
IsXPUserDisabled = function() return false end
BreakUpLargeNumbers = function(n) return tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end

local faction -- { name, reaction, min, max, cur, id }
GetWatchedFactionInfo = function()
    if faction then return unpack(faction) end
end
local friend, renown
C_GossipInfo = C_GossipInfo or {}
C_GossipInfo.GetFriendshipReputation = function(id) return id == friend and {
    friendshipFactionID = id, reactionThreshold = 8400, standing = 9000, nextThreshold = 12600 } or nil end
C_MajorFactions = C_MajorFactions or {}
C_MajorFactions.GetMajorFactionData = function(id) return id == renown and {
    renownLevelThreshold = 2500, renownReputationEarned = 1750 } or nil end
FACTION_BAR_COLORS = { [5] = { r = 0, g = 0.6, b = 0.1 }, [6] = { r = 0, g = 0.7, b = 0.3 } }

DRAWS = 0
local setFont = mod.SetFont
mod.SetFont = function(...)
    DRAWS = DRAWS + 1
    return setFont(...)
end

local bar = mod.BarsInOrder()[1] or mod.CreateBar("empty")
local b = mod.AddBlock(bar.id, "xprep")
b.settings = b.settings or {}
local function Bar() return rawget(_G, "CludesUIDataBarsBar" .. bar.id) end
local function Show(label)
    mod.ApplyBar(bar.id)
    SNAP(label, Bar())
end
local function Hit()
    local found
    local stack = { Bar() }
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "__children") then
            if f.__kind == "Button" and f.__scripts.OnEnter then found = f end
            for _, c in ipairs(f.__children) do stack[#stack + 1] = c end
        end
    end
    return found
end
local function Tip(label)
    local h = Hit()
    h.__scripts.OnEnter(h)
    SNAP(label, rawget(_G, "CludesUIDataBarsTip"))
    h.__scripts.OnLeave(h)
end

Show("xp percent")
Tip("xp tooltip")
b.settings.textDisplay = "values"
Show("xp values")
b.settings.textFormat = "plain"
Show("xp values plain")
b.settings.textFormat = nil
b.settings.textDisplay = "off"
Show("xp off")
b.settings.textDisplay = nil
Show("xp percent again")

-- Gains: three small ones (20%: label the same), then one to 21%.
local before = DRAWS
for _, v in ipairs({ 1005, 1010, 1020 }) do
    xp[1] = v
    HARNESS_FIRE_EVENT("PLAYER_XP_UPDATE", "player")
end
SNAP("xp small gains", Bar())
OUT:write("== draws for 3 gains within one percent: ", DRAWS - before, "\n")
xp[1] = 1050
HARNESS_FIRE_EVENT("PLAYER_XP_UPDATE", "player")
SNAP("xp to 21", Bar())

-- Right-click: reputation, with no faction tracked, then factions.
local h = Hit()
h.__scripts.OnClick(h, "RightButton")
SNAP("rep none tracked", Bar())
faction = { "The Assembly of the Deeps and Much Longer", 5, 3000, 9000, 4500, 2594 }
HARNESS_FIRE_EVENT("UPDATE_FACTION")
SNAP("rep normal", Bar())
Tip("rep tooltip")
before = DRAWS
faction[5] = 4510
HARNESS_FIRE_EVENT("UPDATE_FACTION")
faction[5] = 4520
HARNESS_FIRE_EVENT("UPDATE_FACTION")
OUT:write("== draws for 2 rep gains within one percent: ", DRAWS - before, "\n")
friend = 2594
HARNESS_FIRE_EVENT("UPDATE_FACTION")
SNAP("rep friendship", Bar())
friend, renown = nil, 2594
HARNESS_FIRE_EVENT("UPDATE_FACTION")
SNAP("rep renown", Bar())
renown = nil

-- Back to XP, at max level, forced: the placeholder keeps the click alive.
h = Hit()
h.__scripts.OnClick(h, "RightButton")
atMax = true
mod.ApplyBar(bar.id)
SNAP("xp forced at max", Bar())
Tip("xp forced at max tooltip")
b.settings.mode = nil
Show("auto at max shows rep")
atMax = false

bar.orientation = "V"
Show("xprep vertical")
bar.orientation = "H"
mod.ApplyBar(bar.id)
