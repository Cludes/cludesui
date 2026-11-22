if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_CDM_FocusKick.lua
--
--  The Focus Kick bar and the focus reminders.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- The main file or an earlier CDM file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local GetTime = GetTime

local ECME, _ecmeFC, barDataByKey = Inner.ECME, Inner._ecmeFC, Inner.barDataByKey
local cdmBarFrames, cdmBarIcons = Inner.cdmBarFrames, Inner.cdmBarIcons

-- FocusKick bar: a special CD bar pinned to the focus target's nameplate.
-- Internally it is just another custom cooldowns bar so every existing code
-- path treats it identically. Three behavior overrides handled elsewhere:
--   1. Visibility forced to "always" in _CDMApplyVisibility
--   2. Skipped in RegisterCDMUnlockElements
--   3. Position driven by ApplyFocusKickAnchor (nameplate hook)
local FOCUSKICK_BAR_KEY = "focuskick"
mod.FOCUSKICK_BAR_KEY = FOCUSKICK_BAR_KEY
local function EnsureFocusKickBar()
    local profile = ECME.db and ECME.db.profile
    if not profile or not profile.cdmBars or not profile.cdmBars.bars then return end
    -- Desired position: directly after the "buffs" default bar and before any custom bars (skipping ghost bars).
    local barList = profile.cdmBars.bars
    local goalIdx
    for index, bar in ipairs(barList) do
        if bar.key == "buffs" then
            goalIdx = index + 1
            break
        end
    end
    if not goalIdx then goalIdx = #barList + 1 end
    local foundIdx
    for index, bar in ipairs(barList) do
        if bar.key == FOCUSKICK_BAR_KEY then
            foundIdx = index
            break
        end
    end
    if foundIdx then
        -- Backfill suppressGCD on existing FocusKick bars (default to on)
        if barList[foundIdx].suppressGCD == nil then barList[foundIdx].suppressGCD = true end
        if foundIdx == goalIdx or foundIdx == goalIdx - 1 then
            -- Already in the right spot relative to "buffs"
            return
        end
        local record = table.remove(barList, foundIdx)
        if foundIdx < goalIdx then goalIdx = goalIdx - 1 end
        table.insert(barList, goalIdx, record)
        return
    end
    table.insert(barList, goalIdx, {
        key = FOCUSKICK_BAR_KEY,
        name = "FocusKick",
        barType = "cooldowns",
        enabled = true,
        iconSize = 28,
        numRows = 1,
        spacing = 2,
        borderSize = 1,
        borderR = 0,
        borderG = 0,
        borderB = 0,
        borderA = 1,
        borderClassColor = false,
        borderTexture = "solid",
        borderThickness = "thin",
        bgR = 0.08,
        bgG = 0.08,
        bgB = 0.08,
        bgA = 0.6,
        iconZoom = 0.08,
        iconShape = "none",
        verticalOrientation = false,
        barBgEnabled = false,
        barBgR = 0,
        barBgG = 0,
        barBgB = 0,
        showCooldownText = true,
        cooldownTextPosition = "center",
        showItemCount = true,
        cooldownFontSize = 12,
        showCharges = true,
        chargeFontSize = 11,
        desaturateOnCD = true,
        swipeAlpha = 0.7,
        suppressGCD = true,
        activeStateAnim = "blizzard",
        anchorTo = "none",
        anchorPosition = "left",
        anchorOffsetX = 0,
        anchorOffsetY = 0,
        barVisibility = "always",
        showStackCount = false,
        stackCountSize = 11,
        stackCountPosition = "bottomright",
        outOfRangeOverlay = false,
        pandemicGlow = false,
        -- FocusKick-specific: nameplate side + offsets
        nameplateAnchorSide = "LEFT",
        nameplateOffsetX = 0,
        nameplateOffsetY = 0,
        -- FocusKick-specific: "FOCUS" reminder text on caster/miniboss plates
        focusReminderEnabled = false,
        focusReminderUseAccent = true,
        focusReminderR = 1,
        focusReminderG = 1,
        focusReminderB = 1,
        focusReminderSize = 26,
        focusReminderOffsetX = 0,
        focusReminderOffsetY = 0,
        -- FocusKick-specific: show on target instead of focus
        focusKickUseTarget = false,
        -- FocusKick-specific: focus-cast sound trigger
        focusCastSoundKey = "none",
        focusKickInterruptSpellID = nil,
        -- Sound-only mode: play on every tracked-unit cast, no interrupt or
        -- cooldown gate, so the bar can stay empty (no icon, kick stays on CDM).
        focusCastSoundAnyCast = false,
        growDirection = "RIGHT",
    })
    local spellData = mod.GetBarSpellData(FOCUSKICK_BAR_KEY)
    if spellData then spellData.assignedSpells = {} end
end
mod.EnsureFocusKickBar = EnsureFocusKickBar

-- Returns the unit token the FocusKick bar tracks: "target" when the user has enabled Show on Target, "focus" otherwise.
local function GetFocusKickUnit()
    local edge = barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
    return (edge and edge.focusKickUseTarget) and "target" or "focus"
end
mod.GetFocusKickUnit = GetFocusKickUnit

-- Set the bar frame and all of its icons to the given alpha. CDM icons are parented to the
-- Blizzard viewer pool, not the bar frame, so hiding the bar frame alone leaves the icons visible -- per-icon alpha is required.
local function FadeFocusKick(a)
    local widget = cdmBarFrames[FOCUSKICK_BAR_KEY]
    if widget then
        widget:SetAlpha(a)
        if widget.EnableMouseMotion and not InCombatLockdown() then
            -- Container never captures motion (steals hover from frames underneath); icon hover is owned by the tooltip setting.
            widget:EnableMouseMotion(false)
        end
        widget._visHidden = (a == 0)
    end
    local icons = cdmBarIcons and cdmBarIcons[FOCUSKICK_BAR_KEY]
    if icons then
        for index = 1, #icons do
            if icons[index] then icons[index]:SetAlpha(a) end
        end
    end
end

