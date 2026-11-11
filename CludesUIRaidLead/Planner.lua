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
if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local _, ns = ...
ns = ns or {}

local Planner = {}
ns.Planner = Planner

local GROUP_SIZE = 5
local MAX_GROUPS = 8
Planner.GROUP_SIZE = GROUP_SIZE

-- A damage dealer's range is not in the roster, only their class. These
-- classes are counted as melee; every other class counts as ranged. It is a
-- guess for Druids, Shamans and Hunters, whose specs differ.
local MELEE_CLASS = {
    WARRIOR = true, ROGUE = true, DEATHKNIGHT = true,
    DEMONHUNTER = true, PALADIN = true, MONK = true,
}

local KIND_ORDER = { TANK = 1, MELEE = 2, RANGED = 3, HEALER = 4 }
Planner.KIND_ORDER = KIND_ORDER

--- "TANK", "MELEE", "RANGED" or "HEALER" for a member.
function Planner.Kind(m)
    if m.role == "TANK" then return "TANK" end
    if m.role == "HEALER" then return "HEALER" end
    return MELEE_CLASS[m.class or ""] and "MELEE" or "RANGED"
end

-- Tanks first, then melee, ranged, healers; same class together; then by name
-- so the same raid always sorts the same way.
local function ByKind(a, b)
    local ka, kb = KIND_ORDER[Planner.Kind(a)], KIND_ORDER[Planner.Kind(b)]
    if ka ~= kb then return ka < kb end
    if (a.class or "") ~= (b.class or "") then return (a.class or "") < (b.class or "") end
    return (a.name or "") < (b.name or "")
end

local function Sorted(members)
    local list = {}
    for i = 1, #members do list[i] = members[i] end
    table.sort(list, ByKind)
    return list
end

--- Tanks, melee, ranged, healers, filling group 1, then group 2 and so on.
--- Returns target[name] = group.
function Planner.ByRole(members)
    local target = {}
    local list = Sorted(members)
    for i = 1, #list do
        target[list[i].name] = math.floor((i - 1) / GROUP_SIZE) + 1
    end
    return target
end

--- Two balanced halves. Each kind is dealt out in turn, so both sides get the
--- same number of tanks, healers, melee and ranged (one apart at most), and
--- players of the same class are spread across the two sides. Side one takes
--- the first groups and side two the groups after them.
--- Returns target[name] = group, and the number of groups each side uses.
function Planner.Split(members)
    local list = Sorted(members)
    local sides = { {}, {} }
    local turn = 1
    for i = 1, #list do
        local side = sides[turn]
        side[#side + 1] = list[i]
        turn = 3 - turn
    end
    local perSide = math.max(1, math.ceil(#sides[1] / GROUP_SIZE))
    if perSide * 2 > MAX_GROUPS then perSide = MAX_GROUPS / 2 end
    local target = {}
    for s = 1, 2 do
        local side = sides[s]
        for i = 1, #side do
            target[side[i].name] = (s - 1) * perSide + math.floor((i - 1) / GROUP_SIZE) + 1
        end
    end
    return target, perSide
end

--- The groups as they are now: target[name] = group. Used to undo a sort.
function Planner.Snapshot(members)
    local target = {}
    for i = 1, #members do target[members[i].name] = members[i].group end
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
    local count = {}
    for g = 1, MAX_GROUPS do count[g] = 0 end
    for i = 1, #members do
        local g = members[i].group
        if count[g] then count[g] = count[g] + 1 end
    end
    local setMove
    for i = 1, #members do
        local m = members[i]
        local want = target[m.name]
        if want and want ~= m.group then
            -- A trade that fixes both members is the best move there is.
            for j = 1, #members do
                local n = members[j]
                if n.group == want and target[n.name] == m.group then
                    return { op = "swap", index = m.index, other = n.index }
                end
            end
            if count[want] < GROUP_SIZE then
                setMove = setMove or { op = "set", index = m.index, group = want }
            end
        end
    end
    if setMove then return setMove end
    -- Every wanted group is full: trade with anyone in it who belongs elsewhere.
    for i = 1, #members do
        local m = members[i]
        local want = target[m.name]
        if want and want ~= m.group then
            for j = 1, #members do
                local n = members[j]
                local nWant = target[n.name]
                if n.group == want and nWant and nWant ~= want then
                    return { op = "swap", index = m.index, other = n.index }
                end
            end
        end
    end
    return nil
end

--- How many members of each kind a plan puts in each group, for the summary
--- printed to chat: out[group] = { TANK = n, MELEE = n, RANGED = n, HEALER = n }.
function Planner.Summary(members, target)
    local out = {}
    for i = 1, #members do
        local m = members[i]
        local g = target[m.name] or m.group
        out[g] = out[g] or { TANK = 0, MELEE = 0, RANGED = 0, HEALER = 0 }
        local k = Planner.Kind(m)
        out[g][k] = out[g][k] + 1
    end
    return out
end

return Planner
