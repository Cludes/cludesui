-- Info Bar > Micro Menu block: the default strip, guild and social counters,
-- hover tint, roster events (same count, then a change), and a vertical bar.
local H = dofile("tools/headless/scenarios/_common.lua")
H.OUT = OUT
local guild, friends = 12, 3
IsInGuild = function() return true end
GetNumGuildMembers = function() return 40, guild end
BNGetNumFriends = function() return 10, friends end
C_FriendList.GetNumOnlineFriends = function() return 1 end
local b = H.Block("micromenu")
H.b.settings.guild, H.b.settings.social = true, true
H.Show("micromenu")
H.Hover("micromenu hover", 1)
H.Count("roster events, same counts", function()
    for _ = 1, 3 do HARNESS_FIRE_EVENT("GUILD_ROSTER_UPDATE") end
    HARNESS_FIRE_EVENT("FRIENDLIST_UPDATE")
end)
guild = 13
HARNESS_FIRE_EVENT("GUILD_ROSTER_UPDATE")
friends = 4
HARNESS_FIRE_EVENT("BN_FRIEND_ACCOUNT_ONLINE")
SNAP("micromenu counts changed", H.Bar())
H.Vertical("micromenu vertical")
