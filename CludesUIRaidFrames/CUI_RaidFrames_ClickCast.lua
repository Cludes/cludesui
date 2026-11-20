if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_ClickCast.lua
--  Click-casting: per-spec bindings + global target/menu/macro defaults.
--  Two paths: (1) Frame-based -- WrapScript OnEnter/OnLeave sets keyboard
--  bindings via SetBindingClick; clicks use direct attribute setting.
--  (2) Hovercast -- persistent bindings on a dedicated secure button
--  targeting @mouseover, friend/harm filtered via macro conditionals.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot.
local POOL = CludesUI._Pool

local pairs = pairs
local ipairs = ipairs
local tinsert = table.insert
local tremove = table.remove
local wipe = wipe
local format = string.format
local tostring = tostring
local type = type
local floor = math.floor
local max = math.max
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsInInstance = IsInInstance
local IsShiftKeyDown = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown = IsAltKeyDown
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_Timer = C_Timer
local GetMacroInfo = GetMacroInfo
local GetMacroBody = GetMacroBody
local GetMacroIndexByName = GetMacroIndexByName
local GetNumMacros = GetNumMacros
local MAX_ACCOUNT_MACROS = Constants.MacroConsts.MAX_ACCOUNT_MACROS

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local MODIFIER_KEYS = {
    LSHIFT = true,
    RSHIFT = true,
    LCTRL = true,
    RCTRL = true,
    LALT = true,
    RALT = true,
    LMETA = true,
    RMETA = true,
}

local MOUSE_BUTTON_MAP = {
    LeftButton = "BUTTON1",
    RightButton = "BUTTON2",
    MiddleButton = "BUTTON3",
    Button4 = "BUTTON4",
    Button5 = "BUTTON5",
}

local ACTION_ICONS = {
    target = 132212,
    menu = 5341597,
    macro = 134400,
    dispel = 135894, -- Dispel Magic icon
    external = 135966, -- Blessing of Sacrifice icon
}

-- Dispel spells by class (friendly dispels only). One entry per spec that has a
-- distinct spell; ClassPresetSpells drops the ones this character has not got
-- before they reach the macro.
local DISPEL_SPELLS = {
    { id = 527, name = "Purify", class = "PRIEST" }, -- Disc & Holy
    { id = 213634, name = "Purify Disease", class = "PRIEST" }, -- Shadow
    { id = 115450, name = "Detox", class = "MONK" }, -- Mistweaver
    { id = 218164, name = "Detox", class = "MONK" }, -- Brewmaster & Windwalker
    { id = 4987, name = "Cleanse", class = "PALADIN" }, -- Holy
    { id = 213644, name = "Cleanse Toxins", class = "PALADIN" }, -- Prot & Ret (Cleanse is Holy-only)
    { id = 88423, name = "Nature's Cure", class = "DRUID" }, -- Resto
    { id = 2782, name = "Remove Corruption", class = "DRUID" }, -- Guardian, Feral & Balance
    { id = 77130, name = "Purify Spirit", class = "SHAMAN" }, -- Resto
    { id = 51886, name = "Cleanse Spirit", class = "SHAMAN" }, -- Ele & Enh
    { id = 360823, name = "Naturalize", class = "EVOKER" }, -- Pres
    { id = 365585, name = "Expunge", class = "EVOKER" }, -- Aug & Dev
    { id = 89808, name = "Singe Magic", class = "WARLOCK", pet = true }, -- Imp
    { id = 475, name = "Remove Curse", class = "MAGE" }, -- All specs (Curse only)
}

-- External defensive spells by class
local EXTERNAL_SPELLS = {
    { id = 33206, name = "Pain Suppression", class = "PRIEST" }, -- Disc
    { id = 47788, name = "Guardian Spirit", class = "PRIEST" }, -- Holy
    { id = 102342, name = "Ironbark", class = "DRUID" }, -- Resto
    { id = 6940, name = "Blessing of Sacrifice", class = "PALADIN" },
    { id = 357170, name = "Time Dilation", class = "EVOKER" }, -- Pres
    { id = 116849, name = "Life Cocoon", class = "MONK" }, -- Mistweaver
}

