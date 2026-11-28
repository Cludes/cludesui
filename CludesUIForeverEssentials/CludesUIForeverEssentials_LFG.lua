if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_LFG.lua  (WoW Forever only)
--  Looking For Group: a layer on top of WoW Forever's own group finder, which
--  is a listing board with no applications. Forever does the listing,
--  searching and inviting; CludesUI players see each other's cards (level,
--  roles, Gear Score, boss kills and quests for the dungeon) and can apply to
--  a group, by addon whispers between the two players. The window is
--  CludesUIForeverEssentials_LFGWindow.lua (/clfg).
--
--  Messages: addon whispers, prefix CUILFG, one plain line, version first,
--  at most 255 bytes:
--    1 Q <nonce> <dungeon or ->            ask a listed player for their card
--    1 C <nonce> <card>                    their card
--    1 L <nonce> <card> <min or -> <needs> [note]   card plus their listing
--    1 A <id> <card> [note]                apply
--    1 K <id>  received   1 X <id>  withdrawn   1 D <id>  declined
--  The card: <class ID> <level> <roles> <spec> <score> <BiS> <dungeon>
--  <kills> <quests>, "-" for a field not shared. score is the Gear Score in
--  tenths; kills each Journal boss's count in order; quests the dungeon's
--  quests in your log, a slash, then those you still need.
--  A card or application is answered only while you are listed; answers and
--  sends are rate limited so browsing players cannot fill the queue.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("lfg", {
    enabled = false,
    shareScore = true,
    shareKills = true,
    shareQuests = true,
    sort = "newest",
})
local Get, Enabled = F.Get, F.Enabled
local J = module.Journal

local PREFIX = "CUILFG"
local GF = { PREFIX = PREFIX }
module.LFG = GF

local function Secret(v)
    return v ~= nil and issecretvalue and issecretvalue(v)
end

