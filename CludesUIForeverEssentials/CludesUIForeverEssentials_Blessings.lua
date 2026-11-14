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

local function Secret(v)
    return issecretvalue and issecretvalue(v)
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
local function Print(msg)
    CludesUI.Print("|cff4cc9f0Blessings:|r " .. msg)
end
-- Shared between the sections below (each keeps its own helpers in a do block).
local HiddenAuras, Remembered, ForgetIfDead, CastSent, NoteCast, CastDone, ForgetCasts
local OnPallyPower, PP_PREFIX, asked
local Keys, keyAuto

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
local function Index(entry, untracked)
    BY_KEY[entry.key] = entry
    if entry.code then
        BY_CODE[entry.code] = entry
    end
    IDS[entry.key] = {}
    for _, id in ipairs(entry.ranks) do
        if not untracked then
            FAMILY[id] = entry.key
        end
        IDS[entry.key][id] = true
    end
    for _, id in ipairs(entry.greater or {}) do
        FAMILY[id] = entry.key
        IDS[entry.key][id] = true
        GREATER[id] = true
    end
end
for _, entry in ipairs(BLESSINGS) do
    entry.blessing = true
    Index(entry)
end
for _, entry in ipairs(AURAS) do
    Index(entry)
end
for _, entry in ipairs(SEALS) do
    Index(entry, true)
end
Index(FURY)

local function HighestKnown(ids)
    for i = #(ids or {}), 1, -1 do
        if C_SpellBook.IsSpellKnown(ids[i]) then
            return ids[i]
        end
    end
end
local function Learned(entry)
    return HighestKnown(entry.ranks) or (entry.greater and HighestKnown(entry.greater))
end
local function SpellName(key)
    local entry = BY_KEY[key]
    return entry and C_Spell.GetSpellName(entry.ranks[1]) or key
end
local function SpellIcon(key)
    local entry = BY_KEY[key]
    return entry and C_Spell.GetSpellTexture(entry.ranks[1]) or QUESTION
end

-------------------------------------------------------------------------------
--  Your plan, kept per character
-------------------------------------------------------------------------------
local function Store()
    local cfg = F.Cfg()
    cfg.chars = cfg.chars or {}
    local key = UnitName("player") .. "-" .. GetRealmName()
    local store = cfg.chars[key]
    if not (store and store.classes) then
        store = { classes = {}, players = {} }
        cfg.chars[key] = store
    end
    return store
end

