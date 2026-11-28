if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
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
--  a shared format other addons use too, and PallyPower users' plans are read.
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

local CLASS_LIST = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_OK = {}
for _, class in ipairs(CLASS_LIST) do
    CLASS_OK[class] = true
end
local AURA_COL = "AURA"
local NO_ONE = "-"
local ASK_CODE = 134400

local B = { others = {} }
local others = B.others

local function Secret(val) return issecretvalue and issecretvalue(val) end
local function PaladinUnit() return select(2, UnitClass("player")) == "PALADIN" end
local function OwnName() return (UnitFullName("player")) end
local function ClassLabel(class) return LOCALIZED_CLASS_NAMES_MALE[class] or class end
local function On() return F.Enabled() end
local function Print(message) CUI.Print("|cff4cc9f0Blessings:|r " .. message) end
-- Shared between the sections below (each keeps its own helpers in a do block).
local AurasHidden, Recalled, DropIfDead, OnCastSent, RecordCast, OnCastDone, DropCasts
local FromPP, PPA_PREFIX, asked
local K, keyAuto

-------------------------------------------------------------------------------
--  Spells
-------------------------------------------------------------------------------
local BLESSING_LIST = {
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
local AURA_LIST = {
    { key = "devotion", code = "D", ranks = { 465, 10290, 643, 10291, 1032, 10292, 10293 } },
    { key = "retribution", code = "R", ranks = { 7294, 10298, 10299, 10300, 10301 } },
    { key = "concentration", code = "C", ranks = { 19746 } },
    { key = "shadow", code = "S", ranks = { 19876, 19895, 19896 } },
    { key = "frost", code = "F", ranks = { 19888, 19897, 19898 } },
    { key = "fire", code = "I", ranks = { 19891, 19899, 19900 } },
    { key = "sanctity", code = "T", ranks = { 20218 } },
}
local SPELL_FURY = { key = "fury", ranks = { 25780 } }
local SEAL_LIST = {
    { key = "sealRighteousness", ranks = { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 } },
    { key = "sealCommand", ranks = { 20375, 20915, 20918, 20919, 20920 } },
    { key = "sealFury", ranks = { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 } },
    { key = "sealCrusader", ranks = { 21082, 20162, 20305, 20306, 20307, 20308 } },
    { key = "sealJustice", ranks = { 20164 } },
    { key = "sealLight", ranks = { 20165, 20347, 20348, 20349 } },
    { key = "sealWisdom", ranks = { 20166, 20356, 20357 } },
}
local ITEM_SYMBOL = 21177
local UNASSIGNED_FLAG = "X"

local FROM_KEY, FROM_CODE, SPELL_FAMILY, SPELL_IDS, GREATER_MAP = {}, {}, {}, {}, {}
local function IndexOf(record, untracked)
    FROM_KEY[record.key] = record
    if record.code then FROM_CODE[record.code] = record end
    SPELL_IDS[record.key] = {}
    for _, ident in ipairs(record.ranks) do
        if not untracked then SPELL_FAMILY[ident] = record.key end
        SPELL_IDS[record.key][ident] = true
    end
    for _, ident in ipairs(record.greater or {}) do
        SPELL_FAMILY[ident] = record.key
        SPELL_IDS[record.key][ident] = true
        GREATER_MAP[ident] = true
    end
end
for _, record in ipairs(BLESSING_LIST) do
    record.blessing = true
    IndexOf(record)
end
for _, record in ipairs(AURA_LIST) do
    IndexOf(record)
end
for _, record in ipairs(SEAL_LIST) do
    IndexOf(record, true)
end
IndexOf(SPELL_FURY)

local function BestRank(ids)
    for index = #(ids or {}), 1, -1 do
        if C_SpellBook.IsSpellKnown(ids[index]) then return ids[index] end
    end
end
local function OnLearned(record)
    return BestRank(record.ranks) or (record.greater and BestRank(record.greater))
end
local function NameOfSpell(key)
    local record = FROM_KEY[key]
    return record and C_Spell.GetSpellName(record.ranks[1]) or key
end
local function IconOfSpell(key)
    local record = FROM_KEY[key]
    return record and C_Spell.GetSpellTexture(record.ranks[1]) or ASK_CODE
end

-------------------------------------------------------------------------------
--  Your plan, kept per character
-------------------------------------------------------------------------------
local function Keep()
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

local ReadableName, GroupRoster, ShownNow, Grouped, AssignAllowed, AssignedTo, MayCast, SenderUnit
do
    -------------------------------------------------------------------------------
    --  Group
    -------------------------------------------------------------------------------
    local NAME_COUNT = 4
    function ReadableName(val) return not Secret(val) and val ~= nil and val ~= "" end

    local function ColumnNames(member, realm, firstNames, raid)
        local seen, result = {}, {}
        local function Append(name)
            if ReadableName(name) and not seen[name] then
                seen[name] = true
                result[#result + 1] = name
            end
        end
        for _, name in ipairs(member.candidates) do
            if firstNames[name] == 1 then Append(name) end
        end
        if not member.who:find("-", 1, true) then Append(member.who .. "-" .. realm) end
        local seenBy
        if raid then
            seenBy = member.rosterName
        elseif ReadableName(member.short) then
            seenBy = ReadableName(member.server) and member.short .. "-" .. member.server or member.short
        end
        return table.concat(result, ","), ReadableName(seenBy) and seen[seenBy] == true
    end

    function GroupRoster()
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
                if ReadableName(short) and ReadableName(server) then nameList[4] = short .. "-" .. server end
                member.candidates = {}
                local counted = {}
                for k = 1, NAME_COUNT do
                    local num = nameList[k]
                    if ReadableName(num) and not counted[num] then
                        counted[num] = true
                        firstNames[num] = (firstNames[num] or 0) + 1
                        member.candidates[#member.candidates + 1] = num
                    end
                end
                entries[#entries + 1] = member
            end
        end
        for _, member in ipairs(entries) do
            member.names, member.targetable = ColumnNames(member, realm, firstNames, raid)
        end
        return entries
    end

    -- In a raid dungeon with Hide the Bench on, the groups past its usual size are left out.
    function ShownNow(roster)
        if not (Get("bench") and IsInRaid()) then return roster end
        local _, kind, _, _, maxPlayers = GetInstanceInfo()
        if kind ~= "raid" or not maxPlayers or maxPlayers <= 0 then return roster end
        local last = math.ceil(maxPlayers / 5)
        local isShown = {}
        for _, member in ipairs(roster) do
            if not member.subgroup or member.subgroup <= last then isShown[#isShown + 1] = member end
        end
        return isShown
    end

    function Grouped(who)
        for _, member in ipairs(GroupRoster()) do
            if member.who == who then return member end
        end
    end

    function AssignAllowed(unitToken)
        local lead, assist = UnitIsGroupLeader(unitToken), UnitIsGroupAssistant(unitToken)
        return not (Secret(lead) or Secret(assist)) and (lead or assist)
    end

    local TANK_STATE = { WARRIOR = true, DRUID = true, PALADIN = true }
    local WRONG_ROLE = {
        WARRIOR = { wisdom = true },
        ROGUE = { wisdom = true },
        MAGE = { might = true },
        WARLOCK = { might = true },
        PRIEST = { might = true },
    }
    local BLESSING_NONE = "none"

    local function TankUnit(unitToken)
        local role = UnitGroupRolesAssigned(unitToken)
        if not Secret(role) and role == "TANK" then return true end
        return GetPartyAssignment("MAINTANK", unitToken) and true or false
    end

    local function HasAssist(unitToken) return GetPartyAssignment("MAINASSIST", unitToken) and true or false end

    local function BlessingForRole(member)
        local tank, assist = Get("tank"), Get("assist")
        if not TANK_STATE[member.class] or (tank == BLESSING_NONE and assist == BLESSING_NONE) then return end
        local key = tank ~= BLESSING_NONE and TankUnit(member.unit) and tank
            or assist ~= BLESSING_NONE and HasAssist(member.unit) and assist
        return key and FROM_KEY[key] and OnLearned(FROM_KEY[key]) and key or nil
    end

    function AssignedTo(member)
        local storage = Keep()
        return storage.players[member.guid] or BlessingForRole(member) or storage.classes[member.class]
    end

    function MayCast(class, key)
        local no = Get("smart") and WRONG_ROLE[class]
        return not (no and no[key])
    end

    -- Whether an addon message's sender is this unit.
    function SenderUnit(sender, unitToken, unitGuid)
        if not (ReadableName(sender) and ReadableName(unitToken) and ReadableName(unitGuid)) then return false end
        local g = UnitGUID(unitToken)
        if not ReadableName(g) or g ~= unitGuid then return false end
        local first, second = UnitFullName(unitToken)
        if not first or Secret(first) or Secret(second) then return false end
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
    local BLESSING_SECONDS, CAST_GRACE = 3600, 5
    local HIDDEN_STATES = { pvp = true, arena = true }
    local seen, casts, sent = {}, {}, nil

    function AurasHidden()
        local _, kind = IsInInstance()
        return HIDDEN_STATES[kind] == true
    end

    function Recalled(unitToken, key)
        local unitGuid = UnitGUID(unitToken)
        local mine = unitGuid and not Secret(unitGuid) and seen[unitGuid]
        local ends = mine and mine[key]
        if not ends then return false end
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

    function DropIfDead(unitToken)
        if not next(seen) then return end
        local unitGuid = UnitGUID(unitToken)
        if not unitGuid or Secret(unitGuid) or not seen[unitGuid] then return end
        local dead = UnitIsDeadOrGhost(unitToken)
        if not Secret(dead) and dead then seen[unitGuid] = nil end
    end

    function OnCastSent(castGUID, spell) sent = { guid = castGUID, spell = spell, at = GetTime() } end

    function RecordCast(unitToken, spell)
        local cast = sent
        sent = nil
        if
            not (
                unitToken
                and spell
                and cast
                and cast.spell == spell
                and cast.at == GetTime()
                and AurasHidden()
            )
        then
            return
        end
        local key = SPELL_FAMILY[spell]
        if not key then return end
        local roster = GroupRoster()
        local target
        for _, member in ipairs(roster) do
            local same = UnitIsUnit(unitToken, member.unit)
            if not Secret(same) and same then
                target = member
                break
            end
        end
        if not target then return end
        local guids = {}
        for _, member in ipairs(roster) do
            if member.guid == target.guid or (GREATER_MAP[spell] and member.class == target.class) then
                guids[#guids + 1] = member.guid
            end
        end
        for ident, old in pairs(casts) do
            if GetTime() - old.at >= CAST_GRACE then casts[ident] = nil end
        end
        casts[cast.guid] = { key = key, guids = guids, at = GetTime() }
    end

    function OnCastDone(castGUID)
        local cast = casts[castGUID]
        if not cast then return end
        casts[castGUID] = nil
        if GetTime() - cast.at >= CAST_GRACE then return end
        local ends = GetTime() + (FROM_KEY[cast.key].blessing and BLESSING_SECONDS or math.huge)
        for _, unitGuid in ipairs(cast.guids) do
            seen[unitGuid] = seen[unitGuid] or {}
            seen[unitGuid][cast.key] = ends
        end
    end

    function DropCasts()
        sent = nil
        wipe(casts)
        wipe(seen)
    end
end

local CastingSpell, StartAuraNote, StopAuraNote, BlessState, WaitTime, UrgencySorter, ScanGroup, NeedsRecast
do
    -------------------------------------------------------------------------------
    --  Who has which blessing, and who a class button blesses next
    -------------------------------------------------------------------------------
    local EXPIRY_WARN, AURAS_MAX = 300, 40

    function CastingSpell(key, members)
        local record = FROM_KEY[key]
        local greater = C_Item.GetItemCount(ITEM_SYMBOL) > 0 and BestRank(record.greater)
        if greater then
            for _, member in ipairs(members) do
                if AssignedTo(member) ~= key then
                    greater = nil
                    break
                end
            end
        end
        return greater or BestRank(record.ranks)
    end

    local memoAt
    local memo, scratch = {}, {}
    function StartAuraNote()
        memoAt = GetTime()
        for _, s in pairs(memo) do
            s.stale = true
        end
    end
    function StopAuraNote() memoAt = nil end

    local function FoundUnit(val)
        if val == true then return true end
        return true, val - GetTime()
    end

    function BlessState(unitToken, key)
        if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
            if AurasHidden() then return Recalled(unitToken, key) end
            return nil
        end
        local s
        if memoAt and memoAt == GetTime() then
            s = memo[unitToken]
            if not s then
                s = {}
                memo[unitToken] = s
            end
            if s.stale then wipe(s) end
        else
            wipe(scratch)
            s = scratch
        end
        local val = s[key]
        if val then return FoundUnit(val) end
        if s.ended == "none" then return false end
        if s.ended then return nil end
        for index = s.next or 1, AURAS_MAX do
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
            local family = SPELL_FAMILY[ident]
            if family and s[family] == nil then
                local expires = aura.expirationTime
                s[family] = (Secret(expires) or not expires or expires == 0) and true or expires
            end
            if family and family == key then
                s.next = index + 1
                return FoundUnit(s[family])
            end
        end
        s.ended = "none"
        return false
    end

    local function WithinRange(member, spell)
        if member.guid == UnitGUID("player") then return true end
        local inRange = C_Spell.IsSpellInRange(spell, member.unit)
        if Secret(inRange) then return nil end
        return inRange
    end

    function WaitTime(members, spell)
        if not Get("wait") then return true end
        for _, member in ipairs(members) do
            if
                UnitIsConnected(member.unit)
                and not UnitIsDeadOrGhost(member.unit)
                and WithinRange(member, spell) == false
            then
                return false
            end
        end
        return true
    end

    function UrgencySorter(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.left < b.left
    end

    function ScanGroup(members)
        local cfg = {
            missing = 0,
            reachable = false,
            missingNear = 0,
            expiringNear = 0,
            classDue = 0,
            classMissing = 0,
            queue = {},
        }
        local rank, leftX
        local queue = cfg.queue
        local players = Keep().players
        local spells = {}
        for _, member in ipairs(members) do
            local key = AssignedTo(member)
            if key and spells[key] == nil then
                local cast = CastingSpell(key, members)
                if cast and GREATER_MAP[cast] and not WaitTime(members, cast) then
                    cast = BestRank(FROM_KEY[key].ranks)
                end
                spells[key] = cast or false
            end
            local spell = key and spells[key]
            if spell and UnitIsConnected(member.unit) and not UnitIsDeadOrGhost(member.unit) then
                local has, remaining = BlessState(member.unit, key)
                if has == false then
                    cfg.missing = cfg.missing + 1
                    cfg.shortest = 0
                elseif remaining and (not cfg.shortest or remaining < cfg.shortest) then
                    cfg.shortest = remaining
                end
                local range = UnitIsVisible(member.unit) and WithinRange(member, spell)
                if has ~= nil and range ~= false then
                    cfg.reachable = true
                    local region = not has and 0 or (remaining and remaining < EXPIRY_WARN and 1 or 2)
                    if range == true and region < 2 and member.targetable then
                        if region == 0 then
                            cfg.missingNear = cfg.missingNear + 1
                        else
                            cfg.expiringNear = cfg.expiringNear + 1
                        end
                        if not players[member.guid] then
                            cfg.classDue = cfg.classDue + 1
                            if region == 0 then cfg.classMissing = cfg.classMissing + 1 end
                        end
                    end
                    local l = remaining or math.huge
                    if member.targetable then
                        queue[#queue + 1] = { names = member.names, spell = spell, rank = region, left = l }
                        if not cfg.target or region < rank or (region == rank and l < leftX) then
                            cfg.target, cfg.spell, rank, leftX = member, spell, region, l
                        end
                    end
                end
            end
        end
        table.sort(queue, UrgencySorter)
        local due = 0
        for _, record in ipairs(queue) do
            if record.rank < 2 then due = due + 1 end
        end
        if GREATER_MAP[queue[1] and queue[1].spell] then due = math.min(due, 1) end
        local keep = Get("respect") and 0 or 1
        for index = #queue, math.max(due, keep) + 1, -1 do
            queue[index] = nil
        end
        if due == 0 and keep == 0 then cfg.target = nil end
        cfg.rank, cfg.left = rank, leftX
        return cfg
    end

    function NeedsRecast(member, key, spell)
        if
            not (
                spell
                and UnitIsConnected(member.unit)
                and not UnitIsDeadOrGhost(member.unit)
                and UnitIsVisible(member.unit)
                and WithinRange(member, spell) ~= false
            )
        then
            return
        end
        local has, remaining = BlessState(member.unit, key)
        if has == false then return 0, 0 end
        if has and remaining and remaining < EXPIRY_WARN then return 1, remaining end
    end
end

local STATUS_SPELLS, MyStatus
do
    -------------------------------------------------------------------------------
    --  Symbols of Kings, Lay on Hands and Divine Intervention, shared with the
    --  group's paladins
    -------------------------------------------------------------------------------
    local SPELL_LOH, SPELL_DI = { 633, 2800, 10310 }, { 19752 }
    STATUS_SPELLS = {}
    for _, ranks in ipairs({ SPELL_LOH, SPELL_DI }) do
        for _, ident in ipairs(ranks) do
            STATUS_SPELLS[ident] = true
        end
    end

    local function CooldownRemaining(ranks)
        local spell = BestRank(ranks)
        if not spell then return -1 end
        local details = C_Spell.GetSpellCooldown(spell)
        local start, duration = details and details.startTime, details and details.duration
        if not start or Secret(start) or Secret(duration) or duration <= 1.5 then return 0 end
        return math.max(0, math.floor(start + duration - GetTime()))
    end

    function MyStatus()
        return C_Item.GetItemCount(ITEM_SYMBOL),
            CooldownRemaining(SPELL_LOH),
            CooldownRemaining(SPELL_DI)
    end
end

local RefreshPage, QueryPP, OnChange
local MSG_PREFIX, Transmit, ChatTarget, AnnounceSoon, FromWhom, OnAddonMessage, TransmitPlan, SyncShortly, OutOfCombat
do
    -------------------------------------------------------------------------------
    --  Plans shared with the group's paladins (our message format)
    -------------------------------------------------------------------------------
    MSG_PREFIX = "CludesBless"
    local CODE_NONE = "-"
    local PLAYERS_PER_MESSAGE, PLAYER_CHOICES_MAX, SYMBOLS_MAX, BATCH_WAIT = 200, 40, 9999, 1
    local pending = {}
    local sentPlayers, broadcastAfterCombat, broadcastQueued, syncQueued

    local function WritePlan(classes, aura)
        local result = {}
        for index, class in ipairs(CLASS_LIST) do
            result[index] = classes[class] and FROM_KEY[classes[class]].code or CODE_NONE
        end
        result[#result + 1] = aura and FROM_KEY[aura].code or CODE_NONE
        return table.concat(result)
    end

    local function ReadPlan(textValue)
        if #textValue ~= #CLASS_LIST + 1 then return end
        local classes = {}
        for index, class in ipairs(CLASS_LIST) do
            local c = textValue:sub(index, index)
            if c ~= CODE_NONE then
                local record = FROM_CODE[c]
                if not (record and record.blessing) then return end
                classes[class] = record.key
            end
        end
        local c = textValue:sub(-1)
        if c == CODE_NONE then return classes, nil end
        local record = FROM_CODE[c]
        if record and not record.blessing then return classes, record.key end
    end

    local function CodesKnown()
        local codes = {}
        for _, record in ipairs(BLESSING_LIST) do
            if OnLearned(record) then codes[#codes + 1] = record.code end
        end
        for _, record in ipairs(AURA_LIST) do
            if OnLearned(record) then codes[#codes + 1] = record.code end
        end
        if Keep().free then codes[#codes + 1] = UNASSIGNED_FLAG end
        return table.concat(codes)
    end

    function ChatTarget()
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
    end

    function Transmit(message, key)
        if InCombatLockdown() then
            pending[key or message] = message
            return
        end
        local channel = ChatTarget()
        if channel then C_ChatInfo.SendAddonMessage(MSG_PREFIX, message, channel) end
    end

    local function TransmitPlayers()
        local players = Keep().players
        local parts, num, chunk = {}, 1, ""
        for _, member in ipairs(GroupRoster()) do
            local key = players[member.guid]
            if key then
                local part = member.guid .. "=" .. FROM_KEY[key].code
                if #chunk + #part > PLAYERS_PER_MESSAGE then
                    parts[#parts + 1] = chunk
                    chunk = ""
                end
                chunk = chunk == "" and part or chunk .. "," .. part
            end
        end
        parts[#parts + 1] = chunk
        if chunk == "" and #parts == 1 and not sentPlayers then return end
        sentPlayers = chunk ~= "" or #parts > 1
        for _, body in ipairs(parts) do
            Transmit("P|" .. num .. "|" .. body, "P|" .. num)
            num = num + 1
        end
    end

    local function StatusLine()
        local symbols, loh, di = MyStatus()
        return ("I|%d|%d|%d"):format(symbols, loh, di)
    end

    local function Announce()
        if not PaladinUnit() then return end
        if InCombatLockdown() then
            broadcastAfterCombat = true
            return
        end
        local storage = Keep()
        Transmit("F|" .. WritePlan(storage.classes, storage.aura) .. "|" .. CodesKnown())
        TransmitPlayers()
        Transmit(StatusLine(), "I")
    end

    function AnnounceSoon()
        if broadcastQueued then return end
        broadcastQueued = true
        C_Timer.After(BATCH_WAIT, function()
            broadcastQueued = false
            Announce()
        end)
    end

    local function CanPlan(from)
        return from and (AssignAllowed(from.unit) or (Keep().free and from.class == "PALADIN"))
    end

    local function AssignmentMade(from, name, target, plan)
        local classes, aura = ReadPlan(plan)
        if not (PaladinUnit() and classes and CanPlan(from) and target == UnitGUID("player")) then return end
        local storage = Keep()
        storage.classes = {}
        for class, key in pairs(classes) do
            if OnLearned(FROM_KEY[key]) then storage.classes[class] = key end
        end
        storage.aura = aura and OnLearned(FROM_KEY[aura]) and aura or nil
        Print(name .. " updated your blessings.")
        AnnounceSoon()
        OnChange()
    end

    local function StatusReceived(who, symbols, loh, di)
        local from = others[who]
        if not from then return end
        local nowTime = GetTime()
        local function ExpiresAt(leftX)
            leftX = tonumber(leftX)
            return leftX >= 0 and nowTime + leftX or nil
        end
        from.status = { symbols = math.min(tonumber(symbols), SYMBOLS_MAX), loh = ExpiresAt(loh), di = ExpiresAt(di) }
        RefreshPage()
    end

    local function PlayersReceived(who, part, entries)
        local from = others[who]
        if not from then return end
        if part == "1" then
            from.players, from.choices = {}, 0
        end
        for unitGuid, code in entries:gmatch("(Player%-[%w%-]+)=(%a)") do
            local record = FROM_CODE[code]
            local choices = from.choices or 0
            if record and record.blessing and (from.players[unitGuid] or choices < PLAYER_CHOICES_MAX) then
                if not from.players[unitGuid] then from.choices = choices + 1 end
                from.players[unitGuid] = record.key
            end
        end
        RefreshPage()
    end

    local function PlanReceived(from, body, known)
        if not (body and from.class == "PALADIN") then return end
        local classes, aura = ReadPlan(body)
        if not classes then return end
        local set, free = {}, nil
        for code in known:gmatch(".") do
            if FROM_CODE[code] then set[FROM_CODE[code].key] = true end
            if code == UNASSIGNED_FLAG then free = true end
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

    function FromWhom(sender)
        for _, member in ipairs(GroupRoster()) do
            if SenderUnit(sender, member.unit, member.guid) then return member end
        end
    end

    function OnAddonMessage(message, sender)
        if message == "R" then
            if not SenderUnit(sender, "player", UnitGUID("player")) then AnnounceSoon() end
            return
        end
        local from = FromWhom(sender)
        if not from or from.guid == UnitGUID("player") then return end
        local who = from.who
        local target, plan = message:match("^S|([^|]+)|(%S+)$")
        if target then return AssignmentMade(from, Ambiguate(sender, "none"), target, plan) end
        local symbols, loh, di = message:match("^I|(%d+)|(%-?%d+)|(%-?%d+)$")
        if symbols then return StatusReceived(who, symbols, loh, di) end
        local part, entries = message:match("^P|(%d+)|(.*)$")
        if part then return PlayersReceived(who, part, entries) end
        local body, known = message:match("^F|(%S+)|(%a*)$")
        PlanReceived(from, body, known)
    end

    function TransmitPlan(who, classes, aura)
        local member = Grouped(who)
        if not member then return end
        others[who].classes, others[who].aura = classes, aura
        Transmit("S|" .. member.guid .. "|" .. WritePlan(classes, aura), "S|" .. member.guid)
    end

    function SyncShortly()
        if syncQueued then return end
        syncQueued = true
        C_Timer.After(BATCH_WAIT, function()
            syncQueued = false
            for who in pairs(others) do
                if not Grouped(who) then others[who] = nil end
            end
            if PaladinUnit() or AssignAllowed("player") then
                Transmit("R")
                QueryPP()
            end
            AnnounceSoon()
            RefreshPage()
        end)
    end

    function OutOfCombat()
        if broadcastAfterCombat then
            broadcastAfterCombat = false
            AnnounceSoon()
        end
        for key, message in pairs(pending) do
            pending[key] = nil
            Transmit(message)
        end
        if PaladinUnit() or AssignAllowed("player") then QueryPP() end
    end

    do
    end

    -------------------------------------------------------------------------------
    --  PallyPower users' plans, read from its addon messages
    -------------------------------------------------------------------------------
    PPA_PREFIX = "PLPWR"
    local PPA_CHANGES = { ASSIGN = true, PASSIGN = true, MASSIGN = true, AASSIGN = true, CLEAR = true }
    local PPA_CLASSES =
        { "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN" }
    local PPA_BLESSINGS = { "wisdom", "might", "kings" }
    local PPA_AURAS = { "devotion", "retribution", "concentration", "shadow", "frost", "fire", "sanctity" }
    local PPA_MAX_CD = 7200
    asked = {}

    local function PPAPlan(who)
        local plan = others[who]
        if plan then return plan.pallyPower and plan or nil end
        plan = { classes = {}, known = {}, players = {}, choices = 0, pallyPower = true }
        others[who] = plan
        return plan
    end

    local function PPAKnown(plan, keyList, ranks)
        for index, key in ipairs(keyList) do
            local rank = ranks:sub(2 * index - 1, 2 * index - 1)
            plan.known[key] = rank ~= "" and rank ~= "n" or nil
        end
    end

    local function PPAPick(plan, keyList, index)
        local key = keyList[tonumber(index)]
        return key and plan.known[key] and key or nil
    end

    local function PPAClasses(plan, given)
        plan.classes = {}
        for index, class in ipairs(PPA_CLASSES) do
            plan.classes[class] = PPAPick(plan, PPA_BLESSINGS, given:sub(index, index))
        end
    end

    local function PPAEnds(leftX)
        leftX = tonumber(leftX)
        return leftX and leftX >= 0 and leftX <= PPA_MAX_CD and GetTime() + leftX or nil
    end

    local function PPATarget(name, from)
        local member = FromWhom(name)
        local plan = member and others[member.who]
        if plan and plan.pallyPower and (member.guid == from.guid or AssignAllowed(from.unit) or plan.free) then
            return plan
        end
    end

    local function PPAChange(message, from)
        if message == "CLEAR" or message == "CLEAR SKIP" then
            local lead = AssignAllowed(from.unit)
            for _, plan in pairs(others) do
                if plan.pallyPower and (lead or plan.free) then
                    plan.classes = {}
                    if message == "CLEAR" then plan.aura = nil end
                end
            end
            return
        end
        local name, class, index = message:match("^ASSIGN (.+) (%d+) (%d+)$")
        if name then
            local plan, colour = PPATarget(name, from), PPA_CLASSES[tonumber(class)]
            if plan and colour then plan.classes[colour] = PPAPick(plan, PPA_BLESSINGS, index) end
            return
        end
        local given
        name, given = message:match("^PASSIGN (.+)@([%dn]*)$")
        if name then
            local plan = PPATarget(name, from)
            if plan then PPAClasses(plan, given) end
            return
        end
        name, index = message:match("^MASSIGN (.+) (%d+)$")
        if name then
            local plan = PPATarget(name, from)
            if not plan then return end
            local key = PPAPick(plan, PPA_BLESSINGS, index)
            for _, colour in ipairs(PPA_CLASSES) do
                plan.classes[colour] = key
            end
            return
        end
        name, index = message:match("^AASSIGN (.+) (%d+)$")
        local plan = name and PPATarget(name, from)
        if plan then plan.aura = PPAPick(plan, PPA_AURAS, index) end
    end

    function FromPP(message, sender)
        local ranks, given = message:match("^SELF ([%xn]*)@([%dn]*)$")
        local auraRanks, aura = message:match("^ASELF ([%xn]*)@([%dn]*)$")
        local symbols = message:match("SYMCOUNT (%d+)")
        local change = PPA_CHANGES[message:match("^%u+")]
        if not (ranks or auraRanks or symbols or change) then return end
        local from = FromWhom(sender)
        if not from or from.guid == UnitGUID("player") then return end
        if change then
            PPAChange(message, from)
            return RefreshPage()
        end
        if from.class ~= "PALADIN" then return end
        local plan = ranks and PPAPlan(from.who) or others[from.who]
        if not (plan and plan.pallyPower) then return end
        if ranks then
            PPAKnown(plan, PPA_BLESSINGS, ranks)
            PPAClasses(plan, given)
        elseif auraRanks then
            PPAKnown(plan, PPA_AURAS, auraRanks)
            plan.aura = PPAPick(plan, PPA_AURAS, aura)
        else
            local loh, di = message:match("COOLDOWNS:[^:]*:([^:]*):[^:]*:([^:]*)$")
            plan.free = message:find("FREEASSIGN YES", 1, true) == 1 or nil
            plan.status =
                { symbols = math.min(tonumber(symbols), SYMBOLS_MAX), loh = PPAEnds(loh), di = PPAEnds(di) }
        end
        RefreshPage()
    end

    function QueryPP()
        local channel = ChatTarget()
        if not channel or InCombatLockdown() then return end
        local me, ask = UnitGUID("player"), false
        for _, member in ipairs(GroupRoster()) do
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
        if ask then C_ChatInfo.SendAddonMessage(PPA_PREFIX, "REQ", channel) end
    end
end

local PostReport, REPORT_TARGETS
do
    -------------------------------------------------------------------------------
    --  Report to chat
    -------------------------------------------------------------------------------
    local LINES_MAX = 240
    REPORT_TARGETS = {
        {
            key = "SELF",
            label = "Yourself",
            can = function() return true end,
        },
        {
            key = "SAY",
            label = "Say",
            can = function() return true end,
        },
        {
            key = "PARTY",
            label = "Party",
            can = function() return IsInGroup() end,
        },
        {
            key = "RAID",
            label = "Raid",
            can = function() return IsInRaid() end,
        },
        {
            key = "INSTANCE_CHAT",
            label = "Instance",
            can = function() return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end,
        },
        {
            key = "GUILD",
            label = "Guild",
            can = function() return IsInGuild() end,
        },
    }

    local function HasBlessing(plan)
        local byBlessing, sequence = {}, {}
        for _, class in ipairs(CLASS_LIST) do
            local key = plan.classes[class]
            if key then
                if not byBlessing[key] then
                    byBlessing[key] = {}
                    sequence[#sequence + 1] = key
                end
                table.insert(byBlessing[key], ClassLabel(class))
            end
        end
        local parts = {}
        for _, key in ipairs(sequence) do
            parts[#parts + 1] = NameOfSpell(key) .. " (" .. table.concat(byBlessing[key], ", ") .. ")"
        end
        if plan.aura then parts[#parts + 1] = NameOfSpell(plan.aura) end
        return #parts > 0 and table.concat(parts, ", ") or "Nothing"
    end

    local function SplitList(textValue, result)
        while #textValue > LINES_MAX do
            local comma = textValue:sub(1, LINES_MAX):match("^.*(), ")
            result[#result + 1] = textValue:sub(1, comma and comma - 1 or LINES_MAX)
            textValue = "  " .. textValue:sub(comma and comma + 2 or LINES_MAX + 1)
        end
        result[#result + 1] = textValue
    end

    local function ReportText()
        local plans = {}
        if PaladinUnit() then plans[1] = { who = OwnName(), plan = Keep() } end
        local nameList = {}
        for who in pairs(others) do
            nameList[#nameList + 1] = who
        end
        table.sort(nameList)
        for _, who in ipairs(nameList) do
            plans[#plans + 1] = { who = who, plan = others[who] }
        end
        if #plans == 0 then return end
        local lines = { "--- Paladin blessings ---" }
        for _, record in ipairs(plans) do
            SplitList(Ambiguate(record.who, "short") .. ": " .. HasBlessing(record.plan), lines)
        end
        lines[#lines + 1] = "--- End of blessings ---"
        return lines
    end

    function PostReport(channel)
        if InCombatLockdown() then return Print("Reports are sent outside combat.") end
        local lines = ReportText()
        if not lines then return Print("There are no paladins to report.") end
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

local PaladinList, AutoAssign, UsePlans, PresetList, PlanAllAllowed, StorePreset, UsePreset, ResetAll, AssignFor
do
    -------------------------------------------------------------------------------
    --  Auto-Assign and the saved preset
    -------------------------------------------------------------------------------
    local DESIRED_STATES = {
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
    local AURA_SEQUENCE = { "devotion", "retribution", "concentration", "fire", "frost", "shadow", "sanctity" }

    function PaladinList()
        local entries = {}
        if PaladinUnit() then
            local known = {}
            for _, record in ipairs(BLESSING_LIST) do
                if OnLearned(record) then known[record.key] = true end
            end
            for _, record in ipairs(AURA_LIST) do
                if OnLearned(record) then known[record.key] = true end
            end
            entries[1] = { who = OwnName(), known = known, you = true }
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
            if lhs.count ~= rhs.count then return lhs.count < rhs.count end
            return lhs.who < rhs.who
        end)
        return entries
    end

    local function Choose(paladins, wanted, give)
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

    local function Unclaimed(wanted, fixed, given)
        local result = {}
        for _, key in ipairs(wanted) do
            local taken = false
            for _, plan in ipairs(fixed) do
                if given(plan) == key then taken = true end
            end
            if not taken then result[#result + 1] = key end
        end
        return result
    end

    function AutoAssign()
        local paladins, fixed = {}, {}
        for _, p in ipairs(PaladinList()) do
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
        for _, class in ipairs(CLASS_LIST) do
            local wanted = Unclaimed(DESIRED_STATES[class], fixed, function(plan) return plan.classes[class] end)
            Choose(paladins, wanted, function(profile, key) plans[profile.who].classes[class] = key end)
        end
        local auras = Unclaimed(AURA_SEQUENCE, fixed, function(plan) return plan.aura end)
        Choose(paladins, auras, function(profile, key) plans[profile.who].aura = key end)
        return plans
    end

    function UsePlans(plans)
        local storage = Keep()
        for who, plan in pairs(plans) do
            if who == OwnName() then
                storage.classes = {}
                for class, key in pairs(plan.classes) do
                    storage.classes[class] = key
                end
                storage.aura = plan.aura
                AnnounceSoon()
            elseif others[who] and not others[who].pallyPower then
                TransmitPlan(who, plan.classes, plan.aura)
            end
        end
        OnChange()
    end

    function PresetList()
        local conf = F.Cfg()
        conf.preset = conf.preset or {}
        return conf.preset
    end

    function PlanAllAllowed()
        for _, plan in pairs(others) do
            if not plan.pallyPower then return AssignAllowed("player") end
        end
        return true
    end

    function StorePreset()
        local paladins = PaladinList()
        if #paladins == 0 then return false end
        local preset = {}
        for _, p in ipairs(paladins) do
            local plan = p.you and Keep() or others[p.who]
            local classes = {}
            for class, key in pairs(plan.classes) do
                classes[class] = key
            end
            preset[p.who] = { classes = classes, aura = plan.aura }
        end
        F.Cfg().preset = preset
        return true
    end

    function UsePreset()
        local plans = {}
        for _, p in ipairs(PaladinList()) do
            local saved = PresetList()[p.who]
            if saved and not p.fixed then
                local plan = { classes = {} }
                for class, key in pairs(saved.classes or {}) do
                    if p.known[key] then plan.classes[class] = key end
                end
                plan.aura = saved.aura and p.known[saved.aura] and saved.aura or nil
                plans[p.who] = plan
            end
        end
        UsePlans(plans)
        return next(plans) ~= nil
    end

    function ResetAll()
        local plans = {}
        for _, p in ipairs(PaladinList()) do
            plans[p.who] = { classes = {} }
        end
        if PaladinUnit() then Keep().players = {} end
        UsePlans(plans)
    end

    function AssignFor(who, colour, key)
        local plan = others[who]
        if not plan then return end
        if colour == AURA_COL then
            plan.aura = key
        else
            plan.classes[colour] = key
        end
        TransmitPlan(who, plan.classes, plan.aura)
    end
end

-------------------------------------------------------------------------------
--  Look
-------------------------------------------------------------------------------
local COLOR_RED = { r = 0.97, g = 0.27, b = 0.27 }
local COLOR_YELLOW = { r = 1, g = 0.85, b = 0.3 }
local COLOR_BLUE = { r = 0.35, g = 0.6, b = 1 }
local ICON_TRIM = 0.08
local LABEL_FONT, LABEL_DROP_Y, LABEL_PAD, LABEL_COL = 10, 2, 3, 46
local function Font() return CUI.GetFontPath("essentials") end

local Style = { rows = 1 }

local function StyleIcon(widget)
    widget.edge = widget:CreateTexture(nil, "BACKGROUND")
    widget.edge:SetAllPoints()
    widget.edge:SetColorTexture(0, 0, 0, 1)
    widget.icon = widget:CreateTexture(nil, "ARTWORK")
    widget.icon:SetPoint("TOPLEFT", 1, -1)
    widget.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    widget.icon:SetTexCoord(ICON_TRIM, 1 - ICON_TRIM, ICON_TRIM, 1 - ICON_TRIM)
    widget.mark = widget:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(widget.mark, 14, "essentials")
    widget.mark:SetPoint("CENTER")
    widget.mark:SetTextColor(COLOR_RED.r, COLOR_RED.g, COLOR_RED.b)
    widget.timer = widget:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(widget.timer, 10, "essentials")
    widget.timer:SetPoint("BOTTOM", 0, 1)
end

local function StyleRead()
    Style.size, Style.gap, Style.groupGap = Get("size"), Get("spacing"), Get("groupGap")
    Style.timerSize, Style.labels, Style.vertical = Get("timerSize"), Get("labels"), Get("vertical")
    Style.perRow, Style.rows = math.max(1, Get("perRow")), 1
    Style.border = Get("border")
end

local function LabelWidth()
    if not Style.labels then return 0 end
    if Style.vertical then return LABEL_PAD + LABEL_COL end
    return LABEL_DROP_Y + LABEL_FONT
end

local function ROW_SPACING_FOR() return Style.size + Style.gap + LabelWidth() end

local function StylePin(widget, barFrame, posX, posY)
    widget:ClearAllPoints()
    if Style.vertical then
        widget:SetPoint("TOPLEFT", barFrame, "TOPLEFT", posY or 0, -posX)
    else
        widget:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", posX, posY or 0)
    end
end

local function StylePlace(widget, barFrame, posX, posY)
    local size = Style.size
    widget:SetSize(size, size)
    CUI.Kit.Font(widget.timer, Style.timerSize, "essentials")
    if widget.watchText then CUI.Kit.Font(widget.watchText, Style.timerSize, "essentials") end
    widget.edge:SetShown(Style.border ~= "none")
    if widget.label then
        widget.label:SetShown(Style.labels)
        widget.label:ClearAllPoints()
        if Style.vertical then
            widget.label:SetPoint("LEFT", widget, "RIGHT", LABEL_PAD, 0)
            widget.label:SetWidth(Style.rows > 1 and LABEL_COL or 0)
        else
            widget.label:SetPoint("TOP", widget, "BOTTOM", 0, -LABEL_DROP_Y)
            widget.label:SetWidth(size + Style.gap)
        end
    end
    StylePin(widget, barFrame, posX, posY)
    widget:Show()
    return posX + size + Style.gap
end

local function MinutesText(seconds)
    if not (seconds and seconds > 0 and Get("timers")) then return "" end
    return math.ceil(seconds / 60) .. "m"
end

local function StyleClass(cell, colour, reachable, missing, shortest)
    local status = Style.border == "status"
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
    cell.timer:SetText(MinutesText(shortest))
end

local function StyleSelf(widget, missing, remaining)
    widget.icon:SetVertexColor(missing and COLOR_RED.r or 1, missing and COLOR_RED.g or 1, missing and COLOR_RED.b or 1)
    widget.mark:SetText(missing and "!" or "")
    widget.timer:SetText(MinutesText(remaining))
end

local function StyleState(widget, key, has, remaining)
    local missing = key ~= nil and (widget.watch ~= nil or has == false)
    StyleSelf(widget, missing, not widget.watch and remaining)
end

local function StyleFit(widget, posX)
    local across = Style.size + (Style.rows - 1) * ROW_SPACING_FOR()
    local along = math.max(posX - Style.gap, Style.size)
    if Style.vertical then
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

local function Monitor(widget)
    if watchUnavailable then return end
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
                iconTex:SetTexCoord(ICON_TRIM, 1 - ICON_TRIM, ICON_TRIM, 1 - ICON_TRIM)
                btnFrame:SetIcon(iconTex)
                local textValue = btnFrame:CreateFontString(nil, "OVERLAY")
                CUI.Kit.Font(textValue, Get("timerSize"), "essentials")
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

local function WatchUnits(widget, unitToken, key)
    local c = widget.watch
    if not c or (widget.watchUnit == unitToken and widget.watchKey == key) then return end
    widget.watchUnit, widget.watchKey = unitToken, key
    c:SetUnit(unitToken or "none")
    c:SetAuraSlotCandidateFilters("buff", { includeSpellIDs = key and SPELL_IDS[key] or {} })
    c:SetEnabled(unitToken ~= nil and key ~= nil)
end

-------------------------------------------------------------------------------
--  A secure button that follows one named player through raid reordering,
--  even in combat
-------------------------------------------------------------------------------
local function TargetFor(hostFrame, name)
    local header = CreateFrame("Frame", name, hostFrame, "SecureGroupHeaderTemplate")
    header:SetAttribute("template", "CludesUIBlessButtonTemplate")
    header:SetAttribute("showPlayer", true)
    header:SetAttribute("showParty", true)
    header:SetAttribute("showRaid", true)
    header:SetAttribute("showSolo", true)
    header:SetAttribute("nameList", NO_ONE)
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

local function AssignNames(header, nameList)
    if header:GetAttribute("nameList") ~= nameList then header:SetAttribute("nameList", nameList) end
end

local function TargetSize(header, btnFrame, size)
    header:SetAttribute("minWidth", size)
    header:SetAttribute("minHeight", size)
    btnFrame:SetSize(size, size)
end

-------------------------------------------------------------------------------
--  Menus
-------------------------------------------------------------------------------
local ShowWindow, PlayersOf

local function AssignOwn(colour, key)
    local storage = Keep()
    if colour == AURA_COL then
        storage.aura = key
    else
        storage.classes[colour] = key
    end
    AnnounceSoon()
    OnChange()
end

local function ShowMenuFor(ownerFrame, title, entries, current, choose, noneText, can)
    can = can or OnLearned
    CUI.Kit.ContextMenu(ownerFrame, function(_, root)
        root:CreateTitle(title)
        for _, record in ipairs(entries) do
            if can(record) then
                root:CreateRadio(
                    NameOfSpell(record.key),
                    function() return current() == record.key end,
                    function() choose(record.key) end
                )
            end
        end
        root:CreateRadio(noneText, function() return current() == nil end, function() choose(nil) end)
    end)
end

local function UseSeal(key)
    Keep().seal = key
    OnChange()
end

local function ShowSealMenu(ownerFrame)
    ShowMenuFor(ownerFrame, "Seal", SEAL_LIST, function() return Keep().seal end, UseSeal, "Default")
end

local function ShowAuraMenu(ownerFrame)
    ShowMenuFor(
        ownerFrame,
        "Aura",
        AURA_LIST,
        function() return Keep().aura end,
        function(key) AssignOwn(AURA_COL, key) end,
        "Default"
    )
end

local function MyBlessings(class)
    local players, guids = Keep().players, {}
    for _, member in ipairs(GroupRoster()) do
        if member.class == class and players[member.guid] then guids[#guids + 1] = member.guid end
    end
    return guids
end

local function ShowClassMenu(ownerFrame, class)
    CUI.Kit.ContextMenu(ownerFrame, function(_, root)
        root:CreateTitle(ClassLabel(class))
        for _, record in ipairs(BLESSING_LIST) do
            if OnLearned(record) and (Keep().classes[class] == record.key or MayCast(class, record.key)) then
                root:CreateRadio(
                    NameOfSpell(record.key),
                    function() return Keep().classes[class] == record.key end,
                    function() AssignOwn(class, record.key) end
                )
            end
        end
        root:CreateRadio(
            "None",
            function() return Keep().classes[class] == nil end,
            function() AssignOwn(class, nil) end
        )
        local own = MyBlessings(class)
        if #own > 0 then
            root:CreateDivider()
            root:CreateTitle(
                #own == 1 and "1 player has their own blessing"
                    or ("%d players have their own blessing"):format(#own)
            )
            root:CreateButton("Give them the class blessing", function()
                local players = Keep().players
                for _, unitGuid in ipairs(own) do
                    players[unitGuid] = nil
                end
                AnnounceSoon()
                OnChange()
            end)
        end
        root:CreateDivider()
        if Get("playerList") then
            root:CreateCheckbox(
                "Players",
                function() return PlayersOf.Showing() == class end,
                function() PlayersOf.Toggle(class) end
            )
        end
        root:CreateButton("Assignments", function() ShowWindow() end)
    end)
end

local function ShowTip(widget, title, body)
    widget:HookScript("OnEnter", function(self)
        if not Get("tooltips") then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        local textValue = type(body) == "function" and body() or body
        local ar, ag, ab = CUI.Kit.Accent()
        if textValue and textValue ~= "" then GameTooltip:AddLine(textValue, ar, ag, ab, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local Update
do
    -------------------------------------------------------------------------------
    --  Player list: a class's players above the bar, to bless one person or give
    --  them their own blessing
    -------------------------------------------------------------------------------
    local flyout, rowList, flyoutClass
    local listMembers = {}
    PlayersOf = {}

    local function ShowPlayerMenu(ownerFrame, member)
        local storage = Keep()
        local function Able(record)
            return OnLearned(record)
                and (storage.players[member.guid] == record.key or MayCast(member.class, record.key))
        end
        ShowMenuFor(
            ownerFrame,
            Ambiguate(member.who, "short"),
            BLESSING_LIST,
            function() return storage.players[member.guid] end,
            function(key)
                storage.players[member.guid] = key
                AnnounceSoon()
                OnChange()
            end,
            "Class default",
            Able
        )
    end

    local function MakeRow(index)
        local row = CreateFrame("Frame", nil, flyout)
        row:SetSize(230, 30)
        row.name = row:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(row.name, 12, "essentials")
        row.name:SetPoint("TOPLEFT", 4, -2)
        row.note = row:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(row.note, 10, "essentials")
        row.note:SetTextColor(0.6, 0.65, 0.7)
        row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
        row.slot = CreateFrame("Frame", nil, row)
        row.slot:SetSize(26, 26)
        row.slot:SetPoint("RIGHT", -2, 0)
        StyleIcon(row.slot)
        row.header, row.cast = TargetFor(row.slot, "CludesUIBlessRow" .. index)
        TargetSize(row.header, row.cast, 26)
        row.cast:SetAttribute("ctrl-type1", "maintank")
        row.cast:SetAttribute("ctrl-action1", "toggle")
        row.cast:SetScript("PostClick", function(self, btnFrame, down)
            if btnFrame == "RightButton" and not down and row.member then ShowPlayerMenu(self, row.member) end
            if btnFrame == "LeftButton" then
                RecordCast(self:GetAttribute("unit"), self:GetAttribute("spell1"))
            end
        end)
        ShowTip(
            row.cast,
            "Bless",
            "Left-click: cast this player's blessing.\nRight-click: give them their own blessing, or back to the class default.\nCtrl-click: toggle Main Tank in a raid."
        )
        Monitor(row.slot)
        row.cast:HookScript("OnAttributeChanged", function(_, name, value)
            if name == "unit" then WatchUnits(row.slot, value, row.slot.watchKey) end
        end)
        return row
    end

    local function DrawRow(row, member, storage)
        row.member = member
        local color = RAID_CLASS_COLORS[member.class]
        row.name:SetText(Ambiguate(member.who, "short"))
        row.name:SetTextColor(color.r, color.g, color.b)
        local own = storage.players[member.guid]
        local key = AssignedTo(member)
        row.note:SetText(own and NameOfSpell(own) or "Class default")
        row.slot.icon:SetTexture(key and IconOfSpell(key) or ASK_CODE)
        AssignNames(row.header, member.names)
        row.cast:SetAttribute("spell1", key and BestRank(FROM_KEY[key].ranks))
        WatchUnits(row.slot, member.unit, key)
        local has, remaining
        if key then
            has, remaining = BlessState(member.unit, key)
        end
        StyleState(row.slot, key, has, remaining)
    end

    function PlayersOf.Showing() return flyoutClass end

    function PlayersOf.Build(barFrame)
        flyout = CreateFrame("Frame", nil, barFrame)
        flyout:SetPoint("BOTTOMLEFT", barFrame, "TOPLEFT", 0, 18)
        CUI.Kit.Panel(flyout, 0.9)
        flyout.title = flyout:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(flyout.title, 12, "essentials")
        CUI.Kit.AccentText(flyout.title)
        flyout.title:SetPoint("TOPLEFT", 8, -6)
        local close = CUI.Kit.Glyph(flyout, "x", function() flyout:Hide() end, nil, "essentials")
        close:SetSize(22, 22)
        close:SetPoint("TOPRIGHT", -4, -4)
        close:SetScript("OnClick", function() PlayersOf.Toggle(flyoutClass) end)
        rowList = {}
        flyout:Hide()
    end

    function PlayersOf.Arrange(roster)
        wipe(listMembers)
        for _, member in ipairs(roster) do
            if member.class == flyoutClass then listMembers[#listMembers + 1] = member end
        end
        if #listMembers == 0 or not Get("playerList") then flyoutClass = nil end
        if not flyoutClass then
            flyout:Hide()
            return
        end
        local storage = Keep()
        flyout:Show()
        for index, member in ipairs(listMembers) do
            local row = rowList[index] or MakeRow(index)
            rowList[index] = row
            DrawRow(row, member, storage)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 6, -26 - (index - 1) * 32)
            row:Show()
        end
        for index = #listMembers + 1, #rowList do
            AssignNames(rowList[index].header, NO_ONE)
            WatchUnits(rowList[index].slot, nil, nil)
            rowList[index]:Hide()
        end
        flyout.title:SetText(ClassLabel(flyoutClass))
        flyout:SetSize(242, 30 + #listMembers * 32)
    end

    function PlayersOf.Toggle(class)
        if InCombatLockdown() then
            Print("The player list opens after combat.")
            return
        end
        flyoutClass = flyoutClass ~= class and class or nil
        Update()
    end

    do
    end

    -------------------------------------------------------------------------------
    --  Key bindings: Next Blessing and Next Greater Blessing step through who
    --  needs one, most urgent first
    -------------------------------------------------------------------------------
    local KEY_SPACING = [[
    local i, n = self:GetAttribute("step") or 1, self:GetAttribute("count") or 0
    if i > n then return false end
    self:SetAttribute("unit", self:GetAttribute("unit" .. i))
    self:SetAttribute("spell", self:GetAttribute("spell" .. i))
    self:SetAttribute("step", i + 1)
]]

    local keyNext, keyGreater
    K = {}

    local function MakeKeyButton(name, handler)
        local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyDown")
        button:SetAttribute("useOnKeyDown", true)
        button:SetAttribute("type", "spell")
        button:SetAttribute("count", 0)
        SecureHandlerWrapScript(button, "OnClick", handler, KEY_SPACING)
        button:SetScript(
            "PostClick",
            function(self) RecordCast(self:GetAttribute("unit"), self:GetAttribute("spell")) end
        )
        return button
    end

    local function QueueCasts(button, entries, kind)
        kind = kind or ""
        table.sort(entries, UrgencySorter)
        for index, record in ipairs(entries) do
            button:SetAttribute("unit" .. kind .. index, record.unit)
            button:SetAttribute("spell" .. kind .. index, record.spell)
        end
        button:SetAttribute("count" .. kind, #entries)
        button:SetAttribute("step" .. kind, 1)
    end

    local function SingleBlessings(members, single, shared)
        for _, member in ipairs(members) do
            local key = AssignedTo(member)
            if key ~= shared then shared = nil end
            local spell = key and BestRank(FROM_KEY[key].ranks)
            local rank, leftX = NeedsRecast(member, key, spell)
            if rank then
                single[#single + 1] = { unit = member.unit, spell = spell, rank = rank, left = leftX }
            end
        end
        return shared
    end

    local function NextGreater(members, shared, symbols)
        local spell = shared and symbols and BestRank(FROM_KEY[shared].greater)
        if spell and not WaitTime(members, spell) then spell = nil end
        local best
        for _, member in ipairs(spell and members or {}) do
            local rank, leftX = NeedsRecast(member, shared, spell)
            if rank and (not best or UrgencySorter({ rank = rank, left = leftX }, best)) then
                best = { unit = member.unit, spell = spell, rank = rank, left = leftX }
            end
        end
        return best
    end

    function K.Build(handler)
        keyNext = MakeKeyButton("CludesUIBlessNext", handler)
        keyGreater = MakeKeyButton("CludesUIBlessNextGreater", handler)
    end

    function K.Peek()
        if not keyNext then return end
        return keyNext:GetAttribute("spell1") or keyGreater:GetAttribute("spell1"),
            keyNext:GetAttribute("count") or 0
    end

    function K.Clear()
        if keyNext then keyNext:SetAttribute("count", 0) end
        if keyGreater then keyGreater:SetAttribute("count", 0) end
        if keyAuto then
            keyAuto:SetAttribute("countN", 0)
            keyAuto:SetAttribute("countG", 0)
        end
    end

    function K.Fill(byClass)
        local single, greater = {}, {}
        local symbols = C_Item.GetItemCount(ITEM_SYMBOL) > 0
        for _, class in ipairs(CLASS_LIST) do
            local members = byClass[class]
            if members then
                local shared = SingleBlessings(members, single, Keep().classes[class])
                greater[#greater + 1] = NextGreater(members, shared, symbols)
            end
        end
        QueueCasts(keyNext, single)
        QueueCasts(keyGreater, greater)
        if keyAuto then
            QueueCasts(keyAuto, single, "N")
            QueueCasts(keyAuto, greater, "G")
        end
    end
end

-------------------------------------------------------------------------------
--  The Blessing Bar
-------------------------------------------------------------------------------
local CLASS_SPACING = [[
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

local AUTO_SPACING = [[
    local left = self:GetAttribute("leftKind") or "N"
    local kind = button == "RightButton" and (left == "N" and "G" or "N") or left
    local i, n = self:GetAttribute("step" .. kind) or 1, self:GetAttribute("count" .. kind) or 0
    if i > n then return false end
    self:SetAttribute("unit", self:GetAttribute("unit" .. kind .. i))
    self:SetAttribute("spell", self:GetAttribute("spell" .. kind .. i))
    self:SetAttribute("step" .. kind, i + 1)
]]

local GROUP_TARGETS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
local RESCAN_WAIT, LAND_GRACE, TICK_SECONDS = 1, 1, 3
local barFrame, cells, auraButton, furyButton, sealButton, autoButton, secureHandler
local dirty, ticker, buildAfterCombat
local refreshQueued, landing, landingQueued, sentSymbols
local events = CreateFrame("Frame")
local Apply

local function ScanQueue(cell, queue)
    local parts = {}
    for index, record in ipairs(queue) do
        parts[index] = record.names .. "=" .. record.spell
    end
    local signature = table.concat(parts, ";")
    if signature == cell.signature then return end
    cell.signature = signature
    for index, record in ipairs(queue) do
        cell.cast:SetAttribute("queueNames" .. index, record.names)
        cell.cast:SetAttribute("queueSpell" .. index, record.spell)
    end
    cell.cast:SetAttribute("count", #queue)
end

local function DrawCell(cell, cfg, key)
    local queue = cfg.queue
    local isShown = cfg.spell or (key and CastingSpell(key, cell.members))
    cell.icon:SetTexture(isShown and C_Spell.GetSpellTexture(isShown) or ASK_CODE)
    ScanQueue(cell, queue)
    cell.cast:SetAttribute("step", 1)
    AssignNames(cell.header, queue[1] and queue[1].names or NO_ONE)
    cell.target, cell.queued = cfg.target, #queue
    local color = cfg.classMissing > 0 and COLOR_RED
        or cfg.classDue > 0 and COLOR_YELLOW
        or cfg.missingNear + cfg.expiringNear > 0 and COLOR_BLUE
        or nil
    StyleClass(cell, color, cfg.reachable, cfg.missing, cfg.shortest)
end

local function ArmCell(cell) DrawCell(cell, ScanGroup(cell.members), Keep().classes[cell.class]) end

local function ShowCellTip(cell)
    local target = cell.target and Ambiguate(cell.target.who, "short")
    return (target and ("Left-click: bless %s.\n"):format(target) or "")
        .. ((cell.queued or 0) > 1 and "In combat each click blesses the next who needed it.\n" or "")
        .. "Right-click: choose the blessing, the player list or assignments."
end

local function AurasSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
end

local function MakeCell(class)
    local cell = CreateFrame("Frame", nil, barFrame)
    cell.class = class
    StyleIcon(cell)
    cell.label = cell:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(cell.label, LABEL_FONT, "essentials")
    cell.label:SetWordWrap(false)
    cell.label:SetText(ClassLabel(class))
    local color = RAID_CLASS_COLORS[class]
    if color then cell.label:SetTextColor(color.r, color.g, color.b) end
    cell.header, cell.cast = TargetFor(cell, "CludesUIBless" .. class)
    cell.cast:RegisterForClicks("AnyUp")
    cell.cast:SetAttribute("useOnKeyDown", false)
    cell.cast:SetAttribute("count", 0)
    cell.cast:SetScript("PreClick", function(_, btnFrame)
        if
            btnFrame == "LeftButton"
            and not InCombatLockdown()
            and not (AurasSecret() and not AurasHidden())
        then
            ArmCell(cell)
        end
    end)
    SecureHandlerWrapScript(cell.cast, "OnClick", secureHandler, CLASS_SPACING)
    cell.cast:SetScript("PostClick", function(self, btnFrame, down)
        if btnFrame == "RightButton" and not down then ShowClassMenu(self, class) end
        if btnFrame == "LeftButton" then RecordCast(self:GetAttribute("unit"), self:GetAttribute("spell1")) end
    end)
    ShowTip(cell.cast, ClassLabel(class), function() return ShowCellTip(cell) end)
    return cell
end

local function ActiveAura()
    local key = Keep().aura
    if key and OnLearned(FROM_KEY[key]) then return key end
    for _, record in ipairs(AURA_LIST) do
        if OnLearned(record) then return record.key end
    end
end

local function ActiveSeal()
    local key = Keep().seal
    if key and OnLearned(FROM_KEY[key]) then return key end
    for _, record in ipairs(SEAL_LIST) do
        if OnLearned(record) then return record.key end
    end
end

local function Rotate(entries, current, choose, delta)
    if InCombatLockdown() then return end
    local known = {}
    for _, record in ipairs(entries) do
        if OnLearned(record) then known[#known + 1] = record.key end
    end
    if #known < 2 then return end
    local at = 1
    for index, key in ipairs(known) do
        if key == current() then at = index end
    end
    choose(known[(at - 1 + (delta > 0 and 1 or -1)) % #known + 1])
end

local function MakeBarButton(name)
    local button = CreateFrame("Button", name, barFrame, "SecureActionButtonTemplate")
    StyleIcon(button)
    return button
end

local function MakeSelfButton(name)
    local button = MakeBarButton(name)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("type1", "spell")
    button:SetAttribute("unit1", "player")
    Monitor(button)
    return button
end

local function MakeAutoButton(name)
    local button = MakeBarButton(name)
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type1", "spell")
    button:SetAttribute("type2", "spell")
    button:SetAttribute("countN", 0)
    button:SetAttribute("countG", 0)
    SecureHandlerWrapScript(button, "OnClick", secureHandler, AUTO_SPACING)
    button:SetScript(
        "PostClick",
        function(self) RecordCast(self:GetAttribute("unit"), self:GetAttribute("spell")) end
    )
    keyAuto = button
    return button
end

local function ArmSeal(button, key)
    local ident = FROM_KEY[key].ranks[1]
    button:SetAttribute("spell1", C_Spell.GetSpellName(ident))
    button.icon:SetTexture(C_Spell.GetSpellTexture(ident))
    WatchUnits(button, "player", key)
    StyleSelf(button, false)
end

local function DrawAuto()
    if not autoButton:IsShown() then return end
    local spell, due = K.Peek()
    autoButton.icon:SetTexture(spell and C_Spell.GetSpellTexture(spell) or ASK_CODE)
    autoButton.icon:SetDesaturated(due == 0)
    autoButton.mark:SetText(due > 0 and due or "")
end

local function ArmSelf(button, key)
    local spell = BestRank(FROM_KEY[key].ranks)
    button:SetAttribute("spell1", spell)
    button.icon:SetTexture(C_Spell.GetSpellTexture(spell))
    WatchUnits(button, "player", key)
    StyleState(button, key, BlessState("player", key))
end

local function LayoutSelf(posX)
    local aura = Get("showAura") and ActiveAura()
    if aura then
        ArmSelf(auraButton, aura)
        posX = StylePlace(auraButton, barFrame, posX)
    else
        auraButton:Hide()
    end
    if Get("showFury") and OnLearned(SPELL_FURY) then
        ArmSelf(furyButton, "fury")
        posX = StylePlace(furyButton, barFrame, posX)
    else
        furyButton:Hide()
    end
    local seal = Get("showSeal") and ActiveSeal()
    if seal then
        ArmSeal(sealButton, seal)
        posX = StylePlace(sealButton, barFrame, posX)
    else
        sealButton:Hide()
    end
    if Get("showAuto") then
        autoButton:SetAttribute("leftKind", Get("autoGreater") and "G" or "N")
        posX = StylePlace(autoButton, barFrame, posX)
    else
        autoButton:Hide()
    end
    if posX > 0 then return posX + Style.groupGap end
    return posX
end

local function ClassSorter(roster)
    local byClass = {}
    for _, member in ipairs(roster) do
        byClass[member.class] = byClass[member.class] or {}
        table.insert(byClass[member.class], member)
    end
    return byClass
end

local function ClearCell(cell)
    AssignNames(cell.header, NO_ONE)
    cell:Hide()
end

local function LayoutCells(byClass, posX)
    local total = 0
    for _, class in ipairs(CLASS_LIST) do
        if byClass[class] then total = total + 1 end
    end
    Style.rows = math.max(1, math.ceil(total / Style.perRow))
    local done = posX + math.min(total, Style.perRow) * (Style.size + Style.gap)
    local index = 0
    for _, class in ipairs(CLASS_LIST) do
        local members = byClass[class]
        local cell = cells[class]
        if members then
            cell = cell or MakeCell(class)
            cells[class] = cell
            cell.members = members
            TargetSize(cell.header, cell.cast, Style.size)
            StylePlace(
                cell,
                barFrame,
                posX + index % Style.perRow * (Style.size + Style.gap),
                math.floor(index / Style.perRow) * ROW_SPACING_FOR()
            )
            index = index + 1
            ArmCell(cell)
        elseif cell then
            ClearCell(cell)
        end
    end
    return done
end

local function Desired()
    if IsInRaid() then return true end
    if IsInGroup() then return Get("inParty") end
    return Get("solo")
end

function Update()
    if not barFrame then return end
    if InCombatLockdown() or (AurasSecret() and not AurasHidden()) then
        dirty = true
        return
    end
    dirty = false
    if not (On() and PaladinUnit() and (Desired() or CUI._unlockActive)) then
        barFrame:Hide()
        K.Clear()
        return
    end
    barFrame:Show()
    StartAuraNote()
    StyleRead()
    local posX = LayoutSelf(0)
    local roster = ShownNow(GroupRoster())
    local byClass = ClassSorter(roster)
    if Get("showClasses") then
        posX = LayoutCells(byClass, posX)
    else
        for _, cell in pairs(cells) do
            ClearCell(cell)
        end
    end
    PlayersOf.Arrange(roster)
    K.Fill(byClass)
    DrawAuto()
    StopAuraNote()
    StyleFit(barFrame, posX)
    barFrame:SetShown(posX > 0 or CUI._unlockActive)
end

function OnChange()
    if Update then Update() end
    RefreshPage()
end

local function SelfClicked(self, btnFrame)
    if btnFrame == "LeftButton" then RecordCast(self:GetAttribute("unit1"), self:GetAttribute("spell1")) end
end

local function MakeBar()
    barFrame = CreateFrame("Frame", "CludesUIBlessingBar", UIParent)
    barFrame:SetClampedToScreen(true)
    barFrame:SetSize(Get("size"), Get("size"))
    cells = {}
    secureHandler = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    auraButton = MakeSelfButton("CludesUIBlessAura")
    auraButton:SetScript("PostClick", function(self, btnFrame, down)
        SelfClicked(self, btnFrame)
        if btnFrame == "RightButton" and not down then ShowAuraMenu(self) end
    end)
    ShowTip(
        auraButton,
        "Aura",
        "Left-click: cast your aura.\nRight-click: choose it. Wheel: cycle through your auras."
    )
    auraButton:EnableMouseWheel(true)
    auraButton:SetScript("OnMouseWheel", function(_, delta)
        Rotate(AURA_LIST, ActiveAura, function(key) AssignOwn(AURA_COL, key) end, delta)
    end)
    furyButton = MakeSelfButton("CludesUIBlessFury")
    furyButton:SetScript("PostClick", SelfClicked)
    ShowTip(
        furyButton,
        C_Spell.GetSpellName(SPELL_FURY.ranks[1]) or "Righteous Fury",
        "Left-click: cast it on yourself."
    )
    sealButton = MakeSelfButton("CludesUIBlessSeal")
    sealButton:SetScript("PostClick", function(self, btnFrame, down)
        if btnFrame == "RightButton" and not down then ShowSealMenu(self) end
    end)
    ShowTip(
        sealButton,
        "Seal",
        "Left-click: cast your seal.\nRight-click: choose it. Wheel: cycle through your seals."
    )
    sealButton:EnableMouseWheel(true)
    sealButton:SetScript("OnMouseWheel", function(_, delta) Rotate(SEAL_LIST, ActiveSeal, UseSeal, delta) end)
    K.Build(secureHandler)
    autoButton = MakeAutoButton("CludesUIBlessAuto")
    ShowTip(
        autoButton,
        "Auto Buff",
        "Left-click: the next blessing. Right-click: the next Greater Blessing. Each goes to whoever needs it most."
    )
    PlayersOf.Build(barFrame)
    if not CUI._unlockActive then F.Place(barFrame) end
end

local function UpdateSoon()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(RESCAN_WAIT, function()
        refreshQueued = false
        Update()
    end)
end

local function UpdateLanded()
    if landingQueued then return end
    landingQueued = true
    C_Timer.After(0, function()
        landingQueued = false
        Update()
    end)
end

local function AuraChanged(unitToken)
    local fresh = landing and GetTime() - landing < LAND_GRACE
    if refreshQueued and not fresh then return end
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
            UpdateLanded()
        else
            UpdateSoon()
        end
    end
end

events:SetScript("OnEvent", function(_, evt, ...)
    if evt == "CHAT_MSG_ADDON" then
        local prefixText, message, channel, sender = ...
        if Secret(prefixText) or Secret(message) or Secret(channel) or Secret(sender) then return end
        if prefixText == MSG_PREFIX and GROUP_TARGETS[channel] then
            OnAddonMessage(message, sender)
        elseif prefixText == PPA_PREFIX and (GROUP_TARGETS[channel] or channel == "WHISPER") then
            FromPP(message, sender)
        end
    elseif evt == "GROUP_ROSTER_UPDATE" or evt == "PLAYER_ENTERING_WORLD" then
        if evt == "PLAYER_ENTERING_WORLD" then
            if AurasHidden() and PaladinUnit() then
                events:RegisterEvent("UNIT_HEALTH")
            else
                events:UnregisterEvent("UNIT_HEALTH")
                DropCasts()
            end
        end
        SyncShortly()
        UpdateSoon()
    elseif evt == "PARTY_LEADER_CHANGED" then
        RefreshPage()
    elseif evt == "PLAYER_ROLES_ASSIGNED" then
        UpdateSoon()
    elseif evt == "PLAYER_REGEN_ENABLED" then
        if buildAfterCombat then
            buildAfterCombat = false
            Apply()
        elseif dirty then
            Update()
        end
        OutOfCombat()
    elseif evt == "SPELLS_CHANGED" then
        AnnounceSoon()
        UpdateSoon()
    elseif evt == "UNIT_SPELLCAST_SENT" then
        local _, _, castGUID, spellID = ...
        if Secret(castGUID) or Secret(spellID) or not SPELL_FAMILY[spellID] then return end
        OnCastSent(castGUID, spellID)
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castGUID, spellID = ...
        if Secret(spellID) then return end
        if STATUS_SPELLS[spellID] then AnnounceSoon() end
        if Secret(castGUID) or not SPELL_FAMILY[spellID] then return end
        OnCastDone(castGUID)
        if not InCombatLockdown() then landing = GetTime() end
    elseif evt == "UNIT_HEALTH" then
        DropIfDead(...)
    elseif evt == "UNIT_AURA" then
        AuraChanged(...)
    end
end)

local function Ticked()
    if not (barFrame and barFrame:IsShown() and not InCombatLockdown()) then return end
    local symbols = C_Item.GetItemCount(ITEM_SYMBOL)
    if symbols ~= sentSymbols then
        sentSymbols = symbols
        AnnounceSoon()
    end
    UpdateSoon()
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
    C_ChatInfo.RegisterAddonMessagePrefix(MSG_PREFIX)
    C_ChatInfo.RegisterAddonMessagePrefix(PPA_PREFIX)
    for _, event in ipairs({
        "CHAT_MSG_ADDON",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD",
        "PARTY_LEADER_CHANGED",
        "PLAYER_REGEN_ENABLED",
    }) do
        events:RegisterEvent(event)
    end
    if not PaladinUnit() then return end
    for _, event in ipairs({ "UNIT_AURA", "PLAYER_ROLES_ASSIGNED", "SPELLS_CHANGED" }) do
        events:RegisterEvent(event)
    end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    if not barFrame and InCombatLockdown() then
        buildAfterCombat = true
        return
    end
    if not barFrame then MakeBar() end
    ticker = C_Timer.NewTicker(TICK_SECONDS, Ticked)
    Update()
end

do
    -------------------------------------------------------------------------------
    --  The assignments window (/cbless)
    -------------------------------------------------------------------------------
    local WINDOW_W, WINDOW_H = 640, 470
    local CELL_SIZE, SPACING, NAME_WIDTH = 32, 6, 150
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
            if payload then payload() end
        end,
    }
    local function AskConfirm(textValue, func)
        local dialog = StaticPopup_Show("CUI_BLESS_CONFIRM", textValue)
        if dialog then dialog.data = func end
    end

    local function MayCastOn()
        if PlanAllAllowed() then return true end
        Print("Only the group leader or an assistant can plan every paladin's blessings.")
    end

    local function WindowItem(kind)
        winUsed = winUsed + 1
        local entry = winPool[winUsed]
        if entry and entry.kind ~= kind then
            entry:Hide()
            entry = nil
        end
        if not entry then
            if kind == "cell" then
                entry = CreateFrame("Button", nil, winContent)
                entry:SetSize(CELL_SIZE, CELL_SIZE)
                StyleIcon(entry)
                entry:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.title or "", 1, 1, 1)
                    local ar, ag, ab = CUI.Kit.Accent()
                    if self.body then GameTooltip:AddLine(self.body, ar, ag, ab, true) end
                    GameTooltip:Show()
                end)
                entry:SetScript("OnLeave", function() GameTooltip:Hide() end)
            else
                entry = CreateFrame("Frame", nil, winContent)
                entry:SetSize(1, 1)
                entry.text = entry:CreateFontString(nil, "OVERLAY")
                entry.text:SetPoint("TOPLEFT")
                entry.text:SetJustifyH("LEFT")
            end
            entry.kind = kind
            local old = winPool[winUsed]
            if old then old:Hide() end
            winPool[winUsed] = entry
        end
        entry:ClearAllPoints()
        entry:Show()
        return entry
    end

    local function WindowText(posX, posY, textValue, size, colour, width)
        local entry = WindowItem("text")
        entry:SetPoint("TOPLEFT", winContent, "TOPLEFT", posX, posY)
        CUI.Kit.Font(entry.text, size or 12, "essentials")
        entry.text:SetTextColor(unpack(colour or { 1, 1, 1 }))
        entry.text:SetWidth(width or 0)
        entry.text:SetWordWrap(width ~= nil)
        entry.text:SetText(textValue)
        return entry.text:GetStringHeight()
    end

    local function WindowCell(posX, posY, iconTex, lit, title, body, onClick)
        local button = WindowItem("cell")
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

    local function TimeLeft(leftX)
        if not leftX then return end
        return leftX > 0 and (math.ceil(leftX / 60) .. "m") or "ready"
    end

    local function StatusLabel(row)
        local symbols, loh, di
        if row.you then
            symbols, loh, di = MyStatus()
            if loh < 0 then loh = nil end
            if di < 0 then di = nil end
        elseif row.plan.status then
            local status, nowTime = row.plan.status, GetTime()
            symbols = status.symbols
            loh = status.loh and status.loh - nowTime
            di = status.di and status.di - nowTime
        else
            return ""
        end
        local parts = { ("%d Symbols"):format(symbols) }
        if loh then parts[#parts + 1] = "LoH " .. TimeLeft(loh) end
        if di then parts[#parts + 1] = "DI " .. TimeLeft(di) end
        return table.concat(parts, "  ")
    end

    local function RowList(roster)
        local lead = AssignAllowed("player")
        local entries = {}
        if PaladinUnit() then
            local storage = Keep()
            entries[1] = {
                who = OwnName(),
                you = true,
                plan = storage,
                players = storage.players,
                can = OnLearned,
                set = AssignOwn,
            }
        end
        local mayFree = PaladinUnit()
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
                can = function(record) return plan.known[record.key] end,
                set = not plan.pallyPower and (lead or (mayFree and plan.free)) and function(colour, key)
                    AssignFor(who, colour, key)
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

    local function MyList(roster, players, class)
        local result = {}
        for _, member in ipairs(roster) do
            local key = member.class == class and players and players[member.guid]
            if key then result[#result + 1] = Ambiguate(member.who, "short") .. ": " .. NameOfSpell(key) end
        end
        return #result > 0 and ("\n" .. table.concat(result, "\n")) or ""
    end

    local function Repaint()
        redrawQueued = false
        if not (window and window:IsShown()) then return end
        for index = 1, winUsed do
            winPool[index]:Hide()
        end
        winUsed = 0
        local posY = -4
        local roster = GroupRoster()
        local columns = {}
        for _, class in ipairs(CLASS_LIST) do
            columns[#columns + 1] = class
        end
        columns[#columns + 1] = AURA_COL
        for index, colour in ipairs(columns) do
            local aura = colour == AURA_COL
            WindowCell(
                NAME_WIDTH + (index - 1) * (CELL_SIZE + SPACING),
                posY,
                aura and IconOfSpell("devotion")
                    or ("Interface\\Icons\\ClassIcon_" .. colour:lower():gsub("^%l", string.upper)),
                true,
                aura and "Aura" or ClassLabel(colour)
            )
        end
        posY = posY - CELL_SIZE - 10
        local entries = RowList(roster)
        if #entries == 0 then
            WindowText(0, posY, "No paladins in your group.", 12, { 0.6, 0.65, 0.7 })
            posY = posY - 20
        end
        for _, row in ipairs(entries) do
            WindowText(
                0,
                posY - 4,
                Ambiguate(row.who, "short") .. (row.you and "  (you)" or ""),
                13,
                { 0.96, 0.55, 0.73 },
                NAME_WIDTH - 10
            )
            if row.plan then
                WindowText(0, posY - 20, StatusLabel(row), 10, { 0.6, 0.65, 0.7 }, NAME_WIDTH - 10)
                for index, colour in ipairs(columns) do
                    local aura = colour == AURA_COL
                    local key = aura and row.plan.aura or row.plan.classes[colour]
                    local title = aura and "Aura" or ClassLabel(colour)
                    local onClick = row.set
                        and function(button)
                            local function Able(record)
                                return row.can(record)
                                    and (aura or key == record.key or MayCast(colour, record.key))
                            end
                            ShowMenuFor(
                                button,
                                title,
                                aura and AURA_LIST or BLESSING_LIST,
                                function() return aura and row.plan.aura or row.plan.classes[colour] end,
                                function(choice) row.set(colour, choice) end,
                                "None",
                                Able
                            )
                        end
                    WindowCell(
                        NAME_WIDTH + (index - 1) * (CELL_SIZE + SPACING),
                        posY,
                        key and IconOfSpell(key) or ASK_CODE,
                        key ~= nil,
                        title,
                        (key and NameOfSpell(key) or "Nothing assigned")
                            .. (aura and "" or MyList(roster, row.players, colour))
                            .. (
                                onClick and "\nClick to change."
                                or row.plan.pallyPower and "\nPlanned in PallyPower."
                                or ""
                            ),
                        onClick
                    )
                end
            else
                WindowText(
                    NAME_WIDTH,
                    posY - 10,
                    "No reply: blessings addon off or not installed",
                    12,
                    { 0.6, 0.65, 0.7 }
                )
            end
            posY = posY - CELL_SIZE - SPACING
        end
        winContent:SetHeight(math.abs(posY) + 10)
        local num = 0
        for _, member in ipairs(roster) do
            if member.class == "PALADIN" then num = num + 1 end
        end
        window.foot:SetText(
            not IsInGroup() and (PaladinUnit() and "Just you for now" or "Not in a group")
                or num == 0 and "No paladins in your group"
                or num == 1 and "1 paladin in your group"
                or (num .. " paladins in your group")
        )
        window.free:SetShown(PaladinUnit())
        window.free:SetChecked(PaladinUnit() and Keep().free == true)
    end

    function RefreshPage()
        if redrawQueued or not (window and window:IsShown()) then return end
        redrawQueued = true
        C_Timer.After(0, Repaint)
    end

    local function WindowButton(hostFrame, textValue, posX, onClick, tipText)
        local b =
            CUI.Kit.Button(hostFrame, textValue, 96, 22, onClick, { key = "essentials", tip = tipText })
        b:SetPoint("TOPLEFT", posX, -34)
        return b
    end

    local function MakeWindow()
        window = CreateFrame("Frame", "CludesUIBlessings", UIParent)
        window:SetSize(WINDOW_W, WINDOW_H)
        window:SetPoint("CENTER", 0, 40)
        CUI.Kit.Panel(window, 0.96)
        window:SetMovable(true)
        window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        window:SetFrameStrata("HIGH")
        window:SetClampedToScreen(true)
        local title = window:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(title, 15, "essentials")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText("Blessings")
        CUI.Kit.AccentText(title)
        local close = CUI.Kit.Glyph(window, "x", function() window:Hide() end, nil, "essentials")
        close:SetPoint("TOPRIGHT", -5, -5)
        WindowButton(window, "Auto-Assign", 10, function()
            if MayCastOn() then
                AskConfirm(
                    "Replace every paladin's blessings and auras with an automatic plan?",
                    function() UsePlans(AutoAssign()) end
                )
            end
        end, "A plan for every paladin in the group, by what each has learned.")
        WindowButton(window, "Load Preset", 110, function()
            if not next(PresetList()) then return Print("No preset saved yet.") end
            if MayCastOn() then
                AskConfirm("Load the saved preset for the paladins here now?", function()
                    if not UsePreset() then Print("Nobody in the preset is in your group.") end
                end)
            end
        end)
        WindowButton(window, "Save Preset", 210, function()
            if #PaladinList() == 0 then return Print("No paladins to save a plan for.") end
            local function Persist()
                if StorePreset() then Print("Blessings preset saved.") end
            end
            if next(PresetList()) then
                AskConfirm("Replace the saved preset?", Persist)
            else
                Persist()
            end
        end, "Saves the plan below to load again with this group.")
        WindowButton(window, "Report", 310, function(self)
            CUI.Kit.ContextMenu(self, function(_, root)
                root:CreateTitle("Report the blessings to")
                for _, channel in ipairs(REPORT_TARGETS) do
                    if channel.can() then
                        root:CreateButton(channel.label, function() PostReport(channel.key) end)
                    end
                end
            end)
        end)
        WindowButton(window, "Clear", 410, function()
            if MayCastOn() then
                AskConfirm("Clear every paladin's blessings and auras?", function()
                    ResetAll()
                    RefreshPage()
                end)
            end
        end)
        WindowButton(window, "Refresh", 510, function()
            wipe(asked)
            SyncShortly()
            Print("Asked the group's paladins for their plans.")
        end, "Asks the group's paladins for their plans.")
        window.free = CUI.Kit.Check(
            window,
            "Free Assignment: other paladins may change your blessings without being the leader or an assistant",
            nil,
            "essentials"
        )
        window.free:SetPoint("TOPLEFT", 14, -64)
        window.free:SetScript("OnClick", function(self)
            Keep().free = self:GetChecked() and true or nil
            AnnounceSoon()
            OnChange()
        end)
        winScroll = (CUI.Kit.Scroll(window))
        winScroll:SetPoint("TOPLEFT", 10, -92)
        winScroll:SetPoint("BOTTOMRIGHT", -30, 28)
        winContent = CreateFrame("Frame", nil, winScroll)
        winContent:SetSize(WINDOW_W - 44, 10)
        winScroll:SetScrollChild(winContent)
        window.foot = window:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(window.foot, 11, "essentials")
        window.foot:SetTextColor(0.6, 0.65, 0.7)
        window.foot:SetPoint("BOTTOMLEFT", 10, 8)
        window:Hide()
        tinsert(UISpecialFrames, "CludesUIBlessings")
    end

    function ShowWindow()
        if not window then MakeWindow() end
        window:Show()
        Repaint()
    end

    local function FlipWindow()
        if window and window:IsShown() then
            window:Hide()
        else
            ShowWindow()
        end
    end

    SLASH_CUIBLESS1 = "/cbless"
    SlashCmdList.CUIBLESS = function()
        if not On() then
            Print("turn on Blessings in CludesUI Forever Tools first.")
            return
        end
        FlipWindow()
    end
end

CUI._Blessings = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Open = ShowWindow,
    ClassBlessing = function(class) return Keep().classes[class] end,
    SetClassBlessing = function(class, key) AssignOwn(class, key) end,
    Blessings = BLESSING_LIST,
    SpellName = NameOfSpell,
    Learned = OnLearned,
    Classes = CLASS_LIST,
    ClassName = ClassLabel,
}

F.Start(Apply, {
    key = "CUI_BlessingBar",
    label = "Blessing Bar",
    order = 755,
    shown = function() return F.Enabled() and PaladinUnit() end,
    frame = function(build)
        if build and not barFrame and not InCombatLockdown() then
            MakeBar()
            Update()
        end
        return barFrame
    end,
    size = function()
        return barFrame and barFrame:GetWidth() or Get("size"),
            barFrame and barFrame:GetHeight() or Get("size")
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