-------------------------------------------------------------------------------
--  Listeners: the files and the window tell each other through these.
-------------------------------------------------------------------------------
local subscribers = {}
function GF.On() return Enabled() end
function GF.Subscribe(what, fn)
    local items = subscribers[what]
    if not items then
        items = {}
        subscribers[what] = items
    end
    items[#items + 1] = fn
end
function GF.Notify(what, a, b, c, d)
    local items = subscribers[what]
    if not items then return end
    for i = 1, #items do
        items[i](a, b, c, d)
    end
end

-------------------------------------------------------------------------------
--  Card: your card, and every message as one plain, versioned line
-------------------------------------------------------------------------------
local Card = {}
GF.Card = Card
do
local byte, find, sub, gsub = string.byte, string.find, string.sub, string.gsub
local concat, floor = table.concat, math.floor
local CARD_DEFAULTS = { VERSION = "1", MAX_BYTES = 255, NOTE_MAX = 60, MAX_KILLS = 30, KILL_CAP = 99, MAX_QUESTS = 8, ID_MAX = 9999 }
for k, v in pairs(CARD_DEFAULTS) do
    Card[k] = v
end
local VERSION, MAX_BYTES, NOTE_MAX = Card.VERSION, Card.MAX_BYTES, Card.NOTE_MAX
local MAX_KILLS, KILL_CAP, MAX_QUESTS, ID_MAX = Card.MAX_KILLS, Card.KILL_CAP, Card.MAX_QUESTS, Card.ID_MAX
local CLASS_MAX, LEVEL_MAX, SCORE_MAX, BIS_MAX, QUEST_ID_MAX = 20, 100, 99999, 40, 999999
local KEY_MAX, SPEC_MAX, ROLES_MAX, DIGITS_MAX, NEEDS_DIGITS = 40, 32, 3, 6, 3
local NEED_MAX = 9
Card.NEED_MAX = NEED_MAX
local JOURNAL_KEY_FORMAT = "^%u%w*$"
local SPEC_FORMAT = "^[%l%-]+$"
local NOTE_REJECT = "[^\32-\123\125\126]"
local UI_ESCAPES = { "|c%x%x%x%x%x%x%x%x", "|H.-|h", "|T.-|t", "|A.-|a", "|K.-|k", "|[rh]" }
local DASH, SPACE = "-", " "
local VERSION_BYTE, NONE_BYTE, SPACE_BYTE = byte(VERSION), byte(DASH), byte(SPACE)
local ZERO, NINE = byte("0"), byte("9")
local MESSAGE_KINDS = {}
for _, msgKind in ipairs({ "Q", "C", "A", "K", "X", "D", "L" }) do
    MESSAGE_KINDS[byte(msgKind)] = msgKind
end
local TANK, HEALER, DAMAGE = 4, 2, 1
Card.TANK, Card.HEALER, Card.DAMAGE = TANK, HEALER, DAMAGE
local ROLE_LETTER_FOR = { [0] = DASH, "D", "H", "HD", "T", "TD", "TH", "THD" }
local ROLE_FROM_LETTER = { [byte("T")] = TANK, [byte("H")] = HEALER, [byte("D")] = DAMAGE }
local QUEST_FIELD_ID, QUEST_FIELD_SIDE = 1, 4
local SIDE = { Alliance = "A", Horde = "H" }
local lastTenths
local pieces = {}

function Card.Blank()
    return { killList = {}, questsHave = {}, questsNeed = {}, killCount = 0, haveCount = 0, needCount = 0, roles = 0 }
end
local myCard = Card.Blank()

function Card.RoleBits(tank, healer, damageCount)
    return (tank and TANK or 0) + (healer and HEALER or 0) + (damageCount and DAMAGE or 0)
end
function Card.RoleLetters(mask) return ROLE_LETTER_FOR[mask] or DASH end

local function Cut(t, n)
    for i = #t, n + 1, -1 do
        t[i] = nil
    end
end

-- The roles saved in the game's group finder (tank, healer, damage).
local function MyRoles()
    local roles = C_LFGListRoles and C_LFGListRoles.GetRoles and C_LFGListRoles.GetRoles()
    if not roles then return DAMAGE end
    return Card.RoleBits(roles.tank, roles.healer, roles.dps)
end
Card.MyRoles = MyRoles

local function ScoreTenths()
    local GS = CUI._GearScore
    if not (GS and GS.Score and GS.Score.Unit) then return lastTenths end
    local score, complete = GS.Score.Unit("player")
    if complete and type(score) == "number" then
        local tenths = floor(score * 10 + 0.5)
        if tenths >= 0 and tenths <= SCORE_MAX then lastTenths = tenths end
    end
    return lastTenths
end

local function CountedBosses(journalRow)
    local items = {}
    for _, wing in ipairs(journalRow.wings or {}) do
        for _, boss in ipairs(wing.bosses or {}) do
            if boss.encounters and not boss.trash then items[#items + 1] = boss end
        end
    end
    return items
end
GF.CountedBosses = CountedBosses

local function PutKills(cardRec, journalRow)
    local Kills = module.BossKills
    if not Kills then return false end
    local n = 0
    for _, boss in ipairs(CountedBosses(journalRow)) do
        if n >= MAX_KILLS then break end
        local howMany = Kills.Count(boss)
        n = n + 1
        cardRec.killList[n] = howMany > KILL_CAP and KILL_CAP or howMany
    end
    Cut(cardRec.killList, n)
    cardRec.killCount = n
    return n > 0
end

local function DungeonQuests(journalRow)
    if J.Prepare then J.Prepare() end
    return journalRow.questInfo and journalRow.questInfo.quests
end
GF.DungeonQuests = DungeonQuests

local function OurSide(q)
    local side = q[QUEST_FIELD_SIDE]
    return side == "B" or side == SIDE[UnitFactionGroup("player") or ""]
end
GF.OurSide = OurSide

local function PutQuests(cardRec, journalRow)
    local items = DungeonQuests(journalRow)
    local questsHave, questsNeed, nh, nn = cardRec.questsHave, cardRec.questsNeed, 0, 0
    for i = 1, items and #items or 0 do
        local q = items[i]
        local ref = q[QUEST_FIELD_ID]
        if OurSide(q) then
            if C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(ref) then
                if nh < MAX_QUESTS then
                    nh = nh + 1
                    questsHave[nh] = ref
                end
            elseif not (C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(ref)) and nn < MAX_QUESTS then
                nn = nn + 1
                questsNeed[nn] = ref
            end
        end
    end
    Cut(questsHave, nh)
    Cut(questsNeed, nn)
    cardRec.haveCount, cardRec.needCount = nh, nn
    return true
end

function Card.Own(dungeonKey, roles)
    local cardRec = myCard
    local _, _, classID = UnitClass("player")
    cardRec.class = classID
    cardRec.level = UnitLevel("player")
    cardRec.roles = roles or MyRoles()
    cardRec.specKey = nil
    cardRec.score = Get("shareScore") and ScoreTenths() or nil
    cardRec.bisOwned, cardRec.bisSlots = nil, nil
    local journalRow = dungeonKey and J.byKey[dungeonKey]
    cardRec.dungeon = journalRow and dungeonKey or nil
    cardRec.killsShared = journalRow and Get("shareKills") and PutKills(cardRec, journalRow) or false
    cardRec.questsShared = journalRow and Get("shareQuests") and PutQuests(cardRec, journalRow) or false
    if not cardRec.killsShared then
        cardRec.killCount = 0
        Cut(cardRec.killList, 0)
    end
    if not cardRec.questsShared then
        cardRec.haveCount, cardRec.needCount = 0, 0
        Cut(cardRec.questsHave, 0)
        Cut(cardRec.questsNeed, 0)
    end
    return cardRec
end

local function CommaList(t, n)
    if n == 0 then return "" end
    return concat(t, ",", 1, n)
end

local function WriteCard(cardRec, n, questCap, killList)
    pieces[n + 1] = cardRec.class
    pieces[n + 2] = cardRec.level
    pieces[n + 3] = ROLE_LETTER_FOR[cardRec.roles] or DASH
    pieces[n + 4] = cardRec.specKey or DASH
    pieces[n + 5] = cardRec.score or DASH
    pieces[n + 6] = cardRec.bisSlots and (cardRec.bisOwned .. "/" .. cardRec.bisSlots) or DASH
    pieces[n + 7] = cardRec.dungeon or DASH
    pieces[n + 8] = (cardRec.dungeon and killList and cardRec.killsShared and cardRec.killCount > 0) and CommaList(cardRec.killList, cardRec.killCount)
        or DASH
    if cardRec.dungeon and cardRec.questsShared then
        local nh = cardRec.haveCount < questCap and cardRec.haveCount or questCap
        local nn = cardRec.needCount < questCap and cardRec.needCount or questCap
        pieces[n + 9] = CommaList(cardRec.questsHave, nh) .. "/" .. CommaList(cardRec.questsNeed, nn)
    else
        pieces[n + 9] = DASH
    end
    return n + 9
end

-- A card that would not fit loses its quest lists first, then its kills.
local function Fitted(msgKind, ref, cardRec, memo, groupInfo)
    local cap, killList = MAX_QUESTS, true
    while true do
        pieces[1], pieces[2], pieces[3] = VERSION, msgKind, ref
        local n = WriteCard(cardRec, 3, cap, killList)
        if groupInfo then
            pieces[n + 1] = groupInfo.min > 0 and groupInfo.min or DASH
            pieces[n + 2] = groupInfo.tankCount .. groupInfo.healerCount .. groupInfo.damageCount
            n = n + 2
        end
        if memo then
            n = n + 1
            pieces[n] = memo
        end
        local textLine = concat(pieces, SPACE, 1, n)
        if #textLine <= MAX_BYTES then return textLine end
        if cap > 0 then
            cap = cap - 1
        elseif killList then
            killList = false
        else
            return nil
        end
    end
end

function Card.Answer(nonceRef, cardRec, groupInfo)
    if not groupInfo then return Fitted("C", nonceRef, cardRec) end
    return Fitted("L", nonceRef, cardRec, groupInfo.memo ~= "" and groupInfo.memo or nil, groupInfo)
end
function Card.Applying(ref, cardRec, memo) return Fitted("A", ref, cardRec, memo ~= "" and memo or nil) end
function Card.Request(nonceRef, dungeonKey)
    pieces[1], pieces[2], pieces[3], pieces[4] = VERSION, "Q", nonceRef, dungeonKey or DASH
    return concat(pieces, SPACE, 1, 4)
end
function Card.Bare(msgKind, ref)
    pieces[1], pieces[2], pieces[3] = VERSION, msgKind, ref
    return concat(pieces, SPACE, 1, 3)
end

function Card.TidyNote(textLine)
    if type(textLine) ~= "string" then return "" end
    for i = 1, #UI_ESCAPES do
        textLine = gsub(textLine, UI_ESCAPES[i], "")
    end
    textLine = gsub(gsub(gsub(textLine, "%s+", SPACE), NOTE_REJECT, ""), "  +", SPACE)
    textLine = gsub(gsub(textLine, "^ ", ""), " $", "")
    if #textLine > NOTE_MAX then textLine = gsub(sub(textLine, 1, NOTE_MAX), " $", "") end
    return textLine
end

local function NextField(s, cursor, span)
    if cursor > span then return nil end
    local space = find(s, SPACE, cursor, true)
    if space == cursor then return nil end
    if space then return cursor, space - 1, space + 1 end
    return cursor, span, span + 1
end

local function ReadInt(s, i, j, max)
    if j < i or j - i >= DIGITS_MAX then return nil end
    local v = 0
    for k = i, j do
        local b = byte(s, k)
        if b < ZERO or b > NINE then return nil end
        v = v * 10 + b - ZERO
    end
    if v > max then return nil end
    return v
end

local function IsDash(s, i, j) return i == j and byte(s, i) == NONE_BYTE end

local function Text(s, i, j, max, pattern)
    if j - i + 1 > max then return nil end
    local textLine = sub(s, i, j)
    if not find(textLine, pattern) then return nil end
    return textLine
end

local function ReadRoles(s, i, j)
    if IsDash(s, i, j) then return 0 end
    if j - i >= ROLES_MAX then return nil end
    local mask, prevBit = 0, TANK + 1
    for k = i, j do
        local b = ROLE_FROM_LETTER[byte(s, k)]
        if not b or b >= prevBit then return nil end
        mask, prevBit = mask + b, b
    end
    return mask
end

local function SlashAt(s, i, j)
    local slash = find(s, "/", i, true)
    if not slash or slash > j then return nil end
    local again = find(s, "/", slash + 1, true)
    if again and again <= j then return nil end
    return slash
end

local function List(s, i, j, t, max, cap, low)
    if i > j then
        Cut(t, 0)
        return 0
    end
    local n, at = 0, i
    while true do
        local comma = find(s, ",", at, true)
        local e = (comma and comma <= j) and comma - 1 or j
        local v = ReadInt(s, at, e, cap)
        if not v or v < low or n >= max then return nil end
        n = n + 1
        t[n] = v
        if e == j then break end
        at = e + 2
        if at > j then return nil end
    end
    Cut(t, n)
    return n
end

local function ReadCard(s, cursor, span, cardRec)
    local i, j
    i, j, cursor = NextField(s, cursor, span)
    cardRec.class = i and ReadInt(s, i, j, CLASS_MAX)
    if not cardRec.class or cardRec.class < 1 then return nil end
    i, j, cursor = NextField(s, cursor, span)
    cardRec.level = i and ReadInt(s, i, j, LEVEL_MAX)
    if not cardRec.level or cardRec.level < 1 then return nil end
    i, j, cursor = NextField(s, cursor, span)
    cardRec.roles = i and ReadRoles(s, i, j)
    if not cardRec.roles then return nil end
    i, j, cursor = NextField(s, cursor, span)
    if not i then return nil end
    if IsDash(s, i, j) then
        cardRec.specKey = nil
    else
        cardRec.specKey = Text(s, i, j, SPEC_MAX, SPEC_FORMAT)
        if not cardRec.specKey then return nil end
    end
    i, j, cursor = NextField(s, cursor, span)
    if not i then return nil end
    if IsDash(s, i, j) then
        cardRec.score = nil
    else
        cardRec.score = ReadInt(s, i, j, SCORE_MAX)
        if not cardRec.score then return nil end
    end
    i, j, cursor = NextField(s, cursor, span)
    if not i then return nil end
    if IsDash(s, i, j) then
        cardRec.bisOwned, cardRec.bisSlots = nil, nil
    else
        local slash = SlashAt(s, i, j)
        local questsHave = slash and ReadInt(s, i, slash - 1, BIS_MAX)
        local total = questsHave and ReadInt(s, slash + 1, j, BIS_MAX)
        if not total or total < 1 or questsHave > total then return nil end
        cardRec.bisOwned, cardRec.bisSlots = questsHave, total
    end
    i, j, cursor = NextField(s, cursor, span)
    if not i then return nil end
    if IsDash(s, i, j) then
        cardRec.dungeon = nil
    else
        cardRec.dungeon = Text(s, i, j, KEY_MAX, JOURNAL_KEY_FORMAT)
        if not cardRec.dungeon then return nil end
    end
    i, j, cursor = NextField(s, cursor, span)
    if not i then return nil end
    if IsDash(s, i, j) then
        cardRec.killsShared, cardRec.killCount = false, 0
        Cut(cardRec.killList, 0)
    else
        local n = cardRec.dungeon and List(s, i, j, cardRec.killList, MAX_KILLS, KILL_CAP, 0)
        if not n or n < 1 then return nil end
        cardRec.killsShared, cardRec.killCount = true, n
    end
    i, j, cursor = NextField(s, cursor, span)
    if not i then return nil end
    if IsDash(s, i, j) then
        cardRec.questsShared, cardRec.haveCount, cardRec.needCount = false, 0, 0
        Cut(cardRec.questsHave, 0)
        Cut(cardRec.questsNeed, 0)
    else
        local slash = cardRec.dungeon and SlashAt(s, i, j)
        local nh = slash and List(s, i, slash - 1, cardRec.questsHave, MAX_QUESTS, QUEST_ID_MAX, 1)
        local nn = nh and List(s, slash + 1, j, cardRec.questsNeed, MAX_QUESTS, QUEST_ID_MAX, 1)
        if not nn then return nil end
        cardRec.questsShared, cardRec.haveCount, cardRec.needCount = true, nh, nn
    end
    return cursor, j
end

local function ReadNote(textLine, cursor, span)
    if cursor > span or byte(textLine, cursor) == SPACE_BYTE then return nil end
    local memo = sub(textLine, cursor)
    if #memo > NOTE_MAX or find(memo, NOTE_REJECT) or byte(memo, #memo) == SPACE_BYTE then return nil end
    return memo
end

local function ReadDigit(s, k)
    local b = byte(s, k)
    if b < ZERO or b > NINE then return nil end
    return b - ZERO
end

local function ReadGroupPart(s, cursor, span, groupInfo)
    local i, j
    i, j, cursor = NextField(s, cursor, span)
    if not i then return nil end
    if IsDash(s, i, j) then
        groupInfo.min = 0
    else
        groupInfo.min = ReadInt(s, i, j, SCORE_MAX)
        if not groupInfo.min or groupInfo.min < 1 then return nil end
    end
    i, j, cursor = NextField(s, cursor, span)
    if not i or j - i + 1 ~= NEEDS_DIGITS then return nil end
    groupInfo.tankCount, groupInfo.healerCount, groupInfo.damageCount = ReadDigit(s, i), ReadDigit(s, i + 1), ReadDigit(s, i + 2)
    if not (groupInfo.tankCount and groupInfo.healerCount and groupInfo.damageCount) then return nil end
    return cursor, j
end

-- Returns kind, id, extra (Q: the dungeon key; C/A/L: the note), or nil.
function Card.Parse(textLine, cardRec, groupInfo)
    if type(textLine) ~= "string" then return nil end
    local span = #textLine
    if span > MAX_BYTES then return nil end
    local i, j, cursor = NextField(textLine, 1, span)
    if not i or j ~= i or byte(textLine, i) ~= VERSION_BYTE then return nil end
    i, j, cursor = NextField(textLine, cursor, span)
    local msgKind = i and i == j and MESSAGE_KINDS[byte(textLine, i)]
    if not msgKind then return nil end
    i, j, cursor = NextField(textLine, cursor, span)
    local ref = i and ReadInt(textLine, i, j, ID_MAX)
    if not ref or ref < 1 then return nil end
    if msgKind == "Q" then
        i, j = NextField(textLine, cursor, span)
        if not i or j ~= span then return nil end
        if IsDash(textLine, i, j) then return msgKind, ref, nil end
        local nameKey = Text(textLine, i, j, KEY_MAX, JOURNAL_KEY_FORMAT)
        if not nameKey then return nil end
        return msgKind, ref, nameKey
    end
    if msgKind == "C" or msgKind == "A" or msgKind == "L" then
        if not cardRec then return nil end
        cursor, j = ReadCard(textLine, cursor, span, cardRec)
        if not cursor then return nil end
        if msgKind == "L" then
            if not groupInfo or j == span then return nil end
            cursor, j = ReadGroupPart(textLine, cursor, span, groupInfo)
            if not cursor then return nil end
        end
        if j == span then return msgKind, ref, nil end
        if msgKind == "C" then return nil end
        local memo = ReadNote(textLine, cursor, span)
        if not memo then return nil end
        return msgKind, ref, memo
    end
    if j ~= span then return nil end
    return msgKind, ref
end

end
local find, sub, gsub, concat = string.find, string.sub, string.gsub, table.concat
local ID_MAX, MyRoles = Card.ID_MAX, Card.MyRoles

-------------------------------------------------------------------------------
--  Group: your listing in Forever's group finder
-------------------------------------------------------------------------------
local Group = { activity = nil, style = nil, min = 0, tankCount = 1, healerCount = 1, damageCount = 3, memo = "", ours = false, listedAt = nil }
GF.Group = Group
local createData = { activityIDs = {}, generalPlaystyle = 0 }

function Group.Listed() return C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo() or false end
function Group.CanEdit()
    return not IsInGroup(LE_PARTY_CATEGORY_HOME) or UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME)
end
function Group.Answering() return Group.Listed() and Group.CanEdit() end
function Group.Ready() return Group.activity ~= nil and Group.style ~= nil end
function Group.List()
    if not (GF.On() and Group.Ready() and Group.CanEdit()) then return false end
    createData.activityIDs[1] = Group.activity
    createData.generalPlaystyle = Group.style
    local ok
    if Group.Listed() then
        ok = C_LFGList.UpdateListing(createData)
    else
        ok = C_LFGList.CreateListing(createData)
    end
    if ok then
        Group.ours = true
        Group.listedAt = Group.listedAt or GetTime()
    end
    GF.Notify("group")
    return ok
end
function Group.Delist()
    if not (Group.Listed() and Group.CanEdit()) then return false end
    C_LFGList.RemoveListing()
    return true
end
function Group.Info()
    if Group.ours and Group.Listed() then return Group end
end

-------------------------------------------------------------------------------
--  Comms: the whispers, through a queue kept to the game's limits
-------------------------------------------------------------------------------
local lower, match, remove, max = string.lower, string.match, table.remove, math.max
local WHISPER = "WHISPER"
local SEND_BURST, SEND_RATE = 10, 1
local OUTBOX_MAX = 30
local LOCKED_RETRY = 2
local CARD_WAIT = 10
local APPLY_TTL = 600
local FLOOD_WINDOW, FLOOD_MAX, FLOOD_PLAYERS_MAX = 10, 8, 200
local ANSWER_SPACING, ANSWERS_PER_WINDOW, ANSWER_WINDOW, ANSWERED_PLAYERS_MAX = 30, 5, 10, 40
local OFFLINE_WINDOW, WHISPERED_PLAYERS_MAX = 10, 40
local MAX_ASKS, MAX_MINE, MAX_INCOMING, MAX_KEPT = 20, 10, 40, 100
local RESULT = Enum.SendAddonMessageResult or {}
local CARD_ARRAYS = { "killList", "questsHave", "questsNeed" }
local Comms = { cardAsks = {}, myApps = {}, incomingApps = {}, APPLY_TTL = APPLY_TTL }
GF.Comms = Comms
local cardAsks, myApps, incomingApps = Comms.cardAsks, Comms.myApps, Comms.incomingApps
local LISTS = { cardAsks, myApps, incomingApps }
local talking, talkFrame, prefixDone, myKey = false, nil, false, nil
local outTo, outText = {}, {}
local budget, refillAt, flushAt = SEND_BURST, 0, nil
local whisperedAt, whisperedCount = {}, 0
local floodCount, floodStart, floodPlayers = {}, {}, 0
local answeredAt, answeredPlayers = {}, 0
local answerWindowAt, answersInWindow = -ANSWER_WINDOW, 0
local cardsByName, cardCount = {}, 0
local lastRef = 0
local expiryGen, expiryAt = 0, nil
local inCard = Card.Blank()
local inListing = { min = 0, tankCount = 0, healerCount = 0, damageCount = 0, memo = "" }
local offlinePattern
local AddFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
local RemoveFilter = (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter) or ChatFrame_RemoveMessageEventFilter

local function Key(name) return lower(Ambiguate(name, "none")) end
Comms.Key = Key
function Comms.IsMe(name) return Key(name) == myKey end

local function SplitRealm(nameKey)
    local dash = find(nameKey, "-", 1, true)
    return dash and sub(nameKey, 1, dash - 1) or nameKey, dash ~= nil
end

-- Forever's listings name the leader without a realm, so a name with no
-- realm matches the same name with one.
local function SameChar(a, b)
    local ka, kb = Key(a), Key(b)
    if ka == kb then return true end
    local na, realmA = SplitRealm(ka)
    local nb, realmB = SplitRealm(kb)
    return not (realmA and realmB) and na == nb
end

local function NewRef()
    lastRef = lastRef % ID_MAX + 1
    return lastRef
end

local function FindRecord(items, ref, name)
    for i = 1, #items do
        local app = items[i]
        if (not ref or app.ref == ref) and SameChar(app.name, name) then return app, i end
    end
end

local function Unqueue(app, msgKind)
    local lead = Card.Bare(msgKind, app.ref) .. " "
    local cancelled = false
    for i = #outText, 1, -1 do
        if (sub(outText[i], 1, #lead) == lead or outText[i] == Card.Bare(msgKind, app.ref)) and SameChar(outTo[i], app.name) then
            remove(outTo, i)
            remove(outText, i)
            cancelled = true
        end
    end
    return cancelled
end

local Expiry
local function NextDeadline()
    local at
    for l = 1, #LISTS do
        local items = LISTS[l]
        for i = 1, #items do
            local deadline = items[i].deadline
            if not at or deadline < at then at = deadline end
        end
    end
    return at
end

local function PlanExpiry()
    local at = NextDeadline()
    if not at then
        expiryAt = nil
        expiryGen = expiryGen + 1
        return
    end
    if expiryAt and expiryAt <= at then return end
    expiryGen = expiryGen + 1
    expiryAt = at
    local gen = expiryGen
    C_Timer.After(max(0, at - GetTime()), function() Expiry(gen) end)
end

local function DropExpired(items, clock, what, msgKind)
    for i = #items, 1, -1 do
        local app = items[i]
        if app.deadline <= clock then
            if msgKind then Unqueue(app, msgKind) end
            remove(items, i)
            GF.Notify(what, app)
        end
    end
end

function Expiry(gen)
    if gen ~= expiryGen or not talking then return false end
    expiryAt = nil
    local clock = GetTime()
    DropExpired(cardAsks, clock, "noreply", "Q")
    DropExpired(myApps, clock, "expired", "A")
    DropExpired(incomingApps, clock, "applicantExpired")
    PlanExpiry()
    return true
end

local Flush
local function FlushLater(delay)
    local at = GetTime() + delay
    if flushAt and flushAt <= at then return end
    flushAt = at
    C_Timer.After(delay, Flush)
end

local function MarkWhispered(toName)
    local nameKey = Key(toName)
    if not whisperedAt[nameKey] then
        if whisperedCount >= WHISPERED_PLAYERS_MAX then
            wipe(whisperedAt)
            whisperedCount = 0
        end
        whisperedCount = whisperedCount + 1
    end
    whisperedAt[nameKey] = GetTime()
end

local function WentOffline(name)
    for i = #cardAsks, 1, -1 do
        local cardAsk = cardAsks[i]
        if SameChar(cardAsk.name, name) then
            remove(cardAsks, i)
            GF.Notify("offline", cardAsk)
        end
    end
end

local function ChatLocked()
    return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

function Flush()
    flushAt = nil
    if not talking then return end
    while #outText > 0 do
        if ChatLocked() then return FlushLater(LOCKED_RETRY) end
        local clock = GetTime()
        budget = budget + (clock - refillAt) * SEND_RATE
        if budget > SEND_BURST then budget = SEND_BURST end
        refillAt = clock
        if budget < 1 then return FlushLater((1 - budget) / SEND_RATE) end
        local toName = outTo[1]
        MarkWhispered(toName)
        local sendResult = C_ChatInfo.SendAddonMessage(PREFIX, outText[1], WHISPER, toName)
        if sendResult ~= nil and (sendResult == RESULT.AddonMessageThrottle or sendResult == RESULT.ChannelThrottle) then
            budget = 0
            return FlushLater(1 / SEND_RATE)
        end
        if sendResult ~= nil and sendResult == RESULT.AddOnMessageLockdown then return FlushLater(LOCKED_RETRY) end
        remove(outTo, 1)
        remove(outText, 1)
        budget = budget - 1
        if sendResult ~= nil and sendResult == RESULT.TargetOffline then WentOffline(toName) end
    end
end

local function Send(toName, textLine)
    if not (talking and toName and textLine) then return false end
    for i = 1, #outText do
        if outTo[i] == toName and outText[i] == textLine then return true end
    end
    if #outText >= OUTBOX_MAX then return false end
    outTo[#outTo + 1] = toName
    outText[#outText + 1] = textLine
    if not flushAt then Flush() end
    return true
end
Comms.Send = Send

function Comms.AskCard(name, dungeonKey)
    if not talking or #cardAsks >= MAX_ASKS or #outText >= OUTBOX_MAX then return nil end
    local nonceRef = NewRef()
    local clock = GetTime()
    cardAsks[#cardAsks + 1] = { ref = nonceRef, name = name, dungeon = dungeonKey, sentAt = clock, deadline = clock + CARD_WAIT }
    Send(name, Card.Request(nonceRef, dungeonKey))
    PlanExpiry()
    return nonceRef
end

function Comms.Apply(name, dungeonKey, roles, memo)
    if not talking or #myApps >= MAX_MINE then return nil end
    local ref = NewRef()
    local textLine = Card.Applying(ref, Card.Own(dungeonKey, roles), Card.TidyNote(memo))
    if not Send(name, textLine) then return nil end
    myApps[#myApps + 1] = { ref = ref, name = name, dungeon = dungeonKey, deadline = GetTime() + APPLY_TTL, acked = false, declined = false }
    PlanExpiry()
    return ref
end

function Comms.Retract(ref)
    for i = 1, #myApps do
        local app = myApps[i]
        if app.ref == ref then
            if not Unqueue(app, "A") and not Send(app.name, Card.Bare("X", ref)) then return false end
            remove(myApps, i)
            PlanExpiry()
            return true
        end
    end
    return false
end

function Comms.AppliedTo(name) return (FindRecord(myApps, nil, name)) end

function Comms.Refuse(name)
    local app, i = FindRecord(incomingApps, nil, name)
    if not app then return false end
    if not Send(app.name, Card.Bare("D", app.ref)) then return false end
    remove(incomingApps, i)
    PlanExpiry()
    return true
end

function Comms.IsApplicant(app)
    for i = 1, #incomingApps do
        if incomingApps[i] == app then return true end
    end
    return false
end

local function CopyCard(from, to)
    to.class, to.level, to.roles, to.specKey = from.class, from.level, from.roles, from.specKey
    to.score, to.bisOwned, to.bisSlots, to.dungeon = from.score, from.bisOwned, from.bisSlots, from.dungeon
    to.killsShared, to.questsShared = from.killsShared, from.questsShared
    to.killCount, to.haveCount, to.needCount = from.killCount, from.haveCount, from.needCount
    for l = 1, #CARD_ARRAYS do
        local a, b = from[CARD_ARRAYS[l]], to[CARD_ARRAYS[l]]
        for i = 1, #a do
            b[i] = a[i]
        end
        for i = #b, #a + 1, -1 do
            b[i] = nil
        end
    end
    return to
end

local function StoreCard(name, cardRec)
    local nameKey = Key(name)
    local stored = cardsByName[nameKey]
    if not stored then
        if cardCount >= MAX_KEPT then
            wipe(cardsByName)
            cardCount = 0
        end
        stored = Card.Blank()
        cardsByName[nameKey] = stored
        cardCount = cardCount + 1
    end
    return CopyCard(cardRec, stored)
end

-- A listing names its leader without a realm while their whisper carries
-- one: a name with no realm finds the card kept under name-realm.
function Comms.KnownCard(name)
    local nameKey = Key(name)
    local cardRec = cardsByName[nameKey]
    if cardRec or find(nameKey, "-", 1, true) then return cardRec end
    local lead = nameKey .. "-"
    for stored, c in pairs(cardsByName) do
        if sub(stored, 1, #lead) == lead then return c end
    end
end

local function CanAnswer(nameKey, clock)
    if clock - answerWindowAt >= ANSWER_WINDOW then answerWindowAt, answersInWindow = clock, 0 end
    if answersInWindow >= ANSWERS_PER_WINDOW then return false end
    local prevBit = answeredAt[nameKey]
    if prevBit and clock - prevBit < ANSWER_SPACING then return false end
    if not prevBit then
        if answeredPlayers >= ANSWERED_PLAYERS_MAX then
            wipe(answeredAt)
            answeredPlayers = 0
        end
        answeredPlayers = answeredPlayers + 1
    end
    answeredAt[nameKey] = clock
    answersInWindow = answersInWindow + 1
    return true
end

local Handlers = {}
function Handlers.Q(whisperer, ref, dungeonKey, clock)
    if not Group.Answering() or not CanAnswer(Key(whisperer), clock) then return end
    Send(whisperer, Card.Answer(ref, Card.Own(dungeonKey), Group.Info()))
end

local function GotCard(whisperer, ref, clock, groupInfo)
    local cardAsk, i = FindRecord(cardAsks, ref, whisperer)
    if not cardAsk then return end
    local cardRec = StoreCard(whisperer, inCard)
    if groupInfo then
        local stored = cardRec.group or {}
        stored.min, stored.tankCount, stored.healerCount, stored.damageCount, stored.memo = groupInfo.min, groupInfo.tankCount, groupInfo.healerCount, groupInfo.damageCount, groupInfo.memo
        cardRec.group = stored
    else
        cardRec.group = nil
    end
    remove(cardAsks, i)
    GF.Notify("card", whisperer, cardRec, cardAsk, clock - cardAsk.sentAt)
    PlanExpiry()
end
function Handlers.C(whisperer, ref, _, clock) GotCard(whisperer, ref, clock, nil) end
function Handlers.L(whisperer, ref, memo, clock)
    inListing.memo = memo or ""
    GotCard(whisperer, ref, clock, inListing)
end
function Handlers.A(whisperer, ref, memo, clock)
    if not Group.Answering() then return end
    local app = FindRecord(incomingApps, nil, whisperer)
    if not app then
        if #incomingApps >= MAX_INCOMING then return end
        app = { card = Card.Blank() }
        incomingApps[#incomingApps + 1] = app
    end
    CopyCard(inCard, app.card)
    app.ref, app.name, app.memo = ref, whisperer, memo
    app.invited = false
    app.at, app.deadline = clock, clock + APPLY_TTL
    Send(whisperer, Card.Bare("K", ref))
    PlanExpiry()
    GF.Notify("applicant", app)
end
function Handlers.K(whisperer, ref)
    local app = FindRecord(myApps, ref, whisperer)
    if not app then return end
    app.acked = true
    GF.Notify("received", app)
end
function Handlers.X(whisperer, ref)
    local app, i = FindRecord(incomingApps, ref, whisperer)
    if not app then return end
    remove(incomingApps, i)
    GF.Notify("withdrawn", app)
    PlanExpiry()
end
function Handlers.D(whisperer, ref)
    local app = FindRecord(myApps, ref, whisperer)
    if not app then return end
    app.declined = true
    GF.Notify("declined", app)
end

local function UnderFloodLimit(nameKey, clock)
    local start = floodStart[nameKey]
    if not start or clock - start > FLOOD_WINDOW then
        if not start then
            floodPlayers = floodPlayers + 1
            if floodPlayers > FLOOD_PLAYERS_MAX then
                wipe(floodStart)
                wipe(floodCount)
                floodPlayers = 1
            end
        end
        floodStart[nameKey], floodCount[nameKey] = clock, 1
        return true
    end
    local n = floodCount[nameKey] + 1
    floodCount[nameKey] = n
    return n <= FLOOD_MAX
end

local function OnWhisper(textLine, whisperer)
    local nameKey = Key(whisperer)
    if nameKey == myKey then return end
    if C_FriendList.IsIgnored and C_FriendList.IsIgnored(Ambiguate(whisperer, "none")) then return end
    local clock = GetTime()
    if not UnderFloodLimit(nameKey, clock) then return end
    local msgKind, ref, rest = Card.Parse(textLine, inCard, inListing)
    if not msgKind then return end
    Handlers[msgKind](whisperer, ref, rest, clock)
end
Comms.OnWhisper = OnWhisper

local function OfflinePattern()
    if offlinePattern then return offlinePattern end
    local fmt = gsub(gsub(ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing.", "%%%d?%$?s", "\001"),
        "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    offlinePattern = "^" .. gsub(fmt, "\001", "(.+)") .. "$"
    return offlinePattern
end

-- "No player named X is playing" right after we whispered X: theirs, hidden.
local function HideOffline(_, _, msg)
    if not talking or type(msg) ~= "string" or Secret(msg) then return false end
    local name = match(msg, OfflinePattern())
    if not name then return false end
    local at = whisperedAt[Key(name)]
    if not at or GetTime() - at > OFFLINE_WINDOW then return false end
    WentOffline(name)
    return true
end

local function ClearComms()
    wipe(outTo)
    wipe(outText)
    budget, flushAt = SEND_BURST, nil
    wipe(cardAsks)
    wipe(myApps)
    wipe(incomingApps)
    wipe(whisperedAt)
    whisperedCount = 0
    wipe(floodStart)
    wipe(floodCount)
    floodPlayers = 0
    wipe(answeredAt)
    answeredPlayers, answerWindowAt, answersInWindow = 0, -ANSWER_WINDOW, 0
    wipe(cardsByName)
    cardCount = 0
    expiryGen, expiryAt = expiryGen + 1, nil
end

-------------------------------------------------------------------------------
--  Listings: Forever's search results, with their dungeon as a Journal key
-------------------------------------------------------------------------------
local MEMBERS_MAX, LISTINGS_MAX, PREFIX_MIN = 5, 100, 4
local Listings = { listingsList = {}, n = 0, state = "none", searched = false }
GF.Listings = Listings
local listingsList = Listings.listingsList
local dirty = true
local dungeonByActivity, activityCache = {}, {}
local keyByName, keyByMap, plainNames

local function Simplify(name) return (gsub(gsub(lower(name), "^the ", ""), "[%s%p]", "")) end

local function IndexDungeons()
    if keyByName then return end
    keyByName, keyByMap, plainNames = {}, {}, {}
    for _, journalRow in ipairs(J.dungeons) do
        local plain = Simplify(journalRow.name)
        keyByName[plain] = journalRow.key
        plainNames[#plainNames + 1] = plain
        if journalRow.instance then keyByMap[journalRow.instance] = keyByMap[journalRow.instance] == nil and journalRow.key or false end
    end
end

local function MatchDungeon(fullName, mapID)
    local plain = Simplify(fullName)
    if keyByName[plain] then return keyByName[plain] end
    if #plain >= PREFIX_MIN then
        local best
        for i = 1, #plainNames do
            local name = plainNames[i]
            if sub(plain, 1, #name) == name and (not best or #name > #best) then best = name end
        end
        if best then return keyByName[best] end
        local only, howMany = nil, 0
        for i = 1, #plainNames do
            if sub(plainNames[i], 1, #plain) == plain then only, howMany = plainNames[i], howMany + 1 end
        end
        if howMany == 1 then return keyByName[only] end
    end
    return mapID and keyByMap[mapID] or false
end

function Listings.JournalKey(activityID)
    local nameKey = dungeonByActivity[activityID]
    if nameKey ~= nil then return nameKey or nil end
    IndexDungeons()
    local res = C_LFGList.GetActivityInfoTable(activityID)
    local name = res and res.fullName
    if type(name) ~= "string" or Secret(name) or Secret(res.mapID) then return nil end
    nameKey = MatchDungeon(name, res.mapID)
    dungeonByActivity[activityID] = nameKey
    return nameKey or nil
end

function Listings.ActivityFacts(activityID)
    local act = activityCache[activityID]
    if act then return act end
    local res = C_LFGList.GetActivityInfoTable(activityID)
    if not res or Secret(res.fullName) or Secret(res.shortName) then return nil end
    act = {
        name = res.fullName,
        short = (res.shortName and res.shortName ~= "") and res.shortName or res.fullName,
        min = res.minLevelSuggestion or 0,
        max = res.maxLevelSuggestion or 0,
        size = res.maxNumPlayers or 5,
    }
    activityCache[activityID] = act
    return act
end

local function RoleCounts(lst, ref)
    local roleTotals = C_LFGList.GetSearchResultMemberCounts and C_LFGList.GetSearchResultMemberCounts(ref)
    local tankCount, healerCount, damageCount = roleTotals and roleTotals.TANK, roleTotals and roleTotals.HEALER, roleTotals and roleTotals.DAMAGER
    if Secret(tankCount) or Secret(healerCount) or Secret(damageCount) then tankCount, healerCount, damageCount = nil, nil, nil end
    lst.tankCount, lst.healerCount, lst.damageCount = tankCount or 0, healerCount or 0, damageCount or 0
end

local function ReadResult(lst, ref)
    local res = C_LFGList.GetSearchResultInfo(ref)
    if not res then return false end
    local leadName, howMany, ageSecs, gone, acts = res.leaderName, res.numMembers, res.age, res.isDelisted, res.activityIDs
    if Secret(leadName) or Secret(howMany) or Secret(ageSecs) or Secret(gone) or Secret(acts) then return false end
    if type(howMany) ~= "number" or type(acts) ~= "table" then return false end
    local act = acts[1]
    if Secret(act) then return false end
    lst.ref, lst.leader, lst.numMembers = ref, type(leadName) == "string" and leadName or nil, howMany
    lst.age, lst.delisted = type(ageSecs) == "number" and ageSecs or 0, gone == true
    lst.mine = not Secret(res.hasSelf) and res.hasSelf == true
    lst.activity = act
    lst.dungeon = act and Listings.JournalKey(act) or nil
    RoleCounts(lst, ref)
    local roster, n = lst.members, 0
    for m = 1, math.min(howMany, MEMBERS_MAX) do
        local pl = C_LFGList.GetSearchResultPlayerInfo(ref, m)
        local roles = pl and pl.lfgRoles
        if roles and not (Secret(pl.name) or Secret(pl.level) or Secret(pl.classFilename) or Secret(pl.isLeader)
            or Secret(roles.tank) or Secret(roles.healer) or Secret(roles.dps)) then
            n = n + 1
            local m2 = roster[n] or {}
            roster[n] = m2
            m2.name, m2.level, m2.class = pl.name, pl.level, pl.classFilename
            m2.roles, m2.leader = Card.RoleBits(roles.tank, roles.healer, roles.dps), pl.isLeader == true
            local zone = pl.areaName
            m2.zone = not Secret(zone) and zone ~= "" and zone or nil
        end
    end
    lst.nMembers = n
    return true
end

function Listings.Refresh(force)
    if ChatLocked() then
        Listings.state, Listings.n, dirty = "locked", 0, true
        return 0
    end
    if not (dirty or force) then return Listings.n end
    local getter = C_LFGList.GetFilteredSearchResults or C_LFGList.GetSearchResults
    local _, results = getter()
    results = results or {}
    local n = 0
    for i = 1, math.min(#results, LISTINGS_MAX) do
        local lst = listingsList[n + 1]
        if not lst then
            lst = { members = {} }
            listingsList[n + 1] = lst
        end
        if ReadResult(lst, results[i]) then n = n + 1 end
    end
    Listings.n, Listings.state, dirty = n, "ready", false
    return n
end

-------------------------------------------------------------------------------
--  Search: the activities for your level, all of them, or one
-------------------------------------------------------------------------------
local LEVEL, ALL = "level", "all"
local Search = { state = "idle", pick = LEVEL, LEVEL = LEVEL, ALL = ALL }
GF.Search = Search
local searchFor = {}
local searchGen = 0

local function Listed(lst, ref)
    for _, listed in ipairs(lst and lst.activityIDs or {}) do
        if listed == ref then return true end
    end
    return false
end

local function FitsLevel(act, level)
    return not ((act.min > 0 and act.min > level) or (act.max > 0 and act.max < level))
end

local function ChooseActivities(categoryID, level, lst)
    wipe(searchFor)
    local suited, pick = false, Search.pick
    for _, ref in ipairs(C_LFGList.GetAvailableActivities(categoryID) or {}) do
        local act = Listings.ActivityFacts(ref)
        local suits = act ~= nil and FitsLevel(act, level)
        suited = suited or suits
        if pick == ALL or pick == ref or (pick == LEVEL and (suits or Listed(lst, ref))) then searchFor[#searchFor + 1] = ref end
    end
    return suited
end

local function PickCategory()
    local level, lst = UnitLevel("player"), C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
    local categories = C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableCategories() or {}
    for i = 1, #categories do
        if ChooseActivities(categories[i], level, lst) then return categories[i] end
    end
end

function Search.FitsLevel(activityID)
    local act = Listings.ActivityFacts(activityID)
    return act ~= nil and FitsLevel(act, UnitLevel("player"))
end

function Search.ActivityList(items)
    wipe(items)
    local category = PickCategory()
    if not category then return 0 end
    for _, ref in ipairs(C_LFGList.GetAvailableActivities(category) or {}) do
        if Listings.ActivityFacts(ref) then items[#items + 1] = ref end
    end
    table.sort(items, function(a, b)
        local x, y = Listings.ActivityFacts(a), Listings.ActivityFacts(b)
        if x.min ~= y.min then return x.min < y.min end
        return x.name < y.name
    end)
    return #items
end

local function SetState(state)
    searchGen = searchGen + 1
    Search.state = state
    GF.Notify("search", state)
end

-- The game keeps searching to its own Group Finder (C_LFGList.Search is
-- protected), so the pick filters what that finds: the listings of the picked
-- dungeons, or every one.
local wanted = {}
function Search.Run(pick)
    if not GF.On() then return false end
    Search.pick = pick or Search.pick
    wipe(wanted)
    if not PickCategory() then
        SetState("unavailable")
        return false
    end
    for _, ref in ipairs(searchFor) do
        wanted[ref] = true
    end
    GF.Notify("search", Search.state)
    return true
end

function Search.Wants(lst)
    if Search.pick == ALL or not next(wanted) then return true end
    return lst.activity == nil or wanted[lst.activity] == true
end

-------------------------------------------------------------------------------
--  Browse: each listed leader asked once for their card; filter and sorts
-------------------------------------------------------------------------------
local REASK_AFTER, ASKED_MAX = 300, 200
local Browse = {}
GF.Browse = Browse
local askedAt, noCard, askedCount = {}, {}, 0

function Browse.Request()
    local clock = GetTime()
    for i = 1, Listings.n do
        local lst = listingsList[i]
        local leadName = lst.leader
        if leadName and not lst.delisted and not Comms.IsMe(leadName) and not Comms.KnownCard(leadName) then
            local nameKey = Key(leadName)
            local at = askedAt[nameKey]
            if not at or clock - at > REASK_AFTER then
                if not Comms.AskCard(leadName, lst.dungeon) then return end
                noCard[nameKey] = nil
                if not askedAt[nameKey] then
                    if askedCount >= ASKED_MAX then
                        wipe(askedAt)
                        wipe(noCard)
                        askedCount = 0
                    end
                    askedCount = askedCount + 1
                end
                askedAt[nameKey] = clock
            end
        end
    end
end

function Browse.Apply(leadName, dungeonKey)
    local ref = Comms.Apply(leadName, dungeonKey, MyRoles(), "")
    GF.Notify("applied")
    return ref
end

-- The leader's card, and whether one is still awaited.
function Browse.KnownCard(leadName)
    local cardRec = Comms.KnownCard(leadName)
    if cardRec then return cardRec, false end
    local nameKey = Key(leadName)
    return nil, askedAt[nameKey] ~= nil and not noCard[nameKey]
end

local function Contains(textLine, needle) return textLine ~= nil and find(lower(textLine), needle, 1, true) ~= nil end
function Browse.PassesFilter(lst, needle)
    if needle == "" then return true end
    local act = lst.activity and Listings.ActivityFacts(lst.activity)
    local cardRec = lst.leader and Comms.KnownCard(lst.leader)
    local groupInfo = cardRec and cardRec.group
    return Contains(act and act.name, needle) or Contains(act and act.short, needle) or Contains(lst.leader, needle)
        or Contains(groupInfo and groupInfo.memo, needle)
end

local ORDERINGS = {
    newest = function(a, b)
        if a.mine ~= b.mine then return a.mine end
        return a.age < b.age
    end,
    score = function(a, b)
        if a.mine ~= b.mine then return a.mine end
        if a.leaderScore ~= b.leaderScore then return a.leaderScore > b.leaderScore end
        return a.age < b.age
    end,
    level = function(a, b)
        if a.mine ~= b.mine then return a.mine end
        if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
        return a.age < b.age
    end,
}
function Browse.Order(order, how)
    for i = 1, #order do
        local lst = order[i]
        local cardRec = lst.leader and Comms.KnownCard(lst.leader)
        local act = lst.activity and Listings.ActivityFacts(lst.activity)
        lst.leaderScore = cardRec and cardRec.score or -1
        lst.minLevel = act and act.min or math.huge
    end
    table.sort(order, ORDERINGS[how] or ORDERINGS.newest)
end

local function NoAnswer(cardAsk)
    local nameKey = Key(cardAsk.name)
    if askedAt[nameKey] then noCard[nameKey] = true end
end
GF.Subscribe("noreply", NoAnswer)
GF.Subscribe("offline", NoAnswer)

-------------------------------------------------------------------------------
--  Events and on/off
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a, b, c, d)
    if event == "CHAT_MSG_ADDON" then
        local lead, textLine, channel, whisperer = a, b, c, d
        if Secret(lead) or lead ~= PREFIX then return end
        if Secret(textLine) or Secret(channel) or Secret(whisperer) then return end
        if channel ~= WHISPER or type(textLine) ~= "string" or type(whisperer) ~= "string" or whisperer == "" then return end
        OnWhisper(textLine, whisperer)
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        dirty, Listings.searched = true, true
        SetState("done")
        GF.Notify("listings", false)
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        Listings.n, Listings.state, Listings.searched, dirty = 0, "failed", true, false
        SetState("failed")
        GF.Notify("listings", true)
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        if dirty or Secret(a) then return end
        for i = 1, Listings.n do
            local lst = listingsList[i]
            if lst.ref == a then
                if ChatLocked() or not ReadResult(lst, a) then dirty = true end
                GF.Notify("listing", lst)
                return
            end
        end
    else -- LFG_LIST_ACTIVE_ENTRY_UPDATE, GROUP_ROSTER_UPDATE, PARTY_LEADER_CHANGED
        if not Group.Listed() then Group.ours, Group.listedAt = false, nil end
        GF.Notify("group")
    end
end)

local EVENTS = {
    "CHAT_MSG_ADDON", "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_FAILED", "LFG_LIST_SEARCH_RESULT_UPDATED",
    "LFG_LIST_ACTIVE_ENTRY_UPDATE", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED",
}

local function Apply()
    local want = Enabled() and C_LFGList ~= nil
    if want == talking then return end
    talking = want
    if want then
        if not prefixDone then
            prefixDone = true
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        myKey = Key(GetUnitName("player", true) or UnitName("player") or "?")
        for _, event in ipairs(EVENTS) do
            events:RegisterEvent(event)
        end
        if AddFilter then AddFilter("CHAT_MSG_SYSTEM", HideOffline) end
    else
        events:UnregisterAllEvents()
        if RemoveFilter then RemoveFilter("CHAT_MSG_SYSTEM", HideOffline) end
        ClearComms()
        Listings.n, Listings.state, Listings.searched, dirty = 0, "none", false, true
        searchGen = searchGen + 1
        Search.state, Search.pick = "idle", LEVEL
        Group.ours, Group.listedAt = false, nil
        wipe(askedAt)
        wipe(noCard)
        askedCount = 0
    end
    GF.Notify("enabled", want)
end
GF.Apply = Apply

CUI._LFG = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    GF = GF,
}

F.Start(Apply)
