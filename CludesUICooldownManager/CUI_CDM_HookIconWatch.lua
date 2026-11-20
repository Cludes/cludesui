if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_HookIconWatch.lua
--
--  Per-spell icon watchers: ready sound, charge text, cooldown state effects,
--  Swiftmend brightness, custom icons and icon-art suppression.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._hookInternals
-- CludesUICdmHooks.lua or an earlier hook file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local barDataByKey = mod.barDataByKey
local _ecmeFC = mod._ecmeFC
local GetTime = GetTime

local _isDruid, GetViewerFrame, hookFrameData = Inner._isDruid, Inner.GetViewerFrame, Inner.hookFrameData
local IsCDMSettingsOpen, ResolveFrameSpellID = Inner.IsCDMSettingsOpen, Inner.ResolveFrameSpellID
local ResolveSpellSettings, CdmChargeInfoFor = Inner.ResolveSpellSettings, Inner.CdmChargeInfoFor

-------------------------------------------------------------------------------
--  Audio Effect on CD Ready -- per-spell (CD/utility bars only)
--  Plays a sound the moment a spell becomes ready. Edge-detected with an arm
--  flag (armed only while NOT ready, played + disarmed on the ready edge), so it
--  never fires on login (already ready -> never armed), on a GCD end, or per
--  render tick. The expiry edge comes from Blizzard's TriggerAvailableAlert (see
--  HookCdReadyAvailableAlert): the client sends NO event when a cooldown runs
--  out. Cooldown/charge events drive arming/readiness/resets via the
--  WatchCdReadySoundIfEnabled set -- NEVER the SetDesaturated visual hook, which
--  fires at repaint moments unrelated to the real cooldown where GetSpellCooldown
--  can report a transient isActive=true/isOnGCD=false race that false-armed
--  spells never on cooldown during button spam; reading isActive+isOnGCD AT the
--  event (state settled) avoids that. Charge readiness = GetSpellCharges()
--  .isActive == false (at max, same signal Max Stacks Glow uses); non-charge
--  readiness = not (GetSpellCooldown().isActive and not isOnGCD). No
--  duration/magnitude math (secret in protected instances) -- clean bools only.
-------------------------------------------------------------------------------
mod._cdReadySoundWatch = mod._cdReadySoundWatch or setmetatable({}, { __mode = "k" })

-- Loading-screen / login-settle gate shared by every CDM notification sound (CD-ready,
-- buff gain/loss, preset buff gain). Zone changes, flights and login re-render icons
-- and re-fire aura/charge alerts while the cooldown/charge/aura APIs report transient
-- states across the boundary, false-firing edges on spells/buffs that were mid-cooldown
-- or still present. Cheap: one boolean + one timestamp compare, consulted only on a
-- sound edge (never per tick). Edges landing while suppressed are dropped silently.
do
    local loadingActive = true -- suppressed until the first PLAYER_ENTERING_WORLD
    local settleUntil = 0
    local SETTLE_SECONDS = 2 -- brief window after a load for re-renders to settle

    function mod._cdmSoundSuppressed()
        return loadingActive or GetTime() < settleUntil
    end

    -- Full CDM rebuilds (spec/talent swaps, settings changes) re-render every
    -- icon while the cooldown/charge APIs are transient, so callers open the same
    -- settle window and the re-prime cannot false-arm a batch. Longest wins.
    function mod._cdmBumpSoundSettle(sec)
        local u = GetTime() + (sec or SETTLE_SECONDS)
        if u > settleUntil then
            settleUntil = u
        end
    end

    local gate = mod.TakeShell()
    gate:RegisterEvent("LOADING_SCREEN_ENABLED")
    gate:RegisterEvent("LOADING_SCREEN_DISABLED")
    gate:RegisterEvent("PLAYER_ENTERING_WORLD")
    gate:SetScript("OnEvent", function(_, evt)
        if evt == "LOADING_SCREEN_ENABLED" then
            loadingActive = true
        else
            -- World up: clear the flag, settle so the re-render cannot false-fire.
            loadingActive = false
            settleUntil = GetTime() + SETTLE_SECONDS
        end
    end)
end

-- Reject armed->ready spans shorter than this: a real cooldown arms the moment
-- the spell is used, so a sub-GCD arm can only be a transient misread (GCD tail
-- / charge race). Costs the sound on real cooldowns under ~1.6s (rare in CDM).
local CD_READY_MIN_ARM = 1.6

-- Both drivers (Blizzard's available alert and the event fallback) can land on
-- the same cooldown end a frame apart -- one shared throttle keeps that single.
local CD_READY_SOUND_GAP = 0.5

-- Is the spell READY now? Charge spells: only at MAX charges (recharge not
-- running). Non-charge: not on a real (non-GCD) cooldown. liveSid = resolved
-- override. strict: the GCD does NOT count as ready. ARMING wants the loose read
-- (a GCD must never arm a spell that was never on cooldown); FIRING must be
-- strict, because a CAST-TIME spell raises its cooldown only on cast SUCCESS and
-- until then GetSpellCooldown reports the GCD alone (isActive + isOnGCD) --
-- "ready" under the loose test, firing the armed sound at the moment of cast.
local function CdReadyIsReady(liveSpellId, strict)
    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSpellId)
    if chargeInfo ~= nil and (chargeInfo.maxCharges or 0) > 1 then
        return not chargeInfo.isActive
    end
    local cooldown = C_Spell.GetSpellCooldown(liveSpellId)
    if not cooldown then
        return true
    end
    if strict then
        -- Not ready while a REAL (non-GCD) cooldown runs. A filler GCD alone
        -- must NOT block the edge: the old "any active cooldown" strict test
        -- deferred the ready sound through continuous GCD spam until the
        -- player stopped casting entirely.
        if cooldown.isActive and not cooldown.isOnGCD then
            return false
        end
        -- The one GCD-only state that is NOT ready: this spell's own hard cast
        -- in flight (a cast-time spell raises its cooldown only on cast
        -- SUCCESS). Exact identity check; a secret cast id fails toward
        -- suppress -- the armed state survives and the next event retries.
        if UnitCastingInfo then
            local castSid = select(9, UnitCastingInfo("player"))
            if castSid and ((issecretvalue and issecretvalue(castSid)) or castSid == liveSpellId) then
                return false
            end
        end
        return true
    end
    return not (cooldown.isActive and not cooldown.isOnGCD)
end

-- Charge spells keep their own ready edge (refill to MAX, off
-- SPELL_UPDATE_CHARGES). Blizzard's available alert fires when the FIRST
-- charge returns -- a different edge -- so the alert driver skips them.
local function CdReadyIsChargeSpell(liveSpellId)
    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSpellId)
    return chargeInfo ~= nil and (chargeInfo.maxCharges or 0) > 1
end

-- Single play point for both drivers: throttled, always disarms.
local function PlayCdReadySound(frameData, key, liveSpellId, spellRef, bk, source)
    frameData._cdReadyArmed = false
    local nowTime = GetTime()
    local last = frameData._cdReadySoundAt
    if last and (nowTime - last) < CD_READY_SOUND_GAP then
        return
    end
    frameData._cdReadySoundAt = nowTime
    local filePath = mod.FOCUSKICK_SOUND_PATHS and mod.FOCUSKICK_SOUND_PATHS[key]
    if filePath then
        PlaySoundFile(filePath, "Master")
    end
end

-- Shared evaluator (SPELL_UPDATE_COOLDOWN + SPELL_UPDATE_CHARGES via the
-- WatchCdReadySoundIfEnabled set). Arms while not ready, plays + disarms on the
-- ready edge, deferred one frame and re-confirmed so a charge/GCD-tail race
-- cannot false-fire. Zero-cost on the feature flag. primeOnly: arm state only.
local function EvalCdReadySound(widget, frameData, primeOnly)
    if not mod._cdmAnyCdReadySound then
        return
    end
    if not frameData then
        return
    end
    if frameData._isProcessingOverride then
        return
    end
    -- Buff-family frames never play (see WatchCdReadySoundIfEnabled); held here too so
    -- a frame watched before its decoration flagged it stays silent.
    if frameData._isBuffViewerFrame or widget._isCustomBuffFrame or widget._isPlaceholderFrame then
        frameData._cdReadyArmed = false
        return
    end
    local fc2 = _ecmeFC[widget]
    -- Hidden by its Talent Conditions (TalentCondFilterPass): stays silent.
    if fc2 and fc2.tcHidden then
        frameData._cdReadyArmed = false
        return
    end
    local sid2 = fc2 and fc2.spellID
    local bk2 = fc2 and fc2.barKey
    if not sid2 or not bk2 then
        return
    end
    if bk2 == mod.FOCUSKICK_BAR_KEY then
        return
    end
    if bk2:sub(1, 7) == "__ghost" then
        return
    end
    local ss2 = ResolveSpellSettings(widget, sid2, mod.GetBarSpellData(bk2))
    local key = ss2 and ss2.cdReadySoundKey
    if not key or key == "none" then
        frameData._cdReadyArmed = false
        return
    end
    if mod._cdmSoundSuppressed() then
        -- Settle window: cooldown reads are transient, so gate the ARM (not just
        -- the fire) and clear stale arms. A spell genuinely on cooldown re-arms
        -- on the next SPELL_UPDATE_COOLDOWN after the window: no edge lost.
        frameData._cdReadyArmed = false
        return
    end
    local liveSpellId = sid2
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSpellId = C_SpellBook.FindSpellOverrideByID(sid2) or sid2
    end
    if not CdReadyIsReady(liveSpellId) then
        -- On cooldown (or a charge spell below max): arm.
        if not frameData._cdReadyArmed then
            frameData._cdReadyArmedAt = GetTime()
        end
        frameData._cdReadyArmed = true
        frameData._cdReadyArmedSid = sid2
    elseif frameData._cdReadyArmed and not primeOnly and CdReadyIsReady(liveSpellId, true) then
        if frameData._cdReadyArmedSid ~= sid2 then
            -- Spell on this frame changed since arming (spec/talent swap); stale arm.
            frameData._cdReadyArmed = false
            return
        end
        -- Became ready. Confirm one frame later (let the API settle) before playing.
        if not frameData._cdReadyPending then
            frameData._cdReadyPending = CreateFrame("Frame")
            frameData._cdReadyPending:Hide()
            frameData._cdReadyPending:SetScript("OnUpdate", function(self)
                self:Hide()
                if not frameData._cdReadyArmed then
                    return
                end
                local fcp = _ecmeFC[widget]
                local sidp = fcp and fcp.spellID
                local bkp = fcp and fcp.barKey
                if not sidp or not bkp then
                    return
                end
                if frameData._cdReadyArmedSid ~= sidp then
                    frameData._cdReadyArmed = false
                    return
                end
                local ssp = ResolveSpellSettings(widget, sidp, mod.GetBarSpellData(bkp))
                local kp = ssp and ssp.cdReadySoundKey
                if not kp or kp == "none" then
                    frameData._cdReadyArmed = false
                    return
                end
                local livep = sidp
                if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                    livep = C_SpellBook.FindSpellOverrideByID(sidp) or sidp
                end
                if not CdReadyIsReady(livep, true) then
                    return
                end -- not ready (race/GCD) -> stay armed
                if mod._cdmSoundSuppressed() then
                    frameData._cdReadyArmed = false
                    return
                end -- a load began mid-defer
                -- Sub-GCD arm span = transient misread, not a real cooldown ending.
                local armedAt = frameData._cdReadyArmedAt
                if not armedAt or (GetTime() - armedAt) < CD_READY_MIN_ARM then
                    frameData._cdReadyArmed = false
                    return
                end
                PlayCdReadySound(frameData, kp, livep, sidp, bkp, "event")
            end)
        end
        frameData._cdReadyPending:Show()
    end