-- Find the scale-aware anchor frame inside a Blizzard nameplate. The CludesUINameplates
-- addon mixes a custom NameplateFrame into a child of the plate and applies "Scale Target
-- Nameplate"/"Scale Nameplate On Cast" via NameplateFrame:ApplyScale(); the Blizzard plate itself
-- does NOT scale, so anchoring to the plate ignores those settings. Walk the plate's children for the mixed-in frame's visible health bar (correct scaled bounds). Returns (healthFrame, scaledParent) or nil.
local function GetScaledPlateHealth(backing)
    if not backing then return nil end
    local children = { backing:GetChildren() }
    for index = 1, #children do
        local child = children[index]
        if child and child._mixedIn and child.health then return child.health, child end
    end
    return nil
end

-- Position the FocusKick bar against the tracked unit's nameplate. Called on focus/target change,
-- nameplate add/remove, and nameplate moves. The stored nameplateAnchorSide picks the plate side (LEFT/RIGHT/TOP/BOTTOM); stored offsets shift from that anchor point.
local function PlaceFocusKick()
    local widget = cdmBarFrames[FOCUSKICK_BAR_KEY]
    if not widget then return end
    local profile = ECME.db and ECME.db.profile
    local edge = profile and barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
    if not edge then return end
    local kickUnit = GetFocusKickUnit()
    local backing = C_NamePlate
        and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit(kickUnit)
    if not backing then
        FadeFocusKick(0)
        return
    end
    -- Prefer the scaled health bar from our custom NameplateFrame so the icon tracks Target/Cast
    -- scale changes. Fall back to the raw plate when the nameplates addon isn't loaded or the plate hasn't been decorated yet.
    local anchor = GetScaledPlateHealth(backing) or backing
    local edgeSide = edge.nameplateAnchorSide or "LEFT"
    local ox = edge.nameplateOffsetX or 0
    local oy = edge.nameplateOffsetY or 0
    widget:ClearAllPoints()
    if edgeSide == "LEFT" then
        widget:SetPoint("RIGHT", anchor, "LEFT", ox, oy)
    elseif edgeSide == "RIGHT" then
        widget:SetPoint("LEFT", anchor, "RIGHT", ox, oy)
    elseif edgeSide == "TOP" then
        widget:SetPoint("BOTTOM", anchor, "TOP", ox, oy)
    elseif edgeSide == "BOTTOM" then
        widget:SetPoint("TOP", anchor, "BOTTOM", ox, oy)
    else
        widget:SetPoint("CENTER", anchor, "CENTER", ox, oy)
    end
    FadeFocusKick(1)
end
mod.ApplyFocusKickAnchor = PlaceFocusKick

-- Single event proxy, created once and persistent; just calls ApplyFocusKickAnchor on relevant
-- events. Range-fade handling: when the tracked unit walks out of range, Blizzard fades the
-- nameplate alpha without firing NAME_PLATE_UNIT_REMOVED. The bar icons don't inherit plate
-- visibility (parented to the Blizzard viewer pool), so throttle-poll the plate's visibility and propagate alpha to the icons manually -- only while a tracked plate exists; zero work otherwise.
local _focusKickProxy
local _focusKickLastPlateVisible
local _FOCUSKICK_TICK_INTERVAL = 0.1

-- The re-anchor after a layout pass (LayoutCDMBar): only while the proxy is live (the
-- demand gate unregisters its events), and with the plate-visibility cache cleared as
-- every proxy event clears it, so the plate watch re-applies the fade alpha.
mod.ReapplyFocusKick = function()
    if not (_focusKickProxy and _focusKickProxy:IsEventRegistered("PLAYER_FOCUS_CHANGED")) then return end
    _focusKickLastPlateVisible = nil
    PlaceFocusKick()
end
local function EnsureFocusKickProxy()
    if _focusKickProxy then
        -- Re-apply/re-activate paths must restore the event set (a demand-gate teardown
        -- unregisters it; RegisterEvent is idempotent) and re-arm the watcher: a focus can already exist with no event forthcoming (settings apply, /reload with focus).
        _focusKickProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
        _focusKickProxy:RegisterEvent("PLAYER_TARGET_CHANGED")
        _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        if _focusKickProxy._arm then _focusKickProxy._arm() end
        return _focusKickProxy
    end
    _focusKickProxy = mod.TakeShell()
    _focusKickProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
    _focusKickProxy:RegisterEvent("PLAYER_TARGET_CHANGED")
    _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    _focusKickProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    _focusKickProxy:SetScript("OnEvent", function(self, evt, unitToken)
        local kickUnit = GetFocusKickUnit()
        if evt == "PLAYER_FOCUS_CHANGED" then
            if kickUnit ~= "focus" then return end
            _focusKickLastPlateVisible = nil
            PlaceFocusKick()
            if self._arm then self._arm() end
        elseif evt == "PLAYER_TARGET_CHANGED" then
            if kickUnit ~= "target" then return end
            _focusKickLastPlateVisible = nil
            PlaceFocusKick()
            if self._arm then self._arm() end
        elseif evt == "NAME_PLATE_UNIT_REMOVED" then
            -- Only react when the tracked unit's plate is removed. Reacting to every plate removal caused the bar to flicker off during AoE when unrelated mobs died or faded.
            if unitToken and (unitToken == kickUnit or UnitIsUnit(unitToken, kickUnit)) then
                _focusKickLastPlateVisible = nil
                PlaceFocusKick()
            end
        elseif evt == "NAME_PLATE_UNIT_ADDED" then
            if unitToken and (unitToken == kickUnit or UnitIsUnit(unitToken, kickUnit)) then
                _focusKickLastPlateVisible = nil
                PlaceFocusKick()
                if self._arm then self._arm() end
            end
        end
    end)
    -- Plate fade/occlusion has no event, so watching the tracked unit's plate visibility needs a
    -- poll -- but ONLY while a tracked unit exists, on a self-stopping anim ticker (the C engine
    -- sleeps between 0.1s fires) rather than a per-render-frame OnUpdate. The ticker stops itself the moment the unit is gone; the proxy's own events (focus/target changed, plate added) and EnsureFocusKickProxy re-arm it.
    local kickTicker
    local function FocusKickTick()
        local kickUnit = GetFocusKickUnit()
        if not UnitExists(kickUnit) then return false end
        local backing = C_NamePlate
            and C_NamePlate.GetNamePlateForUnit
            and C_NamePlate.GetNamePlateForUnit(kickUnit)
        local shownNow
        if backing then
            local alpha = backing:GetEffectiveAlpha() or 0
            shownNow = backing:IsVisible() and alpha > 0.01
        else
            shownNow = false
        end
        if shownNow ~= _focusKickLastPlateVisible then
            _focusKickLastPlateVisible = shownNow
            FadeFocusKick(shownNow and 1 or 0)
        end
        return true
    end
    _focusKickProxy._arm = function()
        if not kickTicker then
            kickTicker = CUI.Tick.NewAnimTicker(_focusKickProxy, FocusKickTick, _FOCUSKICK_TICK_INTERVAL)
        end
        kickTicker.Start()
    end
    _focusKickProxy._stop = function()
        if kickTicker then kickTicker.Stop() end
    end
    _focusKickProxy._arm()
    return _focusKickProxy
