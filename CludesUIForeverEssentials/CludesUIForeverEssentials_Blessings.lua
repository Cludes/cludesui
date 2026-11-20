if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Blessings.lua  (WoW Forever only)
--  Blessings, for paladins: the Blessing Bar (your aura, Righteous Fury, your
--  seal, an Auto Buff button and a button per class in the group). Left-click
--  a class to bless the next member of it who needs it, missing first, then
--  running out, skipping anyone dead or out of range; in combat each click
--  steps through the queue. Right-click a class to choose its blessing, list
--  its players (bless one, or give one their own blessing) or open the
--  assignments. A red number counts who is missing it, the minutes show the
--  shortest one left.
--  Plans are shared with the group's other paladins over addon messages, in
--  the format Naowh Forever uses, and PallyPower users' plans are read too.
--  /cbless opens the assignments: every paladin's blessing per class and
--  aura, Auto-Assign, a saved preset and a report to chat. Key bindings:
--  Next Blessing and Next Greater Blessing (CludesUI in Key Bindings).
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("blessings", {
    enabled = false,
    size = 30,
    spacing = 6,
    groupGap = 6,
    timerSize = 12,
    labels = true,
    timers = true,
    showAura = true,
    showFury = false,
    showSeal = false,
    showAuto = false,
    autoGreater = false,
    showClasses = true,
    playerList = true,
    tooltips = true,
    smart = false,
    respect = false,
    wait = false,
    tank = "none",
    assist = "none",
    inParty = true,
    solo = true,
    bench = false,
    perRow = 9,
    vertical = false,
    border = "black",
}, { point = "BOTTOM", relPoint = "BOTTOM", x = -150, y = 230 })
local Get = F.Get

_G.BINDING_HEADER_CUI_BLESSINGS = "CludesUI Blessings"
_G["BINDING_NAME_CLICK CludesUIBlessNext:LeftButton"] = "Next Blessing"
_G["BINDING_NAME_CLICK CludesUIBlessNextGreater:LeftButton"] = "Next Greater Blessing"

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local VALID_CLASS = {}
for _, class in ipairs(CLASSES) do
    VALID_CLASS[class] = true
end
local AURA_COLUMN = "AURA"
local NOBODY = "-"
local QUESTION = 134400

local B = { others = {} }
local others = B.others

local function Secret(val)
    return issecretvalue and issecretvalue(val)
end
local function IsPaladin()
    return select(2, UnitClass("player")) == "PALADIN"
end
local function MyName()
    return (UnitFullName("player"))
end
local function ClassName(class)
    return LOCALIZED_CLASS_NAMES_MALE[class] or class
end
local function On()
    return F.Enabled()
end
local function Print(message)
    CludesUI.Print("|cff4cc9f0Blessings:|r " .. message)
end
-- Shared between the sections below (each keeps its own helpers in a do block).
local HiddenAuras, Remembered, ForgetIfDead, CastSent, NoteCast, CastDone, ForgetCasts
local OnPallyPower, PP_PREFIX, asked
local K, keyAuto

-------------------------------------------------------------------------------
--  Spells
-------------------------------------------------------------------------------
local BLESSINGS = {
    {
        key = "might",
        code = "m",
        ranks = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 },
        greater = { 25782, 25916 },
    },
    {
        key = "wisdom",
        code = "w",
        ranks = { 19742, 19850, 19852, 19853, 19854, 25290 },
        greater = { 25894, 25918 },
    },
    { key = "kings", code = "k", ranks = { 20217 }, greater = { 25898 } },
}
local AURAS = {
    { key = "devotion", code = "D", ranks = { 465, 10290, 643, 10291, 1032, 10292, 10293 } },
    { key = "retribution", code = "R", ranks = { 7294, 10298, 10299, 10300, 10301 } },
    { key = "concentration", code = "C", ranks = { 19746 } },
    { key = "shadow", code = "S", ranks = { 19876, 19895, 19896 } },
    { key = "frost", code = "F", ranks = { 19888, 19897, 19898 } },
    { key = "fire", code = "I", ranks = { 19891, 19899, 19900 } },
    { key = "sanctity", code = "T", ranks = { 20218 } },
}
local FURY = { key = "fury", ranks = { 25780 } }
local SEALS = {
    { key = "sealRighteousness", ranks = { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 } },
    { key = "sealCommand", ranks = { 20375, 20915, 20918, 20919, 20920 } },
    { key = "sealFury", ranks = { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 } },
    { key = "sealCrusader", ranks = { 21082, 20162, 20305, 20306, 20307, 20308 } },
    { key = "sealJustice", ranks = { 20164 } },
    { key = "sealLight", ranks = { 20165, 20347, 20348, 20349 } },
    { key = "sealWisdom", ranks = { 20166, 20356, 20357 } },
}
local SYMBOL_OF_KINGS = 21177
local FREE_FLAG = "X"

local BY_KEY, BY_CODE, FAMILY, IDS, GREATER = {}, {}, {}, {}, {}
local function Index(record, untracked)
    BY_KEY[record.key] = record
    if record.code then
        BY_CODE[record.code] = record
    end
    IDS[record.key] = {}
    for _, ident in ipairs(record.ranks) do
        if not untracked then
            FAMILY[ident] = record.key
        end
        IDS[record.key][ident] = true
    end
    for _, ident in ipairs(record.greater or {}) do
        FAMILY[ident] = record.key
        IDS[record.key][ident] = true
        GREATER[ident] = true
    end
end
for _, record in ipairs(BLESSINGS) do
    record.blessing = true
    Index(record)
end
for _, record in ipairs(AURAS) do
    Index(record)
end
for _, record in ipairs(SEALS) do
    Index(record, true)
end
Index(FURY)

local function HighestKnown(ids)
    for index = #(ids or {}), 1, -1 do
        if C_SpellBook.IsSpellKnown(ids[index]) then
            return ids[index]
        end
    end
end
local function Learned(record)
    return HighestKnown(record.ranks) or (record.greater and HighestKnown(record.greater))
end
local function SpellName(key)
    local record = BY_KEY[key]
    return record and C_Spell.GetSpellName(record.ranks[1]) or key
end
local function SpellIcon(key)
    local record = BY_KEY[key]
    return record and C_Spell.GetSpellTexture(record.ranks[1]) or QUESTION
end

-------------------------------------------------------------------------------
--  Your plan, kept per character
-------------------------------------------------------------------------------
local function Store()
    local conf = F.Cfg()
    conf.chars = conf.chars or {}
    local key = UnitName("player") .. "-" .. GetRealmName()
    local storage = conf.chars[key]
    if not (storage and storage.classes) then
        storage = { classes = {}, players = {} }
        conf.chars[key] = storage
    end
    return storage
end