end

-- PRIMARY driver for non-charge spells: Blizzard's "cooldown just became
-- available" edge. The client dispatches NO event on cooldown expiry;
-- TriggerAvailableAlert simulates the final SPELL_UPDATE_COOLDOWN from the
-- viewer's OnUpdate against the real endTime (riding SPELL_UPDATE_COOLDOWN alone
-- never sees the expiry). Post-hooking the alert is the same taint-safe idiom as
-- EnsureBuffSoundHook on TriggerAuraAppliedAlert: no secret duration read, lands
-- on the exact frame. Charge spells stay with the SPELL_UPDATE_CHARGES watcher:
-- this alert fires on the FIRST charge, but CDM readiness means back at MAX.
local _cdReadyAlertHooked = setmetatable({}, { __mode = "k" })
local function HookCdReadyAvailableAlert(widget, frameData)
    if _cdReadyAlertHooked[widget] then
        return
    end
    if type(widget.TriggerAvailableAlert) ~= "function" then
        _cdReadyAlertHooked[widget] = true -- own placeholder / injected frame: no alert
        return
    end
    _cdReadyAlertHooked[widget] = true
    hooksecurefunc(widget, "TriggerAvailableAlert", function(frame)
        if not mod._cdmAnyCdReadySound then
            return
        end
        if frameData._isProcessingOverride then
            return
        end
        -- A buff frame's alert fires on AURA gain, not readiness (see the watch below).
        if frameData._isBuffViewerFrame or frame._isCustomBuffFrame or frame._isPlaceholderFrame then
            return
        end
        local fca = _ecmeFC[frame]
        local sida = fca and fca.spellID
        local bka = fca and fca.barKey
        if not sida or not bka then
            return
        end
        if fca.tcHidden then
            return
        end -- hidden by its Talent Conditions
        if bka == mod.FOCUSKICK_BAR_KEY then
            return
        end
        if bka:sub(1, 7) == "__ghost" then
            return
        end
        local ssa = ResolveSpellSettings(frame, sida, mod.GetBarSpellData(bka))
        local keya = ssa and ssa.cdReadySoundKey
        if not keya or keya == "none" then
            return
        end
        if mod._cdmSoundSuppressed() then
            frameData._cdReadyArmed = false
            return
        end
        local livea = sida
        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            livea = C_SpellBook.FindSpellOverrideByID(sida) or sida
        end
        if CdReadyIsChargeSpell(livea) then
            return
        end
        PlayCdReadySound(frameData, keya, livea, sida, bka, "alert")
    end)
end

-- Register a spell with a CD-ready sound into the event-driven watch set,
-- evaluated on SPELL_UPDATE_COOLDOWN + SPELL_UPDATE_CHARGES (refill to max),
-- reading isActive/isOnGCD once state settles: covers arming, charge readiness
-- and cooldown RESETS. The expiry edge belongs to the available-alert hook above
-- (this pass backs it up between GCDs); there is NO SetDesaturated driver.
function mod.WatchCdReadySoundIfEnabled(widget)
    if not widget then
        return
    end
    local frameData = hookFrameData[widget]
    if not frameData then
        return
    end
    -- Buff-family frames never watch: a hosted or custom buff frame resolves the
    -- ABILITY's per-spell entry through the linked-id union, and its
    -- TriggerAvailableAlert fires on aura gain (no readiness check in the hook), so
    -- the cd-ready cue played at buff gain. Same exclusion as the charge hooks.
    if frameData._isBuffViewerFrame or widget._isCustomBuffFrame or widget._isPlaceholderFrame then
        if mod._cdReadySoundWatch[widget] then
            mod._cdReadySoundWatch[widget] = nil
        end
        return
    end
    local fcw = _ecmeFC[widget]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not (sidw and bkw) then
        return
    end
    local ssw = ResolveSpellSettings(widget, sidw, mod.GetBarSpellData(bkw))
    if ssw and ssw.cdReadySoundKey and ssw.cdReadySoundKey ~= "none" then
        mod._cdmAnyCdReadySound = true
        mod._cdReadySoundWatch[widget] = frameData
        if not mod._cdReadySoundEventFrame then
            local ef = mod.TakeShell()
            ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            ef:RegisterEvent("SPELL_UPDATE_CHARGES")
            ef:SetScript("OnEvent", function()
                for frame, skinData in pairs(mod._cdReadySoundWatch) do
                    EvalCdReadySound(frame, skinData)
                end
            end)
            mod._cdReadySoundEventFrame = ef
        end
        HookCdReadyAvailableAlert(widget, frameData)
        EvalCdReadySound(widget, frameData, true) -- prime the arm state only; never plays here
    elseif mod._cdReadySoundWatch[widget] then
        mod._cdReadySoundWatch[widget] = nil
    end
end

-------------------------------------------------------------------------------
--  Hide CD Text (Charges) -- per-spell (CD/utility bars only)
--  While a CHARGE spell has a usable charge in hand, hide the recharge countdown
--  numbers; they return once every charge is spent (0 charges == on a real
--  cooldown), so the full countdown shows when unavailable. "charges > 0"
--  derives from CLEAN GetSpellCooldown() flags: charge in hand <=> not
--  (isActive and not isOnGCD) -- isActive alone is wrong (true during the GCD
--  right after a cast even with a charge left). Charge-spell test:
--  GetSpellCharges().maxCharges > 1 (stable through the GCD), never
--  HasVisualDataSource_Charges (flips false during a GCD swipe); neither reads
--  the secret currentCharges. Driven by SPELL_UPDATE_CHARGES (same as Max Stacks
--  Glow), catching the topping-off edge the cooldown-widget hooks miss. Gated on
--  ns._cdmAnyChargeHideCdText (~0 cost when unused).
-------------------------------------------------------------------------------

-- Per-spell Duration Text layered onto a bar-derived hide flag, for the paths that hold only
-- barData: the reanchor assign loop and the Only Show Numbers restore tail. The appearance
-- pass does not call this -- it resolves ssb itself, and re-resolving there would replace a
-- correct value with a worse one. Keyed on the DISPLAYED id, never fc.spellID: for a buff
-- whose base is a shared spec spell the base misses the entry and lets one icon's setting
-- shadow another's, the same rule the appearance pass documents at its own resolve.
-- ~= nil, not truthiness: a per-spell ON must beat a bar that is OFF.
function mod.CdmDurationHideFor(widget, barId, hideBase)
    if not mod._cdmAnySpellDurationText then
        return hideBase
    end
    local fcd = _ecmeFC[widget]
    local sidD = (mod.GetCanonicalSpellIDForFrame and mod.GetCanonicalSpellIDForFrame(widget))
        or (fcd and fcd.spellID)
    if not (sidD and barId and mod.ResolveSpellSettings) then
        return hideBase
    end
    local ssD = mod.ResolveSpellSettings(widget, sidD, mod.GetBarSpellData(barId), barId)
    if ssD and ssD.showCooldownText ~= nil then
        return not ssD.showCooldownText
    end
    return hideBase
end

-- Effective SetHideCountdownNumbers value: layers the per-spell "Hide CD Text
-- (Charges)" toggle on the caller's baseHide (numbers already hidden by the bar
-- / per-icon showCooldownText). Returns baseHide unchanged for anything that is
-- not an enabled charge spell, so callers can wrap unconditionally.
function mod.CdmShouldHideCountdown(widget, hideBase)
    -- Charges/Stacks Only (No Icon) hides the duration outright (the counter is the
    -- whole display). Checked AHEAD of the feature gate so it holds for every caller --
    -- the appearance pass, reanchor loop and SPELL_UPDATE_CHARGES watcher all route
    -- countdown writes through here, so no per-site force is needed. (Only Show Numbers
    -- never sets the flag: there the number IS the display.)
    local fdc = hookFrameData[widget]
    if fdc and fdc._osnHideText then
        return true
    end
    if not mod._cdmAnyChargeHideCdText then
        return hideBase
    end
    if hideBase then
        return true
    end -- already hidden by the bar/per-icon setting
    local ss = mod._ResolveCdmSS(widget)
    if not (ss and ss.chargeHideCdText) then
        return hideBase
    end
    local fc = _ecmeFC[widget]
    local spellRef = fc and fc.spellID
    if not spellRef then
        return hideBase
    end
    local liveSpellId = spellRef
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSpellId = C_SpellBook.FindSpellOverrideByID(spellRef) or spellRef
    end
    -- Charge-spell test via static charge data (stable through the GCD).
    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSpellId)
    if not (chargeInfo and (chargeInfo.maxCharges or 0) > 1) then
        return hideBase
    end
    -- "charges > 0" <=> NOT on a real (non-GCD) cooldown; the isOnGCD term is
    -- required (isActive alone is true through every post-cast GCD). Both flags
    -- clean; the secret currentCharges is never read.
    local cdInfo = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(liveSpellId)
    if not cdInfo then
        return hideBase
    end
    local onRealCd = cdInfo.isActive and not cdInfo.isOnGCD
    if not onRealCd then
        return true
    end -- at least one charge -> hide duration
    return hideBase
end

-- Only icons with the toggle enabled live in this set, so each SPELL_UPDATE_CHARGES
-- iterates a tiny table; the event frame is created lazily on first watch.
mod._chargeCdTextWatch = mod._chargeCdTextWatch or setmetatable({}, { __mode = "k" })

-- Re-apply the countdown-number visibility for one watched charge frame from the
-- current charge state. Self-unwatches when the setting is off or the frame lost
-- its spell, so the set drains itself (mirrors EvalMaxStacksFrame).
local function EvalChargeCdTextFrame(widget, frameData)
    local fcw = _ecmeFC[widget]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    local cooldown = (frameData and frameData.cooldown) or widget.Cooldown
    if not sidw or not bkw or not cooldown or not cooldown.SetHideCountdownNumbers then
        mod._chargeCdTextWatch[widget] = nil
        return
    end
    local edge = barDataByKey and barDataByKey[bkw]
    local hideBase = not mod.CdmDurationTextOn(edge)
    local ssw = ResolveSpellSettings(widget, sidw, mod.GetBarSpellData(bkw))
    if not (ssw and ssw.chargeHideCdText) then
        -- Setting off: restore the bar's showCooldownText result and unwatch
        -- (per-icon showCooldownText exists only on buff bars, which never
        -- enable this charge toggle, so the bar value is right).
        mod._chargeCdTextWatch[widget] = nil
        -- Through the resolver, not raw: returns baseHide unchanged but still
        -- honours Charges/Stacks Only, so no duration flash on a no-icon bar.
        cooldown:SetHideCountdownNumbers(mod.CdmShouldHideCountdown(widget, hideBase))
        return
    end
    cooldown:SetHideCountdownNumbers(mod.CdmShouldHideCountdown(widget, hideBase))
