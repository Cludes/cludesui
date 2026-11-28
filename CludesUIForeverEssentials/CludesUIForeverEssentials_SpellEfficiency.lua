if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
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

local Info = module.SpellEfficiencyData or {}
local TalentInfo = module.SpellEfficiencyTalents or {}

local SCHOOL, LVL, MAX_LVL, AREA = 1, 2, 3, 4
local PART_START, PART_SIZE = 5, 9
local KIND, DIRECT, DIRECT_PER_LVL, DIRECT_COEFFICIENT = 0, 1, 2, 3
local TICK, TICK_PER_LVL, TICK_COEFFICIENT, TICKS, SECONDS = 4, 5, 6, 7, 8
local HEAL, DAMAGE = 1, 0
local MOD_NODE, MOD_OP = 1, 2
local OP_DIRECT, OP_PERIODIC, OP_CRIT_REFUND = 0, 1, 2
local LOWER_LVL_LIMIT, LOWER_LVL_STEP = 20, 0.0375
local MANA = Enum.PowerType.Mana
local TINT = { 0x4d / 255, 0xb5 / 255, 0xf5 / 255 }
local SEPARATOR = "  ||  "
local LONG_FIRST = { "%s %s per mana", "%s %s per second", "%s %s per mana per second" }
local LONG_NEXT = { "%s per mana", "%s per second", "%s per mana per second" }
local SHORT_NAMES = { [HEAL] = { "HPM", "HPS", "HPM/s" }, [DAMAGE] = { "DPM", "DPS", "DPM/s" } }
local KIND_TERMS = { [HEAL] = "healing", [DAMAGE] = "damage" }
local PER_MANA, PER_SECOND, PER_MANA_SECOND = 1, 2, 3

local function Secret(val) return issecretvalue and issecretvalue(val) end
local function Plain(val) return not Secret(val) and (not canaccessvalue or canaccessvalue(val)) end
local function PlainTable(val)
    return Plain(val) and not (issecrettable and issecrettable(val)) and type(val) == "table"
end
local function StatsSecret()
    return C_Secrets and C_Secrets.ShouldUnitStatsBeSecret and C_Secrets.ShouldUnitStatsBeSecret()
end

