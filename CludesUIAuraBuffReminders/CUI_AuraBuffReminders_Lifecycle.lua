if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_AuraBuffReminders_Lifecycle.lua
--
--  The main event frame, OnInitialize, OnEnable, the event handler, the
--  item-use detection and the event registration.
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

local CacheInstanceInfo, REMIND = Inner.CacheInstanceInfo, Inner.EABR
local EnsureGlowModeMigrated, GetPlayerClass = Inner.EnsureGlowModeMigrated, Inner.GetPlayerClass
local GetSpecID, InCombat = Inner.GetSpecID, Inner.InCombat
local InRealInstancedContent, Known = Inner.InRealInstancedContent, Inner.Known
local MarkDungeonPullStarted, Tex = Inner.MarkDungeonPullStarted, Inner.Tex
local _ownOnRaidIDs, _preCombatOwnOnRaidCache = Inner._ownOnRaidIDs, Inner._preCombatOwnOnRaidCache
local _unitInRange, GetWeaponCategory = Inner._unitInRange, Inner.GetWeaponCategory
local SnapshotOwnOnRaidBuffs = Inner.SnapshotOwnOnRaidBuffs
local SnapshotPlayerAuras, _bagCounts, AURAS = Inner.SnapshotPlayerAuras, Inner._bagCounts, Inner.AURAS
local FLASK_ITEMS, FOOD_ITEMS = Inner.FLASK_ITEMS, Inner.FOOD_ITEMS
local InvalidateItemCountCache, PALADIN_RITES = Inner.InvalidateItemCountCache, Inner.PALADIN_RITES
local RAID_BUFFS, RebuildBagCounts = Inner.RAID_BUFFS, Inner.RebuildBagCounts
local ROGUE_POISONS, SHAMAN_IMBUES = Inner.ROGUE_POISONS, Inner.SHAMAN_IMBUES
local SHAMAN_SHIELDS, WARLOCK_PETS = Inner.SHAMAN_SHIELDS, Inner.WARLOCK_PETS
local WEAPON_ENCHANT_CHOICES = Inner.WEAPON_ENCHANT_CHOICES
local WEAPON_ENCHANT_ITEMS, _dismissedUntilLoad = Inner.WEAPON_ENCHANT_ITEMS, Inner._dismissedUntilLoad
local defaultSet, GLOW_VIEW, combatIconPool = Inner.defaults, Inner.GLOW_VIEW, Inner.combatIconPool
local receiverIconPool = Inner.receiverIconPool
local GetStrata, HideCombatIcons = Inner.GetStrata, Inner.HideCombatIcons
local HideCursorIcons, ICON_SIZE, iconPool = Inner.HideCursorIcons, Inner.ICON_SIZE, Inner.iconPool
local HideAllIcons, RequestRefresh = Inner.HideAllIcons, Inner.RequestRefresh
local ApplyUnlockPos, RegisterUnlockElements = Inner.ApplyUnlockPos, Inner.RegisterUnlockElements
local BeaconInit, BeaconRefresh, TrackItemUse = Inner.BeaconInit, Inner.BeaconRefresh, Inner.TrackItemUse
local BeaconCombatEdge, CursorAttachActive = Inner.BeaconCombatEdge, Inner.CursorAttachActive
local SetDB, SetIconAnchor, SetCombatAnchor = Inner.SetDB, Inner.SetIconAnchor, Inner.SetCombatAnchor
local SetCursorAnchor, SetPanelOpen = Inner.SetCursorAnchor, Inner.SetPanelOpen
local SetInCombat, SetHuntersMarkNeeded = Inner.SetInCombat, Inner.SetHuntersMarkNeeded

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end
local iconHolder
Inner.iconAnchorSetters[#Inner.iconAnchorSetters + 1] = function(val)
    iconHolder = val
end
local combatHolder
Inner.combatAnchorSetters[#Inner.combatAnchorSetters + 1] = function(val)
    combatHolder = val
end
local cursorHolder
Inner.cursorAnchorSetters[#Inner.cursorAnchorSetters + 1] = function(val)
    cursorHolder = val
end

local _encounterSnapshotTime = nil
local _needGroupAura = false
local _isEvokerOwnOnRaid = false
local _groupAuraBroadActive = false
local _groupAuraDirty = false
local pendingOOCRefresh = false

-------------------------------------------------------------------------------
--  MAIN EVENT FRAME (forward-declared so OnEnable can reference it)
-------------------------------------------------------------------------------
local hostFrame = CreateFrame("Frame")

-- Toggles broad vs player-only UNIT_AURA registration; file-scope so OnEnable and the event handler can both use it.
local function _setBroad(on)
    if on and not _groupAuraBroadActive then
        hostFrame:RegisterEvent("UNIT_AURA")
        _groupAuraBroadActive = true
    elseif not on and _groupAuraBroadActive then
        hostFrame:UnregisterEvent("UNIT_AURA")
        hostFrame:RegisterUnitEvent("UNIT_AURA", "player")
        _groupAuraBroadActive = false
    end
end

-- Whether group-wide UNIT_AURA stays registered through combat: the Evoker
-- own-cast cache, the targeted own-aura tracker and the provider view
-- ("others missing") read group aura changes mid-fight. One predicate for the
-- pull edge and the registration pass so the two cannot drift.
function REMIND.KeepGroupAuraInCombat()
    if _isEvokerOwnOnRaid or REMIND._trackOwnOtherAuraID ~= nil then
        return true
    end
    local rbSW = saved and saved.profile.raidBuffs and saved.profile.raidBuffs.showWhen
    if not (REMIND._needsProviderCoverage and rbSW) then
        return false
    end
    return rbSW.othersMissing ~= false
end

-------------------------------------------------------------------------------
--  Lifecycle: OnInitialize (fires at ADDON_LOADED time). Creates the DB early so EABR is in _dbRegistry before PreSeedSpecProfile.
-------------------------------------------------------------------------------
function REMIND:OnInitialize()
    SetDB(CludesUI.Lite.NewDB("CludesUIAuraBuffRemindersDB", defaultSet, true))

    ---------------------------------------------------------------------------
    --  Legacy visibility-model migration. Keyed off LEGACY field presence
    --  (the DB layer has already merged the new defaults, so nil checks on
    --  the new keys cannot detect an old profile); fresh installs carry no
    --  legacy keys and every block no-ops.
    ---------------------------------------------------------------------------
    local p = saved.profile
    local collector = p and p.consumables
    -- Old single Augment Rune dropdown -> the dormant per-item "Show In"
    -- tier set (kept for the future per-item conditions cog).
    if collector and collector.runeDisplayMode ~= nil then
        collector.showIn = collector.showIn or {}
        collector.showIn.augment_rune = collector.runeDisplayMode
        collector.runeDisplayMode = nil
    end
    -- Old tiered "Show In" strings -> per-difficulty override sets. Absent
    -- category = on, so only unchecked difficulties store false ("all" =
    -- cleared entirely).
    if collector and collector.showIn then
        local function tierToSet(tier)
            if tier == "heroic_mythic" then
                return { d_normal = false, r_normal = false, r_lfr = false }
            elseif tier == "mythic" then
                return {
                    d_normal = false,
                    d_heroic = false,
                    r_lfr = false,
                    r_normal = false,
                    r_heroic = false,
                }
            end
            return nil -- "all" or unknown => every difficulty on
        end
        for k, val in pairs(collector.showIn) do
            if type(val) == "string" then
                collector.showIn[k] = tierToSet(val)
            end
        end
    end
    -- Per-spell/open-world/others-missing model -> per-section "Where to
    -- Show" + "Show When". Open-world masters map to the open_world bucket;
    -- everything else is retired.
    local rebuild = p and p.raidBuffs
    if rebuild and (rebuild.showOthersMissing ~= nil or rebuild.showNonInstanced ~= nil) then
        rebuild.showWhen = { othersMissing = (rebuild.showOthersMissing ~= false), iAmMissing = false }
        rebuild.whereToShow = { open_world = (rebuild.showNonInstanced == true) }
        rebuild.showOthersMissing, rebuild.showNonInstanced = nil, nil
    end
    local auraRec = p and p.auras
    if auraRec and auraRec.showNonInstanced ~= nil then
        auraRec.whereToShow = { open_world = (auraRec.showNonInstanced ~= false) }
        auraRec.showNonInstanced = nil
    end
    if collector and collector.showSpecialsNonInstanced ~= nil then
        collector.specialsWhereToShow = { open_world = (collector.showSpecialsNonInstanced ~= false) }
        collector.showSpecialsNonInstanced = nil
    end
    -- Old party/raid consumable thresholds -> the global timing pair.
    local display = p and p.display
    if display then
        if display.showUnderDurationDungeon ~= nil or display.showUnderDurationRaid ~= nil then
            if display.showUnder == nil then
                display.showUnder = display.showUnderDurationRaid or 5
            end
            if display.showUnderMPlus == nil then
                display.showUnderMPlus = display.showUnderDurationDungeon or 40
            end
            display.showUnderDurationDungeon = nil
            display.showUnderDurationRaid = nil
        end
        if display.showUnder == nil then
            display.showUnder = 5
        end
        if display.showUnderMPlus == nil then
            display.showUnderMPlus = 40
        end
    end
    -- Retired per-section scale keys (display scale is the one knob).
    if rebuild then
        rebuild.scale = nil
    end
    if auraRec then
        auraRec.scale = nil
    end
    if collector then
        collector.scale = nil
    end

    -- Migrates the login-active profile eagerly; profiles activated later are covered by the read-path call in ResolveGlowTint.
    EnsureGlowModeMigrated(saved.profile.display)
end

-------------------------------------------------------------------------------
--  Lifecycle: OnEnable (fires at PLAYER_LOGIN time, after PreSeedSpecProfile). All UI creation and event wiring that depends on db being ready.
-------------------------------------------------------------------------------
function REMIND:OnEnable()
    -- Expose globals for options
    _G._CUABR_AceDB = saved

    -- Talent reminder migration handled by CludesUIABR_TalentReminders.lua

    _G._CUABR_RequestRefresh = RequestRefresh
    _G._CUABR_ApplyIconBorder = REMIND.ApplyIconBorder
    _G._CUABR_ApplyAllIconBorders = REMIND.ApplyAllIconBorders
    _G._CUABR_HideAllIcons = HideAllIcons
    _G._CUABR_GLOW_VIEW = GLOW_VIEW
    _G._CUABR_EnsureGlowModeMigrated = EnsureGlowModeMigrated
    _G._CUABR_RegisterUnlock = RegisterUnlockElements
    _G._CUABR_ApplyUnlockPos = ApplyUnlockPos
    _G._CUABR_RAID_BUFFS = RAID_BUFFS
    _G._CUABR_AURAS = AURAS
    _G._CUABR_ROGUE_POISONS = ROGUE_POISONS
    _G._CUABR_PALADIN_RITES = PALADIN_RITES
    _G._CUABR_SHAMAN_IMBUES = SHAMAN_IMBUES
    _G._CUABR_SHAMAN_SHIELDS = SHAMAN_SHIELDS
    _G._CUABR_SPECIALS = REMIND.SPECIALS
    _G._CUABR_SpecialsWhere = REMIND.SpecialsWhere
    _G._CUABR_SpecialsSound = REMIND.SpecialsSound
    _G._CUABR_WARLOCK_PETS = WARLOCK_PETS
    _G._CUABR_WEAPON_ENCHANT_ITEMS = WEAPON_ENCHANT_ITEMS
    _G._CUABR_Tex = Tex
    _G._CUABR_Known = Known
    _G._CUABR_ICON_SIZE = ICON_SIZE
    _G._CUABR_FLASK_ITEMS = FLASK_ITEMS
    _G._CUABR_FOOD_ITEMS = FOOD_ITEMS
    _G._CUABR_WEAPON_ENCHANT_CHOICES = WEAPON_ENCHANT_CHOICES
    _G._CUABR_FV_WEAPON_BUFFS = REMIND.FV_WEAPON_BUFFS
    _G._CUABR_FvClassBuffs = REMIND.FvClassBuffs
    _G._CUABR_FvClassBuffOn = REMIND.FvClassBuffs and REMIND.FvClassBuffOn
    -- _CUABR_TALENT_REMINDER_ZONES set by CludesUIABR_TalentReminders.lua

    local STRATA_VALUES = CludesUI.FRAME_STRATA_LABELS
    local STRATA_ORDER = CludesUI.FRAME_STRATA_ORDER_FULL
    _G._CUABR_STRATA_VALUES = STRATA_VALUES
    _G._CUABR_STRATA_ORDER = STRATA_ORDER

    SetIconAnchor(CreateFrame("Frame", "EABR_Anchor", UIParent))
    iconHolder:SetSize(1, 1)
    iconHolder:SetFrameStrata(GetStrata())
    iconHolder:EnableMouse(false)
    ApplyUnlockPos()

    -- Combat anchor: non-secure, follows iconAnchor position; parented to UIParent so Show/Hide is never blocked by combat lockdown.
    SetCombatAnchor(CreateFrame("Frame", "EABR_CombatAnchor", UIParent))
    combatHolder:SetSize(1, 1)
    combatHolder:SetFrameStrata(GetStrata())
    combatHolder:SetFrameLevel(110)
    combatHolder:EnableMouse(false)
    combatHolder:SetAllPoints(iconHolder)
    combatHolder:Show()
    CludesUI.SetElementVisibility(combatHolder, false)

    -- Cursor anchor: tracks cursor position via OnUpdate (same as CDM).
    SetCursorAnchor(CreateFrame("Frame", "EABR_CursorAnchor", UIParent))
    cursorHolder:SetSize(1, 1)
    cursorHolder:SetFrameStrata("TOOLTIP")
    cursorHolder:SetFrameLevel(9980)
    cursorHolder:EnableMouse(false)
    cursorHolder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    do
        -- Cursor glue on the suite's shared cursor service (Tier A motionOnly: fires per render frame while the cursor MOVES, parked at rest). Subscription follows the frame's own OnShow/OnHide; OnShow snaps once via M.Get() so a cursor that moved while hidden never shows stale.
        local lastMX, lastMY
        local function GlueBody(rawX, rawY)
            local uiScale = UIParent:GetEffectiveScale()
            local cursorX = floor(rawX / uiScale + 0.5)
            local cursorY = floor(rawY / uiScale + 0.5)
            if cursorX ~= lastMX or cursorY ~= lastMY then
                lastMX, lastMY = cursorX, cursorY
                cursorHolder:ClearAllPoints()
                cursorHolder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX, cursorY + 60)
            end
        end
        cursorHolder:SetScript("OnShow", function()
            local M = CludesUI.Mouse
            if M then
                GlueBody(M.Get())
                M.SubscribeFrame("abrCursor", GlueBody, true)
            end
        end)
        cursorHolder:SetScript("OnHide", function()
            local M = CludesUI.Mouse
            if M then
                M.UnsubscribeFrame("abrCursor")
            end
        end)
    end
    -- Starts hidden: OnUpdate only runs while :IsShown(), saving CPU when no cursor-attached reminders are active.
    cursorHolder:Hide()
    CludesUI.SetElementVisibility(cursorHolder, false)

    -- Talent reminder anchor created by CludesUIABR_TalentReminders.lua (independent of iconAnchor so parent alpha doesn't hide it).

    local function ApplyStrata()
        local strata = GetStrata()
        iconHolder:SetFrameStrata(strata)
        combatHolder:SetFrameStrata(strata)
        for _, button in pairs(iconPool) do
            button:SetFrameStrata(strata)
        end
        for _, frame in pairs(combatIconPool) do
            frame:SetFrameStrata(strata)
        end
        for _, frame in pairs(receiverIconPool) do
            frame:SetFrameStrata(strata)
        end
        if REMIND._providerCastBtn and not InCombatLockdown() then
            REMIND._providerCastBtn:SetFrameStrata(strata)
        end
        REMIND.ApplyAllIconBorders()
    end
    _G._CUABR_ApplyStrata = ApplyStrata

    -- Hook CUI panel show/hide
    if CludesUI then
        CludesUI:RegisterOnShow(function()
            SetPanelOpen(true)
            HideAllIcons()
            BeaconRefresh()
        end)
        CludesUI:RegisterOnHide(function()
            SetPanelOpen(false)
            RequestRefresh()
            BeaconRefresh()
        end)
    end

    -- Group spec intel over addon comms (LibSpecialization): the lib
    -- handles all transmission itself (request on group join, broadcast on
    -- spec change, chat-lockdown deferral); we only consume its callback.
    -- Never call its request functions -- registration is the whole
    -- integration. Cache writes fire one coalesced refresh on CHANGE only,
    -- so the join burst (one callback per responding member) costs table
    -- writes plus a single refresh.
    do
        local LS = LibStub and LibStub("LibSpecialization", true)
        if LS then
            LS.RegisterGroup(REMIND, function(specID, _, _, playerName)
                if type(specID) == "number" and type(playerName) == "string" then
                    if REMIND._groupSpecs[playerName] ~= specID then
                        REMIND._groupSpecs[playerName] = specID
                        RequestRefresh()
                    end
                end
            end)
        end
    end

    REMIND.ScanEatingState()
    REMIND.SyncProviderCastSpell()
    RequestRefresh()
    if not REMIND.FOREVER then
        BeaconInit()
    end -- retail Holy Paladin beacons only
    C_Timer.After(0.5, RegisterUnlockElements)

    -- Registers broad UNIT_AURA only when the class needs group aura tracking AND only OOC: it fires 100+/sec in a raid, but in-combat CollectRaidBuffs only checks the player's own auras (PlayerHasAuraByID), so group events are pure waste. Evoker keeps broad in combat for ownOnRaid cache updates but skips RequestRefresh on group events (handler below).
    local function UpdateGroupAuraRegistration()
        -- WoW Forever keeps the player-only UNIT_AURA from file scope,
        -- whichever caller (loading screen, profile, spec override, options)
        -- runs this pass: its one group reader, Raid Buffs, has its own watch,
        -- synced by every refresh (EABR.FvSyncGroupWatch).
        if REMIND.FOREVER then
            return
        end
        local playerClass = GetPlayerClass()
        local moonkinOn = playerClass == "DRUID"
            and saved.profile.auras.enabled.moonkin_form == true
            and saved.profile.display.remindersEnabled ~= false
            and GetSpecID() == 102
            and Known(24858)
        if moonkinOn then
            hostFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
            hostFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
        else
            hostFrame:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
            hostFrame:UnregisterEvent("UPDATE_SHAPESHIFT_FORMS")
        end
        _needGroupAura = false
        _isEvokerOwnOnRaid = false
        REMIND._needsProviderCoverage = false
        REMIND._needsGroupAuraRefresh = false
        -- Only the own-cast group checks re-evaluate on roster changes: a
        -- provider's coverage already follows the joiner's UNIT_AURA.
        REMIND._rosterRefresh = false
        -- One gate controls the targeted own-aura cache. Do not pay its cost
        -- unless the relevant reminder can actually be used/shown.
        local prevTrackID = REMIND._trackOwnOtherAuraID
        REMIND._trackOwnOtherAuraID = nil
        local collector = saved.profile.consumables
        local auraRec = saved.profile.auras
        if
            playerClass == "SHAMAN"
            and Known(383010)
            and collector
            and collector.enabled
            and collector.enabled.es_ally == true
            and (IsInGroup() or IsInRaid())
        then
            REMIND._trackOwnOtherAuraID = 974
        elseif
            playerClass == "EVOKER"
            and Known(369459)
            and auraRec
            and auraRec.enabled
            and auraRec.enabled.som ~= false
            and InRealInstancedContent()
            and (IsInGroup() or IsInRaid())
        then
            REMIND._trackOwnOtherAuraID = 369459
        end
        local trackID = REMIND._trackOwnOtherAuraID
        if prevTrackID and prevTrackID ~= trackID then
            -- State kept while untracked goes stale: the old id reads as
            -- unknown (suppressed) until a scan proves it again.
            local wasKnown = REMIND._ownOtherAuraCache[prevTrackID] ~= nil
            REMIND._ownOtherAuraCache[prevTrackID] = nil
            REMIND._ownOtherAuraTargetGUID[prevTrackID] = nil
            REMIND._ownOtherAuraDuration[prevTrackID] = nil
            REMIND._ownOtherAuraExpiration[prevTrackID] = nil
            if wasKnown then
                RequestRefresh()
            end
        end
        if trackID then
            _needGroupAura = true
            REMIND._rosterRefresh = true
        end
        for _, buff in ipairs(RAID_BUFFS) do
            if buff.class == playerClass then
                _needGroupAura = true
                REMIND._needsProviderCoverage = true
                REMIND._needsGroupAuraRefresh = true
                break
            end
        end
        for _, auraInfo in ipairs(AURAS) do
            if
                auraInfo.class == playerClass
                and auraInfo.key ~= "som"
                and (auraInfo.check == "ownOnRaid" or auraInfo.check == "ownGroupOrSelf")
                and saved.profile.auras.enabled[auraInfo.key] ~= false
            then
                _needGroupAura = true
                REMIND._rosterRefresh = true
                REMIND._needsGroupAuraRefresh = true
                if playerClass == "EVOKER" and auraInfo.check == "ownOnRaid" and auraInfo.key ~= "som" then
                    _isEvokerOwnOnRaid = true
                end
                break
            end
        end
        if _needGroupAura then
            hostFrame:RegisterEvent("GROUP_JOINED")
            hostFrame:RegisterEvent("GROUP_LEFT")
            -- Start broad if OOC; in combat only while a group reader needs it
            -- (the same predicate as the pull edge).
            if InCombat() and not REMIND.KeepGroupAuraInCombat() then
                _setBroad(false)
            else
                _setBroad(true)
            end
        else
            _setBroad(false)
            hostFrame:UnregisterEvent("GROUP_JOINED")
            hostFrame:UnregisterEvent("GROUP_LEFT")
        end
        -- Tracking just turned on: seed the cache (the scan is OOC-only;
        -- combat end rescans otherwise).
        if trackID and trackID ~= prevTrackID then
            REMIND.RescanOwnOtherAuras()
        end
    end
    _G._CUABR_UpdateGroupAuraRegistration = UpdateGroupAuraRegistration
    -- Also seeds the targeted-aura cache when tracking turns on. A no-op on
    -- WoW Forever, which keeps the player-only UNIT_AURA from file scope.
    UpdateGroupAuraRegistration()

    -- Register spellcast tracking for Hunters (combat reminder for Hunter's Mark)
    if not REMIND.FOREVER and (GetPlayerClass() == "HUNTER" or GetPlayerClass() == "EVOKER") then
        hostFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end

    -- WoW Forever's Raid Buffs watch tracks its own range (EABR.FvSyncGroupWatch).
    if REMIND.FOREVER then
        return
    end

    ---------------------------------------------------------------------------
    --  Range updates: UNIT_IN_RANGE_UPDATE mirrors the raid frames' range path, so range changes retrigger group-buff evaluation without polling.
    ---------------------------------------------------------------------------
    local _lastRangeSet = {} -- [unitToken] = true/false (last known in-range state)

    -- Pre-build unit token strings to avoid per-poll allocations
    local _raidTokens = {}
    local _partyTokens = {}
    for index = 1, 40 do
        _raidTokens[index] = "raid" .. index
    end
    for index = 1, 4 do
        _partyTokens[index] = "party" .. index
    end

    local rangeFrame = CreateFrame("Frame")
    local _rangeTrackers = {}
    local function _checkUnit(u)
        if not UnitExists(u) then
            if _lastRangeSet[u] ~= nil then
                _lastRangeSet[u] = nil
                return true
            end
            return false
        end
        local status = _unitInRange(u)
        if _lastRangeSet[u] ~= status then
            _lastRangeSet[u] = status
            return true
        end
        return false
    end

    local function _checkAllRangeUnits()
        local changed = false
        if IsInRaid() then
            for index = 1, GetNumGroupMembers() do
                if _checkUnit(_raidTokens[index]) then
                    changed = true
                end
            end
        elseif IsInGroup() then
            for index = 1, GetNumSubgroupMembers() do
                if _checkUnit(_partyTokens[index]) then
                    changed = true
                end
            end
        end
        return changed
    end

    local function _onRangeEvent(_, evt, unitToken)
        if evt == "UNIT_PHASE" then
            if _checkAllRangeUnits() then
                RequestRefresh()
            end
        elseif unitToken and _checkUnit(unitToken) then
            RequestRefresh()
        end
    end

    local function _clearRangeTrackers()
        for _, trackerFrame in pairs(_rangeTrackers) do
            trackerFrame:UnregisterAllEvents()
        end
    end

    local function _trackRangeUnit(unitToken)
        if UnitIsUnit(unitToken, "player") then
            return
        end
        local trackerFrame = _rangeTrackers[unitToken]
        if not trackerFrame then
            trackerFrame = CreateFrame("Frame")
            trackerFrame:SetScript("OnEvent", _onRangeEvent)
            _rangeTrackers[unitToken] = trackerFrame
        end
        trackerFrame:RegisterUnitEvent("UNIT_IN_RANGE_UPDATE", unitToken)
        trackerFrame:RegisterUnitEvent("UNIT_CONNECTION", unitToken)
    end

    local function _rebuildRangeTracking()
        _clearRangeTrackers()
        wipe(_lastRangeSet)
        if IsInRaid() then
            for index = 1, GetNumGroupMembers() do
                _trackRangeUnit(_raidTokens[index])
            end
        elseif IsInGroup() then
            for index = 1, GetNumSubgroupMembers() do
                _trackRangeUnit(_partyTokens[index])
            end
        end
        if _checkAllRangeUnits() then
            RequestRefresh()
        end
    end

    rangeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rangeFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rangeFrame:RegisterEvent("UNIT_PHASE")
    rangeFrame:SetScript("OnEvent", function(_, evt)
        if evt == "UNIT_PHASE" then
            _onRangeEvent(nil, evt)
        else
            _rebuildRangeTracking()
        end
    end)
    _rebuildRangeTracking()
end

-- Combat start with the buffs on the cursor (Only on Cursor in Combat turns
-- that on here): the buff you provide moves from its secure button to the
-- cursor, so the button parks now, while moving it and its mouse is still
-- allowed. In combat it could only fade, and would stay clickable where it sat.
local function ParkProviderForCursor()
    if saved and CursorAttachActive(saved.profile.display) then
        REMIND.ParkProviderCastButton()
    end
end

-------------------------------------------------------------------------------
--  MAIN EVENT HANDLER (OnEvent script for runtime events)
-------------------------------------------------------------------------------
hostFrame:SetScript("OnEvent", function(_, e, firstArg, arg2, arg3)
    if e == "ENCOUNTER_START" then
        SnapshotPlayerAuras()
        if _isEvokerOwnOnRaid then
            SnapshotOwnOnRaidBuffs()
        end
        _encounterSnapshotTime = GetTime()
        -- Marks combat immediately: ENCOUNTER_START fires before InCombatLockdown() returns true but aura APIs are already restricted; without this, non-whitelisted buffs flash "missing" for ~1s.
        SetInCombat(true)
        ParkProviderForCursor()
        BeaconCombatEdge()
        RequestRefresh()
        return
    end

    if e == "PLAYER_REGEN_DISABLED" then
        -- First pull of this dungeon visit: the elevated pre-key/pre-pull
        -- threshold (EABR.GetShowUnderMinutes' showUnderMPlus) is over.
        -- WoW Forever has no pre-key window, none of retail's broad group aura
        -- registration (its Raid Buffs keep their own watch) and no Hunter's
        -- Mark reminder: the whole retail pull bookkeeping is skipped.
        if not REMIND.FOREVER then
            MarkDungeonPullStarted()
            -- Drops broad UNIT_AURA in combat unless a group reader needs it (EABR.KeepGroupAuraInCombat).
            if _needGroupAura and not REMIND.KeepGroupAuraInCombat() then
                _setBroad(false)
            end
            -- Only flag Hunter's Mark needed if the target doesn't already have it
            SetHuntersMarkNeeded(true)
            if
                C_UnitAuras
                and C_UnitAuras.GetUnitAuraBySpellID
                and UnitExists("target")
                and C_UnitAuras.GetUnitAuraBySpellID("target", 257284)
            then
                SetHuntersMarkNeeded(false)
            end
        end -- not FOREVER
        -- Hide secure buttons before lockdown. ENCOUNTER_START may already have
        -- set our combat flag, so HideAllIcons guards on InCombatLockdown itself.
        HideAllIcons()
        HideCursorIcons()
        -- Re-snapshots only if ENCOUNTER_START didn't just do it (fires ms before REGEN_DISABLED, producing a cleaner snapshot since the aura API is fully available pre-lockdown).
        -- Must snapshot before marking combat, or the group-buff lookup treats itself as restricted and reports nothing found.
        if not _encounterSnapshotTime or (GetTime() - _encounterSnapshotTime) > 1 then
            SnapshotPlayerAuras()
            if _isEvokerOwnOnRaid then
                SnapshotOwnOnRaidBuffs()
            end
        end
        SetInCombat(true)
        _encounterSnapshotTime = nil
        ParkProviderForCursor()
        BeaconCombatEdge()
        RequestRefresh()
        return
    end

    -- A fast encounter reset can end without a player combat transition, so
    -- clear ENCOUNTER_START's synthetic flag when lockdown is already gone.
    if e == "PLAYER_REGEN_ENABLED" or (e == "ENCOUNTER_END" and not InCombatLockdown()) then
        SetInCombat(false)
        -- Restore broad UNIT_AURA for OOC group buff tracking
        if _needGroupAura then
            _setBroad(true)
        end
        -- Leaving combat: clean up combat icons, do full OOC refresh with secure buttons
        SetHuntersMarkNeeded(false)
        HideCombatIcons()
        HideCursorIcons()
        BeaconCombatEdge()
        pendingOOCRefresh = false
        REMIND.RescanOwnOtherAuras()
        RequestRefresh()
        return
    end

    if e == "UNIT_SPELLCAST_SUCCEEDED" then
        -- arg1 = unit ("player"), arg2 = castGUID, arg3 = spellID
        if arg3 == 257284 then
            SetHuntersMarkNeeded(false)
            RequestRefresh()
        elseif arg3 == 369459 and REMIND._trackOwnOtherAuraID == 369459 then
            -- Cast success is an immediate fallback; UNIT_AURA will subsequently
            -- attach the concrete target GUID/auraInstanceID via HELPFUL|PLAYER.
            REMIND.SetOwnOtherAuraState(369459, true)
        elseif arg3 == 360827 and _isEvokerOwnOnRaid then
            -- Blistering Scales is secret in a key, so the aura lookups miss it;
            -- our own successful cast is the only proof it went out.
            _preCombatOwnOnRaidCache[360827] = true
            RequestRefresh()
        end
        return
    end

    if e == "PLAYER_DEAD" then
        -- Inky Blackness (and other buffs) drop on death; refresh so aura-based reminders re-evaluate and reappear once lost.
        RequestRefresh()
        return
    end

    if e == "PLAYER_ENTERING_WORLD" then
        wipe(_dismissedUntilLoad)
        -- Preserve the last known targeted-aura state across loading screens;
        -- nil is unknown and readers suppress until the delayed rescan resolves it.
        -- WoW Forever has no targeted own-aura tracking (its Raid Buffs keep
        -- their own group watch).
        if not REMIND.FOREVER then
            C_Timer.After(0.5, function()
                CacheInstanceInfo()
                REMIND.ReevaluateOwnOtherAuraTracking()
            end)
        else
            -- The minimap's trackers and the Sleeping Bag are read afresh after
            -- a loading screen.
            REMIND._fvTrackDirty = true
            REMIND._fvSleepBag = nil
        end
        REMIND.ScanEatingState()
        if not InCombatLockdown() then
            REMIND.SyncProviderCastSpell()
        end
        -- GetInstanceInfo() can return stale data on the first frame after a loading screen (e.g. still
        -- reporting the previous zone on delve entry), which would show a reminder that "Where to Show"
        -- disables for the new location. Skip the immediate refresh and wait for the corrected one.
        C_Timer.After(0.5, RequestRefresh)
        return
    end

    if e == "UNIT_AURA" then
        -- arg1 = unit token. Player aura changes always refresh; group member changes only matter for Evoker ownOnRaid cache updates and OOC raid buff checks (broad UNIT_AURA is only registered for classes needing group tracking).
        if firstArg == "player" then
            if not REMIND.FOREVER then
                REMIND.UpdateEatingState(arg2)
            end -- eating channel feeds the retail food reminder only
            local isEvoker = GetPlayerClass() == "EVOKER"
            if isEvoker and InCombat() and IsInGroup() then
                for _, ident in ipairs(_ownOnRaidIDs) do
                    if REMIND._OwnCastOn("player", ident) then
                        _preCombatOwnOnRaidCache[ident] = true
                    end
                end
            end
            RequestRefresh()
        else
            -- Group member aura change (fast unit-type check via first byte). Broad UNIT_AURA stays registered in combat for Evoker ownOnRaid / provider-view coverage tracking; coalesces group events into one deferred refresh.
            if firstArg and (firstArg:match("^party%d+$") or firstArg:match("^raid%d+$")) then
                if REMIND._trackOwnOtherAuraID then
                    REMIND.UpdateOwnOtherAuraForUnit(firstArg)
                end
                if _isEvokerOwnOnRaid and InCombat() and IsInGroup() then
                    for _, ident in ipairs(_ownOnRaidIDs) do
                        if not _preCombatOwnOnRaidCache[ident] and REMIND._OwnCastOn(firstArg, ident) then
                            _preCombatOwnOnRaidCache[ident] = true
                        end
                    end
                end
                -- The targeted tracker refreshes only when its own cached
                -- state changes. Do not rebuild the whole reminder list for
                -- unrelated group aura traffic when that tracker is the sole
                -- reason broad UNIT_AURA is registered.
                if REMIND._needsGroupAuraRefresh and not _groupAuraDirty then
                    _groupAuraDirty = true
                    C_Timer.After(0.3, function()
                        _groupAuraDirty = false
                        RequestRefresh()
                    end)
                end
            end
        end
        return
    end

    if e == "UNIT_ENTERED_VEHICLE" or e == "UNIT_EXITED_VEHICLE" then
        if firstArg == "player" then
            RequestRefresh()
        end
        return
    end

    -- Roster changes do not touch player buffs/consumables; only the receiver
    -- view (class presence) and the own-cast group checks re-evaluate here.
    if e == "GROUP_ROSTER_UPDATE" then
        REMIND.ReevaluateOwnOtherAuraTracking()
        local rbSW = saved and saved.profile.raidBuffs and saved.profile.raidBuffs.showWhen
        if REMIND._rosterRefresh or (rbSW and rbSW.iAmMissing == true) then
            RequestRefresh()
        end
        return
    end

    -- Bag CONTENT changes (BAG_UPDATE/_DELAYED) alter item counts/resolution, so re-scan. BAG_UPDATE_COOLDOWN
    -- is intentionally NOT registered: it fires ~1/sec from cooldown ticks, changes nothing reminder-relevant, and would refresh every second and bust the resolved-item cache.
    if e == "BAG_UPDATE_DELAYED" or e == "BAG_UPDATE" then
        InvalidateItemCountCache()
        REMIND._fvSleepBag = nil
    end

    -- Equipped-weapon changes alter weapon-enchant resolution (weapon type -> which enchant item/slots show). Item counts are unchanged, so only the resolved cache needs rebuilding.
    if e == "UNIT_INVENTORY_CHANGED" then
        -- UNIT_INVENTORY_CHANGED also fires for temp enchants, procs, durability, etc.; only the WEAPON TYPE feeds resolution, so re-resolves only when the category changed (vs the last-resolved cat).
        local R = REMIND._resolved
        if GetWeaponCategory(16) ~= R.we[16].cat or GetWeaponCategory(17) ~= R.we[17].cat then
            R.dirty = true
        end
    end

    -- Dismount: the pet comes back a moment AFTER the mount display drops, so the "Pet" reminder would flash in that gap. Grace-window it, and schedule the refresh that closes the window (nothing else fires when the pet is genuinely absent, which would latch the reminder off).
    if e == "PLAYER_MOUNT_DISPLAY_CHANGED" and not IsMounted() then
        REMIND._petRemountGrace = GetTime() + 2
        C_Timer.After(2.1, RequestRefresh)
    end

    -- Talent/spec changes affect group aura tracking and form availability.
    if e == "PLAYER_TALENT_UPDATE" or e == "TRAIT_CONFIG_UPDATED" or e == "PLAYER_SPECIALIZATION_CHANGED" then
        REMIND.ReevaluateOwnOtherAuraTracking()
    end

    -- WoW Forever (its only registrations): a new rank joins the custom spells'
    -- rank families on the next pass (EABR.ForeverFamily) and the minimap's
    -- trackers are read again (EABR.FvTrackingState); a spellbook change the
    -- Action Picker listens to (a respec can take a spell away) rebuilds the
    -- families and the class buff choices; a gear change outside the two
    -- weapon slots is ignored.
    if e == "LEARNED_SPELL_IN_SKILL_LINE" or (REMIND.FOREVER and e == "SPELLS_CHANGED") then
        REMIND._fvFamDirty = true
        REMIND._fvClassPickerGroups = nil
        if e == "LEARNED_SPELL_IN_SKILL_LINE" then
            REMIND._fvTrackDirty = true
        end
    elseif e == "MINIMAP_UPDATE_TRACKING" then
        REMIND._fvTrackDirty = true
    elseif e == "PLAYER_EQUIPMENT_CHANGED" and firstArg ~= 16 and firstArg ~= 17 then
        -- Weapon Buffs (its only registration): only a weapon slot matters.
        return
    end

    -- All other events: just refresh
    RequestRefresh()
end)

-- Item use tracking: _bagCounts (built by RebuildBagCounts, shared with the consumable item-count cache) is the
-- single source of truth for bag contents. On BAG_UPDATE_DELAYED, rebuilds ONCE and diffs against the previous snapshot to detect dropped (used) items -- no second bag walk.
local _prevBagCounts = {}

local function DetectUsedItem()
    if not saved then
        return
    end
    RebuildBagCounts()
    for itemId, oldCount in pairs(_prevBagCounts) do
        if (_bagCounts[itemId] or 0) < oldCount then
            TrackItemUse(itemId)
        end
    end
    wipe(_prevBagCounts)
    for k, val in pairs(_bagCounts) do
        _prevBagCounts[k] = val
    end
end

-- Item-use tracking serves the consumable pickers; WoW Forever has no consumable reminders.
if not REMIND.FOREVER then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(_, ev)
        if ev == "PLAYER_LOGIN" then
            C_Timer.After(1, function()
                RebuildBagCounts()
                wipe(_prevBagCounts)
                for k, val in pairs(_bagCounts) do
                    _prevBagCounts[k] = val
                end
            end)
        elseif ev == "BAG_UPDATE_DELAYED" then
            DetectUsedItem()
        end
    end)
end

if REMIND.FOREVER then
    -- WoW Forever: only what its sections need -- combat edges, zone changes,
    -- the player's own aura changes, vehicles, the death states, the rested
    -- state's edges and newly learned spells (a rank joins the custom spells'
    -- families, a raid buff becomes castable). Raid Buffs adds its group
    -- events itself (EABR.FvSyncGroupWatch), the two trackers their minimap
    -- event (EABR.FvSyncTrackingEvent), the Action Picker its spellbook event
    -- (EABR.FvSyncPickerSpellEvents).
    hostFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
    hostFrame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    hostFrame:RegisterEvent("ENCOUNTER_START")
    hostFrame:RegisterEvent("ENCOUNTER_END")
    hostFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    hostFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    hostFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hostFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    hostFrame:RegisterUnitEvent("UNIT_AURA", "player")
    hostFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    hostFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    hostFrame:RegisterEvent("PLAYER_DEAD")
    hostFrame:RegisterEvent("PLAYER_ALIVE")
    hostFrame:RegisterEvent("PLAYER_UNGHOST")
    -- Class trackers and Find Treasure have no aura edge: their minimap event
    -- is listened to only while a reminder that reads them can show
    -- (EABR.CollectForever; EABR.FvStandDown turns it off).
    function REMIND.FvSyncTrackingEvent(wanted)
        if wanted == (REMIND._fvTrackEv or false) then
            return
        end
        REMIND._fvTrackEv = wanted
        if wanted then
            -- Nothing was heard while it was off: the minimap is read afresh.
            REMIND._fvTrackDirty = true
            hostFrame:RegisterEvent("MINIMAP_UPDATE_TRACKING")
        else
            hostFrame:UnregisterEvent("MINIMAP_UPDATE_TRACKING")
        end
    end
    -- The Action Picker's choices follow the spellbook: SPELLS_CHANGED is
    -- listened to only while the picker is on and a reminder can show
    -- (EABR.CollectForever; EABR.FvStandDown turns it off).
    function REMIND.FvSyncPickerSpellEvents(wanted)
        REMIND._fvPickerSpellEvents = wanted
        if wanted then
            -- Talent changes may have happened while this listener was off.
            REMIND._fvFamDirty = true
            REMIND._fvClassPickerGroups = nil
            hostFrame:RegisterEvent("SPELLS_CHANGED")
        else
            hostFrame:UnregisterEvent("SPELLS_CHANGED")
        end
    end
    function REMIND.FvSyncWeaponEvents(wanted)
        if wanted == (REMIND._fvWeaponEv or false) then
            return
        end
        REMIND._fvWeaponEv = wanted
        if wanted then
            hostFrame:RegisterEvent("WEAPON_ENCHANT_CHANGED")
            hostFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        else
            hostFrame:UnregisterEvent("WEAPON_ENCHANT_CHANGED")
            hostFrame:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
        end
    end
    function REMIND.FvSyncBagEvent(wanted)
        if wanted == (REMIND._fvBagEv or false) then
            return
        end
        REMIND._fvBagEv = wanted
        if wanted then
            InvalidateItemCountCache()
            hostFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        else
            hostFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        end
    end
    -- A Cozy Sleeping Bag bought or looted while none is owned and the shared
    -- bag listener above is off: one item count per bag change until one shows
    -- up, which wakes the reminder; that listener takes over from there
    -- (EABR.FvSleepingBagOwned).
    local sleepWatcher
    function REMIND.FvSyncSleepBagWatch(wanted)
        if wanted == (REMIND._fvSleepWatch or false) then
            return
        end
        REMIND._fvSleepWatch = wanted
        if wanted then
            if not sleepWatcher then
                sleepWatcher = CreateFrame("Frame")
                sleepWatcher:SetScript("OnEvent", function()
                    if (C_Item.GetItemCount(REMIND.SLEEPING_BAG_ITEM) or 0) > 0 then
                        REMIND._fvSleepBag = true
                        REMIND.FvSyncSleepBagWatch(false)
                        RequestRefresh()
                    end
                end)
            end
            sleepWatcher:RegisterEvent("BAG_UPDATE_DELAYED")
        elseif sleepWatcher then
            sleepWatcher:UnregisterEvent("BAG_UPDATE_DELAYED")
        end
    end
else
    hostFrame:RegisterEvent("ENCOUNTER_START")
    hostFrame:RegisterEvent("ENCOUNTER_END")
    hostFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    hostFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    hostFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hostFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    hostFrame:RegisterEvent("SPELLS_CHANGED")
    hostFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    hostFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    hostFrame:RegisterEvent("PLAYER_LEVEL_CHANGED")
    hostFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    hostFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    hostFrame:RegisterUnitEvent("UNIT_AURA", "player")
    hostFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    hostFrame:RegisterEvent("CHALLENGE_MODE_START")
    hostFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    hostFrame:RegisterEvent("CHALLENGE_MODE_RESET")
    hostFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    hostFrame:RegisterEvent("WEAPON_ENCHANT_CHANGED")
    hostFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    hostFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    hostFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    hostFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    hostFrame:RegisterEvent("PLAYER_DEAD")
    hostFrame:RegisterEvent("PLAYER_ALIVE")
    hostFrame:RegisterEvent("PLAYER_UNGHOST")
    hostFrame:RegisterEvent("BAG_UPDATE")
    hostFrame:RegisterUnitEvent("UNIT_PET", "player")
    -- UNIT_PET fires on pet summon/dismiss, NOT stance changes. Pet on Passive reacts to the pet's command state via the pet action bar -- PET_BAR_UPDATE is that event; without it the reminder only re-evaluated on reload.
    hostFrame:RegisterEvent("PET_BAR_UPDATE")
end

Inner.broken = false