end
mod.EnsureFocusKickProxy = EnsureFocusKickProxy

-- Sound dropdown data: built-in CludesUI sounds + LibSharedMedia sounds appended at runtime via CludesUI.AppendSharedMediaSounds.
local FOCUSKICK_SOUND_PATHS, FOCUSKICK_SOUND_NAMES, FOCUSKICK_SOUND_ORDER = CUI.BuildAlertSoundTables()
mod.FOCUSKICK_SOUND_PATHS = FOCUSKICK_SOUND_PATHS
mod.FOCUSKICK_SOUND_NAMES = FOCUSKICK_SOUND_NAMES
mod.FOCUSKICK_SOUND_ORDER = FOCUSKICK_SOUND_ORDER

-- Focus-cast sound trigger. When the focus target starts a cast and the user's selected interrupt
-- is off cooldown, play the configured sound. One single proxy registered with RegisterUnitEvent on "focus" -- the token follows focus changes automatically.
local _focusCastProxy
local function RefreshFocusCastProxyUnit()
    if not _focusCastProxy then
        -- No proxy to re-point: the bar had no assigned spell at the last arming (RefreshFocusKickProxies
        -- only builds on its hasContent branch, and its ONLY callers are setup and the tail of
        -- BuildAllCDMBars). Adding a spell in the options writes assignedSpells without re-arming
        -- anything, which left the sound dead on a fully populated bar -- so run the full refresh here instead of returning, letting this path create the proxy.
        if mod.RefreshFocusKickProxies then mod.RefreshFocusKickProxies() end
        return
    end
    local unitToken = GetFocusKickUnit()
    _focusCastProxy:UnregisterAllEvents()
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_START", unitToken)
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unitToken)
end
mod.RefreshFocusCastProxyUnit = RefreshFocusCastProxyUnit

function mod.IsSpellInPlayerBook(ident, includeOverrides)
    if IsPlayerSpell and IsPlayerSpell(ident) then return true end
    if
        C_SpellBook
        and C_SpellBook.IsSpellKnownOrInSpellBook
        and C_SpellBook.IsSpellKnownOrInSpellBook(
            ident,
            Enum.SpellBookSpellBank.Player,
            includeOverrides ~= false
        )
    then
        return true
    end
    return false
end

-- Returns the id of the stored interrupt in the form this character can actually cast, or nil.
-- Validate on READ and never write: focusKickInterruptSpellID is profile-level while the spellbook
-- behind it is per-spec, so the id stays correct for the spec that set it -- clearing it here would
-- destroy that spec's setting the first time the player logged in on another one. Asks the
-- SPELLBOOK, never a class/spec table (a hardcoded list goes stale on a patch). Pet-bank interrupts
-- (a Warlock's Axe Toss, a Hunter's pet kick) are legitimate picks IsPlayerSpell cannot see, so
-- check both banks. Returning the resolved id (not a boolean) is the point: a talent swap moves an
-- interrupt between base and override forms while the stored id stays put; answering "known" but leaving the caller the un-castable form would feed the readiness gate an id that is never on cooldown.
function mod.ResolveCastableInterrupt(spellRef)
    if type(spellRef) ~= "number" or spellRef <= 0 then return nil end
    local knownInBook = mod.IsSpellInPlayerBook
    -- Resolve replacements first: Command Demon can remain known while its
    -- active pet command has the cooldown we need to check.
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        local ovr = C_SpellBook.FindSpellOverrideByID(spellRef)
        if ovr and ovr > 0 and ovr ~= spellRef and knownInBook(ovr) then return ovr end
    end
    if knownInBook(spellRef) then return spellRef end
    -- Talented back out, stored id is the replacement form.
    if C_Spell and C_Spell.GetBaseSpell then
        local base = C_Spell.GetBaseSpell(spellRef)
        if base and base > 0 and base ~= spellRef and knownInBook(base) then return base end
    end
    -- Pet bank last: it has no override/base indirection to walk.
    if
        C_SpellBook
        and C_SpellBook.IsSpellKnownOrInSpellBook
        and Enum
        and Enum.SpellBookSpellBank
        and C_SpellBook.IsSpellKnownOrInSpellBook(spellRef, Enum.SpellBookSpellBank.Pet)
    then
        return spellRef
    end
    return nil
end