local Readable, Roster, Visible, InGroup, CanAssign, Assigned, Allowed, SenderIsUnit
do
    -------------------------------------------------------------------------------
    --  Group
    -------------------------------------------------------------------------------
    local NAME_SLOTS = 4
    function Readable(val)
        return not Secret(val) and val ~= nil and val ~= ""
    end

    local function HeaderNames(member, realm, firstNames, raid)
        local seen, result = {}, {}
        local function Add(name)
            if Readable(name) and not seen[name] then
                seen[name] = true
                result[#result + 1] = name
            end
        end
        for _, name in ipairs(member.candidates) do
            if firstNames[name] == 1 then
                Add(name)
            end
        end
        if not member.who:find("-", 1, true) then
            Add(member.who .. "-" .. realm)
        end
        local seenBy
        if raid then
            seenBy = member.rosterName
        elseif Readable(member.short) then
            seenBy = Readable(member.server) and member.short .. "-" .. member.server or member.short
        end
        return table.concat(result, ","), Readable(seenBy) and seen[seenBy] == true
    end

    function Roster()
        local units = { "player" }
        local raid = IsInRaid()
        if raid then
            units = {}
            for index = 1, GetNumGroupMembers() do
                units[#units + 1] = "raid" .. index
            end
        else
            for index = 1, GetNumSubgroupMembers() do
                units[#units + 1] = "party" .. index
            end
        end
        local realm = GetNormalizedRealmName()
        local entries, firstNames = {}, {}
        for index, unitToken in ipairs(units) do
            local name, unitRealm = UnitFullName(unitToken)
            local _, class = UnitClass(unitToken)
            local unitGuid = UnitGUID(unitToken)
            if
                name
                and not (Secret(name) or Secret(unitRealm) or Secret(class) or Secret(unitGuid))
                and class
            then
                local who = name
                if unitRealm and unitRealm ~= "" and unitRealm ~= realm then
                    who = name .. "-" .. unitRealm
                end
                local short, server = UnitName(unitToken)
                local member = {
                    unit = unitToken,
                    guid = unitGuid,
                    class = class,
                    who = who,
                    short = short,
                    server = server,
                    rosterName = raid and (GetRaidRosterInfo(index)) or nil,
                }
                local subgroup = raid and select(3, GetRaidRosterInfo(index))
                member.subgroup = not Secret(subgroup) and subgroup or nil
                local nameList = { who, short, member.rosterName }
                if Readable(short) and Readable(server) then
                    nameList[4] = short .. "-" .. server
                end
                member.candidates = {}
                local counted = {}
                for k = 1, NAME_SLOTS do
                    local num = nameList[k]
                    if Readable(num) and not counted[num] then
                        counted[num] = true
                        firstNames[num] = (firstNames[num] or 0) + 1
                        member.candidates[#member.candidates + 1] = num
                    end
                end
                entries[#entries + 1] = member
            end
        end
        for _, member in ipairs(entries) do
            member.names, member.targetable = HeaderNames(member, realm, firstNames, raid)
        end
        return entries
    end

    -- In a raid dungeon with Hide the Bench on, the groups past its usual size are left out.
    function Visible(roster)
        if not (Get("bench") and IsInRaid()) then
            return roster
        end
        local _, kind, _, _, maxPlayers = GetInstanceInfo()
        if kind ~= "raid" or not maxPlayers or maxPlayers <= 0 then
            return roster
        end
        local last = math.ceil(maxPlayers / 5)
        local isShown = {}
        for _, member in ipairs(roster) do
            if not member.subgroup or member.subgroup <= last then
                isShown[#isShown + 1] = member
            end
        end
        return isShown
    end

    function InGroup(who)
        for _, member in ipairs(Roster()) do
            if member.who == who then
                return member
            end
        end
    end

    function CanAssign(unitToken)
        local lead, assist = UnitIsGroupLeader(unitToken), UnitIsGroupAssistant(unitToken)
        return not (Secret(lead) or Secret(assist)) and (lead or assist)
    end

    local TANKING = { WARRIOR = true, DRUID = true, PALADIN = true }
    local UNSUITED = {
        WARRIOR = { wisdom = true },
        ROGUE = { wisdom = true },
        MAGE = { might = true },
        WARLOCK = { might = true },
        PRIEST = { might = true },
    }
    local NO_BLESSING = "none"

    local function IsTank(unitToken)
        local role = UnitGroupRolesAssigned(unitToken)
        if not Secret(role) and role == "TANK" then
            return true
        end
        return GetPartyAssignment("MAINTANK", unitToken) and true or false
    end

    local function IsAssist(unitToken)
        return GetPartyAssignment("MAINASSIST", unitToken) and true or false
    end

    local function RoleBlessing(member)
        local tank, assist = Get("tank"), Get("assist")
        if not TANKING[member.class] or (tank == NO_BLESSING and assist == NO_BLESSING) then
            return
        end
        local key = tank ~= NO_BLESSING and IsTank(member.unit) and tank
            or assist ~= NO_BLESSING and IsAssist(member.unit) and assist
        return key and BY_KEY[key] and Learned(BY_KEY[key]) and key or nil
    end

    function Assigned(member)
        local storage = Store()
        return storage.players[member.guid] or RoleBlessing(member) or storage.classes[member.class]
    end

    function Allowed(class, key)
        local no = Get("smart") and UNSUITED[class]
        return not (no and no[key])
    end

    -- Whether an addon message's sender is this unit.
    function SenderIsUnit(sender, unitToken, unitGuid)
        if not (Readable(sender) and Readable(unitToken) and Readable(unitGuid)) then
            return false
        end
        local g = UnitGUID(unitToken)
        if not Readable(g) or g ~= unitGuid then
            return false
        end
        local first, second = UnitFullName(unitToken)
        if not first or Secret(first) or Secret(second) then
            return false
        end
        local own = GetNormalizedRealmName()
        local name, realm = strsplit("-", sender, 2)
        return name == first and (realm or own) == ((second and second ~= "") and second or own)
    end

    do
    end

    -------------------------------------------------------------------------------
    --  Battlegrounds and arenas hide other players' auras: the blessings you cast
    --  there are remembered for an hour (until the player dies).
    -------------------------------------------------------------------------------
    local BLESSING_TIME, CAST_WINDOW = 3600, 5
    local HIDING = { pvp = true, arena = true }
    local seen, casts, sent = {}, {}, nil

    function HiddenAuras()
        local _, kind = IsInInstance()
        return HIDING[kind] == true
    end

    function Remembered(unitToken, key)
        local unitGuid = UnitGUID(unitToken)
        local mine = unitGuid and not Secret(unitGuid) and seen[unitGuid]
        local ends = mine and mine[key]
        if not ends then
            return false
        end
        local dead = UnitIsDeadOrGhost(unitToken)
        if not Secret(dead) and dead then
            seen[unitGuid] = nil
            return false
        end
        local leftX = ends - GetTime()
        if leftX <= 0 then
            mine[key] = nil
            return false
        end
        return true, leftX ~= math.huge and leftX or nil
    end

    function ForgetIfDead(unitToken)
        if not next(seen) then
            return
        end
        local unitGuid = UnitGUID(unitToken)
        if not unitGuid or Secret(unitGuid) or not seen[unitGuid] then
            return
        end
        local dead = UnitIsDeadOrGhost(unitToken)
        if not Secret(dead) and dead then
            seen[unitGuid] = nil
        end
    end

    function CastSent(castGUID, spell)
        sent = { guid = castGUID, spell = spell, at = GetTime() }
    end

    function NoteCast(unitToken, spell)
        local cast = sent
        sent = nil
        if
            not (
                unitToken
                and spell
                and cast
                and cast.spell == spell
                and cast.at == GetTime()
                and HiddenAuras()
            )
        then
            return
        end
        local key = FAMILY[spell]
        if not key then
            return
        end
        local roster = Roster()
        local target
        for _, member in ipairs(roster) do
            local same = UnitIsUnit(unitToken, member.unit)
            if not Secret(same) and same then
                target = member
                break
            end
        end
        if not target then
            return
        end
        local guids = {}
        for _, member in ipairs(roster) do
            if member.guid == target.guid or (GREATER[spell] and member.class == target.class) then
                guids[#guids + 1] = member.guid
            end
        end
        for ident, old in pairs(casts) do
            if GetTime() - old.at >= CAST_WINDOW then
                casts[ident] = nil
            end
        end
        casts[cast.guid] = { key = key, guids = guids, at = GetTime() }
    end

    function CastDone(castGUID)
        local cast = casts[castGUID]
        if not cast then
            return
        end
        casts[castGUID] = nil
        if GetTime() - cast.at >= CAST_WINDOW then
            return
        end
        local ends = GetTime() + (BY_KEY[cast.key].blessing and BLESSING_TIME or math.huge)
        for _, unitGuid in ipairs(cast.guids) do
            seen[unitGuid] = seen[unitGuid] or {}
            seen[unitGuid][cast.key] = ends
        end
    end

    function ForgetCasts()
        sent = nil
        wipe(casts)
        wipe(seen)
    end
end

local CastSpell, BeginAuraMemo, EndAuraMemo, BuffState, WaitedFor, ByUrgency, Survey, Due
do
    -------------------------------------------------------------------------------
    --  Who has which blessing, and who a class button blesses next
    -------------------------------------------------------------------------------
    local EXPIRING, MAX_AURAS = 300, 40

    function CastSpell(key, members)
        local record = BY_KEY[key]
        local greater = C_Item.GetItemCount(SYMBOL_OF_KINGS) > 0 and HighestKnown(record.greater)
        if greater then
            for _, member in ipairs(members) do
                if Assigned(member) ~= key then
                    greater = nil
                    break
                end
            end
        end
        return greater or HighestKnown(record.ranks)
    end

    local memoAt
    local memo, scratch = {}, {}
    function BeginAuraMemo()
        memoAt = GetTime()
        for _, s in pairs(memo) do
            s.stale = true
        end
    end
    function EndAuraMemo()
        memoAt = nil
    end

    local function Found(val)
        if val == true then
            return true
        end
        return true, val - GetTime()
    end

    function BuffState(unitToken, key)
        if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
            if HiddenAuras() then
                return Remembered(unitToken, key)
            end
            return nil
        end
        local s
        if memoAt and memoAt == GetTime() then
            s = memo[unitToken]
            if not s then
                s = {}
                memo[unitToken] = s
            end
            if s.stale then
                wipe(s)
            end
        else
            wipe(scratch)
            s = scratch
        end
        local val = s[key]
        if val then
            return Found(val)
        end
        if s.ended == "none" then
            return false
        end
        if s.ended then
            return nil
        end
        for index = s.next or 1, MAX_AURAS do
            local aura = C_UnitAuras.GetAuraDataByIndex(unitToken, index, "HELPFUL")
            if not aura then
                s.ended = "none"
                return false
            end
            local ident = aura.spellId
            if Secret(ident) then
                s.ended = "secret"
                return nil
            end
            local family = FAMILY[ident]
            if family and s[family] == nil then
                local expires = aura.expirationTime
                s[family] = (Secret(expires) or not expires or expires == 0) and true or expires
            end
            if family and family == key then
                s.next = index + 1
                return Found(s[family])
            end
        end
        s.ended = "none"
        return false
    end

    local function InRange(member, spell)
        if member.guid == UnitGUID("player") then
            return true
        end
        local inRange = C_Spell.IsSpellInRange(spell, member.unit)
        if Secret(inRange) then
            return nil
        end
        return inRange
    end

    function WaitedFor(members, spell)
        if not Get("wait") then
            return true
        end
        for _, member in ipairs(members) do
            if
                UnitIsConnected(member.unit)
                and not UnitIsDeadOrGhost(member.unit)
                and InRange(member, spell) == false
            then
                return false
            end
        end
        return true
    end

    function ByUrgency(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.left < b.left
    end

    function Survey(members)
        local s = {
            missing = 0,
            reachable = false,
            missingNear = 0,
            expiringNear = 0,
            classDue = 0,
            classMissing = 0,
            queue = {},
        }
        local rank, leftX
        local queue = s.queue
        local players = Store().players
        local spells = {}
        for _, member in ipairs(members) do
            local key = Assigned(member)
            if key and spells[key] == nil then
                local cast = CastSpell(key, members)
                if cast and GREATER[cast] and not WaitedFor(members, cast) then
                    cast = HighestKnown(BY_KEY[key].ranks)
                end
                spells[key] = cast or false
            end
            local spell = key and spells[key]
            if spell and UnitIsConnected(member.unit) and not UnitIsDeadOrGhost(member.unit) then
                local has, remaining = BuffState(member.unit, key)
                if has == false then
                    s.missing = s.missing + 1
                    s.shortest = 0
                elseif remaining and (not s.shortest or remaining < s.shortest) then
                    s.shortest = remaining
                end
                local range = UnitIsVisible(member.unit) and InRange(member, spell)
                if has ~= nil and range ~= false then
                    s.reachable = true
                    local region = not has and 0 or (remaining and remaining < EXPIRING and 1 or 2)
                    if range == true and region < 2 and member.targetable then
                        if region == 0 then
                            s.missingNear = s.missingNear + 1
                        else
                            s.expiringNear = s.expiringNear + 1
                        end
                        if not players[member.guid] then
                            s.classDue = s.classDue + 1
                            if region == 0 then
                                s.classMissing = s.classMissing + 1
                            end
                        end
                    end
                    local l = remaining or math.huge
                    if member.targetable then
                        queue[#queue + 1] = { names = member.names, spell = spell, rank = region, left = l }
                        if not s.target or region < rank or (region == rank and l < leftX) then
                            s.target, s.spell, rank, leftX = member, spell, region, l
                        end
                    end
                end
            end
        end
        table.sort(queue, ByUrgency)
        local due = 0
        for _, record in ipairs(queue) do
            if record.rank < 2 then
                due = due + 1
            end
        end
        if GREATER[queue[1] and queue[1].spell] then
            due = math.min(due, 1)
        end
        local keep = Get("respect") and 0 or 1
        for index = #queue, math.max(due, keep) + 1, -1 do
            queue[index] = nil
        end
        if due == 0 and keep == 0 then
            s.target = nil
        end
        s.rank, s.left = rank, leftX
        return s
    end

    function Due(member, key, spell)
        if
            not (
                spell
                and UnitIsConnected(member.unit)
                and not UnitIsDeadOrGhost(member.unit)
                and UnitIsVisible(member.unit)
                and InRange(member, spell) ~= false
            )
        then
            return
        end
        local has, remaining = BuffState(member.unit, key)
        if has == false then
            return 0, 0
        end
        if has and remaining and remaining < EXPIRING then
            return 1, remaining
        end
    end
end

local STATUS_SPELL, OwnStatus
do
    -------------------------------------------------------------------------------
    --  Symbols of Kings, Lay on Hands and Divine Intervention, shared with the
    --  group's paladins
    -------------------------------------------------------------------------------
    local LAY_ON_HANDS, DIVINE_INTERVENTION = { 633, 2800, 10310 }, { 19752 }
    STATUS_SPELL = {}
    for _, ranks in ipairs({ LAY_ON_HANDS, DIVINE_INTERVENTION }) do
        for _, ident in ipairs(ranks) do
            STATUS_SPELL[ident] = true
        end
    end

    local function CooldownLeft(ranks)
        local spell = HighestKnown(ranks)
        if not spell then
            return -1
        end
        local details = C_Spell.GetSpellCooldown(spell)
        local start, duration = details and details.startTime, details and details.duration
        if not start or Secret(start) or Secret(duration) or duration <= 1.5 then
            return 0
        end
        return math.max(0, math.floor(start + duration - GetTime()))
    end

    function OwnStatus()
        return C_Item.GetItemCount(SYMBOL_OF_KINGS),
            CooldownLeft(LAY_ON_HANDS),
            CooldownLeft(DIVINE_INTERVENTION)
    end
end

local RefreshPage, AskPallyPower, Changed
local PREFIX, Send, Channel, BroadcastSoon, Sender, OnMessage, SendPlan, SyncSoon, AfterCombat
do
    -------------------------------------------------------------------------------
    --  Plans shared with the group's paladins (Naowh Forever's format)
    -------------------------------------------------------------------------------
    PREFIX = "NaowhBless"
    local NONE_CODE = "-"
    local PLAYER_BATCH, MAX_PLAYER_CHOICES, MAX_SYMBOLS, BATCH_DELAY = 200, 40, 9999, 1
    local pending = {}
    local sentPlayers, broadcastAfterCombat, broadcastQueued, syncQueued

    local function EncodePlan(classes, aura)
        local result = {}
        for index, class in ipairs(CLASSES) do
            result[index] = classes[class] and BY_KEY[classes[class]].code or NONE_CODE
        end
        result[#result + 1] = aura and BY_KEY[aura].code or NONE_CODE
        return table.concat(result)
    end

    local function DecodePlan(textValue)
        if #textValue ~= #CLASSES + 1 then
            return
        end
        local classes = {}
        for index, class in ipairs(CLASSES) do
            local c = textValue:sub(index, index)
            if c ~= NONE_CODE then
                local record = BY_CODE[c]
                if not (record and record.blessing) then
                    return
                end
                classes[class] = record.key
            end
        end
        local c = textValue:sub(-1)
        if c == NONE_CODE then
            return classes, nil
        end
        local record = BY_CODE[c]
        if record and not record.blessing then
            return classes, record.key
        end
    end

    local function KnownCodes()
        local codes = {}
        for _, record in ipairs(BLESSINGS) do
            if Learned(record) then
                codes[#codes + 1] = record.code
            end
        end
        for _, record in ipairs(AURAS) do
            if Learned(record) then
                codes[#codes + 1] = record.code
            end
        end
        if Store().free then
            codes[#codes + 1] = FREE_FLAG
        end
        return table.concat(codes)
    end

    function Channel()
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            return "INSTANCE_CHAT"
        end
        if IsInRaid() then
            return "RAID"
        end
        if IsInGroup() then
            return "PARTY"
        end
    end

    function Send(message, key)
        if InCombatLockdown() then
            pending[key or message] = message
            return
        end
        local channel = Channel()
        if channel then
            C_ChatInfo.SendAddonMessage(PREFIX, message, channel)
        end
    end

    local function SendPlayers()
        local players = Store().players
        local parts, num, chunk = {}, 1, ""
        for _, member in ipairs(Roster()) do
            local key = players[member.guid]
            if key then
                local part = member.guid .. "=" .. BY_KEY[key].code
                if #chunk + #part > PLAYER_BATCH then
                    parts[#parts + 1] = chunk
                    chunk = ""
                end
                chunk = chunk == "" and part or chunk .. "," .. part
            end
        end
        parts[#parts + 1] = chunk
        if chunk == "" and #parts == 1 and not sentPlayers then
            return
        end
        sentPlayers = chunk ~= "" or #parts > 1
        for _, body in ipairs(parts) do
            Send("P|" .. num .. "|" .. body, "P|" .. num)
            num = num + 1
        end
    end

    local function StatusMessage()
        local symbols, loh, di = OwnStatus()
        return ("I|%d|%d|%d"):format(symbols, loh, di)
    end

    local function Broadcast()
        if not IsPaladin() then
            return
        end
        if InCombatLockdown() then
            broadcastAfterCombat = true
            return
        end
        local storage = Store()
        Send("F|" .. EncodePlan(storage.classes, storage.aura) .. "|" .. KnownCodes())
        SendPlayers()
        Send(StatusMessage(), "I")
    end

    function BroadcastSoon()
        if broadcastQueued then
            return
        end
        broadcastQueued = true
        C_Timer.After(BATCH_DELAY, function()
            broadcastQueued = false
            Broadcast()
        end)
    end

    local function MayPlan(from)
        return from and (CanAssign(from.unit) or (Store().free and from.class == "PALADIN"))
    end

    local function OnAssigned(from, name, target, plan)
        local classes, aura = DecodePlan(plan)
        if not (IsPaladin() and classes and MayPlan(from) and target == UnitGUID("player")) then
            return
        end
        local storage = Store()
        storage.classes = {}
        for class, key in pairs(classes) do
            if Learned(BY_KEY[key]) then
                storage.classes[class] = key
            end
        end
        storage.aura = aura and Learned(BY_KEY[aura]) and aura or nil
        Print(name .. " updated your blessings.")
        BroadcastSoon()
        Changed()
    end

    local function OnStatus(who, symbols, loh, di)
        local from = others[who]
        if not from then
            return
        end
        local nowTime = GetTime()
        local function Ends(leftX)
            leftX = tonumber(leftX)
            return leftX >= 0 and nowTime + leftX or nil
        end
        from.status = { symbols = math.min(tonumber(symbols), MAX_SYMBOLS), loh = Ends(loh), di = Ends(di) }
        RefreshPage()
    end

    local function OnPlayers(who, part, entries)
        local from = others[who]
        if not from then
            return
        end
        if part == "1" then
            from.players, from.choices = {}, 0
        end
        for unitGuid, code in entries:gmatch("(Player%-[%w%-]+)=(%a)") do
            local record = BY_CODE[code]
            local choices = from.choices or 0
            if record and record.blessing and (from.players[unitGuid] or choices < MAX_PLAYER_CHOICES) then
                if not from.players[unitGuid] then
                    from.choices = choices + 1
                end
                from.players[unitGuid] = record.key
            end
        end
        RefreshPage()
    end

    local function OnPlan(from, body, known)
        if not (body and from.class == "PALADIN") then
            return
        end
        local classes, aura = DecodePlan(body)
        if not classes then
            return
        end
        local set, free = {}, nil
        for code in known:gmatch(".") do
            if BY_CODE[code] then
                set[BY_CODE[code].key] = true
            end
            if code == FREE_FLAG then
                free = true
            end
        end
        local was = others[from.who]
        others[from.who] = {
            classes = classes,
            aura = aura,
            free = free,
            known = set,
            players = was and was.players or {},
            choices = was and was.choices or 0,
            status = was and was.status,
        }
        RefreshPage()
    end

    function Sender(sender)
        for _, member in ipairs(Roster()) do
            if SenderIsUnit(sender, member.unit, member.guid) then
                return member
            end
        end
    end

    function OnMessage(message, sender)
        if message == "R" then
            if not SenderIsUnit(sender, "player", UnitGUID("player")) then
                BroadcastSoon()
            end
            return
        end
        local from = Sender(sender)
        if not from or from.guid == UnitGUID("player") then
            return
        end
        local who = from.who
        local target, plan = message:match("^S|([^|]+)|(%S+)$")
        if target then
            return OnAssigned(from, Ambiguate(sender, "none"), target, plan)
        end
        local symbols, loh, di = message:match("^I|(%d+)|(%-?%d+)|(%-?%d+)$")
        if symbols then
            return OnStatus(who, symbols, loh, di)
        end
        local part, entries = message:match("^P|(%d+)|(.*)$")
        if part then
            return OnPlayers(who, part, entries)
        end
        local body, known = message:match("^F|(%S+)|(%a*)$")
        OnPlan(from, body, known)
    end

    function SendPlan(who, classes, aura)
        local member = InGroup(who)
        if not member then
            return
        end
        others[who].classes, others[who].aura = classes, aura
        Send("S|" .. member.guid .. "|" .. EncodePlan(classes, aura), "S|" .. member.guid)
    end

    function SyncSoon()
        if syncQueued then
            return
        end
        syncQueued = true
        C_Timer.After(BATCH_DELAY, function()
            syncQueued = false
            for who in pairs(others) do
                if not InGroup(who) then
                    others[who] = nil
                end
            end
            if IsPaladin() or CanAssign("player") then
                Send("R")
                AskPallyPower()
            end
            BroadcastSoon()
            RefreshPage()
        end)
    end

    function AfterCombat()
        if broadcastAfterCombat then
            broadcastAfterCombat = false
            BroadcastSoon()
        end
        for key, message in pairs(pending) do
            pending[key] = nil
            Send(message)
        end
        if IsPaladin() or CanAssign("player") then
            AskPallyPower()
        end
    end

    do
    end

    -------------------------------------------------------------------------------
    --  PallyPower users' plans, read from its addon messages
    -------------------------------------------------------------------------------
    PP_PREFIX = "PLPWR"
    local PP_CHANGES = { ASSIGN = true, PASSIGN = true, MASSIGN = true, AASSIGN = true, CLEAR = true }
    local PP_CLASSES =
        { "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN" }
    local PP_BLESSINGS = { "wisdom", "might", "kings" }
    local PP_AURAS = { "devotion", "retribution", "concentration", "shadow", "frost", "fire", "sanctity" }
    local PP_MAX_COOLDOWN = 7200
    asked = {}

    local function PPPlan(who)
        local plan = others[who]
        if plan then
            return plan.pallyPower and plan or nil
        end
        plan = { classes = {}, known = {}, players = {}, choices = 0, pallyPower = true }
        others[who] = plan
        return plan
    end

    local function PPKnown(plan, keyList, ranks)
        for index, key in ipairs(keyList) do
            local rank = ranks:sub(2 * index - 1, 2 * index - 1)
            plan.known[key] = rank ~= "" and rank ~= "n" or nil
        end
    end

    local function PPPick(plan, keyList, index)
        local key = keyList[tonumber(index)]
        return key and plan.known[key] and key or nil
    end

    local function PPClasses(plan, given)
        plan.classes = {}
        for index, class in ipairs(PP_CLASSES) do
            plan.classes[class] = PPPick(plan, PP_BLESSINGS, given:sub(index, index))
        end
    end

    local function PPEnds(leftX)
        leftX = tonumber(leftX)
        return leftX and leftX >= 0 and leftX <= PP_MAX_COOLDOWN and GetTime() + leftX or nil
    end

    local function PPTarget(name, from)
        local member = Sender(name)
        local plan = member and others[member.who]
        if plan and plan.pallyPower and (member.guid == from.guid or CanAssign(from.unit) or plan.free) then
            return plan
        end
    end

    local function PPChange(message, from)
        if message == "CLEAR" or message == "CLEAR SKIP" then
            local lead = CanAssign(from.unit)
            for _, plan in pairs(others) do
                if plan.pallyPower and (lead or plan.free) then
                    plan.classes = {}
                    if message == "CLEAR" then
                        plan.aura = nil
                    end
                end
            end
            return
        end
        local name, class, index = message:match("^ASSIGN (.+) (%d+) (%d+)$")
        if name then
            local plan, colour = PPTarget(name, from), PP_CLASSES[tonumber(class)]
            if plan and colour then
                plan.classes[colour] = PPPick(plan, PP_BLESSINGS, index)
            end
            return
        end
        local given
        name, given = message:match("^PASSIGN (.+)@([%dn]*)$")
        if name then
            local plan = PPTarget(name, from)
            if plan then
                PPClasses(plan, given)
            end
            return
        end
        name, index = message:match("^MASSIGN (.+) (%d+)$")
        if name then
            local plan = PPTarget(name, from)
            if not plan then
                return
            end
            local key = PPPick(plan, PP_BLESSINGS, index)
            for _, colour in ipairs(PP_CLASSES) do
                plan.classes[colour] = key
            end
            return
        end
        name, index = message:match("^AASSIGN (.+) (%d+)$")
        local plan = name and PPTarget(name, from)
        if plan then
            plan.aura = PPPick(plan, PP_AURAS, index)
        end
    end

    function OnPallyPower(message, sender)
        local ranks, given = message:match("^SELF ([%xn]*)@([%dn]*)$")
        local auraRanks, aura = message:match("^ASELF ([%xn]*)@([%dn]*)$")
        local symbols = message:match("SYMCOUNT (%d+)")
        local change = PP_CHANGES[message:match("^%u+")]
        if not (ranks or auraRanks or symbols or change) then
            return
        end
        local from = Sender(sender)
        if not from or from.guid == UnitGUID("player") then
            return
        end
        if change then
            PPChange(message, from)
            return RefreshPage()
        end
        if from.class ~= "PALADIN" then
            return
        end
        local plan = ranks and PPPlan(from.who) or others[from.who]
        if not (plan and plan.pallyPower) then
            return
        end
        if ranks then
            PPKnown(plan, PP_BLESSINGS, ranks)
            PPClasses(plan, given)
        elseif auraRanks then
            PPKnown(plan, PP_AURAS, auraRanks)
            plan.aura = PPPick(plan, PP_AURAS, aura)
        else
            local loh, di = message:match("COOLDOWNS:[^:]*:([^:]*):[^:]*:([^:]*)$")
            plan.free = message:find("FREEASSIGN YES", 1, true) == 1 or nil
            plan.status =
                { symbols = math.min(tonumber(symbols), MAX_SYMBOLS), loh = PPEnds(loh), di = PPEnds(di) }
        end
        RefreshPage()
    end

    function AskPallyPower()
        local channel = Channel()
        if not channel or InCombatLockdown() then
            return
        end
        local me, ask = UnitGUID("player"), false
        for _, member in ipairs(Roster()) do
            if
                member.class == "PALADIN"
                and member.guid ~= me
                and not others[member.who]
                and not asked[member.guid]
            then
                asked[member.guid] = true
                ask = true
            end
        end
        if ask then
            C_ChatInfo.SendAddonMessage(PP_PREFIX, "REQ", channel)
        end
    end
end

local Report, REPORT_CHANNELS
do
    -------------------------------------------------------------------------------
    --  Report to chat
    -------------------------------------------------------------------------------
    local LINE_MAX = 240
    REPORT_CHANNELS = {
        {
            key = "SELF",
            label = "Yourself",
            can = function()
                return true
            end,
        },
        {
            key = "SAY",
            label = "Say",
            can = function()
                return true
            end,
        },
        {
            key = "PARTY",
            label = "Party",
            can = function()
                return IsInGroup()
            end,
        },
        {
            key = "RAID",
            label = "Raid",
            can = function()
                return IsInRaid()
            end,
        },
        {
            key = "INSTANCE_CHAT",
            label = "Instance",
            can = function()
                return IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
            end,
        },
        {
            key = "GUILD",
            label = "Guild",
            can = function()
                return IsInGuild()
            end,
        },
    }

    local function Given(plan)
        local byBlessing, sequence = {}, {}
        for _, class in ipairs(CLASSES) do
            local key = plan.classes[class]
            if key then
                if not byBlessing[key] then
                    byBlessing[key] = {}
                    sequence[#sequence + 1] = key
                end
                table.insert(byBlessing[key], ClassName(class))
            end
        end
        local parts = {}
        for _, key in ipairs(sequence) do
            parts[#parts + 1] = SpellName(key) .. " (" .. table.concat(byBlessing[key], ", ") .. ")"
        end
        if plan.aura then
            parts[#parts + 1] = SpellName(plan.aura)
        end
        return #parts > 0 and table.concat(parts, ", ") or "Nothing"
    end

    local function Split(textValue, result)
        while #textValue > LINE_MAX do
            local comma = textValue:sub(1, LINE_MAX):match("^.*(), ")
            result[#result + 1] = textValue:sub(1, comma and comma - 1 or LINE_MAX)
            textValue = "  " .. textValue:sub(comma and comma + 2 or LINE_MAX + 1)
        end
        result[#result + 1] = textValue
    end

    local function ReportLines()
        local plans = {}
        if IsPaladin() then
            plans[1] = { who = MyName(), plan = Store() }
        end
        local nameList = {}
        for who in pairs(others) do
            nameList[#nameList + 1] = who
        end
        table.sort(nameList)
        for _, who in ipairs(nameList) do
            plans[#plans + 1] = { who = who, plan = others[who] }
        end
        if #plans == 0 then
            return
        end
        local lines = { "--- Paladin blessings ---" }
        for _, record in ipairs(plans) do
            Split(Ambiguate(record.who, "short") .. ": " .. Given(record.plan), lines)
        end
        lines[#lines + 1] = "--- End of blessings ---"
        return lines
    end

    function Report(channel)
        if InCombatLockdown() then
            return Print("Reports are sent outside combat.")
        end
        local lines = ReportLines()
        if not lines then
            return Print("There are no paladins to report.")
        end
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        for _, line in ipairs(lines) do
            if channel == "SELF" then
                Print(line)
            else
                send(line, channel)
            end
        end
    end
end

local Paladins, AutoPlans, ApplyPlans, Presets, CanPlanAll, SavePreset, LoadPreset, ClearAll, SetFor
do
    -------------------------------------------------------------------------------
    --  Auto-Assign and the saved preset
    -------------------------------------------------------------------------------
    local WANTED = {
        WARRIOR = { "might", "kings" },
        ROGUE = { "might", "kings" },
        HUNTER = { "might", "kings", "wisdom" },
        PALADIN = { "wisdom", "kings", "might" },
        PRIEST = { "wisdom", "kings" },
        MAGE = { "wisdom", "kings" },
        WARLOCK = { "wisdom", "kings" },
        SHAMAN = { "wisdom", "kings", "might" },
        DRUID = { "wisdom", "kings", "might" },
    }
    local AURA_ORDER = { "devotion", "retribution", "concentration", "fire", "frost", "shadow", "sanctity" }

    function Paladins()
        local entries = {}
        if IsPaladin() then
            local known = {}
            for _, record in ipairs(BLESSINGS) do
                if Learned(record) then
                    known[record.key] = true
                end
            end
            for _, record in ipairs(AURAS) do
                if Learned(record) then
                    known[record.key] = true
                end
            end
            entries[1] = { who = MyName(), known = known, you = true }
        end
        for who, plan in pairs(others) do
            entries[#entries + 1] = { who = who, known = plan.known, fixed = plan.pallyPower and plan or nil }
        end
        for _, p in ipairs(entries) do
            p.count = 0
            for _ in pairs(p.known) do
                p.count = p.count + 1
            end
        end
        table.sort(entries, function(lhs, rhs)
            if lhs.count ~= rhs.count then
                return lhs.count < rhs.count
            end
            return lhs.who < rhs.who
        end)
        return entries
    end

    local function Pick(paladins, wanted, give)
        local free = {}
        for _, p in ipairs(paladins) do
            free[#free + 1] = p
        end
        for _, key in ipairs(wanted) do
            for index, p in ipairs(free) do
                if p.known[key] then
                    give(p, key)
                    table.remove(free, index)
                    break
                end
            end
        end
    end

    local function Untaken(wanted, fixed, given)
        local result = {}
        for _, key in ipairs(wanted) do
            local taken = false
            for _, plan in ipairs(fixed) do
                if given(plan) == key then
                    taken = true
                end
            end
            if not taken then
                result[#result + 1] = key
            end
        end
        return result
    end

    function AutoPlans()
        local paladins, fixed = {}, {}
        for _, p in ipairs(Paladins()) do
            if p.fixed then
                fixed[#fixed + 1] = p.fixed
            else
                paladins[#paladins + 1] = p
            end
        end
        local plans = {}
        for _, p in ipairs(paladins) do
            plans[p.who] = { classes = {} }
        end
        for _, class in ipairs(CLASSES) do
            local wanted = Untaken(WANTED[class], fixed, function(plan)
                return plan.classes[class]
            end)
            Pick(paladins, wanted, function(p, key)
                plans[p.who].classes[class] = key
            end)
        end
        local auras = Untaken(AURA_ORDER, fixed, function(plan)
            return plan.aura
        end)
        Pick(paladins, auras, function(p, key)
            plans[p.who].aura = key
        end)
        return plans
    end

    function ApplyPlans(plans)
        local storage = Store()
        for who, plan in pairs(plans) do
            if who == MyName() then
                storage.classes = {}
                for class, key in pairs(plan.classes) do
                    storage.classes[class] = key
                end
                storage.aura = plan.aura
                BroadcastSoon()
            elseif others[who] and not others[who].pallyPower then
                SendPlan(who, plan.classes, plan.aura)
            end
        end
        Changed()
    end

    function Presets()
        local conf = F.Cfg()
        conf.preset = conf.preset or {}
        return conf.preset
    end

    function CanPlanAll()
        for _, plan in pairs(others) do
            if not plan.pallyPower then
                return CanAssign("player")
            end
        end
        return true
    end

    function SavePreset()
        local paladins = Paladins()
        if #paladins == 0 then
            return false
        end
        local preset = {}
        for _, p in ipairs(paladins) do
            local plan = p.you and Store() or others[p.who]
            local classes = {}
            for class, key in pairs(plan.classes) do
                classes[class] = key
            end
            preset[p.who] = { classes = classes, aura = plan.aura }
        end
        F.Cfg().preset = preset
        return true
    end

    function LoadPreset()
        local plans = {}
        for _, p in ipairs(Paladins()) do
            local saved = Presets()[p.who]
            if saved and not p.fixed then
                local plan = { classes = {} }
                for class, key in pairs(saved.classes or {}) do
                    if p.known[key] then
                        plan.classes[class] = key
                    end
                end
                plan.aura = saved.aura and p.known[saved.aura] and saved.aura or nil
                plans[p.who] = plan
            end
        end
        ApplyPlans(plans)
        return next(plans) ~= nil
    end

    function ClearAll()
        local plans = {}
        for _, p in ipairs(Paladins()) do
            plans[p.who] = { classes = {} }
        end
        if IsPaladin() then
            Store().players = {}
        end
        ApplyPlans(plans)
    end

    function SetFor(who, colour, key)
        local plan = others[who]
        if not plan then
            return
        end
        if colour == AURA_COLUMN then
            plan.aura = key
        else
            plan.classes[colour] = key
        end
        SendPlan(who, plan.classes, plan.aura)
    end
end

-------------------------------------------------------------------------------
--  Look
-------------------------------------------------------------------------------
local RED = { r = 0.97, g = 0.27, b = 0.27 }
local YELLOW = { r = 1, g = 0.85, b = 0.3 }
local BLUE = { r = 0.35, g = 0.6, b = 1 }
local ICON_CROP = 0.08
local LABEL_SIZE, LABEL_DROP, LABEL_SIDE, LABEL_COLUMN = 10, 2, 3, 46
local function Font()
    return CludesUI.GetFontPath("essentials")
end

local Look = { rows = 1 }

local function LookIcon(widget)
    widget.edge = widget:CreateTexture(nil, "BACKGROUND")
    widget.edge:SetAllPoints()
    widget.edge:SetColorTexture(0, 0, 0, 1)
    widget.icon = widget:CreateTexture(nil, "ARTWORK")
    widget.icon:SetPoint("TOPLEFT", 1, -1)
    widget.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    widget.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    widget.mark = widget:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(widget.mark, 14, "essentials")
    widget.mark:SetPoint("CENTER")
    widget.mark:SetTextColor(RED.r, RED.g, RED.b)
    widget.timer = widget:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(widget.timer, 10, "essentials")
    widget.timer:SetPoint("BOTTOM", 0, 1)
end

local function LookRead()
    Look.size, Look.gap, Look.groupGap = Get("size"), Get("spacing"), Get("groupGap")
    Look.timerSize, Look.labels, Look.vertical = Get("timerSize"), Get("labels"), Get("vertical")
    Look.perRow, Look.rows = math.max(1, Get("perRow")), 1
    Look.border = Get("border")
end

local function LabelRoom()
    if not Look.labels then
        return 0
    end
    if Look.vertical then
        return LABEL_SIDE + LABEL_COLUMN
    end
    return LABEL_DROP + LABEL_SIZE
end

local function RowStep()
    return Look.size + Look.gap + LabelRoom()
end

local function LookPin(widget, barFrame, posX, posY)
    widget:ClearAllPoints()
    if Look.vertical then
        widget:SetPoint("TOPLEFT", barFrame, "TOPLEFT", posY or 0, -posX)
    else
        widget:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", posX, posY or 0)
    end
end

local function LookPlace(widget, barFrame, posX, posY)
    local size = Look.size
    widget:SetSize(size, size)
    CludesUI.Kit.Font(widget.timer, Look.timerSize, "essentials")
    if widget.watchText then
        CludesUI.Kit.Font(widget.watchText, Look.timerSize, "essentials")
    end
    widget.edge:SetShown(Look.border ~= "none")
    if widget.label then
        widget.label:SetShown(Look.labels)
        widget.label:ClearAllPoints()
        if Look.vertical then
            widget.label:SetPoint("LEFT", widget, "RIGHT", LABEL_SIDE, 0)
            widget.label:SetWidth(Look.rows > 1 and LABEL_COLUMN or 0)
        else
            widget.label:SetPoint("TOP", widget, "BOTTOM", 0, -LABEL_DROP)
            widget.label:SetWidth(size + Look.gap)
        end
    end
    LookPin(widget, barFrame, posX, posY)
    widget:Show()
    return posX + size + Look.gap
end

local function Minutes(seconds)
    if not (seconds and seconds > 0 and Get("timers")) then
        return ""
    end
    return math.ceil(seconds / 60) .. "m"
end

local function LookClass(cell, colour, reachable, missing, shortest)
    local status = Look.border == "status"
    local tint = not status and colour
    cell.icon:SetDesaturated(not reachable)
    cell.icon:SetVertexColor(tint and tint.r or 1, tint and tint.g or 1, tint and tint.b or 1)
    if status then
        local edge = colour or { r = 0, g = 0, b = 0 }
        cell.edge:SetColorTexture(edge.r, edge.g, edge.b, 1)
    else
        cell.edge:SetColorTexture(0, 0, 0, 1)
    end
    cell.mark:SetText(missing > 0 and missing or "")
    cell.timer:SetText(Minutes(shortest))
end

local function LookSelf(widget, missing, remaining)
    widget.icon:SetVertexColor(missing and RED.r or 1, missing and RED.g or 1, missing and RED.b or 1)
    widget.mark:SetText(missing and "!" or "")
    widget.timer:SetText(Minutes(remaining))
end

local function LookState(widget, key, has, remaining)
    local missing = key ~= nil and (widget.watch ~= nil or has == false)
    LookSelf(widget, missing, not widget.watch and remaining)
end

local function LookFit(widget, posX)
    local across = Look.size + (Look.rows - 1) * RowStep()
    local along = math.max(posX - Look.gap, Look.size)
    if Look.vertical then
        widget:SetSize(across, along)
    else
        widget:SetSize(along, across)
    end
end

-------------------------------------------------------------------------------
--  The game's own aura display over a button: shows a buff and its time,
--  in combat too.
-------------------------------------------------------------------------------
local watchUnavailable

local function Watch(widget)
    if watchUnavailable then
        return
    end
    local success, boxHolder = pcall(function()
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
        local c = CreateFrame("AuraContainer", nil, widget, "CustomAuraContainerTemplate")
        c:SetAllPoints(widget)
        c:SetFrameLevel(widget:GetFrameLevel() + 2)
        c:EnableMouse(false)
        c:AddAuraSlot("buff", "HELPFUL", {
            candidateFilters = { includeSpellIDs = {} },
            initializeFrame = function(btnFrame)
                btnFrame:SetAllPoints(widget.icon)
                btnFrame:EnableMouse(false)
                local iconTex = btnFrame:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
                iconTex:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
                btnFrame:SetIcon(iconTex)
                local textValue = btnFrame:CreateFontString(nil, "OVERLAY")
                CludesUI.Kit.Font(textValue, Get("timerSize"), "essentials")
                widget.watchText = textValue
                textValue:SetPoint("BOTTOM", 0, 1)
                btnFrame:SetDurationText(textValue, {})
            end,
        })
        c:SetEnabled(false)
        return c
    end)
    if not success then
        watchUnavailable = true
        return
    end
    widget.watch = boxHolder
end

local function SetWatch(widget, unitToken, key)
    local c = widget.watch
    if not c or (widget.watchUnit == unitToken and widget.watchKey == key) then
        return
    end
    widget.watchUnit, widget.watchKey = unitToken, key
    c:SetUnit(unitToken or "none")
    c:SetAuraSlotCandidateFilters("buff", { includeSpellIDs = key and IDS[key] or {} })
    c:SetEnabled(unitToken ~= nil and key ~= nil)
end

-------------------------------------------------------------------------------
--  A secure button that follows one named player through raid reordering,
--  even in combat
-------------------------------------------------------------------------------
local function Recipient(hostFrame, name)
    local header = CreateFrame("Frame", name, hostFrame, "SecureGroupHeaderTemplate")
    header:SetAttribute("template", "CludesUIBlessButtonTemplate")
    header:SetAttribute("showPlayer", true)
    header:SetAttribute("showParty", true)
    header:SetAttribute("showRaid", true)
    header:SetAttribute("showSolo", true)
    header:SetAttribute("nameList", NOBODY)
    header:SetAttribute("sortMethod", "NAMELIST")
    header:SetAttribute("point", "TOPLEFT")
    header:SetAttribute("unitsPerColumn", 1)
    header:SetAttribute("maxColumns", 1)
    header:SetPoint("TOPLEFT", hostFrame, "TOPLEFT")
    header:Show()
    local btnFrame = header:GetAttribute("child1")
    btnFrame:RegisterForClicks("AnyUp", "AnyDown")
    btnFrame:SetAttribute("type1", "spell")
    return header, btnFrame
end

local function SetNames(header, nameList)
    if header:GetAttribute("nameList") ~= nameList then
        header:SetAttribute("nameList", nameList)
    end
end

local function SizeRecipient(header, btnFrame, size)
    header:SetAttribute("minWidth", size)
    header:SetAttribute("minHeight", size)
    btnFrame:SetSize(size, size)
end

-------------------------------------------------------------------------------
--  Menus
-------------------------------------------------------------------------------
local OpenWindow, PlayerList

local function SetOwn(colour, key)
    local storage = Store()
    if colour == AURA_COLUMN then
        storage.aura = key
    else
        storage.classes[colour] = key
    end
    BroadcastSoon()
    Changed()
end

local function OpenMenu(ownerFrame, title, entries, current, choose, noneText, can)
    can = can or Learned
    CludesUI.Kit.ContextMenu(ownerFrame, function(_, root)
        root:CreateTitle(title)
        for _, record in ipairs(entries) do
            if can(record) then
                root:CreateRadio(SpellName(record.key), function()
                    return current() == record.key
                end, function()
                    choose(record.key)
                end)
            end
        end
        root:CreateRadio(noneText, function()
            return current() == nil
        end, function()
            choose(nil)
        end)
    end)
end

local function SetSeal(key)
    Store().seal = key
    Changed()
end

local function SealMenu(ownerFrame)
    OpenMenu(ownerFrame, "Seal", SEALS, function()
        return Store().seal
    end, SetSeal, "Default")
end

local function AuraMenu(ownerFrame)
    OpenMenu(ownerFrame, "Aura", AURAS, function()
        return Store().aura
    end, function(key)
        SetOwn(AURA_COLUMN, key)
    end, "Default")
end

local function OwnBlessings(class)
    local players, guids = Store().players, {}
    for _, member in ipairs(Roster()) do
        if member.class == class and players[member.guid] then
            guids[#guids + 1] = member.guid
        end
    end
    return guids
end

local function ClassMenu(ownerFrame, class)
    CludesUI.Kit.ContextMenu(ownerFrame, function(_, root)
        root:CreateTitle(ClassName(class))
        for _, record in ipairs(BLESSINGS) do
            if Learned(record) and (Store().classes[class] == record.key or Allowed(class, record.key)) then
                root:CreateRadio(SpellName(record.key), function()
                    return Store().classes[class] == record.key
                end, function()
                    SetOwn(class, record.key)
                end)
            end
        end
        root:CreateRadio("None", function()
            return Store().classes[class] == nil
        end, function()
            SetOwn(class, nil)
        end)
        local own = OwnBlessings(class)
        if #own > 0 then
            root:CreateDivider()
            root:CreateTitle(
                #own == 1 and "1 player has their own blessing"
                    or ("%d players have their own blessing"):format(#own)
            )
            root:CreateButton("Give them the class blessing", function()
                local players = Store().players
                for _, unitGuid in ipairs(own) do
                    players[unitGuid] = nil
                end
                BroadcastSoon()
                Changed()
            end)
        end
        root:CreateDivider()
        if Get("playerList") then
            root:CreateCheckbox("Players", function()
                return PlayerList.Showing() == class
            end, function()
                PlayerList.Toggle(class)
            end)
        end
        root:CreateButton("Assignments", function()
            OpenWindow()
        end)
    end)
end

local function Tip(widget, title, body)
    widget:HookScript("OnEnter", function(self)
        if not Get("tooltips") then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        local textValue = type(body) == "function" and body() or body
        local ar, ag, ab = CludesUI.Kit.Accent()
        if textValue and textValue ~= "" then
            GameTooltip:AddLine(textValue, ar, ag, ab, true)
        end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local Refresh
do
    -------------------------------------------------------------------------------
    --  Player list: a class's players above the bar, to bless one person or give
    --  them their own blessing
    -------------------------------------------------------------------------------
    local flyout, rowList, flyoutClass
    local listMembers = {}
    PlayerList = {}

    local function PlayerMenu(ownerFrame, member)
        local storage = Store()
        local function Can(record)
            return Learned(record)
                and (storage.players[member.guid] == record.key or Allowed(member.class, record.key))
        end
        OpenMenu(ownerFrame, Ambiguate(member.who, "short"), BLESSINGS, function()
            return storage.players[member.guid]
        end, function(key)
            storage.players[member.guid] = key
            BroadcastSoon()
            Changed()
        end, "Class default", Can)
    end

    local function NewRow(index)
        local row = CreateFrame("Frame", nil, flyout)
        row:SetSize(230, 30)
        row.name = row:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(row.name, 12, "essentials")
        row.name:SetPoint("TOPLEFT", 4, -2)
        row.note = row:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(row.note, 10, "essentials")
        row.note:SetTextColor(0.6, 0.65, 0.7)
        row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
        row.slot = CreateFrame("Frame", nil, row)
        row.slot:SetSize(26, 26)
        row.slot:SetPoint("RIGHT", -2, 0)
        LookIcon(row.slot)
        row.header, row.cast = Recipient(row.slot, "CludesUIBlessRow" .. index)
        SizeRecipient(row.header, row.cast, 26)
        row.cast:SetAttribute("ctrl-type1", "maintank")
        row.cast:SetAttribute("ctrl-action1", "toggle")
        row.cast:SetScript("PostClick", function(self, btnFrame, down)
            if btnFrame == "RightButton" and not down and row.member then
                PlayerMenu(self, row.member)
            end
            if btnFrame == "LeftButton" then
                NoteCast(self:GetAttribute("unit"), self:GetAttribute("spell1"))
            end
        end)
        Tip(
            row.cast,
            "Bless",
            "Left-click: cast this player's blessing.\nRight-click: give them their own blessing, or back to the class default.\nCtrl-click: toggle Main Tank in a raid."
        )
        Watch(row.slot)
        row.cast:HookScript("OnAttributeChanged", function(_, name, value)
            if name == "unit" then
                SetWatch(row.slot, value, row.slot.watchKey)
            end
        end)
        return row
    end

    local function PaintRow(row, member, storage)
        row.member = member
        local color = RAID_CLASS_COLORS[member.class]
        row.name:SetText(Ambiguate(member.who, "short"))
        row.name:SetTextColor(color.r, color.g, color.b)
        local own = storage.players[member.guid]
        local key = Assigned(member)
        row.note:SetText(own and SpellName(own) or "Class default")
        row.slot.icon:SetTexture(key and SpellIcon(key) or QUESTION)
        SetNames(row.header, member.names)
        row.cast:SetAttribute("spell1", key and HighestKnown(BY_KEY[key].ranks))
        SetWatch(row.slot, member.unit, key)
        local has, remaining
        if key then
            has, remaining = BuffState(member.unit, key)
        end
        LookState(row.slot, key, has, remaining)
    end

    function PlayerList.Showing()
        return flyoutClass
    end

    function PlayerList.Build(barFrame)
        flyout = CreateFrame("Frame", nil, barFrame)
        flyout:SetPoint("BOTTOMLEFT", barFrame, "TOPLEFT", 0, 18)
        CludesUI.Kit.Panel(flyout, 0.9)
        flyout.title = flyout:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(flyout.title, 12, "essentials")
        CludesUI.Kit.AccentText(flyout.title)
        flyout.title:SetPoint("TOPLEFT", 8, -6)
        local close = CludesUI.Kit.Glyph(flyout, "x", function()
            flyout:Hide()
        end, nil, "essentials")
        close:SetSize(22, 22)
        close:SetPoint("TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function()
            PlayerList.Toggle(flyoutClass)
        end)
        rowList = {}
        flyout:Hide()
    end

    function PlayerList.Arrange(roster)
        wipe(listMembers)
        for _, member in ipairs(roster) do
            if member.class == flyoutClass then
                listMembers[#listMembers + 1] = member
            end
        end
        if #listMembers == 0 or not Get("playerList") then
            flyoutClass = nil
        end
        if not flyoutClass then
            flyout:Hide()
            return
        end
        local storage = Store()
        flyout:Show()
        for index, member in ipairs(listMembers) do
            local row = rowList[index] or NewRow(index)
            rowList[index] = row
            PaintRow(row, member, storage)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 6, -26 - (index - 1) * 32)
            row:Show()
        end
        for index = #listMembers + 1, #rowList do
            SetNames(rowList[index].header, NOBODY)
            SetWatch(rowList[index].slot, nil, nil)
            rowList[index]:Hide()
        end
        flyout.title:SetText(ClassName(flyoutClass))
        flyout:SetSize(242, 30 + #listMembers * 32)
    end

    function PlayerList.Toggle(class)
        if InCombatLockdown() then
            Print("The player list opens after combat.")
            return
        end
        flyoutClass = flyoutClass ~= class and class or nil
        Refresh()
    end

    do
    end

    -------------------------------------------------------------------------------
    --  Key bindings: Next Blessing and Next Greater Blessing step through who
    --  needs one, most urgent first
    -------------------------------------------------------------------------------
    local KEY_STEP = [[
    local i, n = self:GetAttribute("step") or 1, self:GetAttribute("count") or 0
    if i > n then return false end
    self:SetAttribute("unit", self:GetAttribute("unit" .. i))
    self:SetAttribute("spell", self:GetAttribute("spell" .. i))
    self:SetAttribute("step", i + 1)
]]

    local keyNext, keyGreater
    K = {}

    local function NewKeyButton(name, handler)
        local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyDown")
        button:SetAttribute("useOnKeyDown", true)
        button:SetAttribute("type", "spell")
        button:SetAttribute("count", 0)
        SecureHandlerWrapScript(button, "OnClick", handler, KEY_STEP)
        button:SetScript("PostClick", function(self)
            NoteCast(self:GetAttribute("unit"), self:GetAttribute("spell"))
        end)
        return button
    end

    local function SetQueue(button, entries, kind)
        kind = kind or ""
        table.sort(entries, ByUrgency)
        for index, record in ipairs(entries) do
            button:SetAttribute("unit" .. kind .. index, record.unit)
            button:SetAttribute("spell" .. kind .. index, record.spell)
        end
        button:SetAttribute("count" .. kind, #entries)
        button:SetAttribute("step" .. kind, 1)
    end

    local function Singles(members, single, shared)
        for _, member in ipairs(members) do
            local key = Assigned(member)
            if key ~= shared then
                shared = nil
            end
            local spell = key and HighestKnown(BY_KEY[key].ranks)
            local rank, leftX = Due(member, key, spell)
            if rank then
                single[#single + 1] = { unit = member.unit, spell = spell, rank = rank, left = leftX }
            end
        end
        return shared
    end

    local function GreaterNext(members, shared, symbols)
        local spell = shared and symbols and HighestKnown(BY_KEY[shared].greater)
        if spell and not WaitedFor(members, spell) then
            spell = nil
        end
        local best
        for _, member in ipairs(spell and members or {}) do
            local rank, leftX = Due(member, shared, spell)
            if rank and (not best or ByUrgency({ rank = rank, left = leftX }, best)) then
                best = { unit = member.unit, spell = spell, rank = rank, left = leftX }
            end
        end
        return best
    end

    function K.Build(handler)
        keyNext = NewKeyButton("CludesUIBlessNext", handler)
        keyGreater = NewKeyButton("CludesUIBlessNextGreater", handler)
    end

    function K.Peek()
        if not keyNext then
            return
        end
        return keyNext:GetAttribute("spell1") or keyGreater:GetAttribute("spell1"),
            keyNext:GetAttribute("count") or 0
    end

    function K.Clear()
        if keyNext then
            keyNext:SetAttribute("count", 0)
        end
        if keyGreater then
            keyGreater:SetAttribute("count", 0)
        end
        if keyAuto then
            keyAuto:SetAttribute("countN", 0)
            keyAuto:SetAttribute("countG", 0)
        end
    end

    function K.Fill(byClass)
        local single, greater = {}, {}
        local symbols = C_Item.GetItemCount(SYMBOL_OF_KINGS) > 0
        for _, class in ipairs(CLASSES) do
            local members = byClass[class]
            if members then
                local shared = Singles(members, single, Store().classes[class])
                greater[#greater + 1] = GreaterNext(members, shared, symbols)
            end
        end
        SetQueue(keyNext, single)
        SetQueue(keyGreater, greater)
        if keyAuto then
            SetQueue(keyAuto, single, "N")
            SetQueue(keyAuto, greater, "G")
        end
    end
end

-------------------------------------------------------------------------------
--  The Blessing Bar
-------------------------------------------------------------------------------
local CLASS_STEP = [[
    if button ~= "LeftButton" then return end
    local n = self:GetAttribute("count") or 0
    local i = self:GetAttribute("step") or 1
    local header = self:GetParent()
    if not header:IsVisible() then return false end
    for _ = 1, n do
        if i > n then i = 1 end
        header:SetAttribute("nameList", self:GetAttribute("queueNames" .. i))
        if self:GetAttribute("unit") then
            self:SetAttribute("spell1", self:GetAttribute("queueSpell" .. i))
            self:SetAttribute("step", i + 1)
            return
        end
        i = i + 1
    end
    return false
]]

local AUTO_STEP = [[
    local left = self:GetAttribute("leftKind") or "N"
    local kind = button == "RightButton" and (left == "N" and "G" or "N") or left
    local i, n = self:GetAttribute("step" .. kind) or 1, self:GetAttribute("count" .. kind) or 0
    if i > n then return false end
    self:SetAttribute("unit", self:GetAttribute("unit" .. kind .. i))
    self:SetAttribute("spell", self:GetAttribute("spell" .. kind .. i))
    self:SetAttribute("step" .. kind, i + 1)
]]

local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local RESCAN_DELAY, LANDING_WINDOW, TICK = 1, 1, 3
local barFrame, cells, auraButton, furyButton, sealButton, autoButton, secureHandler
local dirty, ticker, buildAfterCombat
local refreshQueued, landing, landingQueued, sentSymbols
local events = CreateFrame("Frame")
local Apply

local function SurveyQueue(cell, queue)
    local parts = {}
    for index, record in ipairs(queue) do
        parts[index] = record.names .. "=" .. record.spell
    end
    local signature = table.concat(parts, ";")
    if signature == cell.signature then
        return
    end
    cell.signature = signature
    for index, record in ipairs(queue) do
        cell.cast:SetAttribute("queueNames" .. index, record.names)
        cell.cast:SetAttribute("queueSpell" .. index, record.spell)
    end
    cell.cast:SetAttribute("count", #queue)
end

local function PaintCell(cell, s, key)
    local queue = s.queue
    local isShown = s.spell or (key and CastSpell(key, cell.members))
    cell.icon:SetTexture(isShown and C_Spell.GetSpellTexture(isShown) or QUESTION)
    SurveyQueue(cell, queue)
    cell.cast:SetAttribute("step", 1)
    SetNames(cell.header, queue[1] and queue[1].names or NOBODY)
    cell.target, cell.queued = s.target, #queue
    local color = s.classMissing > 0 and RED
        or s.classDue > 0 and YELLOW
        or s.missingNear + s.expiringNear > 0 and BLUE
        or nil
    LookClass(cell, color, s.reachable, s.missing, s.shortest)
end

local function PrepareCell(cell)
    PaintCell(cell, Survey(cell.members), Store().classes[cell.class])
end

local function CellTip(cell)
    local target = cell.target and Ambiguate(cell.target.who, "short")
    return (target and ("Left-click: bless %s.\n"):format(target) or "")
        .. ((cell.queued or 0) > 1 and "In combat each click blesses the next who needed it.\n" or "")
        .. "Right-click: choose the blessing, the player list or assignments."
end

local function SecretAuras()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
end

local function NewCell(class)
    local cell = CreateFrame("Frame", nil, barFrame)
    cell.class = class
    LookIcon(cell)
    cell.label = cell:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(cell.label, LABEL_SIZE, "essentials")
    cell.label:SetWordWrap(false)
    cell.label:SetText(ClassName(class))
    local c = RAID_CLASS_COLORS[class]
    if c then
        cell.label:SetTextColor(c.r, c.g, c.b)
    end
    cell.header, cell.cast = Recipient(cell, "CludesUIBless" .. class)
    cell.cast:RegisterForClicks("AnyUp")
    cell.cast:SetAttribute("useOnKeyDown", false)
    cell.cast:SetAttribute("count", 0)
    cell.cast:SetScript("PreClick", function(_, btnFrame)
        if
            btnFrame == "LeftButton"
            and not InCombatLockdown()
            and not (SecretAuras() and not HiddenAuras())
        then
            PrepareCell(cell)
        end
    end)
    SecureHandlerWrapScript(cell.cast, "OnClick", secureHandler, CLASS_STEP)
    cell.cast:SetScript("PostClick", function(self, btnFrame, down)
        if btnFrame == "RightButton" and not down then
            ClassMenu(self, class)
        end
        if btnFrame == "LeftButton" then
            NoteCast(self:GetAttribute("unit"), self:GetAttribute("spell1"))
        end
    end)
    Tip(cell.cast, ClassName(class), function()
        return CellTip(cell)
    end)
    return cell
end

local function CurrentAura()
    local key = Store().aura
    if key and Learned(BY_KEY[key]) then
        return key
    end
    for _, record in ipairs(AURAS) do
        if Learned(record) then
            return record.key
        end
    end
end

local function CurrentSeal()
    local key = Store().seal
    if key and Learned(BY_KEY[key]) then
        return key
    end
    for _, record in ipairs(SEALS) do
        if Learned(record) then
            return record.key
        end
    end
end

local function Cycle(entries, current, choose, delta)
    if InCombatLockdown() then
        return
    end
    local known = {}
    for _, record in ipairs(entries) do
        if Learned(record) then
            known[#known + 1] = record.key
        end
    end
    if #known < 2 then
        return
    end
    local at = 1
    for index, key in ipairs(known) do
        if key == current() then
            at = index
        end
    end
    choose(known[(at - 1 + (delta > 0 and 1 or -1)) % #known + 1])
end

local function NewBarButton(name)
    local button = CreateFrame("Button", name, barFrame, "SecureActionButtonTemplate")
    LookIcon(button)
    return button
end

local function NewSelfButton(name)
    local button = NewBarButton(name)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type1", "spell")
    button:SetAttribute("unit1", "player")
    Watch(button)
    return button
end

local function NewAutoButton(name)
    local button = NewBarButton(name)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type1", "spell")
    button:SetAttribute("type2", "spell")
    button:SetAttribute("countN", 0)
    button:SetAttribute("countG", 0)
    SecureHandlerWrapScript(button, "OnClick", secureHandler, AUTO_STEP)
    button:SetScript("PostClick", function(self)
        NoteCast(self:GetAttribute("unit"), self:GetAttribute("spell"))
    end)
    keyAuto = button
    return button
end

local function PrepareSeal(button, key)
    local ident = BY_KEY[key].ranks[1]
    button:SetAttribute("spell1", C_Spell.GetSpellName(ident))
    button.icon:SetTexture(C_Spell.GetSpellTexture(ident))
    SetWatch(button, "player", key)
    LookSelf(button, false)
end

local function PaintAuto()
    if not autoButton:IsShown() then
        return
    end
    local spell, due = K.Peek()
    autoButton.icon:SetTexture(spell and C_Spell.GetSpellTexture(spell) or QUESTION)
    autoButton.icon:SetDesaturated(due == 0)
    autoButton.mark:SetText(due > 0 and due or "")
end

local function PrepareSelf(button, key)
    local spell = HighestKnown(BY_KEY[key].ranks)
    button:SetAttribute("spell1", spell)
    button.icon:SetTexture(C_Spell.GetSpellTexture(spell))
    SetWatch(button, "player", key)
    LookState(button, key, BuffState("player", key))
end

local function PlaceSelf(posX)
    local aura = Get("showAura") and CurrentAura()
    if aura then
        PrepareSelf(auraButton, aura)
        posX = LookPlace(auraButton, barFrame, posX)
    else
        auraButton:Hide()
    end
    if Get("showFury") and Learned(FURY) then
        PrepareSelf(furyButton, "fury")
        posX = LookPlace(furyButton, barFrame, posX)
    else
        furyButton:Hide()
    end
    local seal = Get("showSeal") and CurrentSeal()
    if seal then
        PrepareSeal(sealButton, seal)
        posX = LookPlace(sealButton, barFrame, posX)
    else
        sealButton:Hide()
    end
    if Get("showAuto") then
        autoButton:SetAttribute("leftKind", Get("autoGreater") and "G" or "N")
        posX = LookPlace(autoButton, barFrame, posX)
    else
        autoButton:Hide()
    end
    if posX > 0 then
        return posX + Look.groupGap
    end
    return posX
end

local function ByClass(roster)
    local byClass = {}
    for _, member in ipairs(roster) do
        byClass[member.class] = byClass[member.class] or {}
        table.insert(byClass[member.class], member)
    end
    return byClass
end

local function HideCell(cell)
    SetNames(cell.header, NOBODY)
    cell:Hide()
end

local function PlaceCells(byClass, posX)
    local total = 0
    for _, class in ipairs(CLASSES) do
        if byClass[class] then
            total = total + 1
        end
    end
    Look.rows = math.max(1, math.ceil(total / Look.perRow))
    local done = posX + math.min(total, Look.perRow) * (Look.size + Look.gap)
    local index = 0
    for _, class in ipairs(CLASSES) do
        local members = byClass[class]
        local cell = cells[class]
        if members then
            cell = cell or NewCell(class)
            cells[class] = cell
            cell.members = members
            SizeRecipient(cell.header, cell.cast, Look.size)
            LookPlace(
                cell,
                barFrame,
                posX + index % Look.perRow * (Look.size + Look.gap),
                math.floor(index / Look.perRow) * RowStep()
            )
            index = index + 1
            PrepareCell(cell)
        elseif cell then
            HideCell(cell)
        end
    end
    return done
end

local function Wanted()
    if IsInRaid() then
        return true
    end
    if IsInGroup() then
        return Get("inParty")
    end
    return Get("solo")
end

function Refresh()
    if not barFrame then
        return
    end
    if InCombatLockdown() or (SecretAuras() and not HiddenAuras()) then
        dirty = true
        return
    end
    dirty = false
    if not (On() and IsPaladin() and (Wanted() or CludesUI._unlockActive)) then
        barFrame:Hide()
        K.Clear()
        return
    end
    barFrame:Show()
    BeginAuraMemo()
    LookRead()
    local posX = PlaceSelf(0)
    local roster = Visible(Roster())
    local byClass = ByClass(roster)
    if Get("showClasses") then
        posX = PlaceCells(byClass, posX)
    else
        for _, cell in pairs(cells) do
            HideCell(cell)
        end
    end
    PlayerList.Arrange(roster)
    K.Fill(byClass)
    PaintAuto()
    EndAuraMemo()
    LookFit(barFrame, posX)
    barFrame:SetShown(posX > 0 or CludesUI._unlockActive)
end

function Changed()
    if Refresh then
        Refresh()
    end
    RefreshPage()
end

local function OnSelfClick(self, btnFrame)
    if btnFrame == "LeftButton" then
        NoteCast(self:GetAttribute("unit1"), self:GetAttribute("spell1"))
    end
end

local function BuildBar()
    barFrame = CreateFrame("Frame", "CludesUIBlessingBar", UIParent)
    barFrame:SetClampedToScreen(true)
    barFrame:SetSize(Get("size"), Get("size"))
    cells = {}
    secureHandler = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    auraButton = NewSelfButton("CludesUIBlessAura")
    auraButton:SetScript("PostClick", function(self, btnFrame, down)
        OnSelfClick(self, btnFrame)
        if btnFrame == "RightButton" and not down then
            AuraMenu(self)
        end
    end)
    Tip(
        auraButton,
        "Aura",
        "Left-click: cast your aura.\nRight-click: choose it. Wheel: cycle through your auras."
    )
    auraButton:EnableMouseWheel(true)
    auraButton:SetScript("OnMouseWheel", function(_, delta)
        Cycle(AURAS, CurrentAura, function(key)
            SetOwn(AURA_COLUMN, key)
        end, delta)
    end)
    furyButton = NewSelfButton("CludesUIBlessFury")
    furyButton:SetScript("PostClick", OnSelfClick)
    Tip(
        furyButton,
        C_Spell.GetSpellName(FURY.ranks[1]) or "Righteous Fury",
        "Left-click: cast it on yourself."
    )
    sealButton = NewSelfButton("CludesUIBlessSeal")
    sealButton:SetScript("PostClick", function(self, btnFrame, down)
        if btnFrame == "RightButton" and not down then
            SealMenu(self)
        end
    end)
    Tip(
        sealButton,
        "Seal",
        "Left-click: cast your seal.\nRight-click: choose it. Wheel: cycle through your seals."
    )
    sealButton:EnableMouseWheel(true)
    sealButton:SetScript("OnMouseWheel", function(_, delta)
        Cycle(SEALS, CurrentSeal, SetSeal, delta)
    end)
    K.Build(secureHandler)
    autoButton = NewAutoButton("CludesUIBlessAuto")
    Tip(
        autoButton,
        "Auto Buff",
        "Left-click: the next blessing. Right-click: the next Greater Blessing. Each goes to whoever needs it most."
    )
    PlayerList.Build(barFrame)
    if not CludesUI._unlockActive then
        F.Place(barFrame)
    end
end

local function RefreshSoon()
    if refreshQueued then
        return
    end
    refreshQueued = true
    C_Timer.After(RESCAN_DELAY, function()
        refreshQueued = false
        Refresh()
    end)
end

local function RefreshLanded()
    if landingQueued then
        return
    end
    landingQueued = true
    C_Timer.After(0, function()
        landingQueued = false
        Refresh()
    end)
end

local function OnUnitAura(unitToken)
    local fresh = landing and GetTime() - landing < LANDING_WINDOW
    if refreshQueued and not fresh then
        return
    end
    if InCombatLockdown() then
        dirty = true
        return
    end
    if
        unitToken == "player"
        or unitToken:find("party", 1, true) == 1
        or unitToken:find("raid", 1, true) == 1
    then
        if fresh then
            RefreshLanded()
        else
            RefreshSoon()
        end
    end
end

events:SetScript("OnEvent", function(_, evt, ...)
    if evt == "CHAT_MSG_ADDON" then
        local prefixText, message, channel, sender = ...
        if Secret(prefixText) or Secret(message) or Secret(channel) or Secret(sender) then
            return
        end
        if prefixText == PREFIX and GROUP_CHANNELS[channel] then
            OnMessage(message, sender)
        elseif prefixText == PP_PREFIX and (GROUP_CHANNELS[channel] or channel == "WHISPER") then
            OnPallyPower(message, sender)
        end
    elseif evt == "GROUP_ROSTER_UPDATE" or evt == "PLAYER_ENTERING_WORLD" then
        if evt == "PLAYER_ENTERING_WORLD" then
            if HiddenAuras() and IsPaladin() then
                events:RegisterEvent("UNIT_HEALTH")
            else
                events:UnregisterEvent("UNIT_HEALTH")
                ForgetCasts()
            end
        end
        SyncSoon()
        RefreshSoon()
    elseif evt == "PARTY_LEADER_CHANGED" then
        RefreshPage()
    elseif evt == "PLAYER_ROLES_ASSIGNED" then
        RefreshSoon()
    elseif evt == "PLAYER_REGEN_ENABLED" then
        if buildAfterCombat then
            buildAfterCombat = false
            Apply()
        elseif dirty then
            Refresh()
        end
        AfterCombat()
    elseif evt == "SPELLS_CHANGED" then
        BroadcastSoon()
        RefreshSoon()
    elseif evt == "UNIT_SPELLCAST_SENT" then
        local _, _, castGUID, spellID = ...
        if Secret(castGUID) or Secret(spellID) or not FAMILY[spellID] then
            return
        end
        CastSent(castGUID, spellID)
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castGUID, spellID = ...
        if Secret(spellID) then
            return
        end
        if STATUS_SPELL[spellID] then
            BroadcastSoon()
        end
        if Secret(castGUID) or not FAMILY[spellID] then
            return
        end
        CastDone(castGUID)
        if not InCombatLockdown() then
            landing = GetTime()
        end
    elseif evt == "UNIT_HEALTH" then
        ForgetIfDead(...)
    elseif evt == "UNIT_AURA" then
        OnUnitAura(...)
    end
end)

local function OnTick()
    if not (barFrame and barFrame:IsShown() and not InCombatLockdown()) then
        return
    end
    local symbols = C_Item.GetItemCount(SYMBOL_OF_KINGS)
    if symbols ~= sentSymbols then
        sentSymbols = symbols
        BroadcastSoon()
    end
    RefreshSoon()
end

function Apply()
    events:UnregisterAllEvents()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if not On() then
        if barFrame and InCombatLockdown() then
            dirty = true
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
        elseif barFrame then
            barFrame:Hide()
            K.Clear()
        end
        return
    end
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(PP_PREFIX)
    for _, event in ipairs({
        "CHAT_MSG_ADDON",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD",
        "PARTY_LEADER_CHANGED",
        "PLAYER_REGEN_ENABLED",
    }) do
        events:RegisterEvent(event)
    end
    if not IsPaladin() then
        return
    end
    for _, event in ipairs({ "UNIT_AURA", "PLAYER_ROLES_ASSIGNED", "SPELLS_CHANGED" }) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    if not barFrame and InCombatLockdown() then
        buildAfterCombat = true
        return
    end
    if not barFrame then
        BuildBar()
    end
    ticker = C_Timer.NewTicker(TICK, OnTick)
    Refresh()
end

do
    -------------------------------------------------------------------------------
    --  The assignments window (/cbless)
    -------------------------------------------------------------------------------
    local WIN_W, WIN_H = 640, 470
    local CELL, GAP, NAME_W = 32, 6, 150
    local window, winContent, winScroll
    local winPool, winUsed = {}, 0
    local redrawQueued

    StaticPopupDialogs.CUI_BLESS_CONFIRM = {
        text = "%s",
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function(_, payload)
            if payload then
                payload()
            end
        end,
    }
    local function Confirm(textValue, func)
        local dialog = StaticPopup_Show("CUI_BLESS_CONFIRM", textValue)
        if dialog then
            dialog.data = func
        end
    end

    local function Allowed2()
        if CanPlanAll() then
            return true
        end
        Print("Only the group leader or an assistant can plan every paladin's blessings.")
    end

    local function WinItem(kind)
        winUsed = winUsed + 1
        local entry = winPool[winUsed]
        if entry and entry.kind ~= kind then
            entry:Hide()
            entry = nil
        end
        if not entry then
            if kind == "cell" then
                entry = CreateFrame("Button", nil, winContent)
                entry:SetSize(CELL, CELL)
                LookIcon(entry)
                entry:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.title or "", 1, 1, 1)
                    local ar, ag, ab = CludesUI.Kit.Accent()
                    if self.body then
                        GameTooltip:AddLine(self.body, ar, ag, ab, true)
                    end
                    GameTooltip:Show()
                end)
                entry:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            else
                entry = CreateFrame("Frame", nil, winContent)
                entry:SetSize(1, 1)
                entry.text = entry:CreateFontString(nil, "OVERLAY")
                entry.text:SetPoint("TOPLEFT")
                entry.text:SetJustifyH("LEFT")
            end
            entry.kind = kind
            local old = winPool[winUsed]
            if old then
                old:Hide()
            end
            winPool[winUsed] = entry
        end
        entry:ClearAllPoints()
        entry:Show()
        return entry
    end

    local function WinText(posX, posY, textValue, size, colour, width)
        local entry = WinItem("text")
        entry:SetPoint("TOPLEFT", winContent, "TOPLEFT", posX, posY)
        CludesUI.Kit.Font(entry.text, size or 12, "essentials")
        entry.text:SetTextColor(unpack(colour or { 1, 1, 1 }))
        entry.text:SetWidth(width or 0)
        entry.text:SetWordWrap(width ~= nil)
        entry.text:SetText(textValue)
        return entry.text:GetStringHeight()
    end

    local function WinCell(posX, posY, iconTex, lit, title, body, onClick)
        local button = WinItem("cell")
        button:SetPoint("TOPLEFT", winContent, "TOPLEFT", posX, posY)
        button.icon:SetTexture(iconTex)
        button.icon:SetDesaturated(not lit)
        button.icon:SetAlpha(lit and 1 or 0.35)
        button.icon:SetVertexColor(1, 1, 1)
        button.mark:SetText("")
        button.timer:SetText("")
        button.title, button.body = title, body
        button:SetScript("OnClick", onClick)
    end

    local function Remaining(leftX)
        if not leftX then
            return
        end
        return leftX > 0 and (math.ceil(leftX / 60) .. "m") or "ready"
    end

    local function StatusText(row)
        local symbols, loh, di
        if row.you then
            symbols, loh, di = OwnStatus()
            if loh < 0 then
                loh = nil
            end
            if di < 0 then
                di = nil
            end
        elseif row.plan.status then
            local status, nowTime = row.plan.status, GetTime()
            symbols = status.symbols
            loh = status.loh and status.loh - nowTime
            di = status.di and status.di - nowTime
        else
            return ""
        end
        local parts = { ("%d Symbols"):format(symbols) }
        if loh then
            parts[#parts + 1] = "LoH " .. Remaining(loh)
        end
        if di then
            parts[#parts + 1] = "DI " .. Remaining(di)
        end
        return table.concat(parts, "  ")
    end

    local function Rows(roster)
        local lead = CanAssign("player")
        local entries = {}
        if IsPaladin() then
            local storage = Store()
            entries[1] = {
                who = MyName(),
                you = true,
                plan = storage,
                players = storage.players,
                can = Learned,
                set = SetOwn,
            }
        end
        local mayFree = IsPaladin()
        local nameList = {}
        for who in pairs(others) do
            nameList[#nameList + 1] = who
        end
        table.sort(nameList)
        for _, who in ipairs(nameList) do
            local plan = others[who]
            entries[#entries + 1] = {
                who = who,
                plan = plan,
                players = plan.players,
                can = function(record)
                    return plan.known[record.key]
                end,
                set = not plan.pallyPower and (lead or (mayFree and plan.free)) and function(colour, key)
                    SetFor(who, colour, key)
                    RefreshPage()
                end,
            }
        end
        for _, member in ipairs(roster) do
            if member.class == "PALADIN" and member.guid ~= UnitGUID("player") and not others[member.who] then
                entries[#entries + 1] = { who = member.who }
            end
        end
        return entries
    end

    local function OwnList(roster, players, class)
        local result = {}
        for _, member in ipairs(roster) do
            local key = member.class == class and players and players[member.guid]
            if key then
                result[#result + 1] = Ambiguate(member.who, "short") .. ": " .. SpellName(key)
            end
        end
        return #result > 0 and ("\n" .. table.concat(result, "\n")) or ""
    end

    local function Redraw()
        redrawQueued = false
        if not (window and window:IsShown()) then
            return
        end
        for index = 1, winUsed do
            winPool[index]:Hide()
        end
        winUsed = 0
        local posY = -4
        local roster = Roster()
        local columns = {}
        for _, class in ipairs(CLASSES) do
            columns[#columns + 1] = class
        end
        columns[#columns + 1] = AURA_COLUMN
        for index, colour in ipairs(columns) do
            local aura = colour == AURA_COLUMN
            WinCell(
                NAME_W + (index - 1) * (CELL + GAP),
                posY,
                aura and SpellIcon("devotion")
                    or ("Interface\\Icons\\ClassIcon_" .. colour:lower():gsub("^%l", string.upper)),
                true,
                aura and "Aura" or ClassName(colour)
            )
        end
        posY = posY - CELL - 10
        local entries = Rows(roster)
        if #entries == 0 then
            WinText(0, posY, "No paladins in your group.", 12, { 0.6, 0.65, 0.7 })
            posY = posY - 20
        end
        for _, row in ipairs(entries) do
            WinText(
                0,
                posY - 4,
                Ambiguate(row.who, "short") .. (row.you and "  (you)" or ""),
                13,
                { 0.96, 0.55, 0.73 },
                NAME_W - 10
            )
            if row.plan then
                WinText(0, posY - 20, StatusText(row), 10, { 0.6, 0.65, 0.7 }, NAME_W - 10)
                for index, colour in ipairs(columns) do
                    local aura = colour == AURA_COLUMN
                    local key = aura and row.plan.aura or row.plan.classes[colour]
                    local title = aura and "Aura" or ClassName(colour)
                    local onClick = row.set
                        and function(button)
                            local function Can(record)
                                return row.can(record)
                                    and (aura or key == record.key or Allowed(colour, record.key))
                            end
                            OpenMenu(button, title, aura and AURAS or BLESSINGS, function()
                                return aura and row.plan.aura or row.plan.classes[colour]
                            end, function(choice)
                                row.set(colour, choice)
                            end, "None", Can)
                        end
                    WinCell(
                        NAME_W + (index - 1) * (CELL + GAP),
                        posY,
                        key and SpellIcon(key) or QUESTION,
                        key ~= nil,
                        title,
                        (key and SpellName(key) or "Nothing assigned")
                            .. (aura and "" or OwnList(roster, row.players, colour))
                            .. (
                                onClick and "\nClick to change."
                                or row.plan.pallyPower and "\nPlanned in PallyPower."
                                or ""
                            ),
                        onClick
                    )
                end
            else
                WinText(
                    NAME_W,
                    posY - 10,
                    "No reply: blessings addon off or not installed",
                    12,
                    { 0.6, 0.65, 0.7 }
                )
            end
            posY = posY - CELL - GAP
        end
        winContent:SetHeight(math.abs(posY) + 10)
        local num = 0
        for _, member in ipairs(roster) do
            if member.class == "PALADIN" then
                num = num + 1
            end
        end
        window.foot:SetText(
            not IsInGroup() and (IsPaladin() and "Just you for now" or "Not in a group")
                or num == 0 and "No paladins in your group"
                or num == 1 and "1 paladin in your group"
                or (num .. " paladins in your group")
        )
        window.free:SetShown(IsPaladin())
        window.free:SetChecked(IsPaladin() and Store().free == true)
    end

    function RefreshPage()
        if redrawQueued or not (window and window:IsShown()) then
            return
        end
        redrawQueued = true
        C_Timer.After(0, Redraw)
    end

    local function WinButton(hostFrame, textValue, posX, onClick, tipText)
        local b =
            CludesUI.Kit.Button(hostFrame, textValue, 96, 22, onClick, { key = "essentials", tip = tipText })
        b:SetPoint("TOPLEFT", posX, -34)
        return b
    end

    local function BuildWindow()
        window = CreateFrame("Frame", "CludesUIBlessings", UIParent)
        window:SetSize(WIN_W, WIN_H)
        window:SetPoint("CENTER", 0, 40)
        CludesUI.Kit.Panel(window, 0.96)
        window:SetMovable(true)
        window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        window:SetFrameStrata("HIGH")
        window:SetClampedToScreen(true)
        local title = window:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(title, 15, "essentials")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText("Blessings")
        CludesUI.Kit.AccentText(title)
        local close = CludesUI.Kit.Glyph(window, "x", function()
            window:Hide()
        end, nil, "essentials")
        close:SetPoint("TOPRIGHT", -5, -5)
        WinButton(window, "Auto-Assign", 10, function()
            if Allowed2() then
                Confirm("Replace every paladin's blessings and auras with an automatic plan?", function()
                    ApplyPlans(AutoPlans())
                end)
            end
        end, "A plan for every paladin in the group, by what each has learned.")
        WinButton(window, "Load Preset", 110, function()
            if not next(Presets()) then
                return Print("No preset saved yet.")
            end
            if Allowed2() then
                Confirm("Load the saved preset for the paladins here now?", function()
                    if not LoadPreset() then
                        Print("Nobody in the preset is in your group.")
                    end
                end)
            end
        end)
        WinButton(window, "Save Preset", 210, function()
            if #Paladins() == 0 then
                return Print("No paladins to save a plan for.")
            end
            local function Save()
                if SavePreset() then
                    Print("Blessings preset saved.")
                end
            end
            if next(Presets()) then
                Confirm("Replace the saved preset?", Save)
            else
                Save()
            end
        end, "Saves the plan below to load again with this group.")
        WinButton(window, "Report", 310, function(self)
            CludesUI.Kit.ContextMenu(self, function(_, root)
                root:CreateTitle("Report the blessings to")
                for _, channel in ipairs(REPORT_CHANNELS) do
                    if channel.can() then
                        root:CreateButton(channel.label, function()
                            Report(channel.key)
                        end)
                    end
                end
            end)
        end)
        WinButton(window, "Clear", 410, function()
            if Allowed2() then
                Confirm("Clear every paladin's blessings and auras?", function()
                    ClearAll()
                    RefreshPage()
                end)
            end
        end)
        WinButton(window, "Refresh", 510, function()
            wipe(asked)
            SyncSoon()
            Print("Asked the group's paladins for their plans.")
        end, "Asks the group's paladins for their plans.")
        window.free = CludesUI.Kit.Check(
            window,
            "Free Assignment: other paladins may change your blessings without being the leader or an assistant",
            nil,
            "essentials"
        )
        window.free:SetPoint("TOPLEFT", 14, -64)
        window.free:SetScript("OnClick", function(self)
            Store().free = self:GetChecked() and true or nil
            BroadcastSoon()
            Changed()
        end)
        winScroll = (CludesUI.Kit.Scroll(window))
        winScroll:SetPoint("TOPLEFT", 10, -92)
        winScroll:SetPoint("BOTTOMRIGHT", -30, 28)
        winContent = CreateFrame("Frame", nil, winScroll)
        winContent:SetSize(WIN_W - 44, 10)
        winScroll:SetScrollChild(winContent)
        window.foot = window:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(window.foot, 11, "essentials")
        window.foot:SetTextColor(0.6, 0.65, 0.7)
        window.foot:SetPoint("BOTTOMLEFT", 10, 8)
        window:Hide()
        tinsert(UISpecialFrames, "CludesUIBlessings")
    end

    function OpenWindow()
        if not window then
            BuildWindow()
        end
        window:Show()
        Redraw()
    end

    local function ToggleWindow()
        if window and window:IsShown() then
            window:Hide()
        else
            OpenWindow()
        end
    end

    SLASH_CUIBLESS1 = "/cbless"
    SlashCmdList.CUIBLESS = function()
        if not On() then
            Print("turn on Blessings in CludesUI Forever Tools first.")
            return
        end
        ToggleWindow()
    end
end

CludesUI._Blessings = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Open = OpenWindow,
    ClassBlessing = function(class)
        return Store().classes[class]
    end,
    SetClassBlessing = function(class, key)
        SetOwn(class, key)
    end,
    Blessings = BLESSINGS,
    SpellName = SpellName,
    Learned = Learned,
    Classes = CLASSES,
    ClassName = ClassName,
}

F.Start(Apply, {
    key = "CUI_BlessingBar",
    label = "Blessing Bar",
    order = 755,
    shown = function()
        return F.Enabled() and IsPaladin()
    end,
    frame = function(build)
        if build and not barFrame and not InCombatLockdown() then
            BuildBar()
            Refresh()
        end
        return barFrame
    end,
    size = function()
        return barFrame and barFrame:GetWidth() or Get("size"), barFrame and barFrame:GetHeight() or Get("size")
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
