if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_BuffBarPresets.lua
--
--  Stacks, pandemic glow, the Blizzard bar font strings, icon spell ids and
--  the self-timed presets (Bloodlust, Time Spiral, potions).
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._buffBarInternals
-- CludesUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local GetTime = GetTime
local pcall = pcall

local _blizzBarFS, BBFS, StartGlow, StopGlow = Inner._blizzBarFS, Inner.BBFS, Inner.StartGlow, Inner.StopGlow
local _tbbWake, StableCooldownSpellID = Inner._tbbWake, Inner.StableCooldownSpellID
local _tbbAssignment, CfgWantsSID = Inner._tbbAssignment, Inner.CfgWantsSID

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local _tbbAssignDirty = true
Inner.assignDirtySetters[#Inner.assignDirtySetters + 1] = function(val)
    _tbbAssignDirty = val
end

-------------------------------------------------------------------------------
--  Stacks Helper (reads Blizzard child Applications frame)
-------------------------------------------------------------------------------
-- Applications count for a Blizzard child, avoiding the aura-instance query where
-- possible: the child's auraDataCached table usually reads without erroring, its
-- applications field is plain on live and secret under the 12.1 combat
-- restriction, and both feed StatusBar:SetValue/FontString:SetText natively. The
-- cache can also be a secret TABLE (Blizzard fills it from aura queries that hide
-- the whole aura while the unit's auras are restricted), which cannot be indexed,
-- so it reads as an unpopulated cache. The instance-id query is the fallback for an
-- unpopulated cache and HARD-ERRORS on 12.1 restricted units, hence the pcall and
-- the secret-iid guard.
local function ReadStackApplications(blzChild)
    local ad = blzChild.auraDataCached
    if not issecretvalue(ad) and ad and ad.applications then
        return ad.applications
    end
    local auraInstID = blzChild.auraInstanceID
    local auraUnit = blzChild.auraDataUnit
    if auraInstID and auraUnit and not issecretvalue(auraInstID) then
        local success, skinData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, auraUnit, auraInstID)
        if success and skinData and skinData.applications then
            return skinData.applications
        end
    end
    return nil
end

local function UpdateStacks(barFrame, blzChild, conf)
    -- Stack-based fill needs a live count even when Blizzard renders no Applications text
    -- (hidden at 1 stack), plus a restricted marker so the fill site fails open instead of an empty bar.
    local stackFill = conf
        and conf.stackBasedBar
        and conf.trackType ~= "cooldown"
        and conf.stackThresholdMaxEnabled
    barFrame._stackUnreadable = nil
    if stackFill and blzChild then
        -- Stack-based bar: skip the Blizzard text mirror (blank below 2 stacks) and drive
        -- fill/text from the aura data. This helper only runs for active frames, so the aura is
        -- up and a readable count floors at 1; a secret count passes through to SetValue/SetText untouched.
        local apps = ReadStackApplications(blzChild)
        if apps then
            if not issecretvalue(apps) and apps < 1 then
                apps = 1
            end
            barFrame._stackCount = apps
            if barFrame._stacksText then
                if barFrame._stacksHidden then
                    barFrame._stacksText:Hide()
                else
                    barFrame._stacksText:SetText(apps)
                    barFrame._stacksText:Show()
                end
            end
        else
            -- No cached aura table and no readable instance id: count is unknowable, so the fill site fails open.
            barFrame._stackCount = 0
            barFrame._stackUnreadable = true
            if barFrame._stacksText then
                barFrame._stacksText:Hide()
            end
        end
        return
    end
    -- Read stacks from blzChild.Icon.Applications FontString.
    if blzChild and blzChild.Icon and blzChild.Icon.Applications then
        -- NEVER compare the text (it may be secret); SetText takes it natively.
        local success, txt = pcall(blzChild.Icon.Applications.GetText, blzChild.Icon.Applications)
        if success and txt then
            -- _stacksHidden (Stacks Position: None) gates every writer lane:
            -- this helper runs for EVERY active bar once ANY bar wants stacks
            -- (_anyStacks is a global gate), so an unguarded show here painted
            -- stacks onto bars that disabled them.
            if barFrame._stacksText and not barFrame._stacksHidden then
                barFrame._stacksText:SetText(txt)
                barFrame._stacksText:Show()
            elseif barFrame._stacksText then
                barFrame._stacksText:Hide()
            end
            -- Stack count for the threshold overlay: applications can be a secret number we
            -- cannot compare, but the overlay consumes it via SetValue (FeedTBBThresholdOverlay), which accepts secrets.
            barFrame._stackCount = ReadStackApplications(blzChild) or 0
            return
        end
    end
    -- Fallback: top-level Applications (BuffIcon children)
    if blzChild and blzChild.Applications and blzChild.Applications:IsShown() then
        local appsText = blzChild.Applications.Applications
        if appsText then
            local success, txt = pcall(appsText.GetText, appsText)
            if success and txt and (issecretvalue(txt) or txt ~= "") then
                if barFrame._stacksText and not barFrame._stacksHidden then
                    barFrame._stacksText:SetText(txt)
                    barFrame._stacksText:Show()
                end
                barFrame._stackCount = ReadStackApplications(blzChild) or 0
                return
            end
        end
    end
    -- No stacks text
    if barFrame._stacksText then
        barFrame._stacksText:Hide()
    end
    barFrame._stackCount = 0
end

-------------------------------------------------------------------------------
--  Pandemic Glow Helpers
-------------------------------------------------------------------------------
local function ClearPandemic(barFrame)
    if barFrame._pandemicGlowTarget then
        StopGlow(barFrame._pandemicGlowTarget)
    end
    barFrame._pandemicGlowActive = false
    barFrame._pandemicGlowStyleIdx = nil
    barFrame._pandemicGlowTarget = nil
end

--- Start or update the pandemic glow on a bar. Caller checks the threshold and drives alpha from the tick (smooth fade on remaining%).
local function UpdatePandemic(barFrame, conf)
    -- Glow always wraps the whole bar: the overlay covers the entire wrapFrame footprint, so an enabled icon is included rather than glowed alone.
    local glowTarget = barFrame._pandemicGlowOverlay

    -- Bar rectangle: Pixel Glow or Auto-Cast Shine only (texture styles stretch);
    -- any other stored style, and Blizzard Default (-1), render as Pixel Glow.
    local style = mod.PG_TbbEffectiveStyle(conf)

    -- Start/restart glow on style or target change
    if
        not barFrame._pandemicGlowActive
        or barFrame._pandemicGlowStyleIdx ~= style
        or barFrame._pandemicGlowTarget ~= glowTarget
    then
        if barFrame._pandemicGlowActive and barFrame._pandemicGlowTarget and barFrame._pandemicGlowTarget ~= glowTarget then
            StopGlow(barFrame._pandemicGlowTarget)
        end
        local c
        if conf.pandemicGlowMode == "class" then
            c = CludesUI.GetClassColor(CludesUI._playerClass)
        elseif conf.pandemicGlowMode == "custom" then
            c = conf.pandemicGlowColor
        end
        local glowOpts = (style == 1)
                and {
                    N = conf.pandemicGlowLines or 8,
                    th = conf.pandemicGlowThickness or 2,
                    period = conf.pandemicGlowSpeed or 4,
                    bg = conf.pandemicGlowBackground
                            and {
                                r = (conf.pandemicGlowBackgroundColor and conf.pandemicGlowBackgroundColor.r)
                                    or 0,
                                g = (conf.pandemicGlowBackgroundColor and conf.pandemicGlowBackgroundColor.g)
                                    or 0,
                                b = (conf.pandemicGlowBackgroundColor and conf.pandemicGlowBackgroundColor.b)
                                    or 0,
                            }
                        or nil,
                }
            or nil
        StartGlow(glowTarget, style, c and c.r, c and c.g, c and c.b, glowOpts)
        barFrame._pandemicGlowActive = true
        barFrame._pandemicGlowStyleIdx = style
        barFrame._pandemicGlowTarget = glowTarget
    end
end

-------------------------------------------------------------------------------
--  Blizzard Bar FontString Discovery: finds the name/timer FontStrings on a Blizzard
--  Bar StatusBar and caches the refs externally (zero alloc after the first call).
-------------------------------------------------------------------------------
local function GetBlizzBarFontStrings(blizzBar)
    if not blizzBar then
        return nil, nil
    end
    local cached = _blizzBarFS[blizzBar]
    if cached and cached.nameFS then
        return cached.nameFS, cached.timerFS
    end
    -- Discover by iterating regions. The StatusBar has exactly 2 FontStrings: 1st = spell name, 2nd = timer text.
    local nameFS, timerFS
    local fsIdx = 0
    for _, region in pairs({ blizzBar:GetRegions() }) do
        if region:GetObjectType() == "FontString" then
            fsIdx = fsIdx + 1
            if fsIdx == 1 then
                nameFS = region
            end
            if fsIdx == 2 then
                timerFS = region
            end
        end
    end
    -- External cache (false = "searched, not found"), never on the Blizzard frame
    local skinData = BBFS(blizzBar)
    skinData.nameFS = nameFS or false
    skinData.timerFS = timerFS or false
    return nameFS, timerFS
end

-------------------------------------------------------------------------------
--  EffectiveIconSpellID
--  Which spell id's ICON represents a config right now. cfg.spellID is the pick-time
--  form; talents can override it to a different form with a different icon
--  (C_Spell.GetOverrideSpell), and a bar saved for an override form loses that form
--  when untalented (only its base stays known). Icon FALLBACK paths only -- a bound
--  Blizzard frame or live aura data wins when available.
-------------------------------------------------------------------------------
local function EffectiveIconSpellID(conf)
    local spellRef = conf.spellID
    if not spellRef or spellRef <= 0 then
        return nil
    end
    -- Saved form currently overridden by a talent: show the override's icon.
    if C_Spell and C_Spell.GetOverrideSpell then
        local shade = C_Spell.GetOverrideSpell(spellRef)
        if type(shade) == "number" and shade > 0 and shade ~= spellRef then
            return shade
        end
    end
    -- Saved the override form, now untalented: the saved form is no longer known but its captured base is, so show the base form's icon.
    if
        conf.baseSpellID
        and conf.baseSpellID > 0
        and IsPlayerSpell
        and not IsPlayerSpell(spellRef)
        and IsPlayerSpell(conf.baseSpellID)
    then
        return conf.baseSpellID
    end
    return spellRef
end

-- Cooldown-bar spell resolution. Charge Hash Lines needs a STABLE identity (segment math
-- breaks if the tracked id flips to a proc override mid-recharge), so bars with that toggle
-- resolve via StableCooldownSpellID; every other cooldown bar follows overrides via EffectiveIconSpellID.
local function CooldownBarSpellID(conf)
    if conf and conf.chargeHashLines == true then
        return StableCooldownSpellID(conf)
    end
    return EffectiveIconSpellID(conf)
end

-- Mirror the 12.1 engine-written decimal timer string (hidden FS on the aura slot
-- button; see CludesUICdmTbbDecimals.lua) onto the bar's timer FS. SECRET RULES:
-- the slot button's IsShown() is a SECRET BOOLEAN (aura presence) -- never test it in
-- Lua, route through engine-side SetAlphaFromBoolean (present->1, gone->0) so a stale
-- string can never be visible on a filter miss. The engine string may itself be
-- secret: nil-check via type tag only, SetText accepts secret strings. Returns true
-- only when a string was written AND the alpha gate applied (failure degrades
-- precision, never accuracy); bar._tbbAlphaGated tracks the gate so the fallback
-- path never inherits a stuck alpha-0 FS.
local function MirrorEngineTimer(barFrame, conf)
    local engBtn = barFrame._tbbEngineText
    if not engBtn then
        return false
    end
    local result = barFrame._timerText
    local engFS = barFrame._tbbEngineFS
    local wrote = false
    if conf.showTimer and result and engFS then
        local success, txt = pcall(engFS.GetText, engFS)
        if success and type(txt) ~= "nil" then
            wrote = (pcall(result.SetText, result, txt))
        end
    end
    -- Alpha gate is best-effort: every call site has already established aura presence
    -- (viewer isActive/a live aura read), so a missing setter must not disable the mirror itself.
    if wrote and result.SetAlphaFromBoolean then
        pcall(result.SetAlphaFromBoolean, result, engBtn:IsShown(), 1, 0)
        barFrame._tbbAlphaGated = true
    elseif barFrame._tbbAlphaGated then
        if result then
            result:SetAlpha(1)
        end
        barFrame._tbbAlphaGated = nil
    end
    return wrote
end

-------------------------------------------------------------------------------
--  Bloodlust / Heroism duration bar (debuff-driven, self-timed)
--  The lust buff is cast by others and is secret, so it can't be mirrored from a
--  Blizzard buff-bar child. Watch ONLY the player's Sated/Exhaustion debuff
--  (player-only UNIT_AURA, NEVER a global scan) and start a 40s bar on its rising
--  edge. No login/reload reconstruction: reloading mid-lust gives no bar (debuff
--  was not just acquired). Matching preset: popularKey == "bloodlust".
-------------------------------------------------------------------------------
local SATED_DEBUFFS = { 57723, 57724, 80354, 95809, 160455, 264689, 390435 }
local _lustExpiry = 0
local _satedPresent = false
local _satedSince -- GetTime() of the rise this listener armed on (nil = unknown age)
local _lustZoneGuard = 0 -- suppress rising edges until this time (set on zone-in)
local _lustListenerActive = false -- baseline _satedPresent only on (re)enable, not every rebuild
local _lustListener

local function _playerHasSated()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return false
    end
    for index = 1, #SATED_DEBUFFS do
        -- Querying a KNOWN spellID returns the aura even when its fields are secret in
        -- combat, so the edge is detected mid-fight; the (possibly secret) spellID is never read back.
        if C_UnitAuras.GetPlayerAuraBySpellID(SATED_DEBUFFS[index]) then
            return true
        end
    end
    return false
end

-- Toggle the player-only Sated listener. Registered only while a lust bar exists; baselines _satedPresent on enable so it fires only on NEW edges.
local function _ensureLustListener(enable)
    if enable then
        if not _lustListener then
            _lustListener = mod.TakeShell()
            _lustListener:SetScript("OnEvent", function(_, evt, _, updateInfo)
                if evt == "PLAYER_ENTERING_WORLD" then
                    -- Zone/login aura refresh: re-baseline WITHOUT arming and suppress edges
                    -- briefly. An already-carried Sated debuff (zoning out of a dungeon) must
                    -- never read as a fresh cast and pop a phantom 40s bar in the open world.
                    _satedPresent = _playerHasSated()
                    _satedSince = nil
                    _lustZoneGuard = GetTime() + 1.5
                    return
                end
                if evt == "PLAYER_DEAD" or evt == "PLAYER_ALIVE" then
                    -- Death strips the lockout debuff, so the 590s pin below has to be
                    -- released here: a wipe followed by a fresh lust would otherwise be
                    -- swallowed for the rest of the window the pin was stamped for.
                    _satedPresent = _playerHasSated()
                    _satedSince = nil
                    return
                end
                -- Nothing but death lifts the lockout early (handled above), so a rise
                -- this listener armed on pins the debuff for the next 590s: skip the
                -- (allocating) aura probe until it can possibly have dropped.
                if _satedPresent and _satedSince and GetTime() < _satedSince + 590 then
                    return
                end
                local present = _playerHasSated()
                -- Arm ONLY on a genuine incremental application: not a full
                -- aura refresh (zone/login resends every aura), and not inside
                -- the post-zone grace window. The UNIT_AURA payload and its
                -- fields can be SECRET in combat, and boolean use of a secret
                -- errors, so a secret payload is treated as incremental (full
                -- refreshes come from zone/login, covered by the zone guard).
                local isFull = false
                if updateInfo and not issecretvalue(updateInfo) then
                    local val = updateInfo.isFullUpdate
                    if not issecretvalue(val) and val then
                        isFull = true
                    end
                end
                if present and not _satedPresent and not isFull and GetTime() >= _lustZoneGuard then
                    _lustExpiry = GetTime() + 40 -- rising edge: lust just went out
                    mod.TBBPresetSoundEdge("bloodlust", true, _lustExpiry)
                    _satedSince = GetTime()
                    _tbbWake.Wake() -- lust can come from other players: no local cast/aura edge is guaranteed
                    -- Drive Custom Auras (icon) lust displays sharing this edge.
                    if mod.SignalLustCast then
                        mod.SignalLustCast()
                    end
                end
                _satedPresent = present
                if not present then
                    _satedSince = nil
                end
            end)
        end
        -- Baseline ONLY on the OFF->ON transition. Re-baselining on every BuildTrackedBuffBars
        -- (fires during zone changes, sometimes while the aura table is momentarily empty)
        -- could set _satedPresent=false and make the debuff's return look like a cast.
        if not _lustListenerActive then
            _satedPresent = _playerHasSated()
            _satedSince = nil
            _lustListener:RegisterUnitEvent("UNIT_AURA", "player")
            _lustListener:RegisterEvent("PLAYER_ENTERING_WORLD")
            _lustListener:RegisterEvent("PLAYER_DEAD")
            _lustListener:RegisterEvent("PLAYER_ALIVE")
            _lustListenerActive = true
        end
    elseif _lustListener and _lustListenerActive then
        _lustListener:UnregisterAllEvents()
        _lustListenerActive = false
    end
end

-- Arm the shared Sated listener if EITHER a Tracking Bar lust bar OR a Custom Auras (icon)
-- lust display is enabled. Authoritative (scans the DB), safe to call from any rebuild/toggle path.
function mod.UpdateLustListener()
    local any = false
    local tbb = mod.GetTrackedBuffBars and mod.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, conf in ipairs(tbb.bars) do
            if conf.enabled ~= false and conf.popularKey == "bloodlust" then
                any = true
                break
            end
        end
    end
    if not any and mod.AnyCustomAuraLust then
        any = mod.AnyCustomAuraLust()
    end
    -- WoW Forever has no raid lust and no Sated debuff: a lust bar or icon saved
    -- on another client stays dormant there and never arms the listener.
    if CludesUI.IS_FOREVER then
        any = false
    end
    _ensureLustListener(any)
    -- Sibling preset listeners refresh from the same change sites: every add/remove/rebuild path already calls UpdateLustListener.
    if mod.UpdateTimeSpiralListener then
        mod.UpdateTimeSpiralListener()
    end
    if mod.UpdatePotionCastListener then
        mod.UpdatePotionCastListener()
    end
    if mod.UpdateCooldownCastListener then
        mod.UpdateCooldownCastListener()
    end
end

-- Profile-wide smooth-fill switches (Bar Layout > Smooth Bars), resolved ONCE per tick by
-- UpdateTrackedBuffBarTimers for every fill site. buffs = buff mirrors + self-timed
-- presets (lust/time spiral/potions); cooldowns = trackType=="cooldown" bars; off = values
-- snap (no easing). Defaults: buffs ON, cooldowns OFF (absent keys read that way).
-- Fields on _tbbWake: the fill sites sit in three files and the tick writes both every pass.
_tbbWake._smoothBuffs, _tbbWake._smoothCooldowns = true, false

-- Self-driven display for an event-armed, self-timed preset bar (Bloodlust 40s, Time Spiral
-- 10s): fill+timer come from our own countdown, not a Blizzard frame (name/icon are set in
-- BuildTrackedBuffBars). `expiry` = GetTime() the window ends at; `duration` = full window length.
local function _UpdateSelfTimedBar(barFrame, conf, expiry, duration)
    local remaining = expiry - GetTime()
    if remaining <= 0 then
        -- The loss cue comes from the preset's latch in the tick, shown or not.
        if barFrame:IsShown() then
            barFrame:Hide()
        end
        return
    end
    local wasShown = barFrame:IsShown()
    if not wasShown then
        barFrame:Show()
    end
    local scrollBar = barFrame._bar
    if scrollBar then
        scrollBar:SetMinMaxValues(0, duration)
        -- Smooth fill is baseline for tracking bars: they move one direction at a known rate
        -- (unlike a health bar, no sudden jump needs instant read), so interpolation only
        -- removes judder. The wasShown gate snaps a fresh appearance instead of animating from a stale value.
        local smooth = _tbbWake._smoothBuffs
            and wasShown
            and Enum
            and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
        if smooth then
            scrollBar:SetValue(remaining, smooth)
        else
            scrollBar:SetValue(remaining)
        end
        if conf.showSpark and barFrame._spark then
            barFrame._spark:Show()
        end
    end
    if conf.showTimer and barFrame._timerText then
        -- The string changes only when its displayed bucket does (rounded tenths
        -- under 10s, whole seconds above), so stamp the bucket and skip the
        -- per-tick format + SetText otherwise. A fresh appearance always writes
        -- (wasShown false) and the placeholder exit clears the stamp, so no other
        -- writer of this FontString can strand it.
        local key
        if remaining < 10 then
            key = math.floor(remaining * 10 + 0.5)
        else
            key = math.floor(remaining)
        end
        if not wasShown or barFrame._stTxtKey ~= key then
            barFrame._stTxtKey = key
            if remaining < 10 then
                barFrame._timerText:SetText(string.format("%.1f", remaining))
            else
                barFrame._timerText:SetText(string.format("%d", remaining))
            end
        end
        barFrame._timerText:Show()
    elseif barFrame._timerText then
        barFrame._timerText:Hide()
    end
    return true -- window active: keep the tick awake
end
local function UpdateLustBar(barFrame, conf)
    return _UpdateSelfTimedBar(barFrame, conf, _lustExpiry, 40)
end

-------------------------------------------------------------------------------
--  Time Spiral "Free Move" preset (popularKey == "timespiral")
--  Mirrors Bloodlust, but armed off Blizzard's spell-activation glow on the player's
--  class movement ability (free-cast proc) instead of an aura: a whitelisted
--  glow-SHOW starts a self-timed 10s window; like Bloodlust, only a fresh glow arms
--  it, no login/reload reconstruction. Talent-aware suppression drops glows firing on
--  a movement ability for unrelated reasons (DH Inertia/Dash of Chaos, Warlock Soulburn).
-------------------------------------------------------------------------------
local TIME_SPIRAL_DURATION = 10
-- Per-class movement abilities that glow when Time Spiral grants a free cast.
local TIME_SPIRAL_TRIGGERS = {
    [48265] = true, -- Death's Advance
    [195072] = true, -- Fel Rush
    [189110] = true, -- Infernal Strike
    [1850] = true, -- Dash
    [252216] = true, -- Tiger Dash
    [358267] = true, -- Hover
    [186257] = true, -- Aspect of the Cheetah
    [1953] = true, -- Blink
    [212653] = true, -- Shimmer
    [361138] = true, -- Roll
    [119085] = true, -- Chi Torpedo
    [190784] = true, -- Divine Steed
    [73325] = true, -- Leap of Faith
    [2983] = true, -- Sprint
    [192063] = true, -- Gust of Wind
    [58875] = true, -- Spirit Walk
    [79206] = true, -- Spiritwalker's Grace
    [48020] = true, -- Demonic Circle: Teleport
    [6544] = true, -- Heroic Leap
}
-- Talent-gated abilities that ALSO glow a movement ability for reasons unrelated to the proc.
-- While the talent is known, casting one suppresses the glow that follows for a short window.
local TIME_SPIRAL_GLOW_FILTERS = {
    { talent = 427640, spells = { 198793, 370965, 195072 } }, -- DH Inertia
    { talent = 427794, spells = { 195072 } }, -- DH Dash of Chaos
    { talent = 385899, spells = { 385899 } }, -- Warlock Soulburn
}
-- State grouped in one table.
local _ts = { expiry = 0, suppressUntil = 0, suppress = {}, active = false, frame = nil }

local function _rebuildTimeSpiralSuppress()
    wipe(_ts.suppress)
    local known = C_SpellBook and C_SpellBook.IsSpellKnown
    if not known then
        return
    end
    for _, entry in ipairs(TIME_SPIRAL_GLOW_FILTERS) do
        if known(entry.talent) then
            for _, spellRef in ipairs(entry.spells) do
                _ts.suppress[spellRef] = true
            end
        end
    end
end

-- Toggle the glow listener; registered only while an enabled Time Spiral bar or Custom Auras (icon) display exists. Glow-event spellIDs are never secret.
local function _ensureTimeSpiralListener(enable)
    if enable then
        if not _ts.frame then
            _ts.frame = mod.TakeShell()
            _ts.frame:SetScript("OnEvent", function(_, evt, ...)
                if evt == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
                    local spellRef = ...
                    if not TIME_SPIRAL_TRIGGERS[spellRef] then
                        return
                    end
                    if GetTime() < _ts.suppressUntil then
                        return
                    end
                    _ts.expiry = GetTime() + TIME_SPIRAL_DURATION -- free move just granted
                    mod.TBBPresetSoundEdge("timespiral", true, _ts.expiry)
                    _tbbWake.Wake() -- glow edge is outside the sleeper's wake events
                    -- Drive Custom Auras (icon) displays sharing this edge.
                    if mod.SignalTimeSpiralCast then
                        mod.SignalTimeSpiralCast()
                    end
                elseif evt == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
                    local spellRef = ...
                    if not TIME_SPIRAL_TRIGGERS[spellRef] then
                        return
                    end
                    -- Proc consumed or expired: end the window now so bar/icon disappear with
                    -- the glow rather than riding out the full 10s. Guarded on an active window
                    -- so an unrelated trigger's hide cannot fire spuriously.
                    if _ts.expiry > GetTime() then
                        _ts.expiry = 0
                        mod.TBBPresetSoundEdge("timespiral", false)
                        if mod.SignalTimeSpiralEnd then
                            mod.SignalTimeSpiralEnd()
                        end
                    end
                elseif evt == "UNIT_SPELLCAST_SENT" then
                    -- (unit, target, castGUID, spellID); arg4 is the spellID.
                    local _, _, _, spellRef = ...
                    if spellRef and _ts.suppress[spellRef] then
                        _ts.suppressUntil = GetTime() + 1.5
                    end
                elseif evt == "TRAIT_CONFIG_UPDATED" or evt == "PLAYER_ENTERING_WORLD" then
                    _rebuildTimeSpiralSuppress()
                end
            end)
        end
        if not _ts.active then
            _rebuildTimeSpiralSuppress()
            _ts.frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            _ts.frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            _ts.frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
            _ts.frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
            _ts.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
            _ts.active = true
        end
    elseif _ts.frame and _ts.active then
        _ts.frame:UnregisterAllEvents()
        _ts.active = false
    end
end

-- Arm the glow listener if EITHER a Time Spiral Tracking Bar OR a Custom Auras (icon) Time Spiral display is enabled. Authoritative (scans the DB).
function mod.UpdateTimeSpiralListener()
    local any = false
    local tbb = mod.GetTrackedBuffBars and mod.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, conf in ipairs(tbb.bars) do
            if conf.enabled ~= false and conf.popularKey == "timespiral" then
                any = true
                break
            end
        end
    end
    if not any and mod.AnyCustomAuraTimeSpiral then
        any = mod.AnyCustomAuraTimeSpiral()
    end
    -- WoW Forever has no Time Spiral: a bar or icon saved on another client stays
    -- dormant there and never arms the glow listener.
    if CludesUI.IS_FOREVER then
        any = false
    end
    _ensureTimeSpiralListener(any)
end

-------------------------------------------------------------------------------
--  Self-cast potion presets (Light's Potential, Potion of Recklessness, Invisibility
--  Potion). NEVER aura-tracked: a hardcoded window starts the moment the potion's
--  spell is cast, matching the CDM buff-bar/Fake-Active potions. Same self-timed model
--  as Bloodlust/Time Spiral -- only a fresh cast arms it, so a reload mid-buff shows
--  nothing until next use. Built from BUFF_BAR_PRESETS: every non-tbbOnly preset
--  (bloodlust/timespiral are tbbOnly, event-driven above) is cast-timed.
-------------------------------------------------------------------------------
local _potionDur = {} -- [popularKey] = hardcoded window seconds
local _potionTrigger = {} -- [castSpellID] = popularKey
do
    local presets = mod.BUFF_BAR_PRESETS
    if presets then
        for _, p in ipairs(presets) do
            if not p.tbbOnly and p.spellIDs and p.duration then
                _potionDur[p.key] = p.duration
                for _, spellRef in ipairs(p.spellIDs) do
                    if type(spellRef) == "number" and spellRef > 0 then
                        _potionTrigger[spellRef] = p.key
                    end
                end
            end
        end
    end
end
local _potionExpiry = {} -- [popularKey] = GetTime() the window ends at
local _potionFrame
local _potionActive = false

local function _ensurePotionCastListener(enable)
    if enable then
        if not _potionFrame then
            _potionFrame = mod.TakeShell()
            -- UNIT_SPELLCAST_SUCCEEDED (player): same edge the CDM buff-bar potions fire on. arg4 = cast spellID (never secret).
            _potionFrame:SetScript("OnEvent", function(_, _, _, _, spellId)
                local key = spellId and _potionTrigger[spellId]
                if not key then
                    return
                end
                _potionExpiry[key] = GetTime() + (_potionDur[key] or 30)
                mod.TBBPresetSoundEdge(key, true, _potionExpiry[key])
            end)
        end
        if not _potionActive then
            _potionFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            _potionActive = true
        end
    elseif _potionFrame and _potionActive then
        _potionFrame:UnregisterAllEvents()
        _potionActive = false
    end
end

-- Arm the cast listener only while an enabled potion-preset Tracking Bar exists. Refreshed
-- from the same change sites as the other preset listeners (fanned out from UpdateLustListener).
function mod.UpdatePotionCastListener()
    local any = false
    local tbb = mod.GetTrackedBuffBars and mod.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, conf in ipairs(tbb.bars) do
            if conf.enabled ~= false and conf.popularKey and _potionDur[conf.popularKey] then
                any = true
                break
            end
        end
    end
    _ensurePotionCastListener(any)
end

-- Can a sound set on this tracking bar ever play? Options-side predicate:
-- cheap, allocation-free, secret-safe. Cooldown-tracking bars never cue. A
-- preset cues from its own window, so only the self-timed ones count. Any
-- other bar cues only through a Blizzard buff viewer's aura alert, so its
-- spell has to be in the Tracked Bars or Tracked Buffs viewer: the bar's
-- current pairing, or a live frame of either viewer whose spell the bar
-- wants (the id match the alert path uses).
function mod.TBB_BarCanCue(conf)
    if type(conf) ~= "table" or conf.trackType == "cooldown" then
        return false
    end
    local pk = conf.popularKey
    if pk then
        -- The lust and Time Spiral windows never open on WoW Forever (their
        -- listeners stay off there), so only a cast-timed preset can cue.
        if CludesUI.IS_FOREVER then
            return _potionDur[pk] ~= nil
        end
        return pk == "bloodlust" or pk == "timespiral" or _potionDur[pk] ~= nil
    end
    -- A dirty map still holds the previous pass's pairings: trust it only once rebuilt,
    -- and only while Tracking Bars are on (the tick is the only thing that keeps it current).
    if _tbbWake._enabled and not _tbbAssignDirty and _tbbAssignment[conf] then
        return true
    end
    local GetCanonical = mod.GetCanonicalSpellIDForFrame
    if not GetCanonical then
        return false
    end
    for vi = 1, 2 do
        local viewer
        if vi == 1 then
            viewer = _G.BuffBarCooldownViewer
        else
            viewer = _G.BuffIconCooldownViewer
        end
        local pool = viewer and viewer.itemFramePool
        if pool then
            for widget in pool:EnumerateActive() do
                if CfgWantsSID(conf, GetCanonical(widget)) then
                    return true
                end
            end
        end
    end
    return false
end

-- True when v is a plain, readable number. A secret value fails BEFORE any type/comparison touches it; nil and non-numbers fail too.
local function _tbbCleanNum(val)
    if issecretvalue and issecretvalue(val) then
        return false
    end
    return type(val) == "number"
end

Inner._potionDur, Inner._potionExpiry, Inner._tbbCleanNum = _potionDur, _potionExpiry, _tbbCleanNum
Inner._ts, Inner._UpdateSelfTimedBar, Inner.ClearPandemic = _ts, _UpdateSelfTimedBar, ClearPandemic
Inner.CooldownBarSpellID, Inner.EffectiveIconSpellID = CooldownBarSpellID, EffectiveIconSpellID
Inner.GetBlizzBarFontStrings, Inner.MirrorEngineTimer = GetBlizzBarFontStrings, MirrorEngineTimer
Inner.TIME_SPIRAL_DURATION, Inner.UpdateLustBar = TIME_SPIRAL_DURATION, UpdateLustBar
Inner.UpdatePandemic, Inner.UpdateStacks = UpdatePandemic, UpdateStacks
Inner.broken = false