end

local function WatchChargeCdTextFrame(widget, frameData)
    mod._chargeCdTextWatch[widget] = frameData
    if not mod._chargeCdTextEventFrame then
        local ef = mod.TakeShell()
        ef:RegisterEvent("SPELL_UPDATE_CHARGES")
        ef:SetScript("OnEvent", function()
            for frame, skinData in pairs(mod._chargeCdTextWatch) do
                EvalChargeCdTextFrame(frame, skinData)
            end
        end)
        mod._chargeCdTextEventFrame = ef
    end
end

-- Called from RefreshCDMIconAppearance (login + settings changes) so a charge
-- spell at max (no recharge text, never fires the swipe hook) still gets watched
-- for the moment it dips below max. Early-outs on non-charge icons; once watched
-- SPELL_UPDATE_CHARGES keeps it current. Self-cleans when the setting is off.
function mod.WatchChargeCdTextIfEnabled(widget)
    if not widget then
        return
    end
    local frameData = hookFrameData[widget]
    if not frameData then
        return
    end
    local fcw = _ecmeFC[widget]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not (sidw and bkw) then
        return
    end
    local liveSpellId = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSpellId = C_SpellBook.FindSpellOverrideByID(sidw) or sidw
    end
    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSpellId)
    local isCharge = chargeInfo ~= nil and (chargeInfo.maxCharges or 0) > 1
    local ssw = isCharge and ResolveSpellSettings(widget, sidw, mod.GetBarSpellData(bkw)) or nil
    if ssw and ssw.chargeHideCdText then
        mod._cdmAnyChargeHideCdText = true
        WatchChargeCdTextFrame(widget, frameData)
        EvalChargeCdTextFrame(widget, frameData)
    elseif mod._chargeCdTextWatch[widget] then
        mod._chargeCdTextWatch[widget] = nil
        EvalChargeCdTextFrame(widget, frameData)
    end
end

-------------------------------------------------------------------------------
--  "Hide Text at 0 Stacks" (bar-level, cd/utility bars): hide the charge counter
--  (frame.ChargeCount.Current) while a charge spell is genuinely OUT of charges
--  instead of showing a 0. The count IS the alpha: SetAlpha clamps to [0,1]
--  engine-side, so alpha := currentCharges hides at exactly 0 and shows at 1+
--  with no comparison, and SetAlpha accepts secret numbers (SecretArguments
--  AllowedWhenTainted), so the same write runs in and out of instanced combat
--  (secret count written through, memo dirtied, never stored/compared). The
--  clean-flag inference "real non-GCD cooldown = zero charges" is NOT universal
--  -- Roll-class wiring and talent-granted charges on cooldown spells like Feint
--  / Survival of the Fittest keep the main cooldown record active while charges
--  are banked -- so it's unused here; CdmShouldHideCountdown still uses it,
--  harmlessly showing the duration where it could hide it. Driven by the same
--  SPELL_UPDATE_CHARGES edge as the other charge features (lazy shell, self-
--  draining watch set, zero cost for non-users). Alpha not Hide: the engine
--  rewrites the counter's TEXT on charge changes but never its alpha.
-------------------------------------------------------------------------------
mod._zeroChargeTextWatch = mod._zeroChargeTextWatch or setmetatable({}, { __mode = "k" })

-- Paint-the-delta memo: SetAlpha only on a real change. The engine rewrites the
-- counter's TEXT but never its alpha, so the stamp stays truthful.
local function ZctSetAlpha(frameData, fontStr, a)
    if frameData._zctAlpha ~= a then
        frameData._zctAlpha = a
        fontStr:SetAlpha(a)
    end
end

local function EvalZeroChargeTextFrame(widget, frameData)
    local fontStr = widget.ChargeCount and widget.ChargeCount.Current
    local fcz = _ecmeFC[widget]
    local sidz = fcz and fcz.spellID
    local bkz = fcz and fcz.barKey
    if not fontStr or not sidz or not bkz then
        mod._zeroChargeTextWatch[widget] = nil
        if fontStr then
            ZctSetAlpha(frameData, fontStr, 1)
        end
        return
    end
    -- Per-spell "Hide Charge Text" (cd-state menu): a STATIC hide riding this
    -- feature's alpha channel and memo, so the two can never fight over the
    -- counter. It outranks the zero-charge logic; charge events land here and
    -- simply keep the 0.
    local sss = mod._ResolveCdmSS and mod._ResolveCdmSS(widget)
    if sss and sss.hideChargeText then
        ZctSetAlpha(frameData, fontStr, 0)
        return
    end
    local edge = barDataByKey and barDataByKey[bkz]
    if not (edge and edge.hideZeroChargeText) then
        mod._zeroChargeTextWatch[widget] = nil
        ZctSetAlpha(frameData, fontStr, 1)
        return
    end
    local liveSpellId = sidz
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSpellId = C_SpellBook.FindSpellOverrideByID(sidz) or sidz
    end
    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSpellId)
    if not (chargeInfo and (chargeInfo.maxCharges or 0) > 1) then
        -- Not a charge spell (talent changed since enrollment): restore and
        -- unwatch; the appearance pass re-enrolls if charge-ness returns, which
        -- keeps the per-event set charge-spells-only.
        mod._zeroChargeTextWatch[widget] = nil
        ZctSetAlpha(frameData, fontStr, 1)
        return
    end
    -- Alpha := currentCharges (see header). Secret count: same write, memo dirtied.
    local cc = chargeInfo.currentCharges
    -- issecretvalue FIRST, and type() rather than == nil for the missing case.
    -- currentCharges is secret whenever cooldowns are restricted (combat,
    -- encounter, challenge mode, PvP match), and comparing a secret to nil is
    -- the exact operation this addon's own secret rules forbid. Ordering the
    -- nil "belt" ahead of the guard made the belt the hazard: a throw here
    -- aborts the eval with the alpha still 0, so the counter stays HIDDEN until
    -- the next SPELL_UPDATE_CHARGES -- which for a charge spell that just
    -- refilled is a whole recharge away. That is the reported "0 -> 1 hides the
    -- stack count temporarily". The throw also kills the pairs() loop in the
    -- event handler, so every other watched icon stops updating with it.
    if issecretvalue and issecretvalue(cc) then
        frameData._zctAlpha = nil
        fontStr:SetAlpha(cc)
    elseif type(cc) ~= "number" then
        ZctSetAlpha(frameData, fontStr, 1)
    else
        ZctSetAlpha(frameData, fontStr, cc > 1 and 1 or cc)
    end
end

function mod.WatchZeroChargeTextIfEnabled(widget)
    if not widget then
        return
    end
    local frameData = hookFrameData[widget]
    if not frameData then
        return
    end
    local fcz = _ecmeFC[widget]
    local sidz = fcz and fcz.spellID
    local bkz = fcz and fcz.barKey
    -- Per-spell "Hide Charge Text": static, so this appearance-pass call is
    -- its whole driver -- no event watch needed. A frame the bar feature has
    -- watched keeps its enrollment; the eval's own short-circuit holds the 0.
    if sidz and bkz then
        local sss = mod._ResolveCdmSS and mod._ResolveCdmSS(widget)
        if sss and sss.hideChargeText then
            local fsh = widget.ChargeCount and widget.ChargeCount.Current
            if fsh then
                ZctSetAlpha(frameData, fsh, 0)
            end
            return
        end
    end
    local edge = bkz and barDataByKey and barDataByKey[bkz]
    if edge and edge.hideZeroChargeText and sidz then
        -- Enroll CHARGE SPELLS ONLY: non-charge icons would be pure identity
        -- work per event. Talent swaps re-run this via the appearance pass; the
        -- eval self-unwatches the other direction.
        local liveSpellId = sidz
        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            liveSpellId = C_SpellBook.FindSpellOverrideByID(sidz) or sidz
        end
        local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSpellId)
        if not (chargeInfo and (chargeInfo.maxCharges or 0) > 1) then
            if mod._zeroChargeTextWatch[widget] then
                EvalZeroChargeTextFrame(widget, frameData)
            end
            return
        end
        if not mod._zeroChargeTextEventFrame then
            local ef = mod.TakeShell()
            ef:RegisterEvent("SPELL_UPDATE_CHARGES")
            ef:SetScript("OnEvent", function()
                for frame, skinData in pairs(mod._zeroChargeTextWatch) do
                    EvalZeroChargeTextFrame(frame, skinData)
                end
            end)
            mod._zeroChargeTextEventFrame = ef
        end
        mod._zeroChargeTextWatch[widget] = frameData
        EvalZeroChargeTextFrame(widget, frameData)
    elseif mod._zeroChargeTextWatch[widget] then
        -- Setting off: the eval's off-branch unwatches + restores alpha.
        EvalZeroChargeTextFrame(widget, frameData)
    else
        -- Hide Charge Text just turned off with no watch left to restore for
        -- it: put the counter back. Memoized, so a neither-feature icon pays
        -- one SetAlpha(1) ever.
        local fsr = widget.ChargeCount and widget.ChargeCount.Current
        if fsr then
            ZctSetAlpha(frameData, fsr, 1)
        end
    end
end

-------------------------------------------------------------------------------
--  Charge counter on SPELL_UPDATE_CHARGES. Blizzard_CooldownViewer does not
--  register the event, so a proc that hands charges to a chargeless spell
--  reaches the icon only at its next RefreshData, seconds later. Mirrors
--  RefreshSpellChargeInfo's charge branch (maxCharges > 1, NeverSecret) from
--  the frame's own GetSpellChargeInfo; SetText takes a secret count. Not
--  routed through RefreshSpellChargeInfo: SetCachedChargeValues compares
--  currentCharges, secret while cooldowns are restricted. Show() is
--  unconditional because the counter's shown aspect is secret once Blizzard
--  set it from a secret cast count. Frames this wrote are hidden again when
--  maxCharges drops back; the rest stays with Blizzard. No payload.
-------------------------------------------------------------------------------
do
    local wrote = setmetatable({}, { __mode = "k" })

    local function WriteChargeCount(widget)
        local cc = widget.ChargeCount
        local fontStr = cc and cc.Current
        if not fontStr then
            return
        end
        local chargeInfo = CdmChargeInfoFor(widget, nil)
        if chargeInfo and (chargeInfo.maxCharges or 0) > 1 then
            fontStr:SetText(chargeInfo.currentCharges)
            cc:Show()
            wrote[widget] = true
        elseif wrote[widget] then
            wrote[widget] = nil
            cc:Hide()
        end
    end

    local ef = mod.TakeShell()
    ef:RegisterEvent("SPELL_UPDATE_CHARGES")
    ef:SetScript("OnEvent", function()
        if IsCDMSettingsOpen() then
            return
        end
        for vi = 1, 2 do
            local viewer = GetViewerFrame(vi)
            local pool = viewer and viewer.itemFramePool
            if pool and pool.EnumerateActive then
                for widget in pool:EnumerateActive() do
                    WriteChargeCount(widget)
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Cooldown State Effect -- charge-aware readiness for Hidden (CD Ready)
--  For a CHARGE spell "CD Ready" must mean AT MAX CHARGES, not "a charge in
--  hand": GetSpellCooldown().isActive is false with a charge left, so a plain
--  read calls a recharging spell "ready" and the icon vanishes mid-recharge --
--  exactly the countdown this mode exists to watch. Read the recharge flag
--  instead (GetSpellCharges().isActive: true from the first spent charge until
--  the last refills, the clean Max Stacks Glow signal); maxCharges > 1 is the
--  charge-spell test (stable through the GCD, unlike HasVisualDataSource_Charges);
--  non-charge spells keep the caller's cooldown read. Secret currentCharges
--  never read. Per-spell "+ Stay Hidden While Charges Remain"
--  (ss.chargeHideUntilSpent) opts back into "hidden only once fully spent".
--  Deliberately NOT used by other cd-state effects: those answer "can I press
--  this?" (Hidden/Lower Alpha On CD suppress the uncastable, ready-glows
--  highlight the castable) and a charge spell down one stack IS castable --
--  Hidden (CD Ready) is the only mode tracking the countdown.
-------------------------------------------------------------------------------
-- Real cooldown (not the global cooldown) from a GetSpellCooldown read taken
-- outside the SPELL_UPDATE_COOLDOWN response, where Blizzard's API notes say
-- the GCD flag cannot be trusted: as a GCD swipe ends, Blizzard's
-- OnCooldownDone repaints the icon while the lockout can still read active
-- with that flag already clear. Blizzard's viewer keeps the GCD flag it read
-- at its last refresh on the item (frame.isOnGCD, copied from the same
-- never-secret field), and OnCooldownDone only repaints, so a GCD it saw stays
-- a GCD here. The flag counts only while frame.wasSetFromCooldown says the
-- spell's cooldown drew the item: Blizzard skips the write otherwise (charges,
-- suppressed cooldown categories) and leaves an old value behind. Our own
-- frames carry neither field, so the live read alone decides there.
function mod.CdmOnRealCD(widget, details)
    if not (details and details.isActive) or details.isOnGCD then
        return false
    end
    return not (widget and widget.wasSetFromCooldown == true and widget.isOnGCD == true)
