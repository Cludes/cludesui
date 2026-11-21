if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIQoL_ForeverStats.lua
--  WoW Forever has none of retail's ratings, so its Secondary Stats block
--  shows the character pane's stats instead. This is that catalog, grouped as
--  the Choose Stats window lists it. Loads before CludesUIQoL.lua, which
--  reads ns.FvStats (nil on every other client) for the block's rows, their
--  default order and the default hidden set.
-------------------------------------------------------------------------------
local _, mod = ...
local floor = math.floor
-- Label hues, shared with Forever Essentials' Simplified Stats.
local HUE = CludesUI.FOREVER_STAT_HUES

-- A sum or a scale is arithmetic, which a secret refuses: those getters
-- hand back nil (drawn as "?") rather than error.
local function Sum(...)
    local sum = 0
    for index = 1, select("#", ...) do
        local val = select(index, ...)
        if issecretvalue(val) then return nil end
        sum = sum + (val or 0)
    end
    return sum
end
local function SchoolPower(index)
    return function() return GetSpellBonusDamage(index) end
end
local function Resist(index)
    return function() return (select(2, UnitResistance("player", index))) end
end

local NUM, PCT = "%.0f", "%.2f%%"

-- key, label, abbreviated label, label hue, figure format, getter, shown by default
local function StatRow(key, labelText, short, hex, fmt, get, enabled)
    return { key = key, label = labelText, short = short, hex = hex, fmt = fmt, get = get, on = enabled }
end

local GROUPS = {
    {
        title = "Offensive",
        stats = {
            StatRow(
                "ap",
                "Attack Power",
                "AP",
                HUE.ap,
                NUM,
                function() return Sum(UnitAttackPower("player")) end,
                true
            ),
            StatRow(
                "rap",
                "Ranged AP",
                "RAP",
                HUE.ap,
                NUM,
                function() return Sum(UnitRangedAttackPower("player")) end
            ),
            StatRow("mcrit", "Melee Crit", "M.Crit", HUE.crit, PCT, GetCritChance),
            StatRow("rcrit", "Ranged Crit", "R.Crit", HUE.crit, PCT, GetRangedCritChance),
            StatRow("mhaste", "Melee Haste", "M.Haste", HUE.haste, PCT, GetMeleeHaste),
            -- Base and ammo haste, as the character pane adds them.
            StatRow(
                "rhaste",
                "Ranged Haste",
                "R.Haste",
                HUE.haste,
                PCT,
                function() return Sum(GetRangedHaste()) end
            ),
            StatRow("mhit", "Melee Hit", "Hit", HUE.hit, PCT, GetHitModifier),
            -- Off-hand hit, as the character pane shows it ("?" on a client
            -- without the getter).
            StatRow("ohit", "Off-hand Hit", "OH Hit", HUE.hit, PCT, function()
                if GetOffhandHitModifier then return GetOffhandHitModifier() end
            end),
        },
    },
    {
        title = "Spell",
        stats = {
            -- The highest school's bonus, so school-specific gear counts.
            StatRow("sp", "Spell Power", "SP", HUE.sp, NUM, function()
                local best = 0
                for index = 2, 7 do
                    local val = GetSpellBonusDamage(index)
                    if issecretvalue(val) then return nil end
                    if val > best then best = val end
                end
                return best
            end),
            StatRow("healing", "Healing Power", "Heal", HUE.healing, NUM, GetSpellBonusHealing),
            StatRow("scrit", "Spell Crit", "S.Crit", HUE.crit, PCT, GetSpellCritChance),
            StatRow(
                "shaste",
                "Spell Haste",
                "S.Haste",
                HUE.haste,
                PCT,
                function() return UnitSpellHaste("player") end
            ),
            StatRow("shit", "Spell Hit", "S.Hit", HUE.hit, PCT, GetSpellHitModifier),
            StatRow("spen", "Spell Pen", "S.Pen", HUE.spen, NUM, GetSpellPenetration),
        },
    },
    {
        title = "Spell Power / School",
        stats = {
            StatRow("sp_holy", "Holy SP", "Holy", HUE.holy, NUM, SchoolPower(2)),
            StatRow("sp_fire", "Fire SP", "Fire", HUE.fire, NUM, SchoolPower(3)),
            StatRow("sp_frost", "Frost SP", "Frost", HUE.frost, NUM, SchoolPower(5)),
            StatRow("sp_nature", "Nature SP", "Nature", HUE.nature, NUM, SchoolPower(4)),
            StatRow("sp_shadow", "Shadow SP", "Shadow", HUE.shadow, NUM, SchoolPower(6)),
            StatRow("sp_arcane", "Arcane SP", "Arcane", HUE.arcane, NUM, SchoolPower(7)),
        },
    },
    {
        title = "Defensive",
        stats = {
            StatRow(
                "armor",
                "Armor",
                "Armor",
                HUE.armor,
                NUM,
                function() return (select(2, UnitArmor("player"))) end
            ),
            StatRow(
                "defense",
                "Defense",
                "Def",
                HUE.armor,
                NUM,
                function() return Sum(UnitDefenseSkill("player")) end
            ),
            StatRow("dodge", "Dodge", "Dodge", HUE.avoid, PCT, GetDodgeChance),
            StatRow("parry", "Parry", "Parry", HUE.avoid, PCT, GetParryChance),
            StatRow("block", "Block", "Block", HUE.avoid, PCT, GetBlockChance),
            StatRow("blockval", "Block Value", "Blk V", HUE.avoid, NUM, GetShieldBlock),
        },
    },
    -- No Holy: resistance index 1 is no player stat (always 0, not on the pane).
    {
        title = "Resistances",
        stats = {
            StatRow("res_fire", "Fire Resist", "Fire R", HUE.fire, NUM, Resist(2)),
            StatRow("res_frost", "Frost Resist", "Frost R", HUE.frost, NUM, Resist(4)),
            StatRow("res_nature", "Nature Resist", "Nat R", HUE.nature, NUM, Resist(3)),
            StatRow("res_shadow", "Shadow Resist", "Shad R", HUE.shadow, NUM, Resist(5)),
            StatRow("res_arcane", "Arcane Resist", "Arc R", HUE.arcane, NUM, Resist(6)),
        },
    },
    {
        title = "Regen & Utility",
        stats = {
            StatRow("mp5", "Mana Regen", "MP5", HUE.mp5, NUM, function()
                local regen = GetManaRegen()
                if issecretvalue(regen) then return nil end
                return floor(regen * 5)
            end, true),
            StatRow("hp5", "Health Regen", "HP5", HUE.hp5, NUM, function()
                local regen = GetHealthRegen()
                if issecretvalue(regen) then return nil end
                return floor(regen * 5)
            end, true),
            -- Run speed against the base 7 yards a second.
            StatRow("movespeed", "Movement Speed", "MS", HUE.speed, "%.0f%%", function()
                local run = select(2, GetUnitSpeed("player"))
                if issecretvalue(run) then return nil end
                return floor(run / 7 * 100 + 0.5)
            end, true),
        },
    },
}

-- order: every key, group by group (the block's default order). hidden: the
-- profile default for secondaryStatsHidden, every stat not shown by default.
local byKey, sequence, hidden = {}, {}, {}
for _, group in ipairs(GROUPS) do
    for _, s in ipairs(group.stats) do
        byKey[s.key] = s
        sequence[#sequence + 1] = s.key
        if not s.on then hidden[s.key] = true end
    end
end

mod.FvStats = { groups = GROUPS, byKey = byKey, order = sequence, hidden = hidden }
