if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Training_Options.lua
--  Forever Tools > Training: the Training Planner page. Lists what you can
--  train now with its total, then the next levels that bring spells.
-------------------------------------------------------------------------------
local ns = CludesUI._ModuleNS["CludesUIForeverEssentials"]
if not ns then return end

local COMING_LEVELS = 6     -- how many coming levels the page lists

function _G._CUI_BuildForeverTrainingPage(_, parent, yOffset)
    local W = CludesUI.Widgets
    local y = yOffset
    local _, h
    local s = ns.TrainingSettings()

    CludesUI:ClearContentHeader()

    _, h = W:SectionHeader(parent, "TRAINING PLANNER", y);  y = y - h
    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Message on Level Up",
          tooltip = "When you level up, a chat line says how many new spells your trainer has for you and what they cost.",
          getValue = function() return s.levelUpMessage end,
          setValue = function(v) s.levelUpMessage = v and true or false end },
        { type = "label", text = "Base prices, before rep discount",
          tooltip = "Prices are the trainer's base prices. A reputation discount at the trainer makes the real bill a little lower." }
    );  y = y - h

    local plan = ns.TrainingPlan()

    -- Two spells a row: the page's dual rows hold one item each side.
    local function List(entries, showLevel)
        for i = 1, #entries, 2 do
            local function Slot(e)
                if not e then return { type = "label", text = "" } end
                local text = ns.TrainingSpellLabel(e.id) .. "  |cff9aa6b2" .. ns.TrainingMoney(e.cost) .. "|r"
                if showLevel then text = "|cff4cc9f0" .. e.level .. "|r  " .. text end
                if e.needs then text = text .. "  |cffffb040needs " .. (C_Spell.GetSpellName(e.needs) or ("spell " .. e.needs)) .. "|r" end
                if e.skillLevel then text = text .. "  |cff9aa6b2Poisons " .. e.skillLevel .. "|r" end
                return { type = "label", text = text, tooltip = text }
            end
            _, h = W:DualRow(parent, y, Slot(entries[i]), Slot(entries[i + 1]));  y = y - h
        end
    end

    _, h = W:SectionHeader(parent, ("TRAIN NOW  -  %d SPELL%s, %s"):format(#plan.now, #plan.now == 1 and "" or "S",
        ns.TrainingMoney(plan.nowCost)), y);  y = y - h
    if #plan.now == 0 then
        _, h = W:DualRow(parent, y, { type = "label", text = "Nothing to train right now." }, { type = "label", text = "" });  y = y - h
    else
        List(plan.now, true)
    end

    if #plan.blocked > 0 then
        _, h = W:SectionHeader(parent, "WAITING ON A TALENT OR QUEST", y);  y = y - h
        List(plan.blocked, true)
    end

    for i = 1, math.min(COMING_LEVELS, #plan.levels) do
        local lvl = plan.levels[i]
        local entries = plan.coming[lvl]
        local cost = 0
        for _, e in ipairs(entries) do cost = cost + e.cost end
        _, h = W:SectionHeader(parent, ("LEVEL %d  -  %s"):format(lvl, ns.TrainingMoney(cost)), y);  y = y - h
        List(entries, false)
    end

    return math.abs(y)
end
