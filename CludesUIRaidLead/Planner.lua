-------------------------------------------------------------------------------
--  Planner.lua -- Raid Lead: works out who goes in which raid group.
--
--  Pure Lua with no game calls, so tools/test-raidlead.lua can run it outside
--  the game. Setup.lua reads the roster, asks this file for a plan and then
--  for one move at a time.
--
--  A member is { index, name, group, role, class }:
--    index  raid index (1..40), what the game's move calls take
--    group  the raid group the member is in now (1..8)
--    role   "TANK", "HEALER", "DAMAGER" or "NONE" (the role they queued as)
--    class  the class token, e.g. "DEATHKNIGHT"
-------------------------------------------------------------------------------
if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local _, mod = ...
mod = mod or {}

local Planner = {}
mod.Planner = Planner

local GROUP_SIZE = 5
local MAX_GROUPS = 8
Planner.GROUP_SIZE = GROUP_SIZE

-- A damage dealer's range is not in the roster, only their class. These
-- classes are counted as melee; every other class counts as ranged. It is a
-- guess for Druids, Shamans and Hunters, whose specs differ.
local MELEE_CLASS = {
    WARRIOR = true,
    ROGUE = true,
    DEATHKNIGHT = true,
    DEMONHUNTER = true,
    PALADIN = true,
    MONK = true,
}

local KIND_ORDER = { TANK = 1, MELEE = 2, RANGED = 3, HEALER = 4 }
Planner.KIND_ORDER = KIND_ORDER

--- "TANK", "MELEE", "RANGED" or "HEALER" for a member.
function Planner.Kind(m)
    if m.role == "TANK" then
        return "TANK"
    end
    if m.role == "HEALER" then
        return "HEALER"
    end
    return MELEE_CLASS[m.class or ""] and "MELEE" or "RANGED"
end

-- Tanks first, then melee, ranged, healers; same class together; then by name
-- so the same raid always sorts the same way.
local function ByKind(a, b)
    local ka, kb = KIND_ORDER[Planner.Kind(a)], KIND_ORDER[Planner.Kind(b)]
    if ka ~= kb then
        return ka < kb
    end
    if (a.class or "") ~= (b.class or "") then
        return (a.class or "") < (b.class or "")
    end
    return (a.name or "") < (b.name or "")
end

local function Sorted(members)
    local entries = {}
    for idx = 1, #members do
        entries[idx] = members[idx]
    end
    table.sort(entries, ByKind)
    return entries
end

--- Tanks, melee, ranged, healers, filling group 1, then group 2 and so on.
--- Returns target[name] = group.
function Planner.ByRole(members)
    local target = {}
    local entries = Sorted(members)
    for idx = 1, #entries do
        target[entries[idx].name] = math.floor((idx - 1) / GROUP_SIZE) + 1
    end
    return target
end

--- Two balanced halves. Each kind is dealt out in turn, so both sides get the
--- same number of tanks, healers, melee and ranged (one apart at most), and
--- players of the same class are spread across the two sides. Side one takes
--- the first groups and side two the groups after them.
--- Returns target[name] = group, and the number of groups each side uses.
function Planner.Split(members)
    local entries = Sorted(members)
    local sides = { {}, {} }
    local turn = 1
    for idx = 1, #entries do
        local side = sides[turn]
        side[#side + 1] = entries[idx]
        turn = 3 - turn
    end
    local perSide = math.max(1, math.ceil(#sides[1] / GROUP_SIZE))
    if perSide * 2 > MAX_GROUPS then
        perSide = MAX_GROUPS / 2
    end
    local target = {}
    for s = 1, 2 do
        local side = sides[s]
        for idx = 1, #side do
            target[side[idx].name] = (s - 1) * perSide + math.floor((idx - 1) / GROUP_SIZE) + 1
        end
    end
    return target, perSide
end

--- The groups as they are now: target[name] = group. Used to undo a sort.
function Planner.Snapshot(members)
    local target = {}
    for idx = 1, #members do
        target[members[idx].name] = members[idx].group
    end
    return target
end

--- The next single move that brings the raid closer to `target`, or nil when
--- everyone is in place. One of:
---   { op = "set",  index = i, group = g }    move into a group with room
---   { op = "swap", index = i, other = j }    trade places with someone who
---                                            does not belong in that group
--- Members the plan does not name are left where they are. Every move puts at
--- least one member in their final group and never takes one out of it, so
--- repeating this always finishes.
function Planner.NextMove(members, target)
    local total = {}
    for g = 1, MAX_GROUPS do
        total[g] = 0
    end
    for idx = 1, #members do
        local g = members[idx].group
        if total[g] then
            total[g] = total[g] + 1
        end
    end
    local setMove
    for idx = 1, #members do
        local m = members[idx]
        local wanted = target[m.name]
        if wanted and wanted ~= m.group then
            -- A trade that fixes both members is the best move there is.
            for jdx = 1, #members do
                local num = members[jdx]
                if num.group == wanted and target[num.name] == m.group then
                    return { op = "swap", index = m.index, other = num.index }
                end
            end
            if total[wanted] < GROUP_SIZE then
                setMove = setMove or { op = "set", index = m.index, group = wanted }
            end
        end
    end
    if setMove then
        return setMove
    end
    -- Every wanted group is full: trade with anyone in it who belongs elsewhere.
    for idx = 1, #members do
        local m = members[idx]
        local wanted = target[m.name]
        if wanted and wanted ~= m.group then
            for jdx = 1, #members do
                local num = members[jdx]
                local nWant = target[num.name]
                if num.group == wanted and nWant and nWant ~= wanted then
                    return { op = "swap", index = m.index, other = num.index }
                end
            end
        end
    end
    return nil
end

--- How many members of each kind a plan puts in each group, for the summary
--- printed to chat: out[group] = { TANK = n, MELEE = n, RANGED = n, HEALER = n }.
function Planner.Summary(members, target)
    local result = {}
    for idx = 1, #members do
        local m = members[idx]
        local g = target[m.name] or m.group
        result[g] = result[g] or { TANK = 0, MELEE = 0, RANGED = 0, HEALER = 0 }
        local key = Planner.Kind(m)
        result[g][key] = result[g][key] + 1
    end
    return result
end

return Planner
