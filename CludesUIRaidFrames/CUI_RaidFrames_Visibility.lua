if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Visibility.lua
--
--  Range fading, the ghost aura safety net and UpdateVisibility.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsVisible = UnitIsVisible
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsUnit = UnitIsUnit
local UnitInRange = UnitInRange
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local InCombatLockdown = InCombatLockdown
local GetNumGroupMembers = GetNumGroupMembers
local C_Timer = C_Timer

local allButtons, FFD, GetFFD, separatedHdrs = Inner.allButtons, Inner.FFD, Inner.GetFFD, Inner.separatedHdrs
local unitToButton, RebuildUnitMap = Inner.unitToButton, Inner.RebuildUnitMap
local UpdateAllButtons, LayoutGroups = Inner.UpdateAllButtons, Inner.LayoutGroups
local SetFramesVisible, SetRangeUpdate = Inner.SetFramesVisible, Inner.SetRangeUpdate
-- false in the table for a class without one; nil here, which the tests below expect
local playerFriendlySpell = Inner.playerFriendlySpell or nil
local playerRezSpell = Inner.playerRezSpell or nil

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end
local containerFrame
Inner.containerFrameSetters[#Inner.containerFrameSetters + 1] = function(val) containerFrame = val end

-- Assigned below; CUI_RaidFrames_Reload.lua holds the forward declaration
-- ReloadFrames calls through.
local RangeUpdate

-------------------------------------------------------------------------------
--  Range fading
--  Event-driven via UNIT_IN_RANGE_UPDATE for the standard ~40yd interact range
--  (all classes), which also covers dead units (they use UnitInRange like the
--  living). A conditional 0.5s refiner poll handles only what the event cannot:
--  the tighter friendly-spell range (Evoker/Rogue) and re-syncing a revived unit
--  back to that tight range. Pure classes with no rez run fully event-driven.
-------------------------------------------------------------------------------
-- Wrapped in a do-block; only Start/StopRangeTicker (+ RangeUpdate, declared in
-- this file's header) need to be reachable from later code.
local StartRangeTicker, StopRangeTicker
do
    local rangeTicker = nil

    local UnitPhaseReason = UnitPhaseReason
    local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange

    -- Classes whose effective reach is well under the ~40yd UnitInRange interact
    -- range, so living units are refined with a tighter friendly spell check.
    local usesSpellRange = playerFriendlySpell ~= nil
    -- Whether the player can resurrect (enables dead-unit rez-range refinement).
    local playerHasRez = playerRezSpell ~= nil

    -- Apply final alpha to a button: range alpha * BM frame alpha. Range alpha is
    -- stored in FFD so BM can read it; BM alpha lives in _bmSavedAlpha so range can
    -- read it. Each system stores its own value; final apply multiplies the two.
    local function ApplyRangeAlpha(button, rangeAlpha)
        local skinData = GetFFD(button)
        skinData.rangeAlpha = rangeAlpha
        local bmA = button._bmSavedAlpha or 1
        button:SetAlpha(bmA * rangeAlpha)
        -- A 3D party portrait does not take the button's alpha: mirror it.
        if skinData.pt and skinData.pt._3dOn then mod.RF_PtModelAlpha(skinData, bmA * rangeAlpha) end
    end

    -- Secret-safe range alpha via SetAlphaFromBoolean (UnitInRange can return a
    -- secret boolean in Midnight). Marks rangeAlpha nil so UpdateButton/BM leave
    -- the secret-set alpha alone.
    local function ApplyRangeAlphaSecret(button, inRange, inAlpha, outAlpha)
        local bmA = button._bmSavedAlpha or 1
        if button.SetAlphaFromBoolean then
            button:SetAlphaFromBoolean(inRange, bmA * inAlpha, bmA * outAlpha)
        else
            ApplyRangeAlpha(button, inAlpha)
            return
        end
        local skinData = GetFFD(button)
        skinData.rangeAlpha = nil
        -- A 3D party portrait does not take the button's alpha: mirror it.
        if skinData.pt and skinData.pt._3dOn then
            mod.RF_PtModelAlphaSecret(skinData, inRange, bmA * inAlpha, bmA * outAlpha)
        end
    end

    -- Evaluate + apply range alpha for ONE unit. Shared by the
    -- UNIT_IN_RANGE_UPDATE event, the refiner poll, the seed pass, and roster
    -- assignment. Standard living units take the secret-safe UnitInRange path.
    local function UpdateButtonRange(unitToken, button)
        -- Read oorAlpha through the party-aware proxy so a custom party_oorAlpha
        -- actually applies to party frames (was reading the raid value directly).
        local rd = GetFFD(button)
        local rs = rd._isParty and mod._scaledPartyProxy
            or (rd._isExtra and mod._scaledExtraProxy)
            or mod._scaledProfile
        local oorAlpha = rs.oorAlpha or 0.4
        if UnitIsUnit(unitToken, "player") or not UnitExists(unitToken) then
            ApplyRangeAlpha(button, 1)
        elseif not UnitIsConnected(unitToken) then
            -- Offline units take a fixed 80% alpha, never the out-of-range fade --
            -- an offline player isn't "out of range", and a steady alpha reads
            -- better alongside the offline status tint. Overrides oorAlpha entirely.
            ApplyRangeAlpha(button, 0.8)
        elseif UnitPhaseReason and UnitPhaseReason(unitToken) then
            ApplyRangeAlpha(button, oorAlpha)
        elseif UnitIsDeadOrGhost(unitToken) then
            -- Ghost units need to be checked using a rez-spell because UnitInRange checks the ghost's range, not the corpse's.
            -- We want to provide rez-range feedback based on the corpse's position.
            if playerHasRez then
                local region = C_Spell_IsSpellInRange(playerRezSpell, unitToken)
                if region == true then
                    ApplyRangeAlpha(button, 1)
                elseif region == false then
                    ApplyRangeAlpha(button, oorAlpha)
                else
                    -- Use the standard ~40yd interact range (UnitInRange) as fallback
                    ApplyRangeAlphaSecret(button, UnitInRange(unitToken), 1, oorAlpha)
                end
            else
                -- Use the standard ~40yd interact range (UnitInRange) when player has no rez spell
                ApplyRangeAlphaSecret(button, UnitInRange(unitToken), 1, oorAlpha)
            end
        elseif usesSpellRange then
            local region = C_Spell_IsSpellInRange(playerFriendlySpell, unitToken)
            if region == true then
                ApplyRangeAlpha(button, 1)
            elseif region == false then
                ApplyRangeAlpha(button, oorAlpha)
            else
                -- r == nil: no range relationship to this unit (unit-targeted spell, so a
                -- same-zone out-of-range target already returned false above) -- almost
                -- always a different zone (or a brief untargetable/LOS blip). Resolve via
                -- the secret-safe ~40yd UnitInRange (false -> faded) rather than holding the
                -- last alpha, which stranded a zone-departed unit at its old in-range alpha.
                -- Cannot reintroduce the 25-vs-40yd boundary flicker: that needed the spell
                -- check to return nil AT the boundary, which a stable far same-zone target does not.
                ApplyRangeAlphaSecret(button, UnitInRange(unitToken), 1, oorAlpha)
            end
        else
            ApplyRangeAlphaSecret(button, UnitInRange(unitToken), 1, oorAlpha)
        end
    end
    mod._UpdateButtonRange = UpdateButtonRange

    -- Refiner handles only what UNIT_IN_RANGE_UPDATE cannot: the tighter friendly-spell
    -- range (Evoker/Rogue). Dead units use the event-driven UnitInRange path like living
    -- units, but are still polled so a spell-range class hands a revived unit back to its
    -- tight spell range (one-shot resync via _rangeWasDead). Living, non-spell-range units
    -- are owned by the event and skipped here, so the poll does ~no work for a stable raid.
    local function RefineButtonRange(unitToken, button)
        if not UnitExists(unitToken) or UnitIsUnit(unitToken, "player") then return end
        local skinData = GetFFD(button)
        if UnitIsDeadOrGhost(unitToken) then
            skinData._rangeWasDead = true
            UpdateButtonRange(unitToken, button)
        elseif skinData._rangeWasDead then
            skinData._rangeWasDead = nil
            UpdateButtonRange(unitToken, button)
        elseif usesSpellRange then
            UpdateButtonRange(unitToken, button)
        end
    end

    -- Seed / full re-evaluation of every assigned unit (enable, roster change,
    -- phase change). Kept as RangeUpdate (forward-declared) for existing callers.
    RangeUpdate = function()
        for unitToken, button in pairs(unitToButton) do
            UpdateButtonRange(unitToken, button)
        end
        for unitToken, button in pairs(mod._partyUnitToButton) do
            UpdateButtonRange(unitToken, button)
        end
        for unitToken, button in pairs(mod._xfUnitToButton) do
            UpdateButtonRange(unitToken, button)
        end
        mod._PF_RangeSeed()
    end
    SetRangeUpdate(RangeUpdate)
    mod._RangeSeedAll = RangeUpdate

    local function RangeRefineAll()
        for unitToken, button in pairs(unitToButton) do
            RefineButtonRange(unitToken, button)
        end
        for unitToken, button in pairs(mod._partyUnitToButton) do
            RefineButtonRange(unitToken, button)
        end
        for unitToken, button in pairs(mod._xfUnitToButton) do
            RefineButtonRange(unitToken, button)
        end
    end

    function StartRangeTicker()
        -- Seed initial alpha; UNIT_IN_RANGE_UPDATE only fires on later changes.
        RangeUpdate()
        -- Conditional refiner: only spell-range or rez-capable classes poll.
        -- Everyone else is fully event-driven (zero polling).
        if not rangeTicker and (usesSpellRange or playerHasRez) then
            rangeTicker = C_Timer.NewTicker(0.5, RangeRefineAll)
        end
    end

    function StopRangeTicker()
        if rangeTicker then
            rangeTicker:Cancel()
            rangeTicker = nil
        end
        -- Reset range alpha, respect BM frame alpha
        for _, button in pairs(unitToButton) do
            ApplyRangeAlpha(button, 1)
        end
        for _, button in pairs(mod._partyUnitToButton) do
            ApplyRangeAlpha(button, 1)
        end
        for _, button in pairs(mod._xfUnitToButton) do
            ApplyRangeAlpha(button, 1)
        end
    end
end -- range fading section

-------------------------------------------------------------------------------
--  Ghost aura safety net
--  Throttled 1s ticker: UNIT_AURA stops firing for invisible/DC'd units and the
--  render-visibility edge has no event, so a unit that ghosts (loadscreen, out
--  of render range, disconnect) keeps whatever its containers last parsed. On
--  regain the containers are re-parsed in place (the same UpdateAllAuras lever
--  the assist gate uses on its own false->true edge). The same pass audits each
--  container's own unit binding, which nothing else re-drives once the header
--  stops re-asserting the token.
-------------------------------------------------------------------------------
local ghostTicker = nil

local function GhostAuraCheck()
    local function checkUnit(unitToken, button)
        local skinData = GetFFD(button)
        -- unitToButton et al. only ever gain entries on reassignment, never drop
        -- the old one, so unit/btn here can be a stale pairing; re-confirm against
        -- the button's own live attribute before writing to it.
        if button:GetAttribute("unit") == unitToken and mod.RFC_RepointStale then
            mod.RFC_RepointStale(skinData, unitToken)
        end
        if not UnitIsVisible(unitToken) or not UnitIsConnected(unitToken) then
            if not skinData.ghostCleared then
                skinData.ghostCleared = true
                -- Binding at ghost time: a reassignment inside the window already
                -- re-parsed the containers (RFC_OnUnitAssigned), so the regain pass
                -- skips a button whose binding moved.
                skinData.ghostUnit = skinData.rfcUnit
            end
        else
            if skinData.ghostCleared then
                skinData.ghostCleared = false
                -- unitToButton only ever gains entries, so unit/btn can be a stale
                -- pairing: re-parse only containers still bound to this unit.
                if skinData.rfcUnit == unitToken and skinData.ghostUnit == unitToken then
                    if skinData.rfcDebuffs then skinData.rfcDebuffs:UpdateAllAuras() end
                    if skinData.rfcDispLoc then skinData.rfcDispLoc:UpdateAllAuras() end
                    if skinData.rfcBm then skinData.rfcBm:UpdateAllAuras() end
                    if skinData.rfcBmChain then
                        for _, cc in pairs(skinData.rfcBmChain) do
                            cc:UpdateAllAuras()
                        end
                    end
                    if skinData.dmTiles then
                        for _, c in pairs(skinData.dmTiles) do
                            c:UpdateAllAuras()
                        end
                    end
                end
                skinData.ghostUnit = nil
            end
        end
    end
    for unitToken, button in pairs(unitToButton) do
        checkUnit(unitToken, button)
    end
    for unitToken, button in pairs(mod._partyUnitToButton) do
        checkUnit(unitToken, button)
    end
    for unitToken, button in pairs(mod._xfUnitToButton) do
        checkUnit(unitToken, button)
    end
end

local function StartGhostTicker()
    if not ghostTicker then ghostTicker = C_Timer.NewTicker(1.0, GhostAuraCheck) end
end

local function StopGhostTicker()
    if ghostTicker then
        ghostTicker:Cancel()
        ghostTicker = nil
    end
    -- Clear ghost flags
    for _, button in pairs(unitToButton) do
        local skinData = GetFFD(button)
        skinData.ghostCleared = nil
    end
    for _, button in pairs(mod._partyUnitToButton) do
        local skinData = GetFFD(button)
        skinData.ghostCleared = nil
    end
    for _, button in pairs(mod._xfUnitToButton) do
        local skinData = GetFFD(button)
        skinData.ghostCleared = nil
    end
end

-------------------------------------------------------------------------------
--  Visibility: show/hide based on solo/group/raid setting
-------------------------------------------------------------------------------
local framesVisible = false
Inner.framesVisibleSetters[#Inner.framesVisibleSetters + 1] = function(val) framesVisible = val end

-- True when the player is inside an arena instance. Arena puts you in a RAID
-- group, but we deliberately show our PARTY frames there (the party header is
-- bound to raid1-5 via showRaid=true) so small-group styling applies and
-- external trackers that anchor to our party frames keep working. Detection is
-- by instance type and must be checked BEFORE any IsInRaid() branch, since
-- arena makes IsInRaid() return true.
mod._InArena = function()
    local _, instanceType = IsInInstance()
    return instanceType == "arena"
end

-- Party frames while IsInRaid() is true: arena (the whole team, above) or the
-- opt-in Small Raid setting, which shows group 1 as party frames and hides
-- every other member while the raid holds fewer than 10 players. Every
-- "party or raid frames" decision reads this, never ns._InArena directly;
-- the group-1 filter itself lives in _LayoutPartyFrames (ns._SmallRaidGroup).
mod._PartyInRaid = function()
    if mod._InArena() then return true end
    return saved.profile.partySmallRaid == true and IsInRaid() and GetNumGroupMembers() < 10
end

-- The subgroup the party header is limited to in Small Raid mode; nil in
-- arena (whole team) and outside party-in-raid mode.
mod._SmallRaidGroup = function()
    if mod._InArena() or not mod._PartyInRaid() then return nil end
    return 1
end

-- Which set the group state shows (raid, party): raid frames in a raid, party
-- frames in a party (arena and Small Raid included), each set's Show When Solo
-- outside a group. ns._RF_VIS_MACROS spells the same rule as macro conditions.
mod._RFVisWanted = function()
    local cfg = saved.profile
    if not IsInGroup() then
        return cfg.showWhenSolo and true or false, cfg.partyShowWhenSolo and true or false
    end
    if IsInRaid() and not mod._PartyInRaid() then return true, false end
    return false, true
end

-- Secure visibility drivers on both containers: the containers are implicitly
-- protected (secure headers inside), so only secure code can show or hide them
-- in combat, and a driver re-checks its macro every 0.2 s on its own. A group
-- joined, or a party turned raid, mid-fight then shows its frames at once.
-- Macro per [mode][that set's Show When Solo]; the mode is fixed out of combat.
-- Group state reads unit existence: the [group] conditions keep the state from
-- before combat until combat ends, so a group joined mid-fight reads as solo
-- there, while unit tokens follow the roster at once. raid1 exists exactly in
-- a raid; party1 in a party with another member; [group] stays OR'd in so a
-- group with no other member counts as grouped, as IsInGroup() does.
-- Small Raid: raid tokens run contiguously from raid1 and exist only in a raid,
-- so raid10 exists exactly when a raid holds 10 or more members (the
-- GetNumGroupMembers() < 10 rule); a party never reaches it.
-- Arena has no macro condition: it is taken at the zone-in pass.
mod._RF_VIS_MACROS = {
    raid = {
        group = {
            [true] = "[@raid1,exists] show; [@party1,exists][group] hide; show",
            [false] = "[@raid1,exists] show; hide",
        },
        small = {
            [true] = "[@raid10,exists] show; [@raid1,exists][@party1,exists][group] hide; show",
            [false] = "[@raid10,exists] show; hide",
        },
        arena = { [true] = "[@raid1,exists][@party1,exists][group] hide; show", [false] = "hide" },
    },
    party = {
        group = {
            [true] = "[@raid1,exists] hide; show",
            [false] = "[@raid1,exists] hide; [@party1,exists][group] show; hide",
        },
        small = {
            [true] = "[@raid10,exists] hide; show",
            [false] = "[@raid10,exists] hide; [@raid1,exists][@party1,exists][group] show; hide",
        },
        arena = { [true] = "show", [false] = "[@raid1,exists][@party1,exists][group] show; hide" },
    },
}

-- Registers each container's macro, only when its text changes (driver
-- registration is a protected action: out of combat, or the login window).
mod._RFSyncVisDrivers = function()
    local pc = mod._partyContainerFrame
    if not containerFrame or not pc or InCombatLockdown() then return end
    local cfg = saved.profile
    local M = mod._RF_VIS_MACROS
    local mode = (mod._InArena() and "arena") or ((cfg.partySmallRaid == true) and "small") or "group"
    local region = M.raid[mode][cfg.showWhenSolo and true or false]
    local p = M.party[mode][cfg.partyShowWhenSolo and true or false]
    if mod._rfRaidVisMacro ~= region then
        RegisterStateDriver(containerFrame, "visibility", region)
        mod._rfRaidVisMacro = region
    end
    if mod._rfPartyVisMacro ~= p then
        RegisterStateDriver(pc, "visibility", p)
        mod._rfPartyVisMacro = p
    end
end

-- A set that hides keeps its buttons' units (a hidden header ignores the
-- roster) while its events stop routing: forget each painted occupant so the
-- next assignment, in combat too, takes the full repaint.
mod._RFForgetOccupants = function(entries)
    for index = 1, #entries do
        local skinData = FFD[entries[index]]
        if skinData then skinData._lastGuid = nil end
    end
end

local function UpdateVisibility()
    if not containerFrame then return end
    if InCombatLockdown() then return end

    -- Preview overrides all visibility logic -- real buttons stay suppressed
    -- (alpha), no state changes; the preview close re-runs this.
    if mod._raidPvActive then return end

    -- Defensive: re-assert full opacity unless a preview is intentionally
    -- dimming the real frames. The preview system is the only thing that lowers
    -- container alpha; this runs out of combat only (the function bails in combat
    -- above) and heals any case where alpha was left at 0 with the flags cleared.
    -- Gated on the party-preview flag too so a raid-visibility recompute never
    -- un-hides the raid container behind an active party preview.
    if not mod._sizePreviewTier and not mod._partyPvActive then containerFrame:SetAlpha(1) end

    local cfg = saved.profile
    -- Arena and Small Raid mode hide the raid frames. The player is in a raid
    -- group there, but we show our party frames instead (see
    -- _UpdatePartyVisibility), so the raid container must stay hidden even
    -- though IsInRaid() returns true.
    local visible = mod._RFVisWanted()
    local wasVisible = framesVisible
    SetFramesVisible(visible)
    mod._raidFramesVisible = visible -- mirror for readers outside this file (the FrameSort provider)
    -- Raid frames coming or going is the one change a tracker cannot learn from
    -- its own roster events (mirrors the party call in _UpdatePartyVisibility).
    if mod._NotifyTrackerProviders then mod._NotifyTrackerProviders() end

    -- Update showSolo attribute on all headers, but ONLY when it actually
    -- differs from the header's current value. Re-setting a SecureGroupHeader
    -- attribute re-triggers Blizzard's full child re-process (re-sort/re-assign)
    -- even when unchanged, so doing it every combat exit / visibility recompute
    -- was a large needless secure-header spike. showWhenSolo is a static setting;
    -- mirrors the needsHideShow guard in ApplySortToHeaders.
    local wantSolo = cfg.showWhenSolo or false
    for _, heading in ipairs(separatedHdrs) do
        if heading and heading:GetAttribute("showSolo") ~= wantSolo then
            heading:SetAttribute("showSolo", wantSolo)
        end
    end
    if mod._flatHeader and mod._flatHeader:GetAttribute("showSolo") ~= wantSolo then
        mod._flatHeader:SetAttribute("showSolo", wantSolo)
    end

    -- The driver decides the same way; synced first so the two agree this frame
    -- (readers such as the tier offset check IsShown right after).
    mod._RFSyncVisDrivers()
    containerFrame:SetShown(visible)
    if visible then
        -- Suppress Blizzard party frames when we're showing for groups
        if (IsInGroup() and not IsInRaid()) and mod._SuppressBlizzParty then mod._SuppressBlizzParty() end
        -- Headers last laid out hidden (native order) take the shown layout
        -- before the rebuild reads their buttons.
        if mod._rfRaidLaidVis ~= true then LayoutGroups() end
        -- Skip heavy refresh at combat end if roster didn't change. Per-unit events
        -- (UNIT_HEALTH, UNIT_AURA, etc.) kept buttons in sync during combat, so a full
        -- rebuild is only needed when the roster changed or we transition from hidden
        -- to visible. Heavy content rebuild ONLY when it could actually be stale: a
        -- real hidden->visible transition (unitToButton was wiped on hide) or a caller
        -- that flagged a roster/size change. Re-checking visibility while already shown
        -- and unchanged skips the 40-button rebuild -- the live per-unit events kept
        -- every button current the whole time. This generalizes the old combat-exit
        -- "lightweight" skip to every caller (preview restore,
        -- EnsureRealFramesRestored, etc.) so a redundant visibility recompute can never
        -- trigger a full refresh spike.
        local forceRebuild = mod._visForceRebuild
        mod._visForceRebuild = nil
        if (not wasVisible) or forceRebuild then
            RebuildUnitMap()
            if mod.UpdatePowerEventRegistration then mod.UpdatePowerEventRegistration() end
            UpdateAllButtons()
        end
        if IsInGroup() or IsInRaid() then
            StartRangeTicker()
            StartGhostTicker()
        end
    else
        StopRangeTicker()
        StopGhostTicker()
        if wasVisible then mod._RFForgetOccupants(allButtons) end
        wipe(unitToButton)
        -- A hidden set runs native order and keeps every group header up, so the
        -- driver can show it mid-fight with every member in place.
        if mod._rfRaidLaidVis ~= false then
            LayoutGroups()
            -- The dormant container's footprint (see _ApplyTierOffset).
            if mod._ApplyTierOffset then mod._ApplyTierOffset() end
        end
    end
end
mod.UpdateVisibility = UpdateVisibility

Inner.RangeUpdate, Inner.StartGhostTicker = RangeUpdate, StartGhostTicker
Inner.StartRangeTicker, Inner.StopGhostTicker = StartRangeTicker, StopGhostTicker
Inner.StopRangeTicker, Inner.UpdateVisibility = StopRangeTicker, UpdateVisibility
Inner.broken = false
