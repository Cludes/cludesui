if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_SpellEfficiency.lua  (WoW Forever only)
--  Mana Efficiency: on a mana spell's tooltip (and a macro that casts one),
--  its healing or damage per mana, per second, and per mana per second.
--  The amount is the rank's base at your level plus your spell power times
--  the spell's coefficient (cut for spells learned below level 20), with
--  talents that raise it or lower its cost counted. Area spells say
--  "/ target". The data is SpellEfficiencyData.lua.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("spellEfficiency", {
    enabled = false,
    perMana = true,
    perSecond = true,
    perManaSecond = false,
    style = "long",
    decimals = 2,
    bonus = true,
    talents = true,
    show = "all",
})
local Get, Enabled = F.Get, F.Enabled

local Data = module.SpellEfficiencyData or {}
local TalentData = module.SpellEfficiencyTalents or {}

local SCHOOL, LEVEL, MAX_LEVEL, AREA = 1, 2, 3, 4
local PART_START, PART_SIZE = 5, 9
local KIND, DIRECT, DIRECT_PER_LEVEL, DIRECT_COEFFICIENT = 0, 1, 2, 3
local TICK, TICK_PER_LEVEL, TICK_COEFFICIENT, TICKS, SECONDS = 4, 5, 6, 7, 8
local HEAL, DAMAGE = 1, 0
local MOD_NODE, MOD_OP = 1, 2
local OP_DIRECT, OP_PERIODIC, OP_CRIT_REFUND = 0, 1, 2
local LOW_LEVEL_CAP, LOW_LEVEL_STEP = 20, 0.0375
local MANA = Enum.PowerType.Mana
local COLOR = { 0x4d / 255, 0xb5 / 255, 0xf5 / 255 }
local SEPARATOR = "  ||  "
local LONG_FIRST = { "%s %s per mana", "%s %s per second", "%s %s per mana per second" }
local LONG_NEXT = { "%s per mana", "%s per second", "%s per mana per second" }
local SHORT_LABELS = { [HEAL] = { "HPM", "HPS", "HPM/s" }, [DAMAGE] = { "DPM", "DPS", "DPM/s" } }
local KIND_WORDS = { [HEAL] = "healing", [DAMAGE] = "damage" }
local PER_MANA, PER_SECOND, PER_MANA_SECOND = 1, 2, 3

local function Secret(val)
    return issecretvalue and issecretvalue(val)
end
local function Readable(val)
    return not Secret(val) and (not canaccessvalue or canaccessvalue(val))
end
local function ReadableTable(val)
    return Readable(val) and not (issecrettable and issecrettable(val)) and type(val) == "table"
end
local function StatsSecret()
    return C_Secrets and C_Secrets.ShouldUnitStatsBeSecret and C_Secrets.ShouldUnitStatsBeSecret()
end