local Readable, Roster, Visible, InGroup, CanAssign, Assigned, Allowed, SenderIsUnit
do
    -------------------------------------------------------------------------------
    --  Group
    -------------------------------------------------------------------------------
    local NAME_SLOTS = 4
    function Readable(v)
        return not Secret(v) and v ~= nil and v ~= ""
    end

    local function HeaderNames(member, realm, firstNames, raid)
        local seen, out = {}, {}
        local function Add(name)
            if Readable(name) and not seen[name] then
                seen[name] = true
                out[#out + 1] = name
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
        return table.concat(out, ","), Readable(seenBy) and seen[seenBy] == true
    end

    function Roster()
        local units = { "player" }
        local raid = IsInRaid()
        if raid then
            units = {}
            for i = 1, GetNumGroupMembers() do
                units[#units + 1] = "raid" .. i
            end
        else
            for i = 1, GetNumSubgroupMembers() do
                units[#units + 1] = "party" .. i
            end
        end
        local realm = GetNormalizedRealmName()
        local list, firstNames = {}, {}
        for i, unit in ipairs(units) do
            local name, unitRealm = UnitFullName(unit)
            local _, class = UnitClass(unit)
            local guid = UnitGUID(unit)
            if
                name
                and not (Secret(name) or Secret(unitRealm) or Secret(class) or Secret(guid))
                and class
            then
                local who = name
                if unitRealm and unitRealm ~= "" and unitRealm ~= realm then
                    who = name .. "-" .. unitRealm
                end
                local short, server = UnitName(unit)
                local member = {
                    unit = unit,
                    guid = guid,
                    class = class,
                    who = who,
                    short = short,
                    server = server,
                    rosterName = raid and (GetRaidRosterInfo(i)) or nil,
                }
                local subgroup = raid and select(3, GetRaidRosterInfo(i))
                member.subgroup = not Secret(subgroup) and subgroup or nil
                local names = { who, short, member.rosterName }
                if Readable(short) and Readable(server) then
                    names[4] = short .. "-" .. server
                end
                member.candidates = {}
                local counted = {}
                for k = 1, NAME_SLOTS do
                    local n = names[k]
                    if Readable(n) and not counted[n] then
                        counted[n] = true
                        firstNames[n] = (firstNames[n] or 0) + 1
                        member.candidates[#member.candidates + 1] = n
                    end
                end
                list[#list + 1] = member
            end
        end
        for _, member in ipairs(list) do
            member.names, member.targetable = HeaderNames(member, realm, firstNames, raid)
        end
        return list
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
        local shown = {}
        for _, member in ipairs(roster) do
            if not member.subgroup or member.subgroup <= last then
                shown[#shown + 1] = member
            end
        end
        return shown
    end

    function InGroup(who)
        for _, member in ipairs(Roster()) do
            if member.who == who then
                return member
            end
        end
    end

    function CanAssign(unit)
        local lead, assist = UnitIsGroupLeader(unit), UnitIsGroupAssistant(unit)
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

    local function IsTank(unit)
        local role = UnitGroupRolesAssigned(unit)
        if not Secret(role) and role == "TANK" then
            return true
        end
        return GetPartyAssignment("MAINTANK", unit) and true or false
    end

    local function IsAssist(unit)
        return GetPartyAssignment("MAINASSIST", unit) and true or false
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
        local store = Store()
        return store.players[member.guid] or RoleBlessing(member) or store.classes[member.class]
    end

    function Allowed(class, key)
        local no = Get("smart") and UNSUITED[class]
        return not (no and no[key])
    end

    -- Whether an addon message's sender is this unit.
    function SenderIsUnit(sender, unit, guid)
        if not (Readable(sender) and Readable(unit) and Readable(guid)) then
            return false
        end
        local g = UnitGUID(unit)
        if not Readable(g) or g ~= guid then
            return false
        end
        local first, second = UnitFullName(unit)
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

    function Remembered(unit, key)
        local guid = UnitGUID(unit)
        local mine = guid and not Secret(guid) and seen[guid]
        local ends = mine and mine[key]
        if not ends then
            return false
        end
        local dead = UnitIsDeadOrGhost(unit)
        if not Secret(dead) and dead then
            seen[guid] = nil
            return false
        end
        local left = ends - GetTime()
        if left <= 0 then
            mine[key] = nil
            return false
        end
        return true, left ~= math.huge and left or nil
    end

    function ForgetIfDead(unit)
        if not next(seen) then
            return
        end
        local guid = UnitGUID(unit)
        if not guid or Secret(guid) or not seen[guid] then
            return
        end
        local dead = UnitIsDeadOrGhost(unit)
        if not Secret(dead) and dead then
            seen[guid] = nil
        end
    end

    function CastSent(castGUID, spell)
        sent = { guid = castGUID, spell = spell, at = GetTime() }
    end

    function NoteCast(unit, spell)
        local cast = sent
        sent = nil
        if
            not (unit and spell and cast and cast.spell == spell and cast.at == GetTime() and HiddenAuras())
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
            local same = UnitIsUnit(unit, member.unit)
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
        for id, old in pairs(casts) do
            if GetTime() - old.at >= CAST_WINDOW then
                casts[id] = nil
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
        for _, guid in ipairs(cast.guids) do
            seen[guid] = seen[guid] or {}
            seen[guid][cast.key] = ends
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
        local entry = BY_KEY[key]
        local greater = C_Item.GetItemCount(SYMBOL_OF_KINGS) > 0 and HighestKnown(entry.greater)
        if greater then
            for _, member in ipairs(members) do
                if Assigned(member) ~= key then
                    greater = nil
                    break
                end
            end
        end
        return greater or HighestKnown(entry.ranks)
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

    local function Found(v)
        if v == true then
            return true
        end
        return true, v - GetTime()
    end

    function BuffState(unit, key)
        if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
            if HiddenAuras() then
                return Remembered(unit, key)
            end
            return nil
        end
        local s
        if memoAt and memoAt == GetTime() then
            s = memo[unit]
            if not s then
                s = {}
                memo[unit] = s
            end
            if s.stale then
                wipe(s)
            end
        else
            wipe(scratch)
            s = scratch
        end
        local v = s[key]
        if v then
            return Found(v)
        end
        if s.ended == "none" then
            return false
        end
        if s.ended then
            return nil
        end
        for i = s.next or 1, MAX_AURAS do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not aura then
                s.ended = "none"
                return false
            end
            local id = aura.spellId
            if Secret(id) then
                s.ended = "secret"
                return nil
            end
            local family = FAMILY[id]
            if family and s[family] == nil then
                local expires = aura.expirationTime
                s[family] = (Secret(expires) or not expires or expires == 0) and true or expires
            end
            if family and family == key then
                s.next = i + 1
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
        local rank, left
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
                    local r = not has and 0 or (remaining and remaining < EXPIRING and 1 or 2)
                    if range == true and r < 2 and member.targetable then
                        if r == 0 then
                            s.missingNear = s.missingNear + 1
                        else
                            s.expiringNear = s.expiringNear + 1
                        end
                        if not players[member.guid] then
                            s.classDue = s.classDue + 1
                            if r == 0 then
                                s.classMissing = s.classMissing + 1
                            end
                        end
                    end
                    local l = remaining or math.huge
                    if member.targetable then
                        queue[#queue + 1] = { names = member.names, spell = spell, rank = r, left = l }
                        if not s.target or r < rank or (r == rank and l < left) then
                            s.target, s.spell, rank, left = member, spell, r, l
                        end
                    end
                end
            end
        end
        table.sort(queue, ByUrgency)
        local due = 0
        for _, entry in ipairs(queue) do
            if entry.rank < 2 then
                due = due + 1
            end
        end
        if GREATER[queue[1] and queue[1].spell] then
            due = math.min(due, 1)
        end
        local keep = Get("respect") and 0 or 1
        for i = #queue, math.max(due, keep) + 1, -1 do
            queue[i] = nil
        end
        if due == 0 and keep == 0 then
            s.target = nil
        end
        s.rank, s.left = rank, left
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
        for _, id in ipairs(ranks) do
            STATUS_SPELL[id] = true
        end
    end

    local function CooldownLeft(ranks)
        local spell = HighestKnown(ranks)
        if not spell then
            return -1
        end
        local info = C_Spell.GetSpellCooldown(spell)
        local start, duration = info and info.startTime, info and info.duration
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
        local out = {}
        for i, class in ipairs(CLASSES) do
            out[i] = classes[class] and BY_KEY[classes[class]].code or NONE_CODE
        end
        out[#out + 1] = aura and BY_KEY[aura].code or NONE_CODE
        return table.concat(out)
    end

    local function DecodePlan(text)
        if #text ~= #CLASSES + 1 then
            return
        end
        local classes = {}
        for i, class in ipairs(CLASSES) do
            local c = text:sub(i, i)
            if c ~= NONE_CODE then
                local entry = BY_CODE[c]
                if not (entry and entry.blessing) then
                    return
                end
                classes[class] = entry.key
            end
        end
        local c = text:sub(-1)
        if c == NONE_CODE then
            return classes, nil
        end
        local entry = BY_CODE[c]
        if entry and not entry.blessing then
            return classes, entry.key
        end
    end

    local function KnownCodes()
        local codes = {}
        for _, entry in ipairs(BLESSINGS) do
            if Learned(entry) then
                codes[#codes + 1] = entry.code
            end
        end
        for _, entry in ipairs(AURAS) do
            if Learned(entry) then
                codes[#codes + 1] = entry.code
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

    function Send(msg, key)
        if InCombatLockdown() then
            pending[key or msg] = msg
            return
        end
        local channel = Channel()
        if channel then
            C_ChatInfo.SendAddonMessage(PREFIX, msg, channel)
        end
    end

    local function SendPlayers()
        local players = Store().players
        local parts, n, chunk = {}, 1, ""
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
            Send("P|" .. n .. "|" .. body, "P|" .. n)
            n = n + 1
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
        local store = Store()
        Send("F|" .. EncodePlan(store.classes, store.aura) .. "|" .. KnownCodes())
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
        local store = Store()
        store.classes = {}
        for class, key in pairs(classes) do
            if Learned(BY_KEY[key]) then
                store.classes[class] = key
            end
        end
        store.aura = aura and Learned(BY_KEY[aura]) and aura or nil
        Print(name .. " updated your blessings.")
        BroadcastSoon()
        Changed()
    end

    local function OnStatus(who, symbols, loh, di)
        local from = others[who]
        if not from then
            return
        end
        local now = GetTime()
        local function Ends(left)
            left = tonumber(left)
            return left >= 0 and now + left or nil
        end
        from.status = { symbols = math.min(tonumber(symbols), MAX_SYMBOLS), loh = Ends(loh), di = Ends(di) }
        RefreshPage()
    end

    local function OnPlayers(who, part, list)
        local from = others[who]
        if not from then
            return
        end
        if part == "1" then
            from.players, from.choices = {}, 0
        end
        for guid, code in list:gmatch("(Player%-[%w%-]+)=(%a)") do
            local entry = BY_CODE[code]
            local choices = from.choices or 0
            if entry and entry.blessing and (from.players[guid] or choices < MAX_PLAYER_CHOICES) then
                if not from.players[guid] then
                    from.choices = choices + 1
                end
                from.players[guid] = entry.key
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

    function OnMessage(msg, sender)
        if msg == "R" then
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
        local target, plan = msg:match("^S|([^|]+)|(%S+)$")
        if target then
            return OnAssigned(from, Ambiguate(sender, "none"), target, plan)
        end
        local symbols, loh, di = msg:match("^I|(%d+)|(%-?%d+)|(%-?%d+)$")
        if symbols then
            return OnStatus(who, symbols, loh, di)
        end
        local part, list = msg:match("^P|(%d+)|(.*)$")
        if part then
            return OnPlayers(who, part, list)
        end
        local body, known = msg:match("^F|(%S+)|(%a*)$")
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
        for key, msg in pairs(pending) do
            pending[key] = nil
            Send(msg)
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

    local function PPKnown(plan, keys, ranks)
        for i, key in ipairs(keys) do
            local rank = ranks:sub(2 * i - 1, 2 * i - 1)
            plan.known[key] = rank ~= "" and rank ~= "n" or nil
        end
    end

    local function PPPick(plan, keys, index)
        local key = keys[tonumber(index)]
        return key and plan.known[key] and key or nil
    end

    local function PPClasses(plan, given)
        plan.classes = {}
        for i, class in ipairs(PP_CLASSES) do
            plan.classes[class] = PPPick(plan, PP_BLESSINGS, given:sub(i, i))
        end
    end

    local function PPEnds(left)
        left = tonumber(left)
        return left and left >= 0 and left <= PP_MAX_COOLDOWN and GetTime() + left or nil
    end

    local function PPTarget(name, from)
        local member = Sender(name)
        local plan = member and others[member.who]
        if plan and plan.pallyPower and (member.guid == from.guid or CanAssign(from.unit) or plan.free) then
            return plan
        end
    end

    local function PPChange(msg, from)
        if msg == "CLEAR" or msg == "CLEAR SKIP" then
            local lead = CanAssign(from.unit)
            for _, plan in pairs(others) do
                if plan.pallyPower and (lead or plan.free) then
                    plan.classes = {}
                    if msg == "CLEAR" then
                        plan.aura = nil
                    end
                end
            end
            return
        end
        local name, class, index = msg:match("^ASSIGN (.+) (%d+) (%d+)$")
        if name then
            local plan, column = PPTarget(name, from), PP_CLASSES[tonumber(class)]
            if plan and column then
                plan.classes[column] = PPPick(plan, PP_BLESSINGS, index)
            end
            return
        end
        local given
        name, given = msg:match("^PASSIGN (.+)@([%dn]*)$")
        if name then
            local plan = PPTarget(name, from)
            if plan then
                PPClasses(plan, given)
            end
            return
        end
        name, index = msg:match("^MASSIGN (.+) (%d+)$")
        if name then
            local plan = PPTarget(name, from)
            if not plan then
                return
            end
            local key = PPPick(plan, PP_BLESSINGS, index)
            for _, column in ipairs(PP_CLASSES) do
                plan.classes[column] = key
            end
            return
        end
        name, index = msg:match("^AASSIGN (.+) (%d+)$")
        local plan = name and PPTarget(name, from)
        if plan then
            plan.aura = PPPick(plan, PP_AURAS, index)
        end
    end

    function OnPallyPower(msg, sender)
        local ranks, given = msg:match("^SELF ([%xn]*)@([%dn]*)$")
        local auraRanks, aura = msg:match("^ASELF ([%xn]*)@([%dn]*)$")
        local symbols = msg:match("SYMCOUNT (%d+)")
        local change = PP_CHANGES[msg:match("^%u+")]
        if not (ranks or auraRanks or symbols or change) then
            return
        end
        local from = Sender(sender)
        if not from or from.guid == UnitGUID("player") then
            return
        end
        if change then
            PPChange(msg, from)
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
            local loh, di = msg:match("COOLDOWNS:[^:]*:([^:]*):[^:]*:([^:]*)$")
            plan.free = msg:find("FREEASSIGN YES", 1, true) == 1 or nil
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
        local byBlessing, order = {}, {}
        for _, class in ipairs(CLASSES) do
            local key = plan.classes[class]
            if key then
                if not byBlessing[key] then
                    byBlessing[key] = {}
                    order[#order + 1] = key
                end
                table.insert(byBlessing[key], ClassName(class))
            end
        end
        local parts = {}
        for _, key in ipairs(order) do
            parts[#parts + 1] = SpellName(key) .. " (" .. table.concat(byBlessing[key], ", ") .. ")"
        end
        if plan.aura then
            parts[#parts + 1] = SpellName(plan.aura)
        end
        return #parts > 0 and table.concat(parts, ", ") or "Nothing"
    end

    local function Split(text, out)
        while #text > LINE_MAX do
            local comma = text:sub(1, LINE_MAX):match("^.*(), ")
            out[#out + 1] = text:sub(1, comma and comma - 1 or LINE_MAX)
            text = "  " .. text:sub(comma and comma + 2 or LINE_MAX + 1)
        end
        out[#out + 1] = text
    end

    local function ReportLines()
        local plans = {}
        if IsPaladin() then
            plans[1] = { who = MyName(), plan = Store() }
        end
        local names = {}
        for who in pairs(others) do
            names[#names + 1] = who
        end
        table.sort(names)
        for _, who in ipairs(names) do
            plans[#plans + 1] = { who = who, plan = others[who] }
        end
        if #plans == 0 then
            return
        end
        local lines = { "--- Paladin blessings ---" }
        for _, entry in ipairs(plans) do
            Split(Ambiguate(entry.who, "short") .. ": " .. Given(entry.plan), lines)
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
        local list = {}
        if IsPaladin() then
            local known = {}
            for _, entry in ipairs(BLESSINGS) do
                if Learned(entry) then
                    known[entry.key] = true
                end
            end
            for _, entry in ipairs(AURAS) do
                if Learned(entry) then
                    known[entry.key] = true
                end
            end
            list[1] = { who = MyName(), known = known, you = true }
        end
        for who, plan in pairs(others) do
            list[#list + 1] = { who = who, known = plan.known, fixed = plan.pallyPower and plan or nil }
        end
        for _, p in ipairs(list) do
            p.count = 0
            for _ in pairs(p.known) do
                p.count = p.count + 1
            end
        end
        table.sort(list, function(a, b)
            if a.count ~= b.count then
                return a.count < b.count
            end
            return a.who < b.who
        end)
        return list
    end

    local function Pick(paladins, wanted, give)
        local free = {}
        for _, p in ipairs(paladins) do
            free[#free + 1] = p
        end
        for _, key in ipairs(wanted) do
            for i, p in ipairs(free) do
                if p.known[key] then
                    give(p, key)
                    table.remove(free, i)
                    break
                end
            end
        end
    end

    local function Untaken(wanted, fixed, given)
        local out = {}
        for _, key in ipairs(wanted) do
            local taken = false
            for _, plan in ipairs(fixed) do
                if given(plan) == key then
                    taken = true
                end
            end
            if not taken then
                out[#out + 1] = key
            end
        end
        return out
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
        local store = Store()
        for who, plan in pairs(plans) do
            if who == MyName() then
                store.classes = {}
                for class, key in pairs(plan.classes) do
                    store.classes[class] = key
                end
                store.aura = plan.aura
                BroadcastSoon()
            elseif others[who] and not others[who].pallyPower then
                SendPlan(who, plan.classes, plan.aura)
            end
        end
        Changed()
    end

    function Presets()
        local cfg = F.Cfg()
        cfg.preset = cfg.preset or {}
        return cfg.preset
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

    function SetFor(who, column, key)
        local plan = others[who]
        if not plan then
            return
        end
        if column == AURA_COLUMN then
            plan.aura = key
        else
            plan.classes[column] = key
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

local function LookIcon(frame)
    frame.edge = frame:CreateTexture(nil, "BACKGROUND")
    frame.edge:SetAllPoints()
    frame.edge:SetColorTexture(0, 0, 0, 1)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 1, -1)
    frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    frame.mark = frame:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(frame.mark, 14, "essentials")
    frame.mark:SetPoint("CENTER")
    frame.mark:SetTextColor(RED.r, RED.g, RED.b)
    frame.timer = frame:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(frame.timer, 10, "essentials")
    frame.timer:SetPoint("BOTTOM", 0, 1)
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

local function LookPin(frame, bar, x, y)
    frame:ClearAllPoints()
    if Look.vertical then
        frame:SetPoint("TOPLEFT", bar, "TOPLEFT", y or 0, -x)
    else
        frame:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, y or 0)
    end
end

local function LookPlace(frame, bar, x, y)
    local size = Look.size
    frame:SetSize(size, size)
    CludesUI.Kit.Font(frame.timer, Look.timerSize, "essentials")
    if frame.watchText then
        CludesUI.Kit.Font(frame.watchText, Look.timerSize, "essentials")
    end
    frame.edge:SetShown(Look.border ~= "none")
    if frame.label then
        frame.label:SetShown(Look.labels)
        frame.label:ClearAllPoints()
        if Look.vertical then
            frame.label:SetPoint("LEFT", frame, "RIGHT", LABEL_SIDE, 0)
            frame.label:SetWidth(Look.rows > 1 and LABEL_COLUMN or 0)
        else
            frame.label:SetPoint("TOP", frame, "BOTTOM", 0, -LABEL_DROP)
            frame.label:SetWidth(size + Look.gap)
        end
    end
    LookPin(frame, bar, x, y)
    frame:Show()
    return x + size + Look.gap
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

local function LookSelf(frame, missing, remaining)
    frame.icon:SetVertexColor(missing and RED.r or 1, missing and RED.g or 1, missing and RED.b or 1)
    frame.mark:SetText(missing and "!" or "")
    frame.timer:SetText(Minutes(remaining))
end

local function LookState(frame, key, has, remaining)
    local missing = key ~= nil and (frame.watch ~= nil or has == false)
    LookSelf(frame, missing, not frame.watch and remaining)
end

local function LookFit(frame, x)
    local across = Look.size + (Look.rows - 1) * RowStep()
    local along = math.max(x - Look.gap, Look.size)
    if Look.vertical then
        frame:SetSize(across, along)
    else
        frame:SetSize(along, across)
    end
end

-------------------------------------------------------------------------------
--  The game's own aura display over a button: shows a buff and its time,
--  in combat too.
-------------------------------------------------------------------------------
local watchUnavailable

local function Watch(frame)
    if watchUnavailable then
        return
    end
    local ok, container = pcall(function()
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
        local c = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
        c:SetAllPoints(frame)
        c:SetFrameLevel(frame:GetFrameLevel() + 2)
        c:EnableMouse(false)
        c:AddAuraSlot("buff", "HELPFUL", {
            candidateFilters = { includeSpellIDs = {} },
            initializeFrame = function(button)
                button:SetAllPoints(frame.icon)
                button:EnableMouse(false)
                local icon = button:CreateTexture(nil, "ARTWORK")
                icon:SetAllPoints()
                icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
                button:SetIcon(icon)
                local text = button:CreateFontString(nil, "OVERLAY")
                CludesUI.Kit.Font(text, Get("timerSize"), "essentials")
                frame.watchText = text
                text:SetPoint("BOTTOM", 0, 1)
                button:SetDurationText(text, {})
            end,
        })
        c:SetEnabled(false)
        return c
    end)
    if not ok then
        watchUnavailable = true
        return
    end
    frame.watch = container
end

local function SetWatch(frame, unit, key)
    local c = frame.watch
    if not c or (frame.watchUnit == unit and frame.watchKey == key) then
        return
    end
    frame.watchUnit, frame.watchKey = unit, key
    c:SetUnit(unit or "none")
    c:SetAuraSlotCandidateFilters("buff", { includeSpellIDs = key and IDS[key] or {} })
    c:SetEnabled(unit ~= nil and key ~= nil)
end

-------------------------------------------------------------------------------
--  A secure button that follows one named player through raid reordering,
--  even in combat
-------------------------------------------------------------------------------
local function Recipient(parent, name)
    local header = CreateFrame("Frame", name, parent, "SecureGroupHeaderTemplate")
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
    header:SetPoint("TOPLEFT", parent, "TOPLEFT")
    header:Show()
    local button = header:GetAttribute("child1")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type1", "spell")
    return header, button
end

local function SetNames(header, names)
    if header:GetAttribute("nameList") ~= names then
        header:SetAttribute("nameList", names)
    end
end

local function SizeRecipient(header, button, size)
    header:SetAttribute("minWidth", size)
    header:SetAttribute("minHeight", size)
    button:SetSize(size, size)
end

-------------------------------------------------------------------------------
--  Menus
-------------------------------------------------------------------------------
local OpenWindow, PlayerList

local function SetOwn(column, key)
    local store = Store()
    if column == AURA_COLUMN then
        store.aura = key
    else
        store.classes[column] = key
    end
    BroadcastSoon()
    Changed()
end

local function OpenMenu(owner, title, list, current, choose, noneText, can)
    can = can or Learned
    CludesUI.Kit.ContextMenu(owner, function(_, root)
        root:CreateTitle(title)
        for _, entry in ipairs(list) do
            if can(entry) then
                root:CreateRadio(SpellName(entry.key), function()
                    return current() == entry.key
                end, function()
                    choose(entry.key)
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

local function SealMenu(owner)
    OpenMenu(owner, "Seal", SEALS, function()
        return Store().seal
    end, SetSeal, "Default")
end

local function AuraMenu(owner)
    OpenMenu(owner, "Aura", AURAS, function()
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

local function ClassMenu(owner, class)
    CludesUI.Kit.ContextMenu(owner, function(_, root)
        root:CreateTitle(ClassName(class))
        for _, entry in ipairs(BLESSINGS) do
            if Learned(entry) and (Store().classes[class] == entry.key or Allowed(class, entry.key)) then
                root:CreateRadio(SpellName(entry.key), function()
                    return Store().classes[class] == entry.key
                end, function()
                    SetOwn(class, entry.key)
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
                for _, guid in ipairs(own) do
                    players[guid] = nil
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

local function Tip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        if not Get("tooltips") then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        local text = type(body) == "function" and body() or body
        local ar, ag, ab = CludesUI.Kit.Accent()
        if text and text ~= "" then
            GameTooltip:AddLine(text, ar, ag, ab, true)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local Refresh
do
    -------------------------------------------------------------------------------
    --  Player list: a class's players above the bar, to bless one person or give
    --  them their own blessing
    -------------------------------------------------------------------------------
    local flyout, rows, flyoutClass
    local listMembers = {}
    PlayerList = {}

    local function PlayerMenu(owner, member)
        local store = Store()
        local function Can(entry)
            return Learned(entry)
                and (store.players[member.guid] == entry.key or Allowed(member.class, entry.key))
        end
        OpenMenu(owner, Ambiguate(member.who, "short"), BLESSINGS, function()
            return store.players[member.guid]
        end, function(key)
            store.players[member.guid] = key
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
        row.cast:SetScript("PostClick", function(self, button, down)
            if button == "RightButton" and not down and row.member then
                PlayerMenu(self, row.member)
            end
            if button == "LeftButton" then
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

    local function PaintRow(row, member, store)
        row.member = member
        local color = RAID_CLASS_COLORS[member.class]
        row.name:SetText(Ambiguate(member.who, "short"))
        row.name:SetTextColor(color.r, color.g, color.b)
        local own = store.players[member.guid]
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

    function PlayerList.Build(bar)
        flyout = CreateFrame("Frame", nil, bar)
        flyout:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 18)
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
        rows = {}
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
        local store = Store()
        flyout:Show()
        for i, member in ipairs(listMembers) do
            local row = rows[i] or NewRow(i)
            rows[i] = row
            PaintRow(row, member, store)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 6, -26 - (i - 1) * 32)
            row:Show()
        end
        for i = #listMembers + 1, #rows do
            SetNames(rows[i].header, NOBODY)
            SetWatch(rows[i].slot, nil, nil)
            rows[i]:Hide()
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
    Keys = {}

    local function NewKeyButton(name, handler)
        local btn = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        btn:RegisterForClicks("AnyDown")
        btn:SetAttribute("useOnKeyDown", true)
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("count", 0)
        SecureHandlerWrapScript(btn, "OnClick", handler, KEY_STEP)
        btn:SetScript("PostClick", function(self)
            NoteCast(self:GetAttribute("unit"), self:GetAttribute("spell"))
        end)
        return btn
    end

    local function SetQueue(btn, list, kind)
        kind = kind or ""
        table.sort(list, ByUrgency)
        for i, entry in ipairs(list) do
            btn:SetAttribute("unit" .. kind .. i, entry.unit)
            btn:SetAttribute("spell" .. kind .. i, entry.spell)
        end
        btn:SetAttribute("count" .. kind, #list)
        btn:SetAttribute("step" .. kind, 1)
    end

    local function Singles(members, single, shared)
        for _, member in ipairs(members) do
            local key = Assigned(member)
            if key ~= shared then
                shared = nil
            end
            local spell = key and HighestKnown(BY_KEY[key].ranks)
            local rank, left = Due(member, key, spell)
            if rank then
                single[#single + 1] = { unit = member.unit, spell = spell, rank = rank, left = left }
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
            local rank, left = Due(member, shared, spell)
            if rank and (not best or ByUrgency({ rank = rank, left = left }, best)) then
                best = { unit = member.unit, spell = spell, rank = rank, left = left }
            end
        end
        return best
    end

    function Keys.Build(handler)
        keyNext = NewKeyButton("CludesUIBlessNext", handler)
        keyGreater = NewKeyButton("CludesUIBlessNextGreater", handler)
    end

    function Keys.Peek()
        if not keyNext then
            return
        end
        return keyNext:GetAttribute("spell1") or keyGreater:GetAttribute("spell1"),
            keyNext:GetAttribute("count") or 0
    end

    function Keys.Clear()
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

    function Keys.Fill(byClass)
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
local bar, cells, auraButton, furyButton, sealButton, autoButton, secureHandler
local dirty, ticker, buildAfterCombat
local refreshQueued, landing, landingQueued, sentSymbols
local events = CreateFrame("Frame")
local Apply

local function SurveyQueue(cell, queue)
    local parts = {}
    for i, entry in ipairs(queue) do
        parts[i] = entry.names .. "=" .. entry.spell
    end
    local signature = table.concat(parts, ";")
    if signature == cell.signature then
        return
    end
    cell.signature = signature
    for i, entry in ipairs(queue) do
        cell.cast:SetAttribute("queueNames" .. i, entry.names)
        cell.cast:SetAttribute("queueSpell" .. i, entry.spell)
    end
    cell.cast:SetAttribute("count", #queue)
end

local function PaintCell(cell, s, key)
    local queue = s.queue
    local shown = s.spell or (key and CastSpell(key, cell.members))
    cell.icon:SetTexture(shown and C_Spell.GetSpellTexture(shown) or QUESTION)
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
    local cell = CreateFrame("Frame", nil, bar)
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
    cell.cast:SetScript("PreClick", function(_, button)
        if
            button == "LeftButton"
            and not InCombatLockdown()
            and not (SecretAuras() and not HiddenAuras())
        then
            PrepareCell(cell)
        end
    end)
    SecureHandlerWrapScript(cell.cast, "OnClick", secureHandler, CLASS_STEP)
    cell.cast:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and not down then
            ClassMenu(self, class)
        end
        if button == "LeftButton" then
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
    for _, entry in ipairs(AURAS) do
        if Learned(entry) then
            return entry.key
        end
    end
end

local function CurrentSeal()
    local key = Store().seal
    if key and Learned(BY_KEY[key]) then
        return key
    end
    for _, entry in ipairs(SEALS) do
        if Learned(entry) then
            return entry.key
        end
    end
end

local function Cycle(list, current, choose, delta)
    if InCombatLockdown() then
        return
    end
    local known = {}
    for _, entry in ipairs(list) do
        if Learned(entry) then
            known[#known + 1] = entry.key
        end
    end
    if #known < 2 then
        return
    end
    local at = 1
    for i, key in ipairs(known) do
        if key == current() then
            at = i
        end
    end
    choose(known[(at - 1 + (delta > 0 and 1 or -1)) % #known + 1])
end

local function NewBarButton(name)
    local btn = CreateFrame("Button", name, bar, "SecureActionButtonTemplate")
    LookIcon(btn)
    return btn
end

local function NewSelfButton(name)
    local btn = NewBarButton(name)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type1", "spell")
    btn:SetAttribute("unit1", "player")
    Watch(btn)
    return btn
end

local function NewAutoButton(name)
    local btn = NewBarButton(name)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetAttribute("type1", "spell")
    btn:SetAttribute("type2", "spell")
    btn:SetAttribute("countN", 0)
    btn:SetAttribute("countG", 0)
    SecureHandlerWrapScript(btn, "OnClick", secureHandler, AUTO_STEP)
    btn:SetScript("PostClick", function(self)
        NoteCast(self:GetAttribute("unit"), self:GetAttribute("spell"))
    end)
    keyAuto = btn
    return btn
end

local function PrepareSeal(btn, key)
    local id = BY_KEY[key].ranks[1]
    btn:SetAttribute("spell1", C_Spell.GetSpellName(id))
    btn.icon:SetTexture(C_Spell.GetSpellTexture(id))
    SetWatch(btn, "player", key)
    LookSelf(btn, false)
end

local function PaintAuto()
    if not autoButton:IsShown() then
        return
    end
    local spell, due = Keys.Peek()
    autoButton.icon:SetTexture(spell and C_Spell.GetSpellTexture(spell) or QUESTION)
    autoButton.icon:SetDesaturated(due == 0)
    autoButton.mark:SetText(due > 0 and due or "")
end

local function PrepareSelf(btn, key)
    local spell = HighestKnown(BY_KEY[key].ranks)
    btn:SetAttribute("spell1", spell)
    btn.icon:SetTexture(C_Spell.GetSpellTexture(spell))
    SetWatch(btn, "player", key)
    LookState(btn, key, BuffState("player", key))
end

local function PlaceSelf(x)
    local aura = Get("showAura") and CurrentAura()
    if aura then
        PrepareSelf(auraButton, aura)
        x = LookPlace(auraButton, bar, x)
    else
        auraButton:Hide()
    end
    if Get("showFury") and Learned(FURY) then
        PrepareSelf(furyButton, "fury")
        x = LookPlace(furyButton, bar, x)
    else
        furyButton:Hide()
    end
    local seal = Get("showSeal") and CurrentSeal()
    if seal then
        PrepareSeal(sealButton, seal)
        x = LookPlace(sealButton, bar, x)
    else
        sealButton:Hide()
    end
    if Get("showAuto") then
        autoButton:SetAttribute("leftKind", Get("autoGreater") and "G" or "N")
        x = LookPlace(autoButton, bar, x)
    else
        autoButton:Hide()
    end
    if x > 0 then
        return x + Look.groupGap
    end
    return x
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

local function PlaceCells(byClass, x)
    local count = 0
    for _, class in ipairs(CLASSES) do
        if byClass[class] then
            count = count + 1
        end
    end
    Look.rows = math.max(1, math.ceil(count / Look.perRow))
    local done = x + math.min(count, Look.perRow) * (Look.size + Look.gap)
    local i = 0
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
                bar,
                x + i % Look.perRow * (Look.size + Look.gap),
                math.floor(i / Look.perRow) * RowStep()
            )
            i = i + 1
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
    if not bar then
        return
    end
    if InCombatLockdown() or (SecretAuras() and not HiddenAuras()) then
        dirty = true
        return
    end
    dirty = false
    if not (On() and IsPaladin() and (Wanted() or CludesUI._unlockActive)) then
        bar:Hide()
        Keys.Clear()
        return
    end
    bar:Show()
    BeginAuraMemo()
    LookRead()
    local x = PlaceSelf(0)
    local roster = Visible(Roster())
    local byClass = ByClass(roster)
    if Get("showClasses") then
        x = PlaceCells(byClass, x)
    else
        for _, cell in pairs(cells) do
            HideCell(cell)
        end
    end
    PlayerList.Arrange(roster)
    Keys.Fill(byClass)
    PaintAuto()
    EndAuraMemo()
    LookFit(bar, x)
    bar:SetShown(x > 0 or CludesUI._unlockActive)
end

function Changed()
    if Refresh then
        Refresh()
    end
    RefreshPage()
end

local function OnSelfClick(self, button)
    if button == "LeftButton" then
        NoteCast(self:GetAttribute("unit1"), self:GetAttribute("spell1"))
    end
end

local function BuildBar()
    bar = CreateFrame("Frame", "CludesUIBlessingBar", UIParent)
    bar:SetClampedToScreen(true)
    bar:SetSize(Get("size"), Get("size"))
    cells = {}
    secureHandler = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    auraButton = NewSelfButton("CludesUIBlessAura")
    auraButton:SetScript("PostClick", function(self, button, down)
        OnSelfClick(self, button)
        if button == "RightButton" and not down then
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
    sealButton:SetScript("PostClick", function(self, button, down)
        if button == "RightButton" and not down then
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
    Keys.Build(secureHandler)
    autoButton = NewAutoButton("CludesUIBlessAuto")
    Tip(
        autoButton,
        "Auto Buff",
        "Left-click: the next blessing. Right-click: the next Greater Blessing. Each goes to whoever needs it most."
    )
    PlayerList.Build(bar)
    if not CludesUI._unlockActive then
        F.Place(bar)
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

local function OnUnitAura(unit)
    local fresh = landing and GetTime() - landing < LANDING_WINDOW
    if refreshQueued and not fresh then
        return
    end
    if InCombatLockdown() then
        dirty = true
        return
    end
    if unit == "player" or unit:find("party", 1, true) == 1 or unit:find("raid", 1, true) == 1 then
        if fresh then
            RefreshLanded()
        else
            RefreshSoon()
        end
    end
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if Secret(prefix) or Secret(msg) or Secret(channel) or Secret(sender) then
            return
        end
        if prefix == PREFIX and GROUP_CHANNELS[channel] then
            OnMessage(msg, sender)
        elseif prefix == PP_PREFIX and (GROUP_CHANNELS[channel] or channel == "WHISPER") then
            OnPallyPower(msg, sender)
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if event == "PLAYER_ENTERING_WORLD" then
            if HiddenAuras() and IsPaladin() then
                events:RegisterEvent("UNIT_HEALTH")
            else
                events:UnregisterEvent("UNIT_HEALTH")
                ForgetCasts()
            end
        end
        SyncSoon()
        RefreshSoon()
    elseif event == "PARTY_LEADER_CHANGED" then
        RefreshPage()
    elseif event == "PLAYER_ROLES_ASSIGNED" then
        RefreshSoon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if buildAfterCombat then
            buildAfterCombat = false
            Apply()
        elseif dirty then
            Refresh()
        end
        AfterCombat()
    elseif event == "SPELLS_CHANGED" then
        BroadcastSoon()
        RefreshSoon()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local _, _, castGUID, spellID = ...
        if Secret(castGUID) or Secret(spellID) or not FAMILY[spellID] then
            return
        end
        CastSent(castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
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
    elseif event == "UNIT_HEALTH" then
        ForgetIfDead(...)
    elseif event == "UNIT_AURA" then
        OnUnitAura(...)
    end
end)

local function OnTick()
    if not (bar and bar:IsShown() and not InCombatLockdown()) then
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
        if bar and InCombatLockdown() then
            dirty = true
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
        elseif bar then
            bar:Hide()
            Keys.Clear()
        end
        return
    end
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(PP_PREFIX)
    for _, e in ipairs({
        "CHAT_MSG_ADDON",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD",
        "PARTY_LEADER_CHANGED",
        "PLAYER_REGEN_ENABLED",
    }) do
        events:RegisterEvent(e)
    end
    if not IsPaladin() then
        return
    end
    for _, e in ipairs({ "UNIT_AURA", "PLAYER_ROLES_ASSIGNED", "SPELLS_CHANGED" }) do
        events:RegisterEvent(e)
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    if not bar and InCombatLockdown() then
        buildAfterCombat = true
        return
    end
    if not bar then
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
    local win, winContent, winScroll
    local winPool, winUsed = {}, 0
    local redrawQueued

    StaticPopupDialogs.CUI_BLESS_CONFIRM = {
        text = "%s",
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function(_, data)
            if data then
                data()
            end
        end,
    }
    local function Confirm(text, fn)
        local dialog = StaticPopup_Show("CUI_BLESS_CONFIRM", text)
        if dialog then
            dialog.data = fn
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
        local item = winPool[winUsed]
        if item and item.kind ~= kind then
            item:Hide()
            item = nil
        end
        if not item then
            if kind == "cell" then
                item = CreateFrame("Button", nil, winContent)
                item:SetSize(CELL, CELL)
                LookIcon(item)
                item:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.title or "", 1, 1, 1)
                    local ar, ag, ab = CludesUI.Kit.Accent()
                    if self.body then
                        GameTooltip:AddLine(self.body, ar, ag, ab, true)
                    end
                    GameTooltip:Show()
                end)
                item:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            else
                item = CreateFrame("Frame", nil, winContent)
                item:SetSize(1, 1)
                item.text = item:CreateFontString(nil, "OVERLAY")
                item.text:SetPoint("TOPLEFT")
                item.text:SetJustifyH("LEFT")
            end
            item.kind = kind
            local old = winPool[winUsed]
            if old then
                old:Hide()
            end
            winPool[winUsed] = item
        end
        item:ClearAllPoints()
        item:Show()
        return item
    end

    local function WinText(x, y, text, size, colour, width)
        local item = WinItem("text")
        item:SetPoint("TOPLEFT", winContent, "TOPLEFT", x, y)
        CludesUI.Kit.Font(item.text, size or 12, "essentials")
        item.text:SetTextColor(unpack(colour or { 1, 1, 1 }))
        item.text:SetWidth(width or 0)
        item.text:SetWordWrap(width ~= nil)
        item.text:SetText(text)
        return item.text:GetStringHeight()
    end

    local function WinCell(x, y, icon, lit, title, body, onClick)
        local btn = WinItem("cell")
        btn:SetPoint("TOPLEFT", winContent, "TOPLEFT", x, y)
        btn.icon:SetTexture(icon)
        btn.icon:SetDesaturated(not lit)
        btn.icon:SetAlpha(lit and 1 or 0.35)
        btn.icon:SetVertexColor(1, 1, 1)
        btn.mark:SetText("")
        btn.timer:SetText("")
        btn.title, btn.body = title, body
        btn:SetScript("OnClick", onClick)
    end

    local function Remaining(left)
        if not left then
            return
        end
        return left > 0 and (math.ceil(left / 60) .. "m") or "ready"
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
            local status, now = row.plan.status, GetTime()
            symbols = status.symbols
            loh = status.loh and status.loh - now
            di = status.di and status.di - now
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
        local list = {}
        if IsPaladin() then
            local store = Store()
            list[1] = {
                who = MyName(),
                you = true,
                plan = store,
                players = store.players,
                can = Learned,
                set = SetOwn,
            }
        end
        local mayFree = IsPaladin()
        local names = {}
        for who in pairs(others) do
            names[#names + 1] = who
        end
        table.sort(names)
        for _, who in ipairs(names) do
            local plan = others[who]
            list[#list + 1] = {
                who = who,
                plan = plan,
                players = plan.players,
                can = function(entry)
                    return plan.known[entry.key]
                end,
                set = not plan.pallyPower and (lead or (mayFree and plan.free)) and function(column, key)
                    SetFor(who, column, key)
                    RefreshPage()
                end,
            }
        end
        for _, member in ipairs(roster) do
            if member.class == "PALADIN" and member.guid ~= UnitGUID("player") and not others[member.who] then
                list[#list + 1] = { who = member.who }
            end
        end
        return list
    end

    local function OwnList(roster, players, class)
        local out = {}
        for _, member in ipairs(roster) do
            local key = member.class == class and players and players[member.guid]
            if key then
                out[#out + 1] = Ambiguate(member.who, "short") .. ": " .. SpellName(key)
            end
        end
        return #out > 0 and ("\n" .. table.concat(out, "\n")) or ""
    end

    local function Redraw()
        redrawQueued = false
        if not (win and win:IsShown()) then
            return
        end
        for i = 1, winUsed do
            winPool[i]:Hide()
        end
        winUsed = 0
        local y = -4
        local roster = Roster()
        local columns = {}
        for _, class in ipairs(CLASSES) do
            columns[#columns + 1] = class
        end
        columns[#columns + 1] = AURA_COLUMN
        for i, column in ipairs(columns) do
            local aura = column == AURA_COLUMN
            WinCell(
                NAME_W + (i - 1) * (CELL + GAP),
                y,
                aura and SpellIcon("devotion")
                    or ("Interface\\Icons\\ClassIcon_" .. column:lower():gsub("^%l", string.upper)),
                true,
                aura and "Aura" or ClassName(column)
            )
        end
        y = y - CELL - 10
        local list = Rows(roster)
        if #list == 0 then
            WinText(0, y, "No paladins in your group.", 12, { 0.6, 0.65, 0.7 })
            y = y - 20
        end
        for _, row in ipairs(list) do
            WinText(
                0,
                y - 4,
                Ambiguate(row.who, "short") .. (row.you and "  (you)" or ""),
                13,
                { 0.96, 0.55, 0.73 },
                NAME_W - 10
            )
            if row.plan then
                WinText(0, y - 20, StatusText(row), 10, { 0.6, 0.65, 0.7 }, NAME_W - 10)
                for i, column in ipairs(columns) do
                    local aura = column == AURA_COLUMN
                    local key = aura and row.plan.aura or row.plan.classes[column]
                    local title = aura and "Aura" or ClassName(column)
                    local onClick = row.set
                        and function(btn)
                            local function Can(entry)
                                return row.can(entry)
                                    and (aura or key == entry.key or Allowed(column, entry.key))
                            end
                            OpenMenu(btn, title, aura and AURAS or BLESSINGS, function()
                                return aura and row.plan.aura or row.plan.classes[column]
                            end, function(choice)
                                row.set(column, choice)
                            end, "None", Can)
                        end
                    WinCell(
                        NAME_W + (i - 1) * (CELL + GAP),
                        y,
                        key and SpellIcon(key) or QUESTION,
                        key ~= nil,
                        title,
                        (key and SpellName(key) or "Nothing assigned")
                            .. (aura and "" or OwnList(roster, row.players, column))
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
                    y - 10,
                    "No reply: blessings addon off or not installed",
                    12,
                    { 0.6, 0.65, 0.7 }
                )
            end
            y = y - CELL - GAP
        end
        winContent:SetHeight(math.abs(y) + 10)
        local n = 0
        for _, member in ipairs(roster) do
            if member.class == "PALADIN" then
                n = n + 1
            end
        end
        win.foot:SetText(
            not IsInGroup() and (IsPaladin() and "Just you for now" or "Not in a group")
                or n == 0 and "No paladins in your group"
                or n == 1 and "1 paladin in your group"
                or (n .. " paladins in your group")
        )
        win.free:SetShown(IsPaladin())
        win.free:SetChecked(IsPaladin() and Store().free == true)
    end

    function RefreshPage()
        if redrawQueued or not (win and win:IsShown()) then
            return
        end
        redrawQueued = true
        C_Timer.After(0, Redraw)
    end

    local function WinButton(parent, text, x, onClick, tip)
        local b = CludesUI.Kit.Button(parent, text, 96, 22, onClick, { key = "essentials", tip = tip })
        b:SetPoint("TOPLEFT", x, -34)
        return b
    end

    local function BuildWindow()
        win = CreateFrame("Frame", "CludesUIBlessings", UIParent)
        win:SetSize(WIN_W, WIN_H)
        win:SetPoint("CENTER", 0, 40)
        CludesUI.Kit.Panel(win, 0.96)
        win:SetMovable(true)
        win:EnableMouse(true)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        win:SetFrameStrata("HIGH")
        win:SetClampedToScreen(true)
        local title = win:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(title, 15, "essentials")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText("Blessings")
        CludesUI.Kit.AccentText(title)
        local close = CludesUI.Kit.Glyph(win, "x", function()
            win:Hide()
        end, nil, "essentials")
        close:SetPoint("TOPRIGHT", -5, -5)
        WinButton(win, "Auto-Assign", 10, function()
            if Allowed2() then
                Confirm("Replace every paladin's blessings and auras with an automatic plan?", function()
                    ApplyPlans(AutoPlans())
                end)
            end
        end, "A plan for every paladin in the group, by what each has learned.")
        WinButton(win, "Load Preset", 110, function()
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
        WinButton(win, "Save Preset", 210, function()
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
        WinButton(win, "Report", 310, function(self)
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
        WinButton(win, "Clear", 410, function()
            if Allowed2() then
                Confirm("Clear every paladin's blessings and auras?", function()
                    ClearAll()
                    RefreshPage()
                end)
            end
        end)
        WinButton(win, "Refresh", 510, function()
            wipe(asked)
            SyncSoon()
            Print("Asked the group's paladins for their plans.")
        end, "Asks the group's paladins for their plans.")
        win.free = CludesUI.Kit.Check(
            win,
            "Free Assignment: other paladins may change your blessings without being the leader or an assistant",
            nil,
            "essentials"
        )
        win.free:SetPoint("TOPLEFT", 14, -64)
        win.free:SetScript("OnClick", function(self)
            Store().free = self:GetChecked() and true or nil
            BroadcastSoon()
            Changed()
        end)
        winScroll = (CludesUI.Kit.Scroll(win))
        winScroll:SetPoint("TOPLEFT", 10, -92)
        winScroll:SetPoint("BOTTOMRIGHT", -30, 28)
        winContent = CreateFrame("Frame", nil, winScroll)
        winContent:SetSize(WIN_W - 44, 10)
        winScroll:SetScrollChild(winContent)
        win.foot = win:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(win.foot, 11, "essentials")
        win.foot:SetTextColor(0.6, 0.65, 0.7)
        win.foot:SetPoint("BOTTOMLEFT", 10, 8)
        win:Hide()
        tinsert(UISpecialFrames, "CludesUIBlessings")
    end

    function OpenWindow()
        if not win then
            BuildWindow()
        end
        win:Show()
        Redraw()
    end

    local function ToggleWindow()
        if win and win:IsShown() then
            win:Hide()
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
        if build and not bar and not InCombatLockdown() then
            BuildBar()
            Refresh()
        end
        return bar
    end,
    size = function()
        return bar and bar:GetWidth() or Get("size"), bar and bar:GetHeight() or Get("size")
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
