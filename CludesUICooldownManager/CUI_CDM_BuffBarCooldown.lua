if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_BuffBarCooldown.lua
--
--  The charge hash fill, the cooldown cast mirror and the cooldown-tracking
--  bar.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._buffBarInternals
-- CludesUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local GetTime = GetTime

local _classB, _classG, _classR, FormatTime = Inner._classB, Inner._classG, Inner._classR, Inner.FormatTime
local _tbbWake, AnchorTBBSpark = Inner._tbbWake, Inner.AnchorTBBSpark
local ApplyTBBChargeHashLines = Inner.ApplyTBBChargeHashLines
local ApplyTBBTickMarks = Inner.ApplyTBBTickMarks
local FeedTBBThresholdOverlay, _tbbCleanNum = Inner.FeedTBBThresholdOverlay, Inner._tbbCleanNum
local ClearPandemic, CooldownBarSpellID = Inner.ClearPandemic, Inner.CooldownBarSpellID
local SetRestoreNormalFill = Inner.SetRestoreNormalFill

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local _anyThreshold = false
Inner.anyThresholdSetters[#Inner.anyThresholdSetters + 1] = function(val) _anyThreshold = val end
-- Assigned further down and handed to CUI_CDM_BuffBarFrames.lua
-- (SetRestoreNormalFill).
local _restoreTBBNormalFill

-------------------------------------------------------------------------------
--  Charge hash fill
--  currentCharges is secret in combat, so addon Lua cannot compute (currentCharges +
--  next-recharge progress) / maxCharges. Two invisible native StatusBars supply the
--  geometry instead: one takes Blizzard's charge count directly, one animates exactly
--  one charge-wide segment from the duration object. A single full-size texture is
--  clipped to their combined edge, so the player still sees one continuous bar
--  honoring the texture, gradient, spark, orientation and reverse-fill settings.
-------------------------------------------------------------------------------
local function _ensureTBBChargeHashFill(barFrame)
    if barFrame._chargeHashCountBar then return end
    local scrollBar = barFrame._bar
    if not scrollBar then return end

    local countBar = CreateFrame("StatusBar", nil, scrollBar)
    countBar:SetAllPoints(scrollBar)
    countBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local countTexture = countBar:GetStatusBarTexture()
    countTexture:SetSnapToPixelGrid(false)
    countTexture:SetTexelSnappingBias(0)
    countBar:SetAlpha(0)
    countBar:EnableMouse(false)
    barFrame._chargeHashCountBar = countBar
    barFrame._chargeHashCountTexture = countTexture

    local progressBar = CreateFrame("StatusBar", nil, scrollBar)
    progressBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local progressTexture = progressBar:GetStatusBarTexture()
    progressTexture:SetSnapToPixelGrid(false)
    progressTexture:SetTexelSnappingBias(0)
    progressBar:SetAlpha(0)
    progressBar:EnableMouse(false)
    barFrame._chargeHashProgressBar = progressBar
    barFrame._chargeHashProgressTexture = progressTexture

    local clip = CreateFrame("Frame", nil, scrollBar)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(scrollBar:GetFrameLevel() + 1)
    clip:Hide()
    barFrame._chargeHashFillClip = clip

    local fillTex = clip:CreateTexture(nil, "ARTWORK", nil, 1)
    fillTex:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
    fillTex:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
    fillTex:SetSnapToPixelGrid(false)
    fillTex:SetTexelSnappingBias(0)
    barFrame._chargeHashFillTexture = fillTex

    -- Partial-charge shade: darkens the segment still recharging (the region between the
    -- full-charge edge and the live progress edge). Its anchors ride the two invisible
    -- status textures, so the region tracks secret-driven geometry with no Lua computation.
    -- The hash tick lines center on divider bars whose texture edges come from the same
    -- engine math as countTexture's edge, so the shade's leading edge always lands under
    -- its divider line -- no sub-pixel sliver can open beside it at any bar width.
    local shade = clip:CreateTexture(nil, "ARTWORK", nil, 2)
    shade:SetColorTexture(0, 0, 0, 0.5)
    shade:SetSnapToPixelGrid(false)
    shade:SetTexelSnappingBias(0)
    shade:Hide()
    barFrame._chargeHashShadeTexture = shade
end

local function _styleTBBChargeHashFill(barFrame, conf)
    local fillTex = barFrame._chargeHashFillTexture
    if not fillTex then return end
    local texPath = barFrame._lastTexPath or "Interface\\Buttons\\WHITE8x8"
    local fR, fG = barFrame._baseFillR or _classR, barFrame._baseFillG or _classG
    local fB, fA = barFrame._baseFillB or _classB, barFrame._baseFillA or 1
    local gradientEnabled = conf.gradientEnabled and true or false
    local gradientDir = conf.gradientDir or "HORIZONTAL"
    local gR, gG = conf.gradientR or 0.20, conf.gradientG or 0.20
    local gB, gA = conf.gradientB or 0.80, conf.gradientA or 1
    -- SCALAR style signature: unchanged active bars take this branch without allocating a temporary table/key string every tick.
    if
        barFrame._chargeHashFillStyleValid
        and barFrame._chargeHashFillStyleTexPath == texPath
        and barFrame._chargeHashFillStyleGradient == gradientEnabled
        and barFrame._chargeHashFillStyleDirection == gradientDir
        and barFrame._chargeHashFillStyleR == fR
        and barFrame._chargeHashFillStyleG == fG
        and barFrame._chargeHashFillStyleB == fB
        and barFrame._chargeHashFillStyleA == fA
        and barFrame._chargeHashFillStyleGradientR == gR
        and barFrame._chargeHashFillStyleGradientG == gG
        and barFrame._chargeHashFillStyleGradientB == gB
        and barFrame._chargeHashFillStyleGradientA == gA
    then
        return
    end

    fillTex:SetTexture(texPath)
    if barFrame._blizzFillAtlas then fillTex:SetAtlas("UI-HUD-CoolDownManager-Bar") end
    fillTex:ClearAllPoints()
    if gradientEnabled then
        -- Gradients stay mapped across the full bar and are revealed by the moving clip, matching the stock gradient path.
        fillTex:SetPoint("TOPLEFT", barFrame._bar, "TOPLEFT", 0, 0)
        fillTex:SetPoint("BOTTOMRIGHT", barFrame._bar, "BOTTOMRIGHT", 0, 0)
        fillTex:SetVertexColor(1, 1, 1, 1)
        local c1 = barFrame._chargeHashGradientColor1
        local c2 = barFrame._chargeHashGradientColor2
        if not c1 then
            c1 = CreateColor(fR, fG, fB, fA)
            c2 = CreateColor(gR, gG, gB, gA)
            barFrame._chargeHashGradientColor1 = c1
            barFrame._chargeHashGradientColor2 = c2
        else
            c1.r, c1.g, c1.b, c1.a = fR, fG, fB, fA
            c2.r, c2.g, c2.b, c2.a = gR, gG, gB, gA
        end
        fillTex:SetGradient(gradientDir, c1, c2)
    else
        -- Plain/patterned StatusBar textures stretch with the visible fill.
        fillTex:SetAllPoints(barFrame._chargeHashFillClip)
        fillTex:SetVertexColor(fR, fG, fB, fA)
    end
    barFrame._chargeHashFillStyleValid = true
    barFrame._chargeHashFillStyleTexPath = texPath
    barFrame._chargeHashFillStyleGradient = gradientEnabled
    barFrame._chargeHashFillStyleDirection = gradientDir
    barFrame._chargeHashFillStyleR = fR
    barFrame._chargeHashFillStyleG = fG
    barFrame._chargeHashFillStyleB = fB
    barFrame._chargeHashFillStyleA = fA
    barFrame._chargeHashFillStyleGradientR = gR
    barFrame._chargeHashFillStyleGradientG = gG
    barFrame._chargeHashFillStyleGradientB = gB
    barFrame._chargeHashFillStyleGradientA = gA
end

_restoreTBBNormalFill = function(barFrame, conf)
    if not barFrame._chargeHashFillActive then return end
    if barFrame._chargeHashFillClip then barFrame._chargeHashFillClip:Hide() end
    if barFrame._chargeHashCountBar then barFrame._chargeHashCountBar:Hide() end
    if barFrame._chargeHashProgressBar then barFrame._chargeHashProgressBar:Hide() end

    local scrollBar = barFrame._bar
    local fillTex = barFrame._cachedOurFillTex
    if not fillTex and scrollBar then
        fillTex = scrollBar:GetStatusBarTexture()
        barFrame._cachedOurFillTex = fillTex
    end
    if fillTex then fillTex:SetAlpha(1) end
    if barFrame._gradientActive and barFrame._gradClip then barFrame._gradClip:Show() end
    if conf.showSpark and fillTex then
        AnchorTBBSpark(barFrame, conf, (barFrame._gradientActive and barFrame._gradClip) or fillTex)
    end

    barFrame._chargeHashFillActive = nil
    barFrame._chargeHashDuration = nil
    -- The stock bar timer is not re-armed while its texture is hidden, so a mid-recharge exit from hash mode must force the original path to refresh.
    barFrame._cdNeedSet = true
end
SetRestoreNormalFill(_restoreTBBNormalFill)

local function _updateTBBChargeHashFill(
    barFrame,
    conf,
    maxCharges,
    currentCharges,
    durObj,
    remaining,
    duration,
    wasShown
)
    if conf.chargeHashLines ~= true or type(maxCharges) ~= "number" or maxCharges <= 1 then return false end
    local secretCount = issecretvalue and issecretvalue(currentCharges)
    if not secretCount and type(currentCharges) ~= "number" then return false end
    if not durObj and not (_tbbCleanNum(remaining) and _tbbCleanNum(duration) and duration > 0) then
        return false
    end

    _ensureTBBChargeHashFill(barFrame)
    local scrollBar = barFrame._bar
    local countBar = barFrame._chargeHashCountBar
    local progressBar = barFrame._chargeHashProgressBar
    local countTexture = barFrame._chargeHashCountTexture
    local progressTexture = barFrame._chargeHashProgressTexture
    local clip = barFrame._chargeHashFillClip
    if
        not scrollBar
        or not countBar
        or not progressBar
        or not countTexture
        or not progressTexture
        or not clip
    then
        return false
    end

    local isVert = conf.verticalOrientation and true or false
    local reverse = conf.reverseFill and true or false
    local orientation = isVert and "VERTICAL" or "HORIZONTAL"
    local barW, barH = scrollBar:GetWidth(), scrollBar:GetHeight()
    -- The divider boundary bars the hash ticks anchor to are built and cache-gated
    -- by ApplyTBBChargeHashLines, which runs earlier on the same tick; nothing here
    -- reads them, so this per-tick path never touches them.

    -- Direct scalar comparisons name every geometry invalidator while keeping the steady-state update allocation-free.
    if
        not barFrame._chargeHashFillGeometryValid
        or barFrame._chargeHashFillMaxCharges ~= maxCharges
        or barFrame._chargeHashFillVertical ~= isVert
        or barFrame._chargeHashFillReverse ~= reverse
        or barFrame._chargeHashFillBarW ~= barW
        or barFrame._chargeHashFillBarH ~= barH
    then
        countBar:SetOrientation(orientation)
        countBar:SetReverseFill(reverse)
        countBar:SetMinMaxValues(0, maxCharges)

        progressBar:ClearAllPoints()
        progressBar:SetOrientation(orientation)
        progressBar:SetReverseFill(reverse)
        progressBar:SetMinMaxValues(0, 1)
        if isVert then
            progressBar:SetHeight(barH / maxCharges)
            if reverse then
                progressBar:SetPoint("TOPLEFT", countTexture, "BOTTOMLEFT", 0, 0)
                progressBar:SetPoint("TOPRIGHT", countTexture, "BOTTOMRIGHT", 0, 0)
            else
                progressBar:SetPoint("BOTTOMLEFT", countTexture, "TOPLEFT", 0, 0)
                progressBar:SetPoint("BOTTOMRIGHT", countTexture, "TOPRIGHT", 0, 0)
            end
        else
            progressBar:SetWidth(barW / maxCharges)
            if reverse then
                progressBar:SetPoint("TOPRIGHT", countTexture, "TOPLEFT", 0, 0)
                progressBar:SetPoint("BOTTOMRIGHT", countTexture, "BOTTOMLEFT", 0, 0)
            else
                progressBar:SetPoint("TOPLEFT", countTexture, "TOPRIGHT", 0, 0)
                progressBar:SetPoint("BOTTOMLEFT", countTexture, "BOTTOMRIGHT", 0, 0)
            end
        end

        clip:ClearAllPoints()
        if isVert then
            if reverse then
                clip:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, 0)
                clip:SetPoint("BOTTOMLEFT", progressTexture, "BOTTOMLEFT", 0, 0)
            else
                clip:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, 0)
                clip:SetPoint("TOPRIGHT", progressTexture, "TOPRIGHT", 0, 0)
            end
        else
            if reverse then
                clip:SetPoint("TOPLEFT", progressTexture, "TOPLEFT", 0, 0)
                clip:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
            else
                clip:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
                clip:SetPoint("BOTTOMRIGHT", progressTexture, "BOTTOMRIGHT", 0, 0)
            end
        end

        -- The shade spans from the full-charge boundary to the moving progress edge,
        -- mirroring the clip's orientation/reverse geometry.
        local shade = barFrame._chargeHashShadeTexture
        if shade then
            shade:ClearAllPoints()
            if isVert then
                if reverse then
                    shade:SetPoint("TOPLEFT", countTexture, "BOTTOMLEFT", 0, 0)
                    shade:SetPoint("BOTTOMRIGHT", progressTexture, "BOTTOMRIGHT", 0, 0)
                else
                    shade:SetPoint("BOTTOMLEFT", countTexture, "TOPLEFT", 0, 0)
                    shade:SetPoint("TOPRIGHT", progressTexture, "TOPRIGHT", 0, 0)
                end
            else
                if reverse then
                    shade:SetPoint("TOPRIGHT", countTexture, "TOPLEFT", 0, 0)
                    shade:SetPoint("BOTTOMLEFT", progressTexture, "BOTTOMLEFT", 0, 0)
                else
                    shade:SetPoint("TOPLEFT", countTexture, "TOPRIGHT", 0, 0)
                    shade:SetPoint("BOTTOMRIGHT", progressTexture, "BOTTOMRIGHT", 0, 0)
                end
            end
        end

        barFrame._chargeHashFillGeometryValid = true
        barFrame._chargeHashFillMaxCharges = maxCharges
        barFrame._chargeHashFillVertical = isVert
        barFrame._chargeHashFillReverse = reverse
        barFrame._chargeHashFillBarW = barW
        barFrame._chargeHashFillBarH = barH
    end

    -- SetValue is a supported secret sink: NEVER inspect or compute with the live count in Lua.
    countBar:SetValue(currentCharges)

    if durObj and progressBar.SetTimerDuration and Enum and Enum.StatusBarTimerDirection then
        if barFrame._cdNeedSet or barFrame._chargeHashDuration ~= durObj or not wasShown then
            local interp = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
            progressBar:SetTimerDuration(durObj, interp, Enum.StatusBarTimerDirection.ElapsedTime)
            barFrame._chargeHashDuration = durObj
        end
    else
        -- Compatibility fallback for clients that expose only clean timing.
        progressBar:SetValue(1 - (remaining / duration))
        barFrame._chargeHashDuration = nil
    end

    _styleTBBChargeHashFill(barFrame, conf)

    -- Partial-charge shade state: scalar-cached so the steady-state tick is a no-op.
    local shade = barFrame._chargeHashShadeTexture
    if shade then
        local shadeA = conf.chargeHashShade == true and (tonumber(conf.chargeHashShadeAlpha) or 0.5) or 0
        if shadeA > 1 then shadeA = 1 end
        if shadeA > 0 then
            if barFrame._chargeHashShadeAlpha ~= shadeA then
                shade:SetColorTexture(0, 0, 0, shadeA)
                barFrame._chargeHashShadeAlpha = shadeA
            end
            if not shade:IsShown() then shade:Show() end
        elseif shade:IsShown() then
            shade:Hide()
        end
    end

    local activating = not barFrame._chargeHashFillActive
    if activating then
        countBar:Show()
        progressBar:Show()
        local fillTex = barFrame._cachedOurFillTex
        if not fillTex then
            fillTex = scrollBar:GetStatusBarTexture()
            barFrame._cachedOurFillTex = fillTex
        end
        if fillTex then fillTex:SetAlpha(0) end
        if barFrame._gradClip then barFrame._gradClip:Hide() end
        clip:Show()
    end
    if conf.showSpark and barFrame._spark then
        -- Anchor to the native progress TEXTURE, not the intermediate clip frame: its moving
        -- edge is the exact visible fill boundary, and skipping the frame's pixel rounding
        -- keeps the spark joined to that edge in both normal and reverse fill.
        AnchorTBBSpark(barFrame, conf, progressTexture, true)
        if not barFrame._spark:IsShown() then barFrame._spark:Show() end
    end
    barFrame._chargeHashFillActive = true
    barFrame._cdNeedSet = nil
    return true
