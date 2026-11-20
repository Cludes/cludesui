if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_StatWeights.lua  (WoW Forever only)
--  Stat Weights: what each stat is worth to your spec, and so how much
--  stronger an item makes you over what you wear.
--    Upgrades on Tooltips  "+9% upgrade (Fire)" on gear that is an upgrade for
--                          your spec. A ring or trinket is weighed against the
--                          weaker of the two you wear, a two-hander against both
--                          hands. Nothing on gear that is not an upgrade.
--    Best in Slot          the BiS window shows each pick's gain.
--  Your spec is Automatic (the talent tree with the most points) or one you
--  pick. Your own changes to a weight are kept per spec, for the account.
--
--  The percent is the item's weighted stats minus what you wear there, over
--  what your stats are worth now. An estimate: it orders upgrades, it does
--  not promise a number on a meter.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("statWeights", { enabled = false, spec = "" })
local Get = F.Get

local SAME = 1e-9
local MIN_GAIN = 0.5
local CACHE_MAX = 600
local SPEED = 2.6
local MAIN_HAND, OFF_HAND = 16, 17

local STATS = {
    { "str", "Strength", 3 },
    { "agi", "Agility", 3 },
    { "sta", "Stamina", 3 },
    { "int", "Intellect", 3 },
    { "spi", "Spirit", 3 },
    { "ap", "Attack Power", 3 },
    { "rap", "Ranged Attack Power", 3 },
    { "dps", "Weapon DPS", 20 },
    { "hit", "Hit %", 30 },
    { "crit", "Crit %", 30 },
    { "haste", "Haste %", 30 },
    { "spell", "Spell Damage", 3 },
    { "heal", "Healing", 3 },
    { "shit", "Spell Hit %", 30 },
    { "scrit", "Spell Crit %", 30 },
    { "mp5", "Mana every 5 sec", 5 },
    { "fire", "Fire Damage", 3 },
    { "frost", "Frost Damage", 3 },
    { "shadow", "Shadow Damage", 3 },
    { "nature", "Nature Damage", 3 },
    { "arcane", "Arcane Damage", 3 },
    { "holy", "Holy Damage", 3 },
    { "def", "Defense", 5 },
    { "dodge", "Dodge %", 30 },
    { "block", "Block %", 30 },
    { "armor", "Armor", 0.2 },
    { "threat", "Threat %", 30 },
}
local GAME_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "str",
    ITEM_MOD_AGILITY_SHORT = "agi",
    ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int",
    ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_ATTACK_POWER_SHORT = "ap",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "spell",
    ITEM_MOD_SPELL_POWER_SHORT = { "spell", "heal" },
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
    ITEM_MOD_HIT_RATING_SHORT = { "hit", "shit" },
    ITEM_MOD_CRIT_RATING_SHORT = { "crit", "scrit" },
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "shit",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "scrit",
    ITEM_MOD_SPELL_CRIT_RATING_SHORT = "scrit",
    ITEM_MOD_MANA_REGENERATION_SHORT = "mp5",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def",
    ITEM_MOD_DODGE_RATING_SHORT = "dodge",
    ITEM_MOD_BLOCK_RATING_SHORT = "block",
    ITEM_MOD_HASTE_RATING_SHORT = "haste",
    RESISTANCE0_NAME = "armor",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
}
-- Rating points per 1% at level 60, as the game's tooltips read them.
local PER_PERCENT = {
    ITEM_MOD_HIT_RATING_SHORT = 10,
    ITEM_MOD_HIT_SPELL_RATING_SHORT = 10,
    ITEM_MOD_CRIT_RATING_SHORT = 14,
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14,
    ITEM_MOD_SPELL_CRIT_RATING_SHORT = 14,
    ITEM_MOD_DODGE_RATING_SHORT = 12,
    ITEM_MOD_BLOCK_RATING_SHORT = 5,
    ITEM_MOD_HASTE_RATING_SHORT = 10,
}
local TREES = {
    DRUID = { "balance-druid", "feral-dps-druid", "restoration-druid" },
    HUNTER = { "beast-mastery-hunter", "marksmanship-hunter", "survival-hunter" },
    MAGE = { "arcane-mage", "fire-mage", "frost-mage" },
    PALADIN = { "holy-paladin", "protection-paladin", "retribution-paladin" },
    PRIEST = { "discipline-priest", "holy-priest", "shadow-priest" },
    ROGUE = { "assassination-rogue", "combat-rogue", "subtlety-rogue" },
    SHAMAN = { "elemental-shaman", "enhancement-shaman", "restoration-shaman" },
    WARLOCK = { "affliction-warlock", "demonology-warlock", "destruction-warlock" },
    WARRIOR = { "arms-warrior", "fury-warrior", "protection-warrior" },
}
local PRIMARY = { "str", "agi", "sta", "int", "spi" }
local PRIMARY_KEY = { str = true, agi = true, sta = true, int = true, spi = true }
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local DPS_SHARE = { [16] = 1, [17] = 0.5 }
local HUNTER_DPS_SHARE = { [18] = 1 }

