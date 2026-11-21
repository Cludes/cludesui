if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_DamageMeters_State.lua
--
--  Header button layout, per-window settings and position, the shared
--  combat and segment state, unlock registration and the session events.
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

local DB, DM_TYPE_ICONS, DM_TYPE_NAMES = Inner.DB, Inner.DM_TYPE_ICONS, Inner.DM_TYPE_NAMES
local GetHeaderH, HOME_DEFAULTS, MAX_WINDOWS = Inner.GetHeaderH, Inner.HOME_DEFAULTS, Inner.MAX_WINDOWS
local MIN_H, MIN_W, SetCombatEndTime = Inner.MIN_H, Inner.MIN_W, Inner.SetCombatEndTime
local SetCurViewFrozenDur, SetInEncounter = Inner.SetCurViewFrozenDur, Inner.SetInEncounter
local SetInCombat, SetNeedsFinalRefresh = Inner.SetInCombat, Inner.SetNeedsFinalRefresh

-- Header icon visibility (hide until title bar hovered)
local function ResetButtonHidden(conf)
    conf = conf or DB()
    return conf.hideResetButton == true
end

local function GetHeaderLayoutButtons(Win, conf)
    local buttons = {}
    if not Win or not Win.hdrBtns then
        return buttons
    end
    local hideReset = ResetButtonHidden(conf)
    for _, button in ipairs(Win.hdrBtns) do
        if button ~= Win.resetBtn or not hideReset then
            buttons[#buttons + 1] = button
        end
    end
    return buttons
end
-- The same count without building the list (the title fit runs on every paint).
function mod.DMHeaderButtonCount(Win, conf)
    if not Win or not Win.hdrBtns then
        return 0
    end
    local hideReset = ResetButtonHidden(conf)
    local num = 0
    for _, button in ipairs(Win.hdrBtns) do
        if button ~= Win.resetBtn or not hideReset then
            num = num + 1
        end
    end
    return num
end

local function LayoutHeaderButtons(Win, conf, iconSz)
    if not Win or not Win.header or not Win.hdrBtns then
        return
    end
    local btnPad = mod.DMHdrIconPad()
    local lift = mod.DMHdrLift(conf and conf.hdrHeight)
    local layoutBtns = GetHeaderLayoutButtons(Win, conf)
    for bi, button in ipairs(layoutBtns) do
        if iconSz then
            button:SetSize(iconSz, iconSz)
            -- Inset stock art follows the new size.
            if button._hdrIcon and button._hdrIcon._hdrArt then
                mod.DMSeatHdrArt(button._hdrIcon, iconSz)
            end
        end
        button:ClearAllPoints()
        button:SetPoint("RIGHT", Win.header, "RIGHT", -(iconSz * (bi - 1) + btnPad * bi + 2), lift)
    end
end

local function SetHeaderButtonsShown(Win, isShown)
    if not Win or not Win.hdrBtns then
        return
    end
    local hideReset = ResetButtonHidden()
    for _, button in ipairs(Win.hdrBtns) do
        if button == Win.resetBtn and hideReset then
            button:Hide()
            button:SetAlpha(0)
            button:EnableMouse(false)
        else
            button:Show()
            button:SetAlpha(isShown and 1 or 0)
            button:EnableMouse(isShown)
        end
    end
    -- Title reserves room for the icons and must re-fit whenever hide-until-hover shows/hides them
    Win._hdrIconsShown = isShown and true or false
    if Win.FitTitle then
        Win.FitTitle()
    end
end

local function EnsureHeaderButtonsHoverHooks(Win)
    if not Win or Win._hdrHideUntilHoverHooksInstalled then
        return
    end
    Win._hdrHideUntilHoverHooksInstalled = true

    local function Show()
        local conf = DB()
        if not conf.hdrMouseoverIcons then
            return
        end
        SetHeaderButtonsShown(Win, true)
    end

    local function MaybeHide()
        local conf = DB()
        if not conf.hdrMouseoverIcons then
            return
        end
        if not Win.header then
            return
        end
        C_Timer.After(0, function()
            if not Win.header then
                return
            end
            if Win.header:IsMouseOver() then
                return
            end
            SetHeaderButtonsShown(Win, false)
        end)
    end

    if Win.header then
        Win.header:HookScript("OnEnter", Show)
        Win.header:HookScript("OnLeave", MaybeHide)
    end
    if Win.hdrBtns then
        for _, button in ipairs(Win.hdrBtns) do
            button:HookScript("OnEnter", Show)
            button:HookScript("OnLeave", MaybeHide)
        end
    end
end

local function ApplyHeaderButtonsHoverVisibility(Win, conf)
    if not Win or not Win.header or not Win.hdrBtns then
        return
    end
    EnsureHeaderButtonsHoverHooks(Win)
    if conf and conf.hdrMouseoverIcons then
        SetHeaderButtonsShown(Win, Win.header:IsMouseOver())
    else
        SetHeaderButtonsShown(Win, true)
    end
end

-- Per-window DB accessor
local function WinDB(idx)
    local conf = DB()
    if not conf.windows then
        conf.windows = {}
    end
    if not conf.windows[idx] then
        conf.windows[idx] = {
            position = nil,
            width = 375,
            height = 150,
        }
    end
    return conf.windows[idx]
end

-- Applies a window's saved position. Two formats: unlock format { point, relPoint, x, y } (relative
-- to UIParent, from unlock mode's Save & Exit); legacy format { x = left, y = top } (TOPLEFT offset from UIParent's BOTTOMLEFT, from header drags outside unlock mode)
mod.ApplyWinPosition = function(widget, wdb, idx)
    -- The resize grip owns the frame's anchor while a drag is in flight. Even
    -- with the format converted above, re-anchoring mid-resize would fight the
    -- grip's live SetPoint for a frame; leave it alone until the drag ends.
    -- ns._windows, not the _windows local: that local is declared BELOW this
    -- function, so referencing it here would read a nil global and the guard
    -- would silently never fire.
    local Win = mod._windows and mod._windows[idx]
    if Win and Win.resizing then
        return
    end
    local place = wdb.position
    -- Unlock-anchored window (e.g. one meter window anchored to another): the
    -- anchor system owns the position ENTIRELY -- the standard Build* guard
    -- (see the ERB/CDM siblings), but stricter: never seed from the stored
    -- absolute either. A window anchored long ago carries an arbitrarily
    -- stale absolute (wherever it sat before being anchored), and re-applying
    -- it on every login/reload flashed the window at that spot for the first
    -- frames until the login anchor pass landed (field report). With no
    -- geometry yet the window simply stays UNPLACED (renders nothing) for
    -- those frames instead; a genuinely absent anchor target is what the
    -- fallback-anchor feature covers.
    if CUI.IsUnlockAnchored and CUI.IsUnlockAnchored("EDM_Win" .. idx) then
        return
    end
    widget:ClearAllPoints()
    if place and place.point then
        widget:SetPoint(place.point, UIParent, place.relPoint or place.point, place.x or 0, place.y or 0)
    elseif place and place.x and place.y then
        widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", place.x, place.y)
    else
        -- Default: 20px from bottom-right of screen, cascading per window
        local uiW = UIParent:GetWidth()
        local fw, fh = widget:GetSize()
        widget:SetPoint(
            "TOPLEFT",
            UIParent,
            "BOTTOMLEFT",
            uiW - fw - 20 + (idx - 1) * 20,
            fh + 20 - (idx - 1) * 20
        )
    end