end

function mod.CdmCdStateReady(liveSpellId, onCooldown, hideUntilSpent)
    if hideUntilSpent then
        return not onCooldown
    end
    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSpellId)
    if chargeInfo and (chargeInfo.maxCharges or 0) > 1 then
        return not chargeInfo.isActive
    end
    return not onCooldown
end

-- Hidden Until Usable: the spell counts as unavailable while it cannot be used
-- for any reason but missing power, so a reactive spell (Overpower, Victory
-- Rush, Execute) shows once its proc or condition is up, tinted by Blizzard
-- while rage / energy / mana is short, and power ticks never flip the answer.
-- IsSpellUsable returns plain booleans on every client.
function mod.CdmSpellNotUsable(liveSpellId)
    local isUsable, noPower = C_Spell.IsSpellUsable(liveSpellId)
    return not (isUsable or noPower)
end

-- Hidden Outside Form/Stance: the spell's form requirement line, which Blizzard
-- draws red while the current form or stance does not meet it. That answer
-- changes only with the form, so it is kept per spell and form ID: once a pair
-- is read, a form change costs a table lookup. A spell whose tooltip names no
-- form is outside its form while shapeshifted when the game says it cannot be
-- cast now for a reason other than power, asked live, provided it could be
-- cast when last seen in caster form: a warrior (never in caster form) and a
-- spell waiting on a proc never hide this way. A druid caster spell reads
-- usable in a form, since casting it drops the form, so a rule per spell
-- (CasterRule) decides it instead: the forms it cannot be cast in, and the
-- talents and auras that permit it there. A pair whose tooltip cannot be
-- read (not loaded yet, or secret in combat) is decided by the spell's rule,
-- or shows its icon when there is none, and is read again only at the next
-- form change or combat end (ns.CdmRetryUnreadForms), never per evaluation;
-- a talent change clears the table (ScheduleTalentRebuild).
do
    local outside = {} -- [spellID][formID] -> true (red form line), false (met), NO_LINE or UNREAD
    local casterOK = {} -- [spellID] -> castable (power aside) when last seen in caster form
    local procSeen = {} -- [spellID] -> its rule's answer when last evaluated in a form the rule covers
    local UNREAD, NO_LINE = "unread", "noline"
    local unreadN = 0
    -- Read nil-safe: a client without these enums falls back to the text path
    local LINE_TYPES = Enum.TooltipDataLineType or {}
    local REQ_TYPES = Enum.TooltipDataUsageRequirementType or {}
    local LINE_REQ, LINE_NONE, REQ_FORM =
        LINE_TYPES.UsageRequirement, LINE_TYPES.None, REQ_TYPES.ShapeshiftForm
    local TEMPLATES = { SPELL_REQUIRED_FORM, SPELL_REQUIRED_FORM_NOSPACE }
    local formNames, formCount -- the player's form names, read when the count changes
    local casterRules, procAuras -- built on a druid's first ask (CasterRule)
    local known, exists = {}, {} -- [spellID] -> IsSpellKnown / DoesSpellExist answer, or UNREAD
    local auraState = {} -- [aura] -> on the player; read once per change (ProcActive)
    -- [auraInstanceID] -> exception aura, recorded when one is seen on the
    -- player. Kept past its removal (instance IDs are not reused) until the
    -- next form change or combat end, so every caller probing that UNIT_AURA
    -- sees the removal.
    local procIIDs = {}
    local blindBy = {} -- [caller] -> its icons already show the answer for unreadable auras

    -- Tooltip data can come back as secret tables, and indexing one throws
    local function Readable(t)
        return not issecretvalue(t) and type(t) == "table" and (not canaccesstable or canaccesstable(t))
    end

    -- A druid caster spell's rule (nil for other spells and classes). forms:
    -- the forms it cannot be cast in. talents / formTalents[form]: known
    -- spells that permit it in all of them / in that form. procs: [aura] =
    -- the talent that grants the aura, or false for an item or set bonus
    -- (counted while the client has the aura); while one is up the spell is
    -- permitted. Each client lists its own spell IDs.
    local function CasterRule(spellRef)
        if not _isDruid then
            return nil
        end
        if not casterRules then
            local function Forms(...)
                local set = {}
                for index = 1, select("#", ...) do
                    set[select(index, ...)] = true
                end
                return set
            end
            local function Add(activeRule, ids)
                for index = 1, #ids do
                    casterRules[ids[index]] = activeRule
                end
            end
            -- Form IDs (GetShapeshiftFormID): Dire Bear is WoW Forever's, and
            -- Moonkin Form is 31 for Balance, 35 from the class talents.
            local CAT, TRAVEL, AQUATIC, BEAR, DIRE_BEAR = 1, 3, 4, 5, 8
            local SWIFT_FLIGHT, FLIGHT, MOONKIN, MOONKIN_CLASS = 27, 29, 31, 35
            local beasts = Forms(CAT, TRAVEL, AQUATIC, BEAR, DIRE_BEAR, SWIFT_FLIGHT, FLIGHT)
            local heal = {
                forms = Forms(
                    CAT,
                    TRAVEL,
                    AQUATIC,
                    BEAR,
                    DIRE_BEAR,
                    SWIFT_FLIGHT,
                    FLIGHT,
                    MOONKIN,
                    MOONKIN_CLASS
                ),
            }
            local caster = { forms = beasts } -- castable in Moonkin Form
            casterRules = {}
            if CludesUI.IS_FOREVER == true then
                -- No talent permits these in a form; set bonuses and an item do
                Add(heal, { 740, 8918, 9862, 9863 }) -- Tranquility
                Add(heal, { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 }) -- Rejuvenation
                Add(heal, { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 }) -- Regrowth
                Add(heal, { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 }) -- Healing Touch
                Add(heal, { 18562, 17116, 408124, 408247 }) -- Swiftmend, Nature's Swiftness, Lifebloom, Nourish
                Add(caster, { 339, 1062, 5195, 5196, 9852, 9853 }) -- Entangling Roots
                Add(caster, { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 }) -- Moonfire
                Add(caster, { 5570, 24974, 24975, 24976, 24977 }) -- Insect Swarm
                Add(caster, { 437138, 1237948, 1237949, 1237950, 1237951 }) -- Revive
                Add(caster, { 2782, 2893, 8946 }) -- Remove Curse, Abolish Poison, Cure Poison
                Add(caster, { 18960, 417148 }) -- Teleport: Moonglade, Efflorescence
                local mark = CludesUI.FOREVER_BUFF_FAMILIES.mark
                Add(caster, mark.single) -- Mark of the Wild
                Add(caster, mark.group) -- Gift of the Wild
                -- 456325 T1 Guardian 2P, 1232896 Staff of the Glade, 1301005 T1
                -- Guardian 3P, 467206 T2 Restoration 6P (in Moonkin Form)
                casterRules[29166] = { forms = beasts, procs = { [456325] = false, [1232896] = false } } -- Innervate
                Add(
                    { forms = beasts, procs = { [456325] = false, [1232896] = false, [1301005] = false } },
                    { 20484, 20739, 20742, 20747, 20748 }
                ) -- Rebirth
                Add({ forms = heal.forms, procs = { [467206] = false } }, { 408120, 1238214, 1238215 }) -- Wild Growth
            else
                -- Spec passives: Feline Adept (Feral) in Cat, Ursine Adept (Guardian) in Bear
                local FELINE_ADEPT, URSINE_ADEPT = 300349, 300346
                local SWIFTNESS = 132158 -- Nature's Swiftness: the talent and its aura
                Add(heal, { 740, 774, 18562, 33763, 48438 }) -- Tranquility, Rejuvenation, Swiftmend, Lifebloom, Wild Growth
                Add(heal, { 145205, 102342 }) -- Efflorescence, Ironbark
                Add(caster, { 18960, 193753, 473909, 474750 }) -- Teleport: Moonglade, Dreamwalk, Ancient of Lore, Symbiotic Relationship
                Add(
                    { forms = Forms(CAT, TRAVEL, AQUATIC, BEAR, SWIFT_FLIGHT, FLIGHT, MOONKIN) },
                    { 50769, 212040 }
                ) -- Revive, Revitalize
                Add(
                    { forms = beasts, formTalents = { [CAT] = { FELINE_ADEPT }, [BEAR] = { URSINE_ADEPT } } },
                    { 2782, 440015, 88423, 29166 }
                ) -- Remove Corruption (both), Nature's Cure, Innervate
                -- 69369 Predatory Swiftness (talent 16974), 372152 Dream of Cenarius (talent 372119).
                -- overlay: Predatory Swiftness lights the spell, so while the auras
                -- cannot be read (combat) its proc highlight decides (CasterOutside).
                casterRules[8936] = {
                    forms = beasts,
                    overlay = true,
                    procs = { [SWIFTNESS] = SWIFTNESS, [69369] = 16974, [372152] = 372119 },
                } -- Regrowth
                casterRules[339] = {
                    forms = beasts,
                    talents = { 202226 },
                    overlay = true,
                    procs = { [SWIFTNESS] = SWIFTNESS, [69369] = 16974 },
                } -- Entangling Roots; 202226 Entangling Claws
                -- Lunar Inspiration (Feral) in Cat; Celestial Guardian (Balance PvP talent) in Bear
                Add({
                    forms = beasts,
                    formTalents = { [CAT] = { 155580 }, [BEAR] = { URSINE_ADEPT, 233754 } },
                }, { 8921, 155625 }) -- Moonfire
                casterRules[20484] = {
                    forms = beasts,
                    formTalents = { [BEAR] = { URSINE_ADEPT } },
                    procs = { [SWIFTNESS] = SWIFTNESS },
                } -- Rebirth
            end
            procAuras = {}
            for _, activeRule in pairs(casterRules) do
                if activeRule.procs then
                    for auraInfo in pairs(activeRule.procs) do
                        procAuras[auraInfo] = true
                    end
                end
            end
        end
        return casterRules[spellRef]
    end

    -- IsSpellKnown, kept until a talent change (ns.CdmWipeFormCache)
    local function Knows(ident)
        local val = known[ident]
        if val == nil then
            val = C_SpellBook.IsSpellKnown(ident)
            if issecretvalue(val) or type(val) ~= "boolean" then
                val = UNREAD
            end
            known[ident] = val
        end
        return val
    end

    -- Whether this player can gain an exception aura: its talent is known, or
    -- for an item or set bonus (no talent) the client has the aura at all.
    local function CanProc(auraInfo, talent)
        if talent then
            return Knows(talent)
        end
        local val = exists[auraInfo]
        if val == nil then
            val = C_Spell.DoesSpellExist(auraInfo)
            if issecretvalue(val) or type(val) ~= "boolean" then
                val = UNREAD
            end
            exists[auraInfo] = val
        end
        return val
    end

    -- Whether an exception aura is on the player: nil while auras are secret
    -- (not kept, so it is asked again once they read); otherwise read once,
    -- then again after the UNIT_AURA probe (ns.CdmFormAuraEdge) drops it.
    local function ProcActive(auraInfo)
        local val = auraState[auraInfo]
        if val == nil then
            local allSecret, spellSecret =
                C_Secrets.ShouldAurasBeSecret(), C_Secrets.ShouldSpellAuraBeSecret(auraInfo)
            if
                issecretvalue(allSecret)
                or issecretvalue(spellSecret)
                or allSecret ~= false
                or spellSecret ~= false
            then
                return nil
            end
            val = UNREAD
            local success, payload = pcall(C_UnitAuras.GetPlayerAuraBySpellID, auraInfo)
            if success and not issecretvalue(payload) then
                if payload == nil then
                    val = false
                elseif Readable(payload) then
                    val = true
                    -- Recorded so the probe sees it go
                    local iid = payload.auraInstanceID
                    if iid ~= nil and not issecretvalue(iid) then
                        procIIDs[iid] = auraInfo
                    end
                end
            end
            auraState[auraInfo] = val
        end
        if val ~= UNREAD then
            return val
        end
    end

    -- Whether a spell's answer can change within a form: its rule has an
    -- exception aura this player can gain.
    function mod.CdmFormNeedsAura(spellRef)
        if not _isDruid or issecretvalue(spellRef) or type(spellRef) ~= "number" or spellRef <= 0 then
            return false
        end
        local override = C_SpellBook.FindSpellOverrideByID(spellRef)
        if issecretvalue(override) then
            return false
        end
        if type(override) == "number" and override > 0 then
            spellRef = override
        end
        local activeRule = CasterRule(spellRef)
        if activeRule and activeRule.procs then
            for auraInfo, talent in pairs(activeRule.procs) do
                if CanProc(auraInfo, talent) ~= false then
                    return true
                end
            end
        end
        return false
    end

    local function InvalidateFormAuras()
        wipe(auraState)
        wipe(procIIDs)
        wipe(blindBy)
    end

    -- A player UNIT_AURA in an unchanged form, for a caller (who) with icons
    -- whose rules hang on exception auras: true when one came or went (its
    -- answer is read again at the next evaluation) or the payload cannot
    -- tell. While auras are secret a caller gets one true, so its icons take
    -- the answer for unreadable auras (shown), and one more once they read.
    function mod.CdmFormAuraEdge(updateInfo, who)
        if not procAuras then
            return false
        end
        local s = C_Secrets.ShouldAurasBeSecret()
        if issecretvalue(s) or s ~= false then
            if next(auraState) ~= nil then
                wipe(auraState)
            end
            if blindBy[who] then
                return false
            end
            blindBy[who] = true
            return true
        end
        if blindBy[who] then
            blindBy[who] = nil
            return true
        end
        if not Readable(updateInfo) then
            wipe(auraState)
            return true
        end
        local full = updateInfo.isFullUpdate
        if issecretvalue(full) or full then
            wipe(auraState)
            wipe(procIIDs)
            return true
        end
        local hit = false
        local added = updateInfo.addedAuras
        if Readable(added) then
            for index = 1, #added do
                local auraInfo = added[index]
                if Readable(auraInfo) then
                    local ident = auraInfo.spellId
                    if not issecretvalue(ident) and procAuras[ident] then
                        auraState[ident] = nil
                        local iid = auraInfo.auraInstanceID
                        if iid ~= nil and not issecretvalue(iid) then
                            procIIDs[iid] = ident
                        end
                        hit = true
                    end
                end
            end
        end
        local removed = updateInfo.removedAuraInstanceIDs
        if Readable(removed) then
            for index = 1, #removed do
                local iid = removed[index]
                local ident = not issecretvalue(iid) and procIIDs[iid]
                if ident then
                    auraState[ident] = nil
                    hit = true
                end
            end
        end
        return hit
    end

    function mod.CdmCurrentFormID()
        local shapeshiftForm = GetShapeshiftFormID()
        if issecretvalue(shapeshiftForm) then
            return nil
        end
        if shapeshiftForm == nil then
            return 0
        end
        if type(shapeshiftForm) == "number" then
            return shapeshiftForm
        end
    end

    -- Any of these spells known (one that cannot be read counts)
    local function Permits(spells)
        if spells then
            for index = 1, #spells do
                if Knows(spells[index]) ~= false then
                    return true
                end
            end
        end
        return false
    end

    -- The rule's answer for this form: true when the spell cannot be cast
    -- here now. An exception that cannot be read permits it, except on a rule
    -- whose proc lights the spell (rule.overlay): there the spell's proc
    -- highlight, readable in combat too, decides.
    local function CasterOutside(activeRule, shapeshiftForm, spellRef)
        if not activeRule.forms[shapeshiftForm] then
            return false
        end
        if Permits(activeRule.talents) or (activeRule.formTalents and Permits(activeRule.formTalents[shapeshiftForm])) then
            return false
        end
        local uncertain = false
        if activeRule.procs then
            for auraInfo, talent in pairs(activeRule.procs) do
                local can = CanProc(auraInfo, talent)
                if can == UNREAD then
                    uncertain = true
                elseif can then
                    local active = ProcActive(auraInfo)
                    if active then
                        return false
                    end
                    if active == nil then
                        uncertain = true
                    end
                end
            end
        end
        if uncertain and activeRule.overlay then
            local lit = C_SpellActivationOverlay.IsSpellOverlayed(spellRef)
            if not issecretvalue(lit) and type(lit) == "boolean" then
                return not lit
            end
        end
        return not uncertain
    end

    -- The player's forms changed: a line that named none of the old ones may
    -- name a new one
    local function DropNoLine()
        for _, row in pairs(outside) do
            for shapeshiftForm, val in pairs(row) do
                if val == NO_LINE then
                    row[shapeshiftForm] = nil
                end
            end
        end
    end

    -- Text test for a line not typed as a shapeshift requirement: it names one
    -- of the player's forms (an untyped line must also read as the localized
    -- "Requires %s").
    local function NamesForm(textValue, typed)
        if not typed then
            local fits = false
            for index = 1, 2 do
                local tpl = TEMPLATES[index]
                local at = type(tpl) == "string" and tpl:find("%s", 1, true)
                if at then
                    local pre, suf = tpl:sub(1, at - 1), tpl:sub(at + 2)
                    if textValue:sub(1, #pre) == pre and textValue:sub(#textValue - #suf + 1) == suf then
                        fits = true
                    end
                end
            end
            if not fits then
                return false
            end
        end
        local num = GetNumShapeshiftForms()
        if issecretvalue(num) or type(num) ~= "number" then
            return nil
        end
        if num ~= formCount then
            local nameList = {}
            for index = 1, num do
                local _, _, _, formSid = GetShapeshiftFormInfo(index)
                if issecretvalue(formSid) or type(formSid) ~= "number" or formSid <= 0 then
                    return nil
                end
                local name = C_Spell.GetSpellName(formSid)
                if issecretvalue(name) or type(name) ~= "string" or name == "" then
                    return nil
                end
                nameList[#nameList + 1] = name
            end
            if formCount then
                DropNoLine()
            end
            formNames, formCount = nameList, num
        end
        for index = 1, #formNames do
            if textValue:find(formNames[index], 1, true) then
                return true
            end
        end
        return false
    end

    -- true / false from the form line, NO_LINE when no line names a form, or
    -- nil when the answer cannot be read. A form line is typed as a shapeshift
    -- requirement or, whatever its type, names one of the player's forms (an
    -- untyped one as "Requires %s"). A line that cannot be read is skipped, so
    -- the form line further down still decides; only when no line decides and
    -- one was unreadable is the answer unknown.
    local function Read(spellRef)
        local payload = C_TooltipInfo.GetSpellByID(spellRef)
        if not Readable(payload) then
            return nil
        end
        local lines = payload.lines
        if not Readable(lines) or #lines == 0 then
            return nil
        end
        local unread = false
        for index = 1, #lines do
            local line = lines[index]
            local success, t, req = Readable(line)
            if success then
                t, req = line.type, line.requirementType
            end
            if not success or issecretvalue(t) or issecretvalue(req) then
                unread = true
            else
                local isForm = req ~= nil and req == REQ_FORM
                if not isForm and (t == LINE_REQ or t == LINE_NONE or t == nil) then
                    local textValue = line.leftText
                    if issecretvalue(textValue) then
                        unread = true
                    elseif type(textValue) == "string" then
                        isForm = NamesForm(textValue, LINE_REQ ~= nil and t == LINE_REQ)
                        if isForm == nil then
                            unread = true
                        end
                    end
                end
                if isForm then
                    local c = line.leftColor
                    if not Readable(c) then
                        return nil
                    end
                    local red, green, blue = c.r, c.g, c.b
                    if
                        issecretvalue(red)
                        or issecretvalue(green)
                        or issecretvalue(blue)
                        or type(red) ~= "number"
                        or type(green) ~= "number"
                        or type(blue) ~= "number"
                    then
                        return nil
                    end
                    return red >= 0.9 and green <= 0.2 and blue <= 0.2
                end
            end
        end
        if unread then
            return nil
        end
        return NO_LINE
    end

    function mod.CdmSpellOutsideForm(spellRef)
        if issecretvalue(spellRef) or type(spellRef) ~= "number" or spellRef <= 0 then
            return false
        end
        local shapeshiftForm = mod.CdmCurrentFormID()
        if shapeshiftForm == nil then
            return false
        end
        local activeRule = CasterRule(spellRef)
        local casterOutside = activeRule and CasterOutside(activeRule, shapeshiftForm, spellRef)
        if activeRule and activeRule.procs and activeRule.forms[shapeshiftForm] and procSeen[spellRef] ~= casterOutside then
            -- An exception aura coming or going can recolor the form line
            procSeen[spellRef] = casterOutside
            local row = outside[spellRef]
            if row then
                for key, val in pairs(row) do
                    if val == true or val == false then
                        row[key] = nil
                    end
                end
            end
        end
        local row = outside[spellRef]
        local val = row and row[shapeshiftForm]
        if val == nil then
            if not row then
                row = {}
                outside[spellRef] = row
            end
            val = Read(spellRef)
            if val == nil then
                val = UNREAD
                unreadN = unreadN + 1
            end
            row[shapeshiftForm] = val
        end
        if val ~= NO_LINE and val ~= UNREAD then
            return val == true
        end
        if activeRule then
            return casterOutside
        end
        if val == UNREAD then
            return false
        end
        if shapeshiftForm == 0 then
            casterOK[spellRef] = not mod.CdmSpellNotUsable(spellRef)
            return false
        end
        return casterOK[spellRef] == true and mod.CdmSpellNotUsable(spellRef)
    end

    -- A form change or combat end: answers that could not be read are read again
    function mod.CdmRetryUnreadForms()
        InvalidateFormAuras()
        for ident, val in pairs(known) do
            if val == UNREAD then
                known[ident] = nil
            end
        end
        for ident, val in pairs(exists) do
            if val == UNREAD then
                exists[ident] = nil
            end
        end
        local num = GetNumShapeshiftForms()
        if formCount and not issecretvalue(num) and num ~= formCount then
            formCount = nil -- the names are read again
            DropNoLine()
        end
        if unreadN == 0 then
            return
        end
        unreadN = 0
        for _, row in pairs(outside) do
            for shapeshiftForm, val in pairs(row) do
                if val == UNREAD then
                    row[shapeshiftForm] = nil
                end
            end
        end
    end

    function mod.CdmWipeFormCache()
        wipe(outside)
        wipe(casterOK)
        wipe(procSeen)
        wipe(known)
        wipe(exists)
        InvalidateFormAuras()
        unreadN, formCount = 0, nil
        -- A talent can teach or drop an exception: who needs auras is decided again
        mod.CdmFormWatchStale()
        if mod.FakeActive_SyncFormAuraRules then
            mod.FakeActive_SyncFormAuraRules()
        end
    end
end

-- Deferred cd-state evaluator for the hide / lower-alpha modes, shared by the
-- SetDesaturated hook (every cooldown transition) and the charge watch below.
-- Deferred one frame because SetDesaturated fires inside Blizzard's secure CDM
-- chain where GetSpellCooldown can briefly disagree with Blizzard's own
-- evaluation (charge spells report isActive with charges left, GCD tail races).
-- The OnUpdate script is installed ONCE per frame object: the hook fires per
-- repaint, so per-arm work stays plain field writes, never closure creation.
local function ArmCdStateEval(
    widget,
    frameData,
    cse,
    cseShift,
    lowAlpha,
    hideUntilSpent,
    isUsable,
    shapeshiftForm,
    stanceIndex,
    stanceOnly
)
    local waiting = frameData._cdStatePending
    if not waiting then
        waiting = CreateFrame("Frame")
        waiting:Hide()
        frameData._cdStatePending = waiting
        waiting:SetScript("OnUpdate", function(self)
            self:Hide()
            local fc3 = _ecmeFC[widget]
            local sid3 = fc3 and fc3.spellID
            local bk3 = fc3 and fc3.barKey
            if not sid3 or not bk3 then
                return
            end
            -- Stance Bar: hidden on (or off) a stance bar page whatever the
            -- cooldown, with its own Shift Icons choice.
            if self.stance then
                local sHide, sShift = mod.CdmStanceBarHidden(self.stance)
                if sHide or self.stanceOnly then
                    local bdS = barDataByKey and barDataByKey[bk3]
                    widget:SetAlpha(sHide and 0 or mod.IconShownAlpha(fc3, bdS))
                    fc3._cdStateHidden = sHide
                    if mod.SetCdStateShiftHidden then
                        mod.SetCdStateShiftHidden(fc3, sHide and sShift)
                    end
                    return
                end
            end
            local liveSpellId = sid3
            if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                liveSpellId = C_SpellBook.FindSpellOverrideByID(sid3) or sid3
            end
            local onCooldown
            -- Hidden Outside Form/Stance arrives as Hidden (On CD) with the form
            -- flag: only the form decides, so the cooldown is never read. Hidden
            -- Until Usable arrives with the usable flag: an unusable spell hides
            -- whatever its cooldown, so that read is skipped.
            if self.form then
                onCooldown = mod.CdmSpellOutsideForm(liveSpellId)
            elseif self.usable and mod.CdmSpellNotUsable(liveSpellId) then
                onCooldown = true
            else
                onCooldown = mod.CdmOnRealCD(widget, C_Spell.GetSpellCooldown(liveSpellId))
            end
            local myCse = self.cse
            local bd3 = barDataByKey and barDataByKey[bk3]
            local baseA = mod.IconShownAlpha(fc3, bd3)
            if myCse == "lowerAlphaOnCD" then
                -- Lowered (not hidden): reuse _cdStateHidden as the "cd-state
                -- owns this alpha" flag so the opacity appliers leave the lowered
                -- value alone. A visibility-hidden bar (baseA 0) stays 0 either way.
                widget:SetAlpha(baseA == 0 and 0 or (onCooldown and (self.lowAlpha or 0.5) or baseA))
                if fc3 then
                    fc3._cdStateHidden = onCooldown or false
                    if mod.SetCdStateShiftHidden then
                        mod.SetCdStateShiftHidden(fc3, false)
                    end
                end
            else
                local hide
                if myCse == "hiddenOnCD" then
                    hide = onCooldown
                else
                    -- Hidden (CD Ready): on a charge spell "ready" is max
                    -- charges, so the icon keeps tracking the recharge.
                    hide = mod.CdmCdStateReady(liveSpellId, onCooldown, self.hideUntilSpent)
                end
                widget:SetAlpha(hide and 0 or baseA)
                if fc3 then
                    fc3._cdStateHidden = hide or false
                    if mod.SetCdStateShiftHidden then
                        mod.SetCdStateShiftHidden(fc3, self.shift and hide or false)
                    end
                end
            end
        end)
    end
    -- All captured at arm time (settings, not volatile state); only
    -- lowerAlphaOnCD reads lowAlpha, only the CD-Ready modes read hideUntilSpent.
    waiting.cse = cse
    waiting.lowAlpha = lowAlpha
    waiting.shift = cseShift
    waiting.hideUntilSpent = hideUntilSpent
    waiting.usable = isUsable
    waiting.form = shapeshiftForm
    waiting.stance = stanceIndex
    waiting.stanceOnly = stanceOnly
    waiting:Show()
end

-------------------------------------------------------------------------------
--  Hidden (CD Ready) on charge spells: refill-edge coverage
--  The mode's SetDesaturated driver fires when a charge is SPENT but NOT when
--  the last charge REFILLS to max -- the gap SPELL_UPDATE_CHARGES closes (both
--  charge transitions, nothing else, far cheaper than SPELL_UPDATE_COOLDOWN).
--  Without it a topped-off charge spell stays visible forever: at max charges
--  nothing repaints the icon. Only icons running the mode on a charge spell
--  enter the set, and it self-drains (eval unwatches dead effects/spells).
-------------------------------------------------------------------------------
mod._cdStateChargeWatch = mod._cdStateChargeWatch or setmetatable({}, { __mode = "k" })

local function EvalCdStateChargeFrame(widget, frameData)
    local fcw = _ecmeFC[widget]
    local sidw = fcw and fcw.spellID
    local bkw = fcw and fcw.barKey
    if not sidw or not bkw then
        mod._cdStateChargeWatch[widget] = nil
        return
    end
    local ssw = ResolveSpellSettings(widget, sidw, mod.GetBarSpellData(bkw))
    local csew = mod.CdStateHideOf(ssw, widget)
    if csew ~= "hiddenReady" and csew ~= "hiddenReadyShift" then
        -- Effect changed or cleared: the desat hook owns every other mode.
        mod._cdStateChargeWatch[widget] = nil
        return
    end
    ArmCdStateEval(widget, frameData, "hiddenReady", csew == "hiddenReadyShift", nil, ssw.chargeHideUntilSpent)
end

-- Register an icon whose resolved effect is Hidden (CD Ready) (callers check)
-- when its spell has charges; non-charge spells never enter the set, their real
-- CD-end edge fires the desat hook. Called from that hook (on spell rebinding)
-- and RefreshCDMIconAppearance.
function mod.WatchCdStateChargeIfEnabled(widget)
    local frameData = hookFrameData[widget]
    if not frameData then
        return
    end
    local fcw = _ecmeFC[widget]
    local sidw = fcw and fcw.spellID
    if not sidw then
        return
    end
    local liveSpellId = sidw
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSpellId = C_SpellBook.FindSpellOverrideByID(sidw) or sidw
    end
    -- Charge-spell test via static charge data (stable through the GCD).
    local chargeInfo = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(liveSpellId)
    if not (chargeInfo and (chargeInfo.maxCharges or 0) > 1) then
        mod._cdStateChargeWatch[widget] = nil
        return
    end
    mod._cdStateChargeWatch[widget] = frameData
    if not mod._cdStateChargeEventFrame then
        local ef = mod.TakeShell()
        ef:RegisterEvent("SPELL_UPDATE_CHARGES")
        ef:SetScript("OnEvent", function()
            for frame, skinData in pairs(mod._cdStateChargeWatch) do
                EvalCdStateChargeFrame(frame, skinData)
            end
        end)
        mod._cdStateChargeEventFrame = ef
    end
end

-------------------------------------------------------------------------------
--  Hidden Until Usable and Hidden Outside Form/Stance: their edges
--  Both run as Hidden (On CD) with a flag (ns.CD_STATE_HIDE), so their
--  cooldown edges ride the SetDesaturated hook like every hidden mode. A proc
--  (Overpower after a dodge, Victory Rush after a kill) changes only
--  usability, which Blizzard's own icons follow through SPELL_UPDATE_USABLE;
--  a form or stance change fires UPDATE_SHAPESHIFT_FORM (with combat end,
--  which retries form answers that were secret). A druid exception aura
--  (Predatory Swiftness, Nature's Swiftness) changes an answer within a form:
--  the player's UNIT_AURA payload shows one coming or going, and only then
--  do the icons whose rules hang on it re-evaluate (a proc highlight coming
--  or going too, which decides while auras are secret). Each event is registered
--  only while an icon runs its mode; a burst folds into one pass on the next
--  frame, which re-resolves each watched icon (an icon whose mode, spell or
--  owner changed leaves the set) and re-arms the shared evaluator. The set
--  drains itself, and an event unregisters once no icon needs it.
-------------------------------------------------------------------------------
do
    local watch = setmetatable({}, { __mode = "k" }) -- icon frame -> the spell ID it was watched with
    local watcher, flushFrame
    local usableOn, formOn, auraOn, stanceOn = false, false, false, false
    local flushedForm -- the form ID the last pass evaluated

    local function SyncEvents(isUsable, shapeshiftForm, auraInfo, stanceIndex)
        stanceIndex = stanceIndex == true
        if stanceIndex ~= stanceOn then
            stanceOn = stanceIndex
            -- A stance bar page change; Prowl pages on stealth within Cat Form.
            if stanceIndex then
                watcher:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
                watcher:RegisterEvent("UPDATE_STEALTH")
            else
                watcher:UnregisterEvent("UPDATE_BONUS_ACTIONBAR")
                watcher:UnregisterEvent("UPDATE_STEALTH")
            end
        end
        auraInfo = auraInfo == true
        if auraInfo ~= auraOn then
            -- A proc highlight coming or going decides an overlay rule while
            -- its auras cannot be read (CasterOutside).
            if auraInfo then
                watcher:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
                watcher:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            else
                watcher:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
                watcher:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            end
        end
        auraOn = auraInfo
        if isUsable ~= usableOn then
            usableOn = isUsable
            if isUsable then
                watcher:RegisterEvent("SPELL_UPDATE_USABLE")
            else
                watcher:UnregisterEvent("SPELL_UPDATE_USABLE")
            end
        end
        if shapeshiftForm ~= formOn then
            formOn = shapeshiftForm
            -- Combat end too: it retries form answers that were secret in combat.
            -- And the player's auras: a powershift (re-entering the form you are
            -- in) fires the form event as the form drops but none as it comes
            -- back, the same gap that leaves Blizzard's action bar on its caster
            -- page; the form's own aura returning still fires UNIT_AURA. In an
            -- unchanged form only an exception aura counts, while auraOn.
            if shapeshiftForm then
                watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
                watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
                watcher:RegisterUnitEvent("UNIT_AURA", "player")
            else
                watcher:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
                watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
                watcher:UnregisterEvent("UNIT_AURA")
            end
        end
    end

    local function Flush(self)
        self:Hide()
        local auraOnly = self.auraOnly
        self.auraOnly = nil
        flushedForm = mod.CdmCurrentFormID()
        local isUsable, shapeshiftForm, auraInfo, stanceAny = false, false, false, false
        for widget in pairs(watch) do
            local frameData = hookFrameData[widget]
            local fc = _ecmeFC[widget]
            local spellRef = fc and fc.spellID
            local bk = fc and fc.barKey
            local m, ss, cse, stanceIndex
            -- Same ownership guards as the SetDesaturated hook.
            if
                frameData
                and spellRef
                and bk
                and bk:sub(1, 7) ~= "__ghost"
                and bk ~= mod.FOCUSKICK_BAR_KEY
                and not (mod.PresetHasCdState and mod.PresetHasCdState(widget))
            then
                ss = ResolveSpellSettings(widget, spellRef, false)
                cse = mod.CdStateHideOf(ss, widget)
                m = cse and mod.CD_STATE_HIDE[cse]
                stanceIndex = mod.CdmStanceBarOf(ss, widget)
            end
            if (m and (m.usable or m.form)) or stanceIndex then
                watch[widget] = spellRef
                local needsAura
                if m then
                    isUsable = isUsable or m.usable == true
                    shapeshiftForm = shapeshiftForm or m.form == true
                    needsAura = m.form and mod.CdmFormNeedsAura(spellRef)
                    auraInfo = auraInfo or needsAura == true
                end
                stanceAny = stanceAny or stanceIndex ~= nil
                if not auraOnly or needsAura then
                    if stanceIndex then
                        -- The icon's whole hide: its own mode beside the stance bar
                        -- (Hidden (On CD) with the cooldown never read when alone).
                        local base, shift, us, fo, only = "hiddenOnCD", nil, nil, nil, true
                        if m then
                            base, shift, us, fo, only = m.base, m.shift, m.usable, m.form, false
                        elseif cse == "lowerAlphaOnCD" then
                            base, only = cse, false
                        end
                        ArmCdStateEval(
                            widget,
                            frameData,
                            base,
                            shift,
                            (ss and ss.cdStateLowerAlpha) or 0.5,
                            ss and ss.chargeHideUntilSpent,
                            us,
                            fo,
                            stanceIndex,
                            only
                        )
                    else
                        ArmCdStateEval(widget, frameData, m.base, m.shift, nil, nil, m.usable, m.form)
                    end
                end
            else
                watch[widget] = nil
            end
        end
        SyncEvents(isUsable, shapeshiftForm, auraInfo, stanceAny)
    end

    -- Called wherever the mode is resolved for an icon (SetDesaturated hook,
    -- RefreshCDMIconAppearance); form = the icon runs Hidden Outside
    -- Form/Stance. Table reads only, once the icon is watched with its spell.
    function mod.WatchCdUsable(widget, shapeshiftForm, stanceIndex, isUsable)
        local fc = _ecmeFC[widget]
        local spellRef = fc and fc.spellID
        local was = watch[widget]
        -- usable: the icon also runs Hidden Until Usable (implied by a plain call)
        local needUsable = isUsable or (not shapeshiftForm and not stanceIndex)
        if
            was ~= nil
            and was == spellRef
            and (not shapeshiftForm or formOn)
            and (not stanceIndex or stanceOn)
            and (not needUsable or usableOn)
        then
            return
        end
        watch[widget] = spellRef or true
        if not watcher then
            flushFrame = mod.TakeShell()
            flushFrame:Hide()
            flushFrame:SetScript("OnUpdate", Flush)
            watcher = mod.TakeShell()
            watcher:SetScript("OnEvent", function(_, evt, _, updateInfo)
                local overlayFrame = evt == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
                    or evt == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"
                local auraOnly = overlayFrame
                    or (evt == "UNIT_AURA" and mod.CdmCurrentFormID() == flushedForm)
                if overlayFrame then
                    -- Only the icons whose rules hang on exception auras re-read
                elseif auraOnly then
                    -- Same form: only an exception aura coming or going counts
                    if not (auraOn and mod.CdmFormAuraEdge(updateInfo, "watch")) then
                        return
                    end
                elseif
                    evt ~= "SPELL_UPDATE_USABLE"
                    and evt ~= "UPDATE_BONUS_ACTIONBAR"
                    and evt ~= "UPDATE_STEALTH"
                then
                    mod.CdmRetryUnreadForms()
                end
                -- A queued form/usability edge keeps its full pass.
                if not flushFrame:IsShown() then
                    flushFrame.auraOnly = auraOnly
                elseif not auraOnly then
                    flushFrame.auraOnly = false
                end
                flushFrame:Show()
            end)
        end
        local needsAura = shapeshiftForm and mod.CdmFormNeedsAura(spellRef)
        SyncEvents(
            usableOn or needUsable == true,
            formOn or shapeshiftForm == true,
            auraOn or needsAura == true,
            stanceOn or stanceIndex == true
        )
    end

    -- A talent change can teach or drop an exception: each watched icon
    -- decides its aura need again on its next pass (ns.CdmWipeFormCache).
    function mod.CdmFormWatchStale()
        for widget in pairs(watch) do
            watch[widget] = true
        end
    end
end

-------------------------------------------------------------------------------
--  Swiftmend brightness: Blizzard dims the icon via SetVertexColor when
--  Efflorescence / HoTs drop. Hook the icon texture once to force bright.
--  Recursion guard only -- never compare incoming args (secret values).
--  Retried on EVERY DecorateFrame call: spell-ID resolution can miss on a
--  frame's first pass (cooldownID not yet assigned) and a decorated-flag early
--  return would make that permanent. Free: non-Druids skip on the cached class
--  check, hooked frames on one flag read.
-------------------------------------------------------------------------------
local SWIFTMEND_SID = 18562
local _smHookedIcons = {}
local function SwiftmendEnabled()
    return not CludesUIDB or CludesUIDB.brightenSwiftmend ~= false
end
local function TryHookSwiftmend(widget, frameData)
    if not _isDruid or frameData._smVCHooked then
        return
    end
    local iconWidget = frameData.tex
    if not iconWidget then
        return
    end
    local dispSID, baseSID = ResolveFrameSpellID(widget)
    if dispSID and issecretvalue(dispSID) then
        dispSID = nil
    end
    if baseSID and issecretvalue(baseSID) then
        baseSID = nil
    end
    if baseSID ~= SWIFTMEND_SID and dispSID ~= SWIFTMEND_SID then
        return
    end
    frameData._smVCHooked = true
    _smHookedIcons[#_smHookedIcons + 1] = iconWidget
    local smGuard = false
    hooksecurefunc(iconWidget, "SetVertexColor", function()
        if smGuard then
            return
        end
        if not SwiftmendEnabled() then
            return
        end
        smGuard = true
        iconWidget:SetVertexColor(1, 1, 1)
        smGuard = false
    end)
    if SwiftmendEnabled() then
        iconWidget:SetVertexColor(1, 1, 1)
    end
end

-------------------------------------------------------------------------------
--  Ignore Resource Cost (per spell, cd/utility icons): Blizzard tints a viewer
--  icon through SetVertexColor on every usability change -- blue while the
--  spell is short on its resource, grey while unusable for another reason, red
--  out of range. With the setting on only the resource tint goes: a post-hook
--  on the icon texture repaints full color whenever IsSpellUsable reports
--  insufficient power (a plain boolean on every client), through
--  SetVertexColorFromBoolean on Blizzard's own out-of-range flag, so red still
--  wins and a secret range answer in instanced content needs no Lua test.
--  Nothing is hooked or read until some spell uses the setting
--  (ns._cdmAnyNoResourceTint), and an icon is hooked only on a pass that finds
--  its own spell using it: DecorateFrame on every (re)claim, the appearance
--  refresh after a settings change and the swipe hook's gate run this again
--  for an icon that gets such a spell later. Turning it off repaints
--  Blizzard's tint once from the reads its RefreshIconColor makes, never by
--  calling that insecurely.
-------------------------------------------------------------------------------
local RES_WHITE = CreateColor(1, 1, 1, 1)
local resRed, resPower, resGrey
local function ResColors()
    if not resRed then
        local C = CooldownViewerConstants
        resRed = (C and C.ITEM_NOT_IN_RANGE_COLOR) or CreateColor(0.64, 0.15, 0.15, 1)
        resPower = (C and C.ITEM_NOT_ENOUGH_MANA_COLOR) or CreateColor(0.5, 0.5, 1, 1)
        resGrey = (C and C.ITEM_NOT_USABLE_COLOR) or CreateColor(0.4, 0.4, 0.4, 1)
    end
    return resRed, resPower, resGrey
end

-- Paints `base`, or Blizzard's red while its out-of-range flag is set.
local function PaintIconTint(widget, frameData, texture, base)
    local red = ResColors()
    local oor = widget.spellOutOfRange
    frameData._resTintBusy = true
    if type(oor) == "boolean" and texture.SetVertexColorFromBoolean then
        texture:SetVertexColorFromBoolean(oor, red, base)
    else
        texture:SetVertexColor(base:GetRGBA())
    end
    frameData._resTintBusy = false
end

local function ApplyResourceTint(widget, frameData, fromBlizzard)
    if not mod._cdmAnyNoResourceTint then
        return
    end
    frameData = frameData or hookFrameData[widget]
    local texture = frameData and frameData.tex
    if not texture or frameData._isBuffViewerFrame then
        return
    end
    -- Our own frames paint their tint themselves (ns.PaintCustomSpellTint).
    if mod.CdmIsInjectedFrame and mod.CdmIsInjectedFrame(widget) then
        return
    end
    local fc = _ecmeFC[widget]
    local spellRef = fc and fc.spellID
    if not spellRef or not (fc and fc.barKey) then
        return
    end
    local ss = ResolveSpellSettings(widget, spellRef, false)
    local wanted = ss and ss.noResourceTint
    if not wanted and not frameData._resTintOn then
        return
    end
    -- Hooked only once the icon's own spell uses the setting (a lit tint
    -- means the hook is already in).
    if not frameData._resTintHooked then
        frameData._resTintHooked = true
        hooksecurefunc(texture, "SetVertexColor", function()
            if frameData._resTintBusy then
                return
            end
            ApplyResourceTint(widget, frameData, true)
        end)
    end
    local liveSpellId = spellRef
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        liveSpellId = C_SpellBook.FindSpellOverrideByID(spellRef) or spellRef
    end
    local isUsable, noPower = C_Spell.IsSpellUsable(liveSpellId)
    if issecretvalue and (issecretvalue(isUsable) or issecretvalue(noPower)) then
        return
    end
    if wanted then
        if noPower then
            PaintIconTint(widget, frameData, texture, RES_WHITE)
            frameData._resTintOn = true
        else
            -- Not short on power: Blizzard's own tint stands.
            frameData._resTintOn = nil
        end
    elseif frameData._resTintOn then
        frameData._resTintOn = nil
        -- A Blizzard write that just landed already holds its own tint.
        if fromBlizzard then
            return
        end
        local _, power, grey = ResColors()
        PaintIconTint(widget, frameData, texture, isUsable and RES_WHITE or (noPower and power or grey))
    end
end
mod.CdmApplyResourceTint = ApplyResourceTint

-------------------------------------------------------------------------------
--  Per-spell Custom Icon
--  Stamp the configured replacement icon (texture fileID) over the icon texture,
--  from DecorateFrame on every (re)claim and from a per-frame
--  RefreshSpellTexture post-hook (installed on first gated visit), so it
--  survives every Blizzard repaint AND spell transforms: RefreshSpellTexture is
--  the ONLY writer of a viewer item's icon texture (every item type's
--  RefreshData + SPELL_UPDATE_ICON), and the settings resolver matches the
--  stored key against the frame's full identity set. Purely per-spell, never
--  written to bar tiers. Gated on ns._cdmAnyCustomIcon (one boolean, no hooks
--  installed for non-users). Clear/restore: when the setting is removed the last
--  stamped frame (fd._customIconOn) restores its real icon once via
--  C_Spell.GetSpellTexture (base id; API resolves live overrides, next
--  RefreshData corrects aura/link nuance). NEVER call the frame's own
--  RefreshSpellTexture for this -- running Blizzard mixin code from insecure
--  context can write tainted values into the frame's table.
-------------------------------------------------------------------------------
local function ApplyCustomIcon(widget, frameData)
    if not mod._cdmAnyCustomIcon then
        return
    end
    frameData = frameData or hookFrameData[widget]
    local texture = frameData and frameData.tex
    if not texture then
        return
    end
    -- Per-frame re-assert hook. Must hook the frame INSTANCE: leaf-mixin functions are
    -- COPIED onto each item frame at creation, so a hooksecurefunc on the mixin table
    -- never fires for frames that predate the install (the custom icon then reverts on
    -- every cast, RefreshData repainting the real icon). Same per-frame pattern as the
    -- SetDesaturated hooks. Injected/own frames have no RefreshSpellTexture and skip it
    -- (nothing Blizzard-side repaints them; the claim-path stamps suffice).
    if not frameData._ciHooked and widget.RefreshSpellTexture then
        frameData._ciHooked = true
        hooksecurefunc(widget, "RefreshSpellTexture", ApplyCustomIcon)
    end
    local ss = mod._ResolveCdmSS(widget)
    local chargeInfo = ss and ss.customIcon
    if type(chargeInfo) == "number" and chargeInfo > 0 then
        texture:SetTexture(chargeInfo)
        frameData._customIconOn = true
    elseif frameData._customIconOn then
        -- Restore ONLY with a resolvable identity: a nil sid means the identity
        -- cache is transiently empty (bar-rebuild mid-login), not that the user
        -- cleared the setting, so keep the flag armed for the next pass.
        local fc = _ecmeFC[widget]
        local spellRef = fc and (fc.resolvedSid or fc.spellID)
        if
            type(spellRef) == "number"
            and not (issecretvalue and issecretvalue(spellRef))
            and spellRef > 0
            and C_Spell
            and C_Spell.GetSpellTexture
        then
            frameData._customIconOn = nil
            local real = C_Spell.GetSpellTexture(spellRef)
            if real then
                texture:SetTexture(real)
            end
        end
    end