local _, CLASS = UnitClass("player")
local STAT_KEY, STAT_NAME = {}, {}
for _, s in ipairs(STATS) do
    STAT_KEY[s[1]], STAT_NAME[s[1]] = true, s[2]
end

local function Secret(val)
    return issecretvalue and issecretvalue(val)
end
local function StatsSecret()
    return C_Secrets and C_Secrets.ShouldUnitStatsBeSecret and C_Secrets.ShouldUnitStatsBeSecret()
end

-------------------------------------------------------------------------------
--  Specs and weights
-------------------------------------------------------------------------------
local byKey, classSpecs
local function Index()
    byKey, classSpecs = {}, {}
    for _, specInfo in ipairs(module.StatWeightDefaults or {}) do
        byKey[specInfo.key] = specInfo
        if specInfo.class == CLASS then
            classSpecs[#classSpecs + 1] = specInfo
        end
    end
end

local function Spec(key)
    if not byKey then
        Index()
    end
    return byKey[key]
end
local function ClassSpecs()
    if not classSpecs then
        Index()
    end
    return classSpecs
end

-- Forever keeps one spec per class, its three classic trees as the talent
-- tree's groups; the tree with the most points spent is the spec.
local talentSpec, talentRead
local function ReadTalents()
    local trees = TREES[CLASS]
    local configID = trees
        and C_ClassTalents
        and C_ClassTalents.GetActiveConfigID
        and C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then
        return nil
    end
    local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}
    local ids, spent = {}, {}
    for index, group in ipairs(groups) do
        ids[index] = group.groupID
    end
    for _, details in ipairs(C_Traits.GetGroupCurrencyInfo(configID, ids) or {}) do
        local c = details.currencyInfos and details.currencyInfos[1]
        spent[details.traitNodeGroupID] = c and c.spent or 0
    end
    local best, most = nil, 0
    for index, group in ipairs(groups) do
        local num = spent[group.groupID] or 0
        if num > most then
            best, most = trees[index], num
        end
    end
    return best
end

local talentEv = CreateFrame("Frame")
talentEv:RegisterEvent("TRAIT_CONFIG_UPDATED")
talentEv:SetScript("OnEvent", function()
    talentRead = false
end)

local function TalentSpec()
    if not talentRead then
        local success, specInfo = pcall(ReadTalents)
        talentSpec, talentRead = success and specInfo or nil, true
    end
    return talentSpec
end

--- The spec weighed by: the one picked, else your talents', else the class's first.
local function ActiveSpec()
    local picked = Get("spec")
    for _, spec in ipairs(ClassSpecs()) do
        if spec.key == picked then
            return picked
        end
    end
    local t = TalentSpec()
    if t and Spec(t) then
        return t
    end
    local first = ClassSpecs()[1]
    return first and first.key
end

local merged = {}
local function Changes(create)
    local c = F.Cfg()
    if create and type(c.changes) ~= "table" then
        c.changes = {}
    end
    return c.changes
end

local function For(key)
    if not key then
        return nil
    end
    if merged[key] then
        return merged[key]
    end
    local specInfo = Spec(key)
    if not specInfo then
        return nil
    end
    local wid = {}
    for stat, val in pairs(specInfo.weights) do
        wid[stat] = val
    end
    local ch = Changes()
    for stat, val in pairs(ch and ch[key] or {}) do
        if STAT_KEY[stat] and type(val) == "number" then
            wid[stat] = val
        end
    end
    merged[key] = wid
    return wid
end

local function Default(key, stat)
    local s = Spec(key)
    return s and s.weights[stat] or 0
end

local function Set(key, stat, val)
    if not (Spec(key) and STAT_KEY[stat]) then
        return
    end
    local ch = Changes(true)
    if val ~= nil and math.abs(val - Default(key, stat)) < SAME then
        val = nil
    end
    ch[key] = ch[key] or {}
    ch[key][stat] = val
    if next(ch[key]) == nil then
        ch[key] = nil
    end
    merged[key] = nil
end

local function Reset(key)
    local ch = Changes()
    if ch then
        ch[key] = nil
    end
    merged[key] = nil
end

-------------------------------------------------------------------------------
--  Worth
-------------------------------------------------------------------------------
local statsOf, cached = {}, 0
local lastPower = setmetatable({}, { __mode = "k" })
local lastMain, lastOff

local forget = CreateFrame("Frame")
forget:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
forget:RegisterEvent("PLAYER_LEVEL_UP")
forget:SetScript("OnEvent", function()
    wipe(lastPower)
    lastMain, lastOff = nil, nil
end)

local function Stats(entry)
    local s = statsOf[entry]
    if s then
        return s
    end
    if type(entry) == "number" and not C_Item.IsItemDataCachedByID(entry) then
        return nil
    end
    s = C_Item.GetItemStats(type(entry) == "number" and ("item:" .. entry) or entry) or {}
    if cached >= CACHE_MAX then
        wipe(statsOf)
        cached = 0
    end
    statsOf[entry], cached = s, cached + 1
    return s