-- This class's preset entries, narrowed to what the character can cast. A /cast
-- line naming a spell they have not got matches its condition and then casts
-- nothing, eating the fallback the next line was there to be, so an unavailable
-- entry has to be dropped rather than ordered last. Empty falls back to the
-- unfiltered list: the book can lag the first apply at login, so "nothing
-- available" is as likely stale as true, and an all-unknown list shadows
-- nothing anyway. Singe Magic is exempt -- the pet book holds only the
-- summoned demon's spells.
local function ClassPresetSpells(spellList, class)
    local spellBank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local canCheck = C_SpellBook.IsSpellInSpellBook and spellBank
    local usable, all = {}, {}
    for _, spellRec in ipairs(spellList) do
        if spellRec.class == class then
            all[#all + 1] = spellRec
            if spellRec.pet or not canCheck or C_SpellBook.IsSpellInSpellBook(spellRec.id, spellBank, true) then
                usable[#usable + 1] = spellRec
            end
        end
    end
    return #usable > 0 and usable or all
end

-- The dispels the Dispels key casts: this class's preset entries, and on WoW
-- Forever only the first of them (see the Forever list below). The list is a
-- fresh table per call, so it is cut in place.
local function DispelPresetSpells(class)
    local entries = ClassPresetSpells(DISPEL_SPELLS, class)
    if CludesUI.IS_FOREVER then
        for i = #entries, 2, -1 do
            entries[i] = nil
        end
    end
    return entries
end

-- Resurrection spells by class: single (ooc), group (ooc), battle (combat)
local REZ_BY_CLASS = {
    PRIEST = { single = 2006, group = 212036 },
    PALADIN = { single = 7328, group = 212056, battle = 391054 },
    SHAMAN = { single = 2008, group = 212048 },
    DRUID = { single = 50769, group = 212040, battle = 20484 },
    MONK = { single = 115178, group = 212051 },
    EVOKER = { single = 361227, group = 361178 },
    DEATHKNIGHT = { battle = 61999 },
    WARLOCK = { battle = 20707 },
}

-- Combat rez items, best first: a class with no battle rez falls back to the
-- first one carried (Dynamic Rez and Smart Rez). Emergency Soul Link, both
-- crafted ranks (the higher one casts faster).
local REZ_ITEMS = { 269586, 248486 }

-- WoW Forever: the vanilla spells. An entry's alts are its higher ranks and a
-- rez slot lists every rank ID, rank 1 first; /cast by name casts the highest
-- rank the character knows. Each class's dispels are in priority order and the
-- Dispels key casts only the first one the character knows (DispelPresetSpells):
-- a dispel casts even with nothing to remove and starts the GCD, so a later line
-- could never fire (the others can be bound as spell bindings). Paladin is the
-- only class with an external, and there is no group rez, no Warlock entry and
-- no combat rez item.
if CludesUI.IS_FOREVER then
    DISPEL_SPELLS = {
        { id = 527, name = "Dispel Magic", class = "PRIEST", alts = { 988 } },
        { id = 552, name = "Abolish Disease", class = "PRIEST" },
        { id = 528, name = "Cure Disease", class = "PRIEST" }, -- before Dispel Magic is learned
        { id = 4987, name = "Cleanse", class = "PALADIN" },
        { id = 1152, name = "Purify", class = "PALADIN" }, -- before Cleanse is learned
        { id = 2782, name = "Remove Curse", class = "DRUID" },
        { id = 2893, name = "Abolish Poison", class = "DRUID" },
        { id = 8946, name = "Cure Poison", class = "DRUID" }, -- before Remove Curse is learned
        { id = 526, name = "Cure Poison", class = "SHAMAN" },
        { id = 2870, name = "Cure Disease", class = "SHAMAN" },
        { id = 475, name = "Remove Lesser Curse", class = "MAGE" },
        {
            id = 19505,
            name = "Devour Magic",
            class = "WARLOCK",
            pet = true,
            alts = { 19731, 19734, 19736 },
        }, -- Felhunter
    }
    EXTERNAL_SPELLS = {
        { id = 6940, name = "Blessing of Sacrifice", class = "PALADIN", alts = { 20729 } },
        { id = 1022, name = "Blessing of Protection", class = "PALADIN", alts = { 5599, 10278 } },
    }
    REZ_BY_CLASS = {
        PRIEST = { single = { 2006, 2010, 10880, 10881, 20770 } },
        PALADIN = { single = { 7328, 10322, 10324, 20772, 20773 } },
        SHAMAN = { single = { 2008, 20609, 20610, 20776, 20777 } },
        DRUID = {
            single = { 437138, 1237948, 1237949, 1237950, 1237951 }, -- Revive
            battle = { 20484, 20739, 20742, 20747, 20748 },
        },
    }
    REZ_ITEMS = {}
end

-- Every rez spell ID across all classes; exempt from the exists/nodead corpse
-- filter in macro building (corpses are a rez's only valid target). A kit slot
-- holds one spell ID or a list of rank IDs.
local REZ_SPELL_IDS = {}
for _, rezKit in pairs(REZ_BY_CLASS) do
    for _, slot in pairs(rezKit) do
        if type(slot) == "table" then
            for _, spellRef in ipairs(slot) do
                REZ_SPELL_IDS[spellRef] = true
            end
        else
            REZ_SPELL_IDS[slot] = true
        end
    end
end

-- Union of every dispel/external/rez spell ID, alternate ranks included
-- (exposed as ns.CC_PRESET_SPELL_IDS)
local PRESET_SPELL_IDS = {}
for _, entries in ipairs({ DISPEL_SPELLS, EXTERNAL_SPELLS }) do
    for _, s in ipairs(entries) do
        PRESET_SPELL_IDS[s.id] = true
        if s.alts then
            for _, alt in ipairs(s.alts) do
                PRESET_SPELL_IDS[alt] = true
            end
        end
    end
end
for spellRef in pairs(REZ_SPELL_IDS) do
    PRESET_SPELL_IDS[spellRef] = true
end
mod.CC_PRESET_SPELL_IDS = PRESET_SPELL_IDS

-- True when a binding is a rez spell (by stored ID, with a name fallback for
-- legacy bindings saved before IDs were stored). Fallback name lookup is cached
-- ONCE: per-binding/per-frame GetSpellName calls during the login enable-flush
-- multiply into thousands (40+ frames x many bindings), and the enable-flush is
-- a SINGLE synchronous execution shared by every module, so this can trip the
-- "script ran too long" watchdog on /reload.
local _rezNames
local function RezNameSet()
    if _rezNames then
        return _rezNames
    end
    if not (C_Spell and C_Spell.GetSpellName) then
        return nil
    end
    local set, resolved = {}, false
    for spellRef in pairs(REZ_SPELL_IDS) do
        local num = C_Spell.GetSpellName(spellRef)
        if num then
            set[num] = true
            resolved = true
        end
    end
    -- Only latch the cache once something resolved: spell data can be cold this
    -- early in login, and freezing an empty set would break the fallback for good.
    if resolved then
        _rezNames = set
    end
    return set
end

local function IsRezSpellBinding(bindRec)
    if type(bindRec.spellID) == "number" and REZ_SPELL_IDS[bindRec.spellID] then
        return true
    end
    local bn = bindRec.spell
    if type(bn) == "string" then
        local nameList = RezNameSet()
        return nameList ~= nil and nameList[bn] == true
    end
    return false
end

local KEY_DISPLAY = {
    BUTTON1 = "Left Click",
    BUTTON2 = "Right Click",
    BUTTON3 = "Middle Click",
    BUTTON4 = "Mouse 4",
    BUTTON5 = "Mouse 5",
    MOUSEWHEELUP = "Wheel Up",
    MOUSEWHEELDOWN = "Wheel Down",
}

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
local headerText = nil -- SecureHandlerStateTemplate (frame bindings + cui_cc driver)
local bindProxy = nil -- SecureActionButtonTemplate (unnamed frame fallback)
local hoverCastBtn = nil -- SecureActionButtonTemplate (hovercast bindings)
local registeredFrames = {}
local ownedFrames = {}
-- Captures each frame's native type1/*type1 (left-click target) on first register, so
-- DoUnregisterFrame restores it exactly (raid -> target, CUI frames -> none; forcing
-- the raid default onto CUI frames would be wrong). Weak-keyed so dead frames drop out.
local originalTargetAttrs = setmetatable({}, { __mode = "k" })
local regQueue = {}
local unregQueue = {}
local pendingApply = false
local lastRosterCtx = nil -- content gate: last context a roster update saw
local ccInitialized = false
local eventHost = nil
local lastBindingCount = 0
local lastHoverCount = 0
local pendingSetEnabled = nil -- deferred CC_SetEnabled value when toggled in combat

-------------------------------------------------------------------------------
--  Data access
-------------------------------------------------------------------------------
local function GetClickCastDB()
    local saved = mod.db
    if not saved then
        return nil
    end
    if not saved.sv.clickCast then
        saved.sv.clickCast = {
            enabled = false,
            allFrames = true,
            downClick = true,
            specs = {},
            globals = {
                { key = "BUTTON1", type = "target", enabled = true },
                { key = "BUTTON2", type = "menu", enabled = true },
                { type = "dispel", enabled = true },
                { type = "dynamicrez", enabled = true },
                { type = "external", enabled = true },
                { type = "trinket1", enabled = true },
                { type = "trinket2", enabled = true },
            },
        }
    end
    local clickDB = saved.sv.clickCast
    return clickDB
end

-- Exposed for CludesUI._RunConflictCheck: true when click-casting is enabled.
-- Read on demand at login only; not kept live-updated.
_G._CURF_IsHoverCastEnabled = function()
    local clickDB = GetClickCastDB()
    return (clickDB and clickDB.enabled) or false
end

-- The namespaced lookups (the legacy globals are not registered on WoW
-- Forever). A spec-less character answers id 0 there; that is "no spec".
local function GetCurrentSpecID()
    local position = C_SpecializationInfo.GetSpecialization()
    local ident = position and (C_SpecializationInfo.GetSpecializationInfo(position))
    return (ident and ident ~= 0) and ident or nil
end
local function GetCurrentSpecName()
    if not GetCurrentSpecID() then
        return "No Spec"
    end
    local _, num = C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization())
    return num or "No Spec"
end
local function GetCurrentSpecIcon()
    local position = GetCurrentSpecID() and C_SpecializationInfo.GetSpecialization()
    if position then
        local _, _, _, ic = C_SpecializationInfo.GetSpecializationInfo(position)
        return ic
    end
    return nil
end

local function GetSpecBindings(specID)
    local clickDB = GetClickCastDB()
    if not clickDB then
        return {}
    end
    specID = specID or GetCurrentSpecID()
    if specID and clickDB.specs[specID] then
        return clickDB.specs[specID]
    end
    return {}
end

local function GetGlobalBindings()
    local clickDB = GetClickCastDB()
    return clickDB and clickDB.globals or {}
end

-- Content gate. binding.groupCtx is the set of contexts a binding is active in.
-- In a context that is switched off the binding is never applied so the key falls
-- through to whatever the player normally has bound.
local CC_CTX_ORDER = { "solo", "party", "raid", "pvp" }

local function CtxEnabled(bindRec, context)
    local set = bindRec.groupCtx
    if not set then
        return true
    end
    return set[context] == true
end

-- The context the player is in right now.
local function CurrentCtx()
    local _, instType = IsInInstance()
    if instType == "pvp" or instType == "arena" then
        return "pvp"
    end
    if IsInRaid() then
        return "raid"
    end
    if IsInGroup() then
        return "party"
    end
    return "solo"
end

-- True when a binding's content gate matches the context the player is in now.
local function MatchesGroupCtx(bindRec)
    return CtxEnabled(bindRec, CurrentCtx())
end

-- Hovercast mode. binding.hovercast is:
--   false / nil -> frame clicks only (attributes live on the unit frames)
--   true        -> the global @mouseover override button only
--   "both"      -> applied through BOTH paths
local function IsHoverBinding(bindRec)
    return bindRec.hovercast and true or false
end
local function IsFrameBinding(bindRec)
    return (not bindRec.hovercast) or bindRec.hovercast == "both"
end

function mod.CC_GetBindingUnitType(bindRec)
    local friendly, enemy = bindRec.hoverFriendly, bindRec.hoverEnemy
    if friendly == false and enemy == false then
        return "none"
    end
    -- The Friendly checkbox is default-on in the UI, so an omitted value is
    -- friendly unless Enemy is explicitly enabled as well. Enemy is opt-in.
    friendly = friendly ~= false
    enemy = enemy == true
    if friendly and not enemy then
        return "friendly"
    end
    if enemy and not friendly then
        return "harmful"
    end
    return "both"
end

-- Two spell bindings may share a key when their existing Friendly/Enemy
-- checkboxes select opposite reactions. Combine those branches into one macro.
local function IsReactionBinding(bindRec)
    return bindRec
        and (
            bindRec.type == "spell"
            or bindRec.type == "item"
            or (bindRec.type == "macro" and bindRec.hovercast)
        )
end

local function IsBindingActive(bindRec)
    return bindRec.enabled ~= false
        and (not IsReactionBinding(bindRec) or mod.CC_GetBindingUnitType(bindRec) ~= "none")
end

-- A spell binding the character cannot cast right now (the other options of a
-- choice node, a talent swapped out, a loadout without it) stays saved -- the
-- next loadout may bring it back -- but it cannot own a key against a spell
-- they do have, raises no conflict warning, and its tile dims. Pet-book spells
-- read as unknown from the player book, so the preset pet spells are exempt,
-- and a binding with no stored id cannot be judged, so it counts as known.
local PET_SPELL_IDS = {}
for _, spellRec in ipairs(DISPEL_SPELLS) do
    if spellRec.pet then
        PET_SPELL_IDS[spellRec.id] = true
        if spellRec.alts then
            for _, alt in ipairs(spellRec.alts) do
                PET_SPELL_IDS[alt] = true
            end
        end
    end
end

local function IsSpellIDKnown(ident)
    if type(ident) ~= "number" or ident <= 0 or PET_SPELL_IDS[ident] then
        return true
    end
    local spellBank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if not (C_SpellBook.IsSpellInSpellBook and spellBank) then
        return true
    end
    if C_SpellBook.IsSpellInSpellBook(ident, spellBank, true) then
        return true
    end
    -- The saved id may be an override of a base spell the book lists instead.
    local baseId = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(ident)
    if type(baseId) == "number" and baseId > 0 and baseId ~= ident then
        return C_SpellBook.IsSpellInSpellBook(baseId, spellBank, true) and true or false
    end
    return false
end

local function IsBindingKnown(bindRec)
    if not bindRec then
        return false
    end
    if bindRec.type == "spell" then
        if IsSpellIDKnown(bindRec.spellID) then
            return true
        end
        return bindRec.harmfulSpellID ~= nil and IsSpellIDKnown(bindRec.harmfulSpellID)
    elseif bindRec.type == "reaction" then
        return IsBindingKnown(bindRec.friendlyAction) or IsBindingKnown(bindRec.harmfulAction)
    end
    return true
end

function mod.CC_AreComplementaryReactionBindings(one, other)
    if
        not IsReactionBinding(one)
        or not IsReactionBinding(other)
        or one.key ~= other.key
        or one.harmfulSpell
        or other.harmfulSpell
    then
        return false
    end
    if
        not (
            (one.type == "spell" and (other.type == "spell" or other.type == "item"))
            or (one.type == "item" and other.type == "spell")
        )
    then
        return false
    end
    if
        not ((IsFrameBinding(one) and IsFrameBinding(other)) or (IsHoverBinding(one) and IsHoverBinding(other)))
        or (one.oocOnly or false) ~= (other.oocOnly or false)
    then
        return false
    end
    local aReaction, bReaction = mod.CC_GetBindingUnitType(one), mod.CC_GetBindingUnitType(other)
    return (aReaction == "friendly" and bReaction == "harmful")
        or (aReaction == "harmful" and bReaction == "friendly")
end

function mod.CC_AreComplementarySpellBindings(one, other)
    if not one or not other or one.type ~= "spell" or other.type ~= "spell" then
        return false
    end
    return mod.CC_AreComplementaryReactionBindings(one, other)
end

function mod.CC_MergeComplementarySpellBindings(bindList)
    local outcome = {}
    for _, bindRec in ipairs(bindList) do
        local merged = false
        for i, previous in ipairs(outcome) do
            if mod.CC_AreComplementarySpellBindings(previous, bindRec) then
                local friendly = mod.CC_GetBindingUnitType(previous) == "friendly" and previous or bindRec
                local harmful = friendly == previous and bindRec or previous
                local mergedRec = {}
                for bindKey, value in pairs(friendly) do
                    mergedRec[bindKey] = value
                end
                mergedRec.harmfulSpell = harmful.spell
                mergedRec.harmfulSpellID = harmful.spellID
                mergedRec.harmfulIcon = harmful.icon
                mergedRec.harmfulRankPinned = harmful.rankPinned
                mergedRec.hoverFriendly = true
                mergedRec.hoverEnemy = true
                mergedRec.smartRez = friendly.smartRez or harmful.smartRez
                outcome[i] = mergedRec
                merged = true
                break
            end
        end
        if not merged then
            outcome[#outcome + 1] = bindRec
        end
    end
    return outcome
end

-- A spell and an equipped item can safely share a complementary reaction key by
-- becoming one macro. Custom macro bodies remain separate because their actions
-- cannot be safely nested behind a reaction conditional.
function mod.CC_MergeComplementaryItemSpellBindings(bindList)
    local outcome = {}
    for _, bindRec in ipairs(bindList) do
        local merged = false
        for i, previous in ipairs(outcome) do
            if
                mod.CC_AreComplementaryReactionBindings(previous, bindRec)
                and previous.type ~= bindRec.type
            then
                local friendly = mod.CC_GetBindingUnitType(previous) == "friendly" and previous or bindRec
                local harmful = friendly == previous and bindRec or previous
                local spell = friendly.type == "spell" and friendly or harmful
                outcome[i] = {
                    type = "reaction",
                    key = friendly.key,
                    hovercast = friendly.hovercast,
                    oocOnly = friendly.oocOnly,
                    friendlyAction = friendly,
                    harmfulAction = harmful,
                    smartRez = friendly.smartRez or harmful.smartRez,
                    spell = spell.spell,
                    spellID = spell.spellID,
                }
                merged = true
                break
            end
        end
        if not merged then
            outcome[#outcome + 1] = bindRec
        end
    end
    return outcome
end

-- A binding configured for both dispatch paths must participate in each path's
-- merge/conflict resolution separately. This is only a runtime projection: the
-- saved binding remains a single entry in the editor.
local function ExpandBothPathBindings(bindList)
    local outcome = {}
    for _, bindRec in ipairs(bindList) do
        if bindRec.hovercast == "both" then
            local frameBinding, hoverBinding = {}, {}
            for bindKey, value in pairs(bindRec) do
                frameBinding[bindKey] = value
                hoverBinding[bindKey] = value
            end
            frameBinding.hovercast = false
            hoverBinding.hovercast = true
            outcome[#outcome + 1] = frameBinding
            outcome[#outcome + 1] = hoverBinding
        else
            outcome[#outcome + 1] = bindRec
        end
    end
    return outcome
end

-- A warning may remain for two same-reaction bindings, but only one secure
-- action can own a key. Mergeable opposite-reaction spell/item pairs have
-- already become one macro; any remaining same-key action would overwrite the
-- secure attribute, so keep the first resolved action so a later conflict
-- cannot overwrite a valid complementary spell pair. The one exception: a
-- spell the character has not got casts nothing, so a same-key action they do
-- have takes the key off it.
function mod.CC_FilterConflictingBindings(bindList)
    local outcome = {}
    for _, bindRec in ipairs(bindList) do
        local conflicts = false
        for i, previous in ipairs(outcome) do
            if
                bindRec.key == previous.key
                and (
                    (IsFrameBinding(bindRec) and IsFrameBinding(previous))
                    or (IsHoverBinding(bindRec) and IsHoverBinding(previous))
                )
            then
                conflicts = true
                if not IsBindingKnown(previous) and IsBindingKnown(bindRec) then
                    outcome[i] = bindRec
                end
                break
            end
        end
        if not conflicts then
            outcome[#outcome + 1] = bindRec
        end
    end
    return outcome
end

-- Merges globals + current spec (spec wins key conflicts, unless the spec
-- spell is one the character has not got: the global then competes for the key
-- and the conflict filter hands it over); only enabled bindings; gated on the
-- master enable toggle.
local function GetActiveBindings()
    local clickDB = GetClickCastDB()
    if not clickDB or not clickDB.enabled then
        return {}
    end
    local outcome, usedKeys, specBindings = {}, {}, {}
    for _, bind in ipairs(GetSpecBindings()) do
        if IsBindingActive(bind) and bind.key and MatchesGroupCtx(bind) then
            outcome[#outcome + 1] = bind
            specBindings[#specBindings + 1] = bind
            if IsBindingKnown(bind) then
                usedKeys[bind.key] = true
            end
        end
    end
    for _, bind in ipairs(clickDB.globals) do
        local keepGlobal = not usedKeys[bind.key]
        if not keepGlobal then
            for _, specBinding in ipairs(specBindings) do
                if mod.CC_AreComplementaryReactionBindings(specBinding, bind) then
                    keepGlobal = true
                    break
                end
            end
        end
        if IsBindingActive(bind) and bind.key and keepGlobal and MatchesGroupCtx(bind) then
            outcome[#outcome + 1] = bind
        end
    end
    outcome = ExpandBothPathBindings(outcome)
    outcome = mod.CC_MergeComplementarySpellBindings(outcome)
    outcome = mod.CC_MergeComplementaryItemSpellBindings(outcome)
    return mod.CC_FilterConflictingBindings(outcome)
end

-- Talent and loadout swaps change which saved spells the character has got,
-- and SPELLS_CHANGED is their edge (it also fires on every zone-in and spell
-- learn). Only the known/unknown pattern of the enabled spell bindings decides
-- a key, so an event that leaves the pattern as applied re-applies nothing,
-- and the event is listened for only while an enabled spell binding (or a
-- warlock's Dispels binding) exists.
local knownSig = ""
local sigBits = {}
local watchCommandDemon = false
local function ComputeKnownSignature()
    watchCommandDemon = false
    local clickDB = GetClickCastDB()
    if not clickDB or not clickDB.enabled then
        return ""
    end
    wipe(sigBits)
    local hasDispel = false
    for _, bind in ipairs(GetSpecBindings()) do
        if bind.key and IsBindingActive(bind) then
            if bind.type == "spell" then
                sigBits[#sigBits + 1] = IsBindingKnown(bind) and "1" or "0"
            elseif bind.type == "dispel" then
                hasDispel = true
            end
        end
    end
    for _, bind in ipairs(clickDB.globals) do
        if bind.key and IsBindingActive(bind) then
            if bind.type == "spell" then
                sigBits[#sigBits + 1] = IsBindingKnown(bind) and "1" or "0"
            elseif bind.type == "dispel" then
                hasDispel = true
            end
        end
    end
    -- The Dispels macro casts Command Demon only while it overrides to Singe Magic.
    if hasDispel and select(2, UnitClass("player")) == "WARLOCK" then
        watchCommandDemon = true
        sigBits[#sigBits + 1] = "|" .. (C_Spell.GetOverrideSpell(119898) or 0)
    end
    -- WoW Forever: the Dispels key casts the first dispel the character knows,
    -- so learning a better one (or the book filling in after login) rebuilds it.
    if hasDispel and CludesUI.IS_FOREVER then
        local spellRec = DispelPresetSpells(select(2, UnitClass("player")))[1]
        sigBits[#sigBits + 1] = "|d" .. (spellRec and spellRec.id or 0)
    end
    return table.concat(sigBits)
end

-------------------------------------------------------------------------------
--  Key utilities
-------------------------------------------------------------------------------
local function GetModifierPrefix()
    local prefix = ""
    if IsAltKeyDown() then
        prefix = prefix .. "ALT-"
    end
    if IsControlKeyDown() then
        prefix = prefix .. "CTRL-"
    end
    if IsShiftKeyDown() then
        prefix = prefix .. "SHIFT-"
    end
    -- Command uses META; the Mac-only API is optional on other platforms.
    if IsMetaKeyDown and IsMetaKeyDown() then
        prefix = prefix .. "META-"
    end
    return prefix
end
-- Exposed so the keybind-capture button uses this SAME canonical order (WoW matches
-- bindings/clicks in ALT-CTRL-SHIFT-META order). A non-canonical order silently fails to
-- match on double-modifier binds (single-modifier binds are order-independent).
mod.CC_GetModifierPrefix = GetModifierPrefix

function mod.CC_CaptureKey(rawKey)
    if MODIFIER_KEYS[rawKey] or rawKey == "ESCAPE" or rawKey == "UNKNOWN" then
        return nil
    end
    local bindKey = MOUSE_BUTTON_MAP[rawKey] or rawKey:upper()
    return GetModifierPrefix() .. bindKey
end

-- Parses "ALT-CTRL-SHIFT-KEY": modifiers are peeled from the FRONT as known
-- prefixes (never split on "-") because the key itself can BE "-" (minus key) --
-- splitting on "-" would leave key nil and crash for that bind (or CTRL--).
local function ParseKeyString(keyText)
    if not keyText or keyText == "" then
        return { modifiers = "", key = "", isMouseButton = false, buttonNum = nil, full = keyText or "" }
    end
    local rest, mods = keyText, ""
    while true do
        local pre = (rest:sub(1, 4) == "ALT-" and "ALT-")
            or (rest:sub(1, 5) == "CTRL-" and "CTRL-")
            or (rest:sub(1, 6) == "SHIFT-" and "SHIFT-")
            or (rest:sub(1, 5) == "META-" and "META-")
        if pre and #rest > #pre then
            mods = mods .. pre
            rest = rest:sub(#pre + 1)
        else
            break
        end
    end
    local bindKey = rest
    local isMouse = bindKey:match("^BUTTON%d+$") or bindKey == "MOUSEWHEELUP" or bindKey == "MOUSEWHEELDOWN"
    local btnNum = bindKey:match("^BUTTON(%d+)$")
    return {
        modifiers = mods,
        key = bindKey,
        isMouseButton = isMouse ~= nil,
        buttonNum = btnNum and tonumber(btnNum),
        full = keyText,
    }
end

function mod.CC_FormatKey(keyText)
    if not keyText or keyText == "" then
        return ""
    end
    -- ParseKeyString handles key == "-" (minus key); modifiers is a run of
    -- "MOD-" tokens and never contains a bare "-".
    local parsedMacro = ParseKeyString(keyText)
    local display = {}
    for m in parsedMacro.modifiers:gmatch("([^-]+)") do
        display[#display + 1] = m == "SHIFT" and "Shift"
            or m == "CTRL" and "Ctrl"
            or m == "ALT" and "Alt"
            or m == "META" and "Cmd"
            or m
    end
    display[#display + 1] = CludesUI.L(KEY_DISPLAY[parsedMacro.key]) or parsedMacro.key
    return table.concat(display, " + ")
end
mod.CC_ParseKeyString = ParseKeyString

-- Native click prefixes omit META, so Command-clicks need virtual buttons.
local function UsesDirectClickAttributes(parsedMacro)
    return parsedMacro.isMouseButton
        and parsedMacro.buttonNum
        and parsedMacro.buttonNum <= 5
        and not parsedMacro.modifiers:find("META-", 1, true)
end

-- Heals saved keys with non-canonical modifier order (WoW matches ALT-CTRL-SHIFT; other
-- orders silently fail double-modifier binds). Rewrites DB tables in place. Called once
-- at the top of CC_ApplyBindings (load/bind-change/spec-change/ profile-swap only,
-- never per-frame/combat); no-op once canonical -- zero steady-state cost.
local function NormalizeSavedBindingKeys()
    local clickDB = GetClickCastDB()
    if not clickDB then
        return
    end
    local function canon(bind)
        if not bind.key or bind.key == "" then
            return
        end
        local parsedMacro = ParseKeyString(bind.key)
        if parsedMacro.modifiers == "" then
            return
        end -- no modifiers -> nothing to reorder
        local prefix = ""
        if parsedMacro.modifiers:find("ALT-", 1, true) then
            prefix = prefix .. "ALT-"
        end
        if parsedMacro.modifiers:find("CTRL-", 1, true) then
            prefix = prefix .. "CTRL-"
        end
        if parsedMacro.modifiers:find("SHIFT-", 1, true) then
            prefix = prefix .. "SHIFT-"
        end
        if parsedMacro.modifiers:find("META-", 1, true) then
            prefix = prefix .. "META-"
        end
        local canonical = prefix .. parsedMacro.key
        if canonical ~= bind.key then
            bind.key = canonical
        end
    end
    if clickDB.specs then
        for _, entries in pairs(clickDB.specs) do
            if type(entries) == "table" then
                for _, bind in ipairs(entries) do
                    canon(bind)
                end
            end
        end
    end
    if clickDB.globals then
        for _, bind in ipairs(clickDB.globals) do
            canon(bind)
        end
    end
end

-------------------------------------------------------------------------------
--  Macro / spell helpers
-------------------------------------------------------------------------------
-- Macrotext: spells wrap @mouseover+friend/harm+nocombat; macros read the saved
-- body (+ optional /stopmacro [combat]). MOUNT_GUARD appends to hovercast
-- conditionals so overrides don't eat keypresses while dragonriding/in vehicles.
local MOUNT_GUARD = ",nomounted,noflying"

-- Resolves a spell binding to its BASE spell NAME (via stored spellID): casting the
-- base name auto-resolves to whatever talent/hero-talent/proc override is active, while
-- casting the override name directly fails without it. Works for existing and new
-- bindings with no DB rewrite; the binding still DISPLAYS the name the user picked.
local function ResolveCastSpellName(bindRec)
    local ident = bindRec.spellID
    if type(ident) == "number" and ident > 0 and C_Spell and C_Spell.GetBaseSpell then
        local baseId = C_Spell.GetBaseSpell(ident)
        if type(baseId) == "number" and baseId > 0 and baseId ~= ident then
            local num = C_Spell.GetSpellName and C_Spell.GetSpellName(baseId)
            if num then
                return num
            end
        end
    end
    return bindRec.spell
end

local function ResolveHarmfulSpellName(bindRec)
    local ident = bindRec.harmfulSpellID
    if type(ident) == "number" and ident > 0 and C_Spell and C_Spell.GetBaseSpell then
        local baseId = C_Spell.GetBaseSpell(ident)
        if type(baseId) == "number" and baseId > 0 and baseId ~= ident then
            local label = C_Spell.GetSpellName and C_Spell.GetSpellName(baseId)
            if label then
                return label
            end
        end
    end
    return bindRec.harmfulSpell
end

-- WoW Forever spell ranks: /cast by name always casts the highest rank the
-- character knows, so a binding picked from a LOWER rank (binding.rankPinned,
-- its spellID is that rank; harmfulRankPinned for a merged harmful half) casts
-- through a hidden per-rank proxy button instead: CastSpellByID on the exact
-- rank, the path Blizzard's own rank flyout takes, reached by a
-- "/click [conditions] <proxy>" line so every macro condition still applies.
-- A binding picked from the top rank stays unpinned and follows the highest
-- rank as the character learns more. Never set and never read off Forever.
local RANKS = CludesUI.IS_FOREVER == true
local rankProxies = {}
local function PinnedRankID(bindRec, harmful)
    if not RANKS then
        return nil
    end
    local ident
    if harmful then
        ident = bindRec.harmfulRankPinned and bindRec.harmfulSpellID
    else
        ident = bindRec.rankPinned and bindRec.spellID
    end
    if type(ident) == "number" and ident > 0 then
        return ident
    end
    return nil
end

-- The proxy's global name is deterministic, so a macro can name it before the
-- button exists. Built out of combat only; every caller writes secure
-- attributes, which are out-of-combat writes themselves.
local function RankProxyName(ident)
    local label = "CUIClickCastRank" .. ident
    if not rankProxies[ident] and not InCombatLockdown() then
        local p = CreateFrame("Button", label, UIParent, "SecureActionButtonTemplate")
        p:SetSize(1, 1)
        p:SetAlpha(0)
        p:EnableMouse(false)
        p:RegisterForClicks("AnyUp")
        p:SetAttribute("type", "spell")
        for i = 1, 5 do
            p:SetAttribute("type" .. i, "spell")
        end
        p:SetAttribute("spell", ident)
        p:SetAttribute("unit", "mouseover")
        -- Act on the up-click the /click delivers, whatever the cast-on-key-down setting.
        p:SetAttribute("useOnKeyDown", false)
        rankProxies[ident] = p
    end
    return label
end

-- One cast line for a spell binding (harmful = its merged harmful half) under
-- the bracketed condition string condStr: /cast by name, or /click to the
-- rank proxy while that half is pinned to a rank. Nil when there is no spell.
local function SpellCastLine(bindRec, condStr, harmful)
    local ident = PinnedRankID(bindRec, harmful)
    if ident then
        return "/click " .. condStr .. " " .. RankProxyName(ident)
    end
    local label
    if harmful then
        label = ResolveHarmfulSpellName(bindRec)
    else
        label = ResolveCastSpellName(bindRec)
    end
    if not label then
        return nil
    end
    return "/cast " .. condStr .. " " .. label
end

-- The rank a pinned WoW Forever binding casts ("Rank 2"), for display; nil for
-- every other binding and while the spell's text is not loaded.
function mod.CC_GetBindingRankText(bind)
    local ident = bind and bind.type == "spell" and PinnedRankID(bind)
    if not ident then
        return nil
    end
    local sub = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(ident)
    if sub and sub ~= "" then
        return sub
    end
    return nil
end

-- The "already bound" key of a spell picker entry or binding: a pinned WoW
-- Forever rank dims only its own rank, anything else its name.
function mod.CC_SpellBoundKey(ident, label, pinned)
    if RANKS and pinned and ident then
        return "#" .. ident
    end
    return label
end

-- True when a picker entry is already bound: by its own key, or (WoW Forever)
-- by a binding pinned to exactly this rank -- bindings are account-wide, so
-- another character's lower rank can be this one's top rank.
function mod.CC_IsSpellBound(set, ident, label, lowRank)
    return set[mod.CC_SpellBoundKey(ident, label, lowRank)] or (RANKS and ident and set["#" .. ident]) or false
end

-- Picker tooltip for a WoW Forever ranked spell entry; false when the entry
-- carries no rank (the caller keeps its own tooltip, if any).
function mod.CC_RankTip(ownerFrame, entry)
    if not (entry and (entry.lowRank or entry.ranked)) then
        return false
    end
    local textValue
    if entry.lowRank then
        textValue = entry.rankText and (entry.name .. " (" .. entry.rankText .. ")") or entry.name
    else
        textValue = entry.name .. "\n" .. CludesUI.L("Always casts your highest rank.")
    end
    CludesUI.ShowWidgetTooltip(ownerFrame, textValue)
    return true
end

local function BuildReactionMacroText(bindRec, guardCond)
    local lineList = {}
    local function AddAction(part, reaction)
        if part.type == "spell" then
            local conditions = { "@mouseover", reaction }
            if not IsRezSpellBinding(part) then
                conditions[#conditions + 1] = "exists"
                conditions[#conditions + 1] = "nodead"
            end
            if bindRec.oocOnly then
                conditions[#conditions + 1] = "nocombat"
            end
            local line = SpellCastLine(part, "[" .. table.concat(conditions, ",") .. guardCond .. "]")
            if not line then
                return
            end
            lineList[#lineList + 1] = line
        elseif part.type == "item" then
            local target = part.itemSlot or part.itemName
            if not target then
                return
            end
            local conditions = { "@mouseover", reaction, "exists", "nodead" }
            if bindRec.oocOnly then
                conditions[#conditions + 1] = "nocombat"
            end
            lineList[#lineList + 1] = "/use [" .. table.concat(conditions, ",") .. guardCond .. "] " .. target
        end
    end
    AddAction(bindRec.friendlyAction, "help")
    AddAction(bindRec.harmfulAction, "harm")
    if #lineList == 0 then
        return nil
    end
    return table.concat(lineList, "\n")
end

-- The combat rez item a class with no battle rez falls back to: the first one
-- carried, or nil.
local function CarriedRezItem()
    local _, playerClass = UnitClass("player")
    local rezKit = REZ_BY_CLASS[playerClass]
    if rezKit and rezKit.battle then
        return nil
    end
    for i = 1, #REZ_ITEMS do
        if C_Item.GetItemCount(REZ_ITEMS[i]) > 0 then
            return REZ_ITEMS[i]
        end
    end
    return nil
end

-- The item the rez lines use, read once per CC_ApplyBindings (only while a
-- rez binding could use it); the bag listener re-applies when it changes.
local rezItemID = nil

-- Builds dynamic-rez /cast lines (used by the dynamicrez binding type + Smart
-- Rez). Returns a list of macro lines (possibly empty) or nil when the class
-- has no rez kit and carries no combat rez item. Never includes /stopmacro --
-- caller adds that for oocOnly.
-- standalone marks the dedicated rez binding, where these lines are the whole
-- macro rather than a [dead] prefix in front of somebody else's action. noItem
-- leaves the combat rez item out (a Smart Rez macro short of room).
local function BuildRezLines(bindRec, guardCond, standalone, noItem)
    local _, playerClass = UnitClass("player")
    local rezKit = REZ_BY_CLASS[playerClass]
    local entry = not noItem and rezItemID
    if not rezKit and not entry then
        return nil
    end
    local spellBank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    -- A slot is one spell ID or a list of rank IDs. The first rank found in the
    -- book answers: every rank shares the name, and /cast by name casts the
    -- highest rank known.
    local function Known(spellRef)
        if not spellRef then
            return nil
        end
        if type(spellRef) == "table" then
            for i = 1, #spellRef do
                local label = Known(spellRef[i])
                if label then
                    return label
                end
            end
            return nil
        end
        if C_SpellBook.IsSpellInSpellBook and spellBank then
            if not C_SpellBook.IsSpellInSpellBook(spellRef, spellBank, true) then
                return nil
            end
        end
        return C_Spell.GetSpellName and C_Spell.GetSpellName(spellRef)
    end
    local battleName = rezKit and Known(rezKit.battle)
    local groupName = rezKit and Known(rezKit.group)
    local singleName = rezKit and Known(rezKit.single)
    local lineList = {}
    -- [combat] only when there is an out-of-combat rez after it to be the answer
    -- instead. A death knight or a warlock, whose only rez IS the battle one,
    -- would otherwise cast nothing out of combat -- where that spell works
    -- perfectly well, so theirs takes oocOnly's [nocombat] rather than dropping.
    -- That conditional has to live on the line: Smart Rez prepends these ahead of
    -- the base macro, and so ahead of its /stopmacro [combat].
    local hasOOCRez = groupName or singleName
    if battleName and not (hasOOCRez and bindRec.oocOnly) then
        local combatCond = ""
        if hasOOCRez then
            combatCond = ",combat"
        elseif bindRec.oocOnly then
            combatCond = ",nocombat"
        end
        lineList[#lineList + 1] = "/cast [@mouseover,help,dead" .. combatCond .. guardCond .. "] " .. battleName
    elseif entry and not bindRec.oocOnly then
        -- No battle rez in the class: the carried combat rez item instead.
        lineList[#lineList + 1] = "/use [@mouseover,help,dead,combat" .. guardCond .. "] item:" .. entry
    end
    if groupName then
        lineList[#lineList + 1] = "/cast [@mouseover,help,dead,nocombat" .. guardCond .. "] " .. groupName
    elseif singleName then
        lineList[#lineList + 1] = "/cast [@mouseover,help,dead,nocombat" .. guardCond .. "] " .. singleName
    end
    -- Soulstone also pre-buffs a LIVING ally, which the [dead] lines above can
    -- never reach. Standalone only: Smart Rez prepends these lines to another
    -- action and depends on all of them failing on a living unit.
    if standalone and playerClass == "WARLOCK" and battleName then
        local oocCond = bindRec.oocOnly and ",nocombat" or ""
        lineList[#lineList + 1] = "/cast [@mouseover,help,exists,nodead" .. oocCond .. guardCond .. "] " .. battleName
    end
    return lineList
end

-- A macro binding's macro index, or nil. An account macro and a character
-- macro may share a name, and GetMacroIndexByName then returns either one,
-- so a binding records the tab it was picked from (macroChar true or false)
-- and is looked up in that tab only: with its own macro gone it casts
-- nothing rather than a namesake. Bindings saved before that (macroChar nil)
-- look in the account tab first, then up by name.
local function GetBindingMacroIndex(bind)
    local label = bind.macroName
    if not label then
        return nil
    end
    local numAccount, numChar = GetNumMacros()
    local first, last = 1, numAccount or 0
    if bind.macroChar then
        first, last = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + (numChar or 0)
    end
    for i = first, last do
        if GetMacroInfo(i) == label then
            return i
        end
    end
    if bind.macroChar ~= nil then
        return nil
    end
    local position = GetMacroIndexByName(label)
    if position and position > 0 then
        return position
    end
    return nil
end

-- The pickers' "already bound" key for a macro: its name within its own tab,
-- so a bound character macro does not dim an account macro of the same name.
local function MacroBoundKey(label, isChar)
    return (isChar and "char:" or "account:") .. label
end

-- Marks a binding's macro as bound, in the tab it resolves to.
local function MarkBoundMacro(set, bind)
    local position = bind.macroName and GetBindingMacroIndex(bind)
    if position then
        set[MacroBoundKey(bind.macroName, position > MAX_ACCOUNT_MACROS)] = true
    end
end

-- Builds base macrotext (no Smart Rez). Returns nil when no macro wrapping is
-- needed (applied as a direct spell instead).
local function BuildBaseMacroText(bindRec)
    local isHC = bindRec.hovercast
    local guardCond = isHC and MOUNT_GUARD or ""

    if bindRec.type == "reaction" then
        return BuildReactionMacroText(bindRec, guardCond)
    elseif bindRec.type == "spell" then
        local label = ResolveCastSpellName(bindRec)
        if not label then
            return nil
        end
        local isRez = IsRezSpellBinding(bindRec)
        local unitType = mod.CC_GetBindingUnitType(bindRec)
        local conditions = { "@mouseover" }
        if bindRec.harmfulSpell then
            local harmfulName = ResolveHarmfulSpellName(bindRec)
            if harmfulName then
                local lineList = {}
                local function AddReactionLine(reaction, harmful)
                    local reactionEnabled = (reaction == "help" and unitType ~= "harmful")
                        or (reaction == "harm" and unitType ~= "friendly")
                    if not reactionEnabled then
                        return
                    end
                    local reactionConds = { "@mouseover", reaction }
                    if not isRez then
                        reactionConds[#reactionConds + 1] = "exists"
                        reactionConds[#reactionConds + 1] = "nodead"
                    end
                    if bindRec.oocOnly then
                        reactionConds[#reactionConds + 1] = "nocombat"
                    end
                    lineList[#lineList + 1] = SpellCastLine(
                        bindRec,
                        "[" .. table.concat(reactionConds, ",") .. guardCond .. "]",
                        harmful
                    )
                end
                AddReactionLine("help", false)
                AddReactionLine("harm", true)
                if #lineList == 0 then
                    return nil
                end
                return table.concat(lineList, "\n")
            end
        end
        if unitType == "friendly" then
            conditions[#conditions + 1] = "help"
        elseif unitType == "harmful" then
            conditions[#conditions + 1] = "harm"
        end
        -- exists,nodead: without it, a gone/dead hovered unit lets the cast fall
        -- through to Blizzard default targeting -- with auto self-cast on, it
        -- lands on the player instead of being dropped. Rez spells are exempt
        -- (corpses are their only valid target).
        if not isRez then
            conditions[#conditions + 1] = "exists"
            conditions[#conditions + 1] = "nodead"
        end
        if bindRec.oocOnly then
            conditions[#conditions + 1] = "nocombat"
        end
        -- A frame-click rez binding with no other conditions needs no macro
        -- wrapping; it is applied as a direct spell attribute instead.
        if isRez and not isHC and #conditions == 1 then
            return nil
        end
        return SpellCastLine(bindRec, "[" .. table.concat(conditions, ",") .. guardCond .. "]")
    elseif bindRec.type == "macro" then
        local position = GetBindingMacroIndex(bindRec)
        if not position then
            return nil
        end
        local macroBody = GetMacroBody(position)
        if not macroBody then
            return nil
        end
        if bindRec.oocOnly then
            macroBody = "/stopmacro [combat]\n" .. macroBody
        end
        if isHC then
            macroBody = "/stopmacro [mounted][flying]\n" .. macroBody
            -- User macro bodies cannot fold friend/harm conditions into their
            -- own commands, so Hovercast gates the whole macro instead.
            local unitType = mod.CC_GetBindingUnitType(bindRec)
            if unitType == "none" then
                return "/stopmacro"
            end
            if unitType == "friendly" then
                macroBody = "/stopmacro [@mouseover,nohelp]\n" .. macroBody
            elseif unitType == "harmful" then
                macroBody = "/stopmacro [@mouseover,noharm]\n" .. macroBody
            end
        end
        return macroBody
    elseif bindRec.type == "item" then
        local target = bindRec.itemSlot or bindRec.itemName
        if not target then
            return nil
        end
        local unitType = mod.CC_GetBindingUnitType(bindRec)
        local reaction = unitType == "friendly" and ",help" or unitType == "harmful" and ",harm" or ""
        local cmd = "/use [@mouseover" .. reaction .. ",exists,nodead" .. guardCond .. "] " .. target
        if bindRec.oocOnly then
            cmd = "/stopmacro [combat]\n" .. cmd
        end
        return cmd
    elseif bindRec.type == "trinket1" or bindRec.type == "trinket2" then
        local slot = bindRec.type == "trinket1" and 13 or 14
        local cmd = "/use [@mouseover,exists,nodead" .. guardCond .. "] " .. slot
        if bindRec.oocOnly then
            cmd = "/stopmacro [combat]\n" .. cmd
        end
        return cmd
    elseif bindRec.type == "dynamicrez" then
        local lineList = BuildRezLines(bindRec, guardCond, true)
        if not lineList or #lineList == 0 then
            return nil
        end
        if bindRec.oocOnly then
            table.insert(lineList, 1, "/stopmacro [combat]")
        end
        return table.concat(lineList, "\n")
    elseif bindRec.type == "dispel" or bindRec.type == "external" then
        local _, playerClass = UnitClass("player")
        local spellList = bindRec.type == "dispel" and DispelPresetSpells(playerClass)
            or ClassPresetSpells(EXTERNAL_SPELLS, playerClass)
        local lineList = {}
        if bindRec.oocOnly then
            lineList[#lineList + 1] = "/stopmacro [combat]"
        end
        for _, spellRec in ipairs(spellList) do
            -- /cast resolves by localized name; hardcoded English sp.name would
            -- silently fail on non-English clients. Fall back to sp.name only if
            -- the API is unavailable/empty.
            local castID = spellRec.id
            -- Singe Magic goes through Command Demon while that overrides to it (Imp
            -- out or sacrificed): a sacrificed Imp's is reachable no other way.
            if spellRec.pet then
                local commandName = C_Spell.GetSpellName(C_Spell.GetOverrideSpell(119898) or 119898)
                if commandName and commandName == C_Spell.GetSpellName(spellRec.id) then
                    castID = 119898
                end
            end
            local castName = (C_Spell.GetSpellName and C_Spell.GetSpellName(castID)) or spellRec.name
            lineList[#lineList + 1] = "/cast [@mouseover,exists,nodead" .. guardCond .. "] " .. castName
        end
        if #lineList == 0 then
            return nil
        end
        return table.concat(lineList, "\n")
    end
    return nil
end

-- Clear Stuck Spell Targeting (HoverCast page, cc.clearTargeting, on unless
-- switched off). A cast on a unit the spell cannot take (a priest in Spirit of
-- Redemption) leaves the spell waiting for a target, which swallows the next
-- press. Each cast line this file writes is led by /stopspelltarget under the
-- same conditions, so a press that is about to cast first drops a spell still
-- waiting -- what Blizzard's own mouseover casting does before a mouseover
-- cast. The clear goes BEFORE the cast, never after it: a ground-targeted
-- spell ignores @mouseover and opens its placement circle, which a clear after
-- the cast would close at once. SpellStopTargeting is protected, so a secure
-- macro line is the only way to reach it.
local function ClearTargetingOn()
    local clickDB = GetClickCastDB()
    return not (clickDB and clickDB.clearTargeting == false)
end

-- Macro text -> the same text with its clears; the whole input is the key.
-- ResolveBinding runs for every binding on every frame (registration bursts,
-- CC_ApplyBindings), so each repeat of a binding's identical macro is one
-- lookup. Wiped at every apply, so texts an edit retired do not pile up.
local clearMemo = {}

local function AddTargetingClears(textValue)
    if not textValue or not ClearTargetingOn() then
        return textValue
    end
    local hit = clearMemo[textValue]
    if hit then
        return hit
    end
    local out, seen = {}, {}
    for line in (textValue .. "\n"):gmatch("([^\n]*)\n") do
        local cond = line:match("^/cast%s+(%b[])")
            or line:match("^/use%s+(%b[])")
            or line:match("^/click%s+(%b[])")
        -- One clear per condition set: a dispel list repeats the same
        -- conditions on every line, and the first clear already covers them.
        if cond and not seen[cond] then
            seen[cond] = true
            out[#out + 1] = "/stopspelltarget " .. cond
        end
        out[#out + 1] = line
    end
    local outcome = table.concat(out, "\n")
    clearMemo[textValue] = outcome
    return outcome
end

-- Secure macro text is capped at 255 characters, the macro limit, and an
-- action button's macrotext is held to it too: a binding macro past the cap
-- does not run as written, and its own action is the line that goes. Counted
-- in bytes. A HoverCast macro over the cap trades the mount guard on every
-- conditional for one leading /stopmacro, which runs the same.
local MACRO_MAX = 255
local GUARD_STOP = "/stopmacro [mounted][flying]\n"
local function FitMacro(textValue, hover)
    if not textValue or #textValue <= MACRO_MAX then
        return textValue
    end
    if hover then
        local macroBody = textValue:gsub("/stopmacro %[mounted%]%[flying%]\n", "")
        macroBody = macroBody:gsub(",nomounted,noflying%]", "]")
        local compact = GUARD_STOP .. macroBody
        if #compact <= MACRO_MAX then
            return compact
        end
    end
    return nil
end

-- Wraps base macrotext with Smart Rez: when binding.smartRez is set, dynamic-rez
-- /cast lines are prepended (they fail their [dead] condition on a living unit,
-- so the macro falls through to the normal action). Every result fits the
-- macro cap: the clears go first, then Smart Rez's combat rez item, then Smart
-- Rez itself, never the binding's own action.
local function BuildMacroText(bindRec)
    local hover = bindRec.hovercast and true or false
    local plain = BuildBaseMacroText(bindRec)
    -- A user macro body is theirs: only the lines this file writes get clears.
    local cleared = plain
    if bindRec.type ~= "macro" then
        cleared = AddTargetingClears(plain)
    end
    local base = FitMacro(cleared, hover) or FitMacro(plain, hover) or plain
    if not bindRec.smartRez then
        return base
    end
    -- A pinned WoW Forever rez rank is the rez itself: the by-name rez lines
    -- would cast the top rank ahead of it on every dead target.
    if PinnedRankID(bindRec) and IsRezSpellBinding(bindRec) then
        return base
    end
    -- Smart Rez never applies to non-cast bindings or the rez binding itself.
    if bindRec.type == "target" or bindRec.type == "menu" or bindRec.type == "dynamicrez" then
        return base
    end
    local guardCond = hover and MOUNT_GUARD or ""
    local rez = BuildRezLines(bindRec, guardCond)
    if not rez or #rez == 0 then
        return base
    end
    -- A plain spell binding produces no base macro (applied as a direct spell);
    -- convert it to a macro so the rez lines can lead, then cast on the same unit.
    if not plain and bindRec.type == "spell" then
        plain = SpellCastLine(bindRec, "[@mouseover,exists,nodead" .. guardCond .. "]")
        cleared = AddTargetingClears(plain)
    end
    local function Join(rezText, action)
        if action then
            return rezText .. "\n" .. action
        end
        return rezText
    end
    -- The richest form that fits: clears on every line, then on the action
    -- only, then none, then without the combat rez item.
    local rezText = table.concat(rez, "\n")
    local textValue = FitMacro(Join(AddTargetingClears(rezText), cleared), hover)
        or FitMacro(Join(rezText, cleared), hover)
        or FitMacro(Join(rezText, plain), hover)
    if not textValue and rezItemID then
        local spellList = BuildRezLines(bindRec, guardCond, false, true)
        if spellList and #spellList > 0 then
            textValue = FitMacro(Join(table.concat(spellList, "\n"), plain), hover)
        end
    end
    return textValue or base
end

function mod.CC_GetBindingIcon(bind)
    if bind.type == "dispel" then
        local _, pc = UnitClass("player")
        for _, spellRec in ipairs(DispelPresetSpells(pc)) do
            local texture = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellRec.id)
            if texture then
                return texture
            end
        end
        return ACTION_ICONS.dispel
    elseif bind.type == "external" then
        local _, pc = UnitClass("player")
        for _, spellRec in ipairs(ClassPresetSpells(EXTERNAL_SPELLS, pc)) do
            local texture = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellRec.id)
            if texture then
                return texture
            end
        end
        return ACTION_ICONS.external
    elseif bind.type == "trinket1" then
        return GetInventoryItemTexture("player", 13) or 134400
    elseif bind.type == "trinket2" then
        return GetInventoryItemTexture("player", 14) or 134400
    elseif bind.type == "dynamicrez" then
        local _, pc = UnitClass("player")
        local rezKit = REZ_BY_CLASS[pc]
        if rezKit then
            local spellRef = rezKit.battle or rezKit.group or rezKit.single
            if type(spellRef) == "table" then
                spellRef = spellRef[1]
            end
            if spellRef then
                local texture = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellRef)
                if texture then
                    return texture
                end
            end
        end
        return 136080
    end
    if bind.icon then
        return bind.icon
    end
    if bind.spellID then
        local details = C_Spell.GetSpellInfo(bind.spellID)
        if details and details.iconID then
            return details.iconID
        end
    end
    if bind.spell then
        local details = C_Spell.GetSpellInfo(bind.spell)
        if details and details.iconID then
            return details.iconID
        end
    end
    if bind.macroName then
        local position = GetBindingMacroIndex(bind)
        if position then
            local _, iconTexture = GetMacroInfo(position)
            if iconTexture then
                return iconTexture
            end
        end
    end
    if bind.itemSlot then
        local texture = GetInventoryItemTexture("player", bind.itemSlot)
        if texture then
            return texture
        end
    end
    return ACTION_ICONS[bind.type] or 134400
end

function mod.CC_GetBindingName(bind)
    if bind.type == "target" then
        return CludesUI.L("Target Unit")
    end
    if bind.type == "menu" then
        return CludesUI.L("Context Menu")
    end
    if bind.type == "trinket1" then
        return CludesUI.L("Trinket 1")
    end
    if bind.type == "trinket2" then
        return CludesUI.L("Trinket 2")
    end
    if bind.type == "dynamicrez" then
        return CludesUI.L("Dynamic Rez")
    end
    if bind.type == "spell" then
        return bind.spell or CludesUI.L("Unknown Spell")
    end
    if bind.type == "macro" then
        if not bind.macroName then
            return CludesUI.L("Unknown Macro")
        end
        -- A character macro reads "(C) name", as in the pickers, so it is told
        -- apart from an account macro of the same name. A binding saved before
        -- the tab was recorded shows the tab it resolves to.
        local isChar = bind.macroChar
        if isChar == nil then
            local position = GetBindingMacroIndex(bind)
            isChar = position ~= nil and position > MAX_ACCOUNT_MACROS
        end
        return isChar and ("(C) " .. bind.macroName) or bind.macroName
    end
    if bind.type == "item" then
        if bind.itemSlot then
            local itemId = GetInventoryItemID("player", bind.itemSlot)
            if itemId then
                local label = C_Item.GetItemInfo(itemId)
                if label then
                    return label
                end
            end
        end
        return bind.itemName or CludesUI.L("Unknown Item")
    end
    if bind.type == "dispel" then
        return CludesUI.L("Dispels")
    end
    if bind.type == "external" then
        return CludesUI.L("Externals")
    end
    return CludesUI.L("Unknown")
end

-- Spell enumeration (class/spec spells, non-passive, non-general). WoW Forever
-- lists every rank of a spell as its own spellbook item and each keeps its entry
-- (a lower rank can own a key of its own): a lower rank carries lowRank and its
-- rank text, the top rank of a ranked spell carries ranked, and the ranks of one
-- spell sort together, top rank first. topOnly drops the lower ranks.
function mod.CC_GetClassSpells(topOnly)
    local spellList = {}
    if not C_SpellBook then
        return spellList
    end
    local spellBank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if not spellBank then
        return spellList
    end

    local numTabs = C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines() or 0
    local seen = {}
    local lowNames = {} -- WoW Forever: names that have lower ranks

    for tab = 1, numTabs do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(tab)
        if lineInfo then
            local tabName = lineInfo.name or ""
            local isGeneral = (tabName == "General" or tabName == GENERAL or tabName == "")
            local isOffSpec = lineInfo.offSpecID and lineInfo.offSpecID ~= 0

            if not isGeneral and not isOffSpec and not lineInfo.shouldHide then
                local off = lineInfo.itemIndexOffset or 0
                local total = lineInfo.numSpellBookItems or 0
                for si = off + 1, off + total do
                    local spellType, actionId, spellId = C_SpellBook.GetSpellBookItemType(si, spellBank)
                    if spellType == Enum.SpellBookItemType.Spell then
                        local spellRef = spellId or actionId
                        if spellRef and not seen[spellRef] then
                            local isPassive = C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellRef)
                            if not isPassive then
                                seen[spellRef] = true
                                local label = C_Spell.GetSpellName and C_Spell.GetSpellName(spellRef)
                                local icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellRef)
                                if label then
                                    local spellRec = { id = spellRef, name = label, icon = icon }
                                    if RANKS then
                                        if
                                            C_SpellBook.IsSpellBookItemLowRank
                                            and C_SpellBook.IsSpellBookItemLowRank(si, spellBank)
                                        then
                                            spellRec.lowRank = true
                                        end
                                        local details = C_SpellBook.GetSpellBookItemInfo
                                            and C_SpellBook.GetSpellBookItemInfo(si, spellBank)
                                        local sub = details and details.subName
                                        if (not sub or sub == "") and C_Spell.GetSpellSubtext then
                                            sub = C_Spell.GetSpellSubtext(spellRef)
                                        end
                                        if sub and sub ~= "" then
                                            spellRec.rankText = sub
                                            spellRec.rankNum = tonumber(sub:match("(%d+)"))
                                        end
                                    end
                                    if not (topOnly and spellRec.lowRank) then
                                        spellList[#spellList + 1] = spellRec
                                    end
                                    if spellRec.lowRank then
                                        lowNames[label] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if not RANKS then
        table.sort(spellList, function(lhs, rhs)
            return lhs.name < rhs.name
        end)
        return spellList
    end
    for i = 1, #spellList do
        local spellRec = spellList[i]
        if not spellRec.lowRank and lowNames[spellRec.name] then
            spellRec.ranked = true
        end
    end
    table.sort(spellList, function(lhs, rhs)
        if lhs.name ~= rhs.name then
            return lhs.name < rhs.name
        end
        if (lhs.lowRank or false) ~= (rhs.lowRank or false) then
            return not lhs.lowRank
        end
        local lhsRank, rhsRank = lhs.rankNum or 0, rhs.rankNum or 0
        if lhsRank ~= rhsRank then
            return lhsRank > rhsRank
        end
        return lhs.id > rhs.id
    end)
    return spellList
end

-- Macro enumeration
function mod.CC_GetGlobalMacros()
    local macros = {}
    local numGlobal = select(1, GetNumMacros()) or 0
    for i = 1, numGlobal do
        local label, iconTexture, macroBody = GetMacroInfo(i)
        if label then
            macros[#macros + 1] = { index = i, name = label, icon = iconTexture, isGlobal = true }
        end
    end
    return macros
end

function mod.CC_GetAllMacros()
    local macros = mod.CC_GetGlobalMacros()
    local _, numChar = GetNumMacros()
    numChar = numChar or 0
    for i = MAX_ACCOUNT_MACROS + 1, MAX_ACCOUNT_MACROS + numChar do
        local label, iconTexture, macroBody = GetMacroInfo(i)
        if label then
            macros[#macros + 1] = { index = i, name = label, icon = iconTexture, isGlobal = false }
        end
    end
    return macros
end

-- Item enumeration: equipped/bag items that have an on-use effect (trinkets etc).
local EQUIP_SLOTS = {
    { slot = 13, label = "Trinket 1" },
    { slot = 14, label = "Trinket 2" },
    { slot = 1, label = "Head" },
    { slot = 2, label = "Neck" },
    { slot = 15, label = "Back" },
    { slot = 10, label = "Hands" },
    { slot = 6, label = "Waist" },
    { slot = 16, label = "Main Hand" },
    { slot = 17, label = "Off Hand" },
}

function mod.CC_GetEquippedItems()
    local itemList = {}
    local seen = {}
    for _, details in ipairs(EQUIP_SLOTS) do
        local itemId = GetInventoryItemID("player", details.slot)
        if itemId then
            local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemId)
            if itemName then
                local spellName = C_Item.GetItemSpell(itemId)
                if spellName then
                    seen[itemId] = true
                    itemList[#itemList + 1] = {
                        name = itemName,
                        icon = itemIcon or GetInventoryItemTexture("player", details.slot),
                        itemSlot = details.slot,
                        slotLabel = details.label,
                        itemID = itemId,
                    }
                end
            end
        end
    end
    -- Bag on-use items (potions, healthstones, consumables, etc.)
    if C_Container then
        for bag = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
                if containerInfo and containerInfo.itemID and not seen[containerInfo.itemID] then
                    local itemId = containerInfo.itemID
                    local spellName = C_Item.GetItemSpell(itemId)
                    if spellName then
                        seen[itemId] = true
                        local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemId)
                        if itemName then
                            itemList[#itemList + 1] = {
                                name = itemName,
                                icon = itemIcon or containerInfo.iconFileID,
                                itemName = itemName,
                                itemID = itemId,
                            }
                        end
                    end
                end
            end
        end
    end
    return itemList
end

-------------------------------------------------------------------------------
--  Attribute generation helpers
-------------------------------------------------------------------------------
local function ModPrefixForAttr(modsStr)
    if not modsStr or modsStr == "" then
        return ""
    end
    return modsStr:lower()
end

-- Sets a secure "type" attribute, gated OOC via a combat driver when oocOnly:
-- menu/target have no macro conditional (unlike spell/macro), so the attribute
-- itself must switch -- real action OOC, inert "none" in combat. "none" (never
-- nil) matters: unit buttons default *type2="click" (menu proxy; see
-- AttachSecureUnitMenu), and the secure resolver falls back to that wildcard
-- whenever type<N> is nil, so "none" (not nil) suppresses it. OOC-only call
-- site (InCombatLockdown guards in DoRegisterFrame/CC_ApplyBindings);
-- unregisters the driver first so a stale one can't survive a type change.
local function SetGatedType(widget, attrName, value, oocOnly)
    UnregisterAttributeDriver(widget, attrName)
    if oocOnly then
        RegisterAttributeDriver(widget, attrName, "[combat] none; " .. value)
    else
        widget:SetAttribute(attrName, value)
    end
end

-- Apply click (mouse button 1-5) attributes on a frame for one binding.
local function SetClickAttr(widget, parsedMacro, actionType, spellOrMacro, macrotext, oocOnly)
    local prefixText = ModPrefixForAttr(parsedMacro.modifiers)
    local btnSuffix = tostring(parsedMacro.buttonNum)
    local typeAttr = prefixText .. "type" .. btnSuffix
    -- 12.0.7+ gates a raw "togglemenu" on unit buttons (insecure reopen taints
    -- protected items); route through the secure proxy instead. TRANSPORT: the
    -- "click" action itself crashes on a Blizzard typo (SecureTemplates.lua:564,
    -- aspect check on the mouse-button string) -- use a "/click <proxy>" macro.
    if actionType == "togglemenu" and CludesUI.GetSecureMenuMacro then
        SetGatedType(widget, typeAttr, "macro", oocOnly)
        widget:SetAttribute(prefixText .. "macrotext" .. btnSuffix, CludesUI.GetSecureMenuMacro(widget))
        return
    end
    -- 12.0.7+ also gates raw "target" on unit buttons, EXCEPT plain unmodified
    -- left-click (button 1), which still targets via Blizzard's native
    -- Interaction click-binding -- leave that one direct, route every other
    -- target binding through the ungated "click" proxy.
    if actionType == "target" and (btnSuffix ~= "1" or prefixText ~= "") and CludesUI.GetSecureTargetProxy then
        local proxy = CludesUI.GetSecureTargetProxy(widget)
        SetGatedType(widget, typeAttr, "macro", oocOnly)
        widget:SetAttribute(prefixText .. "macrotext" .. btnSuffix, "/click " .. proxy:GetName())
        return
    end
    -- Raw action type. Only menu/target honor oocOnly via the combat driver;
    -- spell/macro carry their own conditional in the macro text.
    local gate = oocOnly and (actionType == "togglemenu" or actionType == "target")
    SetGatedType(widget, typeAttr, actionType, gate)
    if actionType == "spell" then
        widget:SetAttribute(prefixText .. "spell" .. btnSuffix, spellOrMacro or "")
    elseif actionType == "macro" then
        widget:SetAttribute(prefixText .. "macrotext" .. btnSuffix, macrotext or "")
    end
end

local function ClearClickAttr(widget, parsedMacro)
    local prefixText = ModPrefixForAttr(parsedMacro.modifiers)
    local btnSuffix = tostring(parsedMacro.buttonNum)
    UnregisterAttributeDriver(widget, prefixText .. "type" .. btnSuffix)
    widget:SetAttribute(prefixText .. "type" .. btnSuffix, nil)
    widget:SetAttribute(prefixText .. "spell" .. btnSuffix, nil)
    widget:SetAttribute(prefixText .. "macrotext" .. btnSuffix, nil)
    widget:SetAttribute(prefixText .. "clickbutton" .. btnSuffix, nil)
end

-- Apply keyboard binding attributes on a frame (virtual button suffix).
local function SetKeyAttr(widget, position, actionType, spellOrMacro, macrotext, oocOnly)
    local btnSuffix = "cui_" .. position
    local typeAttr = "type-" .. btnSuffix
    -- Route a "menu" keybind through the secure proxy (see SetClickAttr for
    -- why this uses the /click macro transport instead of the click action).
    if actionType == "togglemenu" and CludesUI.GetSecureMenuMacro then
        SetGatedType(widget, typeAttr, "macro", oocOnly)
        widget:SetAttribute("macrotext-" .. btnSuffix, CludesUI.GetSecureMenuMacro(widget))
        return
    end
    -- A "target" keybind is never plain left-click, so it always hits the 12.0.7
    -- gate -- route it through the ungated "click" proxy (see SetClickAttr).
    if actionType == "target" and CludesUI.GetSecureTargetProxy then
        local proxy = CludesUI.GetSecureTargetProxy(widget)
        SetGatedType(widget, typeAttr, "macro", oocOnly)
        widget:SetAttribute("macrotext-" .. btnSuffix, "/click " .. proxy:GetName())
        return
    end
    -- Only menu/target honor oocOnly via the combat driver (see SetClickAttr).
    local gate = oocOnly and (actionType == "togglemenu" or actionType == "target")
    SetGatedType(widget, typeAttr, actionType, gate)
    if actionType == "spell" then
        widget:SetAttribute("spell-" .. btnSuffix, spellOrMacro or "")
    elseif actionType == "macro" then
        widget:SetAttribute("macrotext-" .. btnSuffix, macrotext or "")
    end
end

local function ClearKeyAttrs(widget, total)
    for i = 1, total do
        local btnSuffix = "cui_" .. i
        UnregisterAttributeDriver(widget, "type-" .. btnSuffix)
        widget:SetAttribute("type-" .. btnSuffix, nil)
        widget:SetAttribute("spell-" .. btnSuffix, nil)
        widget:SetAttribute("macrotext-" .. btnSuffix, nil)
        widget:SetAttribute("clickbutton-" .. btnSuffix, nil)
    end
end

-- Same for hovercast global button
local function ClearHoverAttrs(btn, total)
    for i = 1, total do
        local btnSuffix = "cui_hc_" .. i
        UnregisterAttributeDriver(btn, "type-" .. btnSuffix)
        btn:SetAttribute("type-" .. btnSuffix, nil)
        btn:SetAttribute("spell-" .. btnSuffix, nil)
        btn:SetAttribute("macrotext-" .. btnSuffix, nil)
        btn:SetAttribute("unit-" .. btnSuffix, nil)
    end
end

-- Resolves a binding to actionType, spellOrMacroName, macrotext for attribute setting.
local function ResolveBinding(bind)
    if bind.type == "target" then
        return "target", nil, nil
    end
    if bind.type == "menu" then
        return "togglemenu", nil, nil
    end

    local mt = BuildMacroText(bind)
    if mt then
        return "macro", nil, mt
    end

    if bind.type == "spell" then
        -- A pinned WoW Forever rank goes by id: the secure spell action casts a
        -- numeric attribute with CastSpellByID, so exactly that rank.
        local rankID = PinnedRankID(bind)
        return "spell", rankID and tostring(rankID) or ResolveCastSpellName(bind), nil
    elseif bind.type == "macro" then
        local position = GetBindingMacroIndex(bind)
        if position then
            local macroBody = GetMacroBody(position)
            return "macro", nil, macroBody
        end
        return nil, nil, nil
    end
    return nil, nil, nil
end

-- Route physical Command-clicks through the original secure action handler.
local function IsCommandClick(parsedMacro)
    return parsedMacro.buttonNum and parsedMacro.modifiers:find("META-", 1, true)
end

local COMMAND_CLICK_BODY = [[
    -- Restricted snippets expose the macro parser, but not IsMetaKeyDown.
    if not SecureCmdOptionParse("[mod:meta] yes") then return end
    local p = ""
    if IsAltKeyDown() then p = p .. "ALT-" end
    if IsControlKeyDown() then p = p .. "CTRL-" end
    if IsShiftKeyDown() then p = p .. "SHIFT-" end
    local n = button == "LeftButton" and "1"
        or button == "RightButton" and "2"
        or button == "MiddleButton" and "3"
        or button:match("^Button(%d+)$")
    if n then
        local route = self:GetAttribute("cui_cmdclick_" .. p .. "META-BUTTON" .. n)
        if route then return route end
    end
]]

-- Takes this header's wrapper off frame's script wherever it sits. UnwrapScript
-- only ever pops the TOP wrapper, whoever made it, so another addon's wrappers
-- above ours come off first and go back on, in their order, once ours is gone.
-- Out of combat only, like every caller.
local function UnwrapOwn(widget, script)
    local above
    while true do
        local hgt, pre, post = headerText:UnwrapScript(widget, script)
        if not hgt or hgt == headerText then
            break
        end
        above = above or {}
        above[#above + 1] = { hgt, pre, post }
    end
    if above then
        for i = #above, 1, -1 do
            local wid = above[i]
            SecureHandlerWrapScript(widget, script, wid[1], wid[2], wid[3])
        end
    end
end

local commandClickAttrs

local function ConfigureCommandClicks(widget, bindList)
    local previous = commandClickAttrs and commandClickAttrs[widget]
    if previous then
        for _, attr in ipairs(previous) do
            widget:SetAttribute(attr, nil)
        end
    end
    local attrs
    -- Match override precedence: hover bindings win over frame bindings.
    for pass = 1, 2 do
        for i, bind in ipairs(bindList) do
            if bind.key and bind.key:find("META-", 1, true) then
                local parsedMacro = ParseKeyString(bind.key)
                if
                    IsCommandClick(parsedMacro)
                    and (pass == 1 and IsFrameBinding(bind) or pass == 2 and IsHoverBinding(bind))
                then
                    local aType, spellName, macrotext = ResolveBinding(bind)
                    if aType then
                        SetKeyAttr(widget, i, aType, spellName, macrotext, bind.oocOnly)
                        local attr = "cui_cmdclick_" .. bind.key
                        widget:SetAttribute(attr, "cui_" .. i)
                        if not attrs then
                            attrs = {}
                        end
                        attrs[#attrs + 1] = attr
                    end
                end
            end
        end
    end
    if attrs then
        if not previous then
            headerText:WrapScript(widget, "OnClick", COMMAND_CLICK_BODY)
        end
        if not commandClickAttrs then
            commandClickAttrs = setmetatable({}, { __mode = "k" })
        end
        commandClickAttrs[widget] = attrs
    elseif previous then
        UnwrapOwn(widget, "OnClick")
        commandClickAttrs[widget] = nil
        if not next(commandClickAttrs) then
            commandClickAttrs = nil
        end
    end
end

-- OnEnter/OnLeave secure script generation (frame-based keyboard bindings).
-- Returns enterScript, leaveScript, kbClearLines. kbClearLines uses
-- self:ClearBinding (state-driver context, self=header); leaveScript uses
-- control:ClearBinding (WrapScript context, control=header).
local function GenerateKeyBindSnippets(bindList)
    local enterLines, leaveLines, clearLines = {}, {}, {}
    local kbBindings = {}
    for i, bind in ipairs(bindList) do
        if IsFrameBinding(bind) then
            local parsedMacro = ParseKeyString(bind.key)
            if not UsesDirectClickAttributes(parsedMacro) then
                kbBindings[#kbBindings + 1] = { binding = bind, index = i, parsed = parsedMacro }
            end
        end
    end
    if #kbBindings == 0 then
        return "", "", clearLines
    end

    enterLines[#enterLines + 1] = [[local name = self:GetName()]]
    enterLines[#enterLines + 1] = [[local target = name]]
    enterLines[#enterLines + 1] = [[if not name then]]
    enterLines[#enterLines + 1] = [[    local sc = control:GetFrameRef("bindProxy")]]
    enterLines[#enterLines + 1] = [[    sc:SetAttribute("unit", self:GetAttribute("unit"))]]
    enterLines[#enterLines + 1] = [[    target = "CUIClickCastBindProxy"]]
    enterLines[#enterLines + 1] = [[end]]

    -- Set/clear bindings on CONTROL (header) so both OnLeave and the
    -- state driver failsafe can clear them (same owner).
    for _, kb in ipairs(kbBindings) do
        local btnSuffix = "cui_" .. kb.index
        enterLines[#enterLines + 1] = format([[control:SetBindingClick(true, %q, target, %q)]], kb.binding.key, btnSuffix)
    end
    for _, kb in ipairs(kbBindings) do
        leaveLines[#leaveLines + 1] = format([[control:ClearBinding(%q)]], kb.binding.key)
        clearLines[#clearLines + 1] = format([[self:ClearBinding(%q)]], kb.binding.key)
    end
    return table.concat(enterLines, "\n"), table.concat(leaveLines, "\n"), clearLines
end

-------------------------------------------------------------------------------
--  Frame registration
-------------------------------------------------------------------------------
local wrappedFrames = {}
local externalFrames = {}
local ccHookInstalled = false

-- Third-party interop: while OFF, frames are handed to any other ClickCastFrames
-- consumer via the global table without touching their click attributes, so
-- right-click stays Blizzard-default. No-ops once our proxy owns the table.
local function AddFrameToClickCast(widget)
    if ccHookInstalled or not widget then
        return
    end
    if type(ClickCastFrames) ~= "table" then
        ClickCastFrames = {}
    end
    if ClickCastFrames[widget] == nil then
        ClickCastFrames[widget] = true
    end
end
local function RemoveFrameFromClickCast(widget)
    if ccHookInstalled or not widget then
        return
    end
    if type(ClickCastFrames) == "table" and ClickCastFrames[widget] then
        ClickCastFrames[widget] = nil -- tells the other consumer to drop its bindings
    end
end

local function GetClickDirection()
    local clickDB = GetClickCastDB()
    -- Down-click only applies while enabled; disabled must stay "AnyUp" so
    -- right-click fires on the up-stroke like Blizzard's default (a down-stroke
    -- togglemenu would open then instantly dismiss on the trailing up event).
    return (clickDB and clickDB.enabled and clickDB.downClick) and "AnyDown" or "AnyUp"
end

-- Neutralizes unbound-click defaults so a click with no binding does nothing.
-- A unit button is created with type1/*type1="target" + menu wildcard
-- *type2="click"; clearing the wildcards alone isn't enough (type1 survives,
-- and nil type1 falls through to Blizzard's native left-click-targets), so an
-- unbound button gets inert type1/type2="none" instead (non-nil, unrecognized
-- -> does nothing, suppresses the fallback). Bound buttons keep their own
-- type<N> from SetClickAttr. Own secure frame, OOC only -> no taint risk.
-- plan is the bindings' ResolvePlan (keys already parsed).
local function NeutralizeDefaultClicks(widget, layoutPlan)
    local b1, b2 = false, false
    for i = 1, #layoutPlan do
        local planRec = layoutPlan[i]
        if planRec.frame then
            local parsedMacro = planRec.parsed
            if parsedMacro.isMouseButton and parsedMacro.modifiers == "" then
                if parsedMacro.buttonNum == 1 then
                    b1 = true
                elseif parsedMacro.buttonNum == 2 then
                    b2 = true
                end
            end
        end
    end
    widget:SetAttribute("*type1", nil)
    widget:SetAttribute("*type2", nil)
    widget:SetAttribute("*clickbutton2", nil)
    if not b1 then
        widget:SetAttribute("type1", "none")
    end
    if not b2 then
        widget:SetAttribute("type2", "none")
    end
end

-- A binding list parsed and resolved once: what a binding writes is the same on
-- every frame, so the per-frame loops read it from here. Per binding: its parsed
-- key, whether that key is a direct mouse-button click, its cast paths, the
-- resolved action and, for HoverCast, the global button's macro.
local function ResolvePlan(bindList)
    local layoutPlan = {}
    for i, bind in ipairs(bindList) do
        local parsedMacro = ParseKeyString(bind.key)
        local aType, spellName, macrotext = ResolveBinding(bind)
        local hover = IsHoverBinding(bind)
        local hoverMT
        if hover then
            if aType == "spell" then
                hoverMT = BuildMacroText(bind)
                if not hoverMT then
                    hoverMT = AddTargetingClears(SpellCastLine(bind, "[@mouseover" .. MOUNT_GUARD .. "]"))
                        or ("/cast [@mouseover" .. MOUNT_GUARD .. "] ")
                end
            elseif aType == "macro" then
                hoverMT = macrotext or ""
            end
        end
        layoutPlan[i] = {
            b = bind,
            parsed = parsedMacro,
            direct = UsesDirectClickAttributes(parsedMacro),
            frame = IsFrameBinding(bind),
            hover = hover,
            aType = aType,
            spellName = spellName,
            macrotext = macrotext,
            hoverMT = hoverMT,
        }
    end
    return layoutPlan
end

-- Everything an apply writes from a plan as one string: each binding's key,
-- cast paths, combat gate and resolved action in list order (a keyboard
-- binding's virtual button is its position), and the HoverCast macro. Two plans
-- that write the same attributes give the same string.
local planBits = {}
local function PlanSignature(layoutPlan)
    wipe(planBits)
    for i = 1, #layoutPlan do
        local planRec = layoutPlan[i]
        local bind = planRec.b
        planBits[#planBits + 1] = bind.key or ""
        planBits[#planBits + 1] = tostring(bind.hovercast)
        planBits[#planBits + 1] = bind.oocOnly and "1" or "0"
        planBits[#planBits + 1] = planRec.aType or ""
        planBits[#planBits + 1] = planRec.spellName or ""
        planBits[#planBits + 1] = planRec.macrotext or ""
        planBits[#planBits + 1] = planRec.hoverMT or ""
    end
    return table.concat(planBits, "\31")
end

-- The last apply's PlanSignature and binding list, which every registered frame
-- carries. A registration that paints a frame from a list resolving to anything
-- else sets regDrift: that frame then holds bindings the others lack, so the
-- next apply repaints every frame.
local appliedSig, appliedList
local regDrift = false

-- Active-binding list shared across one synchronous registration burst (the
-- CompactUnitFrame hook firing per frame inside one Blizzard rebuild, the
-- init/regen queue drains, the all-frames sweep). GetActiveBindings walks and
-- merges the whole binding set, so recomputing it per frame dominated those
-- bursts. A burst never spans a render frame (GetTime stamp), and
-- CC_ApplyBindings -- where every settings write ends -- refreshes it in place.
local burst = {}
burst.Get = function()
    local nowTime = GetTime()
    if burst.at ~= nowTime then
        burst.at = nowTime
        burst.list = GetActiveBindings()
    end
    return burst.list
end
-- The burst list's plan and signature, resolved once per list.
burst.Plan = function()
    local entries = burst.Get()
    if burst.planList ~= entries then
        burst.planList = entries
        burst.plan = ResolvePlan(entries)
        burst.sig = PlanSignature(burst.plan)
    end
    return burst.plan, entries
end

local function DoRegisterFrame(widget)
    if not widget or not widget.RegisterForClicks then
        return
    end
    if not headerText then
        return
    end
    -- Hard guarantee: while disabled, ZERO frames touched (no RegisterForClicks/
    -- WrapScript/attribute writes) -- clicks never change unless the user enables.
    local clickDB = GetClickCastDB()
    if not (clickDB and clickDB.enabled) then
        return
    end
    -- No early-out on registeredFrames[frame]: re-registration MUST re-apply click
    -- attributes. CUI frames first register mid-spawn (via oUF's ClickCastFrames add);
    -- SetupUnitMenu then re-attaches the secure menu (AttachSecureUnitMenu wipes type2
    -- and re-sets the *type2 menu wildcard) and re-adds the frame -- short-circuiting
    -- would leave the menu in charge and silently revert bound right-clicks every
    -- login/reload. Every step below is idempotent/self-guarded.
    registeredFrames[widget] = true
    -- Captures native left-click target attrs ONCE so DoUnregisterFrame restores
    -- them exactly (raid -> target, CUI frames -> none) across cycles.
    if originalTargetAttrs[widget] == nil then
        originalTargetAttrs[widget] = {
            type1 = widget:GetAttribute("type1"),
            starType1 = widget:GetAttribute("*type1"),
        }
    end
    widget:RegisterForClicks(GetClickDirection())
    if widget.EnableMouseWheel then
        widget:EnableMouseWheel(true)
    end
    if not wrappedFrames[widget] then
        wrappedFrames[widget] = true
        headerText:WrapScript(
            widget,
            "OnEnter",
            [[
            -- Record the hovered CUI frame (the state-driver clear guard reads it),
            -- run the per-frame keyboard setup, then SET the hover override binding
            -- right now if it isn't already active -- so a keypress on arrival can
            -- never lose the race against the binding being set.
            cui_hoverframe = self
            control:RunFor(self, control:GetAttribute("cui_setup_onenter"))
            if not cui_hoveractive then
                control:RunAttribute("cui_hover_set")
                cui_hoveractive = true
            end
        ]]
        )
        headerText:WrapScript(
            widget,
            "OnLeave",
            [[
            -- Forget the hovered frame (so the guard stops protecting it) and run
            -- the per-frame keyboard teardown. The hover binding itself is left to
            -- the guarded state driver so moving onto a non-CUI frame keeps it.
            if cui_hoverframe == self then cui_hoverframe = nil end
            control:RunFor(self, control:GetAttribute("cui_setup_onleave"))
        ]]
        )
    end

    local layoutPlan, bindList = burst.Plan()
    for i = 1, #layoutPlan do
        local planRec = layoutPlan[i]
        if planRec.frame and planRec.b.key and planRec.aType then
            if planRec.direct then
                SetClickAttr(widget, planRec.parsed, planRec.aType, planRec.spellName, planRec.macrotext, planRec.b.oocOnly)
            else
                SetKeyAttr(widget, i, planRec.aType, planRec.spellName, planRec.macrotext, planRec.b.oocOnly)
            end
        end
    end

    ConfigureCommandClicks(widget, bindList)

    -- Neutralize unbound left-click target / right-click menu defaults (see
    -- NeutralizeDefaultClicks); restored in DoUnregisterFrame on disable.
    NeutralizeDefaultClicks(widget, layoutPlan)

    if bindList ~= appliedList and burst.sig ~= appliedSig then
        regDrift = true
    end
end

local function DoUnregisterFrame(widget)
    if not registeredFrames[widget] then
        return
    end
    registeredFrames[widget] = nil

    local bindList = burst.Get()
    for i, bind in ipairs(bindList) do
        if IsFrameBinding(bind) and bind.key then
            local parsedMacro = ParseKeyString(bind.key)
            if UsesDirectClickAttributes(parsedMacro) then
                ClearClickAttr(widget, parsedMacro)
            end
        end
    end
    ConfigureCommandClicks(widget, {})
    ClearKeyAttrs(widget, lastBindingCount)

    -- Restores the frame's NATIVE left-click target attrs captured at register
    -- time (raid -> type1/*type1="target", CUI frames -> none, never forced to
    -- target). Menu's *type2/*clickbutton2 are restored by AttachSecureUnitMenu.
    local o = originalTargetAttrs[widget]
    if o then
        widget:SetAttribute("type1", o.type1)
        widget:SetAttribute("*type1", o.starType1)
    else
        -- Never captured (shouldn't happen): fall back to the raid default.
        widget:SetAttribute("type1", "target")
        widget:SetAttribute("*type1", "target")
    end
    if CludesUI.AttachSecureUnitMenu then
        CludesUI.AttachSecureUnitMenu(widget)
    else
        widget:SetAttribute("type2", "togglemenu")
    end
    -- Fully reverts click registration and removes our OnEnter/OnLeave wraps, so
    -- the frame behaves exactly as before click-casting touched it (right-click
    -- must never be left broken after a disable).
    if widget.RegisterForClicks then
        widget:RegisterForClicks("AnyUp")
    end
    if widget.EnableMouseWheel then
        widget:EnableMouseWheel(false)
    end
    if wrappedFrames[widget] then
        wrappedFrames[widget] = nil
        if headerText and headerText.UnwrapScript then
            pcall(UnwrapOwn, widget, "OnEnter")
            pcall(UnwrapOwn, widget, "OnLeave")
        end
    end
end

-------------------------------------------------------------------------------
--  Tooltip-modifier eaters (Debuff Manager "Shown on Modifier"): secure unit
--  sub-buttons laid over a unit button's debuff band. Wrapped by THIS header
--  regardless of the enabled state (the peek needs the hover tracking even
--  with click-casting off) with the standard enter/leave bodies plus:
--   * an enter-time unit sync -- the engine's mouseover reads the frame's own
--     "unit" attribute, useparent-unit only serves the Lua action path; and
--   * the peek: if the tooltip modifier is already held on entry, the eater
--     hides itself so the hover falls through to the aura button beneath.
--  The "cui_tipmod" state driver on this header flips only the HOVERED eater
--  on a modifier edge (one macro-conditional check per press, nothing else)
--  and re-shows the peeked eater on release. wrappedFrames is set here first,
--  so DoRegisterFrame (click attributes when enabled) never wraps them twice.
-------------------------------------------------------------------------------
local tipEaters = setmetatable({}, { __mode = "k" })
local pendingTipSync = false
local pendingTipKey = nil

local TIP_ENTER_BODY = [[
    local p = self:GetParent()
    if p then self:SetAttribute("unit", p:GetAttribute("unit")) end
    cui_hoverframe = self
    control:RunFor(self, control:GetAttribute("cui_setup_onenter"))
    if not cui_hoveractive then
        control:RunAttribute("cui_hover_set")
        cui_hoveractive = true
    end
    local k = control:GetAttribute("cui_tipmod_key")
    if k and not cui_tippeeked
       and ((k == "shift" and IsShiftKeyDown())
         or (k == "control" and IsControlKeyDown())
         or (k == "alt" and IsAltKeyDown())) then
        cui_tippeeked = self
        self:Hide()
    end
]]
local TIP_LEAVE_BODY = [[
    if cui_hoverframe == self then cui_hoverframe = nil end
    control:RunFor(self, control:GetAttribute("cui_setup_onleave"))
]]

local function WrapTipEater(widget)
    if wrappedFrames[widget] then
        return
    end
    wrappedFrames[widget] = true
    headerText:WrapScript(widget, "OnEnter", TIP_ENTER_BODY)
    headerText:WrapScript(widget, "OnLeave", TIP_LEAVE_BODY)
end

-- Runs before every registration sweep (init, enable, regen) so an eater is
-- always wrapped with ITS bodies before DoRegisterFrame could reach it.
local function SyncTipEaters()
    if not (ccInitialized and headerText) then
        return
    end
    for widget in pairs(tipEaters) do
        WrapTipEater(widget)
    end
end

function mod.CC_RegisterTipEater(widget)
    tipEaters[widget] = true
    if InCombatLockdown() then
        pendingTipSync = true
    else
        SyncTipEaters()
    end
    -- Click attributes follow the enabled state like any owned unit button
    -- (self-queues to regen in combat; the sync above runs first there).
    mod.CC_RegisterFrame(widget)
end

-- A parked eater must never be re-shown by the peek: drop the header's
-- references to it. Out-of-combat only (Execute), like parking itself.
function mod.CC_ReleaseTipEater(widget)
    if not (tipEaters[widget] and ccInitialized and headerText) then
        return
    end
    headerText:SetFrameRef("cui_tipclear", widget)
    headerText:Execute([[
        local f = self:GetFrameRef("cui_tipclear")
        if cui_tippeeked == f then cui_tippeeked = nil end
        if cui_hoverframe == f then cui_hoverframe = nil end
    ]])
end

-- The tooltip modifier ("shift" / "control" / "alt"), nil to disarm. Header
-- writes, so out-of-combat only; before init the key parks until CC_Init.
function mod.CC_SetTipModKey(bindKey)
    if not (ccInitialized and headerText) then
        pendingTipKey = bindKey or false
        return
    end
    UnregisterStateDriver(headerText, "cui_tipmod")
    headerText:SetAttribute("cui_tipmod_key", bindKey)
    if not bindKey then
        headerText:Execute([[
            if cui_tippeeked then cui_tippeeked:Show(); cui_tippeeked = nil end
        ]])
        return
    end
    headerText:SetAttribute(
        "_onstate-cui_tipmod",
        [[
        if newstate == "held" then
            local f = cui_hoverframe
            if f and not cui_tippeeked and f:GetAttribute("cui_tipeater") then
                cui_tippeeked = f
                f:Hide()
            end
        elseif cui_tippeeked then
            cui_tippeeked:Show()
            cui_tippeeked = nil
        end
    ]]
    )
    local cond = (bindKey == "control") and "ctrl" or bindKey
    RegisterStateDriver(headerText, "cui_tipmod", "[mod:" .. cond .. "] held; shown")
end

function mod.CC_RegisterFrame(widget)
    -- Records ownership (for a later enable) without touching click behavior.
    ownedFrames[widget] = true
    local clickDB = GetClickCastDB()
    if not (clickDB and clickDB.enabled) then
        -- OFF: defer to any other consumer via the global ClickCastFrames table
        -- without touching click attributes, so right-click stays Blizzard-default.
        AddFrameToClickCast(widget)
        return
    end
    if not ccInitialized then
        tinsert(regQueue, widget)
        return
    end
    if InCombatLockdown() then
        tinsert(regQueue, widget)
        return
    end
    DoRegisterFrame(widget)
end

function mod.CC_UnregisterFrame(widget)
    if InCombatLockdown() then
        tinsert(unregQueue, widget)
        return
    end
    DoUnregisterFrame(widget)
end

local function RegisterExternalFrame(widget)
    if not ccInitialized then
        tinsert(regQueue, widget)
        return
    end
    local clickDB = GetClickCastDB()
    -- Only touches external/Blizzard frames when BOTH enabled and allFrames
    -- (externalFrames already recorded the frame, so enabling later picks it up).
    if not clickDB or not clickDB.enabled or not clickDB.allFrames then
        return
    end
    if InCombatLockdown() then
        tinsert(regQueue, widget)
        return
    end
    DoRegisterFrame(widget)
end

-- Forward-declared (defined below) so CC_SetAllFrames can register the static
-- Blizzard list at runtime.
local RegisterBlizzardFrames

function mod.CC_SetAllFrames(enabled)
    local clickDB = GetClickCastDB()
    if not clickDB then
        return
    end
    clickDB.allFrames = enabled
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    if enabled then
        -- Grabs the static Blizzard list + installs the CompactUnitFrame hook.
        -- Idempotent (self-gates, skips already-registered, hook installs once).
        if RegisterBlizzardFrames then
            RegisterBlizzardFrames()
        end
        for widget in pairs(externalFrames) do
            if not registeredFrames[widget] and not ownedFrames[widget] then
                DoRegisterFrame(widget)
            end
        end
        mod.CC_ApplyBindings()
    else
        for widget in pairs(registeredFrames) do
            if not ownedFrames[widget] then
                DoUnregisterFrame(widget)
            end
        end
    end
end

function mod.CC_SetDownClick(enabled)
    local clickDB = GetClickCastDB()
    if not clickDB then
        return
    end
    clickDB.downClick = enabled
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    local dir = enabled and "AnyDown" or "AnyUp"
    for widget in pairs(registeredFrames) do
        if widget.RegisterForClicks then
            widget:RegisterForClicks(dir)
        end
    end
end

-- ClickCastFrames hook
local function SetupClickCastFramesHook()
    -- Installs exactly once, only after the user enables (CC_Init/CC_SetEnabled),
    -- so a fresh disabled install never replaces the global table or perturbs others.
    if ccHookInstalled then
        return
    end
    ccHookInstalled = true
    local oldCCF = ClickCastFrames
    ClickCastFrames = setmetatable({}, {
        __newindex = function(t, widget, value)
            if value == nil or value == false then
                externalFrames[widget] = nil
                if not ownedFrames[widget] then
                    mod.CC_UnregisterFrame(widget)
                end
            else
                externalFrames[widget] = true
                if not ownedFrames[widget] then
                    RegisterExternalFrame(widget)
                end
            end
        end,
        __index = function(t, widget)
            return registeredFrames[widget] or nil
        end,
    })
    if oldCCF then
        for widget, val in pairs(oldCCF) do
            if val then
                externalFrames[widget] = true
                if not ownedFrames[widget] then
                    RegisterExternalFrame(widget)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Apply bindings to all registered frames + global button
-------------------------------------------------------------------------------
local prevBindings = {}

-- Writes a plan on every registered frame and the bind proxy: the previous
-- apply's keys come off first, then each frame binding, the Command-click
-- routes and the unbound-click defaults go on.
local function RepaintFrames(layoutPlan, bindList)
    -- The previous apply's mouse-button keys, parsed once for every frame.
    local prevClicks = {}
    for _, pb in ipairs(prevBindings) do
        if IsFrameBinding(pb.b) then
            local parsedMacro = ParseKeyString(pb.b.key)
            if UsesDirectClickAttributes(parsedMacro) then
                prevClicks[#prevClicks + 1] = parsedMacro
            end
        end
    end
    for widget in pairs(registeredFrames) do
        for i = 1, #prevClicks do
            ClearClickAttr(widget, prevClicks[i])
        end
        ClearKeyAttrs(widget, lastBindingCount)
    end
    ClearKeyAttrs(bindProxy, lastBindingCount)

    for widget in pairs(registeredFrames) do
        for i = 1, #layoutPlan do
            local planRec = layoutPlan[i]
            if planRec.frame and planRec.aType then
                if planRec.direct then
                    SetClickAttr(widget, planRec.parsed, planRec.aType, planRec.spellName, planRec.macrotext, planRec.b.oocOnly)
                else
                    SetKeyAttr(widget, i, planRec.aType, planRec.spellName, planRec.macrotext, planRec.b.oocOnly)
                end
            end
        end
        ConfigureCommandClicks(widget, bindList)
        -- Re-neutralize unbound left/right defaults (the clear pass above may
        -- have stripped a previous binding's type<N>).
        NeutralizeDefaultClicks(widget, layoutPlan)
    end
    -- Bind proxy gets keyboard attrs too (unnamed frame fallback)
    for i = 1, #layoutPlan do
        local planRec = layoutPlan[i]
        if planRec.frame and planRec.aType and not planRec.direct then
            SetKeyAttr(bindProxy, i, planRec.aType, planRec.spellName, planRec.macrotext, planRec.b.oocOnly)
        end
    end
end

-- The bound macros as the last apply read them: for each macro binding, the
-- macro it finds (its index, or "-" while none matches) and that macro's body.
-- Empty while no active binding is a macro. UPDATE_MACROS re-applies only
-- when this changes, so an edit to a macro no binding uses costs one read.
local macroSig = ""
local macroParts = {}
local function MacroSignature(bindList)
    wipe(macroParts)
    for _, bind in ipairs(bindList) do
        if bind.type == "macro" then
            local position = GetBindingMacroIndex(bind)
            macroParts[#macroParts + 1] = position and (position .. "\30" .. (GetMacroBody(position) or ""))
                or "-"
        end
    end
    return table.concat(macroParts, "\31")
end

function mod.CC_ApplyBindings()
    if not ccInitialized then
        pendingApply = true
        return
    end
    if InCombatLockdown() then
        pendingApply = true
        return
    end

    -- Self-heals non-canonical modifier-order keys before reading active set
    -- (so GetActiveBindings' de-dup also sees canonical keys).
    NormalizeSavedBindingKeys()
    wipe(clearMemo)

    local bindList = GetActiveBindings()
    -- Fresh list becomes the burst list: any registration later this frame
    -- reads the post-write set.
    burst.at, burst.list = GetTime(), bindList

    knownSig = ComputeKnownSignature()
    if knownSig ~= "" then
        eventHost:RegisterEvent("SPELLS_CHANGED")
    else
        eventHost:UnregisterEvent("SPELLS_CHANGED")
    end
    if watchCommandDemon then
        eventHost:RegisterUnitEvent("UNIT_PET", "player")
    else
        eventHost:UnregisterEvent("UNIT_PET")
    end

    -- Combat rez item: bags are watched only for a class with no battle rez
    -- that has a Dynamic Rez or Smart Rez binding.
    local wantRezItem = false
    if REZ_ITEMS[1] then
        local _, playerClass = UnitClass("player")
        local rezKit = REZ_BY_CLASS[playerClass]
        if not (rezKit and rezKit.battle) then
            for _, bind in ipairs(bindList) do
                if bind.type == "dynamicrez" or bind.smartRez then
                    wantRezItem = true
                    break
                end
            end
        end
    end
    rezItemID = wantRezItem and CarriedRezItem() or nil
    if wantRezItem then
        eventHost:RegisterEvent("BAG_UPDATE_DELAYED")
    else
        eventHost:UnregisterEvent("BAG_UPDATE_DELAYED")
    end

    -- A macro binding carries a copy of its macro's text, so macros are watched
    -- only while an active binding is one: an edit, rename or delete re-applies.
    macroSig = MacroSignature(bindList)
    if macroSig ~= "" then
        eventHost:RegisterEvent("UPDATE_MACROS")
    else
        eventHost:UnregisterEvent("UPDATE_MACROS")
    end

    -- A "both" binding is a frame binding AND a hover binding: frame attributes
    -- for clicks on the frames, plus the hover override for nameplates / world
    -- units.
    local layoutPlan = ResolvePlan(bindList)
    local sig = PlanSignature(layoutPlan)
    burst.planList, burst.plan, burst.sig = bindList, layoutPlan, sig
    -- The frames already carry this plan unless it differs from the last apply's
    -- or a registration painted another: a spell swap that hands a key to a
    -- binding casting the same base spell (Holy Armaments flips which of its
    -- pair is known) repaints no frame. The header part below always runs: its
    -- teardown also clears override bindings a loading screen left set (the
    -- PLAYER_ENTERING_WORLD re-apply).
    if sig ~= appliedSig or regDrift then
        RepaintFrames(layoutPlan, bindList)
    end

    local enterScript, leaveScript, kbClearLines = GenerateKeyBindSnippets(bindList)
    headerText:SetAttribute("cui_setup_onenter", enterScript)
    headerText:SetAttribute("cui_setup_onleave", leaveScript)

    ---------------------------------------------------------------
    -- Hovercast + frame keyboard failsafe, unified on ONE header state driver
    -- (cui_cc, [@mouseover,exists]). Override is SET instantly on the frame's
    -- OnEnter (cui_hover_set) so a keypress on arrival never loses the race; the
    -- driver ALSO sets on "on" (covers non-CUI targets like nameplates with no
    -- OnEnter wrap) and on "off" clears + runs the keyboard failsafe, GUARDED
    -- so a transient exists==0 flicker (common in follower dungeons) while the
    -- last-hovered frame is still under the cursor can't strand it cleared.
    -- cui_hoveractive gates SetBindingClick to the become-active edge only
    -- (zero extra writes on mouse sweep). globalBtn's macro re-evaluates at
    -- cast time, so a press fires on whatever's hovered.
    ---------------------------------------------------------------
    -- Retires the previous driver(s) and wipes prior override bindings
    -- (teardown also resets cui_hoveractive), then rebuilds.
    UnregisterStateDriver(headerText, "cui_cc")
    UnregisterStateDriver(headerText, "cui_fbs") -- legacy: split failsafe driver
    UnregisterStateDriver(hoverCastBtn, "cui_mo") -- legacy: globalBtn hover driver
    if headerText._ccClearScript then
        pcall(function()
            headerText:Execute(headerText._ccClearScript)
        end)
    end
    ClearHoverAttrs(hoverCastBtn, lastHoverCount)

    local hoverSetLines = {}
    local hoverClearLines = {}
    local gbName = hoverCastBtn:GetName()

    local hi = 0
    for i = 1, #layoutPlan do
        local planRec = layoutPlan[i]
        if planRec.hover then
            hi = hi + 1
            local btnSuffix = "cui_hc_" .. hi
            local aType = planRec.aType
            if aType then
                local mt = planRec.hoverMT
                if mt then
                    hoverCastBtn:SetAttribute("type-" .. btnSuffix, "macro")
                    hoverCastBtn:SetAttribute("macrotext-" .. btnSuffix, mt)
                else
                    -- menu/target carry no macro conditional, so honor oocOnly via
                    -- the combat driver (present out of combat, cleared in combat).
                    SetGatedType(
                        hoverCastBtn,
                        "type-" .. btnSuffix,
                        aType,
                        planRec.b.oocOnly and (aType == "togglemenu" or aType == "target")
                    )
                end
                hoverCastBtn:SetAttribute("unit-" .. btnSuffix, "mouseover")
                -- Routes the key/button to the global button for EVERY action type
                -- (not just spell/macro): the global button is a SecureActionButton,
                -- which the 12.0.7 SecureUnitButton menu gate does NOT touch, so
                -- togglemenu/target work here once the click is routed to it.
                hoverSetLines[#hoverSetLines + 1] =
                    string.format([[self:SetBindingClick(true, %q, %q, %q)]], planRec.b.key, gbName, btnSuffix)
                hoverClearLines[#hoverClearLines + 1] = string.format([[self:ClearBinding(%q)]], planRec.b.key)
            end
        end
    end

    -- Hover set/clear bodies: stored as header attributes, invoked via
    -- RunAttribute from both the OnEnter wrap and the state driver, so they
    -- always run with self=header (owner of the override bindings).
    headerText:SetAttribute("cui_hover_set", table.concat(hoverSetLines, "\n"))
    headerText:SetAttribute("cui_hover_clear", table.concat(hoverClearLines, "\n"))

    -- Teardown (next rebuild): self:ClearBindings() wipes every override this
    -- header owns in one shot (safe -- they re-establish on next hover). A
    -- per-key list is fragile: when the LAST binding is unbound the state driver
    -- isn't re-registered (gate below), so it could miss an override still
    -- active from an in-progress hover, stuck firing until /reload.
    headerText._ccClearScript = "self:ClearBindings()\neui_hoveractive = false"

    if #hoverSetLines > 0 or #kbClearLines > 0 then
        local fbFailsafe = table.concat(kbClearLines, "\n")
        headerText:SetAttribute("_onstate-cui_cc", [[
            if newstate == "on" then
                if not cui_hoveractive then
                    self:RunAttribute("cui_hover_set")
                    cui_hoveractive = true
                end
            elseif not (cui_hoverframe and cui_hoverframe:IsUnderMouse()) then
                self:RunAttribute("cui_hover_clear")
                cui_hoveractive = false
                ]] .. fbFailsafe .. [[

            end
        ]])
        -- State values are deliberately non-numeric: Blizzard's driver coerces
        -- with tonumber(newValue) or newValue, so a "1; 0" driver would arrive as
        -- NUMBER 1 and never match quoted "1" -- leaving nameplates (whose only
        -- path is this driver) permanently unbound.
        RegisterStateDriver(headerText, "cui_cc", "[@mouseover,exists] on; off")
    end

    lastBindingCount = #bindList
    lastHoverCount = hi
    prevBindings = {}
    for i, bind in ipairs(bindList) do
        prevBindings[i] = { b = bind, idx = i }
    end
    appliedSig, appliedList, regDrift = sig, bindList, false
end

-------------------------------------------------------------------------------
--  Binding CRUD
-------------------------------------------------------------------------------
function mod.CC_AddSpecBinding(bindRec)
    local clickDB = GetClickCastDB()
    if not clickDB then
        return
    end
    local specID = GetCurrentSpecID()
    if not specID then
        return
    end
    if not clickDB.specs[specID] then
        clickDB.specs[specID] = {}
    end
    if bindRec.enabled == nil then
        bindRec.enabled = true
    end
    tinsert(clickDB.specs[specID], bindRec)
    mod.CC_ApplyBindings()
end

function mod.CC_RemoveSpecBinding(index)
    local clickDB = GetClickCastDB()
    if not clickDB then
        return
    end
    local specID = GetCurrentSpecID()
    if not specID or not clickDB.specs[specID] then
        return
    end
    tremove(clickDB.specs[specID], index)
    mod.CC_ApplyBindings()
end

function mod.CC_AddGlobalBinding(bindRec)
    local clickDB = GetClickCastDB()
    if not clickDB then
        return
    end
    if bindRec.enabled == nil then
        bindRec.enabled = true
    end
    tinsert(clickDB.globals, bindRec)
    mod.CC_ApplyBindings()
end

function mod.CC_RemoveGlobalBinding(index)
    local clickDB = GetClickCastDB()
    if not clickDB then
        return
    end
    tremove(clickDB.globals, index)
    mod.CC_ApplyBindings()
end

-- Expose getters
mod.CC_GetActiveBindings = GetActiveBindings
mod.CC_GetSpecBindings = GetSpecBindings
mod.CC_GetGlobalBindings = GetGlobalBindings
mod.CC_GetCurrentSpecID = GetCurrentSpecID
mod.CC_GetCurrentSpecName = GetCurrentSpecName
mod.CC_GetCurrentSpecIcon = GetCurrentSpecIcon
mod.CC_GetClickCastDB = GetClickCastDB

-- Bindings only compete when their key is dispatched through at least one of
-- the same paths. Frame-only and hover-only bindings may therefore share a key;
-- a "both" binding overlaps either path.
local function BindingsShareCastPath(one, other)
    return (IsFrameBinding(one) and IsFrameBinding(other)) or (IsHoverBinding(one) and IsHoverBinding(other))
end

-- Calls fn for every OTHER active binding sharing the key and cast path, over
-- the globals and the active spec only (other specs are never active at the
-- same time). fn returning true stops the walk; returns whether it stopped.
local function ForEachKeySharer(excludeBinding, func)
    local keyText = excludeBinding.key
    local clickDB = keyText and GetClickCastDB()
    if not clickDB then
        return false
    end
    for _, bind in ipairs(clickDB.globals) do
        if
            bind ~= excludeBinding
            and IsBindingActive(bind)
            and bind.key == keyText
            and BindingsShareCastPath(excludeBinding, bind)
            and func(bind)
        then
            return true
        end
    end
    local specID = GetCurrentSpecID()
    local activeList = specID and clickDB.specs[specID]
    if activeList then
        for _, bind in ipairs(activeList) do
            if
                bind ~= excludeBinding
                and IsBindingActive(bind)
                and bind.key == keyText
                and BindingsShareCastPath(excludeBinding, bind)
                and func(bind)
            then
                return true
            end
        end
    end
    return false
end

-- Finds all bindings (excluding the given one) sharing a key and a cast path;
-- returns a list of names or an empty table. A spell the character has not got
-- never owns the key, so it neither raises nor receives a conflict.
local function FindKeyConflicts(keyText, excludeBinding)
    if not keyText or not IsBindingKnown(excludeBinding) then
        return {}
    end
    local conflicts = {}
    ForEachKeySharer(excludeBinding, function(bind)
        if not mod.CC_AreComplementaryReactionBindings(excludeBinding, bind) and IsBindingKnown(bind) then
            -- A pinned WoW Forever rank is listed with its rank.
            local rank = mod.CC_GetBindingRankText(bind)
            conflicts[#conflicts + 1] = rank and (mod.CC_GetBindingName(bind) .. " (" .. rank .. ")")
                or mod.CC_GetBindingName(bind)
        end
    end)
    return conflicts
end

-- An untalented spell only dims when another binding shares its key: that is
-- the one that lost its key. Alone on a key it looks like any other binding.
local function AnyTrue()
    return true
end
local function IsShadowedBinding(bindRec)
    return not IsBindingKnown(bindRec) and ForEachKeySharer(bindRec, AnyTrue)
end

-------------------------------------------------------------------------------
--  Enable / disable sweep
-------------------------------------------------------------------------------
-- Registers the Blizzard default unit frames + party pool + dynamic raid frames.
-- Self-gated on enabled+allFrames (via RegisterExternalFrame); the CompactUnitFrame
-- hook installs at most once.
local blizzHookInstalled = false
-- Assigns to the forward-declared upvalue above (so CC_SetAllFrames can call it).
function RegisterBlizzardFrames()
    local clickDB = GetClickCastDB()
    if not (clickDB and clickDB.enabled and clickDB.allFrames) then
        return
    end
    local blizzNames = {
        "PlayerFrame",
        "TargetFrame",
        "TargetFrameToT",
        "FocusFrame",
        "FocusFrameToT",
        "PetFrame",
    }
    for i = 1, 5 do
        blizzNames[#blizzNames + 1] = "Boss" .. i .. "TargetFrame"
    end
    for _, label in ipairs(blizzNames) do
        local frameRef = _G[label]
        if frameRef then
            externalFrames[frameRef] = true
            RegisterExternalFrame(frameRef)
        end
    end
    if PartyFrame and PartyFrame.PartyMemberFramePool then
        for mf in PartyFrame.PartyMemberFramePool:EnumerateActive() do
            externalFrames[mf] = true
            RegisterExternalFrame(mf)
            if mf.PetFrame then
                externalFrames[mf.PetFrame] = true
                RegisterExternalFrame(mf.PetFrame)
            end
        end
    end
    -- CompactUnitFrames (Blizzard raid frames) are created dynamically; the hook
    -- installs once and self-gates via RegisterExternalFrame (enabled+allFrames).
    if not blizzHookInstalled and CompactUnitFrame_SetUpFrame then
        blizzHookInstalled = true
        hooksecurefunc("CompactUnitFrame_SetUpFrame", function(widget)
            if not widget then
                return
            end
            if widget.IsForbidden and widget:IsForbidden() then
                return
            end
            -- Frames the raid module parked under its hidden parent (the whole
            -- CompactRaidFrameContainer, the raid-style party members) can never
            -- be clicked, yet Blizzard re-runs SetUpFrame on every one of them
            -- for every roster change -- a full binding pass per hidden frame
            -- per roster event, all wasted. Skip them; a frame that later leaves
            -- the hidden parent registers on its next SetUpFrame.
            local hiddenParent = mod._blizzHiddenParent
            if hiddenParent then
                local p, depth = widget:GetParent(), 0
                while p and depth < 6 do
                    if p == hiddenParent then
                        return
                    end
                    p = p:GetParent()
                    depth = depth + 1
                end
            end
            local success, label = pcall(widget.GetName, widget)
            if success and label and not label:match("^NamePlate") then
                externalFrames[widget] = true
                RegisterExternalFrame(widget)
            end
        end)
    end
end

-- Toggles click-casting with a full register/restore sweep: enabling installs
-- the global hook + registers owned/external frames; disabling returns EVERY
-- touched frame to native click behavior (right-click never left broken).
-- Defers to PLAYER_REGEN_ENABLED in combat.
function mod.CC_SetEnabled(enabled)
    local clickDB = GetClickCastDB()
    if not clickDB then
        return
    end
    clickDB.enabled = enabled
    if not ccInitialized then
        return
    end
    if InCombatLockdown() then
        pendingSetEnabled = enabled
        pendingApply = true
        return
    end
    if enabled then
        -- Hand owned frames back to any other consumer before taking over, so it
        -- drops its bindings and we don't double-bind. Must run BEFORE the proxy
        -- replaces the global table (RemoveFrameFromClickCast no-ops once it has).
        for widget in pairs(ownedFrames) do
            RemoveFrameFromClickCast(widget)
        end
        SetupClickCastFramesHook()
        SyncTipEaters()
        for widget in pairs(ownedFrames) do
            if not registeredFrames[widget] then
                DoRegisterFrame(widget)
            end
        end
        if clickDB.allFrames then
            RegisterBlizzardFrames()
            for widget in pairs(externalFrames) do
                if not registeredFrames[widget] and not ownedFrames[widget] then
                    DoRegisterFrame(widget)
                end
            end
        end
        mod.CC_ApplyBindings()
    else
        -- Clears applied attributes first (CC_ApplyBindings uses the last-applied
        -- set), then reverts every frame to native (type1/type2, AnyUp, wheel, wraps).
        mod.CC_ApplyBindings()
        local entries = {}
        for widget in pairs(registeredFrames) do
            entries[#entries + 1] = widget
        end
        for _, widget in ipairs(entries) do
            DoUnregisterFrame(widget)
        end
        -- The unregister above dropped the eaters' wraps with everyone else's;
        -- the peek needs them back even with click-casting off.
        SyncTipEaters()
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
-- Spec data can lag PLAYER_ENTERING_WORLD by a few frames at login; applying
-- bindings too early drops SPEC-scoped bindings to GLOBAL with nothing to
-- re-apply them (PLAYER_SPECIALIZATION_CHANGED doesn't fire on plain login).
-- Polls until GetCurrentSpecID resolves, then reapplies; safe with no spec
-- (cap stops the poll; a later spec pick fires the event instead).
local specReadyTicker
local function ReapplyWhenSpecReady()
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    -- WoW Forever characters have no spec to wait for.
    if GetCurrentSpecID() or CludesUI.IS_FOREVER then
        mod.CC_ApplyBindings()
        return
    end
    -- Spec not ready: only start the readiness poll when enabled -- a disabled
    -- install has nothing to re-apply, so polling would be idle cost otherwise.
    local clickDB = GetClickCastDB()
    if not (clickDB and clickDB.enabled) then
        return
    end
    if specReadyTicker then
        return
    end
    local tries = 0
    specReadyTicker = C_Timer.NewTicker(0.25, function(t)
        tries = tries + 1
        if GetCurrentSpecID() then
            t:Cancel()
            specReadyTicker = nil
            if not InCombatLockdown() then
                mod.CC_ApplyBindings()
            else
                pendingApply = true
            end
        elseif tries >= 20 then -- ~5s safety cap: the char has no spec
            t:Cancel()
            specReadyTicker = nil
            -- Still apply: the global bindings do not need a spec (WoW Forever
            -- characters and low-level ones have none).
            if not InCombatLockdown() then
                mod.CC_ApplyBindings()
            else
                pendingApply = true
            end
        end
    end)
end

local function OnCCEvent(self, evt)
    if evt == "PLAYER_REGEN_ENABLED" then
        local clickDB = GetClickCastDB()
        -- Eater wraps first: DoRegisterFrame below must find them already wrapped.
        if pendingTipSync then
            pendingTipSync = false
            SyncTipEaters()
        end
        -- Apply a deferred enable/disable sweep that was requested during combat.
        if pendingSetEnabled ~= nil then
            local v = pendingSetEnabled
            pendingSetEnabled = nil
            mod.CC_SetEnabled(v)
        end
        local enabled = clickDB and clickDB.enabled
        local allF = clickDB and clickDB.allFrames
        for _, widget in ipairs(regQueue) do
            -- Never register while disabled (DoRegisterFrame also self-gates).
            if enabled and (ownedFrames[widget] or allF) then
                DoRegisterFrame(widget)
            end
        end
        wipe(regQueue)
        for _, widget in ipairs(unregQueue) do
            DoUnregisterFrame(widget)
        end
        wipe(unregQueue)
        if pendingApply then
            pendingApply = false
            mod.CC_ApplyBindings()
        end
    elseif evt == "PLAYER_SPECIALIZATION_CHANGED" then
        if not InCombatLockdown() then
            mod.CC_ApplyBindings()
        else
            pendingApply = true
        end
    elseif evt == "SPELLS_CHANGED" or evt == "UNIT_PET" then
        -- A talent or loadout swap that moved a bound spell in or out of the
        -- book; the apply re-resolves which binding owns each key.
        if ComputeKnownSignature() ~= knownSig then
            if not InCombatLockdown() then
                mod.CC_ApplyBindings()
            else
                pendingApply = true
            end
        end
    elseif evt == "BAG_UPDATE_DELAYED" then
        -- Re-applies only when the carried combat rez item changed.
        if CarriedRezItem() ~= rezItemID then
            if not InCombatLockdown() then
                mod.CC_ApplyBindings()
            else
                pendingApply = true
            end
        end
    elseif evt == "UPDATE_MACROS" then
        -- A macro was created, edited, renamed or deleted: re-applies only when a
        -- bound macro now resolves or reads differently.
        if MacroSignature(GetActiveBindings()) ~= macroSig then
            if not InCombatLockdown() then
                mod.CC_ApplyBindings()
            else
                pendingApply = true
            end
        end
    elseif evt == "GROUP_ROSTER_UPDATE" then
        -- Solo <-> party <-> raid transitions change which bindings are active.
        -- GROUP_ROSTER_UPDATE fires every join, leave, promote and zone-in, so
        -- only act when the context changed.
        local context = CurrentCtx()
        if context ~= lastRosterCtx then
            lastRosterCtx = context
            if not InCombatLockdown() then
                mod.CC_ApplyBindings()
            else
                pendingApply = true
            end
        end
    elseif evt == "PLAYER_ENTERING_WORLD" then
        -- Reapplies after zone/loading (OnLeave may not fire during transitions,
        -- so stuck frame-bindings need clearing); waits for spec via
        -- ReapplyWhenSpecReady so login doesn't drop spec-scoped bindings to global.
        ReapplyWhenSpecReady()
    end
end

-------------------------------------------------------------------------------
--  Init
-------------------------------------------------------------------------------
function mod.CC_Init()
    if ccInitialized then
        return
    end
    if not mod.db then
        return
    end
    GetClickCastDB()

    -- StateTemplate (not BaseTemplate): only it carries the OnAttributeChanged script
    -- (SecureHandler_StateOnAttributeChanged) that dispatches "_onstate-<id>" -- under
    -- BaseTemplate the driver would write the state but nothing listens, so hovercast
    -- would only work via the OnEnter wrap (everywhere except nameplates). Same
    -- SecureHandler_OnLoad, so Execute/ WrapScript/RunAttribute are unchanged.
    headerText = CreateFrame("Frame", "CUIClickCastHeader", UIParent, "SecureHandlerStateTemplate")
    mod._ccHeader = headerText

    bindProxy = CreateFrame(
        "Button",
        "CUIClickCastBindProxy",
        UIParent,
        "SecureActionButtonTemplate,SecureHandlerBaseTemplate"
    )
    bindProxy:RegisterForClicks("AnyDown", "AnyUp")
    bindProxy:SetSize(1, 1)
    bindProxy:SetAlpha(0)
    bindProxy:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
    bindProxy:Show()
    mod._ccBindProxy = bindProxy
    headerText:SetFrameRef("bindProxy", bindProxy)

    hoverCastBtn = CreateFrame(
        "Button",
        "CUIClickCastGlobalBtn",
        UIParent,
        "SecureActionButtonTemplate,SecureHandlerBaseTemplate"
    )
    hoverCastBtn:RegisterForClicks("AnyDown", "AnyUp")
    hoverCastBtn:EnableMouse(false)
    hoverCastBtn:SetSize(1, 1)
    hoverCastBtn:SetAlpha(0)
    hoverCastBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 100)
    hoverCastBtn:Show()
    mod._ccGlobalBtn = hoverCastBtn

    headerText:SetAttribute("cui_setup_onenter", "")
    headerText:SetAttribute("cui_setup_onleave", "")
    headerText:SetAttribute("cui_hover_set", "")
    headerText:SetAttribute("cui_hover_clear", "")

    -- Shell-pool adoption (ns.TakeShell, main file) so this frame's event tree
    -- bills to click-cast, not the parent addon's lifecycle dispatch.
    eventHost = (mod.TakeShell and mod.TakeShell()) or CreateFrame("Frame")
    eventHost:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- The player's own spec only: unfiltered, every group member's spec change
    -- re-applied every binding.
    eventHost:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    eventHost:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventHost:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventHost:SetScript("OnEvent", OnCCEvent)

    ccInitialized = true

    -- Tooltip-modifier eaters: wrapped whatever the enabled state (before the
    -- registration sweep below), and a key parked before init applies now.
    SyncTipEaters()
    if pendingTipKey ~= nil then
        local modKey = pendingTipKey
        pendingTipKey = nil
        mod.CC_SetTipModKey(modKey or nil)
    end

    -- Only touches frames when enabled: a fresh/default install registers
    -- nothing, so clicks stay Blizzard-default. Enabling later runs the same
    -- sweep via CC_SetEnabled.
    local clickDB = GetClickCastDB()
    if clickDB and clickDB.enabled then
        SetupClickCastFramesHook()
        for _, widget in ipairs(regQueue) do
            DoRegisterFrame(widget)
        end
        wipe(regQueue)
        mod.CC_ApplyBindings()
        RegisterBlizzardFrames()
    else
        wipe(regQueue)
    end
end

-------------------------------------------------------------------------------
--  Reused option surfaces: the three picker popups (Add Global Binding, Add
--  New, Quickbind) and the spell strip are built once per session and
--  re-dressed on every open or page build. Their icon cells are pooled by
--  index: a refill re-dresses the cells it needs and hides the rest.
-------------------------------------------------------------------------------
local ccPickers = {}

local function CC_GetActionItems()
    return {
        { type = "target", name = CludesUI.L("Target Unit"), icon = ACTION_ICONS.target },
        { type = "menu", name = CludesUI.L("Context Menu"), icon = ACTION_ICONS.menu },
    }
end

-- Picker grid cell i on child, made on first use: a button holding a 32px
-- icon and a hidden accent hover border (its label comes with its first use).
local function CC_PickerCell(childFrame, i, Pix, accent)
    local cells = childFrame._cells
    if not cells then
        cells = {}
        childFrame._cells = cells
    end
    local cellFrame = cells[i]
    if cellFrame then
        return cellFrame
    end
    cellFrame = CreateFrame("Button", nil, childFrame)
    local iconFr = CreateFrame("Frame", nil, cellFrame)
    iconFr:SetSize(32, 32)
    local iconTx = iconFr:CreateTexture(nil, "ARTWORK")
    iconTx:SetAllPoints()
    iconTx:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local iconEdgeFrame = CreateFrame("Frame", nil, iconFr)
    iconEdgeFrame:SetAllPoints()
    iconEdgeFrame:SetFrameLevel(iconFr:GetFrameLevel() + 1)
    iconEdgeFrame:Hide()
    if Pix then
        Pix.CreateBorder(iconEdgeFrame, accent.r, accent.g, accent.b, 1, 2)
    end
    cellFrame._icon, cellFrame._tex, cellFrame._bd = iconFr, iconTx, iconEdgeFrame
    cells[i] = cellFrame
    return cellFrame
end

-- Picker grid divider line above row r (r >= 1), made on first use.
local function CC_PickerDivider(childFrame, r, Pix)
    local divs = childFrame._divs
    if not divs then
        divs = {}
        childFrame._divs = divs
    end
    local divider = divs[r]
    if not divider then
        divider = childFrame:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(1, 1, 1, 0.06)
        if Pix then
            Pix.DisablePixelSnap(divider)
        end
        divs[r] = divider
    end
    return divider
end

-- Replays OnEnter on the first of cells 1..n that holds the mouse focus: a
-- cell reused in place keeps the focus, so it never gets the OnEnter a new
-- cell under the cursor would. Returns true when one did.
local function CC_ReplayFocusEnter(cells, num)
    local foci = GetMouseFoci and GetMouseFoci()
    if not (cells and foci) then
        return false
    end
    for modKey = 1, #foci do
        local frameRef = foci[modKey]
        for i = 1, num do
            if cells[i] == frameRef then
                local onEnter = frameRef:GetScript("OnEnter")
                if onEnter then
                    onEnter(frameRef)
                end
                return true
            end
        end
    end
    return false
end

-- Ends a picker refill of n cells over rows rows: hides the unused cells and
-- divider lines, then replays the focused cell's OnEnter.
local function CC_PickerFinish(childFrame, num, rowList)
    local cells = childFrame._cells
    if cells then
        for i = num + 1, #cells do
            cells[i]:Hide()
        end
    end
    local divs = childFrame._divs
    if divs then
        for r = max(rowList, 1), #divs do
            divs[r]:Hide()
        end
    end
    CC_ReplayFocusEnter(cells, num)
end

-------------------------------------------------------------------------------
--  Options Page Builder
--  Layout: Left sidebar (Global) | Center (Options + Per-Binding) | Right sidebar (Spec)
--  Sidebars are 1:1 replica of Buff Manager tile style.
-------------------------------------------------------------------------------
function mod.CC_BuildPage(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local saved = mod.db
    if not saved then
        return 0
    end
    -- Options page pool (CludesUI_FramePool.lua): everything below builds on
    -- the page's kept root, so the next render hands the same frames out again
    -- (in creation order) instead of making new ones. The session-wide picker
    -- popups and the spell strip hang from UIParent and the panel: plain new frames.
    local CreateFrame = POOL.CreateFrame
    -- A handler's own tail after a setter that renders the page again stops once
    -- its widget was dressed again (that render painted it, maybe as another row's).
    local PoolGen = POOL.Gen

    local clickDB = GetClickCastDB()
    if not clickDB then
        return 0
    end

    local fontFile = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
    local outlineFlag = (CludesUI.GetFontOutlineFlag("raidFrames")) or ""
    local useShadow = not CludesUI.GetFontUseShadow or CludesUI.GetFontUseShadow("raidFrames")
    local accentColor = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }

    -- The page root bypasses the scroll system (like BM does)
    local scrollFrame = CludesUI._scrollFrame
    if not scrollFrame then
        return 0
    end
    local visibleH = scrollFrame:GetHeight()
    local parentW = scrollFrame:GetWidth()

    -- The refreshers this render registers replace the previous render's (it
    -- runs outside a page pass too: RebuildPage, the deferred renders).
    CludesUI._BeginRootRender("rf.cc")
    if mod._ccGridPopup then
        mod._ccGridPopup:Hide()
        mod._ccGridPopup = nil
    end
    if mod._ccSpecPopup then
        mod._ccSpecPopup:Hide()
        mod._ccSpecPopup = nil
    end
    -- QB popup is NOT cleaned up here -- it stays open during rebuilds
    -- The spell strip (parented to the panel) is re-dressed further down.
    if mod._ccSpellStrip then
        mod._ccSpellStrip:Hide()
    end

    -- One root for the session (the options page pool): every render dresses
    -- it again, and its reset is the previous render's teardown.
    local root = POOL.Kept(mod, "ccRoot", "Frame", scrollFrame)
    root:SetSize(parentW, visibleH)
    root:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    root:SetFrameLevel(scrollFrame:GetFrameLevel() + 1)
    mod._ccRoot = root

    local TILE_H = 56
    local ICON_SZ = 36
    local ADD_BTN_H = 30
    local ADD_BTN_PAD = 10
    local SPELL_STRIP_W = 57 -- narrow spell icon strip (outside the root, on CUI window edge)
    -- One bindings column on the left (Global over Spec), the options right of it.
    local SIDEBAR_PCT = 0.30
    local COL_GAP = 12
    local sidebarW = floor(parentW * SIDEBAR_PCT)
    local centerW = parentW - sidebarW - COL_GAP
    local globalH = floor((visibleH - COL_GAP) * 0.5)

    -- The page in the options panel's card style. CC.Button: a square
    -- button, dark with an accent outline and accent text (primary) or a grey
    -- outline (secondary), a faint wash on hover. CC.Sidebar: a sidebar as a
    -- card with a heading band (title left, binding count right). CC.Card:
    -- a card behind a centre section, from its heading down to bottomY.
    local CC = {}
    function CC.Button(btn, backdrop, labelFS, primary)
        local red, green, blue = 1, 1, 1
        if primary then
            red, green, blue = accentColor.r, accentColor.g, accentColor.b
        end
        local rest, lit = primary and 0.7 or 0.22, primary and 1 or 0.45
        backdrop:SetColorTexture(red, green, blue, 0.06)
        labelFS:SetTextColor(red, green, blue, primary and 1 or 0.8)
        labelFS:SetAlpha(1)
        local brd = CludesUI.MakeRoundedBorder(btn, red, green, blue, rest, backdrop, 2)
        btn:SetScript("OnEnter", function()
            backdrop:SetColorTexture(red, green, blue, 0.14)
            brd:SetColor(red, green, blue, lit)
        end)
        btn:SetScript("OnLeave", function()
            backdrop:SetColorTexture(red, green, blue, 0.06)
            brd:SetColor(red, green, blue, rest)
        end)
    end
    local function Edge(host, layer, a)
        local texture = host:CreateTexture(nil, layer)
        texture:SetColorTexture(1, 1, 1, a)
        return texture
    end
    function CC.Sidebar(outer, backdrop, headerText, total)
        backdrop:SetColorTexture(1, 1, 1, 0.025)
        local band = Edge(outer, "BACKGROUND", 0.035)
        band:SetPoint("TOPLEFT")
        band:SetPoint("TOPRIGHT")
        band:SetHeight(38)
        local divider = Edge(outer, "ARTWORK", 0.10)
        divider:SetPoint("TOPLEFT", 0, -38)
        divider:SetPoint("TOPRIGHT", 0, -38)
        divider:SetHeight(1)
        local cap = outer:CreateTexture(nil, "ARTWORK")
        cap:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.9)
        cap:SetPoint("TOPLEFT")
        cap:SetPoint("TOPRIGHT")
        cap:SetHeight(2)
        for _, side in ipairs({ "LEFT", "RIGHT" }) do
            local e = Edge(outer, "ARTWORK", 0.10)
            e:SetPoint("TOP" .. side)
            e:SetPoint("BOTTOM" .. side)
            e:SetWidth(1)
        end
        headerText:ClearAllPoints()
        headerText:SetPoint("LEFT", outer, "TOPLEFT", 14, -19)
        headerText:SetText(headerText:GetText():upper())
        headerText:SetTextColor(1, 1, 1, 1)
        local num = CludesUI.MakeFont(outer, 11, nil, 1, 1, 1, 0.45)
        num:SetPoint("RIGHT", outer, "TOPRIGHT", -14, -19)
        num:SetText(tostring(total))
    end
    function CC.Card(host, posX, topY, wid, bottomY)
        local macroBody = Edge(host, "BACKGROUND", 0.025)
        macroBody:SetPoint("TOPLEFT", host, "TOPLEFT", posX, topY)
        macroBody:SetSize(wid, topY - bottomY)
        local band = Edge(host, "BACKGROUND", 0.035)
        band:SetPoint("TOPLEFT", macroBody, "TOPLEFT")
        band:SetPoint("TOPRIGHT", macroBody, "TOPRIGHT")
        band:SetHeight(34)
        local pieces = {
            { "TOPLEFT", "TOPRIGHT", 0, 1 },
            { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
        }
        for _, pc in ipairs(pieces) do
            local e = Edge(host, "ARTWORK", 0.10)
            e:SetPoint(pc[1], macroBody, pc[1])
            e:SetPoint(pc[2], macroBody, pc[2])
            e:SetHeight(1)
        end
        local divider = Edge(host, "ARTWORK", 0.10)
        divider:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
        divider:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")
        divider:SetHeight(1)
        for _, side in ipairs({ "LEFT", "RIGHT" }) do
            local e = Edge(host, "ARTWORK", 0.10)
            e:SetPoint("TOP" .. side, macroBody, "TOP" .. side)
            e:SetPoint("BOTTOM" .. side, macroBody, "BOTTOM" .. side)
            e:SetWidth(1)
        end
    end

    -- StyleFont dresses a font string the way MakeFont makes one; the reused
    -- picker strings are re-dressed with it on every open.
    local function StyleFont(fontStr, size, red, green, blue, a)
        CludesUI.PrimeFontShadow(fontStr, outlineFlag == "" and useShadow)
        fontStr:SetFont(fontFile, size, outlineFlag)
        fontStr:SetTextColor(red or 1, green or 1, blue or 1, a or 1)
    end
    local function NewLabel(p, size, red, green, blue, a)
        local fontStr = p:CreateFontString(nil, "OVERLAY")
        StyleFont(fontStr, size, red, green, blue, a)
        return fontStr
    end

    -- Dresses pooled picker cell i of child for one grid slot the way a new
    -- cell starts: icon (dimmed when already bound), hidden hover border, and
    -- the label (text; nil when its row has none) lblGap above the icon.
    -- Returns the cell, its hover border and its label.
    local function DressPickerCell(
        childFrame,
        i,
        posX,
        posY,
        wid,
        hgt,
        icon,
        dimmed,
        textValue,
        lblSize,
        lblGap
    )
        local cellFrame = CC_PickerCell(childFrame, i, Pix, accentColor)
        cellFrame:SetSize(wid, hgt)
        cellFrame:ClearAllPoints()
        cellFrame:SetPoint("TOPLEFT", childFrame, "TOPLEFT", posX, posY)
        cellFrame:Show()
        local iconFr, iconTx, iconEdgeFrame = cellFrame._icon, cellFrame._tex, cellFrame._bd
        iconTx:SetTexture(icon or 134400)
        iconTx:SetAlpha(dimmed and 0.3 or 1)
        iconEdgeFrame:Hide()
        if Pix then
            Pix.SetBorderColor(iconEdgeFrame, accentColor.r, accentColor.g, accentColor.b, 1)
        end
        iconFr:ClearAllPoints()
        local labelFS = cellFrame._lbl
        if textValue then
            if labelFS then
                StyleFont(labelFS, lblSize, 1, 1, 1, dimmed and 0.3 or 0.7)
            else
                labelFS = NewLabel(cellFrame, lblSize, 1, 1, 1, dimmed and 0.3 or 0.7)
                cellFrame._lbl = labelFS
            end
            labelFS:SetAlpha(1)
            labelFS:ClearAllPoints()
            labelFS:SetPoint("TOP", cellFrame, "TOP", 0, 0)
            labelFS:SetWidth(wid + 4)
            labelFS:SetJustifyH("CENTER")
            labelFS:SetWordWrap(false)
            labelFS:SetText(textValue)
            labelFS:Show()
            iconFr:SetPoint("TOP", labelFS, "BOTTOM", 0, -lblGap)
            return cellFrame, iconEdgeFrame, labelFS
        end
        if labelFS then
            labelFS:Hide()
        end
        iconFr:SetPoint("TOP", cellFrame, "TOP", 0, 0)
        return cellFrame, iconEdgeFrame, nil
    end

    -- Selected binding state (persists across rebuilds via namespace)
    local pickedBinding = nil
    local selectedSide = mod._ccSelSide
    local selectedIndex = mod._ccSelIndex
    if selectedSide == "global" and selectedIndex then
        pickedBinding = clickDB.globals[selectedIndex]
    elseif selectedSide == "spec" and selectedIndex then
        local scrollBar = GetSpecBindings()
        pickedBinding = scrollBar[selectedIndex]
    end

    -- Lookup sets for already-bound spells/macros/items (used to dim in popups + strip)
    local boundSpells, boundMacros, boundItems = {}, {}, {}
    for _, bind in ipairs(GetGlobalBindings()) do
        if bind.spell then
            boundSpells[mod.CC_SpellBoundKey(bind.spellID, bind.spell, bind.rankPinned)] = true
        end
        MarkBoundMacro(boundMacros, bind)
        if bind.itemSlot then
            boundItems[bind.itemSlot] = true
        end
    end
    for _, bind in ipairs(GetSpecBindings()) do
        if bind.spell then
            boundSpells[mod.CC_SpellBoundKey(bind.spellID, bind.spell, bind.rankPinned)] = true
        end
        MarkBoundMacro(boundMacros, bind)
        if bind.itemSlot then
            boundItems[bind.itemSlot] = true
        end
    end
    local _, playerClass = UnitClass("player")
    local hasDispel, hasExternal, hasDynamicRez = false, false, false
    for _, gb in ipairs(GetGlobalBindings()) do
        if gb.enabled and gb.key then
            if gb.type == "dispel" then
                hasDispel = true
            end
            if gb.type == "external" then
                hasExternal = true
            end
            if gb.type == "dynamicrez" then
                hasDynamicRez = true
            end
        end
    end
    if hasDispel then
        for _, spellRec in ipairs(DispelPresetSpells(playerClass)) do
            -- Matches the localized name stored by the spell picker, so
            -- "already bound" dimming works on non-English clients.
            local num = (C_Spell.GetSpellName and C_Spell.GetSpellName(spellRec.id)) or spellRec.name
            boundSpells[num] = true
        end
    end
    if hasExternal then
        for _, spellRec in ipairs(ClassPresetSpells(EXTERNAL_SPELLS, playerClass)) do
            local num = (C_Spell.GetSpellName and C_Spell.GetSpellName(spellRec.id)) or spellRec.name
            boundSpells[num] = true
        end
    end
    if hasDynamicRez then
        local rezKit = REZ_BY_CLASS[playerClass]
        if rezKit then
            for _, slot in pairs(rezKit) do
                -- Every rank of a slot shares one name.
                local spellRef = type(slot) == "table" and slot[1] or slot
                local label = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellRef)
                if label then
                    boundSpells[label] = true
                end
            end
        end
    end

    -- Keybind capture button builder (Party Mode pattern).
    local function BuildKeybindButton(parentFrame, width, getCurrentKey, onKeySet, onKeyClear)
        local KB_H = 30
        local keybindBtn = CreateFrame("Button", nil, parentFrame)
        keybindBtn:SetSize(width, KB_H)
        keybindBtn:SetFrameLevel(parentFrame:GetFrameLevel() + 2)
        keybindBtn:RegisterForClicks("AnyUp")
        local kbBg = CludesUI.SolidTex(
            keybindBtn,
            "BACKGROUND",
            CludesUI.DD_BG_R,
            CludesUI.DD_BG_G,
            CludesUI.DD_BG_B,
            CludesUI.DD_BG_A
        )
        kbBg:SetAllPoints()
        keybindBtn._border = CludesUI.MakeRoundedBorder(keybindBtn, 1, 1, 1, CludesUI.DD_BRD_A, kbBg)
        local kbLbl = CludesUI.MakeFont(keybindBtn, 13, nil, 1, 1, 1)
        kbLbl:SetAlpha(CludesUI.DD_TXT_A)
        kbLbl:SetPoint("CENTER")

        local listening = false
        local function RefreshLabel()
            local bindKey = getCurrentKey and getCurrentKey()
            kbLbl:SetText(bindKey and mod.CC_FormatKey(bindKey) or CludesUI.L("Not Bound"))
        end
        RefreshLabel()

        -- Stops capturing: disables keyboard + wheel so the page scrolls
        -- normally again.
        local function StopListening()
            listening = false
            keybindBtn:EnableKeyboard(false)
            keybindBtn:EnableMouseWheel(false)
            RefreshLabel()
        end

        -- Runs a key setter; false once it rendered the page again: that
        -- render dressed this button again (maybe as another row's), painted
        -- it and dropped the capture (the row's OnHide below).
        local function SetKey(func, v)
            local gen = PoolGen(keybindBtn)
            if func then
                func(v)
            end
            return PoolGen(keybindBtn) == gen
        end

        keybindBtn:SetScript("OnClick", function(self, btnFrame)
            if not listening then
                if btnFrame == "LeftButton" then
                    listening = true
                    kbLbl:SetText(CludesUI.L("Press a key, click, or scroll..."))
                    keybindBtn:EnableKeyboard(true)
                    keybindBtn:EnableMouseWheel(true)
                elseif btnFrame == "RightButton" then
                    if SetKey(onKeyClear) then
                        RefreshLabel()
                    end
                end
                return
            end
            -- While listening, any click is a binding (including bare left-click).
            local mods = mod.CC_GetModifierPrefix()
            local normalized = MOUSE_BUTTON_MAP[btnFrame] or ("BUTTON" .. (btnFrame:match("%d+") or btnFrame))
            if SetKey(onKeySet, mods .. normalized) then
                StopListening()
            end
        end)

        keybindBtn:SetScript("OnKeyDown", function(self, bindKey)
            -- SetPropagateKeyboardInput is blocked in combat on every frame; the
            -- page closes as combat starts, so this stands aside like the
            -- Quickbind cells.
            if InCombatLockdown() then
                return
            end
            if not listening then
                self:SetPropagateKeyboardInput(true)
                return
            end
            if MODIFIER_KEYS[bindKey] then
                self:SetPropagateKeyboardInput(true)
                return
            end
            self:SetPropagateKeyboardInput(false)
            if bindKey == "ESCAPE" then
                StopListening()
                return
            end
            local captured = mod.CC_CaptureKey(bindKey)
            if not captured then
                return
            end
            if SetKey(onKeySet, captured) then
                StopListening()
            end
        end)

        -- Scroll-wheel binding only via this capture button (never Quickbind);
        -- wheel is enabled only while listening. MOUSEWHEELUP/DOWN bind through
        -- the keybind path (SetBindingClick), same as keyboard keys.
        keybindBtn:SetScript("OnMouseWheel", function(self, change)
            if not listening then
                return
            end
            local mods = mod.CC_GetModifierPrefix()
            local wheel = change > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
            if SetKey(onKeySet, mods .. wheel) then
                StopListening()
            end
        end)

        keybindBtn:SetScript("OnEnter", function(self)
            kbBg:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, CludesUI.DD_BG_HA)
            if keybindBtn._border and keybindBtn._border.SetColor then
                keybindBtn._border:SetColor(1, 1, 1, 0.3)
            end
            CludesUI.ShowWidgetTooltip(self, CludesUI.L("Left-click to set keybind.\nRight-click to clear."))
        end)
        keybindBtn:SetScript("OnLeave", function()
            if listening then
                return
            end
            kbBg:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, CludesUI.DD_BG_A)
            if keybindBtn._border and keybindBtn._border.SetColor then
                keybindBtn._border:SetColor(1, 1, 1, CludesUI.DD_BRD_A)
            end
            CludesUI.HideWidgetTooltip()
        end)

        parentFrame:SetScript("OnHide", function()
            if listening then
                StopListening()
            end
        end)

        keybindBtn._refresh = RefreshLabel
        return keybindBtn
    end

    -- Sidebar tile builder (BM replica).
    local function BuildTile(scrollChild, tileY, bindRec, isSelected, side, position, onSelect, onDelete)
        local tileFrame = CreateFrame("Button", nil, scrollChild)
        tileFrame:SetSize(sidebarW, TILE_H)
        tileFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, tileY)
        tileFrame:SetFrameLevel(scrollChild:GetFrameLevel() + 1)

        local tileBg = tileFrame:CreateTexture(nil, "BACKGROUND")
        tileBg:SetAllPoints()
        tileBg:SetColorTexture(1, 1, 1, isSelected and 0.06 or 0)

        if isSelected then
            local accent = tileFrame:CreateTexture(nil, "ARTWORK", nil, 2)
            accent:SetSize(2, TILE_H)
            accent:SetPoint("TOPLEFT", tileFrame, "TOPLEFT", 0, 0)
            accent:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1)
        end

        local iconFrame = CreateFrame("Frame", nil, tileFrame)
        iconFrame:SetSize(ICON_SZ, ICON_SZ)
        iconFrame:SetPoint("LEFT", tileFrame, "LEFT", 8, 0)
        local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTexture:SetAllPoints()
        iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconTexture:SetTexture(mod.CC_GetBindingIcon(bindRec))
        if Pix then
            local iBdr = CreateFrame("Frame", nil, iconFrame)
            iBdr:SetAllPoints()
            iBdr:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            Pix.CreateBorder(iBdr, 0, 0, 0, 0.6, 1)
        end

        local textX = 8 + ICON_SZ + 8
        local title = NewLabel(tileFrame, 13, 1, 1, 1, 1)
        title:SetPoint("TOPLEFT", tileFrame, "TOPLEFT", textX, -8)
        title:SetPoint("RIGHT", tileFrame, "RIGHT", -30, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        title:SetText(CludesUI.L(mod.CC_GetBindingName(bindRec)))

        local keySub = NewLabel(tileFrame, 11, 0.75, 0.75, 0.75, 0.65)
        keySub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        keySub:SetPoint("RIGHT", tileFrame, "RIGHT", -30, 0)
        keySub:SetJustifyH("LEFT")
        keySub:SetWordWrap(false)
        -- A pinned WoW Forever rank names its rank beside the key.
        local rankTxt = mod.CC_GetBindingRankText(bindRec)
        keySub:SetText(
            (bindRec.key and mod.CC_FormatKey(bindRec.key) or CludesUI.L("Not Bound"))
                .. (rankTxt and ("  -  " .. rankTxt) or "")
        )

        -- A spell the character has not got right now dims when another binding
        -- took its key; the binding stays for the loadout that has it.
        local untalented = (side == "spec" or side == "global") and IsShadowedBinding(bindRec)
        if untalented then
            iconTexture:SetAlpha(0.35)
            title:SetAlpha(0.45)
            keySub:SetAlpha(0.45)
        end

        -- Complementary Friendly/Harmful spell pairs may share a key. Mark only
        -- real collisions, positioned in the sidebar action area so the marker
        -- never obscures the spell icon.
        if
            (side == "spec" or side == "global")
            and IsReactionBinding(bindRec)
            and IsBindingActive(bindRec)
            and bindRec.key
        then
            local conflicts = FindKeyConflicts(bindRec.key, bindRec)
            if #conflicts > 0 then
                local warning = CreateFrame("Button", nil, tileFrame)
                warning:SetSize(18, 18)
                warning:SetPoint("TOPRIGHT", tileFrame, "TOPRIGHT", -26, -7)
                warning:SetFrameLevel(tileFrame:GetFrameLevel() + 2)
                local warningText = NewLabel(warning, 15, 1, 0.25, 0.15, 1)
                warningText:SetAllPoints()
                warningText:SetJustifyH("CENTER")
                warningText:SetText("!")
                local warningTooltip = {
                    CludesUI.L("Conflicting Keybind"),
                    CludesUI.Lf("%s is also assigned to:", mod.CC_FormatKey(bindRec.key)),
                }
                for _, label in ipairs(conflicts) do
                    warningTooltip[#warningTooltip + 1] = "- " .. CludesUI.L(label)
                end
                warningTooltip = table.concat(warningTooltip, "\n")
                warning:SetScript("OnEnter", function(self)
                    CludesUI.ShowWidgetTooltip(self, warningTooltip, {
                        color = { 1, 0.25, 0.15, 0.9 },
                        justify = "LEFT",
                        width = 250,
                    })
                end)
                warning:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                warning:SetScript("OnClick", function()
                    onSelect(side, position)
                end)
            end
        end

        if onDelete then
            local delBtn = CreateFrame("Button", nil, tileFrame)
            delBtn:SetSize(16, 16)
            delBtn:SetPoint("TOPRIGHT", tileFrame, "TOPRIGHT", -8, -8)
            delBtn:SetFrameLevel(tileFrame:GetFrameLevel() + 2)
            local delTex = delBtn:CreateTexture(nil, "ARTWORK")
            delTex:SetAllPoints()
            CludesUI.SetDeleteIcon(delTex)
            delTex:SetDesaturated(true)
            delTex:SetVertexColor(0.75, 0.75, 0.75)
            delTex:SetAlpha(0.5)
            delBtn:SetScript("OnEnter", function()
                delTex:SetAlpha(0.9)
            end)
            delBtn:SetScript("OnLeave", function()
                delTex:SetAlpha(0.5)
            end)
            delBtn:SetScript("OnClick", function()
                onDelete(position)
            end)
        end

        local sep = tileFrame:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", tileFrame, "BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", tileFrame, "BOTTOMRIGHT", 0, 0)
        sep:SetColorTexture(1, 1, 1, 0.04)

        tileFrame:SetScript("OnClick", function()
            onSelect(side, position)
        end)
        tileFrame:SetScript("OnEnter", function(self)
            if not isSelected then
                tileBg:SetColorTexture(1, 1, 1, 0.04)
            end
            if untalented then
                CludesUI.ShowWidgetTooltip(self, CludesUI.L("Not currently talented"), { width = 250 })
            end
        end)
        tileFrame:SetScript("OnLeave", function()
            if not isSelected then
                tileBg:SetColorTexture(1, 1, 1, 0)
            end
            if untalented then
                CludesUI.HideWidgetTooltip()
            end
        end)

        return tileFrame
    end

    -- Icon grid popup builder. side: "left" or "right"; sidebarFrame: the
    -- sidebar outer frame for anchoring.
    local function BuildIconGridPopup(anchorBtn, sidebarFrame, side, itemList, onSelect)
        local GRID_COLS = 5
        local ICON_SZ2 = 32
        local CELL_W = 48 -- horizontal slot width (text truncates here)
        local COL_GAP = 19 -- horizontal gap between columns
        local LABEL_FONT = 10
        local LABEL_GAP = 4 -- gap between label bottom and icon top
        local ROW_GAP = 8 -- gap between rows (contains divider)
        local DIV_H = 1
        local INSET = 15

        local gridRows = math.ceil(#itemList / GRID_COLS)
        local rowHasText = {}
        for r = 0, gridRows - 1 do
            rowHasText[r] = false
            for gridC = 0, GRID_COLS - 1 do
                local position = r * GRID_COLS + gridC + 1
                if itemList[position] and itemList[position].name and itemList[position].name ~= "" then
                    rowHasText[r] = true
                    break
                end
            end
        end

        -- LABEL_H ~= 14px for font 10 (measured once, not re-measured per row).
        local LABEL_H = 14
        local rowY = {} -- [r] = top Y of this row (negative, from top)
        local rowH = {} -- [r] = height of this row
        local curY = 0
        for r = 0, gridRows - 1 do
            if r > 0 then
                curY = curY + ROW_GAP
            end -- gap (+ divider) between rows
            rowY[r] = -curY
            if rowHasText[r] then
                rowH[r] = LABEL_H + LABEL_GAP + ICON_SZ2
            else
                rowH[r] = ICON_SZ2
            end
            curY = curY + rowH[r]
        end
        local innerW = GRID_COLS * CELL_W + (GRID_COLS - 1) * COL_GAP
        local innerH = max(curY, 40)

        local popupW = innerW + INSET * 2
        local rootBottom = root:GetBottom() or 0
        local btnTop = anchorBtn:GetTop() or 0
        local maxH = btnTop - rootBottom
        local popupH = min(innerH + INSET * 2, maxH, 400)

        local dialog = CreateFrame("Frame", nil, UIParent)
        dialog:Hide() -- start hidden so Show() triggers OnShow
        dialog:SetSize(popupW, popupH)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(200)

        if side == "left" then
            dialog:SetPoint(
                "TOPLEFT",
                sidebarFrame,
                "TOPRIGHT",
                0,
                -(anchorBtn:GetTop() - sidebarFrame:GetTop())
            )
        else
            dialog:SetPoint(
                "TOPRIGHT",
                sidebarFrame,
                "TOPLEFT",
                0,
                -(anchorBtn:GetTop() - sidebarFrame:GetTop())
            )
        end

        local popBg = dialog:CreateTexture(nil, "BACKGROUND")
        popBg:SetAllPoints()
        popBg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
        dialog:EnableMouse(true)
        CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.2, popBg)
        mod._ccGridPopup = dialog

        local scroll = CreateFrame("ScrollFrame", nil, dialog)
        scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", INSET, -INSET)
        scroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -INSET, INSET)
        scroll:SetFrameLevel(dialog:GetFrameLevel() + 2)
        local childFrame = CreateFrame("Frame", nil, scroll)
        childFrame:SetSize(innerW, innerH)
        scroll:SetScrollChild(childFrame)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, change)
            local scrollY = self:GetVerticalScroll()
            local mx = max(0, childFrame:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(max(0, min(mx, scrollY - change * 30)))
        end)

        for i, entry in ipairs(itemList) do
            local gridCol = (i - 1) % GRID_COLS
            local r = floor((i - 1) / GRID_COLS)
            local cx = gridCol * (CELL_W + COL_GAP)
            local cellY = rowY[r]
            local hasText = rowHasText[r]
            local cellH = rowH[r]

            local pxSnap = mod.PixelSnap or function(v)
                return v
            end

            if gridCol == 0 and r > 0 then
                local divY = cellY + ROW_GAP / 2
                local divider = childFrame:CreateTexture(nil, "ARTWORK")
                divider:SetHeight(pxSnap(1))
                divider:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 0, divY)
                divider:SetPoint("TOPRIGHT", childFrame, "TOPRIGHT", 0, divY)
                divider:SetColorTexture(1, 1, 1, 0.06)
                if Pix then
                    Pix.DisablePixelSnap(divider)
                end
            end

            local cellFrame = CreateFrame("Button", nil, childFrame)
            cellFrame:SetSize(CELL_W, cellH)
            cellFrame:SetPoint("TOPLEFT", childFrame, "TOPLEFT", cx, cellY)

            local iconFrame = CreateFrame("Frame", nil, cellFrame)
            iconFrame:SetSize(ICON_SZ2, ICON_SZ2)
            local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
            iconTexture:SetAllPoints()
            iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            iconTexture:SetTexture(entry.icon or 134400)

            local iconEdge = CreateFrame("Frame", nil, iconFrame)
            iconEdge:SetAllPoints()
            iconEdge:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            iconEdge:Hide()
            if Pix then
                Pix.CreateBorder(iconEdge, accentColor.r, accentColor.g, accentColor.b, 1, 2)
            end

            local cellLbl = nil
            if hasText and entry.name and entry.name ~= "" then
                cellLbl = NewLabel(cellFrame, LABEL_FONT, 1, 1, 1, 0.7)
                cellLbl:SetPoint("TOP", cellFrame, "TOP", 0, 0)
                cellLbl:SetWidth(CELL_W + 4)
                cellLbl:SetJustifyH("CENTER")
                cellLbl:SetWordWrap(false)
                cellLbl:SetText(entry.name)
                iconFrame:SetPoint("TOP", cellLbl, "BOTTOM", 0, -LABEL_GAP)
            else
                iconFrame:SetPoint("TOP", cellFrame, "TOP", 0, 0)
            end

            cellFrame:SetScript("OnEnter", function()
                iconEdge:Show()
                if cellLbl then
                    cellLbl:SetAlpha(1)
                end
            end)
            cellFrame:SetScript("OnLeave", function()
                iconEdge:Hide()
                if cellLbl then
                    cellLbl:SetAlpha(0.7)
                end
            end)
            cellFrame:SetScript("OnClick", function()
                onSelect(entry)
                dialog:Hide()
            end)
        end

        -- Auto-close on click outside (dropdown pattern: poll IsMouseButtonDown)
        dialog:SetScript("OnShow", function(p)
            p:SetScript("OnUpdate", function(frame)
                if
                    not frame:IsMouseOver()
                    and not anchorBtn:IsMouseOver()
                    and IsMouseButtonDown("LeftButton")
                then
                    frame:Hide()
                end
            end)
        end)
        dialog:SetScript("OnHide", function(p)
            p:SetScript("OnUpdate", nil)
            if mod._ccGridPopup == p then
                mod._ccGridPopup = nil
            end
        end)

        dialog:Show()
        return dialog
    end

    -- Page rebuild (called on selection change, add, delete, toggle): the
    -- render again, on the same kept root. The root stays shown until the
    -- render resets it (that reset is the teardown), so the frame under the
    -- cursor, dressed again in place, gets its OnEnter back from the pool.
    local function RedrawPage()
        -- Hides any open popups (QB stays open -- it's parented to UIParent).
        if mod._ccGridPopup then
            mod._ccGridPopup:Hide()
            mod._ccGridPopup = nil
        end
        if mod._ccSpecPopup then
            mod._ccSpecPopup:Hide()
            mod._ccSpecPopup = nil
        end
        mod.CC_BuildPage(page, hostFrame, yOffset)
    end

    local function SelectBinding(side, position)
        mod._ccSelSide = side
        mod._ccSelIndex = position
        RedrawPage()
    end

    ---------------------------------------------------------------------------
    --  LEFT SIDEBAR (Global Bindings)
    ---------------------------------------------------------------------------
    local listPane = CreateFrame("Frame", nil, root)
    listPane:SetSize(sidebarW, globalH)
    listPane:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    listPane:SetFrameLevel(root:GetFrameLevel() + 1)
    local leftBg = listPane:CreateTexture(nil, "BACKGROUND")
    leftBg:SetAllPoints()
    leftBg:SetColorTexture(0, 0, 0, 0.25)

    local leftHeader = NewLabel(listPane, 13, 1, 1, 1, 0.75)
    leftHeader:SetPoint("TOP", listPane, "TOP", 0, -18)
    leftHeader:SetText(CludesUI.L("Global Bindings"))
    CC.Sidebar(listPane, leftBg, leftHeader, #GetGlobalBindings())

    local listScroll = CreateFrame("ScrollFrame", nil, listPane)
    listScroll:SetPoint("TOPLEFT", listPane, "TOPLEFT", 0, -38)
    listScroll:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", 0, 0)
    listScroll:SetFrameLevel(listPane:GetFrameLevel() + 1)
    local listBody = CreateFrame("Frame", nil, listScroll)
    listBody:SetWidth(sidebarW)
    listScroll:SetScrollChild(listBody)
    listScroll:EnableMouseWheel(true)
    listScroll:SetScript("OnMouseWheel", function(self, change)
        local scrollY = self:GetVerticalScroll()
        local mx = max(0, listBody:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(max(0, min(mx, scrollY - change * 30)))
    end)

    local listY = 0
    local globals = GetGlobalBindings()
    for i, gb in ipairs(globals) do
        local isSel = selectedSide == "global" and selectedIndex == i
        local canDelete = gb.customAction
            or (
                gb.type ~= "target"
                and gb.type ~= "menu"
                and gb.type ~= "dispel"
                and gb.type ~= "external"
                and gb.type ~= "trinket1"
                and gb.type ~= "trinket2"
                and gb.type ~= "dynamicrez"
            )
        BuildTile(listBody, listY, gb, isSel, "global", i, SelectBinding, canDelete and function(idx2)
            mod.CC_RemoveGlobalBinding(idx2)
            mod._ccSelSide = nil
            mod._ccSelIndex = nil
            RedrawPage()
        end or nil)
        listY = listY - TILE_H
    end

    local newGlobalBtn = CreateFrame("Button", nil, listBody)
    newGlobalBtn:SetSize(floor(sidebarW * 0.8), ADD_BTN_H)
    newGlobalBtn:SetPoint("TOP", listBody, "TOPLEFT", sidebarW / 2, listY - ADD_BTN_PAD)
    newGlobalBtn:SetFrameLevel(listBody:GetFrameLevel() + 1)
    local agBg = newGlobalBtn:CreateTexture(nil, "BACKGROUND")
    agBg:SetAllPoints()
    agBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
    CludesUI.RoundBody(newGlobalBtn, agBg)
    local agLbl = NewLabel(newGlobalBtn, 12, 1, 1, 1, 1)
    agLbl:SetPoint("CENTER")
    agLbl:SetText(CludesUI.L("Add Global Binding"))
    newGlobalBtn:SetScript("OnEnter", function()
        agBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1)
    end)
    newGlobalBtn:SetScript("OnLeave", function()
        agBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
    end)
    agLbl:SetText("+  " .. CludesUI.L("Add Global Binding"))
    CC.Button(newGlobalBtn, agBg, agLbl, true)

    newGlobalBtn:SetScript("OnClick", function()
        if mod._ccGridPopup and mod._ccGridPopup:IsShown() then
            mod._ccGridPopup:Hide()
            return
        end

        local INSETG = 15
        local innerGridWG = 5 * 48 + 4 * 19
        local popupWG = innerGridWG + INSETG * 2
        local popupHG = 400

        -- Built on the first open; every open re-dresses it.
        local picker = ccPickers.global
        if not picker then
            local dialog = CreateFrame("Frame", nil, UIParent)
            dialog:Hide()
            dialog:SetSize(popupWG, popupHG)
            dialog:SetFrameStrata("FULLSCREEN_DIALOG")
            dialog:SetFrameLevel(200)
            local pBg = dialog:CreateTexture(nil, "BACKGROUND")
            pBg:SetAllPoints()
            pBg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
            dialog:EnableMouse(true)
            CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.2, pBg)

            -- The shared segment switch; each open sets the mode and the handler
            -- (its build refreshes once, before ccPickers holds this popup).
            local tabsG, _, tabsRefreshG = CludesUI.BuildSegmentedControl({
                parent = dialog,
                square = true,
                height = 26,
                width = popupWG - INSETG * 2,
                keys = { "macro", "item", "action" },
                labels = { macro = "Macros", item = "Items", action = "Actions" },
                getChecked = function(bindKey)
                    local u = ccPickers.global
                    return u ~= nil and u.mode == bindKey
                end,
                onToggle = function(bindKey)
                    ccPickers.global.onTab(bindKey)
                end,
            })
            tabsG:SetPoint("TOPLEFT", dialog, "TOPLEFT", INSETG, -INSETG)

            local gridScrollG = CreateFrame("ScrollFrame", nil, dialog)
            gridScrollG:SetPoint("TOPLEFT", dialog, "TOPLEFT", INSETG, -(INSETG + 40))
            gridScrollG:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -INSETG, INSETG)
            gridScrollG:SetFrameLevel(dialog:GetFrameLevel() + 2)
            local gridChildG = CreateFrame("Frame", nil, gridScrollG)
            gridChildG:SetWidth(innerGridWG)
            gridScrollG:SetScrollChild(gridChildG)
            gridScrollG:EnableMouseWheel(true)
            gridScrollG:SetScript("OnMouseWheel", function(self, change)
                local scrollY = self:GetVerticalScroll()
                local mx = max(0, gridChildG:GetHeight() - self:GetHeight())
                self:SetVerticalScroll(max(0, min(mx, scrollY - change * 30)))
            end)

            dialog:SetScript("OnHide", function(p)
                p:SetScript("OnUpdate", nil)
                if mod._ccGridPopup == p then
                    mod._ccGridPopup = nil
                end
            end)

            picker = {
                popup = dialog,
                scroll = gridScrollG,
                child = gridChildG,
                tabsRefresh = tabsRefreshG,
            }
            ccPickers.global = picker
        end
        local dialog, gridScrollG, gridChildG = picker.popup, picker.scroll, picker.child
        -- Left edge flush with right edge of left sidebar, centered vertically on the add button
        local btnMidYG = select(2, newGlobalBtn:GetCenter()) or 0
        local sidebarMidYG = select(2, listPane:GetCenter()) or 0
        local offsetYG = btnMidYG - sidebarMidYG
        -- Clamp so popup bottom doesn't go below root (CUI window)
        local rootBot = root:GetBottom() or 0
        local popupBotG = btnMidYG - popupHG / 2
        if popupBotG < rootBot then
            offsetYG = offsetYG + (rootBot - popupBotG)
        end
        dialog:ClearAllPoints()
        dialog:SetPoint("LEFT", listPane, "RIGHT", 0, offsetYG)
        mod._ccGridPopup = dialog
        gridScrollG:SetVerticalScroll(0)

        picker.mode = "macro"

        -- Reuse the same grid constants as BuildIconGridPopup
        local GCG = 5
        local ISZG = 32
        local CWG = 48
        local CGAPG = 19
        local LFONTG = 10
        local LGAPG = 4
        local RGAPG = 8
        local LHG = 14

        local function PopulateGridG(itemsG, onItemClick)
            local totalRowsG = math.ceil(#itemsG / GCG)
            local rhtG = {}
            for r = 0, totalRowsG - 1 do
                rhtG[r] = false
                for gridC = 0, GCG - 1 do
                    local ii = r * GCG + gridC + 1
                    if itemsG[ii] and itemsG[ii].name and itemsG[ii].name ~= "" then
                        rhtG[r] = true
                        break
                    end
                end
            end
            local rYG, rHG = {}, {}
            local cYG = 0
            for r = 0, totalRowsG - 1 do
                if r > 0 then
                    cYG = cYG + RGAPG
                end
                rYG[r] = -cYG
                rHG[r] = rhtG[r] and (LHG + LGAPG + ISZG) or ISZG
                cYG = cYG + rHG[r]
            end
            local pxSnapG = mod.PixelSnap or function(v)
                return v
            end
            for i, gridItem in ipairs(itemsG) do
                local gridCol = (i - 1) % GCG
                local r = floor((i - 1) / GCG)
                local cx = gridCol * (CWG + CGAPG)
                local cellY = rYG[r]
                if gridCol == 0 and r > 0 then
                    local divider = CC_PickerDivider(gridChildG, r, Pix)
                    divider:SetHeight(pxSnapG(1))
                    divider:ClearAllPoints()
                    divider:SetPoint("TOPLEFT", gridChildG, "TOPLEFT", 0, cellY + RGAPG / 2)
                    divider:SetPoint("TOPRIGHT", gridChildG, "TOPRIGHT", 0, cellY + RGAPG / 2)
                    divider:Show()
                end
                local dimmedG = (gridItem.macroName and boundMacros[MacroBoundKey(gridItem.macroName, gridItem.macroChar)])
                    or (gridItem.itemSlot and boundItems[gridItem.itemSlot])
                local cellFrame, iconEdgeFrame, cellLbl = DressPickerCell(
                    gridChildG,
                    i,
                    cx,
                    cellY,
                    CWG,
                    rHG[r],
                    gridItem.icon,
                    dimmedG,
                    rhtG[r] and gridItem.name and gridItem.name ~= "" and gridItem.name or nil,
                    LFONTG,
                    LGAPG
                )
                cellFrame:SetScript("OnEnter", function()
                    iconEdgeFrame:Show()
                    if cellLbl then
                        cellLbl:SetAlpha(1)
                    end
                end)
                cellFrame:SetScript("OnLeave", function()
                    iconEdgeFrame:Hide()
                    if cellLbl then
                        cellLbl:SetAlpha(0.7)
                    end
                end)
                cellFrame:SetScript("OnClick", function()
                    onItemClick(gridItem)
                    dialog:Hide()
                end)
            end
            gridChildG:SetHeight(max(10, cYG))
            CC_PickerFinish(gridChildG, #itemsG, totalRowsG)
        end

        local function UpdateToggleG()
            picker.tabsRefresh()
            gridScrollG:SetVerticalScroll(0)
            if picker.mode == "macro" then
                local macros = mod.CC_GetGlobalMacros()
                local mItems = {}
                for _, m in ipairs(macros) do
                    mItems[#mItems + 1] =
                        { name = m.name, icon = m.icon, macroName = m.name, macroChar = false }
                end
                PopulateGridG(mItems, function(gridItem)
                    -- Macros default to BOTH reactions (unlike spells, which
                    -- default friendly-only for the click-cast healing case): a
                    -- macro is general-purpose (e.g. mouseover focus/target), so
                    -- friendly-only would leave it dead on enemies.
                    mod.CC_AddGlobalBinding({
                        type = "macro",
                        macroName = gridItem.macroName,
                        macroChar = gridItem.macroChar,
                        icon = gridItem.icon,
                        enabled = true,
                        oocOnly = false,
                        hovercast = false,
                        hoverFriendly = true,
                        hoverEnemy = true,
                    })
                    mod._ccSelSide = "global"
                    mod._ccSelIndex = #(GetGlobalBindings())
                    RedrawPage()
                end)
            elseif picker.mode == "item" then
                local eqItems = mod.CC_GetEquippedItems()
                PopulateGridG(eqItems, function(gridItem)
                    mod.CC_AddGlobalBinding({
                        type = "item",
                        itemSlot = gridItem.itemSlot,
                        itemName = gridItem.name,
                        icon = gridItem.icon,
                        enabled = true,
                        oocOnly = false,
                        hovercast = false,
                        hoverFriendly = true,
                        hoverEnemy = true,
                    })
                    mod._ccSelSide = "global"
                    mod._ccSelIndex = #(GetGlobalBindings())
                    RedrawPage()
                end)
            else -- "action"
                PopulateGridG(CC_GetActionItems(), function(gridItem)
                    mod.CC_AddGlobalBinding({
                        type = gridItem.type,
                        customAction = true,
                        enabled = true,
                        oocOnly = false,
                        hovercast = false,
                    })
                    mod._ccSelSide = "global"
                    mod._ccSelIndex = #(GetGlobalBindings())
                    RedrawPage()
                end)
            end
        end
        UpdateToggleG()

        picker.onTab = function(bindKey)
            picker.mode = bindKey
            UpdateToggleG()
        end

        dialog:SetScript("OnShow", function(p)
            p:SetScript("OnUpdate", function(frame)
                if
                    not frame:IsMouseOver()
                    and not newGlobalBtn:IsMouseOver()
                    and IsMouseButtonDown("LeftButton")
                then
                    frame:Hide()
                end
            end)
        end)
        dialog:Show()
    end)
    listY = listY - ADD_BTN_PAD - ADD_BTN_H - 10
    listBody:SetHeight(max(10, math.abs(listY)))

    local stickyLeftBg = CreateFrame("Frame", nil, listPane)
    stickyLeftBg:SetHeight(ADD_BTN_H + 20)
    stickyLeftBg:SetPoint("BOTTOMLEFT", listPane, "BOTTOMLEFT", 0, 0)
    stickyLeftBg:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", 0, 0)
    stickyLeftBg:SetFrameLevel(listPane:GetFrameLevel() + 4)
    local slbTex = stickyLeftBg:CreateTexture(nil, "BACKGROUND")
    slbTex:SetAllPoints()
    slbTex:SetColorTexture(0.06, 0.07, 0.08, 1)
    stickyLeftBg:Hide()

    local pinnedGlobalBtn = CreateFrame("Button", nil, listPane)
    pinnedGlobalBtn:SetSize(floor(sidebarW * 0.8), ADD_BTN_H)
    pinnedGlobalBtn:SetPoint("BOTTOM", listPane, "BOTTOM", 0, 10)
    pinnedGlobalBtn:SetFrameLevel(listPane:GetFrameLevel() + 5)
    local sgBg = pinnedGlobalBtn:CreateTexture(nil, "BACKGROUND")
    sgBg:SetAllPoints()
    sgBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
    CludesUI.RoundBody(pinnedGlobalBtn, sgBg)
    local sgLbl = NewLabel(pinnedGlobalBtn, 12, 1, 1, 1, 1)
    sgLbl:SetPoint("CENTER")
    sgLbl:SetText(CludesUI.L("Add Global Binding"))
    pinnedGlobalBtn:SetScript("OnEnter", function()
        sgBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1)
    end)
    pinnedGlobalBtn:SetScript("OnLeave", function()
        sgBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
    end)
    sgLbl:SetText("+  " .. CludesUI.L("Add Global Binding"))
    CC.Button(pinnedGlobalBtn, sgBg, sgLbl, true)
    pinnedGlobalBtn:SetScript("OnClick", function()
        if mod._ccGridPopup and mod._ccGridPopup:IsShown() then
            mod._ccGridPopup:Hide()
            return
        end
        newGlobalBtn:Click()
    end)
    pinnedGlobalBtn:Hide()

    -- Button bottom in scroll child space (positive downward)
    local globalBtnBottom = math.abs(listY)
    local function UpdateLeftSticky()
        local scrollVal = listScroll:GetVerticalScroll()
        local viewH = listScroll:GetHeight()
        if globalBtnBottom > scrollVal + viewH then
            stickyLeftBg:Show()
            pinnedGlobalBtn:Show()
            newGlobalBtn:SetAlpha(0)
        else
            stickyLeftBg:Hide()
            pinnedGlobalBtn:Hide()
            newGlobalBtn:SetAlpha(1)
        end
    end
    local origLeftWheel = listScroll:GetScript("OnMouseWheel")
    listScroll:SetScript("OnMouseWheel", function(self, change)
        origLeftWheel(self, change)
        UpdateLeftSticky()
    end)
    UpdateLeftSticky()

    ---------------------------------------------------------------------------
    --  RIGHT SIDEBAR (Spec Bindings)
    ---------------------------------------------------------------------------
    local rightFrame = CreateFrame("Frame", nil, root)
    rightFrame:SetSize(sidebarW, visibleH - globalH - COL_GAP)
    rightFrame:SetPoint("TOPLEFT", listPane, "BOTTOMLEFT", 0, -COL_GAP)
    rightFrame:SetFrameLevel(root:GetFrameLevel() + 1)
    local rightBg = rightFrame:CreateTexture(nil, "BACKGROUND")
    rightBg:SetAllPoints()
    rightBg:SetColorTexture(0, 0, 0, 0.25)

    local rightHeader = NewLabel(rightFrame, 13, 1, 1, 1, 0.75)
    rightHeader:SetPoint("TOP", rightFrame, "TOP", 0, -18)
    rightHeader:SetText(CludesUI.L("Spec Bindings"))
    CC.Sidebar(rightFrame, rightBg, rightHeader, #GetSpecBindings())

    local specScroll = CreateFrame("ScrollFrame", nil, rightFrame)
    specScroll:SetPoint("TOPLEFT", rightFrame, "TOPLEFT", 0, -38)
    specScroll:SetPoint("BOTTOMRIGHT", rightFrame, "BOTTOMRIGHT", 0, 0)
    specScroll:SetFrameLevel(rightFrame:GetFrameLevel() + 1)
    local specBody = CreateFrame("Frame", nil, specScroll)
    specBody:SetWidth(sidebarW)
    specScroll:SetScrollChild(specBody)
    specScroll:EnableMouseWheel(true)
    specScroll:SetScript("OnMouseWheel", function(self, change)
        local scrollY = self:GetVerticalScroll()
        local mx = max(0, specBody:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(max(0, min(mx, scrollY - change * 30)))
    end)

    local rightY = 0
    local specBinds = GetSpecBindings()
    for i, scrollBar in ipairs(specBinds) do
        local isSel = selectedSide == "spec" and selectedIndex == i
        BuildTile(specBody, rightY, scrollBar, isSel, "spec", i, SelectBinding, function(idx2)
            mod.CC_RemoveSpecBinding(idx2)
            mod._ccSelSide = nil
            mod._ccSelIndex = nil
            RedrawPage()
        end)
        rightY = rightY - TILE_H
    end

    local btnW = floor(sidebarW * 0.42)
    local newSpecBtn = CreateFrame("Button", nil, specBody)
    newSpecBtn:SetSize(btnW, ADD_BTN_H)
    newSpecBtn:SetPoint(
        "TOPLEFT",
        specBody,
        "TOPLEFT",
        floor((sidebarW - btnW * 2 - 8) / 2),
        rightY - ADD_BTN_PAD
    )
    newSpecBtn:SetFrameLevel(specBody:GetFrameLevel() + 1)
    local asBg = newSpecBtn:CreateTexture(nil, "BACKGROUND")
    asBg:SetAllPoints()
    asBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
    CludesUI.RoundBody(newSpecBtn, asBg)
    local asLbl = NewLabel(newSpecBtn, 11, 1, 1, 1, 1)
    asLbl:SetPoint("CENTER")
    asLbl:SetText(CludesUI.L("Add New"))
    newSpecBtn:SetScript("OnEnter", function()
        asBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1)
    end)
    newSpecBtn:SetScript("OnLeave", function()
        asBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
    end)
    asLbl:SetText("+  " .. CludesUI.L("Add New"))
    CC.Button(newSpecBtn, asBg, asLbl, true)

    local qbBtn = CreateFrame("Button", nil, specBody)
    qbBtn:SetSize(btnW, ADD_BTN_H)
    qbBtn:SetPoint("LEFT", newSpecBtn, "RIGHT", 8, 0)
    qbBtn:SetFrameLevel(specBody:GetFrameLevel() + 1)
    local qbBg = qbBtn:CreateTexture(nil, "BACKGROUND")
    qbBg:SetAllPoints()
    qbBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
    CludesUI.RoundBody(qbBtn, qbBg)
    local qbLbl = NewLabel(qbBtn, 11, 1, 1, 1, 0.5)
    qbLbl:SetPoint("CENTER")
    qbLbl:SetText(CludesUI.L("Quickbind"))
    qbBtn:SetScript("OnEnter", function()
        qbBg:SetColorTexture(0.35, 0.35, 0.35, 0.8)
        qbLbl:SetAlpha(0.9)
    end)
    qbBtn:SetScript("OnLeave", function()
        qbBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
        qbLbl:SetAlpha(0.5)
    end)
    CC.Button(qbBtn, qbBg, qbLbl, false)

    qbBtn:SetScript("OnClick", function()
        if mod._ccQBPopup and mod._ccQBPopup:IsShown() then
            mod._ccQBPopup:Hide()
            return
        end

        local QB_INSET = 15
        local QB_COLS = 5
        local QB_ICON = 32
        local QB_CELL = 48
        local QB_CGAP = 19
        local QB_LFONT = 10
        local QB_LGAP = 4
        local QB_RGAP = 8
        local QB_LH = 14
        local innerGridWQB = QB_COLS * QB_CELL + (QB_COLS - 1) * QB_CGAP
        local popupWQB = innerGridWQB + QB_INSET * 2
        local popupHQB = 400

        -- Built on the first open; every open re-dresses it.
        local picker = ccPickers.qb
        if not picker then
            local shade = CreateFrame("Frame", nil, UIParent)
            shade:Hide()
            shade:SetFrameStrata("FULLSCREEN")
            shade:SetAllPoints()
            shade:EnableMouse(true)
            local dimBg = shade:CreateTexture(nil, "BACKGROUND")
            dimBg:SetAllPoints()
            dimBg:SetColorTexture(0, 0, 0, 0.6)

            local dialog = CreateFrame("Frame", nil, shade)
            dialog:SetSize(popupWQB, popupHQB)
            dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            dialog:SetFrameStrata("FULLSCREEN_DIALOG")
            dialog:SetFrameLevel(200)
            dialog:EnableMouse(true)

            local pBg = dialog:CreateTexture(nil, "BACKGROUND")
            pBg:SetAllPoints()
            pBg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
            CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.2, pBg)

            local titleLbl = NewLabel(dialog, 13, 1, 1, 1, 0.9)
            titleLbl:SetPoint("TOP", dialog, "TOP", 0, -QB_INSET)
            titleLbl:SetText(CludesUI.L("Quickbind: hover a spell, press a key"))

            local toggleTopQB = -(QB_INSET + 22)

            -- The shared segment switch; each open sets the mode and the handler.
            local tabsQB, _, tabsRefreshQB = CludesUI.BuildSegmentedControl({
                parent = dialog,
                square = true,
                height = 26,
                width = popupWQB - QB_INSET * 2,
                keys = { "spell", "macro", "item" },
                labels = { spell = "Spells", macro = "Macros", item = "Items" },
                getChecked = function(bindKey)
                    local u = ccPickers.qb
                    return u ~= nil and u.mode == bindKey
                end,
                onToggle = function(bindKey)
                    ccPickers.qb.onTab(bindKey)
                end,
            })
            tabsQB:SetPoint("TOPLEFT", dialog, "TOPLEFT", QB_INSET, toggleTopQB)

            local gridScrollQB = CreateFrame("ScrollFrame", nil, dialog)
            gridScrollQB:SetPoint("TOPLEFT", dialog, "TOPLEFT", QB_INSET, toggleTopQB - 36)
            gridScrollQB:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -QB_INSET, QB_INSET + 38)
            gridScrollQB:SetFrameLevel(dialog:GetFrameLevel() + 2)
            local gridChildQB = CreateFrame("Frame", nil, gridScrollQB)
            gridChildQB:SetWidth(innerGridWQB)
            gridScrollQB:SetScrollChild(gridChildQB)
            gridScrollQB:EnableMouseWheel(true)
            gridScrollQB:SetScript("OnMouseWheel", function(self, change)
                local scrollY = self:GetVerticalScroll()
                local mx = max(0, gridChildQB:GetHeight() - self:GetHeight())
                self:SetVerticalScroll(max(0, min(mx, scrollY - change * 30)))
            end)

            local doneBtn = CreateFrame("Button", nil, dialog)
            doneBtn:SetSize(100, 30)
            doneBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, QB_INSET)
            doneBtn:SetFrameLevel(dialog:GetFrameLevel() + 3)
            local doneBg = doneBtn:CreateTexture(nil, "BACKGROUND")
            doneBg:SetAllPoints()
            doneBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
            CludesUI.RoundBody(doneBtn, doneBg)
            local doneLbl = NewLabel(doneBtn, 11, 1, 1, 1, 0.5)
            doneLbl:SetPoint("CENTER")
            doneLbl:SetText(CludesUI.L("Done"))
            doneBtn:SetScript("OnEnter", function()
                doneBg:SetColorTexture(0.35, 0.35, 0.35, 0.8)
                doneLbl:SetAlpha(0.9)
            end)
            doneBtn:SetScript("OnLeave", function()
                doneBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
                doneLbl:SetAlpha(0.5)
            end)
            CC.Button(doneBtn, doneBg, doneLbl, false)
            doneBtn:SetScript("OnClick", function()
                shade:Hide()
            end)

            shade:SetScript("OnMouseDown", function(self, btnFrame)
                if not dialog:IsMouseOver() then
                    shade:Hide()
                end
            end)
            -- Closes as combat starts, with the settings window: its cells take
            -- the keyboard on hover, which combat forbids. Listens only while open
            -- (the OnHide below unregisters).
            shade:SetScript("OnShow", function(self)
                self:RegisterEvent("PLAYER_REGEN_DISABLED")
            end)
            shade:SetScript("OnEvent", function(self)
                self:Hide()
            end)

            picker = {
                dimmer = shade,
                title = titleLbl,
                scroll = gridScrollQB,
                child = gridChildQB,
                tabsRefresh = tabsRefreshQB,
                doneBg = doneBg,
                doneLbl = doneLbl,
            }
            ccPickers.qb = picker
        end
        local shade, gridScrollQB, gridChildQB = picker.dimmer, picker.scroll, picker.child
        mod._ccQBPopup = shade
        StyleFont(picker.title, 13, 1, 1, 1, 0.9)
        StyleFont(picker.doneLbl, 11, 1, 1, 1, 0.5)
        picker.doneLbl:SetAlpha(1)
        picker.doneBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
        gridScrollQB:SetVerticalScroll(0)

        picker.mode = "spell"

        -- Hovered item reference (set by cell OnEnter/OnLeave)
        local hoverItem = nil

        local UpdateToggleQB
        local function PopulateGridQB(items3)
            hoverItem = nil
            local totalRows = math.ceil(#items3 / QB_COLS)
            local rht3 = {}
            for r = 0, totalRows - 1 do
                rht3[r] = false
                for gridC = 0, QB_COLS - 1 do
                    local ii = r * QB_COLS + gridC + 1
                    if items3[ii] and items3[ii].name and items3[ii].name ~= "" then
                        rht3[r] = true
                        break
                    end
                end
            end
            local rY3, rH3 = {}, {}
            local cY3 = 0
            for r = 0, totalRows - 1 do
                if r > 0 then
                    cY3 = cY3 + QB_RGAP
                end
                rY3[r] = -cY3
                rH3[r] = rht3[r] and (QB_LH + QB_LGAP + QB_ICON) or QB_ICON
                cY3 = cY3 + rH3[r]
            end
            local pxSnap3 = mod.PixelSnap or function(v)
                return v
            end
            for i, entry in ipairs(items3) do
                local gridCol = (i - 1) % QB_COLS
                local r = floor((i - 1) / QB_COLS)
                local cx = gridCol * (QB_CELL + QB_CGAP)
                local cellY = rY3[r]
                if gridCol == 0 and r > 0 then
                    local divider = CC_PickerDivider(gridChildQB, r, Pix)
                    divider:SetHeight(pxSnap3(1))
                    divider:ClearAllPoints()
                    divider:SetPoint("TOPLEFT", gridChildQB, "TOPLEFT", 0, cellY + QB_RGAP / 2)
                    divider:SetPoint("TOPRIGHT", gridChildQB, "TOPRIGHT", 0, cellY + QB_RGAP / 2)
                    divider:Show()
                end
                local dimmed3 = (
                    entry.id
                    and mod.CC_IsSpellBound(boundSpells, entry.id, entry.name, entry.lowRank)
                )
                    or (entry.macroName and boundMacros[MacroBoundKey(entry.macroName, entry.macroChar)])
                    or (entry.itemSlot and boundItems[entry.itemSlot])
                -- A WoW Forever lower rank labels itself by its rank.
                local cellFrame, iconEdgeFrame, cellLbl3 = DressPickerCell(
                    gridChildQB,
                    i,
                    cx,
                    cellY,
                    QB_CELL,
                    rH3[r],
                    entry.icon,
                    dimmed3,
                    rht3[r]
                            and entry.name
                            and entry.name ~= ""
                            and (entry.lowRank and entry.rankText or entry.name)
                        or nil,
                    QB_LFONT,
                    QB_LGAP
                )
                cellFrame:RegisterForClicks("AnyUp")
                cellFrame:EnableKeyboard(false)
                cellFrame:SetScript("OnEnter", function()
                    iconEdgeFrame:Show()
                    if cellLbl3 then
                        cellLbl3:SetAlpha(1)
                    end
                    hoverItem = entry
                    if not InCombatLockdown() then
                        cellFrame:EnableKeyboard(true)
                    end
                    mod.CC_RankTip(cellFrame, entry)
                end)
                cellFrame:SetScript("OnLeave", function()
                    iconEdgeFrame:Hide()
                    if cellLbl3 then
                        cellLbl3:SetAlpha(dimmed3 and 0.3 or 0.7)
                    end
                    hoverItem = nil
                    if not InCombatLockdown() then
                        cellFrame:EnableKeyboard(false)
                    end
                    if entry.lowRank or entry.ranked then
                        CludesUI.HideWidgetTooltip()
                    end
                end)
                -- Key press while hovering: bind this item to that key
                cellFrame:SetScript("OnKeyDown", function(self, bindKey)
                    if InCombatLockdown() then
                        return
                    end
                    if MODIFIER_KEYS[bindKey] then
                        self:SetPropagateKeyboardInput(true)
                        return
                    end
                    if bindKey == "ESCAPE" then
                        self:SetPropagateKeyboardInput(false)
                        shade:Hide()
                        return
                    end
                    self:SetPropagateKeyboardInput(false)
                    local captured = mod.CC_CaptureKey(bindKey)
                    if not captured or not hoverItem then
                        return
                    end
                    local bindRec
                    if hoverItem.id then
                        bindRec = {
                            type = "spell",
                            spell = hoverItem.name,
                            spellID = hoverItem.id,
                            icon = hoverItem.icon,
                            key = captured,
                            enabled = true,
                            hoverFriendly = true,
                            hoverEnemy = true,
                            rankPinned = hoverItem.lowRank,
                        }
                    elseif hoverItem.macroName then
                        bindRec = {
                            type = "macro",
                            macroName = hoverItem.macroName,
                            macroChar = hoverItem.macroChar,
                            icon = hoverItem.icon,
                            key = captured,
                            enabled = true,
                            hoverFriendly = true,
                            hoverEnemy = true,
                        }
                    elseif hoverItem.itemSlot then
                        bindRec = {
                            type = "item",
                            itemSlot = hoverItem.itemSlot,
                            itemName = hoverItem.name,
                            icon = hoverItem.icon,
                            key = captured,
                            enabled = true,
                            hoverFriendly = true,
                            hoverEnemy = true,
                        }
                    end
                    if bindRec then
                        mod.CC_AddSpecBinding(bindRec)
                        if hoverItem.macroName then
                            boundMacros[MacroBoundKey(hoverItem.macroName, hoverItem.macroChar)] = true
                        elseif hoverItem.itemSlot then
                            boundItems[hoverItem.itemSlot] = true
                        else
                            boundSpells[mod.CC_SpellBoundKey(
                                hoverItem.id,
                                hoverItem.name or "",
                                hoverItem.lowRank
                            )] =
                                true
                        end
                        UpdateToggleQB()
                        RedrawPage()
                    end
                end)
                -- Mouse click while hovering: bind with modifier+button
                cellFrame:SetScript("OnClick", function(self, btnFrame)
                    if not hoverItem then
                        return
                    end
                    local mods = GetModifierPrefix()
                    local normalized = MOUSE_BUTTON_MAP[btnFrame]
                        or ("BUTTON" .. (btnFrame:match("%d+") or btnFrame))
                    local captured = mods .. normalized
                    local bindRec
                    if hoverItem.id then
                        bindRec = {
                            type = "spell",
                            spell = hoverItem.name,
                            spellID = hoverItem.id,
                            icon = hoverItem.icon,
                            key = captured,
                            enabled = true,
                            hoverFriendly = true,
                            hoverEnemy = true,
                            rankPinned = hoverItem.lowRank,
                        }
                    elseif hoverItem.macroName then
                        bindRec = {
                            type = "macro",
                            macroName = hoverItem.macroName,
                            macroChar = hoverItem.macroChar,
                            icon = hoverItem.icon,
                            key = captured,
                            enabled = true,
                            hoverFriendly = true,
                            hoverEnemy = true,
                        }
                    elseif hoverItem.itemSlot then
                        bindRec = {
                            type = "item",
                            itemSlot = hoverItem.itemSlot,
                            itemName = hoverItem.name,
                            icon = hoverItem.icon,
                            key = captured,
                            enabled = true,
                            hoverFriendly = true,
                            hoverEnemy = true,
                        }
                    end
                    if bindRec then
                        mod.CC_AddSpecBinding(bindRec)
                        if hoverItem.macroName then
                            boundMacros[MacroBoundKey(hoverItem.macroName, hoverItem.macroChar)] = true
                        elseif hoverItem.itemSlot then
                            boundItems[hoverItem.itemSlot] = true
                        else
                            boundSpells[mod.CC_SpellBoundKey(
                                hoverItem.id,
                                hoverItem.name or "",
                                hoverItem.lowRank
                            )] =
                                true
                        end
                        UpdateToggleQB()
                        RedrawPage()
                    end
                end)
            end
            gridChildQB:SetHeight(max(10, cY3))
            CC_PickerFinish(gridChildQB, #items3, totalRows)
        end

        function UpdateToggleQB()
            picker.tabsRefresh()
            if picker.mode == "spell" then
                PopulateGridQB(mod.CC_GetClassSpells())
            elseif picker.mode == "macro" then
                local macros = mod.CC_GetAllMacros()
                local mItems = {}
                for _, m in ipairs(macros) do
                    local prefixText = m.isGlobal and "" or "(C) "
                    mItems[#mItems + 1] = {
                        name = prefixText .. m.name,
                        icon = m.icon,
                        macroName = m.name,
                        macroChar = not m.isGlobal,
                    }
                end
                PopulateGridQB(mItems)
            else
                PopulateGridQB(mod.CC_GetEquippedItems())
            end
        end
        UpdateToggleQB()

        picker.onTab = function(bindKey)
            picker.mode = bindKey
            UpdateToggleQB()
        end

        shade:SetScript("OnHide", function(self)
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            if mod._ccQBPopup == shade then
                mod._ccQBPopup = nil
            end
            -- A close in combat rebuilds the page once combat ends.
            if InCombatLockdown() then
                mod.CombatQueue.Defer("CC_QuickbindPage", RedrawPage)
            else
                RedrawPage()
            end
        end)

        shade:Show()
    end)

    newSpecBtn:SetScript("OnClick", function()
        if mod._ccSpecPopup and mod._ccSpecPopup:IsShown() then
            mod._ccSpecPopup:Hide()
            return
        end

        -- Same grid metrics as BuildIconGridPopup (48px cells, 19px gaps)
        local INSET3 = 15
        local innerGridW3 = 5 * 48 + 4 * 19
        local popupW = innerGridW3 + INSET3 * 2
        local popupH2 = 400
        local INSET2 = 15

        -- Built on the first open; every open re-dresses it.
        local picker = ccPickers.spec
        if not picker then
            local dialog = CreateFrame("Frame", nil, UIParent)
            dialog:Hide() -- start hidden so Show() triggers OnShow
            dialog:SetSize(popupW, popupH2)
            dialog:SetFrameStrata("FULLSCREEN_DIALOG")
            dialog:SetFrameLevel(200)
            local pBg = dialog:CreateTexture(nil, "BACKGROUND")
            pBg:SetAllPoints()
            pBg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
            dialog:EnableMouse(true)
            CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.2, pBg)

            -- The shared segment switch; each open sets the mode and the handler.
            local tabs, _, tabsRefresh = CludesUI.BuildSegmentedControl({
                parent = dialog,
                square = true,
                height = 26,
                width = popupW - INSET2 * 2,
                keys = { "spell", "macro", "item", "action" },
                labels = { spell = "Spells", macro = "Macros", item = "Items", action = "Actions" },
                getChecked = function(bindKey)
                    local u = ccPickers.spec
                    return u ~= nil and u.mode == bindKey
                end,
                onToggle = function(bindKey)
                    ccPickers.spec.onTab(bindKey)
                end,
            })
            tabs:SetPoint("TOPLEFT", dialog, "TOPLEFT", INSET2, -INSET2)

            -- Grid scroll area (inset on all sides, below toggle row)
            local gridScroll = CreateFrame("ScrollFrame", nil, dialog)
            gridScroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", INSET2, -(INSET2 + 40))
            gridScroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -INSET2, INSET2)
            gridScroll:SetFrameLevel(dialog:GetFrameLevel() + 2)
            local innerGridW = popupW - INSET2 * 2
            local gridChild = CreateFrame("Frame", nil, gridScroll)
            gridChild:SetWidth(innerGridW)
            gridScroll:SetScrollChild(gridChild)
            gridScroll:EnableMouseWheel(true)
            gridScroll:SetScript("OnMouseWheel", function(self, change)
                local scrollY = self:GetVerticalScroll()
                local mx = max(0, gridChild:GetHeight() - self:GetHeight())
                self:SetVerticalScroll(max(0, min(mx, scrollY - change * 30)))
            end)

            dialog:SetScript("OnHide", function(p)
                p:SetScript("OnUpdate", nil)
                if mod._ccSpecPopup == p then
                    mod._ccSpecPopup = nil
                end
            end)

            picker = {
                popup = dialog,
                scroll = gridScroll,
                child = gridChild,
                tabsRefresh = tabsRefresh,
            }
            ccPickers.spec = picker
        end
        local dialog, gridScroll, gridChild = picker.popup, picker.scroll, picker.child
        -- Left edge flush with the bindings column's right edge, centred vertically on the add button
        local btnMidY = select(2, newSpecBtn:GetCenter()) or 0
        local sidebarMidY = select(2, rightFrame:GetCenter()) or 0
        local offsetY = btnMidY - sidebarMidY
        -- Clamp so popup bottom doesn't go below root (CUI window)
        local rootBotR = root:GetBottom() or 0
        local popupBotR = btnMidY - popupH2 / 2
        if popupBotR < rootBotR then
            offsetY = offsetY + (rootBotR - popupBotR)
        end
        dialog:ClearAllPoints()
        dialog:SetPoint("LEFT", rightFrame, "RIGHT", 0, offsetY)

        mod._ccSpecPopup = dialog
        gridScroll:SetVerticalScroll(0)

        picker.mode = "spell"

        local GC2 = 5
        local ISZ2 = 32
        local CW2 = 48
        local CGAP2 = 19
        local LFONT2 = 10
        local LGAP2 = 4
        local RGAP2 = 8
        local LH2 = 14

        local function PopulateGrid(items2, onItemClick)
            local totalRows2 = math.ceil(#items2 / GC2)
            local rht = {}
            for r = 0, totalRows2 - 1 do
                rht[r] = false
                for gridC = 0, GC2 - 1 do
                    local ii = r * GC2 + gridC + 1
                    if items2[ii] and items2[ii].name and items2[ii].name ~= "" then
                        rht[r] = true
                        break
                    end
                end
            end
            local rY2, rH2 = {}, {}
            local cY2 = 0
            for r = 0, totalRows2 - 1 do
                if r > 0 then
                    cY2 = cY2 + RGAP2
                end
                rY2[r] = -cY2
                rH2[r] = rht[r] and (LH2 + LGAP2 + ISZ2) or ISZ2
                cY2 = cY2 + rH2[r]
            end

            local pxSnap2 = mod.PixelSnap or function(v)
                return v
            end

            for i, entry in ipairs(items2) do
                local gridCol = (i - 1) % GC2
                local r = floor((i - 1) / GC2)
                local cx = gridCol * (CW2 + CGAP2)
                local cellY = rY2[r]

                if gridCol == 0 and r > 0 then
                    local divY = cellY + RGAP2 / 2
                    local divider = CC_PickerDivider(gridChild, r, Pix)
                    divider:SetHeight(pxSnap2(1))
                    divider:ClearAllPoints()
                    divider:SetPoint("TOPLEFT", gridChild, "TOPLEFT", 0, divY)
                    divider:SetPoint("TOPRIGHT", gridChild, "TOPRIGHT", 0, divY)
                    divider:Show()
                end

                local dimmed = (
                    entry.id
                    and mod.CC_IsSpellBound(boundSpells, entry.id, entry.name, entry.lowRank)
                )
                    or (entry.macroName and boundMacros[MacroBoundKey(entry.macroName, entry.macroChar)])
                    or (entry.itemSlot and boundItems[entry.itemSlot])
                -- A WoW Forever lower rank labels itself by its rank.
                local cellFrame, iconBdr2, cellLbl2 = DressPickerCell(
                    gridChild,
                    i,
                    cx,
                    cellY,
                    CW2,
                    rH2[r],
                    entry.icon,
                    dimmed,
                    rht[r] and entry.name and entry.name ~= "" and (entry.lowRank and entry.rankText or entry.name)
                        or nil,
                    LFONT2,
                    LGAP2
                )

                cellFrame:SetScript("OnEnter", function()
                    iconBdr2:Show()
                    if cellLbl2 then
                        cellLbl2:SetAlpha(1)
                    end
                    mod.CC_RankTip(cellFrame, entry)
                end)
                cellFrame:SetScript("OnLeave", function()
                    iconBdr2:Hide()
                    if cellLbl2 then
                        cellLbl2:SetAlpha(0.7)
                    end
                    if entry.lowRank or entry.ranked then
                        CludesUI.HideWidgetTooltip()
                    end
                end)
                cellFrame:SetScript("OnClick", function()
                    onItemClick(entry)
                    dialog:Hide()
                end)
            end
            gridChild:SetHeight(max(10, cY2))
            CC_PickerFinish(gridChild, #items2, totalRows2)
        end

        local function UpdateToggle()
            picker.tabsRefresh()
            gridScroll:SetVerticalScroll(0)

            if picker.mode == "spell" then
                local spellList = mod.CC_GetClassSpells()
                PopulateGrid(spellList, function(entry)
                    mod.CC_AddSpecBinding({
                        type = "spell",
                        spell = entry.name,
                        spellID = entry.id,
                        icon = entry.icon,
                        enabled = true,
                        oocOnly = false,
                        hovercast = false,
                        hoverFriendly = true,
                        hoverEnemy = true,
                        -- A WoW Forever lower rank keeps casting that rank.
                        rankPinned = entry.lowRank,
                    })
                    mod._ccSelSide = "spec"
                    mod._ccSelIndex = #(GetSpecBindings())
                    RedrawPage()
                end)
            elseif picker.mode == "macro" then
                local macros = mod.CC_GetAllMacros()
                local mItems = {}
                for _, m in ipairs(macros) do
                    local prefixText = m.isGlobal and "" or "(C) "
                    mItems[#mItems + 1] = {
                        name = prefixText .. m.name,
                        icon = m.icon,
                        macroName = m.name,
                        macroChar = not m.isGlobal,
                    }
                end
                PopulateGrid(mItems, function(entry)
                    mod.CC_AddSpecBinding({
                        type = "macro",
                        macroName = entry.macroName,
                        macroChar = entry.macroChar,
                        icon = entry.icon,
                        enabled = true,
                        oocOnly = false,
                        hovercast = false,
                        -- Both reactions: see the global macro add above.
                        hoverFriendly = true,
                        hoverEnemy = true,
                    })
                    mod._ccSelSide = "spec"
                    mod._ccSelIndex = #(GetSpecBindings())
                    RedrawPage()
                end)
            elseif picker.mode == "item" then
                local eqItems = mod.CC_GetEquippedItems()
                PopulateGrid(eqItems, function(entry)
                    mod.CC_AddSpecBinding({
                        type = "item",
                        itemSlot = entry.itemSlot,
                        itemName = entry.name,
                        icon = entry.icon,
                        enabled = true,
                        oocOnly = false,
                        hovercast = false,
                        hoverFriendly = true,
                        hoverEnemy = true,
                    })
                    mod._ccSelSide = "spec"
                    mod._ccSelIndex = #(GetSpecBindings())
                    RedrawPage()
                end)
            else -- "action"
                PopulateGrid(CC_GetActionItems(), function(entry)
                    mod.CC_AddSpecBinding({
                        type = entry.type,
                        enabled = true,
                        oocOnly = false,
                        hovercast = false,
                    })
                    mod._ccSelSide = "spec"
                    mod._ccSelIndex = #(GetSpecBindings())
                    RedrawPage()
                end)
            end
        end
        UpdateToggle()

        picker.onTab = function(bindKey)
            picker.mode = bindKey
            UpdateToggle()
        end

        -- Auto-close on click outside (dropdown pattern: poll IsMouseButtonDown)
        dialog:SetScript("OnShow", function(p)
            p:SetScript("OnUpdate", function(frame)
                if
                    not frame:IsMouseOver()
                    and not newSpecBtn:IsMouseOver()
                    and IsMouseButtonDown("LeftButton")
                then
                    frame:Hide()
                end
            end)
        end)

        dialog:Show()
    end)

    rightY = rightY - ADD_BTN_PAD - ADD_BTN_H - 10
    specBody:SetHeight(max(10, math.abs(rightY)))

    local stickyRightBg = CreateFrame("Frame", nil, rightFrame)
    stickyRightBg:SetHeight(ADD_BTN_H + 20)
    stickyRightBg:SetPoint("BOTTOMLEFT", rightFrame, "BOTTOMLEFT", 0, 0)
    stickyRightBg:SetPoint("BOTTOMRIGHT", rightFrame, "BOTTOMRIGHT", 0, 0)
    stickyRightBg:SetFrameLevel(rightFrame:GetFrameLevel() + 4)
    local srbTex = stickyRightBg:CreateTexture(nil, "BACKGROUND")
    srbTex:SetAllPoints()
    srbTex:SetColorTexture(0.06, 0.07, 0.08, 1)
    stickyRightBg:Hide()

    local stickySpecBtn = CreateFrame("Button", nil, rightFrame)
    stickySpecBtn:SetSize(btnW, ADD_BTN_H)
    stickySpecBtn:SetPoint("BOTTOMLEFT", rightFrame, "BOTTOMLEFT", floor((sidebarW - btnW * 2 - 8) / 2), 10)
    stickySpecBtn:SetFrameLevel(rightFrame:GetFrameLevel() + 5)
    local ssBg = stickySpecBtn:CreateTexture(nil, "BACKGROUND")
    ssBg:SetAllPoints()
    ssBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
    CludesUI.RoundBody(stickySpecBtn, ssBg)
    local ssLbl = NewLabel(stickySpecBtn, 11, 1, 1, 1, 1)
    ssLbl:SetPoint("CENTER")
    ssLbl:SetText(CludesUI.L("Add New"))
    stickySpecBtn:SetScript("OnEnter", function()
        ssBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1)
    end)
    stickySpecBtn:SetScript("OnLeave", function()
        ssBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
    end)
    ssLbl:SetText("+  " .. CludesUI.L("Add New"))
    CC.Button(stickySpecBtn, ssBg, ssLbl, true)
    stickySpecBtn:SetScript("OnClick", function()
        if mod._ccSpecPopup and mod._ccSpecPopup:IsShown() then
            mod._ccSpecPopup:Hide()
            return
        end
        newSpecBtn:Click()
    end)

    local stickyQBBtn = CreateFrame("Button", nil, rightFrame)
    stickyQBBtn:SetSize(btnW, ADD_BTN_H)
    stickyQBBtn:SetPoint("LEFT", stickySpecBtn, "RIGHT", 8, 0)
    stickyQBBtn:SetFrameLevel(rightFrame:GetFrameLevel() + 5)
    local sqBg = stickyQBBtn:CreateTexture(nil, "BACKGROUND")
    sqBg:SetAllPoints()
    sqBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
    CludesUI.RoundBody(stickyQBBtn, sqBg)
    local sqLbl = NewLabel(stickyQBBtn, 11, 1, 1, 1, 0.5)
    sqLbl:SetPoint("CENTER")
    sqLbl:SetText(CludesUI.L("Quickbind"))
    stickyQBBtn:SetScript("OnEnter", function()
        sqBg:SetColorTexture(0.35, 0.35, 0.35, 0.8)
        sqLbl:SetAlpha(0.9)
    end)
    stickyQBBtn:SetScript("OnLeave", function()
        sqBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
        sqLbl:SetAlpha(0.5)
    end)
    CC.Button(stickyQBBtn, sqBg, sqLbl, false)
    stickyQBBtn:SetScript("OnClick", function()
        qbBtn:Click()
    end)

    stickySpecBtn:Hide()
    stickyQBBtn:Hide()

    local rightBtnBottom = math.abs(rightY)
    local function UpdateRightSticky()
        local scrollVal = specScroll:GetVerticalScroll()
        local viewH = specScroll:GetHeight()
        if rightBtnBottom > scrollVal + viewH then
            stickyRightBg:Show()
            stickySpecBtn:Show()
            stickyQBBtn:Show()
            newSpecBtn:SetAlpha(0)
            qbBtn:SetAlpha(0)
        else
            stickyRightBg:Hide()
            stickySpecBtn:Hide()
            stickyQBBtn:Hide()
            newSpecBtn:SetAlpha(1)
            qbBtn:SetAlpha(1)
        end
    end
    local origRightWheel = specScroll:GetScript("OnMouseWheel")
    specScroll:SetScript("OnMouseWheel", function(self, change)
        origRightWheel(self, change)
        UpdateRightSticky()
    end)
    UpdateRightSticky()

    ---------------------------------------------------------------------------
    --  CENTER CONTENT
    --  Uses the standard CUI row pattern: ROW_H=50 frames with RowBg,
    --  SIDE_PAD=20, label on left, control on right.
    ---------------------------------------------------------------------------
    local midFrame = CreateFrame("Frame", nil, root)
    midFrame:SetSize(centerW, visibleH)
    midFrame:SetPoint("TOPLEFT", listPane, "TOPRIGHT", COL_GAP, 0)
    midFrame:SetFrameLevel(root:GetFrameLevel() + 1)

    local C_PAD = 16 -- padding inside center panel
    local ROW_H = 50 -- standard row height (matches Party Mode)
    local SIDE_PAD = 20 -- padding inside each row
    local rowW = centerW - C_PAD * 2 -- row width
    local midY = 0
    -- Everything below Enable Click Casting gates on it; rows parent to bodyHost
    -- so a dimmable container can be swapped in after that first row.
    local bodyHost = midFrame

    local function MakeRow(yPos)
        local line = CreateFrame("Frame", nil, bodyHost)
        Pix.Size(line, rowW, ROW_H)
        Pix.Point(line, "TOPLEFT", bodyHost, "TOPLEFT", C_PAD, yPos)
        CludesUI.RowBg(line, bodyHost)
        return line
    end

    local function RowLabel(line, textValue)
        local labelFS = CludesUI.MakeFont(
            line,
            14,
            nil,
            CludesUI.TEXT_WHITE_R,
            CludesUI.TEXT_WHITE_G,
            CludesUI.TEXT_WHITE_B
        )
        Pix.Point(labelFS, "LEFT", line, "LEFT", SIDE_PAD, 0)
        labelFS:SetText(CludesUI.L(textValue))
        return labelFS
    end

    local function RowToggle(line, getValue, setValue)
        local toggleW, toggleH = 36, 18
        local pill = CreateFrame("Button", nil, line)
        pill:SetSize(toggleW, toggleH)
        Pix.Point(pill, "RIGHT", line, "RIGHT", -SIDE_PAD, 0)
        pill:SetFrameLevel(line:GetFrameLevel() + 2)
        -- Pill and knob on a pixel layer, as the settings toggle draws them.
        local L = CludesUI.MakePixelLayer(pill, CludesUI.TogglePillFit)
        local pillBg = L._frame:CreateTexture(nil, "BACKGROUND")
        pillBg:SetAllPoints(L._frame)
        local knob = L._frame:CreateTexture(nil, "OVERLAY")
        L.track, L.knob, L.pad = pillBg, knob, 2
        local function Refresh()
            local on = getValue()
            if on then
                pillBg:SetVertexColor(accentColor.r, accentColor.g, accentColor.b, 1)
                knob:SetVertexColor(1, 1, 1, 1)
            else
                pillBg:SetVertexColor(0.25, 0.25, 0.25, 1)
                knob:SetVertexColor(0.5, 0.5, 0.5, 1)
            end
            local pad = L.padPx
            if pad then
                knob:ClearAllPoints()
                knob:SetPoint("TOPLEFT", L._frame, "TOPLEFT", on and (L.wp - pad - L.d) or pad, -pad)
            end
        end
        L.apply = Refresh
        L:Fit()
        Refresh()
        pill:SetScript("OnClick", function()
            local gen = PoolGen(pill)
            setValue(not getValue())
            -- A setter that renders the page again dressed this pill again
            -- (maybe as another row's): that render painted it.
            if PoolGen(pill) == gen then
                Refresh()
            end
        end)
        return pill, Refresh
    end

    -------------------------------------------------------------------
    --  GLOBAL OPTIONS section
    -------------------------------------------------------------------
    -- Accent-colored, matches W:SectionHeader style.
    local globalTop
    do
        midY = midY - 6
        globalTop = midY
        local secH = 40
        local secLabel = NewLabel(midFrame, 13, 1, 1, 1, 1)
        secLabel:SetPoint("LEFT", midFrame, "TOPLEFT", C_PAD, midY - 17)
        secLabel:SetText(CludesUI.L("GLOBAL OPTIONS"))
        midY = midY - secH
    end

    -- Row 1: Enable Click Casting (everything else gates on it). Disabled when a
    -- conflicting click-cast addon is loaded (checked below) -- both would bind
    -- clicks on the same frames. That addon's loaded state can't change without
    -- a /reload, so this one-time check is authoritative for the session.
    do
        local line = MakeRow(midY)
        local labelFS = RowLabel(line, "Enable Click Casting")
        local pill = RowToggle(line, function()
            return clickDB.enabled
        end, function(v)
            mod.CC_SetEnabled(v)
            CludesUI:RefreshPage(true)
        end)
        local cliqueLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Clique")
        if cliqueLoaded then
            labelFS:SetAlpha(0.4)
            pill:SetAlpha(0.3)
            pill:SetScript("OnClick", nil) -- non-interactive while the other addon owns clicks
            pill:SetScript("OnEnter", function(self)
                CludesUI.ShowWidgetTooltip(
                    self,
                    CludesUI.L('Please disable the addon "Clique" to use this feature.')
                )
            end)
            pill:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
        end
        midY = midY - ROW_H
    end

    -- Holds every gated center control: dimmed + click-blocked when click-casting
    -- is off; everything below builds into this instead of centerFrame.
    local midBody = CreateFrame("Frame", nil, midFrame)
    midBody:SetAllPoints(midFrame)
    midBody:SetFrameLevel(midFrame:GetFrameLevel() + 1)
    bodyHost = midBody
    local gatedTop = midY -- Y just below the Enable row; the gated region starts here

    do
        local line = MakeRow(midY)
        RowLabel(line, "Trigger Bindings on Down")
        RowToggle(line, function()
            return clickDB.downClick
        end, function(v)
            mod.CC_SetDownClick(v)
        end)
        midY = midY - ROW_H
    end

    -- Clear Stuck Spell Targeting (AddTargetingClears): every binding's macro
    -- changes, so a switch re-applies them all.
    do
        local line = MakeRow(midY)
        RowLabel(line, "Clear Stuck Spell Targeting")
        RowToggle(line, function()
            return clickDB.clearTargeting ~= false
        end, function(v)
            if v then
                clickDB.clearTargeting = nil
            else
                clickDB.clearTargeting = false
            end
            mod.CC_ApplyBindings()
        end)
        line:EnableMouse(true)
        line:SetScript("OnEnter", function(self)
            CludesUI.ShowWidgetTooltip(
                self,
                CludesUI.L(
                    "Before a binding casts, cancel any spell still waiting for a target (the glowing hand cursor left by a cast on a unit it can't take), so the press casts instead of being swallowed."
                )
            )
        end)
        line:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        midY = midY - ROW_H
    end

    do
        local line = MakeRow(midY)
        RowLabel(line, "Mouseover Frames")
        local mfValues = { all = "All Unit Frames", rf = "CUI Raid & Party Frames" }
        local mfOrder = { "all", "rf" }
        local ddCtrl = CludesUI.BuildDropdownControl(
            line,
            190,
            line:GetFrameLevel() + 2,
            mfValues,
            mfOrder,
            function()
                return clickDB.allFrames and "all" or "rf"
            end,
            function(v)
                mod.CC_SetAllFrames(v == "all")
            end
        )
        Pix.Point(ddCtrl, "RIGHT", line, "RIGHT", -SIDE_PAD, 0)
        midY = midY - ROW_H
    end
    midY = midY - 8
    CC.Card(midFrame, C_PAD - 8, globalTop, rowW + 16, midY)

    -------------------------------------------------------------------
    --  PER-SPELL OPTIONS section
    -------------------------------------------------------------------
    local perTop
    do
        midY = midY - 12
        perTop = midY
        local secH = 40
        local secLabel = NewLabel(bodyHost, 13, 1, 1, 1, 1)
        secLabel:SetPoint("LEFT", bodyHost, "TOPLEFT", C_PAD, midY - 17)
        secLabel:SetText(CludesUI.L("PER-SPELL OPTIONS"))
        midY = midY - secH
    end

    if pickedBinding then
        -- Editing title with icon (centered, type label above name)
        do
            midY = midY - 10
            local titleRow = CreateFrame("Frame", nil, bodyHost)
            titleRow:SetSize(rowW, 44)
            titleRow:SetPoint("TOPLEFT", bodyHost, "TOPLEFT", C_PAD, midY)

            local typeStr = "Spell"
            if pickedBinding.type == "macro" then
                typeStr = "Macro"
            elseif pickedBinding.type == "item" then
                typeStr = "Item"
            elseif pickedBinding.type == "target" then
                typeStr = "Action"
            elseif pickedBinding.type == "menu" then
                typeStr = "Action"
            elseif pickedBinding.type == "dispel" then
                typeStr = "Preset"
            elseif pickedBinding.type == "external" then
                typeStr = "Preset"
            end
            local tType = NewLabel(titleRow, 11, 1, 1, 1, 0.4)
            -- A pinned WoW Forever rank names its rank beside the type.
            local rankTxt = mod.CC_GetBindingRankText(pickedBinding)
            tType:SetText(CludesUI.L(typeStr) .. (rankTxt and ("  -  " .. rankTxt) or ""))

            local tName = NewLabel(titleRow, 15, 1, 1, 1, 0.9)
            tName:SetText(CludesUI.L(mod.CC_GetBindingName(pickedBinding)))

            local typeW = tType:GetStringWidth()
            local nameW = tName:GetStringWidth()
            local textW = max(typeW, nameW)
            local iconSz = 32
            local gap = 10
            local totalW = iconSz + gap + textW

            local tIcon = titleRow:CreateTexture(nil, "ARTWORK")
            tIcon:SetSize(iconSz, iconSz)
            tIcon:SetPoint("LEFT", titleRow, "CENTER", -totalW / 2, 0)
            tIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            tIcon:SetTexture(mod.CC_GetBindingIcon(pickedBinding))

            tType:ClearAllPoints()
            tType:SetPoint("TOPLEFT", tIcon, "TOPRIGHT", gap, 0)
            tName:ClearAllPoints()
            tName:SetPoint("BOTTOMLEFT", tIcon, "BOTTOMRIGHT", gap, 0)

            midY = midY - 53
        end

        -- Keybind row (Party Mode style button)
        do
            local line = MakeRow(midY)
            RowLabel(line, "Keybind")
            local function ApplyKey(newKey)
                pickedBinding.key = newKey
                mod.CC_ApplyBindings()
                RedrawPage()
            end
            local keybindBtn = BuildKeybindButton(line, 180, function()
                return pickedBinding.key
            end, function(newKey)
                ApplyKey(newKey)
            end, function()
                pickedBinding.key = nil
                mod.CC_ApplyBindings()
                RedrawPage()
            end)
            Pix.Point(keybindBtn, "RIGHT", line, "RIGHT", -SIDE_PAD, 0)
            midY = midY - ROW_H
        end

        -- Smart Rez row: dead unit runs dynamic rez, living unit fires the
        -- binding's normal action. Only for macro-expressible actions (a [dead]
        -- /cast can lead); target/menu excluded -- no macro fallback (BuildMacroText).
        do
            local t = pickedBinding.type
            local canSmartRez = t == "spell"
                or t == "macro"
                or t == "item"
                or t == "dispel"
                or t == "external"
                or t == "trinket1"
                or t == "trinket2"
            if canSmartRez then
                local line = MakeRow(midY)
                RowLabel(line, "Enable Dynamic Rez")
                RowToggle(line, function()
                    return pickedBinding.smartRez
                end, function(v)
                    pickedBinding.smartRez = v
                    mod.CC_ApplyBindings()
                end)
                midY = midY - ROW_H
            end
        end

        local hasAdvancedOpts = pickedBinding.type == "spell"
            or pickedBinding.type == "macro"
            or pickedBinding.type == "item"
            or pickedBinding.type == "dispel"
            or pickedBinding.type == "external"
            or pickedBinding.type == "trinket1"
            or pickedBinding.type == "trinket2"
            or pickedBinding.type == "dynamicrez"
        -- OOC-Only applies to spell/macro AND menu/target (suppresses the
        -- context menu / targeting in combat); menu/target's combat-gating is
        -- enforced securely via an attribute driver (see SetGatedType).
        if hasAdvancedOpts or pickedBinding.type == "menu" or pickedBinding.type == "target" then
            local line = MakeRow(midY)
            local oocLabel = "Only Cast Out of Combat"
            if pickedBinding.type == "menu" then
                oocLabel = "Only Open Menu Out of Combat"
            elseif pickedBinding.type == "target" then
                oocLabel = "Only Target Out of Combat"
            end
            RowLabel(line, oocLabel)
            RowToggle(line, function()
                return pickedBinding.oocOnly
            end, function(v)
                pickedBinding.oocOnly = v
                mod.CC_ApplyBindings()
            end)
            midY = midY - ROW_H
        end

        -- Content gate row: which content this binding is active in.
        -- Outside the chosen contexts the binding is simply not applied, so
        -- its key keeps doing whatever the player normally has bound.
        do
            local line = MakeRow(midY)
            RowLabel(line, "Active In")
            -- Same checkbox dropdown the buff manager's filter pickers use, so
            -- any combination of Solo / Party / Raid can be ticked. It renders
            -- the summary itself ("All" when everything is on, "None" when
            -- nothing is). groupCtx stays nil while all three are on -- that is
            -- the default, so untouched bindings store nothing.
            local ctxItems = {
                {
                    key = "solo",
                    label = "Solo",
                    tooltip = "Active while you are not in a group.",
                },
                { key = "party", label = "Party", tooltip = "Active in a PvE party." },
                { key = "raid", label = "Raid", tooltip = "Active in a PvE raid." },
                {
                    key = "pvp",
                    label = "PvP",
                    tooltip = "Active in battlegrounds and arenas.",
                },
            }
            local cbDD = CludesUI.BuildVisOptsCBDropdown(
                line,
                160,
                line:GetFrameLevel() + 2,
                ctxItems,
                function(bindKey)
                    return CtxEnabled(pickedBinding, bindKey)
                end,
                function(bindKey, v)
                    -- nil means all-on, so materialize the full set before the
                    -- first tick turns one context off; collapse back to nil
                    -- once everything is on again.
                    local set = pickedBinding.groupCtx
                    if not set then
                        set = {}
                        for _, gridC in ipairs(CC_CTX_ORDER) do
                            set[gridC] = true
                        end
                        pickedBinding.groupCtx = set
                    end
                    set[bindKey] = v and true or false
                    local num = 0
                    for _, gridC in ipairs(CC_CTX_ORDER) do
                        if set[gridC] == true then
                            num = num + 1
                        end
                    end
                    if num == #CC_CTX_ORDER then
                        pickedBinding.groupCtx = nil
                    end
                    mod.CC_ApplyBindings()
                end,
                nil,
                #CC_CTX_ORDER
            )
            Pix.Point(cbDD, "RIGHT", line, "RIGHT", -SIDE_PAD, 0)
            midY = midY - ROW_H
        end

        if hasAdvancedOpts then
            -- Hovercast row: a dropdown rather than a third toggle so the row
            -- count (and the page height) is unchanged -- the center column has
            -- no spare row.
            -- Hovercast is unavailable for bare left/right click, so those two
            -- entries are shown disabled with the reason as a tooltip.
            do
                local line = MakeRow(midY)
                local isBareMouseBtn = pickedBinding.key == "BUTTON1" or pickedBinding.key == "BUTTON2"
                RowLabel(line, "Cast On")
                if isBareMouseBtn and pickedBinding.hovercast then
                    pickedBinding.hovercast = false
                    mod.CC_ApplyBindings()
                end
                local hcValues = {
                    frames = "Frames",
                    units = "Mouseover",
                    both = "Frames and Mouseover",
                }
                local hcOrder = { "frames", "units", "both" }
                local ddCtrl = CludesUI.BuildDropdownControl(
                    line,
                    160,
                    line:GetFrameLevel() + 2,
                    hcValues,
                    hcOrder,
                    function()
                        if pickedBinding.hovercast == "both" then
                            return "both"
                        end
                        return pickedBinding.hovercast and "units" or "frames"
                    end,
                    function(v)
                        pickedBinding.hovercast = (v == "both" and "both")
                            or (v == "units" and true)
                            or false
                        mod.CC_ApplyBindings()
                        RedrawPage()
                    end,
                    function(bindKey)
                        if isBareMouseBtn and bindKey ~= "frames" then
                            return CludesUI.L("Hovercast is not available for unmodified left/right click")
                        end
                        return false
                    end
                )
                Pix.Point(ddCtrl, "RIGHT", line, "RIGHT", -SIDE_PAD, 0)
                midY = midY - ROW_H
            end

            -- Spell and item reactions use the same Friendly/Enemy toggles as
            -- Hovercast. Frame-only custom macros cannot safely share a key
            -- with a complementary action, so they do not expose reactions.
            if
                pickedBinding.type == "spell"
                or pickedBinding.type == "item"
                or pickedBinding.hovercast
            then
                do
                    local line = MakeRow(midY)
                    RowLabel(line, "    Unit Types")
                    local ePill = RowToggle(line, function()
                        return pickedBinding.hoverEnemy == true
                    end, function(v)
                        pickedBinding.hoverEnemy = v
                        mod.CC_ApplyBindings()
                        RedrawPage()
                    end)
                    local eLbl = NewLabel(line, 13, 1, 1, 1, 0.8)
                    eLbl:SetPoint("RIGHT", ePill, "LEFT", -8, 0)
                    eLbl:SetText(CludesUI.L("Enemy"))

                    local fPill = RowToggle(line, function()
                        return pickedBinding.hoverFriendly ~= false
                    end, function(v)
                        pickedBinding.hoverFriendly = v
                        mod.CC_ApplyBindings()
                        RedrawPage()
                    end)
                    fPill:ClearAllPoints()
                    Pix.Point(fPill, "RIGHT", eLbl, "LEFT", -18, 0)
                    local fLbl = NewLabel(line, 13, 1, 1, 1, 0.8)
                    fLbl:SetPoint("RIGHT", fPill, "LEFT", -8, 0)
                    fLbl:SetText(CludesUI.L("Friendly"))
                    midY = midY - ROW_H
                end
                if pickedBinding.type == "spell" or pickedBinding.type == "item" then
                    local note = NewLabel(bodyHost, 11, 1, 1, 1, 0.45)
                    note:SetPoint("TOPLEFT", bodyHost, "TOPLEFT", C_PAD + SIDE_PAD + 20, midY - 5)
                    note:SetText(CludesUI.L("Disabling both disables this binding."))
                    midY = midY - 22
                end
            end
        end
    else
        local hint = NewLabel(bodyHost, 12, 1, 1, 1, 0.25)
        hint:SetPoint("TOP", bodyHost, "TOP", 0, midY - 50)
        hint:SetJustifyH("CENTER")
        hint:SetText(CludesUI.L("Select a binding from either sidebar to edit its options"))
        midY = midY - 90
    end
    CC.Card(bodyHost, C_PAD - 8, perTop, rowW + 16, midY - 8)

    -- SPELL STRIP (right edge, always visible): narrow scrollable column of
    -- class/spec spell icons. Click to add. Built on the first page build and
    -- re-dressed on every later one; its icon cells are pooled by index.
    do
        local SS_ICON = 32
        local SS_PAD = 10
        local SS_GAP = 4

        -- Parent to the CUI panel (outside the scroll system) so it's flush with the window edge
        local cuiPanel = scrollFrame:GetParent()
        local host = cuiPanel or root
        local stripFrame = mod._ccSpellStrip
        if not stripFrame then
            stripFrame = CreateFrame("Frame", nil, host)
            -- Held across renders: never handed out again by the options page
            -- pool should it be made on a pool host (a no-op on the panel).
            POOL.Keep(stripFrame)
            stripFrame:SetFrameLevel(host:GetFrameLevel() + 10)
            local stripBg = stripFrame:CreateTexture(nil, "BACKGROUND")
            stripBg:SetAllPoints()
            stripBg:SetColorTexture(0, 0, 0, 0.6)
            local stripOverlay = CreateFrame("Frame", nil, stripFrame)
            stripOverlay:SetAllPoints()
            stripOverlay:SetFrameLevel(stripFrame:GetFrameLevel() + 20)
            stripOverlay:EnableMouse(false)
            local overlayTex = stripOverlay:CreateTexture(nil, "OVERLAY")
            overlayTex:SetAllPoints()
            overlayTex:SetColorTexture(0, 0, 0, 0.5)
            -- Hover look, applied once per frame; a page build drops a queued
            -- update by clearing _pending.
            local function StripUpdate()
                if not stripFrame._pending then
                    return
                end
                stripFrame._pending = false
                if stripFrame._wantHover then
                    stripFrame:SetAlpha(1)
                    overlayTex:SetAlpha(0)
                else
                    stripFrame:SetAlpha(0.35)
                    overlayTex:SetAlpha(0.5)
                end
            end
            local function StripEnter()
                stripFrame._wantHover = true
                if not stripFrame._pending then
                    stripFrame._pending = true
                    C_Timer.After(0, StripUpdate)
                end
            end
            local function StripLeave()
                stripFrame._wantHover = false
                if not stripFrame._pending then
                    stripFrame._pending = true
                    C_Timer.After(0, StripUpdate)
                end
            end

            stripFrame:SetScript("OnEnter", StripEnter)
            stripFrame:SetScript("OnLeave", StripLeave)

            local stripScroll = CreateFrame("ScrollFrame", nil, stripFrame)
            stripScroll:SetPoint("TOPLEFT", stripFrame, "TOPLEFT", 0, -SS_PAD)
            stripScroll:SetPoint("BOTTOMRIGHT", stripFrame, "BOTTOMRIGHT", 0, SS_PAD)
            stripScroll:SetFrameLevel(stripFrame:GetFrameLevel() + 1)
            local stripChild = CreateFrame("Frame", nil, stripScroll)
            stripChild:SetWidth(SPELL_STRIP_W)
            stripScroll:SetScrollChild(stripChild)
            stripScroll:EnableMouseWheel(true)
            stripScroll:SetScript("OnMouseWheel", function(self, change)
                local scrollY = self:GetVerticalScroll()
                local mx = max(0, stripChild:GetHeight() - self:GetHeight())
                self:SetVerticalScroll(max(0, min(mx, scrollY - change * 30)))
            end)

            stripFrame._overlay, stripFrame._overlayTex = stripOverlay, overlayTex
            stripFrame._scroll, stripFrame._child = stripScroll, stripChild
            stripFrame._enter, stripFrame._leave = StripEnter, StripLeave
            stripFrame._cells = {}
            mod._ccSpellStrip = stripFrame
        end
        -- Every build starts the strip from the look a new one has: resting
        -- alpha, scrolled to the top, no queued hover update.
        if stripFrame:GetParent() ~= host then
            stripFrame:SetParent(host)
        end
        stripFrame:SetSize(SPELL_STRIP_W, visibleH)
        stripFrame:ClearAllPoints()
        stripFrame:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 0, 0)
        stripFrame:SetFrameLevel(host:GetFrameLevel() + 10)
        stripFrame._overlay:SetFrameLevel(stripFrame:GetFrameLevel() + 20)
        stripFrame._scroll:SetFrameLevel(stripFrame:GetFrameLevel() + 1)
        stripFrame._pending = false
        stripFrame._wantHover = false
        stripFrame:SetAlpha(0.35)
        stripFrame._overlayTex:SetAlpha(1)
        local stripScroll, stripChild = stripFrame._scroll, stripFrame._child
        local StripEnter, StripLeave = stripFrame._enter, stripFrame._leave
        local cells = stripFrame._cells
        stripScroll:SetVerticalScroll(0)
        stripFrame:Show()

        -- Icons only here: a WoW Forever spell shows its top rank alone (the
        -- lower ranks are picked from the Add and Quickbind grids, which label them).
        local spellList = mod.CC_GetClassSpells(true)
        local stripY = 0
        for i, spellRec in ipairs(spellList) do
            local cellFrame = cells[i]
            if not cellFrame then
                cellFrame = CreateFrame("Button", nil, stripChild)
                cellFrame:SetSize(SS_ICON, SS_ICON)
                local iconTexture = cellFrame:CreateTexture(nil, "ARTWORK")
                iconTexture:SetAllPoints()
                iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                local iconEdge = CreateFrame("Frame", nil, cellFrame)
                iconEdge:SetAllPoints()
                iconEdge:SetFrameLevel(cellFrame:GetFrameLevel() + 1)
                iconEdge:Hide()
                if Pix then
                    Pix.CreateBorder(iconEdge, accentColor.r, accentColor.g, accentColor.b, 1, 2)
                end
                cellFrame._tex, cellFrame._bd = iconTexture, iconEdge
                cells[i] = cellFrame
            end
            cellFrame:ClearAllPoints()
            cellFrame:SetPoint("TOPLEFT", stripChild, "TOPLEFT", 10, stripY)
            cellFrame:Show()

            local iconTexture, iconEdge = cellFrame._tex, cellFrame._bd
            iconTexture:SetTexture(spellRec.icon or 134400)
            local alreadyBound = mod.CC_IsSpellBound(boundSpells, spellRec.id, spellRec.name)
            iconTexture:SetAlpha(alreadyBound and 0.3 or 1)
            iconEdge:Hide()
            if Pix then
                Pix.SetBorderColor(iconEdge, accentColor.r, accentColor.g, accentColor.b, 1)
            end

            cellFrame:SetScript("OnEnter", function()
                iconEdge:Show()
                StripEnter()
                if not mod.CC_RankTip(cellFrame, spellRec) then
                    CludesUI.ShowWidgetTooltip(cellFrame, spellRec.name)
                end
            end)
            cellFrame:SetScript("OnLeave", function()
                iconEdge:Hide()
                StripLeave()
                CludesUI.HideWidgetTooltip()
            end)
            cellFrame:SetScript("OnClick", function()
                mod.CC_AddSpecBinding({
                    type = "spell",
                    spell = spellRec.name,
                    spellID = spellRec.id,
                    icon = spellRec.icon,
                    enabled = true,
                    oocOnly = false,
                    hovercast = false,
                    hoverFriendly = true,
                    hoverEnemy = true,
                })
                mod._ccSelSide = "spec"
                mod._ccSelIndex = #(GetSpecBindings())
                RedrawPage()
            end)

            stripY = stripY - (SS_ICON + SS_GAP)
        end
        for i = #spellList + 1, #cells do
            cells[i]:Hide()
        end
        stripChild:SetHeight(max(10, math.abs(stripY)))
        -- A strip frame holding the mouse focus is reused in place, so it never
        -- gets the OnEnter a new strip would: replay it.
        if not CC_ReplayFocusEnter(cells, #spellList) then
            local foci = GetMouseFoci and GetMouseFoci()
            if foci then
                for modKey = 1, #foci do
                    if foci[modKey] == stripFrame then
                        StripEnter()
                        break
                    end
                end
            end
        end
    end

    -- Click-casting off: whole UI gates on Enable. Sidebars dim to 60% alpha +
    -- swallow clicks via a black overlay; center's gated body dims + blocks
    -- clicks (the Enable row itself stays interactive on centerFrame above).
    if not clickDB.enabled then
        for _, scrollBar in ipairs({ listPane, rightFrame }) do
            scrollBar:SetAlpha(0.6)
            local shade = CreateFrame("Frame", nil, root)
            shade:SetAllPoints(scrollBar)
            shade:SetFrameLevel(scrollBar:GetFrameLevel() + 100)
            shade:EnableMouse(true)
            shade:EnableMouseWheel(true)
            shade:SetScript("OnMouseWheel", function() end)
            local ovTex = shade:CreateTexture(nil, "OVERLAY")
            ovTex:SetAllPoints()
            ovTex:SetColorTexture(0.08, 0.08, 0.08, 0.4)
        end

        midBody:SetAlpha(0.4)
        -- Block only the gated region (below the Enable row) so the toggle stays usable.
        local blocker = CreateFrame("Frame", nil, midBody)
        blocker:SetPoint("TOPLEFT", midBody, "TOPLEFT", 0, gatedTop)
        blocker:SetPoint("BOTTOMRIGHT", midBody, "BOTTOMRIGHT", 0, 0)
        blocker:SetFrameLevel(midBody:GetFrameLevel() + 100)
        blocker:EnableMouse(true)
        blocker:EnableMouseWheel(true)
        blocker:SetScript("OnMouseWheel", function() end)
    end

    CludesUI._EndRootRender("rf.cc")
    return 0 -- bypass framework scroll (custom root)
end
