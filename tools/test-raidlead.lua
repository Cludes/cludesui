-- Runs the Raid Lead planner outside the game:  luajit tools/test-raidlead.lua
local chunk = assert(loadfile("CludesUIRaidLead/Planner.lua"))
local ns = {}
chunk("CludesUIRaidLead", ns)
local P = ns.Planner

local CLASSES = { "WARRIOR", "ROGUE", "DEATHKNIGHT", "DEMONHUNTER", "PALADIN", "MONK",
                  "MAGE", "WARLOCK", "PRIEST", "EVOKER", "HUNTER", "SHAMAN", "DRUID" }

-- A raid of n players in random groups with at most five in each.
local function Roster(n, seed)
    math.randomseed(seed)
    local slots = {}
    for g = 1, 8 do for _ = 1, 5 do slots[#slots + 1] = g end end
    for i = #slots, 2, -1 do
        local j = math.random(i)
        slots[i], slots[j] = slots[j], slots[i]
    end
    local members = {}
    for i = 1, n do
        local roll = math.random(100)
        local role = (roll <= 10 and "TANK") or (roll <= 30 and "HEALER") or (roll <= 95 and "DAMAGER") or "NONE"
        members[i] = { index = i, name = "Player" .. i, group = slots[i], role = role,
                       class = CLASSES[math.random(#CLASSES)] }
    end
    return members
end

-- Applies moves the way the game would and returns how many it took.
local function Run(members, target)
    local byIndex = {}
    for i = 1, #members do byIndex[members[i].index] = members[i] end
    local steps = 0
    while true do
        local mv = P.NextMove(members, target)
        if not mv then break end
        steps = steps + 1
        assert(steps <= 200, "the moves never finish")
        if mv.op == "set" then
            local n = 0
            for i = 1, #members do if members[i].group == mv.group then n = n + 1 end end
            assert(n < 5, "moved into a full group")
            byIndex[mv.index].group = mv.group
        else
            local a, b = byIndex[mv.index], byIndex[mv.other]
            assert(a.group ~= b.group, "traded within one group")
            a.group, b.group = b.group, a.group
        end
    end
    for i = 1, #members do
        assert(members[i].group == target[members[i].name], "a member is not where the plan put them")
    end
    return steps
end

local function Count(members, target, lo, hi)
    local c = { TANK = 0, MELEE = 0, RANGED = 0, HEALER = 0, all = 0 }
    for i = 1, #members do
        local g = target[members[i].name]
        if g >= lo and g <= hi then
            local k = P.Kind(members[i])
            c[k] = c[k] + 1
            c.all = c.all + 1
        end
    end
    return c
end

local runs, worst = 0, 0
for _, n in ipairs({ 1, 5, 10, 14, 20, 25, 30, 40 }) do
    for seed = 1, 60 do
        -- By role: no group over five, kinds in order across the groups.
        local members = Roster(n, seed * 31 + n)
        local target = P.ByRole(members)
        local size, last = {}, 0
        for g = 1, 8 do size[g] = 0 end
        for i = 1, #members do size[target[members[i].name]] = size[target[members[i].name]] + 1 end
        for g = 1, 8 do assert(size[g] <= 5, "a group is over five") end
        local sorted = {}
        for i = 1, #members do sorted[i] = members[i] end
        table.sort(sorted, function(a, b)
            if target[a.name] ~= target[b.name] then return target[a.name] < target[b.name] end
            return P.KIND_ORDER[P.Kind(a)] < P.KIND_ORDER[P.Kind(b)]
        end)
        for i = 1, #sorted do
            local k = P.KIND_ORDER[P.Kind(sorted[i])]
            assert(k >= last, "kinds are out of order")
            last = k
        end
        worst = math.max(worst, Run(members, target))

        -- Split: two sides, each kind within one of the other side.
        members = Roster(n, seed * 17 + n)
        local split, perSide = P.Split(members)
        local a = Count(members, split, 1, perSide)
        local b = Count(members, split, perSide + 1, perSide * 2)
        assert(a.all + b.all == n, "the split lost someone")
        for _, k in ipairs({ "TANK", "MELEE", "RANGED", "HEALER", "all" }) do
            assert(math.abs(a[k] - b[k]) <= 1, "the sides are uneven in " .. k)
        end
        worst = math.max(worst, Run(members, split))

        -- Undo: a snapshot taken before a sort puts everyone back.
        members = Roster(n, seed * 7 + n)
        local before = P.Snapshot(members)
        Run(members, P.ByRole(members))
        Run(members, before)
        runs = runs + 3
    end
end
print(("raid lead planner: %d plans checked, most moves needed for one: %d"):format(runs, worst))
