if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Nameplates_Events.lua
--
--  The cast event dispatcher, the plate manager, the pending and enemy watchers
--  and the faction frame.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pairs = pairs
local UnitIsUnit, UnitCanAttack = UnitIsUnit, UnitCanAttack
local C_NamePlate = C_NamePlate

local _npYOffsetState, defaultSet = Inner._npYOffsetState, Inner.defaults
local GetCastBarHeight, GetFocusCastHeight = Inner.GetCastBarHeight, Inner.GetFocusCastHeight
local frameCache, questMobCache = Inner.frameCache, Inner.questMobCache
local RefreshThreatCache, NameplateFrame = Inner.RefreshThreatCache, Inner.NameplateFrame

local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(val)
    p = val
end

-------------------------------------------------------------------------------
--  Centralized cast event dispatcher: registers all 13 SPELLCAST events ONCE globally instead
--  of 13 RegisterUnitEvent calls per plate, then looks up ns.plates[unit] (O(1) hash) and
--  dispatches to the plate's handler.
--  Cast-identity caching: the full UpdateCast path caches _kickProtected/_kickIsChannel/
--  _kickIsEmpowered on the plate, so the SPELL_UPDATE_COOLDOWN/USABLE watcher never re-reads
--  cast info per event (it re-pins the kick-tick value pair via RefreshKickTick). Cache
--  maintenance: INTERRUPTIBLE/NOT_INTERRUPTIBLE -> KickProtectionChanged re-reads and stores
--  protection, refreshes color+tick+overlay; DELAYED/CHANNEL_UPDATE/EMPOWER_UPDATE ->
--  _kickGeoDirty (next UpdateCast re-derives geometry from cached identity);
--  START/CHANNEL_START/EMPOWER_START -> _castDirtyFull = full setup; ClearUnit and mid-cast
--  token swaps (UpdateHealthValues) tear down and invalidate all cast caches.
-------------------------------------------------------------------------------
do
    local castDispatcher = CreateFrame("Frame")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_START")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_STOP")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_FAILED")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_EMPOWER_UPDATE")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    castDispatcher:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
    castDispatcher:SetScript("OnEvent", function(_, evt, unitToken, ...)
        local backing = mod.plates[unitToken]
        if not backing then
            return
        end
        local handler = backing[evt]
        if handler then
            handler(backing, unitToken, ...)
        end
    end)
    mod._castDispatcher = castDispatcher
end

local manager = CreateFrame("Frame")
manager:RegisterEvent("NAME_PLATE_UNIT_ADDED")
manager:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
manager:RegisterEvent("PLAYER_TARGET_CHANGED")
manager:RegisterEvent("PLAYER_FOCUS_CHANGED")
manager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
manager:RegisterEvent("RAID_TARGET_UPDATE")
manager:RegisterEvent("PLAYER_REGEN_DISABLED")
manager:RegisterEvent("PLAYER_REGEN_ENABLED")
manager:RegisterEvent("DISPLAY_SIZE_CHANGED")
manager:RegisterEvent("UI_SCALE_CHANGED")

local pendingUnits = {}
mod.pendingUnits = pendingUnits
-- Mouseover-highlight state lives on ns (unified enemy+friendly monitor below).

-- Per-unit event watchers for pending friendly units: per-unit frames avoid the
-- global UNIT_FLAGS firehose.
-- pendingWatchers / enemyWatchers hold the ACTIVE watcher per unit token (nil = not
-- watching). The frames themselves are pooled per token and reused, since WoW never
-- frees a frame; nameplate tokens are a fixed set, so the pools stay bounded.
local pendingWatchers = {}
local enemyWatchers = {}
local pendingWatcherFrames = {}
local enemyWatcherFrames = {}
-- Forward declarations so the two watchers can reference each other
local AcquirePendingWatcher, AcquireEnemyWatcher