local function EnsureFocusCastProxy()
    if _focusCastProxy then
        -- Demand-gate re-activation: re-register (idempotent; re-applying RegisterUnitEvent also picks up a changed kick-unit setting).
        local unitToken = GetFocusKickUnit()
        _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_START", unitToken)
        _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unitToken)
        return _focusCastProxy
    end
    _focusCastProxy = mod.TakeShell()
    local unitToken = GetFocusKickUnit()
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_START", unitToken)
    _focusCastProxy:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unitToken)
    _focusCastProxy:SetScript("OnEvent", function(_, _, castUnit)
        -- Never trust the registration alone: only the tracked unit's own casts
        -- count, it must exist, and it is never the player (no focus set, or
        -- focus/target on yourself, must stay silent).
        local kickUnit = GetFocusKickUnit()
        if castUnit ~= kickUnit then return end
        if not UnitExists(kickUnit) or UnitIsUnit(kickUnit, "player") then return end
        -- Enemies only: a friendly focus (raid member) casts constantly. A secret
        -- answer (protected content) cannot vouch either way, so it plays rather
        -- than silencing a real enemy focus.
        local attackable = UnitCanAttack("player", kickUnit)
        if not (issecretvalue and issecretvalue(attackable)) and not attackable then return end
        local edge = barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
        if not edge then return end
        local soundKey = edge.focusCastSoundKey or "none"
        if soundKey == "none" then return end
        -- Sound-only mode ("Any Cast"): no interrupt lookup, no cooldown gate.
        if edge.focusCastSoundAnyCast == true then
            local anyPath = FOCUSKICK_SOUND_PATHS[soundKey]
            if anyPath then PlaySoundFile(anyPath, "Master") end
            return
        end
        local spellId = edge.focusKickInterruptSpellID
        -- An explicit pick is only trusted while this character can cast it: a stale profile-level
        -- id sails through the cooldown gate below forever (a spell you do not know is never on
        -- cooldown), so a Holy Paladin inheriting a Ret's Rebuke would be pinged on every focus
        -- cast. Deliberately checked HERE and not at arming time: arming runs during loading
        -- screens, when the spellbook reads empty for reasons unrelated to spec, and folding "not
        -- loaded yet" into "cannot cast it" silently unregisters a working proxy. This handler only runs on a live cast, by which point the spellbook is settled.
        if spellId then spellId = mod.ResolveCastableInterrupt(spellId) end
        -- Auto-fallback: with no explicit pick, use the first CASTABLE positive spell on the bar
        -- (the picker exists for users who want a specific one). The bar's own list needs the same
        -- castability check -- not because it crosses specs (assignedSpells is per-spec) but
        -- because it can hold spells this spec no longer has: "Include CDM Spell Layout" imports
        -- write another character's layout into these spec keys wholesale, and talent changes strand entries the same way. Either way, an uncastable interrupt reads as permanently ready below.
        if not spellId or spellId <= 0 then
            local spellData = mod.GetBarSpellData and mod.GetBarSpellData(FOCUSKICK_BAR_KEY)
            if spellData and spellData.assignedSpells then
                for _, spellRef in ipairs(spellData.assignedSpells) do
                    if type(spellRef) == "number" and spellRef > 0 then
                        local castable = mod.ResolveCastableInterrupt(spellRef)
                        if castable then
                            spellId = castable
                            break
                        end
                    end
                end
            end
        end
        if not spellId or spellId <= 0 then return end

        -- No interruptible check. The kickProtected flag on UnitCastingInfo and UnitChannelInfo is
        -- a secret boolean in Midnight and any laundering path that returns a value back into Lua
        -- produces a tainted result we cannot branch on. We accept that the sound will occasionally fire on uninterruptible casts -- the nameplate shield icon still tells the player visually.

        -- Cooldown check: only play if our interrupt is ready. cdInfo.isActive is a clean bool --
        -- the duration/startTime fields are secret in Midnight and can't be compared in Lua, but isActive is safe.
        if C_Spell and C_Spell.GetSpellCooldown then
            local cdInfo = C_Spell.GetSpellCooldown(spellId)
            if cdInfo and cdInfo.isActive then return end
        end
        local filePath = FOCUSKICK_SOUND_PATHS[soundKey]
        if not filePath then return end
        PlaySoundFile(filePath, "Master")
    end)
    return _focusCastProxy
end
mod.EnsureFocusCastProxy = EnsureFocusCastProxy