-- "a,b,c" text to numbers; false when malformed.
local function Numbers(textValue, sep)
    local result, at = {}, 1
    repeat
        local stop = textValue:find(sep, at, true)
        local field = textValue:sub(at, (stop or 0) - 1)
        if not field:find("^%-?%d+%.?%d*$") then
            return false
        end
        result[#result + 1] = tonumber(field)
        at = stop and stop + 1
    until not at
    return result
end

local decoded, decodedMods = {}, {}

local function Entry(spellId)
    local e = decoded[spellId]
    if e == nil then
        local textValue = Data[spellId]
        if type(textValue) ~= "string" then
            return nil
        end
        e = Numbers(textValue, ",")
        if e and (#e < PART_START or (#e - AREA) % PART_SIZE ~= 0) then
            e = false
        end
        if e then
            for part = PART_START, #e, PART_SIZE do
                if e[part + KIND] ~= HEAL and e[part + KIND] ~= DAMAGE then
                    e = false
                    break
                end
            end
        end
        decoded[spellId] = e
    end
    return e or nil
end

local function ModsOf(spellId)
    local m = decodedMods[spellId]
    if m == nil then
        local textValue = TalentData[spellId]
        if type(textValue) ~= "string" then
            return nil
        end
        m = {}
        for part in (textValue .. ";"):gmatch("([^;]*);") do
            local mod = Numbers(part, ",")
            if not mod or #mod <= MOD_OP then
                m = false
                break
            end
            m[#m + 1] = mod
        end
        decodedMods[spellId] = m
    end
    return m or nil
end

local function TalentRank(node)
    local config = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    local details = config and C_Traits.GetNodeInfo(config, node)
    local rank = ReadableTable(details) and details.activeRank
    return type(rank) == "number" and rank or 0
end

local function CritChance(school)
    if StatsSecret() then
        return nil
    end
    local crit = GetSpellCritChance(school)
    if not Readable(crit) or type(crit) ~= "number" then
        return nil
    end
    return math.min(crit / 100, 1)
end

local function TalentEffects(spellId, school)
    local direct, periodic, cost = 1, 1, 1
    local mods = Get("talents") and ModsOf(spellId)
    if not mods then
        return direct, periodic, cost
    end
    for _, mod in ipairs(mods) do
        local rank = TalentRank(mod[MOD_NODE])
        if rank > 0 then
            local value = mod[MOD_OP + math.min(rank, #mod - MOD_OP)]
            local op = mod[MOD_OP]
            if op == OP_DIRECT then
                direct = direct + value
            elseif op == OP_PERIODIC then
                periodic = periodic + value
            elseif op == OP_CRIT_REFUND then
                local crit = CritChance(school)
                if crit then
                    cost = cost * (1 - value * crit)
                end
            else
                cost = cost * (1 - value)
            end
        end
    end
    return direct, periodic, cost
end

local function Shows(kind)
    local show = Get("show")
    if show == "heal" then
        return kind == HEAL
    end
    if show == "damage" then
        return kind ~= HEAL
    end
    return true
end

local function Number(value, whole)
    if whole then
        return ("%d"):format(math.floor(value + 0.5))
    end
    return ("%." .. math.max(0, math.min(2, Get("decimals"))) .. "f"):format(value)
end

local function Piece(textValue, which, kind, value, area)
    local number = Number(value, which == PER_SECOND)
    local piece
    if Get("style") == "short" then
        piece = ("%s %s"):format(SHORT_LABELS[kind][which], number)
    elseif textValue then
        piece = LONG_NEXT[which]:format(number)
    else
        piece = LONG_FIRST[which]:format(number, KIND_WORDS[kind])
    end
    if area then
        piece = piece .. " / target"
    end
    if not textValue then
        return piece
    end
    return textValue .. SEPARATOR .. piece
end

local function Rate(kind, amount, mana, seconds)
    local p = { kind = kind, amount = amount, perMana = amount / mana }
    if seconds and seconds > 0 then
        p.perSecond, p.perManaSecond = amount / seconds, p.perMana / seconds
    end
    return p
end

local function Line(part, area)
    local textValue = Get("perMana") and Piece(nil, PER_MANA, part.kind, part.perMana, area) or nil
    if part.perSecond then
        if Get("perSecond") then
            textValue = Piece(textValue, PER_SECOND, part.kind, part.perSecond, area)
        end
        if Get("perManaSecond") then
            textValue = Piece(textValue, PER_MANA_SECOND, part.kind, part.perManaSecond, area)
        end
    end
    return textValue
end

-- Spells learned below level 20 get only part of your spell power.
local function Penalty(e)
    local lvl = e[LEVEL]
    if lvl < 1 or lvl >= LOW_LEVEL_CAP then
        return 1
    end
    return 1 - (LOW_LEVEL_CAP - lvl) * LOW_LEVEL_STEP
end

local function LevelGain(e, level)
    local cap = e[MAX_LEVEL]
    if cap > 0 and level > cap then
        level = cap
    end
    local g = level - e[LEVEL]
    return g > 0 and g or 0
end

local function Amount(e, at, gain, bonus, directMod, periodicMod)
    local scaled = bonus * Penalty(e)
    local direct = (e[at + DIRECT] + e[at + DIRECT_PER_LEVEL] * gain + e[at + DIRECT_COEFFICIENT] * scaled)
        * directMod
    local tick = (e[at + TICK] + e[at + TICK_PER_LEVEL] * gain + e[at + TICK_COEFFICIENT] * scaled)
        * periodicMod
    return direct + tick * e[at + TICKS]
end

local function ManaCost(spellId)
    local costs = C_Spell.GetSpellPowerCost(spellId)
    if not ReadableTable(costs) then
        return nil
    end
    for _, c in ipairs(costs) do
        if not (Readable(c.type) and Readable(c.cost)) then
            return nil
        end
        if c.type == MANA and c.cost > 0 then
            return c.cost
        end
    end
end

local function CastMs(spellId)
    local details = C_Spell.GetSpellInfo(spellId)
    if not ReadableTable(details) then
        return nil
    end
    local ms = details.castTime
    if not Readable(ms) or type(ms) ~= "number" then
        return nil
    end
    return ms
end

local function Bonus(e, kind)
    if not Get("bonus") then
        return 0
    end
    if StatsSecret() then
        return nil
    end
    local b = kind == HEAL and GetSpellBonusHealing() or GetSpellBonusDamage(e[SCHOOL])
    if not Readable(b) or type(b) ~= "number" then
        return nil
    end
    return b
end

--- { mana, castMs, area, level, count, [i] = { kind, amount, perMana, perSecond, perManaSecond } }
function module.SpellEfficiencyOf(spellId)
    local e = Entry(spellId)
    if not e then
        return nil
    end
    local mana = ManaCost(spellId)
    local castMs = mana and CastMs(spellId)
    local level = UnitLevel("player")
    if not (mana and castMs and Readable(level)) then
        return nil
    end
    local gain = LevelGain(e, level)
    local directMod, periodicMod, costMod = TalentEffects(spellId, e[SCHOOL])
    mana = mana * costMod
    local result = { mana = mana, castMs = castMs, area = e[AREA] == 1, level = e[LEVEL], count = 0 }
    for at = PART_START, #e, PART_SIZE do
        local kind = e[at + KIND]
        if Shows(kind) then
            local bonus = Bonus(e, kind)
            if not bonus then
                break
            end
            local amount = Amount(e, at, gain, bonus, directMod, periodicMod)
            if amount > 0 and mana > 0 then
                local seconds = castMs > 0 and castMs / 1000
                    or (e[at + SECONDS] > 0 and e[at + SECONDS] or nil)
                result.count = result.count + 1
                result[result.count] = Rate(kind, amount, mana, seconds)
            end
        end
    end
    return result
end

local decoratedAt = setmetatable({}, { __mode = "k" })
local decoratedText = setmetatable({}, { __mode = "k" })

local function AddLines(tooltip, spellId)
    local r = module.SpellEfficiencyOf(spellId)
    if not r then
        return
    end
    local first
    for idx = 1, r.count do
        local textValue = Line(r[idx], r.area)
        if textValue then
            if not first then
                -- The game can call the hook twice for one tooltip: add the line once.
                local at = decoratedAt[tooltip]
                if at and at <= tooltip:NumLines() and decoratedText[tooltip] == textValue then
                    local leftX = _G[tooltip:GetName() .. "TextLeft" .. at]
                    local isShown = leftX and leftX:GetText()
                    if Readable(isShown) and isShown == textValue then
                        return
                    end
                end
                first = textValue
            end
            tooltip:AddLine(textValue, COLOR[1], COLOR[2], COLOR[3])
            if first == textValue then
                decoratedAt[tooltip], decoratedText[tooltip] = tooltip:NumLines(), textValue
            end
        end
    end
end

local function Decorates(tooltip)
    return Enabled()
        and not (tooltip.IsForbidden and tooltip:IsForbidden())
        and (tooltip == GameTooltip or tooltip == ItemRefTooltip)
end

local function ActionSlot(ownerFrame)
    local a = ownerFrame.action
    if Readable(a) and type(a) == "number" then
        return a
    end
    a = ownerFrame.GetAttribute and ownerFrame:GetAttribute("action")
    if Readable(a) and type(a) == "number" then
        return a
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, payload)
        if not Decorates(tooltip) or not ReadableTable(payload) then
            return
        end
        local ident = payload.id
        if Readable(ident) and type(ident) == "number" then
            AddLines(tooltip, ident)
        end
    end)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, function(tooltip)
        if not Decorates(tooltip) then
            return
        end
        local ownerFrame = tooltip:GetOwner()
        local action = ownerFrame and ActionSlot(ownerFrame)
        if not action then
            return
        end
        local kind, ident, subType = GetActionInfo(action)
        if kind ~= "macro" or not (Readable(ident) and type(ident) == "number") then
            return
        end
        local spellId = subType == "spell" and ident or GetMacroSpell(ident)
        if Readable(spellId) and type(spellId) == "number" then
            AddLines(tooltip, spellId)
        end
    end)
end

CludesUI._SpellEfficiency = { Get = Get, Cfg = F.Cfg }

F.Start(function() end)
