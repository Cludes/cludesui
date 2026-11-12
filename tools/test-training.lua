-- Runs the Forever Tools training planner outside the game:  luajit tools/test-training.lua
local root = "."
local known, level, class = {}, 1, "WARRIOR"
C_SpellBook = { IsSpellKnown = function(id) return known[id] or false end }
C_Spell = { GetSpellName = function(id) return "S" .. id end }
UnitClass = function() return "x", class end
UnitLevel = function() return level end
CludesUIDB = {}
CludesUI = { Print = print }
C_Timer = { After = function() end }
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
local ns = {}
assert(loadfile(root .. "/CludesUIForeverEssentials/CludesUIForeverEssentials_TrainingData.lua"))("x", ns)
assert(loadfile(root .. "/CludesUIForeverEssentials/CludesUIForeverEssentials_Training.lua"))("x", ns)

local fails = 0
local function check(cond, msg) if not cond then fails = fails + 1; print("FAIL " .. msg) end end

for c in pairs(ns.TrainingData) do
    class = c
    local sold, outside, total = {}, {}, 0
    for _, rows in pairs(ns.TrainingData[c]) do
        for _, r in ipairs(rows) do sold[r[1]] = true; total = total + 1 end
    end
    for _, rows in pairs(ns.TrainingData[c]) do
        for _, r in ipairs(rows) do
            for _, n in ipairs(r[3] or {}) do if not sold[n] then outside[n] = true end end
        end
    end
    -- 1. Every outside requirement known, level 60: everything trainable now.
    known, level = {}, 60
    for id in pairs(outside) do known[id] = true end
    local p = ns.TrainingPlan()
    check(#p.now == total and #p.blocked == 0 and #p.levels == 0, c .. " full: now=" .. #p.now .. "/" .. total .. " blocked=" .. #p.blocked)
    for _, e in ipairs(p.now) do known[e.id] = true end
    check(#ns.TrainingPlan().now == 0, c .. " nothing left after training")
    -- 2. Nothing known, level 60: every non-trainable spell names an outside spell.
    known = {}
    p = ns.TrainingPlan()
    check(#p.now + #p.blocked == total, c .. " split adds up")
    for _, e in ipairs(p.blocked) do check(outside[e.needs], c .. " blocked " .. e.id .. " names " .. tostring(e.needs)) end
    -- 3. Level 10 with outside spells known: now only <=10, coming sorted, no needs flags.
    level = 10
    for id in pairs(outside) do known[id] = true end
    p = ns.TrainingPlan()
    for _, e in ipairs(p.now) do check(e.level <= 10, c .. " level filter") end
    for i = 2, #p.levels do check(p.levels[i] > p.levels[i - 1], c .. " sorted") end
    for _, l in ipairs(p.levels) do for _, e in ipairs(p.coming[l]) do check(not e.needs, c .. " coming needs " .. e.id) end end
    print(("%-8s total=%d"):format(c, total))
end
print(fails == 0 and "ALL OK" or (fails .. " failures"))
if fails > 0 then os.exit(1) end