-- Per-icon "Audio on Buff Gain/Loss": play a sound when a buff becomes active (gain) or drops
-- (loss). Blizzard's buff viewer item frames fire TriggerAuraAppliedAlert on the apply edge and
-- TriggerAuraRemovedAlert on the drop edge, so hooksecurefunc both (taint-safe post-hook, no
-- polling). The frame's GetSpellID is a SECRET value while the aura is active, so resolve the
-- clean canonical id via GetCanonicalSpellIDForFrame (the same id the options menu writes the
-- setting under) -- never index a table with the live secret id. Hooked-frame + throttle state
-- live in a do-block, off the Blizzard frame table per the no-custom-props rule. Reuses the
-- FocusKick sound table (option list identical to Focus Cast Sound). Edges are COALESCED to
-- the end of the frame rather than played on the spot: some auras are reapplied by REPLACING
-- the instance instead of refreshing it, and Blizzard checks its removed-alert triggers before
-- the item frames adopt the new instance, so the drop edge fires while the buff is still up.
-- Death and Decay does this on every entry into the circle, cueing a loss at the moment the
-- buff was GAINED. Both alerts for a replacement fire inside the SAME CooldownViewerMixin
-- :OnUnitAura call -- confirmed live to be indistinguishable from a genuine same-tick
-- drop+reproc (e.g. Prismatic Bolt consumed by a cast and reprocced by Salvo), so only the
-- loss cue is cancelled on a pair. A real gain always plays, even on a replacement, rather
-- than silently eating the reported case with no way to tell the two apart.
do
    local _soundHooked = setmetatable({}, { __mode = "k" })
    -- Edges seen this frame: [spellID] = sound key, or false for "edge happened,
    -- configured silent". A silent edge MUST still be recorded or a replacement
    -- whose gain has no sound (the usual setup -- loss cue only) never pairs.
    local _pendGain = {}
    local _pendLoss = {}
    local _flushQueued = false
    local _pendStamp = 0 -- GetTime() of the frame the pending edges belong to
    -- Overlap guard, NOT an edge filter: two cues for the same spell and edge closer
    -- together than this would talk over each other. Replacements are cancelled by the
    -- pairing above, so this no longer hides them.
    local _soundThrottle = {} -- [spellID] = last GetTime() (gain)
    local _soundThrottleLost = {} -- [spellID] = last GetTime() (loss)
    local SOUND_MIN_GAP = 0.3

    -- Setting key for one edge, nil = silent. A frame the CDM decorates answers
    -- from its own settings first. A Tracked Bars frame then asks its tracking
    -- bar before FindBuffSoundKey, whose bar tier answers for every spell no
    -- extra buff bar claims (a Buffs bar "Apply to Bar" sound would otherwise
    -- shadow the bar's own). A bar with a sound on its other edge only keeps
    -- this edge silent (false), so the Buffs bar is not asked either. A buff
    -- icon frame asks the tracking bars last.
    local function PickBuffSoundKey(spellSettings, spellRef, field, frame)
        local k = spellSettings and spellSettings[field]
        if not k then
            local tbbOn = mod._tbbAnyBuffSound
            local bv = tbbOn and frame and _G.BuffBarCooldownViewer
            local barFrame = bv and frame.viewerFrame == bv
            local owned
            if barFrame then
                k = mod.FindTBBSoundKey(frame, spellRef, field)
                owned = k == false
            end
            if not k and not owned then k = mod.FindBuffSoundKey(spellRef, field) end
            if not k and tbbOn and not barFrame then k = mod.FindTBBSoundKey(frame, spellRef, field) end
        end
        if not k or k == "none" then return nil end
        return k
    end

    local function PlayThrottled(key, spellRef, throttle)
        if not key then return end
        local nowTime = GetTime()
        local last = throttle[spellRef]
        if last and (nowTime - last) < SOUND_MIN_GAP then return end
        throttle[spellRef] = nowTime
        local filePath = FOCUSKICK_SOUND_PATHS[key]
        if filePath then PlaySoundFile(filePath, "Master") end
    end

    -- Edge entry point for Tracking Bars' self-timed presets (Bloodlust, Time
    -- Spiral, potions). They never fire a Blizzard aura alert, so their own timer
    -- start/stop hands the cue here: same loading-screen suppression, same 0.3s
    -- overlap guard (id is a "tbb:<preset>" string, clear of spell ids).
    function mod.PlayBuffSoundEdge(key, ident, gainEdge)
        if not key or key == "none" then return end
        if mod._cdmSoundSuppressed and mod._cdmSoundSuppressed() then return end
        PlayThrottled(key, ident, gainEdge and _soundThrottle or _soundThrottleLost)
    end

    local function FlushEdges()
        _flushQueued = false
        -- Still inside the frame these edges were recorded in (the timer can tick
        -- after some of the frame's aura events but before the rest): a later edge
        -- could still pair with them, so decide next frame instead.
        if GetTime() == _pendStamp then
            _flushQueued = true
            C_Timer.After(0, FlushEdges)
            return
        end
        -- Entries are cleared BEFORE playing so a throw inside PlaySoundFile cannot
        -- strand one and have it cancel an unrelated edge on a later flush.
        for spellRef, key in pairs(_pendLoss) do
            -- Paired with a gain this frame = replacement: the loss cue is spurious
            -- (the buff never really left). The gain may still be real (e.g. a proc
            -- landing the same tick a cast consumes the old stack), so it is left for
            -- the gain loop below instead of being cancelled here too.
            local paired = _pendGain[spellRef] ~= nil
            _pendLoss[spellRef] = nil
            if not paired then PlayThrottled(key, spellRef, _soundThrottleLost) end
        end
        for spellRef, key in pairs(_pendGain) do
            _pendGain[spellRef] = nil
            PlayThrottled(key, spellRef, _soundThrottle)
        end
    end

    -- Record one edge for the end-of-frame flush. gainEdge picks the side.
    local function RecordBuffEdge(frame, gainEdge)
        -- Loading screen / login settle: buffs re-apply and viewer frames re-show
        -- across a zone/login, firing phantom apply/remove alerts. Drop them.
        if mod._cdmSoundSuppressed and mod._cdmSoundSuppressed() then return end
        local spellRef = mod.GetCanonicalSpellIDForFrame and mod.GetCanonicalSpellIDForFrame(frame)
        if not spellRef then return end
        -- Preferred: the frame's decorated context (fast; ResolveSpellSettings also
        -- handles variant/override spells). Falls back to an id-only lookup for the
        -- FIRST gain after login, whose alert fires before DecorateFrame populates
        -- _ecmeFC -- keying off that context dropped the very first cue.
        local spellSettings
        local fc = _ecmeFC[frame]
        local barId = fc and fc.barKey
        if barId then
            local spellData = mod.GetBarSpellData and mod.GetBarSpellData(barId)
            spellSettings = mod.ResolveSpellSettings
                and mod.ResolveSpellSettings(frame, spellRef, spellData, barId)
        end
        -- A silent edge still has to be recorded so it can cancel its partner, but only
        -- when the OTHER edge has a cue -- so the second lookup runs only on that path.
        local key = PickBuffSoundKey(
            spellSettings,
            spellRef,
            gainEdge and "buffActiveSoundKey" or "buffLostSoundKey",
            frame
        )
        if
            not key
            and not PickBuffSoundKey(
                spellSettings,
                spellRef,
                gainEdge and "buffLostSoundKey" or "buffActiveSoundKey",
                frame
            )
        then
            return
        end
        -- A new frame closes the previous batch: pairing must never reach across the
        -- boundary, or a real drop and an unrelated real gain a frame later cancel out.
        local nowTime = GetTime()
        if nowTime ~= _pendStamp then
            FlushEdges()
            _pendStamp = nowTime
        end
        if gainEdge then
            _pendGain[spellRef] = key or false
        else
            _pendLoss[spellRef] = key or false
        end
        if not _flushQueued then
            _flushQueued = true
            C_Timer.After(0, FlushEdges)
        end
    end

    function mod.EnsureBuffSoundHook(widget)
        if not widget or _soundHooked[widget] then return end
        -- Own placeholder/custom frames (and anything that isn't a Blizzard buff
        -- viewer item) have no aura alert -- mark hooked so we never retry.
        if type(widget.TriggerAuraAppliedAlert) ~= "function" then
            _soundHooked[widget] = true
            return
        end
        _soundHooked[widget] = true
        hooksecurefunc(widget, "TriggerAuraAppliedAlert", function(frame) RecordBuffEdge(frame, true) end)
        -- Loss edge: Blizzard fires TriggerAuraRemovedAlert when the buff drops.
        if type(widget.TriggerAuraRemovedAlert) == "function" then
            hooksecurefunc(
                widget,
                "TriggerAuraRemovedAlert",
                function(frame) RecordBuffEdge(frame, false) end
            )
        end
    end
