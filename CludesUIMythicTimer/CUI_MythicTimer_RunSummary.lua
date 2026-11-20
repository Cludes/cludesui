if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CUI_MythicTimer_RunSummary.lua -- Run Summary (Mythic+ Tools): end-of-key
--  overview with one row per party member, plus a per character history of
--  finished runs (/ov). Nothing is registered or built until enabled.
--  Sources: C_ChallengeMode for the run and the local player's score delta,
--  C_DamageMeter for every per player combat number (no combat log in
--  Midnight), rating summaries sampled before and after for party score gain.
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...

local saved -- Lite DB handle, handed over by ns.RS_OnEnable

local SV_NAME = "CludesUIMythicRunsDB"
local SCHEMA = 1

local UNIT_TOKENS = { "player", "party1", "party2", "party3", "party4" }

local DM_TYPE = Enum and Enum.DamageMeterType
local DM_SESSION = Enum and Enum.DamageMeterSessionType
local SESSION_OVERALL = DM_SESSION and DM_SESSION.Overall

-- Interrupts and deaths arrive as totalAmount under their own meter type;
-- there is no count field on a combat source.
local METRICS = {
    { key = "damage", dmType = DM_TYPE and DM_TYPE.DamageDone },
    { key = "damageTaken", dmType = DM_TYPE and DM_TYPE.DamageTaken },
    -- A demon's kicks are its warlock's (PetOwner).
    { key = "interrupts", dmType = DM_TYPE and DM_TYPE.Interrupts, pets = true },
    -- One source row per death, most recent first; a real death carries a
    -- deathRecapID and totalAmount is not a count, so rows are counted.
    { key = "deaths", dmType = DM_TYPE and DM_TYPE.Deaths, countRows = true },
}

-- Declared up here rather than with the rest of the collector state: the meter
-- harvest below banks class and spec onto it and must see it as an upvalue.
local roster -- [guid] = member record

local ShowWindow -- assigned further down, once the panel is defined
local RefreshWindowIfOpen -- same
local ApplyPosition -- same

--------------------------------------------------------------------------------
--  Small helpers
--------------------------------------------------------------------------------
local function Cfg()
    local profile = saved and saved.profile
    return profile and profile.runSummary
end

local function Enabled()
    local cfg = Cfg()
    return cfg and cfg.enabled == true
end

local IsSecret, PlainString = CludesUI.IsSecret, CludesUI.PlainString

local function PlainNumber(v)
    if type(v) == "number" and not IsSecret(v) then
        return v
    end
    return nil
end

--------------------------------------------------------------------------------
--  Store: a per character SavedVariable, deliberately NOT the profile DB.
--  CUILite's logout StripDefaults pass and the profile export/import machinery
--  both treat profile data as settings, so run records do not belong there.
--  Same split as CludesUIChat's scrollback history.
--------------------------------------------------------------------------------
local function GetSV()
    local savedVars = _G[SV_NAME]
    if type(savedVars) ~= "table" then
        savedVars = {}
        _G[SV_NAME] = savedVars
    end
    if type(savedVars.runs) ~= "table" then
        savedVars.runs = {}
    end
    -- Stamped only when absent. Writing it on every read would relabel older
    -- records as current and leave a future migration nothing to branch on.
    if savedVars.schema == nil then
        savedVars.schema = SCHEMA
    end
    return savedVars
end

local function HistorySize()
    local cfg = Cfg()
    local num = cfg and tonumber(cfg.historySize) or 20
    if num < 5 then
        num = 5
    elseif num > 50 then
        num = 50
    end
    return num
end