end

local function DpsShare(slot)
    return ((CLASS == "HUNTER") and HUNTER_DPS_SHARE or DPS_SHARE)[slot] or 0
end

local function Worth(stats, weights, dpsShare, skipPrimary)
    local worth = 0
    for key, value in pairs(stats) do
        local mine = GAME_KEYS[key]
        local per = PER_PERCENT[key]
        if per then
            value = value / per
        end
        if type(mine) == "table" then
            for index = 1, #mine do
                worth = worth + (weights[mine[index]] or 0) * value
            end
        elseif mine == "dps" then
            worth = worth + (weights.dps or 0) * value * (dpsShare or 0)
        elseif mine and not (skipPrimary and PRIMARY_KEY[mine]) then
            worth = worth + (weights[mine] or 0) * value
        end
    end
    return worth
end

local function WornWorth(slot, weights)
    local itemLink = GetInventoryItemLink("player", slot)
    if not itemLink then
        return 0
    end
    local worn = Stats(itemLink)
    return worn and Worth(worn, weights, DpsShare(slot))
end

--- What your stats are worth now: the five stats as the game sums them, the
--- rest from your gear. While the game keeps stats secret, the last reading.
local function Power(weights)
    if StatsSecret() then
        return lastPower[weights]
    end
    local power = 0
    for index, key in ipairs(PRIMARY) do
        local _, effective = UnitStat("player", index)
        if type(effective) == "number" and not Secret(effective) then
            power = power + (weights[key] or 0) * effective
        end
    end
    for _, slot in ipairs(GEAR_SLOTS) do
        local itemLink = GetInventoryItemLink("player", slot)
        local s = itemLink and Stats(itemLink)
        if s then
            power = power + Worth(s, weights, DpsShare(slot), true)
        end
    end
    lastPower[weights] = power
    return power
end

local function Gain(entry, slot, weights, power, also)
    if not (weights and power and power > 0) then
        return nil
    end
    local s = Stats(entry)
    local worn = WornWorth(slot, weights)
    local other = also and WornWorth(also, weights) or 0
    if not (s and worn and other) then
        return nil
    end
    return 100 * (Worth(s, weights, DpsShare(slot)) - worn - other) / power
end

local function Wearing(ident, slots)
    for _, slot in ipairs(slots) do
        if GetInventoryItemID("player", slot) == ident then
            return true
        end
    end
    return false
end

--- The best gain over the slots an item can go in, or nil (not gear, worn,
--- unusable, or under half a percent).
function module.BestGain(ident, itemLink, weights, power)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(ident)
    local slots = module.BIS_EQUIP_SLOTS and module.BIS_EQUIP_SLOTS[equipLoc or ""]
    if not (slots and weights) or Wearing(ident, slots) then
        return nil
    end
    if C_PlayerInfo and C_PlayerInfo.CanUseItem and not C_PlayerInfo.CanUseItem(ident) then
        return nil
    end
    local twoHand = equipLoc == "INVTYPE_2HWEAPON"
    local best
    for _, slot in ipairs(slots) do
        local g =
            Gain(itemLink or ident, slot, weights, power, twoHand and slot == MAIN_HAND and OFF_HAND or nil)
        if g and (not best or g > best) then
            best = g
        end
    end
    return best and best >= MIN_GAIN and best or nil
end

--- The active spec's gain for an item, for other modules (the BiS window).
function module.ItemGain(ident, itemLink)
    if not Get("enabled") then
        return nil
    end
    local key = ActiveSpec()
    local wid = For(key)
    return wid and module.BestGain(ident, itemLink, wid, Power(wid)), key and Spec(key) and Spec(key).name
end

-------------------------------------------------------------------------------
--  Tooltip
-------------------------------------------------------------------------------
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, payload)
        if not Get("enabled") or (tooltip.IsForbidden and tooltip:IsForbidden()) then
            return
        end
        local ident = payload and payload.id
        if type(ident) ~= "number" or Secret(ident) then
            return
        end
        local itemLink = tooltip.GetItem and select(2, tooltip:GetItem())
        if itemLink and Secret(itemLink) then
            itemLink = nil
        end
        local gain, specName = module.ItemGain(ident, itemLink)
        if gain then
            tooltip:AddLine(("|cff60d080+%.1f%% upgrade|r |cff9aa6b2(%s)|r"):format(gain, specName or ""))
        end
    end)
end

CludesUI._StatWeights = {
    Get = Get,
    Cfg = F.Cfg,
    Specs = ClassSpecs,
    Spec = Spec,
    ActiveSpec = ActiveSpec,
    TalentSpec = TalentSpec,
    For = For,
    Set = Set,
    Reset = Reset,
    Default = Default,
    Stats = STATS,
}

F.Start(function() end)