end

-- "FOCUS" reminder text shown on caster/miniboss nameplates when the player
-- has no focus set. Activated by the FocusKick bar's focusReminderEnabled.
-- Performance design:
--   * _focusKickHasFocus updates only on PLAYER_FOCUS_CHANGED so the hot
--     per-plate path never calls UnitExists("focus").
--   * Per-plate font strings live in _focusReminders keyed by token and are
--     reused across show/hide cycles -- never recreated.
--   * Each font string caches its last applied size/text/color/offsets so
--     SetFont / SetText / SetTextColor / SetPoint are skipped when unchanged
--     (SetFont is the most expensive call here).
--   * NAME_PLATE_UNIT_ADDED skips the work entirely when focus is set or the
--     bar setting is off -- no per-plate overhead in the normal case.
local _focusReminders = {} -- nameplate token -> font string (with _holder/_lastX cache)
local _focusReminderProxy
local _focusKickHasFocus = false
-- Context flags updated only on world/zone/spec events. Cached so the
-- per-nameplate hot path is one local read instead of repeated API calls.
local _focusKickInDungeon = false
local _focusKickNoKick = false
local _FOCUS_TEXT = "F O C U S"
local _FR_FALLBACK_FONT = "Fonts/FRIZQT__.TTF"

-- Mirror of the Quest Tracker font handling pattern: tolerate nil/OTF
-- paths, fall back to FRIZQT, and (if SetFont still fails) try alternate
-- separators / Blizzard's default font.
local function FRSafeFont(p)
    if not p or p == "" then return _FR_FALLBACK_FONT end
    local ext = p:match("%.(%a+)$")
    if ext and ext:lower() == "otf" then return _FR_FALLBACK_FONT end
    return p
end
local function FRGlobalFont()
    if CUI and CUI.GetFontPath then return FRSafeFont(CUI.GetFontPath("cdm")) end
    return _FR_FALLBACK_FONT
end
local function FROutlineFlag()
    if CUI and CUI.GetFontOutlineFlag then
        local frame = CUI.GetFontOutlineFlag("cdm")
        if frame and frame ~= "" then return frame end
    end
    return "NONE"
end
local function FRSetFontSafe(fontStr, filePath, size, flags)
    if not fontStr then return end
    local safe = FRSafeFont(filePath)
    size = size or 11
    if flags == "NONE" then flags = "" end
    flags = flags or ""
    local curPath, curSize, curFlags = fontStr:GetFont()
    if curPath == safe and curSize == size and (curFlags or "") == flags then return end
    fontStr:SetFont(safe, size, flags)
    if not fontStr:GetFont() then fontStr:SetFont("Fonts/FRIZQT__.TTF", size, flags) end
    if not fontStr:GetFont() then fontStr:SetFont("Fonts\\FRIZQT__.TTF", size, flags) end
    if not fontStr:GetFont() then
        local gf = GameFontNormal and GameFontNormal:GetFont()
        if gf then fontStr:SetFont(gf, size, flags) end
    end
end
local function FRApplyFontShadow(fontStr)
    if not fontStr then return end
    local useShadow = (CUI.GetFontUseShadow("cdm")) and true or false
    -- Font is set by FRSetFontSafe before this call; capture and restore it so
    -- priming the shadow FontObject does not change the typeface.
    local _pf, _ps, _pfl = fontStr:GetFont()
    CUI.PrimeFontShadow(fontStr, useShadow)
    if _pf then fontStr:SetFont(_pf, _ps, _pfl) end
end

local function GetFocusKickBarData() return barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY] end
local function FocusReminderUnitMatches(unitToken)
    if not unitToken then return false end
    -- Caster = the unit actually has a mana pool (12.1 moved caster marking
    -- off the old internal "PALADIN" class tag; same lane as the nameplate
    -- caster color). Second arg is the typed PowerType enum NUMBER, not the
    -- localized MANA global; the return carries no secrecy flag, so it is
    -- safe to branch on directly even on protected-content nameplates.
    if UnitHasPowerType and Enum and Enum.PowerType and UnitHasPowerType(unitToken, Enum.PowerType.Mana) then
        return true
    end
    -- Elite fallback: identity reads here DO return secrets in protected
    -- content; a secret can vouch nothing, so the signal is dropped, never
    -- compared -- this arm quietly stands down there while the mana arm
    -- above keeps carrying the feature.
    local classFile = UnitClassification and UnitClassification(unitToken)
    if issecretvalue and issecretvalue(classFile) then classFile = nil end
    if classFile == "elite" or classFile == "rareelite" or classFile == "worldboss" then
        local lvl = UnitLevel(unitToken)
        local playerLevel = UnitLevel("player")
        local lvlClean = lvl and not (issecretvalue and issecretvalue(lvl))
        local plvlClean = playerLevel and not (issecretvalue and issecretvalue(playerLevel))
        if lvlClean and (lvl == -1 or (plvlClean and lvl >= playerLevel + 1)) then return true end
    end
    return false
end
local function HideFocusReminder(unitToken)
    local fontStr = _focusReminders[unitToken]
    if fontStr and fontStr:IsShown() then fontStr:Hide() end
end
local function HideAllFocusReminders()
    for _, fontStr in pairs(_focusReminders) do
        if fontStr and fontStr:IsShown() then fontStr:Hide() end
    end
