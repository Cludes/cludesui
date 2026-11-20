if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CUI_MythicTimer_KickEngine.lua
--  Kick Tracker (Mythic+ Tools): who in the group kicked what, and when each
--  member's interrupt comes back. The displays (nameplate icons, bars) read it;
--  it runs only while one of them is subscribed, and registers nothing before.
--
--  Who kicked: inside instanced combat no cast, aura or combat log line names
--  the kicker, but the game's own damage meter does keep an Interrupts count
--  per group member, and each member's row carries their class, spec icon and
--  whether it is you, never hidden. A landed kick changes that data in the
--  same frame the enemy's cast stops: a member's row appears (their first kick
--  of the fight), a row moves up past another, or a member's list of kicked
--  enemy spells grows (fetched by their group GUID, which stays readable). Your
--  own kicks are your own casts, which land a moment after they are cast. A
--  member kicking a spell they kicked before changes nothing visible (the
--  spell is in their list already, and the count on it is hidden), so the
--  engine keeps, per member, which spells their list is known to hold: a
--  member's first kick of a spell, paired with the one plate kicked then,
--  names the entry; an entry that landed unpaired (two kicks in one update, a
--  mob with no plate, a fight joined late) could be anything. A kick that
--  changes nothing is then the one member whose list holds the plate's spell.
--  Where the spell is hidden too (a key), such a kick cannot be a member's
--  first (their list would have grown), and the rows sit in count order, so a
--  member whose row sits right under a member known to be tied with them did
--  not kick either: their count would have passed and moved their row (the
--  engine bounds each hidden count by what it saw). Only those proofs name a
--  kicker; the engine never guesses.
--
--  Every other kick still reaches the displays, exactly: each update also
--  carries a gate packet, every member it named nobody for sure about with
--  their interrupt count before and after the update (hidden in combat). A
--  display hands both to a hidden status bar (the count before as its value,
--  the count after as its maximum), whose fill is whole while the count did
--  not move and short of whole once it rose; a clip hung from that fill's
--  edge shows the member's layer only while the fill is short. So the
--  member whose count rose, and only they, show the kick, with no value read
--  in Lua. Every update also hands the displays each member's count as read
--  (the counts event), so a display can take a member's count at the kick
--  it placed them for as a baseline and hide that kick's icon, the same way,
--  once their count has risen past it (KE.Count, KE.FightGen). A demon's
--  interrupts count under the demon (the meter keeps it as a source of its
--  own), so its warlock's count is read there.
--
--  Cooldowns: every member's interrupt and its cooldown come from
--  the parent's CludesUI.KickData, read for their class, spec and talents. Talents are read by
--  inspecting each member out of combat and outside a running key (a key
--  locks that data, and talents cannot change inside one), the spec also from
--  the meter's rows once their GUIDs are readable again. A kick the tracker
--  sees starts the kicker's modeled cooldown, yours from your own talents. Kicks that
--  stop nothing are known for you alone.
--
--  Secret discipline: the interrupter GUID and every meter amount are secret
--  in restricted content; they are only type-tested and handed to native
--  sinks, never compared, concatenated or keyed. Group GUIDs, classes, roles,
--  the rows' class, spec icon and local-player flags, and the breakdown list
--  lengths are plain, and those are all the engine reasons with.
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...

local KD, MTWhere = CludesUI.KickData, mod.MTWhere
if not (KD and MTWhere) then
    return
end

local KE = {}
mod.KickEngine = KE

local pairs, type, pcall, wipe, tostring, tonumber = pairs, type, pcall, wipe, tostring, tonumber
local GetTime = GetTime
local securecallfunction = securecallfunction

local Secret, PlainString = CludesUI.IsSecret, CludesUI.PlainString

local DM = C_DamageMeter
local INT = Enum.DamageMeterType and Enum.DamageMeterType.Interrupts
local DMG = Enum.DamageMeterType and Enum.DamageMeterType.DamageDone
local HEAL = Enum.DamageMeterType and Enum.DamageMeterType.HealingDone
local CUR = Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current
local ALL = Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Overall
local RT_COMBAT = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Combat
local RT_KEY = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.ChallengeMode
local RS_INACTIVE = Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
local INSPECT_CFG = Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
    or -1

local GROUP_UNITS = { "player", "party1", "party2", "party3", "party4" }
local PET_UNIT =
    { player = "pet", party1 = "partypet1", party2 = "partypet2", party3 = "partypet3", party4 = "partypet4" }
KE.GROUP_UNITS = GROUP_UNITS

-- Only nameplate tokens: a kick stops the same mob on every token that names
-- it, and a plate is the one the displays can use.
local NAMEPLATE_UNITS, NAMEPLATE_TOKENS = mod.NAMEPLATE_UNITS, mod.NAMEPLATE_TOKENS

local ELIM_SLACK = 1.5 -- seconds a modeled cooldown may be off by before it rules a member out
local OWN_WINDOW = 1.0 -- seconds after your kick cast within which a landed kick is yours
local PAIR_WINDOW = 0.25 -- seconds a plate's cast stop and the meter's update may lie apart (seen: the same frame)
local INSPECT_WAIT = 3 -- seconds for the inspect data to arrive
local INSPECT_RETRY = 10 -- seconds before a member out of inspect range is tried again
local INSPECT_FRESH = 60 -- seconds after which a member is inspected again (talent swaps before the key)

local EMPTY = {}
local INF = math.huge
local LEARN_TYPES = { DMG, HEAL, INT }
local LEARN_SESSIONS = { ALL, CUR }