end

-- Bookmarks are shared across all windows (stored in dm.bookmarks)
local function GetBookmarks()
    local conf = DB()
    if not conf.bookmarks then
        conf.bookmarks = {}
        for _, dt in ipairs(HOME_DEFAULTS) do
            conf.bookmarks[#conf.bookmarks + 1] = dt
        end
    end
    return conf.bookmarks
end

-- ipairs over the bookmarks this client offers, keeping each one's index in
-- the saved list: a type not offered here (WoW Forever's Threat in a profile
-- brought elsewhere) gets no card, and its bookmark stays saved.
local function NextHomeType(entries, i)
    i = i + 1
    local val = entries[i]
    while val ~= nil and not DM_TYPE_NAMES[val] do
        i = i + 1
        val = entries[i]
    end
    if val ~= nil then
        return i, val
    end
end
function mod.DMHomeTypes(entries)
    return NextHomeType, entries, 0
end

-- Shared state
local _inCombat = false
local _inEncounter = false -- true between ENCOUNTER_START and ENCOUNTER_END
Inner.inCombatSetters[#Inner.inCombatSetters + 1] = function(val)
    _inCombat = val
end
Inner.inEncounterSetters[#Inner.inEncounterSetters + 1] = function(val)
    _inEncounter = val
end
local _windows = {} -- array of active window tables
mod._windows = _windows
-- Windows taken out of use (a closed window, or one past a profile's window
-- count), kept whole with their frames: ns.DMAcquireWindow brings them back.
mod._dmParked = {}

-- Hotkey toggle state. Deliberately not persisted: a window hidden by accident would
-- otherwise stay gone after a reload with nothing on screen explaining why. Every place
-- that can show one of the toggled frames consults this flag, because the shared
-- visibility dispatcher, the standalone timer ticker and the spell history rebuild all
-- re-show their frames on their own schedule. Options mode and unlock mode still win.
mod._toggleHidden = false

mod._DM_TYPE_NAMES = DM_TYPE_NAMES
mod._DM_TYPE_ICONS = DM_TYPE_ICONS

-- Unlock mode registration: each window is a first-class unlock element (EDM_Win1..N) via the
-- core mover system (drag, exact X/Y, anchor-to-element, width/height matching). Index-based
-- keys; deletion re-keys anchor/match links via ShiftIndexedAnchorKeys (see W.Destroy). Called
-- on login, window add/remove, and profile swap; slots beyond the live count unregister.
mod.RegisterDMUnlock = function()
    if not CUI or not CUI.RegisterUnlockElements or not CUI.MakeUnlockElement then
        return
    end
    local MK = CUI.MakeUnlockElement
    local function winOf(key)
        local i = tonumber(string.match(key or "", "(%d+)$"))
        return i and _windows[i], i
    end
    local elements = {}
    for i = 1, #_windows do
        elements[#elements + 1] = MK({
            key = "EDM_Win" .. i,
            label = CUI.Lf("Damage Meter %1$d", i),
            group = "Damage Meters",
            order = 650 + i,
            getFrame = function(key)
                local wid = winOf(key)
                return wid and wid.frame
            end,
            getSize = function(key)
                local wid, idx = winOf(key)
                if wid and wid.frame then
                    return wid.frame:GetWidth(), wid.frame:GetHeight()
                end
                local wdb = idx and WinDB(idx)
                return wdb and wdb.width or 375, wdb and wdb.height or 150
            end,
            -- A textured window border's reach past the window's edges, so size
            -- matching lines up with what is on screen. Mirrors ns.ApplyWindowBorder:
            -- the border hugs an overlay target set out by the Width/Height
            -- Offsets, and its top starts below the header when the header is
            -- left out. Each side clamped at 0. nil under a stock look or solid.
            getMatchPad = function()
                if mod.DMBlizz() then
                    return nil
                end
                local conf = DB()
                local size = tonumber(conf.windowBorderSize) or 0
                local texture = conf.windowBorderTexture or "solid"
                if size <= 0 or texture == "solid" then
                    return nil
                end
                local color = conf.windowBorderColor
                local left, right, top, b = CUI.BorderReach(
                    size,
                    texture,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    CUI.BorderPx(conf.windowBorderSizePx, size, texture),
                    nil,
                    color and color.a or 1
                )
                if not left then
                    return nil
                end
                local ox = tonumber(conf.windowBorderOffsetX) or 0
                local oy = tonumber(conf.windowBorderOffsetY) or 0
                left, right, b = left + ox, right + ox, b + oy
                if conf.windowBorderIncludeHeader ~= false then
                    top = top + oy
                else
                    top = top + oy - GetHeaderH()
                end
                local pw = (left > 0 and left or 0) + (right > 0 and right or 0)
                local ph = (top > 0 and top or 0) + (b > 0 and b or 0)
                if pw <= 0 and ph <= 0 then
                    return nil
                end
                return pw, ph
            end,
            setWidth = function(key, newW)
                local wid, idx = winOf(key)
                if not wid or not wid.frame then
                    return
                end
                local PPu = CUI.PP
                local val = math.max(MIN_W, newW or MIN_W)
                val = PPu and PPu.Snap and PPu.Snap(val) or math.floor(val + 0.5)
                wid.frame:SetWidth(val)
                if CUI._unlockActive then
                    WinDB(idx).width = math.floor(val + 0.5)
                end
                if wid.FitTitle then
                    wid.FitTitle()
                end
            end,
            setHeight = function(key, newH)
                local wid, idx = winOf(key)
                if not wid or not wid.frame then
                    return
                end
                local PPu = CUI.PP
                local val = math.max(MIN_H, newH or MIN_H)
                val = PPu and PPu.Snap and PPu.Snap(val) or math.floor(val + 0.5)
                wid.frame:SetHeight(val)
                if CUI._unlockActive then
                    WinDB(idx).height = math.floor(val + 0.5)
                end
            end,
            savePos = function(key, anchorPoint, relPoint, posX, posY)
                local wid, idx = winOf(key)
                if not idx then
                    return
                end
                WinDB(idx).position =
                    { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
                if wid and wid.ApplyPosition and not CUI._unlockActive then
                    wid.ApplyPosition()
                end
            end,
            loadPos = function(key)
                local _, idx = winOf(key)
                local place = idx and WinDB(idx).position
                if not place then
                    return nil
                end
                -- Return a copy: callers may hold or rebase the table, and the
                -- live DB entry must never be mutated through it
                if place.point then
                    return { point = place.point, relPoint = place.relPoint, x = place.x, y = place.y }
                end
                if place.x and place.y then
                    -- Legacy drag format: TOPLEFT offset from UIParent's BOTTOMLEFT
                    return { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = place.x, y = place.y }
                end
                return nil
            end,
            clearPos = function(key)
                local _, idx = winOf(key)
                if idx then
                    WinDB(idx).position = nil
                end
            end,
            applyPos = function(key)
                local wid = winOf(key)
                if wid and wid.ApplyPosition then
                    wid.ApplyPosition()
                end
            end,
        })
    end
    -- Standalone combat timer rides the master toggle (factory defined in CUI_DamageMeters_Timer.lua, resolved via ns)
    if DB().standaloneTimer and mod.MakeSATimerUnlockElement then
        elements[#elements + 1] = mod.MakeSATimerUnlockElement(MK)
    end
    -- Icon History is owned by the spell-history file, but participates in the
    -- same first-class unlock system as the meter windows and combat timer.
    local spellHistory = DB().spellHistory
    if spellHistory and spellHistory.iconEnabled and mod.MakeIconHistoryUnlockElement then
        elements[#elements + 1] = mod.MakeIconHistoryUnlockElement(MK)
    end
    CUI:RegisterUnlockElements(elements, "CludesUIDamageMeters")
    -- Drop registrations for window slots beyond the live count and optional
    -- elements while disabled (symmetric across profile swaps).
    if CUI.UnregisterUnlockElement then
        for i = #_windows + 1, MAX_WINDOWS do
            CUI:UnregisterUnlockElement("EDM_Win" .. i)
        end
        if not DB().standaloneTimer then
            CUI:UnregisterUnlockElement("EDM_CombatTimer")
        end
        if not (spellHistory and spellHistory.iconEnabled) then
            CUI:UnregisterUnlockElement("EDM_IconHistory")
        end
    end
    -- Windows paint their border before they register (build, profile swap,
    -- new window), so ApplyWindowBorder's pad report found no element yet:
    -- record each window's pad now, or the first border edit after login
    -- would only be recorded, never re-pushed.
    if CUI.MatchPadChanged then
        for i = 1, #_windows do
            CUI.MatchPadChanged("EDM_Win" .. i)
        end
    end
end
local _combatEndTime = 0 -- GetTime() at combat end; control-flow sentinel (ticker teardown / freeze-once)
local _needsFinalRefresh = false
local _curViewFrozenDur = 0 -- final Current-session duration, pinned when combat ends
Inner.combatEndTimeSetters[#Inner.combatEndTimeSetters + 1] = function(val)
    _combatEndTime = val
end
Inner.needsFinalRefreshSetters[#Inner.needsFinalRefreshSetters + 1] = function(val)
    _needsFinalRefresh = val
end
Inner.curViewFrozenDurSetters[#Inner.curViewFrozenDurSetters + 1] = function(val)
    _curViewFrozenDur = val
end
-- Tracks feigned GUIDs since C_DamageMeter can give a feign a valid deathRecapID, which the
-- deathRecapID > 0 filter would treat as a real death. Cleared at combat/encounter start and on
-- 0 HP (confirmed real death); UnitIsFeignDeath can remain true through a feign-then-die transition so it can't be used to clear safely.
local _feignDeathGUIDs = {}

-- In-combat death time placeholders, keyed by deathRecapID (NeverSecret, unique
-- per death). deathTimeSeconds is SECRET while in combat, so a Deaths row read
-- 0:00 until combat ended; the row's first appearance is stamped with the plain
-- live session duration instead (accurate to one refresh interval) and the
-- engine's exact value replaces it as soon as it reads plain. Wiped at every
-- combat start with the feign cache.
local _deathStamps = {}

-- Switch a window to a segment (sessionID) or session type (Current/Overall); windows with
-- syncSegments switch together. On ns not local: CreateDMWindow is at Lua 5.1's 60-upvalue limit.
function mod.ApplySegmentSelection(Win, sessionType, sessionID)
    local targets = { Win }
    if WinDB(Win.idx).syncSegments then
        targets = {}
        for _, wid in ipairs(_windows) do
            if WinDB(wid.idx).syncSegments then
                targets[#targets + 1] = wid
            end
        end
    end
    for _, wid in ipairs(targets) do
        if sessionID then
            wid.curSessionID = sessionID
        else
            wid.curSession = sessionType
            WinDB(wid.idx).curSession = sessionType
            wid.curSessionID = nil
        end
        if wid.CloseSource then
            wid.CloseSource()
        end
        wid.Refresh()
    end
end

-- Combat start: switch windows viewing a past segment back to Current (per-window autoCurrentOnCombat option); Overall windows untouched.
function mod.AutoCurrentOnCombat()
    for _, wid in ipairs(_windows) do
        if wid.curSessionID and WinDB(wid.idx).autoCurrentOnCombat then
            wid.curSessionID = nil
            wid.curSession = Enum.DamageMeterSessionType.Current
            WinDB(wid.idx).curSession = Enum.DamageMeterSessionType.Current
            if wid.CloseSource then
                wid.CloseSource()
            end
            wid.Refresh()
        end
    end
end

-- Single source of truth for the "Current" session timer (window and standalone both read this).
-- Live, it reads the SAME session the bars render so a server-side roll (chain-pull boss) resets
-- it in lockstep with no separate clock to drift; once combat ends every caller is gated off and returns the value pinned at the freeze instant.
local function GetCurrentViewDuration()
    if _inCombat or _needsFinalRefresh then
        if C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
            local skinData = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current)
            if type(skinData) == "number" and not (issecretvalue and issecretvalue(skinData)) then
                _curViewFrozenDur = skinData -- keep the pin warm with the last live value
                return skinData
            end
        end
        return _curViewFrozenDur or 0
    end
    -- Not live: show the pinned final duration, falling back to the API if unpinned (fresh load/reload with retained session data)
    if _curViewFrozenDur and _curViewFrozenDur > 0 then
        return _curViewFrozenDur
    end
    if C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
        local skinData = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current)
        if type(skinData) == "number" and not (issecretvalue and issecretvalue(skinData)) then
            return skinData
        end
    end
    return 0
end

-- Stop the live timer AND pin its final value atomically at every combat-end freeze site. The d
-- >= pin guard keeps the last live value if Current already rolled to a fresh (smaller) session; the pin resets to 0 at every combat START so it can't carry across combats.
local function FreezeCombat(ts)
    SetCombatEndTime(ts or GetTime())
    if C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
        local skinData = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current)
        if
            type(skinData) == "number"
            and not (issecretvalue and issecretvalue(skinData))
            and skinData >= (_curViewFrozenDur or 0)
        then
            SetCurViewFrozenDur(skinData)
        end
    end
end

local _raidUnits, _partyUnits = {}, {}
for i = 1, 40 do
    _raidUnits[i] = "raid" .. i
end
for i = 1, 4 do
    _partyUnits[i] = "party" .. i
end

local function IsGroupInCombat()
    if UnitAffectingCombat("player") then
        return true
    end
    if IsInRaid() then
        local num = GetNumGroupMembers()
        for i = 1, num do
            if UnitAffectingCombat(_raidUnits[i]) then
                return true
            end
        end
    elseif IsInGroup() then
        local num = GetNumGroupMembers() - 1 -- party units exclude player
        for i = 1, num do
            if UnitAffectingCombat(_partyUnits[i]) then
                return true
            end
        end
    end
    return false
end

-- Clear cached feign GUIDs before filtering so real deaths after Feign Death are not hidden by stale entries
local function CleanupFeignCache()
    if not next(_feignDeathGUIDs) then
        return
    end
    -- Build GUID -> unit map for the group so iteration below runs O(N+M) instead of O(N*M)
    local present = {}
    local function note(unitToken)
        local g = UnitGUID(unitToken)
        if g and not (issecretvalue and issecretvalue(g)) then
            present[g] = unitToken
        end
    end
    note("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            note(_raidUnits[i])
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            note(_partyUnits[i])
        end
    end
    -- HP == 0 confirms a real death; Feign Death keeps actual HP, and UnitIsFeignDeath can linger after a feign-then-die transition
    for unitGuid in pairs(_feignDeathGUIDs) do
        local unitToken = present[unitGuid]
        if not unitToken then
            _feignDeathGUIDs[unitGuid] = nil -- player left the group: untrackable
        else
            local hp = UnitHealth(unitToken)
            if hp and not (issecretvalue and issecretvalue(hp)) and hp <= 0 then
                _feignDeathGUIDs[unitGuid] = nil
            end
        end
    end
end

local StopSharedTicker -- forward declaration (defined in CUI_DamageMeters_Lifecycle.lua)
local StartSharedTicker -- forward declaration (defined in CUI_DamageMeters_Lifecycle.lua)
local _sharedTicker -- the live refresh ticker (assigned in CUI_DamageMeters_Lifecycle.lua)
Inner.stopSharedTickerSetters[#Inner.stopSharedTickerSetters + 1] = function(val)
    StopSharedTicker = val
end
Inner.startSharedTickerSetters[#Inner.startSharedTickerSetters + 1] = function(val)
    StartSharedTicker = val
end
Inner.sharedTickerSetters[#Inner.sharedTickerSetters + 1] = function(val)
    _sharedTicker = val
end
local _targetsCache = {} -- Damage Done targets map (BuildAllPlayerTargets): { key = sessionKey, map = { [playerName] = sorted targets } }

-- Keystone start: wipe data so Overall = this dungeon run
-- Keystone end: auto-swap windows from Current to Overall (if enabled)
local instanceFrame = CreateFrame("Frame")
instanceFrame:RegisterEvent("CHALLENGE_MODE_START")
instanceFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
instanceFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
instanceFrame:RegisterEvent("DAMAGE_METER_RESET")
instanceFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
instanceFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
instanceFrame:SetScript("OnEvent", function(_, evt)
    if evt == "CHALLENGE_MODE_START" then
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            C_DamageMeter.ResetAllCombatSessions()
        end
        SetCombatEndTime(0)
        SetCurViewFrozenDur(0)
        -- Auto-swap: Overall -> Current on key start
        for _, wid in ipairs(_windows) do
            local wdb2 = WinDB(wid.idx)
            if wdb2.autoSwapMythic and wid.curSession == Enum.DamageMeterSessionType.Overall then
                wid.curSession = Enum.DamageMeterSessionType.Current
                wdb2.curSession = Enum.DamageMeterSessionType.Current
                wid.curSessionID = nil
            end
            -- Default on M+ Start: switch this window to its configured meter type
            if wdb2.mythicStartDMType and wid.SetDMType then
                wid.SetDMType(wdb2.mythicStartDMType)
            end
            wid.Refresh()
        end
    elseif evt == "CHALLENGE_MODE_COMPLETED" then
        -- Auto-swap: Current -> Overall on key completion
        for _, wid in ipairs(_windows) do
            local wdb2 = WinDB(wid.idx)
            if
                wdb2.autoSwapMythic
                and not wid.curSessionID
                and wid.curSession == Enum.DamageMeterSessionType.Current
            then
                wid.curSession = Enum.DamageMeterSessionType.Overall
                wdb2.curSession = Enum.DamageMeterSessionType.Overall
                wid.curSessionID = nil
                wid.Refresh()
            end
        end
    elseif evt == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        -- Blizzard created/updated a combat session (boss kill, combat end); "Current" may now point
        -- elsewhere. Invalidate cache for the next ticker refresh; force an immediate refresh only out of combat (the shared ticker covers combat at refreshRate).
        -- Readable session data changed: refresh the breakdown resolver's
        -- class:spec -> guid snapshot (ns route: this closure predates the
        -- resolver's definition).
        if mod._SnapshotSourceKeys and not InCombatLockdown() then
            mod._SnapshotSourceKeys()
        end
        if not instanceFrame._sessionPending then
            instanceFrame._sessionPending = true
            C_Timer.After(0.1, function()
                instanceFrame._sessionPending = nil
                for _, wid in ipairs(_windows) do
                    -- Data-only: session updates change DATA never STYLE. _barCacheKey gates the
                    -- per-bar restyle; nilling it here made every death restyle all bars at ticker rate (the dominant profiled cost). Style invalidation belongs to the settings/palette appliers only.
                    wid._cachedTargets = nil
                end
                if not _inCombat then
                    for _, wid in ipairs(_windows) do
                        wid.Refresh()
                    end
                elseif not _sharedTicker then
                    -- Ticker died from a teardown race; a new server session is our cue to revive it
                    StartSharedTicker()
                end
            end)
        end
    elseif evt == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
        -- Authoritative "Current just rolled" signal (boss-pull reset trigger, catches rolls the
        -- ticker-only model could miss between polls). Can fire continuously during combat, so a
        -- debounced repaint per burst (each paying a session-fetch C call, multiplied across windows) would dwarf the ticker's rate; in combat we only invalidate
        -- caches (ENCOUNTER_START/REGEN_DISABLED already force immediate repaints at segment
        -- boundaries, ticker covers the rest). Out of combat, one debounced repaint keeps rolls prompt.
        for _, wid in ipairs(_windows) do
            -- Data caches only -- style never changes on a session roll (see SESSION_UPDATED note above)
            wid._cachedTargets = nil
        end
        if _inCombat or _needsFinalRefresh then
            if not _sharedTicker then
                StartSharedTicker()
            end
        elseif not instanceFrame._curSessionPending then
            instanceFrame._curSessionPending = true
            C_Timer.After(0.1, function()
                instanceFrame._curSessionPending = nil
                for _, wid in ipairs(_windows) do
                    wid.Refresh()
                end
            end)
        end
    elseif evt == "DAMAGE_METER_RESET" then
        -- Blizzard cleared all session data (auto-reset CVar, manual reset, etc.)
        SetCombatEndTime(0)
        SetCurViewFrozenDur(0)
        if _targetsCache then
            wipe(_targetsCache)
        end
        for _, wid in ipairs(_windows) do
            wid._barCacheKey = nil
            wid._cachedTargets = nil
            wid.Refresh()
        end
    elseif evt == "PLAYER_ENTERING_WORLD" then
        -- Zone transition (load screen); WoW does not re-fire PLAYER_REGEN_DISABLED here, so
        -- combat state must be re-derived per branch below or the session-derived timer would blank.
        if UnitAffectingCombat("player") then
            -- Still personally in combat after the load (e.g. reload on a target dummy, or zoning into an active fight): restore the live timer.
            SetInCombat(true)
            SetCombatEndTime(0)
            SetNeedsFinalRefresh(false)
            if not _sharedTicker then
                StartSharedTicker()
            end
        elseif IsGroupInCombat() then
            -- Not personally in combat but the group is (reload while dead/spectating): poll like the
            -- teammate pre-warm rather than asserting _inCombat -- SharedRefreshTick self-terminates the instant the group leaves combat, so a stale flag can't tick forever.
            SetInCombat(false)
            SetCombatEndTime(0)
            -- A stale stamp of the last fight would trip the 5s failsafe on the first tick.
            if mod.DMClearRegenStamp then
                mod.DMClearRegenStamp()
            end
            SetNeedsFinalRefresh(true)
            if not _sharedTicker then
                StartSharedTicker()
            end
        else
            -- Out of combat: force-end. Covers hearth/teleport, leaving a BG/arena, abandoning an M+ key, any other zone-out.
            local wasLive = _inCombat or _needsFinalRefresh or _inEncounter
            SetInEncounter(false)
            SetInCombat(false)
            SetNeedsFinalRefresh(false)
            StopSharedTicker()
            -- Freeze (pin) the timer if combat was still live
            if wasLive and _combatEndTime == 0 then
                FreezeCombat()
            end
        end
        -- Refresh after zone-in to pick up visibility/data changes (window 1's
        -- refresh also applies the standalone timer's visibility)
        for _, wid in ipairs(_windows) do
            wid._barCacheKey = nil
        end
        C_Timer.After(0.5, function()
            for _, wid in ipairs(_windows) do
                wid.Refresh()
            end
        end)
    end
end)

Inner._combatEndTime, Inner._deathStamps = _combatEndTime, _deathStamps
Inner._feignDeathGUIDs, Inner._inCombat = _feignDeathGUIDs, _inCombat
Inner._needsFinalRefresh, Inner._targetsCache, Inner._windows = _needsFinalRefresh, _targetsCache, _windows
Inner.ApplyHeaderButtonsHoverVisibility = ApplyHeaderButtonsHoverVisibility
Inner.CleanupFeignCache, Inner.FreezeCombat = CleanupFeignCache, FreezeCombat
Inner.GetBookmarks, Inner.GetCurrentViewDuration = GetBookmarks, GetCurrentViewDuration
Inner.IsGroupInCombat, Inner.LayoutHeaderButtons, Inner.WinDB = IsGroupInCombat, LayoutHeaderButtons, WinDB
Inner.broken = false