-- "a,b,c" text to numbers; false when malformed.
local function Numbers(labelValue, sep)
    local result, at = {}, 1
    repeat
        local halt = labelValue:find(sep, at, true)
        local field = labelValue:sub(at, (halt or 0) - 1)
        if not field:find("^%-?%d+%.?%d*$") then return false end
        result[#result + 1] = tonumber(field)
        at = halt and halt + 1
    until not at
    return result
end

local decoded, decodedMods = {}, {}

local function Entry(spellId)
    local e = decoded[spellId]
    if e == nil then
        local labelValue = Info[spellId]
        if type(labelValue) ~= "string" then return nil end
        e = Numbers(labelValue, ",")
        if e and (#e < PART_START or (#e - AREA) % PART_SIZE ~= 0) then e = false end
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
        local labelValue = TalentInfo[spellId]
        if type(labelValue) ~= "string" then return nil end
        m = {}
        for part in (labelValue .. ";"):gmatch("([^;]*);") do
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

local function TalentTier(node)
    local config = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    local details = config and C_Traits.GetNodeInfo(config, node)
    local tier = PlainTable(details) and details.activeRank
    return type(tier) == "number" and tier or 0
end

local function CritOdds(school)
    if StatsSecret() then return nil end
    local crit = GetSpellCritChance(school)
    if not Plain(crit) or type(crit) ~= "number" then return nil end
    return math.min(crit / 100, 1)
end

local function TalentEffects(spellId, school)
    local direct, periodic, cost = 1, 1, 1
    local mods = Get("talents") and ModsOf(spellId)
    if not mods then return direct, periodic, cost end
    for _, mod in ipairs(mods) do
        local tier = TalentTier(mod[MOD_NODE])
        if tier > 0 then
            local value = mod[MOD_OP + math.min(tier, #mod - MOD_OP)]
            local op = mod[MOD_OP]
            if op == OP_DIRECT then
                direct = direct + value
            elseif op == OP_PERIODIC then
                periodic = periodic + value
            elseif op == OP_CRIT_REFUND then
                local crit = CritOdds(school)
                if crit then cost = cost * (1 - value * crit) end
            else
                cost = cost * (1 - value)
            end
        end
    end
    return direct, periodic, cost
end

local function Shows(kind)
    local display = Get("show")
    if display == "heal" then return kind == HEAL end
    if display == "damage" then return kind ~= HEAL end
    return true
end

local function Number(value, whole)
    if whole then return ("%d"):format(math.floor(value + 0.5)) end
    return ("%." .. math.max(0, math.min(2, Get("decimals"))) .. "f"):format(value)
end

local function Piece(labelValue, which, kind, value, area)
    local number = Number(value, which == PER_SECOND)
    local piece
    if Get("style") == "short" then
        piece = ("%s %s"):format(SHORT_NAMES[kind][which], number)
    elseif labelValue then
        piece = LONG_NEXT[which]:format(number)
    else
        piece = LONG_FIRST[which]:format(number, KIND_TERMS[kind])
    end
    if area then piece = piece .. " / target" end
    if not labelValue then return piece end
    return labelValue .. SEPARATOR .. piece
end

local function Rate(kind, amount, mana, seconds)
    local p = { kind = kind, amount = amount, perMana = amount / mana }
    if seconds and seconds > 0 then
        p.perSecond, p.perManaSecond = amount / seconds, p.perMana / seconds
    end
    return p
end

local function Line(part, area)
    local labelValue = Get("perMana") and Piece(nil, PER_MANA, part.kind, part.perMana, area) or nil
    if part.perSecond then
        if Get("perSecond") then labelValue = Piece(labelValue, PER_SECOND, part.kind, part.perSecond, area) end
        if Get("perManaSecond") then
            labelValue = Piece(labelValue, PER_MANA_SECOND, part.kind, part.perManaSecond, area)
        end
    end
    return labelValue
end

-- Spells learned below level 20 get only part of your spell power.
local function Penalty(e)
    local lvl = e[LVL]
    if lvl < 1 or lvl >= LOWER_LVL_LIMIT then return 1 end
    return 1 - (LOWER_LVL_LIMIT - lvl) * LOWER_LVL_STEP
end

local function LvlGain(e, level)
    local limit = e[MAX_LVL]
    if limit > 0 and level > limit then level = limit end
    local g = level - e[LVL]
    return g > 0 and g or 0
end

local function Amount(e, at, gain, bonus, directMod, periodicMod)
    local scaled = bonus * Penalty(e)
    local direct = (e[at + DIRECT] + e[at + DIRECT_PER_LVL] * gain + e[at + DIRECT_COEFFICIENT] * scaled)
        * directMod
    local tick = (e[at + TICK] + e[at + TICK_PER_LVL] * gain + e[at + TICK_COEFFICIENT] * scaled)
        * periodicMod
    return direct + tick * e[at + TICKS]
end

local function ManaCost(spellId)
    local costs = C_Spell.GetSpellPowerCost(spellId)
    if not PlainTable(costs) then return nil end
    for _, c in ipairs(costs) do
        if not (Plain(c.type) and Plain(c.cost)) then return nil end
        if c.type == MANA and c.cost > 0 then return c.cost end
    end
end

local function CastMs(spellId)
    local details = C_Spell.GetSpellInfo(spellId)
    if not PlainTable(details) then return nil end
    local ms = details.castTime
    if not Plain(ms) or type(ms) ~= "number" then return nil end
    return ms
end

local function Bonus(e, kind)
    if not Get("bonus") then return 0 end
    if StatsSecret() then return nil end
    local b = kind == HEAL and GetSpellBonusHealing() or GetSpellBonusDamage(e[SCHOOL])
    if not Plain(b) or type(b) ~= "number" then return nil end
    return b
end

--- { mana, castMs, area, level, count, [i] = { kind, amount, perMana, perSecond, perManaSecond } }
function module.SpellEfficiencyOf(spellId)
    local e = Entry(spellId)
    if not e then return nil end
    local mana = ManaCost(spellId)
    local castMs = mana and CastMs(spellId)
    local level = UnitLevel("player")
    if not (mana and castMs and Plain(level)) then return nil end
    local gain = LvlGain(e, level)
    local directMod, periodicMod, costMod = TalentEffects(spellId, e[SCHOOL])
    mana = mana * costMod
    local result = { mana = mana, castMs = castMs, area = e[AREA] == 1, level = e[LVL], count = 0 }
    for at = PART_START, #e, PART_SIZE do
        local kind = e[at + KIND]
        if Shows(kind) then
            local bonus = Bonus(e, kind)
            if not bonus then break end
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
local decoratedLabel = setmetatable({}, { __mode = "k" })

local function AppendLines(tooltip, spellId)
    local region = module.SpellEfficiencyOf(spellId)
    if not region then return end
    local first
    for index = 1, region.count do
        local labelValue = Line(region[index], region.area)
        if labelValue then
            if not first then
                -- The game can call the hook twice for one tooltip: add the line once.
                local at = decoratedAt[tooltip]
                if at and at <= tooltip:NumLines() and decoratedLabel[tooltip] == labelValue then
                    local leftX = _G[tooltip:GetName() .. "TextLeft" .. at]
                    local isShown = leftX and leftX:GetText()
                    if Plain(isShown) and isShown == labelValue then return end
                end
                first = labelValue
            end
            tooltip:AddLine(labelValue, TINT[1], TINT[2], TINT[3])
            if first == labelValue then
                decoratedAt[tooltip], decoratedLabel[tooltip] = tooltip:NumLines(), labelValue
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
    if Plain(a) and type(a) == "number" then return a end
    a = ownerFrame.GetAttribute and ownerFrame:GetAttribute("action")
    if Plain(a) and type(a) == "number" then return a end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, payload)
        if not Decorates(tooltip) or not PlainTable(payload) then return end
        local ident = payload.id
        if Plain(ident) and type(ident) == "number" then AppendLines(tooltip, ident) end
    end)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, function(tooltip)
        if not Decorates(tooltip) then return end
        local ownerFrame = tooltip:GetOwner()
        local action = ownerFrame and ActionSlot(ownerFrame)
        if not action then return end
        local kind, ident, subType = GetActionInfo(action)
        if kind ~= "macro" or not (Plain(ident) and type(ident) == "number") then return end
        local spellId = subType == "spell" and ident or GetMacroSpell(ident)
        if Plain(spellId) and type(spellId) == "number" then AppendLines(tooltip, spellId) end
    end)
end

CUI._SpellEfficiency = { Get = Get, Cfg = F.Cfg }

F.Start(function() end)
