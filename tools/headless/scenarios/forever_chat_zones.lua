-- Chat Zones (CludesUIForeverEssentials_ChatZones.lua, Forever): a guild
-- member's zone and level tag their channel message; a stranger's whisper
-- ends in a [Where?] link; a Group Finder listing learns its members' zones;
-- an old zone is forgotten.
local CUI = rawget(_G, "CludesUI")
local CZ = CUI._ChatZones
if not CZ then
    OUT:write("== no Chat Zones on this client\n")
    return
end
UnitName = function(u) return u == "player" and "Me" or nil end
IsInGuild = function() return true end
GetNumGuildMembers = function() return 1 end
GetGuildRosterInfo = function() return "Korvath-Lightbane", "Member", 2, 25, "Warrior", "Westfall", "", "", true end
GetPlayerInfoByGUID = function() return "Warrior", "WARRIOR" end
C_ClassColor = { GetClassColor = function() return { WrapTextInColorCode = function(_, t) return "{warrior}" .. t end } end }
C_LFGList.GetSearchResultInfo = function() return { isDelisted = false, numMembers = 2 } end
C_LFGList.GetSearchResultPlayerInfo = function(_, i)
    return ({ { name = "Nessa", areaName = "Duskwood", level = 19 }, { name = "Pal", areaName = "Elwynn Forest", level = 18 } })[i]
end
C_LFGList.GetSearchResults = function() return 1, { 77 } end

CludesUIDB.chatZones = { enabled = true }
CZ.Apply()
HARNESS_FIRE_EVENT("GUILD_ROSTER_UPDATE")
local function Say(label, event, author, guid)
    local args = { CZ.TagChat(nil, event, "LFM Deadmines", author, "", "", "", "", 0, 0, "", 0, 0, guid) }
    local prefix = args[2] or "(unchanged)"
    OUT:write(("== %s: %s\n"):format(label, (prefix:gsub("|", "!"))))
end
Say("guild member in a channel", "CHAT_MSG_CHANNEL", "Korvath-Lightbane", "Player-1-AAA")
Say("stranger in a channel", "CHAT_MSG_CHANNEL", "Zed-Lightbane", "Player-1-BBB")
Say("stranger whispers", "CHAT_MSG_WHISPER", "Zed-Lightbane", "Player-1-BBB")
HARNESS_FIRE_EVENT("LFG_LIST_SEARCH_RESULTS_RECEIVED")
Say("listed in the Group Finder", "CHAT_MSG_CHANNEL", "Nessa", "Player-1-CCC")
CZ.Cfg().level = false
Say("level off", "CHAT_MSG_CHANNEL", "Nessa", "Player-1-CCC")
HARNESS_ADVANCE(16 * 60)
Say("16 minutes later", "CHAT_MSG_CHANNEL", "Nessa", "Player-1-CCC")
CZ.Cfg().enabled = false
CZ.Apply()
OUT:write("== off: known " .. tostring(CZ.Recent("Korvath") ~= nil) .. "\n")