-- Watches a friendly/pending unit for becoming attackable (e.g. duel start)
local function PendingWatcherOnEvent(self, evt, u)
    if not UnitCanAttack("player", u) then
        return
    end
    -- Unit became attackable -> promote to enemy plate
    self:UnregisterAllEvents()
    pendingWatchers[u] = nil
    pendingUnits[u] = nil
    local currentPlate = C_NamePlate.GetNamePlateForUnit(u)
    -- Name-only friendly NPCs are suppressed via a nameplate-keyed name
    -- overlay, not the friendlyPlates[] pool the calls below clean up.
    -- Tear it down here or the old friendly name text is left rendering
    -- on top of the new enemy plate/bar.
    if mod.RemoveFriendlyNPCOverlayForUnit then
        mod.RemoveFriendlyNPCOverlayForUnit(u, currentPlate)
    end
    -- Remove friendly plate WITHOUT restoring Blizzard UF (we'll suppress it as enemy)
    if mod.RemoveFriendlyPlateNoRestore then
        mod.RemoveFriendlyPlateNoRestore(u)
    elseif mod.RemoveFriendlyPlate then
        mod.RemoveFriendlyPlate(u)
    end
    if currentPlate then
        local backing = frameCache:Acquire()
        if not backing._mixedIn then
            Mixin(backing, NameplateFrame)
            backing._mixedIn = true
        end
        mod.plates[u] = backing
        backing:SetUnit(u, currentPlate)
    end
    -- Watch for the reverse transition (enemy -> friendly, e.g. duel end)
    enemyWatchers[u] = AcquireEnemyWatcher(u)
end

-- Watches a promoted-enemy unit for becoming friendly again (e.g. duel end)
local function EnemyWatcherOnEvent(self, evt, u)
    if UnitCanAttack("player", u) then
        return
    end
    -- Unit became friendly again -> tear down enemy plate, restore to pending
    self:UnregisterAllEvents()
    enemyWatchers[u] = nil
    local backing = mod.plates[u]
    if backing then
        if mod._ClearMouseoverPlate then
            mod._ClearMouseoverPlate(backing)
        end
        -- Same cached-ref release as NAME_PLATE_UNIT_REMOVED.
        if mod._cachedTargetPlate == backing then
            mod._cachedTargetPlate = nil
        end
        if mod._cachedFocusPlate == backing then
            mod._cachedFocusPlate = nil
        end
        backing:ClearUnit()
        frameCache:Release(backing)
        mod.plates[u] = nil
    end
    -- Re-add as pending friendly
    local currentPlate = C_NamePlate.GetNamePlateForUnit(u)
    if currentPlate then
        -- The unit keeps this nameplate (no NAME_PLATE_UNIT_ADDED follows a
        -- duel's end), so Blizzard's frame gets back here what the enemy plate
        -- parked on it; else the friendly name stays hidden until the plate is
        -- next added.
        mod.NP_ReclaimBlizzardFrame(currentPlate.UnitFrame)
        pendingUnits[u] = currentPlate
        pendingWatchers[u] = AcquirePendingWatcher(u)
        if mod.TryAddFriendlyPlate then
            mod.TryAddFriendlyPlate(u)
        end
    end
end

AcquirePendingWatcher = function(unitToken)
    local watcher = pendingWatcherFrames[unitToken]
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", PendingWatcherOnEvent)
        pendingWatcherFrames[unitToken] = watcher
    end
    watcher:RegisterUnitEvent("UNIT_FLAGS", unitToken)
    watcher:RegisterUnitEvent("UNIT_NAME_UPDATE", unitToken)
    return watcher
end

AcquireEnemyWatcher = function(unitToken)
    local watcher = enemyWatcherFrames[unitToken]
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", EnemyWatcherOnEvent)
        enemyWatcherFrames[unitToken] = watcher
    end
    watcher:RegisterUnitEvent("UNIT_FLAGS", unitToken)
    return watcher
end

-- Single shared UNIT_FACTION handler avoids N watchers each registering the global event;
-- dispatches to the correct watcher's OnEvent handler. Only active in the open world.
local factionFrame = CreateFrame("Frame")
local factionFrameActive = false

local function UpdateFactionFrameForZone()
    local _, instanceType = IsInInstance()
    local shouldBeActive = (instanceType == "none" or instanceType == nil)
    if shouldBeActive and not factionFrameActive then
        factionFrame:RegisterEvent("UNIT_FACTION")
        factionFrameActive = true
    elseif not shouldBeActive and factionFrameActive then
        factionFrame:UnregisterEvent("UNIT_FACTION")
        factionFrameActive = false
    end
end

-- Options setter of Show Threat Colors: re-derive the flag and repaint every plate's
-- colors once (the zone / role path below without its quest-cache wipe).
function mod.NP_ApplyThreatColorMode()
    mod.NP_RefreshThreatColorFlag()
    for _, backing in pairs(mod.plates) do
        backing:UpdateHealthColor()
    end
end

local function RefreshThreatContextAndPlateColors()
    RefreshThreatCache()
    -- Unit tokens are recycled across zone/instance transitions; clear any
    -- stale quest-mob decisions that were made under a different context.
    wipe(questMobCache)
    wipe(mod._questObjText)
    if mod._questObjectiveTypeEnabled then
        mod.InvalidateQuestObjectiveTypeCache()
    end
    for _, backing in pairs(mod.plates) do
        backing:UpdateHealthColor()
    end
    mod.NP_RefreshTypeScale()
end

factionFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
factionFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
factionFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
factionFrame:RegisterEvent("ROLE_CHANGED_INFORM")
factionFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
factionFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
-- The cached tank-role verdict is spec-derived for the player (effective
-- role), so the player's own spec swap must refresh it; the event also fires
-- for other units' spec updates, which change nothing here.
factionFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
factionFrame:SetScript("OnEvent", function(_, evt, unitToken)
    if evt == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Never fall through: the dispatch below keys watchers by unit token,
        -- and this event's unit args are not faction-watcher units.
        if unitToken == "player" then
            RefreshThreatContextAndPlateColors()
        end
        return
    end
    if
        evt == "PLAYER_ENTERING_WORLD"
        or evt == "ZONE_CHANGED_NEW_AREA"
        or evt == "PLAYER_DIFFICULTY_CHANGED"
        or evt == "ROLE_CHANGED_INFORM"
        or evt == "PLAYER_ROLES_ASSIGNED"
        or evt == "GROUP_ROSTER_UPDATE"
    then
        RefreshThreatContextAndPlateColors()
        if evt == "PLAYER_ENTERING_WORLD" or evt == "ZONE_CHANGED_NEW_AREA" then
            UpdateFactionFrameForZone()
        end
        if evt == "PLAYER_ENTERING_WORLD" then
            -- Initial PEW can fire before difficulty/instance data settles.
            C_Timer.After(0.6, function()
                RefreshThreatContextAndPlateColors()
                UpdateFactionFrameForZone()
            end)
        end
        return
    end
    -- UNIT_FACTION dispatch
    if pendingWatchers[unitToken] then
        local wid = pendingWatchers[unitToken]
        wid:GetScript("OnEvent")(wid, "UNIT_FACTION", unitToken)
    elseif enemyWatchers[unitToken] then
        local wid = enemyWatchers[unitToken]
        wid:GetScript("OnEvent")(wid, "UNIT_FACTION", unitToken)
    end
    -- Tap state changes arrive here, not on any per-plate event. WoW
    -- Forever's level box follows too: whether a unit can be attacked picks
    -- its level's colour, and the player's own faction moves every one.
    local backing = mod.plates[unitToken]
    if backing then
        backing:UpdateHealthColor()
        if backing._fvLevelBox then
            mod.NP_UpdateForeverLevel(backing)
        end
    else
        -- A friendly full plate's faction badge: PvP flag and faction changes.
        local fp = mod.friendlyPlates[unitToken]
        if fp then
            mod.NP_FriendlyFactionRefresh(fp)
            if fp._fvLevelBox then
                mod.NP_UpdateForeverLevel(fp)
            end
        elseif unitToken == "player" and mod._npFvLevelArmed then
            mod.NP_ForeverSweepLevels()
        end
    end
end)
-- Unified mouseover monitor (enemy + friendly). UPDATE_MOUSEOVER_UNIT fires when a mouseover
-- STARTS but never when it clears, so a single shared 0.1s ticker (alive only while a mouseover
-- exists) watches for the mouse leaving. A held mouse button transiently drops the mouseover
-- unit, so in that case we wait for GLOBAL_MOUSE_UP (handled on `manager`) and re-check.
function mod._EnsureMouseoverTicker()
    if mod._mouseoverTicker then
        return
    end
    mod._mouseoverTicker = C_Timer.NewTicker(0.1, function()
        if not UnitExists("mouseover") then
            if mod._mouseoverTicker then
                mod._mouseoverTicker:Cancel()
                mod._mouseoverTicker = nil
            end
            mod._UpdateMouseover()
            if IsMouseButtonDown() then
                manager:RegisterEvent("GLOBAL_MOUSE_UP")
            end
        end
    end)
end

-- Drop the highlight tracking if `plate` is the one currently highlighted.
-- Called from both enemy and friendly plate removal.
function mod._ClearMouseoverPlate(backing)
    if mod._currentMouseoverPlate == backing then
        mod._currentMouseoverPlate = nil
        if mod._mouseoverTicker then
            mod._mouseoverTicker:Cancel()
            mod._mouseoverTicker = nil
        end
    end
    -- Pooled enemy frames recycle without re-running ApplyBorder, so a
    -- hover-sized border is restored here before its flag is dropped.
    if backing._hoverBorderSized then
        backing._hoverBorderSized = nil
        if backing.ApplyBorder then
            backing:ApplyBorder()
        end
    end
    backing._hoverFxOn = nil
end

function mod._UpdateMouseover()
    local current = mod._currentMouseoverPlate
    if current then
        mod.HideHoverEffect(current)
        mod.ClearHoverExtras(current)
        mod._currentMouseoverPlate = nil
    end
    if not UnitExists("mouseover") then
        return
    end
    local found
    for _, backing in pairs(mod.plates) do
        if backing.unit and UnitIsUnit(backing.unit, "mouseover") then
            found = backing
            break
        end
    end
    if not found and mod.friendlyPlates then
        for _, backing in pairs(mod.friendlyPlates) do
            if backing.unit and UnitIsUnit(backing.unit, "mouseover") then
                found = backing
                break
            end
        end
    end
    if found then
        mod.ShowHoverEffect(found)
        mod.ApplyHoverExtras(found)
        mod._currentMouseoverPlate = found
    end
    mod._EnsureMouseoverTicker()
end
-- Baseline lift for friendly plates, applied to BOTH distance settings: Name Distance
-- (name-only) and the friendly plate cog's Distance slider (full plate). Name-only needs it
-- because the friendly module collapses Blizzard's two-point name anchor onto the UnitFrame
-- centre (so long names stop truncating and the guild line has room), landing the name this
-- far below Blizzard's own anchor; the full plate carries the same lift so switching modes
-- does not jump. On ns (local cap).
mod.FRIENDLY_Y_BASE = 26

-- Refresh Y-offset on all visible friendly name-only plates
function mod.RefreshFriendlyNameOnlyOffset()
    local saved = p or defaultSet
    local nameOnly = (saved.friendlyNameOnly ~= false)
    local yOff = nameOnly and ((saved.friendlyNameOnlyYOffset or 0) + mod.FRIENDLY_Y_BASE) or 0
    for unitToken, nameplate in pairs(pendingUnits) do
        if nameplate.UnitFrame then
            local uf = nameplate.UnitFrame
            if yOff ~= 0 then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, yOff)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, yOff)
                _npYOffsetState[nameplate] = true
            elseif _npYOffsetState[nameplate] then
                uf:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, 0)
                uf:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, 0)
                _npYOffsetState[nameplate] = nil
            end
        end
    end
