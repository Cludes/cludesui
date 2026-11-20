if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Sort.lua
--
--  Show Self First, the Prioritize Class lists, the FrameSort provider and
--  ApplySortToHeaders.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ipairs = ipairs
local wipe = wipe
local type = type
local tostring = tostring
local UnitName = UnitName
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local InCombatLockdown = InCombatLockdown
local GetNumGroupMembers = GetNumGroupMembers
local issecretvalue = issecretvalue

local separatedHdrs = Inner.separatedHdrs

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end
local containerFrame
Inner.containerFrameSetters[#Inner.containerFrameSetters + 1] = function(val)
    containerFrame = val
end

-------------------------------------------------------------------------------
--  Show Self First (raid, OOC only): the player's subgroup header sorts via a
--  per-group nameList listing every member with the player first, so the
--  secure header orders natively -- no SetPoint override, no flicker.
--  showPlayer can't exclude the player in a raid, so the party-style self
--  button doesn't apply here. Merged mode pins the player via a whole-raid
--  nameList instead (ns._BuildMergedSelfNameList below).
-------------------------------------------------------------------------------
-- Player's raid subgroup (1-8). Party/solo collapses to group 1.
function mod._GetPlayerSubgroup()
    if not IsInRaid() then
        return 1
    end
    local num = GetNumGroupMembers()
    for index = 1, num do
        if UnitIsUnit("raid" .. index, "player") then
            local _, _, subgroup = GetRaidRosterInfo(index)
            return subgroup
        end
    end
    return nil
end

-- A nameList is a FILTER as much as an order: the secure header re-matches
-- every member's CURRENT name against the list on its own, in combat too,
-- and a member whose name is not listed is hidden outright. Names are not
-- stable: the UNKNOWNOBJECT placeholder stands in while a roster entry has
-- not populated yet (zoning, mid-loadscreen join) AND whenever a rename
-- effect resolves a unit to it mid-fight, when the attribute cannot be
-- rewritten. Every list therefore ends with the placeholder token, so a
-- member carrying it stays visible (sorted last) until the next rebuild
-- re-lists them under their real name. Builders skip in-set placeholders
-- (the token covers them) and bail to nil when a placeholder exists OUTSIDE
-- their set: the token would pull that member into a header that must not
-- show them, so the engine path (everyone visible, native order) runs until
-- names resolve. Pass the sorted member entries (each carrying .name).
-- noToken: per-group lists that cover EVERY separated header (Prioritize
-- Class, FrameSort) leave the token off -- it would pull a placeholder that
-- appears mid-fight into all of those headers at once; such a member waits
-- for the regen rebuild instead, and the builders drop a group whose own
-- roster holds a placeholder to its native path.
function mod._FinishNameList(members, noToken)
    local nameList = mod._nlBuf
    if nameList then
        wipe(nameList)
    else
        nameList = {}
        mod._nlBuf = nameList
    end
    for index = 1, #members do
        nameList[index] = members[index].name
    end
    if not noToken then
        nameList[#nameList + 1] = UNKNOWNOBJECT
    end
    return table.concat(nameList, ",")
end

-- Reused member records and per-group buckets for the list builders, which
-- run on every LayoutGroups pass (options slider drags included). One builder
-- runs at a time and returns finished strings, so the pool is free again when
-- it returns; each builder writes every field its comparator reads.
function mod._NLRec(index)
    local pool = mod._nlPool
    if not pool then
        pool = {}
        mod._nlPool = pool
    end
    local m = pool[index]
    if not m then
        m = {}
        pool[index] = m
    end
    return m
end

function mod._NLGroups()
    local groups, bad = mod._nlGroups, mod._nlBad
    if groups then
        for g = 1, 8 do
            wipe(groups[g])
        end
        wipe(bad)
    else
        groups, bad = {}, {}
        for g = 1, 8 do
            groups[g] = {}
        end
        mod._nlGroups, mod._nlBad = groups, bad
    end
    return groups, bad
end

-- Build a "player first" nameList for the player's raid subgroup. Names come from
-- GetRaidRosterInfo (same source the secure header matches against, range-independent),
-- so nothing can vanish. Others follow the active sort: role order (ROLE mode, via
-- CludesUI.UnitEffectiveRole) else raid index. selfLast orders the player LAST instead.
function mod._BuildSelfFirstNameList(playerGroup, sortByRole, roleOrder, selfLast)
    if not IsInRaid() or not playerGroup then
        return nil
    end
    local pri
    if sortByRole then
        pri = {}
        for p, region in ipairs(roleOrder) do
            pri[region] = p
        end
    end
    local members = {}
    local num = GetNumGroupMembers()
    for index = 1, num do
        local name, _, subgroup = GetRaidRosterInfo(index)
        -- A nil name = roster not populated at all; the subgroup is not
        -- trustworthy either. Bail (see ns._FinishNameList).
        if not name then
            return nil
        end
        if subgroup == playerGroup then
            if name ~= UNKNOWNOBJECT then
                local unitToken = "raid" .. index
                local rp = 99
                if pri then
                    rp = pri[CludesUI.UnitEffectiveRole(unitToken)] or 99
                end
                members[#members + 1] = {
                    name = name,
                    isPlayer = UnitIsUnit(unitToken, "player"),
                    rolePri = rp,
                    index = index,
                }
            end
        elseif name == UNKNOWNOBJECT then
            return nil
        end
    end
    if #members == 0 then
        return nil
    end
    table.sort(members, function(lhs, rhs)
        -- Player to the top (self-first) or bottom (self-last). Exactly one of
        -- a/b is the player inside this branch, so the XOR with selfLast flips it.
        if lhs.isPlayer ~= rhs.isPlayer then
            return lhs.isPlayer ~= selfLast
        end
        if sortByRole and lhs.rolePri ~= rhs.rolePri then
            return lhs.rolePri < rhs.rolePri
        end
        return lhs.index < rhs.index
    end)
    return mod._FinishNameList(members)
end

-- Default class sort order: real player classes only, alphabetical by
-- localized name, enumerated via GetNumClasses + C_CreatureInfo.GetClassInfo
-- so non-class entries (Adventurer/Traveler in LOCALIZED_CLASS_NAMES_MALE) are
-- excluded. Also populates ns._classNameByToken (token -> localized name) for
-- the options list. Cached on ns.
function mod._GetDefaultClassOrder()
    if mod._defaultClassOrderCache then
        return mod._defaultClassOrderCache
    end
    local entries, nameList = {}, {}
    local num = (GetNumClasses and GetNumClasses()) or 0
    for index = 1, num do
        local details = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(index)
        if details and details.classFile then
            entries[#entries + 1] = details.classFile
            nameList[details.classFile] = details.className or details.classFile
        end
    end
    table.sort(entries, function(lhs, rhs)
        return (nameList[lhs] or lhs) < (nameList[rhs] or rhs)
    end)
    mod._classNameByToken = nameList
    if #entries > 0 then
        mod._defaultClassOrderCache = entries
    end
    return entries
end

-- Build a class-priority nameList for the party header. Lists the party members
-- the header shows (player only when includePlayer), ordered by role (optional
-- primary) -> class -> name. Names use the same UnitName + "-realm" format
-- Blizzard's GetGroupRosterInfo produces for party units, so the secure header
-- matches them. nameList is only honored when groupFilter is cleared.
function mod._BuildPartyClassNameList(includePlayer, sortByRole, roleOrder, classOrder)
    if not IsInGroup() then
        return nil
    end
    classOrder = classOrder or mod._GetDefaultClassOrder()
    local classPri = {}
    for index, c in ipairs(classOrder) do
        classPri[c] = index
    end
    local rolePri
    if sortByRole then
        rolePri = {}
        for index, region in ipairs(roleOrder) do
            rolePri[region] = index
        end
    end
    local members = {}
    local units = {}
    if includePlayer then
        units[#units + 1] = "player"
    end
    for index = 1, 4 do
        units[#units + 1] = "party" .. index
    end
    for _, unitToken in ipairs(units) do
        if UnitExists(unitToken) then
            local name, server = UnitName(unitToken)
            if not name then
                return nil
            end
            -- Every unit here is in the header's set: a placeholder name is
            -- covered by the trailing token (see ns._FinishNameList).
            if name ~= UNKNOWNOBJECT then
                if server and server ~= "" then
                    name = name .. "-" .. server
                end
                local _, classToken = UnitClass(unitToken)
                members[#members + 1] = {
                    name = name,
                    rolePri = (rolePri and rolePri[CludesUI.UnitEffectiveRole(unitToken)]) or 99,
                    classPri = classPri[classToken] or 99,
                }
            end
        end
    end
    if #members == 0 then
        return nil
    end
    table.sort(members, function(lhs, rhs)
        if sortByRole and lhs.rolePri ~= rhs.rolePri then
            return lhs.rolePri < rhs.rolePri
        end
        if lhs.classPri ~= rhs.classPri then
            return lhs.classPri < rhs.classPri
        end
        return lhs.name < rhs.name
    end)
    return mod._FinishNameList(members)
end

-- Party header nameList for ARENA, where the header is bound to raid1-5.
-- showPlayer cannot exclude the player in a raid group and the static self
-- button cannot reorder them; a NAMELIST does both (Hide Self; Self
-- First/Last). Rest follow role order (ROLE mode) else raid index. Names come
-- from GetRaidRosterInfo (what the header matches against). Placeholder
-- names follow the ns._FinishNameList rules (a hidden self is out of set).
function mod._BuildArenaNameList(hideSelf, selfFirst, selfLast, sortByRole, roleOrder, onlyGroup)
    if not IsInRaid() then
        return nil
    end
    local pri
    if sortByRole then
        pri = {}
        for p, region in ipairs(roleOrder) do
            pri[region] = p
        end
    end
    local members = {}
    local num = GetNumGroupMembers()
    for index = 1, num do
        local name, _, subgroup = GetRaidRosterInfo(index)
        if not name then
            return nil
        end
        -- Small Raid mode: members outside the kept subgroup are simply not
        -- listed (the header hides them); the player included.
        if not (onlyGroup and subgroup ~= onlyGroup) then
            local unitToken = "raid" .. index
            local isPlayer = UnitIsUnit(unitToken, "player")
            if not (hideSelf and isPlayer) then
                if name ~= UNKNOWNOBJECT then
                    local rp = 99
                    if pri then
                        rp = pri[CludesUI.UnitEffectiveRole(unitToken)] or 99
                    end
                    members[#members + 1] = {
                        name = name,
                        isPlayer = isPlayer,
                        rolePri = rp,
                        index = index,
                    }
                end
            elseif name == UNKNOWNOBJECT then
                return nil
            end
        elseif name == UNKNOWNOBJECT then
            -- Outside the kept subgroup: the token would pull them in.
            return nil
        end
    end
    if #members == 0 then
        return nil
    end
    table.sort(members, function(lhs, rhs)
        -- Player to top (self-first) or bottom (self-last); exactly one of a/b
        -- is the player in this branch, so the XOR with selfLast flips it.
        if (selfFirst or selfLast) and lhs.isPlayer ~= rhs.isPlayer then
            return lhs.isPlayer ~= selfLast
        end
        if sortByRole and lhs.rolePri ~= rhs.rolePri then
            return lhs.rolePri < rhs.rolePri
        end
        return lhs.index < rhs.index
    end)
    return mod._FinishNameList(members)
end

-- Whole-raid nameList for Merge Groups + Self Position: player pinned first
-- (or last), everyone else in the active sort (role blocks in ROLE mode, raid
-- index otherwise). Replaces the flat header's groupFilter, so members of
-- groups hidden via Show Groups are simply not listed. Placeholder names
-- follow the ns._FinishNameList rules (hidden groups are out of set); the
-- caller falls back to the engine path on a bail.
function mod._BuildMergedSelfNameList(sortByRole, roleOrder, selfLast, visibleGroups)
    if not IsInRaid() then
        return nil
    end
    local pri
    if sortByRole then
        pri = {}
        for p, region in ipairs(roleOrder) do
            pri[region] = p
        end
    end
    local members = {}
    local num = GetNumGroupMembers()
    for index = 1, num do
        local name, _, subgroup = GetRaidRosterInfo(index)
        if not name then
            return nil
        end
        if not visibleGroups or visibleGroups[subgroup] ~= false then
            if name ~= UNKNOWNOBJECT then
                local unitToken = "raid" .. index
                local rp = 99
                if pri then
                    rp = pri[CludesUI.UnitEffectiveRole(unitToken)] or 99
                end
                members[#members + 1] = {
                    name = name,
                    isPlayer = UnitIsUnit(unitToken, "player"),
                    rolePri = rp,
                    index = index,
                }
            end
        elseif name == UNKNOWNOBJECT then
            return nil
        end
    end
    if #members == 0 then
        return nil
    end
    table.sort(members, function(lhs, rhs)
        -- Player to top (self-first) or bottom (self-last); exactly one of a/b
        -- is the player in this branch, so the XOR with selfLast flips it.
        if lhs.isPlayer ~= rhs.isPlayer then
            return lhs.isPlayer ~= selfLast
        end
        if sortByRole and lhs.rolePri ~= rhs.rolePri then
            return lhs.rolePri < rhs.rolePri
        end
        return lhs.index < rhs.index
    end)
    return mod._FinishNameList(members)
end

-------------------------------------------------------------------------------
--  Raid Prioritize Class lists: role (Sort By = Role) -> class (the Class
--  Order list) -> name, the same order as the party header's
--  ns._BuildPartyClassNameList, with Self Position pinning the player first
--  or last. Group sort + Prioritize Class needs no list at all (the headers'
--  own CLASS grouping gives this order and stays live in combat, see
--  ApplySortToHeaders); lists serve Role + Class (a header groups by one key
--  only), Self Position's group, and merged mode. Separated mode returns one
--  list per subgroup, without the placeholder token (see ns._FinishNameList),
--  and leaves out any group whose roster holds a placeholder (native path).
--  onlyGroup (Self Position's one header) and merged mode return a single
--  list WITH the token, under the ns._FinishNameList rules: a placeholder in
--  the set rides the token, one outside it bails. Names come from
--  GetRaidRosterInfo (what the header matches against).
-------------------------------------------------------------------------------
function mod._RCLess(a, b)
    -- Exactly one of a/b is the player here, so the XOR with the Self Last
    -- flag sends them to the top (Self First) or the bottom (Self Last).
    if a.isPlayer ~= b.isPlayer then
        return a.isPlayer ~= mod._rcSelfLast
    end
    if a.rolePri ~= b.rolePri then
        return a.rolePri < b.rolePri
    end
    if a.classPri ~= b.classPri then
        return a.classPri < b.classPri
    end
    return a.name < b.name
end

function mod._BuildRaidClassLists(
    merged,
    visibleGroups,
    sortByRole,
    roleOrder,
    classOrder,
    selfFirst,
    selfLast,
    onlyGroup
)
    if not IsInRaid() then
        return nil
    end
    local classPri = mod._rcClassPri
    if classPri then
        wipe(classPri)
    else
        classPri = {}
        mod._rcClassPri = classPri
    end
    for index, c in ipairs(classOrder or mod._GetDefaultClassOrder()) do
        classPri[c] = index
    end
    local rolePri = mod._rcRolePri
    if rolePri then
        wipe(rolePri)
    else
        rolePri = {}
        mod._rcRolePri = rolePri
    end
    if sortByRole then
        for index, region in ipairs(roleOrder) do
            rolePri[region] = index
        end
    end
    mod._rcSelfLast = selfLast == true
    local pin = (selfFirst or selfLast) and true or false
    local tok = mod._FsRaidTok()
    local groups, bad = mod._NLGroups()
    local used = 0
    local num = GetNumGroupMembers()
    for index = 1, num do
        local name, _, subgroup, _, _, classToken = GetRaidRosterInfo(index)
        if not name or not subgroup then
            return nil
        end
        local skip = (merged and visibleGroups and visibleGroups[subgroup] == false)
            or (onlyGroup ~= nil and subgroup ~= onlyGroup)
        if name == UNKNOWNOBJECT then
            if merged or onlyGroup then
                -- One header carrying the token: a placeholder in its set
                -- rides it, one outside would be pulled in.
                if skip then
                    return nil
                end
            elseif not skip then
                bad[subgroup] = true
            end
        elseif not skip then
            used = used + 1
            local m = mod._NLRec(used)
            local unitToken = tok[index]
            m.name = name
            m.isPlayer = pin and UnitIsUnit(unitToken, "player") == true
            m.rolePri = (sortByRole and rolePri[CludesUI.UnitEffectiveRole(unitToken)]) or 99
            m.classPri = classPri[classToken] or 99
            local g = groups[merged and 1 or subgroup]
            g[#g + 1] = m
        end
    end
    if merged then
        local entries = groups[1]
        if #entries == 0 then
            return nil
        end
        table.sort(entries, mod._RCLess)
        return mod._FinishNameList(entries)
    end
    if onlyGroup then
        local entries = groups[onlyGroup]
        if not entries or #entries == 0 then
            return nil
        end
        table.sort(entries, mod._RCLess)
        return mod._FinishNameList(entries)
    end
    local result = mod._rcOut
    if result then
        wipe(result)
    else
        result = {}
        mod._rcOut = result
    end
    for g = 1, 8 do
        local entries = groups[g]
        if #entries > 0 and not bad[g] then
            table.sort(entries, mod._RCLess)
            result[g] = mod._FinishNameList(entries, true)
        end
    end
    return result
end

-------------------------------------------------------------------------------
--  FrameSort provider (compatibility shim for the FrameSort addon). With
--  Sort By = FrameSort the headers take their order from FrameSort's sorted
--  friendly unit list through a nameList built from OUR roster: every member
--  a header shows is listed (a nameList is a filter), members the list does
--  not rank sort last by index, and the ns._FinishNameList placeholder rules
--  apply. FrameSort never reads or moves our frames (self-managed provider);
--  its list is read in place, never modified. Everything below costs nothing
--  unless the mode is picked, and nothing at all when FrameSort is absent.
-------------------------------------------------------------------------------
function mod._FrameSortApi()
    local api = _G.FrameSortApi
    api = api and api.v3
    if api and api.Sorting and api.Sorting.GetFriendlyUnits then
        return api
    end
    return nil
end

-- The party mode is live only while FrameSort is loaded: a saved choice with
-- the addon gone runs the native order, and the self button keeps its job.
function mod._FsPartyMode()
    local profile = saved and saved.profile
    return profile ~= nil and (profile.partySortMode or profile.sortMode) == "FRAMESORT" and mod._FrameSortApi() ~= nil
end

-- rank[token] = position in FrameSort's list, players only (pets and the
-- tank-target tokens are not header members), in a reused map. nil when
-- FrameSort is absent or the list ranks no player. `fresh` drops FrameSort's
-- cache first: our own roster handlers can run before its invalidation and
-- would otherwise read the previous roster's order.
function mod._FrameSortRanks(fresh)
    local api = mod._FrameSortApi()
    if not api then
        return nil
    end
    if fresh and api.Caching and api.Caching.Invalidate then
        api.Caching:Invalidate()
    end
    local units = api.Sorting:GetFriendlyUnits()
    if type(units) ~= "table" then
        return nil
    end
    local success = mod._fsTokenOK
    if not success then
        success = { player = true }
        for index = 1, 4 do
            success["party" .. index] = true
        end
        for index = 1, 40 do
            success["raid" .. index] = true
        end
        mod._fsTokenOK = success
    end
    local rank = mod._fsRank
    if rank then
        wipe(rank)
    else
        rank = {}
        mod._fsRank = rank
    end
    local num = 0
    for index = 1, #units do
        local tok = units[index]
        if type(tok) == "string" and success[tok] and not rank[tok] then
            num = num + 1
            rank[tok] = num
        end
    end
    if num == 0 then
        return nil
    end
    return rank
end

function mod._FsMemberLess(a, b)
    if a.rank ~= b.rank then
        return a.rank < b.rank
    end
    return a.index < b.index
end

function mod._FsRaidTok()
    local tok = mod._raidTok
    if not tok then
        tok = {}
        for index = 1, 40 do
            tok[index] = "raid" .. index
        end
        mod._raidTok = tok
    end
    return tok
end

-- Raid: separated mode returns one nameList per subgroup, without the
-- placeholder token (see ns._FinishNameList); a group missing from the result
-- (none of its members listed, or a placeholder in its roster) keeps the
-- native path. Merged mode returns the whole-raid list for the visible groups:
-- a placeholder in a hidden group bails, one in a visible group rides the
-- token. Names come from GetRaidRosterInfo (what the header matches against).
function mod._BuildFrameSortRaidLists(rank, merged, visibleGroups)
    if not IsInRaid() then
        return nil
    end
    local tok = mod._FsRaidTok()
    local groups, bad = mod._NLGroups()
    local used = 0
    local num = GetNumGroupMembers()
    for index = 1, num do
        local name, _, subgroup = GetRaidRosterInfo(index)
        if not name or not subgroup then
            return nil
        end
        local hidden = merged and visibleGroups and visibleGroups[subgroup] == false
        if name == UNKNOWNOBJECT then
            if merged then
                if hidden then
                    return nil
                end
            else
                bad[subgroup] = true
            end
        elseif not hidden then
            used = used + 1
            local m = mod._NLRec(used)
            m.name, m.rank, m.index = name, rank[tok[index]] or 99, index
            local g = groups[merged and 1 or subgroup]
            g[#g + 1] = m
        end
    end
    if merged then
        local entries = groups[1]
        if #entries == 0 then
            return nil
        end
        table.sort(entries, mod._FsMemberLess)
        return mod._FinishNameList(entries)
    end
    local result = mod._fsGroupLists
    if result then
        wipe(result)
    else
        result = {}
        mod._fsGroupLists = result
    end
    for g = 1, 8 do
        local entries = groups[g]
        if #entries > 0 and not bad[g] then
            table.sort(entries, mod._FsMemberLess)
            result[g] = mod._FinishNameList(entries, true)
        end
    end
    return result
end

-- Party header on party units: the same UnitName + "-realm" form as
-- ns._BuildPartyClassNameList. Names can be secret in restricted content:
-- a secret or missing name bails to the native path.
function mod._BuildFrameSortPartyNameList(rank, includePlayer)
    if not IsInGroup() then
        return nil
    end
    local members = {}
    for index = includePlayer and 0 or 1, 4 do
        local unitToken = (index == 0) and "player" or ("party" .. index)
        if UnitExists(unitToken) then
            local name, server = UnitName(unitToken)
            if
                (issecretvalue and (issecretvalue(name) or issecretvalue(server)))
                or type(name) ~= "string"
            then
                return nil
            end
            if name ~= UNKNOWNOBJECT then
                if server and server ~= "" then
                    name = name .. "-" .. server
                end
                members[#members + 1] = { name = name, rank = rank[unitToken] or 99, index = index }
            end
        end
    end
    if #members == 0 then
        return nil
    end
    table.sort(members, mod._FsMemberLess)
    return mod._FinishNameList(members)
end

-- Party header bound to raid units (arena, Small Raid): the arena builder's
-- membership rules (Hide Self, one kept subgroup) in FrameSort's order.
function mod._BuildFrameSortRaidPartyNameList(rank, hideSelf, onlyGroup)
    if not IsInRaid() then
        return nil
    end
    local tok = mod._FsRaidTok()
    local members = {}
    local num = GetNumGroupMembers()
    for index = 1, num do
        local name, _, subgroup = GetRaidRosterInfo(index)
        if not name then
            return nil
        end
        if not (onlyGroup and subgroup ~= onlyGroup) then
            local unitToken = tok[index]
            if not (hideSelf and UnitIsUnit(unitToken, "player")) then
                if name ~= UNKNOWNOBJECT then
                    members[#members + 1] = { name = name, rank = rank[unitToken] or 99, index = index }
                end
            elseif name == UNKNOWNOBJECT then
                return nil
            end
        elseif name == UNKNOWNOBJECT then
            -- Outside the kept subgroup: the token would pull them in.
            return nil
        end
    end
    if #members == 0 then
        return nil
    end
    table.sort(members, mod._FsMemberLess)
    return mod._FinishNameList(members)
end

-- FrameSort's sort request (and its settings-changed callback): re-apply the
-- headers from its list. Out of combat only (attribute writes); a request in
-- combat rides the regen flush. Returns whether any header attribute changed,
-- which FrameSort's post-sort callbacks key on.
function mod._FrameSortApply()
    -- Zero cost unless the mode is picked (FrameSort calls in on its own runs
    -- and settings edits whatever our choice).
    local profile = saved and saved.profile
    if not (profile and (profile.sortMode == "FRAMESORT" or (profile.partySortMode or profile.sortMode) == "FRAMESORT")) then
        return false
    end
    if InCombatLockdown() then
        mod._rosterDirtyInCombat = true
        return false
    end
    if not mod._FrameSortApi() then
        return false
    end
    mod._fsChanged = false
    mod._fsFromProvider = true
    if mod._raidFramesVisible and mod._ApplySortToHeaders then
        mod._ApplySortToHeaders()
    end
    if mod._partyFramesVisible and mod._LayoutPartyFrames then
        mod._LayoutPartyFrames()
    end
    mod._fsFromProvider = nil
    return mod._fsChanged == true
end

-- Registers once FrameSort's API exists (FrameSort loads after this addon).
-- A provider registered before FrameSort's own init is asked for Init, so
-- one is supplied; Containers is read on every provider at combat start.
-- Name is spliced into a secure attribute key and Enabled is written as an
-- attribute value, so both return plain values only.
function mod._FrameSortRegister()
    if mod._fsRegistered then
        return
    end
    local api = mod._FrameSortApi()
    if not (api and api.Sorting.RegisterFrameProvider) then
        return
    end
    local none = {}
    local provider = {
        Name = function()
            return "CludesUI"
        end,
        Enabled = function()
            local profile = saved and saved.profile
            return profile ~= nil and (profile.sortMode == "FRAMESORT" or (profile.partySortMode or profile.sortMode) == "FRAMESORT")
        end,
        IsVisible = function()
            return mod._raidFramesVisible == true or mod._partyFramesVisible == true
        end,
        IsSelfManaged = true,
        Containers = function()
            return none
        end,
        Init = function() end,
        Sort = function()
            return mod._FrameSortApply()
        end,
    }
    if api.Sorting:RegisterFrameProvider(provider) then
        mod._fsRegistered = true
        if api.Options and api.Options.RegisterConfigurationChangedCallback then
            api.Options:RegisterConfigurationChangedCallback(function()
                mod._FrameSortApply()
            end)
        end
    end
end

-------------------------------------------------------------------------------
--  Apply sort attributes to all headers. Show Self First (raid) uses the
--  per-group nameList (see the Show Self First banner above); merged mode
--  uses the whole-raid nameList (ns._BuildMergedSelfNameList). Expensive
--  Hide/Show runs only when an attribute actually changed.
-------------------------------------------------------------------------------
local function ApplySortToHeaders()
    if not containerFrame or InCombatLockdown() then
        return
    end
    local cfg = saved.profile
    local sortByRole = cfg.sortMode == "ROLE"
    local roleOrder = cfg.roleOrder or { "TANK", "HEALER", "DAMAGER" }
    -- A raid set the group state hides takes no nameList (FrameSort, Role +
    -- Class, Self Position): a nameList is also a filter, and the visibility
    -- driver can show the set mid-fight, when no list can be rebuilt, so a stale
    -- list would drop every member it does not name. The shown pass applies them.
    local live = mod._RFVisWanted()
    -- Sort By = FrameSort: its list owns the order (Self Position included);
    -- with FrameSort absent, or no list yet, the Group sort runs (Prioritize
    -- Class and Self Position included).
    local fsRank = live and (cfg.sortMode == "FRAMESORT") and mod._FrameSortRanks(not mod._fsFromProvider)
        or nil
    -- Prioritize Class (FrameSort's list wins). Group sort + class runs on the
    -- headers' own CLASS grouping (Class Order, then name), so membership
    -- stays live in combat. A header groups by one key only, so Role + Class
    -- takes nameLists on every header instead: like Self Position's list, a
    -- member who joins mid-fight appears at the regen rebuild.
    local classOn = cfg.prioritizeClass == true and not fsRank and IsInRaid()
    local classNative = classOn and not sortByRole
    local classLists = live and classOn and sortByRole
    local selfOn = live and (cfg.showSelfFirst or cfg.showSelfLast) and IsInRaid()
    local selfLast = cfg.showSelfLast

    local baseGroupBy, baseSortMethod, baseGroupingOrder
    if classNative then
        baseGroupBy = "CLASS"
        baseSortMethod = "NAME"
        baseGroupingOrder = table.concat(cfg.classOrder or mod._GetDefaultClassOrder(), ",")
    else
        baseGroupBy = sortByRole and "ASSIGNEDROLE" or nil
        baseSortMethod = sortByRole and "NAME" or "INDEX"
        baseGroupingOrder = sortByRole and (table.concat(roleOrder, ",") .. ",NONE") or ""
    end

    -- gf = desired groupFilter. nameList is only honored when groupFilter is
    -- CLEARED (with one present the engine ignores nameList and uses
    -- roster/index order); the nameList lists every group member, so clearing
    -- groupFilter shows the same members in nameList order.
    local function applySortTo(heading, gb, sm, go, nl, gf)
        local needsHideShow = (heading:GetAttribute("groupBy") ~= gb)
            or (heading:GetAttribute("sortMethod") ~= sm)
            or (heading:GetAttribute("groupingOrder") ~= go)
            or (heading:GetAttribute("nameList") ~= nl)
            or (heading:GetAttribute("groupFilter") ~= gf)
        if needsHideShow then
            mod._fsChanged = true
            -- Hide/Show makes a shown header re-read the set; one LayoutGroups
            -- hid (a hidden or empty group, the idle flat header) stays hidden
            -- and reads it when LayoutGroups shows it.
            local isShown = heading:IsShown()
            if isShown then
                heading:Hide()
            end
            heading:SetAttribute("groupFilter", gf)
            heading:SetAttribute("groupBy", gb)
            heading:SetAttribute("sortMethod", sm)
            heading:SetAttribute("groupingOrder", go)
            heading:SetAttribute("nameList", nl)
            if isShown then
                heading:Show()
            end
        end
    end

    if cfg.mergeGroups and mod._flatHeader then
        -- Self Position in merged mode: a whole-raid nameList owns the order
        -- (player pinned, rest by the active sort), so groupFilter must be
        -- CLEARED -- the list itself only names visible groups' members --
        -- and groupBy nil so the list order is what the header uses (same
        -- combo as the non-merged player's-group path). While names are
        -- unresolved (builder bailed) the engine path runs instead, with
        -- LayoutGroups' groupFilter restored from ns._flatGfStr. FrameSort
        -- mode and Prioritize Class (Role + Class, or with Self Position) use
        -- the same whole-raid list shape; Group + Class alone runs native.
        local mergedList
        if fsRank then
            mergedList = mod._BuildFrameSortRaidLists(fsRank, true, mod._VisibleGroups())
        end
        if not mergedList and (classLists or (classNative and selfOn)) then
            mergedList = mod._BuildRaidClassLists(
                true,
                mod._VisibleGroups(),
                sortByRole,
                roleOrder,
                cfg.classOrder,
                cfg.showSelfFirst,
                selfLast
            )
        end
        if not mergedList and selfOn then
            mergedList = mod._BuildMergedSelfNameList(sortByRole, roleOrder, selfLast, mod._VisibleGroups())
        end
        if mergedList then
            applySortTo(mod._flatHeader, nil, "NAMELIST", "", mergedList, nil)
        else
            applySortTo(
                mod._flatHeader,
                baseGroupBy,
                baseSortMethod,
                baseGroupingOrder,
                nil,
                mod._flatGfStr or mod._flatHeader:GetAttribute("groupFilter")
            )
        end
    else
        local groupLists
        if fsRank then
            groupLists = mod._BuildFrameSortRaidLists(fsRank, false)
        elseif classLists then
            groupLists =
                mod._BuildRaidClassLists(false, nil, true, roleOrder, cfg.classOrder, cfg.showSelfFirst, selfLast)
        end
        -- Self Position: the player's group takes a player-pinned nameList
        -- (Class Order under Group + Class) whenever no per-group list covers
        -- it -- also the fallback while a list builder waits on names.
        local playerGroup = selfOn and mod._GetPlayerSubgroup() or nil
        if playerGroup and groupLists and groupLists[playerGroup] then
            playerGroup = nil
        end
        local selfNameList
        if playerGroup then
            if classOn then
                selfNameList = mod._BuildRaidClassLists(
                    false,
                    nil,
                    sortByRole,
                    roleOrder,
                    cfg.classOrder,
                    cfg.showSelfFirst,
                    selfLast,
                    playerGroup
                )
            end
            selfNameList = selfNameList
                or mod._BuildSelfFirstNameList(playerGroup, sortByRole, roleOrder, selfLast)
            if not selfNameList then
                playerGroup = nil
            end
        end
        for set = 1, 8 do
            local heading = separatedHdrs[set]
            if not heading then
                break
            end
            local groupList = groupLists and groupLists[set]
            if groupList then
                applySortTo(heading, nil, "NAMELIST", "", groupList, nil)
            elseif playerGroup and set == playerGroup then
                -- Player's group: ordered by nameList -- clear groupFilter, nil
                -- groupBy so the nameList order is what the header uses.
                applySortTo(heading, nil, "NAMELIST", "", selfNameList, nil)
            else
                applySortTo(heading, baseGroupBy, baseSortMethod, baseGroupingOrder, nil, tostring(set))
            end
        end
    end
end
mod._ApplySortToHeaders = ApplySortToHeaders

Inner.ApplySortToHeaders = ApplySortToHeaders
Inner.broken = false
