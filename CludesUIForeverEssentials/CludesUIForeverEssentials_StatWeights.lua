if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
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
local LEAST_GAIN = 0.5
local CACHE_TOP = 600
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
local PRIMARY_ID = { str = true, agi = true, sta = true, int = true, spi = true }
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local DPS_SHARE = { [16] = 1, [17] = 0.5 }
local HUNTER_DPS_SHARE = { [18] = 1 }

local _, CALLING = UnitClass("player")
local STAT_ID, STAT_TITLE = {}, {}
for _, s in ipairs(STATS) do
    STAT_ID[s[1]], STAT_TITLE[s[1]] = true, s[2]
end

local function Secret(val) return issecretvalue and issecretvalue(val) end
local function StatsSecret()
    return C_Secrets and C_Secrets.ShouldUnitStatsBeSecret and C_Secrets.ShouldUnitStatsBeSecret()
end

-------------------------------------------------------------------------------
--  Specs and weights
-------------------------------------------------------------------------------
local byId, callingSpecs
local function Catalog()
    byId, callingSpecs = {}, {}
    for _, specInfo in ipairs(module.StatWeightDefaults or {}) do
        byId[specInfo.key] = specInfo
        if specInfo.class == CALLING then callingSpecs[#callingSpecs + 1] = specInfo end
    end
end

local function Spec(key)
    if not byId then Catalog() end
    return byId[key]
end
local function CallingSpecs()
    if not callingSpecs then Catalog() end
    return callingSpecs
end

-- Forever keeps one spec per class, its three classic trees as the talent
-- tree's groups; the tree with the most points spent is the spec.
local talentSpec, talentLoad
local function LoadTalents()
    local trees = TREES[CALLING]
    local configID = trees
        and C_ClassTalents
        and C_ClassTalents.GetActiveConfigID
        and C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil end
    local sets = C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}
    local ids, spent = {}, {}
    for catalog, group in ipairs(sets) do
        ids[catalog] = group.groupID
    end
    for _, details in ipairs(C_Traits.GetGroupCurrencyInfo(configID, ids) or {}) do
        local c = details.currencyInfos and details.currencyInfos[1]
        spent[details.traitNodeGroupID] = c and c.spent or 0
    end
    local top, most = nil, 0
    for catalog, group in ipairs(sets) do
        local num = spent[group.groupID] or 0
        if num > most then
            top, most = trees[catalog], num
        end
    end
    return top
end

local talentEv = CreateFrame("Frame")
talentEv:RegisterEvent("TRAIT_CONFIG_UPDATED")
talentEv:SetScript("OnEvent", function() talentLoad = false end)

local function TalentSpec()
    if not talentLoad then
        local success, specInfo = pcall(LoadTalents)
        talentSpec, talentLoad = success and specInfo or nil, true
    end
    return talentSpec
end

--- The spec weighed by: the one picked, else your talents', else the class's first.
local function ActiveSpec()
    local chosen = Get("spec")
    for _, spec in ipairs(CallingSpecs()) do
        if spec.key == chosen then return chosen end
    end
    local t = TalentSpec()
    if t and Spec(t) then return t end
    local first = CallingSpecs()[1]
    return first and first.key
end

local merged = {}
local function Changes(create)
    local cfg = F.Cfg()
    if create and type(cfg.changes) ~= "table" then cfg.changes = {} end
    return cfg.changes
end

local function For(key)
    if not key then return nil end
    if merged[key] then return merged[key] end
    local specInfo = Spec(key)
    if not specInfo then return nil end
    local wid = {}
    for stat, val in pairs(specInfo.weights) do
        wid[stat] = val
    end
    local ch = Changes()
    for stat, val in pairs(ch and ch[key] or {}) do
        if STAT_ID[stat] and type(val) == "number" then wid[stat] = val end
    end
    merged[key] = wid
    return wid
end

local function Default(key, stat)
    local cfg = Spec(key)
    return cfg and cfg.weights[stat] or 0
end

local function Assign(key, stat, val)
    if not (Spec(key) and STAT_ID[stat]) then return end
    local ch = Changes(true)
    if val ~= nil and math.abs(val - Default(key, stat)) < SAME then val = nil end
    ch[key] = ch[key] or {}
    ch[key][stat] = val
    if next(ch[key]) == nil then ch[key] = nil end
    merged[key] = nil
end

local function Restart(key)
    local ch = Changes()
    if ch then ch[key] = nil end
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
    if s then return s end
    if type(entry) == "number" and not C_Item.IsItemDataCachedByID(entry) then return nil end
    s = C_Item.GetItemStats(type(entry) == "number" and ("item:" .. entry) or entry) or {}
    if cached >= CACHE_TOP then
        wipe(statsOf)
        cached = 0
    end
    statsOf[entry], cached = s, cached + 1
    return s