end

-------------------------------------------------------------------------------
--  Cooldown-bar cast mirror. In combat the cooldown APIs keep isActive readable but
--  turn startTime/duration SECRET, which would drop every on-cooldown bar into the
--  shown-full fail-open for the whole fight. So each tracked spell keeps a local
--  { start, dur } mirror of clean numbers: synced from every clean read (out of
--  combat, incl. mid-cooldown) and armed from the player's own cast edge in combat
--  (UNIT_SPELLCAST_SUCCEEDED's spellID arg is never secret). The tick falls back to
--  the mirror when the API turns secret; isActive stays readable, so the bar still
--  ends/hides exactly when the real cooldown does even if the mirror drifts (CDR, resets).
-------------------------------------------------------------------------------
local _cdCast = {} -- [sid] = { start, dur } live local cooldown mirror
local _cdDurCache = {} -- [sid] = last clean cooldown/recharge duration seen
local _cdWatch = {} -- [watched sid] = canonical sid to key the mirror by
local _cdFrame
local _cdActive = false
-- Cooldown-state generation: bumped by SPELL_UPDATE_COOLDOWN/CHARGES/player casts. Bars
-- re-fetch + re-arm their engine duration handle only when this moves; a cached handle keeps
-- ticking down on its own, and only a CDR/reset-adjusted cooldown needs a fresh fetch.
local _cdGen = 0

-- Static base cooldown (ms) as the arm-time seed before any clean read. The API lives
-- ONLY at the global (client-verified: no C_Spell form exists); static data, never secret,
-- but validated anyway since the seed feeds arithmetic.
local function _cdBaseDuration(spellRef)
    if not GetSpellBaseCooldown then return nil end
    local ms = GetSpellBaseCooldown(spellRef)
    if _tbbCleanNum(ms) and ms > 0 then return ms / 1000 end
    return nil
end

local function _ensureCooldownCastListener(enable)
    if enable then
        if not _cdFrame then
            _cdFrame = mod.TakeShell()
            _cdFrame:SetScript("OnEvent", function(_, evt, _, _, castSid)
                _cdGen = _cdGen + 1
                if evt ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
                local spellId = castSid
                if not spellId then return end
                local canon = _cdWatch[spellId]
                if not canon and C_Spell and C_Spell.GetBaseSpell then
                    -- Cast can fire with the override form while the bar watches the base.
                    local base = C_Spell.GetBaseSpell(spellId)
                    if type(base) == "number" then canon = _cdWatch[base] end
                end
                if not canon then return end
                local nowTime = GetTime()
                -- Charge spells: maxCharges is static and stays readable, and the cast just consumed one charge.
                local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(canon)
                local maxCh = ch and ch.maxCharges
                if not (_tbbCleanNum(maxCh) and maxCh > 1) then maxCh = nil end
                -- NEVER overwrite an unexpired mirror: a plain spell cannot be cast while on
                -- cooldown, and a charge spell cast while already recharging does NOT restart the next charge; only the count drops.
                local m = _cdCast[canon]
                if m and m.dur and (m.start + m.dur) > nowTime then
                    if maxCh and m.charges and m.charges > 0 then m.charges = m.charges - 1 end
                    return
                end
                local dur = _cdDurCache[canon] or _cdBaseDuration(canon)
                if dur then
                    if not m then
                        m = {}
                        _cdCast[canon] = m
                    end
                    m.start = nowTime
                    m.dur = dur
                    if maxCh then
                        -- Cast from full: the first recharge starts now.
                        m.charges = maxCh - 1
                        m.maxCh = maxCh
                    else
                        m.charges = nil
                        m.maxCh = nil
                    end
                end
            end)
        end
        if not _cdActive then
            _cdFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            _cdFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            _cdFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
            _cdActive = true
        end
    elseif _cdFrame and _cdActive then
        _cdFrame:UnregisterAllEvents()
        _cdActive = false
    end
end

-- Authoritative (scans the DB): rebuild the watched-spell map and arm the cast listener only
-- while an enabled cooldown-tracking bar exists. Refreshed from the same sites as the other preset listeners.
function mod.UpdateCooldownCastListener()
    wipe(_cdWatch)
    local any = false
    local tbb = mod.GetTrackedBuffBars and mod.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, conf in ipairs(tbb.bars) do
            if conf.enabled ~= false and conf.trackType == "cooldown" then
                local canon = CooldownBarSpellID(conf)
                if canon then
                    any = true
                    -- Every form the cast event could fire with maps to the canonical id the tick keys the mirror by.
                    _cdWatch[canon] = canon
                    if conf.spellID and conf.spellID > 0 then _cdWatch[conf.spellID] = canon end
                    if conf.baseSpellID and conf.baseSpellID > 0 then _cdWatch[conf.baseSpellID] = canon end
                    -- Seed the duration cache NOW: build paths run out of combat where these
                    -- reads are clean. In combat the same reads can be secret and a fresh
                    -- session has no clean tick read yet, so without a seed the combat cast
                    -- could never arm the mirror. Never overwrites a live clean read.
                    if not _cdDurCache[canon] then
                        local seed
                        local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(canon)
                        local rd = ch and ch.cooldownDuration
                        if _tbbCleanNum(rd) and rd > 0 then seed = rd end
                        if not seed then seed = _cdBaseDuration(canon) end
                        _cdDurCache[canon] = seed
                    end
                end
            end
        end
    end
    _ensureCooldownCastListener(any)
end

-------------------------------------------------------------------------------
--  Cooldown-tracking bar (cfg.trackType == "cooldown"): the stock fill drains with the
--  spell's remaining cooldown. cfg.fillUp inverts that, filling as the cooldown
--  recovers -- it changes only WHICH WAY the value travels, and every fill source
--  below honours it. Reverse Fill is a different thing entirely and composes with
--  it: that mirrors the bar's geometry and never touches the value. Charge Hash
--  Lines instead fill one section per recovered charge while the timer stays the
--  NEXT charge's cooldown, and already fill upward by construction, so fillUp is a
--  no-op there. Stacks text = current charges. Ready (off cooldown/GCD-only/max
--  charges/unknown) counts as INACTIVE for hideWhenInactive; a shown-but-ready bar
--  renders full with no timer, in either direction.
--
--  FILL SOURCE ORDER (each honours cfg.fillUp):
--  1. Engine duration handle (GetSpellCooldownDuration/GetSpellChargeDuration +
--     SetTimerDuration): engine animates the drain and tracks CDR/resets live,
--     secret-proof by construction; timer text reads the handle's remaining (secret
--     in combat, which SetFormattedText accepts).
--  2. Clean API numbers (out of combat): exact pretty timer text, keeps the cast mirror synced.
--  3. Cast mirror (no duration-object API, or secret reads with no handle): clean local
--     dead-reckoning, blind to in-combat CDR, hence last.
--  4. Fail-open: shown-full bar, no text. Secrecy loses precision, never errors.
-------------------------------------------------------------------------------
local function _UpdateCooldownBar(barFrame, conf)
    local spellRef = CooldownBarSpellID(conf)

    -- remaining/duration: CLEAN numbers only (nil = ready or secret). wantHandle:
    -- which engine duration handle drives the fill ("charge"/"cd"). timingSecret: raw
    -- numbers unreadable, bar NEEDS the handle (or falls back to the mirror). charges:
    -- CLEAN count for logic/overlays; chargesDisplay: maybe-secret count that ONLY
    -- flows into SetFormattedText; hasCharges: clean flag so no secret is ever branched on.
    local remaining, duration, unreadable, wantHandle, timingSecret
    local charges, chargesDisplay, hasCharges
    local maxCharges, chargeCountValue
    if spellRef then
        local ch = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellRef)
        local maxCh = ch and ch.maxCharges
        if _tbbCleanNum(maxCh) and maxCh > 1 then
            maxCharges = math.floor(maxCh + 0.5)
            -- Charge spell: the bar tracks the next charge's recharge. The recharge-active
            -- flag is the same CLEAN combat signal Max Stacks Glow uses: false only at max
            -- charges, and readable while the count/timing fields are secret.
            local chActive = ch.isActive
            if issecretvalue and issecretvalue(chActive) then
                unreadable = true
            elseif not chActive then
                -- At max charges: ready, and the count is KNOWN without ever touching the secret currentCharges field.
                charges = maxCh
                chargesDisplay = maxCh
                chargeCountValue = maxCh
                hasCharges = true
            else
                -- Recharging (below max).
                wantHandle = "charge"
                local current = ch.currentCharges
                if _tbbCleanNum(current) then charges = current end
                chargesDisplay = current
                chargeCountValue = current
                hasCharges = true
                local st, du = ch.cooldownStartTime, ch.cooldownDuration
                if _tbbCleanNum(st) and _tbbCleanNum(du) and du > 0 then
                    duration = du
                    remaining = st + du - GetTime()
                    -- Clean read: keep the fallback mirror exact.
                    _cdDurCache[spellRef] = du
                    local m = _cdCast[spellRef]
                    if not m then
                        m = {}
                        _cdCast[spellRef] = m
                    end
                    m.start = st
                    m.dur = du
                    if charges then m.charges = charges end
                    m.maxCh = maxCh
                else
                    timingSecret = true
                end
            end
        else
            local cd = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellRef)
            if cd then
                local act, gcd = cd.isActive, cd.isOnGCD
                local isSec = issecretvalue
                if isSec and (isSec(act) or isSec(gcd)) then
                    unreadable = true
                elseif act and not gcd then
                    -- Real cooldown running; a GCD-only spin never drives the bar.
                    wantHandle = "cd"
                    local st, du = cd.startTime, cd.duration
                    if _tbbCleanNum(st) and _tbbCleanNum(du) and du > 0 then
                        duration = du
                        remaining = st + du - GetTime()
                        -- Clean read: keep the fallback mirror exact.
                        _cdDurCache[spellRef] = du
                        local m = _cdCast[spellRef]
                        if not m then
                            m = {}
                            _cdCast[spellRef] = m
                        end
                        m.start = st
                        m.dur = du
                    else
                        timingSecret = true
                    end
                end
            end
        end
    end
    -- Resolve the engine duration handle (preferred fill source). Fetch+re-arm ONLY when
    -- cooldown state may have changed: the generation bumps on SPELL_UPDATE_COOLDOWN/CHARGES/
    -- player casts, plus a 1s revalidate for eventless adjustments; between those the CACHED
    -- handle serves every tick, ticking down on its own.
    local durObj
    if wantHandle then
        durObj = barFrame._cdDurObj
        local nowTime = GetTime()
        if
            durObj == nil
            or barFrame._cdArmGen ~= _cdGen
            or barFrame._cdArmSid ~= spellRef
            or barFrame._cdArmKind ~= wantHandle
            or nowTime - (barFrame._cdArmTime or 0) > 1
        then
            local fetch
            if wantHandle == "charge" then
                if C_Spell.GetSpellChargeDuration then fetch = C_Spell.GetSpellChargeDuration(spellRef) end
            else
                if C_Spell.GetSpellCooldownDuration then
                    fetch = C_Spell.GetSpellCooldownDuration(spellRef)
                end
            end
            durObj = fetch
            barFrame._cdDurObj = fetch
            barFrame._cdArmGen = _cdGen
            barFrame._cdArmSid = spellRef
            barFrame._cdArmKind = wantHandle
            barFrame._cdArmTime = nowTime
            -- The bar timer must be re-set from the fresh handle.
            barFrame._cdNeedSet = fetch ~= nil
        end
    else
        barFrame._cdDurObj = nil
    end
    if timingSecret and not durObj then unreadable = true end

    -- Combat-secrecy fallback: timing went secret but the cast mirror holds clean local
    -- numbers, so drive the drain from those instead of shown-full fail-open (expired/absent mirror keeps the fail-open).
    if unreadable and spellRef then
        local m = _cdCast[spellRef]
        if m and m.dur then
            local nowTime = GetTime()
            local rem = m.start + m.dur - nowTime
            -- Charge model: an expiry means one charge finished and the next recharge began
            -- at that exact moment, so advance in place. The clean at-max flag above already
            -- ends the bar when the spell truly tops off; still recharging here means the
            -- model ran ahead, so hold one below max and keep draining.
            if m.maxCh and m.charges then
                local guard = m.maxCh + 1
                while rem <= 0 and guard > 0 do
                    m.charges = m.charges + 1
                    if m.charges >= m.maxCh then m.charges = m.maxCh - 1 end
                    m.start = m.start + m.dur
                    if m.start > nowTime then m.start = nowTime end
                    rem = m.start + m.dur - nowTime
                    guard = guard - 1
                end
            end
            if rem > 0 then
                remaining = rem
                duration = m.dur
                unreadable = nil
                if m.charges then
                    charges = m.charges
                    chargesDisplay = m.charges
                    hasCharges = true
                end
            end
        end
    end

    if remaining and remaining <= 0 then
        remaining = nil
        duration = nil
    end

    -- Clean ready: drop the mirror so a stale window can never resurrect. A live duration
    -- handle means ON cooldown with secret timing (not ready), so the mirror stays in that case.
    if spellRef and not unreadable and remaining == nil and not durObj then _cdCast[spellRef] = nil end

    local onCooldown = (remaining ~= nil) or (durObj ~= nil) or unreadable

    local hashChargeMode = conf.chargeHashLines == true and type(maxCharges) == "number" and maxCharges > 1
    if barFrame._bar then ApplyTBBChargeHashLines(barFrame, conf, maxCharges) end

    -- No pandemic concept for cooldowns: clear stale glow from a re-purposed bar frame.
    if barFrame._pandemicGlowActive then ClearPandemic(barFrame) end

    if not onCooldown and conf.hideWhenInactive ~= false then
        -- Ready = inactive: hide, matching the buff inactive branch.
        _restoreTBBNormalFill(barFrame, conf)
        barFrame._stackCount = 0
        if barFrame._stacksText then barFrame._stacksText:Hide() end
        barFrame._nameSet = nil
        if barFrame:IsShown() then barFrame:Hide() end
        return
    end

    local wasShown = barFrame:IsShown()
    if not wasShown then barFrame:Show() end
    local scrollBar = barFrame._bar
    if scrollBar then
        local timerDir = Enum and Enum.StatusBarTimerDirection
        local hashFillActive = hashChargeMode
            and _updateTBBChargeHashFill(
                barFrame,
                conf,
                maxCharges,
                chargeCountValue,
                durObj,
                remaining,
                duration,
                wasShown
            )
        if hashFillActive then
            -- The composite's invisible native bars own the recovery geometry; the visible clipped texture and spark were updated above.
        elseif durObj and scrollBar.SetTimerDuration and timerDir then
            _restoreTBBNormalFill(barFrame, conf)
            -- Engine-driven fill: the handle tracks CDR and resets live with no numbers ever
            -- read. The bar timer is re-set only when a fresh handle was fetched
            -- (event/revalidate), the bar just appeared, or the requested direction changed --
            -- the engine animates in between. Fill Up asks the engine for ElapsedTime instead
            -- of RemainingTime, the same constant the charge-hash recovery bar uses. The
            -- direction term matters because toggling the option restyles a LIVE bar in
            -- place: with only the fetch/show terms the engine would keep animating the old
            -- direction until the next handle fetch.
            local wantDir = conf.fillUp and timerDir.ElapsedTime or timerDir.RemainingTime
            if barFrame._cdNeedSet or not wasShown or barFrame._cdFillDir ~= wantDir then
                scrollBar:SetMinMaxValues(0, 1)
                local interpE = Enum.StatusBarInterpolation
                local interp
                if interpE then
                    if wasShown and _tbbWake._smoothCooldowns then
                        interp = interpE.ExponentialEaseOut
                    else
                        interp = interpE.None
                    end
                end
                scrollBar:SetTimerDuration(durObj, interp, wantDir)
                -- Snap whenever the bar was not already animating THIS
                -- direction. First show is the original case (the
                -- empty-to-full sweep-in). The direction term adds two more:
                -- arriving from the ready state, which parks the bar full and
                -- clears _cdFillDir, and a mid-cooldown toggle. Both leave the
                -- bar sitting at the opposite end, and with smooth cooldowns
                -- on, easing from there plays a visible backwards sweep at the
                -- exact moment the spell was cast.
                if (not wasShown or barFrame._cdFillDir ~= wantDir) and scrollBar.SetToTargetValue then
                    scrollBar:SetToTargetValue()
                end
                barFrame._cdNeedSet = nil
                barFrame._cdFillDir = wantDir
            end
            if conf.showSpark and barFrame._spark then barFrame._spark:Show() end
        elseif remaining then
            _restoreTBBNormalFill(barFrame, conf)
            scrollBar:SetMinMaxValues(0, duration)
            -- Both operands are clean numbers on this branch, and a
            -- non-positive remaining was normalised away above, so Fill Up
            -- can simply mirror the fraction in Lua.
            local fillVal = conf.fillUp and (duration - remaining) or remaining
            -- Smooth fill is baseline (see UpdateLustBar note).
            local smooth = _tbbWake._smoothCooldowns
                and wasShown
                and Enum
                and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            if smooth then
                scrollBar:SetValue(fillVal, smooth)
            else
                scrollBar:SetValue(fillVal)
            end
            -- Plain SetValue cancels the running bar timer, so the cached
            -- engine direction is stale the moment this branch runs.
            barFrame._cdFillDir = nil
            if conf.showSpark and barFrame._spark then barFrame._spark:Show() end
        else
            _restoreTBBNormalFill(barFrame, conf)
            -- Ready (kept on screen) or unreadable fail-open: full bar in either direction.
            -- Plain SetValue also cancels any running bar timer.
            scrollBar:SetMinMaxValues(0, 1)
            scrollBar:SetValue(1)
            barFrame._cdFillDir = nil
            if barFrame._spark then barFrame._spark:Hide() end
        end
    end

    -- Timer: remaining cooldown, hidden when ready/unreadable. Clean numbers get the pretty
    -- format; a secret remaining from the duration handle goes through SetFormattedText
    -- (accepts secrets). Hash mode shows tenths, stock mode whole seconds.
    if barFrame._timerText then
        if remaining and conf.showTimer then
            if hashChargeMode then
                barFrame._timerText:SetFormattedText("%.1f", remaining)
            elseif remaining < 10 then
                barFrame._timerText:SetText(string.format("%.1f", remaining))
            else
                barFrame._timerText:SetText(FormatTime(remaining))
            end
            barFrame._timerText:Show()
        elseif conf.showTimer and durObj and durObj.GetRemainingDuration then
            local rem = durObj:GetRemainingDuration()
            if (issecretvalue and issecretvalue(rem)) or type(rem) == "number" then
                barFrame._timerText:SetFormattedText(hashChargeMode and "%.1f" or "%.0f", rem)
                barFrame._timerText:Show()
            else
                barFrame._timerText:Hide()
            end
        else
            barFrame._timerText:Hide()
        end
    end

    -- Charges reuse the stacks text and the threshold overlay feed. The text setter accepts
    -- a SECRET live count; overlays need clean numbers, so a secret count zeroes them instead of freezing a stale value.
    if hasCharges then
        barFrame._stackCount = charges or 0
        if barFrame._stacksText then
            if (conf.stacksPosition or "center") ~= "none" then
                barFrame._stacksText:SetFormattedText("%d", chargesDisplay)
                barFrame._stacksText:Show()
            else
                barFrame._stacksText:Hide()
            end
        end
    else
        barFrame._stackCount = 0
        if barFrame._stacksText then barFrame._stacksText:Hide() end
    end

    -- Threshold feed (gated): runs in both arms so a charge count that becomes unreadable zeroes the overlay instead of freezing its last value.
    if _anyThreshold and conf.stackThresholdEnabled then FeedTBBThresholdOverlay(barFrame) end

    -- Deferred tick marks (same consume as the buff mirror branch).
    if barFrame._ticksDirty and scrollBar then
        local bw = scrollBar:GetWidth()
        if bw and bw > 0 then
            ApplyTBBTickMarks(
                scrollBar,
                conf,
                barFrame._threshTicks,
                conf.verticalOrientation,
                barFrame._tickOverlay
            )
            barFrame._ticksDirty = nil
        end
    end
end

Inner._UpdateCooldownBar = _UpdateCooldownBar
Inner.broken = false
