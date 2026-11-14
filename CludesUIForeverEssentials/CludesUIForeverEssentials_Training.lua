if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Training.lua -- Training Planner (WoW Forever).
--
--  What your class can learn at its trainer: what you can train right now,
--  and what each coming level brings with its price. The spell list and the
--  base prices are TrainingData.lua (from What's Training, MIT licence).
--  A reputation discount at the trainer is not counted, so a real bill can
--  be a little lower than the total shown.
--
--  A spell counts as learned when the game says the player knows it. A rank
--  needs the rank before it (requiredSpellIDs); a Rogue poison also needs
--  the Poisons skill at a level, which is shown, not checked.
-------------------------------------------------------------------------------
local _, ns = ...

local function Settings()
    CludesUIDB.foreverTraining = CludesUIDB.foreverTraining or {}
    local s = CludesUIDB.foreverTraining
    if s.levelUpMessage == nil then s.levelUpMessage = true end
    return s
end
ns.TrainingSettings = Settings

local function Known(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) end
    return IsSpellKnown and IsSpellKnown(id) or false
end

--- "Name (Rank 3)" for a spell.
function ns.TrainingSpellLabel(id)
    local name = C_Spell.GetSpellName(id) or ("Spell " .. id)
    local rank = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
    if type(rank) == "string" and rank ~= "" then name = name .. " (" .. rank .. ")" end
    return name
end

function ns.TrainingMoney(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

--- The plan for this character:
---   now     = { entry, ... }   learnable at the trainer right now
---   coming  = { [level] = { entry, ... } }
---   nowCost, levels (sorted list of coming levels)
--- entry = { id, cost, level, skillLevel, needs = spellID it is waiting on }
--- A rank that waits on an earlier rank from the same trainer is not
--- flagged: you will have trained that one first. `needs` is set only when
--- the missing spell comes from somewhere else (a talent, a quest, a spell
--- every character starts with), since the trainer cannot sell it.
function ns.TrainingPlan()
    local _, class = UnitClass("player")
    local data = ns.TrainingData and ns.TrainingData[class]
    local plan = { now = {}, coming = {}, levels = {}, blocked = {}, nowCost = 0 }
    if not data then return plan end
    local level = UnitLevel("player")

    local order, sold = {}, {}
    for lvl, rows in pairs(data) do
        order[#order + 1] = lvl
        for _, r in ipairs(rows) do sold[r[1]] = true end
    end
    table.sort(order)

    -- What the player can get: known spells, plus trainer spells reachable
    -- through them. `ready` holds what is trainable up to the current level,
    -- `later` what a coming level will make trainable.
    local ready, later, blockedBy = {}, {}, {}
    local function Have(id, upTo) return Known(id) or ready[id] or (upTo > level and later[id]) end
    for _, lvl in ipairs(order) do
        local changed = true
        while changed do        -- a rank can wait on one listed after it at the same level
            changed = false
            for _, r in ipairs(data[lvl]) do
                local id = r[1]
                if not Known(id) and not ready[id] and not later[id] then
                    local ok = true
                    for _, need in ipairs(r[3] or {}) do
                        if not Have(need, lvl) then ok = false; break end
                    end
                    if ok then
                        if lvl <= level then ready[id] = true else later[id] = true end
                        changed = true
                    end
                end
            end
        end
    end
    -- The first missing requirement that no trainer sells, for the label.
    local function Root(id, seen)
        seen = seen or {}
        if seen[id] then return nil end
        seen[id] = true
        for lvl, rows in pairs(data) do
            for _, r in ipairs(rows) do
                if r[1] == id then
                    for _, need in ipairs(r[3] or {}) do
                        if not Known(need) and not ready[need] and not later[need] then
                            if not sold[need] then return need end
                            local deeper = Root(need, seen)
                            if deeper then return deeper end
                        end
                    end
                end
            end
        end
    end

    for _, lvl in ipairs(order) do
        for _, r in ipairs(data[lvl]) do
            local id = r[1]
            if not Known(id) then
                local entry = { id = id, cost = r[2], level = lvl, skillLevel = r[5] }
                if not ready[id] and not later[id] then
                    blockedBy[id] = Root(id)
                    entry.needs = blockedBy[id]
                end
                if ready[id] then
                    plan.now[#plan.now + 1] = entry
                    plan.nowCost = plan.nowCost + entry.cost
                elseif lvl > level or entry.needs then
                    -- Waiting on a level, or on something the trainer cannot sell.
                    local at = lvl > level and lvl or 0
                    plan.coming[at] = plan.coming[at] or {}
                    table.insert(plan.coming[at], entry)
                end
            end
        end
    end
    -- Level 0 = "waiting on a talent or quest", listed apart by the page.
    plan.blocked = plan.coming[0] or {}
    plan.coming[0] = nil
    for lvl in pairs(plan.coming) do plan.levels[#plan.levels + 1] = lvl end
    table.sort(plan.levels)
    return plan
end

-- Learning a spell or a level changes the plan: drop the cached Training
-- page, and rebuild it in place if it is the page on screen. SPELLS_CHANGED
-- fires in bursts, so the rebuild waits for them to settle.
local refreshQueued
local function RefreshPage()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.5, function()
        refreshQueued = nil
        if not CludesUI.InvalidateModulePageCache then return end
        CludesUI:InvalidateModulePageCache("CludesUIForeverEssentials")
        if CludesUI.GetActiveModule and CludesUI:GetActiveModule() == "CludesUIForeverEssentials"
            and CludesUI:GetActivePage() == "Training" then
            CludesUI:RefreshPage(true)
        end
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("SPELLS_CHANGED")
ev:SetScript("OnEvent", function(_, event, newLevel)
    RefreshPage()
    if event ~= "PLAYER_LEVEL_UP" or not Settings().levelUpMessage then return end
    C_Timer.After(2, function()
        local plan = ns.TrainingPlan()
        local fresh, cost = 0, 0
        for _, e in ipairs(plan.now) do
            if e.level == newLevel then fresh = fresh + 1; cost = cost + e.cost end
        end
        if fresh > 0 then
            CludesUI.Print(("|cff4cc9f0Training:|r level %d brings %d new spell%s (%s). %d in all to train now (%s)."):format(
                newLevel, fresh, fresh == 1 and "" or "s", ns.TrainingMoney(cost), #plan.now, ns.TrainingMoney(plan.nowCost)))
        end
    end)
end)
