-- Looking For Group (CludesUIForeverEssentials_LFG.lua + LFGWindow.lua,
-- Forever): a card survives encode and decode; a search reads Forever's
-- listings (leader, zone, roles, dungeon); a leader's card arrives and shows
-- on their row; while listed, a card request is answered and an application
-- is received and acknowledged; each tab paints.
local CUI = rawget(_G, "CludesUI")
local LF = CUI._LFG
if not (LF and LF.GF) then
    OUT:write("== no Looking For Group on this client\n")
    return
end
local GF = LF.GF
local Card, Comms, Listings = GF.Card, GF.Comms, GF.Listings

local sentMsgs = {}
C_ChatInfo.SendAddonMessage = function(prefix, text, channel, target)
    sentMsgs[#sentMsgs + 1] = ("%s %s -> %s: %s"):format(prefix, channel, target, text)
    return 0
end
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ChatInfo.InChatMessagingLockdown = function() return false end
C_FriendList.IsIgnored = function() return false end
UnitName = function(u) return u == "player" and "Me" or nil end
GetUnitName = function() return "Me" end
UnitLevel = function() return 20 end
UnitClass = function() return "Warrior", "WARRIOR", 1 end
UnitFactionGroup = function() return "Alliance" end
GetClassInfo = function(id) return "Warrior", "WARRIOR", id end
C_LFGListRoles = { GetRoles = function() return { tank = true, healer = false, dps = true } end }

local listed = false
C_LFGList.HasActiveEntryInfo = function() return listed end
C_LFGList.GetActiveEntryInfo = function() return listed and { activityIDs = { 801 } } or nil end
C_LFGList.GetAvailableCategories = function() return { 2 } end
C_LFGList.GetAvailableActivities = function() return { 801, 802 } end
C_LFGList.GetActivityInfoTable = function(id)
    if id == 801 then return { fullName = "The Deadmines", shortName = "Deadmines", minLevelSuggestion = 17, maxLevelSuggestion = 26, maxNumPlayers = 5 } end
    return { fullName = "Wailing Caverns", shortName = "WC", minLevelSuggestion = 15, maxLevelSuggestion = 25, maxNumPlayers = 5 }
end
local searched
C_LFGList.Search = function(...) searched = select("#", ...) end
C_LFGList.GetFilteredSearchResults = function() return 2, { 11, 12 } end
C_LFGList.GetSearchResultInfo = function(id)
    if id == 11 then return { leaderName = "Korvath", numMembers = 3, age = 600, isDelisted = false, activityIDs = { 801 } } end
    return { leaderName = "Nessa", numMembers = 1, age = 30, isDelisted = false, activityIDs = { 802 } }
end
C_LFGList.GetSearchResultMemberCounts = function(id) return id == 11 and { TANK = 1, HEALER = 0, DAMAGER = 2 } or { TANK = 0, HEALER = 1, DAMAGER = 0 } end
C_LFGList.GetSearchResultPlayerInfo = function(id, i)
    if id == 11 then
        return ({ { name = "Korvath", level = 25, classFilename = "WARRIOR", isLeader = true, areaName = "Westfall", lfgRoles = { tank = true } },
            { name = "Pal", level = 22, classFilename = "PALADIN", isLeader = false, lfgRoles = { dps = true } },
            { name = "Rog", level = 21, classFilename = "ROGUE", isLeader = false, lfgRoles = { dps = true } } })[i]
    end
    return i == 1 and { name = "Nessa", level = 19, classFilename = "PRIEST", isLeader = true, areaName = "Duskwood", lfgRoles = { healer = true } } or nil
end

-- A card round trip.
local card = Card.New()
card.class, card.level, card.roles, card.score, card.dungeon = 1, 20, Card.TANK + Card.DAMAGE, 189, "Deadmines"
card.hasKills, card.nKills, card.kills = true, 3, { 3, 2, 0 }
card.hasQuests, card.nHave, card.nNeed, card.have, card.need = true, 1, 1, { 168 }, { 214 }
local text = Card.Application(42, card, "LF tank, need quests")
OUT:write("== application: " .. tostring(text) .. "\n")
local back = Card.New()
local kind, id, note = Card.Decode(text, back)
OUT:write(("== decoded: %s %s %s, level %d, score %s, kills %d,%d,%d, quests %d/%d\n"):format(kind, id, note, back.level,
    back.score, back.kills[1], back.kills[2], back.kills[3], back.nHave, back.nNeed))
OUT:write("== junk decodes: " .. tostring(Card.Decode("1 A 0 x", back)) .. " " .. tostring(Card.Decode("2 K 5", back)) .. "\n")

-- Open the window: turns it on and searches.
LF.Show()
OUT:write("== on " .. tostring(LF.Get("enabled")) .. ", search sent " .. tostring(searched ~= nil) .. ", state " .. GF.Search.state .. "\n")
HARNESS_FIRE_EVENT("LFG_LIST_SEARCH_RESULTS_RECEIVED")
HARNESS_ADVANCE(0.1)
local n = Listings.Read(true)
for i = 1, n do
    local e = Listings.entries[i]
    OUT:write(("   listing %s: %s, %s, T%d H%d D%d, %d members, leader zone %s\n"):format(e.id, tostring(e.leader),
        tostring(e.dungeon), e.tanks, e.healers, e.damage, e.numMembers, tostring(e.members[1] and e.members[1].zone)))
end
HARNESS_ADVANCE(2)
OUT:write("== card requests sent:\n")
for _, m in ipairs(sentMsgs) do OUT:write("   " .. m .. "\n") end

-- Korvath answers with his listing's card.
local nonce = tonumber(sentMsgs[1] and sentMsgs[1]:match("1 Q (%d+)"))
local reply = Card.Reply(nonce or 1, card, { min = 150, tanks = 0, healers = 1, damage = 1, note = "need heals" })
HARNESS_FIRE_EVENT("CHAT_MSG_ADDON", "CUILFG", reply, "WHISPER", "Korvath-Lightbane")
local got = Comms.CardOf("Korvath")
OUT:write(("== Korvath's card: score %s, group min %s needs %d/%d/%d note %s\n"):format(tostring(got and got.score),
    tostring(got and got.group and got.group.min), got and got.group and got.group.tanks or -1, got and got.group and got.group.healers or -1,
    got and got.group and got.group.damage or -1, tostring(got and got.group and got.group.note)))
local win = rawget(_G, "CludesUILookingForGroup")
OUT:write("== window shown " .. tostring(win and win:IsShown()) .. "\n")

-- Apply to Korvath.
wipe(sentMsgs)
GF.Browse.Apply("Korvath", "Deadmines")
HARNESS_ADVANCE(1)
OUT:write("== applied: " .. tostring(sentMsgs[1]) .. ", sent records " .. #Comms.sent .. "\n")
HARNESS_FIRE_EVENT("CHAT_MSG_ADDON", "CUILFG", "1 K " .. Comms.sent[1].id, "WHISPER", "Korvath")
OUT:write("== acknowledged " .. tostring(Comms.sent[1].acked) .. "\n")

-- Now listed ourselves: answer a card request and take an application.
listed = true
wipe(sentMsgs)
HARNESS_FIRE_EVENT("CHAT_MSG_ADDON", "CUILFG", "1 Q 7 Deadmines", "WHISPER", "Zed-Lightbane")
HARNESS_ADVANCE(1)
OUT:write("== answered a card request: " .. tostring(sentMsgs[1]) .. "\n")
wipe(sentMsgs)
HARNESS_FIRE_EVENT("CHAT_MSG_ADDON", "CUILFG", text, "WHISPER", "Zed-Lightbane")
HARNESS_ADVANCE(1)
OUT:write("== applicants " .. #Comms.applicants .. ", ack " .. tostring(sentMsgs[1]) .. "\n")

-- Every tab paints without an error.
for _, label in ipairs({ "Your Group", "Create", "Browse" }) do
    local found
    for _, child in ipairs({ win:GetChildren() }) do
        if child.GetText and child:GetText() == label then found = child end
    end
    local onClick = found and found:GetScript("OnClick")
    local ok, err = pcall(function() if onClick then onClick(found, "LeftButton") end end)
    OUT:write(("== tab %s %s%s\n"):format(label, found and "clicked" or "missing", ok and "" or (" ERR " .. tostring(err))))
end
LF.Toggle()
OUT:write("== toggled shown " .. tostring(win:IsShown()) .. "\n")
