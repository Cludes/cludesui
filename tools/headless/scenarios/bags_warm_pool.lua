-- Bags: CUI_Bags:WarmSlotPool, the builder of the secure item-button pools.
-- Called directly in each situation, with the slot creator and the list-row
-- warmer replaced by recorders: grid display (all built; the creator failing
-- part way, as the combat guard does; the time budget running out), list
-- display (pinned and recent items add rows; the row warmer failing), the
-- display mode still unknown, and the reagent pool (real slots, 4 of them).
-- Each case prints the return value, whether the pool is flagged short, and
-- what the creator, the hider and the row warmer saw.
local ns = CludesUI._ModuleNS and CludesUI._ModuleNS["CludesUIBags"]
local bags = rawget(_G, "CUI_Bags")
if not (ns and bags and bags.WarmSlotPool) then
    OUT:write("== no bags pool builder\n")
    return
end
local inner = ns._bagsInternals
local p = inner and inner.BP and inner.BP()
if not p then
    OUT:write("== no bags profile\n")
    return
end

-- Bag sizes: bags 0-4 hold 6 slots each (30), the reagent bag (5) holds 4.
C_Container.GetContainerNumSlots = function(bag)
    if bag == 5 then return 4 end
    if bag >= 0 and bag <= 4 then return 6 end
    return 0
end

local made, hidden, warmed = {}, {}, {}
local failAt, warmResult
ns.GetOrCreateSlot = function(i)
    made[#made + 1] = i
    if failAt and i >= failAt then return nil end
    return {
        GetParent = function()
            return { Hide = function() hidden[#hidden + 1] = i end }
        end,
    }
end
ns.WarmListRows = function(sum, t0, budget)
    warmed[#warmed + 1] = tostring(sum) .. "/" .. tostring(t0 ~= nil) .. "/" .. tostring(budget)
    return warmResult
end
local clock = 0
local realClock = debugprofilestop
debugprofilestop = function()
    clock = clock + 1
    return clock
end

local function Latch(mode)
    p.bagDisplayMode = mode
    local fn = bags.IsListMode
    for i = 1, 20 do
        local name = debug.getupvalue(fn, i)
        if not name then break end
        if name == "_listMode" then debug.setupvalue(fn, i, nil) end
    end
end

local function Case(label, mode, budget, fail, warm)
    Latch(mode)
    made, hidden, warmed = {}, {}, {}
    failAt, warmResult = fail, warm
    clock = 0
    bags._poolShort = nil
    for k in pairs(inner.reagentSlots) do inner.reagentSlots[k] = nil end
    local ok, res = pcall(bags.WarmSlotPool, bags, budget)
    local reagents = 0
    for _ in pairs(inner.reagentSlots) do reagents = reagents + 1 end
    OUT:write(string.format("== %s: ok=%s result=%s short=%s made=%d hidden=%d warmed=[%s] reagents=%d\n", label,
        tostring(ok), tostring(res), tostring(bags._poolShort), #made, #hidden, table.concat(warmed, ","), reagents))
    OUT:write("   made: " .. table.concat(made, ",") .. "\n")
end

CludesUIDB.bagPinsPerCharacter = false
CludesUIDB.bagPinnedItems = nil
bags._recentItems = nil

Case("grid, all built", "grid", nil, nil, true)
Case("grid, creator fails from slot 10", "grid", nil, 10, true)
Case("grid, time budget spent after the first slot", "grid", 1, nil, true)
Case("grid, budget never reached", "grid", 100000, nil, true)

CludesUIDB.bagPinnedItems = { a = true, b = true, c = true }
bags._recentItems = { x = true, y = true }
Case("list, pinned 3 + recent 2, rows warm", "list", nil, nil, true)
Case("list, rows warm fails", "list", 5, nil, false)
bags._recentItems = nil
CludesUIDB.bagPinnedItems = nil
Case("list, none pinned or recent", "list", nil, nil, true)

-- Mode still unknown: nothing built, flagged short, reagents still built.
local realIsList = bags.IsListMode
bags.IsListMode = function() return nil end
Case("mode unknown", "grid", nil, nil, true)
bags.IsListMode = realIsList

debugprofilestop = realClock
Latch("grid")
