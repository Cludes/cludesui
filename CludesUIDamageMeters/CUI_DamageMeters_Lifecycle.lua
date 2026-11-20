if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_DamageMeters_Lifecycle.lua
--
--  The shared refresh ticker, the combat and PvP events, the key binding
--  buttons and the login build of the windows.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._dmInternals
-- CludesUIDamageMeters.lua or an earlier CUI_DamageMeters_*.lua file
-- failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local CUI = CludesUI

local DB, EnsureDB, MAX_WINDOWS = Inner.DB, Inner.EnsureDB, Inner.MAX_WINDOWS
local REFRESH_RATE_FLOOR = Inner.REFRESH_RATE_FLOOR
local REFRESH_RATE_HARD_FLOOR, TICK_COMBAT = Inner.REFRESH_RATE_HARD_FLOOR, Inner.TICK_COMBAT
local _deathStamps, _feignDeathGUIDs = Inner._deathStamps, Inner._feignDeathGUIDs
local _targetsCache, _windows, FreezeCombat = Inner._targetsCache, Inner._windows, Inner.FreezeCombat
local IsGroupInCombat, _srcKeyGuid = Inner.IsGroupInCombat, Inner._srcKeyGuid
local AppendDMSharedMedia, SnapshotSourceKeys = Inner.AppendDMSharedMedia, Inner.SnapshotSourceKeys
local _hoverPollFrame, EnsureTooltipFrame = Inner._hoverPollFrame, Inner.EnsureTooltipFrame
local CreateDMWindow, CreateSATimer = Inner.CreateDMWindow, Inner.CreateSATimer
local SetupSATimer, UpdateSATimerText = Inner.SetupSATimer, Inner.UpdateSATimerText
local SetInCombat, SetNeedsFinalRefresh = Inner.SetInCombat, Inner.SetNeedsFinalRefresh
local SetSharedTicker, SetCombatEndTime = Inner.SetSharedTicker, Inner.SetCombatEndTime
local SetCurViewFrozenDur, SetInEncounter = Inner.SetCurViewFrozenDur, Inner.SetInEncounter
local SetPlayerGUID, SetTTLastScale = Inner.SetPlayerGUID, Inner.SetTTLastScale
local SetActiveRow, SetStartSharedTicker = Inner.SetActiveRow, Inner.SetStartSharedTicker
local SetStopSharedTicker = Inner.SetStopSharedTicker

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._dmInternals, which hands the value to every copy.
local _inCombat = Inner._inCombat
Inner.inCombatSetters[#Inner.inCombatSetters + 1] = function(val)
    _inCombat = val
end
local _combatEndTime = Inner._combatEndTime
Inner.combatEndTimeSetters[#Inner.combatEndTimeSetters + 1] = function(val)
    _combatEndTime = val
end
local _needsFinalRefresh = Inner._needsFinalRefresh
Inner.needsFinalRefreshSetters[#Inner.needsFinalRefreshSetters + 1] = function(val)
    _needsFinalRefresh = val
end
local _sharedTicker
Inner.sharedTickerSetters[#Inner.sharedTickerSetters + 1] = function(val)
    _sharedTicker = val
end
local _ttFrame
Inner.ttFrameSetters[#Inner.ttFrameSetters + 1] = function(val)
    _ttFrame = val
end
local _saTimer
Inner.saTimerSetters[#Inner.saTimerSetters + 1] = function(val)
    _saTimer = val
end

-- Bumped whenever a build of the windows starts or _CUDM_Apply() supersedes one. The
-- login build is staggered across frames, so a profile swap arriving while it is still
-- in flight would otherwise let the pending steps assign _windows[i] over the windows
-- the swap had just set up -- abandoning those frames while they stay parented and
-- visible. A staggered step checks this before doing any work and drops out if a newer
-- build has taken over.
local _buildGen = 0
local _combatGen = 0 -- monotonic segment token; stale deferred teardowns compare against it
-- Assigned below. The first two are handed to the earlier files
-- (SetStopSharedTicker, SetStartSharedTicker).
local StopSharedTicker
local StartSharedTicker
local ScheduleStopTicker

-- Shared refresh ticker (one ticker for ALL windows). _sharedTicker is one copy per
-- reading file (State, Format, this one), all fed by SetSharedTicker; State's lets the
-- session-update handler revive it after a teardown race. Start/StopSharedTicker assign it.

local _regenTimestamp = 0 -- GetTime() when player left combat
-- State's zone-in group poll drops a stale stamp through this (State loads first).
mod.DMClearRegenStamp = function()
    _regenTimestamp = 0
end

-- Dedicated combat-timer ticker: keeps header clocks (and the standalone timer) ticking once per displayed second regardless of refresh rate, only while the shared ticker runs (combat); the second
-- memo in UpdateTimerText makes redundant ticks free. Historical-session windows are skipped -- their duration is static and already painted by RefreshUI.
local _timerTicker
local _saDecimalTicker

local function TimerTick()
    for _, wid in ipairs(_windows) do
        if not wid.curSessionID and wid.UpdateTimerText then
            wid.UpdateTimerText()
        end
    end
    if _windows[1] and UpdateSATimerText then
        UpdateSATimerText()
    end
end

local function CancelTimerTicker()
    if _timerTicker then
        _timerTicker:Cancel()
        _timerTicker = nil
    end
    if _saDecimalTicker then
        _saDecimalTicker:Cancel()
        _saDecimalTicker = nil
    end
end

-- What the ticks feed: true while something is on screen (a visible window, or the enabled
-- standalone timer, whose clock lives on these tickers); "stamp" while only a hidden window
-- on the live Current Deaths view needs them (ns._DMHiddenDeathsPass, no clock); false
-- otherwise. A hidden window's refresh only marks it stale for its OnShow catch-up.
local function AnyTickViewer()
    if DB().standaloneTimer then
        return true
    end
    local stamp = false
    for _, wid in ipairs(_windows) do
        local frame = wid.frame
        -- A Threat window (WoW Forever) is painted by its own list's updates.
        if frame and wid.curDMType ~= "threat" then
            if frame:IsVisible() then
                return true
            end
            if
                wid.curDMType == Enum.DamageMeterType.Deaths
                and not wid.curSessionID
                and wid.curSession == Enum.DamageMeterSessionType.Current
            then
                stamp = "stamp"
            end
        end
    end
    return stamp
end

local function SharedRefreshTick()
    -- Player out of combat but group still fighting (player died mid-pull)
    if _needsFinalRefresh then
        local groupDone = not IsGroupInCombat()
        -- Failsafe: if player has been out of combat for 5s, force-freeze
        -- even if IsGroupInCombat still reports true (healer HoTs, API lag)
        if not groupDone and _regenTimestamp > 0 and (GetTime() - _regenTimestamp) > 5 then
            groupDone = true
        end
        if groupDone then
            -- Group combat ended: freeze timer (pin final duration), final refresh, stop
            FreezeCombat(_regenTimestamp > 0 and _regenTimestamp or GetTime())
            SetInCombat(false)
            SetNeedsFinalRefresh(false)
            _regenTimestamp = 0
            for _, wid in ipairs(_windows) do
                if wid.curDMType ~= "threat" then
                    wid.Refresh()
                end
            end
            if _sharedTicker then
                _sharedTicker:Cancel()
                SetSharedTicker(nil)
            end
            CancelTimerTicker()
            return
        end
        -- Group still fighting: fall through to normal refresh
    end
    if _combatEndTime > 0 or (not _inCombat and not _needsFinalRefresh) then
        -- Combat fully ended or state lost: stop ticking
        if _sharedTicker then
            _sharedTicker:Cancel()
            SetSharedTicker(nil)
        end
        CancelTimerTicker()
        return
    end
    -- (Threat windows, WoW Forever, are painted by their own list's updates.)
    for _, wid in ipairs(_windows) do
        if wid.curDMType ~= "threat" then
            wid.Refresh()
        end
    end
    -- Nothing on screen any more (each window above only marked itself stale): stop, and the
    -- next window to show restarts the ticks. The group-fight poll and a hidden live Deaths
    -- view keep their tick, no clock.
    local val = AnyTickViewer()
    if val ~= true then
        if _needsFinalRefresh or val then
            CancelTimerTicker()
        else
            StopSharedTicker()
        end
    end
end

-- Only active during combat to avoid idle CPU cost, and only while AnyTickViewer or the
-- group-fight poll (_needsFinalRefresh) needs a tick. Gated here rather than at the call
-- sites, so the session-event revivals cannot bring back a ticker with nothing to paint.
StartSharedTicker = function()
    if _sharedTicker then
        _sharedTicker:Cancel()
        SetSharedTicker(nil)
    end
    CancelTimerTicker()
    local viewers = AnyTickViewer()
    if not viewers and not _needsFinalRefresh then
        -- Data keeps moving with nothing refreshing it: mark every (hidden) window stale so
        -- its show catches up at once instead of a tick later.
        for _, wid in ipairs(_windows) do
            wid._refreshPending = true
        end
        return
    end
    local rate = DB().refreshRate or TICK_COMBAT
    -- Belt for values the login clamp has not seen yet (a profile imported
    -- mid-session from an old export can carry a sub-floor rate). Respects
    -- unsafeRefreshRate the same way the login clamp does; the hard floor
    -- applies either way so 0 or negative can never reach the ticker.
    local floor = DB().unsafeRefreshRate and REFRESH_RATE_HARD_FLOOR or REFRESH_RATE_FLOOR
    if rate < floor then
        rate = floor
    end
    SetSharedTicker(C_Timer.NewTicker(rate, SharedRefreshTick))
    -- The poll or a hidden live Deaths view alone (nothing on screen) needs no clock
    if viewers ~= true then
        return
    end
    _timerTicker = C_Timer.NewTicker(0.5, TimerTick)
    -- Tenths display needs a faster brush than the 0.5s timer tick; combat-only, opt-in only, standalone timer only
    local conf = DB()
    if conf.standaloneTimer and conf.standaloneTimerDecimal then
        _saDecimalTicker = C_Timer.NewTicker(0.1, UpdateSATimerText)
    end
end
SetStartSharedTicker(StartSharedTicker)

StopSharedTicker = function()
    if _sharedTicker then
        _sharedTicker:Cancel()
        SetSharedTicker(nil)
    end
    CancelTimerTicker()
end
SetStopSharedTicker(StopSharedTicker)

-- Something came on screen (a window's OnShow, after its catch-up; a build or profile
-- swap, whose windows show without an OnShow edge): start the ticks, or add the clock
-- to a clockless ticker. The clock runs whenever anything is on screen, so its absence
-- is the signal. On ns: CreateDMWindow sits at the 60-upvalue cap.
mod._DMReviveTicks = function()
    if (_inCombat or _needsFinalRefresh) and not _timerTicker then
        StartSharedTicker()
    end
end

-- Stop the ticker after `delay`, no-op if a newer combat segment started (generation mismatch)
-- or combat is still live. Guards against cancelling the NEXT segment's ticker when a boss is pulled within the stop delay of the previous pack ending.
ScheduleStopTicker = function(delay)
    local gen = _combatGen
    C_Timer.After(delay, function()
        if gen ~= _combatGen then
            return
        end
        if _inCombat or _needsFinalRefresh then
            return
        end
        StopSharedTicker()
    end)
end

-- Combat state tracking (shared, group-aware)
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
combatFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
combatFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
combatFrame:RegisterEvent("UNIT_FLAGS")
combatFrame:RegisterEvent("ENCOUNTER_START")
combatFrame:RegisterEvent("ENCOUNTER_END")
-- Detect Feign Death via UNIT_SPELLCAST_SUCCEEDED (Blizzard doesn't fire UNIT_AURA for FD, and
-- the combat log is unreliable for this). High-frequency event, so gate it with a tight integer compare.
combatFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
combatFrame:SetScript("OnEvent", function(_, evt, ...)
    -- UNIT_SPELLCAST_SUCCEEDED is the highest-frequency event here; check first with a tight integer compare so non-FD casts cost ~nothing
    if evt == "UNIT_SPELLCAST_SUCCEEDED" then
        local unitToken, _, spellId = ...
        if not unitToken then
            return
        end
        -- spellID can be a secret number when tainted by C_DamageMeter (comparing one throws "attempt to compare a secret value");
        -- without a usable spellID we can't classify the cast, so bail
        if issecretvalue and issecretvalue(spellId) then
            return
        end
        if spellId == 5384 then -- Feign Death
            local unitGuid = UnitGUID(unitToken)
            if unitGuid and not (issecretvalue and issecretvalue(unitGuid)) then
                _feignDeathGUIDs[unitGuid] = true
            end
        end
        -- Do not clear on non-FD casts: a live hunter can still have a feign entry with a valid
        -- deathRecapID; CleanupFeignCache clears it once they are truly dead.
        return
    end
    if evt == "GROUP_ROSTER_UPDATE" or evt == "PLAYER_SPECIALIZATION_CHANGED" then
        -- The TWO stale-key edges own the additive snapshot map's wipe:
        -- membership changes (guids leave) and spec changes (a respec strands
        -- the old CLASS:specIcon key; field dump showed a lone live mage
        -- blocked by its former twin's echo, and a respec's old key can
        -- ambiguous-block the new one). Never mid-combat, where the rebuild
        -- would read secrets and trade good captures for nothing; the lift
        -- edge re-runs the harvest anyway.
        if not InCombatLockdown() then
            wipe(_srcKeyGuid)
            SnapshotSourceKeys()
        end
        return
    end
    if evt == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- Doc-sequenced to fire AFTER a restriction deactivates: the Combat
        -- restriction lifting is the exact declassified edge -- the moment
        -- every source field reads plain again. Snapshot right here (the
        -- function self-gates against the activation-side firing).
        local rType = ...
        if
            Enum.AddOnRestrictionType
            and rType == Enum.AddOnRestrictionType.Combat
            and not InCombatLockdown()
        then
            SnapshotSourceKeys()
        end
        return
    end
    if evt == "UNIT_FLAGS" then
        -- Moved profiling inside the gate so filtered-out calls are truly zero-cost
        -- Quick bail: only care when in an instance, out of combat, and ticker not running
        if _inCombat or _sharedTicker or not IsInInstance() then
            return
        end
        local unitToken = ...
        if not unitToken or not (unitToken:match("^raid") or unitToken:match("^party")) then
            return
        end
        -- Group member entered combat before us: start polling so bars populate
        if IsGroupInCombat() then
            SetCombatEndTime(0)
            SetCurViewFrozenDur(0)
            -- A stale stamp of the last fight would trip the 5s failsafe on the first tick
            _regenTimestamp = 0
            -- Pre-warm: a teammate pulled before us. Mark a final-refresh poll (NOT _inCombat --
            -- the player may never personally enter combat, so nothing would ever clear _inCombat if we set it). SharedRefreshTick refreshes while the group fights and self-terminates when it leaves combat.
            SetNeedsFinalRefresh(true)
            _combatGen = _combatGen + 1
            StartSharedTicker()
        end
        return
    end
    if evt == "ENCOUNTER_START" then
        SetInEncounter(true)
        -- A boss pull is a hard segment boundary even in chain-pull combat, where PLAYER_REGEN_DISABLED
        -- never fires: bump the segment token (pending deferred stops no-op), assert combat, reset
        -- the timer pin. No clock anchored here -- the timer derives from the live "Current" session so it self-resets on the roll; a synchronous read here would race it and show the stale pre-pull duration.
        _combatGen = _combatGen + 1
        if next(_feignDeathGUIDs) then
            wipe(_feignDeathGUIDs)
        end -- new segment: stale feign tags would mis-filter real deaths
        if next(_deathStamps) then
            wipe(_deathStamps)
        end
        SetInCombat(true)
        SetCombatEndTime(0)
        SetCurViewFrozenDur(0)
        _regenTimestamp = 0
        SetNeedsFinalRefresh(false)
        if not _sharedTicker then
            StartSharedTicker()
        end
        mod.AutoCurrentOnCombat()
        for _, wid in ipairs(_windows) do
            wid._barCacheKey = nil
            wid._cachedTargets = nil
            wid.Refresh()
        end
        return
    end
    if evt == "ENCOUNTER_END" then
        SetInEncounter(false)
        local success = select(5, ...) -- 1 = kill, 0 = wipe
        -- On a clean kill, end combat promptly (PLAYER_REGEN_ENABLED can lag ENCOUNTER_END by
        -- several seconds). If it was NOT a clean kill and the group is still fighting (wipe with
        -- survivors, adds left, AoE into the next pack), do NOT hard-freeze mid-combat -- keep the ticker live and freeze only once the group truly leaves combat.
        if _inCombat or _needsFinalRefresh then
            local gen = _combatGen
            -- Short delay: let Blizzard finalize the session data first
            C_Timer.After(0.5, function()
                if gen ~= _combatGen then
                    return
                end -- a new segment (chain pull) started
                if _combatEndTime > 0 then
                    return
                end -- already ended elsewhere
                if success ~= 1 and IsGroupInCombat() then
                    SetNeedsFinalRefresh(true)
                    if not _sharedTicker then
                        StartSharedTicker()
                    end
                    return
                end
                FreezeCombat()
                SetInCombat(false)
                SetNeedsFinalRefresh(false)
                for _, wid in ipairs(_windows) do
                    wid.Refresh()
                end
                ScheduleStopTicker(0.5)
            end)
        end
        return
    end
    if evt == "PLAYER_REGEN_DISABLED" then
        -- Ignore post-match cleanup combat after a PvP match ends
        if _G._CUIDM_PvpBlocked and _G._CUIDM_PvpBlocked() then
            return
        end
        _combatGen = _combatGen + 1
        if next(_feignDeathGUIDs) then
            wipe(_feignDeathGUIDs)
        end -- new segment: stale feign tags would mis-filter real deaths
        if next(_deathStamps) then
            wipe(_deathStamps)
        end
        SetInCombat(true)
        SetCombatEndTime(0)
        SetCurViewFrozenDur(0)
        _regenTimestamp = 0
        SetNeedsFinalRefresh(false)
        if _targetsCache then
            wipe(_targetsCache)
        end
        StartSharedTicker()
        mod.AutoCurrentOnCombat()
    else
        _regenTimestamp = GetTime()
        -- Feign Death + group still fighting: keep timer running
        if UnitIsFeignDeath and UnitIsFeignDeath("player") and IsGroupInCombat() then
            return
        end
        if _targetsCache then
            wipe(_targetsCache)
        end
        -- Check if group is still fighting (player died but boss alive)
        if IsGroupInCombat() then
            SetNeedsFinalRefresh(true) -- let tick poll until group leaves combat
            -- The poll needs its tick even when a fully hidden meter let the ticker lapse
            if not _sharedTicker then
                StartSharedTicker()
            end
            -- Don't freeze timer -- group is still in combat
        else
            -- Freeze timer: entire group out of combat. Guard against overwriting an earlier freeze (e.g. ENCOUNTER_END already froze at the boss end)
            if _combatEndTime == 0 then
                FreezeCombat()
            end
            SetInCombat(false)
            SetNeedsFinalRefresh(false)
            for _, wid in ipairs(_windows) do
                wid.Refresh()
            end
            -- One final tick then stop (guarded so it can't cancel a new segment).
            ScheduleStopTicker(DB().refreshRate or TICK_COMBAT)
        end
        -- Delayed refresh after exiting combat: API needs a moment to declassify secret source GUIDs so breakdowns work post-combat
        C_Timer.After(0.5, function()
            for _, wid in ipairs(_windows) do
                wid.Refresh()
            end
            -- Declassified = the ideal moment to refresh the breakdown
            -- resolver's class:spec -> guid snapshot for the NEXT pull.
            if mod._SnapshotSourceKeys and not InCombatLockdown() then
                mod._SnapshotSourceKeys()
            end
        end)
    end
end)

-- PvP match end detection: arenas/solo shuffle don't reliably fire PLAYER_REGEN_ENABLED when the
-- match ends (IsGroupInCombat() stays true between rounds), so track match state via C_PvP and force-end the segment when the match finishes.
do
    local _pvpMatchActive = false
    local _pvpBlockUntil = 0

    local pvpFrame = CreateFrame("Frame")
    pvpFrame:RegisterEvent("PVP_MATCH_COMPLETE")
    pvpFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
    pvpFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    pvpFrame:SetScript("OnEvent", function()
        if not C_PvP or not C_PvP.IsMatchActive then
            return
        end
        local isActive = C_PvP.IsMatchActive()
        if isActive and not _pvpMatchActive then
            _pvpMatchActive = true
        elseif not isActive and _pvpMatchActive then
            _pvpMatchActive = false
            C_Timer.After(1.5, function()
                if _pvpMatchActive then
                    return
                end
                if _combatEndTime > 0 then
                    return
                end
                FreezeCombat()
                SetInCombat(false)
                SetNeedsFinalRefresh(false)
                for _, wid in ipairs(_windows) do
                    wid.Refresh()
                end
                ScheduleStopTicker(0.5)
                -- Block new segments from post-match cleanup damage
                _pvpBlockUntil = GetTime() + 20
            end)
        end
    end)

    -- Expose the block check so combat start can respect it
    _G._CUIDM_PvpBlocked = function()
        return GetTime() < _pvpBlockUntil
    end
end

-- Reset Data keybind button (hidden, receives override binding click)
if not _G["CludesUIDMResetBindBtn"] then
    local button = CreateFrame("Button", "CludesUIDMResetBindBtn", UIParent)
    button:Hide()
    button:SetScript("OnClick", function()
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            C_DamageMeter.ResetAllCombatSessions()
            SetCombatEndTime(0)
            SetCurViewFrozenDur(0)
            for _, wid in ipairs(_windows) do
                wid.Refresh()
            end
        end
    end)
end

-- Show/hide all windows keybind button (hidden, receives override binding click)
if not _G["CludesUIDMToggleBindBtn"] then
    local button = CreateFrame("Button", "CludesUIDMToggleBindBtn", UIParent)
    button:Hide()
    button:SetScript("OnClick", function()
        if mod.ToggleDMWindows then
            mod.ToggleDMWindows()
        end
    end)
end

-- Init
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if CUI and CUI.ADDON_ROSTER then
        for _, details in ipairs(CUI.ADDON_ROSTER) do
            if details.folder == "CludesUIDamageMeters" and details.comingSoon then
                return
            end
        end
    end

    EnsureDB()
    -- DB is now available; rebuild number format so a saved forceEnglishUnits preference applies at login (load-time build ran before the DB existed)
    if mod.RebuildNumberFormat then
        mod.RebuildNumberFormat()
    end
    -- A profile already on Classic WoW UI gets its one-time seed here (the
    -- Style page seeds on the switch; flags make both idempotent).
    if mod.DMClassic() then
        mod.DMSeedClassic(DB())
    end
    -- Disable Blizzard's built-in damage meter UI; C_DamageMeter API still works
    CludesUI.SetCVar("damageMeterEnabled", 0, "CludesUIDamageMeters")
    AppendDMSharedMedia()

    SetPlayerGUID(UnitGUID("player"))

    -- Restore the reset data and show/hide all windows keybinds
    mod.ApplyDMKeybinds()

    -- Defer window creation off the login frame to avoid blocking
    local conf = DB()
    if not conf.windows then
        conf.windows = {}
    end
    -- windowCount is authoritative; trim stale array entries beyond it
    local winCount = math.max(1, conf.windowCount or 1)
    conf.windowCount = winCount
    for index = winCount + 1, MAX_WINDOWS do
        conf.windows[index] = nil
    end
    local winIdx = 0
    _buildGen = _buildGen + 1
    local myBuildGen = _buildGen
    local function CreateNextWindow()
        -- A rebuild has superseded this staggered build; carrying on would overwrite the
        -- windows it created and leave those frames orphaned but visible.
        if myBuildGen ~= _buildGen then
            return
        end
        winIdx = winIdx + 1
        if winIdx > winCount then
            -- All windows exist: register them with the core unlock mode system
            mod.RegisterDMUnlock()
            if conf.standaloneTimer then
                CreateSATimer()
            end
            mod._DMReviveTicks()
            -- Pre-create tooltip frame so first hover doesn't pay creation cost
            EnsureTooltipFrame()
            local sc = (conf.hoverTooltipScale or 100) / 100
            if _ttFrame then
                _ttFrame:SetScale(sc)
                SetTTLastScale(sc)
            end
            return
        end
        _windows[winIdx] = CreateDMWindow(winIdx)
        mod.ApplyWindowBorder()
        C_Timer.After(0, CreateNextWindow)
    end
    C_Timer.After(0, CreateNextWindow)

    -- Profile swap: the windows are kept and re-read the new profile (W.Reapply); windows
    -- past its window count are parked (W.Park) and come back when a later profile, or
    -- New Window, needs them again.
    _G._CUDM_Apply = function()
        -- Supersede any staggered build still in flight, so its remaining steps do not
        -- assign over the windows set up below
        _buildGen = _buildGen + 1
        -- Hide tooltip
        if _ttFrame then
            _ttFrame:Hide()
        end
        SetActiveRow(nil)
        _hoverPollFrame:Hide()
        local cfg = DB()
        -- Clear the hotkey toggle so a profile swap never lands in a hidden state whose
        -- cause is no longer visible, then re-apply both keybinds from the new profile
        mod._toggleHidden = false
        mod.ApplyDMKeybinds()
        -- Force English Units from the new profile
        mod.RebuildNumberFormat()
        if not cfg.windows then
            cfg.windows = {}
        end
        local wc = math.max(1, cfg.windowCount or 1)
        cfg.windowCount = wc
        for index = wc + 1, MAX_WINDOWS do
            cfg.windows[index] = nil
        end
        -- Windows past the new count are parked, the last first (they come back in order)
        for index = #_windows, wc + 1, -1 do
            local wid = _windows[index]
            _windows[index] = nil
            wid.Park()
        end
        -- Kept windows re-read the new profile; a slot with none brings back a parked
        -- window or builds one
        for index = 1, wc do
            local wid = _windows[index]
            if wid then
                wid.Reapply(index)
            else
                _windows[index] = mod.DMAcquireWindow(index)
            end
        end
        mod.ApplyWindowBorder()
        -- A window that left the Threat type may leave its list with no window (WoW Forever)
        if mod.DMThreatSync then
            mod.DMThreatSync()
        end
        -- Spell History caches its profile table; refresh it before rebuilding
        -- optional unlock registrations so enable state and positions agree.
        if mod.RefreshSpellHistoryProfile then
            mod.RefreshSpellHistoryProfile()
        end
        -- Refresh unlock registrations for the new profile's window count
        mod.RegisterDMUnlock()
        -- The standalone timer is kept: set up again as built, or hidden while disabled
        if _saTimer then
            if cfg.standaloneTimer then
                SetupSATimer()
            else
                _saTimer:Hide()
            end
        elseif cfg.standaloneTimer then
            CreateSATimer()
        end
        -- Pre-create tooltip frame so first hover doesn't pay creation cost. This and the
        -- ticker below are the staggered build's closing steps, repeated here because
        -- this pass may have superseded that build before it reached them.
        EnsureTooltipFrame()
        -- Update tooltip scale
        if _ttFrame then
            local sc = (cfg.hoverTooltipScale or 100) / 100
            _ttFrame:SetScale(sc)
        end
        mod._DMReviveTicks()
    end
end)

-- The start values the copies were built from: nothing may read them again.
Inner._combatEndTime, Inner._inCombat, Inner._needsFinalRefresh = nil, nil, nil
Inner.broken = false