-- The run history other modules read (the data bar's M+ Summary block): Get,
-- Clear, and OnChanged, which a reader sets to hear of a stored or cleared
-- run. Internal, not a public API.
CludesUI._MythicRuns = {}

-- A reader's error is reported, never passed on: StoreRun's caller still sets
-- up the meter retries after it.
local function NotifyRunsChanged()
    local func = CludesUI._MythicRuns.OnChanged
    if func then
        xpcall(func, geterrorhandler())
    end
end

local function StoreRun(runRecord)
    if type(runRecord) ~= "table" then
        return
    end
    local savedVars = GetSV()
    table.insert(savedVars.runs, 1, runRecord)
    local cap = HistorySize()
    for i = #savedVars.runs, cap + 1, -1 do
        savedVars.runs[i] = nil
    end
    NotifyRunsChanged()
end

function mod.RS_GetRuns()
    return GetSV().runs
end

-- Stored runs, newest first, or nil. Read only: never creates the SavedVariable.
function CludesUI._MythicRuns.Get()
    local savedVars = _G[SV_NAME]
    local runs = type(savedVars) == "table" and savedVars.runs
    return type(runs) == "table" and runs or nil
end

function mod.RS_ClearHistory()
    local savedVars = GetSV()
    wipe(savedVars.runs)
    if RefreshWindowIfOpen then
        RefreshWindowIfOpen()
    end
    NotifyRunsChanged()
end
CludesUI._MythicRuns.Clear = mod.RS_ClearHistory

-- Season purge: drop records for dungeons that are no longer in the pool, the
-- same shape EMT:OnInitialize already uses for bestObjectiveSplits.
local function PurgeOldSeasons()
    local savedVars = _G[SV_NAME]
    if type(savedVars) ~= "table" or type(savedVars.runs) ~= "table" then
        return
    end
    local maps = C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()
    if type(maps) ~= "table" or #maps == 0 then
        return
    end
    local valid = {}
    for _, mapID in ipairs(maps) do
        valid[mapID] = true
    end
    for i = #savedVars.runs, 1, -1 do
        local runRec = savedVars.runs[i]
        local mapID = runRec and tonumber(runRec.mapID)
        if not mapID or not valid[mapID] then
            table.remove(savedVars.runs, i)
        end
    end
end

--------------------------------------------------------------------------------
--  C_DamageMeter harvest. Every GetCombatSession* call is SecretWhenInCombat
--  and declassification lags regen, so every field is guarded and the caller
--  retries once. Overall totals are diffed against a baseline taken at key
--  start rather than trusted to be empty: CludesUIDamageMeters resets the
--  sessions on CHALLENGE_MODE_START and may simply not be loaded.
--------------------------------------------------------------------------------
local function MeterAvailableIsTrue()
    return C_DamageMeter.IsDamageMeterAvailable() == true
end

local function MeterReady()
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        return false
    end
    if SESSION_OVERALL == nil then
        return false
    end
    if not C_DamageMeter.IsDamageMeterAvailable then
        return true
    end
    -- The truthiness test runs inside the pcall so a raise cannot take the
    -- whole harvest with it.
    local success, ready = pcall(MeterAvailableIsTrue)
    return success and ready == true
end

-- The pet units and the units that own them.
local PET_OWNER_UNIT = {
    pet = "player",
    partypet1 = "party1",
    partypet2 = "party2",
    partypet3 = "party3",
    partypet4 = "party4",
}

-- The classes whose interrupt a demon casts (Spell Lock, Axe Toss).
local PET_KICK_CLASS = {}
for _, kick in pairs(CludesUI.KickData.INTERRUPTS) do
    if kick.pet then
        PET_KICK_CLASS[kick.class] = true
    end
end

-- Whose kicks a row that is no member's own holds. The meter keeps a demon as
-- a source of its own and files its kicks there, never under its warlock: a
-- row of class WARLOCK with no spec icon. The member whose pet the row's GUID
-- names owns it; failing that (a demon summoned again keeps its old row), the
-- one member of a class whose interrupt a demon casts. With two such members
-- and no pet to match, nobody.
local function PetOwner(source, owners)
    local raw = source.sourceGUID
    if IsSecret(raw) then
        return nil
    end
    local unitGuid = PlainString(raw)
    if unitGuid then
        for petUnit, ownerUnit in pairs(PET_OWNER_UNIT) do
            if PlainString(UnitGUID(petUnit)) == unitGuid then
                local og = PlainString(UnitGUID(ownerUnit))
                return og and owners[og] and og or nil
            end
        end
    end
    local iconTex = source.specIconID
    if IsSecret(iconTex) or (iconTex ~= nil and iconTex ~= 0) then
        return nil
    end
    local cls = PlainString(source.classFilename)
    if not (cls and PET_KICK_CLASS[cls]) then
        return nil
    end
    local found
    for g, runRec in pairs(owners) do
        if runRec.class == cls then
            if found then
                return nil
            end
            found = g
        end
    end
    return found
end

local function WalkSources(session, totals, perSec, identityRoster, countRows, owners)
    local num = 0
    for _, source in ipairs(session.combatSources) do
        num = num + 1
        local unitGuid = PlainString(source.sourceGUID)
        local sum = PlainNumber(source.totalAmount)
        if countRows then
            local rid = PlainNumber(source.deathRecapID)
            if unitGuid and rid and rid > 0 then
                totals[unitGuid] = (totals[unitGuid] or 0) + 1
            end
        elseif sum then
            local into = unitGuid
            if owners and not (into and owners[into]) then
                into = PetOwner(source, owners)
            end
            if into then
                totals[into] = (totals[into] or 0) + sum
                if perSec then
                    perSec[into] = PlainNumber(source.amountPerSecond)
                end
            end
        end
        if identityRoster and unitGuid and identityRoster[unitGuid] then
            local runRec = identityRoster[unitGuid]
            runRec.specIcon = runRec.specIcon or PlainNumber(source.specIconID)
            runRec.class = runRec.class or PlainString(source.classFilename)
        end
    end
    return num
end

-- Fills totals[guid] and, when perSec is given, perSec[guid]. Returns false if
-- the session could not be read at all, else true plus how many source rows
-- the session held (nil when the walk raised), so an empty session can be
-- told apart from rows that are still classified.
-- identityRoster, when given, also banks classFilename and specIconID onto it.
-- Both are NeverSecret, so they read even when the amounts beside them do not.
-- owners, the run's roster for a metric whose pets count for their owners,
-- adds each pet's row to its owner's total (PetOwner).
local function HarvestTotals(dmType, totals, perSec, identityRoster, countRows, owners)
    if dmType == nil then
        return false
    end
    local success, session = pcall(C_DamageMeter.GetCombatSessionFromType, SESSION_OVERALL, dmType)
    if not success or type(session) ~= "table" or type(session.combatSources) ~= "table" then
        return false
    end
    -- The whole walk sits inside the pcall, not just the call that produced
    -- the session: type() answers "table" for a secret table too, so indexing
    -- one raises rather than reading nil.
    local walked, rowList = pcall(WalkSources, session, totals, perSec, identityRoster, countRows, owners)
    return true, walked and rowList or nil
end

local function SessionDuration()
    if not (C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds) then
        return nil
    end
    if SESSION_OVERALL == nil then
        return nil
    end
    -- One argument only: the session type. There is no meter type parameter.
    local success, dur = pcall(C_DamageMeter.GetSessionDurationSeconds, SESSION_OVERALL)
    if not success then
        return nil
    end
    return PlainNumber(dur)
end

--------------------------------------------------------------------------------
--  Collector state
--------------------------------------------------------------------------------
local widget -- built on first enable
local collectingNow -- true between CHALLENGE_MODE_START and the panel showing
local rosterOrder -- ordered guids
local baseTotals -- [metricKey][guid] = total at key start
local baseDuration -- Overall session duration at key start
local hasBaseline -- false when the key start sample failed or was skipped
local inspectPending -- guid of the outstanding NotifyInspect
-- Meter resets mid-key (another meter resetting after each pull, a Reset
-- button, Blizzard's auto-reset) would cut the Overall session short, so the
-- run banks what the meter gained at each checkpoint (a pull ended and the
-- combat restriction lifted) and folds it in on a reset:
--   bank[metric][guid] = gains banked before a reset, bankDur = their seconds,
--   snap[metric][guid] = Overall totals at the last checkpoint, snapDur = its
--   duration, unbanked = a pull began since that checkpoint, gaps = a reset
--   landed on unbanked gains (the run's numbers are short).
-- The finished run carries it on (lastRun.seg) while it waits for the meter.
local segRec

-- Everything the finishing phase needs, captured when the key completes and
-- deliberately out of ResetCollector's reach. The key resets behind us on the
-- way out of the instance while the run is still waiting on the meter, on the
-- chest and on the late score push, so none of that may live in state the
-- reset wipes.
local previousRun -- { record, rst, ord, base, baseDur, based, seg, awaitingMeter, lootArmed, settled }

-- Collecting-phase state only. The finished run lives in lastRun.
local function ResetCollector()
    collectingNow = false
    roster = {}
    rosterOrder = {}
    baseTotals = {}
    baseDuration = nil
    hasBaseline = false
    inspectPending = nil
    segRec = { bank = {}, snap = {}, bankDur = 0, unbanked = false, gaps = false }
end
ResetCollector()

local function EnsureMember(unitGuid)
    local runRec = roster[unitGuid]
    if not runRec then
        runRec = { guid = unitGuid }
        roster[unitGuid] = runRec
        rosterOrder[#rosterOrder + 1] = unitGuid
    end
    return runRec
end

local function StillIs(runRec)
    if not (runRec and runRec.unit and runRec.guid) then
        return false
    end
    if not UnitExists(runRec.unit) then
        return false
    end
    return PlainString(UnitGUID(runRec.unit)) == runRec.guid
end

-- Item link straight out of a chat line. Matching the hyperlink rather than the
-- sentence keeps this independent of client language.
local function LinkFromText(textValue)
    if type(textValue) ~= "string" or IsSecret(textValue) then
        return nil
    end
    return textValue:match("(|c%x+|Hitem:.-|h.-|h|r)") or textValue:match("(|Hitem:.-|h.-|h)")
end

-- Bonus roll loot is announced through CHAT_MSG_LOOT like the chest's, and only
-- the sentence tells them apart. The client's own localized strings become the
-- patterns, so this holds in every client language.
local IsBonusRollLine
do
    local BONUS_KEYS = {
        "LOOT_ITEM_BONUS_ROLL",
        "LOOT_ITEM_BONUS_ROLL_MULTIPLE",
        "LOOT_ITEM_BONUS_ROLL_SELF",
        "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
    }
    local patterns

    local function ToPattern(fmt)
        local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
        p = p:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
        return "^" .. p:gsub("\1", ".+"):gsub("\2", "%%d+")
    end

    function IsBonusRollLine(textValue)
        if type(textValue) ~= "string" or IsSecret(textValue) then
            return false
        end
        if not patterns then
            patterns = {}
            for _, recKey in ipairs(BONUS_KEYS) do
                local fmt = _G[recKey]
                if type(fmt) == "string" and fmt ~= "" then
                    patterns[#patterns + 1] = ToPattern(fmt)
                end
            end
        end
        for i = 1, #patterns do
            if textValue:find(patterns[i]) then
                return true
            end
        end
        return false
    end
end

local function IDFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end
    return tonumber(itemLink:match("|Hitem:(%d+)"))
end

-- Records a looted item against a roster member, found by GUID when we have one
-- and by short name otherwise. Never overwrites an item already recorded.
local ITEM_CLASS = Enum and Enum.ItemClass
local ITEM_QUALITY = Enum and Enum.ItemQuality
local GetInstant = C_Item.GetItemInfoInstant

local ITEM_BIND = Enum and Enum.ItemBind
local GetFullInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- A Warbound until Equipped item reports bindType OnEquip, so the predicate
-- has to run first: the bind type alone only catches the fully bound ones.
local function IsWarboundLoot(details)
    if not details then
        return false
    end
    if
        C_Item
        and C_Item.IsItemBindToAccountUntilEquip
        and C_Item.IsItemBindToAccountUntilEquip(details) == true
    then
        return true
    end
    if ITEM_BIND and GetFullInfo then
        local bind = PlainNumber(select(14, GetFullInfo(details)))
        if
            bind
            and (
                bind == ITEM_BIND.ToWoWAccount
                or bind == ITEM_BIND.ToBnetAccount
                or bind == ITEM_BIND.ToBnetAccountUntilEquipped
            )
        then
            return true
        end
    end
    return false
end

-- The column is for the chest's gear. Keystones, quest items, housing decor,
-- reagents and anything below epic arrive through the same loot channels and
-- are skipped. Quality is read from the link where there is one, since bonus
-- IDs can raise it; an item not yet cached reports no quality and is let
-- through on its equip slot alone.
local function IsExcludedLootID(ident, itemLink)
    if not ident then
        return true
    end
    if ident == 180653 then
        return true
    end
    if C_Item and C_Item.IsItemKeystoneByID and C_Item.IsItemKeystoneByID(ident) == true then
        return true
    end
    if IsWarboundLoot(itemLink or ident) then
        return true
    end
    if GetInstant then
        local _, _, _, equipLoc, _, classID = GetInstant(ident)
        classID = PlainNumber(classID)
        if ITEM_CLASS and (classID == ITEM_CLASS.Questitem or classID == ITEM_CLASS.Housing) then
            return true
        end
        equipLoc = PlainString(equipLoc)
        if not equipLoc or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
            return true
        end
    end
    if ITEM_QUALITY and C_Item and C_Item.GetItemQualityByID then
        local q = PlainNumber(C_Item.GetItemQualityByID(itemLink or ident))
        if q and q < ITEM_QUALITY.Epic then
            return true
        end
    end
    return false
end

local function IsExcludedLoot(itemLink)
    if itemLink:find("|Hkeystone:", 1, true) then
        return true
    end
    return IsExcludedLootID(IDFromLink(itemLink), itemLink)
end

local function RecordLoot(runState, order, unitGuid, name, itemLink)
    if not (runState and order and itemLink) then
        return false
    end
    if IsExcludedLoot(itemLink) then
        return false
    end
    local runRec = unitGuid and runState[unitGuid]
    if not runRec and name then
        local short = name:match("^([^%-]+)") or name
        for _, g in ipairs(order) do
            local region = runState[g]
            if region and region.name and (region.name:match("^([^%-]+)") or region.name) == short then
                runRec = region
                break
            end
        end
    end
    if not runRec then
        return false
    end
    -- The chest reward is the item the column is for: a link gets in only when
    -- it is that same item, carrying the level and bonuses the ID has not got.
    if runRec.lootChest then
        if runRec.lootLink or IDFromLink(itemLink) ~= runRec.lootID then
            return false
        end
        runRec.lootLink = itemLink
        return true
    end
    if runRec.lootLink then
        return false
    end
    runRec.lootLink = itemLink
    runRec.lootID = IDFromLink(itemLink) or runRec.lootID
    return true
end

local function ScoreFor(unitToken)
    if not (C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then
        return nil
    end
    local success, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unitToken)
    if not success or type(summary) ~= "table" then
        return nil
    end
    return PlainNumber(summary.currentSeasonScore)
end

-- Walks Blizzard's own five token list. Fills anything still missing; never
-- overwrites a value already captured, so a member who leaves after completion
-- keeps the data collected while they were present.
local function ScanRoster(withStartScore)
    for _, unitToken in ipairs(UNIT_TOKENS) do
        if UnitExists(unitToken) then
            local unitGuid = PlainString(UnitGUID(unitToken))
            if unitGuid then
                local runRec = EnsureMember(unitGuid)
                runRec.unit = unitToken
                runRec.name = runRec.name or PlainString(UnitName(unitToken))
                if not runRec.class then
                    local _, classFile = UnitClass(unitToken)
                    runRec.class = PlainString(classFile)
                end
                if UnitGroupRolesAssignedEnum then
                    runRec.role = PlainNumber(UnitGroupRolesAssignedEnum(unitToken)) or runRec.role
                end
                if withStartScore and runRec.scoreStart == nil then
                    runRec.scoreStart = ScoreFor(unitToken)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Inspect queue: item level and spec icon. GetInspectItemLevel reads whichever
--  player the client currently has cached, so exactly one inspect may be
--  outstanding at a time. The queue sweeps every few seconds during the key and
--  stops once everyone has both values. Taking the spec icon from here rather
--  than from the meter means it does not depend on the meter at all.
--------------------------------------------------------------------------------
local function OwnSpecIcon()
    local CSI = C_SpecializationInfo
    if not (CSI and CSI.GetSpecialization and CSI.GetSpecializationInfo) then
        return nil
    end
    local index = CSI.GetSpecialization()
    if not index then
        return nil
    end
    local _, _, _, iconTex = CSI.GetSpecializationInfo(index)
    return PlainNumber(iconTex)
end

-- GetSpecializationInfoForSpecID is the documented name; the ByID global is
-- undocumented but still present and used elsewhere in the suite, so it stays
-- as the fallback.
local function SpecIconForSpecID(specID)
    if not specID or specID == 0 then
        return nil
    end
    local func = GetSpecializationInfoForSpecID or GetSpecializationInfoByID
    if not func then
        return nil
    end
    return PlainNumber(select(4, func(specID)))
end

local function InspectSpecIcon(unitToken)
    local CSI = C_SpecializationInfo
    if not (CSI and CSI.GetInspectSpecialization) then
        return nil
    end
    return SpecIconForSpecID(PlainNumber(CSI.GetInspectSpecialization(unitToken)))
end

local function OwnItemLevel()
    if GetAverageItemLevel then
        local _, equipped = GetAverageItemLevel()
        local v = PlainNumber(equipped)
        if v and v > 0 then
            return math.floor(v)
        end
    end
    if C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local v = PlainNumber(C_PaperDollInfo.GetInspectItemLevel("player"))
        if v and v > 0 then
            return math.floor(v)
        end
    end
    return nil
end

local INSPECT_MAX_TRIES = 8

local function NeedsInspect(runRec)
    return not runRec.ilvl or not runRec.specIcon
end

-- The roster being worked on: the live one during the key, then the finished
-- run's snapshot while it settles, when the group stands at the chest out of
-- combat and in range -- the best inspect window of the whole run.
local function InspectRoster()
    if collectingNow then
        return roster, rosterOrder
    end
    if previousRun and not previousRun.settled then
        return previousRun.rst, previousRun.ord
    end
    return nil
end

-- Event driven: INSPECT_READY chains to the next member; a pull ending, a
-- roster change or the loot window closing restarts it. Fewest attempts goes
-- first, so one player out of range cannot starve everyone behind them.
local function InspectSweep()
    local runState, order = InspectRoster()
    if not runState then
        return
    end

    local missing = false
    for _, unitGuid in ipairs(order) do
        local runRec = runState[unitGuid]
        if runRec then
            if runRec.unit == "player" then
                runRec.ilvl = runRec.ilvl or OwnItemLevel()
                runRec.specIcon = runRec.specIcon or OwnSpecIcon()
            end
            if NeedsInspect(runRec) then
                missing = true
            end
        end
    end
    if not missing or inspectPending or InCombatLockdown() or (InspectFrame and InspectFrame:IsShown()) then
        return
    end

    local pick, fewest
    for _, unitGuid in ipairs(order) do
        local runRec = runState[unitGuid]
        local tries = runRec and (runRec.inspectTries or 0)
        if
            runRec
            and runRec.unit ~= "player"
            and NeedsInspect(runRec)
            and tries < INSPECT_MAX_TRIES
            and StillIs(runRec)
            and UnitIsVisible(runRec.unit)
            and CanInspect(runRec.unit)
            and (fewest == nil or tries < fewest)
        then
            pick, fewest = runRec, tries
        end
    end
    if not pick then
        return
    end
    pick.inspectTries = fewest + 1
    inspectPending = pick.guid
    if ClearInspectPlayer then
        ClearInspectPlayer()
    end
    NotifyInspect(pick.unit)
end

-- Returns true when it filled something in.
local function OnInspectReady(unitGuid)
    unitGuid = PlainString(unitGuid)
    if not unitGuid then
        return false
    end
    if inspectPending == unitGuid then
        inspectPending = nil
    end
    local runState = InspectRoster()
    local runRec = runState and runState[unitGuid]
    if not runRec or not UnitTokenFromGUID then
        return false
    end
    local unitToken = PlainString(UnitTokenFromGUID(unitGuid))
    if not unitToken or not UnitExists(unitToken) then
        return false
    end
    local changed = false
    if not runRec.ilvl and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel then
        local val = PlainNumber(C_PaperDollInfo.GetInspectItemLevel(unitToken))
        if val and val > 0 then
            runRec.ilvl = math.floor(val)
            changed = true
        end
    end
    if not runRec.specIcon then
        runRec.specIcon = InspectSpecIcon(unitToken)
        changed = changed or runRec.specIcon ~= nil
    end
    return changed
end

--------------------------------------------------------------------------------
--  Run lifecycle
--------------------------------------------------------------------------------
-- While a Combat or ChallengeMode restriction is up, the meter's source rows
-- read classified (sourceGUID and totalAmount come back secret), so a harvest
-- banks nothing. Declassification lags the end of combat, which is exactly the
-- window CHALLENGE_MODE_COMPLETED lands in.
local RESTRICTION_KINDS = { "Combat", "ChallengeMode" }
local function RestrictionActive()
    local CRA = C_RestrictedActions
    if not (CRA and CRA.IsAddOnRestrictionActive and Enum.AddOnRestrictionType) then
        return false
    end
    for _, kind in ipairs(RESTRICTION_KINDS) do
        local t = Enum.AddOnRestrictionType[kind]
        if t ~= nil and CRA.IsAddOnRestrictionActive(t) == true then
            return true
        end
    end
    return false
end

-- The finished run is "settling" from completion until we leave the instance:
-- the meter may still be classified, party scores arrive late, and loot is
-- announced as the chest is opened. Leaving the instance ends it.
local function Settling()
    return previousRun ~= nil and not previousRun.settled
end

local function SetEvent(evt, isOn)
    if isOn then
        widget:RegisterEvent(evt)
    else
        widget:UnregisterEvent(evt)
    end
end

-- Every registration derives from state here, so no path can leave an event
-- registered or dropped out of step. Loot has three sources, none complete:
-- the rewards payload (our own item), ENCOUNTER_LOOT_RECEIVED (docs say args
-- 5/6 are itemName/fileName; BossBannerToast binds playerName/className) and
-- CHAT_MSG_LOOT (looter GUID in arg 12). Bonus roll loot is dropped: from the
-- chat line for everyone, and from BONUS_ROLL_RESULT for our own roll.
local function SyncEvents()
    if not widget then
        return
    end
    local isOn = Enabled() == true
    local settlingNow = isOn and Settling()
    local waiting = settlingNow and previousRun.awaitingMeter == true
    SetEvent("CHALLENGE_MODE_START", isOn)
    SetEvent("CHALLENGE_MODE_COMPLETED", isOn)
    SetEvent("CHALLENGE_MODE_RESET", isOn)
    SetEvent("INSPECT_READY", isOn and (collectingNow or settlingNow))
    SetEvent("GROUP_ROSTER_UPDATE", isOn and (collectingNow or settlingNow))
    SetEvent("CHALLENGE_MODE_MEMBER_INFO_UPDATED", isOn and (collectingNow or settlingNow))
    SetEvent("PLAYER_REGEN_ENABLED", isOn and (collectingNow or settlingNow))
    -- While the key runs, and while the finished run still waits for the
    -- meter: the combat restriction's edges are the per-pull checkpoints, and
    -- a meter reset folds into the bank (see seg).
    local keyRunning = isOn and collectingNow and not previousRun
    SetEvent("ADDON_RESTRICTION_STATE_CHANGED", waiting or keyRunning)
    SetEvent("DAMAGE_METER_RESET", waiting or keyRunning)
    SetEvent("CHALLENGE_MODE_COMPLETED_REWARDS", settlingNow)
    SetEvent("ENCOUNTER_LOOT_RECEIVED", settlingNow)
    SetEvent("CHAT_MSG_LOOT", settlingNow)
    SetEvent("BONUS_ROLL_RESULT", settlingNow)
    SetEvent("LOOT_CLOSED", settlingNow)
    SetEvent("PLAYER_ENTERING_WORLD", settlingNow)
end

-- skipBaseline is for the recovery path at CHALLENGE_MODE_COMPLETED, where a
-- reload lost the key start. Sampling a baseline there would bank the finished
-- run's own totals and make every delta zero; with none, the deltas are the
-- Overall session, which is the closest honest answer available.
local function StartCollecting(skipBaseline)
    -- A new key supersedes anything the previous one was still waiting for.
    previousRun = nil
    ResetCollector()
    collectingNow = true
    ScanRoster(true)
    if not skipBaseline and MeterReady() then
        local allRead = true
        for _, m in ipairs(METRICS) do
            local t = {}
            if not HarvestTotals(m.dmType, t, nil, nil, m.countRows, m.pets and roster) then
                allRead = false
            end
            baseTotals[m.key] = t
        end
        -- Right after the reset at key start there is no session yet and the
        -- duration reads nil; that is an empty session, so it counts as zero.
        baseDuration = SessionDuration() or 0
        -- An unread baseline is not a zero baseline: without this flag a failed
        -- read silently turns into "the whole session counts as this run".
        hasBaseline = allRead
        -- The first checkpoint is the baseline itself, so a reset before the
        -- first pull (a meter clearing itself at key start) banks nothing.
        for _, m in ipairs(METRICS) do
            local cfg = {}
            for unitGuid, val in pairs(baseTotals[m.key]) do
                cfg[unitGuid] = val
            end
            segRec.snap[m.key] = cfg
        end
        segRec.snapDur = baseDuration
    end
    SyncEvents()
    InspectSweep()
end

-- Leaves the finish watch alone on purpose: the key resetting behind us is
-- normal on the way out of the instance, and the finished run is still waiting
-- for the meter to declassify. It holds its own roster snapshot, so the wipe
-- below cannot reach it.
local function StopCollecting()
    ResetCollector()
    SyncEvents()
end

-- Reads the four meter types, subtracts the key start baseline, adds what was
-- banked before any mid-key meter reset (see seg) and writes the numbers onto
-- the run's roster. Baseline and bank are passed in rather than read from the
-- live upvalues: retries land after the key has reset, which wipes them.
local scratchTotals, scratchPerSec = {}, {}

local function HarvestInto(runRecord, runState, base, baseDur, based, segment)
    runState = runState or roster
    base = base or baseTotals
    if baseDur == nil then
        baseDur = baseDuration
    end
    if based == nil then
        based = hasBaseline
    end
    segment = segment or segRec
    if not MeterReady() then
        -- Must be recorded here too, or the panel shows empty combat columns
        -- with no word of why the meter had nothing to give.
        runRecord.meterAvailable = false
        return false
    end

    local totals, perSec = scratchTotals, scratchPerSec
    local okAny = false
    local matched = 0
    local duration = SessionDuration()
    local deltaDuration
    -- Without a trustworthy key start sample the session duration covers
    -- everything since login, so it must not be used as the run's duration.
    -- amountPerSecond is Blizzard's own figure and is the honest fallback.
    if based and baseDur then
        local live = (duration and duration > baseDur) and (duration - baseDur) or 0
        local skinData = live + segment.bankDur
        if skinData > 0 then
            deltaDuration = skinData
        end
    end
    runRecord.hasBaseline = based and true or false
    -- A mid-key meter reset cost a pull no checkpoint had banked.
    if segment.gaps then
        runRecord.meterGaps = true
    end

    for _, m in ipairs(METRICS) do
        wipe(totals)
        wipe(perSec)
        local isDamage = (m.key == "damage")
        local read, rowList = HarvestTotals(
            m.dmType,
            totals,
            isDamage and perSec or nil,
            isDamage and runState or nil,
            m.countRows,
            m.pets and runState
        )
        if read then
            okAny = true
            local b = base[m.key]
            local bk = segment.bank[m.key]
            -- Members with banked gains but no row since the reset still count.
            -- When the meter sits empty since a reset that landed after the last
            -- checkpoint, the bank IS the whole run, so it matches on its own.
            if bk then
                local complete = isDamage and rowList == 0 and not segment.unbanked
                for unitGuid, val in pairs(bk) do
                    local runRec = runState[unitGuid]
                    if runRec and totals[unitGuid] == nil then
                        runRec[m.key] = val
                        if isDamage and deltaDuration and deltaDuration > 1 then
                            runRec.dps = val / deltaDuration
                        end
                        if complete then
                            matched = matched + 1
                        end
                    end
                end
            end
            for unitGuid, sum in pairs(totals) do
                local runRec = runState[unitGuid]
                if runRec then
                    local delta = sum - ((b and b[unitGuid]) or 0)
                    if delta < 0 then
                        delta = sum
                    end
                    delta = delta + ((bk and bk[unitGuid]) or 0)
                    runRec[m.key] = delta
                    if isDamage then
                        matched = matched + 1
                        if deltaDuration and deltaDuration > 1 then
                            runRec.dps = delta / deltaDuration
                        else
                            runRec.dps = perSec[unitGuid]
                        end
                    end
                end
            end
        end
    end

    runRecord.meterAvailable = okAny
    -- How many roster members actually came back with a damage figure. Zero
    -- with a readable session means the rows were still classified, which is
    -- what the retries below wait out.
    runRecord._matched = matched
    return okAny
end

-- Whose reset state the meter events feed: the running key's, or the finished
-- run's while it still waits for the meter (a reset between the last pull and
-- the final read would otherwise take that pull with it). Only from a trusted
-- baseline; nothing once the run's numbers are in. Returns the seg, plus the
-- finished run when the seg is its.
local function ResetScope()
    local lastSummary = previousRun
    if lastSummary then
        if lastSummary.awaitingMeter and lastSummary.based then
            return lastSummary.seg, lastSummary
        end
    elseif collectingNow and hasBaseline then
        return segRec
    end
end

-- A checkpoint: a pull ended and the combat restriction lifted, so the Overall
-- totals read plain. A row still classified keeps its last value, and the
-- pull only counts as banked once the damage rows came back readable (or the
-- meter is simply empty). rst is the roster the seg belongs to.
local function Checkpoint(segment, runState)
    if not MeterReady() then
        return
    end
    local readable = false
    for _, m in ipairs(METRICS) do
        wipe(scratchTotals)
        local read, rowList = HarvestTotals(m.dmType, scratchTotals, nil, nil, m.countRows, m.pets and runState)
        if read then
            local cfg = segment.snap[m.key]
            if not cfg then
                cfg = {}
                segment.snap[m.key] = cfg
            end
            for unitGuid, val in pairs(scratchTotals) do
                cfg[unitGuid] = val
            end
            if m.key == "damage" and (rowList == 0 or next(scratchTotals) ~= nil) then
                readable = true
            end
        end
    end
    local skinData = SessionDuration()
    if skinData then
        segment.snapDur = skinData
    end
    if readable then
        segment.unbanked = false
    end
end

-- The meter was reset: bank what it gained up to the last checkpoint and count
-- on from zero. A reset landing on a pull no checkpoint banked loses that
-- pull, which the panel then says instead of passing short numbers off as the
-- whole run. Returns the new baseline duration.
local function BankReset(base, segment, baseDur)
    if segment.unbanked then
        segment.gaps = true
    end
    for _, m in ipairs(METRICS) do
        local bank = segment.bank[m.key]
        if not bank then
            bank = {}
            segment.bank[m.key] = bank
        end
        local snap, b = segment.snap[m.key], base[m.key]
        if snap then
            for unitGuid, val in pairs(snap) do
                local gain = val - ((b and b[unitGuid]) or 0)
                if gain > 0 then
                    bank[unitGuid] = (bank[unitGuid] or 0) + gain
                end
            end
            wipe(snap)
        end
        if b then
            wipe(b)
        else
            base[m.key] = {}
        end
    end
    if segment.snapDur and baseDur and segment.snapDur > baseDur then
        segment.bankDur = segment.bankDur + (segment.snapDur - baseDur)
    end
    segment.snapDur = 0
    return 0
end

local function ApplyScores(runRecord, runState, order)
    runState, order = runState or roster, order or rosterOrder
    for _, unitGuid in ipairs(order) do
        local runRec = runState[unitGuid]
        if StillIs(runRec) then
            local nowTime = ScoreFor(runRec.unit)
            if nowTime then
                runRec.score = nowTime
                -- No API reports another player's delta for the run, so it is
                -- the score after the key minus the score sampled at its start.
                -- Without a baseline the cell stays empty rather than showing a
                -- wrong number.
                if runRec.scoreStart then
                    runRec.scoreGain = nowTime - runRec.scoreStart
                end
            end
        end
    end
    -- The local player has a real server side delta; prefer it.
    if runRecord.scoreOld and runRecord.scoreNew then
        local ownGUID = PlainString(UnitGUID("player"))
        local own = ownGUID and runState[ownGUID]
        if own then
            own.score = runRecord.scoreNew
            own.scoreGain = runRecord.scoreNew - runRecord.scoreOld
        end
    end
end

-- Row order: one of the four sortable columns (a click on its header picks
-- it, a second click flips the direction), DPS descending by default, like a
-- damage meter -- role is not a key, tank and healer fall where their numbers
-- put them. Persisted per profile (runSummary.sortKey / sortAsc). Missing
-- values sort last either way; DPS falls back to total damage while the
-- meter has not settled. Every value was validated plain before it was
-- stored, so comparing cannot raise.
local SORT_KEYS = { dps = true, damageTaken = true, interrupts = true, deaths = true }
local sortKey, sortAsc = "dps", false -- refreshed from the profile by SortMembers

local function SortState()
    local cfg = Cfg()
    local recKey = cfg and cfg.sortKey
    if not SORT_KEYS[recKey] then
        recKey = "dps"
    end
    return recKey, (cfg and cfg.sortAsc == true) or false
end

local function MemberOrder(a, b)
    local va, vb = a[sortKey], b[sortKey]
    if sortKey == "dps" then
        va = va or a.damage
        vb = vb or b.damage
    end
    local ma, mb = va == nil, vb == nil
    if ma ~= mb then
        return mb
    end
    if not ma and va ~= vb then
        if sortAsc then
            return va < vb
        end
        return va > vb
    end
    return (a.name or "") < (b.name or "")
end

local function SortMembers(entries)
    sortKey, sortAsc = SortState()
    table.sort(entries, MemberOrder)
end

local MEMBER_FIELDS = {
    "guid",
    "name",
    "class",
    "role",
    "specIcon",
    "ilvl",
    "score",
    "scoreGain",
    "damage",
    "dps",
    "damageTaken",
    "interrupts",
    "deaths",
    "lootID",
    "lootLink",
}

-- Rebuilt on every settling event, so the member tables already stored on the
-- record are overwritten in place rather than allocated again.
local function BuildMembers(runRecord, runState, order)
    runState, order = runState or roster, order or rosterOrder
    local result = runRecord.members
    if type(result) ~= "table" then
        result = {}
        runRecord.members = result
    end
    local num = 0
    for _, unitGuid in ipairs(order) do
        local runRec = runState[unitGuid]
        if runRec and runRec.name then
            num = num + 1
            local m = result[num]
            if type(m) ~= "table" then
                m = {}
                result[num] = m
            end
            for _, frame in ipairs(MEMBER_FIELDS) do
                m[frame] = runRec[frame]
            end
        end
    end
    for i = #result, num + 1, -1 do
        result[i] = nil
    end
    SortMembers(result)
end

local function TryFinishHarvest()
    local lastSummary = previousRun
    if not (lastSummary and lastSummary.awaitingMeter) then
        return
    end
    if RestrictionActive() then
        return
    end
    HarvestInto(lastSummary.record, lastSummary.rst, lastSummary.base, lastSummary.baseDur, lastSummary.based, lastSummary.seg)
    BuildMembers(lastSummary.record, lastSummary.rst, lastSummary.ord)
    if RefreshWindowIfOpen then
        RefreshWindowIfOpen()
    end
    if (lastSummary.record._matched or 0) > 0 then
        lastSummary.awaitingMeter = false
        SyncEvents()
    end
end

-- Party members' rating is pushed by the server after the key and has no event
-- of its own, so it is re-read on the settling events that do fire.
local function RefreshScores()
    local lastSummary = previousRun
    if not (lastSummary and not lastSummary.settled) then
        return
    end
    ApplyScores(lastSummary.record, lastSummary.rst, lastSummary.ord)
    BuildMembers(lastSummary.record, lastSummary.rst, lastSummary.ord)
    if RefreshWindowIfOpen then
        RefreshWindowIfOpen()
    end
end

local function FinishRun()
    local details = C_ChallengeMode
        and C_ChallengeMode.GetChallengeCompletionInfo
        and C_ChallengeMode.GetChallengeCompletionInfo()
    if type(details) ~= "table" then
        return
    end

    -- Capture the party tokens here and now: Blizzard's own completion banner
    -- does the same because members can leave immediately afterwards.
    ScanRoster(false)

    -- info.members is the server side roster and survives people leaving.
    if type(details.members) == "table" then
        for _, m in ipairs(details.members) do
            local unitGuid = PlainString(m.memberGUID)
            if unitGuid then
                local runRec = EnsureMember(unitGuid)
                runRec.name = runRec.name or PlainString(m.name)
                if not runRec.class then
                    -- UnitClass takes a unit token, so it cannot answer for
                    -- someone who already left. GetPlayerInfoByGUID is the
                    -- GUID keyed equivalent.
                    if GetPlayerInfoByGUID then
                        runRec.class = PlainString(select(2, GetPlayerInfoByGUID(unitGuid)))
                    end
                    if not runRec.class and UnitTokenFromGUID then
                        local u = PlainString(UnitTokenFromGUID(unitGuid))
                        if u and UnitExists(u) then
                            runRec.class = PlainString(select(2, UnitClass(u)))
                        end
                    end
                end
            end
        end
    end

    local mapID = PlainNumber(details.mapChallengeModeID)
    local mapName, _, timeLimit
    if mapID and C_ChallengeMode.GetMapUIInfo then
        mapName, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    end
    local deaths, timeLost
    if C_ChallengeMode.GetDeathCount then
        deaths, timeLost = C_ChallengeMode.GetDeathCount()
    end

    local runRecord = {
        mapID = mapID,
        mapName = PlainString(mapName),
        timeLimit = PlainNumber(timeLimit),
        level = PlainNumber(details.level),
        timeMS = PlainNumber(details.time), -- milliseconds
        onTime = details.onTime == true,
        upgrades = PlainNumber(details.keystoneUpgradeLevels) or 0,
        practice = details.practiceRun == true,
        mapRecord = details.isMapRecord == true,
        deaths = PlainNumber(deaths) or 0,
        timeLost = PlainNumber(timeLost) or 0,
        scoreOld = PlainNumber(details.oldOverallDungeonScore),
        scoreNew = PlainNumber(details.newOverallDungeonScore),
        finishedAt = time(),
    }

    local lastSummary = {
        record = runRecord,
        rst = roster,
        ord = rosterOrder,
        base = baseTotals,
        baseDur = baseDuration,
        based = hasBaseline,
        seg = segRec,
        bonus = {},
    }
    previousRun = lastSummary
    PurgeOldSeasons()
    HarvestInto(runRecord, lastSummary.rst, lastSummary.base, lastSummary.baseDur, lastSummary.based, lastSummary.seg)
    ApplyScores(runRecord, lastSummary.rst, lastSummary.ord)
    BuildMembers(runRecord, lastSummary.rst, lastSummary.ord)
    StoreRun(runRecord)

    -- If the rows are still classified, the restriction lift, the next pull
    -- ending, the loot window closing or leaving the instance each retry.
    lastSummary.awaitingMeter = (runRecord._matched or 0) == 0
    SyncEvents()
end

local function ShowPending()
    local lastSummary = previousRun
    if not lastSummary then
        return
    end
    lastSummary.lootArmed = false
    BuildMembers(lastSummary.record, lastSummary.rst, lastSummary.ord)
    if ShowWindow then
        ShowWindow(lastSummary.record)
    end
    -- The roster scan is done; the settling watch, inspects included, runs on.
    collectingNow = false
    SyncEvents()
    InspectSweep()
end

-- Leaving the instance closes the settling phase: one last attempt at the
-- meter and the scores, the panel if it never opened, then everything that was
-- only listening for this run is dropped.
local function EndSettling()
    local lastSummary = previousRun
    if not (lastSummary and not lastSummary.settled) then
        return
    end
    TryFinishHarvest()
    RefreshScores()
    if lastSummary.lootArmed then
        ShowPending()
    end
    lastSummary.awaitingMeter = false
    lastSummary.settled = true
    SyncEvents()
    if RefreshWindowIfOpen then
        RefreshWindowIfOpen()
    end
end

local function ArmLootWait()
    local lastSummary = previousRun
    if not lastSummary then
        return
    end
    local cfg = Cfg()
    if not (cfg and cfg.showAfterLoot) then
        ShowPending()
        return
    end
    -- Opens on the rewards payload or the loot window closing; if neither
    -- comes, leaving the instance opens it.
    lastSummary.lootArmed = true
end

-- The item string alone: a chat link loses a |cn quality color in LinkFromText,
-- so the same item arrives as different link strings. Bonus IDs are kept, so
-- a chest drop and a bonus copy of the same item still differ.
local function LinkKey(itemLink)
    return type(itemLink) == "string" and itemLink:match("|H(item:[^|]+)|h") or nil
end

-- Marks a link as bonus roll loot for the rest of the run and takes it back
-- from whoever it was already recorded against, since ENCOUNTER_LOOT_RECEIVED
-- may have delivered it before the chat line. True when a row changed.
local function ForgetBonusLoot(lastSummary, itemLink)
    local recKey = LinkKey(itemLink)
    if not recKey then
        return false
    end
    lastSummary.bonus[recKey] = true
    local changed = false
    for _, unitGuid in ipairs(lastSummary.ord) do
        local runRec = lastSummary.rst[unitGuid]
        if runRec and LinkKey(runRec.lootLink) == recKey then
            runRec.lootLink = nil
            -- The chest reward's ID stays when the bonus copy is the same item.
            if not runRec.lootChest and runRec.lootID == IDFromLink(itemLink) then
                runRec.lootID = nil
            end
            changed = true
        end
    end
    return changed
end

--------------------------------------------------------------------------------
--  Events
--------------------------------------------------------------------------------
local function OnEvent(_, evt, ...)
    if evt == "CHALLENGE_MODE_START" then
        StartCollecting()
    elseif evt == "CHALLENGE_MODE_RESET" then
        StopCollecting()
    elseif evt == "CHALLENGE_MODE_COMPLETED" then
        -- lastRun is only set by FinishRun and only cleared when a new key
        -- starts, so its presence means this key was already recorded. Without
        -- this, a repeated delivery would store the run twice, the second time
        -- with no baseline and with every score sampled after the fact.
        if previousRun then
            return
        end
        if not collectingNow then
            -- Reloading mid key loses the key start; collect what is still
            -- readable rather than dropping the run entirely.
            StartCollecting(true)
        end
        FinishRun()
        ArmLootWait()
    elseif evt == "CHALLENGE_MODE_COMPLETED_REWARDS" then
        -- rewards carry the LOCAL player's chest loot only; personal loot is
        -- never reported for anyone else.
        local lastSummary = previousRun
        if lastSummary then
            local rewards = select(5, ...)
            local ownGUID = PlainString(UnitGUID("player"))
            local own = ownGUID and lastSummary.rst[ownGUID]
            if own and type(rewards) == "table" then
                for _, reward in ipairs(rewards) do
                    local ident = PlainNumber(reward.rewardID)
                    if ident and reward.isCurrency ~= true and not IsExcludedLootID(ident) then
                        -- Kept as an ID: the item is often not in the client's
                        -- cache yet here, so icon and tooltip resolve from the
                        -- ID at render time. A link from one of the two loot
                        -- events below is preferred when it arrives.
                        if (own.lootID or IDFromLink(own.lootLink)) ~= ident then
                            own.lootLink = nil
                        end
                        own.lootID = ident
                        own.lootChest = true
                        break
                    end
                end
            end
            BuildMembers(lastSummary.record, lastSummary.rst, lastSummary.ord)
            if RefreshWindowIfOpen then
                RefreshWindowIfOpen()
            end
        end
        if lastSummary and lastSummary.lootArmed then
            ShowPending()
        end
    elseif evt == "ENCOUNTER_LOOT_RECEIVED" then
        local lastSummary = previousRun
        if lastSummary then
            local itemLink, who = PlainString((select(3, ...))), select(5, ...)
            if
                itemLink
                and not lastSummary.bonus[LinkKey(itemLink)]
                and RecordLoot(lastSummary.rst, lastSummary.ord, nil, PlainString(who), itemLink)
            then
                BuildMembers(lastSummary.record, lastSummary.rst, lastSummary.ord)
                if RefreshWindowIfOpen then
                    RefreshWindowIfOpen()
                end
            end
        end
    elseif evt == "BONUS_ROLL_RESULT" then
        -- Our own roll only; nobody else's is reported this way.
        local lastSummary = previousRun
        local rewardType, itemLink = ...
        itemLink = PlainString(itemLink)
        if lastSummary and itemLink and PlainString(rewardType) == "item" and ForgetBonusLoot(lastSummary, itemLink) then
            BuildMembers(lastSummary.record, lastSummary.rst, lastSummary.ord)
            if RefreshWindowIfOpen then
                RefreshWindowIfOpen()
            end
        end
    elseif evt == "CHAT_MSG_LOOT" then
        local lastSummary = previousRun
        if lastSummary then
            local textValue, who, unitGuid = select(1, ...), select(2, ...), select(12, ...)
            local itemLink = LinkFromText(textValue)
            if itemLink and IsBonusRollLine(textValue) then
                if ForgetBonusLoot(lastSummary, itemLink) then
                    BuildMembers(lastSummary.record, lastSummary.rst, lastSummary.ord)
                    if RefreshWindowIfOpen then
                        RefreshWindowIfOpen()
                    end
                end
            elseif
                itemLink
                and not lastSummary.bonus[LinkKey(itemLink)]
                and RecordLoot(lastSummary.rst, lastSummary.ord, PlainString(unitGuid), PlainString(who), itemLink)
            then
                BuildMembers(lastSummary.record, lastSummary.rst, lastSummary.ord)
                if RefreshWindowIfOpen then
                    RefreshWindowIfOpen()
                end
            end
        end
    elseif evt == "LOOT_CLOSED" then
        if previousRun and previousRun.lootArmed then
            ShowPending()
        end
        TryFinishHarvest()
        RefreshScores()
        InspectSweep()
    elseif evt == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- The combat restriction's edges (see ResetScope): switching on means
        -- a pull began (its gains are unbanked until the next checkpoint);
        -- switching off is the checkpoint itself.
        local rtype, rstate = PlainNumber((select(1, ...))), PlainNumber((select(2, ...)))
        local R, S = Enum.AddOnRestrictionType, Enum.AddOnRestrictionState
        local segment, lastSummary = ResetScope()
        if segment and rtype and R and S and rtype == R.Combat then
            if rstate == S.Inactive then
                Checkpoint(segment, lastSummary and lastSummary.rst or roster)
            else
                segment.unbanked = true
            end
        end
        TryFinishHarvest()
    elseif evt == "DAMAGE_METER_RESET" then
        local segment, lastSummary = ResetScope()
        if lastSummary then
            lastSummary.baseDur = BankReset(lastSummary.base, segment, lastSummary.baseDur)
        elseif segment then
            baseDuration = BankReset(baseTotals, segment, baseDuration)
        end
    elseif evt == "PLAYER_REGEN_ENABLED" then
        -- A pull ended: an inspect still pending from before it was dropped,
        -- so free the slot and carry on.
        inspectPending = nil
        InspectSweep()
        TryFinishHarvest()
    elseif evt == "PLAYER_ENTERING_WORLD" then
        EndSettling()
    elseif evt == "INSPECT_READY" then
        if OnInspectReady((select(1, ...))) and previousRun and not previousRun.settled then
            BuildMembers(previousRun.record, previousRun.rst, previousRun.ord)
            if RefreshWindowIfOpen then
                RefreshWindowIfOpen()
            end
        end
        InspectSweep()
    elseif evt == "CHALLENGE_MODE_MEMBER_INFO_UPDATED" or evt == "GROUP_ROSTER_UPDATE" then
        if collectingNow then
            ScanRoster(true)
        end
        InspectSweep()
        RefreshScores()
    end
end

--------------------------------------------------------------------------------
--  Enable / disable. Nothing exists until the feature is switched on.
--------------------------------------------------------------------------------
-- Lets the options page repaint an open panel when a column or the scale
-- changes, without exposing the panel internals.
function mod.RS_Refresh()
    if RefreshWindowIfOpen then
        RefreshWindowIfOpen()
    end
end

function mod.RS_Apply()
    if Enabled() then
        if not widget then
            widget = CreateFrame("Frame")
            widget:SetScript("OnEvent", OnEvent)
        end
        SyncEvents()
        -- Enabling mid key still picks the run up from here on. Guarded on
        -- lastRun because IsChallengeModeActive stays true after completion
        -- until the key resets, and every options change calls back in here:
        -- without it, touching a setting inside the instance would restart the
        -- collector and discard the run that just finished.
        if
            not collectingNow
            and not previousRun
            and C_ChallengeMode
            and C_ChallengeMode.IsChallengeModeActive
            and C_ChallengeMode.IsChallengeModeActive()
        then
            StartCollecting()
        end
        -- Unlock Mode entry intentionally not registered for now; the panel is
        -- moved by dragging its header. RegisterUnlock is kept for later.
    elseif widget then
        widget:UnregisterAllEvents()
        previousRun = nil
        StopCollecting()
    end
end

function mod.RS_OnEnable(database)
    saved = database
    if not saved then
        return
    end
    mod.RS_Apply()
end

--------------------------------------------------------------------------------
--  Panel. CludesUI.Widgets is deliberately not used: CludesUIOptions is
--  LoadOnDemand, so a widget call would force load the whole options addon at
--  the end of every key. Chrome mirrors Damage Meters' own window, and all
--  geometry goes through CludesUI.PP, the game grid, never PanelPP.
--------------------------------------------------------------------------------
local CUI = CludesUI
local format = string.format
local floor = math.floor

-- Sized for reading at a glance rather than as a compact HUD element; the
-- Panel Scale setting multiplies all of it on top of the player's UI scale.
local PAD = 15
local HEAD_H = 56
local COLHDR_H = 22
local COL_GAP = 15
local SUB_GAP = 5
local ICON_SZ = 20
-- Member-row text: user-set (runSummary.textSize, default 14); the row height
-- follows it. Title, subline and column headers keep their fixed sizes.
local DEFAULT_TEXT_SZ = 14
local FONT_SZ = DEFAULT_TEXT_SZ -- SetFS fallback only
local TITLE_SZ = 17
local SUBLINE_SZ = 13
local COLHDR_SZ = 12
local PICKER_SZ = 12
local NAME_MIN = 150
local PICKER_W = 240
local PICKER_H = 22
local CLOSE_W = 14
local HEADER_GAP = 10
local CLOSE_ICON = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png"
local FONT_FALLBACK = "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
local CLASS_ICON_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

-- `sub` marks a column that carries a second, separately styled font string.
-- "inline" keeps it right after the primary's own text (item level after a
-- name); "column" parks it at a fixed offset so the primaries stay right
-- aligned under each other and the extras all start on the same x (score).
local COLUMNS = {
    {
        key = "spec",
        header = "",
        kind = "icon",
        minW = ICON_SZ,
        cfg = "showSpecIcons",
        gapAfter = SUB_GAP,
    },
    {
        key = "name",
        header = "Player",
        kind = "text",
        justify = "LEFT",
        minW = NAME_MIN,
        sub = "inline",
    },
    {
        key = "score",
        header = "Score",
        kind = "text",
        justify = "RIGHT",
        minW = 42,
        cfg = "colScore",
        sub = "column",
    },
    { key = "loot", header = "Loot", kind = "icon", minW = ICON_SZ, cfg = "colLoot" },
    {
        key = "dps",
        header = "DPS",
        kind = "text",
        justify = "RIGHT",
        minW = 52,
        cfg = "colDps",
    },
    {
        key = "damageTaken",
        header = "Taken",
        kind = "text",
        justify = "RIGHT",
        minW = 52,
        cfg = "colDamageTaken",
    },
    {
        key = "interrupts",
        header = "Interrupts",
        kind = "text",
        justify = "RIGHT",
        minW = 28,
        cfg = "colInterrupts",
    },
    {
        key = "deaths",
        header = "Deaths",
        kind = "text",
        justify = "RIGHT",
        minW = 28,
        cfg = "colDeaths",
    },
}

-- Secondary font strings: item level and score gain, two sizes below the row
-- text and unbolded (size resolved from the setting at stamp time).
local SUB_STYLE = {
    name = { r = 0.55, g = 0.55, b = 0.55 },
    score = { r = 0.35, g = 0.95, b = 0.35 },
}

local window, rowList, colHdr, titleFS, subFS, pickerButton, pickerLbl
local visibleCols = {}
local currentRecord
local rowsTextSize -- the size the member rows were last stamped with

local function TextSize()
    local cfg = Cfg()
    local v = cfg and tonumber(cfg.textSize) or DEFAULT_TEXT_SZ
    if v < 8 then
        v = 8
    elseif v > 24 then
        v = 24
    end
    return v
end

local function RowHeight(size)
    return size + 9
end

--------------------------------------------------------------------------------
--  Formatting
--------------------------------------------------------------------------------
-- flags = nil follows the module's font setting; pass "" for an unbolded run.
local function SetFS(fontStr, size, flags)
    local filePath = (CUI.GetFontPath("mythicTimer")) or FONT_FALLBACK
    local outline = flags
    if outline == nil then
        outline = (CUI.GetFontOutlineFlag("mythicTimer")) or ""
    end
    fontStr:SetFont(filePath, size or FONT_SZ, outline)
end

-- SetFS for a table row's primary texts: the Player column names group members,
-- so they take a font family (Cyrillic, Korean and Chinese names draw), with no
-- shadow, as SetFS draws them. These texts are made with no font of their own
-- (a plain SetFont would pin their face), and every font write to them comes here.
local function SetRowFS(fontStr, size, flags)
    local filePath = (CUI.GetFontPath("mythicTimer")) or FONT_FALLBACK
    local outline = flags
    if outline == nil then
        outline = (CUI.GetFontOutlineFlag("mythicTimer")) or ""
    end
    CUI.SetFontFamily(fontStr, filePath, size or FONT_SZ, outline, false)
end

local function Hex(red, green, blue)
    return format("%02x%02x%02x", floor((red or 1) * 255), floor((green or 1) * 255), floor((blue or 1) * 255))
end

-- Shared number engine: K/M/B, or thousand/wan/yi grouping on koKR/zhCN/zhTW.
local function Abbrev(v)
    if type(v) ~= "number" then
        return nil
    end
    return CludesUI.AbbreviateNumber(v)
end

local function Clock(seconds)
    if type(seconds) ~= "number" or seconds < 0 then
        seconds = 0
    end
    local whole = floor(seconds)
    return format("%d:%02d", floor(whole / 60), whole % 60)
end

-- Indexing RAID_CLASS_COLORS with a secret token throws, so this is the guard
-- shape Damage Meters already uses on its own rows.
local function ClassHex(class)
    if class and not IsSecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local cc = CUI.GetClassColor(class)
        if cc then
            return Hex(cc.r, cc.g, cc.b)
        end
    end
    return "ffffff"
end

local function ShortName(name)
    if type(name) ~= "string" then
        return "?"
    end
    return name:match("^([^%-]+)") or name
end

local function ScoreText(m)
    if not m.score then
        return "-"
    end
    local hex = "ffffff"
    local colour = C_ChallengeMode
        and C_ChallengeMode.GetDungeonScoreRarityColor
        and C_ChallengeMode.GetDungeonScoreRarityColor(m.score)
    if type(colour) == "table" and colour.r then
        hex = Hex(colour.r, colour.g, colour.b)
    end
    return format("|cff%s%d|r", hex, floor(m.score))
end

-- Zero and missing both read as a dash in the combat columns.
local function NonZero(v)
    if type(v) == "number" and floor(v) > 0 then
        return v
    end
    return nil
end

local function CellText(colour, m, c)
    local k = colour.key
    if k == "name" then
        return format("|cff%s%s|r", ClassHex(m.class), ShortName(m.name))
    end
    if k == "score" then
        return ScoreText(m)
    end
    if k == "dps" then
        return Abbrev(NonZero(m.dps)) or "-"
    end
    if k == "damageTaken" then
        return Abbrev(NonZero(m.damageTaken)) or "-"
    end
    if k == "interrupts" then
        return NonZero(m.interrupts) and format("%d", floor(m.interrupts)) or "-"
    end
    if k == "deaths" then
        return NonZero(m.deaths) and format("%d", floor(m.deaths)) or "-"
    end
    return ""
end

local function SubText(colour, m, cfg)
    if colour.key == "name" then
        if cfg and cfg.colItemLevel ~= false and m.ilvl then
            return format("(%d)", m.ilvl)
        end
        return ""
    end
    if colour.key == "score" then
        if m.scoreGain and m.scoreGain > 0 then
            return format("(+%d)", floor(m.scoreGain))
        end
        return ""
    end
    return ""
end

-- date() without a leading "!" formats in the player's local time. Short
-- month and day with no year, 12-hour clock: "Sep 18, 6:02pm".
local function RunWhen(ts)
    if not ts then
        return ""
    end
    local hgt = tonumber(date("%H", ts)) or 0
    local ampm = (hgt >= 12) and "pm" or "am"
    hgt = hgt % 12
    if hgt == 0 then
        hgt = 12
    end
    return format("%s %d, %d:%s%s", date("%b", ts), tonumber(date("%d", ts)) or 0, hgt, date("%M", ts), ampm)
end

local function RunLabel(runRec)
    return format("+%d %s   %s", runRec.level or 0, runRec.mapName or "?", RunWhen(runRec.finishedAt))
end

--------------------------------------------------------------------------------
--  Chrome
--------------------------------------------------------------------------------
local function SavePositionFromFrame()
    local cfg = Cfg()
    if not (cfg and window) then
        return
    end
    local anchorPoint, _, relPoint, posX, posY = window:GetPoint(1)
    if not anchorPoint then
        return
    end
    cfg.position = { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
end

ApplyPosition = function()
    if not window then
        return
    end
    local cfg = Cfg()
    local place = cfg and cfg.position
    window:ClearAllPoints()
    if place and place.point then
        local Pix = CUI.PP
        local es = window:GetEffectiveScale() or 1
        local posX, posY = place.x or 0, place.y or 0
        if Pix and Pix.SnapForES then
            posX, posY = Pix.SnapForES(posX, es), Pix.SnapForES(posY, es)
        end
        window:SetPoint(place.point, UIParent, place.relPoint or place.point, posX, posY)
    else
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

-- Stamps the member-row font sizes: primary text at `size`, sub text two
-- below. Called at creation and again whenever the setting changes.
local function StampRowFonts(line, size)
    for recKey, fontStr in pairs(line.text) do
        SetRowFS(fontStr, size)
    end
    for _, subText in pairs(line.sub) do
        SetFS(subText, size - 2, "")
    end
    line:SetHeight(RowHeight(size))
end

local function MakeRow(hostFrame, size)
    size = size or DEFAULT_TEXT_SZ
    local line = CreateFrame("Frame", nil, hostFrame)
    line:SetHeight(RowHeight(size))
    line.text, line.sub, line.icons = {}, {}, {}
    local px = (CUI.PP and CUI.PP.mult) or 1
    for _, colour in ipairs(COLUMNS) do
        local fontStr = line:CreateFontString(nil, "OVERLAY")
        SetRowFS(fontStr, size)
        fontStr:SetTextColor(1, 1, 1, 1)
        fontStr:SetJustifyH(colour.justify or (colour.kind == "icon" and "CENTER" or "LEFT"))
        fontStr:SetWordWrap(false)
        line.text[colour.key] = fontStr
        if colour.kind == "icon" then
            local cellFrame = CreateFrame("Frame", nil, line)
            cellFrame:SetSize(ICON_SZ, ICON_SZ)
            cellFrame.tex = cellFrame:CreateTexture(nil, "ARTWORK")
            if colour.key == "spec" or colour.key == "loot" then
                -- Square icon on a black plate, inset by one physical pixel so
                -- the plate reads as a 1px border.
                cellFrame.bg = cellFrame:CreateTexture(nil, "BACKGROUND")
                cellFrame.bg:SetAllPoints()
                cellFrame.bg:SetColorTexture(0, 0, 0, 1)
                cellFrame.tex:SetPoint("TOPLEFT", cellFrame, "TOPLEFT", px, -px)
                cellFrame.tex:SetPoint("BOTTOMRIGHT", cellFrame, "BOTTOMRIGHT", -px, px)
            else
                cellFrame.tex:SetAllPoints()
            end
            line.icons[colour.key] = cellFrame
        else
            local style = colour.sub and SUB_STYLE[colour.key]
            if style then
                local subText = CUI.MakeFont(line, size - 2, nil, style.r, style.g, style.b, 1)
                SetFS(subText, size - 2, "")
                subText:SetJustifyH("LEFT")
                subText:SetWordWrap(false)
                line.sub[colour.key] = subText
            end
        end
    end
    return line
end

local ShowPicker -- assigned below, once the record list is reachable

local function BuildWindow()
    if window then
        return window
    end
    local Pix = CUI.PP

    window = CreateFrame("Frame", "CUIMythicRunSummaryFrame", UIParent)
    -- FULLSCREEN: above the options window (DIALOG), so Show Preview is not
    -- hidden behind it, and below FULLSCREEN_DIALOG, where the run picker menu,
    -- confirmation popups and Unlock Mode movers live.
    window:SetFrameStrata("FULLSCREEN")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:Hide()
    -- Escape closes it like every other CUI window (the shared proxy, never
    -- a direct UISpecialFrames insert).
    if CUI.RegisterEscapeClose then
        CUI.RegisterEscapeClose(window)
    end

    -- House window chrome (the /keys popup, Bags, the skinned Blizzard
    -- windows): the modern_blizz cover art under a black wash, a darker strip
    -- for the title bar, and the dark 1px PP border.
    window._bg = window:CreateTexture(nil, "BACKGROUND", nil, 0)
    window._bg:SetAllPoints()
    window._bg:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
    window._bg:SetTexCoord(0.25, 1, 0, 0.75)
    window._bgOverlay = window:CreateTexture(nil, "BACKGROUND", nil, 1)
    window._bgOverlay:SetAllPoints()
    window._bgOverlay:SetColorTexture(0, 0, 0, 0.55)

    local headerText = CreateFrame("Frame", nil, window)
    headerText:SetFrameLevel(window:GetFrameLevel() + 5)
    headerText:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
    headerText:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, 0)
    headerText:SetHeight(HEAD_H)
    headerText:EnableMouse(true)
    headerText:RegisterForDrag("LeftButton")
    headerText:SetScript("OnDragStart", function()
        window:StartMoving()
    end)
    headerText:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        SavePositionFromFrame()
    end)
    window._header = headerText

    local hbg = CUI.SolidTex(headerText, "BACKGROUND", 0, 0, 0, 0.25)
    hbg:SetAllPoints()

    local px = (Pix and Pix.mult) or 1
    local sep = headerText:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(px)
    sep:SetPoint("BOTTOMLEFT", headerText, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", headerText, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(1, 1, 1, 0.10)

    titleFS = CUI.MakeFont(headerText, TITLE_SZ, nil, 1, 1, 1, 1)
    SetFS(titleFS, TITLE_SZ)
    titleFS:SetPoint("TOPLEFT", headerText, "TOPLEFT", PAD, -HEADER_GAP)
    titleFS:SetJustifyH("LEFT")

    subFS = CUI.MakeFont(headerText, SUBLINE_SZ, nil, 1, 1, 1, 0.8)
    SetFS(subFS, SUBLINE_SZ)
    subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -SUB_GAP)
    subFS:SetJustifyH("LEFT")

    local closeBtn = CreateFrame("Button", nil, headerText)
    closeBtn:SetSize(CLOSE_W, CLOSE_W)
    closeBtn:SetPoint("TOPRIGHT", headerText, "TOPRIGHT", -PAD, -(HEADER_GAP + 2))
    closeBtn.icon = closeBtn:CreateTexture(nil, "OVERLAY")
    closeBtn.icon:SetAllPoints()
    closeBtn.icon:SetTexture(CLOSE_ICON)
    closeBtn.icon:SetAlpha(0.7)
    closeBtn:SetScript("OnEnter", function()
        closeBtn.icon:SetAlpha(0.9)
    end)
    closeBtn:SetScript("OnLeave", function()
        closeBtn.icon:SetAlpha(0.7)
    end)
    closeBtn:SetScript("OnClick", function()
        window:Hide()
    end)

    -- Run picker: the window-skin dropdown look every skinned Blizzard
    -- window's dropdowns carry (flat block, 1px grey border, hover wash, the
    -- small pointing arrow, white left-aligned label), with its menu hung
    -- below the button like the options dropdowns (ShowPicker).
    pickerButton = CreateFrame("Button", nil, headerText)
    pickerButton:SetSize(PICKER_W, PICKER_H)
    pickerButton:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -HEADER_GAP, (PICKER_H - CLOSE_W) / 2)
    local pfill = CUI.SolidTex(pickerButton, "BACKGROUND", 0.08, 0.08, 0.08, 0.92)
    pfill:SetAllPoints()
    if Pix and Pix.CreateBorder then
        -- Border container demoted to the button's own level so the label,
        -- a higher draw layer, renders over the strips (the skin's rule).
        local pbrd = Pix.CreateBorder(pickerButton, 0.25, 0.25, 0.25, 1, 1, "BORDER", -7)
        if pbrd and pbrd.SetFrameLevel then
            pbrd:SetFrameLevel(pickerButton:GetFrameLevel())
        end
    end
    local phover = CUI.SolidTex(pickerButton, "HIGHLIGHT", 1, 1, 1, 0.05)
    phover:SetAllPoints()
    local parrow = pickerButton:CreateTexture(nil, "OVERLAY")
    parrow:SetAtlas("Azerite-PointingArrow")
    parrow:SetSize(14, 10)
    parrow:SetPoint("RIGHT", pickerButton, "RIGHT", -6, 0)
    pickerLbl = CUI.MakeFont(pickerButton, PICKER_SZ, nil, 1, 1, 1, 1)
    SetFS(pickerLbl, PICKER_SZ)
    -- Two-point anchored and non-wrapping: a long dungeon name truncates
    -- inside the button instead of running back over the title.
    pickerLbl:SetPoint("LEFT", pickerButton, "LEFT", 8, 0)
    pickerLbl:SetPoint("RIGHT", parrow, "LEFT", -6, 0)
    pickerLbl:SetJustifyH("LEFT")
    pickerLbl:SetWordWrap(false)
    pickerButton:SetScript("OnClick", function()
        if ShowPicker then
            ShowPicker(pickerButton)
        end
    end)

    colHdr = MakeRow(window)
    colHdr:SetPoint("TOPLEFT", window, "TOPLEFT", 0, -HEAD_H)
    colHdr:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, -HEAD_H)
    colHdr:SetHeight(COLHDR_H)
    for _, colour in ipairs(COLUMNS) do
        local fontStr = colHdr.text[colour.key]
        if fontStr then
            SetRowFS(fontStr, COLHDR_SZ)
            fontStr:SetTextColor(1, 1, 1, 0.45)
        end
    end
    -- The header carries no icons, and the spec cell's black plate would show
    -- as an empty square if its frame were left visible.
    for _, cellFrame in pairs(colHdr.icons) do
        cellFrame:Hide()
    end

    -- Sortable column headers: a button over each cell (hit rect seated by
    -- PlaceInto each render). Click = sort by that column, click again = flip
    -- direction; stored on the profile. The active column is the bright
    -- header, nothing else marks it.
    colHdr.sortBtns = {}
    for _, colour in ipairs(COLUMNS) do
        if SORT_KEYS[colour.key] then
            local fontStr = colHdr.text[colour.key]
            local button = CreateFrame("Button", nil, colHdr)
            button:SetFrameLevel(colHdr:GetFrameLevel() + 2)
            button:SetScript("OnEnter", function()
                if fontStr and not button.active then
                    fontStr:SetTextColor(1, 1, 1, 0.8)
                end
            end)
            button:SetScript("OnLeave", function()
                if fontStr and not button.active then
                    fontStr:SetTextColor(1, 1, 1, 0.45)
                end
            end)
            button:SetScript("OnClick", function()
                local cfg = Cfg()
                if not cfg then
                    return
                end
                local recKey, asc = SortState()
                if recKey == colour.key then
                    cfg.sortAsc = not asc
                else
                    cfg.sortKey = colour.key
                    cfg.sortAsc = false
                end
                RefreshWindowIfOpen()
            end)
            colHdr.sortBtns[colour.key] = button
        end
    end

    local hsep = window:CreateTexture(nil, "ARTWORK")
    hsep:SetHeight(px)
    hsep:SetPoint("TOPLEFT", colHdr, "BOTTOMLEFT", PAD, 0)
    hsep:SetPoint("TOPRIGHT", colHdr, "BOTTOMRIGHT", -PAD, 0)
    hsep:SetColorTexture(1, 1, 1, 0.10)

    rowList = {}
    -- The border spans the whole frame, header included: it lives on its own
    -- host above the header (frame level + 5), or the header would draw over
    -- the top edge and only the body would look framed.
    if Pix and Pix.CreateBorder then
        local bh = CreateFrame("Frame", nil, window)
        bh:SetAllPoints()
        bh:SetFrameLevel(window:GetFrameLevel() + 10)
        Pix.CreateBorder(bh, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
        window._borderHost = bh
    end
    return window
end

--------------------------------------------------------------------------------
--  Layout and render
--------------------------------------------------------------------------------
local function VisibleColumns()
    local c = Cfg() or {}
    wipe(visibleCols)
    for _, colour in ipairs(COLUMNS) do
        if not colour.cfg or c[colour.cfg] ~= false then
            visibleCols[#visibleCols + 1] = colour
        end
    end
    return visibleCols
end

local function MeasuredWidth(fontStr, fallback)
    if not fontStr then
        return fallback
    end
    local wid = fontStr:GetStringWidth()
    if type(wid) ~= "number" or IsSecret(wid) then
        return fallback
    end
    -- Rounded up with a pixel spare: a font string sized to its exact
    -- fractional width truncates its own text to an ellipsis.
    if wid > 0 then
        wid = math.ceil(wid) + 1
    end
    return wid
end

-- Spec icon where the meter reported one, class icon otherwise. Both are
-- cropped so the round frame baked into the art does not show inside the
-- square plate.
local function FillSpecCell(cellFrame, m)
    local zoom = 0.08
    local ident = m.specIcon
    if type(ident) == "number" and ident ~= 0 then
        cellFrame.tex:SetTexture(ident)
        cellFrame.tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        cellFrame:Show()
        return
    end
    local coords = m.class and not IsSecret(m.class) and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.class]
    if coords then
        cellFrame.tex:SetTexture(CLASS_ICON_TEX)
        local left, right, top, bottom = coords[1], coords[2], coords[3], coords[4]
        local dx, dy = (right - left) * zoom, (bottom - top) * zoom
        cellFrame.tex:SetTexCoord(left + dx, right - dx, top + dy, bottom - dy)
        cellFrame:Show()
        return
    end
    cellFrame:Hide()
end

-- Hoisted so a render does not build four closures per row; the cell carries
-- its item on _itemID and the handlers branch on that.
local function LootEnter(self)
    if self._link or self._itemID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- The link carries the item's actual level and bonuses; the bare ID is
        -- the fallback for the rewards payload, which has no link.
        if self._link then
            GameTooltip:SetHyperlink(self._link)
        else
            GameTooltip:SetItemByID(self._itemID)
        end
        GameTooltip:Show()
    elseif CUI.ShowWidgetTooltip then
        CUI.ShowWidgetTooltip(self, CludesUI.L("No loot recorded for this player in this run."))
    end
end

local function LootLeave(self)
    if self._link or self._itemID then
        GameTooltip:Hide()
    elseif CUI.HideWidgetTooltip then
        CUI.HideWidgetTooltip()
    end
end

local function FillLootCell(cellFrame, m)
    cellFrame:EnableMouse(true)
    cellFrame:Show()
    cellFrame._itemID = m.lootID
    cellFrame._link = m.lootLink
    if m.lootID or m.lootLink then
        local ident = m.lootID or IDFromLink(m.lootLink)
        local iconTex = ident and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(ident)
        cellFrame.tex:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")
        cellFrame.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        cellFrame.tex:SetTexture(nil)
    end
    -- No plate without an item, or an empty cell would show a black square.
    if cellFrame.bg then
        cellFrame.bg:SetShown(m.lootID ~= nil or m.lootLink ~= nil)
    end
    cellFrame:SetScript("OnEnter", LootEnter)
    cellFrame:SetScript("OnLeave", LootLeave)
end

-- Places every visible column of one container (the column header row or a
-- member row) at the widths measured in the second pass, and hides the cells
-- of columns the user switched off.
local function PlaceInto(boxHolder, cols, widths, primW, subW)
    local posX = PAD
    for index, colour in ipairs(cols) do
        local wt = widths[index]
        local fontStr = boxHolder.text[colour.key]
        local subText = boxHolder.sub and boxHolder.sub[colour.key]
        local iconTex = boxHolder.icons[colour.key]
        if iconTex then
            iconTex:ClearAllPoints()
            iconTex:SetPoint("LEFT", boxHolder, "LEFT", posX + (wt - ICON_SZ) / 2, 0)
        end
        local scrollBar = boxHolder.sortBtns and boxHolder.sortBtns[colour.key]
        if scrollBar then
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOPLEFT", boxHolder, "TOPLEFT", posX, 0)
            scrollBar:SetPoint("BOTTOMRIGHT", boxHolder, "TOPLEFT", posX + wt, -COLHDR_H)
            scrollBar:Show()
        end
        if fontStr then
            fontStr:ClearAllPoints()
            fontStr:SetPoint("LEFT", boxHolder, "LEFT", posX, 0)
            if colour.sub == "inline" then
                fontStr:SetWidth(wt)
                if subText then
                    -- Anchored off this row's own text, so the item level sits
                    -- against the name instead of in a column of its own.
                    local own = MeasuredWidth(fontStr, 0)
                    subText:ClearAllPoints()
                    subText:SetPoint("LEFT", boxHolder, "LEFT", posX + own + SUB_GAP, 0)
                    subText:SetWidth(math.max(1, wt - own - SUB_GAP))
                    subText:Show()
                end
            else
                fontStr:SetWidth(primW[index])
                if subText then
                    subText:ClearAllPoints()
                    subText:SetPoint("LEFT", boxHolder, "LEFT", posX + primW[index] + SUB_GAP, 0)
                    subText:SetWidth(math.max(1, subW[index]))
                    subText:Show()
                end
            end
            fontStr:Show()
        end
        posX = posX + wt + (colour.gapAfter or COL_GAP)
    end
    for _, colour in ipairs(COLUMNS) do
        local isShown = false
        for _, vc in ipairs(cols) do
            if vc.key == colour.key then
                isShown = true
                break
            end
        end
        if not isShown then
            local fontStr = boxHolder.text[colour.key]
            if fontStr then
                fontStr:Hide()
            end
            local subText = boxHolder.sub and boxHolder.sub[colour.key]
            if subText then
                subText:Hide()
            end
            local iconTex = boxHolder.icons[colour.key]
            if iconTex then
                iconTex:Hide()
            end
            local scrollBar = boxHolder.sortBtns and boxHolder.sortBtns[colour.key]
            if scrollBar then
                scrollBar:Hide()
            end
        end
    end
end

local function RenderHeader(runRecord)
    local lvlHex = "ffffff"
    local kcol = C_ChallengeMode
        and C_ChallengeMode.GetKeystoneLevelRarityColor
        and C_ChallengeMode.GetKeystoneLevelRarityColor(runRecord.level or 0)
    if type(kcol) == "table" and kcol.r then
        lvlHex = Hex(kcol.r, kcol.g, kcol.b)
    end
    -- One string, keystone-rarity colour on the level only: "+12 Voidscar Arena".
    titleFS:SetText(format("|cff%s+%d|r %s", lvlHex, runRecord.level or 0, runRecord.mapName or "?"))

    local timeHex = runRecord.onTime and "40ff40" or "ff6060"
    local sub =
        format("|cff%s%s|r / %s", timeHex, Clock((runRecord.timeMS or 0) / 1000), Clock(runRecord.timeLimit or 0))
    -- Key upgrade levels read as the chest count: "(2 Chest)".
    if (runRecord.upgrades or 0) > 0 then
        sub = sub .. "   " .. CludesUI.Lf("(%1$d Chest)", runRecord.upgrades)
    elseif not runRecord.onTime then
        sub = sub .. "   " .. CludesUI.L("Depleted")
    end
    -- Deaths and the time they cost share one muted run.
    local deaths = CludesUI.Lf("%1$d Deaths", runRecord.deaths or 0)
    if (runRecord.timeLost or 0) > 0 then
        deaths = deaths .. format(" (-%s)", Clock(runRecord.timeLost))
    end
    sub = sub .. "   |cff808080" .. deaths .. "|r"
    -- One warning slot, most fundamental first.
    local warn
    if runRecord.meterAvailable == false then
        warn = CludesUI.L("Blizzard damage meter is off")
    elseif (runRecord._matched or 0) == 0 then
        warn = CludesUI.L("Combat data stayed restricted for this run")
    elseif runRecord.meterGaps then
        warn = CludesUI.L("Damage meter was reset mid-run, some numbers are low")
    end
    if warn then
        sub = sub .. "   |cffff8040" .. warn .. "|r"
    end
    subFS:SetText(sub)

    if pickerLbl then
        pickerLbl:SetText(RunLabel(runRecord))
    end
end

local scratchWidths, scratchPrim, scratchSub = {}, {}, {}

local function Render(runRecord)
    if not runRecord or not window then
        return
    end
    local c = Cfg() or {}
    local memberList = runRecord.members or {}
    local cols = VisibleColumns()
    -- Re-sorted on every render so a header click (or a stored run opened
    -- under a different sort) follows the current column and direction.
    SortMembers(memberList)

    RenderHeader(runRecord)

    -- Row text size from the setting; a change re-stamps every pooled row's
    -- fonts and height, and the rows are re-seated below (their pitch moved).
    local textSize = TextSize()
    local rowH = RowHeight(textSize)
    local restamp = rowsTextSize ~= textSize
    rowsTextSize = textSize

    -- First pass: grow the row pool and give every cell its final text, so the
    -- widths measured below are the ones actually rendered.
    for i = 1, #memberList do
        if not rowList[i] then
            rowList[i] = MakeRow(window, textSize)
        elseif restamp then
            StampRowFonts(rowList[i], textSize)
        end
        local posY = -(HEAD_H + COLHDR_H + (i - 1) * rowH)
        rowList[i]:ClearAllPoints()
        rowList[i]:SetPoint("TOPLEFT", window, "TOPLEFT", 0, posY)
        rowList[i]:SetPoint("TOPRIGHT", window, "TOPRIGHT", 0, posY)
        local line, m = rowList[i], memberList[i]
        line:Show()
        for _, colour in ipairs(COLUMNS) do
            local fontStr = line.text[colour.key]
            if fontStr then
                fontStr:SetText(CellText(colour, m, c))
                fontStr:SetTextColor(1, 1, 1, 1)
            end
            local subText = line.sub[colour.key]
            if subText then
                subText:SetText(SubText(colour, m, c))
            end
        end
        if line.icons.spec then
            FillSpecCell(line.icons.spec, m)
        end
        if line.icons.loot then
            FillLootCell(line.icons.loot, m)
        end
    end
    for i = #memberList + 1, #rowList do
        rowList[i]:Hide()
    end

    for _, colour in ipairs(COLUMNS) do
        local fontStr = colHdr.text[colour.key]
        if fontStr then
            fontStr:SetText(colour.header ~= "" and CUI.L(colour.header) or "")
        end
        local subText = colHdr.sub[colour.key]
        if subText then
            subText:SetText("")
        end
        -- Active sort column: bright header; the rest muted.
        local scrollBar = colHdr.sortBtns and colHdr.sortBtns[colour.key]
        if scrollBar then
            local isActive = (colour.key == sortKey)
            scrollBar.active = isActive
            if fontStr then
                fontStr:SetTextColor(1, 1, 1, isActive and 1 or 0.45)
            end
        end
    end

    -- Second pass: measure, then place. A column holding only dashes collapses
    -- to its minimum width instead of reserving room it does not need.
    local widths, primW, subW, sum = scratchWidths, scratchPrim, scratchSub, 0
    wipe(widths)
    wipe(primW)
    wipe(subW)
    for index, colour in ipairs(cols) do
        local wp, ws, wt = colour.minW, 0, colour.minW
        if colour.kind == "icon" then
            wt = math.max(colour.minW, MeasuredWidth(colHdr.text[colour.key], 0))
            wp = wt
        elseif colour.kind == "text" then
            wp = MeasuredWidth(colHdr.text[colour.key], 0)
            for i = 1, #memberList do
                wp = math.max(wp, MeasuredWidth(rowList[i].text[colour.key], 0))
                if colour.sub then
                    ws = math.max(ws, MeasuredWidth(rowList[i].sub[colour.key], 0))
                end
            end
            if colour.sub == "inline" then
                -- The primary is sized per row here, so the column only has to
                -- fit the widest name plus its own extra.
                wt = math.max(colour.minW, MeasuredWidth(colHdr.text[colour.key], 0))
                for i = 1, #memberList do
                    local a = MeasuredWidth(rowList[i].text[colour.key], 0)
                    local b = MeasuredWidth(rowList[i].sub[colour.key], 0)
                    wt = math.max(wt, a + (b > 0 and (SUB_GAP + b) or 0))
                end
            else
                wp = math.max(wp, colour.minW)
                wt = wp + (ws > 0 and (SUB_GAP + ws) or 0)
            end
        end
        primW[index], subW[index], widths[index] = wp, ws, wt
        sum = sum + wt
    end
    for index = 1, #cols - 1 do
        sum = sum + (cols[index].gapAfter or COL_GAP)
    end
    sum = sum + PAD * 2

    PlaceInto(colHdr, cols, widths, primW, subW)
    for i = 1, #memberList do
        PlaceInto(rowList[i], cols, widths, primW, subW)
    end

    -- The header is laid out independently of the table, so with enough columns
    -- switched off the picker and title would overrun a table-width frame.
    local headerMin = math.max(
        PAD + MeasuredWidth(titleFS, 0) + COL_GAP + PICKER_W + HEADER_GAP + CLOSE_W + PAD,
        PAD + MeasuredWidth(subFS, 0) + PAD
    )
    sum = math.max(sum, headerMin)

    local Pix = CUI.PP
    local height = HEAD_H + COLHDR_H + #memberList * rowH + PAD
    -- Scale first: PP.Size snaps against the frame's current effective scale,
    -- so changing the scale afterwards would throw that snap away.
    local scale = tonumber(c.scale) or 1
    if scale < 0.5 then
        scale = 0.5
    elseif scale > 2 then
        scale = 2
    end
    window:SetScale(scale)
    if Pix and Pix.Size then
        Pix.Size(window, sum, height)
    else
        window:SetSize(sum, height)
    end
end

--------------------------------------------------------------------------------
--  Show, refresh, run picker
--------------------------------------------------------------------------------
ShowWindow = function(runRecord)
    if not runRecord then
        return
    end
    BuildWindow()
    currentRecord = runRecord
    Render(runRecord)
    ApplyPosition()
    window:Show()
end

RefreshWindowIfOpen = function()
    if window and window:IsShown() and currentRecord then
        Render(currentRecord)
    end
end
-- An open summary redraws its numbers after a Number Format change.
CludesUI.RegisterNumberFormatCallback(function()
    RefreshWindowIfOpen()
end)

ShowPicker = function(anchor)
    local runs = mod.RS_GetRuns()
    local itemList = {}
    for i = 1, #runs do
        local runRec = runs[i]
        itemList[#itemList + 1] = {
            text = RunLabel(runRec),
            onClick = function()
                ShowWindow(runRec)
            end,
        }
    end
    if #itemList == 0 then
        itemList[1] = {
            text = CludesUI.L("No runs recorded yet"),
            isDisabled = function()
                return true
            end,
        }
    end
    -- Hung below the picker, at least its width: a dropdown, not a cursor menu.
    CUI.ShowContextMenu(anchor, itemList, { below = true, minWidth = PICKER_W })
end

-- Opens the n-th most recent run (1 = newest).
function mod.RS_Show(index)
    local i = math.floor(tonumber(index) or 1)
    if i < 1 then
        i = 1
    end
    local runRec = mod.RS_GetRuns()[i]
    if not runRec then
        CUI.PrintError(CludesUI.L("No runs recorded yet"))
        return
    end
    ShowWindow(runRec)
end

-- Preview: a synthetic run so the panel can be checked without going into a
-- key. Built on demand and never written to the history. Row 3 deliberately
-- carries no score gain, which is what a member without a start baseline
-- looks like.
local PREVIEW_CLASSES = { "PALADIN", "PRIEST", "ROGUE", "DRUID", "MAGE" }
-- Protection, Holy, Assassination, Balance, Frost. Resolved through the
-- global when it exists; otherwise nil and the class icon fallback shows.
local PREVIEW_SPEC_IDS = { 66, 257, 259, 102, 64 }
local function PREVIEW_SPEC_ICON(i)
    return SpecIconForSpecID(PREVIEW_SPEC_IDS[i])
end
function mod.RS_ShowPreview()
    local R = Enum and Enum.LFGRole
    local memberList = {}
    for i = 1, 5 do
        memberList[i] = {
            name = "Preview " .. i,
            class = PREVIEW_CLASSES[i],
            role = R and ((i == 1 and R.Tank) or (i == 2 and R.Healer) or R.Damage),
            specIcon = PREVIEW_SPEC_ICON(i),
            ilvl = 316 + i * 3,
            score = 2950 + i * 90,
            scoreGain = (i ~= 3) and (6 + i * 3) or nil,
            damage = 30000000 + i * 8000000,
            dps = 21000 + i * 6000,
            damageTaken = 9200000 - i * 1200000,
            interrupts = 5 - i,
            deaths = i % 2,
        }
    end
    -- Same order the live panel gets from BuildMembers.
    SortMembers(memberList)
    -- SEASON UPDATE (cosmetic): the preview dungeon and its timer, as in the
    -- Mythic+ Timer's PREVIEW_RUN, and the members' item levels above. Resolve
    -- the dungeon name from its ID so the preview is localized by the client.
    -- Out of season the API returns nothing and the English name shows; it is
    -- not a translator key, so it is not wrapped in L().
    local mapName = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(585)
    ShowWindow({
        mapID = 585,
        mapName = PlainString(mapName) or "Voidscar Arena",
        level = 12,
        timeMS = 1380000,
        timeLimit = 1800,
        onTime = true,
        upgrades = 2,
        deaths = 3,
        timeLost = 15,
        meterAvailable = true,
        _matched = #memberList,
        finishedAt = time(),
        members = memberList,
    })
end

--------------------------------------------------------------------------------
--  Slash command
--------------------------------------------------------------------------------
SLASH_CUIMPLUS1 = "/ov"
SLASH_CUIMPLUS2 = "/cuimplus"
SlashCmdList.CUIMPLUS = function(message)
    if not Enabled() then
        CUI.PrintError(CludesUI.L("Run Summary is disabled in Mythic+ Tools."))
        return
    end
    local lower = message and message:lower() or ""
    if lower:find("preview", 1, true) then
        mod.RS_ShowPreview()
        return
    end
    mod.RS_Show(message and tonumber(message:match("%d+")))
end
