-- Info Bar > Great Vault block (retail): the label and icon, the tooltip's
-- reward rows (done, partial, empty), the player's keystone, party keystones
-- arriving over LibKeystone (exact and short names, a stranger ignored), a
-- member leaving, hover, and a vertical bar. Counts draws.
local H = dofile("tools/headless/scenarios/_common.lua")
H.OUT = OUT
local lib = LibStub("LibKeystone", true)
local feed
REQUESTS = 0
if lib then
    lib.Register = function(_, fn) feed = fn end
    lib.Request = function() REQUESTS = REQUESTS + 1 end
end
C_WeeklyRewards.GetActivities = function(t)
    if t == 3 then return { { index = 1, progress = 2, threshold = 2 }, { index = 2, progress = 2, threshold = 4 }, { index = 3, progress = 2, threshold = 6 } } end
    if t == 1 then return { { index = 1, progress = 8, threshold = 1, level = 12 }, { index = 2, progress = 8, threshold = 4, level = 10 }, { index = 3, progress = 8, threshold = 8, level = 9 } } end
    return {}
end
C_MythicPlus.GetOwnedKeystoneChallengeMapID = function() return 503 end
C_MythicPlus.GetOwnedKeystoneLevel = function() return 11 end
local MAPS = { [503] = "Ara-Kara", [505] = "The Dawnbreaker", [499] = "Priory" }
C_ChallengeMode.GetMapUIInfo = function(id) return MAPS[id] end
local group = { "Alpha", "Bravo-OtherRealm" }
IsInGroup = function() return #group > 0 end
IsInRaid = function() return false end
GetNumGroupMembers = function() return #group + 1 end
GetUnitName = function(u) local i = tonumber(u:match("party(%d)")) return i and group[i] end
UnitExists = function(u) return GetUnitName(u) ~= nil end
UnitIsUnit = function() return false end
UnitClass = function(u) return "Mage", u == "party1" and "MAGE" or "PRIEST" end

local b = H.Block("greatvault")
H.Show("vault")
if feed then
    feed(14, 505, nil, "Alpha-TestRealm")
    feed(9, 499, nil, "Bravo-OtherRealm")
    feed(20, 503, nil, "Stranger-Realm")
end
H.Hover("vault hover")
H.Count("hover and leave", function()
    local h = H.Buttons()[1]
    h.__scripts.OnEnter(h)
    h.__scripts.OnLeave(h)
end)
group[2] = nil
HARNESS_FIRE_EVENT("GROUP_ROSTER_UPDATE")
H.Hover("vault after leave")
OUT:write("== key requests: ", REQUESTS, "\n")
H.Vertical("vault vertical")