end

manager:SetScript("OnEvent", function(self, evt, unitToken)
    if evt == "NAME_PLATE_UNIT_ADDED" then
        local nameplate = C_NamePlate.GetNamePlateForUnit(unitToken)
        if not nameplate then
            return
        end
        if not UnitCanAttack("player", unitToken) then
            pendingUnits[unitToken] = nameplate
            pendingWatchers[unitToken] = AcquirePendingWatcher(unitToken)
            if mod.TryAddFriendlyPlate then
                mod.TryAddFriendlyPlate(unitToken)
            end
            -- Color NPC names green in name-only mode
            if mod.TryColorFriendlyNPCName then
                mod.TryColorFriendlyNPCName(unitToken, nameplate)
            end
            -- Hide NPC health bars in name-only mode (show name only)
            if mod.TrySuppressNPCHealthBar then
                mod.TrySuppressNPCHealthBar(unitToken, nameplate)
            end
            -- Ensure the Blizzard UF is visible for name-only friendly plates. UnitFrames are
            -- pooled; children an earlier enemy parked already came back in the
            -- OnNamePlateAdded hook (ns.NP_ReclaimBlizzardFrame).
            local saved = p or defaultSet
            if saved.friendlyNameOnly ~= false then
                local uf = nameplate.UnitFrame
                if uf then
                    -- Restore alpha in case the recycled UF was suppressed
                    if uf:GetAlpha() < 0.01 then
                        uf:SetAlpha(1)
                    end
                    -- Restore name FontString if it was moved offscreen
                    if uf.name and uf.name:GetParent() ~= uf then
                        uf.name:SetParent(uf)
                    end
                    -- Ensure UF is parented to the nameplate (not hidden frame)
                    if uf:GetParent() ~= nameplate then
                        uf:SetParent(nameplate)
                        uf:SetAlpha(1)
                        uf:Show()
                    end
                end
                -- Apply Y-offset (+ the name-only baseline lift; see
                -- ns.FRIENDLY_Y_BASE)
                local yOff = (saved.friendlyNameOnlyYOffset or 0) + mod.FRIENDLY_Y_BASE
                if yOff ~= 0 and nameplate.UnitFrame then
                    nameplate.UnitFrame:SetPoint("TOPLEFT", nameplate, "TOPLEFT", 0, yOff)
                    nameplate.UnitFrame:SetPoint("BOTTOMRIGHT", nameplate, "BOTTOMRIGHT", 0, yOff)
                    _npYOffsetState[nameplate] = true
                end
                -- Font is applied globally via SystemFont_NamePlate override
            end
            return
        end
        pendingUnits[unitToken] = nil
        local backing = frameCache:Acquire()
        if not backing._mixedIn then
            Mixin(backing, NameplateFrame)
            backing._mixedIn = true
        end
        mod.plates[unitToken] = backing
        backing:SetUnit(unitToken, nameplate)
        -- If this plate is the current target, update the cached ref so class power pips
        -- track it immediately: no PLAYER_TARGET_CHANGED fires on recycle for the same target.
        if UnitIsUnit(unitToken, "target") then
            mod._cachedTargetPlate = backing
        end
        if UnitIsUnit(unitToken, "focus") then
            mod._cachedFocusPlate = backing
        end
    elseif evt == "NAME_PLATE_UNIT_REMOVED" then
        questMobCache[unitToken] = nil
        mod._questObjText[unitToken] = nil
        if mod._questObjectiveTypeEnabled then
            mod._questObjType[unitToken] = nil
        end
        -- The driver has already released this base's UnitFrame (base.UnitFrame is nil
        -- here); its parked pieces come back on the next acquire (ns.NP_ReclaimBlizzardFrame).
        local nameplate = C_NamePlate.GetNamePlateForUnit(unitToken)
        -- Restore NPC name color if we tinted it
        if nameplate and mod.RestoreFriendlyNPCNameColor then
            mod.RestoreFriendlyNPCNameColor(nameplate)
        end
        -- Restore NPC health bar if we suppressed it
        if nameplate and mod.RestoreNPCHealthBar then
            mod.RestoreNPCHealthBar(nameplate)
        end
        -- Drop the name-only Y-offset flag only: the pool release clears the UnitFrame's
        -- anchors and the next acquire re-anchors it (SetAllPoints).
        if nameplate then
            _npYOffsetState[nameplate] = nil
        end
        pendingUnits[unitToken] = nil
        if pendingWatchers[unitToken] then
            pendingWatchers[unitToken]:UnregisterAllEvents()
            pendingWatchers[unitToken] = nil
        end
        if enemyWatchers[unitToken] then
            enemyWatchers[unitToken]:UnregisterAllEvents()
            enemyWatchers[unitToken] = nil
        end
        local backing = mod.plates[unitToken]
        if backing then
            if mod._ClearMouseoverPlate then
                mod._ClearMouseoverPlate(backing)
            end
            -- Clear cached refs before release
            if mod._cachedTargetPlate == backing then
                mod._cachedTargetPlate = nil
            end
            if mod._cachedFocusPlate == backing then
                mod._cachedFocusPlate = nil
            end
            backing:ClearUnit()
            frameCache:Release(backing)
            mod.plates[unitToken] = nil
        end
        if mod.RemoveFriendlyPlate then
            mod.RemoveFriendlyPlate(unitToken)
        end
    elseif evt == "PLAYER_TARGET_CHANGED" then
        -- PERF: only update old + new target plates instead of iterating all
        local oldTarget = mod._cachedTargetPlate
        mod._cachedTargetPlate = nil
        -- Find new target plate
        for _, backing in pairs(mod.plates) do
            if backing.unit and UnitIsUnit(backing.unit, "target") then
                mod._cachedTargetPlate = backing
                break
            end
        end
        if oldTarget and oldTarget.unit then
            oldTarget:ApplyTarget()
            oldTarget:UpdateHealthColor()
        end
        if mod._cachedTargetPlate and mod._cachedTargetPlate ~= oldTarget then
            mod._cachedTargetPlate:ApplyTarget()
            mod._cachedTargetPlate:UpdateHealthColor()
        end
        -- Non-Target and Out of Combat Opacity: gaining/losing a target flips every plate's
        -- fade state, so this is the one full-iteration site. Zero cost while off (compares).
        if mod._ntAlpha < 1 or mod._oocAlpha < 1 then
            mod.NT_ApplyAll()
        end
    elseif evt == "PLAYER_FOCUS_CHANGED" then
        -- PERF: only update old + new focus plates instead of iterating all
        local oldFocus = mod._cachedFocusPlate
        mod._cachedFocusPlate = nil
        local focusPct = GetFocusCastHeight()
        -- Find new focus plate
        for _, backing in pairs(mod.plates) do
            if backing.unit and UnitIsUnit(backing.unit, "focus") then
                mod._cachedFocusPlate = backing
                break
            end
        end
        local function UpdateFocusPlate(backing)
            if not backing or not backing.unit then
                return
            end
            backing:UpdateHealthColor()
            -- Blizzard Style: the focus ring follows the focus, not just the target.
            if mod.NP_Style() == "blizzard" then
                mod.NP_ApplyBlizzSelection(backing)
            end
            if focusPct ~= 100 then
                local castH = GetCastBarHeight()
                if UnitIsUnit(backing.unit, "focus") then
                    castH = math.floor(castH * focusPct / 100 + 0.5)
                end
                mod.LayoutCastBar(backing, mod.GetHealthBarWidth(), castH)
                mod.LayoutCastIcon(backing, castH)
                mod.NP_SetSparkHeight(backing, castH)
                backing.kickMarker:SetHeight(castH)
            end
        end
        UpdateFocusPlate(oldFocus)
        if mod._cachedFocusPlate and mod._cachedFocusPlate ~= oldFocus then
            UpdateFocusPlate(mod._cachedFocusPlate)
        end
        -- Non-Target and Out of Combat Opacity: only the old and new focus
        -- plates change fade state on a focus swap.
        if mod._ntAlpha < 1 or mod._oocAlpha < 1 then
            if oldFocus then
                mod.NT_Apply(oldFocus)
            end
            if mod._cachedFocusPlate and mod._cachedFocusPlate ~= oldFocus then
                mod.NT_Apply(mod._cachedFocusPlate)
            end
        end
    elseif evt == "UPDATE_MOUSEOVER_UNIT" then
        mod._UpdateMouseover()
    elseif evt == "GLOBAL_MOUSE_UP" then
        self:UnregisterEvent("GLOBAL_MOUSE_UP")
        mod._UpdateMouseover()
    elseif evt == "RAID_TARGET_UPDATE" then
        for _, backing in pairs(mod.plates) do
            backing:UpdateRaidIcon()
            if p and p.nameRaidMarkerEnabled == true then
                backing:RefreshNamePosition(true)
            end
            -- A marker appearing/clearing in a side slot changes the side extents the target
            -- arrows sit outside of, so re-run arrow positioning (no-op without arrows).
            mod.PositionArrowsOutsideAuras(backing)
        end
    elseif evt == "PLAYER_REGEN_DISABLED" or evt == "PLAYER_REGEN_ENABLED" then
        for _, backing in pairs(mod.plates) do
            backing:UpdateHealthColor()
        end
        if mod._oocAlpha < 1 then
            mod.NT_ApplyAll()
        end
    elseif evt == "DISPLAY_SIZE_CHANGED" or evt == "UI_SCALE_CHANGED" then
        if mod.ApplyNamePlateClickArea then
            mod.ApplyNamePlateClickArea()
        end
    end
end)

Inner.broken = false