end
mod.ApplyCustomIcon = ApplyCustomIcon

-------------------------------------------------------------------------------
--  Icon-art suppression (two bar settings, one machine)
--    buff-family bars: "Only Show Numbers"            -> barData.onlyShowNumbers
--    cd/utility bars:  "Charges/Stacks Only (No Icon)" -> barData.chargesOnly
--  Both hide icon texture, background, square border, shape ring, Blizzard
--  debuff border, swipe and recharge edge; they differ only in the countdown:
--  Only Show Numbers leaves it to the normal Duration Text settings (bar toggle
--  + per-icon overrides; off = stacks-only), Charges/Stacks Only forces it OFF.
--  Swipe, edge and countdown have writers that re-assert between our passes, so
--  each is gated at its own choke point: the SetDrawSwipe hook and
--  ApplyCdmChargeStyle (owner of ApplyCdmEdge) read _osnOn; the resolver every
--  countdown writer funnels through, ns.CdmShouldHideCountdown, reads
--  _osnHideText. Every hide is REGION-level, never frame alpha: frame.ChargeCount
--  / frame.Applications are siblings of the icon (on container-Icon frames the
--  stack text is at Icon.Applications), so frame:SetAlpha(0)/Icon:SetAlpha(0)
--  would take the counters with it; fd.tex is already resolved to the leaf
--  texture by DecorateFrame's GetTexture descent. Applied from DecorateFrame on
--  every (re)claim and re-asserted at the end of RefreshCDMIconAppearance's
--  per-icon pass (which re-applies borders/shapes and would otherwise undo the
--  hides). Hides are alpha/shown/flag based with regions staying live, so
--  turning the setting off restores one-shot via fd._osnOn (pooled frames
--  moving to a bar without the setting restore the same way); normal style
--  passes re-assert the rest. Cost when off: one field read per call.
-------------------------------------------------------------------------------
local function ApplyOnlyNumbers(widget, frameData, barInfo)
    if not barInfo then
        return
    end
    frameData = frameData or hookFrameData[widget]
    local osn = barInfo.onlyShowNumbers
    if osn or barInfo.chargesOnly then
        -- Set BEFORE the swipe/edge writes: the per-frame SetDrawSwipe/
        -- SetDrawEdge hooks force defaults for non-charge frames and read _osnOn
        -- to stand down (buff frames early-out on _isBuffViewerFrame and never
        -- reach that hook, which is why cd/utility needed the gate).
        -- _osnHideText tells ns.CdmShouldHideCountdown the duration is
        -- suppressed; every countdown writer resolves through it.
        if frameData then
            frameData._osnOn = true
            frameData._osnHideText = (not osn) or nil
        end
        local texture = (frameData and frameData.tex) or widget._tex
        if texture then
            texture:SetAlpha(0)
            -- Hide() too, load-bearing on cd/utility: Texture SetAlpha and
            -- SetVertexColor share ONE alpha slot on this client, and the
            -- resource-dim pass writes a 3-arg SetVertexColor on injected
            -- custom-spell icons, resetting alpha to 1 and popping the art back.
            -- Shown-state is an independent channel no colour writer can touch,
            -- and nothing in the addon Shows an icon texture.
            texture:Hide()
        end
        local backdrop = (frameData and frameData.bg) or widget._bg
        if backdrop then
            backdrop:SetAlpha(0)
        end
        if frameData and frameData.borderFrame then
            CludesUI.PP.HideBorder(frameData.borderFrame)
            local bdFrame = CludesUI._bdBorderData and CludesUI._bdBorderData[frameData.borderFrame]
            if bdFrame then
                bdFrame:Hide()
            end
        end
        local ifc = _ecmeFC[widget]
        if ifc and ifc.shapeBorder then
            ifc.shapeBorder:SetAlpha(0)
        end
        -- Blizzard Style ring goes with the art (the custom-aura buttons hide theirs too).
        if ifc and ifc.blizzHost then
            ifc.blizzHost:Hide()
        end
        if widget.DebuffBorder then
            widget.DebuffBorder:SetAlpha(0)
        end
        local cooldown = (frameData and frameData.cooldown) or widget.Cooldown or widget._cooldown
        if cooldown then
            if cooldown.SetDrawSwipe then
                cooldown:SetDrawSwipe(false)
            end
            -- No icon means no recharge edge either.
            if cooldown.SetDrawEdge then
                cooldown:SetDrawEdge(false)
            end
            -- Charges/Stacks Only forces the countdown OFF. The buff variant does
            -- NOT touch it: the duration follows the normal Duration Text
            -- settings, applied by the appearance pass before this re-hide tail.
            if (not osn) and cooldown.SetHideCountdownNumbers then
                cooldown:SetHideCountdownNumbers(true)
            end
        end
    elseif frameData and frameData._osnOn then
        frameData._osnOn = nil
        frameData._osnHideText = nil
        local texture = frameData.tex or widget._tex
        if texture then
            texture:SetAlpha(1)
            texture:Show()
        end
        local backdrop = frameData.bg or widget._bg
        if backdrop then
            backdrop:SetAlpha(1)
        end
        local ifc = _ecmeFC[widget]
        if ifc and ifc.shapeBorder then
            ifc.shapeBorder:SetAlpha(1)
        end
        if ifc and ifc.blizzHost then
            ifc.blizzHost:Show()
        end
        if widget.DebuffBorder then
            widget.DebuffBorder:SetAlpha(1)
        end
        local cooldown = frameData.cooldown or widget.Cooldown or widget._cooldown
        if cooldown then
            if cooldown.SetDrawSwipe then
                cooldown:SetDrawSwipe(true)
            end
            if cooldown.SetHideCountdownNumbers then
                cooldown:SetHideCountdownNumbers(
                    mod.CdmDurationHideFor(widget, barInfo.key, not mod.CdmDurationTextOn(barInfo))
                )
            end
        end
        -- Square border / shape ring re-apply on the next style pass
        -- (DecorateFrame / RefreshCDMIconAppearance via BuildAllCDMBars).
    end
end
mod.ApplyOnlyNumbers = ApplyOnlyNumbers

Inner._smHookedIcons, Inner.ApplyCustomIcon = _smHookedIcons, ApplyCustomIcon
Inner.ApplyOnlyNumbers, Inner.ArmCdStateEval = ApplyOnlyNumbers, ArmCdStateEval
Inner.SwiftmendEnabled, Inner.TryHookSwiftmend = SwiftmendEnabled, TryHookSwiftmend
Inner.ApplyResourceTint = ApplyResourceTint
Inner.broken = false
