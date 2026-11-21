if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_AuraBuffReminders_Refresh.lua
--
--  The WoW Forever collectors, Refresh and its throttle, the Forever group
--  watch and the duration ticker.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._abrInternals
-- CludesUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local floor = math.floor

local CacheInstanceInfo, REMIND, GetPlayerClass = Inner.CacheInstanceInfo, Inner.EABR, Inner.GetPlayerClass
local GetSpecID, InCombat, InMythicPlusKey = Inner.GetSpecID, Inner.InCombat, Inner.InMythicPlusKey
local InPvPInstance, InRealInstancedContent = Inner.InPvPInstance, Inner.InRealInstancedContent
local isSecret, Known, ShortLabel, SpellName = Inner.isSecret, Inner.Known, Inner.ShortLabel, Inner.SpellName
local Tex, _unitInRange, _unitOk = Inner.Tex, Inner._unitInRange, Inner._unitOk
local BuildPlayerAuraCache, PlayerHasAuraByID = Inner.BuildPlayerAuraCache, Inner.PlayerHasAuraByID
local PET_CLASSES, RAID_BUFFS, WARLOCK_PETS = Inner.PET_CLASSES, Inner.RAID_BUFFS, Inner.WARLOCK_PETS
local _dismissedUntilLoad, AcquireEntry = Inner._dismissedUntilLoad, Inner.AcquireEntry
local ApplyGlow, combatActiveIcons = Inner.ApplyGlow, Inner.combatActiveIcons
local cursorActiveIcons, FadeOutSecureIcons = Inner.cursorActiveIcons, Inner.FadeOutSecureIcons
local HideCombatIcons, HideCursorIcons = Inner.HideCombatIcons, Inner.HideCursorIcons
local ICON_SIZE, IsImportantBuff = Inner.ICON_SIZE, Inner.IsImportantBuff
local LayoutCombatIcons, LayoutCursorIcons = Inner.LayoutCombatIcons, Inner.LayoutCursorIcons
local ResetEntryPool, ShowCombatIcon = Inner.ResetEntryPool, Inner.ShowCombatIcon
local ShowCursorIcon, CollectAuras = Inner.ShowCursorIcon, Inner.CollectAuras
local CollectConsumables, CollectRaidBuffs = Inner.CollectConsumables, Inner.CollectRaidBuffs
local InkyMapWatch = Inner.InkyMapWatch
local HideAllIcons, LayoutIcons, ShowIcon = Inner.HideAllIcons, Inner.LayoutIcons, Inner.ShowIcon
local SetCachedOutline, CursorAttachActive = Inner.SetCachedOutline, Inner.CursorAttachActive
local CachedGetItemCount, GetWeaponCategory = Inner.CachedGetItemCount, Inner.GetWeaponCategory

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end
local cuiPanelOpen = false
Inner.panelOpenSetters[#Inner.panelOpenSetters + 1] = function(val)
    cuiPanelOpen = val
end
local iconAnchor
Inner.iconAnchorSetters[#Inner.iconAnchorSetters + 1] = function(val)
    iconAnchor = val
end
local combatAnchor
Inner.combatAnchorSetters[#Inner.combatAnchorSetters + 1] = function(val)
    combatAnchor = val
end
local cursorHolder
Inner.cursorAnchorSetters[#Inner.cursorAnchorSetters + 1] = function(val)
    cursorHolder = val
end

local refreshQueued = false

-- Reusable tables wiped each Refresh() call to avoid per-call allocation.
local _refreshMissing = {}
local UpdateDurationTicker -- forward-declare; defined after RequestRefresh

-- WoW Forever rank families of the custom spell IDs: an ID stands for itself,
-- every spellbook entry with its name (each rank the player knows is its own
-- spell there) and the shared buff family that lists it (every rank, the group
-- version, other casters' versions: CludesUI.FOREVER_BUFF_FAMILIES). One
-- spellbook pass resolves every tracked ID, run again only after a spell is
-- learned (LEARNED_SPELL_IN_SKILL_LINE sets _fvFamDirty), after any spellbook
-- change while the Action Picker listens (SPELLS_CHANGED: a respec can take a
-- spell away), when the picker is turned on or off, or when an ID joins the
-- list; the families then serve every refresh as they are. With the picker
-- on, a family's EABR._fvKnownFams entry is the list of its known ranks,
-- lowest first as the spellbook lists them (one list per name), else the last
-- rank found.
local function PickerEnabled()
    local frameOrder = saved.profile.forever
    return frameOrder ~= nil and frameOrder.pickerEnabled == true
end

function REMIND.ForeverFamily(ident)
    local fams = REMIND._fvFams
    if not (fams and fams[ident]) or REMIND._fvFamDirty or REMIND._fvRanksEnabled ~= PickerEnabled() then
        REMIND.BuildForeverFamilies()
        fams = REMIND._fvFams
    end
    return fams[ident]
end

function REMIND.BuildForeverFamilies()
    REMIND._fvFamDirty = false
    local pickerEnabled = PickerEnabled()
    REMIND._fvRanksEnabled = pickerEnabled
    local fams = REMIND._fvFams
    if fams then
        wipe(fams)
    else
        fams = {}
        REMIND._fvFams = fams
    end
    -- The families with a rank in this character's spellbook (spell groups:
    -- EABR.CollectForeverGroups), from the same pass.
    local known = REMIND._fvKnownFams
    if known then
        wipe(known)
    else
        known = {}
        REMIND._fvKnownFams = known
    end
    -- The rank each cast-by-name reminder resolves to is read again too.
    if REMIND._fvTopRank then
        wipe(REMIND._fvTopRank)
    end
    local frameOrder = saved.profile.forever
    local custom = frameOrder and frameOrder.customIDs
    local groups = frameOrder and frameOrder.customGroups
    if not ((custom and custom[1]) or (groups and groups[1])) then
        return
    end
    local familyOf = REMIND._fvFamilyOf
    if not familyOf then
        familyOf = {}
        for _, shared in pairs(CludesUI.FOREVER_BUFF_FAMILIES) do
            for _, spellRef in ipairs(shared.ids) do
                familyOf[spellRef] = shared
            end
        end
        REMIND._fvFamilyOf = familyOf
    end
    -- name -> the families its spellbook entries join
    local byName = {}
    local function buildFamilyFor(spellId)
        if type(spellId) ~= "number" or fams[spellId] then
            return
        end
        local entries = { spellId }
        local shared = familyOf[spellId]
        if shared then
            for _, spellRef in ipairs(shared.ids) do
                if spellRef ~= spellId then
                    entries[#entries + 1] = spellRef
                end
            end
        end
        fams[spellId] = entries
        local label = SpellName(spellId)
        if label then
            local into = byName[label]
            if not into then
                into = {}
                byName[label] = into
            end
            into[#into + 1] = entries
        end
    end
    if custom then
        for _, spellId in ipairs(custom) do
            buildFamilyFor(spellId)
        end
    end
    -- Group members get the same rank expansion, from the same spellbook pass.
    if groups then
        for _, set in ipairs(groups) do
            local groupSpellIDs = type(set) == "table" and set.ids
            if type(groupSpellIDs) == "table" then
                for _, spellId in ipairs(groupSpellIDs) do
                    buildFamilyFor(spellId)
                end
            end
        end
    end
    if not next(byName) then
        return
    end
    local bank = Enum.SpellBookSpellBank.Player
    local SPELL = Enum.SpellBookItemType.Spell
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local details = C_SpellBook.GetSpellBookSkillLineInfo(line)
        local offset = details and details.itemIndexOffset or 0
        for slot = offset + 1, offset + (details and details.numSpellBookItems or 0) do
            local kind, _, spellRef = C_SpellBook.GetSpellBookItemType(slot, bank)
            local into = kind == SPELL and spellRef and byName[C_Spell.GetSpellName(spellRef)]
            if into then
                local cast = spellRef
                if pickerEnabled then
                    cast = known[into[1]] or {}
                    if not tContains(cast, spellRef) then
                        cast[#cast + 1] = spellRef
                    end
                end
                for _, entries in ipairs(into) do
                    local listed = false
                    for k = 1, #entries do
                        if entries[k] == spellRef then
                            listed = true
                            break
                        end
                    end
                    if not listed then
                        entries[#entries + 1] = spellRef
                    end
                    known[entries] = cast
                end
            end
        end
    end
end

function REMIND.ForeverGroupCastSpell(set, spellId, family)
    local rankList
    if set.ranksBySpell then
        rankList = set.ranksBySpell[spellId]
    else
        family = family
            or (type(spellId) == "number" and SpellName(spellId) and REMIND.ForeverFamily(spellId))
        rankList = family and REMIND._fvKnownFams[family]
    end
    if type(rankList) ~= "table" then
        return
    end
    local prefs = set.settings or set
    local pinned = prefs.castRanks and prefs.castRanks[spellId]
    if pinned then
        for index, ident in ipairs(rankList) do
            if ident == pinned then
                if index == #rankList then
                    break
                end
                local _, rank = REMIND.ForeverPickerSpellData(ident, true)
                if rank then
                    return ident, rankList, index
                end
                break
            end
        end
    end
    return rankList[#rankList], rankList, #rankList
end

local function SetForeverPickerSpell(record, set, ident, rankList)
    local macroText, rank = REMIND.ForeverPickerSpellData(ident, #rankList > 1)
    if not macroText then
        return
    end
    record.mode = "macro"
    record.macro = macroText
    record.spellID = ident
    record.foreverGroup = set
    record.spellRank = rank
end

-- The click of a WoW Forever reminder that casts its spell by name (a spell
-- group, or a custom spell the character knows): /cast [@player] <name>, which
-- casts the highest rank in the spellbook, and that rank for the tooltip, read
-- by name as /cast reads it (the rank lists are not in rank order: a stored ID
-- leads its list). Both are kept per name: the macro for the session, the rank
-- until the families are rebuilt (BuildForeverFamilies wipes EABR._fvTopRank).
-- The section never shows in combat, so the macro can always be set.
local castMacros = {}

local function CastByName(record, castName, fallbackID)
    local macroText = castMacros[castName]
    if not macroText then
        macroText = "/cast [@player] " .. castName
        castMacros[castName] = macroText
    end
    local tops = REMIND._fvTopRank
    if not tops then
        tops = {}
        REMIND._fvTopRank = tops
    end
    local topY = tops[castName]
    if topY == nil then
        -- By name the client answers the highest rank in the spellbook.
        local details = C_Spell.GetSpellInfo(castName)
        if details then
            topY = C_SpellBook.IsSpellKnown(details.spellID) and details.spellID or false
            tops[castName] = topY
        end
    end
    record.mode = "macro"
    record.macro = macroText
    record.spellID = topY or fallbackID
end

-- WoW Forever spell groups: one reminder per group while no aura from its
-- spells (or their ranks, EABR.ForeverFamily) is active, out of combat only.
-- While the client hides aura data from addons (AuraKit.AurasRestricted), a
-- group counts as having no active aura only if none of its spells is flagged
-- secret, so a hidden aura is not read as absent. A group shows only for a
-- character that knows one of its spells (a rank in the spellbook): groups are
-- profile settings, so one made on another class shows nothing here. The icon
-- uses the selected spell or the first known member. Groups covered by
-- enabled class buff reminders stand down.
local function GroupCovered(spellIDs, ids, nameList)
    local anyMissing = false
    for _, spellId in ipairs(spellIDs) do
        if type(spellId) == "number" then
            local label = SpellName(spellId)
            if not (ids[spellId] or (label and nameList[label])) then
                return false
            end
            anyMissing = true
        end
    end
    return anyMissing
end

function REMIND.CollectForeverGroups(missing, groups, coveredIDs, coveredNames)
    local dismissKeys = REMIND._fvGroupKeys
    if not dismissKeys then
        dismissKeys = setmetatable({}, { __mode = "k" })
        REMIND._fvGroupKeys = dismissKeys
        REMIND._fvGroupN = 0
    end
    local aurasRestricted = CludesUI.AuraKit and CludesUI.AuraKit.AurasRestricted()
    local pickerEnabled = PickerEnabled()
    for _, set in ipairs(groups) do
        local spellIDs = type(set) == "table" and set.ids
        if
            type(spellIDs) == "table"
            and not (coveredIDs and GroupCovered(spellIDs, coveredIDs, coveredNames))
        then
            local iconSpellID, castSpellID, hasActiveAura
            local firstRanks, castRanks, hasChoices
            local allAurasReadable = true
            for _, spellId in ipairs(spellIDs) do
                local rankSpellIDs = type(spellId) == "number"
                    and SpellName(spellId)
                    and REMIND.ForeverFamily(spellId)
                if rankSpellIDs then
                    if pickerEnabled then
                        local knownSpellID, rankList = REMIND.ForeverGroupCastSpell(set, spellId, rankSpellIDs)
                        if knownSpellID then
                            firstRanks = firstRanks or rankList
                            if rankList ~= firstRanks then
                                hasChoices = true
                            end
                            if not castSpellID or spellId == set.castSpellID then
                                iconSpellID, castSpellID, castRanks = knownSpellID, knownSpellID, rankList
                            end
                        end
                    elseif not iconSpellID and REMIND._fvKnownFams[rankSpellIDs] then
                        iconSpellID = spellId
                    end
                    hasActiveAura = PlayerHasAuraByID(rankSpellIDs)
                    if hasActiveAura then
                        break
                    end
                    if aurasRestricted and not REMIND.FvRanksReadable(rankSpellIDs) then
                        allAurasReadable = false
                    end
                end
            end
            if iconSpellID and allAurasReadable and not hasActiveAura then
                local dismissKey = dismissKeys[set]
                if not dismissKey then
                    REMIND._fvGroupN = REMIND._fvGroupN + 1
                    dismissKey = "forever:g" .. REMIND._fvGroupN
                    dismissKeys[set] = dismissKey
                end
                local record = AcquireEntry()
                local castName = SpellName(iconSpellID)
                record.texture = Tex(iconSpellID)
                if castSpellID then
                    SetForeverPickerSpell(record, hasChoices and set or nil, castSpellID, castRanks)
                else
                    CastByName(record, castName, iconSpellID)
                end
                record.label = type(set.name) == "string" and set.name or ShortLabel(castName)
                record.cat = "forever"
                record.dismissKey = dismissKey
                missing[#missing + 1] = record
            end
        end
    end
end

-- One pass over the minimap trackers, for those that are no auras there:
-- whether Find Treasure is up (it stacks with any other tracking) and whether
-- another spell tracking is (a class one: the gathering ones are already ruled
-- out by their aura when this runs, and those share one slot with it). The
-- answer is kept until the tracking can have changed (EABR._fvTrackDirty):
-- MINIMAP_UPDATE_TRACKING, a learned spell, a loading screen, and every new
-- registration of that event, since nothing is heard while it is off.
function REMIND.FvTrackingState()
    if REMIND._fvTrackDirty ~= false then
        REMIND._fvTrackDirty = false
        local treasure, classKey = false, false
        for index = 1, C_Minimap.GetNumTrackingTypes() do
            local details = C_Minimap.GetTrackingInfo(index)
            if details and details.active and details.type == "spell" then
                if details.spellID == REMIND.FIND_TREASURE then
                    treasure = true
                else
                    classKey = true
                end
            end
        end
        REMIND._fvTreasureUp, REMIND._fvClassUp = treasure, classKey
    end
    return REMIND._fvTreasureUp, REMIND._fvClassUp
end

-- A cast-on-click reminder for a WoW Forever spell (gathering, Find Treasure,
-- the mage armors, class buffs), labelled with the spell's name unless a
-- label is given.
function REMIND.FvSpellEntry(missing, ident, dismissKey, labelText)
    local entry = AcquireEntry()
    entry.mode = "spell"
    entry.spellID = ident
    entry.label = labelText or ShortLabel(SpellName(ident) or tostring(ident))
    entry.cat = "forever"
    entry.dismissKey = dismissKey
    missing[#missing + 1] = entry
    return entry
end

-- Whether the player's own aura of a spell is up: true, false (absent or
-- another caster's), or nil when a secret or unreadable answer cannot tell.
local function OwnAuraState(ident)
    local success, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ident)
    if not success or isSecret(aura) then
        return nil
    end
    if aura == nil then
        return false
    end
    local okMine, mine = pcall(REMIND._StrictAuraFromMe, aura)
    if not okMine or isSecret(mine) then
        return nil
    end
    return mine
end

-- Whether any rank in a list is up (ids: the one-slot lookup): true, false,
-- or nil while an own-only read cannot tell.
local function RanksState(rankList, ids, own)
    local unknown
    for jdx = 1, #rankList do
        if own then
            local status = OwnAuraState(rankList[jdx])
            if status then
                return true
            end
            if status == nil then
                unknown = true
            end
        else
            ids[1] = rankList[jdx]
            if PlayerHasAuraByID(ids) then
                return true
            end
        end
    end
    if unknown then
        return nil
    end
    return false
end

local function LineState(lines, index, ids, also, own)
    local status = RanksState(lines[index], ids, own)
    if status then
        return true
    end
    local extra = also and also[index]
    if extra then
        local extraState = RanksState(extra, ids, own)
        if extraState then
            return true
        end
        if extraState == nil then
            status = nil
        end
    end
    return status
end

local function LineReadable(lines, index, also)
    local extra = also and also[index]
    return REMIND.FvRanksReadable(lines[index]) and not (extra and not REMIND.FvRanksReadable(extra))
end

-- One reminder while no rank of any line is up (the mage armors, a class
-- buff). Returns the index of the line up, which the caller records for this
-- character (a profile is shared by every character on it), or false while
-- the reminder is held back without a line to record. The icon and the click
-- then follow the line last seen up, with no event of their own (the player's
-- UNIT_AURA already drives the refresh). Nothing up casts the strongest rank
-- known of that line, else the strongest line known. The recorded line (last)
-- is read first: the line up is nearly always it. own: only the player's own
-- aura is found and recorded; anyCounts: another caster's still holds the
-- reminder back, unrecorded.
local function CollectLines(missing, auraLock, ids, lines, last, dismissKey, labelText, also, own, anyCounts)
    local first = lines[last] and last
    local unknown = false
    if first then
        local status = LineState(lines, first, ids, also, own)
        if status then
            return first
        end
        if status == nil then
            unknown = true
        end
    end
    local readable = not (auraLock and first and not LineReadable(lines, first, also))
    for index = 1, #lines do
        if index ~= first then
            local status = LineState(lines, index, ids, also, own)
            if status then
                return index
            end
            if status == nil then
                unknown = true
            end
            if auraLock and not LineReadable(lines, index, also) then
                readable = false
            end
        end
    end
    -- Under the aura lock an unreadable rank would read absent: say nothing.
    if unknown or not readable then
        return false
    end
    if anyCounts then
        for index = 1, #lines do
            if LineState(lines, index, ids, also, false) then
                return false
            end
        end
    end
    local ident = first and REMIND.FvHighest(lines[first])
    if not ident then
        for index = #lines, 1, -1 do
            ident = REMIND.FvHighest(lines[index])
            if ident then
                break
            end
        end
    end
    if ident then
        return nil, REMIND.FvSpellEntry(missing, ident, dismissKey, labelText)
    end
end

local function CharStore(field)
    local storage = CludesUIDB[field]
    local keyList = REMIND._fvCharKeys
    if not keyList then
        keyList = {}
        REMIND._fvCharKeys = keyList
    end
    local key = keyList[field]
    if not key then
        key = CludesUI.CharKey("-", storage)
        keyList[field] = key
    end
    return storage, key
end

-- Mage armors (WoW Forever): one reminder while no rank of Frost Armor, Ice
-- Armor or Mage Armor is up; the line up is recorded in
-- CludesUIDB.mageArmorByChar by CludesUI.CharKey.
function REMIND.CollectMageArmor(missing, auraLock, ids)
    local storage, key = CharStore("mageArmorByChar")
    local last = storage and key and storage[key]
    local up = CollectLines(
        missing,
        auraLock,
        ids,
        REMIND.MAGE_ARMORS,
        last,
        "forever:magearmor",
        CludesUI.L("Armor")
    )
    if up and up ~= last and key then
        if not storage then
            storage = {}
            CludesUIDB.mageArmorByChar = storage
        end
        storage[key] = up
    end
end

-- Whether a class buff is ticked: the user's pick, else its default (each
-- class's always-on buffs ticked; Thorns, Righteous Fury and Shadowform not).
local function ClassBuffOn(buffRec, picks)
    local val = picks and picks[buffRec.key]
    if val == nil then
        return buffRec.on == true
    end
    return val == true
end
REMIND.FvClassBuffOn = ClassBuffOn

-- The spells the ticked class buffs track, by ID and by name (every rank, the
-- Greater Blessings and the up-only extras included). A custom spell, or a
-- spell group made only of them, stands down while Class Buffs covers it and
-- is back once that buff is unticked: a reminder the user made before Class
-- Buffs existed is never shown twice and never deleted. Rebuilt only when the
-- class or the ticked set changes; nil while none is ticked.
local coveredIDs, coveredNames, coveredMask, coveredClass = {}, {}, nil, nil
local function CoverLines(lines)
    if not lines then
        return
    end
    for index = 1, #lines do
        local rankList = lines[index]
        for jdx = 1, #rankList do
            local ident = rankList[jdx]
            coveredIDs[ident] = true
            local label = SpellName(ident)
            if label then
                coveredNames[label] = true
            end
        end
    end
end
function REMIND.FvClassTracked(frameOrder, classKey)
    local entries = REMIND.FvClassBuffs()[classKey]
    if not entries then
        return nil
    end
    local picks = frameOrder.classBuffPicks
    local mask, bit = 0, 1
    for index = 1, #entries do
        if ClassBuffOn(entries[index], picks) then
            mask = mask + bit
        end
        bit = bit * 2
    end
    if mask == 0 then
        return nil
    end
    if mask ~= coveredMask or classKey ~= coveredClass then
        wipe(coveredIDs)
        wipe(coveredNames)
        for index = 1, #entries do
            local buffRec = entries[index]
            if ClassBuffOn(buffRec, picks) then
                CoverLines(buffRec.lines)
                CoverLines(buffRec.also)
            end
        end
        coveredMask, coveredClass = mask, classKey
    end
    return coveredIDs, coveredNames
end

local function BuildClassBuffPicker(buffRec, actions, prefs)
    local set = { ids = {}, ranksBySpell = {}, actions = actions, key = buffRec.key, settings = prefs }
    for _, line in ipairs(buffRec.lines) do
        local rankList = {}
        for _, ident in ipairs(line) do
            if C_SpellBook.IsSpellKnown(ident) and SpellName(ident) then
                rankList[#rankList + 1] = ident
            end
        end
        if rankList[1] then
            set.ids[#set.ids + 1] = line[1]
            set.ranksBySpell[line[1]] = rankList
        end
    end
    return set
end

local function ClassPickerSpell(set, defaultID)
    local prefs = set.settings
    if prefs then
        local ident, rankList = REMIND.ForeverGroupCastSpell(set, prefs.castSpellID)
        if ident then
            return ident, rankList
        end
    end
    for _, spellId in ipairs(set.ids) do
        if tContains(set.ranksBySpell[spellId], defaultID) then
            return REMIND.ForeverGroupCastSpell(set, spellId)
        end
    end
end

local function ApplyClassBuffPicker(record, frameOrder, buffRec)
    local actions = frameOrder.classBuffActions
    local prefs = actions[buffRec.key]
    local cache = REMIND._fvClassPickerGroups
    if not cache then
        cache = {}
        REMIND._fvClassPickerGroups = cache
    end
    local set = cache[buffRec.key]
    local ident, rankList
    if set and set.actions == actions and set.settings == prefs then
        ident, rankList = ClassPickerSpell(set, record.spellID)
    end
    -- Talent changes can invalidate the cached choice without a spell-learned event.
    if not ident or not C_SpellBook.IsSpellKnown(ident) then
        set = BuildClassBuffPicker(buffRec, actions, prefs)
        cache[buffRec.key] = set
        ident, rankList = ClassPickerSpell(set, record.spellID)
    end
    if ident then
        SetForeverPickerSpell(record, set.ids[2] and set or nil, ident, rankList)
    end
end

function REMIND.CollectClassBuffs(missing, frameOrder, auraLock, ids, classKey)
    local entries = REMIND.FvClassBuffs()[classKey]
    if not entries then
        return
    end
    local picks = frameOrder.classBuffPicks
    local storage, key = CharStore("classBuffByChar")
    local rec = storage and key and storage[key]
    for index = 1, #entries do
        local buffRec = entries[index]
        if ClassBuffOn(buffRec, picks) then
            local deathKnight = buffRec.dismissKey
            if not deathKnight then
                deathKnight = "forever:class_" .. buffRec.key
                buffRec.dismissKey = deathKnight
            end
            local last = rec and rec[buffRec.key]
            local up, record = CollectLines(
                missing,
                auraLock,
                ids,
                buffRec.lines,
                last,
                deathKnight,
                buffRec.label,
                buffRec.also,
                buffRec.own or buffRec.ownMemory,
                buffRec.ownMemory
            )
            if record and PickerEnabled() then
                ApplyClassBuffPicker(record, frameOrder, buffRec)
            end
            if up and up ~= last and key and buffRec.lines[2] then
                if not storage then
                    storage = {}
                    CludesUIDB.classBuffByChar = storage
                end
                rec = storage[key]
                if not rec then
                    rec = {}
                    storage[key] = rec
                end
                rec[buffRec.key] = up
            end
        end
    end
end

local FV_HANDS = {
    {
        slot = 16,
        ws = "MainHand",
        imbue = "mhImbue",
        temp = "mhTemp",
        label = "Main Hand",
        imbueKey = "forever:weapon_mh_imbue",
        tempKey = "forever:weapon_mh_temp",
        macros = {},
    },
    {
        slot = 17,
        ws = "OffHand",
        imbue = "ohImbue",
        temp = "ohTemp",
        label = "Off Hand",
        imbueKey = "forever:weapon_oh_imbue",
        tempKey = "forever:weapon_oh_temp",
        macros = {},
    },
}
local FISHING_POLE = 20

local function FvWeaponCategory(slot)
    local category = GetWeaponCategory(slot)
    if not category or category == "RANGED" then
        return nil
    end
    local _, _, _, _, _, _, sub = C_Item.GetItemInfoInstant(GetInventoryItemID("player", slot))
    if sub == FISHING_POLE then
        return nil
    end
    return category
end

local function FvWeaponEnchants(ws)
    local entries = C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot[ws])
    if isSecret(entries) then
        return false
    end
    local imbueLeft, tempLeft
    if type(entries) == "table" then
        local IMBUE, TEMPORARY = Enum.ItemEnchantType.Imbue, Enum.ItemEnchantType.Temporary
        for index = 1, #entries do
            local entry = entries[index]
            local has, kind, leftX = entry.hasEnchant, entry.enchantType, entry.timeLeft
            if isSecret(has) or isSecret(kind) or isSecret(leftX) then
                return false
            end
            if has and leftX and leftX > 0 then
                if kind == IMBUE then
                    imbueLeft = leftX / 1000
                elseif kind == TEMPORARY then
                    tempLeft = leftX / 1000
                end
            end
        end
    end
    return true, imbueLeft, tempLeft
end

local function FvAvailable(buffRec, low)
    if buffRec.spells then
        return REMIND.FvHighest(buffRec.spells), nil
    end
    local itemList = buffRec.items
    local first, last, step = #itemList, 1, -1
    if low then
        first, last, step = 1, #itemList, 1
    end
    for index = first, last, step do
        if CachedGetItemCount(itemList[index]) > 0 then
            return nil, itemList[index]
        end
    end
end

local function FvPick(choice, isImbue, classKey, wcat, low)
    if choice == "off" then
        return nil
    end
    local auto = choice == nil or choice == "auto"
    local entries = REMIND.FV_WEAPON_BUFFS
    for index = 1, #entries do
        local buffRec = entries[index]
        if
            (auto or choice == buffRec.key)
            and (buffRec.imbue == true) == isImbue
            and (not buffRec.class or buffRec.class == classKey)
            and (not buffRec.weapon or buffRec.weapon == wcat)
        then
            local spellId, itemId = FvAvailable(buffRec, low)
            if spellId or itemId or not auto then
                return buffRec, spellId, itemId
            end
        end
    end
end

local function FvNeeds(leftX, warnSec)
    if not leftX then
        return true
    end
    if warnSec and leftX < warnSec then
        return true
    end
    local at = GetTime() + leftX - (warnSec or 0)
    local nextAt = REMIND._nextDurationRefreshTime
    if not nextAt or at < nextAt then
        REMIND._nextDurationRefreshTime = at
    end
    return false
end

local function FvWeaponEntry(missing, hand, labelText, dismissKey, buffRec, spellId, itemId, hideNoItem, leftX)
    if buffRec.spells and not spellId then
        return
    end
    if buffRec.items and not itemId and hideNoItem then
        return
    end
    local entry = AcquireEntry()
    if spellId then
        entry.mode = "spell"
        entry.spellID = spellId
    else
        local isShown = itemId or buffRec.items[#buffRec.items]
        entry.texture = C_Item.GetItemIconByID(isShown) or 134400
        entry.tooltipItem = isShown
        entry.bagCount = itemId and CachedGetItemCount(itemId) or 0
        entry.desaturated = not itemId
        if itemId then
            local macroText = hand.macros[itemId]
            if not macroText then
                macroText = "/use item:" .. itemId .. "\n/use " .. hand.slot
                hand.macros[itemId] = macroText
            end
            entry.mode = "macro"
            entry.macro = macroText
        else
            entry.mode = "texture"
        end
    end
    if leftX then
        entry.expireAt = GetTime() + leftX
        entry.expireTotal = leftX
    end
    entry.label = labelText
    entry.cat = "forever"
    entry.dismissKey = dismissKey
    missing[#missing + 1] = entry
end

function REMIND.CollectForeverWeapons(missing, frameOrder, classKey)
    if not (C_Item.GetWeaponEnchantInfo and Enum.WeaponSlot and Enum.ItemEnchantType) then
        return
    end
    local hands = frameOrder.weaponHands and frameOrder.weaponHands[classKey]
    local low, hideNoItem = frameOrder.weaponLowRank == true, frameOrder.weaponHideNoItem ~= false
    local showBelow = frameOrder.weaponShowBelow or 1
    local warnSec = showBelow > 0 and showBelow * 60 or nil
    local mhFull, ohFull = CludesUI.L(FV_HANDS[1].label), CludesUI.L(FV_HANDS[2].label)
    local mhLabel, ohLabel = ShortLabel(mhFull), ShortLabel(ohFull)
    if mhLabel == ohLabel then
        mhLabel, ohLabel = mhFull, ohFull
    end
    for index = 1, #FV_HANDS do
        local hand = FV_HANDS[index]
        local wcat = FvWeaponCategory(hand.slot)
        local success, imbueLeft, tempLeft
        if wcat then
            success, imbueLeft, tempLeft = FvWeaponEnchants(hand.ws)
        end
        if success then
            local labelText = index == 1 and mhLabel or ohLabel
            local buffRec, spellId, itemId = FvPick(hands and hands[hand.imbue], true, classKey, wcat, low)
            if buffRec and FvNeeds(imbueLeft, warnSec) then
                FvWeaponEntry(
                    missing,
                    hand,
                    labelText,
                    hand.imbueKey,
                    buffRec,
                    spellId,
                    itemId,
                    hideNoItem,
                    imbueLeft
                )
            end
            buffRec, spellId, itemId = FvPick(hands and hands[hand.temp], false, classKey, wcat, low)
            if buffRec and FvNeeds(tempLeft, warnSec) then
                FvWeaponEntry(
                    missing,
                    hand,
                    labelText,
                    hand.tempKey,
                    buffRec,
                    spellId,
                    itemId,
                    hideNoItem,
                    tempLeft
                )
            end
        end
    end
end

local function FvAtMaxLevel()
    local level = UnitLevel("player") or 0
    if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then
        return true
    end
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
        or (GetMaxPlayerLevel and GetMaxPlayerLevel())
    return (maxLevel and level >= maxLevel) or false
end

function REMIND.FvSleepingBagOwned()
    if REMIND._fvMaxLevel then
        return false
    end
    if FvAtMaxLevel() then
        REMIND._fvMaxLevel = true
        return false
    end
    local owned = REMIND._fvSleepBag
    if owned == nil then
        owned = (C_Item.GetItemCount(REMIND.SLEEPING_BAG_ITEM) or 0) > 0
        REMIND._fvSleepBag = owned
    end
    return owned
end

-- WoW Forever collector: the Camp Benefits campfire buff, the Sleeping Bag's
-- Well-Rested buff (missing or under its full stacks, while a Cozy Sleeping Bag
-- is in the bags below max level: EABR.FvSleepingBagOwned), Well Fed (any food
-- buff: the shared Well Fed name, or one of EABR.FOOD_BUFFS), the gathering
-- and Find Treasure trackers, a Mage's armors (EABR.CollectMageArmor), the
-- class buffs (EABR.CollectClassBuffs), the weapon buffs
-- (EABR.CollectForeverWeapons), the user's spell groups
-- (EABR.CollectForeverGroups) and custom spell IDs (each for the classes ticked
-- on it), those a ticked class buff covers standing down outside PvP. All are
-- absence only but
-- the weapon buffs, which also show their Show Below minutes before running
-- out (the one-shot duration refresh). A custom ID counts as up while any
-- spell of its rank family is (EABR.ForeverFamily). Entries are display-only
-- textures carrying the spell for the tooltip, except the Sleeping Bag, the two
-- trackers, the mage armors, the class buffs, the weapon buffs, the spell
-- groups and the custom spells the character knows, whose click casts the spell
-- or uses the item; presence goes through PlayerHasAuraByID. The section shows
-- nothing in combat (its Where to Show offers no In Combat entry: always
-- unchecked), and Camp Benefits, the Sleeping Bag, Well Fed, the mage armors,
-- the class buffs and the trackers nothing in PvP either. The one-slot id
-- table, the cached families, the kept minimap answer and the dismiss-key memo
-- keep the pass allocation-free; the weapon pass reads the game's enchant
-- lists, a table per weapon.
function REMIND.CollectForever(missing, inInstance, inPvP)
    local frameOrder = saved.profile.forever
    local shows = frameOrder and not InCombat() and REMIND.SectionShows(frameOrder.whereToShow, inInstance)
    -- Class trackers and Find Treasure are read from the minimap, whose event
    -- is listened to only while a reminder that reads it can show.
    REMIND.FvSyncTrackingEvent(
        shows and not inPvP and ((frameOrder.gather == true and frameOrder.gatherClassTrack ~= false) or frameOrder.treasure == true)
            or false
    )
    REMIND.FvSyncWeaponEvents(shows and frameOrder.weapon == true or false)
    local wantBag = shows and frameOrder.sleepingBag == true and not inPvP
    local sleepBag = wantBag and REMIND.FvSleepingBagOwned()
    -- No bag yet below max level: a light watcher hears one arrive, unless
    -- Weapon Buffs' bag listener (below) already hears every bag change.
    REMIND.FvSyncSleepBagWatch(
        wantBag and not sleepBag and not REMIND._fvMaxLevel and frameOrder.weapon ~= true or false
    )
    REMIND.FvSyncBagEvent(shows and (frameOrder.weapon == true or sleepBag) or false)
    local watchPickerSpells = shows and PickerEnabled() or false
    if watchPickerSpells ~= (REMIND._fvPickerSpellEvents or false) then
        REMIND.FvSyncPickerSpellEvents(watchPickerSpells)
    end
    if not shows then
        return
    end
    local open = not inPvP
    -- Under the aura lock a secret aura reads absent, so an aura reminder
    -- shows only while none of its spells is secret.
    local auraLock = CludesUI.AuraKit.AurasRestricted()
    local ids = REMIND._foreverIDs
    if not ids then
        ids = {}
        REMIND._foreverIDs = ids
    end
    if frameOrder.camp ~= false and open then
        ids[1] = REMIND.CAMP_BENEFITS
        if not PlayerHasAuraByID(ids) and not (auraLock and not REMIND.FvRanksReadable(ids)) then
            local entry = AcquireEntry()
            entry.mode = "texture"
            entry.spellID = REMIND.CAMP_BENEFITS
            entry.texture = Tex(REMIND.CAMP_BENEFITS)
            entry.label = CludesUI.L("Camp")
            entry.cat = "forever"
            entry.dismissKey = "forever:camp"
            missing[#missing + 1] = entry
        end
    end
    local sleepIDs = REMIND._fvSleepIDs
    if not sleepIDs then
        sleepIDs = { REMIND.SLEEPING_BAG_BUFF }
        REMIND._fvSleepIDs = sleepIDs
    end
    if sleepBag and not (auraLock and not REMIND.FvRanksReadable(sleepIDs)) then
        local success, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, REMIND.SLEEPING_BAG_BUFF)
        local stacks = success and not isSecret(aura) and (aura and aura.applications or 0)
        if stacks and not isSecret(stacks) and stacks < REMIND.SLEEPING_BAG_STACKS then
            local entry = REMIND.SLEEPING_BAG_ITEM
            local e = AcquireEntry()
            e.mode = "item"
            e.itemID = entry
            e.texture = C_Item.GetItemIconByID(entry) or Tex(REMIND.SLEEPING_BAG_BUFF)
            e.label = CludesUI.L("Sleeping")
            e.cat = "forever"
            e.dismissKey = "forever:sleepingbag"
            missing[#missing + 1] = e
        end
    end
    -- Gathering tracking: shown while no tracker is up and the player knows
    -- one; the button casts the first one known. The aura read goes first, so
    -- the common case (a tracker up) skips the rest; class trackers are no
    -- auras there, so the minimap is asked only once a tracker is known.
    local scanned, treasureUp, classUp
    local entries = REMIND.GATHER_TRACKING
    if
        frameOrder.gather
        and open
        and not PlayerHasAuraByID(entries)
        and not (auraLock and not REMIND.FvRanksReadable(entries))
    then
        local ident
        for index = 1, #entries do
            if Known(entries[index]) then
                ident = entries[index]
                break
            end
        end
        if ident then
            if frameOrder.gatherClassTrack ~= false then
                scanned = true
                treasureUp, classUp = REMIND.FvTrackingState()
            end
            if not classUp then
                REMIND.FvSpellEntry(missing, ident, "forever:gather")
            end
        end
    end
    -- Find Treasure (Dwarf racial): no aura there, so read from the same
    -- minimap pass when the gathering check already ran it.
    local tid = REMIND.FIND_TREASURE
    if frameOrder.treasure and open and Known(tid) then
        if not scanned then
            treasureUp = REMIND.FvTrackingState()
        end
        if not treasureUp then
            REMIND.FvSpellEntry(missing, tid, "forever:treasure")
        end
    end
    if frameOrder.wellFed and open then
        local label = SpellName(REMIND.WELL_FED) or "Well Fed"
        local success, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", label, "HELPFUL")
        if success and not isSecret(aura) and not aura and not PlayerHasAuraByID(REMIND.FOOD_BUFFS) then
            local entry = AcquireEntry()
            entry.mode = "texture"
            entry.spellID = REMIND.WELL_FED
            entry.texture = Tex(REMIND.WELL_FED)
            entry.label = label
            entry.cat = "forever"
            entry.dismissKey = "forever:wellfed"
            missing[#missing + 1] = entry
        end
    end
    if frameOrder.mageArmor and open and GetPlayerClass() == "MAGE" then
        REMIND.CollectMageArmor(missing, auraLock, ids)
    end
    -- The ticked class buffs, outside PvP; the custom spells and spell groups
    -- they cover stand down there (EABR.FvClassTracked).
    local coveredIDs, coveredNames
    if open then
        coveredIDs, coveredNames = REMIND.FvClassTracked(frameOrder, GetPlayerClass())
        if coveredIDs then
            REMIND.CollectClassBuffs(missing, frameOrder, auraLock, ids, GetPlayerClass())
        end
    end
    if frameOrder.weapon == true then
        REMIND.CollectForeverWeapons(missing, frameOrder, GetPlayerClass())
    end
    local groups = frameOrder.customGroups
    if groups and groups[1] then
        REMIND.CollectForeverGroups(missing, groups, coveredIDs, coveredNames)
    end
    local custom = frameOrder.customIDs
    if not custom then
        return
    end
    local keyList = REMIND._foreverKeys
    if not keyList then
        keyList = {}
        REMIND._foreverKeys = keyList
    end
    -- A custom spell reminds only the classes ticked on its options slot
    -- (forever.customClasses[id][CLASS] = false unticks one; unset: every class).
    local classOff, classKey = frameOrder.customClasses, GetPlayerClass()
    for index = 1, #custom do
        local ident = custom[index]
        local off = classOff and classOff[ident]
        if not (off and off[classKey] == false) then
            local label = SpellName(ident)
            if not (coveredIDs and (coveredIDs[ident] or (label and coveredNames[label]))) then
                local fam = REMIND.ForeverFamily(ident)
                if
                    not PlayerHasAuraByID(fam) and not (auraLock and fam and not REMIND.FvRanksReadable(fam))
                then
                    local deathKnight = keyList[ident]
                    if not deathKnight then
                        deathKnight = "forever:" .. ident
                        keyList[ident] = deathKnight
                    end
                    local entry = AcquireEntry()
                    -- A spell the character knows (a rank in the spellbook)
                    -- casts on click; any other (a buff someone else casts) is
                    -- only shown.
                    if label and fam and REMIND._fvKnownFams[fam] then
                        CastByName(entry, label, ident)
                    else
                        entry.mode = "texture"
                        entry.spellID = ident
                    end
                    entry.texture = Tex(ident)
                    entry.label = ShortLabel(label or tostring(ident))
                    entry.cat = "forever"
                    entry.dismissKey = deathKnight
                    missing[#missing + 1] = entry
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  WoW Forever Raid Buffs: the retail section's two views over that client's
--  buffs (RAID_BUFFS). A member has a buff while an aura with one of its
--  family's names is up (every rank, the group version, other casters'
--  versions). Under the game's aura restriction a buff is read only while none
--  of its ranks is secret (a secret aura would read absent while up), and
--  shows nothing otherwise rather than a false alarm. Absence only (no expiry
--  thresholds).
-------------------------------------------------------------------------------
-- Localized names of a family, cached per family (cold spell data stays uncached).
function REMIND.FvNames(fam)
    local cache = REMIND._fvNameCache
    if not cache then
        cache = {}
        REMIND._fvNameCache = cache
    end
    local nameList = cache[fam]
    if nameList then
        return nameList
    end
    nameList = {}
    for _, ident in ipairs(fam.names) do
        local num = SpellName(ident)
        if num then
            nameList[#nameList + 1] = num
        end
    end
    if nameList[1] then
        cache[fam] = nameList
    end
    return nameList
end

-- Whether a unit carries any rank of a family: true / false, or nil when the
-- answer cannot be read. rec (optional) collects the found aura's instance ID
-- for the group aura probe.
function REMIND.FvUnitHas(unit, fam, rec)
    local nameList = REMIND.FvNames(fam)
    if not nameList[1] then
        return nil
    end
    for num = 1, #nameList do
        local success, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, nameList[num], "HELPFUL")
        if not success or isSecret(aura) then
            return nil
        end
        if aura then
            local iid = rec and aura.auraInstanceID
            if iid and not isSecret(iid) then
                rec[iid] = true
            end
            return true
        end
    end
    return false
end

-- The highest rank in a list (lowest first) the player knows, or nil.
function REMIND.FvHighest(entries)
    for index = #entries, 1, -1 do
        if C_SpellBook.IsSpellKnown(entries[index]) then
            return entries[index]
        end
    end
end

-- Whether no rank in a list reads secret right now.
function REMIND.FvRanksReadable(entries)
    for index = 1, #entries do
        if not REMIND.IsRuntimeNonSecret(entries[index]) then
            return false
        end
    end
    return true
end

-- Whether a family can be read now: always outside the aura restriction,
-- inside it only while none of its ranks is secret. The restricted answer is
-- kept for the frame (inputs: the family and the frame's time), since a burst
-- of unreadable group aura payloads asks it per event.
function REMIND.FvReadable(fam, restricted)
    if not restricted then
        return true
    end
    local memo = REMIND._fvReadMemo
    if not memo then
        memo = {}
        REMIND._fvReadMemo = memo
    end
    local nowTime = GetTime()
    if memo.t ~= nowTime then
        wipe(memo)
        memo.t = nowTime
    end
    local val = memo[fam]
    if val == nil then
        val = REMIND.FvRanksReadable(fam.single) and REMIND.FvRanksReadable(fam.group)
        memo[fam] = val
    end
    return val
end

-- The group unit tokens, built once: party = the player and party1-4, raid =
-- raid1-40.
function REMIND.FvTokens()
    local tbl = REMIND._fvTokens
    if tbl then
        return tbl
    end
    tbl = { party = { "player" }, raid = {} }
    for index = 1, 4 do
        tbl.party[index + 1] = "party" .. index
    end
    for index = 1, 40 do
        tbl.raid[index] = "raid" .. index
    end
    REMIND._fvTokens = tbl
    return tbl
end

-- In-range beneficiaries carrying a family vs all of them (the "12/15" badge),
-- plus the first one without it (the click's target). A member whose answer
-- cannot be read counts on neither side. The found aura instances
-- (EABR._fvInst, kept outside the watch so the pass that first builds it
-- records them too) feed the group aura probe (EABR.FvAuraRelevant); keep
-- adds them to the ones an earlier call of the same pass found (a class that
-- provides two buffs).
function REMIND.FvCoverage(fam, benefit, keep)
    local instance = REMIND._fvInst
    if not instance then
        instance = {}
        REMIND._fvInst = instance
    end
    local raid = IsInRaid()
    local tokens = REMIND.FvTokens()
    local entries = raid and tokens.raid or tokens.party
    local num = raid and GetNumGroupMembers() or (GetNumSubgroupMembers() + 1)
    local have, sum, first = 0, 0, nil
    for index = 1, num do
        local u = entries[index]
        if not u then
            break
        end
        local rec = instance[u]
        if rec and not keep then
            wipe(rec)
        end
        if _unitOk(u) and UnitIsPlayer(u) and _unitInRange(u) and REMIND.UnitBenefits(u, benefit) then
            if not rec then
                rec = {}
                instance[u] = rec
            end
            local has = REMIND.FvUnitHas(u, fam, rec)
            if has ~= nil then
                sum = sum + 1
                if has then
                    have = have + 1
                elseif not first then
                    first = u
                end
            end
        end
    end
    return have, sum, first
end

-- The click's cast: the group version on the player while they know it and
-- could cast it now (its reagent in the bags; mana aside), else the highest
-- known rank on the member who lacks the buff (the player for a shout).
function REMIND.FvPickCast(buffRec, unitToken)
    local fam = buffRec.fam
    local g = REMIND.FvHighest(fam.group)
    if g then
        local usable, noMana = C_Spell.IsSpellUsable(g)
        if not isSecret(usable) and not isSecret(noMana) and (usable or noMana) then
            return g, "player"
        end
    end
    return REMIND.FvHighest(fam.single), (not buffRec.selfCast and unitToken) or "player"
end

-- The collector. Provider: the player knows a rank (or the group version) of
-- their class's buff; with "Others are missing my buff" in a group it counts
-- the in-range members who benefit, otherwise the player alone. Receiver ("I
-- am missing others' buffs"): a buff of another class the player lacks while a
-- member of that class is in range (informational, no click; never a talent
-- buff). Out of combat the pass also picks the provider's cast
-- (EABR.SyncProviderCastSpell binds it), and every pass syncs the group watch
-- to what it read. One button casts the provider's buffs, so a class that
-- provides two (a priest with Divine Spirit) shows one provider reminder at a
-- time: the first of its buffs in list order that is missing and not
-- dismissed, with the button bound to its cast; with none showing, the button
-- stays bound to the first buff it provides. Under lockdown the binding
-- cannot change, so only the buff the button casts shows there; another waits
-- for the end of combat.
function REMIND.CollectForeverRaidBuffs(missing, classFile, inInstance)
    local rb = saved.profile.raidBuffs
    local watch = REMIND._fvWatchFams
    if watch then
        wipe(watch)
    else
        watch = {}
        REMIND._fvWatchFams = watch
    end
    local roster = false
    local castSpell, castUnit
    local provided, covered, idle, idleFirst = false, false, nil, nil
    local lockdown = InCombatLockdown()
    if rb and REMIND.SectionShows(rb.whereToShow, inInstance) then
        local sw = rb.showWhen
        local othersMissing = not sw or sw.othersMissing ~= false
        local iAmMissing = sw and sw.iAmMissing == true
        local grouped = IsInGroup()
        local groupClasses = iAmMissing and grouped and REMIND.BuildGroupClassSet() or nil
        local restricted = CludesUI.AuraKit.AurasRestricted()
        for _, buffRec in ipairs(RAID_BUFFS) do
            if rb.enabled[buffRec.key] then
                local fam = buffRec.fam
                local iCast = buffRec.class == classFile
                    and (REMIND.FvHighest(fam.single) or REMIND.FvHighest(fam.group)) ~= nil
                if iCast and othersMissing then
                    watch[#watch + 1] = fam
                end
                if not iCast and iAmMissing and not buffRec.talent then
                    roster = true
                end
                local doReceiver = not iCast
                    and not buffRec.talent
                    and groupClasses
                    and groupClasses[buffRec.class]
                    and REMIND.PlayerBenefitsFromBuff(buffRec)
                if (iCast or doReceiver) and REMIND.FvReadable(fam, restricted) then
                    local isMissing, have, sum, first
                    if iCast and othersMissing and grouped then
                        have, sum, first = REMIND.FvCoverage(fam, buffRec.benefit, covered)
                        covered = true
                        isMissing = sum > 0 and have < sum
                    else
                        isMissing = REMIND.FvUnitHas("player", fam) == false
                    end
                    if iCast then
                        if not idle then
                            idle, idleFirst = buffRec, first
                        end
                        -- Under lockdown: the spell the button casts, a rank or
                        -- group version of the one buff that may show.
                        local bound = lockdown and REMIND._providerCastSpell
                        isMissing = isMissing
                            and not provided
                            and not _dismissedUntilLoad[buffRec.dismissKey]
                            and not (
                                bound and not (tContains(fam.single, bound) or tContains(fam.group, bound))
                            )
                        if isMissing then
                            provided = true
                            if not lockdown then
                                castSpell, castUnit = REMIND.FvPickCast(buffRec, first)
                            end
                        end
                    end
                    if isMissing then
                        local entry = AcquireEntry()
                        entry.label = ShortLabel(SpellName(buffRec.castSpell) or buffRec.name)
                        entry.cat = "raidbuff"
                        entry.data = buffRec
                        entry.dismissKey = buffRec.dismissKey
                        if sum then
                            entry.groupHave = have
                            entry.groupTotal = sum
                        end
                        if iCast then
                            -- The provider button casts it; in combat it keeps
                            -- the cast bound before the pull.
                            entry.mode = "spell"
                            entry.spellID = castSpell or REMIND._providerCastSpell
                        else
                            entry.mode = "texture"
                            entry.spellID = buffRec.castSpell
                            entry.texture = Tex(buffRec.castSpell)
                        end
                        missing[#missing + 1] = entry
                    end
                end
            end
        end
    end
    if not lockdown then
        if not provided and idle then
            castSpell, castUnit = REMIND.FvPickCast(idle, idleFirst)
        end
        REMIND._fvCastSpell, REMIND._fvCastUnit = castSpell, castUnit
    end
    REMIND.FvSyncGroupWatch(watch, roster)
end

-- WoW Forever: what a pass that shows nothing stands down (the Raid Buffs group
-- watch and the minimap, weapon and bag events); the next pass that can show
-- re-arms them.
function REMIND.FvStandDown()
    REMIND.FvSyncGroupWatch(nil, false)
    REMIND.FvSyncTrackingEvent(false)
    REMIND.FvSyncWeaponEvents(false)
    REMIND.FvSyncBagEvent(false)
    -- Bag changes go unheard while the section stands down (resting in a city,
    -- for one): the Sleeping Bag is counted again when it is back.
    REMIND.FvSyncSleepBagWatch(false)
    REMIND._fvSleepBag = nil
    if REMIND._fvPickerSpellEvents then
        REMIND.FvSyncPickerSpellEvents(false)
    end
    if REMIND.ValidateOpenPicker then
        REMIND.ValidateOpenPicker()
    end
    if REMIND._durationTimer then
        REMIND._durationTimer:Cancel()
        REMIND._durationTimer = nil
    end
end

local function Refresh()
    SetCachedOutline(nil)
    REMIND._nextDurationRefreshTime = nil
    if not saved then
        return
    end
    -- Pooled reminder buttons are children of iconAnchor, built in OnEnable (PLAYER_LOGIN). File-scope events (SPELLS_CHANGED, PLAYER_TALENT_UPDATE,
    -- TRAIT_CONFIG_UPDATED, ...) can fire DURING loading before OnEnable runs; a reminder created then via GetOrCreateIcon gets a nil parent and renders oversized forever (scale 1.0, not UIParent scale -- pooled buttons are never re-parented). Wait for the anchor; OnEnable fires its own refresh.
    if not iconAnchor then
        return
    end
    -- WoW Forever: the returns below show nothing, so the Raid Buffs group
    -- watch and the tracking event stand down with them (EABR.FvStandDown);
    -- the event that ends each state (panel close, vehicle exit, alive, rest
    -- ended) refreshes and re-arms them.
    if cuiPanelOpen then
        HideCombatIcons()
        HideAllIcons()
        if REMIND.FOREVER then
            REMIND.FvStandDown()
        end
        return
    end

    -- Hides all reminders while skyriding (mounted+flying) or in a vehicle; IsMounted/IsFlying/UnitInVehicle are combat-safe (no taint).
    if UnitInVehicle("player") or (IsMounted() and IsFlying()) then
        HideCombatIcons()
        HideCursorIcons()
        if InCombat() then
            FadeOutSecureIcons()
        else
            HideAllIcons()
        end
        if REMIND.FOREVER then
            REMIND.FvStandDown()
        end
        return
    end

    -- Suppresses while dead or in a rested area (city/inn) -- rested areas
    -- always stay hidden, independent of every "Where to Show" setting.
    if UnitIsDeadOrGhost("player") then
        HideCombatIcons()
        HideCursorIcons()
        HideAllIcons()
        if REMIND.FOREVER then
            REMIND.FvStandDown()
        end
        return
    end
    if IsResting() then
        HideCombatIcons()
        HideCursorIcons()
        if InCombat() then
            FadeOutSecureIcons()
        else
            HideAllIcons()
        end
        if REMIND.FOREVER then
            REMIND.FvStandDown()
        end
        return
    end

    CacheInstanceInfo()

    BuildPlayerAuraCache()

    local classFile = GetPlayerClass()
    local inCombat = InCombat()

    -- Collect missing reminders (reuse pooled entry tables)
    ResetEntryPool()
    local missing = _refreshMissing
    wipe(missing)

    local remindersOn = saved.profile.display.remindersEnabled ~= false

    -- Instance/spec state (all combat-safe reads) -- needed even in
    -- restricted contexts so the trackable subset can still be collected.
    -- "restricted" = aura reads are locked (combat or an active keystone);
    -- the collectors self-limit under it, and where reminders may appear is
    -- governed per-section by "Where to Show".
    local specID = GetSpecID()
    local inInstance = InRealInstancedContent()
    local inKeystone = InMythicPlusKey()
    local inPvP = InPvPInstance()
    local restricted = inCombat or inKeystone

    -- WoW Forever: its Raid Buffs and the one Forever section stand in for the
    -- four collectors below (reminders off: their watch and event stand down).
    if REMIND.FOREVER then
        if remindersOn then
            REMIND.CollectForeverRaidBuffs(missing, classFile, inInstance)
            REMIND.CollectForever(missing, inInstance, inPvP)
        else
            REMIND.FvStandDown()
        end
    end

    ---------------------------------------------------------------------------
    --  1) Raid Buffs (runs in and out of combat)
    ---------------------------------------------------------------------------
    if remindersOn and not REMIND.FOREVER then
        CollectRaidBuffs(missing, classFile, inInstance, inCombat)
    end

    ---------------------------------------------------------------------------
    --  2) Auras: OOC normally; in restricted contexts only reminders whose
    --  detection survives the aura lock (stances/forms + whitelisted IDs).
    ---------------------------------------------------------------------------
    if remindersOn and not REMIND.FOREVER then
        CollectAuras(missing, classFile, specID, inInstance, restricted)
    end

    ---------------------------------------------------------------------------
    --  3) Consumables: OOC normally; in restricted contexts the trackable
    --  subset only. In a PvP instance the class specials (poisons, rites,
    --  imbues, shields) still run; the bag and equip items stay off there.
    ---------------------------------------------------------------------------
    if remindersOn and not REMIND.FOREVER then
        CollectConsumables(missing, classFile, specID, inInstance, inKeystone, inCombat, inPvP)
    else
        -- The Inky Black Potion map watch follows the collector that reads it
        InkyMapWatch(false)
    end

    ---------------------------------------------------------------------------
    --  4) Pet Reminders (combat-safe: UnitExists/UnitIsDead unrestricted); suppressed for petless specs, Grimoire of Sacrifice, etc.
    ---------------------------------------------------------------------------
    if remindersOn and not REMIND.FOREVER and PET_CLASSES[classFile] then
        local co = saved.profile.consumables
        if
            co
            and co.enabled
            and co.enabled.pet ~= false
            and REMIND.SectionShows(REMIND.SpecialsWhere(co, REMIND.SPECIALS.PET.where), inInstance)
        then
            local suppress = false
            local petIcon = 132161
            local petLabel = "Pet"
            local warlockEnforcedPets
            if classFile == "HUNTER" then
                local specInfo = GetSpecialization and GetSpecialization()
                if specInfo then
                    local spellRef = GetSpecializationInfo(specInfo)
                    if spellRef == 254 and not Known(1223323) then
                        suppress = true
                    end
                end
            elseif classFile == "WARLOCK" then
                petIcon = 136218
                if Known(108503) and PlayerHasAuraByID({ 196099 }) then
                    suppress = true
                end
                local allowed = co.wrongPetAllowed
                warlockEnforcedPets = {}
                if allowed then
                    for _, pet in ipairs(WARLOCK_PETS) do
                        if allowed[pet.key] and Known(pet.castSpell) then
                            warlockEnforcedPets[#warlockEnforcedPets + 1] = pet
                        end
                    end
                end
            elseif classFile == "DEATHKNIGHT" then
                petIcon = 1100170
                petLabel = "Ghoul"
                if specID ~= 252 then
                    suppress = true
                end
            elseif classFile == "MAGE" then
                petIcon = 135862
                petLabel = "Water Elemental"
                if specID ~= 64 or not Known(31687) then
                    suppress = true
                end
            end
            -- Skipped while mounted, and for a beat after dismounting: mounting auto-dismisses the pet and the server resummons it on dismount a moment after the mount display drops, so the reminder is never actionable there (summoning would dismount you anyway). IsMounted()/GetTime() are combat-safe.
            if
                not suppress
                and not IsMounted()
                and not (REMIND._petRemountGrace and GetTime() < REMIND._petRemountGrace)
                and not (UnitExists("pet") and not UnitIsDead("pet"))
            then
                local entry = AcquireEntry()
                entry.cat = "consumable"
                entry.dismissKey = "consumable:pet"
                local num = warlockEnforcedPets and #warlockEnforcedPets or 0
                if num > 0 then
                    REMIND.SetWarlockPetSpell(entry, warlockEnforcedPets, petIcon)
                else
                    entry.mode = "texture"
                    entry.texture = petIcon
                    entry.label = petLabel
                end
                missing[#missing + 1] = entry
            end
            if
                not suppress
                and classFile == "WARLOCK"
                and co.enabled.wrong_pet ~= false
                and REMIND.SectionShows(co.warlockWhereToShow, inInstance)
                and UnitExists("pet")
                and not UnitIsDead("pet")
            then
                local _, familyID = UnitCreatureFamily("pet")
                familyID = familyID and not (issecretvalue and issecretvalue(familyID)) and familyID or nil
                local isAllowed = false
                for _, pet in ipairs(warlockEnforcedPets) do
                    if familyID and pet.families[familyID] then
                        isAllowed = true
                        break
                    end
                end
                if #warlockEnforcedPets > 0 and not isAllowed then
                    local entry = AcquireEntry()
                    REMIND.SetWarlockPetSpell(entry, warlockEnforcedPets, 136216, CludesUI.L("Wrong Demon"))
                    entry.cat = "consumable"
                    entry.dismissKey = "consumable:wrong_pet"
                    missing[#missing + 1] = entry
                end
            end
            -- Pet on Passive: warns when an active pet is set to Passive stance. Combat-safe (pet command state isn't secret); skipped while mounted (pet is auto-forced to Passive).
            if
                not suppress
                and co.enabled.pet_passive ~= false
                and UnitExists("pet")
                and not UnitIsDead("pet")
                and not IsMounted()
            then
                local passiveActive, passiveTex, passiveIsToken
                for index = 1, (NUM_PET_ACTION_SLOTS or 10) do
                    local nm, tx, tok, isActive = GetPetActionInfo(index)
                    if nm == "PET_MODE_PASSIVE" then
                        if not isSecret(isActive) then
                            passiveActive = (isActive == true)
                        end
                        passiveTex, passiveIsToken = tx, tok
                        break
                    end
                end
                if passiveActive then
                    local entry = AcquireEntry()
                    entry.mode = "texture"
                    entry.texture = (passiveIsToken and _G[passiveTex]) or passiveTex or petIcon
                    entry.label = PET_MODE_PASSIVE or "Passive"
                    entry.cat = "consumable"
                    entry.dismissKey = "consumable:pet_passive"
                    missing[#missing + 1] = entry
                end
            end
        end
    end

    -- Talent reminders handled by CludesUIABR_TalentReminders.lua

    -- Per-section sound alerts: fire once as each reminder newly appears.
    REMIND.HandleAppearSounds(missing)

    ---------------------------------------------------------------------------
    --  Apply results
    ---------------------------------------------------------------------------
    if inCombat then
        -- Combat path: visual-only icons for most reminders. The player's
        -- own raid buff routes to the pre-bound provider SecureActionButton
        -- so rebuffing stays clickable under lockdown -- unless cursor
        -- attach is on, where it rides the cursor as a visual icon instead
        -- (see the provider peel below).
        FadeOutSecureIcons()
        HideCombatIcons()
        HideCursorIcons()
        local provider
        if #missing > 0 then
            local useCursor = CursorAttachActive(saved.profile.display) and cursorHolder
            local combatIdx, cursorIndex = 0, 0
            for _, m in ipairs(missing) do
                -- Skip middle-click dismissed reminders. The collectors are
                -- the restriction gate now (each emits only what its combat
                -- detection can verify), so no whitelist re-filter here.
                local deathKnight = m.dismissKey or (m.data and m.data.key and (m.cat .. ":" .. m.data.key)) or nil
                if not (deathKnight and _dismissedUntilLoad[deathKnight]) then
                    -- With cursor attach ON the provider reminder rides the
                    -- cursor instead of the secure button (a cursor-chasing
                    -- icon could never be clicked anyway, and a protected
                    -- frame could not chase the cursor in combat at all).
                    -- Peel to the secure button ONLY while it holds its combat
                    -- slot (visible at pull, or shown earlier this combat). A
                    -- button that entered combat PARKED sits at -10000 and its
                    -- SetPoint is lockdown-protected, so a mid-combat first
                    -- show there is invisible (die -> combat res -> own buff
                    -- missing was the field case); fall through to a normal
                    -- pooled icon instead -- visual-only, like every other
                    -- combat entry. The button resumes ownership at the OOC
                    -- refresh.
                    if
                        m.cat == "raidbuff"
                        and m.mode == "spell"
                        and not useCursor
                        and (REMIND._providerCastVisible or REMIND._providerCastCombatReserved)
                    then
                        provider = m
                    else
                        local frame
                        if useCursor and IsImportantBuff(m) then
                            cursorIndex = cursorIndex + 1
                            ShowCursorIcon(cursorIndex, m)
                            frame = cursorActiveIcons[#cursorActiveIcons]
                        else
                            combatIdx = combatIdx + 1
                            ShowCombatIcon(m)
                            frame = combatActiveIcons[#combatActiveIcons]
                        end
                        if frame and not m.isEating then
                            local display = saved.profile.display
                            local baseScale = display.scale or 1.0
                            local iconSz = floor(ICON_SIZE * baseScale + 0.5)
                            ApplyGlow(frame, display, iconSz)
                        end
                    end
                end
            end
            if provider then
                REMIND.SetProviderCastCombatVisible(true, provider)
                local pBtn = REMIND._providerCastBtn
                if pBtn then
                    local display = saved.profile.display
                    local sz = pBtn:GetWidth() or ICON_SIZE
                    if pBtn._eabrGlowWrapper then
                        pBtn._eabrGlowWrapper:Hide()
                    end
                    ApplyGlow(pBtn, display, sz)
                end
            end
            if (combatIdx > 0 or provider) and combatAnchor then
                combatAnchor:Show()
                CludesUI.SetElementVisibility(combatAnchor, true)
                LayoutCombatIcons()
            end
            if cursorIndex > 0 and cursorHolder then
                cursorHolder:Show()
                CludesUI.SetElementVisibility(cursorHolder, true)
                LayoutCursorIcons()
            end
        end
        return
    end

    -- OOC path: full secure button display
    REMIND.SyncProviderCastSpell()
    HideCombatIcons()
    HideCursorIcons()
    HideAllIcons()

    if #missing > 0 then
        -- Cursor attach applies OOC too. Cursor icons are visual-only: an
        -- important buff routed here trades its secure click-to-cast for
        -- at-cursor placement, same as in combat -- no loss, since an icon
        -- chasing the cursor can never be clicked anyway. With cursor attach
        -- ON the player's own raid buff is the main case: it rides the
        -- cursor and the provider secure button parks; with it OFF the
        -- provider button keeps sole ownership as before. Only on Cursor
        -- in Combat keeps everything at its normal spot out here.
        local useCursor = CursorAttachActive(saved.profile.display) and cursorHolder
        local iconIdx, cursorIndex = 0, 0
        local provider
        for _, m in ipairs(missing) do
            local deathKnight = m.dismissKey or (m.data and m.data.key and (m.cat .. ":" .. m.data.key)) or nil
            if not deathKnight or not _dismissedUntilLoad[deathKnight] then
                if m.cat == "raidbuff" and m.mode == "spell" and not useCursor then
                    provider = m
                elseif useCursor and IsImportantBuff(m) then
                    cursorIndex = cursorIndex + 1
                    ShowCursorIcon(cursorIndex, m)
                    local frame = cursorActiveIcons[#cursorActiveIcons]
                    if frame and not m.isEating then
                        local display = saved.profile.display
                        local baseScale = display.scale or 1.0
                        local iconSz = floor(ICON_SIZE * baseScale + 0.5)
                        ApplyGlow(frame, display, iconSz)
                    end
                else
                    iconIdx = iconIdx + 1
                    ShowIcon(iconIdx, m)
                end
            end
        end
        if provider then
            REMIND.SetProviderCastCombatVisible(true, provider)
            local pBtn = REMIND._providerCastBtn
            if pBtn then
                local display = saved.profile.display
                local sz = pBtn:GetWidth() or ICON_SIZE
                if pBtn._eabrGlowWrapper then
                    pBtn._eabrGlowWrapper:Hide()
                end
                ApplyGlow(pBtn, display, sz)
            end
        else
            REMIND.ParkProviderCastButton()
        end
        if cursorIndex > 0 then
            cursorHolder:Show()
            CludesUI.SetElementVisibility(cursorHolder, true)
            LayoutCursorIcons()
        end
        if iconIdx > 0 or provider then
            LayoutIcons()
            CludesUI.SetElementVisibility(iconAnchor, true)
        else
            CludesUI.SetElementVisibility(iconAnchor, false)
        end
    else
        REMIND.ParkProviderCastButton()
        CludesUI.SetElementVisibility(iconAnchor, false)
    end

    -- The pool is rebuilt above. A visible button can now represent another reminder.
    if REMIND.ValidateOpenPicker then
        REMIND.ValidateOpenPicker()
    end
    UpdateDurationTicker()
end

local REFRESH_THROTTLE_COMBAT = 0.5
local REFRESH_THROTTLE_OOC = 0.5
local _lastRefreshTime = 0
local _refreshTimerActive = false
local function _doRefresh()
    _refreshTimerActive = false
    refreshQueued = false
    _lastRefreshTime = GetTime()
    Refresh()
end
local function QueueRefresh()
    if refreshQueued then
        return
    end
    refreshQueued = true
    local throttle = InCombat() and REFRESH_THROTTLE_COMBAT or REFRESH_THROTTLE_OOC
    local elapsed = GetTime() - _lastRefreshTime
    if elapsed >= throttle then
        C_Timer.After(0, _doRefresh)
    elseif not _refreshTimerActive then
        _refreshTimerActive = true
        C_Timer.After(throttle - elapsed, _doRefresh)
    end
end

-------------------------------------------------------------------------------
--  WoW Forever Raid Buffs group watch, synced by every collector pass to what
--  it read (fams = the list of the provider's buffs whose coverage counts the
--  group, or nil; roster = a receiver reminder is possible):
--  GROUP_ROSTER_UPDATE while either applies; while grouped also
--  UNIT_IN_RANGE_UPDATE and UNIT_CONNECTION per group token, plus UNIT_AURA
--  for a provider, each aura event probing its own added and removed auras
--  before a refresh is asked (EABR.FvAuraRelevant).
--  Nothing is registered otherwise (Refresh also stands it down while it
--  shows nothing: the options panel open, a vehicle, dead, resting).
--  RegisterUnitEvent takes two units, so the tokens ride one frame per pair:
--  party1-4 in a party (the player's own auras come through the main frame),
--  raid1-40 in a raid.
-------------------------------------------------------------------------------
function REMIND.FvSyncGroupWatch(fams, roster)
    local num = fams and #fams or 0
    local anyMissing = num > 0 or roster
    local Watch = REMIND._fvWatch
    if not Watch then
        if not anyMissing then
            return
        end
        Watch = { ids = {}, frames = {}, fams = {} }
        -- With a refresh already queued there is nothing to probe.
        local function OnUnitEvent(_, evt, unitToken, details)
            if refreshQueued then
                return
            end
            if evt ~= "UNIT_AURA" or REMIND.FvAuraRelevant(unitToken, details) then
                QueueRefresh()
            end
        end
        local tokens = REMIND.FvTokens()
        for kind, from in pairs({ party = 2, raid = 1 }) do
            local entries = tokens[kind]
            for index = from, #entries, 2 do
                local frame = CreateFrame("Frame")
                frame.kind, frame.u1, frame.u2 = kind, entries[index], entries[index + 1]
                frame:SetScript("OnEvent", OnUnitEvent)
                Watch.frames[#Watch.frames + 1] = frame
            end
        end
        Watch.world = CreateFrame("Frame")
        Watch.world:SetScript("OnEvent", function()
            QueueRefresh()
        end)
        REMIND._fvWatch = Watch
    end
    -- The watched buffs, copied (the collector reuses its list).
    local same = #Watch.fams == num
    for index = 1, num do
        if Watch.fams[index] ~= fams[index] then
            same = false
        end
    end
    if not same then
        wipe(Watch.fams)
        wipe(Watch.ids)
        for index = 1, num do
            local fam = fams[index]
            Watch.fams[index] = fam
            for _, ident in ipairs(fam.ids) do
                Watch.ids[ident] = true
            end
        end
    end
    if Watch.any ~= anyMissing then
        Watch.any = anyMissing
        if anyMissing then
            Watch.world:RegisterEvent("GROUP_ROSTER_UPDATE")
        else
            Watch.world:UnregisterEvent("GROUP_ROSTER_UPDATE")
        end
    end
    local mode = anyMissing and IsInGroup() and (IsInRaid() and "raid" or "party") or nil
    local auraOn = mode ~= nil and num > 0
    if Watch.mode ~= mode or Watch.auraOn ~= auraOn then
        Watch.mode, Watch.auraOn = mode, auraOn
        for _, frame in ipairs(Watch.frames) do
            frame:UnregisterAllEvents()
            if frame.kind == mode then
                frame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", frame.u1, frame.u2)
                frame:RegisterUnitEvent("UNIT_CONNECTION", frame.u1, frame.u2)
                if auraOn then
                    frame:RegisterUnitEvent("UNIT_AURA", frame.u1, frame.u2)
                end
            end
        end
        if not auraOn and REMIND._fvInst then
            for _, rec in pairs(REMIND._fvInst) do
                wipe(rec)
            end
        end
    end
end

-- Whether any watched buff stays readable under the restriction.
local function FvWatchReadable(Watch)
    local fams = Watch.fams
    for index = 1, #fams do
        if REMIND.FvReadable(fams[index], true) then
            return true
        end
    end
    return false
end

-- One group aura event against the watched buffs: an added aura of one, or
-- the removal of one the last pass found on that member, asks for a refresh;
-- a full update always does; a payload the restriction made unreadable does
-- while a watched buff itself stays readable.
function REMIND.FvAuraRelevant(unitToken, details)
    local Watch = REMIND._fvWatch
    if not (Watch and Watch.fams[1]) then
        return false
    end
    if not details then
        return true
    end
    if isSecret(details) then
        return FvWatchReadable(Watch)
    end
    local full = details.isFullUpdate
    if isSecret(full) then
        return FvWatchReadable(Watch)
    end
    if full then
        return true
    end
    local added = details.addedAuras
    if added then
        if isSecret(added) then
            return FvWatchReadable(Watch)
        end
        for index = 1, #added do
            local aura = added[index]
            if isSecret(aura) then
                return FvWatchReadable(Watch)
            end
            local spellRef = aura.spellId
            if isSecret(spellRef) then
                return FvWatchReadable(Watch)
            end
            if spellRef and Watch.ids[spellRef] then
                return true
            end
        end
    end
    local removed, found = details.removedAuraInstanceIDs, REMIND._fvInst and REMIND._fvInst[unitToken]
    if removed and found and next(found) then
        if isSecret(removed) then
            return FvWatchReadable(Watch)
        end
        for index = 1, #removed do
            local iid = removed[index]
            if isSecret(iid) then
                return FvWatchReadable(Watch)
            end
            if found[iid] then
                return true
            end
        end
    end
    return false
end

-- Duration-threshold timer: arms one refresh for the next known buff/enchant threshold crossing instead of polling while idle.
UpdateDurationTicker = function()
    if REMIND._durationTimer then
        REMIND._durationTimer:Cancel()
        REMIND._durationTimer = nil
    end

    if not (REMIND._nextDurationRefreshTime and saved and REMIND.ShowUnderThresholdApplies()) then
        return
    end

    local delay = REMIND._nextDurationRefreshTime - GetTime() + 0.1
    if delay < 0.1 then
        delay = 0.1
    end

    REMIND._durationTimer = C_Timer.NewTimer(delay, function()
        REMIND._durationTimer = nil
        if not REMIND.ShowUnderThresholdApplies() then
            return
        end
        QueueRefresh()
    end)
end

-- Soulstone cooldown expiry: one refresh when the cooldown runs out while
-- nothing else fires. Re-armed (or cleared with nil) on every Soulstone
-- check, so a cooldown reset by a boss wipe leaves at most one stale, harmless
-- extra refresh behind. Exists only while a Warlock has the reminder on.
function REMIND.ArmSoulstoneCooldownRefresh(remaining)
    if REMIND._soulstoneCdTimer then
        REMIND._soulstoneCdTimer:Cancel()
        REMIND._soulstoneCdTimer = nil
    end
    if type(remaining) ~= "number" or remaining <= 0 then
        return
    end
    REMIND._soulstoneCdTimer = C_Timer.NewTimer(remaining + 0.1, function()
        REMIND._soulstoneCdTimer = nil
        QueueRefresh()
    end)
end

Inner.RequestRefresh = QueueRefresh
Inner.broken = false