end

local function DpsShare(slot) return ((CALLING == "HUNTER") and HUNTER_DPS_SHARE or DPS_SHARE)[slot] or 0 end

local function Worth(stats, weights, dpsShare, skipPrimary)
    local worth = 0
    for key, value in pairs(stats) do
        local mine = GAME_KEYS[key]
        local per = PER_PERCENT[key]
        if per then value = value / per end
        if type(mine) == "table" then
            for catalog = 1, #mine do
                worth = worth + (weights[mine[catalog]] or 0) * value
            end
        elseif mine == "dps" then
            worth = worth + (weights.dps or 0) * value * (dpsShare or 0)
        elseif mine and not (skipPrimary and PRIMARY_ID[mine]) then
            worth = worth + (weights[mine] or 0) * value
        end
    end
    return worth
end

local function WornWorth(slot, weights)
    local thingChain = GetInventoryItemLink("player", slot)
    if not thingChain then return 0 end
    local worn = Stats(thingChain)
    return worn and Worth(worn, weights, DpsShare(slot))
end

--- What your stats are worth now: the five stats as the game sums them, the
--- rest from your gear. While the game keeps stats secret, the last reading.
local function Power(weights)
    if StatsSecret() then return lastPower[weights] end
    local power = 0
    for catalog, key in ipairs(PRIMARY) do
        local _, effective = UnitStat("player", catalog)
        if type(effective) == "number" and not Secret(effective) then
            power = power + (weights[key] or 0) * effective
        end
    end
    for _, slot in ipairs(GEAR_SLOTS) do
        local thingChain = GetInventoryItemLink("player", slot)
        local s = thingChain and Stats(thingChain)
        if s then power = power + Worth(s, weights, DpsShare(slot), true) end
    end
    lastPower[weights] = power
    return power
end

local function Gain(entry, slot, weights, power, also)
    if not (weights and power and power > 0) then return nil end
    local s = Stats(entry)
    local worn = WornWorth(slot, weights)
    local other = also and WornWorth(also, weights) or 0
    if not (s and worn and other) then return nil end
    return 100 * (Worth(s, weights, DpsShare(slot)) - worn - other) / power
end

local function Wearing(ident, slots)
    for _, slot in ipairs(slots) do
        if GetInventoryItemID("player", slot) == ident then return true end
    end
    return false
end

--- The best gain over the slots an item can go in, or nil (not gear, worn,
--- unusable, or under half a percent).
function module.BestGain(ident, thingChain, weights, power)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(ident)
    local slots = module.BIS_EQUIP_SLOTS and module.BIS_EQUIP_SLOTS[equipLoc or ""]
    if not (slots and weights) or Wearing(ident, slots) then return nil end
    if C_PlayerInfo and C_PlayerInfo.CanUseItem and not C_PlayerInfo.CanUseItem(ident) then return nil end
    local twoHand = equipLoc == "INVTYPE_2HWEAPON"
    local top
    for _, slot in ipairs(slots) do
        local g =
            Gain(thingChain or ident, slot, weights, power, twoHand and slot == MAIN_HAND and OFF_HAND or nil)
        if g and (not top or g > top) then top = g end
    end
    return top and top >= LEAST_GAIN and top or nil
end

--- The active spec's gain for an item, for other modules (the BiS window).
function module.ItemGain(ident, thingChain)
    if not Get("enabled") then return nil end
    local key = ActiveSpec()
    local wid = For(key)
    return wid and module.BestGain(ident, thingChain, wid, Power(wid)), key and Spec(key) and Spec(key).name
end

-------------------------------------------------------------------------------
--  Tooltip
-------------------------------------------------------------------------------
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, payload)
        if not Get("enabled") or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
        local ident = payload and payload.id
        if type(ident) ~= "number" or Secret(ident) then return end
        local thingChain = tooltip.GetItem and select(2, tooltip:GetItem())
        if thingChain and Secret(thingChain) then thingChain = nil end
        local gain, specTitle = module.ItemGain(ident, thingChain)
        if gain then
            tooltip:AddLine(("|cff60d080+%.1f%% upgrade|r |cff9aa6b2(%s)|r"):format(gain, specTitle or ""))
        end
    end)
end

CUI._StatWeights = {
    Get = Get,
    Cfg = F.Cfg,
    Specs = CallingSpecs,
    Spec = Spec,
    ActiveSpec = ActiveSpec,
    TalentSpec = TalentSpec,
    For = For,
    Set = Assign,
    Reset = Restart,
    Default = Default,
    Stats = STATS,
}

F.Start(function() end)