end
local function ShowFocusReminder(unitToken)
    -- Cheap rejects first
    if _focusKickHasFocus then
        HideFocusReminder(unitToken)
        return
    end
    if not _focusKickInDungeon then
        HideFocusReminder(unitToken)
        return
    end
    if _focusKickNoKick then
        HideFocusReminder(unitToken)
        return
    end
    local edge = GetFocusKickBarData()
    if not edge or edge.focusReminderEnabled ~= true then
        HideFocusReminder(unitToken)
        return
    end
    if not FocusReminderUnitMatches(unitToken) then
        HideFocusReminder(unitToken)
        return
    end
    local backing = C_NamePlate
        and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit(unitToken)
    if not backing then
        HideFocusReminder(unitToken)
        return
    end

    local fontStr = _focusReminders[unitToken]
    if not fontStr then
        local holderFrame = CreateFrame("Frame", nil, backing)
        holderFrame:SetSize(1, 1)
        holderFrame:SetFrameStrata("HIGH")
        holderFrame:SetFrameLevel(backing:GetFrameLevel() + 10)
        fontStr = holderFrame:CreateFontString(nil, "OVERLAY")
        fontStr._holder = holderFrame
        fontStr:SetPoint("CENTER", holderFrame, "CENTER", 0, 0)
        -- IMPORTANT: SetFont must run before SetText. Initialize the font using the safe helper
        -- here so the very first SetText below has a valid font. (Calling SetText on a font string with no font set raises "FontString:SetText(): Font not set".)
        FRSetFontSafe(fontStr, FRGlobalFont(), edge.focusReminderSize or 26, FROutlineFlag())
        FRApplyFontShadow(fontStr)
        fontStr:SetText(_FOCUS_TEXT)
        fontStr._lastText = _FOCUS_TEXT
        _focusReminders[unitToken] = fontStr
    end

    -- Reparent only when the plate frame for this token actually changed
    if fontStr._holder:GetParent() ~= backing then
        fontStr._holder:SetParent(backing)
        fontStr._lastOX, fontStr._lastOY = nil, nil -- force point reapply on parent change
    end

    -- Anchor: only re-SetPoint if X or Y changed
    local ox = edge.focusReminderOffsetX or 0
    local oy = (edge.focusReminderOffsetY or 0) - 15 -- internal -15 baseline
    if fontStr._lastOX ~= ox or fontStr._lastOY ~= oy then
        fontStr._holder:ClearAllPoints()
        fontStr._holder:SetPoint("TOP", backing, "BOTTOM", ox, oy)
        fontStr._lastOX, fontStr._lastOY = ox, oy
    end

    -- Font: re-apply only if size, font path, or outline changed. Goes through FRSetFontSafe so
    -- the user's global font + outline (CludesUI -> Fonts) drives the look, with fallbacks for missing/unsupported paths.
    local size = edge.focusReminderSize or 26
    local fontFile = FRGlobalFont()
    local outline = FROutlineFlag()
    if fontStr._lastSize ~= size or fontStr._lastFontPath ~= fontFile or fontStr._lastOutline ~= outline then
        FRSetFontSafe(fontStr, fontFile, size, outline)
        FRApplyFontShadow(fontStr)
        fontStr._lastSize = size
        fontStr._lastFontPath = fontFile
        fontStr._lastOutline = outline
    end

    -- Color: accent mode reads the live CLUDES_GREEN; custom mode reads the stored RGB. Re-SetTextColor only if the resolved color changed.
    local red, green, blue
    if edge.focusReminderUseAccent then
        local brandGreen = CUI.CLUDES_GREEN
        red = (brandGreen and brandGreen.r) or 0.298
        green = (brandGreen and brandGreen.g) or 0.788
        blue = (brandGreen and brandGreen.b) or 0.941
    else
        red = edge.focusReminderR or 1
        green = edge.focusReminderG or 1
        blue = edge.focusReminderB or 1
    end
    if fontStr._lastR ~= red or fontStr._lastG ~= green or fontStr._lastB ~= blue then
        fontStr:SetTextColor(red, green, blue)
        fontStr._lastR, fontStr._lastG, fontStr._lastB = red, green, blue
    end

    if not fontStr:IsShown() then fontStr:Show() end
end

local function RefreshFocusReminders()
    -- Clear all, then re-show for currently visible nameplates. Iterate unit tokens directly:
    -- plate.namePlateUnitToken can be nil when polled outside of NAME_PLATE_UNIT_ADDED events, so the safer path is to walk nameplate1..nameplate40 and let UnitExists filter.
    HideAllFocusReminders()
    if _focusKickHasFocus then return end
    if not _focusKickInDungeon then return end
    if _focusKickNoKick then return end
    local edge = GetFocusKickBarData()
    if not edge or edge.focusReminderEnabled ~= true then return end
    for index = 1, 40 do
        local unitToken = "nameplate" .. index
        if UnitExists(unitToken) then ShowFocusReminder(unitToken) end
    end
end
mod.RefreshFocusReminders = RefreshFocusReminders
_G._CUCME_RefreshFocusReminders = RefreshFocusReminders

-- Refresh the cached context flags (instance type + role) and trigger a visual refresh if either
-- flag transitioned. Called on PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA, and PLAYER_SPECIALIZATION_CHANGED.
-- Healer specs that have no kick (Resto Shaman has Wind Shear, so excluded)
local _HEALER_NO_KICK = {
    [65] = true, -- Holy Paladin
    [256] = true, -- Discipline Priest
    [257] = true, -- Holy Priest
    [105] = true, -- Restoration Druid
    [270] = true, -- Mistweaver Monk
    [1468] = true, -- Preservation Evoker
}

local function SyncFocusKickContext()
    local _, instanceType = IsInInstance()
    local inDungeonNow = (instanceType == "party")
    local specIdx = C_SpecializationInfo.GetSpecialization()
    local specId = specIdx > 0 and C_SpecializationInfo.GetSpecializationInfo(specIdx)
    local nowNoKick = specId and _HEALER_NO_KICK[specId] or false
    local changed = (inDungeonNow ~= _focusKickInDungeon) or (nowNoKick ~= _focusKickNoKick)
    _focusKickInDungeon = inDungeonNow
    _focusKickNoKick = nowNoKick
    if changed then RefreshFocusReminders() end
end
mod.UpdateFocusKickContext = SyncFocusKickContext

