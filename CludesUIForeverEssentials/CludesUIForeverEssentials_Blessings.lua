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

local CALLING_ROSTER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CALLING_OK = {}
for _, calling in ipairs(CALLING_ROSTER) do
    CALLING_OK[calling] = true
end
local AURA_COL = "AURA"
local NO_ONE = "-"
local ASK_CODE = 134400

local B = { others = {} }
local others = B.others

local function Secret(val) return issecretvalue and issecretvalue(val) end
local function PaladinUnit() return select(2, UnitClass("player")) == "PALADIN" end
local function MineTitle() return (UnitFullName("player")) end
local function CallingLabel(calling) return LOCALIZED_CLASS_NAMES_MALE[calling] or calling end
local function On() return F.Enabled() end
local function Print(message) CUI.Print("|cff4cc9f0Blessings:|r " .. message) end
-- Shared between the sections below (each keeps its own helpers in a do block).
local AurasHidden, Recalled, DropIfDead, OnCastSent, LogCast, OnCastDone, DropCasts
local FromPP, PPA_LEAD, asked
local K, idAuto

-------------------------------------------------------------------------------
--  Spells
-------------------------------------------------------------------------------
local BLESSING_ROSTER = {
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
local AURA_ROSTER = {
    { key = "devotion", code = "D", ranks = { 465, 10290, 643, 10291, 1032, 10292, 10293 } },
    { key = "retribution", code = "R", ranks = { 7294, 10298, 10299, 10300, 10301 } },
    { key = "concentration", code = "C", ranks = { 19746 } },
    { key = "shadow", code = "S", ranks = { 19876, 19895, 19896 } },
    { key = "frost", code = "F", ranks = { 19888, 19897, 19898 } },
    { key = "fire", code = "I", ranks = { 19891, 19899, 19900 } },
    { key = "sanctity", code = "T", ranks = { 20218 } },
}
local SPELL_FURY = { key = "fury", ranks = { 25780 } }
local SEAL_ROSTER = {
    { key = "sealRighteousness", ranks = { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 } },
    { key = "sealCommand", ranks = { 20375, 20915, 20918, 20919, 20920 } },
    { key = "sealFury", ranks = { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 } },
    { key = "sealCrusader", ranks = { 21082, 20162, 20305, 20306, 20307, 20308 } },
    { key = "sealJustice", ranks = { 20164 } },
    { key = "sealLight", ranks = { 20165, 20347, 20348, 20349 } },
    { key = "sealWisdom", ranks = { 20166, 20356, 20357 } },
}
local THING_SYMBOL = 21177
local UNASSIGNED_FLAG = "X"

local FROM_ID, FROM_CODE, SPELL_FAMILY, SPELL_IDS, GREATER_CHART = {}, {}, {}, {}, {}
local function CatalogOf(log, untracked)
    FROM_ID[log.key] = log
    if log.code then FROM_CODE[log.code] = log end
    SPELL_IDS[log.key] = {}
    for _, ident in ipairs(log.ranks) do
        if not untracked then SPELL_FAMILY[ident] = log.key end
        SPELL_IDS[log.key][ident] = true
    end
    for _, ident in ipairs(log.greater or {}) do
        SPELL_FAMILY[ident] = log.key
        SPELL_IDS[log.key][ident] = true
        GREATER_CHART[ident] = true
    end
end
for _, log in ipairs(BLESSING_ROSTER) do
    log.blessing = true
    CatalogOf(log)
end
for _, log in ipairs(AURA_ROSTER) do
    CatalogOf(log)
end
for _, log in ipairs(SEAL_ROSTER) do
    CatalogOf(log, true)
end
CatalogOf(SPELL_FURY)

local function TopTier(ids)
    for catalog = #(ids or {}), 1, -1 do
        if C_SpellBook.IsSpellKnown(ids[catalog]) then return ids[catalog] end
    end
end
local function OnTrained(log)
    return TopTier(log.ranks) or (log.greater and TopTier(log.greater))
end
local function TitleOfSpell(id)
    local log = FROM_ID[id]
    return log and C_Spell.GetSpellName(log.ranks[1]) or id
end
local function GlyphOfSpell(id)
    local log = FROM_ID[id]
    return log and C_Spell.GetSpellTexture(log.ranks[1]) or ASK_CODE
end

-------------------------------------------------------------------------------
--  Your plan, kept per character
-------------------------------------------------------------------------------
local function Keep()
    local conf = F.Cfg()
    conf.chars = conf.chars or {}
    local id = UnitName("player") .. "-" .. GetRealmName()
    local storage = conf.chars[id]
    if not (storage and storage.classes) then
        storage = { classes = {}, players = {} }
        conf.chars[id] = storage
    end
    return storage
end

local PlainTitle, GroupRoster, ShownNow, Grouped, AssignAllowed, AssignedTo, MayCast, SenderUnit
do
    -------------------------------------------------------------------------------
    --  Group
    -------------------------------------------------------------------------------
    local TITLE_TALLY = 4
    function PlainTitle(val) return not Secret(val) and val ~= nil and val ~= "" end

    local function ColNames(member, realm, firstNames, raid)
        local spotted, result = {}, {}
        local function Append(name)
            if PlainTitle(name) and not spotted[name] then
                spotted[name] = true
                result[#result + 1] = name
            end
        end
        for _, name in ipairs(member.candidates) do
            if firstNames[name] == 1 then Append(name) end
        end
        if not member.who:find("-", 1, true) then Append(member.who .. "-" .. realm) end
        local spottedBy
        if raid then
            spottedBy = member.rosterName
        elseif PlainTitle(member.short) then
            spottedBy = PlainTitle(member.server) and member.short .. "-" .. member.server or member.short
        end
        return table.concat(result, ","), PlainTitle(spottedBy) and spotted[spottedBy] == true
    end

    function GroupRoster()
        local units = { "player" }
        local raid = IsInRaid()
        if raid then
            units = {}
            for catalog = 1, GetNumGroupMembers() do
                units[#units + 1] = "raid" .. catalog
            end
        else
            for catalog = 1, GetNumSubgroupMembers() do
                units[#units + 1] = "party" .. catalog
            end
        end
        local realm = GetNormalizedRealmName()
        local items, firstNames = {}, {}
        for catalog, unitToken in ipairs(units) do
            local name, unitRealm = UnitFullName(unitToken)
            local _, calling = UnitClass(unitToken)
            local unitId = UnitGUID(unitToken)
            if
                name
                and not (Secret(name) or Secret(unitRealm) or Secret(calling) or Secret(unitId))
                and calling
            then
                local who = name
                if unitRealm and unitRealm ~= "" and unitRealm ~= realm then
                    who = name .. "-" .. unitRealm
                end
                local lacking, server = UnitName(unitToken)
                local member = {
                    unit = unitToken,
                    guid = unitId,
                    class = calling,
                    who = who,
                    short = lacking,
                    server = server,
                    rosterName = raid and (GetRaidRosterInfo(catalog)) or nil,
                }
                local subgroup = raid and select(3, GetRaidRosterInfo(catalog))
                member.subgroup = not Secret(subgroup) and subgroup or nil
                local titleRoster = { who, lacking, member.rosterName }
                if PlainTitle(lacking) and PlainTitle(server) then titleRoster[4] = lacking .. "-" .. server end
                member.candidates = {}
                local counted = {}
                for k = 1, TITLE_TALLY do
                    local num = titleRoster[k]
                    if PlainTitle(num) and not counted[num] then
                        counted[num] = true
                        firstNames[num] = (firstNames[num] or 0) + 1
                        member.candidates[#member.candidates + 1] = num
                    end
                end
                items[#items + 1] = member
            end
        end
        for _, member in ipairs(items) do
            member.names, member.targetable = ColNames(member, realm, firstNames, raid)
        end
        return items
    end

    -- In a raid dungeon with Hide the Bench on, the groups past its usual size are left out.
    function ShownNow(roster)
        if not (Get("bench") and IsInRaid()) then return roster end
        local _, kind, _, _, topPeople = GetInstanceInfo()
        if kind ~= "raid" or not topPeople or topPeople <= 0 then return roster end
        local last = math.ceil(topPeople / 5)
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

    local TANK_STATUS = { WARRIOR = true, DRUID = true, PALADIN = true }
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
        if not TANK_STATUS[member.class] or (tank == BLESSING_NONE and assist == BLESSING_NONE) then return end
        local id = tank ~= BLESSING_NONE and TankUnit(member.unit) and tank
            or assist ~= BLESSING_NONE and HasAssist(member.unit) and assist
        return id and FROM_ID[id] and OnTrained(FROM_ID[id]) and id or nil
    end

    function AssignedTo(member)
        local storage = Keep()
        return storage.players[member.guid] or BlessingForRole(member) or storage.classes[member.class]
    end

    function MayCast(calling, id)
        local no = Get("smart") and WRONG_ROLE[calling]
        return not (no and no[id])
    end

    -- Whether an addon message's sender is this unit.
    function SenderUnit(sender, unitToken, unitId)
        if not (PlainTitle(sender) and PlainTitle(unitToken) and PlainTitle(unitId)) then return false end
        local g = UnitGUID(unitToken)
        if not PlainTitle(g) or g ~= unitId then return false end
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
    local spotted, casts, sent = {}, {}, nil

    function AurasHidden()
        local _, kind = IsInInstance()
        return HIDDEN_STATES[kind] == true
    end

    function Recalled(unitToken, id)
        local unitId = UnitGUID(unitToken)
        local mine = unitId and not Secret(unitId) and spotted[unitId]
        local ends = mine and mine[id]
        if not ends then return false end
        local dead = UnitIsDeadOrGhost(unitToken)
        if not Secret(dead) and dead then
            spotted[unitId] = nil
            return false
        end
        local leftX = ends - GetTime()
        if leftX <= 0 then
            mine[id] = nil
            return false
        end
        return true, leftX ~= math.huge and leftX or nil
    end

    function DropIfDead(unitToken)
        if not next(spotted) then return end
        local unitId = UnitGUID(unitToken)
        if not unitId or Secret(unitId) or not spotted[unitId] then return end
        local dead = UnitIsDeadOrGhost(unitToken)
        if not Secret(dead) and dead then spotted[unitId] = nil end
    end

    function OnCastSent(castId, spell) sent = { guid = castId, spell = spell, at = GetTime() } end

    function LogCast(unitToken, spell)
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
        local id = SPELL_FAMILY[spell]
        if not id then return end
        local roster = GroupRoster()
        local aim
        for _, member in ipairs(roster) do
            local same = UnitIsUnit(unitToken, member.unit)
            if not Secret(same) and same then
                aim = member
                break
            end
        end
        if not aim then return end
        local guids = {}
        for _, member in ipairs(roster) do
            if member.guid == aim.guid or (GREATER_CHART[spell] and member.class == aim.class) then
                guids[#guids + 1] = member.guid
            end
        end
        for ident, old in pairs(casts) do
            if GetTime() - old.at >= CAST_GRACE then casts[ident] = nil end
        end
        casts[cast.guid] = { key = id, guids = guids, at = GetTime() }
    end

    function OnCastDone(castId)
        local cast = casts[castId]
        if not cast then return end
        casts[castId] = nil
        if GetTime() - cast.at >= CAST_GRACE then return end
        local ends = GetTime() + (FROM_ID[cast.key].blessing and BLESSING_SECONDS or math.huge)
        for _, unitId in ipairs(cast.guids) do
            spotted[unitId] = spotted[unitId] or {}
            spotted[unitId][cast.key] = ends
        end
    end

    function DropCasts()
        sent = nil
        wipe(casts)
        wipe(spotted)
    end
end

local CastingSpell, StartAuraJot, HaltAuraJot, BlessStatus, WaitTime, UrgencySorter, SweepGroup, RequiresRecast
do
    -------------------------------------------------------------------------------
    --  Who has which blessing, and who a class button blesses next
    -------------------------------------------------------------------------------
    local EXPIRY_CAUTION, AURAS_TOP = 300, 40

    function CastingSpell(id, members)
        local log = FROM_ID[id]
        local greater = C_Item.GetItemCount(THING_SYMBOL) > 0 and TopTier(log.greater)
        if greater then
            for _, member in ipairs(members) do
                if AssignedTo(member) ~= id then
                    greater = nil
                    break
                end
            end
        end
        return greater or TopTier(log.ranks)
    end

    local memoAt
    local memo, scratch = {}, {}
    function StartAuraJot()
        memoAt = GetTime()
        for _, s in pairs(memo) do
            s.stale = true
        end
    end
    function HaltAuraJot() memoAt = nil end

    local function FoundUnit(val)
        if val == true then return true end
        return true, val - GetTime()
    end

    function BlessStatus(unitToken, id)
        if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
            if AurasHidden() then return Recalled(unitToken, id) end
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
        local val = s[id]
        if val then return FoundUnit(val) end
        if s.ended == "none" then return false end
        if s.ended then return nil end
        for catalog = s.next or 1, AURAS_TOP do
            local aura = C_UnitAuras.GetAuraDataByIndex(unitToken, catalog, "HELPFUL")
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
            if family and family == id then
                s.next = catalog + 1
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

    function SweepGroup(members)
        local cfg = {
            missing = 0,
            reachable = false,
            missingNear = 0,
            expiringNear = 0,
            classDue = 0,
            classMissing = 0,
            queue = {},
        }
        local tier, leftX
        local queue = cfg.queue
        local people = Keep().players
        local abilities = {}
        for _, member in ipairs(members) do
            local id = AssignedTo(member)
            if id and abilities[id] == nil then
                local cast = CastingSpell(id, members)
                if cast and GREATER_CHART[cast] and not WaitTime(members, cast) then
                    cast = TopTier(FROM_ID[id].ranks)
                end
                abilities[id] = cast or false
            end
            local spell = id and abilities[id]
            if spell and UnitIsConnected(member.unit) and not UnitIsDeadOrGhost(member.unit) then
                local has, remaining = BlessStatus(member.unit, id)
                if has == false then
                    cfg.missing = cfg.missing + 1
                    cfg.shortest = 0
                elseif remaining and (not cfg.shortest or remaining < cfg.shortest) then
                    cfg.shortest = remaining
                end
                local range = UnitIsVisible(member.unit) and WithinRange(member, spell)
                if has ~= nil and range ~= false then
                    cfg.reachable = true
                    local region = not has and 0 or (remaining and remaining < EXPIRY_CAUTION and 1 or 2)
                    if range == true and region < 2 and member.targetable then
                        if region == 0 then
                            cfg.missingNear = cfg.missingNear + 1
                        else
                            cfg.expiringNear = cfg.expiringNear + 1
                        end
                        if not people[member.guid] then
                            cfg.classDue = cfg.classDue + 1
                            if region == 0 then cfg.classMissing = cfg.classMissing + 1 end
                        end
                    end
                    local l = remaining or math.huge
                    if member.targetable then
                        queue[#queue + 1] = { names = member.names, spell = spell, rank = region, left = l }
                        if not cfg.target or region < tier or (region == tier and l < leftX) then
                            cfg.target, cfg.spell, tier, leftX = member, spell, region, l
                        end
                    end
                end
            end
        end
        table.sort(queue, UrgencySorter)
        local due = 0
        for _, log in ipairs(queue) do
            if log.rank < 2 then due = due + 1 end
        end
        if GREATER_CHART[queue[1] and queue[1].spell] then due = math.min(due, 1) end
        local keep = Get("respect") and 0 or 1
        for catalog = #queue, math.max(due, keep) + 1, -1 do
            queue[catalog] = nil
        end
        if due == 0 and keep == 0 then cfg.target = nil end
        cfg.rank, cfg.left = tier, leftX
        return cfg
    end

    function RequiresRecast(member, id, spell)
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
        local has, remaining = BlessStatus(member.unit, id)
        if has == false then return 0, 0 end
        if has and remaining and remaining < EXPIRY_CAUTION then return 1, remaining end
    end
end

local STATUS_ABILITIES, MyStatus
do
    -------------------------------------------------------------------------------
    --  Symbols of Kings, Lay on Hands and Divine Intervention, shared with the
    --  group's paladins
    -------------------------------------------------------------------------------
    local SPELL_LOH, SPELL_DI = { 633, 2800, 10310 }, { 19752 }
    STATUS_ABILITIES = {}
    for _, ranks in ipairs({ SPELL_LOH, SPELL_DI }) do
        for _, ident in ipairs(ranks) do
            STATUS_ABILITIES[ident] = true
        end
    end

    local function CooldownRemaining(ranks)
        local spell = TopTier(ranks)
        if not spell then return -1 end
        local details = C_Spell.GetSpellCooldown(spell)
        local start, duration = details and details.startTime, details and details.duration
        if not start or Secret(start) or Secret(duration) or duration <= 1.5 then return 0 end
        return math.max(0, math.floor(start + duration - GetTime()))
    end

    function MyStatus()
        return C_Item.GetItemCount(THING_SYMBOL),
            CooldownRemaining(SPELL_LOH),
            CooldownRemaining(SPELL_DI)
    end
end

local RenewPage, QueryPP, OnChange
local MSG_LEAD, Transmit, TalkAim, AnnounceSoon, FromWhom, OnAddonMessage, TransmitPlan, SyncShortly, OutOfCombat
do
    -------------------------------------------------------------------------------
    --  Plans shared with the group's paladins (our message format)
    -------------------------------------------------------------------------------
    MSG_LEAD = "CludesBless"
    local CODE_NONE = "-"
    local PEOPLE_PER_MESSAGE, PERSON_CHOICES_TOP, SYMBOLS_TOP, BATCH_WAIT = 200, 40, 9999, 1
    local pending = {}
    local sentPeople, broadcastLaterCombat, broadcastQueued, syncQueued

    local function WritePlan(callings, aura)
        local result = {}
        for catalog, calling in ipairs(CALLING_ROSTER) do
            result[catalog] = callings[calling] and FROM_ID[callings[calling]].code or CODE_NONE
        end
        result[#result + 1] = aura and FROM_ID[aura].code or CODE_NONE
        return table.concat(result)
    end

    local function LoadPlan(labelValue)
        if #labelValue ~= #CALLING_ROSTER + 1 then return end
        local callings = {}
        for catalog, calling in ipairs(CALLING_ROSTER) do
            local c = labelValue:sub(catalog, catalog)
            if c ~= CODE_NONE then
                local log = FROM_CODE[c]
                if not (log and log.blessing) then return end
                callings[calling] = log.key
            end
        end
        local c = labelValue:sub(-1)
        if c == CODE_NONE then return callings, nil end
        local log = FROM_CODE[c]
        if log and not log.blessing then return callings, log.key end
    end

    local function CodesLearned()
        local codes = {}
        for _, log in ipairs(BLESSING_ROSTER) do
            if OnTrained(log) then codes[#codes + 1] = log.code end
        end
        for _, log in ipairs(AURA_ROSTER) do
            if OnTrained(log) then codes[#codes + 1] = log.code end
        end
        if Keep().free then codes[#codes + 1] = UNASSIGNED_FLAG end
        return table.concat(codes)
    end

    function TalkAim()
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
    end

    function Transmit(message, id)
        if InCombatLockdown() then
            pending[id or message] = message
            return
        end
        local medium = TalkAim()
        if medium then C_ChatInfo.SendAddonMessage(MSG_LEAD, message, medium) end
    end

    local function TransmitPeople()
        local people = Keep().players
        local parts, num, chunk = {}, 1, ""
        for _, member in ipairs(GroupRoster()) do
            local id = people[member.guid]
            if id then
                local part = member.guid .. "=" .. FROM_ID[id].code
                if #chunk + #part > PEOPLE_PER_MESSAGE then
                    parts[#parts + 1] = chunk
                    chunk = ""
                end
                chunk = chunk == "" and part or chunk .. "," .. part
            end
        end
        parts[#parts + 1] = chunk
        if chunk == "" and #parts == 1 and not sentPeople then return end
        sentPeople = chunk ~= "" or #parts > 1
        for _, body in ipairs(parts) do
            Transmit("P|" .. num .. "|" .. body, "P|" .. num)
            num = num + 1
        end
    end

    local function StatusRow()
        local symbols, loh, di = MyStatus()
        return ("I|%d|%d|%d"):format(symbols, loh, di)
    end

    local function Announce()
        if not PaladinUnit() then return end
        if InCombatLockdown() then
            broadcastLaterCombat = true
            return
        end
        local storage = Keep()
        Transmit("F|" .. WritePlan(storage.classes, storage.aura) .. "|" .. CodesLearned())
        TransmitPeople()
        Transmit(StatusRow(), "I")
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

    local function AssignmentMade(from, name, aim, plan)
        local callings, aura = LoadPlan(plan)
        if not (PaladinUnit() and callings and CanPlan(from) and aim == UnitGUID("player")) then return end
        local storage = Keep()
        storage.classes = {}
        for calling, id in pairs(callings) do
            if OnTrained(FROM_ID[id]) then storage.classes[calling] = id end
        end
        storage.aura = aura and OnTrained(FROM_ID[aura]) and aura or nil
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
        from.status = { symbols = math.min(tonumber(symbols), SYMBOLS_TOP), loh = ExpiresAt(loh), di = ExpiresAt(di) }
        RenewPage()
    end

    local function PeopleReceived(who, part, items)
        local from = others[who]
        if not from then return end
        if part == "1" then
            from.players, from.choices = {}, 0
        end
        for unitId, code in items:gmatch("(Player%-[%w%-]+)=(%a)") do
            local log = FROM_CODE[code]
            local choices = from.choices or 0
            if log and log.blessing and (from.players[unitId] or choices < PERSON_CHOICES_TOP) then
                if not from.players[unitId] then from.choices = choices + 1 end
                from.players[unitId] = log.key
            end
        end
        RenewPage()
    end

    local function PlanReceived(from, body, known)
        if not (body and from.class == "PALADIN") then return end
        local callings, aura = LoadPlan(body)
        if not callings then return end
        local assign, free = {}, nil
        for code in known:gmatch(".") do
            if FROM_CODE[code] then assign[FROM_CODE[code].key] = true end
            if code == UNASSIGNED_FLAG then free = true end
        end
        local was = others[from.who]
        others[from.who] = {
            classes = callings,
            aura = aura,
            free = free,
            known = assign,
            players = was and was.players or {},
            choices = was and was.choices or 0,
            status = was and was.status,
        }
        RenewPage()
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
        local aim, plan = message:match("^S|([^|]+)|(%S+)$")
        if aim then return AssignmentMade(from, Ambiguate(sender, "none"), aim, plan) end
        local symbols, loh, di = message:match("^I|(%d+)|(%-?%d+)|(%-?%d+)$")
        if symbols then return StatusReceived(who, symbols, loh, di) end
        local part, items = message:match("^P|(%d+)|(.*)$")
        if part then return PeopleReceived(who, part, items) end
        local body, known = message:match("^F|(%S+)|(%a*)$")
        PlanReceived(from, body, known)
    end

    function TransmitPlan(who, callings, aura)
        local member = Grouped(who)
        if not member then return end
        others[who].classes, others[who].aura = callings, aura
        Transmit("S|" .. member.guid .. "|" .. WritePlan(callings, aura), "S|" .. member.guid)
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
            RenewPage()
        end)
    end

    function OutOfCombat()
        if broadcastLaterCombat then
            broadcastLaterCombat = false
            AnnounceSoon()
        end
        for id, message in pairs(pending) do
            pending[id] = nil
            Transmit(message)
        end
        if PaladinUnit() or AssignAllowed("player") then QueryPP() end
    end

    do
    end

    -------------------------------------------------------------------------------
    --  PallyPower users' plans, read from its addon messages
    -------------------------------------------------------------------------------
    PPA_LEAD = "PLPWR"
    local PPA_CHANGES = { ASSIGN = true, PASSIGN = true, MASSIGN = true, AASSIGN = true, CLEAR = true }
    local PPA_CALLINGS =
        { "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN" }
    local PPA_BLESSINGS = { "wisdom", "might", "kings" }
    local PPA_AURAS = { "devotion", "retribution", "concentration", "shadow", "frost", "fire", "sanctity" }
    local PPA_TOP_CD = 7200
    asked = {}

    local function PPAPlan(who)
        local plan = others[who]
        if plan then return plan.pallyPower and plan or nil end
        plan = { classes = {}, known = {}, players = {}, choices = 0, pallyPower = true }
        others[who] = plan
        return plan
    end

    local function PPALearned(plan, idRoster, ranks)
        for catalog, id in ipairs(idRoster) do
            local tier = ranks:sub(2 * catalog - 1, 2 * catalog - 1)
            plan.known[id] = tier ~= "" and tier ~= "n" or nil
        end
    end

    local function PPAPick(plan, idRoster, catalog)
        local id = idRoster[tonumber(catalog)]
        return id and plan.known[id] and id or nil
    end

    local function PPACallings(plan, given)
        plan.classes = {}
        for catalog, calling in ipairs(PPA_CALLINGS) do
            plan.classes[calling] = PPAPick(plan, PPA_BLESSINGS, given:sub(catalog, catalog))
        end
    end

    local function PPAEnds(leftX)
        leftX = tonumber(leftX)
        return leftX and leftX >= 0 and leftX <= PPA_TOP_CD and GetTime() + leftX or nil
    end

    local function PPAAim(name, from)
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
        local name, calling, catalog = message:match("^ASSIGN (.+) (%d+) (%d+)$")
        if name then
            local plan, colour = PPAAim(name, from), PPA_CALLINGS[tonumber(calling)]
            if plan and colour then plan.classes[colour] = PPAPick(plan, PPA_BLESSINGS, catalog) end
            return
        end
        local given
        name, given = message:match("^PASSIGN (.+)@([%dn]*)$")
        if name then
            local plan = PPAAim(name, from)
            if plan then PPACallings(plan, given) end
            return
        end
        name, catalog = message:match("^MASSIGN (.+) (%d+)$")
        if name then
            local plan = PPAAim(name, from)
            if not plan then return end
            local id = PPAPick(plan, PPA_BLESSINGS, catalog)
            for _, colour in ipairs(PPA_CALLINGS) do
                plan.classes[colour] = id
            end
            return
        end
        name, catalog = message:match("^AASSIGN (.+) (%d+)$")
        local plan = name and PPAAim(name, from)
        if plan then plan.aura = PPAPick(plan, PPA_AURAS, catalog) end
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
            return RenewPage()
        end
        if from.class ~= "PALADIN" then return end
        local plan = ranks and PPAPlan(from.who) or others[from.who]
        if not (plan and plan.pallyPower) then return end
        if ranks then
            PPALearned(plan, PPA_BLESSINGS, ranks)
            PPACallings(plan, given)
        elseif auraRanks then
            PPALearned(plan, PPA_AURAS, auraRanks)
            plan.aura = PPAPick(plan, PPA_AURAS, aura)
        else
            local loh, di = message:match("COOLDOWNS:[^:]*:([^:]*):[^:]*:([^:]*)$")
            plan.free = message:find("FREEASSIGN YES", 1, true) == 1 or nil
            plan.status =
                { symbols = math.min(tonumber(symbols), SYMBOLS_TOP), loh = PPAEnds(loh), di = PPAEnds(di) }
        end
        RenewPage()
    end

    function QueryPP()
        local medium = TalkAim()
        if not medium or InCombatLockdown() then return end
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
        if ask then C_ChatInfo.SendAddonMessage(PPA_LEAD, "REQ", medium) end
    end
end

local PostReport, REPORT_TARGETS
do
    -------------------------------------------------------------------------------
    --  Report to chat
    -------------------------------------------------------------------------------
    local LINES_TOP = 240
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
        for _, calling in ipairs(CALLING_ROSTER) do
            local id = plan.classes[calling]
            if id then
                if not byBlessing[id] then
                    byBlessing[id] = {}
                    sequence[#sequence + 1] = id
                end
                table.insert(byBlessing[id], CallingLabel(calling))
            end
        end
        local parts = {}
        for _, id in ipairs(sequence) do
            parts[#parts + 1] = TitleOfSpell(id) .. " (" .. table.concat(byBlessing[id], ", ") .. ")"
        end
        if plan.aura then parts[#parts + 1] = TitleOfSpell(plan.aura) end
        return #parts > 0 and table.concat(parts, ", ") or "Nothing"
    end

    local function SplitRoster(labelValue, result)
        while #labelValue > LINES_TOP do
            local comma = labelValue:sub(1, LINES_TOP):match("^.*(), ")
            result[#result + 1] = labelValue:sub(1, comma and comma - 1 or LINES_TOP)
            labelValue = "  " .. labelValue:sub(comma and comma + 2 or LINES_TOP + 1)
        end
        result[#result + 1] = labelValue
    end

    local function ReportLabel()
        local plans = {}
        if PaladinUnit() then plans[1] = { who = MineTitle(), plan = Keep() } end
        local titleRoster = {}
        for who in pairs(others) do
            titleRoster[#titleRoster + 1] = who
        end
        table.sort(titleRoster)
        for _, who in ipairs(titleRoster) do
            plans[#plans + 1] = { who = who, plan = others[who] }
        end
        if #plans == 0 then return end
        local lines = { "--- Paladin blessings ---" }
        for _, log in ipairs(plans) do
            SplitRoster(Ambiguate(log.who, "short") .. ": " .. HasBlessing(log.plan), lines)
        end
        lines[#lines + 1] = "--- End of blessings ---"
        return lines
    end

    function PostReport(medium)
        if InCombatLockdown() then return Print("Reports are sent outside combat.") end
        local lines = ReportLabel()
        if not lines then return Print("There are no paladins to report.") end
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        for _, line in ipairs(lines) do
            if medium == "SELF" then
                Print(line)
            else
                send(line, medium)
            end
        end
    end
end

local PaladinRoster, AutoAssign, UsePlans, PresetRoster, PlanAllAllowed, KeepPreset, UsePreset, RestartAll, AssignFor
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

    function PaladinRoster()
        local items = {}
        if PaladinUnit() then
            local known = {}
            for _, log in ipairs(BLESSING_ROSTER) do
                if OnTrained(log) then known[log.key] = true end
            end
            for _, log in ipairs(AURA_ROSTER) do
                if OnTrained(log) then known[log.key] = true end
            end
            items[1] = { who = MineTitle(), known = known, you = true }
        end
        for who, plan in pairs(others) do
            items[#items + 1] = { who = who, known = plan.known, fixed = plan.pallyPower and plan or nil }
        end
        for _, p in ipairs(items) do
            p.count = 0
            for _ in pairs(p.known) do
                p.count = p.count + 1
            end
        end
        table.sort(items, function(lhs, rhs)
            if lhs.count ~= rhs.count then return lhs.count < rhs.count end
            return lhs.who < rhs.who
        end)
        return items
    end

    local function Choose(paladins, desired, give)
        local free = {}
        for _, p in ipairs(paladins) do
            free[#free + 1] = p
        end
        for _, id in ipairs(desired) do
            for catalog, p in ipairs(free) do
                if p.known[id] then
                    give(p, id)
                    table.remove(free, catalog)
                    break
                end
            end
        end
    end

    local function Unclaimed(desired, fixed, given)
        local result = {}
        for _, id in ipairs(desired) do
            local taken = false
            for _, plan in ipairs(fixed) do
                if given(plan) == id then taken = true end
            end
            if not taken then result[#result + 1] = id end
        end
        return result
    end

    function AutoAssign()
        local paladins, fixed = {}, {}
        for _, p in ipairs(PaladinRoster()) do
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
        for _, calling in ipairs(CALLING_ROSTER) do
            local desired = Unclaimed(DESIRED_STATES[calling], fixed, function(plan) return plan.classes[calling] end)
            Choose(paladins, desired, function(profile, id) plans[profile.who].classes[calling] = id end)
        end
        local auras = Unclaimed(AURA_SEQUENCE, fixed, function(plan) return plan.aura end)
        Choose(paladins, auras, function(profile, id) plans[profile.who].aura = id end)
        return plans
    end

    function UsePlans(plans)
        local storage = Keep()
        for who, plan in pairs(plans) do
            if who == MineTitle() then
                storage.classes = {}
                for calling, id in pairs(plan.classes) do
                    storage.classes[calling] = id
                end
                storage.aura = plan.aura
                AnnounceSoon()
            elseif others[who] and not others[who].pallyPower then
                TransmitPlan(who, plan.classes, plan.aura)
            end
        end
        OnChange()
    end

    function PresetRoster()
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

    function KeepPreset()
        local paladins = PaladinRoster()
        if #paladins == 0 then return false end
        local preset = {}
        for _, p in ipairs(paladins) do
            local plan = p.you and Keep() or others[p.who]
            local callings = {}
            for calling, id in pairs(plan.classes) do
                callings[calling] = id
            end
            preset[p.who] = { classes = callings, aura = plan.aura }
        end
        F.Cfg().preset = preset
        return true
    end

    function UsePreset()
        local plans = {}
        for _, p in ipairs(PaladinRoster()) do
            local saved = PresetRoster()[p.who]
            if saved and not p.fixed then
                local plan = { classes = {} }
                for calling, id in pairs(saved.classes or {}) do
                    if p.known[id] then plan.classes[calling] = id end
                end
                plan.aura = saved.aura and p.known[saved.aura] and saved.aura or nil
                plans[p.who] = plan
            end
        end
        UsePlans(plans)
        return next(plans) ~= nil
    end

    function RestartAll()
        local plans = {}
        for _, p in ipairs(PaladinRoster()) do
            plans[p.who] = { classes = {} }
        end
        if PaladinUnit() then Keep().players = {} end
        UsePlans(plans)
    end

    function AssignFor(who, colour, id)
        local plan = others[who]
        if not plan then return end
        if colour == AURA_COL then
            plan.aura = id
        else
            plan.classes[colour] = id
        end
        TransmitPlan(who, plan.classes, plan.aura)
    end
end

-------------------------------------------------------------------------------
--  Look
-------------------------------------------------------------------------------
local TINT_CRIMSON = { r = 0.97, g = 0.27, b = 0.27 }
local TINT_GOLDEN = { r = 1, g = 0.85, b = 0.3 }
local TINT_BLUE = { r = 0.35, g = 0.6, b = 1 }
local GLYPH_TRIM = 0.08
local LABEL_TYPEFACE, LABEL_DROP_Y, LABEL_PAD, LABEL_COL = 10, 2, 3, 46
local function Typeface() return CUI.GetFontPath("essentials") end

local Skin = { rows = 1 }

local function SkinGlyph(widget)
    widget.edge = widget:CreateTexture(nil, "BACKGROUND")
    widget.edge:SetAllPoints()
    widget.edge:SetColorTexture(0, 0, 0, 1)
    widget.icon = widget:CreateTexture(nil, "ARTWORK")
    widget.icon:SetPoint("TOPLEFT", 1, -1)
    widget.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    widget.icon:SetTexCoord(GLYPH_TRIM, 1 - GLYPH_TRIM, GLYPH_TRIM, 1 - GLYPH_TRIM)
    widget.mark = widget:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(widget.mark, 14, "essentials")
    widget.mark:SetPoint("CENTER")
    widget.mark:SetTextColor(TINT_CRIMSON.r, TINT_CRIMSON.g, TINT_CRIMSON.b)
    widget.timer = widget:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(widget.timer, 10, "essentials")
    widget.timer:SetPoint("BOTTOM", 0, 1)
end

local function SkinLoad()
    Skin.size, Skin.gap, Skin.groupGap = Get("size"), Get("spacing"), Get("groupGap")
    Skin.timerSize, Skin.labels, Skin.vertical = Get("timerSize"), Get("labels"), Get("vertical")
    Skin.perRow, Skin.rows = math.max(1, Get("perRow")), 1
    Skin.border = Get("border")
end

local function LabelWidth()
    if not Skin.labels then return 0 end
    if Skin.vertical then return LABEL_PAD + LABEL_COL end
    return LABEL_DROP_Y + LABEL_TYPEFACE
end

local function LINE_SPACING_FOR() return Skin.size + Skin.gap + LabelWidth() end

local function SkinMarker(widget, barWindow, posX, posY)
    widget:ClearAllPoints()
    if Skin.vertical then
        widget:SetPoint("TOPLEFT", barWindow, "TOPLEFT", posY or 0, -posX)
    else
        widget:SetPoint("BOTTOMLEFT", barWindow, "BOTTOMLEFT", posX, posY or 0)
    end
end

local function SkinPlace(widget, barWindow, posX, posY)
    local dims = Skin.size
    widget:SetSize(dims, dims)
    CUI.Kit.Font(widget.timer, Skin.timerSize, "essentials")
    if widget.watchText then CUI.Kit.Font(widget.watchText, Skin.timerSize, "essentials") end
    widget.edge:SetShown(Skin.border ~= "none")
    if widget.label then
        widget.label:SetShown(Skin.labels)
        widget.label:ClearAllPoints()
        if Skin.vertical then
            widget.label:SetPoint("LEFT", widget, "RIGHT", LABEL_PAD, 0)
            widget.label:SetWidth(Skin.rows > 1 and LABEL_COL or 0)
        else
            widget.label:SetPoint("TOP", widget, "BOTTOM", 0, -LABEL_DROP_Y)
            widget.label:SetWidth(dims + Skin.gap)
        end
    end
    SkinMarker(widget, barWindow, posX, posY)
    widget:Show()
    return posX + dims + Skin.gap
end

local function MinutesLabel(seconds)
    if not (seconds and seconds > 0 and Get("timers")) then return "" end
    return math.ceil(seconds / 60) .. "m"
end

local function SkinCalling(cell, colour, reachable, missing, shortest)
    local status = Skin.border == "status"
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
    cell.timer:SetText(MinutesLabel(shortest))
end

local function SkinSelf(widget, missing, remaining)
    widget.icon:SetVertexColor(missing and TINT_CRIMSON.r or 1, missing and TINT_CRIMSON.g or 1, missing and TINT_CRIMSON.b or 1)
    widget.mark:SetText(missing and "!" or "")
    widget.timer:SetText(MinutesLabel(remaining))
end

local function SkinStatus(widget, id, has, remaining)
    local missing = id ~= nil and (widget.watch ~= nil or has == false)
    SkinSelf(widget, missing, not widget.watch and remaining)
end

local function SkinFit(widget, posX)
    local across = Skin.size + (Skin.rows - 1) * LINE_SPACING_FOR()
    local along = math.max(posX - Skin.gap, Skin.size)
    if Skin.vertical then
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
    local success, boxBox = pcall(function()
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
        local c = CreateFrame("AuraContainer", nil, widget, "CustomAuraContainerTemplate")
        c:SetAllPoints(widget)
        c:SetFrameLevel(widget:GetFrameLevel() + 2)
        c:EnableMouse(false)
        c:AddAuraSlot("buff", "HELPFUL", {
            candidateFilters = { includeSpellIDs = {} },
            initializeFrame = function(btnWindow)
                btnWindow:SetAllPoints(widget.icon)
                btnWindow:EnableMouse(false)
                local glyphTex = btnWindow:CreateTexture(nil, "ARTWORK")
                glyphTex:SetAllPoints()
                glyphTex:SetTexCoord(GLYPH_TRIM, 1 - GLYPH_TRIM, GLYPH_TRIM, 1 - GLYPH_TRIM)
                btnWindow:SetIcon(glyphTex)
                local labelValue = btnWindow:CreateFontString(nil, "OVERLAY")
                CUI.Kit.Font(labelValue, Get("timerSize"), "essentials")
                widget.watchText = labelValue
                labelValue:SetPoint("BOTTOM", 0, 1)
                btnWindow:SetDurationText(labelValue, {})
            end,
        })
        c:SetEnabled(false)
        return c
    end)
    if not success then
        watchUnavailable = true
        return
    end
    widget.watch = boxBox
end

local function WatchUnits(widget, unitToken, id)
    local c = widget.watch
    if not c or (widget.watchUnit == unitToken and widget.watchKey == id) then return end
    widget.watchUnit, widget.watchKey = unitToken, id
    c:SetUnit(unitToken or "none")
    c:SetAuraSlotCandidateFilters("buff", { includeSpellIDs = id and SPELL_IDS[id] or {} })
    c:SetEnabled(unitToken ~= nil and id ~= nil)
end

-------------------------------------------------------------------------------
--  A secure button that follows one named player through raid reordering,
--  even in combat
-------------------------------------------------------------------------------
local function AimFor(hostWindow, name)
    local heading = CreateFrame("Frame", name, hostWindow, "SecureGroupHeaderTemplate")
    heading:SetAttribute("template", "CludesUIBlessButtonTemplate")
    heading:SetAttribute("showPlayer", true)
    heading:SetAttribute("showParty", true)
    heading:SetAttribute("showRaid", true)
    heading:SetAttribute("showSolo", true)
    heading:SetAttribute("nameList", NO_ONE)
    heading:SetAttribute("sortMethod", "NAMELIST")
    heading:SetAttribute("point", "TOPLEFT")
    heading:SetAttribute("unitsPerColumn", 1)
    heading:SetAttribute("maxColumns", 1)
    heading:SetPoint("TOPLEFT", hostWindow, "TOPLEFT")
    heading:Show()
    local btnWindow = heading:GetAttribute("child1")
    btnWindow:RegisterForClicks("AnyUp", "AnyDown")
    btnWindow:SetAttribute("type1", "spell")
    return heading, btnWindow
end

local function AssignNames(heading, titleRoster)
    if heading:GetAttribute("nameList") ~= titleRoster then heading:SetAttribute("nameList", titleRoster) end
end

local function AimDims(heading, btnWindow, dims)
    heading:SetAttribute("minWidth", dims)
    heading:SetAttribute("minHeight", dims)
    btnWindow:SetSize(dims, dims)
end

-------------------------------------------------------------------------------
--  Menus
-------------------------------------------------------------------------------
local RevealFrame, PeopleOf

local function AssignMine(colour, id)
    local storage = Keep()
    if colour == AURA_COL then
        storage.aura = id
    else
        storage.classes[colour] = id
    end
    AnnounceSoon()
    OnChange()
end

local function RevealMenuFor(ownerWindow, title, items, current, choose, noneLabel, can)
    can = can or OnTrained
    CUI.Kit.ContextMenu(ownerWindow, function(_, root)
        root:CreateTitle(title)
        for _, log in ipairs(items) do
            if can(log) then
                root:CreateRadio(
                    TitleOfSpell(log.key),
                    function() return current() == log.key end,
                    function() choose(log.key) end
                )
            end
        end
        root:CreateRadio(noneLabel, function() return current() == nil end, function() choose(nil) end)
    end)
end

local function UseSeal(id)
    Keep().seal = id
    OnChange()
end

local function RevealSealMenu(ownerWindow)
    RevealMenuFor(ownerWindow, "Seal", SEAL_ROSTER, function() return Keep().seal end, UseSeal, "Default")
end

local function RevealAuraMenu(ownerWindow)
    RevealMenuFor(
        ownerWindow,
        "Aura",
        AURA_ROSTER,
        function() return Keep().aura end,
        function(id) AssignMine(AURA_COL, id) end,
        "Default"
    )
end

local function MyBlessings(calling)
    local people, guids = Keep().players, {}
    for _, member in ipairs(GroupRoster()) do
        if member.class == calling and people[member.guid] then guids[#guids + 1] = member.guid end
    end
    return guids
end

local function RevealCallingMenu(ownerWindow, calling)
    CUI.Kit.ContextMenu(ownerWindow, function(_, root)
        root:CreateTitle(CallingLabel(calling))
        for _, log in ipairs(BLESSING_ROSTER) do
            if OnTrained(log) and (Keep().classes[calling] == log.key or MayCast(calling, log.key)) then
                root:CreateRadio(
                    TitleOfSpell(log.key),
                    function() return Keep().classes[calling] == log.key end,
                    function() AssignMine(calling, log.key) end
                )
            end
        end
        root:CreateRadio(
            "None",
            function() return Keep().classes[calling] == nil end,
            function() AssignMine(calling, nil) end
        )
        local own = MyBlessings(calling)
        if #own > 0 then
            root:CreateDivider()
            root:CreateTitle(
                #own == 1 and "1 player has their own blessing"
                    or ("%d players have their own blessing"):format(#own)
            )
            root:CreateButton("Give them the class blessing", function()
                local people = Keep().players
                for _, unitId in ipairs(own) do
                    people[unitId] = nil
                end
                AnnounceSoon()
                OnChange()
            end)
        end
        root:CreateDivider()
        if Get("playerList") then
            root:CreateCheckbox(
                "Players",
                function() return PeopleOf.Showing() == calling end,
                function() PeopleOf.Toggle(calling) end
            )
        end
        root:CreateButton("Assignments", function() RevealFrame() end)
    end)
end

local function RevealHint(widget, title, body)
    widget:HookScript("OnEnter", function(self)
        if not Get("tooltips") then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        local labelValue = type(body) == "function" and body() or body
        local ar, ag, ab = CUI.Kit.Accent()
        if labelValue and labelValue ~= "" then GameTooltip:AddLine(labelValue, ar, ag, ab, true) end
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
    local flyout, lineRoster, flyoutCalling
    local rosterMembers = {}
    PeopleOf = {}

    local function RevealPersonMenu(ownerWindow, member)
        local storage = Keep()
        local function Able(log)
            return OnTrained(log)
                and (storage.players[member.guid] == log.key or MayCast(member.class, log.key))
        end
        RevealMenuFor(
            ownerWindow,
            Ambiguate(member.who, "short"),
            BLESSING_ROSTER,
            function() return storage.players[member.guid] end,
            function(id)
                storage.players[member.guid] = id
                AnnounceSoon()
                OnChange()
            end,
            "Class default",
            Able
        )
    end

    local function BuildLine(catalog)
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
        SkinGlyph(row.slot)
        row.header, row.cast = AimFor(row.slot, "CludesUIBlessRow" .. catalog)
        AimDims(row.header, row.cast, 26)
        row.cast:SetAttribute("ctrl-type1", "maintank")
        row.cast:SetAttribute("ctrl-action1", "toggle")
        row.cast:SetScript("PostClick", function(self, btnWindow, down)
            if btnWindow == "RightButton" and not down and row.member then RevealPersonMenu(self, row.member) end
            if btnWindow == "LeftButton" then
                LogCast(self:GetAttribute("unit"), self:GetAttribute("spell1"))
            end
        end)
        RevealHint(
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

    local function RenderLine(row, member, storage)
        row.member = member
        local color = RAID_CLASS_COLORS[member.class]
        row.name:SetText(Ambiguate(member.who, "short"))
        row.name:SetTextColor(color.r, color.g, color.b)
        local own = storage.players[member.guid]
        local id = AssignedTo(member)
        row.note:SetText(own and TitleOfSpell(own) or "Class default")
        row.slot.icon:SetTexture(id and GlyphOfSpell(id) or ASK_CODE)
        AssignNames(row.header, member.names)
        row.cast:SetAttribute("spell1", id and TopTier(FROM_ID[id].ranks))
        WatchUnits(row.slot, member.unit, id)
        local has, remaining
        if id then
            has, remaining = BlessStatus(member.unit, id)
        end
        SkinStatus(row.slot, id, has, remaining)
    end

    function PeopleOf.Showing() return flyoutCalling end

    function PeopleOf.Build(barWindow)
        flyout = CreateFrame("Frame", nil, barWindow)
        flyout:SetPoint("BOTTOMLEFT", barWindow, "TOPLEFT", 0, 18)
        CUI.Kit.Panel(flyout, 0.9)
        flyout.title = flyout:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(flyout.title, 12, "essentials")
        CUI.Kit.AccentText(flyout.title)
        flyout.title:SetPoint("TOPLEFT", 8, -6)
        local shut = CUI.Kit.Glyph(flyout, "x", function() flyout:Hide() end, nil, "essentials")
        shut:SetSize(22, 22)
        shut:SetPoint("TOPRIGHT", -4, -4)
        shut:SetScript("OnClick", function() PeopleOf.Toggle(flyoutCalling) end)
        lineRoster = {}
        flyout:Hide()
    end

    function PeopleOf.Arrange(roster)
        wipe(rosterMembers)
        for _, member in ipairs(roster) do
            if member.class == flyoutCalling then rosterMembers[#rosterMembers + 1] = member end
        end
        if #rosterMembers == 0 or not Get("playerList") then flyoutCalling = nil end
        if not flyoutCalling then
            flyout:Hide()
            return
        end
        local storage = Keep()
        flyout:Show()
        for catalog, member in ipairs(rosterMembers) do
            local row = lineRoster[catalog] or BuildLine(catalog)
            lineRoster[catalog] = row
            RenderLine(row, member, storage)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 6, -26 - (catalog - 1) * 32)
            row:Show()
        end
        for catalog = #rosterMembers + 1, #lineRoster do
            AssignNames(lineRoster[catalog].header, NO_ONE)
            WatchUnits(lineRoster[catalog].slot, nil, nil)
            lineRoster[catalog]:Hide()
        end
        flyout.title:SetText(CallingLabel(flyoutCalling))
        flyout:SetSize(242, 30 + #rosterMembers * 32)
    end

    function PeopleOf.Toggle(calling)
        if InCombatLockdown() then
            Print("The player list opens after combat.")
            return
        end
        flyoutCalling = flyoutCalling ~= calling and calling or nil
        Update()
    end

    do
    end

    -------------------------------------------------------------------------------
    --  Key bindings: Next Blessing and Next Greater Blessing step through who
    --  needs one, most urgent first
    -------------------------------------------------------------------------------
    local ID_SPACING = [[
    local i, n = self:GetAttribute("step") or 1, self:GetAttribute("count") or 0
    if i > n then return false end
    self:SetAttribute("unit", self:GetAttribute("unit" .. i))
    self:SetAttribute("spell", self:GetAttribute("spell" .. i))
    self:SetAttribute("step", i + 1)
]]

    local idNext, idGreater
    K = {}

    local function BuildIdBtn(name, handler)
        local btn = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        btn:RegisterForClicks("AnyDown")
        btn:SetAttribute("useOnKeyDown", true)
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("count", 0)
        SecureHandlerWrapScript(btn, "OnClick", handler, ID_SPACING)
        btn:SetScript(
            "PostClick",
            function(self) LogCast(self:GetAttribute("unit"), self:GetAttribute("spell")) end
        )
        return btn
    end

    local function LineCasts(btn, items, kind)
        kind = kind or ""
        table.sort(items, UrgencySorter)
        for catalog, log in ipairs(items) do
            btn:SetAttribute("unit" .. kind .. catalog, log.unit)
            btn:SetAttribute("spell" .. kind .. catalog, log.spell)
        end
        btn:SetAttribute("count" .. kind, #items)
        btn:SetAttribute("step" .. kind, 1)
    end

    local function SingleBlessings(members, single, shared)
        for _, member in ipairs(members) do
            local id = AssignedTo(member)
            if id ~= shared then shared = nil end
            local spell = id and TopTier(FROM_ID[id].ranks)
            local tier, leftX = RequiresRecast(member, id, spell)
            if tier then
                single[#single + 1] = { unit = member.unit, spell = spell, rank = tier, left = leftX }
            end
        end
        return shared
    end

    local function NextGreater(members, shared, symbols)
        local spell = shared and symbols and TopTier(FROM_ID[shared].greater)
        if spell and not WaitTime(members, spell) then spell = nil end
        local top
        for _, member in ipairs(spell and members or {}) do
            local tier, leftX = RequiresRecast(member, shared, spell)
            if tier and (not top or UrgencySorter({ rank = tier, left = leftX }, top)) then
                top = { unit = member.unit, spell = spell, rank = tier, left = leftX }
            end
        end
        return top
    end

    function K.Build(handler)
        idNext = BuildIdBtn("CludesUIBlessNext", handler)
        idGreater = BuildIdBtn("CludesUIBlessNextGreater", handler)
    end

    function K.Peek()
        if not idNext then return end
        return idNext:GetAttribute("spell1") or idGreater:GetAttribute("spell1"),
            idNext:GetAttribute("count") or 0
    end

    function K.Clear()
        if idNext then idNext:SetAttribute("count", 0) end
        if idGreater then idGreater:SetAttribute("count", 0) end
        if idAuto then
            idAuto:SetAttribute("countN", 0)
            idAuto:SetAttribute("countG", 0)
        end
    end

    function K.Fill(byCalling)
        local single, greater = {}, {}
        local symbols = C_Item.GetItemCount(THING_SYMBOL) > 0
        for _, calling in ipairs(CALLING_ROSTER) do
            local members = byCalling[calling]
            if members then
                local shared = SingleBlessings(members, single, Keep().classes[calling])
                greater[#greater + 1] = NextGreater(members, shared, symbols)
            end
        end
        LineCasts(idNext, single)
        LineCasts(idGreater, greater)
        if idAuto then
            LineCasts(idAuto, single, "N")
            LineCasts(idAuto, greater, "G")
        end
    end
end

-------------------------------------------------------------------------------
--  The Blessing Bar
-------------------------------------------------------------------------------
local CALLING_SPACING = [[
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
local barWindow, cells, auraBtn, furyBtn, sealBtn, autoBtn, secureHandler
local dirty, ticker, makeLaterCombat
local renewQueued, landing, landingQueued, sentSymbols
local events = CreateFrame("Frame")
local Apply

local function SweepLine(cell, queue)
    local parts = {}
    for catalog, log in ipairs(queue) do
        parts[catalog] = log.names .. "=" .. log.spell
    end
    local signature = table.concat(parts, ";")
    if signature == cell.signature then return end
    cell.signature = signature
    for catalog, log in ipairs(queue) do
        cell.cast:SetAttribute("queueNames" .. catalog, log.names)
        cell.cast:SetAttribute("queueSpell" .. catalog, log.spell)
    end
    cell.cast:SetAttribute("count", #queue)
end

local function RenderCell(cell, cfg, id)
    local queue = cfg.queue
    local isShown = cfg.spell or (id and CastingSpell(id, cell.members))
    cell.icon:SetTexture(isShown and C_Spell.GetSpellTexture(isShown) or ASK_CODE)
    SweepLine(cell, queue)
    cell.cast:SetAttribute("step", 1)
    AssignNames(cell.header, queue[1] and queue[1].names or NO_ONE)
    cell.target, cell.queued = cfg.target, #queue
    local color = cfg.classMissing > 0 and TINT_CRIMSON
        or cfg.classDue > 0 and TINT_GOLDEN
        or cfg.missingNear + cfg.expiringNear > 0 and TINT_BLUE
        or nil
    SkinCalling(cell, color, cfg.reachable, cfg.missing, cfg.shortest)
end

local function ArmCell(cell) RenderCell(cell, SweepGroup(cell.members), Keep().classes[cell.class]) end

local function RevealCellHint(cell)
    local aim = cell.target and Ambiguate(cell.target.who, "short")
    return (aim and ("Left-click: bless %s.\n"):format(aim) or "")
        .. ((cell.queued or 0) > 1 and "In combat each click blesses the next who needed it.\n" or "")
        .. "Right-click: choose the blessing, the player list or assignments."
end

local function AurasSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
end

local function BuildCell(calling)
    local cell = CreateFrame("Frame", nil, barWindow)
    cell.class = calling
    SkinGlyph(cell)
    cell.label = cell:CreateFontString(nil, "OVERLAY")
    CUI.Kit.Font(cell.label, LABEL_TYPEFACE, "essentials")
    cell.label:SetWordWrap(false)
    cell.label:SetText(CallingLabel(calling))
    local color = RAID_CLASS_COLORS[calling]
    if color then cell.label:SetTextColor(color.r, color.g, color.b) end
    cell.header, cell.cast = AimFor(cell, "CludesUIBless" .. calling)
    cell.cast:RegisterForClicks("AnyUp")
    cell.cast:SetAttribute("useOnKeyDown", false)
    cell.cast:SetAttribute("count", 0)
    cell.cast:SetScript("PreClick", function(_, btnWindow)
        if
            btnWindow == "LeftButton"
            and not InCombatLockdown()
            and not (AurasSecret() and not AurasHidden())
        then
            ArmCell(cell)
        end
    end)
    SecureHandlerWrapScript(cell.cast, "OnClick", secureHandler, CALLING_SPACING)
    cell.cast:SetScript("PostClick", function(self, btnWindow, down)
        if btnWindow == "RightButton" and not down then RevealCallingMenu(self, calling) end
        if btnWindow == "LeftButton" then LogCast(self:GetAttribute("unit"), self:GetAttribute("spell1")) end
    end)
    RevealHint(cell.cast, CallingLabel(calling), function() return RevealCellHint(cell) end)
    return cell
end

local function ActiveAura()
    local id = Keep().aura
    if id and OnTrained(FROM_ID[id]) then return id end
    for _, log in ipairs(AURA_ROSTER) do
        if OnTrained(log) then return log.key end
    end
end

local function ActiveSeal()
    local id = Keep().seal
    if id and OnTrained(FROM_ID[id]) then return id end
    for _, log in ipairs(SEAL_ROSTER) do
        if OnTrained(log) then return log.key end
    end
end

local function Rotate(items, current, choose, delta)
    if InCombatLockdown() then return end
    local known = {}
    for _, log in ipairs(items) do
        if OnTrained(log) then known[#known + 1] = log.key end
    end
    if #known < 2 then return end
    local at = 1
    for catalog, id in ipairs(known) do
        if id == current() then at = catalog end
    end
    choose(known[(at - 1 + (delta > 0 and 1 or -1)) % #known + 1])
end

local function BuildBarBtn(name)
    local btn = CreateFrame("Button", name, barWindow, "SecureActionButtonTemplate")
    SkinGlyph(btn)
    return btn
end

local function BuildSelfBtn(name)
    local btn = BuildBarBtn(name)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type1", "spell")
    btn:SetAttribute("unit1", "player")
    Monitor(btn)
    return btn
end

local function BuildAutoBtn(name)
    local btn = BuildBarBtn(name)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetAttribute("type1", "spell")
    btn:SetAttribute("type2", "spell")
    btn:SetAttribute("countN", 0)
    btn:SetAttribute("countG", 0)
    SecureHandlerWrapScript(btn, "OnClick", secureHandler, AUTO_SPACING)
    btn:SetScript(
        "PostClick",
        function(self) LogCast(self:GetAttribute("unit"), self:GetAttribute("spell")) end
    )
    idAuto = btn
    return btn
end

local function ArmSeal(btn, id)
    local ident = FROM_ID[id].ranks[1]
    btn:SetAttribute("spell1", C_Spell.GetSpellName(ident))
    btn.icon:SetTexture(C_Spell.GetSpellTexture(ident))
    WatchUnits(btn, "player", id)
    SkinSelf(btn, false)
end

local function RenderAuto()
    if not autoBtn:IsShown() then return end
    local spell, due = K.Peek()
    autoBtn.icon:SetTexture(spell and C_Spell.GetSpellTexture(spell) or ASK_CODE)
    autoBtn.icon:SetDesaturated(due == 0)
    autoBtn.mark:SetText(due > 0 and due or "")
end

local function ArmSelf(btn, id)
    local spell = TopTier(FROM_ID[id].ranks)
    btn:SetAttribute("spell1", spell)
    btn.icon:SetTexture(C_Spell.GetSpellTexture(spell))
    WatchUnits(btn, "player", id)
    SkinStatus(btn, id, BlessStatus("player", id))
end

local function ArrangeSelf(posX)
    local aura = Get("showAura") and ActiveAura()
    if aura then
        ArmSelf(auraBtn, aura)
        posX = SkinPlace(auraBtn, barWindow, posX)
    else
        auraBtn:Hide()
    end
    if Get("showFury") and OnTrained(SPELL_FURY) then
        ArmSelf(furyBtn, "fury")
        posX = SkinPlace(furyBtn, barWindow, posX)
    else
        furyBtn:Hide()
    end
    local seal = Get("showSeal") and ActiveSeal()
    if seal then
        ArmSeal(sealBtn, seal)
        posX = SkinPlace(sealBtn, barWindow, posX)
    else
        sealBtn:Hide()
    end
    if Get("showAuto") then
        autoBtn:SetAttribute("leftKind", Get("autoGreater") and "G" or "N")
        posX = SkinPlace(autoBtn, barWindow, posX)
    else
        autoBtn:Hide()
    end
    if posX > 0 then return posX + Skin.groupGap end
    return posX
end

local function CallingSorter(roster)
    local byCalling = {}
    for _, member in ipairs(roster) do
        byCalling[member.class] = byCalling[member.class] or {}
        table.insert(byCalling[member.class], member)
    end
    return byCalling
end

local function WipeCell(cell)
    AssignNames(cell.header, NO_ONE)
    cell:Hide()
end

local function ArrangeCells(byCalling, posX)
    local total = 0
    for _, calling in ipairs(CALLING_ROSTER) do
        if byCalling[calling] then total = total + 1 end
    end
    Skin.rows = math.max(1, math.ceil(total / Skin.perRow))
    local done = posX + math.min(total, Skin.perRow) * (Skin.size + Skin.gap)
    local catalog = 0
    for _, calling in ipairs(CALLING_ROSTER) do
        local members = byCalling[calling]
        local cell = cells[calling]
        if members then
            cell = cell or BuildCell(calling)
            cells[calling] = cell
            cell.members = members
            AimDims(cell.header, cell.cast, Skin.size)
            SkinPlace(
                cell,
                barWindow,
                posX + catalog % Skin.perRow * (Skin.size + Skin.gap),
                math.floor(catalog / Skin.perRow) * LINE_SPACING_FOR()
            )
            catalog = catalog + 1
            ArmCell(cell)
        elseif cell then
            WipeCell(cell)
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
    if not barWindow then return end
    if InCombatLockdown() or (AurasSecret() and not AurasHidden()) then
        dirty = true
        return
    end
    dirty = false
    if not (On() and PaladinUnit() and (Desired() or CUI._unlockActive)) then
        barWindow:Hide()
        K.Clear()
        return
    end
    barWindow:Show()
    StartAuraJot()
    SkinLoad()
    local posX = ArrangeSelf(0)
    local roster = ShownNow(GroupRoster())
    local byCalling = CallingSorter(roster)
    if Get("showClasses") then
        posX = ArrangeCells(byCalling, posX)
    else
        for _, cell in pairs(cells) do
            WipeCell(cell)
        end
    end
    PeopleOf.Arrange(roster)
    K.Fill(byCalling)
    RenderAuto()
    HaltAuraJot()
    SkinFit(barWindow, posX)
    barWindow:SetShown(posX > 0 or CUI._unlockActive)
end

function OnChange()
    if Update then Update() end
    RenewPage()
end

local function SelfClicked(self, btnWindow)
    if btnWindow == "LeftButton" then LogCast(self:GetAttribute("unit1"), self:GetAttribute("spell1")) end
end

local function BuildBar()
    barWindow = CreateFrame("Frame", "CludesUIBlessingBar", UIParent)
    barWindow:SetClampedToScreen(true)
    barWindow:SetSize(Get("size"), Get("size"))
    cells = {}
    secureHandler = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    auraBtn = BuildSelfBtn("CludesUIBlessAura")
    auraBtn:SetScript("PostClick", function(self, btnWindow, down)
        SelfClicked(self, btnWindow)
        if btnWindow == "RightButton" and not down then RevealAuraMenu(self) end
    end)
    RevealHint(
        auraBtn,
        "Aura",
        "Left-click: cast your aura.\nRight-click: choose it. Wheel: cycle through your auras."
    )
    auraBtn:EnableMouseWheel(true)
    auraBtn:SetScript("OnMouseWheel", function(_, delta)
        Rotate(AURA_ROSTER, ActiveAura, function(id) AssignMine(AURA_COL, id) end, delta)
    end)
    furyBtn = BuildSelfBtn("CludesUIBlessFury")
    furyBtn:SetScript("PostClick", SelfClicked)
    RevealHint(
        furyBtn,
        C_Spell.GetSpellName(SPELL_FURY.ranks[1]) or "Righteous Fury",
        "Left-click: cast it on yourself."
    )
    sealBtn = BuildSelfBtn("CludesUIBlessSeal")
    sealBtn:SetScript("PostClick", function(self, btnWindow, down)
        if btnWindow == "RightButton" and not down then RevealSealMenu(self) end
    end)
    RevealHint(
        sealBtn,
        "Seal",
        "Left-click: cast your seal.\nRight-click: choose it. Wheel: cycle through your seals."
    )
    sealBtn:EnableMouseWheel(true)
    sealBtn:SetScript("OnMouseWheel", function(_, delta) Rotate(SEAL_ROSTER, ActiveSeal, UseSeal, delta) end)
    K.Build(secureHandler)
    autoBtn = BuildAutoBtn("CludesUIBlessAuto")
    RevealHint(
        autoBtn,
        "Auto Buff",
        "Left-click: the next blessing. Right-click: the next Greater Blessing. Each goes to whoever needs it most."
    )
    PeopleOf.Build(barWindow)
    if not CUI._unlockActive then F.Place(barWindow) end
end

local function RefreshSoon()
    if renewQueued then return end
    renewQueued = true
    C_Timer.After(RESCAN_WAIT, function()
        renewQueued = false
        Update()
    end)
end

local function RefreshLanded()
    if landingQueued then return end
    landingQueued = true
    C_Timer.After(0, function()
        landingQueued = false
        Update()
    end)
end

local function AuraAltered(unitToken)
    local fresh = landing and GetTime() - landing < LAND_GRACE
    if renewQueued and not fresh then return end
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
        local leadLabel, message, medium, sender = ...
        if Secret(leadLabel) or Secret(message) or Secret(medium) or Secret(sender) then return end
        if leadLabel == MSG_LEAD and GROUP_TARGETS[medium] then
            OnAddonMessage(message, sender)
        elseif leadLabel == PPA_LEAD and (GROUP_TARGETS[medium] or medium == "WHISPER") then
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
        RefreshSoon()
    elseif evt == "PARTY_LEADER_CHANGED" then
        RenewPage()
    elseif evt == "PLAYER_ROLES_ASSIGNED" then
        RefreshSoon()
    elseif evt == "PLAYER_REGEN_ENABLED" then
        if makeLaterCombat then
            makeLaterCombat = false
            Apply()
        elseif dirty then
            Update()
        end
        OutOfCombat()
    elseif evt == "SPELLS_CHANGED" then
        AnnounceSoon()
        RefreshSoon()
    elseif evt == "UNIT_SPELLCAST_SENT" then
        local _, _, castId, spellID = ...
        if Secret(castId) or Secret(spellID) or not SPELL_FAMILY[spellID] then return end
        OnCastSent(castId, spellID)
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castId, spellID = ...
        if Secret(spellID) then return end
        if STATUS_ABILITIES[spellID] then AnnounceSoon() end
        if Secret(castId) or not SPELL_FAMILY[spellID] then return end
        OnCastDone(castId)
        if not InCombatLockdown() then landing = GetTime() end
    elseif evt == "UNIT_HEALTH" then
        DropIfDead(...)
    elseif evt == "UNIT_AURA" then
        AuraAltered(...)
    end
end)

local function Ticked()
    if not (barWindow and barWindow:IsShown() and not InCombatLockdown()) then return end
    local symbols = C_Item.GetItemCount(THING_SYMBOL)
    if symbols ~= sentSymbols then
        sentSymbols = symbols
        AnnounceSoon()
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
        if barWindow and InCombatLockdown() then
            dirty = true
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
        elseif barWindow then
            barWindow:Hide()
            K.Clear()
        end
        return
    end
    C_ChatInfo.RegisterAddonMessagePrefix(MSG_LEAD)
    C_ChatInfo.RegisterAddonMessagePrefix(PPA_LEAD)
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
    if not barWindow and InCombatLockdown() then
        makeLaterCombat = true
        return
    end
    if not barWindow then BuildBar() end
    ticker = C_Timer.NewTicker(TICK_SECONDS, Ticked)
    Update()
end

do
    -------------------------------------------------------------------------------
    --  The assignments window (/cbless)
    -------------------------------------------------------------------------------
    local FRAME_W, FRAME_H = 640, 470
    local CELL_DIMS, SPACING, TITLE_WIDTH = 32, 6, 150
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
    local function AskConfirm(labelValue, func)
        local dialog = StaticPopup_Show("CUI_BLESS_CONFIRM", labelValue)
        if dialog then dialog.data = func end
    end

    local function MayCastOn()
        if PlanAllAllowed() then return true end
        Print("Only the group leader or an assistant can plan every paladin's blessings.")
    end

    local function FrameThing(kind)
        winUsed = winUsed + 1
        local item = winPool[winUsed]
        if item and item.kind ~= kind then
            item:Hide()
            item = nil
        end
        if not item then
            if kind == "cell" then
                item = CreateFrame("Button", nil, winContent)
                item:SetSize(CELL_DIMS, CELL_DIMS)
                SkinGlyph(item)
                item:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.title or "", 1, 1, 1)
                    local ar, ag, ab = CUI.Kit.Accent()
                    if self.body then GameTooltip:AddLine(self.body, ar, ag, ab, true) end
                    GameTooltip:Show()
                end)
                item:SetScript("OnLeave", function() GameTooltip:Hide() end)
            else
                item = CreateFrame("Frame", nil, winContent)
                item:SetSize(1, 1)
                item.text = item:CreateFontString(nil, "OVERLAY")
                item.text:SetPoint("TOPLEFT")
                item.text:SetJustifyH("LEFT")
            end
            item.kind = kind
            local old = winPool[winUsed]
            if old then old:Hide() end
            winPool[winUsed] = item
        end
        item:ClearAllPoints()
        item:Show()
        return item
    end

    local function FrameLabel(posX, posY, labelValue, dims, colour, width)
        local item = FrameThing("text")
        item:SetPoint("TOPLEFT", winContent, "TOPLEFT", posX, posY)
        CUI.Kit.Font(item.text, dims or 12, "essentials")
        item.text:SetTextColor(unpack(colour or { 1, 1, 1 }))
        item.text:SetWidth(width or 0)
        item.text:SetWordWrap(width ~= nil)
        item.text:SetText(labelValue)
        return item.text:GetStringHeight()
    end

    local function FrameCell(posX, posY, glyphTex, lit, title, body, onClick)
        local btn = FrameThing("cell")
        btn:SetPoint("TOPLEFT", winContent, "TOPLEFT", posX, posY)
        btn.icon:SetTexture(glyphTex)
        btn.icon:SetDesaturated(not lit)
        btn.icon:SetAlpha(lit and 1 or 0.35)
        btn.icon:SetVertexColor(1, 1, 1)
        btn.mark:SetText("")
        btn.timer:SetText("")
        btn.title, btn.body = title, body
        btn:SetScript("OnClick", onClick)
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

    local function LineRoster(roster)
        local lead = AssignAllowed("player")
        local items = {}
        if PaladinUnit() then
            local storage = Keep()
            items[1] = {
                who = MineTitle(),
                you = true,
                plan = storage,
                players = storage.players,
                can = OnTrained,
                set = AssignMine,
            }
        end
        local mayFree = PaladinUnit()
        local titleRoster = {}
        for who in pairs(others) do
            titleRoster[#titleRoster + 1] = who
        end
        table.sort(titleRoster)
        for _, who in ipairs(titleRoster) do
            local plan = others[who]
            items[#items + 1] = {
                who = who,
                plan = plan,
                players = plan.players,
                can = function(log) return plan.known[log.key] end,
                set = not plan.pallyPower and (lead or (mayFree and plan.free)) and function(colour, id)
                    AssignFor(who, colour, id)
                    RenewPage()
                end,
            }
        end
        for _, member in ipairs(roster) do
            if member.class == "PALADIN" and member.guid ~= UnitGUID("player") and not others[member.who] then
                items[#items + 1] = { who = member.who }
            end
        end
        return items
    end

    local function MyRoster(roster, people, calling)
        local result = {}
        for _, member in ipairs(roster) do
            local id = member.class == calling and people and people[member.guid]
            if id then result[#result + 1] = Ambiguate(member.who, "short") .. ": " .. TitleOfSpell(id) end
        end
        return #result > 0 and ("\n" .. table.concat(result, "\n")) or ""
    end

    local function Repaint()
        redrawQueued = false
        if not (window and window:IsShown()) then return end
        for catalog = 1, winUsed do
            winPool[catalog]:Hide()
        end
        winUsed = 0
        local posY = -4
        local roster = GroupRoster()
        local columns = {}
        for _, calling in ipairs(CALLING_ROSTER) do
            columns[#columns + 1] = calling
        end
        columns[#columns + 1] = AURA_COL
        for catalog, colour in ipairs(columns) do
            local aura = colour == AURA_COL
            FrameCell(
                TITLE_WIDTH + (catalog - 1) * (CELL_DIMS + SPACING),
                posY,
                aura and GlyphOfSpell("devotion")
                    or ("Interface\\Icons\\ClassIcon_" .. colour:lower():gsub("^%l", string.upper)),
                true,
                aura and "Aura" or CallingLabel(colour)
            )
        end
        posY = posY - CELL_DIMS - 10
        local items = LineRoster(roster)
        if #items == 0 then
            FrameLabel(0, posY, "No paladins in your group.", 12, { 0.6, 0.65, 0.7 })
            posY = posY - 20
        end
        for _, row in ipairs(items) do
            FrameLabel(
                0,
                posY - 4,
                Ambiguate(row.who, "short") .. (row.you and "  (you)" or ""),
                13,
                { 0.96, 0.55, 0.73 },
                TITLE_WIDTH - 10
            )
            if row.plan then
                FrameLabel(0, posY - 20, StatusLabel(row), 10, { 0.6, 0.65, 0.7 }, TITLE_WIDTH - 10)
                for catalog, colour in ipairs(columns) do
                    local aura = colour == AURA_COL
                    local id = aura and row.plan.aura or row.plan.classes[colour]
                    local title = aura and "Aura" or CallingLabel(colour)
                    local onClick = row.set
                        and function(btn)
                            local function Able(log)
                                return row.can(log)
                                    and (aura or id == log.key or MayCast(colour, log.key))
                            end
                            RevealMenuFor(
                                btn,
                                title,
                                aura and AURA_ROSTER or BLESSING_ROSTER,
                                function() return aura and row.plan.aura or row.plan.classes[colour] end,
                                function(choice) row.set(colour, choice) end,
                                "None",
                                Able
                            )
                        end
                    FrameCell(
                        TITLE_WIDTH + (catalog - 1) * (CELL_DIMS + SPACING),
                        posY,
                        id and GlyphOfSpell(id) or ASK_CODE,
                        id ~= nil,
                        title,
                        (id and TitleOfSpell(id) or "Nothing assigned")
                            .. (aura and "" or MyRoster(roster, row.players, colour))
                            .. (
                                onClick and "\nClick to change."
                                or row.plan.pallyPower and "\nPlanned in PallyPower."
                                or ""
                            ),
                        onClick
                    )
                end
            else
                FrameLabel(
                    TITLE_WIDTH,
                    posY - 10,
                    "No reply: blessings addon off or not installed",
                    12,
                    { 0.6, 0.65, 0.7 }
                )
            end
            posY = posY - CELL_DIMS - SPACING
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

    function RenewPage()
        if redrawQueued or not (window and window:IsShown()) then return end
        redrawQueued = true
        C_Timer.After(0, Repaint)
    end

    local function FrameBtn(hostWindow, labelValue, posX, onClick, hintLabel)
        local b =
            CUI.Kit.Button(hostWindow, labelValue, 96, 22, onClick, { key = "essentials", tip = hintLabel })
        b:SetPoint("TOPLEFT", posX, -34)
        return b
    end

    local function BuildFrame()
        window = CreateFrame("Frame", "CludesUIBlessings", UIParent)
        window:SetSize(FRAME_W, FRAME_H)
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
        local shut = CUI.Kit.Glyph(window, "x", function() window:Hide() end, nil, "essentials")
        shut:SetPoint("TOPRIGHT", -5, -5)
        FrameBtn(window, "Auto-Assign", 10, function()
            if MayCastOn() then
                AskConfirm(
                    "Replace every paladin's blessings and auras with an automatic plan?",
                    function() UsePlans(AutoAssign()) end
                )
            end
        end, "A plan for every paladin in the group, by what each has learned.")
        FrameBtn(window, "Load Preset", 110, function()
            if not next(PresetRoster()) then return Print("No preset saved yet.") end
            if MayCastOn() then
                AskConfirm("Load the saved preset for the paladins here now?", function()
                    if not UsePreset() then Print("Nobody in the preset is in your group.") end
                end)
            end
        end)
        FrameBtn(window, "Save Preset", 210, function()
            if #PaladinRoster() == 0 then return Print("No paladins to save a plan for.") end
            local function Persist()
                if KeepPreset() then Print("Blessings preset saved.") end
            end
            if next(PresetRoster()) then
                AskConfirm("Replace the saved preset?", Persist)
            else
                Persist()
            end
        end, "Saves the plan below to load again with this group.")
        FrameBtn(window, "Report", 310, function(self)
            CUI.Kit.ContextMenu(self, function(_, root)
                root:CreateTitle("Report the blessings to")
                for _, medium in ipairs(REPORT_TARGETS) do
                    if medium.can() then
                        root:CreateButton(medium.label, function() PostReport(medium.key) end)
                    end
                end
            end)
        end)
        FrameBtn(window, "Clear", 410, function()
            if MayCastOn() then
                AskConfirm("Clear every paladin's blessings and auras?", function()
                    RestartAll()
                    RenewPage()
                end)
            end
        end)
        FrameBtn(window, "Refresh", 510, function()
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
        winContent:SetSize(FRAME_W - 44, 10)
        winScroll:SetScrollChild(winContent)
        window.foot = window:CreateFontString(nil, "OVERLAY")
        CUI.Kit.Font(window.foot, 11, "essentials")
        window.foot:SetTextColor(0.6, 0.65, 0.7)
        window.foot:SetPoint("BOTTOMLEFT", 10, 8)
        window:Hide()
        tinsert(UISpecialFrames, "CludesUIBlessings")
    end

    function RevealFrame()
        if not window then BuildFrame() end
        window:Show()
        Repaint()
    end

    local function FlipFrame()
        if window and window:IsShown() then
            window:Hide()
        else
            RevealFrame()
        end
    end

    SLASH_CUIBLESS1 = "/cbless"
    SlashCmdList.CUIBLESS = function()
        if not On() then
            Print("turn on Blessings in CludesUI Forever Tools first.")
            return
        end
        FlipFrame()
    end
end

CUI._Blessings = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Open = RevealFrame,
    ClassBlessing = function(calling) return Keep().classes[calling] end,
    SetClassBlessing = function(calling, id) AssignMine(calling, id) end,
    Blessings = BLESSING_ROSTER,
    SpellName = TitleOfSpell,
    Learned = OnTrained,
    Classes = CALLING_ROSTER,
    ClassName = CallingLabel,
}

F.Start(Apply, {
    key = "CUI_BlessingBar",
    label = "Blessing Bar",
    order = 755,
    shown = function() return F.Enabled() and PaladinUnit() end,
    frame = function(make)
        if make and not barWindow and not InCombatLockdown() then
            BuildBar()
            Update()
        end
        return barWindow
    end,
    size = function()
        return barWindow and barWindow:GetWidth() or Get("size"),
            barWindow and barWindow:GetHeight() or Get("size")
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