--------------------------------------------------------------------------------
--  State
--------------------------------------------------------------------------------
local rosterMap = {} -- unit -> member record (built once per slot, reset on a new GUID)
local subs = {} -- key -> handlers { kick = fn, cooldown = fn, roster = fn }
local subCount = 0
local isActive = false
local eventTag -- event frame, built on the first activation
local ownT = -1 -- GetTime() of your last kick cast
local ownPending = false -- that cast has not been matched to a landed kick yet
local wasStopped = {} -- plate units whose cast was kicked this frame, waiting for the meter
local stoppedBy = {} -- their interrupter values (secret or plain)
local stoppedSpell = {} -- the spells those casts were (plain), false where hidden
local stoppedT = -1
local flushArmed = false
local rosterT = -1 -- GetTime() of the last roster sync (a roster storm syncs once per frame)
local rosterFlush = false -- a sync is queued for the end of a roster storm
local specIconOf = {} -- specID -> icon file ID (the meter's specIconID)
local specOfIcon = {} -- class token -> { [icon] = specID }
local keyMemo = {} -- class -> icon -> own -> the row key string, built once
local lastSession -- the Interrupts session the rows were last read from
local spareKeys, spareN = {}, {} -- the row buffers not holding the baseline
local spareA, spareG = {}, {} -- the same for each member's gate source: its count (hidden in combat) and entry count
local readPrevA, readPrevG = {}, {} -- the update's counts before it (Attribute; read by BuildGate in that frame)
local gateList, gatePrev, gateCur, gatePlates = {}, {}, {}, {} -- the gate packet (read at once by the displays)
local gateT = -1 -- the update the packet was built for
local countList = {} -- the counts event's members (read at once by the displays)
local fightGen = 0 -- bumped whenever the counts restart (a new fight, a reset, a load); KE.FightGen
local lateArmed = false -- a plate stop waits one frame for an update of its own (OnStop, LatePair)
local rosterGrew, leftX = {}, {} -- Attribute's scratch
local growth = {} -- Attribute's scratch: unit -> entries its list gained this update
local preNarrow = {} -- Pick's scratch: the candidates before the cooldown narrowing
local rowIdx, rowAt, rowScratch = {}, {}, {} -- TieNarrow's scratch: unit -> its one row's index (false: several), index -> unit

-- Attribution memory: the Current session's rows (keys "CLASS:icon", "*" for
-- you) in the engine's order, each member's breakdown entry count, what the
-- last meter update concluded (lastT) and from which row evidence (rowKey,
-- rowHow: a plate naming the kicked spell can settle an ambiguous answer
-- again), the one member whose list grew by one entry on it (learn: the
-- plate paired with it names that entry's spell) and when a plate event last
-- took it (pairedT: an attribution serves one frame's plates, or a later
-- frame's within PAIR_WINDOW while no frame has taken it).
-- `a` and `g`: each member's gate source (their demon's for a demon's
-- interrupt) as last read, its count and its entry count; `gated`: the last
-- update sent a gate packet a plate arriving later in its window can join.
local cache = {
    rows = {},
    n = {},
    a = {},
    g = {},
    frameT = -1,
    lastT = -1,
    pairedT = -1,
    who = nil,
    scratch = nil,
    how = nil,
    rowKey = nil,
    rowHow = nil,
    learn = nil,
    gated = false,
    grew = false,
}

local function NewMember(unitToken)
    local m = { unit = unitToken, lastSure = false }
    rosterMap[unitToken] = m
    return m
end

local function Dispatch(name, ...)
    for _, hgt in pairs(subs) do
        local func = hgt[name]
        if func then
            securecallfunction(func, ...)
        end
    end
end

--------------------------------------------------------------------------------
--  Specs
--------------------------------------------------------------------------------
-- The meter's rows name a spec by its icon; each class's specs map their icon
-- back to the spec ID (built once per class).
local function IconSpecs(classID, classFile)
    local tbl = specOfIcon[classFile]
    if tbl then
        return tbl
    end
    tbl = {}
    specOfIcon[classFile] = tbl
    local num = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    for i = 1, num do
        local ident, _, _, iconTex = GetSpecializationInfoForClassID(classID, i)
        if ident and iconTex then
            tbl[iconTex] = ident
            specIconOf[ident] = iconTex
        end
    end
    return tbl
end

-- The icon the meter's rows show for a member's spec, from their class's
-- spec list.
local function IconOf(classID, classFile, specID)
    if not (classID and classFile and specID) then
        return nil
    end
    IconSpecs(classID, classFile)
    return specIconOf[specID]
end

--------------------------------------------------------------------------------
--  Cooldown model
--------------------------------------------------------------------------------
local function StartCd(m, start, dur)
    m.downAt, m.downFor, m.readyAt = start, dur, start + dur
    Dispatch("cooldown", m.unit, start, dur)
end

local function ClearCd(m)
    if not m.downAt then
        return
    end
    m.downAt, m.downFor, m.readyAt = nil, nil, nil
    Dispatch("cooldown", m.unit, nil, nil)
end

-- The member's interrupt and its cooldowns from what is known of them.
local function ResolveKick(m)
    local kickRec, cd, landed, minCd
    local specInfo = m.specID
    if m.class then
        if m.unit == "player" then
            -- Your own: the spellbook knows (a demon's interrupt included).
            kickRec = CludesUI.GetActiveKickSpell()
            if kickRec and not KD.INTERRUPTS[kickRec] then
                kickRec = KD.OwnCastKick(kickRec)
            end
            if not kickRec then
                kickRec, specInfo = KD.KickSpell(m.class, m.specID, m.role, m.talents, m.pet)
            end
        else
            kickRec, specInfo = KD.KickSpell(m.class, m.specID, m.role, m.talents, m.pet)
        end
        if kickRec then
            cd, landed = KD.Cooldown(kickRec, specInfo, m.talents)
            -- The shortest the landed cooldown could be, with every cooldown
            -- talent: what a member whose talents were never read is held to.
            local _, shortest = KD.Cooldown(kickRec, specInfo, KD.WATCHED_TALENTS)
            minCd = shortest
        end
    end
    local didChange = (m.kick ~= (kickRec or false))
        or (m.cd ~= cd)
        or (m.landedCd ~= landed)
        or (m.minCd ~= minCd)
    m.kick, m.cd, m.landedCd, m.minCd = kickRec or false, cd, landed, minCd
    return didChange
end

--------------------------------------------------------------------------------
--  Roster
--------------------------------------------------------------------------------
local function UnitOfGUID(g)
    if type(g) ~= "string" or Secret(g) then
        return nil
    end
    for i = 1, #GROUP_UNITS do
        local member = rosterMap[GROUP_UNITS[i]]
        if member and member.guid == g then
            return GROUP_UNITS[i]
        end
    end
    return nil
end

-- The demons with an interrupt, by creature ID (the pet's GUID names it on
-- every client; the family name the client gives is in its own language).
local DEMON_BY_NPC =
    { [417] = "Felhunter", [17252] = "Felguard", [58965] = "Wrathguard", [110397] = "Wrathguard" }

local function PetFamily(unitToken)
    local pet = PET_UNIT[unitToken]
    if not (pet and UnitExists(pet)) then
        return nil
    end
    local g = PlainString(UnitGUID(pet))
    local npc = g and tonumber(g:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if npc and DEMON_BY_NPC[npc] then
        return DEMON_BY_NPC[npc]
    end
    local success, fam = pcall(UnitCreatureFamily, pet)
    if success then
        return PlainString(fam)
    end
    return nil
end

local AskRead, RefreshPlayer

local function IsPlayerUnit(unitToken)
    local success, val = pcall(UnitIsPlayer, unitToken)
    return success and val == true
end

-- Reads every slot: a new GUID resets the record (and asks for an inspect),
-- an empty slot clears it. Role, pet and the kick are re-read every time.
local function SyncRoster()
    local nowTime = GetTime()
    local didChange = false
    for i = 1, #GROUP_UNITS do
        local unitToken = GROUP_UNITS[i]
        local member = rosterMap[unitToken] or NewMember(unitToken)
        -- Players only: a delve companion or a follower NPC in the slot is an
        -- empty slot (no row, no inspect).
        if UnitExists(unitToken) and (unitToken == "player" or IsPlayerUnit(unitToken)) then
            local unitGuid = PlainString(UnitGUID(unitToken))
            if unitGuid ~= member.guid then
                wipe(member)
                member.unit, member.guid, member.lastSure = unitToken, unitGuid, false
                didChange = true
                -- A new occupant is read whatever the slot's last read did.
                if unitGuid and unitToken ~= "player" then
                    AskRead(unitToken, true)
                end
            end
            -- A read that comes back hidden (UnitClass and the role are secret
            -- while a unit's identity is restricted) keeps the last plain
            -- value: the same occupant has the same class, and a new one wiped
            -- the record above.
            local _, classFile, classID = UnitClass(unitToken)
            classFile = PlainString(classFile)
            if classFile then
                member.class = classFile
                member.classID = (type(classID) == "number" and not Secret(classID)) and classID or member.classID
            end
            local success, role = pcall(UnitGroupRolesAssigned, unitToken)
            role = success and PlainString(role) or nil
            if role then
                member.role = role
            end
            if member.class == "WARLOCK" then
                member.pet = PetFamily(unitToken)
            end
            if member.class and member.classID then
                IconSpecs(member.classID, member.class)
            end
            if unitToken == "player" then
                if RefreshPlayer(member, true) then
                    didChange = true
                end
            elseif ResolveKick(member) then
                didChange = true
            end
        elseif member.guid or member.class then
            wipe(member)
            member.unit, member.lastSure = unitToken, false
            didChange = true
        end
    end
    if didChange then
        Dispatch("roster", nowTime)
    end
end

-- Your own spec and talents (IsPlayerSpell), read directly. Returns whether
-- the kick changed; dispatches unless the caller does (quiet).
RefreshPlayer = function(m, quiet)
    m = m or rosterMap.player
    if not m then
        return false
    end
    local position = C_SpecializationInfo.GetSpecialization()
    local ident = position and C_SpecializationInfo.GetSpecializationInfo(position)
    m.specID = (type(ident) == "number" and ident > 0) and ident or nil
    m.specIcon = IconOf(m.classID, m.class, m.specID)
    m.specSrc = "self"
    local tbl = m.talents or {}
    wipe(tbl)
    for spellRef in pairs(KD.WATCHED_TALENTS) do
        if IsPlayerSpell(spellRef) then
            tbl[spellRef] = true
        end
    end
    m.talents = tbl
    m.pet = PetFamily("player")
    local didChange = ResolveKick(m)
    if didChange and not quiet then
        Dispatch("roster", GetTime())
    end
    return didChange
end

--------------------------------------------------------------------------------
--  Inspect: one member at a time, out of combat and outside a running key,
--  with the game's own inspect window closed. Their spec and the talents the
--  data table watches are read from the inspect talent config.
--------------------------------------------------------------------------------
local readList = {} -- unit list, in order
local readAsked = {} -- unit -> true
local readingUnit, readingGuid -- the request in flight
local readWait = false -- a retry is scheduled

local function KeyActive()
    if not (RT_KEY and C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive) then
        return false
    end
    local success, val = pcall(C_RestrictedActions.IsAddOnRestrictionActive, RT_KEY)
    return success and val == true
end

-- Your own casts (OnOwnCast): yours, and your demon's when you are a warlock
-- (Spell Lock and Axe Toss are the demon's spells). Nobody else's: another
-- member's casts, their demon's included, never reach this client on a
-- dungeon map (field 2026-10-21: an unfiltered listener heard none), and
-- the meter credits their kicks through their row. Registered at Activate,
-- after the roster read gave your class; a hunter's pet is never listened to.
local function RegisterOwnCasts()
    local me = rosterMap.player
    if me and me.class == "WARLOCK" then
        eventTag:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
    else
        eventTag:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end
end

-- For /cuikt: the units whose casts are heard, the key state and each
-- member's class, spec icon and kick, one line.
function KE.Listening()
    local me = rosterMap.player
    local units = (me and me.class == "WARLOCK") and "player pet" or "player"
    local members = {}
    for i = 1, #GROUP_UNITS do
        local member = rosterMap[GROUP_UNITS[i]]
        if member and member.guid then
            members[#members + 1] = member.unit
                .. " "
                .. tostring(member.class)
                .. ":"
                .. tostring(member.specIcon)
                .. " "
                .. tostring(member.kick)
        end
    end
    return "casts heard: "
        .. units
        .. (KeyActive() and " (key)" or "")
        .. " | roster: "
        .. (#members > 0 and table.concat(members, ", ") or "empty")
end

-- Whether the player's own inspect window, or the talent view it opens, is up.
local function InspectWindowUp()
    local frame = InspectFrame
    if frame and frame:IsShown() then
        return true
    end
    local ps = PlayerSpellsFrame
    return (ps and ps.IsInspecting and ps:IsInspecting()) and true or false
end

local function MayReadNow()
    if InCombatLockdown() or KeyActive() then
        return false
    end
    return not InspectWindowUp()
end

local function ReadTree()
    if not (C_Traits and C_Traits.HasValidInspectData and C_Traits.HasValidInspectData()) then
        return nil
    end
    local details = C_Traits.GetConfigInfo(INSPECT_CFG)
    local trees = details and details.treeIDs
    if type(trees) ~= "table" then
        return nil
    end
    local watched = KD.WATCHED_TALENTS
    local set = {}
    local any = false
    for t = 1, #trees do
        local nodes = C_Traits.GetTreeNodes(trees[t])
        if type(nodes) == "table" then
            for i = 1, #nodes do
                local ni = C_Traits.GetNodeInfo(INSPECT_CFG, nodes[i])
                local record = ni and ni.activeEntry
                if record and type(ni.activeRank) == "number" and ni.activeRank > 0 then
                    any = true
                    local ei = C_Traits.GetEntryInfo(INSPECT_CFG, record.entryID)
                    local defID = ei and ei.definitionID
                    if defID then
                        local di = C_Traits.GetDefinitionInfo(defID)
                        local spellRef = di and di.spellID
                        if spellRef and watched[spellRef] then
                            set[spellRef] = true
                        end
                    end
                end
            end
        end
    end
    -- A tree with nothing active was not really read (data that arrived
    -- empty).
    if not any then
        return nil
    end
    return set
end

local ReadNext

local function ReadLater(delay)
    if readWait then
        return
    end
    readWait = true
    C_Timer.After(delay, function()
        readWait = false
        if isActive then
            ReadNext()
        end
    end)
end

local function DoneReading()
    readingUnit, readingGuid = nil, nil
    if eventTag then
        eventTag:UnregisterEvent("INSPECT_READY")
    end
    -- An inspect the player's own window opened meanwhile is theirs to keep.
    if ClearInspectPlayer and not InspectWindowUp() then
        pcall(ClearInspectPlayer)
    end
end

local function OnReadReady(unitGuid)
    if not readingUnit or Secret(unitGuid) or unitGuid ~= readingGuid then
        return
    end
    local unitToken = readingUnit
    local member = rosterMap[unitToken]
    if member and member.guid == unitGuid then
        local get = C_SpecializationInfo.GetInspectSpecialization
        local success, specInfo = pcall(get, unitToken)
        if success and type(specInfo) == "number" and not Secret(specInfo) and specInfo > 0 then
            member.specID, member.specSrc = specInfo, "inspect"
            member.specIcon = IconOf(member.classID, member.class, specInfo)
        end
        local talents = ReadTree()
        if talents then
            member.talents = talents
            member.readAt = GetTime()
            member.readTries = nil
        end
        if ResolveKick(member) then
            Dispatch("roster", GetTime())
        end
    end
    DoneReading()
    readAsked[unitToken] = nil
    ReadNext()
end

-- A member whose data never came goes to the back of the queue; after
-- INSPECT_TRIES the slot waits for the next stale check or a new occupant.
local INSPECT_TRIES = 3
local function ReadTimedOut(unitGuid)
    if readingUnit and readingGuid == unitGuid then
        local unitToken = readingUnit
        DoneReading()
        local member = rosterMap[unitToken]
        local tries = ((member and member.readTries) or 0) + 1
        if member then
            member.readTries = tries
        end
        if tries < INSPECT_TRIES then
            readList[#readList + 1] = unitToken
        else
            readAsked[unitToken] = nil
        end
        ReadLater(INSPECT_RETRY)
    end
end

ReadNext = function()
    if not isActive or readingUnit or #readList == 0 then
        return
    end
    if not MayReadNow() then
        ReadLater(INSPECT_RETRY)
        return
    end
    for i = 1, #readList do
        local unitToken = readList[i]
        local member = rosterMap[unitToken]
        local unitGuid = member and member.guid
        if not (unitGuid and UnitExists(unitToken) and UnitIsConnected(unitToken)) then
            table.remove(readList, i)
            readAsked[unitToken] = nil
            ReadNext()
            return
        end
        if CanInspect(unitToken) then
            table.remove(readList, i)
            readingUnit, readingGuid = unitToken, unitGuid
            eventTag:RegisterEvent("INSPECT_READY")
            NotifyInspect(unitToken)
            C_Timer.After(INSPECT_WAIT, function()
                ReadTimedOut(unitGuid)
            end)
            return
        end
    end
    -- Everyone queued is out of range: try again later.
    ReadLater(INSPECT_RETRY)
end

-- renew: a new occupant of the slot is read even where the last read of
-- that slot still counts as asked (one already queued is read in its turn).
AskRead = function(unitToken, renew)
    if unitToken == "player" then
        return
    end
    if readAsked[unitToken] then
        if not renew then
            return
        end
        for i = 1, #readList do
            if readList[i] == unitToken then
                return
            end
        end
    end
    readAsked[unitToken] = true
    readList[#readList + 1] = unitToken
    if isActive then
        ReadNext()
    end
end

-- Members whose talents were read a while ago are read again (a talent swap
-- before the key), while a key is not running.
local function ReReadStale()
    if KeyActive() then
        return
    end
    local nowTime = GetTime()
    for i = 2, #GROUP_UNITS do
        local member = rosterMap[GROUP_UNITS[i]]
        if member and member.guid and (not member.readAt or nowTime - member.readAt >= INSPECT_FRESH) then
            AskRead(GROUP_UNITS[i])
        end
    end
end

--------------------------------------------------------------------------------
--  Meter reads
--------------------------------------------------------------------------------
-- The Current session's interrupt rows as keys in the engine's order, and each
-- member's breakdown entry count (the enemy spells they have kicked this
-- fight), fetched by their readable group GUID.
-- The key naming a row ("CLASS:icon", "*" for you): one string per
-- combination, built the first time it is seen.
local function RowKey(cls, iconTex, loc)
    -- An enemy's or a pet's row carries no class and no spec icon: "-" for
    -- each, since a nil cannot index the memo.
    local c = Secret(cls) and "?" or (cls == nil and "-" or tostring(cls))
    local ic = Secret(iconTex) and "?" or (iconTex == nil and "-" or iconTex)
    local own = (not Secret(loc) and loc == true) and true or false
    local byCls = keyMemo[c]
    if not byCls then
        byCls = {}
        keyMemo[c] = byCls
    end
    local byIcon = byCls[ic]
    if not byIcon then
        byIcon = {}
        byCls[ic] = byIcon
    end
    local k = byIcon[own]
    if not k then
        k = c .. ":" .. tostring(ic) .. (own and "*" or "")
        byIcon[own] = k
    end
    return k
end

-- The session's own ID, where it is readable.
local function SessionID(cfg)
    if type(cfg) ~= "table" or Secret(cfg) then
        return nil
    end
    local ident = cfg.sessionID
    if type(ident) == "number" and not Secret(ident) then
        return ident
    end
    return nil
end

-- One source's breakdown by its readable GUID: its entry count (plain) and
-- its interrupt count (hidden in combat; only ever handed on), or nil.
local function ReadSource(g)
    local success, skinData = pcall(DM.GetCombatSessionSourceFromType, CUR, INT, g)
    if success and type(skinData) == "table" and not Secret(skinData) then
        local sp = skinData.combatSpells
        if type(sp) == "table" and not Secret(sp) then
            return #sp, skinData.totalAmount
        end
    end
    return nil, nil
end

-- Whether a member's interrupt is their demon's (Spell Lock, Axe Toss), and
-- the demon's GUID where readable (a group member's pet is player-controlled,
-- so it is). The meter keeps a demon as a source of its own: the demon's
-- count is the one its kicks move.
local function DemonGUID(unit, m)
    local k = m.kick and KD.INTERRUPTS[m.kick]
    if not (k and k.pet) then
        return false, nil
    end
    local pet = PET_UNIT[unit]
    if not (pet and UnitExists(pet)) then
        return true, nil
    end
    return true, PlainString(UnitGUID(pet))
end

-- Fills the caller's tables and returns the first two with the session's ID:
-- the rows' keys, each member's entry count, and, for every member but you,
-- their gate source's count (amap) and entry count (gmap): their own, or
-- their demon's. A demon with no readable source of its own takes the one
-- row the meter keeps for a warlock with no spec icon, while one warlock in
-- the group has a demon's interrupt (that row then can be no one else's).
local function ReadRows(keyList, nmap, auraMap, guidMap)
    wipe(keyList)
    wipe(nmap)
    wipe(auraMap)
    wipe(guidMap)
    local spellRef
    local demonRows, demonRowAmt = 0, nil
    local success, s = pcall(DM.GetCombatSessionFromType, CUR, INT)
    if success and type(s) == "table" and not Secret(s) then
        spellRef = SessionID(s)
        local source = s.combatSources
        if type(source) == "table" and not Secret(source) then
            for i = 1, #source do
                local region = source[i]
                if type(region) == "table" and not Secret(region) then
                    local k = RowKey(region.classFilename, region.specIconID, region.isLocalPlayer)
                    keyList[i] = k
                    if k == "WARLOCK:-" then
                        demonRows = demonRows + 1
                        demonRowAmt = region.totalAmount
                    end
                else
                    keyList[i] = "?"
                end
            end
        end
    end
    local demonUnit, demons = nil, 0
    for i = 1, #GROUP_UNITS do
        local unit = GROUP_UNITS[i]
        local member = rosterMap[unit]
        local g = member and member.guid
        if g then
            local num, amt = ReadSource(g)
            if num then
                nmap[unit] = num
            end
            if i > 1 then
                local isDemon, pg = DemonGUID(unit, member)
                if isDemon then
                    demons = demons + 1
                    local pn, pamt
                    if pg then
                        pn, pamt = ReadSource(pg)
                    end
                    if pn and pn > 0 then
                        guidMap[unit], auraMap[unit] = pn, pamt
                    else
                        demonUnit = unit
                    end
                elseif num then
                    guidMap[unit], auraMap[unit] = num, amt
                end
            end
        end
    end
    if demonUnit and demons == 1 and demonRows == 1 and demonRowAmt ~= nil then
        -- A row exists only once its source interrupted: one entry at least.
        guidMap[demonUnit], auraMap[demonUnit] = 1, demonRowAmt
    end
    return keyList, nmap, spellRef
end

-- What each member's Interrupts list is known to hold, kept on the record:
-- `known` (enemy spell ID -> true) and `holes`, the entries whose spell the
-- engine never learned. Every read of the counts keeps them in step: an entry
-- that appeared is a hole until the plate paired with it names its spell, a
-- list that shrank restarted with a new fight, and a record read for the
-- first time holds nothing but holes. The record's interrupt count bounds
-- (`lo`, `hi`) start there too: nothing seen yet, and no ceiling while
-- entries the engine never saw land are already there (Bound keeps them).
local function SyncLists(nmap, prevN)
    for i = 1, #GROUP_UNITS do
        local unit = GROUP_UNITS[i]
        local member = rosterMap[unit]
        if member then
            local num = nmap[unit] or 0
            if not member.known then
                member.known, member.holes = {}, num
                member.lo, member.hi = 0, (num > 0) and INF or 0
            else
                local previous = prevN[unit] or 0
                if num < previous then
                    wipe(member.known)
                    member.holes = num
                    member.lo, member.hi = 0, (num > 0) and INF or 0
                elseif num > previous then
                    member.holes = member.holes + (num - previous)
                end
            end
        end
    end
end

-- Forgets every list: the next read holds nothing but holes. The counts
-- restarted with them (a new fight), which the displays' count gates need to
-- know (KE.FightGen).
local function ResetLists()
    for _, m in pairs(rosterMap) do
        m.known, m.holes = nil, nil
    end
    fightGen = fightGen + 1
end

-- A member whose count could not be read keeps the count last read, so a
-- failed read is neither a shrink nor, when it reads again, a growth (nor,
-- for the gate source, a rise the read before it would then miss).
local function CarryCounts(nmap, auraMap, guidMap)
    for i = 1, #GROUP_UNITS do
        local unit = GROUP_UNITS[i]
        if nmap[unit] == nil then
            nmap[unit] = cache.n[unit]
        end
        if auraMap[unit] == nil and guidMap[unit] == nil then
            auraMap[unit], guidMap[unit] = cache.a[unit], cache.g[unit]
        end
    end
end

-- Whether a read shrank (fewer rows, or a member's count fell: a new fight)
-- and whether it rose (a row or a count more) against a baseline.
local function ListsMoved(keyList, nmap, prevKeys, prevN)
    local shrank, rose = #keyList < #prevKeys, #keyList > #prevKeys
    for i = 1, #GROUP_UNITS do
        local unit = GROUP_UNITS[i]
        local num, previous = nmap[unit] or 0, prevN[unit] or 0
        if num < previous then
            shrank = true
        elseif num > previous then
            rose = true
        end
    end
    return shrank, rose
end

-- A new baseline: the rows of a fight the engine has not read yet. The
-- current-session event also fires through combat, where the session's ID
-- is hidden, so whether this is still the session the baseline came from is
-- judged by the counts: one that fell is a new fight (the lists restarted
-- with it); one that rose is a kick whose own Interrupts update, in this
-- frame, reads it (adopted here, that kick would read as nothing new), so
-- the baseline stays. A reset or a load forces it and forgets the lists.
local function Rebase(force)
    local newSession = force
    if not force then
        if GetTime() == cache.frameT then
            return
        end
        local success, s = pcall(DM.GetCombatSessionFromType, CUR, INT)
        local spellRef = success and SessionID(s) or nil
        if spellRef ~= nil then
            if spellRef == lastSession then
                return
            end
            newSession = true
        end
    end
    local k, num, spellRef = ReadRows(spareKeys, spareN, spareA, spareG)
    local a, g = spareA, spareG
    CarryCounts(num, a, g)
    if not newSession then
        local shrank, rose = ListsMoved(k, num, cache.rows, cache.n)
        if rose and not shrank then
            return
        end
        newSession = shrank
    end
    if newSession then
        ResetLists()
    end
    SyncLists(num, cache.n)
    spareKeys, spareN, spareA, spareG = cache.rows, cache.n, cache.a, cache.g
    cache.rows, cache.n, cache.a, cache.g, lastSession = k, num, a, g, spellRef
    -- A new baseline: no gate packet is pending against the old one.
    cache.gated = false
end

-- Each member's spec icon from the meter's rows, where the GUIDs are readable
-- (out of restricted combat). An inspect's answer is never overwritten.
local function ReadSpecs()
    if InCombatLockdown() then
        return
    end
    local didChange = false
    for t = 1, #LEARN_TYPES do
        for s = 1, #LEARN_SESSIONS do
            local success, sess = pcall(DM.GetCombatSessionFromType, LEARN_SESSIONS[s], LEARN_TYPES[t])
            if success and type(sess) == "table" and not Secret(sess) then
                local source = sess.combatSources
                if type(source) == "table" and not Secret(source) then
                    for i = 1, #source do
                        local region = source[i]
                        if type(region) == "table" and not Secret(region) then
                            local unitToken = UnitOfGUID(region.sourceGUID)
                            local iconTex = region.specIconID
                            local m = unitToken and rosterMap[unitToken]
                            if
                                m
                                and unitToken ~= "player"
                                and m.specSrc ~= "inspect"
                                and type(iconTex) == "number"
                                and not Secret(iconTex)
                            then
                                local map = m.class and m.classID and IconSpecs(m.classID, m.class)
                                local specInfo = map and map[iconTex]
                                if m.specIcon ~= iconTex or m.specID ~= specInfo then
                                    m.specIcon, m.specID, m.specSrc = iconTex, specInfo, "meter"
                                    if ResolveKick(m) then
                                        didChange = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if didChange then
        Dispatch("roster", GetTime())
    end
end

-- The members a row key ("CLASS:icon", "*" for you) can belong to: those of
-- the class who have an interrupt (a healer paladin has none, so a Ret's row
-- is never theirs) and whose spec, where known, the icon names. A row with no
-- icon ("CLASS:-": the meter knows no spec for its source, as it filed a
-- warlock's demon kicks in the field, 2026-10-21) names its member by class
-- alone, whatever spec an inspect gave them.
local function KeyUnits(key, result)
    wipe(result)
    if key:sub(-1) == "*" then
        result[1] = "player"
        return result
    end
    local cls, iconTex = key:match("^([^:]+):([^:%*]+)")
    iconTex = tonumber(iconTex)
    for i = 2, #GROUP_UNITS do
        local member = rosterMap[GROUP_UNITS[i]]
        if
            member
            and member.guid
            and member.kick
            and member.class == cls
            and (iconTex == nil or member.specIcon == nil or member.specIcon == iconTex)
        then
            result[#result + 1] = GROUP_UNITS[i]
        end
    end
    return result
end

-- A row attributed to one member for sure names their spec by its icon: a
-- member not inspected yet (inside a key no inspect runs and the meter's
-- GUIDs stay hidden) learns it from their own row, and the displays switch
-- from their class icon to the spec's.
local function LearnRow(m, key, T)
    if not m or m.specSrc == "inspect" or m.specIcon ~= nil then
        return
    end
    local cls, iconTex = key:match("^([^:]+):([^:%*]+)")
    iconTex = tonumber(iconTex)
    if not iconTex or cls ~= m.class then
        return
    end
    local map = m.classID and IconSpecs(m.classID, m.class)
    m.specIcon, m.specID, m.specSrc = iconTex, map and map[iconTex] or nil, "row"
    ResolveKick(m)
    Dispatch("roster", T)
end

--------------------------------------------------------------------------------
--  Attribution
--------------------------------------------------------------------------------
local scratch = {}
local kept = {}

-- Every member but you who has an interrupt.
local function AllOthers(result)
    wipe(result)
    for i = 2, #GROUP_UNITS do
        local member = rosterMap[GROUP_UNITS[i]]
        if member and member.guid and member.kick then
            result[#result + 1] = GROUP_UNITS[i]
        end
    end
    return result
end

-- The member's interrupt is still on cooldown from a kick that was theirs
-- for sure. A member whose talents were never read is held to the shortest
-- cooldown they could have (a cooldown talent the engine does not know of
-- lets them kick sooner than the plain cooldown says).
local function StillDown(m, T)
    local cd = m.talents and m.landedCd or m.minCd
    local last = m.lastSure and m.lastKick
    return (cd and last and T - last < cd - ELIM_SLACK) and true or false
end

-- The members of `list` whose modeled interrupt could be ready.
local function Eliminate(entries, T)
    wipe(kept)
    for i = 1, #entries do
        local member = rosterMap[entries[i]]
        if not (member and StillDown(member, T)) then
            kept[#kept + 1] = entries[i]
        end
    end
    return kept
end

-- Narrows a candidate list by cooldown. Returns who (one left), how, and the
-- list while several are left.
local function Narrow(entries, T, method)
    if #entries > 1 then
        local leftX = Eliminate(entries, T)
        if #leftX > 0 and #leftX < #entries then
            wipe(entries)
            for i = 1, #leftX do
                entries[i] = leftX[i]
            end
            method = "cooldown"
        end
    end
    if #entries == 1 then
        return entries[1], method or "only", nil
    end
    if #entries == 0 then
        return nil, "unknown", nil
    end
    return nil, "ambiguous", entries
end

-- Interrupt counts the meter keeps hidden, bounded by what the engine saw
-- (lo..hi on the record; hi INF once a mass interrupt, or a read of entries
-- it never saw land, left the count unknowable). The meter's rows sit in
-- count order, so a member whose count passed the member above would have
-- moved: a kick that moved no row is not theirs while the two are known to
-- be tied. Bounds only ever loosen where the engine is unsure.
local function Loosen(entries)
    for i = 1, #entries do
        local member = rosterMap[entries[i]]
        if member and member.hi then
            member.hi = member.hi + 1
        end
    end
end

-- A kick any member with entries may have landed, none of it visible.
local function LoosenAll()
    for i = 1, #GROUP_UNITS do
        local unit = GROUP_UNITS[i]
        local member = rosterMap[unit]
        if member and member.hi and (cache.n[unit] or 0) > 0 then
            member.hi = member.hi + 1
        end
    end
end

-- The member landed `d` kicks for sure; `exact` while the count rose by no
-- more than that.
local function Count(m, skinData, exact)
    if not (m and m.lo) then
        return
    end
    m.lo = m.lo + skinData
    m.hi = exact and (m.hi + skinData) or INF
end

-- The members of `list` with entries: a kick that changed nothing cannot be
-- a member's first (their list would have grown).
local function Entered(entries)
    local num = 0
    for i = 1, #entries do
        if (cache.n[entries[i]] or 0) > 0 then
            num = num + 1
            entries[num] = entries[i]
        end
    end
    for i = #entries, num + 1, -1 do
        entries[i] = nil
    end
    return entries
end

-- The one member with entries a row names, or nil: an enemy's or a hidden
-- row, or a key two such members share.
local function RowMember(key)
    local entries = Entered(KeyUnits(key, rowScratch))
    return #entries == 1 and entries[1] or nil
end

-- The members of `list` whose unseen kick the meter's order allows: a
-- member whose row sits right under a member known to be tied with them is
-- out (their count would have passed the other's and moved their row). Only
-- rows that name one member, each named by one row, take part.
local function TieNarrow(entries)
    wipe(rowIdx)
    wipe(rowAt)
    local rowList = cache.rows
    for i = 1, #rowList do
        local u = RowMember(rowList[i])
        if u then
            if rowIdx[u] == nil then
                rowIdx[u] = i
            else
                rowIdx[u] = false
            end
            rowAt[i] = u
        end
    end
    local num = 0
    for i = 1, #entries do
        local posX = entries[i]
        local keep = true
        local position = rowIdx[posX]
        if position and position > 1 then
            local a = rowAt[position - 1]
            if a and rowIdx[a] == position - 1 then
                local mx, ma = rosterMap[posX], rosterMap[a]
                if mx and ma and mx.lo and ma.hi and ma.hi <= mx.lo then
                    keep = false
                end
            end
        end
        if keep then
            num = num + 1
            entries[num] = posX
        end
    end
    for i = #entries, num + 1, -1 do
        entries[i] = nil
    end
    return entries
end

-- The members of `list` whose Interrupts list may hold `spell`: those known
-- to hold it, and those with entries the engine never learned (which could
-- be anything). A record never read may hold anything too.
local function MayHold(entries, spellRec)
    local num = 0
    for i = 1, #entries do
        local member = rosterMap[entries[i]]
        if member and (not member.known or member.holes > 0 or member.known[spellRec]) then
            num = num + 1
            entries[num] = entries[i]
        end
    end
    for i = #entries, num + 1, -1 do
        entries[i] = nil
    end
    return entries
end

-- Picks the kicker from a candidate list. With the kicked spell known, one
-- member whose list holds it for sure is the kicker (a repeat of a spell
-- they kicked before: the meter shows nothing new for it); with it hidden,
-- only members with entries could have kicked unseen, and `unseen` (the
-- kick moved no row) lets the meter's order rule out more. One left by
-- those deductions is the kicker; several are narrowed by cooldown.
local function Pick(entries, T, spellRec, unseen)
    local before = #entries
    if spellRec then
        MayHold(entries, spellRec)
        if #entries == 1 then
            local member = rosterMap[entries[1]]
            if member and member.known and member.known[spellRec] then
                return entries[1], "repeat", nil
            end
        end
    else
        Entered(entries)
    end
    if unseen then
        TieNarrow(entries)
    end
    if #entries == 1 and before > 1 then
        return entries[1], "order", nil
    end
    wipe(preNarrow)
    for i = 1, #entries do
        preNarrow[i] = entries[i]
    end
    return Narrow(entries, T, nil)
end

-- Your cast is unresolved and `T` lies within its window after it.
local function OwnPending(T)
    return ownPending and T >= ownT and T - ownT <= OWN_WINDOW
end

local function RecordKick(m, T, sure)
    m.lastKick, m.lastSure = T, sure
    if m.unit == "player" then
        ownPending = false
        -- Your cast started its plain cooldown: the landed one replaces it
        -- from the same start (Coldthirst, Light of the Sun).
        if m.downAt and m.landedCd and m.downFor ~= m.landedCd and T - m.downAt <= OWN_WINDOW then
            StartCd(m, m.downAt, m.landedCd)
        end
    elseif m.landedCd then
        StartCd(m, T, m.landedCd)
    end
end

-- The one member whose list grew by one entry on the last update, paired
-- with the one plate kicked in this batch: that entry is the plate's spell.
-- Not while your own cast is unresolved: it may be the kick that stopped
-- this plate, the entry another member's kick of a mob with no plate.
local function PairLearn()
    local u = cache.learn
    if not u then
        return
    end
    cache.learn = nil
    if #wasStopped ~= 1 or OwnPending(GetTime()) then
        return
    end
    local spellRec = stoppedSpell[1]
    local member = rosterMap[u]
    if spellRec and member and member.known and member.holes > 0 then
        member.holes = member.holes - 1
        member.known[spellRec] = true
    end
end

-- The gate packet for update T: every member but you with an interrupt who
-- could have landed it (not still on cooldown from a kick that was theirs
-- for sure, which a sure kicker of this update is now too), with entries
-- before and after it (a member whose list grew is named by the list), and
-- their gate source's count before and after it, handed on as they are:
-- hidden in combat, never read here. Built in the update's own frame, from
-- the counts Attribute just read. Returns whether anyone is in it.
local function BuildGate(T)
    wipe(gateList)
    wipe(gatePrev)
    wipe(gateCur)
    gateT = T
    local pa, pg, ca, cg = readPrevA, readPrevG, cache.a, cache.g
    for i = 2, #GROUP_UNITS do
        local unit = GROUP_UNITS[i]
        local member = rosterMap[unit]
        if member and member.guid and member.kick and not StillDown(member, T) then
            local before, after = pa[unit], ca[unit]
            if before ~= nil and after ~= nil and (pg[unit] or 0) >= 1 and (cg[unit] or 0) >= 1 then
                gateList[#gateList + 1] = unit
                gatePrev[unit], gateCur[unit] = before, after
            end
        end
    end
    cache.gated = #gateList > 0
    return cache.gated
end

-- Sends the packet built for update T: with the plates stopped in its batch
-- when nobody was placed on them for sure, else for the bars alone; or, with
-- `platesOnly`, those plates joining the packet already sent (a plate whose
-- cast stopped after the meter's update, in its window).
local function SendGate(T, withPlates, platesOnly)
    if gateT ~= T or #gateList == 0 then
        return
    end
    wipe(gatePlates)
    if withPlates then
        for i = 1, #wasStopped do
            gatePlates[i] = wasStopped[i]
        end
    end
    if platesOnly and #gatePlates == 0 then
        return
    end
    Dispatch("gate", T, gateList, gatePrev, gateCur, gatePlates, platesOnly and true or false)
end

-- Reports the kick to the displays for each plate unit kicked this frame.
local function EmitStopped(T, caster, entries, method)
    for i = 1, #wasStopped do
        Dispatch("kick", wasStopped[i], caster, entries, stoppedBy[i], method, T)
    end
    wipe(wasStopped)
    wipe(stoppedBy)
    wipe(stoppedSpell)
    stoppedT = -1
end

-- Forward: Settle is defined below the pieces it settles with.
local Settle

-- Plate events the meter never answered within PAIR_WINDOW: their plates
-- show the hidden kicker only (your own unanswered cast does not claim them:
-- it may have missed, and your icon moved at the cast). A newer batch still
-- inside its window waits on.
local function FlushStopped()
    flushArmed = false
    if #wasStopped == 0 then
        return
    end
    local leftX = PAIR_WINDOW - (GetTime() - stoppedT)
    if leftX > 0.001 then
        flushArmed = true
        C_Timer.After(leftX, FlushStopped)
        return
    end
    EmitStopped(stoppedT, nil, nil, "unknown")
end

-- Settles who kicked from the evidence, best first: a member whose breakdown
-- grew, the member a new or moved row names, your own cast a moment ago, the
-- member whose list holds the kicked spell (where a plate named it), then
-- whoever is not on cooldown. grewBy: the entries the one grown list gained;
-- plates: the casts stopped in the batch paired with this. Returns who, how,
-- the list while several are left, and whether the answer is sure.
local function Decide(T, lineKey, rowHow, rosterGrew, grewBy, oneNew, spellRec, plates)
    local caster, method, entries
    if rosterGrew and #rosterGrew == 1 then
        caster, method = rosterGrew[1], "breakdown"
        -- The row that moved is the kicker's, and so is the one row that
        -- appeared with their first kick: either names their spec.
        if lineKey and (rowHow == "reorder" or oneNew) then
            LearnRow(rosterMap[caster], lineKey, T)
        end
        -- The meter counts every interrupt, a grip of a caster included.
        -- Several entries or several casts stopped at once is a grip of a
        -- whole pack; one while the member's kick cannot be ready is a grip
        -- too (your own, a cast of yours the engine never saw). Neither is a
        -- kick: nothing is placed and no cooldown starts.
        local member = rosterMap[caster]
        if grewBy > 1 or plates > 1 then
            return nil, "mass", nil, false
        elseif caster == "player" then
            if not OwnPending(T) then
                return nil, "grip", nil, false
            end
        elseif member and StillDown(member, T) then
            return nil, "grip", nil, false
        end
    elseif rosterGrew and #rosterGrew > 1 then
        -- Several lists grew at once: each of those members kicked (Settle
        -- records them all); which of them stopped this plate is narrowed
        -- among them alone.
        entries = scratch
        wipe(entries)
        for i = 1, #rosterGrew do
            entries[i] = rosterGrew[i]
        end
    elseif lineKey then
        entries = KeyUnits(lineKey, scratch)
        if #entries == 1 then
            caster, method, entries = entries[1], rowHow, nil
            LearnRow(rosterMap[caster], lineKey, T)
        elseif #entries == 0 then
            entries = nil
        end
    end
    if not caster and not entries then
        if OwnPending(T) then
            caster, method = "player", "cast"
        else
            caster, method, entries = Pick(AllOthers(scratch), T, spellRec, true)
        end
    elseif entries then
        caster, method, entries = Pick(entries, T, spellRec, false)
        if caster and method == "only" and rowHow then
            method = rowHow
        end
    end
    local sure = method == "cast"
        or method == "breakdown"
        or method == "new row"
        or method == "reorder"
        or method == "repeat"
        or method == "order"
    return caster, method, entries, sure
end

-- Keeps the count bounds in step with this update's verdict: a grown list
-- is that many kicks for sure (a mass interrupt or a grip: at least), a sure
-- kicker one more, an unsure one or an ambiguous list one more for each
-- member it could have been, and no answer at all one more for everyone.
local function Bound(caster, method, entries, rosterGrew)
    if rosterGrew and #rosterGrew > 0 then
        local exact = not (method == "mass" or method == "grip")
        for i = 1, #rosterGrew do
            local u = rosterGrew[i]
            Count(rosterMap[u], growth[u] or 1, exact)
        end
    elseif caster then
        if method == "only" or method == "cooldown" then
            Loosen(preNarrow)
        else
            Count(rosterMap[caster], 1, true)
        end
    elseif entries then
        Loosen(entries)
    else
        LoosenAll()
    end
end

-- Decides, records the kick and, with `emit`, tells the displays about the
-- plates waiting for it (the one plate kicked then names the spell).
Settle = function(T, lineKey, rowHow, rosterGrew, grewBy, emit, oneNew)
    local spellRec = emit and #wasStopped == 1 and stoppedSpell[1] or nil
    local caster, method, entries, sure =
        Decide(T, lineKey, rowHow, rosterGrew, grewBy, oneNew, spellRec, emit and #wasStopped or 0)
    Bound(caster, method, entries, rosterGrew)
    local several = rosterGrew and #rosterGrew > 1
    if several then
        -- Every member whose list grew kicked, whichever plate this was.
        for i = 1, #rosterGrew do
            local member = rosterMap[rosterGrew[i]]
            if member then
                RecordKick(member, T, true)
            end
        end
    elseif caster and sure then
        local member = rosterMap[caster]
        if member then
            RecordKick(member, T, true)
        end
    end
    -- Only a kicker named for sure is placed and timed; the gate packet shows
    -- any other answer exactly, by whose count rose, and any kick of another
    -- member this update hid. A grip (one, or a whole pack) is no kick: no
    -- packet. With several kickers named, which of them stopped this plate is
    -- not known: it gets nobody.
    local placed = (sure and not several) and caster or nil
    cache.lastT, cache.who, cache.scratch, cache.how = T, placed, entries, method
    cache.rowKey, cache.rowHow = lineKey, rowHow
    cache.grew = (rosterGrew and #rosterGrew > 0) and true or false
    cache.gated = false
    if method ~= "mass" and method ~= "grip" and BuildGate(T) then
        SendGate(T, emit and not placed and not several, false)
    end
    if emit then
        cache.pairedT = T
        PairLearn()
        EmitStopped(stoppedT, placed, entries, method)
    end
end

-- The first Interrupts-typed meter update of a frame against the last one.
local function Attribute()
    local T = GetTime()
    if T == cache.frameT then
        return
    end
    cache.frameT = T
    local keyList, nmap, spellRef = ReadRows(spareKeys, spareN, spareA, spareG)
    local auraMap, guidMap = spareA, spareG
    CarryCounts(nmap, auraMap, guidMap)
    local prevKeys, prevN, prevA, prevG = cache.rows, cache.n, cache.a, cache.g
    -- A count that fell: a new fight began without its session update, and
    -- the lists restarted with it.
    local shrank = ListsMoved(keyList, nmap, prevKeys, prevN)
    cache.rows, cache.n, cache.a, cache.g, lastSession = keyList, nmap, auraMap, guidMap, spellRef
    spareKeys, spareN, spareA, spareG = prevKeys, prevN, prevA, prevG
    if shrank then
        prevKeys, prevN, prevA, prevG = EMPTY, EMPTY, EMPTY, EMPTY
        ResetLists()
    end
    -- The counts before this update, for its gate packet (BuildGate).
    readPrevA, readPrevG = prevA, prevG
    SyncLists(nmap, prevN)
    -- Every member's count as read now, for the displays' count gates: a
    -- member with entries (so their count is one at least), never you.
    -- Handed on as read, hidden in combat; read at once, never kept.
    wipe(countList)
    for i = 2, #GROUP_UNITS do
        local unit = GROUP_UNITS[i]
        if (guidMap[unit] or 0) >= 1 and auraMap[unit] ~= nil then
            countList[#countList + 1] = unit
        end
    end
    if #countList > 0 then
        Dispatch("counts", T, countList, auraMap)
    end

    wipe(rosterGrew)
    wipe(growth)
    local grewBy = 0
    for u, num in pairs(nmap) do
        local skinData = num - (prevN[u] or 0)
        if skinData > 0 then
            rosterGrew[#rosterGrew + 1] = u
            growth[u] = skinData
            grewBy = skinData
        end
    end
    -- One member's list grew: by one entry, the plate paired with this
    -- update names its spell; by more, a grip of a pack.
    if #rosterGrew ~= 1 then
        grewBy = 0
    end
    cache.learn = (grewBy == 1) and rosterGrew[1] or nil
    local lineKey, rowHow, newCount = nil, nil, 0
    if #keyList > #prevKeys then
        wipe(leftX)
        for i = 1, #prevKeys do
            leftX[prevKeys[i]] = (leftX[prevKeys[i]] or 0) + 1
        end
        for i = 1, #keyList do
            local k = keyList[i]
            if (leftX[k] or 0) > 0 then
                leftX[k] = leftX[k] - 1
            else
                lineKey = k
                newCount = newCount + 1
            end
        end
        rowHow = "new row"
    elseif #keyList == #prevKeys then
        for i = 1, #keyList do
            if keyList[i] ~= prevKeys[i] then
                lineKey, rowHow = keyList[i], "reorder"
                break
            end
        end
    end
    -- A row no member can own (an enemy that interrupted a player) is no
    -- evidence of a kick.
    if lineKey and #KeyUnits(lineKey, scratch) == 0 then
        lineKey, rowHow = nil, nil
    end
    -- Plates whose cast stopped just before (the same frame, as seen in the
    -- field, or within the window) take this update's answer.
    local landedHere = stoppedT >= 0 and T - stoppedT <= PAIR_WINDOW
    -- A refresh with nothing new and no kick seen says nothing to read (any
    -- member with entries may have landed it, or an enemy that interrupted
    -- a player); the gate packet shows whoever's count rose, and a plate
    -- event a moment later joins it (OnStop).
    if not lineKey and #rosterGrew == 0 and not OwnPending(T) and not landedHere then
        LoosenAll()
        cache.lastT, cache.who, cache.scratch, cache.how = T, nil, nil, "none"
        cache.rowKey, cache.rowHow, cache.grew = nil, nil, false
        if BuildGate(T) then
            SendGate(T, false, false)
        end
        return
    end
    Settle(T, lineKey, rowHow, rosterGrew, grewBy, landedHere, newCount == 1)
end

-- The batch of plates stopped at stoppedT takes the meter's update at T0 (the
-- same frame's, or an earlier frame's no batch took yet): the plates are
-- emitted with its answer, decided again with the batch where it lacked one.
local function PairWith(T0)
    local T = stoppedT
    -- Nobody was placed on an update no list grew in: decided again with
    -- the batch it lacked. An update with nothing to read always is (a
    -- plate first gives the batch's size; its spell, plain outside a key,
    -- can name the one member whose list holds it); any other only with
    -- that spell named, and not over an unresolved cast of yours.
    local named = #wasStopped == 1 and stoppedSpell[1] or nil
    local none = cache.how == "none"
    if not cache.who and not cache.grew and (none or (named and not OwnPending(T))) then
        local caster, method, entries, sure = Decide(T0, cache.rowKey, cache.rowHow, nil, 0, false, named, #wasStopped)
        if caster and sure and method ~= "mass" and method ~= "grip" then
            local member = rosterMap[caster]
            if member then
                RecordKick(member, T0, true)
                Count(member, 1, true)
            end
            cache.who = caster
        end
        cache.scratch, cache.how = entries, method
    end
    cache.pairedT = T0
    PairLearn()
    -- Still nobody: the plate joins the update's gate packet.
    if not cache.who and cache.gated then
        SendGate(T0, true, true)
    end
    EmitStopped(stoppedT, cache.who, cache.scratch, cache.how)
end

-- A stop that found only an EARLIER frame's update, a frame later: a kick's
-- own update arrives in the frame of its cast stop (the field, every run),
-- so an update with no plate in its frame was a kick on a mob this client
-- has no plate for (a tank kicking off screen), and the next stop within the
-- window is most often another member's kick, whose own update lands in the
-- stop's frame, after the stop. That update takes the batch (Attribute's
-- landedHere) and this finds it gone; only when the frame brought none does
-- the earlier verdict serve the batch, as it always did.
local function LatePair()
    lateArmed = false
    if #wasStopped == 0 then
        return
    end
    local T0 = cache.lastT
    if T0 >= 0 and stoppedT - T0 <= PAIR_WINDOW and cache.pairedT ~= T0 then
        PairWith(T0)
    end
end

-- A plate's cast stopped. A hidden (or plain, non-empty) interrupter is a
-- kick; nil or "" is crowd control or a natural end. An enemy's spell is
-- plain; a hidden one is kept as unknown.
local function OnStop(unitToken, spellRec, by)
    if not NAMEPLATE_UNITS[unitToken] then
        return
    end
    if type(by) == "nil" then
        return
    end
    if not Secret(by) and (type(by) ~= "string" or by == "") then
        return
    end
    local T = GetTime()
    if stoppedT < 0 or T - stoppedT > PAIR_WINDOW then
        -- An older batch the meter never answered goes out first.
        if #wasStopped > 0 then
            EmitStopped(stoppedT, nil, nil, "unknown")
        end
        stoppedT = T
    end
    for i = 1, #wasStopped do
        if wasStopped[i] == unitToken then
            return
        end
    end
    wasStopped[#wasStopped + 1] = unitToken
    stoppedBy[#wasStopped] = by
    stoppedSpell[#wasStopped] = (type(spellRec) == "number" and not Secret(spellRec)) and spellRec or false
    -- The meter spoke first in this frame: its answer, now.
    if cache.lastT == T then
        PairWith(T)
        return
    end
    -- A recent update no frame has taken yet: next frame, unless this frame
    -- brings the batch an update of its own (LatePair). The flush below is
    -- the fallback either way.
    if cache.lastT >= 0 and T - cache.lastT <= PAIR_WINDOW and cache.pairedT ~= cache.lastT and not lateArmed then
        lateArmed = true
        C_Timer.After(0, LatePair)
    end
    if not flushArmed then
        flushArmed = true
        C_Timer.After(PAIR_WINDOW, FlushStopped)
    end
end

-- Your target's nameplate token, or nil: UnitIsUnit may compare "target"
-- with a plate token on any map; a hidden answer never counts as a match.
local function TargetPlate()
    if not UnitExists("target") then
        return nil
    end
    for i = 1, #NAMEPLATE_TOKENS do
        local token = NAMEPLATE_TOKENS[i]
        if UnitExists(token) then
            local success, same = pcall(UnitIsUnit, "target", token)
            if success and not Secret(same) and same == true then
                return token
            end
        end
    end
    return nil
end

-- Your own kick (or your demon's): the model starts now with the plain
-- cooldown; the landed kick a moment later may shorten it. Your icon goes to
-- your target's plate at once (a missed kick stops nothing, so nothing else
-- would ever report it).
local function OnOwnCast(spellId)
    if Secret(spellId) then
        return
    end
    local kickRec = KD.OwnCastKick(spellId)
    if not kickRec then
        return
    end
    local m = rosterMap.player
    if not m then
        return
    end
    local T = GetTime()
    ownT, ownPending = T, true
    if m.kick ~= kickRec then
        m.kick = kickRec
        m.cd, m.landedCd = KD.Cooldown(kickRec, m.specID, m.talents)
    end
    if m.cd then
        StartCd(m, T, m.cd)
    end
    m.lastKick, m.lastSure = T, true
    local backing = TargetPlate()
    if backing then
        Dispatch("kick", backing, "player", nil, nil, "cast", T)
    end
end

--------------------------------------------------------------------------------
--  Events
--------------------------------------------------------------------------------
local LIVE_EVENTS = {
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_STOP",
    "DAMAGE_METER_COMBAT_SESSION_UPDATED",
    "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED",
    "SPELLS_CHANGED",
    "ADDON_RESTRICTION_STATE_CHANGED",
    "PLAYER_REGEN_ENABLED",
    "CHALLENGE_MODE_START", -- guardrails-allow: combat-deferral by Cludes: the engine's combat-end edge (specs from the meter rows, stale talent re-reads, the next inspect), live only while a display subscribes and dropped at Deactivate; a recurring listener, not a one-shot deferral
    "PLAYER_ENTERING_WORLD",
}

local function OnEvent(_, eventName, firstArg, a2, a3, a4, a5)
    if eventName == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        if firstArg == INT then
            Attribute()
        end
    elseif eventName == "UNIT_SPELLCAST_SUCCEEDED" then
        OnOwnCast(a3)
    elseif eventName == "UNIT_SPELLCAST_INTERRUPTED" or eventName == "UNIT_SPELLCAST_CHANNEL_STOP" then
        OnStop(firstArg, a3, a4)
    elseif eventName == "UNIT_SPELLCAST_EMPOWER_STOP" then
        OnStop(firstArg, a3, a5)
    elseif eventName == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
        Rebase()
    elseif eventName == "DAMAGE_METER_RESET" then
        Rebase(true)
    elseif eventName == "GROUP_ROSTER_UPDATE" then
        -- A roster storm (a load, a group forming) syncs once per frame, and
        -- once more after it: the burst's last event carries its final state.
        local T = GetTime()
        if T ~= rosterT then
            rosterT = T
            SyncRoster()
            if not InCombatLockdown() then
                ReadSpecs()
            end
        elseif not rosterFlush then
            rosterFlush = true
            C_Timer.After(0, function()
                rosterFlush = false
                if not isActive then
                    return
                end
                SyncRoster()
                if not InCombatLockdown() then
                    ReadSpecs()
                end
            end)
        end
    elseif eventName == "UNIT_PET" then
        local member = rosterMap[firstArg]
        if member and member.class == "WARLOCK" then
            member.pet = PetFamily(firstArg)
            if ResolveKick(member) then
                Dispatch("roster", GetTime())
            end
        end
    elseif eventName == "PLAYER_SPECIALIZATION_CHANGED" then
        if firstArg == "player" then
            RefreshPlayer()
        else
            local m = firstArg and rosterMap[firstArg]
            if m and m.guid then
                m.specID, m.specIcon, m.specSrc, m.talents, m.readAt = nil, nil, nil, nil, nil
                if ResolveKick(m) then
                    Dispatch("roster", GetTime())
                end
                AskRead(firstArg)
            end
        end
    elseif eventName == "TRAIT_CONFIG_UPDATED" or eventName == "SPELLS_CHANGED" then
        RefreshPlayer()
    elseif eventName == "INSPECT_READY" then
        OnReadReady(firstArg)
    elseif eventName == "ADDON_RESTRICTION_STATE_CHANGED" then
        if firstArg == RT_COMBAT and a2 == RS_INACTIVE then
            ReadSpecs()
        end
    elseif eventName == "PLAYER_REGEN_ENABLED" then
        ReadSpecs()
        ReReadStale()
        ReadNext()
    elseif eventName == "CHALLENGE_MODE_START" then
        -- A last chance before the key locks the inspect data.
        ReReadStale()
        ReadNext()
    elseif eventName == "PLAYER_ENTERING_WORLD" then
        for _, m in pairs(rosterMap) do
            ClearCd(m)
        end
        wipe(wasStopped)
        wipe(stoppedBy)
        wipe(stoppedSpell)
        stoppedT = -1
        ownPending = false
        cache.lastT, cache.pairedT, cache.who, cache.scratch, cache.how = -1, -1, nil, nil, nil
        cache.rowKey, cache.rowHow, cache.learn, cache.gated, cache.grew = nil, nil, nil, false, false
        gateT = -1
        Rebase(true)
        SyncRoster()
        ReReadStale()
    end
end

local function Activate()
    if isActive then
        return
    end
    isActive = true
    if not eventTag then
        eventTag = CreateFrame("Frame")
        eventTag:SetScript("OnEvent", OnEvent)
    end
    for i = 1, #LIVE_EVENTS do
        eventTag:RegisterEvent(LIVE_EVENTS[i])
    end
    eventTag:RegisterUnitEvent("UNIT_PET", "player", "party1", "party2", "party3", "party4")
    cache.frameT = -1
    Rebase(true)
    SyncRoster()
    RegisterOwnCasts()
    if not InCombatLockdown() then
        ReadSpecs()
    end
    ReReadStale()
    ReadNext()
end

local function Deactivate()
    if not isActive then
        return
    end
    isActive = false
    eventTag:UnregisterAllEvents()
    if readingUnit then
        DoneReading()
    end
    wipe(readList)
    wipe(readAsked)
    wipe(wasStopped)
    wipe(stoppedBy)
    wipe(stoppedSpell)
    stoppedT = -1
    ownPending = false
    for _, m in pairs(rosterMap) do
        m.downAt, m.downFor, m.readyAt = nil, nil, nil
    end
    wipe(gateList)
    wipe(gatePrev)
    wipe(gateCur)
    wipe(gatePlates)
    gateT, cache.gated = -1, false
end

--------------------------------------------------------------------------------
--  Public surface
--------------------------------------------------------------------------------
-- handlers: { kick = fn(plateUnit, kickerUnit|nil, candidates|nil, interrupter,
-- how, t), cooldown = fn(unit, start|nil, dur|nil), roster = fn(t),
-- gate = fn(t, units, before, after, plates, platesOnly) }. kick names a
-- kicker only when the engine is sure of them (and starts their cooldown);
-- gate is every update's exact answer for everyone else: `units` the members
-- who could have kicked at t, `before` / `after` their interrupt counts by
-- unit (hidden in combat: handed to a status bar as value and maximum, never
-- read), `plates` the plates kicked in that update nobody was placed on (or,
-- with platesOnly, plates joining the packet already sent for t). A display
-- shows member u's kick at t, with u's cooldown (KE.KickDuration) from t,
-- only where u's count rose. counts = fn(t, units, after) comes with every
-- update, before its kick or gate: `units` the members with entries (never
-- you), `after` their counts as read now, for the displays' own count gates
-- (a kick's icon hidden once its kicker's count rose past the count at that
-- kick). Every table is the engine's own scratch, read at once and never
-- kept. The first subscriber starts the engine, the last leaving stops it.
-- The content the tracker runs in at all: Mythic and Mythic+ dungeons and
-- arenas, as the Where buckets of CUI_MythicTimer_Where.lua name them. The
-- Where to Show filter offers these keys alone, and both displays ask Allowed
-- before going live, so elsewhere nothing subscribes and the engine sleeps.
KE.WHERE_LIST = { "dungeon_mythic", "arena" }

function KE.Allowed()
    local bucket = MTWhere.Bucket and MTWhere.Bucket()
    return bucket == "dungeon_mythic" or bucket == "arena"
end

function KE.Subscribe(key, handlers)
    if not subs[key] then
        subCount = subCount + 1
    end
    subs[key] = handlers
    Activate()
end

function KE.Unsubscribe(key)
    if not subs[key] then
        return
    end
    subs[key] = nil
    subCount = subCount - 1
    if subCount <= 0 then
        subCount = 0
        Deactivate()
    end
end

function KE.IsActive()
    return isActive
end

-- A member record: unit, guid, class, specID, kick (spell ID, false for none,
-- nil unknown), cd, landedCd, minCd (the landed cooldown with every cooldown
-- talent), downAt, downFor, readyAt, what their Interrupts list holds (known,
-- holes) and the bounds on their hidden interrupt count (lo, hi). Read-only
-- by contract.
function KE.Member(unitToken)
    return rosterMap[unitToken]
end

-- A member's interrupt count as the meter last read it (their gate source's:
-- their demon's for a demon's interrupt), hidden in combat and only ever to
-- be handed to a native sink, or nil while none was read. The displays' count
-- gates take it as a baseline at a sure kick and as the maximum at every
-- update (the counts event).
function KE.Count(unitToken)
    return cache.a[unitToken]
end

-- The fight the counts belong to: a plain number that moves whenever they
-- restart (a new fight, a reset, a load). A count taken in an older fight is
-- no baseline for this one.
function KE.FightGen()
    return fightGen
end

-- The cooldown a member is held to before they could kick again after a kick
-- the engine timed: their landed cooldown, or the shortest they could have
-- (every cooldown talent) while their talents were never read; nil while
-- their interrupt is not known. StillDown's own measure, less KE.ELIM_SLACK.
function KE.DownFor(unitToken)
    local member = rosterMap[unitToken]
    if not (member and member.kick) then
        return nil
    end
    return member.talents and member.landedCd or member.minCd
end
KE.ELIM_SLACK = ELIM_SLACK

-- How long a member's interrupt is down after a kick the tracker saw land
-- (their landed cooldown: Coldthirst and Light of the Sun shorten only that),
-- or nil while their interrupt is not known.
function KE.KickDuration(unitToken)
    local member = rosterMap[unitToken]
    if not (member and member.kick) then
        return nil
    end
    return member.landedCd or member.cd
end

-- The modeled cooldown of a member's interrupt: start, duration and end time,
-- nil while ready or unknown.
function KE.Cooldown(unitToken)
    local member = rosterMap[unitToken]
    if not (member and member.downAt) then
        return nil
    end
    if member.readyAt <= GetTime() then
        return nil
    end
    return member.downAt, member.downFor, member.readyAt
end