local function EnsureFocusReminderProxy()
    if _focusReminderProxy then
        -- Demand-gate re-activation: restore the event set (idempotent) and re-seed the state the creation path seeds.
        _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        _focusReminderProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
        _focusReminderProxy:RegisterEvent("PLAYER_ENTERING_WORLD")
        _focusReminderProxy:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        _focusReminderProxy:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        _focusKickHasFocus = UnitExists("focus") and true or false
        SyncFocusKickContext()
        return _focusReminderProxy
    end
    -- Initialize focus + context state once at proxy creation
    _focusKickHasFocus = UnitExists("focus") and true or false
    SyncFocusKickContext()
    _focusReminderProxy = mod.TakeShell()
    _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    _focusReminderProxy:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    _focusReminderProxy:RegisterEvent("PLAYER_FOCUS_CHANGED")
    _focusReminderProxy:RegisterEvent("PLAYER_ENTERING_WORLD")
    _focusReminderProxy:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    _focusReminderProxy:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    _focusReminderProxy:SetScript("OnEvent", function(_, evt, unitToken)
        if evt == "PLAYER_FOCUS_CHANGED" then
            local hadFocus = _focusKickHasFocus
            _focusKickHasFocus = UnitExists("focus") and true or false
            if hadFocus ~= _focusKickHasFocus then RefreshFocusReminders() end
        elseif
            evt == "PLAYER_ENTERING_WORLD"
            or evt == "ZONE_CHANGED_NEW_AREA"
            or evt == "PLAYER_SPECIALIZATION_CHANGED"
        then
            SyncFocusKickContext()
        elseif evt == "NAME_PLATE_UNIT_ADDED" then
            if _focusKickHasFocus then return end
            if not _focusKickInDungeon then return end
            if _focusKickNoKick then return end
            ShowFocusReminder(unitToken)
        elseif evt == "NAME_PLATE_UNIT_REMOVED" then
            HideFocusReminder(unitToken)
        end
    end)
    return _focusReminderProxy
end
mod.EnsureFocusReminderProxy = EnsureFocusReminderProxy

-- Demand gate for the whole FocusKick feature family (anchor proxy + plate watcher, reminder
-- text, cast sound). An EMPTY kick bar -- no positive spell assigned, or the bar disabled --
-- means the feature does not exist at runtime: no events registered anywhere, no ticker, zero
-- cost. Called from setup and from the tail of every BuildAllCDMBars, so assigning the first kick spell (or removing the last) flips the family on/off live.
function mod.RefreshFocusKickProxies()
    local edge = barDataByKey and barDataByKey[FOCUSKICK_BAR_KEY]
    local hasIcons = false
    -- "No spell data available" is NOT the same as "the bar is empty": GetBarSpellData returns nil
    -- while the active spec key is unresolved, which is exactly the loading-screen state. Treating
    -- that as empty ran the teardown below and UNREGISTERED a perfectly good proxy (sound dying after a port/zone until something rebuilt the bars). With the store not ready, leave the proxy exactly as it is; the next rebuild arms it.
    local storeReady, playSound = true, false
    if edge and edge.enabled ~= false then
        local spellData = mod.GetBarSpellData and mod.GetBarSpellData(FOCUSKICK_BAR_KEY)
        if not spellData then storeReady = false end
        local spells = spellData and spellData.assignedSpells
        if spells then
            for _, spellRef in ipairs(spells) do
                if type(spellRef) == "number" and spellRef > 0 then
                    hasIcons = true
                    break
                end
            end
        end
        -- The cast SOUND has a weaker requirement than the rest of the family: its handler needs a
        -- configured sound plus an interrupt id for the readiness check, and the bar's assigned
        -- spells are only the FALLBACK source for that id -- an explicit focusKickInterruptSpellID
        -- satisfies it alone. Gating the sound on hasContent made a legitimate setup impossible: the focus-cast sound WITHOUT the kick icon.
        local sk = edge.focusCastSoundKey
        if sk and sk ~= "none" then
            local pick = edge.focusKickInterruptSpellID
            playSound = (edge.focusCastSoundAnyCast == true)
                or (type(pick) == "number" and pick > 0)
                or hasIcons
        end
    end

    if not hasIcons and not storeReady then
        -- Spell store unresolved: hold the current state rather than tearing down something that
        -- may still be correct, and COME BACK -- arming is otherwise a one-shot (its only callers
        -- are setup and the tail of BuildAllCDMBars), so a login/zone where the spec key has not
        -- resolved yet would leave the proxy unbuilt all session on a fully populated bar. An explicit interrupt spell id lives on the bar data, not the spell store, so the sound can arm right now; only the bar-content dependent parts have to wait.
        if playSound then EnsureFocusCastProxy() end
        -- One pending retry at a time, self-cancelling.
        if not mod._fkRearmPending then
            mod._fkRearmPending = true
            C_Timer.After(2, function()
                mod._fkRearmPending = nil
                if mod.RefreshFocusKickProxies then mod.RefreshFocusKickProxies() end
            end)
        end
        return
    end
    -- Icon-bearing parts of the family keep the original bar-content gate.
    if hasIcons then
        EnsureFocusKickProxy()
        _focusKickLastPlateVisible = nil
        PlaceFocusKick()
        EnsureFocusReminderProxy()
        RefreshFocusReminders()
    else
        if _focusKickProxy then
            _focusKickProxy:UnregisterAllEvents()
            if _focusKickProxy._stop then _focusKickProxy._stop() end
            FadeFocusKick(0)
        end
        if _focusReminderProxy then
            _focusReminderProxy:UnregisterAllEvents()
            HideAllFocusReminders()
        end
    end

    if playSound then
        EnsureFocusCastProxy()
    elseif _focusCastProxy then
        _focusCastProxy:UnregisterAllEvents()
    end
end

Inner.EnsureFocusKickBar, Inner.FOCUSKICK_BAR_KEY = EnsureFocusKickBar, FOCUSKICK_BAR_KEY
Inner.FOCUSKICK_SOUND_NAMES, Inner.FOCUSKICK_SOUND_ORDER = FOCUSKICK_SOUND_NAMES, FOCUSKICK_SOUND_ORDER
Inner.FOCUSKICK_SOUND_PATHS = FOCUSKICK_SOUND_PATHS
Inner.broken = false
