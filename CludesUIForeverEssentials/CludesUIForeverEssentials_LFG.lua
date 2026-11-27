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
local listeners = {}
function GF.On() return Enabled() end
function GF.Listen(what, fn)
    local list = listeners[what]
    if not list then
        list = {}
        listeners[what] = list
    end
    list[#list + 1] = fn
end
function GF.Fire(what, a, b, c, d)
    local list = listeners[what]
    if not list then return end
    for i = 1, #list do
        list[i](a, b, c, d)
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
local KEY_PATTERN = "^%u%w*$"
local SPEC_PATTERN = "^[%l%-]+$"
local NOTE_BAD = "[^\32-\123\125\126]"
local ESCAPES = { "|c%x%x%x%x%x%x%x%x", "|H.-|h", "|T.-|t", "|A.-|a", "|K.-|k", "|[rh]" }
local NONE, SPACE = "-", " "
local VERSION_BYTE, NONE_BYTE, SPACE_BYTE = byte(VERSION), byte(NONE), byte(SPACE)
local ZERO, NINE = byte("0"), byte("9")
local KINDS = {}
for _, kind in ipairs({ "Q", "C", "A", "K", "X", "D", "L" }) do
    KINDS[byte(kind)] = kind
end
local TANK, HEALER, DAMAGE = 4, 2, 1
Card.TANK, Card.HEALER, Card.DAMAGE = TANK, HEALER, DAMAGE
local ROLE_CODE = { [0] = NONE, "D", "H", "HD", "T", "TD", "TH", "THD" }
local ROLE_BIT = { [byte("T")] = TANK, [byte("H")] = HEALER, [byte("D")] = DAMAGE }
local QUEST_ID, QUEST_SIDE = 1, 4
local SIDE = { Alliance = "A", Horde = "H" }
local lastTenths
local out = {}

function Card.New()
    return { kills = {}, have = {}, need = {}, nKills = 0, nHave = 0, nNeed = 0, roles = 0 }
end
local mine = Card.New()

function Card.Roles(tank, healer, damage)
    return (tank and TANK or 0) + (healer and HEALER or 0) + (damage and DAMAGE or 0)
end
function Card.RoleCode(bits) return ROLE_CODE[bits] or NONE end

local function Trim(t, n)
    for i = #t, n + 1, -1 do
        t[i] = nil
    end
end

-- The roles saved in the game's group finder (tank, healer, damage).
local function SavedRoles()
    local roles = C_LFGListRoles and C_LFGListRoles.GetRoles and C_LFGListRoles.GetRoles()
    if not roles then return DAMAGE end
    return Card.Roles(roles.tank, roles.healer, roles.dps)
end
Card.SavedRoles = SavedRoles

local function Tenths()
    local GS = CUI._GearScore
    if not (GS and GS.Score and GS.Score.Unit) then return lastTenths end
    local score, complete = GS.Score.Unit("player")
    if complete and type(score) == "number" then
        local tenths = floor(score * 10 + 0.5)
        if tenths >= 0 and tenths <= SCORE_MAX then lastTenths = tenths end
    end
    return lastTenths
end

local function Bosses(dungeon)
    local list = {}
    for _, wing in ipairs(dungeon.wings or {}) do
        for _, boss in ipairs(wing.bosses or {}) do
            if boss.encounters and not boss.trash then list[#list + 1] = boss end
        end
    end
    return list
end
GF.Bosses = Bosses

local function FillKills(card, dungeon)
    local Kills = module.BossKills
    if not Kills then return false end
    local n = 0
    for _, boss in ipairs(Bosses(dungeon)) do
        if n >= MAX_KILLS then break end
        local count = Kills.Count(boss)
        n = n + 1
        card.kills[n] = count > KILL_CAP and KILL_CAP or count
    end
    Trim(card.kills, n)
    card.nKills = n
    return n > 0
end

local function QuestList(dungeon)
    if J.Prepare then J.Prepare() end
    return dungeon.questInfo and dungeon.questInfo.quests
end
GF.QuestList = QuestList

local function ForMe(quest)
    local side = quest[QUEST_SIDE]
    return side == "B" or side == SIDE[UnitFactionGroup("player") or ""]
end
GF.ForMe = ForMe

local function FillQuests(card, dungeon)
    local list = QuestList(dungeon)
    local have, need, nh, nn = card.have, card.need, 0, 0
    for i = 1, list and #list or 0 do
        local quest = list[i]
        local id = quest[QUEST_ID]
        if ForMe(quest) then
            if C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then
                if nh < MAX_QUESTS then
                    nh = nh + 1
                    have[nh] = id
                end
            elseif not (C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)) and nn < MAX_QUESTS then
                nn = nn + 1
                need[nn] = id
            end
        end
    end
    Trim(have, nh)
    Trim(need, nn)
    card.nHave, card.nNeed = nh, nn
    return true
end

function Card.Mine(dungeonKey, roles)
    local card = mine
    local _, _, classID = UnitClass("player")
    card.class = classID
    card.level = UnitLevel("player")
    card.roles = roles or SavedRoles()
    card.spec = nil
    card.score = Get("shareScore") and Tenths() or nil
    card.bisHave, card.bisTotal = nil, nil
    local dungeon = dungeonKey and J.byKey[dungeonKey]
    card.dungeon = dungeon and dungeonKey or nil
    card.hasKills = dungeon and Get("shareKills") and FillKills(card, dungeon) or false
    card.hasQuests = dungeon and Get("shareQuests") and FillQuests(card, dungeon) or false
    if not card.hasKills then
        card.nKills = 0
        Trim(card.kills, 0)
    end
    if not card.hasQuests then
        card.nHave, card.nNeed = 0, 0
        Trim(card.have, 0)
        Trim(card.need, 0)
    end
    return card
end

local function Joined(t, n)
    if n == 0 then return "" end
    return concat(t, ",", 1, n)
end

local function Body(card, n, questCap, kills)
    out[n + 1] = card.class
    out[n + 2] = card.level
    out[n + 3] = ROLE_CODE[card.roles] or NONE
    out[n + 4] = card.spec or NONE
    out[n + 5] = card.score or NONE
    out[n + 6] = card.bisTotal and (card.bisHave .. "/" .. card.bisTotal) or NONE
    out[n + 7] = card.dungeon or NONE
    out[n + 8] = (card.dungeon and kills and card.hasKills and card.nKills > 0) and Joined(card.kills, card.nKills)
        or NONE
    if card.dungeon and card.hasQuests then
        local nh = card.nHave < questCap and card.nHave or questCap
        local nn = card.nNeed < questCap and card.nNeed or questCap
        out[n + 9] = Joined(card.have, nh) .. "/" .. Joined(card.need, nn)
    else
        out[n + 9] = NONE
    end
    return n + 9
end

-- A card that would not fit loses its quest lists first, then its kills.
local function WithCard(kind, id, card, note, group)
    local cap, kills = MAX_QUESTS, true
    while true do
        out[1], out[2], out[3] = VERSION, kind, id
        local n = Body(card, 3, cap, kills)
        if group then
            out[n + 1] = group.min > 0 and group.min or NONE
            out[n + 2] = group.tanks .. group.healers .. group.damage
            n = n + 2
        end
        if note then
            n = n + 1
            out[n] = note
        end
        local text = concat(out, SPACE, 1, n)
        if #text <= MAX_BYTES then return text end
        if cap > 0 then
            cap = cap - 1
        elseif kills then
            kills = false
        else
            return nil
        end
    end
end

function Card.Reply(nonce, card, group)
    if not group then return WithCard("C", nonce, card) end
    return WithCard("L", nonce, card, group.note ~= "" and group.note or nil, group)
end
function Card.Application(id, card, note) return WithCard("A", id, card, note ~= "" and note or nil) end
function Card.Ask(nonce, dungeonKey)
    out[1], out[2], out[3], out[4] = VERSION, "Q", nonce, dungeonKey or NONE
    return concat(out, SPACE, 1, 4)
end
function Card.Short(kind, id)
    out[1], out[2], out[3] = VERSION, kind, id
    return concat(out, SPACE, 1, 3)
end

function Card.CleanNote(text)
    if type(text) ~= "string" then return "" end
    for i = 1, #ESCAPES do
        text = gsub(text, ESCAPES[i], "")
    end
    text = gsub(gsub(gsub(text, "%s+", SPACE), NOTE_BAD, ""), "  +", SPACE)
    text = gsub(gsub(text, "^ ", ""), " $", "")
    if #text > NOTE_MAX then text = gsub(sub(text, 1, NOTE_MAX), " $", "") end
    return text
end

local function Field(s, pos, len)
    if pos > len then return nil end
    local space = find(s, SPACE, pos, true)
    if space == pos then return nil end
    if space then return pos, space - 1, space + 1 end
    return pos, len, len + 1
end

local function Int(s, i, j, max)
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

local function IsNone(s, i, j) return i == j and byte(s, i) == NONE_BYTE end

local function Text(s, i, j, max, pattern)
    if j - i + 1 > max then return nil end
    local text = sub(s, i, j)
    if not find(text, pattern) then return nil end
    return text
end

local function ParseRoles(s, i, j)
    if IsNone(s, i, j) then return 0 end
    if j - i >= ROLES_MAX then return nil end
    local bits, last = 0, TANK + 1
    for k = i, j do
        local b = ROLE_BIT[byte(s, k)]
        if not b or b >= last then return nil end
        bits, last = bits + b, b
    end
    return bits
end

local function Slash(s, i, j)
    local slash = find(s, "/", i, true)
    if not slash or slash > j then return nil end
    local again = find(s, "/", slash + 1, true)
    if again and again <= j then return nil end
    return slash
end

local function List(s, i, j, t, max, cap, low)
    if i > j then
        Trim(t, 0)
        return 0
    end
    local n, at = 0, i
    while true do
        local comma = find(s, ",", at, true)
        local e = (comma and comma <= j) and comma - 1 or j
        local v = Int(s, at, e, cap)
        if not v or v < low or n >= max then return nil end
        n = n + 1
        t[n] = v
        if e == j then break end
        at = e + 2
        if at > j then return nil end
    end
    Trim(t, n)
    return n
end

local function ParseBody(s, pos, len, card)
    local i, j
    i, j, pos = Field(s, pos, len)
    card.class = i and Int(s, i, j, CLASS_MAX)
    if not card.class or card.class < 1 then return nil end
    i, j, pos = Field(s, pos, len)
    card.level = i and Int(s, i, j, LEVEL_MAX)
    if not card.level or card.level < 1 then return nil end
    i, j, pos = Field(s, pos, len)
    card.roles = i and ParseRoles(s, i, j)
    if not card.roles then return nil end
    i, j, pos = Field(s, pos, len)
    if not i then return nil end
    if IsNone(s, i, j) then
        card.spec = nil
    else
        card.spec = Text(s, i, j, SPEC_MAX, SPEC_PATTERN)
        if not card.spec then return nil end
    end
    i, j, pos = Field(s, pos, len)
    if not i then return nil end
    if IsNone(s, i, j) then
        card.score = nil
    else
        card.score = Int(s, i, j, SCORE_MAX)
        if not card.score then return nil end
    end
    i, j, pos = Field(s, pos, len)
    if not i then return nil end
    if IsNone(s, i, j) then
        card.bisHave, card.bisTotal = nil, nil
    else
        local slash = Slash(s, i, j)
        local have = slash and Int(s, i, slash - 1, BIS_MAX)
        local total = have and Int(s, slash + 1, j, BIS_MAX)
        if not total or total < 1 or have > total then return nil end
        card.bisHave, card.bisTotal = have, total
    end
    i, j, pos = Field(s, pos, len)
    if not i then return nil end
    if IsNone(s, i, j) then
        card.dungeon = nil
    else
        card.dungeon = Text(s, i, j, KEY_MAX, KEY_PATTERN)
        if not card.dungeon then return nil end
    end
    i, j, pos = Field(s, pos, len)
    if not i then return nil end
    if IsNone(s, i, j) then
        card.hasKills, card.nKills = false, 0
        Trim(card.kills, 0)
    else
        local n = card.dungeon and List(s, i, j, card.kills, MAX_KILLS, KILL_CAP, 0)
        if not n or n < 1 then return nil end
        card.hasKills, card.nKills = true, n
    end
    i, j, pos = Field(s, pos, len)
    if not i then return nil end
    if IsNone(s, i, j) then
        card.hasQuests, card.nHave, card.nNeed = false, 0, 0
        Trim(card.have, 0)
        Trim(card.need, 0)
    else
        local slash = card.dungeon and Slash(s, i, j)
        local nh = slash and List(s, i, slash - 1, card.have, MAX_QUESTS, QUEST_ID_MAX, 1)
        local nn = nh and List(s, slash + 1, j, card.need, MAX_QUESTS, QUEST_ID_MAX, 1)
        if not nn then return nil end
        card.hasQuests, card.nHave, card.nNeed = true, nh, nn
    end
    return pos, j
end

local function Note(text, pos, len)
    if pos > len or byte(text, pos) == SPACE_BYTE then return nil end
    local note = sub(text, pos)
    if #note > NOTE_MAX or find(note, NOTE_BAD) or byte(note, #note) == SPACE_BYTE then return nil end
    return note
end

local function Digit(s, k)
    local b = byte(s, k)
    if b < ZERO or b > NINE then return nil end
    return b - ZERO
end

local function ParseGroup(s, pos, len, group)
    local i, j
    i, j, pos = Field(s, pos, len)
    if not i then return nil end
    if IsNone(s, i, j) then
        group.min = 0
    else
        group.min = Int(s, i, j, SCORE_MAX)
        if not group.min or group.min < 1 then return nil end
    end
    i, j, pos = Field(s, pos, len)
    if not i or j - i + 1 ~= NEEDS_DIGITS then return nil end
    group.tanks, group.healers, group.damage = Digit(s, i), Digit(s, i + 1), Digit(s, i + 2)
    if not (group.tanks and group.healers and group.damage) then return nil end
    return pos, j
end

-- Returns kind, id, extra (Q: the dungeon key; C/A/L: the note), or nil.
function Card.Decode(text, card, group)
    if type(text) ~= "string" then return nil end
    local len = #text
    if len > MAX_BYTES then return nil end
    local i, j, pos = Field(text, 1, len)
    if not i or j ~= i or byte(text, i) ~= VERSION_BYTE then return nil end
    i, j, pos = Field(text, pos, len)
    local kind = i and i == j and KINDS[byte(text, i)]
    if not kind then return nil end
    i, j, pos = Field(text, pos, len)
    local id = i and Int(text, i, j, ID_MAX)
    if not id or id < 1 then return nil end
    if kind == "Q" then
        i, j = Field(text, pos, len)
        if not i or j ~= len then return nil end
        if IsNone(text, i, j) then return kind, id, nil end
        local key = Text(text, i, j, KEY_MAX, KEY_PATTERN)
        if not key then return nil end
        return kind, id, key
    end
    if kind == "C" or kind == "A" or kind == "L" then
        if not card then return nil end
        pos, j = ParseBody(text, pos, len, card)
        if not pos then return nil end
        if kind == "L" then
            if not group or j == len then return nil end
            pos, j = ParseGroup(text, pos, len, group)
            if not pos then return nil end
        end
        if j == len then return kind, id, nil end
        if kind == "C" then return nil end
        local note = Note(text, pos, len)
        if not note then return nil end
        return kind, id, note
    end
    if j ~= len then return nil end
    return kind, id
end

end
local find, sub, gsub, concat = string.find, string.sub, string.gsub, table.concat
local ID_MAX, SavedRoles = Card.ID_MAX, Card.SavedRoles

-------------------------------------------------------------------------------
--  Group: your listing in Forever's group finder
-------------------------------------------------------------------------------
local Group = { activity = nil, style = nil, min = 0, tanks = 1, healers = 1, damage = 3, note = "", ours = false, listedAt = nil }
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
    GF.Fire("group")
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
local BURST, RATE = 10, 1
local QUEUE_MAX = 30
local LOCKDOWN_RETRY = 2
local PING_WAIT = 10
local APP_TTL = 600
local SENDER_WINDOW, SENDER_MAX, SENDERS_MAX = 10, 8, 200
local ANSWER_GAP, ANSWERS_MAX, ANSWERS_WINDOW, ASKERS_MAX = 30, 5, 10, 40
local NOT_FOUND_WINDOW, WHISPERED_MAX = 10, 40
local MAX_PINGS, MAX_SENT, MAX_APPLICANTS, MAX_CARDS = 20, 10, 40, 100
local RESULT = Enum.SendAddonMessageResult or {}
local CARD_LISTS = { "kills", "have", "need" }
local Comms = { pings = {}, sent = {}, applicants = {}, APP_TTL = APP_TTL }
GF.Comms = Comms
local pings, sent, applicants = Comms.pings, Comms.sent, Comms.applicants
local LISTS = { pings, sent, applicants }
local commsOn, commsFrame, prefixed, ownKey = false, nil, false, nil
local qTarget, qText = {}, {}
local tokens, refilled, drainAt = BURST, 0, nil
local whispered, nWhispered = {}, 0
local senderCount, senderStart, senderN = {}, {}, 0
local askers, nAskers = {}, 0
local windowAt, answeredCount = -ANSWERS_WINDOW, 0
local cards, nCards = {}, 0
local nextId = 0
local sweepGen, sweepAt = 0, nil
local incoming = Card.New()
local incomingGroup = { min = 0, tanks = 0, healers = 0, damage = 0, note = "" }
local notFound
local AddFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
local RemoveFilter = (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter) or ChatFrame_RemoveMessageEventFilter

local function Key(name) return lower(Ambiguate(name, "none")) end
Comms.Key = Key
function Comms.IsMe(name) return Key(name) == ownKey end

local function NamePart(key)
    local dash = find(key, "-", 1, true)
    return dash and sub(key, 1, dash - 1) or key, dash ~= nil
end

-- Forever's listings name the leader without a realm, so a name with no
-- realm matches the same name with one.
local function SameName(a, b)
    local ka, kb = Key(a), Key(b)
    if ka == kb then return true end
    local na, realmA = NamePart(ka)
    local nb, realmB = NamePart(kb)
    return not (realmA and realmB) and na == nb
end

local function NextId()
    nextId = nextId % ID_MAX + 1
    return nextId
end

local function Find(list, id, name)
    for i = 1, #list do
        local record = list[i]
        if (not id or record.id == id) and SameName(record.name, name) then return record, i end
    end
end

local function CancelQueued(record, kind)
    local prefix = Card.Short(kind, record.id) .. " "
    local cancelled = false
    for i = #qText, 1, -1 do
        if (sub(qText[i], 1, #prefix) == prefix or qText[i] == Card.Short(kind, record.id)) and SameName(qTarget[i], record.name) then
            remove(qTarget, i)
            remove(qText, i)
            cancelled = true
        end
    end
    return cancelled
end

local Sweep
local function Earliest()
    local at
    for l = 1, #LISTS do
        local list = LISTS[l]
        for i = 1, #list do
            local deadline = list[i].deadline
            if not at or deadline < at then at = deadline end
        end
    end
    return at
end

local function ScheduleSweep()
    local at = Earliest()
    if not at then
        sweepAt = nil
        sweepGen = sweepGen + 1
        return
    end
    if sweepAt and sweepAt <= at then return end
    sweepGen = sweepGen + 1
    sweepAt = at
    local gen = sweepGen
    C_Timer.After(max(0, at - GetTime()), function() Sweep(gen) end)
end

local function Expire(list, now, what, kind)
    for i = #list, 1, -1 do
        local record = list[i]
        if record.deadline <= now then
            if kind then CancelQueued(record, kind) end
            remove(list, i)
            GF.Fire(what, record)
        end
    end
end

function Sweep(gen)
    if gen ~= sweepGen or not commsOn then return false end
    sweepAt = nil
    local now = GetTime()
    Expire(pings, now, "noreply", "Q")
    Expire(sent, now, "expired", "A")
    Expire(applicants, now, "applicantExpired")
    ScheduleSweep()
    return true
end

local Drain
local function DrainLater(delay)
    local at = GetTime() + delay
    if drainAt and drainAt <= at then return end
    drainAt = at
    C_Timer.After(delay, Drain)
end

local function Whispered(target)
    local key = Key(target)
    if not whispered[key] then
        if nWhispered >= WHISPERED_MAX then
            wipe(whispered)
            nWhispered = 0
        end
        nWhispered = nWhispered + 1
    end
    whispered[key] = GetTime()
end

local function Offline(name)
    for i = #pings, 1, -1 do
        local ping = pings[i]
        if SameName(ping.name, name) then
            remove(pings, i)
            GF.Fire("offline", ping)
        end
    end
end

local function Locked()
    return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

function Drain()
    drainAt = nil
    if not commsOn then return end
    while #qText > 0 do
        if Locked() then return DrainLater(LOCKDOWN_RETRY) end
        local now = GetTime()
        tokens = tokens + (now - refilled) * RATE
        if tokens > BURST then tokens = BURST end
        refilled = now
        if tokens < 1 then return DrainLater((1 - tokens) / RATE) end
        local target = qTarget[1]
        Whispered(target)
        local result = C_ChatInfo.SendAddonMessage(PREFIX, qText[1], WHISPER, target)
        if result ~= nil and (result == RESULT.AddonMessageThrottle or result == RESULT.ChannelThrottle) then
            tokens = 0
            return DrainLater(1 / RATE)
        end
        if result ~= nil and result == RESULT.AddOnMessageLockdown then return DrainLater(LOCKDOWN_RETRY) end
        remove(qTarget, 1)
        remove(qText, 1)
        tokens = tokens - 1
        if result ~= nil and result == RESULT.TargetOffline then Offline(target) end
    end
end

local function Send(target, text)
    if not (commsOn and target and text) then return false end
    for i = 1, #qText do
        if qTarget[i] == target and qText[i] == text then return true end
    end
    if #qText >= QUEUE_MAX then return false end
    qTarget[#qTarget + 1] = target
    qText[#qText + 1] = text
    if not drainAt then Drain() end
    return true
end
Comms.Send = Send

function Comms.Ping(name, dungeonKey)
    if not commsOn or #pings >= MAX_PINGS or #qText >= QUEUE_MAX then return nil end
    local nonce = NextId()
    local now = GetTime()
    pings[#pings + 1] = { id = nonce, name = name, dungeon = dungeonKey, sentAt = now, deadline = now + PING_WAIT }
    Send(name, Card.Ask(nonce, dungeonKey))
    ScheduleSweep()
    return nonce
end

function Comms.Apply(name, dungeonKey, roles, note)
    if not commsOn or #sent >= MAX_SENT then return nil end
    local id = NextId()
    local text = Card.Application(id, Card.Mine(dungeonKey, roles), Card.CleanNote(note))
    if not Send(name, text) then return nil end
    sent[#sent + 1] = { id = id, name = name, dungeon = dungeonKey, deadline = GetTime() + APP_TTL, acked = false, declined = false }
    ScheduleSweep()
    return id
end

function Comms.Withdraw(id)
    for i = 1, #sent do
        local record = sent[i]
        if record.id == id then
            if not CancelQueued(record, "A") and not Send(record.name, Card.Short("X", id)) then return false end
            remove(sent, i)
            ScheduleSweep()
            return true
        end
    end
    return false
end

function Comms.SentTo(name) return (Find(sent, nil, name)) end

function Comms.Decline(name)
    local record, i = Find(applicants, nil, name)
    if not record then return false end
    if not Send(record.name, Card.Short("D", record.id)) then return false end
    remove(applicants, i)
    ScheduleSweep()
    return true
end

function Comms.HasApplicant(record)
    for i = 1, #applicants do
        if applicants[i] == record then return true end
    end
    return false
end

local function Copy(from, to)
    to.class, to.level, to.roles, to.spec = from.class, from.level, from.roles, from.spec
    to.score, to.bisHave, to.bisTotal, to.dungeon = from.score, from.bisHave, from.bisTotal, from.dungeon
    to.hasKills, to.hasQuests = from.hasKills, from.hasQuests
    to.nKills, to.nHave, to.nNeed = from.nKills, from.nHave, from.nNeed
    for l = 1, #CARD_LISTS do
        local a, b = from[CARD_LISTS[l]], to[CARD_LISTS[l]]
        for i = 1, #a do
            b[i] = a[i]
        end
        for i = #b, #a + 1, -1 do
            b[i] = nil
        end
    end
    return to
end

local function Keep(name, card)
    local key = Key(name)
    local kept = cards[key]
    if not kept then
        if nCards >= MAX_CARDS then
            wipe(cards)
            nCards = 0
        end
        kept = Card.New()
        cards[key] = kept
        nCards = nCards + 1
    end
    return Copy(card, kept)
end

-- A listing names its leader without a realm while their whisper carries
-- one: a name with no realm finds the card kept under name-realm.
function Comms.CardOf(name)
    local key = Key(name)
    local card = cards[key]
    if card or find(key, "-", 1, true) then return card end
    local prefix = key .. "-"
    for kept, c in pairs(cards) do
        if sub(kept, 1, #prefix) == prefix then return c end
    end
end

local function MayAnswer(key, now)
    if now - windowAt >= ANSWERS_WINDOW then windowAt, answeredCount = now, 0 end
    if answeredCount >= ANSWERS_MAX then return false end
    local last = askers[key]
    if last and now - last < ANSWER_GAP then return false end
    if not last then
        if nAskers >= ASKERS_MAX then
            wipe(askers)
            nAskers = 0
        end
        nAskers = nAskers + 1
    end
    askers[key] = now
    answeredCount = answeredCount + 1
    return true
end

local Handle = {}
function Handle.Q(sender, id, dungeonKey, now)
    if not Group.Answering() or not MayAnswer(Key(sender), now) then return end
    Send(sender, Card.Reply(id, Card.Mine(dungeonKey), Group.Info()))
end

local function Answered(sender, id, now, group)
    local ping, i = Find(pings, id, sender)
    if not ping then return end
    local card = Keep(sender, incoming)
    if group then
        local kept = card.group or {}
        kept.min, kept.tanks, kept.healers, kept.damage, kept.note = group.min, group.tanks, group.healers, group.damage, group.note
        card.group = kept
    else
        card.group = nil
    end
    remove(pings, i)
    GF.Fire("card", sender, card, ping, now - ping.sentAt)
    ScheduleSweep()
end
function Handle.C(sender, id, _, now) Answered(sender, id, now, nil) end
function Handle.L(sender, id, note, now)
    incomingGroup.note = note or ""
    Answered(sender, id, now, incomingGroup)
end
function Handle.A(sender, id, note, now)
    if not Group.Answering() then return end
    local record = Find(applicants, nil, sender)
    if not record then
        if #applicants >= MAX_APPLICANTS then return end
        record = { card = Card.New() }
        applicants[#applicants + 1] = record
    end
    Copy(incoming, record.card)
    record.id, record.name, record.note = id, sender, note
    record.invited = false
    record.at, record.deadline = now, now + APP_TTL
    Send(sender, Card.Short("K", id))
    ScheduleSweep()
    GF.Fire("applicant", record)
end
function Handle.K(sender, id)
    local record = Find(sent, id, sender)
    if not record then return end
    record.acked = true
    GF.Fire("received", record)
end
function Handle.X(sender, id)
    local record, i = Find(applicants, id, sender)
    if not record then return end
    remove(applicants, i)
    GF.Fire("withdrawn", record)
    ScheduleSweep()
end
function Handle.D(sender, id)
    local record = Find(sent, id, sender)
    if not record then return end
    record.declined = true
    GF.Fire("declined", record)
end

local function Allowed(key, now)
    local start = senderStart[key]
    if not start or now - start > SENDER_WINDOW then
        if not start then
            senderN = senderN + 1
            if senderN > SENDERS_MAX then
                wipe(senderStart)
                wipe(senderCount)
                senderN = 1
            end
        end
        senderStart[key], senderCount[key] = now, 1
        return true
    end
    local n = senderCount[key] + 1
    senderCount[key] = n
    return n <= SENDER_MAX
end

local function OnMessage(text, sender)
    local key = Key(sender)
    if key == ownKey then return end
    if C_FriendList.IsIgnored and C_FriendList.IsIgnored(Ambiguate(sender, "none")) then return end
    local now = GetTime()
    if not Allowed(key, now) then return end
    local kind, id, extra = Card.Decode(text, incoming, incomingGroup)
    if not kind then return end
    Handle[kind](sender, id, extra, now)
end
Comms.OnMessage = OnMessage

local function NotFoundPattern()
    if notFound then return notFound end
    local fmt = gsub(gsub(ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing.", "%%%d?%$?s", "\001"),
        "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    notFound = "^" .. gsub(fmt, "\001", "(.+)") .. "$"
    return notFound
end

-- "No player named X is playing" right after we whispered X: theirs, hidden.
local function NotFoundFilter(_, _, msg)
    if not commsOn or type(msg) ~= "string" or Secret(msg) then return false end
    local name = match(msg, NotFoundPattern())
    if not name then return false end
    local at = whispered[Key(name)]
    if not at or GetTime() - at > NOT_FOUND_WINDOW then return false end
    Offline(name)
    return true
end

local function ResetComms()
    wipe(qTarget)
    wipe(qText)
    tokens, drainAt = BURST, nil
    wipe(pings)
    wipe(sent)
    wipe(applicants)
    wipe(whispered)
    nWhispered = 0
    wipe(senderStart)
    wipe(senderCount)
    senderN = 0
    wipe(askers)
    nAskers, windowAt, answeredCount = 0, -ANSWERS_WINDOW, 0
    wipe(cards)
    nCards = 0
    sweepGen, sweepAt = sweepGen + 1, nil
end

-------------------------------------------------------------------------------
--  Listings: Forever's search results, with their dungeon as a Journal key
-------------------------------------------------------------------------------
local MEMBERS_READ, MAX_ENTRIES, NAME_MIN = 5, 100, 4
local Listings = { entries = {}, n = 0, state = "none", searched = false }
GF.Listings = Listings
local entries = Listings.entries
local stale = true
local activityKey, activityInfo = {}, {}
local byName, byMap, names

local function Plain(name) return (gsub(gsub(lower(name), "^the ", ""), "[%s%p]", "")) end

local function Index()
    if byName then return end
    byName, byMap, names = {}, {}, {}
    for _, dungeon in ipairs(J.dungeons) do
        local plain = Plain(dungeon.name)
        byName[plain] = dungeon.key
        names[#names + 1] = plain
        if dungeon.instance then byMap[dungeon.instance] = byMap[dungeon.instance] == nil and dungeon.key or false end
    end
end

local function Match(fullName, mapID)
    local plain = Plain(fullName)
    if byName[plain] then return byName[plain] end
    if #plain >= NAME_MIN then
        local best
        for i = 1, #names do
            local name = names[i]
            if sub(plain, 1, #name) == name and (not best or #name > #best) then best = name end
        end
        if best then return byName[best] end
        local only, count = nil, 0
        for i = 1, #names do
            if sub(names[i], 1, #plain) == plain then only, count = names[i], count + 1 end
        end
        if count == 1 then return byName[only] end
    end
    return mapID and byMap[mapID] or false
end

function Listings.DungeonOf(activityID)
    local key = activityKey[activityID]
    if key ~= nil then return key or nil end
    Index()
    local info = C_LFGList.GetActivityInfoTable(activityID)
    local name = info and info.fullName
    if type(name) ~= "string" or Secret(name) or Secret(info.mapID) then return nil end
    key = Match(name, info.mapID)
    activityKey[activityID] = key
    return key or nil
end

function Listings.Activity(activityID)
    local activity = activityInfo[activityID]
    if activity then return activity end
    local info = C_LFGList.GetActivityInfoTable(activityID)
    if not info or Secret(info.fullName) or Secret(info.shortName) then return nil end
    activity = {
        name = info.fullName,
        short = (info.shortName and info.shortName ~= "") and info.shortName or info.fullName,
        min = info.minLevelSuggestion or 0,
        max = info.maxLevelSuggestion or 0,
        size = info.maxNumPlayers or 5,
    }
    activityInfo[activityID] = activity
    return activity
end

local function Counts(entry, id)
    local counts = C_LFGList.GetSearchResultMemberCounts and C_LFGList.GetSearchResultMemberCounts(id)
    local tanks, healers, damage = counts and counts.TANK, counts and counts.HEALER, counts and counts.DAMAGER
    if Secret(tanks) or Secret(healers) or Secret(damage) then tanks, healers, damage = nil, nil, nil end
    entry.tanks, entry.healers, entry.damage = tanks or 0, healers or 0, damage or 0
end

local function Fill(entry, id)
    local info = C_LFGList.GetSearchResultInfo(id)
    if not info then return false end
    local leader, count, age, delisted, activities = info.leaderName, info.numMembers, info.age, info.isDelisted, info.activityIDs
    if Secret(leader) or Secret(count) or Secret(age) or Secret(delisted) or Secret(activities) then return false end
    if type(count) ~= "number" or type(activities) ~= "table" then return false end
    local activity = activities[1]
    if Secret(activity) then return false end
    entry.id, entry.leader, entry.numMembers = id, type(leader) == "string" and leader or nil, count
    entry.age, entry.delisted = type(age) == "number" and age or 0, delisted == true
    entry.mine = not Secret(info.hasSelf) and info.hasSelf == true
    entry.activity = activity
    entry.dungeon = activity and Listings.DungeonOf(activity) or nil
    Counts(entry, id)
    local members, n = entry.members, 0
    for m = 1, math.min(count, MEMBERS_READ) do
        local player = C_LFGList.GetSearchResultPlayerInfo(id, m)
        local roles = player and player.lfgRoles
        if roles and not (Secret(player.name) or Secret(player.level) or Secret(player.classFilename) or Secret(player.isLeader)
            or Secret(roles.tank) or Secret(roles.healer) or Secret(roles.dps)) then
            n = n + 1
            local member = members[n] or {}
            members[n] = member
            member.name, member.level, member.class = player.name, player.level, player.classFilename
            member.roles, member.leader = Card.Roles(roles.tank, roles.healer, roles.dps), player.isLeader == true
            local zone = player.areaName
            member.zone = not Secret(zone) and zone ~= "" and zone or nil
        end
    end
    entry.nMembers = n
    return true
end

function Listings.Read(force)
    if Locked() then
        Listings.state, Listings.n, stale = "locked", 0, true
        return 0
    end
    if not (stale or force) then return Listings.n end
    local getter = C_LFGList.GetFilteredSearchResults or C_LFGList.GetSearchResults
    local _, results = getter()
    results = results or {}
    local n = 0
    for i = 1, math.min(#results, MAX_ENTRIES) do
        local entry = entries[n + 1]
        if not entry then
            entry = { members = {} }
            entries[n + 1] = entry
        end
        if Fill(entry, results[i]) then n = n + 1 end
    end
    Listings.n, Listings.state, stale = n, "ready", false
    return n
end

-------------------------------------------------------------------------------
--  Search: the activities for your level, all of them, or one
-------------------------------------------------------------------------------
local SEARCH_WAIT = 15
local LEVEL, ALL = "level", "all"
local Search = { state = "idle", pick = LEVEL, LEVEL = LEVEL, ALL = ALL }
GF.Search = Search
local wanted = {}
local generation = 0

local function Listed(entry, id)
    for _, listed in ipairs(entry and entry.activityIDs or {}) do
        if listed == id then return true end
    end
    return false
end

local function Suits(activity, level)
    return not ((activity.min > 0 and activity.min > level) or (activity.max > 0 and activity.max < level))
end

local function FillWanted(categoryID, level, entry)
    wipe(wanted)
    local suited, pick = false, Search.pick
    for _, id in ipairs(C_LFGList.GetAvailableActivities(categoryID) or {}) do
        local activity = Listings.Activity(id)
        local suits = activity ~= nil and Suits(activity, level)
        suited = suited or suits
        if pick == ALL or pick == id or (pick == LEVEL and (suits or Listed(entry, id))) then wanted[#wanted + 1] = id end
    end
    return suited
end

local function Category()
    local level, entry = UnitLevel("player"), C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
    local categories = C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableCategories() or {}
    for i = 1, #categories do
        if FillWanted(categories[i], level, entry) then return categories[i] end
    end
end

function Search.Suits(activityID)
    local activity = Listings.Activity(activityID)
    return activity ~= nil and Suits(activity, UnitLevel("player"))
end

function Search.Activities(list)
    wipe(list)
    local category = Category()
    if not category then return 0 end
    for _, id in ipairs(C_LFGList.GetAvailableActivities(category) or {}) do
        if Listings.Activity(id) then list[#list + 1] = id end
    end
    table.sort(list, function(a, b)
        local x, y = Listings.Activity(a), Listings.Activity(b)
        if x.min ~= y.min then return x.min < y.min end
        return x.name < y.name
    end)
    return #list
end

local function Settle(state)
    generation = generation + 1
    Search.state = state
    GF.Fire("search", state)
end

function Search.Run(pick)
    if not GF.On() or Search.state == "searching" then return false end
    Search.pick = pick or Search.pick
    local category = Category()
    if not category then
        Settle("unavailable")
        return false
    end
    C_LFGList.Search(category, 0, 0, nil, false, nil, wanted)
    Settle("searching")
    local gen = generation
    C_Timer.After(SEARCH_WAIT, function()
        if gen == generation then Settle("failed") end
    end)
    return true
end

-------------------------------------------------------------------------------
--  Browse: each listed leader asked once for their card; filter and sorts
-------------------------------------------------------------------------------
local ASK_AGAIN, KNOWN_MAX = 300, 200
local Browse = {}
GF.Browse = Browse
local asked, without, nAsked = {}, {}, 0

function Browse.Ask()
    local now = GetTime()
    for i = 1, Listings.n do
        local entry = entries[i]
        local leader = entry.leader
        if leader and not entry.delisted and not Comms.IsMe(leader) and not Comms.CardOf(leader) then
            local key = Key(leader)
            local at = asked[key]
            if not at or now - at > ASK_AGAIN then
                if not Comms.Ping(leader, entry.dungeon) then return end
                without[key] = nil
                if not asked[key] then
                    if nAsked >= KNOWN_MAX then
                        wipe(asked)
                        wipe(without)
                        nAsked = 0
                    end
                    nAsked = nAsked + 1
                end
                asked[key] = now
            end
        end
    end
end

function Browse.Apply(leader, dungeonKey)
    local id = Comms.Apply(leader, dungeonKey, SavedRoles(), "")
    GF.Fire("applied")
    return id
end

-- The leader's card, and whether one is still awaited.
function Browse.CardOf(leader)
    local card = Comms.CardOf(leader)
    if card then return card, false end
    local key = Key(leader)
    return nil, asked[key] ~= nil and not without[key]
end

local function Has(text, needle) return text ~= nil and find(lower(text), needle, 1, true) ~= nil end
function Browse.Matches(entry, needle)
    if needle == "" then return true end
    local activity = entry.activity and Listings.Activity(entry.activity)
    local card = entry.leader and Comms.CardOf(entry.leader)
    local group = card and card.group
    return Has(activity and activity.name, needle) or Has(activity and activity.short, needle) or Has(entry.leader, needle)
        or Has(group and group.note, needle)
end

local SORTS = {
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
function Browse.Sort(order, how)
    for i = 1, #order do
        local entry = order[i]
        local card = entry.leader and Comms.CardOf(entry.leader)
        local activity = entry.activity and Listings.Activity(entry.activity)
        entry.leaderScore = card and card.score or -1
        entry.minLevel = activity and activity.min or math.huge
    end
    table.sort(order, SORTS[how] or SORTS.newest)
end

local function NoCard(ping)
    local key = Key(ping.name)
    if asked[key] then without[key] = true end
end
GF.Listen("noreply", NoCard)
GF.Listen("offline", NoCard)

-------------------------------------------------------------------------------
--  Events and on/off
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a, b, c, d)
    if event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = a, b, c, d
        if Secret(prefix) or prefix ~= PREFIX then return end
        if Secret(text) or Secret(channel) or Secret(sender) then return end
        if channel ~= WHISPER or type(text) ~= "string" or type(sender) ~= "string" or sender == "" then return end
        OnMessage(text, sender)
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        stale, Listings.searched = true, true
        Settle("done")
        GF.Fire("listings", false)
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        Listings.n, Listings.state, Listings.searched, stale = 0, "failed", true, false
        Settle("failed")
        GF.Fire("listings", true)
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        if stale or Secret(a) then return end
        for i = 1, Listings.n do
            local entry = entries[i]
            if entry.id == a then
                if Locked() or not Fill(entry, a) then stale = true end
                GF.Fire("listing", entry)
                return
            end
        end
    else -- LFG_LIST_ACTIVE_ENTRY_UPDATE, GROUP_ROSTER_UPDATE, PARTY_LEADER_CHANGED
        if not Group.Listed() then Group.ours, Group.listedAt = false, nil end
        GF.Fire("group")
    end
end)

local EVENTS = {
    "CHAT_MSG_ADDON", "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_FAILED", "LFG_LIST_SEARCH_RESULT_UPDATED",
    "LFG_LIST_ACTIVE_ENTRY_UPDATE", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED",
}

local function Apply()
    local want = Enabled() and C_LFGList ~= nil
    if want == commsOn then return end
    commsOn = want
    if want then
        if not prefixed then
            prefixed = true
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        ownKey = Key(GetUnitName("player", true) or UnitName("player") or "?")
        for _, event in ipairs(EVENTS) do
            events:RegisterEvent(event)
        end
        if AddFilter then AddFilter("CHAT_MSG_SYSTEM", NotFoundFilter) end
    else
        events:UnregisterAllEvents()
        if RemoveFilter then RemoveFilter("CHAT_MSG_SYSTEM", NotFoundFilter) end
        ResetComms()
        Listings.n, Listings.state, Listings.searched, stale = 0, "none", false, true
        generation = generation + 1
        Search.state, Search.pick = "idle", LEVEL
        Group.ours, Group.listedAt = false, nil
        wipe(asked)
        wipe(without)
        nAsked = 0
    end
    GF.Fire("enabled", want)
end
GF.Apply = Apply

CUI._LFG = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    GF = GF,
}

F.Start(Apply)
