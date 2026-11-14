if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Training_Options.lua
--  Forever Tools > Training: the Training Planner page. Lists what you can
--  train now with its total, then the next levels that bring spells.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIForeverEssentials"]
if not mod then
    return
end

local COMING_LEVELS = 6 -- how many coming levels the page lists

function _G._CUI_BuildForeverTrainingPage(_, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local posY = yOffset
    local _, hgt
    local s = mod.TrainingSettings()

    CludesUI:ClearContentHeader()

    _, hgt = W:SectionHeader(hostFrame, "TRAINING PLANNER", posY)
    posY = posY - hgt
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Message on Level Up",
        tooltip = "When you level up, a chat line says how many new spells your trainer has for you and what they cost.",
        getValue = function()
            return s.levelUpMessage
        end,
        setValue = function(val)
            s.levelUpMessage = val and true or false
        end,
    }, {
        type = "label",
        text = "Base prices, before rep discount",
        tooltip = "Prices are the trainer's base prices. A reputation discount at the trainer makes the real bill a little lower.",
    })
    posY = posY - hgt

    local plan = mod.TrainingPlan()

    -- Two spells a row: the page's dual rows hold one item each side.
    local function List(entries, showLevel)
        for idx = 1, #entries, 2 do
            local function Slot(e)
                if not e then
                    return { type = "label", text = "" }
                end
                local textValue = mod.TrainingSpellLabel(e.id)
                    .. "  |cff9aa6b2"
                    .. mod.TrainingMoney(e.cost)
                    .. "|r"
                if showLevel then
                    textValue = "|cff4cc9f0" .. e.level .. "|r  " .. textValue
                end
                if e.needs then
                    textValue = textValue
                        .. "  |cffffb040needs "
                        .. (C_Spell.GetSpellName(e.needs) or ("spell " .. e.needs))
                        .. "|r"
                end
                if e.skillLevel then
                    textValue = textValue .. "  |cff9aa6b2Poisons " .. e.skillLevel .. "|r"
                end
                return { type = "label", text = textValue, tooltip = textValue }
            end
            _, hgt = W:DualRow(hostFrame, posY, Slot(entries[idx]), Slot(entries[idx + 1]))
            posY = posY - hgt
        end
    end

    _, hgt = W:SectionHeader(
        hostFrame,
        ("TRAIN NOW  -  %d SPELL%s, %s"):format(
            #plan.now,
            #plan.now == 1 and "" or "S",
            mod.TrainingMoney(plan.nowCost)
        ),
        posY
    )
    posY = posY - hgt
    if #plan.now == 0 then
        _, hgt = W:DualRow(
            hostFrame,
            posY,
            { type = "label", text = "Nothing to train right now." },
            { type = "label", text = "" }
        )
        posY = posY - hgt
    else
        List(plan.now, true)
    end

    if #plan.blocked > 0 then
        _, hgt = W:SectionHeader(hostFrame, "WAITING ON A TALENT OR QUEST", posY)
        posY = posY - hgt
        List(plan.blocked, true)
    end

    for idx = 1, math.min(COMING_LEVELS, #plan.levels) do
        local lvl = plan.levels[idx]
        local entries = plan.coming[lvl]
        local cost = 0
        for _, e in ipairs(entries) do
            cost = cost + e.cost
        end
        _, hgt = W:SectionHeader(hostFrame, ("LEVEL %d  -  %s"):format(lvl, mod.TrainingMoney(cost)), posY)
        posY = posY - hgt
        List(entries, false)
    end

    return math.abs(posY)
end
